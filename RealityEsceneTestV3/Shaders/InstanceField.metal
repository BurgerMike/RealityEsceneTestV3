//
//  InstanceField.metal
//  RealityEsceneTestV3
//
//  Per-instance transforms for the GPU instancing demo, computed on the GPU.
//
//  LowLevelInstanceData hands out its transform buffer two ways. The CPU path,
//  withMutableTransforms, is a plain Swift loop over 40 000 matrices. This is
//  the other one: replace(using:) returns the same storage as an MTLBuffer,
//  and RealityKit waits on the command buffer before it renders from it, so
//  the whole field can be built by a compute kernel and never cross the bus.
//
//  The kernel is a direct translation of writeInstanceTransforms in
//  InstanceField.swift, which stays as the fallback. Keeping them in step
//  matters: the two have to produce the same field.
//

#include <metal_stdlib>
using namespace metal;

// Mirrored by InstanceFieldParams in InstanceField.swift. Every member is a
// 4-byte scalar so both sides agree on layout without padding rules.
struct InstanceFieldParams {
    uint  columns;
    uint  rows;
    uint  rowOffset;
    uint  totalRows;
    float spacing;
    float cubeScale;
    float time;
    float waveSpeed;
    float waveLength;
    float amplitude;
    float spin;
    float cameraX;
    float cameraZ;
    float heightOffset;
};

kernel void instance_field_transforms(
    device   float4x4           *transforms [[buffer(0)]],
    constant InstanceFieldParams &params    [[buffer(1)]],
    uint                         index      [[thread_position_in_grid]])
{
    // The grid is rounded up to the threadgroup size, so the tail has to be
    // discarded rather than writing past the buffer.
    if (index >= params.columns * params.rows) {
        return;
    }

    const uint row    = index / params.columns;
    const uint column = index % params.columns;

    const float halfX = float(params.columns)   * 0.5f;
    const float halfZ = float(params.totalRows) * 0.5f;

    const float x = (float(column) - halfX) * params.spacing;
    const float z = (float(row + params.rowOffset) - halfZ) * params.spacing;

    // Radial travelling wave, centred on the camera, so walking across the
    // field pushes the ripple ahead of you.
    const float dx       = x - params.cameraX;
    const float dz       = z - params.cameraZ;
    const float distance = sqrt(dx * dx + dz * dz);

    const float phase  = distance / params.waveLength - params.time * params.waveSpeed;
    const float height = (sin(phase) * 0.5f + 0.5f) * params.amplitude;

    // Spin, phase-shifted by distance so the field twists instead of rotating
    // as one block.
    const float angle = params.time * params.spin + distance * 0.25f;
    const float c     = cos(angle) * params.cubeScale;
    const float s     = sin(angle) * params.cubeScale;

    // Columns, not rows: simd and Metal are both column-major, and the
    // translation belongs in the fourth column.
    transforms[index] = float4x4(
        float4( c, 0.0f, s,    0.0f),
        float4( 0.0f, params.cubeScale, 0.0f, 0.0f),
        float4(-s, 0.0f, c,    0.0f),
        float4( x, height + params.heightOffset, z, 1.0f)
    );
}
