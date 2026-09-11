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
uniform float u_BloomHDRThreshold;
uniform vec2 u_BloomHDRMix;
uniform vec2 u_Bright2InvSize;
uniform vec2 u_Bright4InvSize;
uniform vec2 u_Bright8InvSize;
uniform vec2 u_Bright16InvSize;
uniform vec2 u_Bright32InvSize;
uniform float u_BloomHDRPlusIntensity;

#define cBloomHDRThreshold u_BloomHDRThreshold
#define cBloomHDRMix u_BloomHDRMix
#define cBright2InvSize u_Bright2InvSize
#define cBright4InvSize u_Bright4InvSize
#define cBright8InvSize u_Bright8InvSize
#define cBright16InvSize u_Bright16InvSize
#define cBright32InvSize u_Bright32InvSize
#define cBloomHDRPlusIntensity u_BloomHDRPlusIntensity

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

// Dual Kawase Downsample (13 tap) - from bgfx bloom example
vec4 DualKawaseDownsample(vec2 invSize, sampler2D texSampler, vec2 texCoord)
{
    vec2 halfpixel = 0.5 * invSize;
    vec2 onepixel = invSize;

    vec4 sum = vec4_splat(0.0);
    sum += (4.0/32.0) * texture2D(texSampler, texCoord);

    sum += (4.0/32.0) * texture2D(texSampler, texCoord + vec2(-halfpixel.x, -halfpixel.y));
    sum += (4.0/32.0) * texture2D(texSampler, texCoord + vec2(+halfpixel.x, +halfpixel.y));
    sum += (4.0/32.0) * texture2D(texSampler, texCoord + vec2(+halfpixel.x, -halfpixel.y));
    sum += (4.0/32.0) * texture2D(texSampler, texCoord + vec2(-halfpixel.x, +halfpixel.y));

    sum += (2.0/32.0) * texture2D(texSampler, texCoord + vec2(+onepixel.x, 0.0));
    sum += (2.0/32.0) * texture2D(texSampler, texCoord + vec2(-onepixel.x, 0.0));
    sum += (2.0/32.0) * texture2D(texSampler, texCoord + vec2(0.0, +onepixel.y));
    sum += (2.0/32.0) * texture2D(texSampler, texCoord + vec2(0.0, -onepixel.y));

    sum += (1.0/32.0) * texture2D(texSampler, texCoord + vec2(+onepixel.x, +onepixel.y));
    sum += (1.0/32.0) * texture2D(texSampler, texCoord + vec2(-onepixel.x, +onepixel.y));
    sum += (1.0/32.0) * texture2D(texSampler, texCoord + vec2(+onepixel.x, -onepixel.y));
    sum += (1.0/32.0) * texture2D(texSampler, texCoord + vec2(-onepixel.x, -onepixel.y));

    return sum;
}

// Dual Kawase Upsample (9 tap) - from bgfx bloom example
vec4 DualKawaseUpsample(vec2 invSize, sampler2D texSampler, vec2 texCoord, float intensity)
{
    vec2 halfpixel = invSize;

    vec4 sum = vec4_splat(0.0);
    sum += (2.0/16.0) * texture2D(texSampler, texCoord + vec2(-halfpixel.x, 0.0));
    sum += (2.0/16.0) * texture2D(texSampler, texCoord + vec2(0.0, +halfpixel.y));
    sum += (2.0/16.0) * texture2D(texSampler, texCoord + vec2(+halfpixel.x, 0.0));
    sum += (2.0/16.0) * texture2D(texSampler, texCoord + vec2(0.0, -halfpixel.y));

    sum += (1.0/16.0) * texture2D(texSampler, texCoord + vec2(-halfpixel.x, -halfpixel.y));
    sum += (1.0/16.0) * texture2D(texSampler, texCoord + vec2(-halfpixel.x, +halfpixel.y));
    sum += (1.0/16.0) * texture2D(texSampler, texCoord + vec2(+halfpixel.x, -halfpixel.y));
    sum += (1.0/16.0) * texture2D(texSampler, texCoord + vec2(+halfpixel.x, +halfpixel.y));

    sum += (4.0/16.0) * texture2D(texSampler, texCoord);

    return sum * intensity;
}

// Get luminance for bloom threshold
float GetBloomLuminance(vec3 rgb)
{
    return dot(vec3(0.2126729, 0.7151522, 0.0721750), rgb);
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
    // Bright extraction pass (same as GameBloomHDR)
    #ifdef BRIGHT
        gl_FragColor = ExtractBright(texture2D(sDiffMap, vScreenPos), cBloomHDRThreshold);
        gl_FragColor.rgb = clamp(gl_FragColor.rgb, vec3_splat(0.0), vec3_splat(100.0));
    #endif

    // Downsample passes (13 tap)
    #ifdef DUALBLUR_DOWN2
        gl_FragColor = DualKawaseDownsample(cBright2InvSize, sDiffMap, vScreenPos);
    #endif

    #ifdef DUALBLUR_DOWN4
        gl_FragColor = DualKawaseDownsample(cBright4InvSize, sDiffMap, vScreenPos);
    #endif

    #ifdef DUALBLUR_DOWN8
        gl_FragColor = DualKawaseDownsample(cBright8InvSize, sDiffMap, vScreenPos);
    #endif

    #ifdef DUALBLUR_DOWN16
        gl_FragColor = DualKawaseDownsample(cBright16InvSize, sDiffMap, vScreenPos);
    #endif

    #ifdef DUALBLUR_DOWN32
        gl_FragColor = DualKawaseDownsample(cBright32InvSize, sDiffMap, vScreenPos);
    #endif

    // Upsample passes (9 tap, combine upsampled result with current level bloom)
    // diffuse = lower resolution (to upsample), normal = current level bloom (to combine)
    #ifdef DUALBLUR_UP32
        vec3 upsampled32 = DualKawaseUpsample(cBright32InvSize, sDiffMap, vScreenPos, cBloomHDRPlusIntensity).rgb;
        vec3 current32 = texture2D(sNormalMap, vTexCoord).rgb;
        gl_FragColor = vec4(upsampled32 + current32, 1.0);
    #endif

    #ifdef DUALBLUR_UP16
        vec3 upsampled16 = DualKawaseUpsample(cBright16InvSize, sDiffMap, vScreenPos, cBloomHDRPlusIntensity).rgb;
        vec3 current16 = texture2D(sNormalMap, vTexCoord).rgb;
        gl_FragColor = vec4(upsampled16 + current16, 1.0);
    #endif

    #ifdef DUALBLUR_UP8
        vec3 upsampled8 = DualKawaseUpsample(cBright8InvSize, sDiffMap, vScreenPos, cBloomHDRPlusIntensity).rgb;
        vec3 current8 = texture2D(sNormalMap, vTexCoord).rgb;
        gl_FragColor = vec4(upsampled8 + current8, 1.0);
    #endif

    #ifdef DUALBLUR_UP4
        vec3 upsampled4 = DualKawaseUpsample(cBright4InvSize, sDiffMap, vScreenPos, cBloomHDRPlusIntensity).rgb;
        vec3 current4 = texture2D(sNormalMap, vTexCoord).rgb;
        gl_FragColor = vec4(upsampled4 + current4, 1.0);
    #endif

    #ifdef DUALBLUR_UP2
        vec3 upsampled2 = DualKawaseUpsample(cBright2InvSize, sDiffMap, vScreenPos, cBloomHDRPlusIntensity).rgb;
        vec3 current2 = texture2D(sNormalMap, vTexCoord).rgb;
        gl_FragColor = vec4(upsampled2 + current2, 1.0);
    #endif

    // Final combine pass (same as GameBloomHDR COMBINE2 - uses weightBloom + ACES tonemapping)
    #ifdef DUALBLUR_COMBINE
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
