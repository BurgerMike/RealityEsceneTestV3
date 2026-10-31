// RenderShowcaseScene.swift
// RealityEsceneTestV3
//
// The rendering scene: parts of RealityKit that are about what the renderer
// can do rather than what the simulation can do.
//
// Portals render a second world through a surface in this one. The material
// lab takes a PBR material apart channel by channel. Neither is a physics
// demo, so neither belongs in the physics scene, and both want the same
// camera, HUD and quality handling every other scene already has.

import SwiftUI
import RealityKit

enum ShowcaseMode: CaseIterable {
    case portals
    case materials
    case surface

    var label: String {
        switch self {
        case .portals:   return "🪟  Portals"
        case .materials: return "🎨  Material Lab"
        case .surface:   return "🌊  Procedural Mesh"
        }
    }

    var hint: String {
        switch self {
        case .portals:   return "three windows onto three separate worlds"
        case .materials: return "press E to step through the PBR channels"
        case .surface:   return "every vertex written by a compute kernel, every frame"
        }
    }

    var feature: String {
        switch self {
        case .portals:   return "PortalComponent · WorldComponent"
        case .materials: return "ModelDebugOptionsComponent"
        case .surface:   return "LowLevelMesh · Metal compute"
        }
    }

    var actionKeyHint: String {
        switch self {
        case .portals:   return "—"
        case .materials: return "channel"
        case .surface:   return "—"
        }
    }
}

struct RenderShowcaseScene: View {
    let controller: CameraController
    @Binding var isMenuOpen: Bool
    @Binding var currentShowcaseMode: ShowcaseMode
    @Binding var renderSettings: RenderSettings

    @State private var cameraAnchor = AnchorEntity(world: .zero)
    @State private var cameraEntity = PerspectiveCamera()
    @State private var runtime = SceneRuntime()

    @State private var rig: SceneRig?
    @State private var activeEntities: [Entity] = []

    @State private var samples: [ModelEntity] = []
    @State private var channel: MaterialChannel = .final
    @State private var portalCount = 0
    @State private var surfaceVertices = 0
    @State private var surfaceTriangles = 0
    @State private var surfaceOnGPU = false
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
                load(currentShowcaseMode, rig: builtRig)
            } update: { content in
                renderSettings.applyEffects(to: &content)
            }
            .onChange(of: currentShowcaseMode) { _, newMode in
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
                bindKeys()

                // Sampled rather than assumed: the kernel may not have loaded.
                runtime.onFrame = { _ in
                    guard currentShowcaseMode == .surface else { return }
                    surfaceOnGPU = ProceduralSurfaceSystem.onGPU
                }
            }
            .onDisappear {
                runtime.stop(controller: controller)
                activeEntities.forEach { $0.removeFromParent() }
                activeEntities = []
                samples = []
            }

            PerformanceHUD(
                title: currentShowcaseMode.label,
                subtitle: currentShowcaseMode.hint,
                feature: currentShowcaseMode.feature,
                stats: runtime.frameStats,
                hardware: runtime.hardware,
                quality: renderSettings.preset,
                extraStats: extraStats,
                expanded: hudExpanded,
                actionKeyHint: currentShowcaseMode.actionKeyHint
            )

            DisplayLinkView(gameLoop: runtime.gameLoop)
                .frame(width: 0, height: 0)
        }
    }

    private var extraStats: [HUDStat] {
        switch currentShowcaseMode {
        case .portals:
            return [
                HUDStat(label: "PORTALS", value: "\(portalCount)", tint: .cyan),
                HUDStat(label: "WORLDS", value: "\(portalCount)", tint: .cyan),
                HUDStat(label: "BOUNDARY", value: "infinite plane")
            ]
        case .materials:
            return [
                HUDStat(label: "CHANNEL", value: channel.label, tint: .cyan),
                HUDStat(label: "", value: channel.explanation, tint: .white.opacity(0.55)),
                HUDStat(label: "SAMPLES", value: "\(samples.count)")
            ]

        case .surface:
            return [
                HUDStat(label: "VERTICES", value: surfaceVertices.formatted(), tint: .cyan),
                HUDStat(label: "TRIANGLES", value: surfaceTriangles.formatted(), tint: .cyan),
                HUDStat(label: "REBUILT",
                        value: surfaceOnGPU ? "GPU, every frame" : "not running",
                        tint: surfaceOnGPU ? .green : .orange)
            ]
        }
    }

    private func load(_ mode: ShowcaseMode, rig: SceneRig) {
        activeEntities.forEach { $0.removeFromParent() }
        activeEntities = []
        samples = []
        portalCount = 0
        surfaceVertices = 0
        surfaceTriangles = 0
        surfaceOnGPU = false
        channel = LaunchOptions.current.materialChannel

        switch mode {
        case .portals:
            let result = setupPortals(in: rig)
            activeEntities = result.entities
            portalCount = result.portalCount

        case .materials:
            let result = setupMaterialLab(in: rig)
            activeEntities = result.entities
            samples = result.samples
            applyChannel(channel, to: samples)

        case .surface:
            let result = setupProceduralSurface(in: rig)
            activeEntities = result.entities
            surfaceVertices = result.vertexCount
            surfaceTriangles = result.triangleCount
        }
    }

    private func bindKeys() {
        controller.onEPressed = {
            Task { @MainActor in
                guard currentShowcaseMode == .materials else { return }
                channel = channel.next
                applyChannel(channel, to: samples)
            }
        }

        controller.onCommandKey = { key in
            Task { @MainActor in
                switch key {
                case "1": renderSettings = RenderSettings(preset: .performance)
                case "2": renderSettings = RenderSettings(preset: .balanced)
                case "3": renderSettings = RenderSettings(preset: .ultra)
                case "r":
                    if let rig { load(currentShowcaseMode, rig: rig) }
                case "h": hudExpanded.toggle()
                default: break
                }
            }
        }
    }
}
