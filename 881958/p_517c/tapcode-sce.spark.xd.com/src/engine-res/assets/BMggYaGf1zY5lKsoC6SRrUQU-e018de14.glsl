#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"

$input a_position _OBJECTPOS _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
#ifdef PERPIXEL
    $output vTexCoord _VTANGENT, vNormal, vWorldPos _VTERRAINDATAUV _VPAINTUV _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR, vDrawableInfo _AOUV _VCLUSTERVS _VLIGHTMAPUV _VTEXCOORD3 _VPLANTMASK
#else
    $output vTexCoord _VTANGENT, vNormal, vWorldPos _VTERRAINDATAUV _VPAINTUV, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR, vDrawableInfo _AOUV _VCLUSTERVS _VLIGHTMAPUV _VTEXCOORD3 _VPLANTMASK
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#include "constants.sh"
#if defined(SPEED_GRASS) || defined(VERTEX_ANIMATION)
#include "LitSolid/VertexAnimation.sh"
#endif
#if defined(WIND_EFFECT)
#include "WindEffect.sh"
#endif
#if defined(PLANT_ANIMATION)
#include "PlantAnimation.sh"
#endif

#ifdef LIGHTMAP
#include "LightMap.sh"
#endif

#if defined(COMPILEVS) && defined(CLUSTER_VS)
#include "PBR/GI.sh"
#include "Cluster/clusterlights.sh"
#include "Cluster/clusters.sh"
#endif

void VS()
{
    #ifdef NOUV
    vec2 iTexCoord = vec2(0.0, 0.0);
    #endif

    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    #ifdef WORLD_TILING
        vNormal = iNormal.xyz;
    #else
        vNormal = GetWorldNormal(modelMatrix);
    #endif

    vec2 tTexCoord = GetTexCoord(iTexCoord);
    hvec3 originPos = worldPos;
    #ifdef SPEED_GRASS
        worldPos = worldPos + GetWindEffect(worldPos, tTexCoord, vNormal);
    #elif defined(VERTEX_ANIMATION)
        worldPos = worldPos + SimpleVertexAnimation(worldPos, iColor.r, vNormal);
    #endif
    //WIND_EFFECT能和VERTEX_ANIMATION叠加
    #if defined(WIND_EFFECT)
        worldPos = worldPos + GetWindEffectPosition(worldPos, modelMatrix[3].xyz);
    #endif

    #ifdef PLANT_ANIMATION
        worldPos = worldPos + GetPlantVariation(worldPos);
    #endif

    vNormal *= cNormalOddNegativeScale;

    #ifdef DISSOLVEUP
        worldPos.z += _DissolveRate * _DissolveRate * 200.0;
    #endif

    gl_Position = GetClipPos(worldPos);
    vWorldPos = hvec4_init(worldPos, GetDepth(gl_Position));

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #ifdef NORMALMAP
        #ifdef WORLD_TILING
            vec4 tangent = iTangent;
        #else
            vec4 tangent = GetWorldTangent(modelMatrix);
        #endif
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w * cBitangentOddNegativeScale;
        vTexCoord = vec4(tTexCoord, bitangent.xy);
        vTangent = vec4(tangent.xyz, bitangent.z);
    #else
        vTexCoord = tTexCoord;
    #endif

    #if defined(AO)
        #if defined(SSAO)
            vAOUV = GetSSAOTexCoord(gl_Position);
        #else
            vAOUV = iTexCoord1.xy;
        #endif
    #endif

    #if defined(LIGHTMAP)
        #if defined(SPEED_GRASS) || defined(SCE_GRASS)
            vLightMapUV = GetTileLightMapUV(vWorldPos.xy - cTerrainOffset, vec2(256.0, 256.0));
        #else
            vLightMapUV = GetLightMapUV(iTexCoord1.xy);
        #endif
    #endif

    #ifndef PAINTABLE
        // Terrain data uv
        // 注意：
        // 1.使用云阴影时CPU传入的cWeatherTiling=vec2(0, 0)，这样vTerrainDataUV.z=0.0，于是Pixel采样Texture2DArray时使用layer=0
        // 2.使用天气系统时，cWeatherTiling为正常的tiling
        // 因为云阴影和天气系统不会同时存在，所以这里可以省一个float的varying变量
        vTerrainDataUV = vec4((vWorldPos.xy - cTerrainOffset) / cTerrainSize, (originPos.xy - cTerrainOffset) * cWeatherTiling);
    #endif

    #ifdef PAINTABLE
        vPaintUV = iTexCoord1.xy;
    #endif

    #ifdef NO_SPEC_UV_ANIMATION
        vTexCoord3 = iTexCoord;
    #endif

    vDrawableInfo = hvec4_init(iGroundZ, iBBoxMaxZ, iBBoxMinZ, iObjectType);

    #ifdef PERPIXEL
        // Per-pixel forward lighting
        hvec4 projWorldPos = hvec4_init(originPos, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            GetShadowPos(projWorldPos, vNormal, vShadowPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = mul(projWorldPos, cLightMatrices[0]);
        #endif
    
        #ifdef POINTLIGHT
            vCubeMaskVec = mul(vec4(worldPos - cLightPos.xyz, 0.0), cLightMatrices[0]).xyz;
        #endif
    #else
        // Ambient & per-vertex lighting
        #if defined(LIGHTMAP) || defined(AO)
            // If using lightmap, disregard zone ambient light
            // If using AO, calculate ambient in the PS
            vVertexLight = vec3(0.0, 0.0, 0.0);
            vTexCoord2 = iTexCoord1;
        #else
            vVertexLight = GetAmbient(GetZonePos(worldPos));
        #endif
        
        #ifdef NUMVERTEXLIGHTS
            for (int i = 0; i < NUMVERTEXLIGHTS; ++i)
                vVertexLight += GetVertexLight(i, worldPos, vNormal) * cVertexLights[i * 3].rgb;
        #endif
        
        vScreenPos = GetScreenPos(gl_Position);

        #ifdef ENVCUBEMAP
            vReflectionVec = worldPos - cCameraPos;
        #endif
    #endif

#ifdef CLUSTER_VS
    vec3 vecIrrR, vecIrrG, vecIrrB, mrpDir;
    vec4 mrp;
    vec3 viewDirection = normalize(cCameraPos - worldPos);
    getClusterLightVS(gl_Position, viewDirection, vecIrrR, vecIrrG, vecIrrB, mrpDir, mrp);
    vVecIrrR.rgb = vecIrrR;
    vVecIrrG.rgb = vecIrrG;
    vVecIrrR.w = vecIrrB.r;
    vVecIrrG.w = vecIrrB.g;
    vMrpDir = vec4(mrpDir, vecIrrB.b);
    vMrp = mrp;
#endif
}
