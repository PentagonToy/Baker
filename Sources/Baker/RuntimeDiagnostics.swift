import Foundation
import Darwin

/// Read-only process accounting; no file paths, captured content or external requests.
enum RuntimeDiagnostics {
    static func process() -> [String: Any] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var result: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "memoryAvailable": status == KERN_SUCCESS]
        if status == KERN_SUCCESS {
            result["residentBytes"] = info.resident_size
            result["physicalFootprintBytes"] = info.phys_footprint
        }
        return result
    }
}
