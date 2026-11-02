// BenchmarkLoadTrace.swift
// RealityEsceneTestV3
//
// Peak and mean machine load across a whole benchmark run.
//
// The summary used to print whatever hardware.cpuUsage happened to hold the
// instant the run ended, which for the stress test is the least interesting
// moment it has: by second twelve the ball has come to rest, SleepSystem has
// parked all 512 bodies and the solver is doing nothing at all. That printed
// 8% of the machine under a demo whose HUD had just shown 80% while the block
// was coming apart. Both numbers were true readings. Only one of them
// describes what the demo costs, and it was not the one going into the table.
//
// Same shape as BenchmarkWindowWatch, for the same reason: the benchmark's own
// poll loop feeds this a sample while the run is happening, and it answers
// once at the end. A number sampled once, at a moment nobody chose, is not a
// measurement.

import Foundation

@MainActor
struct BenchmarkLoadTrace {

    private var samples = 0
    private var cpuPercentPeak  = 0.0
    private var cpuPercentTotal = 0.0
    private var cpuCoresPeak    = 0.0
    private var gpuPercentPeak  = 0.0
    private var gpuPercentTotal = 0.0

    // HardwareMetrics refreshes every 500 ms and this is called every 100 ms,
    // so consecutive samples repeat the same reading. That costs nothing for a
    // peak, and it makes the mean time-weighted rather than sample-weighted,
    // which is what it should be.
    mutating func sample(cpuPercent: Double, cpuCores: Double, gpuPercent: Double) {
        samples += 1
        cpuPercentPeak   = max(cpuPercentPeak, cpuPercent)
        cpuPercentTotal += cpuPercent
        cpuCoresPeak     = max(cpuCoresPeak, cpuCores)
        gpuPercentPeak   = max(gpuPercentPeak, gpuPercent)
        gpuPercentTotal += gpuPercent
    }

    var cpuPeak: Double      { cpuPercentPeak }
    var cpuMean: Double      { mean(cpuPercentTotal) }
    var cpuPeakCores: Double { cpuCoresPeak }
    var gpuPeak: Double      { gpuPercentPeak }
    var gpuMean: Double      { mean(gpuPercentTotal) }

    private func mean(_ total: Double) -> Double {
        samples == 0 ? 0 : total / Double(samples)
    }
}
