#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    #ifdef PERPIXEL
        $output vTexCoord, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #else
        $output vTexCoord, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
    #else
        $input vTexCoord, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV
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

uniform vec4 u_BackFaceColor;
uniform float u_BackFacePower;

uniform vec4 u_FresnelColor;
uniform float u_FresnelPower;
uniform float u_FresnelExtension;
uniform float u_FresnelFraction;
uniform float u_ColorFresnelAlpha;

uniform vec4 u_EmissiveFresnelColor;
uniform float u_EmissiveFresnelExtension;
uniform float u_EmissiveFresnelFraction;

uniform vec4 u_SubsurfaceColor;
uniform float u_SubsurfacePower;

uniform float u_FoliageStyle;
uniform float u_TwoSidedSignEffect;
uniform vec4 u_TwoSidedSignNormalColor;

uniform float u_HideEdgeFaces;
uniform float u_HideEdgePower;

uniform float u_AODensity;
uniform float u_GradientPower;
uniform float u_GradientRadius;
uniform vec4 u_GradientCenter;

uniform float u_HueShift;
uniform float u_SaturationAdjust;
uniform float u_ValueAdjust;

#define cBackFaceColor u_BackFaceColor
#define cBackFacePower u_BackFacePower
#define cFresnelColor u_FresnelColor
#define cFresnelPower u_FresnelPower
#define cFresnelExtension u_FresnelExtension
#define cFresnelFraction u_FresnelFraction
#define cColorFresnelAlpha u_ColorFresnelAlpha
#define cEmissiveFresnelColor u_EmissiveFresnelColor
#define cEmissiveFresnelExtension u_EmissiveFresnelExtension
#define cEmissiveFresnelFraction u_EmissiveFresnelFraction
#define cSubsurfaceColor u_SubsurfaceColor
#define cSubsurfacePower u_SubsurfacePower
#define cFoliageStyle u_FoliageStyle
#define cTwoSidedSignEffect u_TwoSidedSignEffect
#define cTwoSidedSignNormalColor u_TwoSidedSignNormalColor
#define cHideEdgeFaces u_HideEdgeFaces
#define cHideEdgePower u_HideEdgePower
#define cAODensity u_AODensity
#define cGradientPower u_GradientPower
#define cGradientRadius u_GradientRadius
#define cGradientCenter u_GradientCenter

#define cHueShift u_HueShift
#define cSaturationAdjust u_SaturationAdjust
#define cValueAdjust u_ValueAdjust

float GaussianAO(vec2 uv, vec2 center, float invRadius, float density)
{
    vec2 offset = uv - center;
    float dist = length(offset) * invRadius;
    float x = 1.0 - dist;
    float g = (abs(x) > 0.00001 && x >= 0.0) ? (1.0 / exp(x * density * x * density)) : 1.0;
    return 1.0 - (1.0 - g);
}

// UE M_Leaves HSV (HueShift + Desaturation + Multiply)
//   Sat=0.5 = 恒等; <0.5 去饱和; >0.5 增饱和
//   Val=0.4 = 恒等(× 1.0); 0=黑; 1=× 2.5
vec3 RotateAroundAxis(vec3 value, vec3 axis, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return value * c + cross(axis, value) * s + axis * dot(axis, value) * (1.0 - c);
}

vec3 ApplyHSV(vec3 color, float hueShift, float satParam, float valParam)
{
    vec3 axis = normalize(vec3(1.0, 1.0, 1.0));
    vec3 rotated = RotateAroundAxis(color, axis, hueShift * 6.28318530718);
    float luminance = dot(rotated, vec3(0.21263900, 0.71516865, 0.07219232));
    vec3 saturated = lerp(rotated, vec3(luminance, luminance, luminance), 1.0 - 2.0 * satParam);
    return saturated * (valParam * 2.5);
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

    vNormal *= cNormalOddNegativeScale;

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    vTexCoord = GetTexCoord(iTexCoord);

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
            // UE5 "Hide faces seen from edge": geometric face normal via screen derivatives
            // Blueprint: DDX/DDY → Cross → Normalize → Dot(CamVec) → Abs → Multiply chain → pow
            vec3 faceNormal = normalize(cross(dFdx(vWorldPos.xyz), dFdy(vWorldPos.xyz)));
            float edgeDot = abs(dot(normalize(cCameraPosPS - vWorldPos.xyz), faceNormal));
            float edgeMask = pow(max(edgeDot, 0.0), cHideEdgePower);
            diffInput.a *= lerp(1.0, edgeMask, cHideEdgeFaces);

            if (diffInput.a < 0.5)
                discard;
            diffInput.rgb *= min(1.0 / diffInput.a, 2.0);
            diffInput.a = 1.0;
        #endif
        // FoliageStyle: 0=color*texture, 1=flat color (alpha always from texture)
        vec4 baseColor = vec4(
            lerp(cMatDiffColor.rgb * diffInput.rgb, cMatDiffColor.rgb, cFoliageStyle),
            cMatDiffColor.a * diffInput.a
        );
    #else
        vec4 baseColor = cMatDiffColor;
    #endif

    #ifdef VERTEXCOLOR
        baseColor *= vColor;
    #endif

    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);
    vec3 geomNormal = normalize(vNormal);
    vec3 origNormal = geomNormal;

    bool isBackFace = (dot(viewDirection, geomNormal) < 0.0);

    if (isBackFace)
    {
        geomNormal = -geomNormal;

        // TwoSidedSign: blend back-face normal toward a fixed direction for consistent lighting
        if (cTwoSidedSignEffect > 0.0)
            geomNormal = normalize(lerp(geomNormal, cTwoSidedSignNormalColor.rgb, cTwoSidedSignEffect));

        #ifdef DIFFMAP
            baseColor.rgb = lerp(cBackFaceColor.rgb * diffInput.rgb, cBackFaceColor.rgb, cFoliageStyle);
        #else
            baseColor.rgb = cBackFaceColor.rgb;
        #endif
    }

    // UE M_Leaves HSV (Sat=0.5/Val=0.4 = 恒等基线; 偏离值用于 C5/C6 等变体)
    baseColor.rgb = ApplyHSV(baseColor.rgb, cHueShift, cSaturationAdjust, cValueAdjust);

    // UE M_Leaves Color Fresnel: pow(fresnelDot + Extension, Power) * Fraction
    //   Fraction=0 → 完全无 rim (即使 Power/Extension 非零)
    //   ColorFresnelAlpha 作为最终乘子(0=禁用整个 fresnel rim)
    float fresnelDot = 1.0 - max(dot(viewDirection, geomNormal), 0.0);
    if (cColorFresnelAlpha > 0.0)
    {
        float fresnelMask = clamp(pow(fresnelDot + cFresnelExtension, cFresnelPower) * cFresnelFraction, 0.0, 1.0);
        baseColor.rgb = lerp(baseColor.rgb, cFresnelColor.rgb, fresnelMask * cColorFresnelAlpha);
    }

    if (cAODensity > 0.0)
    {
        float invRadius = 1.0 / max(cGradientRadius, 0.001);
        float ao = GaussianAO(vTexCoord.xy, cGradientCenter.xy, invRadius, cGradientPower);
        baseColor.rgb *= lerp(1.0, ao, cAODensity);
    }

    float roughness = cRoughness;
    float metallic = cMetallic;
    float occlusion = 1.0;
    float specular = max(cMatSpecColor.r, max(cMatSpecColor.g, cMatSpecColor.b));

    vec3 normalDirection = geomNormal;

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

    {
        vec3 lightDir = normalize(cLightDirPS);

        float wrapNoL = clamp((-dot(origNormal, lightDir) + 0.5) / 2.25, 0.0, 1.0);

        float negVoL = clamp(-dot(viewDirection, lightDir), 0.0, 1.0);
        float scatter = GGXTerm(negVoL, 0.6);

        #ifdef DIFFMAP
            vec3 subColor = lerp(cSubsurfaceColor.rgb * diffInput.rgb, cSubsurfaceColor.rgb, cFoliageStyle);
        #else
            vec3 subColor = cSubsurfaceColor.rgb;
        #endif
        finalColor += subColor * wrapNoL * scatter * cLightColor.rgb * shadowColor.rgb;
    }

    #ifdef AMBIENT
        #ifdef EMISSIVEMAP
            finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, vTexCoord.xy).rgb;
        #else
            finalColor += cMatEmissiveColor;
        #endif

        if (cEmissiveFresnelColor.a > 0.0)
        {
            float eMask = clamp(
                pow(max(fresnelDot, 0.0001), max(cEmissiveFresnelExtension, 0.001))
                    * (1.0 - cEmissiveFresnelFraction) + cEmissiveFresnelFraction,
                0.0, 1.0);
            finalColor += eMask * cEmissiveFresnelColor.rgb;
        }
    #endif

    finalColor = GetFog(finalColor, fogFactor);

    gl_FragColor = vec4(finalColor, baseColor.a);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
    #endif
#endif
}
