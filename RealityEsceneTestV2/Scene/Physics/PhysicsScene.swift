// PhysicsScene.swift
// RealityEsceneTestV2
//
// Six physics demos behind one TAB overlay. The scene owns the rig returned by
// buildBaseScene, hands it to whichever mode is loading, and reports what the
// engine is actually doing to the HUD: live rigid-body count, how many of them
// the SleepSystem has parked, instance counts when the GPU instancing mode is
// up, and how many towers each LOD band is holding.

import SwiftUI
import RealityKit

struct PhysicsScene: View {
    let controller: CameraController
    @Binding var isMenuOpen: Bool
    @Binding var currentDemoMode: DemoMode
    @Binding var renderSettings: RenderSettings

    @State private var cameraAnchor = AnchorEntity(world: .zero)
    @State private var cameraEntity = PerspectiveCamera()
    @State private var runtime = SceneRuntime()

    @State private var rig: SceneRig?
    @State private var sceneContent: (any RealityViewContentProtocol)?
    @State private var activeEntities: [Entity] = []

    @State private var basketballAudio: AudioFileResource?
    @State private var boxDropAudio: AudioFileResource?
    @State private var brokenGlassAudio: AudioFileResource?

    // Live engine counters, refreshed from the frame loop rather than from the
    // view, so SwiftUI is not re-evaluated 120 times a second.
    @State private var bodyCount = 0
    @State private var sleepingCount = 0
    @State private var instanceCount = 0
    @State private var drawCalls = 0
    @State private var jointCount = 0
    @State private var lodBands: [Int] = [0, 0, 0]
    @State private var statsCounter = 0
    @State private var hudExpanded = true

    // Projectiles fired with E, oldest first. Capped so a long recording does
    // not quietly turn into its own stress test.
    @State private var projectiles: [Entity] = []
    private let maxProjectiles = 24

    var body: some View {
        ZStack {
            RealityView { content in
                renderSettings.apply(to: &content)

                // Spatial audio is computed relative to this entity. Without
                // it the listener sits at the world origin and walking around
                // changes nothing of what you hear.
                content.audioListener = cameraEntity

                let builtRig = buildBaseScene(
                    in: content,
                    cameraAnchor: cameraAnchor,
                    cameraEntity: cameraEntity,
                    controller: controller,
                    settings: renderSettings
                )
                rig = builtRig
                sceneContent = content

                // One scene-wide subscription filtered by component type,
                // instead of one per body. This is what lets a cube the
                // SleepSystem parked react to a projectile a minute later.
                _ = content.subscribe(
                    to: CollisionEvents.Began.self,
                    componentType: SleepComponent.self
                ) { event in
                    // Called straight through, not hopped onto a Task.
                    // RealityKit delivers these on the main actor already, and
                    // when the ball lands on the block there are hundreds of
                    // contacts in one frame — a Task allocation each was the
                    // spike that showed up as the 1% low.
                    event.entityA.wakePhysicsBody()
                    event.entityB.wakePhysicsBody()
                }

                basketballAudio = try? await AudioFileResource(
                    named: "BasketBall.m4a", configuration: .init(shouldLoop: false))
                boxDropAudio = try? await AudioFileResource(
                    named: "BoxDrop.m4a", configuration: .init(shouldLoop: false))
                brokenGlassAudio = try? await AudioFileResource(
                    named: "BrokenGlass.m4a", configuration: .init(shouldLoop: false))

                load(currentDemoMode, rig: builtRig, content: content)
            } update: { content in
                // Quality changes mid-scene land here. Flags only — the
                // environment is bound once, in make.
                renderSettings.applyEffects(to: &content)
            }
            .onChange(of: currentDemoMode) { _, newMode in
                guard let rig, let sceneContent else { return }
                load(newMode, rig: rig, content: sceneContent)
            }
            .onChange(of: renderSettings) { _, settings in
                guard let rig else { return }
                settings.apply(to: rig)
            }
            .onAppear {
                runtime.start(
                    controller: controller,
                    cameraAnchor: cameraAnchor,
                    cameraEntity: cameraEntity
                )
                runtime.bindMenuToggle(controller: controller, isMenuOpen: $isMenuOpen)
                bindCommandKeys()
                runtime.onFrame = { _ in sampleEngineCounters() }
            }
            .onDisappear {
                runtime.stop(controller: controller)
                activeEntities.forEach { $0.removeFromParent() }
                activeEntities = []
                projectiles.forEach { $0.removeFromParent() }
                projectiles = []
            }

            PerformanceHUD(
                title: currentDemoMode.label,
                subtitle: currentDemoMode.hint,
                feature: currentDemoMode.feature,
                stats: runtime.frameStats,
                hardware: runtime.hardware,
                quality: renderSettings.preset,
                extraStats: extraStats,
                expanded: hudExpanded
            )

            DisplayLinkView(gameLoop: runtime.gameLoop)
                .frame(width: 0, height: 0)
        }
    }

    // MARK: - HUD rows

    private var extraStats: [HUDStat] {
        var rows: [HUDStat] = []

        if currentDemoMode == .instancing {
            rows.append(HUDStat(label: "INSTANCES",
                                value: instanceCount.formatted(),
                                tint: .cyan))
            rows.append(HUDStat(label: "DRAW CALLS", value: "\(drawCalls)", tint: .cyan))
        } else if bodyCount > 0 {
            rows.append(HUDStat(label: "RIGID BODIES", value: "\(bodyCount + projectiles.count)"))
            if sleepingCount > 0 {
                rows.append(HUDStat(label: "ASLEEP",
                                    value: "\(sleepingCount)",
                                    tint: .green))
                rows.append(HUDStat(label: "SIMULATED",
                                    value: "\(max(bodyCount - sleepingCount, 0))",
                                    tint: .yellow))
            }
        }

        if jointCount > 0 {
            rows.append(HUDStat(label: "JOINTS", value: "\(jointCount)", tint: .cyan))
        }
        if !projectiles.isEmpty {
            rows.append(HUDStat(label: "PROJECTILES",
                                value: "\(projectiles.count)",
                                tint: .yellow))
        }
        rows.append(HUDStat(label: "LOD  hi/md/lo",
                            value: "\(lodBands[0])/\(lodBands[1])/\(lodBands[2])",
                            tint: .white.opacity(0.8)))
        return rows
    }

    // MARK: - Counters

    private func sampleEngineCounters() {
        statsCounter += 1
        guard statsCounter >= 12 else { return }
        statsCounter = 0

        sleepingCount = SleepSystem.sleepingCount

        if currentDemoMode == .instancing {
            instanceCount = InstanceFieldSystem.animatedInstances
        }

        // Which LOD band each tower is in, using the same thresholds the
        // component was configured with.
        if let rig {
            var bands = [0, 0, 0]
            let camera = controller.position
            for tower in rig.skyline.towers {
                let d = tower.position(relativeTo: nil) - camera
                bands[LODBand.band(forDistance: sqrt(d.x * d.x + d.y * d.y + d.z * d.z))] += 1
            }
            lodBands = bands
        }
    }

    // MARK: - Mode loading

    private func load(_ mode: DemoMode, rig: SceneRig, content: any RealityViewContentProtocol) {
        activeEntities.forEach { $0.removeFromParent() }
        activeEntities = []
        projectiles.forEach { $0.removeFromParent() }
        projectiles = []
        bodyCount = 0
        sleepingCount = 0
        instanceCount = 0
        drawCalls = 0
        jointCount = 0

        switch mode {
        case .balls:
            activeEntities = setupBalls(in: rig, content: content, audioResource: basketballAudio)
            bodyCount = activeEntities.count

        case .breakable:
            activeEntities = setupBreakable(
                in: rig,
                content: content,
                softResource: basketballAudio,
                breakResource: brokenGlassAudio,
                onFragmentCreated: { fragment in
                    activeEntities.append(fragment)
                    bodyCount = activeEntities.count
                }
            )
            bodyCount = activeEntities.count

        case .tower:
            activeEntities = setupTower(in: rig, content: content, audioResource: boxDropAudio)
            bodyCount = activeEntities.count

        case .joints:
            let result = setupJoints(in: rig, content: content)
            activeEntities = result.entities
            bodyCount = result.bodyCount
            jointCount = result.jointCount

        case .forceField:
            let result = setupForceField(in: rig, content: content)
            activeEntities = result.entities
            bodyCount = result.bodyCount

        case .towerStress:
            activeEntities = setupTowerStress(
                in: rig,
                content: content,
                audioResource: boxDropAudio,
                onCubeCountChanged: { count in bodyCount = count }
            )

        case .instancing:
            let result = setupInstancing(in: rig)
            activeEntities = result.entities
            instanceCount = result.field.instanceCount
            drawCalls = result.field.bandCount
        }

        installWorldLabel(for: mode, in: rig)
    }

    // A caption that lives in the scene rather than in a corner panel, so a
    // recording shows the number next to the thing it describes.
    private func installWorldLabel(for mode: DemoMode, in rig: SceneRig) {
        let caption: (title: String, subtitle: String)

        switch mode {
        case .balls:
            caption = ("MASS & RESTITUTION", "3 bodies · clearcoat PBR")
        case .breakable:
            caption = ("IMPULSE THRESHOLD", "shatters above 6 N·s")
        case .tower:
            caption = ("TOWER COLLAPSE", "18 bodies · 20 kg ball")
        case .joints:
            caption = ("\(jointCount) SPHERICAL JOINTS", "\(bodyCount) bodies · press E")
        case .forceField:
            caption = ("FORCE FIELDS", "vortex + turbulence · \(bodyCount) bodies")
        case .towerStress:
            caption = ("\(bodyCount) RIGID BODIES", "ECS sleep + wake on contact")
        case .instancing:
            caption = ("\(instanceCount.formatted()) INSTANCES", "\(drawCalls) draw calls")
        }

        let label = makeWorldLabel(
            caption.title,
            subtitle: caption.subtitle,
            at: [0, 4.4, -7.5],
            tint: .init(red: 0.6, green: 0.95, blue: 1.0, alpha: 1)
        )
        rig.install(label, castsShadow: false)
        activeEntities.append(label)
    }

    // MARK: - Keys

    private func fire() {
        guard let rig else { return }

        let ball = fireProjectile(
            from: controller.position,
            yaw: controller.yaw,
            pitch: controller.pitch,
            in: rig
        )
        projectiles.append(ball)

        // Retire the oldest once the cap is reached, so the frame cost of
        // firing stays flat however long the demo runs.
        while projectiles.count > maxProjectiles {
            projectiles.removeFirst().removeFromParent()
        }
    }

    private func bindCommandKeys() {
        controller.onEPressed = { Task { @MainActor in fire() } }

        controller.onCommandKey = { key in
            Task { @MainActor in
                switch key {
                case "1": renderSettings = RenderSettings(preset: .performance)
                case "2": renderSettings = RenderSettings(preset: .balanced)
                case "3": renderSettings = RenderSettings(preset: .ultra)
                case "r":
                    if let rig, let sceneContent {
                        load(currentDemoMode, rig: rig, content: sceneContent)
                    }
                case "h": hudExpanded.toggle()
                default: break
                }
            }
        }
    }
}
