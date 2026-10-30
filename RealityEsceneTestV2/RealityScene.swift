// RealityScene.swift
// RealityEsceneTestV2
//
// Hosts whichever scene is active and owns the state the pause menu writes to,
// including the graphics preset — so a quality change survives switching
// between scenes instead of resetting with each one.

import SwiftUI
import RealityKit

struct RealityScene: View {
    let modoInicial: SceneMode
    let quality: QualityPreset
    let onVolver: () -> Void

    @State private var currentMode: SceneMode
    @State private var isMenuOpen = false
    @State private var controller = CameraController()
    @State private var renderSettings: RenderSettings

    // Submodes live here so MenuOverlay can read and write them.
    @State private var currentDemoMode: DemoMode = .balls
    @State private var currentParticleMode: ParticleMode = .rain

    init(
        modoInicial: SceneMode,
        quality: QualityPreset,
        demoMode: DemoMode = .balls,
        particleMode: ParticleMode = .rain,
        onVolver: @escaping () -> Void
    ) {
        self.modoInicial = modoInicial
        self.quality = quality
        self.onVolver = onVolver
        _currentMode = State(initialValue: modoInicial)
        _renderSettings = State(initialValue: RenderSettings(preset: quality))
        _currentDemoMode = State(initialValue: demoMode)
        _currentParticleMode = State(initialValue: particleMode)
    }

    var body: some View {
        ZStack {
            switch currentMode {
            case .audioMovement:
                AudioMovementScene(
                    controller: controller,
                    isMenuOpen: $isMenuOpen,
                    renderSettings: $renderSettings
                )
            case .fisica:
                PhysicsScene(
                    controller: controller,
                    isMenuOpen: $isMenuOpen,
                    currentDemoMode: $currentDemoMode,
                    renderSettings: $renderSettings
                )
            case .particles:
                ParticleScene(
                    controller: controller,
                    isMenuOpen: $isMenuOpen,
                    currentParticleMode: $currentParticleMode,
                    renderSettings: $renderSettings
                )
            }

            if isMenuOpen {
                MenuOverlay(
                    currentMode: $currentMode,
                    isMenuOpen: $isMenuOpen,
                    onVolver: onVolver,
                    currentDemoMode: $currentDemoMode,
                    currentParticleMode: $currentParticleMode,
                    renderSettings: $renderSettings,
                    onDemoModeSelected: { mode in
                        currentDemoMode = mode
                        resumeScene()
                    },
                    onParticleModeSelected: { mode in
                        currentParticleMode = mode
                        resumeScene()
                    }
                )
            }
        }
    }

    private func resumeScene() {
        isMenuOpen = false
        controller.isPaused = false
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
