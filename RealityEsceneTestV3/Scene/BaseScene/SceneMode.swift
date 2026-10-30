// SceneMode.swift
// RealityEsceneTestV3

import Foundation

enum SceneMode: Hashable, CaseIterable {
    case audioMovement
    case fisica
    case particles
}

extension SceneMode {
    var overlayTitle: String {
        switch self {
        case .audioMovement: return "🔊 SPATIAL AUDIO"
        case .fisica:        return "🎮 PHYSICS"
        case .particles:     return "✨ PARTICLES"
        }
    }

    var icon: String {
        switch self {
        case .audioMovement: return "🔊"
        case .fisica:        return "🎮"
        case .particles:     return "✨"
        }
    }

    var cardTitle: String {
        switch self {
        case .audioMovement: return "Spatial Audio"
        case .fisica:        return "Physics & Instancing"
        case .particles:     return "Particle VFX"
        }
    }

    var cardSubtitle: String {
        switch self {
        case .audioMovement:
            return "Three looping sources moving on one axis each, heard through the camera as the listener."
        case .fisica:
            return "Seven demos, from mass and restitution up to articulated chains, 512 rigid bodies and 40 000 GPU instances."
        case .particles:
            return "Four effects built on the full emitter parameter set — noise fields, vortex, spawned emitters."
        }
    }

    // Named on the launcher card so the demo states what it is exercising.
    var features: [String] {
        switch self {
        case .audioMovement:
            return ["SpatialAudioComponent", "ReverbComponent", "HRTF listener tracking"]
        case .fisica:
            return ["PhysicsSimulationComponent", "ForceEffectComponent", "MeshInstancesComponent", "ECS sleep + wake"]
        case .particles:
            return ["ParticleEmitterComponent", "Additive blending", "Spawned emitters", "Lit particles"]
        }
    }
}
