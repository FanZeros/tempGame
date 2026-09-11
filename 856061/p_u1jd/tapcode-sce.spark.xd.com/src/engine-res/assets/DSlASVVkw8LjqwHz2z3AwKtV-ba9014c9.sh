#ifndef SSGI_COMMON_SH
#define SSGI_COMMON_SH

/*
 * SSGI ray casting, port of the IS_SSGI_SHADER / SSGI_TRACE_CONE paths of
 * UE SSRTRayCast.ush plus the sampling helpers of MonteCarlo.ush.
 *
 * Platform adaptations (marked inline):
 *   - standard Z instead of reverse Z (same sign conventions as SSRHiZTrace)
 *   - screen position work happens in UV space [0,1] instead of NDC [-1,1]
 *   - float-only sign copy (no asuint bit ops, DXBC toolchain constraint)
 *
 * Requires SSRCommon.sh (ProjectViewToUVZ) and the includer to bind:
 *   u_FarthestHiZ2 = FarthestHiZ (unit 2), u_HCB3 = HCB (unit 3)
 */

#include "ScreenSpace/SSR/SSRCommon.sh"

#if defined(COMPILEPS) && defined(SSGI_TRACE_PASS)

SAMPLER2D(u_FarthestHiZ2, 2);
SAMPLER2D(u_HCB3, 3);

// Screen UV -> HZB/HCB UV factor (UE HZBUvFactorAndInvFactor semantics),
// set by View::ApplyHiZSampleParameters. HZB and HCB share the pow2half layout.
uniform hvec4 u_HZBUvFactor;

#define SSGI_PI 3.14159265

// SSGI traces the HZB in its own mip domain (StartMipLevel = 1.0 relative to the
// pow2half chain), unlike SSRHiZTrace which keeps a legacy full-res mip mapping.
hfloat SsgiSampleFarthestHZB(hvec2 uv, hfloat hzbMip)
{
    return texture2DLod(u_FarthestHiZ2, uv * u_HZBUvFactor.xy, hzbMip).r;
}

hvec4 SsgiSampleHCB(hvec2 uv, hfloat hcbMip)
{
    return texture2DLod(u_HCB3, uv * u_HZBUvFactor.xy, hcbMip);
}

// [UE MonteCarlo.ush ConcentricDiskSamplingHelper]
// Returns a point on the unit circle and a radius in z.
hvec3 SsgiConcentricDiskSamplingHelper(hvec2 e)
{
    // Rescale input from [0,1) to (-1,1). This ensures the output radius is in [0,1)
    hvec2 p = 2.0 * e - 0.99999994;
    hvec2 a = abs(p);
    hfloat lo = min(a.x, a.y);
    hfloat hi = max(a.x, a.y);
    hfloat epsilon = 5.42101086243e-20; // 2^-64 (this avoids 0/0 without changing the rest of the mapping)
    hfloat phi = (SSGI_PI / 4.0) * (lo / (hi + epsilon) + 2.0 * (a.y >= a.x ? 1.0 : 0.0));
    hfloat radius = hi;
    // Copy sign bits from p. UE uses asuint bit ops; float-only equivalent here.
    hvec2 disk = hvec2_init(
        abs(cos(phi)) * (p.x >= 0.0 ? 1.0 : -1.0),
        abs(sin(phi)) * (p.y >= 0.0 ? 1.0 : -1.0));
    return hvec3_init(disk.x, disk.y, radius);
}

// [UE MonteCarlo.ush CosineSampleHemisphereConcentric] PDF = NoL / PI (w unused here)
hvec3 SsgiCosineSampleHemisphereConcentric(hvec2 e)
{
    hvec3 result = SsgiConcentricDiskSamplingHelper(e);
    hfloat sinTheta = result.z;
    hfloat cosTheta = sqrt(saturate(1.0 - sinTheta * sinTheta));
    return hvec3_init(result.x * sinTheta, result.y * sinTheta, cosTheta);
}

// [UE SSRTRayCast.ush GetStepScreenFactorToClipAtScreenEdge]
// Operates in screen space [-1,1]; the UV-space caller converts via *2 (offsets) and
// *2-1 (positions) — abs/symmetric math, so the D3D y-flip does not matter.
hfloat SsgiGetStepScreenFactorToClipAtScreenEdge(hvec2 rayStartScreen, hvec2 rayStepScreen)
{
    // Computes the scale down factor for RayStepScreen required to fit on the X and Y axis in order to clip it in the viewport
    hfloat rayStepScreenInvFactor = 0.5 * length(rayStepScreen);
    hvec2 s = 1.0 - max(abs(rayStepScreen + rayStartScreen * rayStepScreenInvFactor) - rayStepScreenInvFactor, vec2_splat(0.0)) / abs(rayStepScreen);

    // Rescales RayStepScreen accordingly
    hfloat rayStepFactor = min(s.x, s.y) / rayStepScreenInvFactor;

    return rayStepFactor;
}

// [UE SSRTRayCast.ush InitScreenSpaceRay, IS_SSGI_SHADER variant]
// Builds a screen-space ray in (uv, deviceZ) from a unit view-space direction.
// UE works in NDC (ScreenPos); this works in UV with the same homogeneous trick:
// endClip = startClip/w + Proj * (viewDir, 0).
void InitScreenSpaceRaySSGI(hvec2 uv, hfloat deviceZ, hvec3 viewRayDirection,
                            out hvec3 rayStartUVZ, out hvec3 rayStepUVZ, out hfloat compareTolerance)
{
    // UV -> NDC (invert the ProjectViewToUVZ conventions)
    hvec2 ndcXY = uv * 2.0 - 1.0;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    ndcXY.y = -ndcXY.y;
#endif
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    hfloat ndcZ = deviceZ * 2.0 - 1.0;
#else
    hfloat ndcZ = deviceZ;
#endif

    // float4 RayEndClip = ApplyProjMatrix(float4(ViewRayDirection, 0)) + float4(RayStartScreen, 1)
    hvec4 dirClip = mul(hvec4_init(viewRayDirection.x, viewRayDirection.y, viewRayDirection.z, 0.0), cProj);
    hvec4 rayEndClip = hvec4_init(ndcXY.x + dirClip.x, ndcXY.y + dirClip.y, ndcZ + dirClip.z, 1.0 + dirClip.w);
    hvec3 rayEndNDC = rayEndClip.xyz / max(rayEndClip.w, 1.0e-4);

    // NDC -> UVZ
    hvec2 endUV = rayEndNDC.xy * 0.5 + 0.5;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    endUV.y = 1.0 - endUV.y;
#endif
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    hfloat endDeviceZ = rayEndNDC.z * 0.5 + 0.5;
#else
    hfloat endDeviceZ = rayEndNDC.z;
#endif

    rayStartUVZ = hvec3_init(uv.x, uv.y, deviceZ);
    rayStepUVZ = hvec3_init(endUV.x, endUV.y, endDeviceZ) - rayStartUVZ;

    // float3 RayDepthScreen = 0.5 * (RayStartScreen + mul(float4(0, 0, 1, 0), View.ViewToClip).xyz)
    // (UE approximation, no w divide; device-Z domain adaptation for GL below)
    hfloat unitDepthClipZ = mul(hvec4_init(0.0, 0.0, 1.0, 0.0), cProj).z;
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    unitDepthClipZ = unitDepthClipZ * 0.5 + 0.5;
#endif
    hfloat rayDepthScreenZ = 0.5 * (deviceZ + unitDepthClipZ);

    // Ray.RayStepScreen *= GetStepScreenFactorToClipAtScreenEdge(...)
    // UV offsets scale by 2 to screen units; positions by *2-1.
    hfloat clipFactor = SsgiGetStepScreenFactorToClipAtScreenEdge(rayStartUVZ.xy * 2.0 - 1.0, rayStepUVZ.xy * 2.0);
    rayStepUVZ *= clipFactor;

    // IS_SSGI_SHADER: CompareTolerance = max(abs(step.z), (start.z - depth.z) * 2)
    // (SSRTRayCast.ush:161; abs() adapts the sign to standard Z, same as SSRHiZTrace)
    compareTolerance = max(abs(rayStepUVZ.z), abs(rayStartUVZ.z - rayDepthScreenZ) * 2.0);
}

// [UE SSRTRayCast.ush CastScreenSpaceRay, IS_SSGI_SHADER && SSGI_TRACE_CONE variant]
// Exponential step distribution, HZB mip walk, discrete hit time (no depth-diff lerp).
// outLevel is the HZB/HCB mip at the end of the walk, used to sample the HCB.
// bUncertain is computed for parity with UE but — matching UE SSRTDiffuseIndirect.usf,
// where bRejectUncertainRays is never consumed — it does not reject hits.
void CastScreenSpaceRayCone(hvec3 rayStartUVZ, hvec3 rayStepUVZ, hfloat rayCompareTolerance,
                            int numSteps, hfloat stepOffset, hfloat roughness,
                            out hvec3 hitUVZ, out hfloat outLevel, out bool bHit, out bool bUncertain)
{
    hfloat step = 1.0 / hfloat_init(numSteps);
    hfloat compareTolerance = rayCompareTolerance * step;

    hfloat level = 1.0; // StartMipLevel = 1.0 (SSRTDiffuseIndirect.usf:461)

    // const float ConeAngle = PI / 4; const float d = 1; const float r = d * sin(0.5 * ConeAngle);
    // const float Exp = 1.6; //(d + r) / (d - r);
    hfloat expLog2 = 0.678071905; // log2(1.6)
    hfloat maxPower = exp2(expLog2 * (hfloat_init(numSteps) + 1.0)) - 0.9;

    hvec3 rayStepPerStep = rayStepUVZ * step;
    hvec3 rayUVZ = rayStartUVZ; // cone path: no StepOffset pre-advance (SSRTRayCast.ush:287)

    bHit = false;
    bUncertain = false;
    hitUVZ = rayStartUVZ;
    outLevel = level;

    bvec4 multipleSampleHit = bvec4(false, false, false, false);
    // UE reads the loop counter after the loop (HLSL scoping); GLSL scopes it to the
    // for-statement, so the hit batch index is snapshotted instead.
    int hitBatchIndex = 0;

    LOOP
    for (int i = 0; i < 64; i += 4)
    {
        BRANCH
        if (i >= numSteps)
            break;

        // float S = float(i + j) + StepOffset;
        // float NormalizedPower = (exp2(ExpLog2 * S) - 0.9) / MaxPower;
        // float Offset = NormalizedPower * NumSteps;
        hfloat s0 = hfloat_init(i) + stepOffset;
        hfloat offset0 = (exp2(expLog2 * (s0 + 0.0)) - 0.9) / maxPower * hfloat_init(numSteps);
        hfloat offset1 = (exp2(expLog2 * (s0 + 1.0)) - 0.9) / maxPower * hfloat_init(numSteps);
        hfloat offset2 = (exp2(expLog2 * (s0 + 2.0)) - 0.9) / maxPower * hfloat_init(numSteps);
        hfloat offset3 = (exp2(expLog2 * (s0 + 3.0)) - 0.9) / maxPower * hfloat_init(numSteps);

        hvec3 sample0 = rayUVZ + rayStepPerStep * offset0;
        hvec3 sample1 = rayUVZ + rayStepPerStep * offset1;
        hvec3 sample2 = rayUVZ + rayStepPerStep * offset2;
        hvec3 sample3 = rayUVZ + rayStepPerStep * offset3;

        hfloat mip01 = level;
        level += (8.0 / hfloat_init(numSteps)) * roughness;
        hfloat mip23 = level;
        level += (8.0 / hfloat_init(numSteps)) * roughness;

        hfloat d0 = sample0.z - SsgiSampleFarthestHZB(sample0.xy, mip01);
        hfloat d1 = sample1.z - SsgiSampleFarthestHZB(sample1.xy, mip01);
        hfloat d2 = sample2.z - SsgiSampleFarthestHZB(sample2.xy, mip23);
        hfloat d3 = sample3.z - SsgiSampleFarthestHZB(sample3.xy, mip23);
        hvec4 multipleSampleDepthDiff = hvec4_init(d0, d1, d2, d3);

        // bMultipleSampleHit = abs(Diff + Tolerance) < Tolerance (reverse Z);
        // standard-Z mirror, same as SSRHiZTrace
#ifdef REVERSED_Z
        multipleSampleHit = lessThan(abs(multipleSampleDepthDiff + hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance)), hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance));
        bvec4 multipleSampleUncertain = lessThan(multipleSampleDepthDiff + hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance), hvec4_init(-compareTolerance, -compareTolerance, -compareTolerance, -compareTolerance));
#else
        multipleSampleHit = lessThan(abs(multipleSampleDepthDiff - hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance)), hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance));
        bvec4 multipleSampleUncertain = greaterThan(multipleSampleDepthDiff - hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance), hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance));
#endif

        bHit = multipleSampleHit.x || multipleSampleHit.y || multipleSampleHit.z || multipleSampleHit.w;
        bUncertain = bUncertain || ((multipleSampleUncertain.x || multipleSampleUncertain.y || multipleSampleUncertain.z || multipleSampleUncertain.w) && !bHit);

        BRANCH
        if (bHit)
        {
            hitBatchIndex = i;
            break;
        }
    }

    outLevel = level;

    BRANCH
    if (bHit)
    {
        // float4 HitTime = bMultipleSampleHit ? float4(0, 1, 2, 3) : 4; take closest
        hfloat time1 = 4.0;
        if (multipleSampleHit.w) time1 = 3.0;
        if (multipleSampleHit.z) time1 = 2.0;
        if (multipleSampleHit.y) time1 = 1.0;
        if (multipleSampleHit.x) time1 = 0.0;

        hfloat s = hfloat_init(hitBatchIndex) + time1 + stepOffset;
        hfloat offset = (exp2(expLog2 * s) - 0.9) / maxPower * hfloat_init(numSteps);
        hitUVZ = rayUVZ + rayStepPerStep * offset;
    }
}

#endif // COMPILEPS && SSGI_TRACE_PASS
#endif // SSGI_COMMON_SH
