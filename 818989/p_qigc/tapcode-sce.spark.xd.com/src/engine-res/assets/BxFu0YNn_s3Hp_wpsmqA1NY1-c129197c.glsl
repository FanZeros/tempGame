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
#include "post_process.sh"

#ifdef COMPILEPS

uniform hvec4 u_HistogramParams;        // x = scale, y = bias, z = logMin, w = logMax
uniform hvec4 u_ExposurePercentiles;    // x = lowPercent, y = highPercent, z = blackBucketInfluence
uniform hvec4 u_ExposureSpeedParams;    // x = speedUp, y = speedDown
uniform hvec4 u_ExposureLumRange;       // x = minBrightness, y = maxBrightness
uniform hvec4 u_HistogramInvSize;

#define cHistogramLogMin            u_HistogramParams.z
#define cHistogramLogMax            u_HistogramParams.w
#define cLowPercent                 u_ExposurePercentiles.x
#define cHighPercent                u_ExposurePercentiles.y
#define cBlackBucketInfluence       u_ExposurePercentiles.z
#define cSpeedUp                    u_ExposureSpeedParams.x
#define cSpeedDown                  u_ExposureSpeedParams.y
#define cMinBrightness              u_ExposureLumRange.x
#define cMaxBrightness              u_ExposureLumRange.y
#define cHistogramInvSize           vec2(u_HistogramInvSize.xy)

#define HISTOGRAM_SIZE  64
#define HISTOGRAM_COLS  16

// Compute log-luminance for a given bin index
float ComputeLogLuminanceFromBin(int bin)
{
    return cHistogramLogMin + float(bin) / float(HISTOGRAM_SIZE - 1) * (cHistogramLogMax - cHistogramLogMin);
}

// Process one bin for percentile filtering (no array needed)
void ProcessBin(float binValue, float logLum,
                inout float minFrac, inout float maxFrac,
                inout float sumLogLum, inout float sumWeight)
{
    float sub = min(binValue, minFrac);
    binValue -= sub;
    minFrac -= sub;
    maxFrac -= sub;

    binValue = min(binValue, maxFrac);
    maxFrac -= binValue;

    sumLogLum += logLum * binValue;
    sumWeight += binValue;
}

#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

void PS()
{
    // ========================================================================
    // Stage 1: Compute total weight from reduced histogram (16x1)
    // ========================================================================
    float totalWeight = 0.0;

    LOOP for (int col = 0; col < HISTOGRAM_COLS; col++)
    {
        float u = (float(col) + 0.5) * cHistogramInvSize.x;
        vec4 bins = texture2D(sDiffMap, vec2(u, 0.5));

        // Apply black bucket influence to bin 0 (first channel of first texel)
        if (col == 0)
            bins.r *= cBlackBucketInfluence;

        totalWeight += bins.r + bins.g + bins.b + bins.a;
    }

    // ========================================================================
    // Stage 2: Percentile filtering (UE: ComputeAverageLuminanceWithoutOutlier)
    // ========================================================================
    float minFractionSum = totalWeight * cLowPercent;
    float maxFractionSum = totalWeight * cHighPercent;
    float sumLogLum = 0.0;
    float sumWeight = 0.0;

    LOOP for (int col = 0; col < HISTOGRAM_COLS; col++)
    {
        float u = (float(col) + 0.5) * cHistogramInvSize.x;
        vec4 bins = texture2D(sDiffMap, vec2(u, 0.5));
        int base = col * 4;

        // Apply black bucket influence to bin 0
        if (col == 0)
            bins.r *= cBlackBucketInfluence;

        ProcessBin(bins.r, ComputeLogLuminanceFromBin(base),     minFractionSum, maxFractionSum, sumLogLum, sumWeight);
        ProcessBin(bins.g, ComputeLogLuminanceFromBin(base + 1), minFractionSum, maxFractionSum, sumLogLum, sumWeight);
        ProcessBin(bins.b, ComputeLogLuminanceFromBin(base + 2), minFractionSum, maxFractionSum, sumLogLum, sumWeight);
        ProcessBin(bins.a, ComputeLogLuminanceFromBin(base + 3), minFractionSum, maxFractionSum, sumLogLum, sumWeight);
    }

    float avgLogLum = sumLogLum / max(sumWeight, 0.0001);
    float avgLum = exp2(avgLogLum);

    // ========================================================================
    // Stage 3: Temporal adaptation (UE: ComputeEyeAdaptation)
    // ========================================================================

    // Clamp average luminance to configured range
    float targetLum = clamp(avgLum, cMinBrightness, cMaxBrightness);

    // Target exposure: maps targetLum to 18% middle grey
    float targetExposure = targetLum / 0.18;

    // Read previous frame's adapted exposure from .g channel (persistent RT)
    float prevExposure = texture2D(sNormalMap, vec2(0.5, 0.5)).g;

    // First frame: jump to target immediately
    if (prevExposure <= 0.0)
        prevExposure = targetExposure;

    // Asymmetric adaptation speed (UE default: up=2.0, down=1.0 f-stops/s)
    float logTarget = log2(max(targetExposure, 1e-10));
    float logPrev = log2(max(prevExposure, 1e-10));
    float logDiff = logTarget - logPrev;
    float speed = logDiff > 0.0 ? cSpeedUp : cSpeedDown;

    // Exponential adaptation
    float adaptFactor = 1.0 - exp2(-cDeltaTimePS * speed);
    float logAdapted = logPrev + logDiff * adaptFactor;
    float adaptedExposure = exp2(logAdapted);

    // Output:
    //   .r = exposureScale (BloomHDR COMBINE multiplies directly)
    //   .g = adaptedExposure (temporal feedback for next frame)
    float exposureScale = 1.0 / max(adaptedExposure, 1e-10);

    gl_FragColor = vec4(exposureScale, adaptedExposure, avgLum, 0.0);
}
