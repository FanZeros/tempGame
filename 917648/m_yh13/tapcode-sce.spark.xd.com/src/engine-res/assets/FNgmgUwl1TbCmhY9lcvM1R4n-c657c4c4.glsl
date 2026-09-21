/*
 * HiZ Downsample Shader
 * Generates hierarchical depth buffer by downsampling previous mip level.
 * Uses 2x2 sampling with min/max operations for conservative bounds.
 *
 * Reads from separate source RT (single mip), writes to next level RT.
 *
 * Output 0: ClosestHiZ - min of 4 samples (standard Z) or max (reversed Z)
 * Output 1: FarthestHiZ - max of 4 samples (standard Z) or min (reversed Z)
 */

#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

// Source ClosestHiZ RT (register 0)
SAMPLER2D(u_ClosestHiZ0, 0);
// Source FarthestHiZ RT (register 1)
SAMPLER2D(u_FarthestHiZ1, 1);

void PS()
{
    // Under the pow2half chain the input is exactly 2x the output (strict 2:1).
    // Use gl_FragCoord (highp by spec) for integer addressing: gl_FragCoord.xy * 2 = center
    // corner of the source 2x2 block (2x+1, 2y+1), and +/-0.5 source texel offsets hit the
    // 4 texel centers exactly — avoids half-precision vTexCoord off-by-one.
    // cGBufferInvSize is output RT's invSize; input texelSize = output invSize * 0.5.
    // Must be full precision (hvec2): a half-quantized texelSize multiplied by a large
    // fragcoord drifts up to half a source texel, causing off-by-one sampling on mobile
    hvec2 texelSize = cGBufferInvSize * 0.5;
    hvec2 srcCorner = hvec2_init(gl_FragCoord.x, gl_FragCoord.y) * 2.0 * texelSize;

    hvec2 uv00 = srcCorner + hvec2_init(-0.5, -0.5) * texelSize;
    hvec2 uv10 = srcCorner + hvec2_init( 0.5, -0.5) * texelSize;
    hvec2 uv01 = srcCorner + hvec2_init(-0.5,  0.5) * texelSize;
    hvec2 uv11 = srcCorner + hvec2_init( 0.5,  0.5) * texelSize;

    // Use full precision (hfloat/hvec4) for depth — fp16 causes quantization stripes
    hvec4 closestSamples;
    closestSamples.x = texture2D(u_ClosestHiZ0, uv00).r;
    closestSamples.y = texture2D(u_ClosestHiZ0, uv10).r;
    closestSamples.z = texture2D(u_ClosestHiZ0, uv01).r;
    closestSamples.w = texture2D(u_ClosestHiZ0, uv11).r;

    hvec4 farthestSamples;
    farthestSamples.x = texture2D(u_FarthestHiZ1, uv00).r;
    farthestSamples.y = texture2D(u_FarthestHiZ1, uv10).r;
    farthestSamples.z = texture2D(u_FarthestHiZ1, uv01).r;
    farthestSamples.w = texture2D(u_FarthestHiZ1, uv11).r;

    hfloat closest;
    hfloat farthest;

#ifdef REVERSED_Z
    // Reversed-Z: near = 1.0, far = 0.0
    closest = max(max(closestSamples.x, closestSamples.y),
                  max(closestSamples.z, closestSamples.w));
    farthest = min(min(farthestSamples.x, farthestSamples.y),
                   min(farthestSamples.z, farthestSamples.w));
#else
    // Standard Z: near = 0.0, far = 1.0
    closest = min(min(closestSamples.x, closestSamples.y),
                  min(closestSamples.z, closestSamples.w));
    farthest = max(max(farthestSamples.x, farthestSamples.y),
                   max(farthestSamples.z, farthestSamples.w));
#endif

    // MRT output
    gl_FragData[0] = hvec4_init(closest, 0.0, 0.0, 1.0);
    gl_FragData[1] = hvec4_init(farthest, 0.0, 0.0, 1.0);
}

#endif
