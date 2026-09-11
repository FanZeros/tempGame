/*
 * SSGI spatial reconstruction / pre-convolution (half resolution).
 * Port of UE SSDSpatialAccumulation.usf, SIGNAL_PROCESSING_DIFFUSE_INDIRECT_AND_AO
 * (STAGE_RECONSTRUCTION, and STAGE_PRE_CONVOLUTION with SSGI_PRECONVOLUTION defined).
 *
 * Line-by-line ported pieces:
 *   - kStackowiakSampleSet0 offsets (verbatim table, SSGIStackowiak.sh)
 *   - 2x2 quad interleaving: SampleTrackId = (x&1) | ((y&1)<<1), kernel center at the
 *     quad corner (SSDSpatialAccumulation.usf:938-941), per-pixel sample count =
 *     ReconstructionSamples / 4 (SSDSpatialKernel.ush:914)
 *   - bilateral weight = BILATERAL_PRESET_DIFFUSE = POSITION_BASED | NORMAL:
 *     plane-distance test + pow(NoN, 4) (SSDSpatialKernel.ush:351,
 *     SSDSignalFramework.ush:546-552)
 * UrhoX deviation (marked): the SSD world-frequency machinery (hit-distance driven
 * per-sample InvFrequency) is reduced to a depth-proportional plane tolerance; color
 * and AO share the bilateral weight. Revisit if quality demands it.
 *
 * ReconstructionSamples default 16 follows r.GlobalIllumination.Denoiser.
 * ReconstructionSamples (ScreenSpaceDenoise.cpp:99-100).
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
#include "ScreenSpace/SSGI/SSGIStackowiak.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

SAMPLER2D(u_SSGIInput0, 0);
SAMPLER2D(u_SSGIHitDistance1, 1);
SAMPLER2D(u_Depth2, 2);
SAMPLER2D(u_Normal3, 3);

// Kernel radius scale in (half-res) pixels, UE KernelSpreadFactor semantics.
uniform hfloat u_KernelSpread;

// r.GlobalIllumination.Denoiser.ReconstructionSamples = 16, spread over the 2x2 quad
// via the 4 interleaved track sets -> 4 taps per pixel.
#define RECONSTRUCTION_SAMPLES 16
#define SAMPLES_PER_PIXEL (RECONSTRUCTION_SAMPLES / STACKOWIAK_SAMPLE_SET_COUNT)

hvec3 SampleViewPos(hvec2 uv)
{
    return ReconstructViewPos(uv, texture2D(u_Depth2, uv).r);
}

hvec3 SampleViewNormal(hvec2 uv)
{
    hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal3, uv).rgb);
    return normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
}

void PS()
{
    hvec2 uv = vTexCoord;

    hfloat depth = texture2D(u_Depth2, uv).r;
    hvec4 centerColor = texture2D(u_SSGIInput0, uv);
    hfloat centerHitDistance = texture2D(u_SSGIHitDistance1, uv).r;

    BRANCH
    if (depth >= 0.9999)
    {
        gl_FragData[0] = centerColor;
        gl_FragData[1] = hvec4_init(centerHitDistance, 0.0, 0.0, 1.0);
        return;
    }

    hvec3 refViewPos = SampleViewPos(uv);
    hvec3 refNormal = SampleViewNormal(uv);

    // uint SampleTrackId = (x & 1) | ((y & 1) << 1); kernel center at the quad corner
    // (DispatchThreadId | 1 in UE = odd pixel corner shared by the 2x2 quad).
    hvec2 pixelCoord = floor(uv / cGBufferInvSize.xy);
    hfloat trackX = pixelCoord.x - 2.0 * floor(pixelCoord.x * 0.5); // x & 1
    hfloat trackY = pixelCoord.y - 2.0 * floor(pixelCoord.y * 0.5); // y & 1
    int sampleTrackId = int(trackX + trackY * 2.0);
    // Quad corner: odd coordinate + 0.5 texel = shared corner of the 2x2 quad
    hvec2 quadCornerUV = (floor(pixelCoord * 0.5) * 2.0 + 1.0 + 0.5) * cGBufferInvSize.xy;

    hvec4 colorSum = centerColor;
    hfloat weightSum = 1.0;
    hfloat outHitDistance = centerHitDistance;

    // UrhoX deviation: plane tolerance is depth-proportional instead of the SSD
    // hit-distance-driven world frequency.
    hfloat planeTolerance = max(abs(refViewPos.z) * 0.02, 0.02) * (u_KernelSpread / 8.0);

    LOOP
    for (int sampleId = 0; sampleId < SAMPLES_PER_PIXEL; sampleId++)
    {
        hvec2 offsetPixels = kStackowiakSampleSet0[sampleId * STACKOWIAK_SAMPLE_SET_COUNT + sampleTrackId];
        hvec2 sampleUV = quadCornerUV + offsetPixels * u_KernelSpread * cGBufferInvSize.xy;

        BRANCH
        if (any(lessThan(sampleUV, vec2_splat(0.0))) || any(greaterThan(sampleUV, vec2_splat(1.0))))
            continue;

        hfloat sampleDepth = texture2D(u_Depth2, sampleUV).r;
        BRANCH
        if (sampleDepth >= 0.9999)
            continue;

        hvec3 sampleViewPos = SampleViewPos(sampleUV);
        hvec3 sampleNormal = SampleViewNormal(sampleUV);

        // BILATERAL_POSITION_BASED: plane mis-alignment against the reference plane
        hfloat planeDist = abs(dot(sampleViewPos - refViewPos, refNormal));
        hfloat positionWeight = saturate(1.0 - planeDist / planeTolerance);

        // BILATERAL_NORMAL: pow(NoN, 4) (SSDSignalFramework.ush:552)
        hfloat NoN = max(dot(refNormal, sampleNormal), 0.0);
        hfloat normalWeight = NoN * NoN * NoN * NoN;

        hfloat weight = positionWeight * normalWeight;

        BRANCH
        if (weight <= 0.0)
            continue;

        colorSum += texture2D(u_SSGIInput0, sampleUV) * weight;
        weightSum += weight;

        hfloat sampleHitDistance = texture2D(u_SSGIHitDistance1, sampleUV).r;
        BRANCH
        if (sampleHitDistance > 0.0 && (outHitDistance <= 0.0 || sampleHitDistance < outHitDistance))
            outHitDistance = sampleHitDistance;
    }

    hvec4 result = colorSum / weightSum;
    gl_FragData[0] = max(result, vec4_splat(0.0));
    gl_FragData[1] = hvec4_init(outHitDistance, 0.0, 0.0, 1.0);
}

#endif // COMPILEPS
