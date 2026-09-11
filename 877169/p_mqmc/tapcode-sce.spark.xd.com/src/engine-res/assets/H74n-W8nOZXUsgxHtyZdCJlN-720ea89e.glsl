/*
 * HiZ Occlusion Test Shader
 * UrhoX port of UE HZBTestPS (HZBOcclusion.usf + NaniteHZBCull.ush).
 *
 * One pixel per object: fetch world-space AABB from the bounds textures,
 * project its 8 corners, build the screen rect, pick a mip so the dilated
 * footprint fits 4x4 texels, compare the box's closest depth against the
 * farthest occluder depth from FarthestHiZ (pow2half HZB).
 *
 * Conservative rules (visible on any doubt):
 *   - empty slot (extent.w == 0)      -> visible
 *   - any corner crosses near plane   -> visible
 *   - rect corners floor/ceil + 1 texel dilation, depth epsilon
 *
 * Output: r = 1 visible, r = 0 occluded (RGBA8 result RT, async readback).
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

// Bounds textures (RGBA32F): xyz = world center / extent; extent.w == 0 marks empty slot
SAMPLER2D(u_BoundsCenter0, 0);
SAMPLER2D(u_BoundsExtent1, 1);
// FarthestHiZ mipmapped pyramid (pow2half, r32f)
SAMPLER2D(u_FarthestHiZ2, 2);

// World -> clip of the culling camera (current frame, includes TAA jitter — absorbed
// by the 1-texel rect dilation + depth epsilon, same as UE using the view UB matrices)
uniform hmat4 u_OcclViewProj;
// xy = HZB mip0 size, z = HZB mip count, w = depth epsilon
uniform hvec4 u_OcclHZBParams;
// Screen UV -> HZB UV factor (UE HZBUvFactorAndInvFactor semantics)
uniform hvec4 u_HZBUvFactor;

void PS()
{
    // NOTE: keep this shader GLSL 1.20 compatible (desktop GL 2.1 editor backend):
    // no texelFetch, no integer bitwise ops. gl_FragCoord = texel center (x+0.5, y+0.5),
    // so * 1/256 point-samples the exact bounds texel.
    hvec2 slotUV = hvec2_init(gl_FragCoord.x, gl_FragCoord.y) * (1.0 / 256.0);
    hvec4 center = texture2DLod(u_BoundsCenter0, slotUV, 0.0);
    hvec4 extent = texture2DLod(u_BoundsExtent1, slotUV, 0.0);

    // Empty slot -> visible (matches UE HZBOcclusion.usf BoundsExtent.w == 0 branch)
    if (extent.w == 0.0)
    {
        gl_FragColor = hvec4_init(1.0, 0.0, 0.0, 1.0);
        return;
    }

    // Project the 8 AABB corners. Track the screen rect and the box depth closest
    // to the camera. UV/depth conventions mirror ProjectViewToUVZ (SSRCommon.sh).
    bool nearClip = false;
    hvec2 uvMin = hvec2_init(1.0, 1.0);
    hvec2 uvMax = hvec2_init(0.0, 0.0);
#ifdef REVERSED_Z
    hfloat boxClosest = 0.0;    // reversed-Z: closest = max depth
#else
    hfloat boxClosest = 1.0;    // standard Z: closest = min depth
#endif

    // 8 corners via nested 2x2x2 loops (GLSL 1.20: no bitwise ops)
    LOOP
    for (int cz = 0; cz < 2; ++cz)
    {
        LOOP
        for (int cy = 0; cy < 2; ++cy)
        {
            LOOP
            for (int cx = 0; cx < 2; ++cx)
            {
                hvec3 corner = center.xyz + extent.xyz * hvec3_init(
                    cx == 0 ? -1.0 : 1.0,
                    cy == 0 ? -1.0 : 1.0,
                    cz == 0 ? -1.0 : 1.0);
                hvec4 clipPos = mul(hvec4_init(corner.x, corner.y, corner.z, 1.0), u_OcclViewProj);

                // Any corner behind/crossing the near plane -> visible (UE bCrossesNearPlane)
                if (clipPos.w <= 0.0001)
                {
                    nearClip = true;
                }
                else
                {
                    hvec3 ndc = clipPos.xyz / clipPos.w;
                    hvec2 uv = ndc.xy * 0.5 + 0.5;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
                    uv.y = 1.0 - uv.y;
#endif
                    hfloat depth = ndc.z;
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
                    depth = depth * 0.5 + 0.5;
#endif

                    uvMin = min(uvMin, uv);
                    uvMax = max(uvMax, uv);
#ifdef REVERSED_Z
                    boxClosest = max(boxClosest, depth);
#else
                    boxClosest = min(boxClosest, depth);
#endif
                }
            }
        }
    }

    BRANCH
    if (nearClip)
    {
        gl_FragColor = hvec4_init(1.0, 0.0, 0.0, 1.0);
        return;
    }

    uvMin = clamp(uvMin, 0.0, 1.0);
    uvMax = clamp(uvMax, 0.0, 1.0);

    // Screen UV -> HZB mip0 texel coords (uv * factor * hzbSize = viewport px / 2,
    // i.e. UE GetScreenRect's ">> 1"). Outward rounding + 1 texel dilation.
    hvec2 hzbSize = u_OcclHZBParams.xy;
    hvec2 rMin = floor(uvMin * u_HZBUvFactor.xy * hzbSize) - 1.0;
    hvec2 rMax = ceil(uvMax * u_HZBUvFactor.xy * hzbSize);          // inclusive + dilation

    // Pick the mip where the dilated footprint fits 4x4 texels
    hvec2 rectSize = max(rMax - rMin + 1.0, 1.0);
    hfloat mip = ceil(log2(max(rectSize.x, rectSize.y) * 0.25));
    mip = clamp(mip, 0.0, u_OcclHZBParams.z - 1.0);
    hfloat scale = exp2(-mip);

    hvec2 mMin = max(floor(rMin * scale), 0.0);
    hvec2 mMax = floor(rMax * scale);                                // inclusive
    hvec2 mipSize = max(floor(hzbSize * scale), 1.0);
    mMax = min(mMax, mipSize - 1.0);
    hvec2 invMipSize = 1.0 / mipSize;

    // 4x4 max reduction over the rect (UE GetMinDepthFromHZB pattern: min(base+i, max))
#ifdef REVERSED_Z
    hfloat farthest = 1.0;
#else
    hfloat farthest = 0.0;
#endif
    LOOP
    for (int sy = 0; sy < 4; ++sy)
    {
        hfloat ty = min(mMin.y + hfloat_init(sy), mMax.y);
        LOOP
        for (int sx = 0; sx < 4; ++sx)
        {
            hfloat tx = min(mMin.x + hfloat_init(sx), mMax.x);
            hvec2 uv = (hvec2_init(tx, ty) + 0.5) * invMipSize;
            hfloat d = texture2DLod(u_FarthestHiZ2, uv, mip).r;
#ifdef REVERSED_Z
            farthest = min(farthest, d);
#else
            farthest = max(farthest, d);
#endif
        }
    }

    // Occluded when the box's closest point lies behind the farthest occluder.
    // Compare in LINEAR depth: device-Z compresses nonlinearly in the distance, so a
    // fixed device-Z epsilon swallows the entire occlusion margin beyond ~100m
    // (e.g. near=0.1/far=1000: wall@200m vs object@240m differ by only ~8e-5).
    // ReconstructDepth returns linear [0,1] fraction of the far clip; x cFarClipPS = meters.
    hfloat boxLinear = ReconstructDepth(boxClosest) * cFarClipPS;
    hfloat occluderLinear = ReconstructDepth(farthest) * cFarClipPS;
    // Epsilon: absolute (u_OcclHZBParams.w, meters) + 0.5% relative — absorbs TAA jitter
    // and HZB quantization at any distance without eating thin nearby occluders
    hfloat linearEps = max(u_OcclHZBParams.w, occluderLinear * 0.005);
    bool occludedResult = boxLinear > occluderLinear + linearEps;

    gl_FragColor = occludedResult ? hvec4_init(0.0, 0.0, 0.0, 1.0) : hvec4_init(1.0, 0.0, 0.0, 1.0);
}

#endif
