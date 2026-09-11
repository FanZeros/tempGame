// UE Gaussian Bloom (BLOOM_MODE_UE)
// Ported from UnrealEngine:
//   BLOOM_SETUP       <- Engine/Shaders/Private/PostProcessBloom.usf (BloomSetupCommon)
//   DOWNSAMPLE_*      <- Engine/Shaders/Private/PostProcessDownsample.usf (DownsampleCommon, QUALITY_HIGH)
//   BLUR              <- Engine/Shaders/Private/FilterPixelShader.usf (MainPS, dynamic loop path)
//   COMBINE           <- platform adaptation: UrhoX applies tonemap inside the bloom combine pass
//                        (in UE bloom is an input texture of the Tonemapper), energy-equivalent
// CPU-side kernel generation: View::ApplyBloomUEParameters (port of PostProcessWeightedSampleSum.cpp)
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

// Max taps per direction, must match BLOOM_UE_MAX_FILTER_SAMPLES in View.cpp
#define BLOOM_UE_MAX_FILTER_SAMPLES 32
#define BLOOM_UE_PACKED_OFFSETS 16

uniform float u_BloomUEThreshold;
uniform vec4 u_BloomUEOffsets[BLOOM_UE_PACKED_OFFSETS];  // two float2 UV offsets packed per vec4 (FilterPixelShader.usf packing)
uniform vec4 u_BloomUEWeights[BLOOM_UE_MAX_FILTER_SAMPLES];
uniform float u_BloomUESampleCount;
uniform vec2 u_BloomHDRMix;
uniform vec2 u_BloomUEDown2InvSize;
uniform vec2 u_BloomUEDown4InvSize;
uniform vec2 u_BloomUEDown8InvSize;
uniform vec2 u_BloomUEDown16InvSize;
uniform vec2 u_BloomUEDown32InvSize;

#define cBloomUEThreshold u_BloomUEThreshold
#define cBloomUESampleCount u_BloomUESampleCount
#define cBloomHDRMix u_BloomHDRMix

#ifdef SATURATION
    uniform float u_Saturation;
    #define cSaturation u_Saturation
#endif
#ifdef MULTIPLY
    uniform vec4 u_Multiply;
    #define cMultiply u_Multiply
#endif
#ifdef VIGNETTE
    uniform float u_VignetteIntensity;
    #define cVignetteIntensity u_VignetteIntensity
#endif

#ifdef TONEMAP_LUT
    uniform float u_TonemapLUTSize;
    #define cTonemapLUTSize u_TonemapLUTSize

    // UE Log2 编码（移植自 UE GammaCorrectionCommon.ush）
    vec3 LinToLog(vec3 linearColor)
    {
        const float LinearRange = 14.0;
        const float LinearGrey = 0.18;
        const float ExposureGrey = 444.0 / 1023.0;
        return log2(linearColor) / LinearRange
             - log2(LinearGrey) / LinearRange
             + ExposureGrey;
    }

    vec3 SampleTonemapLUT(vec3 hdrColor)
    {
        float lutSize = cTonemapLUTSize;
        // LogToLin(0) 偏移防 log2(0)，与 UE 一致
        const float LinearRange = 14.0;
        const float LinearGrey = 0.18;
        const float ExposureGrey = 444.0 / 1023.0;
        float logToLinZero = exp2((0.0 - ExposureGrey) * LinearRange) * LinearGrey;
        vec3 encoded = LinToLog(max(hdrColor, vec3_splat(0.0)) + vec3_splat(logToLinZero));
        vec3 lutUV = clamp(encoded, 0.0, 1.0);
        // texel center remap
        float invLutSize = 1.0 / lutSize;
        float halfTexel = 0.5 * invLutSize;
        float scale = 1.0 - invLutSize;
        vec3 coord = lutUV * scale + vec3_splat(halfTexel);
        return texture3DLod(sVolumeMap, coord, 0.0).rgb;
    }
#endif

// UE Common.ush: Luminance()
hfloat UELuminance(hvec3 linearColor)
{
    return dot(linearColor, hvec3_init(0.3, 0.59, 0.11));
}

// UE PostProcessDownsample.usf: DownsampleCommon, DOWNSAMPLE_QUALITY_HIGH
// "Blur during downsample (4x4 kernel) to get better quality especially for HDR content."
vec4 UEDownsampleCommon(sampler2D texSampler, vec2 uv, vec2 inputInvSize)
{
    vec4 sample0 = texture2D(texSampler, uv + inputInvSize * vec2(-1.0, -1.0));
    vec4 sample1 = texture2D(texSampler, uv + inputInvSize * vec2( 1.0, -1.0));
    vec4 sample2 = texture2D(texSampler, uv + inputInvSize * vec2(-1.0,  1.0));
    vec4 sample3 = texture2D(texSampler, uv + inputInvSize * vec2( 1.0,  1.0));

    vec4 outColor = (sample0 + sample1 + sample2 + sample3) * 0.25;

    // UE: "Fixed rarely occurring yellow color tint of the whole viewport"
    outColor.rgb = max(vec3_splat(0.0), outColor.rgb);
    return outColor;
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
    // ---- Threshold extraction (PostProcessBloom.usf: BloomSetupCommon) ----
    // Deviations from UE (platform adaptation):
    // 1. UE takes half-res SceneColor as input; here we bilinear-sample the full-res
    //    viewport into a 1/2 RT, which is equivalent to a 2x2 box downsample
    // 2. UE skips the setup pass on C++ side when threshold <= -1 (USE_THRESHOLD=0);
    //    renderpath passes are static, so an equivalent uniform branch is used instead
    // 3. UrhoX has no PreExposure mechanism, OneOverPreExposure/PreExposure omitted
    #ifdef BLOOM_SETUP
        vec4 sceneColor = texture2D(sDiffMap, vScreenPos);

        #ifdef AUTO_EXPOSURE
            hfloat exposureScale = texture2D(sEmissiveMap, vec2(0.5, 0.5)).r;
        #else
            hfloat exposureScale = 1.0;
        #endif

        hfloat bloomAmount;
        if (cBloomUEThreshold > -1.0)
        {
            // UE: threshold operates on post-exposure luminance, soft ramp spans 2 luminance units
            hfloat totalLuminance = UELuminance(sceneColor.rgb) * exposureScale;
            hfloat bloomLuminance = totalLuminance - cBloomUEThreshold;
            bloomAmount = saturate(bloomLuminance * 0.5);
        }
        else
        {
            // UE: no threshold (energy conserving mode), every pixel contributes to bloom
            bloomAmount = 1.0;
        }

        gl_FragColor = vec4(bloomAmount * sceneColor.rgb, 0.0);
    #endif

    // ---- Downsample chain (PostProcessDownsample.usf: QUALITY_HIGH 4-tap) ----
    #ifdef DOWNSAMPLE_4
        gl_FragColor = UEDownsampleCommon(sDiffMap, vScreenPos, u_BloomUEDown2InvSize);
    #endif
    #ifdef DOWNSAMPLE_8
        gl_FragColor = UEDownsampleCommon(sDiffMap, vScreenPos, u_BloomUEDown4InvSize);
    #endif
    #ifdef DOWNSAMPLE_16
        gl_FragColor = UEDownsampleCommon(sDiffMap, vScreenPos, u_BloomUEDown8InvSize);
    #endif
    #ifdef DOWNSAMPLE_32
        gl_FragColor = UEDownsampleCommon(sDiffMap, vScreenPos, u_BloomUEDown16InvSize);
    #endif
    #ifdef DOWNSAMPLE_64
        gl_FragColor = UEDownsampleCommon(sDiffMap, vScreenPos, u_BloomUEDown32InvSize);
    #endif

    // ---- Separable gaussian (FilterPixelShader.usf: MainPS, dynamic loop) ----
    // Blur direction is decided by CPU-side offsets (View::ApplyBloomUEParameters);
    // tint x intensity is baked into Y pass weights. COMBINE_ADDITIVE matches UE
    // FCombineAdditive: the Y pass also bilinear-upsamples and adds the accumulated
    // result of the previous (lower resolution) stage
    #ifdef BLUR
        vec4 color = vec4_splat(0.0);
        int sampleCount = int(cBloomUESampleCount);

        int sampleIndex = 0;
        for (; sampleIndex < sampleCount - 1; sampleIndex += 2)
        {
            vec4 uvuv = vScreenPos.xyxy + u_BloomUEOffsets[sampleIndex / 2];
            color += texture2D(sDiffMap, uvuv.xy) * u_BloomUEWeights[sampleIndex];
            color += texture2D(sDiffMap, uvuv.zw) * u_BloomUEWeights[sampleIndex + 1];
        }

        if (sampleIndex < sampleCount)
        {
            vec2 uv = vScreenPos + u_BloomUEOffsets[sampleIndex / 2].xy;
            color += texture2D(sDiffMap, uv) * u_BloomUEWeights[sampleIndex];
        }

        #ifdef COMBINE_ADDITIVE
            color += texture2D(sNormalMap, vTexCoord);
        #endif

        gl_FragColor = color;
    #endif

    // ---- Final combine (same tonemap tail as BloomHDR.glsl COMBINE2, mix fixed at (1,1)) ----
    #ifdef COMBINE
        vec3 color = texture2D(sDiffMap, vScreenPos).rgb * cBloomHDRMix.x;
        vec3 bloom = texture2D(sNormalMap, vTexCoord).rgb * cBloomHDRMix.y;

        #ifdef MULTIPLY
            color = color * cMultiply.xyz * cMultiply.w;
        #endif

        #ifdef AUTO_EXPOSURE
            float exposureScale = texture2D(sEmissiveMap, vec2(0.5, 0.5)).r;
        #endif

        #ifndef DISABLE_TONEMAPPINGS
            #ifdef TONEMAP_LUT
                #ifdef AUTO_EXPOSURE
                    color = SampleTonemapLUT((color + bloom) * exposureScale);
                #else
                    color = SampleTonemapLUT(color + bloom);
                #endif
            #else
                #ifdef AUTO_EXPOSURE
                    color = toAcesFilmic_HalfSafe((color + bloom) * exposureScale);
                #else
                    color = toAcesFilmic_HalfSafe(color + bloom);
                #endif
            #endif
        #else
            color = color + bloom;
        #endif

        #ifdef SATURATION
            color = SetSaturation(color, cSaturation);
        #endif

        #ifdef VIGNETTE
            color = color * min(texture2D(sSpecMap, vScreenPos).r * cVignetteIntensity, 1.0);
        #endif

        #ifdef GAMMA_IN_SHADERING
            gl_FragColor = vec4(LinearToGammaSpace(color), 1.0);
        #else
            gl_FragColor = vec4(color, 1.0);
        #endif
    #endif
}
