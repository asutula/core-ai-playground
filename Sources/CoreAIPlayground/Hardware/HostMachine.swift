import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(Metal)
import Metal
#endif

/// A snapshot of the machine the app is running on. Plain data so the
/// compatibility engine can be unit-tested with synthetic hosts.
struct HostMachine: Sendable, Hashable {

    var brandString: String          // e.g. "Apple M3 Pro" or "Intel Core i7"
    var isAppleSilicon: Bool
    var physicalMemoryGB: Double
    var totalCPUCores: Int
    var performanceCores: Int
    var efficiencyCores: Int
    var osMajor: Int
    var osMinor: Int
    var osVersionString: String
    var freeDiskGB: Double
    var modelIdentifier: String      // e.g. "Mac15,3"
    var metalDeviceName: String?
    var recommendedMaxWorkingSetGB: Double?  // Metal's hint for GPU-resident bytes

    /// Resolved Apple Silicon reference data, when we can identify the chip.
    var chip: ChipInfo? { AppleSiliconDatabase.match(brandString: brandString) }

    /// Whether the OS is new enough for the Core AI framework (macOS 27+).
    var supportsCoreAI: Bool { isAppleSilicon && osMajor >= 27 }

    /// Memory we assume the OS + foreground apps need, so we don't promise a
    /// model the entire machine. Scales with RAM, clamped to a sane band.
    var systemReserveGB: Double {
        min(10.0, max(3.5, physicalMemoryGB * 0.22))
    }

    /// RAM realistically available to load a model's working set.
    var memoryAvailableForModelGB: Double {
        max(0, physicalMemoryGB - systemReserveGB)
    }
}

#if canImport(Darwin)
extension HostMachine {

    /// Reads the current machine's specs from the kernel + Metal.
    static func current() -> HostMachine {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Unknown CPU"
        let model = sysctlString("hw.model") ?? "Unknown"

        #if arch(arm64)
        let isAppleSilicon = true
        #else
        // Even on arm64-built binaries running under Rosetta we want the truth.
        let isAppleSilicon = (sysctlInt("hw.optional.arm64") ?? 0) == 1 || brand.hasPrefix("Apple")
        #endif

        let memBytes = sysctlUInt64("hw.memsize") ?? UInt64(ProcessInfo.processInfo.physicalMemory)
        let totalCores = sysctlInt("hw.ncpu") ?? ProcessInfo.processInfo.processorCount
        let pCores = sysctlInt("hw.perflevel0.physicalcpu") ?? totalCores
        let eCores = sysctlInt("hw.perflevel1.physicalcpu") ?? 0

        let os = ProcessInfo.processInfo.operatingSystemVersion

        var metalName: String?
        var maxWorkingSetGB: Double?
        #if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            metalName = device.name
            maxWorkingSetGB = Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824.0
        }
        #endif

        return HostMachine(
            brandString: brand,
            isAppleSilicon: isAppleSilicon,
            physicalMemoryGB: Double(memBytes) / 1_073_741_824.0,
            totalCPUCores: totalCores,
            performanceCores: pCores,
            efficiencyCores: eCores,
            osMajor: os.majorVersion,
            osMinor: os.minorVersion,
            osVersionString: ProcessInfo.processInfo.operatingSystemVersionString,
            freeDiskGB: freeDiskGB(),
            modelIdentifier: model,
            metalDeviceName: metalName,
            recommendedMaxWorkingSetGB: maxWorkingSetGB
        )
    }

    private static func freeDiskGB() -> Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return Double(capacity) / 1_073_741_824.0
        }
        return 0
    }

    // MARK: - sysctl helpers

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
#endif

#if !canImport(Darwin)
extension HostMachine {
    /// Placeholder used when building on non-Darwin platforms (e.g. Linux CI).
    static func current() -> HostMachine {
        HostMachine(
            brandString: "Non-Darwin host",
            isAppleSilicon: false,
            physicalMemoryGB: 16,
            totalCPUCores: 8,
            performanceCores: 8,
            efficiencyCores: 0,
            osMajor: 0,
            osMinor: 0,
            osVersionString: "n/a",
            freeDiskGB: 100,
            modelIdentifier: "n/a",
            metalDeviceName: nil,
            recommendedMaxWorkingSetGB: nil
        )
    }
}
#endif
