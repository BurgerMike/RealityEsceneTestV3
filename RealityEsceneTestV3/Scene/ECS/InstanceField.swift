// InstanceField.swift
// RealityEsceneTestV3
//
// GPU instancing — the headline of the demo.
//
// MeshInstancesComponent hands RealityKit one mesh plus a buffer of per
// instance transforms, and the whole field is drawn in a single instanced
// draw call. Twenty-five thousand animated cubes as twenty-five thousand
// ModelEntities would mean twenty-five thousand draw submissions and an
// entity hierarchy the engine has to traverse every frame; here it is one
// entity per colour band.
//
// InstanceFieldSystem rewrites the transform buffer each frame through
// LowLevelInstanceData.withMutableTransforms, so the field is genuinely
// animated rather than a static scatter.

import RealityKit
import simd
import AppKit

// MARK: - Component

struct InstanceFieldComponent: Component {
    // The transform buffer RealityKit reads. Held by reference so the system
    // can rewrite it in place without rebuilding the component.
    let data: LowLevelInstanceData

    let columns: Int
    let rows: Int
    let rowOffset: Int        // where this band starts in the full field
    let totalRows: Int
    let spacing: Float
    let cubeScale: Float

    var time: Float = 0
    var waveSpeed: Float = 2.2
    var waveLength: Float = 1.6
    // Kept below eye height: the field is something you look across, not
    // something you stand inside.
    var amplitude: Float = 0.85
    var spin: Float = 0.9
    // How far the whole field sits above the floor. Shared with the Metal
    // kernel, which has to produce exactly the same field as the CPU path.
    var heightOffset: Float = 0.06
}

// MARK: - Transform writing

// Writes one band's transforms into its buffer. Shared between the builder and
// the system so the field is never left holding uninitialised data: a buffer of
// zero matrices draws nothing, and nothing drawn means the entity is not
// rendering, which is the one condition the system needs in order to run.
@MainActor
func writeInstanceTransforms(_ field: InstanceFieldComponent, cameraXZ: SIMD2<Float>) {
    let halfX = Float(field.columns) * 0.5
    let halfZ = Float(field.totalRows) * 0.5

    field.data.withMutableTransforms { buffer in
        var i = 0
        for row in 0..<field.rows {
            let globalRow = Float(row + field.rowOffset)
            let z = (globalRow - halfZ) * field.spacing

            for column in 0..<field.columns {
                let x = (Float(column) - halfX) * field.spacing

                // Radial travelling wave, centred on the camera.
                let dx = x - cameraXZ.x
                let dz = z - cameraXZ.y
                let distance = sqrt(dx * dx + dz * dz)
                let phase = distance / field.waveLength - field.time * field.waveSpeed
                let height = (sin(phase) * 0.5 + 0.5) * field.amplitude

                // Spin each cube, phase-shifted by its distance so the field
                // twists instead of rotating as one block.
                let angle = field.time * field.spin + distance * 0.25
                let c = cos(angle) * field.cubeScale
                let sn = sin(angle) * field.cubeScale

                // Built by hand rather than through Transform: a Y-axis
                // rotation needs six of these sixteen slots, and this runs
                // forty thousand times a frame.
                buffer[i] = float4x4(
                    SIMD4<Float>( c, 0, sn, 0),
                    SIMD4<Float>( 0, field.cubeScale, 0, 0),
                    SIMD4<Float>(-sn, 0, c, 0),
                    SIMD4<Float>( x, height + 0.06, z, 1)
                )
                i += 1
            }
        }
    }
}

// MARK: - System

struct InstanceFieldSystem: System {

    static let query = EntityQuery(where: .has(InstanceFieldComponent.self))

    // Instances rewritten on the last frame — reported by the HUD.
    @MainActor static var animatedInstances = 0

    // Which path actually ran, so the HUD can say so rather than claim it.
    @MainActor static var usesGPUTransforms = false

    init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        // Looked up once per frame, not once per instance: the wave radiates
        // from wherever the player is standing, so walking across the field
        // pushes the ripple ahead of you instead of playing a canned loop.
        let camera = context.scene.findEntity(named: "cameraAnchor")?.position(relativeTo: nil)
            ?? .zero
        let cameraXZ = SIMD2<Float>(camera.x, camera.z)

        var animated = 0

        // One command buffer for every band. The GPU fills the instance
        // storage in place through LowLevelInstanceData.replace(using:), and
        // RealityKit waits on this buffer before it renders from it.
        let gpu = InstanceFieldGPU.shared
        let commandBuffer = gpu?.queue.makeCommandBuffer()
        var encodedOnGPU = false

        // performQuery rather than entities(matching:updatingSystemWhen:
        // .rendering). The only available condition is `.rendering`, and
        // gating this system on it is circular: the instances are not drawn
        // until their transforms are written, and the transforms are not
        // written until something is drawn.
        for entity in context.scene.performQuery(Self.query) {
            guard var field = entity.components[InstanceFieldComponent.self] else { continue }

            field.time += Float(context.deltaTime)
            entity.components[InstanceFieldComponent.self] = field

            if let gpu, let commandBuffer,
               gpu.encode(field: field, cameraXZ: cameraXZ, into: commandBuffer) {
                encodedOnGPU = true
            } else {
                // No Metal device, no compiled kernel, or the encoder could
                // not be made: fall back to building the field in Swift.
                writeInstanceTransforms(field, cameraXZ: cameraXZ)
            }

            animated += field.columns * field.rows
        }

        if encodedOnGPU { commandBuffer?.commit() }

        Self.animatedInstances = animated
        Self.usesGPUTransforms = encodedOnGPU
    }
}

// MARK: - Builder

@MainActor
struct InstanceField {
    let entities: [Entity]
    let instanceCount: Int
    let bandCount: Int
}

// Splits the field into horizontal bands so each band can carry its own
// colour: LowLevelInstanceData stores transforms only, so colour variety
// comes from using a handful of instanced entities instead of one.
@MainActor
func buildInstanceField(
    columns: Int = 200,
    rows: Int = 200,
    bands: Int = 6,
    spacing: Float = 0.10
) -> InstanceField {

    // A plain box, deliberately. MeshInstancesComponent silently refuses a
    // mesh built with generateBox(cornerRadius:) — the component is accepted,
    // the counters all read correctly and the system keeps writing transforms,
    // but nothing is ever drawn. That cost an afternoon.
    let mesh = MeshResource.generateBox(size: 0.075)
    let rowsPerBand = rows / bands
    let extent = max(Float(columns), Float(rows)) * spacing * 0.5 + 1

    var entities: [Entity] = []
    var total = 0

    for band in 0..<bands {
        let bandRows = band == bands - 1 ? rows - rowsPerBand * (bands - 1) : rowsPerBand
        let count = columns * bandRows
        guard let data = try? LowLevelInstanceData(instanceCount: count) else { continue }

        let hue = CGFloat(band) / CGFloat(bands) * 0.72 + 0.04
        let color = NSColor(hue: hue, saturation: 0.82, brightness: 1.0, alpha: 1.0)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.26)
        material.metallic  = .init(floatLiteral: 0.72)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 0.9

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "instanceBand\(band)"

        // Explicit bounds: automatic recalculation would walk every instance
        // each time the buffer changes, and the field's extent never does.
        let bounds = BoundingBox(
            min: [-extent, -0.5, -extent],
            max: [ extent,  2.0,  extent]
        )

        // The explicit initialiser binds the instance buffer to the mesh
        // itself. Assigning through subscript(partIndex:) on a default-
        // constructed component left the field silently undrawn: the counters
        // all reported 40 000 and the system was writing transforms every
        // frame, but nothing reached the screen.
        let modelIDs = mesh.contents.models.map { $0.id }

        let instances: MeshInstancesComponent
        do {
            instances = try MeshInstancesComponent(
                mesh: mesh,
                modelID: modelIDs.first,
                instances: data,
                bounds: bounds
            )
        } catch {
            print("⚠️ MeshInstancesComponent rejected band \(band): \(error)")
            continue
        }
        entity.components.set(instances)

        let fieldComponent = InstanceFieldComponent(
            data: data,
            columns: columns,
            rows: bandRows,
            rowOffset: band * rowsPerBand,
            totalRows: rows,
            spacing: spacing,
            cubeScale: 1.0
        )

        // Fill the buffer before it is ever rendered.
        writeInstanceTransforms(fieldComponent, cameraXZ: .zero)
        entity.components.set(fieldComponent)

        entities.append(entity)
        total += count
    }

    return InstanceField(entities: entities, instanceCount: total, bandCount: entities.count)
}
