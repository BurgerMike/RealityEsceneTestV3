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

        benchmarkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.printBenchmark()
            NSApplication.shared.terminate(nil)
        }
    }

    private func printBenchmark() {
        let options = LaunchOptions.current

        // Name what actually ran: --mode only means anything in the physics
        // scene, and reporting it regardless labelled every particle and
        // audio run as whatever the physics default happened to be.
        let scene: String
        switch options.scene {
        case .fisica:        scene = "physics / \(options.demoMode)"
        case .particles:     scene = "particles / \(options.particleMode)"
        case .audioMovement: scene = "audio"
        case nil:            scene = "menu"
        }

        func row(_ label: String, _ value: String) {
            print(" " + label.padding(toLength: 11, withPad: " ", startingAt: 0) + value)
        }

        print("")
        print("-- BENCHMARK ----------------------------------")
        row("scene", scene)
        row("preset", options.quality.label)
        row("display", "\(frameStats.displayRefreshRate) Hz")
        row("avg", String(format: "%.1f fps", frameStats.averageFPS))
        row("1% low", String(format: "%.1f fps", frameStats.onePercentLowFPS))
        row("frame", String(format: "%.2f ms", 1000 / max(frameStats.averageFPS, 0.001)))
        row("p99", String(format: "%.2f ms", frameStats.p99FrameTimeMS))
        row("dropped", "\(frameStats.droppedFrames)")
        row("cpu", String(format: "%.0f%%", hardware.cpuUsage))
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
