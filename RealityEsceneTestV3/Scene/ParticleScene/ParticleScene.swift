// ParticleScene.swift
// RealityEsceneTestV3
//
// Particle effects behind the same TAB overlay as the physics scene. The HUD
// reports the emitter's configured birth rate and the resulting particle
// budget, so the cost of each effect is on screen next to the frame time.

import SwiftUI
import RealityKit

struct ParticleScene: View {
    let controller: CameraController
    @Binding var isMenuOpen: Bool
    @Binding var currentParticleMode: ParticleMode
    @Binding var renderSettings: RenderSettings

    @State private var cameraAnchor = AnchorEntity(world: .zero)
    @State private var cameraEntity = PerspectiveCamera()
    @State private var runtime = SceneRuntime()

    @State private var rig: SceneRig?
    @State private var sceneContent: (any RealityViewContentProtocol)?
    @State private var activeEntities: [Entity] = []

    @State private var emitterCount = 0
    @State private var hudExpanded = true

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
                sceneContent = content

                load(currentParticleMode, rig: builtRig)
            } update: { content in
                renderSettings.applyEffects(to: &content)
            }
            .onChange(of: currentParticleMode) { _, newMode in
                guard let rig else { return }
                load(newMode, rig: rig)
            }
            .onChange(of: renderSettings) { _, settings in
                guard let rig else { return }
                settings.apply(to: rig)
            }
            .onAppear {
                runtime.start(
                    controller: controller,
                    cameraAnchor: cameraAnchor,
                    cameraEntity: cameraEntity
                )
                runtime.bindMenuToggle(controller: controller, isMenuOpen: $isMenuOpen)
                bindCommandKeys()
            }
            .onDisappear {
                runtime.stop(controller: controller)
                activeEntities.forEach { $0.removeFromParent() }
                activeEntities = []
            }

            PerformanceHUD(
                title: currentParticleMode.label,
                subtitle: currentParticleMode.hint,
                feature: currentParticleMode.feature,
                stats: runtime.frameStats,
                hardware: runtime.hardware,
                quality: renderSettings.preset,
                extraStats: [
                    HUDStat(label: "EMITTERS", value: "\(emitterCount)"),
                    HUDStat(label: "BIRTH RATE",
                            value: "\(Int(currentParticleMode.birthRate))/s",
                            tint: .cyan),
                    HUDStat(label: "PEAK PARTICLES",
                            value: Int(currentParticleMode.peakParticles).formatted(),
                            tint: .cyan)
                ],
                expanded: hudExpanded
            )

            DisplayLinkView(gameLoop: runtime.gameLoop)
                .frame(width: 0, height: 0)
        }
    }

    private func load(_ mode: ParticleMode, rig: SceneRig) {
        activeEntities.forEach { $0.removeFromParent() }
        activeEntities = []

        switch mode {
        case .rain:   activeEntities = setupRain(in: rig)
        case .snow:   activeEntities = setupSnow(in: rig)
        case .fire:   activeEntities = setupFire(in: rig)
        case .sparks: activeEntities = setupSparks(in: rig)
        }

        emitterCount = activeEntities.filter {
            $0.components.has(ParticleEmitterComponent.self)
        }.count
    }

    private func bindCommandKeys() {
        controller.onCommandKey = { key in
            Task { @MainActor in
                switch key {
                case "1": renderSettings = RenderSettings(preset: .performance)
                case "2": renderSettings = RenderSettings(preset: .balanced)
                case "3": renderSettings = RenderSettings(preset: .ultra)
                case "r":
                    if let rig { load(currentParticleMode, rig: rig) }
                case "h": hudExpanded.toggle()
                default: break
                }
            }
        }
    }
}
