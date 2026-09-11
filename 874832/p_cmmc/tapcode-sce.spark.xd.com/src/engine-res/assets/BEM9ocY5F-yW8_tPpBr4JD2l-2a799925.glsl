/*
 * SSR HiZ Trace Shader
 * UE-style screen-space ray cast over the UrhoX HiZ depth chain.
 *
 * This follows the practical structure of UE 5.x SSRTRayCast.ush:
 *   - Build a screen-space ray in UV + device-Z.
 *   - March a fixed number of screen-space steps.
 *   - Sample increasing HiZ mips based on roughness.
 *   - Detect hits with UE's signed tolerance test:
 *       abs(RayZ - SceneZ + CompareTolerance) < CompareTolerance
 *   - Interpolate the hit from adjacent depth differences.
 *
 * Output is pre-multiplied SSR color:
 *   RGB = reflected color * confidence
 *   A   = confidence
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
// Pull in the shared trace-pass samplers (MotionVector=4, SceneLighting=5,
// TAAHistory=6) and hit reprojection helpers from SSRCommon.sh.
#define SSR_TRACE_PASS
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

SAMPLER2D(u_Depth0, 0);
SAMPLER2D(u_Normal1, 1);
SAMPLER2D(u_GBufferB2, 2);
SAMPLER2D(u_FarthestHiZ3, 3);

uniform hfloat u_MaxDistance;
uniform hfloat u_MaxSteps;
uniform hfloat u_Thickness;
uniform hfloat u_NumRays;
uniform hfloat u_FrameIndex;

// Screen UV -> HZB UV factor (UE HZBUvFactorAndInvFactor semantics).
// The HZB is pow2half sized (RoundUpPow2(viewport)>>1), valid region = uv * factor;
// set by View::ApplyHiZSampleParameters
uniform hvec4 u_HZBUvFactor;

#define UE_SSR_MAX_ROUGHNESS 0.6
#define UE_SSR_ROUGHNESS_MASK_SCALE (-2.0 / UE_SSR_MAX_ROUGHNESS)
#define MAX_SSR_RAYS 12
#define MAX_TRACE_STEPS 64
#define MAX_HIZ_MIP 4.0

// Sample the pow2half FarthestHiZ. Mip keeps the legacy full-res chain semantics:
// legacy mip k == HZB mip k-1 (preserves the pre-M0 effective sampling resolution,
// so the trace tuning stays unchanged)
hfloat SampleFarthestHZB(hvec2 uv, hfloat legacyMip)
{
    return texture2DLod(u_FarthestHiZ3, uv * u_HZBUvFactor.xy, max(legacyMip - 1.0, 0.0)).r;
}

hvec3 SampleViewNormal(hvec2 uv)
{
    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal1, uv).rgb);
    return normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
}

#define StoreSSRTraceResult(color, confusion) \
    gl_FragData[0] = color; \
    gl_FragData[1] = hvec4_init(confusion, 0.0, 0.0, 1.0)

hfloat ClipRayToScreen(hvec2 originUV, hvec2 rayUV)
{
    hfloat t = 1.0;

    BRANCH
    if (rayUV.x > 0.0001)
        t = min(t, (1.0 - originUV.x) / rayUV.x);
    else if (rayUV.x < -0.0001)
        t = min(t, -originUV.x / rayUV.x);

    BRANCH
    if (rayUV.y > 0.0001)
        t = min(t, (1.0 - originUV.y) / rayUV.y);
    else if (rayUV.y < -0.0001)
        t = min(t, -originUV.y / rayUV.y);

    return saturate(t);
}

bool ScreenSpaceRayCastUE(hvec3 viewOrigin, hvec3 rayDir, hfloat roughness, int traceMaxSteps, hfloat stepOffset,
                          out hvec2 hitUV, out hfloat hitDepth, out hfloat hitDistance, out hfloat hitConfidence)
{
    hfloat sceneDepth = max(viewOrigin.z, cNearClipPS);
    hfloat rayDistance = sceneDepth;

    BRANCH
    if (rayDir.z < -0.0001)
        rayDistance = min(rayDistance, -0.95 * sceneDepth / rayDir.z);

    BRANCH
    if (rayDistance <= 0.0)
        return false;

    hvec3 rayEnd = viewOrigin + rayDir * rayDistance;
    hvec3 rayStartUVZ = ProjectViewToUVZ(viewOrigin);
    hvec3 rayEndUVZ = ProjectViewToUVZ(rayEnd);
    hvec3 rayStepUVZ = rayEndUVZ - rayStartUVZ;

    hfloat screenClip = ClipRayToScreen(rayStartUVZ.xy, rayStepUVZ.xy);
    rayStepUVZ *= screenClip;

    hvec2 screenSize = hvec2_init(1.0, 1.0) / cGBufferInvSize;
    hfloat pixelDist = max(abs(rayStepUVZ.x) * screenSize.x, abs(rayStepUVZ.y) * screenSize.y);
    BRANCH
    if (pixelDist < 1.0)
        return false;

    int numSteps = min(min(int(ceil(pixelDist)), traceMaxSteps), MAX_TRACE_STEPS);
    // Samples are taken in batches of 4; round numSteps up to a multiple of 4 so the
    // last batch never extrapolates past the ray end (t > 1). UE's NumSteps presets
    // are always multiples of 4, but ceil(pixelDist) is not.
    numSteps = ((numSteps + 3) / 4) * 4;
    hfloat step = 1.0 / hfloat_init(numSteps);

    hfloat rayDepthZ = ProjectViewToUVZ(viewOrigin + hvec3_init(0.0, 0.0, rayDistance)).z;
    hfloat rayCompareTolerance = max(abs(rayStepUVZ.z), abs(rayStartUVZ.z - rayDepthZ) * 4.0);
    hfloat compareTolerance = rayCompareTolerance * step;

    rayStepUVZ *= step;
    hvec3 rayUVZ = rayStartUVZ + rayStepUVZ * stepOffset;

    bool foundHit = false;
    hvec4 multipleSampleDepthDiff = hvec4_init(0.0, 0.0, 0.0, 0.0);
    bvec4 multipleSampleHit = bvec4(false, false, false, false);
    hfloat lastDiff = 0.0;
    hfloat level = 1.0;
    int hitBatchIndex = 0;

    LOOP
    for (int i = 0; i < MAX_TRACE_STEPS; i += 4)
    {
        BRANCH
        if (i >= numSteps)
            break;

        hvec3 sample0 = rayUVZ + rayStepUVZ * hfloat_init(i + 1);
        hvec3 sample1 = rayUVZ + rayStepUVZ * hfloat_init(i + 2);
        hvec3 sample2 = rayUVZ + rayStepUVZ * hfloat_init(i + 3);
        hvec3 sample3 = rayUVZ + rayStepUVZ * hfloat_init(i + 4);

        BRANCH
        if (any(lessThan(sample0.xy, vec2_splat(0.0))) || any(greaterThan(sample0.xy, vec2_splat(1.0))))
            break;

        hfloat mip01 = level;
        level += (8.0 / hfloat_init(numSteps)) * roughness;
        hfloat mip23 = level;
        level += (8.0 / hfloat_init(numSteps)) * roughness;

        hfloat d0 = sample0.z - SampleFarthestHZB(sample0.xy, clamp(mip01, 0.0, MAX_HIZ_MIP));
        hfloat d1 = sample1.z - SampleFarthestHZB(sample1.xy, clamp(mip01, 0.0, MAX_HIZ_MIP));
        hfloat d2 = sample2.z - SampleFarthestHZB(sample2.xy, clamp(mip23, 0.0, MAX_HIZ_MIP));
        hfloat d3 = sample3.z - SampleFarthestHZB(sample3.xy, clamp(mip23, 0.0, MAX_HIZ_MIP));
        multipleSampleDepthDiff = hvec4_init(d0, d1, d2, d3);

#ifdef REVERSED_Z
        multipleSampleHit = lessThan(abs(multipleSampleDepthDiff + hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance)), hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance));
#else
        multipleSampleHit = lessThan(abs(multipleSampleDepthDiff - hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance)), hvec4_init(compareTolerance, compareTolerance, compareTolerance, compareTolerance));
#endif

        foundHit = multipleSampleHit.x || multipleSampleHit.y || multipleSampleHit.z || multipleSampleHit.w;
        BRANCH
        if (foundHit)
        {
            hitBatchIndex = i;
            break;
        }

        lastDiff = multipleSampleDepthDiff.w;
    }

    BRANCH
    if (!foundHit)
        return false;

    hfloat depthDiff0 = multipleSampleDepthDiff.z;
    hfloat depthDiff1 = multipleSampleDepthDiff.w;
    hfloat time0 = 3.0;

    if (multipleSampleHit.z)
    {
        depthDiff0 = multipleSampleDepthDiff.y;
        depthDiff1 = multipleSampleDepthDiff.z;
        time0 = 2.0;
    }
    if (multipleSampleHit.y)
    {
        depthDiff0 = multipleSampleDepthDiff.x;
        depthDiff1 = multipleSampleDepthDiff.y;
        time0 = 1.0;
    }
    if (multipleSampleHit.x)
    {
        depthDiff0 = lastDiff;
        depthDiff1 = multipleSampleDepthDiff.x;
        time0 = 0.0;
    }

    time0 += hfloat_init(hitBatchIndex);
    hfloat timeLerp = saturate(depthDiff0 / (depthDiff0 - depthDiff1));
    hfloat intersectTime = time0 + timeLerp;
    hvec3 hitUVZ = rayUVZ + rayStepUVZ * intersectTime;

    BRANCH
    if (any(lessThan(hitUVZ.xy, vec2_splat(0.0))) || any(greaterThan(hitUVZ.xy, vec2_splat(1.0))))
        return false;

    // Hit thickness validation (UrhoX addition, not present in UE):
    // The x4 slope term of CompareTolerance roughly equals the full ray's device-Z span
    // at 8 steps, so once a ray crosses from in front of a floating object to behind it,
    // every sample counts as a hit — stretching spheres/cylinders into long streaks in
    // floor reflections. Re-validate the hit against the actual full-res surface depth
    // (the pow2half HZB mip0 is only half resolution, so sample the full-res depth at
    // unit0 instead for better precision) and smoothly reject hits farther than
    // u_Thickness in view space.
    hfloat surfaceZ = texture2DLod(u_Depth0, hitUVZ.xy, 0.0).r;
    BRANCH
    if (surfaceZ >= 0.9999)
        return false;

    hvec3 surfaceViewPos = ReconstructViewPos(hitUVZ.xy, surfaceZ);
    hvec3 hitViewPos = ReconstructViewPos(hitUVZ.xy, hitUVZ.z);
    hfloat surfaceDist = length(hitViewPos - surfaceViewPos);
    hitConfidence = 1.0 - smoothstep(0.0, u_Thickness, surfaceDist);
    hitConfidence *= hitConfidence;

    BRANCH
    if (hitConfidence <= 0.0)
        return false;

    hitUV = hitUVZ.xy;
    hitDepth = hitUVZ.z;
    hitDistance = length(hitViewPos - viewOrigin);
    return true;
}

void PS()
{
    hvec2 uv = vTexCoord;

    hfloat depth = texture2D(u_Depth0, uv).r;
    BRANCH
    if (depth >= 0.9999)
    {
        StoreSSRTraceResult(hvec4_init(0.0, 0.0, 0.0, 0.0), -1.0);
        return;
    }

    hvec3 normal = SampleViewNormal(uv);
    hvec4 gbufferB = texture2D(u_GBufferB2, uv);
    hfloat roughness = gbufferB.b;
    hfloat metallic = gbufferB.r;

    hfloat roughnessFade = min(roughness * UE_SSR_ROUGHNESS_MASK_SCALE + 2.0, 1.0);
    BRANCH
    if (roughnessFade <= 0.0)
    {
        StoreSSRTraceResult(hvec4_init(0.0, 0.0, 0.0, 0.0), -1.0);
        return;
    }

    hfloat specular = gbufferB.g;
    BRANCH
    if (metallic < 0.01 && specular < 0.1)
    {
        StoreSSRTraceResult(hvec4_init(0.0, 0.0, 0.0, 0.0), -1.0);
        return;
    }

    hvec3 viewPos = ReconstructViewPos(uv, depth);
    hvec3 viewDir = normalize(viewPos);
    hvec3 V = -viewDir;
    hfloat alpha = roughness * roughness;
    int baseMaxSteps = int(u_MaxSteps);
    int numRays = int(clamp(u_NumRays, 1.0, 12.0));
    int traceMaxSteps = baseMaxSteps;

    hvec2 pixelCoord = uv / cGBufferInvSize;
    hfloat noiseX = InterleavedGradientNoise(pixelCoord + u_FrameIndex * hvec2_init(32.665, 11.815));
    // UE re-randomizes the Hammersley scramble every frame via
    // Rand3DPCG16(PixelPos, StateFrameIndexMod8) so temporal accumulation converges the
    // GGX lobe. The frame index must be mixed in here, otherwise each pixel traces the
    // same ray directions forever and the noise becomes a static streak pattern.
    hfloat randomX = SsrHash13(hvec3_init(pixelCoord.x, pixelCoord.y, u_FrameIndex));
    hfloat randomY = SsrHash13(hvec3_init(pixelCoord.y + 17.0, pixelCoord.x + 43.0, u_FrameIndex));
    hvec3 tangentV = UEWorldToTangent(V, normal);

    BRANCH
    if (numRays > 1 && roughness < 0.1)
    {
        traceMaxSteps = min(baseMaxSteps * numRays, 24);
        numRays = 1;
    }

    hvec3 accumulatedRgb = hvec3_init(0.0, 0.0, 0.0);
    hfloat accumulatedAlpha = 0.0;
    hfloat closestHitDistance = 1.0e20;

    LOOP
    for (int rayIndex = 0; rayIndex < MAX_SSR_RAYS; rayIndex++)
    {
        BRANCH
        if (rayIndex >= numRays)
            break;

        hfloat stepOffset = noiseX - 0.5;
        hvec2 xi = HammersleyFloat(rayIndex, numRays, randomX, randomY);
        xi.y *= 1.0 - SSR_GGX_IMPORTANT_SAMPLE_BIAS;
        hvec3 H = UETangentToWorld(ImportanceSampleVisibleGGX(xi, alpha, tangentV), normal);
        hvec3 reflectDir = 2.0 * dot(V, H) * H - V;

        BRANCH
        if (roughness < 0.1)
            reflectDir = reflect(-V, normal);

        hvec2 hitUV;
        hfloat hitDepth;
        hfloat hitDistance;
        hfloat hitConfidence;
        BRANCH
        if (ScreenSpaceRayCastUE(viewPos, reflectDir, roughness, traceMaxSteps, stepOffset, hitUV, hitDepth, hitDistance, hitConfidence))
        {
            hvec4 reflectSample = SampleSSRSceneColor(hitUV);
            hfloat sampleConfidence = reflectSample.a * hitConfidence;
            hvec3 sampleRgb = max(reflectSample.rgb, hvec3_init(0.0, 0.0, 0.0)) * hitConfidence;

            BRANCH
            if (numRays > 1)
                sampleRgb *= 1.0 / (1.0 + SsrLuminance(sampleRgb));

            accumulatedRgb += sampleRgb;
            accumulatedAlpha += sampleConfidence;
            closestHitDistance = min(closestHitDistance, hitDistance);
        }
    }

    hfloat invNumRays = 1.0 / hfloat_init(numRays);
    accumulatedRgb *= invNumRays;
    accumulatedAlpha *= invNumRays;

    BRANCH
    if (numRays > 1)
        accumulatedRgb *= 1.0 / max(1.0 - SsrLuminance(accumulatedRgb), 0.001);

    accumulatedRgb *= roughnessFade;
    accumulatedAlpha *= roughnessFade;

    hfloat outputConfusion = closestHitDistance < 1.0e19 ? closestHitDistance / max(length(viewPos) + closestHitDistance, 0.0001) : -1.0;
    StoreSSRTraceResult(hvec4_init(accumulatedRgb.x, accumulatedRgb.y, accumulatedRgb.z, accumulatedAlpha), outputConfusion);
}

#endif
