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

uniform vec4 u_BackFaceColor;
uniform float u_BackFacePower;

uniform vec4 u_FresnelColor;
uniform float u_FresnelPower;
uniform float u_FresnelExtension;
uniform float u_FresnelFraction;

uniform vec4 u_EmissiveFresnelParams;

uniform vec4 u_SubsurfaceColor;
uniform float u_SubsurfacePower;

uniform float u_HueShift;
uniform float u_SaturationAdjust;
uniform float u_ValueAdjust;

uniform float u_AODensity;
uniform float u_GradientPower;
uniform float u_GradientRadius;
uniform vec4 u_GradientCenter;

#define cTextureMetallicFactor u_TextureMetallicFactor
#define cTextureRoughnessFactor u_TextureRoughnessFactor
#define cBackFaceColor u_BackFaceColor
#define cBackFacePower u_BackFacePower
#define cFresnelColor u_FresnelColor
#define cFresnelPower u_FresnelPower
#define cFresnelExtension u_FresnelExtension
#define cFresnelFraction u_FresnelFraction
#define cEmissiveFresnelParams u_EmissiveFresnelParams
#define cSubsurfaceColor u_SubsurfaceColor
#define cSubsurfacePower u_SubsurfacePower
#define cHueShift u_HueShift
#define cSaturationAdjust u_SaturationAdjust
#define cValueAdjust u_ValueAdjust
#define cAODensity u_AODensity
#define cGradientPower u_GradientPower
#define cGradientRadius u_GradientRadius
#define cGradientCenter u_GradientCenter

vec3 RGBtoHSV(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = lerp(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = lerp(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 HSVtoRGB(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 ApplyHSV(vec3 color, float hueShift, float satMul, float valMul)
{
    vec3 hsv = RGBtoHSV(color);
    hsv.x = fract(hsv.x + hueShift);
    hsv.y = clamp(hsv.y * satMul, 0.0, 1.0);
    hsv.z = clamp(hsv.z * valMul, 0.0, 1.0);
    return HSVtoRGB(hsv);
}

float RadialGradient(vec2 uv, vec2 center, float radius, float power)
{
    float dist = length(uv - center) / max(radius, 0.001);
    return pow(clamp(1.0 - dist, 0.0, 1.0), power);
}
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

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #if defined(NORMALMAP) || defined(DIRBILLBOARD)
        vec4 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w;
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
        vec4 projWorldPos = vec4(worldPos, 1.0);

        #ifdef SHADOW
            GetShadowPos(projWorldPos, vNormal, vShadowPos);
        #endif

        #ifdef SPOTLIGHT
            vSpotPos = mul(projWorldPos, cLightMatrices[0]);
        #endif
    
        #ifdef POINTLIGHT
            vCubeMaskVec = mul((worldPos - cLightPos.xyz), mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz));
        #endif
    #else
        #if defined(LIGHTMAP) || defined(AO)
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
    #ifdef DIFFMAP
        #ifdef NOT_SUPPORT_SRGB
            vec4 diffInput = GammaToLinearSpace(texture2D(sDiffMap, vTexCoord.xy));
        #else
            vec4 diffInput = texture2D(sDiffMap, vTexCoord.xy);
        #endif
        #ifdef ALPHAMASK
            if (diffInput.a < 0.333)
                discard;
            diffInput.a = 1.0;
        #endif
        vec4 baseColor = cMatDiffColor * diffInput;
    #else
        vec4 baseColor = cMatDiffColor;
    #endif

    #ifdef VERTEXCOLOR
        baseColor *= vColor;
    #endif

    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);
    vec3 geomNormal = normalize(vNormal);

    bool isBackFace = (dot(viewDirection, geomNormal) < 0.0);
    if (isBackFace)
    {
        baseColor.rgb = lerp(baseColor.rgb, cBackFaceColor.rgb, cBackFacePower);
    }

    if (cHueShift != 0.0 || cSaturationAdjust != 1.0 || cValueAdjust != 1.0)
    {
        baseColor.rgb = ApplyHSV(baseColor.rgb, cHueShift, cSaturationAdjust, cValueAdjust);
    }

    float fresnelDot = 1.0 - max(dot(viewDirection, geomNormal), 0.0);
    float fresnelMask = clamp(pow(fresnelDot + cFresnelExtension, cFresnelPower) * cFresnelFraction, 0.0, 1.0);
    baseColor.rgb = lerp(baseColor.rgb, cFresnelColor.rgb, fresnelMask);

    if (cAODensity > 0.0)
    {
        float radialAO = RadialGradient(vTexCoord.xy, cGradientCenter.xy, cGradientRadius, cGradientPower);
        baseColor.rgb *= lerp(1.0, radialAO, cAODensity);
    }

    #ifdef METALLIC
        vec4 roughMetalSrc = texture2D(sSpecMap, vTexCoord.xy);

        float roughness = roughMetalSrc.r * cTextureRoughnessFactor;
        float metallic = roughMetalSrc.g * cTextureMetallicFactor;
        float occlusion = roughMetalSrc.b;
    #else
        float roughness = cRoughness;
        float metallic = cMetallic;
        float occlusion = 1.0;
    #endif

    float specular = max(cMatSpecColor.r, max(cMatSpecColor.g, cMatSpecColor.b));

    #if defined(NORMALMAP) || defined(DIRBILLBOARD)
        vec3 tangent = vTangent.xyz;
        vec3 bitangent = vec3(vTexCoord.zw, vTangent.w);
        mat3 tbn = TR(mat3(tangent, bitangent, vNormal));
    #endif

    #ifdef NORMALMAP
        vec3 nn = DecodeNormal(texture2D(sNormalMap, vTexCoord.xy));
        vec3 normalDirection = normalize(mul(tbn, nn));
    #else
        vec3 normalDirection = normalize(vNormal);
    #endif

    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    vec4 shadowColor = vec4(1.0, 1.0, 1.0, 1.0);

    #ifdef SHADOW  
        shadowColor.rgb = shadowColor.rgb * GetShadow(vShadowPos, vWorldPos.w);
    #endif

#if defined(DEFERRED)
    EncodeGBufferPBR(baseColor.rgb, metallic, specular, roughness, normalDirection, cMatEmissiveColor, SHADINGMODELID_PBR_LIT);
#else
    vec3 finalColor = MetallicPBR(baseColor.rgb, metallic, specular, roughness, vWorldPos.xyz, normalDirection, viewDirection, shadowColor.rgb, occlusion
    #ifdef USES_ANISOTROPY
        , cAnisotropy
    #endif
        );

    if (isBackFace)
    {
        float translucency = max(dot(-geomNormal, normalize(cLightDirPS)), 0.0);
        finalColor += cSubsurfaceColor.rgb * translucency * cLightColor.rgb * cSubsurfacePower * shadowColor.rgb;
    }

    float emissiveFresnel = clamp(
        pow(fresnelDot + cEmissiveFresnelParams.y, cEmissiveFresnelParams.x) * cEmissiveFresnelParams.z,
        0.0, 1.0);
    vec3 emissiveContrib = cMatEmissiveColor * cEmissiveFresnelParams.w * emissiveFresnel;

    #ifdef EMISSIVEMAP
        finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, vTexCoord.xy).rgb;
    #else
        finalColor += cMatEmissiveColor;
    #endif
    finalColor += emissiveContrib;

    finalColor = GetFog(finalColor, fogFactor);

    gl_FragColor = vec4(finalColor, baseColor.a);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
    #endif
#endif
}
