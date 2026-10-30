// LaunchOptions.swift
// RealityEsceneTestV2
//
// Command line control over which demo opens and at what quality, plus a
// headless-ish benchmark mode.
//
// This is what makes the project measurable instead of anecdotal. Claiming a
// frame rate in a README is worth nothing; being able to run
//
//   RealityEsceneTestV2 --scene physics --mode stress --quality ultra --benchmark 12
//
// and have the app print its own average, 1% low and p99 is worth something,
// and it is how every change in here gets checked.

import Foundation

struct LaunchOptions: Sendable {
    var scene: SceneMode?
    var demoMode: DemoMode = .balls
    var particleMode: ParticleMode = .rain
    var quality: QualityPreset = .ultra

    // Seconds to run before printing a summary and quitting. 0 = normal run.
    var benchmarkSeconds: Double = 0

    static let current = LaunchOptions(ProcessInfo.processInfo.arguments)

    init(_ arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  index + 1 < arguments.count else { return nil }
            return arguments[index + 1].lowercased()
        }

        switch value("--scene") {
        case "physics", "fisica": scene = .fisica
        case "particles":         scene = .particles
        case "audio":             scene = .audioMovement
        default:                  scene = nil
        }

        switch value("--mode") {
        case "breakable":               demoMode = .breakable
        case "tower":                   demoMode = .tower
        case "joints", "chains":        demoMode = .joints
        case "forcefield", "force":     demoMode = .forceField
        case "stress", "towerstress":   demoMode = .towerStress
        case "instancing", "instances": demoMode = .instancing
        default:                        demoMode = .balls
        }

        switch value("--effect") {
        case "snow":   particleMode = .snow
        case "fire":   particleMode = .fire
        case "sparks": particleMode = .sparks
        default:       particleMode = .rain
        }

        switch value("--quality") {
        case "performance": quality = .performance
        case "balanced":    quality = .balanced
        default:            quality = .ultra
        }

        benchmarkSeconds = Double(value("--benchmark") ?? "") ?? 0
    }
}
