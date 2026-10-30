// SleepSystem.swift
// RealityEsceneTestV2
//
// Parks settled physics bodies so the solver stops paying for them, and puts
// them back when something disturbs them.
//
// V1 of this system set mode = .static the first frame a body dropped below
// the speed threshold and never looked at it again: bodies froze mid-bounce,
// and a cube that had gone to sleep ignored the next impact for the rest of
// the demo. This version requires sustained quiet before sleeping, and wakes
// a body again on contact — which is what makes the stress test both cheap
// and still interactive.

import RealityKit

struct SleepSystem: System {

    static let query = EntityQuery(
        where: .has(SleepComponent.self) && .has(PhysicsBodyComponent.self)
    )

    // Read by the HUD — how much of the scene the solver is skipping.
    @MainActor static var sleepingCount = 0
    @MainActor static var trackedCount  = 0

    init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        var sleeping = 0
        var tracked  = 0

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var sleep = entity.components[SleepComponent.self],
                  var body  = entity.components[PhysicsBodyComponent.self] else { continue }

            tracked += 1

            if sleep.isAsleep {
                // Nothing to update: writing the component back unchanged
                // still costs a component-store round trip, and with hundreds
                // of parked bodies that is the system's whole cost.
                sleeping += 1
                continue
            }

            // Speed is the magnitude of the linear velocity. A body with no
            // motion component is not being simulated at all, so skip it.
            guard let motion = entity.components[PhysicsMotionComponent.self] else { continue }
            let v = motion.linearVelocity
            let speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

            let wasQuiet = sleep.quietFrames
            if speed < sleep.velocityThreshold {
                sleep.quietFrames += 1
            } else {
                sleep.quietFrames = 0
            }

            if sleep.quietFrames >= sleep.framesToSleep {
                sleep.storedMass = body.massProperties.mass
                sleep.isAsleep   = true
                sleep.quietFrames = 0
                body.mode = .static
                entity.components[PhysicsBodyComponent.self] = body
                sleeping += 1
            }

            // Only write back when the counter actually moved.
            if sleep.quietFrames != wasQuiet {
                entity.components[SleepComponent.self] = sleep
            }
        }

        Self.sleepingCount = sleeping
        Self.trackedCount  = tracked
    }
}

// MARK: - Waking

@MainActor
extension Entity {

    // Called from the collision subscription on a sleeping body. Restores the
    // dynamic mode and mass captured when it went to sleep, so a cube that has
    // been parked for a minute still reacts to a ball hitting it.
    func wakePhysicsBody() {
        guard var sleep = components[SleepComponent.self], sleep.isAsleep else { return }
        guard var body  = components[PhysicsBodyComponent.self] else { return }

        body.mode = .dynamic
        body.massProperties.mass = sleep.storedMass
        components[PhysicsBodyComponent.self] = body

        sleep.isAsleep    = false
        sleep.quietFrames = 0
        components[SleepComponent.self] = sleep
    }
}
