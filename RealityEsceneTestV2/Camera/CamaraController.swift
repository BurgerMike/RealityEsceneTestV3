// CamaraController.swift
// RealityEsceneTestV2
//
// First-person camera driven by NSEvent monitors.
//
// The movement integration is delta-time based. V1 added a fixed 0.05 per
// frame, which means the player walked twice as fast on a 120 Hz display as on
// a 60 Hz one — the demo's own frame rate changed the gameplay. Speed is now
// in metres per second and multiplied by the real frame delta, so the scene
// behaves identically at any refresh rate.

import SwiftUI
import RealityKit
import AppKit
import Observation

@Observable
final class CameraController {

    // MARK: Pose
    var position: SIMD3<Float> = [0, 1.7, 4]
    var yaw: Float = 0
    var pitch: Float = -.pi / 12

    // MARK: Tuning — metres per second, not per frame
    private let walkSpeed: Float = 3.4
    private let sprintSpeed: Float = 8.0
    private let acceleration: Float = 14.0
    var mouseSensitivity: Float = 0.0028

    private let eyeHeight: Float = 1.7
    private let arenaHalfExtent: Float = 10.4

    // MARK: Input state
    private var pressedKeys: Set<String> = []
    private var velocity: SIMD3<Float> = .zero

    // All monitors are retained. V1 kept only the first and leaked the other
    // four for the lifetime of the process.
    private var monitors: [Any] = []

    // MARK: Callbacks
    var onTabPressed: (() -> Void)?
    var onEPressed: (() -> Void)?
    // Any other single key the scene wants to act on — quality presets, reload.
    var onCommandKey: ((String) -> Void)?

    var movementEnabled: Bool = true

    // Clearing the keys on pause matters: when the menu takes focus, keyUp
    // never fires for whatever was held down, so W or Shift stays stuck.
    var isPaused: Bool = false {
        didSet {
            if isPaused {
                pressedKeys.removeAll()
                velocity = .zero
            }
        }
    }

    // Keys the scene handles rather than the camera.
    private let commandKeys: Set<String> = ["1", "2", "3", "r", "h", "f"]

    func startListening() {
        let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {                      // esc — release the mouse
                NSCursor.unhide()
                CGAssociateMouseAndMouseCursorPosition(1)
                return event
            }
            if event.keyCode == 48 {                      // tab — menu
                self.onTabPressed?()
                return nil
            }

            let key = (event.charactersIgnoringModifiers ?? "").lowercased()

            if key == "e" {
                self.onEPressed?()
                return nil
            }
            if self.commandKeys.contains(key) {
                self.onCommandKey?(key)
                return nil
            }

            self.pressedKeys.insert(key)
            return nil
        }

        let keyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.pressedKeys.remove((event.charactersIgnoringModifiers ?? "").lowercased())
            return event
        }

        let mouseMove = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, !self.isPaused else { return event }
            self.handleMouseDelta(dx: Float(event.deltaX), dy: Float(event.deltaY))
            return event
        }

        // Dragging counts as looking too — otherwise holding the button while
        // turning freezes the view.
        let mouseDrag = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self, !self.isPaused else { return event }
            self.handleMouseDelta(dx: Float(event.deltaX), dy: Float(event.deltaY))
            return event
        }

        let mouseDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, !self.isPaused else { return event }
            NSCursor.hide()
            CGAssociateMouseAndMouseCursorPosition(0)
            return event
        }

        let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if event.modifierFlags.contains(.shift) {
                self?.pressedKeys.insert("shift")
            } else {
                self?.pressedKeys.remove("shift")
            }
            return event
        }

        monitors = [keyDown, keyUp, mouseMove, mouseDrag, mouseDown, flags].compactMap { $0 }
    }

    func stopListening() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    var isSprinting: Bool { pressedKeys.contains("shift") }
    var speed: Float { length(velocity) }

    // deltaTime in seconds, straight from the display link.
    func update(deltaTime: Float) {
        guard movementEnabled else {
            velocity = .zero
            return
        }

        let dt = min(max(deltaTime, 0.0001), 0.1)   // clamp: a stall must not teleport the camera

        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let right   = SIMD3<Float>( cos(yaw), 0, -sin(yaw))

        var wish = SIMD3<Float>.zero
        if pressedKeys.contains("w") { wish += forward }
        if pressedKeys.contains("s") { wish -= forward }
        if pressedKeys.contains("a") { wish -= right }
        if pressedKeys.contains("d") { wish += right }

        let targetSpeed = isSprinting ? sprintSpeed : walkSpeed
        let target = length(wish) > 0.0001 ? normalize(wish) * targetSpeed : .zero

        // Exponential approach — gives weight to starting and stopping instead
        // of the camera snapping between still and full speed.
        let blend = 1 - exp(-acceleration * dt)
        velocity += (target - velocity) * blend

        var next = position + velocity * dt
        next.x = max(-arenaHalfExtent, min(arenaHalfExtent, next.x))
        next.z = max(-arenaHalfExtent, min(arenaHalfExtent, next.z))
        next.y = eyeHeight
        position = next
    }

    func handleMouseDelta(dx: Float, dy: Float) {
        yaw   -= dx * mouseSensitivity
        pitch -= dy * mouseSensitivity
        pitch = max(-.pi / 2 + 0.01, min(.pi / 2 - 0.01, pitch))
    }

    func resetKeys() {
        pressedKeys.removeAll()
        velocity = .zero
    }
}
