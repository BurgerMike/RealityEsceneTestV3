// InstanceFieldGPU.swift
// RealityEsceneTestV3
//
// The Metal side of the GPU instancing demo.
//
// RealityKit renders on Metal regardless, but everything else in this project
// talks to it through RealityKit. This is the one place the project reaches
// for Metal directly: a compute pipeline that fills LowLevelInstanceData's
// transform buffer in place, so the 40 000 matrices are built by the GPU that
// is about to draw them instead of by a Swift loop that then uploads them.
//
// Setting up a device, a queue and a pipeline can all fail — no Metal device,
// a library that did not get compiled into the bundle, a kernel that is not
// there. Every one of those returns nil here and InstanceFieldSystem falls
// back to the CPU path, which is why that path is still in the project.

import Metal
import RealityKit

// Mirrors InstanceFieldParams in InstanceField.metal. All members are 4-byte
// scalars, which is what keeps the two layouts identical without having to
// reason about padding.
struct InstanceFieldParams {
    var columns: UInt32
    var rows: UInt32
    var rowOffset: UInt32
    var totalRows: UInt32
    var spacing: Float
    var cubeScale: Float
    var time: Float
    var waveSpeed: Float
    var waveLength: Float
    var amplitude: Float
    var spin: Float
    var cameraX: Float
    var cameraZ: Float
    var heightOffset: Float
}

@MainActor
final class InstanceFieldGPU {

    // nil when Metal is unavailable or the kernel could not be loaded.
    static let shared = InstanceFieldGPU()

    let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let threadExecutionWidth: Int

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "instance_field_transforms"),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else {
            return nil
        }

        self.queue = queue
        self.pipeline = pipeline
        self.threadExecutionWidth = pipeline.threadExecutionWidth
    }

    // Encodes one band's field into the command buffer. The buffer comes from
    // LowLevelInstanceData.replace(using:), which hands back the instance
    // storage itself — nothing is copied, and RealityKit will not render from
    // it until this command buffer completes.
    func encode(
        field: InstanceFieldComponent,
        cameraXZ: SIMD2<Float>,
        into commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let count = field.columns * field.rows
        guard count > 0,
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return false }

        var params = InstanceFieldParams(
            columns: UInt32(field.columns),
            rows: UInt32(field.rows),
            rowOffset: UInt32(field.rowOffset),
            totalRows: UInt32(field.totalRows),
            spacing: field.spacing,
            cubeScale: field.cubeScale,
            time: field.time,
            waveSpeed: field.waveSpeed,
            waveLength: field.waveLength,
            amplitude: field.amplitude,
            spin: field.spin,
            cameraX: cameraXZ.x,
            cameraZ: cameraXZ.y,
            heightOffset: field.heightOffset
        )

        let transforms = field.data.replace(using: commandBuffer)

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(transforms, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<InstanceFieldParams>.stride, index: 1)

        // One thread per instance, in groups sized to the pipeline's own
        // execution width so no lane in a group goes unused.
        let groupWidth = min(pipeline.maxTotalThreadsPerThreadgroup, threadExecutionWidth * 8)
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: groupWidth, height: 1, depth: 1)
        )
        encoder.endEncoding()
        return true
    }
}
