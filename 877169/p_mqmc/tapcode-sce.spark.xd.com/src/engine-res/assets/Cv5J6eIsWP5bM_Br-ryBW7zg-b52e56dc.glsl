/*
 * SSR Linear Trace Shader
 * Performs screen-space ray marching to find reflection hits.
 *
 * Key technique: Stochastic SSR with GGX importance sampling.
 * Each pixel traces a small configurable ray set per frame with directions sampled
 * from the GGX distribution (based on roughness). A temporal filter accumulates results
 * over multiple frames to converge to the correct filtered reflection.
 *
 * Matches UE SSR ray selection: multi-ray rough reflections, but roughness below
 * 0.1 collapses to a single mirror ray with increased march precision.
 *
 * Output:
 *   RGB = Reflected color
 *   A   = Confidence (0 = no hit/use IBL fallback, 1 = perfect hit)
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

// Depth buffer (register 0)
SAMPLER2D(u_Depth0, 0);

// GBufferA - normal (register 1)
SAMPLER2D(u_Normal1, 1);

// GBufferB - metallic, specular, roughness (register 2)
SAMPLER2D(u_GBufferB2, 2);

// Render path parameters (names must match XML <parameter name="..."> with u_ prefix)
uniform hfloat u_MaxDistance;
uniform hfloat u_MaxSteps;
uniform hfloat u_Thickness;
uniform hfloat u_NumRays;
uniform hfloat u_FrameIndex;

#define MAX_ITERATIONS 64
#define MAX_SSR_RAYS 12
#define MAX_ROUGHNESS_FOR_SSR 0.5


// Sample linear depth at a screen UV
hfloat SampleLinearDepth(hvec2 uv)
{
    hfloat rawDepth = texture2D(u_Depth0, uv).r;
    return LinearizeDepth(rawDepth, cNearClipPS, cFarClipPS);
}

hvec3 SampleViewNormal(hvec2 uv)
{
    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal1, uv).rgb);
    return normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
}

hfloat CalculateHitValidationFade(hvec2 uv, hvec3 rayDir, hfloat sceneDepth)
{
    hvec2 ts = cGBufferInvSize;

    hfloat d0 = SampleLinearDepth(uv + hvec2_init(-1.0,  0.0) * ts);
    hfloat d1 = SampleLinearDepth(uv + hvec2_init( 1.0,  0.0) * ts);
    hfloat d2 = SampleLinearDepth(uv + hvec2_init( 0.0, -1.0) * ts);
    hfloat d3 = SampleLinearDepth(uv + hvec2_init( 0.0,  1.0) * ts);
    hfloat minDepth = min(min(d0, d1), min(d2, d3));
    hfloat maxDepth = max(max(d0, d1), max(d2, d3));
    hfloat depthRange = maxDepth - minDepth;

    // Reject stable silhouette hits that would otherwise smear into SSR history.
    hfloat depthThreshold = max(u_Thickness * 0.75, sceneDepth * 0.003);
    hfloat depthFade = 1.0 - saturate((depthRange - depthThreshold) / max(depthThreshold * 4.0, 0.0001));

    hvec3 centerN = SampleViewNormal(uv);
    hfloat n0 = dot(centerN, SampleViewNormal(uv + hvec2_init(-1.0,  0.0) * ts));
    hfloat n1 = dot(centerN, SampleViewNormal(uv + hvec2_init( 1.0,  0.0) * ts));
    hfloat n2 = dot(centerN, SampleViewNormal(uv + hvec2_init( 0.0, -1.0) * ts));
    hfloat n3 = dot(centerN, SampleViewNormal(uv + hvec2_init( 0.0,  1.0) * ts));
    hfloat minNormalDot = min(min(n0, n1), min(n2, n3));
    hfloat normalFade = saturate((minNormalDot - 0.55) / 0.35);

    // Only strongly back-facing hits are rejected. Near-silhouette hits are handled by depth/normal fades.
    hfloat frontFaceFade = 1.0 - saturate((dot(centerN, rayDir) - 0.15) / 0.35);

    return depthFade * normalFade * frontFaceFade;
}

// Project view-space position to screen UV
hvec2 ProjectToUV(hvec3 viewPos)
{
    return ProjectViewToUVZ(viewPos).xy;
}

// Screen-space ray march with perspective-correct 1/z depth interpolation.
// Each step advances ~1 pixel in screen space for uniform coverage.
// Two-phase: linear march (up to 64 steps) + binary refinement (4 steps)
bool ScreenSpaceTrace(hvec3 viewOrigin, hvec3 rayDir, hfloat roughness, int traceMaxSteps, hfloat stepOffset,
                      out hvec2 hitUV, out hfloat hitDepth, out hfloat confidence)
{
    hfloat thickness = u_Thickness;
    int maxSteps = traceMaxSteps;
    hfloat maxDist = u_MaxDistance;

    // Ray end in view space
    hvec3 rayEnd = viewOrigin + rayDir * maxDist;

    // Clip to near plane if ray goes behind camera (left-handed: z > 0 is forward)
    if (rayEnd.z < cNearClipPS)
    {
        if (abs(rayDir.z) < 0.0001)
            return false;
        hfloat tClip = (cNearClipPS - viewOrigin.z) / rayDir.z;
        if (tClip <= 0.0)
            return false;
        rayEnd = viewOrigin + rayDir * tClip;
    }

    // Project both endpoints to clip space
    hvec4 h0 = mul(hvec4_init(viewOrigin.x, viewOrigin.y, viewOrigin.z, 1.0), cProj);
    hvec4 h1 = mul(hvec4_init(rayEnd.x, rayEnd.y, rayEnd.z, 1.0), cProj);

    if (h0.w <= 0.0 || h1.w <= 0.0)
        return false;

    // To screen UV
    hvec2 uv0 = h0.xy / h0.w * 0.5 + 0.5;
    hvec2 uv1 = h1.xy / h1.w * 0.5 + 0.5;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    uv0.y = 1.0 - uv0.y;
    uv1.y = 1.0 - uv1.y;
#endif

    // 1/w for perspective-correct depth (compute before screen clipping)
    hfloat k0 = 1.0 / h0.w;
    hfloat k1 = 1.0 / h1.w;

    // Clip ray endpoint to visible screen bounds [0,1].
    // Critical for backward-facing rays: perspective magnification makes the
    // endpoint project far off-screen, causing each step to skip many pixels.
    {
        hvec2 uvDir = uv1 - uv0;
        hfloat tScreen = 1.0;

        if (uvDir.x > 0.0001)
            tScreen = min(tScreen, (1.0 - uv0.x) / uvDir.x);
        else if (uvDir.x < -0.0001)
            tScreen = min(tScreen, -uv0.x / uvDir.x);

        if (uvDir.y > 0.0001)
            tScreen = min(tScreen, (1.0 - uv0.y) / uvDir.y);
        else if (uvDir.y < -0.0001)
            tScreen = min(tScreen, -uv0.y / uvDir.y);

        tScreen = clamp(tScreen, 0.0, 1.0);

        uv1 = uv0 + uvDir * tScreen;
        k1 = mix(k0, k1, tScreen);
    }

    // Screen-space ray length in pixels
    hvec2 screenSize = hvec2_init(1.0, 1.0) / cGBufferInvSize;
    hvec2 deltaPixels = (uv1 - uv0) * screenSize;
    hfloat pixelDist = max(abs(deltaPixels.x), abs(deltaPixels.y));

    if (pixelDist < 1.0)
        return false;

    // ~1 pixel per step, capped at maxSteps
    int numSteps = min(int(ceil(pixelDist)), maxSteps);
    hfloat stepT = 1.0 / hfloat_init(numSteps);

    // UE ray cast offsets the first sample by StepOffset in ray-step units.
    hfloat jitterOffset = stepOffset * stepT;

    // Phase 1: Screen-space linear march
    hfloat hitParamT = -1.0;
    hfloat hitDiff = 0.0;
    hfloat lastFrontT = 0.0;

    for (int i = 1; i <= MAX_ITERATIONS && i <= numSteps; i++)
    {
        hfloat t = stepT * hfloat_init(i) + jitterOffset;
        if (t > 1.0) break;
        hvec2 sampleUV = mix(uv0, uv1, t);

        if (any(lessThan(sampleUV, vec2_splat(0.0))) || any(greaterThan(sampleUV, vec2_splat(1.0))))
            break;

        hfloat rayZ = 1.0 / mix(k0, k1, t);
        hfloat sceneZ = SampleLinearDepth(sampleUV);
        hfloat depthDiff = rayZ - sceneZ;

        if (depthDiff > 0.0 && depthDiff < thickness)
        {
            // Ray is behind surface within thickness -> valid hit
            hitParamT = t;
            hitDiff = depthDiff;
            break;
        }
        else if (depthDiff <= 0.0)
        {
            // Ray in front of surface -> track last safe position
            lastFrontT = t;
        }
        // else: depthDiff > thickness -> ray passed THROUGH a thin surface,
        // continue marching to find the actual target behind the occluder
    }

    if (hitParamT < 0.0)
        return false;

    // Phase 2: Binary refinement (8 iterations for precise hit at depth edges)
    hfloat lo = lastFrontT;
    hfloat hi = hitParamT;
    hvec2 refinedUV = mix(uv0, uv1, hitParamT);
    hfloat refinedDiff = hitDiff;

    for (int j = 0; j < 8; j++)
    {
        hfloat mid = (lo + hi) * 0.5;
        hvec2 midUV = mix(uv0, uv1, mid);
        hfloat midRayZ = 1.0 / mix(k0, k1, mid);
        hfloat midSceneZ = SampleLinearDepth(midUV);
        hfloat midDiff = midRayZ - midSceneZ;

        if (midDiff > 0.0)
        {
            hi = mid;
            refinedUV = midUV;
            refinedDiff = midDiff;
        }
        else
        {
            lo = mid;
        }
    }

    hitUV = refinedUV;
    hitDepth = texture2D(u_Depth0, refinedUV).r;

    // Confidence computation
    hfloat screenDistPx = length((refinedUV - uv0) * screenSize);
    hfloat selfIntFade = saturate((screenDistPx - 2.0) / 4.0);
    hfloat edgeFade = CalculateEdgeFade(refinedUV);
    hfloat thicknessFade = 1.0 - saturate(refinedDiff / thickness);
    hfloat distanceFade = 1.0 - saturate(hi);
    hfloat hitValidationFade = CalculateHitValidationFade(refinedUV, rayDir, SampleLinearDepth(refinedUV));

    confidence = edgeFade * thicknessFade * distanceFade * selfIntFade * hitValidationFade;
    return true;
}

void PS()
{
    hvec2 uv = vTexCoord;

    hfloat depth = texture2D(u_Depth0, uv).r;
    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal1, uv).rgb);
    hvec3 normal = normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
    hvec4 gbufferB = texture2D(u_GBufferB2, uv);
    hfloat roughness = gbufferB.b;
    hfloat metallic = gbufferB.r;

    BRANCH
    if (roughness > MAX_ROUGHNESS_FOR_SSR)
    {
        gl_FragColor = hvec4_init(0.0, 0.0, 0.0, 0.0);
        return;
    }

    hfloat specular = gbufferB.g;
    BRANCH
    if (metallic < 0.01 && specular < 0.1)
    {
        gl_FragColor = hvec4_init(0.0, 0.0, 0.0, 0.0);
        return;
    }

    // Reconstruct view-space position from depth buffer
    hvec3 viewPos = ReconstructViewPos(uv, depth);
    hvec3 viewDir = normalize(viewPos);

    // ================================================================
    // Stochastic SSR: UE-style GGX importance sampling
    // ================================================================
    hvec2 pixelCoord = uv / cGBufferInvSize;
    hvec3 V = -viewDir;
    hfloat alpha = roughness * roughness;
    int baseMaxSteps = int(u_MaxSteps);
    int numRays = int(clamp(u_NumRays, 1.0, 12.0));
    int traceMaxSteps = baseMaxSteps;

    hfloat noiseX = InterleavedGradientNoise(pixelCoord + u_FrameIndex * hvec2_init(32.665, 11.815));
    // Mix in the frame index so ray directions vary per frame and temporal accumulation
    // can converge (kept in sync with SSRHiZTrace).
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
    hfloat roughnessFade = CalculateRoughnessFade(roughness, MAX_ROUGHNESS_FOR_SSR);

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
        hfloat confidence;

        BRANCH
        if (ScreenSpaceTrace(viewPos, reflectDir, roughness, traceMaxSteps, stepOffset, hitUV, hitDepth, confidence))
        {
            hvec4 reflectSample = SampleSSRSceneColor(hitUV);
            hfloat sampleConfidence = confidence * reflectSample.a;
            hvec3 sampleRgb = max(reflectSample.rgb, hvec3_init(0.0, 0.0, 0.0)) * confidence;

            BRANCH
            if (numRays > 1)
                sampleRgb *= 1.0 / (1.0 + SsrLuminance(sampleRgb));

            accumulatedRgb += sampleRgb;
            accumulatedAlpha += sampleConfidence;
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

    gl_FragColor = hvec4_init(accumulatedRgb.x, accumulatedRgb.y, accumulatedRgb.z, accumulatedAlpha);
}

#endif
