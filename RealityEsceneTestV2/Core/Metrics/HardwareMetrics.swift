// HardwareMetrics.swift
// RealityEsceneTestV2
//
// Live CPU and GPU load, sampled off the render thread.
//
// Two things were wrong before this file existed. getGPUUsage() returned a
// hardcoded 0.0 with a comment promising IOKit later — a performance demo
// cannot show a fake zero. And getCPUUsage() walked every thread in the task
// from the frame callback, on the main thread, twice a second: a periodic
// stall big enough to show up in the 1% low the HUD reports.
//
// Both now run in HardwareSampler, which is explicitly nonisolated and pure.
// It returns a Sendable snapshot; only that value crosses back to the main
// actor. This target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so
// anything not marked nonisolated here would be main-actor isolated.

import Foundation
import IOKit
import Metal
import Observation

// MARK: - Sampler

enum HardwareSampler {

    struct Snapshot: Sendable {
        var cpuUsage: Double = 0
        var gpuUtilization: Double = 0
        var allocatedBytes: UInt64 = 0
        var deviceBytes: UInt64 = 0
        var gpuAvailable = false
    }

    // Long-lived system handle, only ever read. MTLDevice is already Sendable,
    // so plain `nonisolated` is enough — without it the default MainActor
    // isolation of this target would put it out of reach of sample().
    nonisolated private static let device = MTLCreateSystemDefaultDevice()

    nonisolated static var deviceName: String {
        device?.name ?? "No Metal device"
    }

    nonisolated static func sample() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.cpuUsage       = processCPUUsage()
        snapshot.allocatedBytes = UInt64(device?.currentAllocatedSize ?? 0)

        guard let stats = acceleratorStatistics() else { return snapshot }

        // Key names differ between GPU families, so try the known spellings.
        for key in ["Device Utilization %", "Renderer Utilization %", "GPU Core Utilization"] {
            guard let raw = stats[key] as? NSNumber else { continue }
            var value = raw.doubleValue
            // "GPU Core Utilization" is reported in ten-millionths.
            if key == "GPU Core Utilization" { value /= 100_000 }
            snapshot.gpuUtilization = min(max(value, 0), 100)
            break
        }

        for key in ["In use system memory", "inUseSystemMemory", "Alloc system memory"] {
            guard let raw = stats[key] as? NSNumber else { continue }
            snapshot.deviceBytes = raw.uint64Value
            break
        }

        snapshot.gpuAvailable = true
        return snapshot
    }

    // MARK: CPU

    // Sum of per-thread CPU usage for this process, as a percentage of one
    // core — the same number Activity Monitor shows for an app.
    nonisolated private static func processCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threads)),
                vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            )
        }

        var total = 0.0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { continue }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        return min(total, 100)
    }

    // MARK: GPU

    nonisolated private static func acceleratorStatistics() -> [String: Any]? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                    service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any]
            else { continue }

            if let stats = properties["PerformanceStatistics"] as? [String: Any] {
                return stats
            }
        }
        return nil
    }
}

// MARK: - Observable state

@Observable
final class HardwareMetrics {

    var cpuUsage: Double = 0
    var gpuUtilization: Double = 0
    var allocatedBytes: UInt64 = 0
    var deviceBytes: UInt64 = 0
    var gpuAvailable = false

    let deviceName: String = HardwareSampler.deviceName

    private var pollTask: Task<Void, Never>?

    init() {}

    // The loop stays on the main actor and only the sampling is pushed off it,
    // through a detached task that captures nothing. A DispatchSourceTimer was
    // tried first: with this target's default MainActor isolation its event
    // handler was inferred main-actor isolated, and dispatch calling it on a
    // utility queue tripped the isolation check and trapped at launch.
    func start() {
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let snapshot = await Task.detached(priority: .utility) {
                    HardwareSampler.sample()
                }.value

                guard let self, !Task.isCancelled else { return }
                self.apply(snapshot)

                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func apply(_ snapshot: HardwareSampler.Snapshot) {
        cpuUsage       = snapshot.cpuUsage
        gpuUtilization = snapshot.gpuUtilization
        allocatedBytes = snapshot.allocatedBytes
        deviceBytes    = snapshot.deviceBytes
        gpuAvailable   = snapshot.gpuAvailable
    }
}
