// EnvironmentFactory.swift
// RealityEsceneTestV3
//
// Builds the scene environment procedurally — zero asset files in the bundle.
//
// The sky is written pixel by pixel as an equirectangular map and handed to
// EnvironmentResource, which RealityKit turns into both the visible skybox and
// the image based lighting (IBL) that every PBR material samples for ambient
// and specular response. That is what makes metal read as metal instead of
// flat colour.
//
// Two encodings are attempted, in order:
//   1. 32-bit float / extendedLinearSRGB — true HDR. The sun is written far
//      above 1.0 so highlights carry real energy into the IBL.
//   2. 8-bit sRGB — fallback if the HDR path is rejected by the encoder.

import Foundation
import CoreGraphics
import RealityKit

// MARK: - Sky model

// Direction-to-radiance for the environment. Returns LINEAR values that may
// exceed 1.0 on purpose: the sun disc is the energy source for the IBL.
// Pure math, no actor state — safe to call from anywhere.
private func skyRadiance(elevation: Float, azimuth: Float) -> SIMD3<Float> {

    // Key light direction — must match SunDirection in BaseScene so the
    // baked highlights line up with the shadow-casting directional light.
    let sunElevation: Float = 0.42      // ~25° above the horizon
    let sunAzimuth:   Float = 3.75      // radians

    let zenith   = SIMD3<Float>(0.015, 0.035, 0.105)
    let skyMid   = SIMD3<Float>(0.055, 0.115, 0.250)
    let haze     = SIMD3<Float>(0.420, 0.330, 0.270)
    let groundUp = SIMD3<Float>(0.030, 0.031, 0.036)
    let groundDn = SIMD3<Float>(0.008, 0.008, 0.010)

    var color: SIMD3<Float>

    if elevation >= 0 {
        // Above the horizon — haze → mid → zenith, biased so the gradient
        // compresses near the horizon the way a real sky does.
        let t = powf(elevation, 0.45)
        color = t < 0.5
            ? mix(haze, skyMid, t * 2)
            : mix(skyMid, zenith, (t - 0.5) * 2)
    } else {
        // Below the horizon — dark ground bounce, keeps the floor grounded
        // instead of glowing from underneath.
        color = mix(groundUp, groundDn, powf(-elevation, 0.6))
    }

    // Angular distance to the sun, used for both the disc and its glow.
    var dAz = abs(azimuth - sunAzimuth)
    if dAz > .pi { dAz = 2 * .pi - dAz }
    let dEl = elevation - sunElevation
    let angular = sqrtf(dAz * dAz * cosf(sunElevation) * cosf(sunElevation) + dEl * dEl)

    // Wide warm glow — sells the golden-hour read and lifts the horizon.
    let glow = expf(-angular * 3.4) * 1.6
    color += SIMD3<Float>(1.00, 0.62, 0.34) * glow

    // Sun disc — the HDR payload. Soft edge so the IBL convolution stays clean.
    let discRadius: Float = 0.045
    if angular < discRadius * 3 {
        let falloff = 1 - smoothstepf(discRadius, discRadius * 3, angular)
        color += SIMD3<Float>(1.00, 0.94, 0.86) * 26.0 * falloff * falloff
    }

    return simd_max(color, SIMD3<Float>(repeating: 0))
}

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * min(max(t, 0), 1)
}

private func smoothstepf(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

// Linear → sRGB transfer, only needed for the 8-bit fallback.
private func encodeSRGB(_ v: Float) -> Float {
    let c = min(max(v, 0), 1)
    return c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
}

// MARK: - Image encoders

private func renderSky(width: Int, height: Int, _ store: (Int, SIMD3<Float>) -> Void) {
    for y in 0..<height {
        // theta: 0 at the zenith, pi at the nadir — equirectangular convention.
        let theta = (Float(y) + 0.5) / Float(height) * .pi
        let elevation = cosf(theta)
        for x in 0..<width {
            let azimuth = (Float(x) + 0.5) / Float(width) * 2 * .pi
            store(y * width + x, skyRadiance(elevation: elevation, azimuth: azimuth))
        }
    }
}

// 32-bit float RGBA in extended linear sRGB — values above 1.0 survive.
private func makeHDRSkyImage(width: Int, height: Int) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }

    var pixels = [Float](repeating: 1, count: width * height * 4)
    renderSky(width: width, height: height) { i, c in
        pixels[i * 4 + 0] = c.x
        pixels[i * 4 + 1] = c.y
        pixels[i * 4 + 2] = c.z
        pixels[i * 4 + 3] = 1
    }

    let byteCount = pixels.count * MemoryLayout<Float>.size
    guard let data = pixels.withUnsafeBytes({ CFDataCreate(nil, $0.baseAddress, byteCount) }),
          let provider = CGDataProvider(data: data) else { return nil }

    let info = CGBitmapInfo(rawValue:
        CGBitmapInfo.floatComponents.rawValue |
        CGBitmapInfo.byteOrder32Little.rawValue |
        CGImageAlphaInfo.premultipliedLast.rawValue)

    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 32,
        bitsPerPixel: 128,
        bytesPerRow: width * 16,
        space: space,
        bitmapInfo: info,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

// 8-bit sRGB — tone mapped on the way in so the sun does not clip to a flat disc.
private func makeSDRSkyImage(width: Int, height: Int) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let buffer = ctx.data else { return nil }

    let bytes = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
    renderSky(width: width, height: height) { i, c in
        // Reinhard so the 26x sun compresses into range instead of clipping.
        let m = c / (1 + c)
        bytes[i * 4 + 0] = UInt8(encodeSRGB(m.x) * 255)
        bytes[i * 4 + 1] = UInt8(encodeSRGB(m.y) * 255)
        bytes[i * 4 + 2] = UInt8(encodeSRGB(m.z) * 255)
        bytes[i * 4 + 3] = 255
    }
    return ctx.makeImage()
}

// MARK: - Floor texture

// Dark polished surface with a grid, generated at a resolution that already
// contains the tiling. PhysicallyBasedMaterial has no UV-scale knob, so the
// repetition is baked into the texture instead of the shader.
private func makeFloorImage(size: Int = 2048, cells: Int = 32) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let buffer = ctx.data else { return nil }

    let bytes = buffer.bindMemory(to: UInt8.self, capacity: size * size * 4)
    let cell = Float(size) / Float(cells)
    var seed: UInt64 = 0x9E3779B97F4A7C15

    for y in 0..<size {
        for x in 0..<size {
            // Distance to the nearest grid line, in pixels.
            let fx = Float(x).truncatingRemainder(dividingBy: cell)
            let fy = Float(y).truncatingRemainder(dividingBy: cell)
            let edge = min(min(fx, cell - fx), min(fy, cell - fy))

            // Cheap hash noise so the surface is not perfectly uniform.
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float((seed >> 33) & 0xFF) / 255 * 0.035

            var v: Float = 0.052 + noise
            if edge < 1.6 { v = 0.145 }                     // grid line
            if edge < 1.6 && (x / Int(cell)) % 8 == 0 { v = 0.30 }   // major line
            if edge < 1.6 && (y / Int(cell)) % 8 == 0 { v = 0.30 }

            let b = UInt8(min(encodeSRGB(v), 1) * 255)
            let i = (y * size + x) * 4
            bytes[i] = b; bytes[i + 1] = b; bytes[i + 2] = UInt8(min(Float(b) * 1.06, 255))
            bytes[i + 3] = 255
        }
    }
    return ctx.makeImage()
}

// MARK: - Public factory

@MainActor
enum EnvironmentFactory {

    // Cached — building the sky costs a few hundred milliseconds and the
    // result is identical for every scene.
    private static var cachedSky: EnvironmentResource?
    private static var cachedFloor: PhysicallyBasedMaterial.Texture?

    static var skyIsHDR = false

    static func sky() -> EnvironmentResource? {
        if let cachedSky { return cachedSky }

        let (w, h) = (1024, 512)

        if let hdr = makeHDRSkyImage(width: w, height: h),
           let resource = try? EnvironmentResource(
                equirectangular: hdr,
                options: .init(samplingQuality: .high)) {
            skyIsHDR = true
            cachedSky = resource
            return resource
        }

        if let sdr = makeSDRSkyImage(width: w, height: h),
           let resource = try? EnvironmentResource(
                equirectangular: sdr,
                options: .init(samplingQuality: .high)) {
            skyIsHDR = false
            cachedSky = resource
            return resource
        }

        return nil
    }

    static func floorTexture() -> PhysicallyBasedMaterial.Texture? {
        if let cachedFloor { return cachedFloor }
        guard let image = makeFloorImage(),
              let resource = try? TextureResource(
                image: image,
                options: .init(semantic: .color)) else { return nil }
        let texture = PhysicallyBasedMaterial.Texture(resource)
        cachedFloor = texture
        return texture
    }
}
