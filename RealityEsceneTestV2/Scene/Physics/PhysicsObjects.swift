// PhysicsObjects.swift
// RealityEsceneTestV2
//
// Six physics demos, each self-contained and each cleaned up before the next
// one loads. Every object goes into the world through rig.install, which
// parents it under the lit, simulated scene root and opts it into the shadow
// maps.
//
// New in this pass:
//   .forceField — ForceEffectComponent driving a vortex and turbulence field,
//                 so the solver is doing continuous work on every body rather
//                 than just resolving contacts
//   .instancing — MeshInstancesComponent, 25k animated cubes in six draw
//                 calls instead of 25k entities
// and the stress test now wakes sleeping bodies on contact instead of
// freezing them permanently.

import RealityKit
import SwiftUI

// MARK: - Demo Mode

enum DemoMode: CaseIterable {
    case balls
    case breakable
    case tower
    case joints
    case forceField
    case towerStress
    case instancing

    var label: String {
        switch self {
        case .balls:       return "⚽  Mass & Bounce"
        case .breakable:   return "💥  Breakable Glass"
        case .tower:       return "🏗  Tower Collapse"
        case .joints:      return "⛓  Chains & Wrecking Balls"
        case .forceField:  return "🌪  Force Fields"
        case .towerStress: return "⚡  Physics Stress"
        case .instancing:  return "🧊  GPU Instancing"
        }
    }

    var hint: String {
        switch self {
        case .balls:       return "clearcoat PBR — mass drives restitution"
        case .breakable:   return "impulse threshold spawns 14 rigid shards"
        case .tower:       return "3 stacks, 20 kg wrecking ball"
        case .joints:      return "articulated chains — shoot them and they swing"
        case .forceField:  return "ForceEffectComponent — vortex + turbulence"
        case .towerStress: return "512 rigid bodies, ECS sleep + wake on contact"
        case .instancing:  return "MeshInstancesComponent — 40 000 instances"
        }
    }

    // Which RealityKit feature the HUD should name while this mode runs.
    var feature: String {
        switch self {
        case .balls:       return "PhysicallyBasedMaterial · clearcoat"
        case .breakable:   return "CollisionEvents.impulse"
        case .tower:       return "PhysicsSimulationComponent · 8 position iters"
        case .joints:      return "PhysicsSphericalJoint · GeometricPin"
        case .forceField:  return "ForceEffectComponent"
        case .towerStress: return "SleepSystem · scene-wide collision filter"
        case .instancing:  return "MeshInstancesComponent · LowLevelInstanceData"
        }
    }
}

// MARK: - Mode 1: Mass & bounce

@MainActor
func setupBalls(
    in rig: SceneRig,
    content: any RealityViewContentProtocol,
    audioResource: AudioFileResource?
) -> [Entity] {

    let configs: [(color: NSColor, radius: Float, mass: Float, pos: SIMD3<Float>)] = [
        (.systemRed,    0.20, 0.5, [-2.5, 5, 0]),
        (.white,        0.30, 2.0, [   0, 6, 0]),
        (.systemBlue,   0.40, 8.0, [ 2.5, 7, 0])
    ]

    var entities: [Entity] = []

    for config in configs {
        let ball = ModelEntity(
            mesh: .generateSphere(radius: config.radius),
            materials: [Mat.carPaint(config.color)]
        )
        ball.position = config.pos

        ball.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: config.radius)]
        ))

        var physics = PhysicsBodyComponent(
            shapes: [.generateSphere(radius: config.radius)],
            mass: config.mass,
            mode: .dynamic
        )
        // Lighter ball bounces more — heavier ball thuds.
        physics.material = PhysicsMaterialResource.generate(
            staticFriction:  0.3,
            dynamicFriction: 0.2,
            restitution:     config.mass < 1.0 ? 0.85
                           : config.mass < 4.0 ? 0.50
                           :                     0.15
        )
        ball.components.set(physics)

        var spatial = SpatialAudioComponent()
        spatial.gain = -30
        spatial.distanceAttenuation = .rolloff(factor: 1.5)
        spatial.reverbLevel = -8
        ball.components.set(spatial)

        rig.install(ball)

        if let resource = audioResource {
            _ = content.subscribe(to: CollisionEvents.Began.self, on: ball) { event in
                Task { @MainActor in
                    // Volume scales with impulse — soft hit quiet, hard hit loud.
                    let impulse = event.impulse
                    let gain = Double(-20) + Double(26) * min(Double(impulse) / 8.0, 1.0)
                    ball.components[SpatialAudioComponent.self]?.gain = gain
                    ball.playAudio(resource)
                }
            }
        }

        entities.append(ball)
    }

    return entities
}

// MARK: - Mode 2: Breakable glass

@MainActor
func setupBreakable(
    in rig: SceneRig,
    content: any RealityViewContentProtocol,
    softResource: AudioFileResource?,
    breakResource: AudioFileResource?,
    onFragmentCreated: @escaping (Entity) -> Void
) -> [Entity] {

    var entities: [Entity] = []

    let glass = ModelEntity(
        mesh: .generateSphere(radius: 0.4),
        materials: [Mat.glass()]
    )
    glass.position = [0, 7, -1]

    glass.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.4)]))

    var physics = PhysicsBodyComponent(
        shapes: [.generateSphere(radius: 0.4)],
        mass: 1.5,
        mode: .dynamic
    )
    physics.material = PhysicsMaterialResource.generate(
        staticFriction:  0.1,
        dynamicFriction: 0.1,
        restitution:     0.3
    )
    glass.components.set(physics)

    var spatial = SpatialAudioComponent()
    spatial.gain = 0
    spatial.distanceAttenuation = .rolloff(factor: 2)
    spatial.reverbLevel = -4
    glass.components.set(spatial)

    rig.install(glass)
    entities.append(glass)

    var broken = false

    _ = content.subscribe(to: CollisionEvents.Began.self, on: glass) { event in
        Task { @MainActor in
            let impulse = event.impulse

            guard !broken else { return }

            guard impulse > 6.0 else {
                if let r = softResource { glass.playAudio(r) }
                return
            }

            broken = true
            let origin = glass.position

            // Audio and particles live on their own entity: playing them on
            // the glass would cut both off the moment it is removed.
            let burst = Entity()
            burst.position = origin
            var burstAudio = SpatialAudioComponent()
            burstAudio.gain = 0
            burst.components.set(burstAudio)

            // Short-lived shard spray — the visual punch the impulse deserves.
            var sparks = ParticleEmitterComponent()
            sparks.emitterShape     = .sphere
            sparks.emitterShapeSize = [0.25, 0.25, 0.25]
            sparks.birthDirection   = .world
            sparks.mainEmitter.birthRate = 2600
            sparks.mainEmitter.lifeSpan  = 0.55
            sparks.mainEmitter.size      = 0.025
            sparks.mainEmitter.acceleration = [0, -9, 0]
            sparks.mainEmitter.stretchFactor = 3
            sparks.mainEmitter.color = .evolving(
                start: .single(.init(red: 0.85, green: 0.97, blue: 1.0, alpha: 1.0)),
                end:   .single(.init(red: 0.35, green: 0.70, blue: 1.0, alpha: 0.0))
            )
            burst.components.set(sparks)

            rig.install(burst, castsShadow: false)
            onFragmentCreated(burst)
            if let r = breakResource { burst.playAudio(r) }

            // One shot: the emitter has no built-in duration, so it is shut
            // off again a few frames later.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(130))
                burst.components[ParticleEmitterComponent.self]?.isEmitting = false
            }

            for _ in 0..<14 {
                let size = Float.random(in: 0.10...0.26)
                let frag = ModelEntity(
                    mesh: .generateBox(size: size, cornerRadius: 0.01),
                    materials: [Mat.shard()]
                )
                frag.position = origin + SIMD3<Float>(
                    Float.random(in: -0.2...0.2),
                    Float.random(in:  0.0...0.3),
                    Float.random(in: -0.2...0.2)
                )

                frag.components.set(CollisionComponent(
                    shapes: [.generateBox(size: [size, size, size])]
                ))

                var fragPhysics = PhysicsBodyComponent(
                    shapes: [.generateBox(size: [size, size, size])],
                    mass: 0.3,
                    mode: .dynamic
                )
                fragPhysics.material = PhysicsMaterialResource.generate(
                    staticFriction:  0.8,
                    dynamicFriction: 0.6,
                    restitution:     0.05
                )
                frag.components.set(fragPhysics)

                // Shards settle and then stop costing the solver anything.
                frag.components.set(SleepComponent(velocityThreshold: 0.1, framesToSleep: 20))

                rig.install(frag)
                onFragmentCreated(frag)

                frag.applyLinearImpulse(
                    SIMD3<Float>(
                        Float.random(in: -2...2),
                        Float.random(in: 0.2...1.0),
                        Float.random(in: -2...2)
                    ),
                    relativeTo: nil
                )
            }

            glass.removeFromParent()
        }
    }

    return entities
}

// MARK: - Mode 3: Tower collapse

@MainActor
func setupTower(
    in rig: SceneRig,
    content: any RealityViewContentProtocol,
    audioResource: AudioFileResource?
) -> [Entity] {

    var entities: [Entity] = []

    let towerPositions: [(x: Float, z: Float)] = [
        (x:  0.0,  z: -1.0),
        (x: -0.25, z: -1.5),
        (x:  0.5,  z: -0.5)
    ]
    let boxSize: Float = 0.6
    let boxMesh = MeshResource.generateBox(size: boxSize, cornerRadius: 0.02)
    let boxShape = ShapeResource.generateBox(size: [boxSize, boxSize, boxSize])

    for (towerIndex, tower) in towerPositions.enumerated() {
        for row in 0..<6 {
            let hue = CGFloat(towerIndex) / 3.0 + CGFloat(row) / 18.0
            let box = ModelEntity(
                mesh: boxMesh,
                materials: [Mat.carPaint(.init(
                    hue: hue.truncatingRemainder(dividingBy: 1.0),
                    saturation: 0.72,
                    brightness: 0.88,
                    alpha: 1.0
                ))]
            )
            box.position = [
                tower.x,
                boxSize / 2 + Float(row) * (boxSize + 0.02),
                tower.z
            ]

            box.components.set(CollisionComponent(shapes: [boxShape]))

            var physics = PhysicsBodyComponent(shapes: [boxShape], mass: 1.0, mode: .dynamic)
            physics.material = PhysicsMaterialResource.generate(
                staticFriction:  0.8,
                dynamicFriction: 0.6,
                restitution:     0.1
            )
            box.components.set(physics)
            box.components.set(SleepComponent())

            var spatial = SpatialAudioComponent()
            spatial.gain = -40
            spatial.distanceAttenuation = .rolloff(factor: 2)
            spatial.reverbLevel = -6
            box.components.set(spatial)

            rig.install(box)
            entities.append(box)

            if let resource = audioResource {
                _ = content.subscribe(to: CollisionEvents.Began.self, on: box) { event in
                    Task { @MainActor in
                        let impulse = event.impulse
                        guard impulse > 0.5 else { return }
                        let gain = Double(-20) + Double(20) * min(Double(impulse) / 5.0, 1.0)
                        box.components[SpatialAudioComponent.self]?.gain = gain
                        box.playAudio(resource)
                    }
                }
            }
        }
    }

    // Wrecking ball — rolls straight through all three stacks.
    let ball = ModelEntity(
        mesh: .generateSphere(radius: 0.45),
        materials: [Mat.polishedMetal()]
    )
    ball.position = [0, 0.45, 6]
    ball.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.45)]))
    ball.components.set(PhysicsBodyComponent(
        shapes: [.generateSphere(radius: 0.45)],
        mass: 20.0,
        mode: .dynamic
    ))

    rig.install(ball)
    ball.applyLinearImpulse([0, 1, -150], relativeTo: nil)
    entities.append(ball)

    return entities
}

// MARK: - Mode 4: Force fields

// ForceEffectComponent applies continuous forces to every dynamic body inside
// its falloff volume, evaluated by the solver rather than by app code. Two
// effects are stacked: a vortex that spins bodies around the Y axis and
// turbulence that keeps the motion from settling into a clean orbit.
@MainActor
func setupForceField(
    in rig: SceneRig,
    content: any RealityViewContentProtocol
) -> (entities: [Entity], bodyCount: Int) {

    var entities: [Entity] = []

    // MARK: The field itself
    let field = Entity()
    field.name = "forceField"
    field.position = [0, 2.2, 0]

    let bounds = ForceEffectBounds.sphere(radius: 7.5)

    let vortex = ForceEffect(
        effect: VortexForceEffect(strength: 14, axis: [0, 1, 0]),
        spatialFalloff: SpatialForceFalloff(bounds: bounds, rate: 0.6)
    )

    let lift = ForceEffect(
        effect: ConstantRadialForceEffect(strength: -3.2),
        spatialFalloff: SpatialForceFalloff(bounds: bounds, rate: 1.0)
    )

    let turbulence = ForceEffect(
        effect: TurbulenceForceEffect(strength: 5.5, smoothness: 0.45, speed: 1.4),
        spatialFalloff: SpatialForceFalloff(bounds: bounds, rate: 0.4)
    )

    field.components.set(ForceEffectComponent(
        effects: [vortex, lift, turbulence],
        simulationState: .start
    ))
    rig.install(field, castsShadow: false)
    entities.append(field)

    // MARK: Visible core — tells the viewer where the field is
    let core = ModelEntity(
        mesh: .generateSphere(radius: 0.35),
        materials: [Mat.neon(.init(red: 0.4, green: 0.85, blue: 1.0, alpha: 1), intensity: 6)]
    )
    core.position = [0, 2.2, 0]
    rig.install(core, castsShadow: false)
    entities.append(core)

    var funnel = ParticleEmitterComponent()
    funnel.emitterShape     = .torus
    funnel.emitterShapeSize = [3.5, 0.2, 3.5]
    funnel.birthDirection   = .world
    funnel.mainEmitter.birthRate = 900
    funnel.mainEmitter.lifeSpan  = 2.2
    funnel.mainEmitter.size      = 0.05
    funnel.mainEmitter.acceleration = [0, 1.6, 0]
    funnel.mainEmitter.stretchFactor = 2
    funnel.mainEmitter.color = .evolving(
        start: .single(.init(red: 0.45, green: 0.9,  blue: 1.0, alpha: 0.8)),
        end:   .single(.init(red: 0.15, green: 0.35, blue: 0.9, alpha: 0.0))
    )
    let swirl = Entity()
    swirl.position = [0, 0.6, 0]
    swirl.components.set(funnel)
    rig.install(swirl, castsShadow: false)
    entities.append(swirl)

    // MARK: Bodies caught in the field
    let count = 150
    let mesh = MeshResource.generateBox(size: 0.22, cornerRadius: 0.03)
    let shape = ShapeResource.generateBox(size: [0.22, 0.22, 0.22])
    // Shared palette — same reason as the stress test: a material per body is
    // a pipeline switch per body.
    let palette = (0..<8).map { Mat.hueCube(CGFloat($0) / 8.0 * 0.8, emissive: 1.1) }
    var generator = SystemRandomNumberGenerator()

    for i in 0..<count {
        let angle  = Float.random(in: 0...(2 * .pi), using: &generator)
        let radius = Float.random(in: 1.5...6.5, using: &generator)

        let body = ModelEntity(mesh: mesh, materials: [palette[i % palette.count]])
        body.position = [
            cos(angle) * radius,
            Float.random(in: 0.4...5.0, using: &generator),
            sin(angle) * radius
        ]

        body.components.set(CollisionComponent(shapes: [shape]))
        var physics = PhysicsBodyComponent(shapes: [shape], mass: 0.35, mode: .dynamic)
        physics.material = PhysicsMaterialResource.generate(
            staticFriction: 0.35, dynamicFriction: 0.25, restitution: 0.35
        )
        // No SleepComponent here on purpose: the field never lets these rest,
        // so the solver load stays constant for the whole demo.
        body.components.set(physics)

        rig.install(body)
        entities.append(body)
    }

    return (entities, count)
}

// MARK: - Mode 5: Physics stress

// Shared meshes and shapes — one GPU upload and one collision shape reused by
// every cube. Generating 512 of each is what makes a stress test look like a
// RealityKit limit when it is really an allocation problem.
@MainActor
private enum StressAssets {
    static let mesh  = MeshResource.generateBox(size: 0.18)
    static let shape = ShapeResource.generateBox(size: [0.18, 0.18, 0.18])

    // One material per row, shared by the 64 cubes in it. Building a fresh
    // PhysicallyBasedMaterial per cube meant 512 distinct materials, so the
    // renderer could not batch anything and switched pipeline state for every
    // single box. Emissive is off here too: 512 glowing cubes all feed the
    // bloom pass for no visual gain.
    // One material per row, shared by the 64 cubes in it, and plain boxes
    // rather than rounded ones: generateBox(cornerRadius:) carries a far
    // heavier triangle count, and with every cube feeding the shadow cascades
    // that single parameter was costing more than everything else combined.
    static let rowMaterials: [PhysicallyBasedMaterial] = (0..<8).map {
        Mat.hueCube(CGFloat($0) / 8.0 * 0.85, emissive: 0)
    }
}

@MainActor
func setupTowerStress(
    in rig: SceneRig,
    content: any RealityViewContentProtocol,
    audioResource: AudioFileResource?,
    onCubeCountChanged: @escaping (Int) -> Void
) -> [Entity] {

    var entities: [Entity] = []

    let cubeSize: Float = 0.18
    let cols = 8, rows = 8, depth = 8      // 512 rigid bodies
    let spacing = cubeSize + 0.02
    let originX = -Float(cols) / 2 * spacing
    let originZ = -Float(depth) / 2 * spacing

    for row in 0..<rows {
        for col in 0..<cols {
            for d in 0..<depth {
                let cube = ModelEntity(
                    mesh: StressAssets.mesh,
                    materials: [StressAssets.rowMaterials[row % StressAssets.rowMaterials.count]]
                )
                cube.position = [
                    originX + Float(col) * spacing,
                    cubeSize / 2 + Float(row) * spacing,
                    originZ + Float(d) * spacing
                ]

                cube.components.set(CollisionComponent(shapes: [StressAssets.shape]))

                var physics = PhysicsBodyComponent(
                    shapes: [StressAssets.shape],
                    mass: 0.2,
                    mode: .dynamic
                )
                physics.material = PhysicsMaterialResource.generate(
                    staticFriction: 0.6, dynamicFriction: 0.4, restitution: 0.05
                )
                cube.components.set(physics)
                cube.components.set(SleepComponent())

                rig.install(cube)
                entities.append(cube)
            }
        }
    }

    onCubeCountChanged(rows * cols * depth)

    // Heavy ball fired across the block.
    let ball = ModelEntity(
        mesh: .generateSphere(radius: 0.30),
        materials: [Mat.polishedMetal()]
    )
    ball.position = [-8, 0.55, 0]
    ball.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.30)]))
    ball.components.set(PhysicsBodyComponent(
        shapes: [.generateSphere(radius: 0.30)],
        mass: 50.0,
        mode: .dynamic
    ))

    rig.install(ball)
    ball.applyLinearImpulse([800, 1, 0], relativeTo: nil)
    entities.append(ball)

    return entities
}

// MARK: - Mode 6: GPU instancing

@MainActor
func setupInstancing(in rig: SceneRig) -> (entities: [Entity], field: InstanceField) {
    let field = buildInstanceField()

    // The field is its own geometry, not physics — shadow casting 25k
    // instances into the cascades would be measuring the wrong thing.
    for entity in field.entities {
        rig.install(entity, castsShadow: false)
    }

    return (field.entities, field)
}

// MARK: - Projectile

// Fired from the camera with E. Every physics mode gets it, which is the
// difference between watching a scripted collapse once and being able to keep
// knocking the scene apart for as long as the recording runs.
@MainActor
private enum ProjectileAssets {
    static let mesh  = MeshResource.generateSphere(radius: 0.22)
    static let shape = ShapeResource.generateSphere(radius: 0.22)
    static let material = Mat.polishedMetal(.init(red: 1.0, green: 0.86, blue: 0.5, alpha: 1))
}

@MainActor
func fireProjectile(
    from position: SIMD3<Float>,
    yaw: Float,
    pitch: Float,
    in rig: SceneRig
) -> Entity {
    // Camera basis: the anchor yaws around Y, the camera pitches around X.
    let forward = SIMD3<Float>(
        -sin(yaw) * cos(pitch),
         sin(pitch),
        -cos(yaw) * cos(pitch)
    )

    let ball = ModelEntity(
        mesh: ProjectileAssets.mesh,
        materials: [ProjectileAssets.material]
    )
    ball.name = "projectile"
    ball.position = position + forward * 0.9

    ball.components.set(CollisionComponent(shapes: [ProjectileAssets.shape]))

    var body = PhysicsBodyComponent(
        shapes: [ProjectileAssets.shape],
        mass: 14,
        mode: .dynamic
    )
    body.material = PhysicsMaterialResource.generate(
        staticFriction: 0.4, dynamicFriction: 0.3, restitution: 0.35
    )
    ball.components.set(body)

    // Settles like everything else once it has stopped rolling.
    ball.components.set(SleepComponent(velocityThreshold: 0.12, framesToSleep: 30))

    rig.install(ball)
    ball.applyLinearImpulse(forward * 260, relativeTo: nil)
    return ball
}
