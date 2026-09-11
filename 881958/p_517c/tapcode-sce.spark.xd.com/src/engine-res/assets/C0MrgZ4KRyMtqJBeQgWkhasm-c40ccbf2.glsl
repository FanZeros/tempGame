#include "varying_scenepass_depth.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    #if defined(SPEED_GRASS) || defined(VERTEX_ANIMATION)
        #define _GRASS_NORMAL , a_normal
    #else
        #define _GRASS_NORMAL
    #endif
    $input a_position _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA3 _GRASS_NORMAL
    $output vTexCoord

    uniform vec2 u_LerpTransform;
    #define _LerpTransform u_LerpTransform
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
    #if defined(TERRAIN_SINK_AO_FIX) && defined(SSAO)
        worldPos.z += floor(iColor.r * 255.0 + 0.5);
    #endif
    #ifdef BLEND_DRAWABLE
        float lerpFactor = mix(_LerpTransform.x, _LerpTransform.y, iColor.a);
        worldPos.z = mix(modelMatrix[3].z, worldPos.z, lerpFactor);
    #endif
    gl_Position = GetClipPos(worldPos);
    vTexCoord = vec3(tTexCoord, GetDepth(gl_Position));
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

    gl_FragColor = vec4(EncodeDepth(vTexCoord.z), 1.0);
}
