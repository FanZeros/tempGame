#ifndef SSR_DENOISE_COMMON_SH
#define SSR_DENOISE_COMMON_SH

#include "ScreenSpace/SSR/SSRCommon.sh"

#define SSR_DENOISER_INVALID_CONFUSION_FACTOR (-1.0)
#define SSR_DENOISER_RECONSTRUCTION_SAMPLES 8
#define SSR_DENOISER_TARGET_SAMPLE_PER_PIXEL 0.25

// Shared scene samplers for all denoise passes. The render path must bind
// depth=5, GBufferA=6, GBufferB=7 on every pass that includes this header.
#ifdef COMPILEPS

SAMPLER2D(u_DenoiseDepth5, 5);
SAMPLER2D(u_DenoiseNormal6, 6);
SAMPLER2D(u_DenoiseGBufferB7, 7);

hvec3 SampleViewPos(hvec2 uv)
{
    return ReconstructViewPos(uv, texture2D(u_DenoiseDepth5, uv).r);
}

hvec3 SampleViewNormal(hvec2 uv)
{
    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_DenoiseNormal6, uv).rgb);
    return normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
}

hfloat SampleRoughness(hvec2 uv)
{
    return texture2D(u_DenoiseGBufferB7, uv).b;
}

#endif // COMPILEPS

hfloat SsrDenoiseSafeRcp(hfloat x)
{
    return x > 0.0 ? 1.0 / x : 0.0;
}

hfloat SsrDenoiseLuma4(hvec3 color)
{
    return color.g * 2.0 + color.r + color.b;
}

hfloat SsrDenoiseKarisHdrWeight(hvec3 color)
{
    return 1.0 / (SsrDenoiseLuma4(color) + 4.0);
}

hfloat SsrDenoiseKarisHdrWeightInv(hvec3 color)
{
    return 4.0 / max(1.0 - SsrDenoiseLuma4(color), 0.03125);
}

hvec4 SsrDenoiseClampColorForEncoding(hvec4 color)
{
    return max(color, vec4_splat(0.0));
}

void SsrDenoiseComputeSpecularLobeAngles(hvec3 viewDir, hvec3 normal, hfloat roughness, out hfloat majorAngle, out hfloat minorAngle)
{
    hfloat e = 0.5;
    hfloat a = roughness * roughness;
    hvec3 tangentView = UEWorldToTangent(viewDir, normal);

    hvec3 h0 = ImportanceSampleVisibleGGX(hvec2_init(0.00, e), a, tangentView);
    hvec3 h1 = ImportanceSampleVisibleGGX(hvec2_init(0.25, e), a, tangentView);
    hvec3 h2 = ImportanceSampleVisibleGGX(hvec2_init(0.50, e), a, tangentView);
    hvec3 h3 = ImportanceSampleVisibleGGX(hvec2_init(0.75, e), a, tangentView);

    hvec3 l0 = 2.0 * dot(tangentView, h0) * h0 - tangentView;
    hvec3 l1 = 2.0 * dot(tangentView, h1) * h1 - tangentView;
    hvec3 l2 = 2.0 * dot(tangentView, h2) * h2 - tangentView;
    hvec3 l3 = 2.0 * dot(tangentView, h3) * h3 - tangentView;

    majorAngle = acos(clamp(dot(l2, l3), -1.0, 1.0));
    minorAngle = acos(clamp(dot(l0, l1), -1.0, 1.0));
}

hfloat SsrDenoiseLobeAngleToViewportRadius(hfloat lobeAngle)
{
    return tan(0.5 * lobeAngle) * abs(cProj[0][0]);
}

void SsrDenoiseProjectSpecularLobeToScreenSpace(hvec2 uv, hvec3 viewPos, hvec3 viewNormal, hfloat roughness,
                                                out hvec2 majorAxis, out hfloat majorViewportRadius, out hfloat minorViewportRadius)
{
    hvec3 viewDir = normalize(-viewPos);
    hvec3 reflectionDir = 2.0 * dot(viewDir, viewNormal) * viewNormal - viewDir;
    hvec3 rayEnd = viewPos + reflectionDir * (0.5 * max(viewPos.z, 0.001));
    hvec2 rayEndUV = ProjectViewToUVZ(rayEnd).xy;
    hvec2 rayDirectionPixels = (rayEndUV - uv) / cGBufferInvSize.xy;

    hfloat rayDirectionLengthSqr = dot(rayDirectionPixels, rayDirectionPixels);
    BRANCH
    if (rayDirectionLengthSqr < 1.0e-4)
        majorAxis = hvec2_init(1.0, 0.0);
    else
        majorAxis = rayDirectionPixels * inversesqrt(rayDirectionLengthSqr);

    hfloat majorAngle;
    hfloat minorAngle;
    SsrDenoiseComputeSpecularLobeAngles(viewDir, viewNormal, roughness, majorAngle, minorAngle);
    majorViewportRadius = SsrDenoiseLobeAngleToViewportRadius(majorAngle);
    minorViewportRadius = SsrDenoiseLobeAngleToViewportRadius(minorAngle);
}

void SsrDenoiseComputeDirectionalEllipseKernel(hvec2 uv, hvec3 viewPos, hvec3 viewNormal, hfloat roughness, hfloat confusion,
                                               hfloat previousCumulativeMaxSampleCount, hfloat maxSampleCount,
                                               out hvec2 majorAxis, out hvec2 minorAxis,
                                               out hfloat majorPixelRadius, out hfloat minorPixelRadius, out hfloat sampleCount)
{
    hfloat majorViewportRadius;
    hfloat minorViewportRadius;
    SsrDenoiseProjectSpecularLobeToScreenSpace(uv, viewPos, viewNormal, roughness, majorAxis, majorViewportRadius, minorViewportRadius);

    hfloat aspectRatio = clamp(minorViewportRadius * SsrDenoiseSafeRcp(majorViewportRadius), 0.05, 1.0);
    hfloat previousMaxPixelDiameter = sqrt(SsrDenoiseSafeRcp(SSR_DENOISER_TARGET_SAMPLE_PER_PIXEL) * previousCumulativeMaxSampleCount * SsrDenoiseSafeRcp(aspectRatio));
    hfloat maxPixelDiameter = sqrt(SsrDenoiseSafeRcp(SSR_DENOISER_TARGET_SAMPLE_PER_PIXEL) * maxSampleCount * previousCumulativeMaxSampleCount * SsrDenoiseSafeRcp(aspectRatio));
    hfloat maxPixelRadius = 0.5 * maxPixelDiameter;

    majorPixelRadius = majorViewportRadius * saturate(confusion) / cGBufferInvSize.x - previousMaxPixelDiameter;
    majorPixelRadius = clamp(majorPixelRadius, 0.0, maxPixelRadius);
    minorPixelRadius = aspectRatio * majorPixelRadius;

    hfloat minimalPixelRadius = 0.5 * 0.70710678;
    hfloat convolutionArea = 4.0 * max(majorPixelRadius, minimalPixelRadius) * max(minorPixelRadius, minimalPixelRadius);
    sampleCount = clamp(convolutionArea * SSR_DENOISER_TARGET_SAMPLE_PER_PIXEL * SsrDenoiseSafeRcp(previousCumulativeMaxSampleCount), 0.0, maxSampleCount);

    minorAxis = hvec2_init(-majorAxis.y, majorAxis.x);
}

hfloat SsrDenoiseTokoyashiWeight(hvec3 refViewPos, hvec3 refNormal, hfloat refRoughness,
                                 hvec3 sampleViewPos, hvec3 sampleNormal, hfloat sampleRoughness)
{
    hvec3 refViewDir = normalize(-refViewPos);
    hvec3 sampleViewDir = normalize(-sampleViewPos);

    hfloat refA = max(0.001, refRoughness);
    refA *= refA;
    hfloat refA2 = refA * refA;
    hfloat refNoV = saturate(abs(dot(refNormal, refViewDir)) + 1.0e-5);
    hvec3 refAxis = 2.0 * refNoV * refNormal - refViewDir;
    hfloat refSharpness = 0.5 / (refA2 * max(refNoV, 0.1));

    hfloat sampleA = max(0.001, sampleRoughness);
    sampleA *= sampleA;
    hfloat sampleA2 = sampleA * sampleA;
    hfloat sampleNoV = saturate(abs(dot(sampleNormal, sampleViewDir)) + 1.0e-5);
    hvec3 sampleAxis = 2.0 * sampleNoV * sampleNormal - sampleViewDir;
    hfloat sampleSharpness = 0.5 / (sampleA2 * max(sampleNoV, 0.1));

    hfloat invSharpnessSum = SsrDenoiseSafeRcp(refSharpness + sampleSharpness);
    hfloat beta = 32.0;
    hfloat lobeSimilarity = pow(saturate(2.0 * sqrt(refSharpness * sampleSharpness) * invSharpnessSum), beta);
    hfloat axesSimilarity = exp(-(beta * (refSharpness * sampleSharpness) * invSharpnessSum) * saturate(1.0 - dot(refAxis, sampleAxis)));
    return lobeSimilarity * axesSimilarity;
}

hvec2 SsrDenoiseEllipseSampleOffset(int sampleIndex, hvec2 majorAxis, hvec2 minorAxis, hfloat majorRadius, hfloat minorRadius)
{
    hfloat index = hfloat_init(sampleIndex);
    hfloat angle = 6.2831853 * (index + 0.5) / hfloat_init(SSR_DENOISER_RECONSTRUCTION_SAMPLES);
    hfloat radius = sqrt((index + 0.5) / hfloat_init(SSR_DENOISER_RECONSTRUCTION_SAMPLES));
    return majorAxis * (cos(angle) * radius * majorRadius) + minorAxis * (sin(angle) * radius * minorRadius);
}

#endif // SSR_DENOISE_COMMON_SH
