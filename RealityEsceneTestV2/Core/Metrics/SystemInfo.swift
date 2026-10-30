// SystemInfo.swift
// RealityEsceneTestV2
//
// The machine the demo is running on, read once at launch.
//
// The point of the project is that Apple silicon runs real-time 3D well, so
// the hardware it is running on belongs on screen next to the frame rate.
// Without it a screenshot of "120 FPS" says nothing about what produced it.

import Foundation
import Metal
import IOKit
import AppKit

struct SystemInfo: Sendable {

    let chip: String
    let cpuCores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let gpuCores: Int
    let memoryGB: Int
    let gpuName: String
    let hasUnifiedMemory: Bool
    let osVersion: String
    let displayRefreshRate: Int
    let displayResolution: String

    @MainActor
    static let current = SystemInfo()

    @MainActor
    init() {
        chip             = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        cpuCores         = Self.sysctlInt("hw.ncpu") ?? ProcessInfo.processInfo.processorCount
        performanceCores = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        efficiencyCores  = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        memoryGB         = Int((Self.sysctlUInt64("hw.memsize") ?? 0) / 1_073_741_824)

        let device = MTLCreateSystemDefaultDevice()
        gpuName          = device?.name ?? "No Metal device"
        hasUnifiedMemory = device?.hasUnifiedMemory ?? false

        // Not exposed by Metal — read from the accelerator's registry entry.
        gpuCores = Self.gpuCoreCount()

        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "macOS \(v.majorVersion).\(v.minorVersion)"

        let screen = NSScreen.main
        displayRefreshRate = screen?.maximumFramesPerSecond ?? 60
        if let frame = screen?.frame, let scale = screen?.backingScaleFactor {
            let w = Int(frame.width * scale)
            let h = Int(frame.height * scale)
            displayResolution = "\(w)x\(h)"
        } else {
            displayResolution = "unknown"
        }
    }

    // Short label for the HUD — "Apple M3 Pro" rather than the full brand string.
    var shortChip: String {
        if let range = chip.range(of: "Apple ") {
            return String(chip[range.lowerBound...])
        }
        return chip
    }

    var coreSummary: String {
        if performanceCores > 0 && efficiencyCores > 0 {
            return "\(cpuCores)-core CPU (\(performanceCores)P + \(efficiencyCores)E)"
        }
        return "\(cpuCores)-core CPU"
    }

    var gpuSummary: String {
        gpuCores > 0 ? "\(gpuCores)-core GPU" : gpuName
    }

    // MARK: - sysctl helpers

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func gpuCoreCount() -> Int {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AGXAccelerator"),
            &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any]
            else { continue }

            if let cores = properties["gpu-core-count"] as? NSNumber {
                return cores.intValue
            }
        }
        return 0
    }
}
