/*
 * XeGTAO — Ground Truth Ambient Occlusion
 *
 * Faithful port of Intel's XeGTAO (GameTechDev/XeGTAO, MIT License).
 * Reference: XeGTAO.hlsli — XeGTAO_MainPass()
 *
 * Key features ported from XeGTAO:
 *   - Per-slice projected normal angle (paper lines 8-15)
 *   - Full cosine-weighted visibility integral: IntegrateArc(h, n)
 *   - Distance falloff via lerp-to-lowHorizon (not angle scaling)
 *   - Power-distributed sampling (focus near center for small crevices)
 *   - Screen-space pixel radius from projection matrix
 *
 * Differences from XeGTAO:
 *   - Pixel shader instead of compute shader
 *   - Uses engine HiZ (min-depth mip) instead of weighted-average depth mip
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
#include "ScreenSpace/SSAO/GTAOCommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

// GBufferA - encoded normal (register 0)
SAMPLER2D(u_Normal0, 0);

// ClosestHiZ mipmapped texture (register 1). Pow2half HZB: mip0 is half resolution,
// sampling must multiply by u_HZBUvFactor (screen UV -> HZB UV)
SAMPLER2D(u_ClosestHiZ1, 1);

// Full-res depth buffer (register 2): fine samples (legacy mip0 semantics) read it directly
SAMPLER2D(u_Depth2, 2);

// Screen UV -> HZB UV factor (UE HZBUvFactorAndInvFactor semantics),
// set by View::ApplyHiZSampleParameters
uniform hvec4 u_HZBUvFactor;

// Render path parameters
uniform hfloat u_AORadius;      // World-space effect radius (before XeGTAO multiplier)
uniform hfloat u_AOIntensity;   // Final value power (XeGTAO default: 2.2)
uniform hfloat u_AOBias;        // Reserved (unused in XeGTAO algorithm)
uniform hfloat u_FrameIndex;    // Temporal frame index (0-7) for noise rotation

// Quality presets (slices x steps):
//   Low    = 1 x 2
//   Medium = 2 x 2
//   High   = 3 x 3  (recommended, requires temporal denoise)
//   Ultra  = 9 x 3  (clean single-frame, no temporal needed)
#define AO_SLICES 3
#define AO_STEPS  3
#define USE_HIZ   1

// Sample depth by legacy full-res mip semantics:
// legacy mip k == pow2half HZB mip k-1 (preserves the pre-M0 effective sampling
// resolution, so the XeGTAO tuning stays unchanged).
// mip 0 -> full-res depth directly; mip k>0 -> HZB mip k-1 with the UV factor.
hfloat SampleHiZ(hvec2 uv, int mipLevel)
{
    if (mipLevel <= 0)
        return texture2DLod(u_Depth2, uv, 0.0).r;
    return texture2DLod(u_ClosestHiZ1, uv * u_HZBUvFactor.xy, hfloat_init(mipLevel - 1)).r;
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 pixelCoord = uv / cGBufferInvSize;

    hfloat rawDepth = SampleHiZ(uv, 0);

    // Skip sky/background
    if (rawDepth > 0.99999)
    {
        gl_FragColor = hvec4_init(1.0, 1.0, 1.0, 1.0);
        return;
    }

    // ================================================================
    // 1. Reconstruct view-space position and normal
    // ================================================================
    hvec3 pixCenterPos = ReconstructViewPos(uv, rawDepth);
    hfloat viewspaceZ = pixCenterPos.z;  // left-handed: z positive forward

    hvec3 viewVec = normalize(-pixCenterPos);

    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal0, uv).rgb);
    hvec3 viewspaceNormal = normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);

    // ================================================================
    // 2. Screen-space radius from world-space effect radius
    // ================================================================
    // XeGTAO: effectRadius = user_radius * RadiusMultiplier
    hfloat effectRadius = u_AORadius * XE_GTAO_RADIUS_MULTIPLIER;

    // XeGTAO: screenspaceRadius = effectRadius / (viewspaceZ * pixelSizeInViewspace)
    // pixelSizeInViewspace = viewspaceZ * (2.0 / proj[0][0]) * (1/screenWidth)
    // => screenspaceRadius = effectRadius / viewspaceZ * proj[0][0] * 0.5 / cGBufferInvSize.x
    hfloat screenspaceRadius = effectRadius / viewspaceZ
                             * cProj[0][0] * 0.5 / cGBufferInvSize.x;

    // Early out: too small on screen (XeGTAO: fade + skip)
    if (screenspaceRadius < 2.0)
    {
        gl_FragColor = hvec4_init(1.0, 1.0, 1.0, 1.0);
        return;
    }

    // XeGTAO: minimum sample distance to avoid sampling center pixel
    hfloat minS = XE_GTAO_PIXEL_TOO_CLOSE_THRESHOLD / screenspaceRadius;

    // ================================================================
    // 3. Distance falloff precomputation (XeGTAO linear ramp)
    // ================================================================
    // At dist = falloffFrom: weight = 1.0
    // At dist = effectRadius: weight = 0.0
    hfloat falloffRange = XE_GTAO_FALLOFF_RANGE * effectRadius;
    hfloat falloffFrom  = effectRadius * (1.0 - XE_GTAO_FALLOFF_RANGE);
    hfloat falloffMul = -1.0 / falloffRange;
    hfloat falloffAdd = falloffFrom / falloffRange + 1.0;

    // ================================================================
    // 4. Noise — Hilbert curve + R2 quasi-random sequence (XeGTAO original)
    // ================================================================
    // XeGTAO: Hilbert curve maps 2D pixel coords to 1D with excellent
    // spatial distribution (neighboring pixels → very different indices).
    // R2 sequence provides 2D quasi-random jitter with temporal variation.
    hvec2 localNoise = XeGTAO_SpatioTemporalNoise(int(pixelCoord.x), int(pixelCoord.y), int(u_FrameIndex));
    hfloat noiseSlice  = localNoise.x;
    hfloat noiseSample = localNoise.y;

    // ================================================================
    // 5. Main slice loop (XeGTAO_MainPass core)
    // ================================================================
    hfloat visibility = 0.0;

    for (int slice = 0; slice < AO_SLICES; slice++)
    {
        // XeGTAO: slice angle with noise jitter, covering [0, PI)
        hfloat phi = (hfloat_init(slice) + noiseSlice) / hfloat_init(AO_SLICES) * PI;
        hfloat cosPhi = cos(phi);
        hfloat sinPhi = sin(phi);

        // View-space direction in the slice plane (XeGTAO: directionVec)
        hvec3 directionVec = hvec3_init(cosPhi, sinPhi, 0.0);

        // Screen-space sampling direction
        // D3D11: screen Y is down, view Y is up => negate sinPhi
        // GL: screen Y is up, view Y is up => no negation
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
        hvec2 omega = hvec2_init(cosPhi, -sinPhi);
#else
        hvec2 omega = hvec2_init(cosPhi, sinPhi);
#endif

        // ============================================================
        // Projected normal computation (XeGTAO paper lines 8-15)
        // ============================================================
        // Line 9: remove component along view direction
        hvec3 orthoDirectionVec = directionVec
            - dot(directionVec, viewVec) * viewVec;

        // Line 10: axis perpendicular to both slice direction and view
        hvec3 axisVec = normalize(cross(orthoDirectionVec, viewVec));

        // Line 11: project normal onto slice plane
        hvec3 projectedNormalVec = viewspaceNormal
            - axisVec * dot(viewspaceNormal, axisVec);

        // Line 13-14: projected normal angle
        hfloat projectedNormalVecLength = length(projectedNormalVec);
        hfloat signNorm = sign(dot(orthoDirectionVec, projectedNormalVec));
        hfloat cosNorm = saturate(dot(projectedNormalVec, viewVec)
            / max(projectedNormalVecLength, 0.0001));
        hfloat n = signNorm * XeGTAO_FastACos(cosNorm);

        // ============================================================
        // Initial horizon at tangent plane (XeGTAO: lowHorizonCos)
        // ============================================================
        hfloat lowHorizonCos0 = cos(n + HALF_PI);   // = -sin(n)
        hfloat lowHorizonCos1 = cos(n - HALF_PI);   // =  sin(n)
        hfloat horizonCos0 = lowHorizonCos0;
        hfloat horizonCos1 = lowHorizonCos1;

        // ============================================================
        // Per-step horizon search (XeGTAO inner loop)
        // ============================================================
        for (int step = 0; step < AO_STEPS; step++)
        {
            // XeGTAO: R1 quasi-random step noise (golden ratio offset)
            hfloat stepBaseNoise = hfloat_init(slice + step * AO_SLICES)
                * 0.6180339887;
            hfloat stepNoise = fract(noiseSample + stepBaseNoise);

            // Sample position with power distribution
            // XeGTAO: SampleDistributionPower = 2.0 (focus near center)
            hfloat s = (hfloat_init(step) + stepNoise) / hfloat_init(AO_STEPS);
            s *= s;   // pow(s, 2.0)
            s += minS;

            // Screen-space offset in pixels
            hvec2 sampleOffset = s * omega * screenspaceRadius;
            hfloat sampleOffsetLength = length(sampleOffset);

            // MIP level selection (XeGTAO: DepthMIPSamplingOffset)
            int mipLevel = 0;
#if USE_HIZ
            mipLevel = int(clamp(
                log2(sampleOffsetLength) - XE_GTAO_DEPTH_MIP_SAMPLING_OFFSET,
                0.0, 3.0));
#endif

            // Snap to pixel center and convert to UV
            hvec2 uvOffset = round(sampleOffset) * cGBufferInvSize.xy;

            hvec2 sampleUV0 = uv + uvOffset;  // positive direction
            hvec2 sampleUV1 = uv - uvOffset;  // negative direction

            // --- Positive direction ---
            if (all(greaterThanEqual(sampleUV0, vec2_splat(0.0))) &&
                all(lessThanEqual(sampleUV0, vec2_splat(1.0))))
            {
                hfloat sd0 = SampleHiZ(sampleUV0, mipLevel);
                hvec3 sp0 = ReconstructViewPos(sampleUV0, sd0);
                hvec3 delta0 = sp0 - pixCenterPos;
                hfloat dist0 = length(delta0);
                hvec3 horizonDir0 = delta0 / max(dist0, 0.0001);

                // XeGTAO: falloff via lerp to lowHorizon (not angle scaling)
                hfloat weight0 = saturate(dist0 * falloffMul + falloffAdd);
                hfloat shc0 = dot(horizonDir0, viewVec);
                shc0 = mix(lowHorizonCos0, shc0, weight0);
                horizonCos0 = max(horizonCos0, shc0);
            }

            // --- Negative direction ---
            if (all(greaterThanEqual(sampleUV1, vec2_splat(0.0))) &&
                all(lessThanEqual(sampleUV1, vec2_splat(1.0))))
            {
                hfloat sd1 = SampleHiZ(sampleUV1, mipLevel);
                hvec3 sp1 = ReconstructViewPos(sampleUV1, sd1);
                hvec3 delta1 = sp1 - pixCenterPos;
                hfloat dist1 = length(delta1);
                hvec3 horizonDir1 = delta1 / max(dist1, 0.0001);

                hfloat weight1 = saturate(dist1 * falloffMul + falloffAdd);
                hfloat shc1 = dot(horizonDir1, viewVec);
                shc1 = mix(lowHorizonCos1, shc1, weight1);
                horizonCos1 = max(horizonCos1, shc1);
            }
        }

        // ============================================================
        // Visibility integral — IntegrateArc (XeGTAO paper Eq. 10)
        // ============================================================
        // XeGTAO: fudge factor to reduce overdarkening on slopes
        projectedNormalVecLength = mix(projectedNormalVecLength, 1.0, 0.05);

        // Convert horizon cosines to angles
        // horizonCos0 = positive omega direction, horizonCos1 = negative omega direction
        hfloat h0 = -XeGTAO_FastACos(horizonCos1);
        hfloat h1 =  XeGTAO_FastACos(horizonCos0);

        hfloat sinN = sin(n);

        // IntegrateArc(h, n) = (cos(n) + 2*h*sin(n) - cos(2*h - n)) / 4
        hfloat iarc0 = (cosNorm + 2.0 * h0 * sinN - cos(2.0 * h0 - n)) / 4.0;
        hfloat iarc1 = (cosNorm + 2.0 * h1 * sinN - cos(2.0 * h1 - n)) / 4.0;

        // Weight by projected normal length
        hfloat localVisibility = projectedNormalVecLength * (iarc0 + iarc1);
        visibility += localVisibility;
    }

    // Average across all slices
    visibility /= hfloat_init(AO_SLICES);

    // XeGTAO: final value power curve (default 2.2, exposed as u_AOIntensity)
    visibility = pow(visibility, u_AOIntensity);

    // XeGTAO: minimum visibility to prevent total blackness
    visibility = max(0.03, visibility);

    gl_FragColor = hvec4_init(visibility, visibility, visibility, 1.0);
}

#endif
