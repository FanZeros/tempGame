#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    #ifdef PERPIXEL
        $output vTexCoord _VTANGENT, vNormal, vWorldPos, vNodePos, vDrawableInfo _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #else
        $output vTexCoord _VTANGENT, vNormal, vWorldPos, vNodePos, vDrawableInfo, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord _VTANGENT, vNormal, vWorldPos, vNodePos, vDrawableInfo _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #else
        $input vTexCoord _VTANGENT, vNormal, vWorldPos, vNodePos, vDrawableInfo, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
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
uniform vec4 u_TriplanarParams;
uniform vec4 u_TriplanarOffset;
uniform vec4 u_TriplanarNormalFade;

#define cTextureMetallicFactor u_TextureMetallicFactor
#define cTextureRoughnessFactor u_TextureRoughnessFactor
#define cTintColor u_TintColor
#define cTriplanarAnchor u_TriplanarParams.x
#define cTriplanarTileSize u_TriplanarParams.y
#define cTriplanarBlendSharpness u_TriplanarParams.z
#define cTriplanarNormalStrength u_TriplanarParams.w
#define cTriplanarOffset u_TriplanarOffset
#define cTriplanarNormalFade u_TriplanarNormalFade

vec3 GetTriplanarWeights(vec3 normalDirection)
{
    float blendSharpness = max(cTriplanarBlendSharpness, 0.001);
    vec3 weights = pow(abs(normalDirection), vec3(blendSharpness, blendSharpness, blendSharpness));
    return weights / max(weights.x + weights.y + weights.z, 0.0001);
}

vec2 GetTriplanarUV(vec3 position, int axis)
{
    float tileSize = max(cTriplanarTileSize, 0.001);
    vec3 p = position + cTriplanarOffset.xyz;

    if (axis == 0)
        return p.zy / tileSize;
    if (axis == 1)
        return p.xz / tileSize;
    return p.xy / tileSize;
}

vec4 SampleTriplanarDiff(vec3 position, vec3 weights)
{
    vec4 xSample = texture2D(sDiffMap, GetTriplanarUV(position, 0));
    vec4 ySample = texture2D(sDiffMap, GetTriplanarUV(position, 1));
    vec4 zSample = texture2D(sDiffMap, GetTriplanarUV(position, 2));
    return xSample * weights.x + ySample * weights.y + zSample * weights.z;
}

vec4 SampleTriplanarSpec(vec3 position, vec3 weights)
{
    vec4 xSample = texture2D(sSpecMap, GetTriplanarUV(position, 0));
    vec4 ySample = texture2D(sSpecMap, GetTriplanarUV(position, 1));
    vec4 zSample = texture2D(sSpecMap, GetTriplanarUV(position, 2));
    return xSample * weights.x + ySample * weights.y + zSample * weights.z;
}

#ifdef NORMALMAP
float AxisSign(float value)
{
    return value < 0.0 ? -1.0 : 1.0;
}

float GetDistanceNormalStrength(vec3 worldPosition)
{
    float fullStrength = max(cTriplanarNormalStrength, 0.0);
    float fadeStart = cTriplanarNormalFade.x;
    float fadeEnd = cTriplanarNormalFade.y;
    float minStrength = clamp(cTriplanarNormalFade.z, 0.0, fullStrength);

    if (fadeEnd <= fadeStart)
        return fullStrength;

    float viewDistance = distance(worldPosition, cCameraPosPS);
    float fade = 1.0 - clamp((viewDistance - fadeStart) / max(fadeEnd - fadeStart, 0.001), 0.0, 1.0);
    return mix(minStrength, fullStrength, fade);
}

vec3 ApplyNormalStrength(vec3 normalInput, float strength)
{
    normalInput.xy *= strength;
    return normalize(normalInput);
}

vec3 SampleTriplanarNormal(vec3 position, vec3 weights, vec3 surfaceNormal, float normalStrength)
{
    vec3 xNormal = ApplyNormalStrength(DecodeNormal(texture2D(sNormalMap, GetTriplanarUV(position, 0))), normalStrength);
    vec3 yNormal = ApplyNormalStrength(DecodeNormal(texture2D(sNormalMap, GetTriplanarUV(position, 1))), normalStrength);
    vec3 zNormal = ApplyNormalStrength(DecodeNormal(texture2D(sNormalMap, GetTriplanarUV(position, 2))), normalStrength);

    vec3 mappedX = vec3(xNormal.z * AxisSign(surfaceNormal.x), xNormal.y, xNormal.x);
    vec3 mappedY = vec3(yNormal.x, yNormal.z * AxisSign(surfaceNormal.y), yNormal.y);
    vec3 mappedZ = vec3(zNormal.x, zNormal.y, zNormal.z * AxisSign(surfaceNormal.z));

    return normalize(mappedX * weights.x + mappedY * weights.y + mappedZ * weights.z);
}
#endif
#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);

    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vNormal *= cNormalOddNegativeScale;

    vec3 objectAxisScale = vec3(
        length(mul(vec4(1.0, 0.0, 0.0, 0.0), modelMatrix).xyz),
        length(mul(vec4(0.0, 1.0, 0.0, 0.0), modelMatrix).xyz),
        length(mul(vec4(0.0, 0.0, 1.0, 0.0), modelMatrix).xyz)
    );
    vec3 objectAxisX = normalize(mul(vec4(1.0, 0.0, 0.0, 0.0), modelMatrix).xyz);
    vec3 objectAxisY = normalize(mul(vec4(0.0, 1.0, 0.0, 0.0), modelMatrix).xyz);

    vNodePos = vec4(iPos.xyz * objectAxisScale, 0.0);
    vDrawableInfo = vec4(objectAxisY, 0.0);
    #ifdef NORMALMAP
        vTexCoord = vec4(0.0, 0.0, 0.0, 0.0);
        vTangent = vec4(objectAxisX, 0.0);
    #else
        vTexCoord = vec2(0.0, 0.0);
    #endif

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #if defined(AO)
        #if defined(SSAO)
            vAOUV = GetSSAOTexCoord(gl_Position);
        #else
            vAOUV = iTexCoord1.xy;
        #endif
    #endif

    #if defined(LIGHTMAP)
        vLightMapUV = GetLightMapUV(iTexCoord1.xy);
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
    float anchor = step(0.5, cTriplanarAnchor);
    vec3 samplePosition = lerp(vWorldPos.xyz, vNodePos.xyz, anchor);
    vec3 objectAxisX = normalize(vTangent.xyz);
    vec3 objectAxisY = normalize(vDrawableInfo.xyz);
    vec3 objectAxisZ = normalize(cross(objectAxisX, objectAxisY));
    vec3 objectSpaceNormal = normalize(vec3(dot(vNormal, objectAxisX), dot(vNormal, objectAxisY), dot(vNormal, objectAxisZ)));
    vec3 sampleNormal = normalize(lerp(vNormal, objectSpaceNormal, anchor));
    vec3 triplanarWeights = GetTriplanarWeights(sampleNormal);

    #ifdef DIFFMAP
        vec4 diffInput = SampleTriplanarDiff(samplePosition, triplanarWeights);
        #ifdef NOT_SUPPORT_SRGB
            diffInput = GammaToLinearSpace(diffInput);
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
        vec4 roughMetalSrc = SampleTriplanarSpec(samplePosition, triplanarWeights);

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

    float specular = max(cMatSpecColor.r, max(cMatSpecColor.g, cMatSpecColor.b));
    #ifdef NORMALMAP
        float normalStrength = GetDistanceNormalStrength(vWorldPos.xyz);
        vec3 triplanarNormal = SampleTriplanarNormal(samplePosition, triplanarWeights, sampleNormal, normalStrength);
        vec3 objectNormalDirection = normalize(
            triplanarNormal.x * objectAxisX +
            triplanarNormal.y * objectAxisY +
            triplanarNormal.z * objectAxisZ
        );
        vec3 normalDirection = normalize(lerp(triplanarNormal, objectNormalDirection, anchor));
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

    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);

#if defined(DEFERRED)
    EncodeGBufferPBR(baseColor.rgb, metallic, specular, roughness, normalDirection, cMatEmissiveColor, SHADINGMODELID_PBR_LIT);
#else
    vec3 finalColor = MetallicPBR(baseColor.rgb, metallic, specular, roughness, vWorldPos.xyz, normalDirection, viewDirection, shadowColor.rgb, occlusion
    #ifdef DEFERRED_CLUSTER
        , LinearizeDepth(gl_FragCoord.z, cNearClipPS, cFarClipPS)
    #endif
        );

    #ifdef AMBIENT
        finalColor += cMatEmissiveColor;
    #endif

    finalColor = GetFog(finalColor, fogFactor);
    gl_FragColor = vec4(finalColor, 1.0);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
    #endif
#endif
}
