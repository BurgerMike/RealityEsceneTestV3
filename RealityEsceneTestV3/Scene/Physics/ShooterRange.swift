// ShooterRange.swift
// RealityEsceneTestV3
//
// A shooting range, built as a benchmark load rather than as a game.
//
// Every other physics demo here measures a single event: drop the bodies,
// watch them settle, read the settling. A game is not shaped like that. It is
// input, spawning, physics, collisions, audio and rendering competing for the
// same frame, continuously, for as long as somebody is playing. Nothing in
// this suite measured that mixture, and it is exactly the gap behind "sure,
// it moves 40 000 cubes, but a game is different". They are right that it is
// different. This is the row that answers them.
//
// The constraint that shapes the whole file: it has to produce that load with
// nobody at the keyboard. A --benchmark run has no player, so a range that
// only does something when you shoot it would measure an empty arena and
// report a fine frame rate that means nothing. Clays launch themselves,
// targets rise and drop on their own, and bodies are retired on a cap rather
// than when they happen to settle. The score is the only part that needs a
// human, and the score is the part that does not matter.

import RealityKit
import AppKit

// Marks a target so one scene-wide collision subscription can find them all.
// Eighteen per-entity subscriptions would work and would also be eighteen
// closures the engine walks on every contact in the scene; the filtered
// scene-wide form is what the stress test already uses for the same reason.
struct TargetComponent: Component {
    var points: Int = 10

    // Where it sits when standing. A knocked-down target is restored to this
    // rather than to wherever the physics left it.
    var restPosition: SIMD3<Float> = .zero

    // Offsets the bob so the row does not move as one block.
    var phase: Float = 0

    var isDown = false
    var respawnIn: Float = 0
}

@MainActor
final class ShooterRange {

    // Tuned so the range is never empty and never unbounded. Both matter for
    // a measurement: an empty range measures nothing, and a range that keeps
    // every clay it ever threw measures a slow leak instead of a frame.
    private let clayInterval: Float = 0.35
    private let maxClays = 14

    // The range the scene-wide collision subscription talks to. That
    // subscription is installed once when the RealityView is made, long
    // before any mode has loaded, so it cannot capture the range directly.
    // Weak, because the scene owns the range and this must not keep a torn
    // down one alive.
    @MainActor static weak var active: ShooterRange?

    private(set) var score = 0
    private(set) var hits = 0
    private(set) var shots = 0

    private var targets: [ModelEntity] = []
    private var clays: [ModelEntity] = []
    private var clock: Float = 0
    private var nextClay: Float = 0
    private var launchFromLeft = true

    private let rig: SceneRig

    // Built once and handed to every body that needs them.
    //
    // The first version called Mat.carPaint, Mat.brushedMetal and
    // generateBox inside the per-target builder, which produced eighteen
    // distinct box meshes, eighteen cylinder meshes, thirty-six collision
    // shapes and thirty-six materials for what is really three. RealityKit
    // batches by mesh and material identity, so every one of those was its
    // own draw call: the range rendered at 30 fps with the GPU at 93%, next
    // to 113 for a scene of three spheres.
    private let clayMaterial: PhysicallyBasedMaterial
    private let clayMesh: MeshResource
    private let clayShape: ShapeResource
    private let targetMesh: MeshResource
    private let targetShape: ShapeResource
    private let targetMaterials: [NSColor: PhysicallyBasedMaterial]
    private let postMesh: MeshResource
    private let postMaterial: PhysicallyBasedMaterial

    var entities: [Entity] { targets + clays }

    // How many bodies this load is actually simulating, for the HUD. Targets
    // standing still are static and cost the solver nothing; the honest
    // number is the ones in motion.
    var activeBodies: Int { clays.count + targets.filter(\.isTargetDown).count }

    // One size for every target, so one mesh and one shape serve all of them.
    private static let targetSize: SIMD3<Float> = [0.9, 0.9, 0.14]

    init(rig: SceneRig) {
        self.rig = rig
        clayMesh = .generateSphere(radius: 0.22)
        clayShape = .generateSphere(radius: 0.22)
        clayMaterial = Mat.neon(.systemOrange, intensity: 2.2)

        targetMesh = .generateBox(size: Self.targetSize)
        targetShape = .generateBox(size: Self.targetSize)
        targetMaterials = Dictionary(
            uniqueKeysWithValues: Self.rowTints.map { ($0, Mat.carPaint($0)) }
        )

        postMesh = .generateCylinder(height: 1.4, radius: 0.06)
        postMaterial = Mat.brushedMetal()
    }

    private static let rowTints: [NSColor] = [.systemRed, .systemYellow, .systemGreen]

    // MARK: Build

    func build() {
        Self.active = self

        let rows: [(z: Float, count: Int, tint: NSColor)] = [
            (-9.0,  6, Self.rowTints[0]),
            (-13.5, 6, Self.rowTints[1]),
            (-18.0, 6, Self.rowTints[2])
        ]

        for (rowIndex, row) in rows.enumerated() {
            let span: Float = 13
            let step = span / Float(row.count - 1)

            for i in 0..<row.count {
                let x = -span / 2 + step * Float(i)
                // Farther rows are worth more, which is the only game design
                // in this file and exists so the HUD number moves.
                let target = makeTarget(
                    at: [x, 1.4, row.z],
                    tint: row.tint,
                    points: (rowIndex + 1) * 10,
                    phase: Float(i) * 0.9 + Float(rowIndex) * 1.7
                )
                targets.append(target)
            }
        }
    }

    private func makeTarget(
        at position: SIMD3<Float>,
        tint: NSColor,
        points: Int,
        phase: Float
    ) -> ModelEntity {
        let target = ModelEntity(
            mesh: targetMesh,
            materials: [targetMaterials[tint] ?? Mat.carPaint(tint)]
        )
        target.name = "target"
        target.position = position

        target.components.set(CollisionComponent(shapes: [targetShape]))

        // Static while standing: a target that is not moving should cost the
        // solver nothing, which is the same bargain SleepSystem strikes for
        // the 512-body test.
        var body = PhysicsBodyComponent(shapes: [targetShape], mass: 3, mode: .static)
        body.material = PhysicsMaterialResource.generate(
            staticFriction: 0.5, dynamicFriction: 0.4, restitution: 0.1
        )
        target.components.set(body)

        var marker = TargetComponent()
        marker.points = points
        marker.restPosition = position
        marker.phase = phase
        target.components.set(marker)

        // The post. No collider — it is scenery, and giving it one would add
        // eighteen static shapes the broadphase has to carry for nothing.
        let post = ModelEntity(mesh: postMesh, materials: [postMaterial])
        post.position = [position.x, position.y - 1.15, position.z]
        // No shadow either. Eighteen thin cylinders, each drawn again per
        // shadow cascade, for something the eye reads as a dark line.
        rig.install(post, castsShadow: false)
        targets.append(post)

        rig.install(target)
        return target
    }

    // MARK: Per frame

    func tick(deltaTime: Float) {
        clock += deltaTime

        launchClaysIfDue()
        updateTargets(deltaTime: deltaTime)
        retireFallenClays()
    }

    private func launchClaysIfDue() {
        guard clock >= nextClay else { return }
        nextClay = clock + clayInterval

        let x: Float = launchFromLeft ? -9 : 9
        launchFromLeft.toggle()

        let clay = ModelEntity(mesh: clayMesh, materials: [clayMaterial])
        clay.name = "clay"
        clay.position = [x, 2.2, Float.random(in: -17 ... -8)]
        clay.components.set(CollisionComponent(shapes: [clayShape]))

        var body = PhysicsBodyComponent(shapes: [clayShape], mass: 2, mode: .dynamic)
        body.material = PhysicsMaterialResource.generate(
            staticFriction: 0.3, dynamicFriction: 0.25, restitution: 0.55
        )
        clay.components.set(body)
        clay.components.set(SleepComponent(velocityThreshold: 0.15, framesToSleep: 24))

        rig.install(clay)
        clay.applyLinearImpulse([launchFromLeft ? -16 : 16, 15, 0], relativeTo: nil)
        clays.append(clay)

        while clays.count > maxClays {
            clays.removeFirst().removeFromParent()
        }
    }

    private func updateTargets(deltaTime: Float) {
        for target in targets where target.name == "target" {
            guard var marker = target.components[TargetComponent.self] else { continue }

            if marker.isDown {
                marker.respawnIn -= deltaTime
                if marker.respawnIn <= 0 {
                    stand(target, marker: &marker)
                }
                target.components.set(marker)
                continue
            }

            // Standing targets bob. It is movement the renderer has to carry
            // every frame, which is the point: a static scene measured as a
            // game would flatter the result.
            let bob = sin(clock * 1.3 + marker.phase) * 0.35
            target.position = marker.restPosition + [0, bob, 0]
        }
    }

    private func stand(_ target: ModelEntity, marker: inout TargetComponent) {
        marker.isDown = false
        target.position = marker.restPosition
        target.orientation = .init(angle: 0, axis: [0, 1, 0])

        if var body = target.components[PhysicsBodyComponent.self] {
            body.mode = .static
            target.components.set(body)
        }
    }

    // A clay that has stopped and settled is no longer load, it is clutter.
    private func retireFallenClays() {
        clays.removeAll { clay in
            guard clay.position.y < -3 else { return false }
            clay.removeFromParent()
            return true
        }
    }

    // MARK: Scoring

    // Called from the scene-wide collision subscription. Returns true when the
    // hit scored, so the caller can play a sound without this file owning one.
    @discardableResult
    func registerHit(on target: Entity, by other: Entity) -> Bool {
        guard let target = target as? ModelEntity,
              other.name == "projectile",
              var marker = target.components[TargetComponent.self],
              !marker.isDown else { return false }

        marker.isDown = true
        marker.respawnIn = 2.5
        target.components.set(marker)

        // Goes dynamic only now, so it can be knocked over, and goes back to
        // static when it stands up again.
        if var body = target.components[PhysicsBodyComponent.self] {
            body.mode = .dynamic
            target.components.set(body)
        }
        target.applyLinearImpulse([0, 2, -9], relativeTo: nil)

        score += marker.points
        hits += 1
        return true
    }

    func countShot() { shots += 1 }

    // Clays are spawned after the scene recorded what to clean up, so the
    // range has to retire its own entities rather than leaving it to the
    // caller's list.
    func teardown() {
        if Self.active === self { Self.active = nil }
        for entity in targets + clays { entity.removeFromParent() }
        targets.removeAll()
        clays.removeAll()
    }

    var accuracy: Int {
        guard shots > 0 else { return 0 }
        return Int((Double(hits) / Double(shots) * 100).rounded())
    }
}

private extension Entity {
    var isTargetDown: Bool {
        components[TargetComponent.self]?.isDown ?? false
    }
}

// MARK: - Setup

@MainActor
func setupShooter(in rig: SceneRig) -> ShooterRange {
    let range = ShooterRange(rig: rig)
    range.build()
    return range
}
