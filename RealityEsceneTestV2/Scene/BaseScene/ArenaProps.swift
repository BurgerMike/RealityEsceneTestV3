// ArenaProps.swift
// RealityEsceneTestV2
//
// The skyline around the arena, and the demo of RealityKit's own
// LevelOfDetailComponent.
//
// Each tower is one parent entity holding three groups of children — a
// detailed group, a simplified group and a single box. RealityKit shows and
// hides the groups by camera distance on its own; there is no per-frame code
// and no manual mesh swapping. This replaces the hand-written LODSystem that
// walked every entity each frame and searched the scene for the camera.

import RealityKit
import SwiftUI

// Distance bands, also read by the HUD so it can report how many towers sit
// in each band without duplicating the thresholds.
enum LODBand {
    static let high:   Float = 22
    static let medium: Float = 45
    static let low:    Float = 400

    static func band(forDistance d: Float) -> Int {
        d < high ? 0 : d < medium ? 1 : 2
    }
}

@MainActor
struct ArenaSkyline {
    let towers: [Entity]
}

@MainActor
func buildSkyline(in root: Entity, count: Int = 60) -> ArenaSkyline {

    // Shared meshes and materials — one GPU upload reused by every tower.
    let shaftMesh  = MeshResource.generateBox(size: [1.0, 1.0, 1.0], cornerRadius: 0.04)
    let capMesh    = MeshResource.generateBox(size: [1.3, 0.25, 1.3], cornerRadius: 0.05)
    let ringMesh   = MeshResource.generateBox(size: [1.08, 0.12, 1.08])
    let mastMesh   = MeshResource.generateCylinder(height: 1.0, radius: 0.05)
    let simpleMesh = MeshResource.generateBox(size: [1.0, 1.0, 1.0])

    var concrete = PhysicallyBasedMaterial()
    concrete.baseColor = .init(tint: .init(white: 0.13, alpha: 1))
    concrete.roughness = .init(floatLiteral: 0.72)
    concrete.metallic  = .init(floatLiteral: 0.25)

    var steel = PhysicallyBasedMaterial()
    steel.baseColor = .init(tint: .init(white: 0.22, alpha: 1))
    steel.roughness = .init(floatLiteral: 0.28)
    steel.metallic  = .init(floatLiteral: 0.95)

    // Emissive bands are what the bloom pass picks up.
    func neon(_ hue: CGFloat) -> PhysicallyBasedMaterial {
        let color = NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1.0)
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.emissiveColor = .init(color: color)
        m.emissiveIntensity = 4.5
        m.roughness = .init(floatLiteral: 0.3)
        return m
    }

    var towers: [Entity] = []
    var generator = SystemRandomNumberGenerator()

    for i in 0..<count {
        let angle  = Float(i) / Float(count) * 2 * .pi
        let radius = Float.random(in: 15...32, using: &generator)
        let height = Float.random(in: 3...13,  using: &generator)
        let width  = Float.random(in: 1.4...3.2, using: &generator)

        let tower = Entity()
        tower.name = "tower\(i)"
        tower.position = [cos(angle) * radius, 0, sin(angle) * radius]
        tower.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &generator),
                                       axis: [0, 1, 0])

        // MARK: Detail level 0 — full silhouette
        let shaft = ModelEntity(mesh: shaftMesh, materials: [concrete])
        shaft.scale    = [width, height, width]
        shaft.position = [0, height / 2, 0]

        let cap = ModelEntity(mesh: capMesh, materials: [steel])
        cap.scale    = [width, 1, width]
        cap.position = [0, height, 0]

        let hue = CGFloat((Float(i) / Float(count)) * 0.45 + 0.5)
        let ringLow = ModelEntity(mesh: ringMesh, materials: [neon(hue)])
        ringLow.scale    = [width, 1, width]
        ringLow.position = [0, height * 0.35, 0]

        let ringHigh = ModelEntity(mesh: ringMesh, materials: [neon(hue)])
        ringHigh.scale    = [width, 1, width]
        ringHigh.position = [0, height * 0.72, 0]

        let mast = ModelEntity(mesh: mastMesh, materials: [steel])
        mast.scale    = [1, height * 0.22, 1]
        mast.position = [0, height + height * 0.11, 0]

        // MARK: Detail level 1 — shaft, cap and one band
        let shaftMid = ModelEntity(mesh: simpleMesh, materials: [concrete])
        shaftMid.scale    = [width, height, width]
        shaftMid.position = [0, height / 2, 0]

        let capMid = ModelEntity(mesh: simpleMesh, materials: [steel])
        capMid.scale    = [width * 1.25, 0.25, width * 1.25]
        capMid.position = [0, height, 0]

        let ringMid = ModelEntity(mesh: simpleMesh, materials: [neon(hue)])
        ringMid.scale    = [width * 1.05, 0.12, width * 1.05]
        ringMid.position = [0, height * 0.6, 0]

        // MARK: Detail level 2 — one box
        let far = ModelEntity(mesh: simpleMesh, materials: [concrete])
        far.scale    = [width, height, width]
        far.position = [0, height / 2, 0]

        let levels: [[Entity]] = [
            [shaft, cap, ringLow, ringHigh, mast],
            [shaftMid, capMid, ringMid],
            [far]
        ]
        levels.flatMap { $0 }.forEach { tower.addChild($0) }

        // RealityKit owns the switching from here on.
        LevelOfDetailComponent.addByCameraDistance(to: tower, levels: [
            (entities: levels[0], maxDistance: LODBand.high),
            (entities: levels[1], maxDistance: LODBand.medium),
            (entities: levels[2], maxDistance: LODBand.low)
        ])

        root.addChild(tower)
        towers.append(tower)
    }

    return ArenaSkyline(towers: towers)
}
