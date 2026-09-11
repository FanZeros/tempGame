#include "varying_shadow.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _OBJECTPOS _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA3
    $output vTexCoord
#endif
#ifdef COMPILEPS
    $input vTexCoord
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "constants.sh"
#if defined(SPEED_GRASS) || defined(VERTEX_ANIMATION)
#include "LitSolid/VertexAnimation.sh"
#endif
#if defined(WIND_EFFECT)
#include "WindEffect.sh"
#endif

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
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    vec2 tTexCoord = GetTexCoord(iTexCoord);
    #ifdef VSM_SHADOW
        vTexCoord = vec4(tTexCoord, gl_Position.z, gl_Position.w);
    #else
        vTexCoord = tTexCoord;
    #endif
    #ifdef SPEED_GRASS
        vec3 tNormal = GetWorldNormal(modelMatrix);
        worldPos = worldPos + GetWindEffect(worldPos, tTexCoord, tNormal);
    #elif defined(VERTEX_ANIMATION)
        vec3 tNormal = GetWorldNormal(modelMatrix);
        worldPos = worldPos + SimpleVertexAnimation(worldPos, iColor.r, tNormal);
    #endif
    #if defined(WIND_EFFECT)
        worldPos = worldPos + GetWindEffectPosition(worldPos, modelMatrix[3].xyz);
    #endif
    gl_Position = GetClipPos(worldPos);
}

void PS()
{
    #ifdef ALPHAMASK
        #if defined(ALPHAMASK_DIFF_R)
            float alpha = texture2D(sMaskTextureMap, vTexCoord.xy).r;
        #elif defined(ALPHAMASK_DIFF_G)
            float alpha = texture2D(sMaskTextureMap, vTexCoord.xy).g;
        #elif defined(ALPHAMASK_DIFF_B)
            float alpha = texture2D(sMaskTextureMap, vTexCoord.xy).b;
        #elif defined(ALPHAMASK_DIFF_A)
            float alpha = texture2D(sMaskTextureMap, vTexCoord.xy).a;
        #else
            float alpha = texture2D(sMaskTextureMap, vTexCoord.xy).a;
        #endif
        if (alpha < 0.5)
            discard;
    #endif

    #ifdef VSM_SHADOW
        float depth = vTexCoord.z / vTexCoord.w * 0.5 + 0.5;
        gl_FragColor = vec4(depth, depth * depth, 1.0, 1.0);
    #else
        gl_FragColor = vec4_splat(1.0);
    #endif
}
