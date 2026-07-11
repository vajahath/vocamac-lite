// SystemInfo.swift
// VocaMac Lite
//
// Detects system hardware capabilities for display in settings.

import Foundation

// MARK: - SystemCapabilities

/// Detected system hardware information
struct SystemCapabilities {
    let isAppleSilicon: Bool
    let physicalMemoryGB: Int
    let processorName: String
    let coreCount: Int
    let supportsMetalAcceleration: Bool

    /// Human-readable summary for display in settings
    var summaryDescription: String {
        """
        Processor: \(processorName)
        Architecture: \(isAppleSilicon ? "Apple Silicon (ARM64)" : "Intel (x86_64)")
        Memory: \(physicalMemoryGB) GB
        Cores: \(coreCount)
        Metal: \(supportsMetalAcceleration ? "Supported" : "Not Available")
        """
    }
}

// MARK: - SystemInfo

/// Utility class for detecting system hardware capabilities
enum SystemInfo {

    /// Detect all system capabilities and return a summary
    static func detect() -> SystemCapabilities {
        let appleSilicon = isAppleSilicon
        let memoryGB = physicalMemoryGB
        let processor = processorName
        let cores = coreCount
        let metal = appleSilicon // Metal acceleration is available on Apple Silicon

        return SystemCapabilities(
            isAppleSilicon: appleSilicon,
            physicalMemoryGB: memoryGB,
            processorName: processor,
            coreCount: cores,
            supportsMetalAcceleration: metal
        )
    }

    // MARK: - Hardware Detection

    /// Whether the system is running on Apple Silicon (ARM64)
    static var isAppleSilicon: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { ptr in
            ptr.compactMap { byte -> Character? in
                guard byte > 0 else { return nil }
                return Character(UnicodeScalar(byte))
            }
            .map(String.init)
            .joined()
        }
        return machine.contains("arm64")
    }

    /// Physical memory in gigabytes
    static var physicalMemoryGB: Int {
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        return Int(memoryBytes / (1024 * 1024 * 1024))
    }

    /// Processor brand string (e.g., "Apple M1 Pro", "Intel Core i9-9880H")
    static var processorName: String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        guard size > 0 else { return "Unknown" }

        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)

        return String(cString: brand)
    }

    /// Number of active processor cores
    static var coreCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    /// Mac model identifier (e.g., "MacBookPro18,1")
    static var modelIdentifier: String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)

        guard size > 0 else { return "Unknown" }

        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)

        return String(cString: model)
    }
}
