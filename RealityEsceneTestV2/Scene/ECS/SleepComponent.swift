// SleepComponent.swift
// RealityEsceneTestV2
//
// Marks a physics body as eligible for the engine-independent sleep pass run
// by SleepSystem.

import RealityKit

struct SleepComponent: Component {
    // Below this speed the body is a candidate for sleeping.
    var velocityThreshold: Float = 0.08

    // Frames it must stay below the threshold before it is put to sleep.
    // Without this hysteresis a body is frozen the instant it reaches the apex
    // of a bounce, mid-air.
    var framesToSleep: Int = 14

    // Running count of consecutive slow frames.
    var quietFrames: Int = 0

    // True while the body is parked as static.
    var isAsleep: Bool = false

    // Mass is lost when a body goes static, so it is kept here to restore the
    // body exactly as it was when something wakes it up.
    var storedMass: Float = 1.0
}
