// AudioPulse.swift
// RealityEsceneTestV3
//
// Makes the spatial audio demo legible on video.
//
// The whole point of that scene is where a sound is coming from, and a
// recording loses it: viewers watching on laptop speakers hear mono and see
// three spheres sliding around. These pulses give each source a visible
// emission — an expanding translucent shell that fades as it grows — so the
// footage still reads as "this one is the sound on your left" even muted.
//
// Driven by a System rather than the frame loop, so the pulses keep their
// timing from RealityKit's own delta and the scene file stays about the scene.

import RealityKit

struct AudioPulseComponent: Component {
    // Seconds for one shell to go from the source to its full radius.
    var period: Float = 1.6
    // Staggered per shell so a source emits a steady train rather than one
    // shell at a time.
    var phase: Float = 0
    var maxScale: Float = 4.2
    var time: Float = 0
}

struct AudioPulseSystem: System {

    static let query = EntityQuery(where: .has(AudioPulseComponent.self))

    init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var pulse = entity.components[AudioPulseComponent.self] else { continue }

            pulse.time += Float(context.deltaTime)
            entity.components[AudioPulseComponent.self] = pulse

            // Normalised progress through this shell's life, wrapping.
            let t = ((pulse.time / pulse.period) + pulse.phase).truncatingRemainder(dividingBy: 1)

            // Grows fast then eases, the way a wavefront loses speed.
            let eased = 1 - (1 - t) * (1 - t)
            entity.scale = .init(repeating: 1 + eased * (pulse.maxScale - 1))

            // Fades out over the back half so shells do not pop.
            var opacity = entity.components[OpacityComponent.self] ?? OpacityComponent(opacity: 1)
            opacity.opacity = max(0, 0.42 * (1 - t) * (1 - t))
            entity.components.set(opacity)
        }
    }
}
