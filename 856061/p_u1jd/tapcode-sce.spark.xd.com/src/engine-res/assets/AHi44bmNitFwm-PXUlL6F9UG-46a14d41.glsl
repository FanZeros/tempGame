#ifdef BGFX_SHADER
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

#else

#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"

varying vec2 vTexCoord;
varying vec2 vScreenPos;

#endif // BGFX_SHADER

#ifdef COMPILEPS
    #ifdef BGFX_SHADER
        #ifdef BLURH
        uniform hvec4 u_Blur2InvSize;
        #define cBlurInvSize vec2(u_Blur2InvSize.xy)
        #endif
        #ifdef BLURV
        uniform hvec4 u_Bright2InvSize;
        #define cBlurInvSize vec2(u_Bright2InvSize.xy)
        #endif
    #else
        uniform hvec2 cBlurInvSize;
    #endif
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
    #ifdef BLURH
    vec3 rgb = texture2D(sDiffMap, vTexCoord + vec2(-6.0, 0.0) * cBlurInvSize).rgb * 0.05;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(-2.0, 0.0) * cBlurInvSize).rgb * 0.1;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(-1.0, 0.0) * cBlurInvSize).rgb * 0.15;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, 0.0) * cBlurInvSize).rgb * 0.4;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(1.0, 0.0) * cBlurInvSize).rgb * 0.15;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(2.0, 0.0) * cBlurInvSize).rgb * 0.1;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(6.0, 0.0) * cBlurInvSize).rgb * 0.05;
    gl_FragColor = vec4(rgb, 1.0);
    #endif

    #ifdef BLURV
    vec3 rgb = texture2D(sDiffMap, vTexCoord + vec2(0.0, -6.0) * cBlurInvSize).rgb * 0.05;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, -2.0) * cBlurInvSize).rgb * 0.1;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, -1.0) * cBlurInvSize).rgb * 0.15;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, 0.0) * cBlurInvSize).rgb * 0.4;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, 1.0) * cBlurInvSize).rgb * 0.15;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, 2.0) * cBlurInvSize).rgb * 0.1;
    rgb += texture2D(sDiffMap, vTexCoord + vec2(0.0, 6.0) * cBlurInvSize).rgb * 0.05;
    gl_FragColor = vec4(rgb, 1.0);
    #endif

    #ifdef COMBINE
        vec3 color = texture2D(sDiffMap, vScreenPos).rgb;   
        #ifdef GAMMA_IN_SHADERING
        gl_FragColor = vec4(LinearToGammaSpace(color), 1.0);
        #else
        gl_FragColor = vec4(color, 1.0);
        #endif
    #endif
}

