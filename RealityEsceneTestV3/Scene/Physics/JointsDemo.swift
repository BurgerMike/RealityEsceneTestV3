// JointsDemo.swift
// RealityEsceneTestV3
//
// Articulated physics — the one thing in RealityKit that reads as "game
// engine" the instant it moves.
//
// A joint connects two GeometricPins, each a named point on an entity's own
// frame. PhysicsSphericalJoint is a ball-and-socket: the pins stay coincident
// while the bodies rotate freely around them, which is exactly a chain link.
// Chaining links pin-to-pin and anchoring the first one to a static beam gives
// a rope the solver maintains for free.
//
// Order matters: both entities have to be in the scene before the joint is
// added to the simulation, so every link is installed first and pinned after.
//
// checksForInternalCollisions stays false. Letting neighbouring links collide
// with each other is what makes chains jitter and eventually explode; the
// joint constraint is already keeping them together.

import RealityKit
import SwiftUI

@MainActor
func setupJoints(
    in rig: SceneRig,
    content: any RealityViewContentProtocol
) -> (entities: [Entity], bodyCount: Int, jointCount: Int) {

    var entities: [Entity] = []
    var jointCount = 0

    let linkSize = SIMD3<Float>(0.14, 0.30, 0.14)
    let linkMesh  = MeshResource.generateBox(size: linkSize, cornerRadius: 0.03)
    let linkShape = ShapeResource.generateBox(size: linkSize)
    var linkMaterial = Mat.brushedMetal(.init(white: 0.88, alpha: 1))
    linkMaterial.metallic = .init(floatLiteral: 0.75)
    linkMaterial.roughness = .init(floatLiteral: 0.3)

    // MARK: Gantry — static, carries every chain
    let beamSize = SIMD3<Float>(9.0, 0.34, 0.34)
    let beam = ModelEntity(
        mesh: .generateBox(size: beamSize, cornerRadius: 0.05),
        materials: [Mat.brushedMetal(.init(white: 0.55, alpha: 1))]
    )
    beam.name = "gantry"
    beam.position = [0, 3.3, -1.5]
    beam.components.set(CollisionComponent(shapes: [.generateBox(size: beamSize)]))
    beam.components.set(PhysicsBodyComponent(
        shapes: [.generateBox(size: beamSize)],
        mass: 0,
        mode: .static
    ))
    rig.install(beam)
    entities.append(beam)

    // Legs, purely visual — they hold the beam up for the eye, not the solver.
    for side in [Float(-1), 1] {
        let legSize = SIMD3<Float>(0.3, 3.3, 0.3)
        let leg = ModelEntity(
            mesh: .generateBox(size: legSize, cornerRadius: 0.04),
            materials: [Mat.brushedMetal(.init(white: 0.45, alpha: 1))]
        )
        leg.position = [side * 4.4, 1.65, -1.5]
        rig.install(leg)
        entities.append(leg)
    }

    // MARK: Chains
    //
    // The two outer chains are light and end bare, so a projectile sends them
    // whipping. The two inner ones carry a wrecking ball each: heavy, slow,
    // and they knock the light ones around when they swing.
    let chains: [(x: Float, links: Int, ball: Float?)] = [
        (x: -3.2, links: 5, ball: nil),
        (x: -1.1, links: 4, ball: 26),
        (x:  1.1, links: 4, ball: 26),
        (x:  3.2, links: 5, ball: nil)
    ]

    for (chainIndex, chain) in chains.enumerated() {
        var previous = beam
        var previousAnchorY = -beamSize.y / 2       // bottom of the beam
        var previousIsBeam = true

        for linkIndex in 0..<chain.links {
            let link = ModelEntity(mesh: linkMesh, materials: [linkMaterial])

            // Hang each link directly under the one above it.
            let y = beam.position.y - beamSize.y / 2 - linkSize.y * (Float(linkIndex) + 0.5)
            link.position = [chain.x, y, beam.position.z]

            link.components.set(CollisionComponent(shapes: [linkShape]))
            var body = PhysicsBodyComponent(shapes: [linkShape], mass: 1.4, mode: .dynamic)
            body.material = PhysicsMaterialResource.generate(
                staticFriction: 0.5, dynamicFriction: 0.4, restitution: 0.05
            )
            link.components.set(body)

            // In the scene first — addToSimulation needs both bodies present.
            rig.install(link)
            entities.append(link)

            // Pin names are scoped to their own entity, but the beam anchors
            // four chains, so its pins need to stay distinct.
            let upperPinName = previousIsBeam ? "anchor\(chainIndex)" : "bottom"
            let upperPin = previous.pins.set(
                named: upperPinName,
                position: [previousIsBeam ? chain.x : 0, previousAnchorY, 0]
            )
            let lowerPin = link.pins.set(named: "top", position: [0, linkSize.y / 2, 0])

            let joint = PhysicsSphericalJoint(pin0: upperPin, pin1: lowerPin)
            if (try? joint.addToSimulation()) != nil { jointCount += 1 }

            previous = link
            previousAnchorY = -linkSize.y / 2
            previousIsBeam = false
        }

        // MARK: Wrecking ball on the end of the inner chains
        guard let mass = chain.ball else { continue }

        let radius: Float = 0.42
        let ball = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [Mat.polishedMetal(.init(white: 0.86, alpha: 1))]
        )
        let y = beam.position.y - beamSize.y / 2 - linkSize.y * Float(chain.links) - radius
        ball.position = [chain.x, y, beam.position.z]

        ball.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        var ballBody = PhysicsBodyComponent(
            shapes: [.generateSphere(radius: radius)],
            mass: mass,
            mode: .dynamic
        )
        ballBody.material = PhysicsMaterialResource.generate(
            staticFriction: 0.6, dynamicFriction: 0.5, restitution: 0.15
        )
        ball.components.set(ballBody)

        rig.install(ball)
        entities.append(ball)

        let chainPin = previous.pins.set(named: "bottom", position: [0, -linkSize.y / 2, 0])
        let ballPin  = ball.pins.set(named: "top", position: [0, radius, 0])
        let joint = PhysicsSphericalJoint(pin0: chainPin, pin1: ballPin)
        if (try? joint.addToSimulation()) != nil { jointCount += 1 }
    }

    // MARK: Crates underneath, for the balls to scatter
    let crateSize = SIMD3<Float>(0.5, 0.5, 0.5)
    let crateMesh  = MeshResource.generateBox(size: crateSize, cornerRadius: 0.03)
    let crateShape = ShapeResource.generateBox(size: crateSize)
    let cratePalette = (0..<4).map { Mat.carPaint(.init(
        hue: CGFloat($0) / 4.0 * 0.5 + 0.05, saturation: 0.7, brightness: 0.9, alpha: 1
    )) }

    var crateCount = 0
    for row in 0..<4 {
        for column in 0..<8 {
            let crate = ModelEntity(
                mesh: crateMesh,
                materials: [cratePalette[(row + column) % cratePalette.count]]
            )
            crate.position = [
                -1.75 + Float(column) * 0.52,
                crateSize.y / 2 + Float(row) * 0.52,
                -4.2
            ]
            crate.components.set(CollisionComponent(shapes: [crateShape]))
            var body = PhysicsBodyComponent(shapes: [crateShape], mass: 1.0, mode: .dynamic)
            body.material = PhysicsMaterialResource.generate(
                staticFriction: 0.7, dynamicFriction: 0.55, restitution: 0.05
            )
            crate.components.set(body)
            crate.components.set(SleepComponent())

            rig.install(crate)
            entities.append(crate)
            crateCount += 1
        }
    }

    // Report only what the solver is integrating: the beam and its legs are
    // static scenery and cost nothing.
    let dynamicBodies = chains.reduce(crateCount) {
        $0 + $1.links + ($1.ball == nil ? 0 : 1)
    }

    return (entities, dynamicBodies, jointCount)
}
