import Foundation
import MachO

enum GameMemoryError: LocalizedError {
    case processNotFound(String)
    case taskPortFailed
    case invalidOffset
    case readFailed(kern_return_t)
    case writeFailed(kern_return_t)
    case gameNotRunning

    var errorDescription: String? {
        switch self {
        case .processNotFound(let name):
            return "Không tìm thấy process '\(name)'. Game đang chạy không?"
        case .taskPortFailed:
            return "Không lấy được task port. Exploit chưa active?"
        case .invalidOffset:
            return "Offset không hợp lệ. Kiểm tra lại định dạng hex."
        case .readFailed(let kr):
            return "Đọc memory thất bại: \(kr)"
        case .writeFailed(let kr):
            return "Ghi memory thất bại: \(kr)"
        case .gameNotRunning:
            return "Game chưa chạy. Mở game trước rồi thử lại."
        }
    }
}

enum GameMemoryService {
    // Tên process của từng game
    static func processName(for bundleID: String) -> String {
        switch bundleID {
        case "com.garena.game.kgvn": return "GarenaMobile"
        case "com.dts.freefireth": return "freefire"
        case "com.dts.freefiremax": return "freefiremax"
        case "vn.vng.pubgmobile": return "PUBGMOBILE"
        default: return bundleID.components(separatedBy: ".").last ?? bundleID
        }
    }

    // Lấy task port của game dùng sandbox escape + task_for_pid
    static func getTaskPort(bundleID: String) throws -> mach_port_t {
        // Elevate to root trước
        let selfProc = proc_self()
        _ = sandbox_elevate_to_root(selfProc)

        // Tìm process game
        let procName = processName(for: bundleID)
        let gameProc = proc_find_by_name(procName)
        guard gameProc != 0 else {
            throw GameMemoryError.processNotFound(procName)
        }

        // Lấy PID từ proc
        var pid: pid_t = 0
        let pidResult = withUnsafeMutablePointer(to: &pid) { ptr in
            proc_pidpath(Int32(gameProc), ptr, UInt32(MemoryLayout<pid_t>.size))
        }

        // Dùng task_for_pid để lấy task port
        var taskPort: mach_port_t = MACH_PORT_NULL
        let kr = task_for_pid(mach_task_self(), pid, &taskPort)
        guard kr == KERN_SUCCESS, taskPort != MACH_PORT_NULL else {
            throw GameMemoryError.taskPortFailed
        }
        return taskPort
    }

    // Đọc base address của game
    static func getBaseAddress(task: mach_port_t) -> UInt64 {
        var address: mach_vm_address_t = 0
        var size: mach_vm_size_t = 0
        var info = vm_region_basic_info_data_64_t()
        var count = mach_msg_type_number_t(VM_REGION_BASIC_INFO_COUNT_64)
        var objectName: mach_port_t = 0

        while true {
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: Int32.self, capacity: Int(VM_REGION_BASIC_INFO_COUNT_64)) { infoPtr in
                    mach_vm_region(task, &address, &size,
                                   VM_REGION_BASIC_INFO_64,
                                   infoPtr,
                                   &count, &objectName)
                }
            }
            if kr != KERN_SUCCESS { break }
            // Base address thường là region đầu tiên có quyền execute
            let perms = info.protection
            if perms & VM_PROT_EXECUTE != 0 {
                return address
            }
            address += size
        }
        return 0
    }

    // Ghi Float vào địa chỉ (dùng cho No Recoil, Speed...)
    static func writeFloat(_ value: Float, to address: UInt64, task: mach_port_t) throws {
        var val = value
        let data = withUnsafeBytes(of: &val) { Data($0) }
        let kr = data.withUnsafeBytes { ptr in
            mach_vm_write(task,
                         mach_vm_address_t(address),
                         vm_offset_t(bitPattern: ptr.baseAddress!),
                         mach_msg_type_number_t(data.count))
        }
        guard kr == KERN_SUCCESS else {
            throw GameMemoryError.writeFailed(kr)
        }
    }

    // Ghi Bool (1/0) vào địa chỉ
    static func writeBool(_ value: Bool, to address: UInt64, task: mach_port_t) throws {
        var val: UInt8 = value ? 1 : 0
        let kr = withUnsafePointer(to: &val) { ptr in
            mach_vm_write(task,
                         mach_vm_address_t(address),
                         vm_offset_t(bitPattern: ptr),
                         1)
        }
        guard kr == KERN_SUCCESS else {
            throw GameMemoryError.writeFailed(kr)
        }
    }

    // Apply patch từ offset hex string
    static func applyPatch(offset hexOffset: String, value: Float, bundleID: String) throws {
        let cleaned = hexOffset
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")

        guard let offsetValue = UInt64(cleaned, radix: 16) else {
            throw GameMemoryError.invalidOffset
        }

        let task = try getTaskPort(bundleID: bundleID)
        let base = getBaseAddress(task: task)
        guard base != 0 else { throw GameMemoryError.taskPortFailed }

        let targetAddress = base + offsetValue
        try writeFloat(value, to: targetAddress, task: task)
    }

    static func applyBoolPatch(offset hexOffset: String, value: Bool, bundleID: String) throws {
        let cleaned = hexOffset
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")

        guard let offsetValue = UInt64(cleaned, radix: 16) else {
            throw GameMemoryError.invalidOffset
        }

        let task = try getTaskPort(bundleID: bundleID)
        let base = getBaseAddress(task: task)
        guard base != 0 else { throw GameMemoryError.taskPortFailed }

        let targetAddress = base + offsetValue
        try writeBool(value, to: targetAddress, task: task)
    }
}
