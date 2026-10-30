// FrameStats.swift
// RealityEsceneTestV2
//
// Frame pacing, reported the way a game benchmark reports it.
//
// Instantaneous FPS — 1 / (t - tPrev) — is what V1 showed, and it is the one
// number that cannot tell you whether a demo is smooth: a scene that drops a
// frame every tenth of a second still reads as 120 on that counter. What
// matters is the distribution, so this keeps a rolling window of frame times
// and derives the averages, the percentiles and the 1% low that stutter
// actually shows up in.

import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class FrameStats {

    // Rolling window of frame times in milliseconds.
    private var samples: [Double] = []
    private let capacity = 240

    private var lastTimestamp: Double = 0

    // Current values, refreshed at most 10 times a second so the HUD text is
    // readable instead of flickering.
    var fps: Double = 0
    var frameTimeMS: Double = 0
    var averageFPS: Double = 0
    var onePercentLowFPS: Double = 0
    var p99FrameTimeMS: Double = 0
    var droppedFrames: Int = 0

    // Normalised history for the HUD graph, oldest first.
    var graph: [Double] = []

    // The display's own ceiling — the demo is pointless without it, since
    // "120 FPS" only means something next to a 120 Hz panel.
    var displayRefreshRate: Int = 60

    private var lastPublish: Double = 0
    private var frameBudgetMS: Double = 1000.0 / 60.0

    // Frames discarded after a reset. Building the procedural environment and
    // uploading the first meshes costs tens of milliseconds, and folding that
    // into the average and the 1% low would misreport the steady state the
    // demo is actually there to show.
    private var warmupFrames = 0
    private let warmupBudget = 45

    init() {
        refreshDisplayRate()
    }

    func refreshDisplayRate() {
        let rate = NSScreen.main?.maximumFramesPerSecond ?? 60
        displayRefreshRate = max(rate, 1)
        // A frame counts as dropped past 1.5x the display's budget.
        frameBudgetMS = 1000.0 / Double(displayRefreshRate) * 1.5
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        graph.removeAll(keepingCapacity: true)
        lastTimestamp = 0
        droppedFrames = 0
        warmupFrames = 0
    }

    // Called once per display-link callback with the link's timestamp.
    func record(timestamp: Double) {
        defer { lastTimestamp = timestamp }
        guard lastTimestamp > 0 else { return }

        let deltaMS = (timestamp - lastTimestamp) * 1000
        guard deltaMS > 0, deltaMS < 1000 else { return }

        guard warmupFrames >= warmupBudget else {
            warmupFrames += 1
            return
        }

        samples.append(deltaMS)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        if deltaMS > frameBudgetMS { droppedFrames += 1 }

        guard timestamp - lastPublish > 0.1 else { return }
        lastPublish = timestamp
        publish(latest: deltaMS)
    }

    private func publish(latest: Double) {
        frameTimeMS = latest
        fps = 1000 / latest

        guard !samples.isEmpty else { return }

        let mean = samples.reduce(0, +) / Double(samples.count)
        averageFPS = 1000 / mean

        // Percentiles over the window. Sorting 240 doubles ten times a second
        // is free next to the frame itself.
        let sorted = samples.sorted()
        let p99Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.99))
        p99FrameTimeMS = sorted[p99Index]

        // 1% low: the mean of the worst one percent of frames, expressed as
        // FPS. This is the number that matches what the eye calls stutter.
        let worstCount = max(1, sorted.count / 100)
        let worst = sorted.suffix(worstCount)
        let worstMean = worst.reduce(0, +) / Double(worst.count)
        onePercentLowFPS = 1000 / worstMean

        // Graph: last 120 frames, normalised against twice the display budget
        // so a perfectly paced scene sits at a flat half height.
        let window = samples.suffix(120)
        let ceiling = 1000.0 / Double(displayRefreshRate) * 2
        graph = window.map { min($0 / ceiling, 1.0) }
    }
}
