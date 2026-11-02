// RenderSettings.swift
// RealityEsceneTestV3
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
    case auto
    case performance
    case balanced
    case ultra

    var label: String {
        switch self {
        case .auto:        return "AUTO"
        case .performance: return "PERFORMANCE"
        case .balanced:    return "BALANCED"
        case .ultra:       return "ULTRA"
        }
    }

    var hint: String {
        switch self {
        case .auto:        return "picked from the window's pixel count"
        case .performance: return "no MSAA · no bloom · SDR"
        case .balanced:    return "MSAA 4x · bloom · HDR"
        case .ultra:       return "MSAA 4x · bloom · HDR · motion blur · DoF"
        }
    }

    // Which of the three fixed presets AUTO stands for at a given surface size.
    //
    // Every scene here is fill-rate bound, so the drawable's pixel count is
    // the one number worth branching on — and MSAA 4x multiplies whatever that
    // number is. The bands are the panels people actually sit in front of:
    //
    //   up to  9 Mpx   a 14-inch MacBook Pro (5.9) or a 4K display (8.3)
    //   up to 16 Mpx   a 5K display (14.7)
    //   above          6K and up (20.4), where offering ULTRA is a lie
    //
    // Deliberately three bands and not a continuous scale. --quality ultra has
    // to mean the same thing on every machine or none of the numbers in the
    // README can be compared to each other, so AUTO resolves to one of the
    // documented presets and the benchmark summary prints which one it picked.
    static func resolved(forSurfacePixels pixels: Double) -> QualityPreset {
        // Before the first layout there is no drawable to measure. ULTRA is
        // the configuration the README reports, so an unmeasured surface gets
        // that rather than a guess, and the first layout corrects it.
        guard pixels > 0 else { return .ultra }
        if pixels > 16_000_000 { return .performance }
        if pixels >  9_000_000 { return .balanced }
        return .ultra
    }

    func resolving(surfacePixels pixels: Double) -> QualityPreset {
        self == .auto ? Self.resolved(forSurfacePixels: pixels) : self
    }
}

// MARK: - Settings

struct RenderSettings: Equatable {
    // What was asked for, which may be .auto.
    var selection: QualityPreset = .ultra

    // What .auto worked out to. Never .auto itself, so everything downstream
    // can keep switching on it exhaustively.
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

    // Kept for the 1/2/3 hotkeys, which name a fixed preset and need no
    // surface. An .auto passed here lands on ULTRA until the first layout
    // reports a real size.
    init(preset: QualityPreset) {
        self.init(preset, surfacePixels: 0)
    }

    init(_ selection: QualityPreset, surfacePixels: Double) {
        let resolved = selection.resolving(surfacePixels: surfacePixels)
        self.selection = selection
        self.preset = resolved
        switch resolved {
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
        // .auto is already resolved away above; it shares this branch only to
        // keep the switch exhaustive.
        case .ultra, .auto:
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

        Self.activeLabel = benchmarkLabel
    }

    // What the benchmark summary prints. An AUTO run has to say what it ran
    // as, or its row cannot be compared with any other row.
    var benchmarkLabel: String {
        selection == .auto ? "AUTO (\(preset.label))" : preset.label
    }

    // Read by the benchmark summary, which lives in SceneRuntime and never
    // sees the scene's settings. Same reason as toneMappingOwner below: the
    // alternative is threading a label through four scenes that do not care.
    @MainActor static var activeLabel = QualityPreset.ultra.label

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
            // RealityKit allows one ToneMappingComponent per scene. A previous
            // scene's rig can outlive its view for a moment while scenes
            // switch, so hand the component over instead of duplicating it.
            if let previous = Self.toneMappingOwner, previous !== postFX {
                previous.components.remove(ToneMappingComponent.self)
            }
            postFX.components.set(ToneMappingComponent(exposure: exposure))
            Self.toneMappingOwner = postFX
        } else {
            postFX.components.remove(ToneMappingComponent.self)
            if Self.toneMappingOwner === postFX { Self.toneMappingOwner = nil }
        }
    }

    // The entity that currently carries the scene's single ToneMappingComponent.
    @MainActor private static weak var toneMappingOwner: Entity?
}
