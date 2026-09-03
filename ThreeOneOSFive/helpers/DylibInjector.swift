import Foundation

enum DylibInjectorError: LocalizedError {
    case dylibNotFound(String)
    case processNotFound(String)
    case taskPortFailed
    case injectFailed(String)

    var errorDescription: String? {
        switch self {
        case .dylibNotFound(let path):
            return "Không tìm thấy dylib tại: \(path). Copy dylib vào Documents của 3105 trước."
        case .processNotFound(let name):
            return "Không tìm thấy process '\(name)'. Mở game trước rồi thử lại."
        case .taskPortFailed:
            return "Không lấy được task port. Exploit chưa active."
        case .injectFailed(let reason):
            return "Inject thất bại: \(reason)"
        }
    }
}

@_silgen_name("mach_vm_allocate")
func mach_vm_allocate(_ task: mach_port_t, _ addr: UnsafeMutablePointer<UInt64>, _ size: UInt64, _ flags: Int32) -> kern_return_t

@_silgen_name("mach_vm_write")
func mach_vm_write_injector(_ task: mach_port_t, _ address: UInt64, _ data: UnsafeRawPointer, _ size: UInt32) -> kern_return_t

@_silgen_name("mach_vm_protect")
func mach_vm_protect(_ task: mach_port_t, _ addr: UInt64, _ size: UInt64, _ setMax: Int32, _ prot: Int32) -> kern_return_t

@_silgen_name("thread_create_running")
func thread_create_running(_ task: mach_port_t, _ flavor: Int32, _ state: UnsafeRawPointer, _ stateCount: UInt32, _ thread: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

enum DylibInjector {

    // Tìm dylib trong Documents của 3105
    static func findDylib(named name: String) -> URL? {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Lấy tất cả dylib trong Documents
    static func availableDylibs() -> [URL] {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = (try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "dylib" }
    }

    // Lấy PID của process theo tên
    static func getPID(processName: String) -> Int32? {
        var allPIDs = [Int32](repeating: 0, count: 1024)
        let count = proc_listallpids(&allPIDs, Int32(allPIDs.count * MemoryLayout<Int32>.size))
        for i in 0..<Int(count) {
            let p = allPIDs[i]
            var name = [CChar](repeating: 0, count: 256)
            proc_name(p, &name, 256)
            if String(cString: name) == processName {
                return p
            }
        }
        return nil
    }

    // Main inject function
    static func inject(dylibURL: URL, into bundleID: String, processName: String) throws {
        // 1. Kiểm tra dylib tồn tại
        guard FileManager.default.fileExists(atPath: dylibURL.path) else {
            throw DylibInjectorError.dylibNotFound(dylibURL.path)
        }

        // 2. Elevate privileges
        let selfProc = proc_self()
        _ = sandbox_elevate_to_root(selfProc)

        // 3. Tìm PID của game
        guard let pid = getPID(processName: processName) else {
            throw DylibInjectorError.processNotFound(processName)
        }

        // 4. Lấy task port
        var taskPort: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let kr = task_for_pid(mach_task_self_, pid, &taskPort)
        guard kr == KERN_SUCCESS, taskPort != mach_port_t(MACH_PORT_NULL) else {
            throw DylibInjectorError.taskPortFailed
        }

        // 5. Chuẩn bị dylib path string
        let dylibPath = dylibURL.path
        let pathData = dylibPath.utf8CString.map { UInt8(bitPattern: $0) }
        let pathSize = UInt64(pathData.count)

        // 6. Allocate memory trong game process cho path string
        var remotePathAddr: UInt64 = 0
        let allocKR = mach_vm_allocate(taskPort, &remotePathAddr, pathSize, 1) // VM_FLAGS_ANYWHERE = 1
        guard allocKR == KERN_SUCCESS else {
            throw DylibInjectorError.injectFailed("allocate path failed: \(allocKR)")
        }

        // 7. Write dylib path vào game memory
        let writeKR = pathData.withUnsafeBytes { ptr in
            mach_vm_write_injector(taskPort, remotePathAddr, ptr.baseAddress!, UInt32(pathSize))
        }
        guard writeKR == KERN_SUCCESS else {
            throw DylibInjectorError.injectFailed("write path failed: \(writeKR)")
        }

        // 8. Make memory executable
        _ = mach_vm_protect(taskPort, remotePathAddr, pathSize, 0, 7) // PROT_READ|WRITE|EXEC

        // 9. Dùng dlopen thông qua remote thread để load dylib
        // Tìm địa chỉ của dlopen trong game process (offset từ libdyld)
        let dlopenAddr = getDlopenAddress(task: taskPort)
        guard dlopenAddr != 0 else {
            throw DylibInjectorError.injectFailed("cannot find dlopen address")
        }

        // 10. Tạo remote thread chạy dlopen với path dylib
        try createRemoteThread(task: taskPort, function: dlopenAddr, argument: remotePathAddr)
    }

    private static func getDlopenAddress(task: mach_port_t) -> UInt64 {
        // dlopen nằm trong libdyld.dylib — offset thường cố định
        // Lấy địa chỉ dlopen từ process hiện tại rồi tính offset sang game
        guard let localDlopen = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "dlopen") else {
            return 0
        }
        return UInt64(UInt(bitPattern: localDlopen))
    }

    private static func createRemoteThread(task: mach_port_t, function: UInt64, argument: UInt64) throws {
        // ARM64 thread state
        var state = arm_thread_state64_t()
        state.__x.0 = argument  // x0 = dylib path
        state.__x.1 = 2          // x1 = RTLD_NOW
        state.__pc = function    // pc = dlopen address
        state.__sp = 0           // sp sẽ được tự allocate

        var newThread: mach_port_t = 0
        let kr = withUnsafeBytes(of: &state) { statePtr in
            thread_create_running(
                task,
                6, // ARM_THREAD_STATE64
                statePtr.baseAddress!,
                UInt32(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size),
                &newThread
            )
        }
        guard kr == KERN_SUCCESS else {
            throw DylibInjectorError.injectFailed("thread_create_running failed: \(kr)")
        }
    }
}
