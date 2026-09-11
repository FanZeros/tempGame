#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
// #if defined(COMBINE2) && defined(VIGNETTE)
//     #define _VVIGNETTE , vVignette
// #else
//     #define _VVIGNETTE
// #endif
#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos _VVIGNETTE
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos _VVIGNETTE
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "post_process.sh"

#ifdef COMPILEVS
#ifdef VIGNETTE
    uniform float u_AspectRatio;
    #define cAspectRatio u_AspectRatio
#endif
#endif

#ifdef COMPILEPS
uniform float u_BloomHDRThreshold;
uniform float u_BloomHDRBlurSigma;
uniform float u_BloomHDRBlurRadius;
uniform vec2 u_BloomHDRBlurDir;
uniform vec2 u_BloomHDRMix;
uniform vec2 u_Bright2InvSize;
uniform vec2 u_Bright4InvSize;
uniform vec2 u_Bright8InvSize;
uniform vec2 u_Bright16InvSize;
uniform vec2 u_Bright32InvSize;
uniform vec2 u_TileScissor;

#define cBloomHDRThreshold u_BloomHDRThreshold
#define cBloomHDRBlurSigma u_BloomHDRBlurSigma
#define cBloomHDRBlurRadius u_BloomHDRBlurRadius
#define cBloomHDRBlurDir u_BloomHDRBlurDir
#define cBloomHDRMix u_BloomHDRMix
#define cBright2InvSize u_Bright2InvSize
#define cBright4InvSize u_Bright4InvSize
#define cBright8InvSize u_Bright8InvSize
#define cBright16InvSize u_Bright16InvSize
#define cBright32InvSize u_Bright32InvSize
#define cTileScissor u_TileScissor

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
#ifdef AUTO_EXPOSURE
    // HistogramExposure outputs exposureScale directly, no middleGrey needed
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

vec4 KawaseBlur(vec2 invSize, sampler2D texSampler, vec2 texCoord, float offset)
{
    #ifdef TILE_SCISSOR
        vec2 tileTexSize = cTileScissor;
        float colIdx = floor(texCoord.x/tileTexSize.x);
        float rowIdx = floor(texCoord.y/tileTexSize.y);
        vec2 maxCoord = vec2(tileTexSize.x * (colIdx + 1.0),tileTexSize.y * (rowIdx + 1.0)) - invSize;
        vec2 minCoord = vec2(tileTexSize.x * colIdx,tileTexSize.y * rowIdx) + invSize;
        return 0.25 * texture2D(texSampler, clamp(texCoord + vec2(offset, offset) * invSize,minCoord, maxCoord))
            + 0.25 * texture2D(texSampler, clamp(texCoord + vec2(-offset, offset) * invSize,minCoord, maxCoord))
            + 0.25 * texture2D(texSampler, clamp(texCoord + vec2(-offset, -offset) * invSize,minCoord, maxCoord))
            + 0.25 * texture2D(texSampler, clamp(texCoord + vec2(offset, -offset) * invSize,minCoord, maxCoord));
    #else
        return 0.25 * texture2D(texSampler, texCoord + vec2(offset, offset) * invSize)
            + 0.25 * texture2D(texSampler, texCoord + vec2(-offset, offset) * invSize)
            + 0.25 * texture2D(texSampler, texCoord + vec2(-offset, -offset) * invSize)
            + 0.25 * texture2D(texSampler, texCoord + vec2(offset, -offset) * invSize);
    #endif
}

#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
    // #if defined(COMBINE2) && defined(VIGNETTE)
    //     vVignette = VignetteSpace(iPos.xy, cAspectRatio);
    // #endif
}


void PS()
{
    #ifdef BRIGHT2
        gl_FragColor = ExtractBright(texture2D(sDiffMap, vTexCoord), cBloomHDRThreshold);
        gl_FragColor.rgb = clamp(gl_FragColor.rgb, vec3_splat(0.0), vec3_splat(100.0));
    #endif

    #ifdef BRIGHT4
        gl_FragColor = KawaseBlur(cBright4InvSize/2.0, sDiffMap, vScreenPos, 1.0);
    #endif

    #ifdef BRIGHT8
        gl_FragColor = KawaseBlur(cBright8InvSize/2.0, sDiffMap, vScreenPos, 1.0);
    #endif

    #ifdef BRIGHT16
        gl_FragColor = KawaseBlur(cBright16InvSize/2.0, sDiffMap, vScreenPos, 1.0);
    #endif
    
    #ifdef BRIGHT32
        gl_FragColor = KawaseBlur(cBright32InvSize/2.0, sDiffMap, vScreenPos, 1.0);
    #endif

    float samplerScale = 1.28627 * 0.5;

    #ifdef COMBINE32
    #ifndef RESOLVE_ALPHA
        vec3 blurColor = KawaseBlur(cBright32InvSize, sDiffMap, vScreenPos, samplerScale).rgb;
        gl_FragColor = vec4(blurColor + texture2D(sNormalMap, vTexCoord).rgb,1.0);
    #else
        vec4 blurColor = KawaseBlur(cBright32InvSize, sDiffMap, vScreenPos, samplerScale);
        gl_FragColor = vec4(blurColor.rgb + texture2D(sNormalMap, vTexCoord).rgb, blurColor.a);
    #endif
    #endif

    #ifdef COMBINE16
    #ifndef RESOLVE_ALPHA
        vec3 blurColor = KawaseBlur(cBright16InvSize, sDiffMap, vScreenPos, samplerScale).rgb;
        gl_FragColor = vec4(blurColor + texture2D(sNormalMap, vTexCoord).rgb,1.0);
    #else
        vec4 blurColor = KawaseBlur(cBright16InvSize, sDiffMap, vScreenPos, samplerScale);
        gl_FragColor = vec4(blurColor.rgb + texture2D(sNormalMap, vTexCoord).rgb, blurColor.a);
    #endif
    #endif

    #ifdef COMBINE8
    #ifndef RESOLVE_ALPHA
        vec3 blurColor = KawaseBlur(cBright8InvSize, sDiffMap, vScreenPos, samplerScale).rgb;
        gl_FragColor = vec4(blurColor + texture2D(sNormalMap, vTexCoord).rgb,1.0);
    #else
        vec4 blurColor = KawaseBlur(cBright8InvSize, sDiffMap, vScreenPos, samplerScale);
        gl_FragColor = vec4(blurColor.rgb + texture2D(sNormalMap, vTexCoord).rgb, blurColor.a);
    #endif
    #endif

    #ifdef COMBINE4
    #ifndef RESOLVE_ALPHA
        vec3 blurColor = KawaseBlur(cBright4InvSize, sDiffMap, vScreenPos, samplerScale).rgb;
        gl_FragColor = vec4(blurColor + texture2D(sNormalMap, vTexCoord).rgb,1.0);
    #else
        vec4 blurColor = KawaseBlur(cBright4InvSize, sDiffMap, vScreenPos, samplerScale);
        gl_FragColor = vec4(blurColor.rgb + texture2D(sNormalMap, vTexCoord).rgb, blurColor.a);
    #endif
    #endif

    #ifdef COMBINE2
    #ifndef RESOLVE_ALPHA
        vec3 color = texture2D(sDiffMap, vScreenPos).rgb * cBloomHDRMix.x;
        vec3 bloom = texture2D(sNormalMap, vTexCoord).rgb * cBloomHDRMix.y;

        #ifdef MULTIPLY
            color.rgb = color.rgb * cMultiply.xyz * cMultiply.w;
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
            color.rgb = SetSaturation(color, cSaturation);
        #endif

        #ifdef VIGNETTE
            // color.rgb = color.rgb * ComputeVignetteMask(vVignette, cVignetteIntensity);
            color.rgb = color.rgb * min(texture2D(sSpecMap, vScreenPos).r * cVignetteIntensity, 1.0);
        #endif

        #ifdef GAMMA_IN_SHADERING
            gl_FragColor = vec4(LinearToGammaSpace(color), 1.0);
        #else
            gl_FragColor = vec4(color, 1.0);
        #endif
    #else
        vec4 color = texture2D(sDiffMap, vScreenPos);
        vec4 bloom = texture2D(sNormalMap, vTexCoord);
        color.rgb *= cBloomHDRMix.x;
        bloom.rgb *= cBloomHDRMix.y;

        #ifdef MULTIPLY
            color.rgb = color.rgb * cMultiply.xyz * cMultiply.w;
        #endif

        #ifdef AUTO_EXPOSURE
            float exposureScale = texture2D(sEmissiveMap, vec2(0.5, 0.5)).r;
        #endif

        #ifndef DISABLE_TONEMAPPINGS
            #ifdef TONEMAP_LUT
                #ifdef AUTO_EXPOSURE
                    color = vec4(SampleTonemapLUT((color.rgb + bloom.rgb) * exposureScale), color.a);
                #else
                    color = vec4(SampleTonemapLUT(color.rgb + bloom.rgb), color.a);
                #endif
            #else
                #ifdef AUTO_EXPOSURE
                    color = vec4(toAcesFilmic_HalfSafe((color.rgb + bloom.rgb) * exposureScale), color.a);
                #else
                    color = vec4(toAcesFilmic_HalfSafe(color.rgb + bloom.rgb), color.a);
                #endif
            #endif
        #else
            color.rgb = color.rgb + bloom.rgb;
        #endif

        #ifdef SATURATION  
            color.rgb = SetSaturation(color.rgb, cSaturation);
        #endif
    
        #ifdef GAMMA_IN_SHADERING
            gl_FragColor = LinearToGammaSpace(color);
        #else
            gl_FragColor = color;
        #endif
    #endif
    #endif
}
