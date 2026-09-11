#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED
    #ifdef PERPIXEL
        $output vTexCoord , vTangent, vNormal, vWorldPos, vDetailTexCoord _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV
    #else
        $output vTexCoord , vTangent, vNormal, vWorldPos, vVertexLight, vScreenPos, vDetailTexCoord _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord , vTangent, vNormal, vWorldPos, vDetailTexCoord _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV
    #else
        $input vTexCoord , vTangent, vNormal, vWorldPos, vVertexLight, vScreenPos, vDetailTexCoord _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV
    #endif
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#include "constants.sh"
#ifdef COMPILEPS
#ifdef LIGHTMAP
#include "LightMap.sh"
#endif
#include "PBR/StandardPBR.sh"
#endif

SAMPLER2D(u_WeightMap0, 0);
SAMPLER2DARRAY(u_DetailArray1, 1);
SAMPLER2DARRAY(u_MixArray2, 2);
uniform vec2 u_DetailTiling;

#define sWeightMap u_WeightMap0
#define sDetailArray u_DetailArray1
#define sMixArray u_MixArray2
#define cDetailTiling u_DetailTiling

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vTexCoord.xy = GetTexCoord(iTexCoord);
    vDetailTexCoord = cDetailTiling * vTexCoord.xy;

    // TBN
    vec4 tangent = GetWorldTangent(modelMatrix);
    vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w;
    vTexCoord.zw = bitangent.xy;
    vTangent = vec4(tangent.xyz, bitangent.z);

    #if defined(AO)
        #if defined(SSAO)
            vAOUV = GetSSAOTexCoord(gl_Position);
        #else
            vAOUV = vec2(0.0, 0.0);
        #endif
    #endif

    #ifdef PERPIXEL
        // Per-pixel forward lighting
        vec4 projWorldPos = vec4(worldPos, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            GetShadowPos(projWorldPos, vNormal, vShadowPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = mul(projWorldPos, cLightMatrices[0]);
        #endif
    
        #ifdef POINTLIGHT
            vCubeMaskVec = mul((worldPos - cLightPos.xyz), mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz));
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
}

void PS()
{
    // Get material diffuse albedo
    vec3 weights = texture2D(sWeightMap, vTexCoord.xy).rgb;
    float sumWeights = weights.r + weights.g + weights.b;
    weights /= sumWeights;
    vec4 baseColor =
        weights.r * GammaToLinearSpace(texture2DArray(sDetailArray, vec3(vDetailTexCoord, 0))) +
        weights.g * GammaToLinearSpace(texture2DArray(sDetailArray, vec3(vDetailTexCoord, 1))) + 
        weights.b * GammaToLinearSpace(texture2DArray(sDetailArray, vec3(vDetailTexCoord, 2)));

    vec4 mixColor0 = GammaToLinearSpace(texture2DArray(sMixArray, vec3(vDetailTexCoord, 0)));
    vec4 mixColor1 = GammaToLinearSpace(texture2DArray(sMixArray, vec3(vDetailTexCoord, 1)));
    vec4 mixColor2 = GammaToLinearSpace(texture2DArray(sMixArray, vec3(vDetailTexCoord, 2)));

    vec3 normalDirection = 
        weights.r * DecodeNormal(mixColor0) +
        weights.g * DecodeNormal(mixColor1) +
        weights.b * DecodeNormal(mixColor2);

    vec2 metallicRoughness = 
        weights.r * mixColor0.wz +
        weights.g * mixColor1.wz + 
        weights.b * mixColor2.wz;

    // Get view dir (eyes dir)
    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);

    // Transform normal to worldspace
    mat3 tbn = TR(mat3(vTangent.xyz, vec3(vTexCoord.zw, vTangent.w), vNormal));
    normalDirection = normalize(mul(tbn, normalDirection));

    // Get shadow
    #ifdef SHADOW  
        vec3 shadowColor = GetShadow(vShadowPos, vWorldPos.w) * vec3(1.0, 1.0, 1.0);
    #else
        vec3 shadowColor = vec3(0.0, 0.0, 0.0);
    #endif

// Deferred
#if defined(MATERIALBAKE)
    EncodeGBufferBake(baseColor.rgb, baseColor.a, metallicRoughness.y, metallicRoughness.x, 1.0, normalDirection, vec3_splat(0.0));
#elif defined(DEFERRED)
    EncodeGBufferPBR(baseColor.rgb, metallicRoughness.x, 0.5, metallicRoughness.y, normalDirection, shadowColor, SHADINGMODELID_PBR_LIT);
#else
    // PBR calc
    vec3 finalColor = MetallicPBR(baseColor.rgb, metallicRoughness.x, 0.5, metallicRoughness.y, vWorldPos.xyz, normalDirection, viewDirection, shadowColor, 1.0);

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    // Mix final color and fog
    finalColor = GetFog(finalColor, fogFactor);

    // Gamma in shadering
    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        finalColor = LinearToGammaSpace(toAcesFilmic(finalColor));
    #endif

    gl_FragColor = vec4(finalColor, 1.0);
#endif    
}
