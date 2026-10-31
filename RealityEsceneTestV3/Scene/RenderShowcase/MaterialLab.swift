// MaterialLab.swift
// RealityEsceneTestV3
//
// What a PBR material is actually made of, taken apart one channel at a time.
//
// ModelDebugOptionsComponent replaces an entity's shading with a single
// channel of it: the raw base colour, the interpolated normals, the roughness
// value that decides how wide a highlight spreads, the diffuse and specular
// lighting terms before they are combined. Cycling through those on a row of
// deliberately different materials shows why clearcoat paint and brushed metal
// respond to light the way they do, rather than asserting that they do.
//
// It is also the cheapest debugging tool RealityKit has, and nothing in the
// project used it.

import RealityKit
import SwiftUI

// The channels worth stepping through, in an order that tells a story:
// geometry first, then the material inputs, then the lighting they produce.
enum MaterialChannel: Int, CaseIterable {
    case final
    case baseColor
    case normal
    case roughness
    case metallic
    case clearcoat
    case ambientOcclusion
    case lightingDiffuse
    case lightingSpecular

    var label: String {
        switch self {
        case .final:            return "FINAL SHADING"
        case .baseColor:        return "BASE COLOR"
        case .normal:           return "NORMALS"
        case .roughness:        return "ROUGHNESS"
        case .metallic:         return "METALLIC"
        case .clearcoat:        return "CLEARCOAT"
        case .ambientOcclusion: return "AMBIENT OCCLUSION"
        case .lightingDiffuse:  return "DIFFUSE LIGHTING"
        case .lightingSpecular: return "SPECULAR LIGHTING"
        }
    }

    var explanation: String {
        switch self {
        case .final:            return "everything below, combined"
        case .baseColor:        return "the albedo, before any light touches it"
        case .normal:           return "the surface direction used for every lighting term"
        case .roughness:        return "black is a mirror, white scatters light wide"
        case .metallic:         return "white reflects its surroundings instead of a diffuse colour"
        case .clearcoat:        return "the lacquer layer, the second highlight on car paint"
        case .ambientOcclusion: return "how much ambient light reaches each point"
        case .lightingDiffuse:  return "the soft term — base colour times incoming light"
        case .lightingSpecular: return "the sharp term — the highlights alone"
        }
    }

    var visualizationMode: ModelDebugOptionsComponent.VisualizationMode {
        switch self {
        case .final:            return .none
        case .baseColor:        return .baseColor
        case .normal:           return .normal
        case .roughness:        return .roughness
        case .metallic:         return .metallic
        case .clearcoat:        return .clearcoat
        case .ambientOcclusion: return .ambientOcclusion
        case .lightingDiffuse:  return .lightingDiffuse
        case .lightingSpecular: return .lightingSpecular
        }
    }

    // Parsed from --channel so a recording can open straight on one.
    static func named(_ name: String) -> MaterialChannel? {
        switch name {
        case "final":                     return .final
        case "basecolor", "albedo":       return .baseColor
        case "normal", "normals":         return .normal
        case "roughness":                 return .roughness
        case "metallic", "metal":         return .metallic
        case "clearcoat":                 return .clearcoat
        case "ao", "ambientocclusion":    return .ambientOcclusion
        case "diffuse":                   return .lightingDiffuse
        case "specular":                  return .lightingSpecular
        default:                          return nil
        }
    }

    var next: MaterialChannel {
        MaterialChannel(rawValue: (rawValue + 1) % MaterialChannel.allCases.count) ?? .final
    }
}

@MainActor
struct MaterialLabSamples {
    // The spheres, so the scene can retint their debug mode as it changes.
    let samples: [ModelEntity]
    let entities: [Entity]
}

@MainActor
func setupMaterialLab(in rig: SceneRig) -> MaterialLabSamples {

    var entities: [Entity] = []
    var samples: [ModelEntity] = []

    // Six materials chosen to differ in a *different* channel each, so every
    // step of the cycle has something to show.
    let specimens: [(name: String, material: PhysicallyBasedMaterial)] = [
        ("CAR PAINT",     Mat.carPaint(.systemRed)),
        ("BRUSHED METAL", Mat.brushedMetal()),
        ("POLISHED",      Mat.polishedMetal()),
        ("GLASS",         Mat.glass()),
        ("NEON",          Mat.neon(.init(red: 0.3, green: 1.0, blue: 0.8, alpha: 1), intensity: 4)),
        ("ROUGH",         roughStone())
    ]

    let mesh = MeshResource.generateSphere(radius: 0.46)
    let spacing: Float = 1.45
    let startX = -Float(specimens.count - 1) / 2 * spacing

    // A plinth under the row, so the spheres sit on something and cast
    // shadows onto it rather than floating.
    var plinthMaterial = PhysicallyBasedMaterial()
    plinthMaterial.baseColor = .init(tint: .init(white: 0.07, alpha: 1))
    plinthMaterial.roughness = .init(floatLiteral: 0.55)
    plinthMaterial.metallic  = .init(floatLiteral: 0.3)

    let plinth = ModelEntity(
        mesh: .generateBox(size: [Float(specimens.count) * spacing + 0.6, 0.25, 1.6]),
        materials: [plinthMaterial]
    )
    plinth.position = [0, 0.78, -2.6]
    rig.install(plinth)
    entities.append(plinth)

    for (index, specimen) in specimens.enumerated() {
        let sphere = ModelEntity(mesh: mesh, materials: [specimen.material])
        sphere.position = [startX + Float(index) * spacing, 1.36, -2.6]
        sphere.components.set(SpinComponent(speed: 0.35, bobAmplitude: 0))

        rig.install(sphere)
        entities.append(sphere)
        samples.append(sphere)

        // Name plate, so the row reads without a legend.
        // In front of the plinth, not on it: at the plinth's own depth the
        // plate is edge-on to the camera and unreadable.
        let plate = makeWorldLabel(
            specimen.name,
            at: [sphere.position.x, 0.56, -1.55],
            tint: .init(white: 0.92, alpha: 1),
            width: 1400
        )
        plate.scale = .init(repeating: 2.0)   // wider and the names collide
        rig.install(plate, castsShadow: false)
        entities.append(plate)
    }

    return MaterialLabSamples(samples: samples, entities: entities)
}

// Deliberately the opposite of everything else in the row: no metal, no
// clearcoat, nothing but a wide rough diffuse response.
@MainActor
private func roughStone() -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    m.baseColor = .init(tint: .init(red: 0.55, green: 0.5, blue: 0.45, alpha: 1))
    m.roughness = .init(floatLiteral: 0.95)
    m.metallic  = .init(floatLiteral: 0.0)
    m.specular  = .init(floatLiteral: 0.2)
    return m
}

// MARK: - Applying a channel

@MainActor
func applyChannel(_ channel: MaterialChannel, to samples: [ModelEntity]) {
    for sample in samples {
        if channel == .final {
            // Removing the component restores normal shading; setting .none
            // leaves the debug path in place for no reason.
            sample.components.remove(ModelDebugOptionsComponent.self)
        } else {
            sample.components.set(
                ModelDebugOptionsComponent(visualizationMode: channel.visualizationMode)
            )
        }
    }
}
