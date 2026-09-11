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

uniform hvec4 u_UEExposureParams0;  // x = lowPercent, y = highPercent, z = blackBucketInfluence, w = forceTarget
uniform hvec4 u_UEExposureParams1;  // x = histogramLogMin, y = histogramLogMax, z = minAverageLum, w = maxAverageLum
uniform hvec4 u_UEExposureParams2;  // x = speedUp, y = speedDown, z = startDistance, w = exposureCompensation
uniform hvec4 u_HistogramInvSize;

#define cLowPercent             u_UEExposureParams0.x
#define cHighPercent            u_UEExposureParams0.y
#define cBlackBucketInfluence   u_UEExposureParams0.z
#define cForceTarget            u_UEExposureParams0.w
#define cHistogramLogMin        u_UEExposureParams1.x
#define cHistogramLogMax        u_UEExposureParams1.y
#define cMinAverageLum          u_UEExposureParams1.z
#define cMaxAverageLum          u_UEExposureParams1.w
#define cSpeedUp                u_UEExposureParams2.x
#define cSpeedDown              u_UEExposureParams2.y
#define cStartDistance          u_UEExposureParams2.z
#define cExposureCompensation   u_UEExposureParams2.w
#define cHistogramInvSize       vec2(u_HistogramInvSize.xy)

#define HISTOGRAM_SIZE  64
#define HISTOGRAM_COLS  16

float ComputeLogLuminanceFromBin(int bin)
{
    return cHistogramLogMin + float(bin) / float(HISTOGRAM_SIZE - 1) * (cHistogramLogMax - cHistogramLogMin);
}

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

float ExponentialAdaption(float current, float target, float frameTime, float speed, float m)
{
    float factor = 1.0 - exp2(-frameTime * speed);
    return current + (target - current) * factor * m;
}

float LinearAdaption(float current, float target, float frameTime, float speed)
{
    float offset = frameTime * speed;
    return current < target ? min(target, current + offset) : max(target, current - offset);
}

float ComputeExponentialM(float speed, float startDistance)
{
    if (speed <= 0.0 || startDistance <= 0.0)
        return 0.0;

    float frameTimeEps = 1.0 / 60.0;
    float startTime = startDistance / max(speed, 0.001);
    float denom = (1.0 - exp2(-frameTimeEps * speed)) * startTime;
    return frameTimeEps / max(denom, 1e-6);
}

float ComputeUEEyeAdaptation(float oldExposure, float targetExposure, float frameTime)
{
    float logTargetExposure = log2(max(targetExposure, 1e-10));
    float logOldExposure = log2(max(oldExposure, 1e-10));
    float logDiff = logTargetExposure - logOldExposure;
    float speed = logDiff > 0.0 ? cSpeedUp : cSpeedDown;
    float m = ComputeExponentialM(speed, cStartDistance);
    float absLogDiff = abs(logDiff);

    float logAdaptedExp = ExponentialAdaption(logOldExposure, logTargetExposure, frameTime, speed, m);
    float logAdaptedLin = LinearAdaption(logOldExposure, logTargetExposure, frameTime, speed);
    float logAdapted = absLogDiff > cStartDistance ? logAdaptedLin : logAdaptedExp;
    float adaptedExposure = exp2(logAdapted);

    return mix(adaptedExposure, targetExposure, cForceTarget);
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
    float totalWeight = 0.0;

    LOOP for (int col = 0; col < HISTOGRAM_COLS; col++)
    {
        float u = (float(col) + 0.5) * cHistogramInvSize.x;
        vec4 bins = texture2D(sDiffMap, vec2(u, 0.5));

        if (col == 0)
            bins.r *= cBlackBucketInfluence;

        totalWeight += bins.r + bins.g + bins.b + bins.a;
    }

    float minFractionSum = totalWeight * cLowPercent;
    float maxFractionSum = totalWeight * cHighPercent;
    float sumLogLum = 0.0;
    float sumWeight = 0.0;

    LOOP for (int col = 0; col < HISTOGRAM_COLS; col++)
    {
        float u = (float(col) + 0.5) * cHistogramInvSize.x;
        vec4 bins = texture2D(sDiffMap, vec2(u, 0.5));
        int base = col * 4;

        if (col == 0)
            bins.r *= cBlackBucketInfluence;

        ProcessBin(bins.r, ComputeLogLuminanceFromBin(base),     minFractionSum, maxFractionSum, sumLogLum, sumWeight);
        ProcessBin(bins.g, ComputeLogLuminanceFromBin(base + 1), minFractionSum, maxFractionSum, sumLogLum, sumWeight);
        ProcessBin(bins.b, ComputeLogLuminanceFromBin(base + 2), minFractionSum, maxFractionSum, sumLogLum, sumWeight);
        ProcessBin(bins.a, ComputeLogLuminanceFromBin(base + 3), minFractionSum, maxFractionSum, sumLogLum, sumWeight);
    }

    float avgLogLum = sumLogLum / max(sumWeight, 0.0001);
    float avgLum = exp2(avgLogLum);

    float targetAverageLum = clamp(avgLum, cMinAverageLum, cMaxAverageLum);
    float targetExposure = targetAverageLum / 0.18;
    float oldExposureScale = texture2D(sNormalMap, vec2(0.5, 0.5)).r;
    float oldExposure = cExposureCompensation / (oldExposureScale != 0.0 ? oldExposureScale : 1.0);
    float smoothedExposure = ComputeUEEyeAdaptation(oldExposure, targetExposure, cDeltaTimePS);
    smoothedExposure = clamp(smoothedExposure, cMinAverageLum / 0.18, cMaxAverageLum / 0.18);

    float smoothedExposureScale = 1.0 / max(0.0001, smoothedExposure);
    float targetExposureScale = 1.0 / max(0.0001, targetExposure);

    gl_FragColor = vec4(cExposureCompensation * smoothedExposureScale,
                        cExposureCompensation * targetExposureScale,
                        avgLum,
                        cExposureCompensation);
}
