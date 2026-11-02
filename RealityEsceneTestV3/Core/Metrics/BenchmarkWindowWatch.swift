// BenchmarkWindowWatch.swift
// RealityEsceneTestV3
//
// The one thing that can quietly invalidate a benchmark on macOS: the window
// stopped being on screen and frontmost, so the compositor throttled it and
// the run measured power saving instead of this machine.
//
// This used to be inferred from the frame count — "fewer than a quarter of
// the display's frames means the window was throttled". That rule cannot
// tell a throttled window from a demo that is honestly slow. The
// 40 000-instance field runs at roughly 22 fps on a 120 Hz panel with the
// GPU pinned near 100%, so it presents about 220 of the 1200 frames the
// panel could have shown, and every single run of it was thrown away as
// invalid. Ask AppKit what the window is doing instead of guessing it from
// the symptom.

import AppKit

@MainActor
final class BenchmarkWindowWatch {

    // Polled, not driven by didChangeOcclusionStateNotification. An
    // observer block is @Sendable and runs on whichever queue the centre
    // picks, which under this project's default-MainActor isolation is an
    // isolation trap — the same one that crashed the GPU sampler. Polling
    // from the benchmark's own MainActor task cannot trap, and a tenth of a
    // second is far finer than any throttling that could move a ten-second
    // average.
    static let intervalSeconds = 0.1

    private var occluded = 0
    private var background = 0
    private var total = 0

    // Deliberately not NSApp.mainWindow, which is nil precisely when the app
    // is inactive — the case this is here to catch.
    private var window: NSWindow? { NSApplication.shared.windows.first }

    func sample() {
        total += 1
        if let window, !window.occlusionState.contains(.visible) { occluded += 1 }
        if !NSApplication.shared.isActive { background += 1 }
    }

    // nil when the run can be trusted.
    func invalidReason(recordedFrames: Int, duration: Double) -> String? {
        // One stray sample is not worth discarding a run for: a window can
        // report itself occluded for a moment while it is being brought to
        // the front. A real stretch is a tenth of the run.
        let tolerated = max(2, total / 10)

        if occluded > tolerated {
            return "window was occluded for \(elapsed(occluded)) of the run"
        }
        if background > tolerated {
            return "app was not frontmost for \(elapsed(background)) of the run"
        }

        // Last resort, and the only frame-count rule left. If the window says
        // it stayed visible and frontmost and the display link still produced
        // less than a frame a second, whatever came out is not a frame rate.
        if Double(recordedFrames) < duration {
            return "presented only \(recordedFrames) frames in \(Int(duration))s"
        }

        return nil
    }

    private func elapsed(_ samples: Int) -> String {
        String(format: "%.1fs", Double(samples) * Self.intervalSeconds)
    }
}
