// MenuOverlay.swift
// RealityEsceneTestV3
//
// The in-scene pause menu: pick a submode, change the graphics preset, or go
// back to the launcher. Opened and closed with TAB.

import SwiftUI

struct MenuOverlay: View {
    @Binding var currentMode: SceneMode
    @Binding var isMenuOpen: Bool
    let onVolver: () -> Void
    @Binding var currentDemoMode: DemoMode
    @Binding var currentParticleMode: ParticleMode
    @Binding var currentShowcaseMode: ShowcaseMode
    @Binding var renderSettings: RenderSettings
    let onDemoModeSelected: ((DemoMode) -> Void)?
    let onParticleModeSelected: ((ParticleMode) -> Void)?
    let onShowcaseModeSelected: ((ShowcaseMode) -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: 22) {

                Text(currentMode.overlayTitle)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white)

                // MARK: Submodes
                VStack(spacing: 9) {
                    switch currentMode {
                    case .audioMovement:
                        InfoRow(text: "3 sources moving on the X, Y and Z axes")
                        InfoRow(text: "Headphones recommended — HRTF is applied by the system")
                        InfoRow(text: "Mouse looks around; the sources do the moving")

                    case .fisica:
                        if let onSelect = onDemoModeSelected {
                            ForEach(DemoMode.allCases, id: \.self) { mode in
                                ModeButton(
                                    title: mode.label,
                                    subtitle: mode.hint,
                                    isSelected: currentDemoMode == mode
                                ) {
                                    onSelect(mode)
                                    isMenuOpen = false
                                }
                            }
                        }

                    case .particles:
                        if let onSelect = onParticleModeSelected {
                            ForEach(ParticleMode.allCases, id: \.self) { mode in
                                ModeButton(
                                    title: mode.label,
                                    subtitle: mode.hint,
                                    isSelected: currentParticleMode == mode
                                ) {
                                    onSelect(mode)
                                    isMenuOpen = false
                                }
                            }
                        }

                    case .rendering:
                        if let onSelect = onShowcaseModeSelected {
                            ForEach(ShowcaseMode.allCases, id: \.self) { mode in
                                ModeButton(
                                    title: mode.label,
                                    subtitle: mode.hint,
                                    isSelected: currentShowcaseMode == mode
                                ) {
                                    onSelect(mode)
                                    isMenuOpen = false
                                }
                            }
                        }
                    }
                }

                Divider().overlay(.white.opacity(0.12)).frame(width: 430)

                // MARK: Graphics
                VStack(spacing: 8) {
                    Text("GRAPHICS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 8) {
                        ForEach(QualityPreset.allCases, id: \.self) { preset in
                            let selected = renderSettings.preset == preset
                            Button {
                                renderSettings = RenderSettings(preset: preset)
                            } label: {
                                Text(preset.label)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(selected ? Color.cyan.opacity(0.18) : .white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(selected ? Color.cyan.opacity(0.7) : .white.opacity(0.1),
                                                    lineWidth: 1)
                                    )
                                    .foregroundStyle(selected ? .cyan : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(renderSettings.activeFeatures.joined(separator: "  ·  "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.38))
                }

                Text("[ TAB ]  close")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 2)

                Button("← Main menu") {
                    onVolver()
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.red.opacity(0.8))
                .buttonStyle(.plain)
            }
            .padding(36)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.black.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - InfoRow

struct InfoRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 430, alignment: .leading)
    }
}

// MARK: - ModeButton

struct ModeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                if isSelected {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.cyan.opacity(0.13) : .white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.cyan.opacity(0.6) : .white.opacity(0.09),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: 430)
    }
}
