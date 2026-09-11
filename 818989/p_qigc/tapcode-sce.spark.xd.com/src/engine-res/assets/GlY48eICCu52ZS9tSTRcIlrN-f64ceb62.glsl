#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
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
#include "constants.sh"

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

const int BlurKernelSize = 5;
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
    #ifdef BRIGHT
        gl_FragColor = ExtractBright(texture2D(sDiffMap, vScreenPos), cBloomHDRThreshold);
    #endif

    #ifdef BLUR16
        gl_FragColor = GaussianBlur(BlurKernelSize, cBloomHDRBlurDir, cBright16InvSize * cBloomHDRBlurRadius, cBloomHDRBlurSigma, sDiffMap, vScreenPos);
    #endif

    #ifdef BLUR8
        gl_FragColor = GaussianBlur(BlurKernelSize, cBloomHDRBlurDir, cBright8InvSize * cBloomHDRBlurRadius, cBloomHDRBlurSigma, sDiffMap, vScreenPos);
    #endif

    #ifdef BLUR4
        gl_FragColor = GaussianBlur(BlurKernelSize, cBloomHDRBlurDir, cBright4InvSize * cBloomHDRBlurRadius, cBloomHDRBlurSigma, sDiffMap, vScreenPos);
    #endif

    #ifdef BLUR2
        gl_FragColor = GaussianBlur(BlurKernelSize, cBloomHDRBlurDir, cBright2InvSize * cBloomHDRBlurRadius, cBloomHDRBlurSigma, sDiffMap, vScreenPos);
    #endif

    #ifdef COMBINE16
        gl_FragColor = texture2D(sDiffMap, vScreenPos) + texture2D(sNormalMap, vTexCoord);
    #endif

    #ifdef COMBINE8
        gl_FragColor = texture2D(sDiffMap, vScreenPos) + texture2D(sNormalMap, vTexCoord);
    #endif

    #ifdef COMBINE4
        gl_FragColor = texture2D(sDiffMap, vScreenPos) + texture2D(sNormalMap, vTexCoord);
    #endif

    #ifdef COMBINE2
        vec3 color = texture2D(sDiffMap, vScreenPos).rgb * cBloomHDRMix.x;
        vec3 bloom = texture2D(sNormalMap, vTexCoord).rgb * cBloomHDRMix.y;

        #ifndef DISABLE_TONEMAPPINGS
            color = toAcesFilmic_HalfSafe(color + bloom);
        #else
            color = color + bloom;
        #endif
        
        #ifdef GAMMA_IN_SHADERING
            gl_FragColor = vec4(LinearToGammaSpace(color), 1.0);
        #else
            gl_FragColor = vec4(color, 1.0);
        #endif
    #endif
}
