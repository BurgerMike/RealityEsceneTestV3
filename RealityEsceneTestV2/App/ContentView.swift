// ContentView.swift
// RealityEsceneTestV2
//
// Launcher ↔ scene. The graphics preset chosen on the launcher is carried into
// whichever scene starts; LaunchOptions can skip the launcher entirely.

import SwiftUI

struct ContentView: View {
    @State private var modoActivo: SceneMode?
    @State private var quality: QualityPreset

    private let options = LaunchOptions.current

    init() {
        _modoActivo = State(initialValue: LaunchOptions.current.scene)
        _quality    = State(initialValue: LaunchOptions.current.quality)
    }

    var body: some View {
        if let modo = modoActivo {
            RealityScene(
                modoInicial: modo,
                quality: quality,
                demoMode: options.demoMode,
                particleMode: options.particleMode
            ) {
                NSCursor.unhide()
                CGAssociateMouseAndMouseCursorPosition(1)
                modoActivo = nil
            }
        } else {
            MenuPrincipal(
                onStart: { modo in modoActivo = modo },
                quality: $quality
            )
        }
    }
}
