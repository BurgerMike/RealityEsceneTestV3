// SpatialHUD.swift
// RealityEsceneTestV2
//
// The radar for the spatial audio scene: where each source is relative to
// where the listener is facing, plus a per-axis position bar.
//
// Frame rate and CPU used to be duplicated here; those now come from
// PerformanceHUD, which every scene shares. What is left is the part specific
// to this scene — and the radar now counter-rotates with the listener's yaw,
// so turning your head moves the dots the same way it moves the sound.

import SwiftUI

private let sphereColors: [Color] = [.red, .green, .blue]
private let axisLabels: [String] = ["X  Left / Right", "Y  Vertical", "Z  Front / Back"]

struct SpatialHUD: View {
    let spherePositions: [SIMD3<Float>]
    let listenerPosition: SIMD3<Float>
    let listenerYaw: Float

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 14) {
                CompassView(
                    spherePositions: spherePositions,
                    listenerPosition: listenerPosition,
                    listenerYaw: listenerYaw
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("AXIS POSITION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))

                    ForEach(0..<3, id: \.self) { i in
                        if i < spherePositions.count {
                            let axisValue: Float = i == 0 ? spherePositions[i].x
                                                 : i == 1 ? spherePositions[i].y - 1.5
                                                 :          spherePositions[i].z
                            DistanceBar(
                                label: axisLabels[i],
                                color: sphereColors[i],
                                position: axisValue,
                                maxRange: 7.0
                            )
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .padding(.leading, 22)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - CompassView

struct CompassView: View {
    let spherePositions: [SIMD3<Float>]
    let listenerPosition: SIMD3<Float>
    let listenerYaw: Float

    private let size: CGFloat = 132
    private let scale: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.62))
                .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                .frame(width: size, height: size)

            ForEach([0.33, 0.66], id: \.self) { ratio in
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: size * ratio, height: size * ratio)
            }

            Path { p in
                p.move(to:    CGPoint(x: size / 2, y: 0))
                p.addLine(to: CGPoint(x: size / 2, y: size))
                p.move(to:    CGPoint(x: 0,    y: size / 2))
                p.addLine(to: CGPoint(x: size, y: size / 2))
            }
            .stroke(.white.opacity(0.12), lineWidth: 1)
            .frame(width: size, height: size)

            // Labels are listener-relative, so they stay put while the dots
            // rotate underneath them.
            Group {
                label("L", x: -size / 2 + 9, y: 0)
                label("R", x:  size / 2 - 9, y: 0)
                label("F", x: 0, y: -size / 2 + 9)
                label("B", x: 0, y:  size / 2 - 9)
            }

            // Facing wedge — where the listener is pointed.
            Path { p in
                p.move(to: CGPoint(x: size / 2, y: size / 2))
                p.addLine(to: CGPoint(x: size / 2 - 11, y: size / 2 - 26))
                p.addLine(to: CGPoint(x: size / 2 + 11, y: size / 2 - 26))
                p.closeSubpath()
            }
            .fill(.white.opacity(0.14))
            .frame(width: size, height: size)

            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)

            ForEach(0..<3, id: \.self) { i in
                if i < spherePositions.count {
                    let point = listenerRelative(spherePositions[i])
                    // No .shadow() here: SwiftUI renders it offscreen, and
                    // this overlay redraws while the sources move. A ring
                    // reads as well and costs nothing.
                    Circle()
                        .fill(sphereColors[i])
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(sphereColors[i].opacity(0.35), lineWidth: 3)
                                .frame(width: 16, height: 16)
                        )
                        .offset(x: point.x, y: point.y)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.38))
            .offset(x: x, y: y)
    }

    // World offset rotated into the listener's frame: forward is always up.
    private func listenerRelative(_ pos: SIMD3<Float>) -> CGPoint {
        let dx = pos.x - listenerPosition.x
        let dz = pos.z - listenerPosition.z

        let c = cos(-listenerYaw)
        let s = sin(-listenerYaw)
        let rx = dx * c - dz * s
        let rz = dx * s + dz * c

        var x = CGFloat(rx) / scale * (size / 2)
        var y = CGFloat(rz) / scale * (size / 2)

        let maxR = size / 2 - 9
        let r = sqrt(x * x + y * y)
        if r > maxR {
            x = x / r * maxR
            y = y / r * maxR
        }
        return CGPoint(x: x, y: y)
    }
}

// MARK: - DistanceBar

struct DistanceBar: View {
    let label: String
    let color: Color
    let position: Float
    let maxRange: Float

    private var ratio: CGFloat {
        CGFloat(max(-1.0, min(1.0, position / maxRange)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(color)

            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.08))
                    .frame(width: 180, height: 6)

                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 1, height: 10)

                // Fill grows out from the centre in the direction of travel.
                GeometryReader { geo in
                    let center = geo.size.width / 2
                    let fill = abs(ratio) * center
                    Rectangle()
                        .fill(color.opacity(0.8))
                        .frame(width: fill, height: 6)
                        .offset(x: ratio >= 0 ? center : center - fill)
                }
                .frame(width: 180, height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}
