// AudioMovementScene.swift
// RealityEsceneTestV2
//
// Spatial audio demo. Three sources move on one axis each, and the HUD radar
// shows where they are relative to where the listener is facing.
//
// The listener is the camera entity, set through content.audioListener. V1
// never set it, so RealityKit used the scene origin: turning your head changed
// nothing of what you heard, which is the one thing this scene exists to show.
// The room's reverb comes from the ReverbComponent on the scene root.

import SwiftUI
import RealityKit

struct AudioMovementScene: View {
    let controller: CameraController
    @Binding var isMenuOpen: Bool
    @Binding var renderSettings: RenderSettings

    @State private var cameraAnchor = AnchorEntity(world: .zero)
    @State private var cameraEntity = PerspectiveCamera()
    @State private var runtime = SceneRuntime()

    @State private var rig: SceneRig?
    @State private var spheres: [ModelEntity] = []
    @State private var bobTime: Float = 0

    // Sphere positions mirrored for the HUD. Written from the frame loop —
    // never from RealityView's update closure, which would be mutating state
    // during a view update.
    @State private var positions: [SIMD3<Float>] = Array(repeating: .zero, count: 3)
    @State private var hudExpanded = true
    @State private var radarCounter = 0

    var body: some View {
        ZStack {
            RealityView { content in
                renderSettings.apply(to: &content)
                content.audioListener = cameraEntity

                let builtRig = buildBaseScene(
                    in: content,
                    cameraAnchor: cameraAnchor,
                    cameraEntity: cameraEntity,
                    controller: controller,
                    settings: renderSettings
                )
                rig = builtRig
                spheres = createAudioSpheres(in: builtRig)
            } update: { content in
                renderSettings.applyEffects(to: &content)
            }
            .onChange(of: renderSettings) { _, settings in
                guard let rig else { return }
                settings.apply(to: rig)
            }
            .onAppear {
                controller.position = [0, 1.7, 0]
                controller.yaw   = 0
                controller.pitch = 0
                controller.movementEnabled = false   // look only — the sources move

                runtime.start(
                    controller: controller,
                    cameraAnchor: cameraAnchor,
                    cameraEntity: cameraEntity
                )
                runtime.bindMenuToggle(controller: controller, isMenuOpen: $isMenuOpen)
                bindCommandKeys()

                // Source motion is driven from the frame loop with the real
                // delta, so the paths play back at the same speed on any
                // refresh rate.
                runtime.onFrame = { delta in
                    bobTime += delta * 0.9
                    guard spheres.count == 3 else { return }

                    // Each source still owns one axis, but the paths are
                    // offset so none of them passes through the listener.
                    // They used to orbit through the camera's own position,
                    // which put a translucent emission shell over the whole
                    // viewport and left nothing to look at facing forward.
                    spheres[0].position = [sin(bobTime) * 6, 1.6, -3.6]
                    spheres[1].position = [2.2, 1.8 + sin(bobTime * 0.8 - .pi / 2) * 2.8, -3.6]
                    spheres[2].position = [-2.2, 1.6, sin(bobTime * 1.3 - .pi / 3) * 6]

                    // The radar does not need 120 updates a second, and every
                    // one of them re-evaluates the whole overlay.
                    radarCounter += 1
                    if radarCounter >= 10 {
                        radarCounter = 0
                        positions = spheres.map { $0.position }
                    }
                }
            }
            .onDisappear {
                controller.movementEnabled = true
                runtime.stop(controller: controller)
                spheres.forEach { $0.stopAllAudio() }
                spheres = []
            }

            PerformanceHUD(
                title: "🔊  Spatial Audio",
                subtitle: "3 looping sources, one per axis — headphones recommended",
                feature: "SpatialAudioComponent · ReverbComponent · audioListener",
                stats: runtime.frameStats,
                hardware: runtime.hardware,
                quality: renderSettings.preset,
                extraStats: [
                    HUDStat(label: "SOURCES", value: "\(spheres.count)"),
                    HUDStat(label: "REVERB", value: "largeRoom", tint: .cyan),
                    HUDStat(label: "LISTENER", value: "camera", tint: .cyan)
                ],
                expanded: hudExpanded
            )

            SpatialHUD(
                spherePositions: positions,
                listenerPosition: controller.position,
                listenerYaw: controller.yaw
            )

            DisplayLinkView(gameLoop: runtime.gameLoop)
                .frame(width: 0, height: 0)
        }
    }

    private func bindCommandKeys() {
        controller.onCommandKey = { key in
            Task { @MainActor in
                switch key {
                case "1": renderSettings = RenderSettings(preset: .performance)
                case "2": renderSettings = RenderSettings(preset: .balanced)
                case "3": renderSettings = RenderSettings(preset: .ultra)
                case "h": hudExpanded.toggle()
                default: break
                }
            }
        }
        controller.onEPressed = { }
    }
}
