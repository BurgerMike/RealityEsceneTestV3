// ParticleEffects.swift
// RealityEsceneTestV2
//
// Four effects, each exercising a different part of ParticleEmitterComponent.
//
// V1 used five properties per emitter: shape, birth rate, lifespan, size and
// acceleration. The emitter exposes the rest of what a game VFX system needs
// and that is where the quality is — additive blending for anything glowing,
// opacity curves so particles fade instead of popping, noise fields for drift,
// vortex for swirl, spawnedEmitter so rain can splash when a drop dies, and
// isLightingEnabled so snow picks up the scene's own light.

import RealityKit
import SwiftUI

// MARK: - Particle Mode

enum ParticleMode: CaseIterable {
    case rain
    case snow
    case fire
    case sparks

    var label: String {
        switch self {
        case .rain:   return "🌧  Rain"
        case .snow:   return "❄️  Snow"
        case .fire:   return "🔥  Fire"
        case .sparks: return "✨  Sparks"
        }
    }

    var hint: String {
        switch self {
        case .rain:   return "stretched drops with splash spawned on death"
        case .snow:   return "lit particles drifting through a noise field"
        case .fire:   return "additive blend, colour evolution, point light"
        case .sparks: return "vortex field, angular spread, trail emitter"
        }
    }

    var feature: String {
        switch self {
        case .rain:   return "ParticleEmitterComponent · spawnOccasion .onDeath"
        case .snow:   return "ParticleEmitter · noiseStrength · isLightingEnabled"
        case .fire:   return "ParticleEmitter · blendMode .additive"
        case .sparks: return "ParticleEmitter · vortexStrength · spawnedEmitter"
        }
    }

    // Shown in the HUD so the cost of the effect is on screen with the frame
    // time. Peak is birth rate times lifespan — the steady-state population.
    var birthRate: Float {
        switch self {
        case .rain:   return 2400
        case .snow:   return 600
        case .fire:   return 1000
        case .sparks: return 1800
        }
    }

    var peakParticles: Float {
        switch self {
        case .rain:   return birthRate * 2.0
        case .snow:   return birthRate * 9.0
        case .fire:   return birthRate * 1.4 + 600
        case .sparks: return birthRate * 2.2
        }
    }
}

// MARK: - Mode 1: Rain

@MainActor
func setupRain(in rig: SceneRig) -> [Entity] {
    let emitter = Entity()
    emitter.name = "rain"
    emitter.position = [0, 9, 0]

    var particles = ParticleEmitterComponent()
    particles.emitterShape     = .plane
    particles.emitterShapeSize = [22, 0, 22]
    particles.birthDirection   = .world
    particles.emissionDirection = [0, -1, 0]
    particles.speed = 9

    var drop = particles.mainEmitter
    drop.birthRate     = ParticleMode.rain.birthRate
    drop.lifeSpan      = 2.0
    drop.lifeSpanVariation = 0.3
    drop.size          = 0.02
    drop.sizeVariation = 0.008
    drop.acceleration  = [0, -22, 0]
    drop.stretchFactor = 9                      // drops, not dots
    drop.blendMode     = .alpha
    drop.opacityCurve  = .easeFadeIn
    drop.sortOrder     = .decreasingDepth
    drop.billboardMode = .billboardYAligned
    drop.color = .constant(.single(.init(
        red: 0.72, green: 0.86, blue: 1.0, alpha: 0.55
    )))
    particles.mainEmitter = drop

    // Splash: a second emitter fired at the end of each drop's life. This is
    // the part that reads as rain hitting a floor rather than rain falling
    // through one.
    var splash = ParticleEmitterComponent.ParticleEmitter()
    splash.birthRate     = 6
    splash.lifeSpan      = 0.35
    splash.size          = 0.012
    splash.acceleration  = [0, -6, 0]
    splash.spreadingAngle = .pi / 3
    splash.blendMode     = .alpha
    splash.opacityCurve  = .linearFadeOut
    splash.color = .constant(.single(.init(
        red: 0.8, green: 0.92, blue: 1.0, alpha: 0.5
    )))
    particles.spawnedEmitter = splash
    particles.spawnOccasion  = .onDeath

    emitter.components.set(particles)
    rig.install(emitter, castsShadow: false)
    return [emitter]
}

// MARK: - Mode 2: Snow

@MainActor
func setupSnow(in rig: SceneRig) -> [Entity] {
    let emitter = Entity()
    emitter.name = "snow"
    emitter.position = [0, 9, 0]

    var particles = ParticleEmitterComponent()
    particles.emitterShape     = .plane
    particles.emitterShapeSize = [22, 0, 22]
    particles.birthDirection   = .world
    particles.emissionDirection = [0, -1, 0]
    particles.speed = 0.5

    var flake = particles.mainEmitter
    flake.birthRate     = ParticleMode.snow.birthRate
    flake.lifeSpan      = 9.0
    flake.lifeSpanVariation = 2.0
    flake.size          = 0.045
    flake.sizeVariation = 0.02
    flake.acceleration  = [0, -0.55, 0]
    flake.dampingFactor = 2.2                   // air resistance, so it floats
    flake.stretchFactor = 0

    // Noise field — each flake takes its own wandering path instead of the
    // whole snowfall descending on rails.
    flake.noiseStrength       = 0.55
    flake.noiseScale          = 1.4
    flake.noiseAnimationSpeed = 0.35

    flake.angularSpeed          = 1.2
    flake.angularSpeedVariation = 0.8

    // Lit by the scene's own lights, so flakes brighten under the key light
    // and darken in shadow.
    flake.isLightingEnabled = true
    flake.blendMode    = .alpha
    flake.opacityCurve = .gradualFadeInOut
    flake.sortOrder    = .decreasingDepth
    flake.color = .constant(.single(.init(white: 1.0, alpha: 0.92)))
    particles.mainEmitter = flake

    emitter.components.set(particles)
    rig.install(emitter, castsShadow: false)
    return [emitter]
}

// MARK: - Mode 3: Fire

@MainActor
func setupFire(in rig: SceneRig) -> [Entity] {
    var entities: [Entity] = []

    // Flickering light so the fire lights the floor and the arena walls.
    let light = Entity()
    light.name = "fireLight"
    light.position = [0, 0.9, 0]
    var pointLight = PointLightComponent()
    pointLight.color     = .init(red: 1.0, green: 0.45, blue: 0.15, alpha: 1.0)
    pointLight.intensity = 9000
    pointLight.attenuationRadius = 11
    light.components.set(pointLight)
    rig.install(light, castsShadow: false)
    entities.append(light)

    // Emissive core — bright enough to cross the bloom threshold.
    let core = ModelEntity(
        mesh: .generateSphere(radius: 0.18),
        materials: [Mat.neon(.init(red: 1.0, green: 0.42, blue: 0.08, alpha: 1), intensity: 7)]
    )
    core.position = [0, 0.32, 0]
    rig.install(core, castsShadow: false)
    entities.append(core)

    // MARK: Flame
    let flame = Entity()
    flame.position = [0, 0.3, 0]

    var fire = ParticleEmitterComponent()
    fire.emitterShape     = .sphere
    fire.emitterShapeSize = [0.22, 0.12, 0.22]
    fire.birthDirection   = .world
    fire.emissionDirection = [0, 1, 0]
    fire.speed = 1.1

    var flameEmitter = fire.mainEmitter
    flameEmitter.birthRate     = ParticleMode.fire.birthRate
    flameEmitter.lifeSpan      = 1.1
    flameEmitter.lifeSpanVariation = 0.35
    flameEmitter.size          = 0.13
    flameEmitter.sizeVariation = 0.05
    flameEmitter.sizeMultiplierAtEndOfLifespan = 0.25   // tapers as it rises
    flameEmitter.acceleration  = [0, 3.4, 0]
    flameEmitter.stretchFactor = 1.6
    flameEmitter.spreadingAngle = .pi / 9
    flameEmitter.noiseStrength = 0.7
    flameEmitter.noiseScale    = 2.2
    flameEmitter.noiseAnimationSpeed = 1.6

    // Additive is what makes overlapping particles build into a hot core
    // instead of flattening into one orange blob.
    flameEmitter.blendMode    = .additive
    flameEmitter.opacityCurve = .linearFadeOut
    flameEmitter.sortOrder    = .unsorted
    flameEmitter.colorEvolutionPower = 1.8
    flameEmitter.color = .evolving(
        start: .single(.init(red: 1.0, green: 0.78, blue: 0.25, alpha: 1.0)),
        end:   .single(.init(red: 0.85, green: 0.12, blue: 0.02, alpha: 0.0))
    )
    fire.mainEmitter = flameEmitter

    flame.components.set(fire)
    rig.install(flame, castsShadow: false)
    entities.append(flame)

    // MARK: Smoke
    let smokeEntity = Entity()
    smokeEntity.position = [0, 1.6, 0]

    var smoke = ParticleEmitterComponent()
    smoke.emitterShape     = .sphere
    smoke.emitterShapeSize = [0.3, 0.2, 0.3]
    smoke.birthDirection   = .world
    smoke.emissionDirection = [0, 1, 0]
    smoke.speed = 0.5

    var smokeEmitter = smoke.mainEmitter
    smokeEmitter.birthRate = 70
    smokeEmitter.lifeSpan  = 2.8
    smokeEmitter.lifeSpanVariation = 1.0
    smokeEmitter.size      = 0.26
    smokeEmitter.sizeMultiplierAtEndOfLifespan = 2.2    // billows outward
    smokeEmitter.acceleration = [0.25, 1.1, 0]
    smokeEmitter.dampingFactor = 1.1
    smokeEmitter.noiseStrength = 0.5
    smokeEmitter.noiseScale    = 1.8
    smokeEmitter.angularSpeed  = 0.4
    smokeEmitter.isLightingEnabled = true
    smokeEmitter.blendMode    = .alpha
    smokeEmitter.opacityCurve = .gradualFadeInOut
    smokeEmitter.sortOrder    = .decreasingDepth
    smokeEmitter.color = .evolving(
        start: .single(.init(white: 0.26, alpha: 0.30)),
        end:   .single(.init(white: 0.10, alpha: 0.0))
    )
    smoke.mainEmitter = smokeEmitter

    smokeEntity.components.set(smoke)
    rig.install(smokeEntity, castsShadow: false)
    entities.append(smokeEntity)

    return entities
}

// MARK: - Mode 4: Sparks

@MainActor
func setupSparks(in rig: SceneRig) -> [Entity] {
    var entities: [Entity] = []

    let anchor = ModelEntity(
        mesh: .generateSphere(radius: 0.09),
        materials: [Mat.neon(.init(red: 1.0, green: 0.95, blue: 0.7, alpha: 1), intensity: 9)]
    )
    anchor.position = [0, 1.4, 0]
    rig.install(anchor, castsShadow: false)
    entities.append(anchor)

    let emitter = Entity()
    emitter.position = [0, 1.4, 0]

    var particles = ParticleEmitterComponent()
    particles.emitterShape     = .sphere
    particles.emitterShapeSize = [0.06, 0.06, 0.06]
    particles.birthDirection   = .world
    particles.speed = 4.2
    particles.speedVariation = 2.0

    var spark = particles.mainEmitter
    spark.birthRate     = ParticleMode.sparks.birthRate
    spark.lifeSpan      = 1.8
    spark.lifeSpanVariation = 0.7
    spark.size          = 0.022
    spark.acceleration  = [0, -7.5, 0]
    spark.stretchFactor = 6
    spark.spreadingAngle = .pi
    spark.dampingFactor = 0.8

    // Vortex field — the sparks spiral out instead of falling in a cone.
    spark.vortexStrength  = 2.4
    spark.vortexDirection = [0, 1, 0]

    spark.blendMode    = .additive
    spark.opacityCurve = .easeFadeOut
    spark.sortOrder    = .unsorted
    spark.billboardMode = .billboardYAligned
    spark.color = .evolving(
        start: .single(.init(red: 1.0, green: 1.0,  blue: 0.85, alpha: 1.0)),
        end:   .single(.init(red: 1.0, green: 0.28, blue: 0.0,  alpha: 0.0))
    )
    particles.mainEmitter = spark

    // Trail — each spark leaves a thin stream of embers behind it.
    var trail = ParticleEmitterComponent.ParticleEmitter()
    trail.birthRate    = 24
    trail.lifeSpan     = 0.4
    trail.size         = 0.01
    trail.acceleration = [0, -2, 0]
    trail.blendMode    = .additive
    trail.opacityCurve = .linearFadeOut
    trail.color = .constant(.single(.init(red: 1.0, green: 0.55, blue: 0.1, alpha: 0.7)))
    particles.spawnedEmitter = trail
    particles.spawnOccasion  = .onUpdate

    emitter.components.set(particles)
    rig.install(emitter, castsShadow: false)
    entities.append(emitter)

    return entities
}
