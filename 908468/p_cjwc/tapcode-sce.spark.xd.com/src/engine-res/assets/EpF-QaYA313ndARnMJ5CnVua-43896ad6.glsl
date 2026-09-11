/*
 * SSR Temporal Denoise (UE4 SSRTemporalAAPS)
 *
 * Exact match of PostProcessTemporalCommon.usf SSR configuration:
 *   AA_FILTERED=1  — Blackman-Harris 3x3 spatially filtered current frame
 *   AA_LOWPASS=1   — wide Blackman-Harris (scale*0.25) as AABB clamp target
 *   AA_ROUND=1     — variance-based neighborhood bounds (mu +/- sigma, 8 samples)
 *   AA_AABB=1      — ray-AABB intersection clamp on RGB only toward FilteredLow
 *   AA_ALPHA=0     — alpha treated as data, filtered with color (no separate clamp)
 *   AA_TONE=1      — HDR perceptual weighting (HdrWeight4 on full float4)
 *   AA_LERP=8      — fixed 12.5% blend
 *   AA_CROSS=0     — direct motion vector sample (no closest-depth dilation)
 *
 * SSR uses pre-multiplied alpha (RGB = color * confidence, A = confidence).
 * All 4 channels scale uniformly by HdrWeight, matching UE4.
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

// Current frame SSR trace result (register 0)
SAMPLER2D(u_SSRCurrent0, 0);
// Previous frame temporal output (register 1)
SAMPLER2D(u_SSRHistory1, 1);
// Motion vector buffer (register 2)
SAMPLER2D(u_MotionVector2, 2);

// Render path parameter (UE4: 1/AA_LERP = 1/8 = 0.125)
uniform hfloat u_TemporalBlend;

// TAA jitter offset in pixel space (±0.5 pixels), set by C++ View per frame
uniform hvec2 u_JitterOffset;


// ============================================================
// UE4 perceptual luminance and HDR weighting
// ============================================================
hfloat Luma4(hvec3 c)
{
    return c.g * 2.0 + c.r + c.b;
}

hfloat HdrWeight(hvec3 c)
{
    return 1.0 / (Luma4(c) + 4.0);
}

// ============================================================
// UE4 Blackman-Harris kernel weight (PostProcessTemporalAA.cpp)
// ============================================================
// Exponential fit to Blackman-Harris 3.3:
//   weight = exp(-2.29 * ||(offset - jitter) * scale||^2)
hfloat BhWeight(hvec2 sampleOffset, hvec2 jitter, hfloat scale)
{
    hvec2 d = (sampleOffset - jitter) * scale;
    return exp(-2.29 * dot(d, d));
}

// ============================================================
// UE4 IntersectAABB + HistoryClamp
// ============================================================
hfloat IntersectAABB(hvec3 dir, hvec3 org, hvec3 scale)
{
    hvec3 rcpDir = hvec3_init(1.0, 1.0, 1.0) / (dir + sign(dir) * hvec3_init(0.00001, 0.00001, 0.00001));
    hvec3 tNeg = ( scale - org) * rcpDir;
    hvec3 tPos = (-scale - org) * rcpDir;
    return max(max(min(tNeg.x, tPos.x), min(tNeg.y, tPos.y)), min(tNeg.z, tPos.z));
}

hfloat HistoryClamp(hvec3 history, hvec3 target, hvec3 nmin, hvec3 nmax)
{
    hvec3 dir = target - history;
    if (dot(dir, dir) < 0.00001)
        return 0.0;

    // UE4 exact: AABB = variance bounds only, NOT expanded to include target
    hvec3 extent = (nmax - nmin) * 0.5;
    hvec3 center = nmin + extent;
    hvec3 org = history - center;
    return clamp(IntersectAABB(dir, org, extent), 0.0, 1.0);
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 ts = cGBufferInvSize;

    // ================================================================
    // 1. Sample 3x3 neighborhood (9 taps)
    // ================================================================
    hvec4 s0 = texture2D(u_SSRCurrent0, uv + hvec2_init(-1.0, -1.0) * ts);
    hvec4 s1 = texture2D(u_SSRCurrent0, uv + hvec2_init( 0.0, -1.0) * ts);
    hvec4 s2 = texture2D(u_SSRCurrent0, uv + hvec2_init( 1.0, -1.0) * ts);
    hvec4 s3 = texture2D(u_SSRCurrent0, uv + hvec2_init(-1.0,  0.0) * ts);
    hvec4 s4 = texture2D(u_SSRCurrent0, uv);
    hvec4 s5 = texture2D(u_SSRCurrent0, uv + hvec2_init( 1.0,  0.0) * ts);
    hvec4 s6 = texture2D(u_SSRCurrent0, uv + hvec2_init(-1.0,  1.0) * ts);
    hvec4 s7 = texture2D(u_SSRCurrent0, uv + hvec2_init( 0.0,  1.0) * ts);
    hvec4 s8 = texture2D(u_SSRCurrent0, uv + hvec2_init( 1.0,  1.0) * ts);

    // ================================================================
    // 2. HDR perceptual weighting (AA_TONE=1, UE4 HdrWeight4)
    // ================================================================
    // Full float4: pre-multiplied RGB and alpha all scale by same factor.
    s0 *= HdrWeight(s0.rgb);
    s1 *= HdrWeight(s1.rgb);
    s2 *= HdrWeight(s2.rgb);
    s3 *= HdrWeight(s3.rgb);
    s4 *= HdrWeight(s4.rgb);
    s5 *= HdrWeight(s5.rgb);
    s6 *= HdrWeight(s6.rgb);
    s7 *= HdrWeight(s7.rgb);
    s8 *= HdrWeight(s8.rgb);

    // ================================================================
    // 3. Blackman-Harris spatial filter (AA_FILTERED=1)
    // ================================================================
    // UE4 PostProcessTemporalAA.cpp: exp(-2.29 * d²) with Sharpness=1.0.
    // Kernel recentered each frame based on TAA jitter offset.
    // scale = 1.0 + Sharpness * 0.5 = 1.5
    hvec2 jitter = u_JitterOffset;
    hfloat bhS = 1.5;

    hfloat wf0 = BhWeight(hvec2_init(-1.0, -1.0), jitter, bhS);
    hfloat wf1 = BhWeight(hvec2_init( 0.0, -1.0), jitter, bhS);
    hfloat wf2 = BhWeight(hvec2_init( 1.0, -1.0), jitter, bhS);
    hfloat wf3 = BhWeight(hvec2_init(-1.0,  0.0), jitter, bhS);
    hfloat wf4 = BhWeight(hvec2_init( 0.0,  0.0), jitter, bhS);
    hfloat wf5 = BhWeight(hvec2_init( 1.0,  0.0), jitter, bhS);
    hfloat wf6 = BhWeight(hvec2_init(-1.0,  1.0), jitter, bhS);
    hfloat wf7 = BhWeight(hvec2_init( 0.0,  1.0), jitter, bhS);
    hfloat wf8 = BhWeight(hvec2_init( 1.0,  1.0), jitter, bhS);

    hfloat totalF = wf0+wf1+wf2+wf3+wf4+wf5+wf6+wf7+wf8;
    hfloat invF = 1.0 / totalF;
    hvec4 filtered = (s0*wf0 + s1*wf1 + s2*wf2
                   + s3*wf3 + s4*wf4 + s5*wf5
                   + s6*wf6 + s7*wf7 + s8*wf8) * invF;

    // ================================================================
    // 4. Wide lowpass filter (AA_LOWPASS=1, AABB clamp target)
    // ================================================================
    // UE4: same Blackman-Harris but with coordinates * 0.25 → much wider.
    // scaleLP = scale * 0.25 = 0.375
    hfloat bhL = bhS * 0.25;

    hfloat wl0 = BhWeight(hvec2_init(-1.0, -1.0), jitter, bhL);
    hfloat wl1 = BhWeight(hvec2_init( 0.0, -1.0), jitter, bhL);
    hfloat wl2 = BhWeight(hvec2_init( 1.0, -1.0), jitter, bhL);
    hfloat wl3 = BhWeight(hvec2_init(-1.0,  0.0), jitter, bhL);
    hfloat wl4 = BhWeight(hvec2_init( 0.0,  0.0), jitter, bhL);
    hfloat wl5 = BhWeight(hvec2_init( 1.0,  0.0), jitter, bhL);
    hfloat wl6 = BhWeight(hvec2_init(-1.0,  1.0), jitter, bhL);
    hfloat wl7 = BhWeight(hvec2_init( 0.0,  1.0), jitter, bhL);
    hfloat wl8 = BhWeight(hvec2_init( 1.0,  1.0), jitter, bhL);

    hfloat totalL = wl0+wl1+wl2+wl3+wl4+wl5+wl6+wl7+wl8;
    hfloat invL = 1.0 / totalL;
    hvec4 filteredLow = (s0*wl0 + s1*wl1 + s2*wl2
                      + s3*wl3 + s4*wl4 + s5*wl5
                      + s6*wl6 + s7*wl7 + s8*wl8) * invL;

    // ================================================================
    // 5. Variance bounds (AA_ROUND=1: mu +/- sigma, 8 samples)
    // ================================================================
    // UE4 uses 8 samples (Neighbor0..7), excluding Neighbor8 (bottom-right corner).
    hvec4 m1 = s0 + s1 + s2 + s3 + s4 + s5 + s6 + s7;
    hvec4 m2 = s0*s0 + s1*s1 + s2*s2 + s3*s3 + s4*s4 + s5*s5 + s6*s6 + s7*s7;
    hvec4 mu = m1 / 8.0;
    hvec4 sigma = sqrt(max(m2 / 8.0 - mu * mu, vec4_splat(0.0)));
    hvec4 nmin = mu - sigma;
    hvec4 nmax = mu + sigma;

    // ================================================================
    // 6. History fetch + HDR weight (AA_CROSS=0: direct sample)
    // ================================================================
    hvec2 motionVec = texture2D(u_MotionVector2, uv).rg;
    hvec2 historyUV = uv - motionVec;
    bool historyValid = all(greaterThanEqual(historyUV, vec2_splat(0.0)))
                     && all(lessThanEqual(historyUV, vec2_splat(1.0)));

    hvec4 history;
    if (historyValid)
    {
        history = texture2D(u_SSRHistory1, historyUV);
        history *= HdrWeight(history.rgb);

        // ============================================================
        // 7. AABB clamp toward FilteredLow (AA_AABB=1)
        // ============================================================
        // UE4: OutColor.rgb = lerp(OutColor.rgb, FilteredLow.rgb, ClampBlend)
        // RGB only — alpha is not modified by the clamp.
        hfloat clampBlend = HistoryClamp(history.rgb, filteredLow.rgb, nmin.rgb, nmax.rgb);
        history.rgb = mix(history.rgb, filteredLow.rgb, clampBlend);
    }
    else
    {
        history = filtered;
    }

    // ================================================================
    // 8. Fixed 12.5% lerp blend (AA_LERP=8)
    // ================================================================
    hfloat blendFactor = historyValid ? u_TemporalBlend : 1.0;
    hvec4 result = mix(history, filtered, blendFactor);

    // ================================================================
    // 9. Inverse HDR weight + NaN protection
    // ================================================================
    // UE4 HdrWeightInv4: 4.0 * rcp(Luma4(C) * (-E) + 1.0) = 4.0 / (1.0 - Luma4(C))
    // Clamp denominator to 1/32 (matching UE4) to limit max amplification to 128x.
    result *= 4.0 / max(1.0 - Luma4(result.rgb), 0.03125);

    // NaN protection (AA_NAN=1)
    result = max(result, vec4_splat(0.0));

    gl_FragColor = result;
}

#endif
