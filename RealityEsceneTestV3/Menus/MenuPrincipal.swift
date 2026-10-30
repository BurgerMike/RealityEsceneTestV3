// MenuPrincipal.swift
// RealityEsceneTestV3
//
// The launcher.
//
// V1 was three bordered buttons on a black background. The project's argument
// is that this machine runs real-time 3D well, so the launcher states which
// machine it is and what each scene puts under load, before anything starts.

import SwiftUI

struct MenuPrincipal: View {
    let onStart: (SceneMode) -> Void
    @Binding var quality: QualityPreset

    @State private var hovered: SceneMode?

    private var info: SystemInfo { .current }

    var body: some View {
        ZStack {
            // Background — dark with a cool cast, so the cards read as glass.
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Faint horizon glow behind the title.
            RadialGradient(
                colors: [Color.cyan.opacity(0.14), .clear],
                center: .init(x: 0.5, y: 0.26),
                startRadius: 10,
                endRadius: 620
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                header

                Spacer(minLength: 34)

                HStack(alignment: .top, spacing: 18) {
                    ForEach(SceneMode.allCases, id: \.self) { mode in
                        sceneCard(mode)
                    }
                }

                Spacer(minLength: 28)

                qualityRow

                Spacer(minLength: 26)

                machineFooter

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("REALITY SCENE")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .tracking(10)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("REALITYKIT  ·  METAL  ·  APPLE SILICON")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.cyan.opacity(0.75))

            Text("Real-time 3D on macOS — physics, GPU instancing, spatial audio and\nHDR post-processing, built with RealityKit and nothing else.")
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 4)
        }
    }

    // MARK: - Scene cards

    private func sceneCard(_ mode: SceneMode) -> some View {
        let isHovered = hovered == mode

        return Button {
            onStart(mode)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(mode.icon)
                    .font(.system(size: 34))
                    .padding(.bottom, 14)

                Text(mode.cardTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(mode.cardSubtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(.white.opacity(0.1))
                    .padding(.vertical, 13)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mode.features, id: \.self) { feature in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(.cyan.opacity(0.8))
                                .frame(width: 4, height: 4)
                            Text(feature)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }

                Spacer(minLength: 14)

                HStack(spacing: 5) {
                    Text("LAUNCH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(isHovered ? .cyan : .white.opacity(0.4))
            }
            .padding(20)
            .frame(width: 236, height: 300, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(isHovered ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? Color.cyan.opacity(0.55) : .white.opacity(0.09),
                            lineWidth: 1)
            )
            .shadow(color: isHovered ? .cyan.opacity(0.18) : .clear, radius: 18)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? mode : nil }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    // MARK: - Quality

    private var qualityRow: some View {
        VStack(spacing: 9) {
            Text("GRAPHICS PRESET")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.35))

            HStack(spacing: 10) {
                ForEach(QualityPreset.allCases, id: \.self) { preset in
                    let selected = quality == preset
                    Button {
                        quality = preset
                    } label: {
                        VStack(spacing: 3) {
                            Text(preset.label)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text(preset.hint)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(selected ? Color.cyan.opacity(0.16) : .white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(selected ? Color.cyan.opacity(0.7) : .white.opacity(0.08),
                                        lineWidth: 1)
                        )
                        .foregroundStyle(selected ? .cyan : .white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Switchable live in any scene with 1 / 2 / 3")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    // MARK: - Footer

    private var machineFooter: some View {
        HStack(spacing: 26) {
            footerItem("CHIP", info.shortChip)
            footerItem("CPU", info.coreSummary)
            footerItem("GPU", info.gpuSummary)
            footerItem("MEMORY", "\(info.memoryGB) GB unified")
            footerItem("DISPLAY", "\(info.displayResolution) @ \(info.displayRefreshRate) Hz")
            footerItem("OS", info.osVersion)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func footerItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.3))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}
