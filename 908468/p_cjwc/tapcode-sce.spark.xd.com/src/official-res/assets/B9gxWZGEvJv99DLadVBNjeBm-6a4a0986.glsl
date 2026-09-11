#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    #ifdef PERPIXEL
        $output vTexCoord _VTANGENT, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #else
        $output vTexCoord _VTANGENT, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord _VTANGENT, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #else
        $input vTexCoord _VTANGENT, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
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
#ifdef LIGHTMAP
#include "LightMap.sh"
#endif
#if defined(COMPILEVS) && defined(CLUSTER_VS)
#include "PBR/GI.sh"
#include "Cluster/clusterlights.sh"
#include "Cluster/clusters.sh"
#endif
#if COMPILEPS
#include "PBR/StandardPBR.sh"

uniform float u_TextureMetallicFactor;
uniform float u_TextureRoughnessFactor;
uniform vec4 u_TintColor;
uniform float u_Anisotropy;

#ifdef CLEARCOAT
uniform float u_CoatRoughness;
uniform float u_CoatStrength;
#define cCoatRoughness u_CoatRoughness
#define cCoatStrength u_CoatStrength
#endif

#define cTextureMetallicFactor u_TextureMetallicFactor
#define cTextureRoughnessFactor u_TextureRoughnessFactor
#define cTintColor u_TintColor
#define cAnisotropy u_Anisotropy
#endif

void VS()
{
    #ifdef NOUV
    vec2 iTexCoord = vec2(0.0, 0.0);
    #endif
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    vNormal *= cNormalOddNegativeScale;

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #if defined(NORMALMAP) || defined(DIRBILLBOARD)
        vec4 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w * cBitangentOddNegativeScale;
        vTexCoord = vec4(GetTexCoord(iTexCoord), bitangent.xy);
        vTangent = vec4(tangent.xyz, bitangent.z);
    #else
        vTexCoord = GetTexCoord(iTexCoord);
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
    #ifdef DIFFMAP
        #ifdef NOT_SUPPORT_SRGB
            vec4 diffInput = GammaToLinearSpace(texture2D(sDiffMap, vTexCoord.xy));
        #else
            vec4 diffInput = texture2D(sDiffMap, vTexCoord.xy);
        #endif
        vec4 baseColor = cMatDiffColor * diffInput;
    #else
        vec4 baseColor = cMatDiffColor;
    #endif

    baseColor.rgb = lerp(baseColor.rgb, GetIntensity(baseColor.rgb) * cTintColor.rgb, cTintColor.a);

    #ifdef VERTEXCOLOR
        baseColor *= vColor;
    #endif

    #ifdef METALLIC
        vec4 roughMetalSrc = texture2D(sSpecMap, vTexCoord.xy);

        float roughness = roughMetalSrc.r * cTextureRoughnessFactor;
        float metallic = roughMetalSrc.g * cTextureMetallicFactor;
        float occlusion = roughMetalSrc.b;

        #ifdef ALPHAMASK
            if (roughMetalSrc.a < 0.5)
                discard;
        #endif
    #else
        float roughness = cRoughness;
        float metallic = cMetallic;
        float occlusion = 1.0;
    #endif

    // 为了兼容延迟渲染，只能使用max了（GBuffer编码不够用，实际上虚幻也是这样搞的）
    // 缺点就是无法支持带颜色的高光
    float specular = max(cMatSpecColor.r, max(cMatSpecColor.g, cMatSpecColor.b));

    // Get normal
    #if defined(NORMALMAP) || defined(DIRBILLBOARD)
        vec3 tangent = vTangent.xyz;
        vec3 bitangent = vec3(vTexCoord.zw, vTangent.w);
        mat3 tbn = TR(mat3(tangent, bitangent, vNormal));
    #endif

    #ifdef NORMALMAP
        vec3 nn = DecodeNormal(texture2D(sNormalMap, vTexCoord.xy));
        //nn.rg *= 2.0;
        vec3 normalDirection = normalize(mul(tbn, nn));
    #else
        vec3 normalDirection = normalize(vNormal);
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    vec4 shadowColor = vec4(1.0, 1.0, 1.0, 1.0);

    // Get shadow
    #ifdef SHADOW  
        shadowColor.rgb = shadowColor.rgb * GetShadow(vShadowPos, vWorldPos.w);
    #endif

    // Get view dir (eyes dir)
    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);

// Deferred
#if defined(DEFERRED)
    #ifdef CLEARCOAT
        vec3 coatNormalDirection = normalize(vNormal);  // Coat uses smooth vertex normal
        EncodeGBufferClearCoat(baseColor.rgb, metallic, specular, roughness, normalDirection, cCoatRoughness, cCoatStrength, coatNormalDirection, SHADINGMODELID_CLEARCOAT);
    #else
        EncodeGBufferPBR(baseColor.rgb, metallic, specular, roughness, normalDirection, cMatEmissiveColor, SHADINGMODELID_PBR_LIT);
    #endif
#else
    // PBR calc
    #ifdef CLEARCOAT
        vec3 coatNormalDirection = normalize(vNormal);  // Coat uses smooth vertex normal
        vec3 finalColor = ClearCoatPBR(baseColor.rgb, metallic, specular, roughness, vWorldPos.xyz, normalDirection, viewDirection, shadowColor.rgb, occlusion,
            cCoatRoughness, cCoatStrength, coatNormalDirection
        #ifdef USES_ANISOTROPY
            , cAnisotropy
        #endif
        #ifdef DEFERRED_CLUSTER
            , LinearizeDepth(gl_FragCoord.z, cNearClipPS, cFarClipPS)
        #endif
            );
    #else
        vec3 finalColor = MetallicPBR(baseColor.rgb, metallic, specular, roughness, vWorldPos.xyz, normalDirection, viewDirection, shadowColor.rgb, occlusion
        #ifdef USES_ANISOTROPY
            ,  cAnisotropy
        #endif
        #ifdef DEFERRED_CLUSTER
            , LinearizeDepth(gl_FragCoord.z, cNearClipPS, cFarClipPS)
        #endif
            );
    #endif

    // Add emissive color
    #ifdef AMBIENT
        #ifdef EMISSIVEMAP
            finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, vTexCoord.xy).rgb;
        #else
            finalColor += cMatEmissiveColor;
        #endif
    #endif

    // Mix final color and fog
    finalColor = GetFog(finalColor, fogFactor);

    // Final color
    gl_FragColor = vec4(finalColor, baseColor.a);

    // Gamma in shadering
    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
    #endif
#endif
}
