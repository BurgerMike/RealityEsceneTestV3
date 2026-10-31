// PortalDemo.swift
// RealityEsceneTestV3
//
// Portals — windows onto worlds that are not in the scene you are standing in.
//
// An entity carrying WorldComponent, and everything parented under it, is
// removed from the default world: it renders nowhere except through a
// PortalComponent that targets it. Each world here gets its own floor, its own
// lights and its own palette, so the three windows are genuinely three places
// rather than three views of the same room.
//
// PortalComponent.makePortal builds both halves and wires them together. Both
// entities have to be added to the scene — the portal surface where you want
// the window, the world wherever you like, since it is only ever seen through
// the portal.

import RealityKit
import SwiftUI

@MainActor
struct PortalShowcase {
    let entities: [Entity]
    let portalCount: Int
}

@MainActor
func setupPortals(in rig: SceneRig) -> PortalShowcase {

    var entities: [Entity] = []

    // Each world gets a hue and a mood. The frame around the window is built
    // from the same hue so the two read as a pair.
    let worlds: [(x: Float, hue: CGFloat, name: String)] = [
        (x: -4.6, hue: 0.55, name: "cyan"),
        (x:  0.0, hue: 0.08, name: "amber"),
        (x:  4.6, hue: 0.80, name: "magenta")
    ]

    for (index, world) in worlds.enumerated() {
        let portal = PortalComponent.makePortal(
            surfaceStyle: .init(width: 3.4, height: 2.6),
            boundaryStyle: .infinitePlane(),
            boundaryMode: .none
        )

        // MARK: The window
        portal.portalEntity.position = [world.x, 1.8, -5.0]
        rig.install(portal.portalEntity, castsShadow: false)
        entities.append(portal.portalEntity)

        // MARK: The world behind it
        //
        // Co-located with its own window. The portal shows the target world
        // from the camera's position relative to the portal surface, so a
        // world parked somewhere else shows you the empty space around it —
        // which is exactly what three black rectangles looked like.
        //
        // The three worlds sitting in the same place is fine: WorldComponent
        // isolates each one, so they cannot see each other.
        portal.worldEntity.position = portal.portalEntity.position
        rig.install(portal.worldEntity, castsShadow: false)
        entities.append(portal.worldEntity)

        buildPortalWorld(portal.worldEntity, hue: world.hue, seed: index)

        // MARK: Frame
        //
        // A glowing border, in the default world, sitting just around the
        // portal surface. Without it the window has no edge and reads as a
        // hole in the render rather than a thing in the room.
        let frameColor = NSColor(hue: world.hue, saturation: 0.8, brightness: 1.0, alpha: 1)
        let frameMaterial = Mat.neon(frameColor, intensity: 5.0)

        let bars: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0,  1.38, 0], [3.6, 0.1, 0.1]),
            ([0, -1.38, 0], [3.6, 0.1, 0.1]),
            ([-1.78, 0, 0], [0.1, 2.86, 0.1]),
            ([ 1.78, 0, 0], [0.1, 2.86, 0.1])
        ]
        for (offset, size) in bars {
            let bar = ModelEntity(mesh: .generateBox(size: size), materials: [frameMaterial])
            bar.position = [world.x + offset.x, 1.8 + offset.y, -5.0 + offset.z]
            rig.install(bar, castsShadow: false)
            entities.append(bar)
        }
    }

    return PortalShowcase(entities: entities, portalCount: worlds.count)
}

// MARK: - A world behind a portal

// Lights live inside the world. It is cut off from the default world's
// lighting, so without them the contents render black.
@MainActor
private func buildPortalWorld(_ world: Entity, hue: CGFloat, seed: Int) {

    let tint = NSColor(hue: hue, saturation: 0.75, brightness: 1.0, alpha: 1)

    // MARK: Key light
    let key = DirectionalLight()
    key.light.color = tint
    key.light.intensity = 4200
    key.orientation = simd_quatf(from: [0, 0, -1], to: normalize([-0.4, -0.7, -0.5]))
    world.addChild(key)

    // MARK: Fill, from below and opposite — gives the shapes a rim
    let fill = PointLight()
    fill.light.color = .white
    fill.light.intensity = 6000
    fill.light.attenuationRadius = 18
    fill.position = [0, 0.6, 2]
    world.addChild(fill)

    // MARK: Floor, receding into the dark
    var floorMaterial = PhysicallyBasedMaterial()
    floorMaterial.baseColor = .init(tint: .init(white: 0.04, alpha: 1))
    floorMaterial.roughness = .init(floatLiteral: 0.35)
    floorMaterial.metallic  = .init(floatLiteral: 0.85)

    let floor = ModelEntity(
        mesh: .generatePlane(width: 40, depth: 40),
        materials: [floorMaterial]
    )
    floor.position = [0, -1.6, 0]
    world.addChild(floor)

    // MARK: Floating shapes
    //
    // Each world uses a different primitive so the three are distinguishable
    // at a glance, not just differently coloured.
    var generator = SystemRandomNumberGenerator()
    let mesh: MeshResource = switch seed % 3 {
    case 0:  .generateSphere(radius: 0.42)
    case 1:  .generateBox(size: 0.68, cornerRadius: 0.06)
    default: .generateCone(height: 0.9, radius: 0.45)
    }

    var shapeMaterial = Mat.polishedMetal(tint)
    shapeMaterial.emissiveColor = .init(color: tint)
    shapeMaterial.emissiveIntensity = 0.8

    for i in 0..<14 {
        let shape = ModelEntity(mesh: mesh, materials: [shapeMaterial])
        shape.position = [
            Float.random(in: -5...5, using: &generator),
            Float.random(in: -1.0...3.0, using: &generator),
            Float.random(in: -9 ... -1, using: &generator)
        ]
        shape.components.set(SpinComponent(
            axis: [
                Float.random(in: -1...1, using: &generator),
                1,
                Float.random(in: -1...1, using: &generator)
            ],
            speed: Float.random(in: 0.4...1.3, using: &generator),
            bobAmplitude: Float.random(in: 0.1...0.4, using: &generator),
            bobSpeed: Float.random(in: 0.5...1.2, using: &generator),
            phase: Float(i)
        ))
        world.addChild(shape)
    }

    // MARK: A glowing core, far back, to give the world depth
    let core = ModelEntity(
        mesh: .generateSphere(radius: 1.1),
        materials: [Mat.neon(tint, intensity: 8)]
    )
    core.position = [0, 1.2, -14]
    world.addChild(core)
}
