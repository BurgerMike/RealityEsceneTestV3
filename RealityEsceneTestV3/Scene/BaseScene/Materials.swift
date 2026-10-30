// Materials.swift
// RealityEsceneTestV3
//
// Shared PhysicallyBasedMaterial recipes.
//
// Every surface in the demo goes through here so the scenes read consistently
// and the full PBR parameter set is actually used — clearcoat for painted
// surfaces, anisotropy for brushed metal, subsurface for the glass, emissive
// for anything the bloom pass should pick up. V1 set baseColor, roughness and
// metallic and left the rest at defaults, which is why plastic, metal and
// glass all looked like the same material in different colours.

import RealityKit
import SwiftUI

@MainActor
enum Mat {

    // Automotive paint: coloured base under a clear lacquer. The clearcoat is
    // what produces the second, sharper highlight on top of the diffuse one.
    static func carPaint(_ color: NSColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor          = .init(tint: color)
        m.roughness          = .init(floatLiteral: 0.38)
        m.metallic           = .init(floatLiteral: 0.1)
        m.clearcoat          = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.06)
        return m
    }

    // Brushed metal. anisotropyLevel stretches the highlight along one axis,
    // which is the difference between "metal" and "grey plastic".
    static func brushedMetal(_ color: NSColor = .init(white: 0.78, alpha: 1)) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor       = .init(tint: color)
        m.roughness       = .init(floatLiteral: 0.22)
        m.metallic        = .init(floatLiteral: 1.0)
        m.anisotropyLevel = .init(floatLiteral: 0.7)
        m.specular        = .init(floatLiteral: 1.0)
        return m
    }

    static func polishedMetal(_ color: NSColor = .init(white: 0.95, alpha: 1)) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: 0.06)
        m.metallic  = .init(floatLiteral: 1.0)
        return m
    }

    // Transparent glass with a tint and a faint internal scatter.
    static func glass(_ color: NSColor = .init(red: 0.45, green: 0.75, blue: 1.0, alpha: 1)) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor          = .init(tint: color)
        m.roughness          = .init(floatLiteral: 0.02)
        m.metallic           = .init(floatLiteral: 0.0)
        m.clearcoat          = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.02)
        m.blending           = .transparent(opacity: .init(floatLiteral: 0.28))
        m.specular           = .init(floatLiteral: 1.0)
        return m
    }

    // Shattered glass shard — more opaque than the intact sphere so the
    // fragments read clearly against the dark floor.
    static func shard(_ color: NSColor = .init(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor          = .init(tint: color)
        m.roughness          = .init(floatLiteral: 0.05)
        m.metallic           = .init(floatLiteral: 0.3)
        m.clearcoat          = .init(floatLiteral: 1.0)
        m.blending           = .transparent(opacity: .init(floatLiteral: 0.65))
        return m
    }

    // Anything that should glow. intensity above ~1 is what crosses the
    // bloom threshold in RenderSettings.
    static func neon(_ color: NSColor, intensity: Float = 4.0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor         = .init(tint: color)
        m.emissiveColor     = .init(color: color)
        m.emissiveIntensity = intensity
        m.roughness         = .init(floatLiteral: 0.25)
        m.metallic          = .init(floatLiteral: 0.2)
        return m
    }

    // The expanding shell on a spatial audio source: emissive so it carries in
    // the dark arena, and transparent enough that the source stays visible
    // through it.
    static func pulseShell(_ color: NSColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor         = .init(tint: color)
        m.emissiveColor     = .init(color: color)
        m.emissiveIntensity = 2.6
        m.roughness         = .init(floatLiteral: 0.5)
        m.metallic          = .init(floatLiteral: 0.0)
        m.blending          = .transparent(opacity: .init(floatLiteral: 0.35))
        m.faceCulling       = .none
        return m
    }

    static func hueCube(_ hue: CGFloat, emissive: Float = 0.5) -> PhysicallyBasedMaterial {
        let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.95, alpha: 1)
        var m = PhysicallyBasedMaterial()
        m.baseColor         = .init(tint: color)
        m.roughness         = .init(floatLiteral: 0.34)
        m.metallic          = .init(floatLiteral: 0.55)
        m.emissiveColor     = .init(color: color)
        m.emissiveIntensity = emissive
        return m
    }
}
