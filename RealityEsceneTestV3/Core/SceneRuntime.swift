// SceneRuntime.swift
// RealityEsceneTestV3
//
// Everything the three scenes used to each duplicate: the display link, the
// camera integration, the metrics sampling and the pause/menu handshake.
//
// All three scenes had the same forty lines of onAppear / onFrame /
// onDisappear with slightly different drift between them. One runtime means
// one place where frame pacing, benchmarking and cleanup are correct.

import SwiftUI
import RealityKit
import AppKit
import Observation

@Observable
@MainActor
final class SceneRuntime {

    // MARK: Metrics
    let frameStats = FrameStats()
    let hardware = HardwareMetrics()

    // MARK: Frame loop
    let gameLoop = GameLoop()
    private var lastTimestamp: Double = 0

    // Per-scene work, called every frame after the camera has been updated.
    var onFrame: ((Float) -> Void)?

    private var benchmarkTask: Task<Void, Never>?

    // MARK: Lifecycle

    func start(
        controller: CameraController,
        cameraAnchor: AnchorEntity,
        cameraEntity: PerspectiveCamera
    ) {
        frameStats.reset()
        frameStats.refreshDisplayRate()
        hardware.start()
        controller.startListening()
        startBenchmarkIfRequested()

        gameLoop.onFrame = { [weak self] timestamp in
            guard let self else { return }

            self.frameStats.record(timestamp: timestamp)

            let delta = self.lastTimestamp > 0 ? Float(timestamp - self.lastTimestamp) : 1.0 / 120
            self.lastTimestamp = timestamp

            guard !controller.isPaused else { return }

            controller.update(deltaTime: delta)
            cameraAnchor.position    = controller.position
            cameraAnchor.orientation = simd_quatf(angle: controller.yaw,   axis: [0, 1, 0])
            cameraEntity.orientation = simd_quatf(angle: controller.pitch, axis: [1, 0, 0])

            self.onFrame?(delta)
        }
    }

    func stop(controller: CameraController) {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        gameLoop.stop()
        hardware.stop()
        controller.stopListening()
        controller.resetKeys()

        // The controller is shared between scenes, so every callback this
        // scene installed has to come off with it. Leaving them bound meant
        // the next scene inherited the previous one's key handlers.
        controller.onEPressed = nil
        controller.onCommandKey = nil
        controller.onTabPressed = nil

        onFrame = nil
        lastTimestamp = 0
        releaseMouse()
    }

    // MARK: Benchmark

    // --benchmark <seconds>: let the scene settle, measure, print, quit. The
    // summary goes to stdout so a run can be piped straight into notes or a
    // comparison table.
    private func startBenchmarkIfRequested() {
        let duration = LaunchOptions.current.benchmarkSeconds
        guard duration > 0, benchmarkTask == nil else { return }

        pinWindowForBenchmark()

        benchmarkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.printBenchmark(duration: duration)
            NSApplication.shared.terminate(nil)
        }
    }

    // Every scene here is fill-rate bound, so the window's pixel count is the
    // single biggest variable in any measurement. Left to itself the window
    // opens wherever macOS puts it — on this machine that is either a 1600pt
    // built-in panel at 120 Hz or a 4K external at 60 Hz, which is a fivefold
    // difference in pixels and a twofold one in the ceiling. Two identical
    // sweeps came out 2-3x apart before this existed.
    //
    // Benchmark runs are therefore pinned to a fixed size, so a number from
    // one run means the same thing as a number from the next.
    private func pinWindowForBenchmark() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.setContentSize(NSSize(width: 1600, height: 1000))
        window.center()

        // And brought to the front. macOS throttles an occluded window hard —
        // resizing one into the space behind another dropped a scene that
        // runs at 120 to under 4 fps, with the GPU at a third. A benchmark
        // that measures the compositor's power saving is worth nothing.
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    // The window's own backing pixels, which is what the renderer actually
    // fills — not the screen's resolution, which says nothing about how big
    // the window on it happens to be.
    private var benchmarkSurfaceDescription: String {
        guard let window = NSApplication.shared.windows.first else { return "unknown" }
        let scale = window.backingScaleFactor
        let size = window.contentView?.bounds.size ?? window.frame.size
        return "\(Int(size.width * scale))x\(Int(size.height * scale)) px"
    }

    private func printBenchmark(duration: Double) {
        let options = LaunchOptions.current

        // Name what actually ran: --mode only means anything in the physics
        // scene, and reporting it regardless labelled every particle and
        // audio run as whatever the physics default happened to be.
        let scene: String
        switch options.scene {
        case .fisica:        scene = "physics / \(options.demoMode)"
        case .particles:     scene = "particles / \(options.particleMode)"
        case .audioMovement: scene = "audio"
        case .rendering:     scene = "rendering / \(options.showcaseMode)"
        case nil:            scene = "menu"
        }

        func row(_ label: String, _ value: String) {
            print(" " + label.padding(toLength: 11, withPad: " ", startingAt: 0) + value)
        }

        // macOS throttles an occluded or background window down to a few
        // frames a second, and after several launches in a row it stops
        // granting an app focus at all. Either way the run measures the
        // compositor's power saving, not this machine. Saying so is the only
        // honest option: a confident "0.0 fps" in a results table is worse
        // than no row at all.
        let expected = Double(frameStats.displayRefreshRate) * duration * 0.25
        guard Double(frameStats.recordedFrames) >= expected else {
            print("")
            print("-- BENCHMARK ----------------------------------")
            row("scene", scene)
            row("INVALID", "presented \(frameStats.recordedFrames) frames in \(Int(duration))s")
            print("")
            print(" The window was not frontmost, so macOS throttled it.")
            print(" Run the sweep without using the Mac for anything else.")
            print("-----------------------------------------------")
            print("")
            fflush(stdout)
            return
        }

        print("")
        print("-- BENCHMARK ----------------------------------")
        row("scene", scene)
        row("preset", options.quality.label)
        // Without the resolution these numbers cannot be reproduced or even
        // compared: the renderer is fill-rate bound, so the same scene at 4K
        // costs roughly five times what it does in a 1600x1000 window.
        row("surface", benchmarkSurfaceDescription)
        row("display", "\(frameStats.displayRefreshRate) Hz")
        row("avg", String(format: "%.1f fps", frameStats.averageFPS))
        row("1% low", String(format: "%.1f fps", frameStats.onePercentLowFPS))
        row("frame", String(format: "%.2f ms", 1000 / max(frameStats.averageFPS, 0.001)))
        row("p99", String(format: "%.2f ms", frameStats.p99FrameTimeMS))
        row("dropped", "\(frameStats.droppedFrames)")
        row("cpu", String(format: "%.0f%% of machine (%.2f cores)",
                          hardware.cpuUsage, hardware.cpuCores))
        row("gpu", String(format: "%.0f%%", hardware.gpuUtilization))
        row("alloc", "\(hardware.allocatedBytes / 1_048_576) MB")
        print("-----------------------------------------------")
        print("")
        fflush(stdout)
    }

    // MARK: Mouse capture

    func captureMouse() {
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    func releaseMouse() {
        NSCursor.unhide()
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // The TAB handshake: pause the camera, give the cursor back, and reverse
    // it on close.
    func bindMenuToggle(controller: CameraController, isMenuOpen: Binding<Bool>) {
        controller.onTabPressed = { [weak self] in
            Task { @MainActor in
                isMenuOpen.wrappedValue.toggle()
                controller.isPaused = isMenuOpen.wrappedValue
                if isMenuOpen.wrappedValue {
                    self?.releaseMouse()
                } else {
                    self?.captureMouse()
                }
            }
        }
    }
}
