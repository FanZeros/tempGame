/*
 * Reflections denoiser pre-convolution stage.
 * UE default r.Reflections.Denoiser.PreConvolution is 1, so this is the
 * single history-layout spatial pass after reconstruction.
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

#include "ScreenSpace/SSR/SSRDenoiseCommon.sh"

// Scene samplers (depth=5, normal=6, gbufferB=7) come from SSRDenoiseCommon.sh.
SAMPLER2D(u_SSRHistoryColor0, 0);
SAMPLER2D(u_SSRHistoryMeta1, 1);

#define StoreDenoiseResult(color, meta) \
    gl_FragData[0] = color; \
    gl_FragData[1] = meta

void AccumulateHistory(hvec2 uv, hvec3 refViewPos, hvec3 refNormal, hfloat refRoughness,
                       inout hvec4 colorSum, inout hfloat sampleSum, inout hfloat minConfusion)
{
    BRANCH
    if (any(lessThan(uv, vec2_splat(0.0))) || any(greaterThan(uv, vec2_splat(1.0))))
        return;

    hvec4 meta = texture2D(u_SSRHistoryMeta1, uv);
    BRANCH
    if (meta.r <= 0.0 || meta.g == SSR_DENOISER_INVALID_CONFUSION_FACTOR)
        return;

    hvec3 viewPos = SampleViewPos(uv);
    hvec3 normal = SampleViewNormal(uv);
    hfloat roughness = SampleRoughness(uv);
    hfloat weight = SsrDenoiseTokoyashiWeight(refViewPos, refNormal, refRoughness, viewPos, normal, roughness);
    hvec4 color = texture2D(u_SSRHistoryColor0, uv);

    colorSum += color * meta.r * weight;
    sampleSum += meta.r * weight;
    minConfusion = min(minConfusion, meta.g);
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec4 centerMeta = texture2D(u_SSRHistoryMeta1, uv);
    hvec4 centerColor = texture2D(u_SSRHistoryColor0, uv);

    BRANCH
    if (centerMeta.r <= 0.0 || centerMeta.g == SSR_DENOISER_INVALID_CONFUSION_FACTOR)
    {
        StoreDenoiseResult(centerColor, centerMeta);
        return;
    }

    hvec3 viewPos = SampleViewPos(uv);
    hvec3 viewNormal = SampleViewNormal(uv);
    hfloat roughness = SampleRoughness(uv);

    hvec2 majorAxis;
    hvec2 minorAxis;
    hfloat majorRadius;
    hfloat minorRadius;
    hfloat kernelSampleCount;
    SsrDenoiseComputeDirectionalEllipseKernel(
        uv, viewPos, viewNormal, roughness, centerMeta.g,
        hfloat_init(SSR_DENOISER_RECONSTRUCTION_SAMPLES), hfloat_init(SSR_DENOISER_RECONSTRUCTION_SAMPLES),
        majorAxis, minorAxis, majorRadius, minorRadius, kernelSampleCount);

    hvec4 colorSum = centerColor * centerMeta.r;
    hfloat sampleSum = centerMeta.r;
    hfloat minConfusion = centerMeta.g;

    LOOP
    for (int i = 0; i < SSR_DENOISER_RECONSTRUCTION_SAMPLES; i++)
    {
        BRANCH
        if (hfloat_init(i) >= kernelSampleCount)
            continue;

        hvec2 offset = SsrDenoiseEllipseSampleOffset(i, majorAxis, minorAxis, majorRadius, minorRadius) * cGBufferInvSize.xy;
        AccumulateHistory(uv + offset, viewPos, viewNormal, roughness, colorSum, sampleSum, minConfusion);
    }

    hvec4 result = colorSum * SsrDenoiseSafeRcp(sampleSum);
    StoreDenoiseResult(SsrDenoiseClampColorForEncoding(result), hvec4_init(sampleSum, minConfusion, 0.0, 1.0));
}

#endif
