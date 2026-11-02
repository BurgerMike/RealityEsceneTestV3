// FrameStats.swift
// RealityEsceneTestV3
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
    //
    // fps is smoothed over the last half second, not the last frame. The raw
    // reciprocal of one frame interval is the jumpiest number a HUD can show:
    // once a scene stops holding 120 Hz, vsync drops it to 60, so single
    // frames read as either 120 or 60 and nothing between, while the real
    // rate sits somewhere in the middle. It is also why this panel used to
    // disagree with Xcode's FPS gauge, which smooths its own reading.
    var fps: Double = 0
    var frameTimeMS: Double = 0
    var averageFPS: Double = 0
    var onePercentLowFPS: Double = 0
    var p99FrameTimeMS: Double = 0
    var droppedFrames: Int = 0

    // Normalised history for the HUD graph, oldest first.
    var graph: [Double] = []

    // How many frames the window actually presented since the last reset.
    // A run that gathered almost none was not slow; it was not drawing.
    private(set) var recordedFrames = 0

    // Every frame time since the reset, kept only while benchmarking.
    //
    // The rolling window above is the right shape for a HUD — it should
    // answer "how is it going right now" — but it is the wrong shape for a
    // result. It holds 240 frames, so at 120 fps the figure printed at the
    // end of a ten-second run described its last two seconds, with the other
    // eight thrown away. That is what made the fast demos swing: the same
    // procedural surface measured 47.8, 110.8, 72.8 and 55.3 fps on four
    // runs, while a demo at 45 fps looked steady only because 240 frames
    // happened to span most of its run.
    //
    // A ten-second benchmark reports ten seconds.
    var keepsFullHistory = false
    private var history: [Double] = []

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
        history.removeAll(keepingCapacity: true)
        graph.removeAll(keepingCapacity: true)
        lastTimestamp = 0
        droppedFrames = 0
        warmupFrames = 0
        recordedFrames = 0
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
        if keepsFullHistory { history.append(deltaMS) }
        recordedFrames += 1
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        if deltaMS > frameBudgetMS { droppedFrames += 1 }

        guard timestamp - lastPublish > 0.1 else { return }
        lastPublish = timestamp
        publish(latest: deltaMS)
    }

    // MARK: Whole-run figures, for the benchmark summary

    // Nil when nothing was recorded, so a caller cannot print a confident
    // zero for a run that never drew.
    struct RunSummary {
        var averageFPS: Double
        var onePercentLowFPS: Double
        var p99FrameTimeMS: Double
        var meanFrameTimeMS: Double
    }

    func runSummary() -> RunSummary? {
        guard !history.isEmpty else { return nil }

        let mean = history.reduce(0, +) / Double(history.count)

        let sorted = history.sorted()
        let p99Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.99))

        let worstCount = max(1, sorted.count / 100)
        let worst = sorted.suffix(worstCount)
        let worstMean = worst.reduce(0, +) / Double(worst.count)

        return RunSummary(
            averageFPS: 1000 / mean,
            onePercentLowFPS: 1000 / worstMean,
            p99FrameTimeMS: sorted[p99Index],
            meanFrameTimeMS: mean
        )
    }

    private func publish(latest: Double) {
        // The real cost of the frame that just went by, untouched. The
        // headline rate below is smoothed so it stops snapping between the
        // panel's rate and half of it, but this row stays raw: it is what the
        // machine actually just did, and averaging it away would hide the
        // spikes the graph and the percentiles exist to show.
        frameTimeMS = latest

        guard !samples.isEmpty else { return }

        // Headline rate: mean frame time over roughly the last half second.
        let smoothingWindow = max(8, Int(Double(displayRefreshRate) * 0.5))
        let recent = samples.suffix(smoothingWindow)
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        fps = 1000 / recentMean

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
