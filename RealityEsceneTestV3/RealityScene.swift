// RealityScene.swift
// RealityEsceneTestV3
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

    // What AUTO reads. displayScale is the scale of the display the window is
    // on and changes when it is dragged to another one.
    @Environment(\.displayScale) private var displayScale
    @State private var surfaceSize: CGSize = .zero

    // Submodes live here so MenuOverlay can read and write them.
    @State private var currentDemoMode: DemoMode = .balls
    @State private var currentParticleMode: ParticleMode = .rain
    @State private var currentShowcaseMode: ShowcaseMode = .portals

    init(
        modoInicial: SceneMode,
        quality: QualityPreset,
        demoMode: DemoMode = .balls,
        particleMode: ParticleMode = .rain,
        showcaseMode: ShowcaseMode = .portals,
        onVolver: @escaping () -> Void
    ) {
        self.modoInicial = modoInicial
        self.quality = quality
        self.onVolver = onVolver
        _currentMode = State(initialValue: modoInicial)
        _renderSettings = State(initialValue: RenderSettings(preset: quality))
        _currentDemoMode = State(initialValue: demoMode)
        _currentParticleMode = State(initialValue: particleMode)
        _currentShowcaseMode = State(initialValue: showcaseMode)
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
            case .rendering:
                RenderShowcaseScene(
                    controller: controller,
                    isMenuOpen: $isMenuOpen,
                    currentShowcaseMode: $currentShowcaseMode,
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
                    currentShowcaseMode: $currentShowcaseMode,
                    renderSettings: $renderSettings,
                    onDemoModeSelected: { mode in
                        currentDemoMode = mode
                        resumeScene()
                    },
                    onParticleModeSelected: { mode in
                        currentParticleMode = mode
                        resumeScene()
                    },
                    onShowcaseModeSelected: { mode in
                        currentShowcaseMode = mode
                        resumeScene()
                    }
                )
            }
        }
        // AUTO depends on the drawable, so it has to be re-resolved whenever
        // the drawable changes: a window resize, or the window moving onto a
        // display with a different scale. onGeometryChange reports this view's
        // own size without wrapping the scene in a GeometryReader and changing
        // its layout, and unlike NSApplication.shared.windows.first it cannot
        // end up describing some other window.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            surfaceSize = size
            syncAutoQuality()
        }
        .onChange(of: displayScale) { _, _ in syncAutoQuality() }
        .onChange(of: renderSettings.selection) { _, _ in syncAutoQuality() }
    }

    // Pixels the renderer actually fills: points from the layout, times the
    // scale of the display showing them.
    private var surfacePixels: Double {
        Double(surfaceSize.width * displayScale) * Double(surfaceSize.height * displayScale)
    }

    // A fixed preset is left exactly as chosen; only AUTO is recomputed, and
    // only when the surface lands in a different band, so dragging a window
    // edge does not rebuild the settings on every frame of the drag.
    private func syncAutoQuality() {
        guard renderSettings.selection == .auto, surfacePixels > 0 else { return }
        let resolved = QualityPreset.resolved(forSurfacePixels: surfacePixels)
        guard renderSettings.preset != resolved else { return }
        renderSettings = RenderSettings(.auto, surfacePixels: surfacePixels)
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
