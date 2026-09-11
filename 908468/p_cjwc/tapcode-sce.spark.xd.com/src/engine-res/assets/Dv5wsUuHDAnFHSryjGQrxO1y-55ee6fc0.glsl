/*
 * HiZ Initialize Shader (Mip 0) — first reduction, UE HZB style
 * Reduces full-resolution depth into the pow2half HZB mip0 (2x2 min/max).
 * Output RT is RoundUpPow2(viewport)>>1: ratio in (1,2] per axis, so every
 * source texel is claimed by at least one output texel (conservative by
 * construction, see UE SceneTextureReductions.cpp / HZB.usf).
 * Output 0: ClosestHiZ - conservative closest depth
 * Output 1: FarthestHiZ - conservative farthest depth
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

// Depth buffer (register 0, matching RenderPath texture unit)
SAMPLER2D(u_Depth0, 0);

// Depth source (viewport) size: xy = size, zw = invSize. The HZB RT is pow2half sized
// and no longer matches the viewport; set by View::ApplyHiZBuildParameters
uniform hvec4 u_HiZViewport;

void PS()
{
    // Output texel (x,y) reduces the 2x2 source depth block (2x,2y)..(2x+1,2y+1).
    // Use gl_FragCoord (highp by spec) for integer addressing to avoid half-precision
    // vTexCoord off-by-one at large resolutions.
    // gl_FragCoord.xy = (x+0.5, y+0.5), so x2 = center corner of the source block (2x+1, 2y+1).
    hvec2 srcCorner = hvec2_init(gl_FragCoord.x, gl_FragCoord.y) * 2.0;

    // Clamp out-of-range samples (pow2 padding / odd viewport edge) to the last texel center
    // inside the viewport, matching UE HZB.usf InputViewportMaxBound semantics —
    // duplicated samples are harmless for min/max reduction
    hvec2 maxUV = (u_HiZViewport.xy - 0.5) * u_HiZViewport.zw;

    hvec2 uv00 = min((srcCorner + hvec2_init(-0.5, -0.5)) * u_HiZViewport.zw, maxUV);
    hvec2 uv10 = min((srcCorner + hvec2_init( 0.5, -0.5)) * u_HiZViewport.zw, maxUV);
    hvec2 uv01 = min((srcCorner + hvec2_init(-0.5,  0.5)) * u_HiZViewport.zw, maxUV);
    hvec2 uv11 = min((srcCorner + hvec2_init( 0.5,  0.5)) * u_HiZViewport.zw, maxUV);

    // Use full precision (hfloat/hvec4) for depth to avoid fp16 quantization artifacts
    hvec4 depth4;
    depth4.x = texture2D(u_Depth0, uv00).r;
    depth4.y = texture2D(u_Depth0, uv10).r;
    depth4.z = texture2D(u_Depth0, uv01).r;
    depth4.w = texture2D(u_Depth0, uv11).r;

#ifdef REVERSED_Z
    // Reversed-Z: near = 1.0, far = 0.0
    hfloat closest = max(max(depth4.x, depth4.y), max(depth4.z, depth4.w));
    hfloat farthest = min(min(depth4.x, depth4.y), min(depth4.z, depth4.w));
#else
    // Standard Z: near = 0.0, far = 1.0
    hfloat closest = min(min(depth4.x, depth4.y), min(depth4.z, depth4.w));
    hfloat farthest = max(max(depth4.x, depth4.y), max(depth4.z, depth4.w));
#endif

    // MRT output: gl_FragData[0] = ClosestHiZ, gl_FragData[1] = FarthestHiZ
    gl_FragData[0] = hvec4_init(closest, 0.0, 0.0, 1.0);
    gl_FragData[1] = hvec4_init(farthest, 0.0, 0.0, 1.0);
}

#endif
