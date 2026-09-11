/*
 * SSGI temporal accumulation (half resolution).
 *
 * UrhoX deviation from UE SSDTemporalAccumulation.usf, interim — the UE pass depends on
 * the whole SSD signal-encoding framework; this reuses the SSRDenoiseTemporal structure
 * (sample-count driven blend + 1.5 sigma variance clamp) until M3 aligns it. The
 * bilateral history rejection follows UE's BILATERAL_PRESET_DIFFUSE semantics instead of
 * the reflections Tokuyoshi weight: plane-distance depth term + pow(NoN, 4) normal term
 * (SSDSpatialKernel.ush:351, SSDSignalFramework.ush:546-552).
 *
 * Signal layout:
 *   color RT: rgb = bounce radiance, a = ambient visibility (filtered together)
 *   meta RT:  r = temporal sample count, g = closest hit distance (min-carried)
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
#include "ScreenSpace/ScreenSpaceCommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

SAMPLER2D(u_CurrentColor0, 0);
SAMPLER2D(u_CurrentHitDistance1, 1);
SAMPLER2D(u_HistoryColor2, 2);
SAMPLER2D(u_HistoryMeta3, 3);
SAMPLER2D(u_MotionVector4, 4);
SAMPLER2D(u_Depth5, 5);
SAMPLER2D(u_Normal6, 6);

uniform hfloat u_TemporalBlend;

#define StoreTemporalResult(color, meta) \
    gl_FragData[0] = color; \
    gl_FragData[1] = meta

hvec3 SampleViewPos(hvec2 uv)
{
    return ReconstructViewPos(uv, texture2D(u_Depth5, uv).r);
}

hvec3 SampleViewNormal(hvec2 uv)
{
    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal6, uv).rgb);
    return normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
}

hvec4 ClampHistoryToVarianceBoundary(hvec2 uv, hvec4 historyColor)
{
    hvec4 sum = vec4_splat(0.0);
    hvec4 sumSq = vec4_splat(0.0);

    LOOP
    for (int y = -1; y <= 1; y++)
    {
        LOOP
        for (int x = -1; x <= 1; x++)
        {
            hvec2 sampleUV = uv + hvec2_init(hfloat_init(x), hfloat_init(y)) * cGBufferInvSize.xy;
            sampleUV = clamp(sampleUV, vec2_splat(0.0), vec2_splat(1.0));
            hvec4 sampleColor = texture2D(u_CurrentColor0, sampleUV);
            sum += sampleColor;
            sumSq += sampleColor * sampleColor;
        }
    }

    hvec4 mean = sum * (1.0 / 9.0);
    hvec4 variance = max(sumSq * (1.0 / 9.0) - mean * mean, vec4_splat(0.0));
    hvec4 sigma = sqrt(variance);
    hvec4 minColor = mean - sigma * 1.5;
    hvec4 maxColor = mean + sigma * 1.5;
    return clamp(historyColor, minColor, maxColor);
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec4 currentColor = texture2D(u_CurrentColor0, uv);
    hfloat currentHitDistance = texture2D(u_CurrentHitDistance1, uv).r;

    hfloat depth = texture2D(u_Depth5, uv).r;
    BRANCH
    if (depth >= 0.9999)
    {
        StoreTemporalResult(currentColor, hvec4_init(1.0, currentHitDistance, 0.0, 1.0));
        return;
    }

    hvec2 historyUV = uv - texture2D(u_MotionVector4, uv).rg;
    bool historyValid = all(greaterThanEqual(historyUV, vec2_splat(0.0))) && all(lessThanEqual(historyUV, vec2_splat(1.0)));

    hvec4 historyColor = currentColor;
    hvec4 historyMeta = hvec4_init(0.0, -1.0, 0.0, 1.0);
    BRANCH
    if (historyValid)
    {
        historyColor = texture2D(u_HistoryColor2, historyUV);
        historyMeta = texture2D(u_HistoryMeta3, historyUV);
        historyValid = historyMeta.r > 0.0;
    }

    BRANCH
    if (!historyValid)
    {
        StoreTemporalResult(currentColor, hvec4_init(1.0, currentHitDistance, 0.0, 1.0));
        return;
    }

    hvec3 currentViewPos = SampleViewPos(uv);
    hvec3 currentNormal = SampleViewNormal(uv);
    hvec3 historyViewPos = SampleViewPos(historyUV);
    hvec3 historyNormal = SampleViewNormal(historyUV);

    // BILATERAL_PRESET_DIFFUSE semantics: plane-distance depth term + pow(NoN, 4)
    hfloat depthDelta = abs(currentViewPos.z - historyViewPos.z);
    hfloat depthWeight = saturate(1.0 - depthDelta / max(currentViewPos.z * 0.02, 0.02));
    hfloat NoN = max(dot(currentNormal, historyNormal), 0.0);
    hfloat normalWeight = NoN * NoN * NoN * NoN;
    hfloat historyWeight = depthWeight * normalWeight;

    historyColor = ClampHistoryToVarianceBoundary(uv, historyColor);

    // Sample-count driven accumulation with u_TemporalBlend as the responsiveness floor
    // (same scheme as SSRDenoiseTemporal).
    hfloat historySampleCount = min(historyMeta.r, 32.0);
    hfloat currentBlend = saturate(max(u_TemporalBlend, 1.0 / (1.0 + historySampleCount)) + (1.0 - historyWeight));
    hvec4 outColor = mix(historyColor, currentColor, currentBlend);
    hfloat outSampleCount = min(historySampleCount * historyWeight + 1.0, 32.0);

    // Carry the closest hit distance for the M3 spatial reconstruction kernel.
    hfloat outHitDistance = currentHitDistance;
    BRANCH
    if (historyMeta.g > 0.0 && currentHitDistance > 0.0)
        outHitDistance = min(historyMeta.g, currentHitDistance);
    else if (historyMeta.g > 0.0)
        outHitDistance = historyMeta.g;

    StoreTemporalResult(max(outColor, vec4_splat(0.0)), hvec4_init(outSampleCount, outHitDistance, 0.0, 1.0));
}

#endif // COMPILEPS
