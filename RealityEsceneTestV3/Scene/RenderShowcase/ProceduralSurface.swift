// ProceduralSurface.swift
// RealityEsceneTestV3
//
// A mesh built by the GPU, every frame, from nine floats.
//
// MeshResource.generateBox and friends hand you geometry RealityKit authored.
// LowLevelMesh is the other end of that: you declare a vertex layout and an
// index buffer, and you own the memory. Here the indices are written once on
// the CPU — the grid's topology never changes — and the positions and normals
// are rewritten by a Metal compute kernel on every frame, through the same
// replace(using:) pattern the instancing demo uses for its transforms.
//
// Nothing about this surface exists in Swift. There is no array of vertices.

import RealityKit
import Metal
import SwiftUI

// Mirrors SurfaceParams in ProceduralSurface.metal.
struct SurfaceParams {
    var columns: UInt32
    var rows: UInt32
    var spacing: Float
    var time: Float
    var amplitude: Float
    var frequency: Float
    var speed: Float
    var cameraX: Float
    var cameraZ: Float
}

// MARK: - Component and system

struct ProceduralSurfaceComponent: Component {
    let mesh: LowLevelMesh
    let columns: Int
    let rows: Int
    let spacing: Float

    var time: Float = 0
    var amplitude: Float = 0.62
    var frequency: Float = 0.38
    var speed: Float = 1.1
}

struct ProceduralSurfaceSystem: System {

    static let query = EntityQuery(where: .has(ProceduralSurfaceComponent.self))

    // Vertices rewritten on the last frame, for the HUD.
    @MainActor static var vertexCount = 0
    @MainActor static var onGPU = false

    init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        guard let gpu = SurfaceGPU.shared,
              let commandBuffer = gpu.queue.makeCommandBuffer()
        else {
            Self.onGPU = false
            return
        }

        let camera = context.scene.findEntity(named: "cameraAnchor")?.position(relativeTo: nil)
            ?? .zero

        var vertices = 0
        var encoded = false

        for entity in context.scene.performQuery(Self.query) {
            guard var surface = entity.components[ProceduralSurfaceComponent.self] else { continue }

            surface.time += Float(context.deltaTime)
            entity.components[ProceduralSurfaceComponent.self] = surface

            if gpu.encode(
                surface: surface,
                cameraXZ: SIMD2(camera.x, camera.z),
                into: commandBuffer
            ) {
                encoded = true
                vertices += surface.columns * surface.rows
            }
        }

        if encoded { commandBuffer.commit() }

        Self.vertexCount = vertices
        Self.onGPU = encoded
    }
}

// MARK: - Pipeline

@MainActor
final class SurfaceGPU {

    static let shared = SurfaceGPU()

    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "surface_vertices"),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func encode(
        surface: ProceduralSurfaceComponent,
        cameraXZ: SIMD2<Float>,
        into commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let count = surface.columns * surface.rows
        guard count > 0,
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return false }

        var params = SurfaceParams(
            columns: UInt32(surface.columns),
            rows: UInt32(surface.rows),
            spacing: surface.spacing,
            time: surface.time,
            amplitude: surface.amplitude,
            frequency: surface.frequency,
            speed: surface.speed,
            cameraX: cameraXZ.x,
            cameraZ: cameraXZ.y
        )

        // Buffer index 0 is the vertex buffer the descriptor declared.
        let vertexBuffer = surface.mesh.replace(bufferIndex: 0, using: commandBuffer)

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<SurfaceParams>.stride, index: 1)

        let groupWidth = min(pipeline.maxTotalThreadsPerThreadgroup, pipeline.threadExecutionWidth * 8)
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: groupWidth, height: 1, depth: 1)
        )
        encoder.endEncoding()
        return true
    }
}

// MARK: - Builder

@MainActor
struct ProceduralSurfaceResult {
    let entities: [Entity]
    let vertexCount: Int
    let triangleCount: Int
}

@MainActor
func setupProceduralSurface(
    in rig: SceneRig,
    columns: Int = 240,
    rows: Int = 160,
    spacing: Float = 0.10
) -> ProceduralSurfaceResult {

    let vertexCount = columns * rows
    let quadCount = (columns - 1) * (rows - 1)
    let indexCount = quadCount * 6

    // 12 bytes of position, 12 of normal, 8 of UV. The kernel writes exactly
    // this layout, so the two have to agree member for member.
    let stride = MemoryLayout<Float>.size * 8

    let descriptor = LowLevelMesh.Descriptor(
        vertexCapacity: vertexCount,
        vertexAttributes: [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal,   format: .float3, layoutIndex: 0, offset: 12),
            .init(semantic: .uv0,      format: .float2, layoutIndex: 0, offset: 24)
        ],
        vertexLayouts: [
            .init(bufferIndex: 0, bufferOffset: 0, bufferStride: stride)
        ],
        indexCapacity: indexCount,
        indexType: .uint32
    )

    guard let mesh = try? LowLevelMesh(descriptor: descriptor) else {
        return ProceduralSurfaceResult(entities: [], vertexCount: 0, triangleCount: 0)
    }

    // The topology never changes, so the indices are written once, on the CPU.
    mesh.replaceUnsafeMutableIndices { raw in
        let indices = raw.bindMemory(to: UInt32.self)
        var i = 0
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let topLeft     = UInt32(row * columns + column)
                let topRight    = topLeft + 1
                let bottomLeft  = topLeft + UInt32(columns)
                let bottomRight = bottomLeft + 1

                indices[i + 0] = topLeft
                indices[i + 1] = bottomLeft
                indices[i + 2] = topRight
                indices[i + 3] = topRight
                indices[i + 4] = bottomLeft
                indices[i + 5] = bottomRight
                i += 6
            }
        }
    }

    // Bounds are declared rather than derived: the vertices live on the GPU,
    // so RealityKit has nothing to measure.
    let halfWidth = Float(columns) * spacing * 0.5
    let halfDepth = Float(rows) * spacing * 0.5
    mesh.parts.append(
        LowLevelMesh.Part(
            indexOffset: 0,
            indexCount: indexCount,
            topology: .triangle,
            materialIndex: 0,
            bounds: BoundingBox(
                min: [-halfWidth, -3, -halfDepth],
                max: [ halfWidth,  3,  halfDepth]
            )
        )
    )

    guard let resource = try? MeshResource(from: mesh) else {
        return ProceduralSurfaceResult(entities: [], vertexCount: 0, triangleCount: 0)
    }

    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: .init(red: 0.12, green: 0.42, blue: 0.68, alpha: 1))
    material.roughness = .init(floatLiteral: 0.18)
    material.metallic  = .init(floatLiteral: 0.85)
    // No clearcoat. On a surface that is already metallic and smooth the
    // second specular lobe is invisible, and it is evaluated for every pixel
    // the swell covers — which is most of the lower screen.
    // Both sides: the swell lifts above eye level and you end up under it.
    material.faceCulling = .none

    let entity = ModelEntity(mesh: resource, materials: [material])
    entity.name = "proceduralSurface"
    // In front of the player, not under them. Centred on the origin the
    // surface reached the camera's own feet, so the nearest polygons filled
    // the frame and there was no way to see the swell as a whole. Pushed back,
    // it starts a few metres out and recedes.
    entity.position = [0, 0.95, -8]
    entity.components.set(ProceduralSurfaceComponent(
        mesh: mesh,
        columns: columns,
        rows: rows,
        spacing: spacing
    ))

    rig.install(entity, castsShadow: false)

    return ProceduralSurfaceResult(
        entities: [entity],
        vertexCount: vertexCount,
        triangleCount: quadCount * 2
    )
}
