// RealityEsceneTestV3App.swift
// RealityEsceneTestV3
//
// Component and system registration. Custom components must be registered
// before anything sets them, and systems before the first scene is built —
// doing it here means it happens once, at launch, for the whole process.

import SwiftUI
import RealityKit

@main
struct RealityEsceneTestV3App: App {

    init() {
        // ECS — the solver-sleep pass and the GPU instancing field.
        SleepComponent.registerComponent()
        SleepSystem.registerSystem()
        InstanceFieldComponent.registerComponent()
        InstanceFieldSystem.registerSystem()
        AudioPulseComponent.registerComponent()
        AudioPulseSystem.registerSystem()
        SpinComponent.registerComponent()
        SpinSystem.registerSystem()

        // Built-in force effects used by the force field demo.
        VortexForceEffect.register()
        TurbulenceForceEffect.register()
        ConstantRadialForceEffect.register()

    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1600, height: 1000)
    }
}
