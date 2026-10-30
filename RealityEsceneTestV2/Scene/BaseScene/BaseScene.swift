// BaseScene.swift
// RealityEsceneTestV2
//
// The lighting and staging rig every scene is built on.
//
// What RealityKit does here:
//   environment skybox + EnvironmentLightingConfigurationComponent
//       → image based lighting: ambient and specular response for every
//         PhysicallyBasedMaterial in the scene
//   DirectionalLight + DirectionalLightComponent.Shadow
//       → the single shadow-casting key light, cascaded shadow maps
//   DynamicLightShadowComponent
//       → per-entity opt in to casting into those shadow maps
//   PhysicsSimulationComponent
//       → explicit solver budget instead of the engine default
//   ReverbComponent
//       → room acoustics applied to every SpatialAudioComponent in the scene
//
// Entities are parented to `rig.root`, never to content directly: the root
// owns the lighting configuration and physics simulation scope, and both
// inherit down the hierarchy.

import SwiftUI
import RealityKit

// Travel direction of the key light. Kept in one place so the baked sun in
// EnvironmentFactory and the real shadow-casting light point the same way.
let sunTravelDirection = normalize(SIMD3<Float>(-0.60, -0.42, -0.68))

// MARK: - Scene rig

@MainActor
struct SceneRig {
    let root:   Entity
    let postFX: Entity
    let sun:    DirectionalLight
    let floor:  ModelEntity
    let skyline: ArenaSkyline

    // Single entry point for putting an object into the world. Parents it to
    // the lit, simulated root and opts it into the shadow maps.
    func install(_ entity: Entity, castsShadow: Bool = true) {
        if castsShadow {
            entity.components.set(DynamicLightShadowComponent(castsShadow: true))
        }
        root.addChild(entity)
    }

    func install(_ entities: [Entity], castsShadow: Bool = true) {
        entities.forEach { install($0, castsShadow: castsShadow) }
    }
}

// MARK: - Build

@MainActor
func buildBaseScene(
    in content: any RealityViewContentProtocol,
    cameraAnchor: AnchorEntity,
    cameraEntity: PerspectiveCamera,
    controller: CameraController,
    settings: RenderSettings
) -> SceneRig {

    // MARK: Root — lighting scope + physics scope for everything below
    let root = Entity()
    root.name = "sceneRoot"

    // How much the skybox contributes as ambient light. 1.0 keeps the IBL at
    // full strength so metals pick up the sky instead of looking painted.
    root.components.set(EnvironmentLightingConfigurationComponent(
        environmentLightingWeight: 1.0
    ))

    // Explicit solver budget. Position iterations are what stop a tall stack
    // from sinking into itself, but they are also the per-body CPU cost, and
    // with 512 bodies this is what the frame is spending its time on. Six is
    // measurably stable for these stacks and noticeably cheaper than eight.
    var simulation = PhysicsSimulationComponent()
    simulation.gravity = [0, -9.81, 0]
    simulation.solverIterations = .init(positionIterations: 6, velocityIterations: 1)
    root.components.set(simulation)

    // Room acoustics for every spatial audio source in the scene.
    root.components.set(ReverbComponent(reverb: .preset(.largeRoom)))

    content.add(root)

    // MARK: Post-process — bloom and the filmic curve
    let postFX = Entity()
    postFX.name = "postFX"
    settings.apply(to: postFX)
    root.addChild(postFX)

    // MARK: Key light — the only shadow caster
    let sun = DirectionalLight()
    sun.name = "sun"
    sun.light.color     = .init(red: 1.0, green: 0.93, blue: 0.82, alpha: 1.0)
    sun.light.intensity = 3400
    sun.orientation = simd_quatf(from: [0, 0, -1], to: sunTravelDirection)

    // Cascaded shadow maps: crisp contact shadows near the camera, cheaper
    // projections further out. maximumDistance is the single biggest shadow
    // cost knob — every metre of it is more geometry re-rendered per cascade.
    // The preset owns the distance; the skyline outside it casts nothing.
    var shadow = DirectionalLightComponent.Shadow(
        maximumDistance: settings.shadowDistance,
        depthBias: 1.4
    )
    shadow.cascades = .automatic
    sun.shadow = shadow
    root.addChild(sun)

    // MARK: Fill light — cool bounce from the opposite side, no shadows.
    // Stops the unlit side of every object from going to pure black.
    let fill = DirectionalLight()
    fill.name = "fill"
    fill.light.color     = .init(red: 0.52, green: 0.68, blue: 1.0, alpha: 1.0)
    fill.light.intensity = 900
    fill.orientation = simd_quatf(from: [0, 0, -1],
                                  to: normalize(SIMD3<Float>(0.7, -0.35, 0.6)))
    fill.shadow = nil
    root.addChild(fill)

    // MARK: Floor
    var floorMaterial = PhysicallyBasedMaterial()
    if let texture = EnvironmentFactory.floorTexture() {
        floorMaterial.baseColor = .init(tint: .white, texture: texture)
    } else {
        floorMaterial.baseColor = .init(tint: .init(white: 0.06, alpha: 1))
    }
    // Rough and non-metallic on purpose. A glossy floor mirrors the sun into
    // one blown-out glitter path straight down the middle of frame, which is
    // the first thing that makes a render look amateur.
    floorMaterial.roughness = .init(floatLiteral: 0.82)
    floorMaterial.metallic  = .init(floatLiteral: 0.0)
    floorMaterial.specular  = .init(floatLiteral: 0.25)

    let floor = ModelEntity(
        mesh: .generatePlane(width: 24, depth: 24),
        materials: [floorMaterial]
    )
    floor.name = "floor"
    floor.components.set(CollisionComponent(
        shapes: [.generateBox(width: 24, height: 0.02, depth: 24)]
    ))
    floor.components.set(PhysicsBodyComponent(
        shapes: [.generateBox(width: 24, height: 0.02, depth: 24)],
        mass: 0,
        mode: .static
    ))
    root.addChild(floor)

    // MARK: Arena walls — keep physics bodies on stage.
    // Thin, dark, and emissive along the top edge so they read as a boundary
    // rather than a box the camera is trapped in.
    buildArena(in: root)

    // MARK: Skyline — scenery outside the walls, driven by RealityKit's own
    // LevelOfDetailComponent. Visible in every scene, so LOD is always live.
    let skyline = buildSkyline(in: root)

    // MARK: Camera
    cameraEntity.camera.fieldOfViewInDegrees = 72
    cameraEntity.name = "playerCamera"
    cameraEntity.orientation = simd_quatf(angle: 0, axis: [1, 0, 0])
    cameraAnchor.name     = "cameraAnchor"
    cameraAnchor.position = controller.position
    cameraAnchor.addChild(cameraEntity)
    content.add(cameraAnchor)

    return SceneRig(root: root, postFX: postFX, sun: sun, floor: floor, skyline: skyline)
}

// MARK: - Arena

@MainActor
private func buildArena(in root: Entity) {
    let half: Float   = 11.0
    let height: Float = 3.2
    let thickness: Float = 0.3

    var wallMaterial = PhysicallyBasedMaterial()
    // Dark, but not black: the walls need enough albedo for the skybox to
    // shape them, or the arena reads as a void band across the middle.
    wallMaterial.baseColor = .init(tint: .init(white: 0.11, alpha: 1))
    wallMaterial.roughness = .init(floatLiteral: 0.55)
    wallMaterial.metallic  = .init(floatLiteral: 0.35)

    // Emissive trim — picked up by the bloom pass, which is what makes the
    // arena edge glow instead of just being a dark slab.
    var trimMaterial = PhysicallyBasedMaterial()
    trimMaterial.baseColor = .init(tint: .init(red: 0.1, green: 0.5, blue: 0.9, alpha: 1))
    trimMaterial.emissiveColor = .init(color: .init(red: 0.25, green: 0.75, blue: 1.0, alpha: 1))
    trimMaterial.emissiveIntensity = 3.2
    trimMaterial.roughness = .init(floatLiteral: 0.2)

    let placements: [(position: SIMD3<Float>, size: SIMD3<Float>)] = [
        ([0, height / 2,  half], [half * 2, height, thickness]),
        ([0, height / 2, -half], [half * 2, height, thickness]),
        ([ half, height / 2, 0], [thickness, height, half * 2]),
        ([-half, height / 2, 0], [thickness, height, half * 2])
    ]

    for placement in placements {
        let wall = ModelEntity(
            mesh: .generateBox(size: placement.size),
            materials: [wallMaterial]
        )
        wall.position = placement.position
        wall.components.set(CollisionComponent(shapes: [.generateBox(size: placement.size)]))
        wall.components.set(PhysicsBodyComponent(
            shapes: [.generateBox(size: placement.size)],
            mass: 0,
            mode: .static
        ))
        root.addChild(wall)

        let trim = ModelEntity(
            mesh: .generateBox(size: [placement.size.x * 1.001, 0.06, placement.size.z * 1.001]),
            materials: [trimMaterial]
        )
        trim.position = [placement.position.x, height, placement.position.z]
        root.addChild(trim)
    }
}
