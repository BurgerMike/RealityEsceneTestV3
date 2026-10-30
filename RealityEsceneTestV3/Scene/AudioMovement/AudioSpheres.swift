// AudioSpheres.swift
// RealityEsceneTestV3
//
// Three looping spatial sources, one per world axis.
//
// RealityKit handles direction and distance from the source's transform to
// whatever entity is set as content.audioListener; HRTF comes from the system.
// reverbLevel feeds each source into the ReverbComponent on the scene root, so
// the sources sit in the same room rather than playing dry on top of it.

import RealityKit
import SwiftUI

struct AudioSource {
    let file: String        // .m4a in the bundle
    let color: NSColor
    let axis: String        // label shown in the HUD
}

@MainActor
func createAudioSpheres(in rig: SceneRig) -> [ModelEntity] {

    let sources: [AudioSource] = [
        AudioSource(file: "Guitarra", color: .systemRed,   axis: "X — Left / Right"),
        AudioSource(file: "Bajo",     color: .systemGreen, axis: "Y — Up / Down"),
        AudioSource(file: "Synth",    color: .systemBlue,  axis: "Z — Front / Back")
    ]

    let positions: [SIMD3<Float>] = [
        [ 3, 1.5, -3],
        [ 0, 3.0, -3],
        [-3, 1.5, -3]
    ]

    var entities: [ModelEntity] = []

    for (index, source) in sources.enumerated() {
        guard let resource = try? AudioFileResource.load(
            named: "\(source.file).m4a",
            configuration: .init(shouldLoop: true)
        ) else {
            print("❌ Audio file not found: \(source.file).m4a")
            continue
        }

        // Emissive so each source is visible as a light in the dark arena and
        // picked up by the bloom pass.
        var material = Mat.carPaint(source.color)
        material.emissiveColor     = .init(color: source.color)
        material.emissiveIntensity = 2.2

        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.35),
            materials: [material]
        )
        sphere.position = positions[index]

        var spatial = SpatialAudioComponent()
        spatial.gain = 0
        // rolloff factor 2 — audible falloff without going silent across the
        // width of the arena.
        spatial.distanceAttenuation = .rolloff(factor: 2)
        spatial.reverbLevel = -6
        sphere.components.set(spatial)

        // One shell per source. Two looked better but each is a large
        // translucent sphere drawn over the whole scene, and the overdraw of
        // the second one measured at eleven frames a second.
        for shell in 0..<1 {
            let pulse = ModelEntity(
                mesh: .generateSphere(radius: 0.38),
                materials: [Mat.pulseShell(source.color)]
            )
            pulse.components.set(AudioPulseComponent(
                period: 1.6,
                phase: Float(shell),
                maxScale: 3.0
            ))
            pulse.components.set(OpacityComponent(opacity: 0))
            sphere.addChild(pulse)
        }

        rig.install(sphere)
        sphere.playAudio(resource)
        entities.append(sphere)
    }

    return entities
}
