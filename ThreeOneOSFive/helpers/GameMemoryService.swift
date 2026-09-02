import Foundation
import Darwin

// Khai báo Mach VM APIs
@_silgen_name("mach_vm_read_overwrite")
func mach_vm_read_overwrite(_ target: mach_port_t, _ address: UInt64, _ size: UInt64, _ data: UInt64, _ outsize: UnsafeMutablePointer<UInt64>) -> kern_return_t

@_silgen_name("mach_vm_write")
func mach_vm_write(_ target: mach_port_t, _ address: UInt64, _ data: UnsafeRawPointer, _ size: UInt32) -> kern_return_t

@_silgen_name("mach_vm_region")
func mach_vm_region(_ target: mach_port_t, _ address: UnsafeMutablePointer<UInt64>, _ size: UnsafeMutablePointer<UInt64>, _ flavor: Int32, _ info: UnsafeMutableRawPointer, _ count: UnsafeMutablePointer<UInt32>, _ object: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

@_silgen_name("task_for_pid")
func task_for_pid(_ host: mach_port_t, _ pid: Int32, _ task: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

let VM_REGION_BASIC_INFO_64: Int32 = 9
let VM_REGION_BASIC_INFO_COUNT_64: UInt32 = 9
let VM_PROT_EXECUTE: Int32 = 0x4

enum GameMemoryError: LocalizedError {
    case processNotFound(String)
    case taskPortFailed
    case invalidOffset
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
        case .writeFailed(let kr):
            return "Ghi memory thất bại: \(kr)"
        case .gameNotRunning:
            return "Game chưa chạy. Mở game trước rồi thử lại."
        }
    }
}

enum GameMemoryService {
    static func processName(for bundleID: String) -> String {
        switch bundleID {
        case "com.garena.game.kgvn": return "GarenaMobile"
        case "com.dts.freefireth": return "freefire"
        case "com.dts.freefiremax": return "freefiremax"
        case "vn.vng.pubgmobile": return "PUBGMOBILE"
        default: return bundleID.components(separatedBy: ".").last ?? bundleID
        }
    }

    static func getTaskPort(bundleID: String) throws -> mach_port_t {
        let selfProc = proc_self()
        _ = sandbox_elevate_to_root(selfProc)

        let procName = processName(for: bundleID)
        let gameProc = proc_find_by_name(procName)
        guard gameProc != 0 else {
            throw GameMemoryError.processNotFound(procName)
        }

        // Lấy PID
        var pid: Int32 = 0
        var nameBuffer = [CChar](repeating: 0, count: 256)
        _ = proc_name(Int32(truncatingIfNeeded: gameProc), &nameBuffer, 256)

        // Scan PIDs để tìm đúng process
        var allPIDs = [Int32](repeating: 0, count: 1024)
        let count = proc_listallpids(&allPIDs, Int32(allPIDs.count * MemoryLayout<Int32>.size))
        for i in 0..<Int(count) {
            let p = allPIDs[i]
            var name = [CChar](repeating: 0, count: 256)
            proc_name(p, &name, 256)
            if String(cString: name) == procName {
                pid = p
                break
            }
        }

        guard pid != 0 else { throw GameMemoryError.processNotFound(procName) }

        var taskPort: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let kr = task_for_pid(mach_task_self_, pid, &taskPort)
        guard kr == KERN_SUCCESS, taskPort != mach_port_t(MACH_PORT_NULL) else {
            throw GameMemoryError.taskPortFailed
        }
        return taskPort
    }

    static func getBaseAddress(task: mach_port_t) -> UInt64 {
        var address: UInt64 = 0
        var size: UInt64 = 0
        var info = (Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0))
        var count = VM_REGION_BASIC_INFO_COUNT_64
        var objectName = mach_port_t(MACH_PORT_NULL)

        while true {
            let kr = withUnsafeMutableBytes(of: &info) { infoPtr in
                mach_vm_region(task, &address, &size,
                               VM_REGION_BASIC_INFO_64,
                               infoPtr.baseAddress!,
                               &count, &objectName)
            }
            if kr != KERN_SUCCESS { break }
            address += size
        }
        return 0
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
        var val: UInt8 = value ? 1 : 0
        let kr = withUnsafePointer(to: &val) { ptr in
            mach_vm_write(task, targetAddress, ptr, 1)
        }
        guard kr == KERN_SUCCESS else {
            throw GameMemoryError.writeFailed(kr)
        }
    }

    static func applyFloatPatch(offset hexOffset: String, value: Float, bundleID: String) throws {
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
        var val = value
        let kr = withUnsafePointer(to: &val) { ptr in
            mach_vm_write(task, targetAddress, ptr, 4)
        }
        guard kr == KERN_SUCCESS else {
            throw GameMemoryError.writeFailed(kr)
        }
    }
}
