// RenderSettings.swift
// RealityEsceneTestV2
//
// The graphics-settings panel of the demo, in one value type.
//
// Everything here maps onto RealityKit's own rendering pipeline:
//   RealityViewCameraContent.renderingEffects — MSAA, HDR output, motion blur,
//                                               depth of field, camera grain
//   BloomComponent / BloomOptionsComponent    — HDR highlight bleed
//   ToneMappingComponent                      — filmic curve + exposure
//
// Presets are applied live while the scene runs, so the demo can show the
// cost of each feature instead of only claiming it.

import SwiftUI
import RealityKit

// MARK: - Preset

enum QualityPreset: String, CaseIterable, Hashable {
    case performance
    case balanced
    case ultra

    var label: String {
        switch self {
        case .performance: return "PERFORMANCE"
        case .balanced:    return "BALANCED"
        case .ultra:       return "ULTRA"
        }
    }

    var hint: String {
        switch self {
        case .performance: return "no MSAA · no bloom · SDR"
        case .balanced:    return "MSAA 4x · bloom · HDR"
        case .ultra:       return "MSAA 4x · bloom · HDR · motion blur · DoF"
        }
    }
}

// MARK: - Settings

struct RenderSettings: Equatable {
    var preset: QualityPreset = .ultra

    var multisampling   = true
    var highDynamicRange = true
    var bloom           = true
    var motionBlur      = true
    var depthOfField    = false
    var toneMapping     = true

    var bloomStrength: Float  = 0.30
    var bloomThreshold: Float = 1.15
    var bloomRadius: Float    = 7
    var exposure: Float       = -0.15

    // How far the cascaded shadow maps reach, in metres. This is the single
    // most expensive setting in the scene: every metre is more geometry
    // re-rendered once per cascade, and with hundreds of rigid bodies on
    // screen it dominates the frame.
    var shadowDistance: Float = 22

    init() {}

    init(preset: QualityPreset) {
        self.preset = preset
        switch preset {
        case .performance:
            multisampling    = false
            highDynamicRange = false
            bloom            = false
            motionBlur       = false
            depthOfField     = false
            toneMapping      = true
            exposure         = -0.15
            shadowDistance   = 9
        case .balanced:
            multisampling    = true
            highDynamicRange = true
            bloom            = true
            motionBlur       = false
            depthOfField     = false
            toneMapping      = true
            bloomStrength    = 0.24
            exposure         = -0.15
            shadowDistance   = 15
        case .ultra:
            multisampling    = true
            highDynamicRange = true
            bloom            = true
            motionBlur       = true
            depthOfField     = true
            toneMapping      = true
            bloomStrength    = 0.30
            exposure         = -0.15
            shadowDistance   = 22
        }
    }

    // One line per feature, so the HUD can list exactly what is switched on.
    var activeFeatures: [String] {
        var out: [String] = []
        out.append(multisampling ? "MSAA 4x" : "MSAA off")
        out.append("Shadows \(Int(shadowDistance)) m")
        out.append(highDynamicRange ? "HDR" : "SDR")
        if bloom        { out.append("Bloom") }
        if motionBlur   { out.append("Motion blur") }
        if depthOfField { out.append("DoF") }
        if toneMapping  { out.append("Filmic") }
        return out
    }
}

// MARK: - Applying to the renderer

extension RenderSettings {

    // Full setup. Only for RealityView's make closure: assigning the
    // environment rebinds the skybox and its image-based lighting, which is
    // far too expensive to repeat on every SwiftUI view update.
    @MainActor
    func apply(to content: inout RealityViewCameraContent) {
        applyEffects(to: &content)

        if let sky = EnvironmentFactory.sky() {
            content.environment = .skybox(sky)
        }
    }

    // Just the render flags — cheap enough for the update closure, which runs
    // whenever any state the scene reads changes.
    @MainActor
    func applyEffects(to content: inout RealityViewCameraContent) {
        content.renderingEffects.antialiasing = multisampling ? .multisample4X : .none
        content.renderingEffects.dynamicRange = highDynamicRange ? .default : .standard
        content.renderingEffects.motionBlur   = motionBlur   ? .enabled : .disabled
        content.renderingEffects.depthOfField = depthOfField ? .enabled : .disabled
        content.renderingEffects.cameraGrain  = .disabled
    }

    // Everything in the scene graph that a preset change touches: the
    // post-process entity and the key light's shadow budget.
    @MainActor
    func apply(to rig: SceneRig) {
        apply(to: rig.postFX)

        var shadow = DirectionalLightComponent.Shadow(
            maximumDistance: shadowDistance,
            depthBias: 1.4
        )
        shadow.cascades = .automatic
        rig.sun.shadow = shadow
    }

    // Post-process components live on a dedicated entity. RealityKit picks the
    // options component closest to the camera, so keeping exactly one avoids
    // ambiguity.
    @MainActor
    func apply(to postFX: Entity) {
        if bloom {
            postFX.components.set(BloomComponent(scope: .unbounded))
            var options = BloomOptionsComponent()
            options.strength   = bloomStrength
            options.threshold  = bloomThreshold
            options.blurRadius = bloomRadius
            postFX.components.set(options)
        } else {
            postFX.components.remove(BloomComponent.self)
            postFX.components.remove(BloomOptionsComponent.self)
        }

        if toneMapping {
            postFX.components.set(ToneMappingComponent(exposure: exposure))
        } else {
            postFX.components.remove(ToneMappingComponent.self)
        }
    }
}
