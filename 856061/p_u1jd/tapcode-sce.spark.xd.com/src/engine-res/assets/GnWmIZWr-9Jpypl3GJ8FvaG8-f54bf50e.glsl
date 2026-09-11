/*
 * HCB (Hierarchical Color Buffer) reduction.
 * Port of UE SSRTPrevFrameReduction.usf (DIM_LEAK_FREE=0 permutation), consumed by the
 * SSGI cone trace via SampleHCBLevel (SSRTRayCast.ush).
 *
 * UE runs this as a compute shader with LDS mip reduction; here it is degraded to one
 * quad pass per mip (platform adaptation, math semantics preserved):
 *   - default:        HCB mip0 (pow2half) = reproject prev scene color at full res,
 *                     reject sky, apply pre-exposure + vignette, 2x2 box average
 *                     (UE MainCS non-LOWER_MIPS path + LDS MipLevel=1 reduction)
 *   - HCB_LOWER_MIPS: HCB mip N = 2x2 box average of mip N-1
 *                     (UE MainCS DIM_LOWER_MIPS path + LDS reduction)
 *
 * The HCB shares the pow2half layout of the HZB so both are sampled with the same
 * HZBUvFactor mapping and their mip levels stay spatially aligned.
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
#include "ScreenSpace/SSR/SSRCommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

#ifdef HCB_LOWER_MIPS

// Source: previous HCB mip (register 0)
SAMPLER2D(u_HigherMip0, 0);

void PS()
{
    // Output texel (x,y) averages the 2x2 source block (2x,2y)..(2x+1,2y+1).
    // Same addressing pattern as HiZDownsample; UE reference is the LDS 2x2 reduction
    // in SSRTPrevFrameReduction.usf MainCS (ReducedColor = sum(4) * rcp(4)).
    // cGBufferInvSize is the output RT invSize; source texel = output invSize * 0.5.
    vec2 uv = hvec2_init(gl_FragCoord.x, gl_FragCoord.y) * cGBufferInvSize;
    vec2 texelSize = cGBufferInvSize * 0.5;

    hvec3 c0 = texture2D(u_HigherMip0, uv + vec2(-0.25, -0.25) * texelSize).rgb;
    hvec3 c1 = texture2D(u_HigherMip0, uv + vec2( 0.25, -0.25) * texelSize).rgb;
    hvec3 c2 = texture2D(u_HigherMip0, uv + vec2(-0.25,  0.25) * texelSize).rgb;
    hvec3 c3 = texture2D(u_HigherMip0, uv + vec2( 0.25,  0.25) * texelSize).rgb;

    hvec3 reduced = (c0 + c1 + c2 + c3) * 0.25;
    gl_FragData[0] = hvec4_init(reduced.x, reduced.y, reduced.z, 1.0);
}

#else // mip0 build (UE MainCS non-LOWER_MIPS path)

// Previous frame resolved scene color / TAA history (register 0)
SAMPLER2D(u_PrevSceneColor0, 0);
// Current frame depth (register 1)
SAMPLER2D(u_Depth1, 1);
// Motion vectors: current UV - previous UV (register 2)
SAMPLER2D(u_MotionVector2, 2);

// Depth source (viewport) size: xy = size, zw = invSize (View::ApplyHiZBuildParameters)
uniform hvec4 u_HiZViewport;
uniform hfloat u_PrevSceneColorPreExposureCorrection;

// One full-res sample of UE's reprojection path (SSRTPrevFrameReduction.usf:141-212)
hvec3 SamplePrevColor(hvec2 uv)
{
    hfloat deviceZ = texture2D(u_Depth1, uv).r;

    // Sky rejection ("Ignore sky contribution because in skylight", :200-203).
    // UE tests WorldDepth > SkyDistance; with standard Z the far plane sits at
    // deviceZ ~= 1, so the device-Z test is the UrhoX equivalent.
    BRANCH
    if (deviceZ >= 0.9999)
        return hvec3_init(0.0, 0.0, 0.0);

    // UE reprojects via ClipToPrevClip and overrides with the velocity texture for
    // dynamic objects (:146-157); the UrhoX MotionVector already encodes the camera
    // reprojection (object velocity is a known engine-wide gap).
    hvec2 motion = texture2D(u_MotionVector2, uv).rg;
    hvec2 prevUV = clamp(uv - motion, vec2_splat(0.0), vec2_splat(1.0));

    hvec3 color = texture2D(u_PrevSceneColor0, prevUV).rgb;

    // Transform NaNs to black, transform negative colors to black (:196)
    color = -min(-color, vec3_splat(0.0));

    // Correct scene color exposure (:206)
    color *= u_PrevSceneColorPreExposureCorrection;

    // Apply vignette to the color (:208-212)
    hfloat vignette = min(ComputeHitVignette(uv), ComputeHitVignette(prevUV));
    return color * vignette;
}

void PS()
{
    // Output texel (x,y) reduces the 2x2 full-res block (2x,2y)..(2x+1,2y+1) —
    // same addressing as HiZInit; corresponds to UE's LDS MipLevel=1 reduction that
    // produces the half-res ReducedSceneColor mip0.
    hvec2 srcCorner = hvec2_init(gl_FragCoord.x, gl_FragCoord.y) * 2.0;
    hvec2 maxUV = (u_HiZViewport.xy - 0.5) * u_HiZViewport.zw;

    hvec2 uv00 = min((srcCorner + hvec2_init(-0.5, -0.5)) * u_HiZViewport.zw, maxUV);
    hvec2 uv10 = min((srcCorner + hvec2_init( 0.5, -0.5)) * u_HiZViewport.zw, maxUV);
    hvec2 uv01 = min((srcCorner + hvec2_init(-0.5,  0.5)) * u_HiZViewport.zw, maxUV);
    hvec2 uv11 = min((srcCorner + hvec2_init( 0.5,  0.5)) * u_HiZViewport.zw, maxUV);

    hvec3 reduced = (SamplePrevColor(uv00) + SamplePrevColor(uv10) +
                     SamplePrevColor(uv01) + SamplePrevColor(uv11)) * 0.25;

    gl_FragData[0] = hvec4_init(reduced.x, reduced.y, reduced.z, 1.0);
}

#endif // HCB_LOWER_MIPS

#endif // COMPILEPS
