#ifndef __TOON_UNIFORMS_SH__
#define __TOON_UNIFORMS_SH__

#define TOON_DEFAULT_SOFTNESS 0.025

#if COMPILEPS

// Toon zone and runtime lighting parameters.
// Softness is a Surface output (SOFTNESS), not a Zone uniform.
uniform float u_ToonMidpoint;
uniform vec3 u_ToonShadowHSV;
uniform vec4 u_ToonSkinShadowTint;
uniform vec3 u_ToonMainLightMax;
uniform vec3 u_ToonMainLightMul;
uniform vec4 u_ToonRimColor;
uniform vec2 u_ToonDepthEffectsOffset;
uniform vec2 u_ToonDepthRim;
uniform vec3 u_ToonDepthShadow;

struct ToonSurfaceParams
{
    float midpoint;
    vec3 shadowHSV;
    vec4 skinShadowTint;
    vec4 rimColor;
};

ToonSurfaceParams GetZoneToonSurfaceParams()
{
    ToonSurfaceParams result;
    result.midpoint = u_ToonMidpoint;
    result.shadowHSV = u_ToonShadowHSV;
    result.skinShadowTint = u_ToonSkinShadowTint;
    result.rimColor = u_ToonRimColor;
    return result;
}

#define cToonMainLightMax u_ToonMainLightMax
#define cToonMainLightMul u_ToonMainLightMul

#define cToonDepthEffectsSimpleOffset u_ToonDepthEffectsOffset.x
#define cToonFaceDepthEffectsSimpleOffsetMultiplier u_ToonDepthEffectsOffset.y

#define cToonDepthRimThreshold u_ToonDepthRim.x
#define cToonDepthRimFadeRange u_ToonDepthRim.y

#define cToonDepthShadowInfluence u_ToonDepthShadow.x
#define cToonDepthShadowThreshold u_ToonDepthShadow.y
#define cToonDepthShadowFadeRange u_ToonDepthShadow.z

#endif

#endif
