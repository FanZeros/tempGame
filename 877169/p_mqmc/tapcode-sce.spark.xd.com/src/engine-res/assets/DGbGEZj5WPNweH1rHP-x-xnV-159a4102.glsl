/*
 * Reflections denoiser reconstruction stage.
 * Mirrors UE ScreenSpaceDenoise reflections input/history layout:
 *   input RT0: SSR color
 *   input RT1.r: denoiser confusion factor
 *   output RT0: normalized color
 *   output RT1.r: sample count, RT1.g: confusion factor
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
SAMPLER2D(u_SSRInput0, 0);
SAMPLER2D(u_SSRConfusion1, 1);

#define StoreDenoiseResult(color, meta) \
    gl_FragData[0] = color; \
    gl_FragData[1] = meta

void AccumulateInput(hvec2 uv, hvec3 refViewPos, hvec3 refNormal, hfloat refRoughness,
                     inout hvec4 colorSum, inout hfloat sampleSum, inout hfloat minConfusion)
{
    BRANCH
    if (any(lessThan(uv, vec2_splat(0.0))) || any(greaterThan(uv, vec2_splat(1.0))))
        return;

    hfloat confusion = texture2D(u_SSRConfusion1, uv).r;
    BRANCH
    if (confusion == SSR_DENOISER_INVALID_CONFUSION_FACTOR)
        return;

    hvec4 color = texture2D(u_SSRInput0, uv);
    hvec3 viewPos = SampleViewPos(uv);
    hvec3 normal = SampleViewNormal(uv);
    hfloat roughness = SampleRoughness(uv);
    hfloat weight = SsrDenoiseTokoyashiWeight(refViewPos, refNormal, refRoughness, viewPos, normal, roughness);

    colorSum += color * SsrDenoiseKarisHdrWeight(color.rgb) * weight;
    sampleSum += weight;
    minConfusion = min(minConfusion, confusion);
}

void PS()
{
    hvec2 uv = vTexCoord;
    hfloat centerConfusion = texture2D(u_SSRConfusion1, uv).r;
    hvec4 centerColor = texture2D(u_SSRInput0, uv);

    BRANCH
    if (centerConfusion == SSR_DENOISER_INVALID_CONFUSION_FACTOR)
    {
        StoreDenoiseResult(centerColor, hvec4_init(0.0, SSR_DENOISER_INVALID_CONFUSION_FACTOR, 0.0, 1.0));
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
        uv, viewPos, viewNormal, roughness, centerConfusion,
        1.0, hfloat_init(SSR_DENOISER_RECONSTRUCTION_SAMPLES),
        majorAxis, minorAxis, majorRadius, minorRadius, kernelSampleCount);

    hvec4 colorSum = centerColor * SsrDenoiseKarisHdrWeight(centerColor.rgb);
    hfloat sampleSum = 1.0;
    hfloat minConfusion = centerConfusion;

    LOOP
    for (int i = 0; i < SSR_DENOISER_RECONSTRUCTION_SAMPLES; i++)
    {
        BRANCH
        if (hfloat_init(i) >= kernelSampleCount)
            continue;

        hvec2 offset = SsrDenoiseEllipseSampleOffset(i, majorAxis, minorAxis, majorRadius, minorRadius) * cGBufferInvSize.xy;
        AccumulateInput(uv + offset, viewPos, viewNormal, roughness, colorSum, sampleSum, minConfusion);
    }

    hvec4 result = colorSum * SsrDenoiseSafeRcp(sampleSum);
    result *= SsrDenoiseKarisHdrWeightInv(result.rgb);
    StoreDenoiseResult(SsrDenoiseClampColorForEncoding(result), hvec4_init(sampleSum, minConfusion, 0.0, 1.0));
}

#endif
