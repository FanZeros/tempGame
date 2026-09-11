/*
 * Object Velocity (per-drawable)
 * Writes MotionVector RG = currUV - prevUV for moving geometry.
 * Camera MV fullscreen pass already filled static pixels; this pass
 * depth-equals overwrites movers only.
 *
 * Curr / Prev transforms are VS-only (rigid: cModel + cPrevModel;
 * skinned TX: sBoneMtxMap + sPrevBoneMtxMap 同 UV).
 */

#define VELOCITY_PASS

#include "varying_scenepass_velocity.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA3
    $output vTexCoord, vCurrClip, vPrevClip
#endif
#ifdef COMPILEPS
    $input vTexCoord, vCurrClip, vPrevClip
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"

// Unjittered matrices (ApplyMotionVectorParameters)
uniform hmat4 u_UnjitteredViewProj;
uniform hmat4 u_PrevViewProj;
// Rigid prev model (Batch::Prepare velocity)
uniform hmat4 u_PrevModel;

#ifdef METALLIC
    #define sMaskTextureMap sSpecMap
#else
    #define sMaskTextureMap sDiffMap
#endif

void VS()
{
    #ifdef NOUV
    vec2 iTexCoord = vec2(0.0, 0.0);
    #endif
    hmat4 currM = iModelMatrix;
    hvec3 worldPos = GetWorldPos(currM);

#if defined(SKIN_MATRIX_TEXTURE)
    // TX：curr/prev 均为 world-space skin，同 UV 换 sampler
    hmat4 prevM = TR(GetSkinMatrixFromPrevTexture(iBlendWeights, iBlendIndices));
    hvec3 prevWorldPos = mul(iPos, prevM).xyz;
#else
    hmat4 prevM = u_PrevModel;
    hvec3 prevWorldPos = mul(iPos, prevM).xyz;
#endif

    // 光栅 z 必须与 Pre-Z/GBuffer 一致：command 开 jitter 时 GetClipPos 带 TAA jitter，
    // 才能 depth-equal 命中；MV 本身用 unjittered，避免把 jitter 编进 velocity。
    gl_Position = GetClipPos(worldPos);
    vCurrClip = mul(hvec4_init(worldPos, 1.0), u_UnjitteredViewProj);
    vPrevClip = mul(hvec4_init(prevWorldPos, 1.0), u_PrevViewProj);
    vTexCoord = GetTexCoord(iTexCoord);
}

void PS()
{
#ifdef ALPHAMASK
    #if defined(ALPHAMASK_DIFF_R)
        float alpha = texture2D(sMaskTextureMap, vTexCoord).r;
    #elif defined(ALPHAMASK_DIFF_G)
        float alpha = texture2D(sMaskTextureMap, vTexCoord).g;
    #elif defined(ALPHAMASK_DIFF_B)
        float alpha = texture2D(sMaskTextureMap, vTexCoord).b;
    #elif defined(ALPHAMASK_DIFF_A)
        float alpha = texture2D(sMaskTextureMap, vTexCoord).a;
    #else
        float alpha = texture2D(sMaskTextureMap, vTexCoord).a;
    #endif
    if (alpha < 0.5)
        discard;
#endif

    hvec2 currNDC = vCurrClip.xy / max(vCurrClip.w, 1e-6);
    hvec2 prevNDC = vPrevClip.xy / max(vPrevClip.w, 1e-6);
    hvec2 currUV = currNDC * 0.5 + 0.5;
    hvec2 prevUV = prevNDC * 0.5 + 0.5;

    // D3D：clip.y 与 UV.y 方向相反（与 MotionVector.glsl 一致）
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    currUV.y = 1.0 - currUV.y;
    prevUV.y = 1.0 - prevUV.y;
#endif

    hvec2 motion = clamp(currUV - prevUV, vec2_splat(-0.5), vec2_splat(0.5));
    gl_FragColor = hvec4_init(motion.x, motion.y, 0.0, 1.0);
}
