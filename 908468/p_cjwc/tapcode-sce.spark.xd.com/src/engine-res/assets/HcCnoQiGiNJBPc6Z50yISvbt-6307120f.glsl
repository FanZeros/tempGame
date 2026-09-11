/*
 * SSGI trace pass, port of UE SSRTDiffuseIndirect.usf (DIM_LIGHTING_TERM == DIFFUSE_TERM).
 * Runs at half resolution; UE's CS/LDS layout is degraded to a plain pixel shader
 * (platform adaptation), the per-ray math is a line-by-line port:
 *   - cosine hemisphere rays around the view-space normal (CosineSampleHemisphereConcentric)
 *   - IS_SSGI_SHADER screen-space ray init (tolerance slope scale 2)
 *   - SSGI_TRACE_CONE exponential-step HZB walk
 *   - hits sample the HCB (prev frame color pyramid) at the walk's end mip
 *   - Karis luminance weighting when CONFIG_RAY_COUNT > 1
 *
 * Output:
 *   RT0: rgb = bounce radiance (avg over rays), a = ambient visibility (1 - hit ratio,
 *        UE AmbientOcclusionOutput semantics — 1 means fully open, use IBL fallback)
 *   RT1: r = closest hit view-space distance (-1 when no ray hit; denoiser input)
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
#define SSGI_TRACE_PASS
#include "ScreenSpace/SSGI/SSGICommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

// FarthestHiZ (unit 2) and HCB (unit 3) samplers come from SSGICommon.sh.
SAMPLER2D(u_Depth0, 0);
SAMPLER2D(u_Normal1, 1);
SAMPLER2D(u_GBufferB4, 4);

uniform hfloat u_FrameIndex;
// UE quality presets (SSRTDiffuseIndirect.usf:22-37, r.SSGI.Quality 1-4) delivered as
// runtime uniforms by View::ApplySSGIParameters — UrhoX runs them as dynamic loop
// bounds instead of UE's compile-time permutations (same pattern as the SSR trace).
uniform hfloat u_SSGIRayCount;
uniform hfloat u_SSGISteps;

// Loop cap = quality 4 ray count (32) / max steps (12)
#define MAX_SSGI_RAYS 32

// HCB has 6 mips (0..5)
#define MAX_HCB_MIP 5.0

#define StoreSSGITraceResult(color, hitDist) \
    gl_FragData[0] = color; \
    gl_FragData[1] = hvec4_init(hitDist, 0.0, 0.0, 1.0)

void PS()
{
    hvec2 uv = vTexCoord;

    hfloat deviceZ = texture2D(u_Depth0, uv).r;
    hfloat shadingModelID = texture2D(u_GBufferB4, uv).a * 255.0;

    // UE bTraceRay = ShadingModelID != SHADINGMODELID_UNLIT because every lit model
    // consumes SSGI there. UrhoX deviation: only PBR_LIT(1) consumes SSGI; Toon completes
    // its indirect diffuse in deferred lighting to preserve its direct-vs-indirect max.
    bool ssgiModel = abs(shadingModelID - 1.0) < 0.5;
    BRANCH
    if (deviceZ >= 0.9999 || !ssgiModel)
    {
        StoreSSGITraceResult(hvec4_init(0.0, 0.0, 0.0, 1.0), -1.0);
        return;
    }

    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal1, uv).rgb);
    hvec3 viewN = normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
    hvec3 viewPos = ReconstructViewPos(uv, deviceZ);

    // half-res pixel coord (UE ComputeRandomSeed uses the tracing-res PixelPosition)
    hvec2 pixelCoord = uv / cGBufferInvSize;

    // float StepOffset = InterleavedGradientNoise(PixelPosition + 0.5, StateFrameIndexMod8);
    // SSGI_TRACE_CONE keeps the raw value (the -0.9 shift is the non-cone path only).
    hfloat stepOffset = InterleavedGradientNoise(pixelCoord + u_FrameIndex * hvec2_init(32.665, 11.815));

    // UE: Rand3DPCG16(PixelPosition, StateFrameIndexMod8) scrambles Hammersley16.
    // Float-hash adaptation, same as the SSR trace passes.
    hfloat randomX = SsrHash13(hvec3_init(pixelCoord.x, pixelCoord.y, u_FrameIndex));
    hfloat randomY = SsrHash13(hvec3_init(pixelCoord.y + 17.0, pixelCoord.x + 43.0, u_FrameIndex));

    hvec3 diffuseColor = hvec3_init(0.0, 0.0, 0.0);
    hfloat ambientOcclusion = 0.0;
    hfloat closestHitDistance = 1.0e20;

    int rayCount = int(clamp(u_SSGIRayCount, 1.0, hfloat_init(MAX_SSGI_RAYS)));
    int raySteps = int(clamp(u_SSGISteps, 4.0, 12.0));
    bool karisWeighting = rayCount > 1; // CONFIG_KARIS_WEIGHTING = CONFIG_RAY_COUNT > 1

    LOOP
    for (int raySequenceId = 0; raySequenceId < MAX_SSGI_RAYS; raySequenceId++)
    {
        BRANCH
        if (raySequenceId >= rayCount)
            break;

        hvec2 e = HammersleyFloat(raySequenceId, rayCount, randomX, randomY);

        // float3 ViewL = ComputeL(ViewN, E) — cosine hemisphere in view space
        hvec3 tangentL = SsgiCosineSampleHemisphereConcentric(e);
        hvec3 viewL = UETangentToWorld(tangentL, viewN);

        hvec3 rayStartUVZ;
        hvec3 rayStepUVZ;
        hfloat rayCompareTolerance;
        InitScreenSpaceRaySSGI(uv, deviceZ, viewL, rayStartUVZ, rayStepUVZ, rayCompareTolerance);

        hvec3 hitUVZ;
        hfloat level;
        bool bHit;
        bool bUncertain;
        CastScreenSpaceRayCone(rayStartUVZ, rayStepUVZ, rayCompareTolerance,
            raySteps, stepOffset, /* RayRoughness = */ 1.0,
            hitUVZ, level, bHit, bUncertain);

        // UE computes bUncertain but never consumes it for SSGI (bRejectUncertainRays
        // is dead code in SSRTDiffuseIndirect.usf); leak control comes from the HCB
        // sky rejection + vignette instead.

        BRANCH
        if (bHit)
        {
            hvec4 sampleColor = SsgiSampleHCB(hitUVZ.xy, clamp(level, 0.0, MAX_HCB_MIP));

            hfloat sampleColorWeight = 1.0;
            BRANCH
            if (karisWeighting)
                sampleColorWeight *= 1.0 / (1.0 + SsrLuminance(sampleColor.rgb));

            diffuseColor += sampleColor.rgb * sampleColorWeight;
            ambientOcclusion += 1.0;

            hvec3 hitViewPos = ReconstructViewPos(hitUVZ.xy, hitUVZ.z);
            closestHitDistance = min(closestHitDistance, length(hitViewPos - viewPos));
        }
    }

    diffuseColor *= 1.0 / hfloat_init(rayCount);
    ambientOcclusion *= 1.0 / hfloat_init(rayCount);

    BRANCH
    if (karisWeighting)
        diffuseColor *= 1.0 / max(1.0 - SsrLuminance(diffuseColor), 0.001);

    // AmbientOcclusion = 1 - AmbientOcclusion (UE output semantics: ambient visibility)
    ambientOcclusion = 1.0 - ambientOcclusion;

    hfloat outHitDistance = closestHitDistance < 1.0e19 ? closestHitDistance : -1.0;
    StoreSSGITraceResult(hvec4_init(diffuseColor.x, diffuseColor.y, diffuseColor.z, ambientOcclusion), outHitDistance);
}

#endif // COMPILEPS
