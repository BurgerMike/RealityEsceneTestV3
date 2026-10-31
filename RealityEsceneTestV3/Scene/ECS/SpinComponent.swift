// SpinComponent.swift
// RealityEsceneTestV3
//
// Continuous rotation and bobbing, driven by a System rather than by each
// scene's frame callback.
//
// Several demos want objects turning slowly on the spot: the shapes inside the
// portal worlds, the sample spheres in the material lab. Doing that from a
// scene's onFrame means every scene grows its own animation loop; doing it
// here means an entity opts in by having a component, and the scenes stay
// about what they are showing.

import RealityKit

struct SpinComponent: Component {
    // Radians per second about each axis.
    var axis: SIMD3<Float> = [0, 1, 0]
    var speed: Float = 0.6

    // Vertical bob, layered on top of the entity's starting height.
    var bobAmplitude: Float = 0
    var bobSpeed: Float = 1.0

    // Captured the first time the system sees the entity, so the bob is
    // relative to wherever it was placed.
    var baseY: Float? = nil
    var phase: Float = 0
    var time: Float = 0
}

struct SpinSystem: System {

    static let query = EntityQuery(where: .has(SpinComponent.self))

    init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        let delta = Float(context.deltaTime)

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var spin = entity.components[SpinComponent.self] else { continue }

            if spin.baseY == nil { spin.baseY = entity.position.y }
            spin.time += delta

            entity.orientation *= simd_quatf(
                angle: spin.speed * delta,
                axis: normalize(spin.axis)
            )

            if spin.bobAmplitude > 0, let baseY = spin.baseY {
                entity.position.y = baseY
                    + sin(spin.time * spin.bobSpeed + spin.phase) * spin.bobAmplitude
            }

            entity.components[SpinComponent.self] = spin
        }
    }
}
