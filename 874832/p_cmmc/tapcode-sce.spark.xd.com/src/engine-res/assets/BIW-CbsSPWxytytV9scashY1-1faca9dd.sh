#include "Toon/ToonUniforms.sh"
#include "SurfaceOutline.sh"

// 2-bit Area Type，高位=皮肤族：11=Face 10=Skin 01=Hair 00=Default。
// 该编码让皮肤/脸判定退化为单条 step，无逻辑运算。
#define TOON_AREA_DEFAULT 0.0
#define TOON_AREA_HAIR 1.0
#define TOON_AREA_SKIN 2.0
#define TOON_AREA_FACE 3.0
#define TOON_FACE_SHADOW_LIFT 0.5
#define TOON_LOW_SATURATION_SCALE 5.0
#define TOON_NDOTV_RIM_MIDPOINT 0.6
#define TOON_NDOTV_RIM_TRANSITION 0.02
#define TOON_NDOTV_RIM_DERIVATIVE_SCALE 50.0
#define TOON_DEPTH_RIM_BASE_THRESHOLD 0.05
#define TOON_DEPTH_RIM_FADEOUT_SCALE 10.0
#define TOON_DEPTH_SHADOW_BASE_THRESHOLD 0.03
#define TOON_DEPTH_SHADOW_FADEOUT_SCALE 50.0
#define TOON_DEPTH_ORTHO_DISTANCE_FIX 0.7
#define TOON_DEPTH_ORTHO_SIZE_SCALE 100.0

// Forward / Forward+：只有 litbase 带 AMBIENT，用它认出写底那一次。
// Deferred：每盏 Light Volume 都带 AMBIENT，改用 DIRLIGHT；平行光 Replace 覆盖，与旧链路一致。
// CLUSTER_BASE 是无真实太阳时的黑色载体，直接光已被关掉，不能当太阳。
#if defined(DIRLIGHT) && !defined(CLUSTER_BASE) && (defined(AMBIENT) || defined(DEFERRED))
    #define TOON_FULL_SHADE
#endif

float ToonSkinAreaMask(float areaType)
{
    return step(1.5, areaType); // 2/3 -> 1
}

float ToonFaceAreaMask(float areaType)
{
    return step(2.5, areaType); // 3 -> 1
}

vec3 ToonRgbToHsv(vec3 color)
{
    vec4 k = vec4(0.0, -0.3333333333, 0.6666666667, -1.0);
    vec4 p = mix(vec4(color.bg, k.wz), vec4(color.gb, k.xy), step(color.b, color.g));
    vec4 q = mix(vec4(p.xyw, color.r), vec4(color.r, p.yzx), step(p.x, color.r));
    float delta = q.x - min(q.w, q.y);
    float epsilon = M_EPSILON;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * delta + epsilon)), delta / (q.x + epsilon), q.x);
}

vec3 ToonHsvToRgb(vec3 color)
{
    vec3 p = abs(fract(color.xxx + vec3(0.0, 0.6666666667, 0.3333333333)) * 6.0 - 3.0);
    return color.z * mix(vec3_splat(1.0), saturate(p - 1.0), color.y);
}

float GetToonBand(ToonSurfaceParams toonParams, vec3 normalDirection, vec3 lightDirection, float areaType,
    float softness)
{
    float faceMask = ToonFaceAreaMask(areaType);
    vec3 lightingNormal = mix(normalDirection, -GetCameraForwardDir(), faceMask);
    float midpoint = mix(toonParams.midpoint, -0.3, faceMask);
    softness = mix(clamp(softness, 0.001, 1.0), 1.0, faceMask);
    return smoothstep(midpoint - softness, midpoint + softness,
        dot(lightingNormal, lightDirection));
}

vec3 GetToonGenericShadowColor(ToonSurfaceParams toonParams, vec3 baseColor)
{
    float saturationBoost = saturate(toonParams.shadowHSV.y);
    float valueMultiplier = max(toonParams.shadowHSV.z, 0.0);

    // Zero Hue Offset is the common path. Fold HSV saturation adjustment and
    // low-saturation fallback into RGB space to avoid both color conversions.
    BRANCH if (toonParams.shadowHSV.x == 0.0)
    {
        float maxColor = max(max(baseColor.r, baseColor.g), baseColor.b);
        float minColor = min(min(baseColor.r, baseColor.g), baseColor.b);
        float chroma = maxColor - minColor;
        float denominator = max(max(chroma, maxColor / TOON_LOW_SATURATION_SCALE), M_EPSILON);
        float saturationScale = 1.0 + saturationBoost * minColor / denominator;
        return (maxColor + (baseColor - maxColor) * saturationScale) * valueMultiplier;
    }

    vec3 hsv = ToonRgbToHsv(baseColor);
    float originalSaturation = hsv.y;
    hsv.x += toonParams.shadowHSV.x;
    hsv.y = mix(hsv.y, 1.0, saturationBoost);
    hsv.z *= valueMultiplier;

    vec3 hsvShadow = ToonHsvToRgb(hsv);
    vec3 neutralShadow = baseColor * valueMultiplier;
    return mix(neutralShadow, hsvShadow,
        saturate(originalSaturation * TOON_LOW_SATURATION_SCALE));
}

vec3 GetToonSkinShadowColor(ToonSurfaceParams toonParams, vec3 baseColor, float areaType)
{
    vec3 skinShadow = baseColor * max(toonParams.skinShadowTint.rgb, vec3_splat(0.0));
    skinShadow += TOON_FACE_SHADOW_LIFT * max(skinShadow * (1.0 - skinShadow), vec3_splat(0.0))
        * ToonFaceAreaMask(areaType);
    return skinShadow;
}

vec3 GetToonShadowColor(ToonSurfaceParams toonParams, vec3 baseColor, float areaType)
{
    float skinInfluence = ToonSkinAreaMask(areaType) * saturate(toonParams.skinShadowTint.a);
    BRANCH if (skinInfluence <= 0.0)
        return GetToonGenericShadowColor(toonParams, baseColor);

    vec3 skinShadow = GetToonSkinShadowColor(toonParams, baseColor, areaType);
    BRANCH if (skinInfluence >= 1.0)
        return skinShadow;

    return mix(GetToonGenericShadowColor(toonParams, baseColor), skinShadow, skinInfluence);
}

float GetToonShadowAttenuation(vec3 shadow)
{
    return saturate(dot(shadow, vec3(0.2126, 0.7152, 0.0722)));
}

float GetToonNdotVRimMask(vec3 normalDirection, vec3 viewDirection,
    vec3 lightDirection, float areaType)
{
    float rimAttenuation = 1.0 - saturate(dot(normalDirection, viewDirection));
    float NoL = dot(normalDirection, lightDirection);
    rimAttenuation *= saturate(NoL) * 0.25 + 0.75;
    rimAttenuation *= step(0.0, NoL);
    rimAttenuation *= 1.0 - ToonFaceAreaMask(areaType);

    float derivativeFix = saturate((abs(dFdx(rimAttenuation)) + abs(dFdy(rimAttenuation))) * TOON_NDOTV_RIM_DERIVATIVE_SCALE);
    return smoothstep(
        TOON_NDOTV_RIM_MIDPOINT - TOON_NDOTV_RIM_TRANSITION,
        TOON_NDOTV_RIM_MIDPOINT + TOON_NDOTV_RIM_TRANSITION,
        rimAttenuation) * derivativeFix;
}

vec2 GetToonDepthMasks(vec2 screenUV, float currentLinearDepth, vec3 normalDirection,
    vec3 viewDirection, vec3 lightDirection, float areaType)
{
#if defined(DEFERRED) && RENDER_QUALITY >= RENDER_QUALITY_HIGH
    BRANCH if (cToonDepthEffectsSimpleOffset != 0.0)
    {
        vec3 lightDirectionVS = mul(hvec4_init(lightDirection, 0.0), cView).xyz;
        float faceMask = ToonFaceAreaMask(areaType);
        float faceDepthEffectsSimpleOffsetMultiplier = mix(
            1.0, cToonFaceDepthEffectsSimpleOffsetMultiplier, faceMask);
        // Match the reference depth-texture offset: closer objects get a larger
        // screen-space sample, then divide by FOV / ortho size.
        float cameraDistanceFix = cProj[3][3] == 0.0
            ? 1.0 / (1.0 + max(currentLinearDepth, 0.0))
            : TOON_DEPTH_ORTHO_DISTANCE_FIX;
        float verticalFocal = max(abs(cProj[1][1]), 1e-6);
        float fovOrOrthoSizeFix = cProj[3][3] == 0.0
            ? 1.0 / (2.0 * atan(1.0 / verticalFocal) * (180.0 / 3.14159265))
            : verticalFocal / TOON_DEPTH_ORTHO_SIZE_SCALE;
        float widthMultiplier = cToonDepthEffectsSimpleOffset * faceDepthEffectsSimpleOffsetMultiplier
            * cameraDistanceFix * fovOrOrthoSizeFix;
        // Reference applies (height/width, 1) * width / FOV directly in UV space.
        vec2 offsetUV = screenUV + lightDirectionVS.xy * vec2(
            cGBufferInvSize.x / max(cGBufferInvSize.y, 1e-6), 1.0) * widthMultiplier;
        offsetUV = clamp(offsetUV, vec2_splat(0.0), vec2_splat(1.0));
        float sampledRawDepth = texture2D(u_GBuffer4, offsetUV).r;
        float sampledLinearDepth = LinearizeDepth(sampledRawDepth, cNearClipPS, cFarClipPS);
        float depthDifference = sampledLinearDepth - currentLinearDepth;

        // Threshold is a signed offset on a fixed base, not an absolute meter value.
        float rimThreshold = saturate(TOON_DEPTH_RIM_BASE_THRESHOLD + cToonDepthRimThreshold);
        float rimFade = max(cToonDepthRimFadeRange, 0.01);
        float rimMask = saturate((depthDifference - rimThreshold)
            * TOON_DEPTH_RIM_FADEOUT_SCALE / rimFade);

        float shadowThreshold =
            TOON_DEPTH_SHADOW_BASE_THRESHOLD
            + cToonDepthShadowThreshold;
        float shadowFade = max(cToonDepthShadowFadeRange, 0.01);
        float shadowVisibility = saturate((depthDifference + shadowThreshold)
            * TOON_DEPTH_SHADOW_FADEOUT_SCALE / shadowFade);
        float shadowMask = (1.0 - shadowVisibility) * saturate(cToonDepthShadowInfluence);
        return vec2(rimMask, shadowMask);
    }
#endif

    // Deferred keeps only the final shading normal in GBuffer, so its NdotV fallback cannot recover
    // the interpolated geometric normal. The preferred high-quality Depth Rim path above is unaffected.
    return vec2(GetToonNdotVRimMask(normalDirection, viewDirection,
        lightDirection, areaType), 0.0);
}

vec3 GetToonMainDiffuse(ToonSurfaceParams toonParams, vec3 baseColor, vec3 normalDirection, vec3 rimNormalDirection,
    vec3 viewDirection, vec3 lightDirection, float areaType, float softness, float shadowAttenuation,
    vec2 screenUV, float currentLinearDepth, bool enableDepthEffects, out float outRimMask)
{
    float litBand = GetToonBand(toonParams, normalDirection, lightDirection, areaType, softness)
        * saturate(shadowAttenuation);
    vec2 depthMasks = enableDepthEffects
        ? GetToonDepthMasks(screenUV, currentLinearDepth, rimNormalDirection, viewDirection, lightDirection, areaType)
        : vec2(0.0, 0.0);
    outRimMask = depthMasks.x;
    float depthVisibility = 1.0 - depthMasks.y;
    float litVisibility = saturate(litBand * depthVisibility);
    BRANCH if (litVisibility >= 1.0)
        return baseColor;
    return mix(GetToonShadowColor(toonParams, baseColor, areaType), baseColor, litVisibility);
}

vec3 GetToonMainLightFactor(vec3 lightColor, float attenuation)
{
    vec3 factor = max(lightColor * attenuation, vec3_splat(0.0));
    return min(factor, max(cToonMainLightMax, vec3_splat(0.0)))
        * max(cToonMainLightMul, vec3_splat(0.0));
}

// Rim 是 max(direct, indirect) 之后的独立加法项。
// 阴影内降至 25% 而非清零；主光色 min(2) 防过曝并叠加 5% 保底（无主光也有微弱 Rim）。
vec3 GetToonRimLighting(ToonSurfaceParams toonParams, float rimMask, float shadowAttenuation, vec3 mainLightColor)
{
    float shadowMul = mix(0.25, 1.0, saturate(shadowAttenuation));
    vec3 rimColor = vec3_splat(0.05)
        + min(max(mainLightColor, vec3_splat(0.0)), vec3_splat(2.0)) * toonParams.rimColor.rgb / 6.0;
    return rimMask * shadowMul * rimColor * max(toonParams.rimColor.a, 0.0);
}

vec3 GetToonAdditionalDiffuse(vec3 baseColor, vec3 normalDirection,
    vec3 lightDirection, float attenuation, float shadowAttenuation, vec3 lightColor, float areaType)
{
    vec3 additionalLightNormal = mix(normalDirection, -GetCameraForwardDir(),
        ToonFaceAreaMask(areaType));
    float angular = 0.8 + 0.2 * dot(additionalLightNormal, lightDirection);
    float boundedAttenuation = min(1.0, max(attenuation, 0.0));
    return baseColor * lightColor * angular * boundedAttenuation * shadowAttenuation * 0.5;
}

vec3 GetToonDirectSpecular(vec3 specularColor, float roughness, float perceptualRoughness,
    vec3 normalDirection, vec3 viewDirection, vec3 lightDirection)
{
    float NdotV = abs(dot(normalDirection, viewDirection));
    return GetSpecularColor(specularColor, roughness, perceptualRoughness,
        normalDirection, viewDirection, lightDirection, NdotV);
}

struct ToonDirectDiffuseLighting
{
    vec3 lighting;
    float rimMask;
    vec3 mainLightColor;
    vec3 mainLightDirection;
    float mainShadowAttenuation;
    vec3 mainLightFactor;
};

ToonDirectDiffuseLighting EvaluateToonDirectDiffuseLighting(ToonSurfaceParams toonParams, vec3 baseColor, hvec3 worldPos,
    vec3 normalDirection, vec3 rimNormalDirection, vec3 viewDirection, vec3 shadow, float areaType, float softness,
    vec2 screenUV, float currentLinearDepth, bool enableDepthEffects
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
)
{
    ToonDirectDiffuseLighting result;
    result.lighting = vec3_splat(0.0);
    result.rimMask = 0.0;
    result.mainLightColor = vec3_splat(0.0);
    result.mainLightDirection = vec3_splat(0.0);
    result.mainShadowAttenuation = 1.0;
    result.mainLightFactor = vec3_splat(0.0);

#if defined(PERPIXEL)
    hvec3 lightColor;
    vec3 lightDirection;
    hfloat attenuation;

#if (defined(DIRLIGHT) && !defined(CLUSTER_BASE)) || !defined(CLUSTER)
    lightColor = GI_GetLightColor();
    attenuation = GI_GetAttenAndLightDir(worldPos, lightDirection);
    float shadowAttenuation = GetToonShadowAttenuation(shadow);

    #ifdef TOON_FULL_SHADE
        result.mainLightColor = vec3(lightColor);
        result.mainLightDirection = lightDirection;
        result.mainShadowAttenuation = shadowAttenuation;
        result.mainLightFactor = GetToonMainLightFactor(lightColor, attenuation);
        float rimMask;
        vec3 directDiffuse = GetToonMainDiffuse(toonParams, baseColor, normalDirection, rimNormalDirection, viewDirection,
            lightDirection, areaType, softness, shadowAttenuation, screenUV, currentLinearDepth,
            enableDepthEffects, rimMask);
        result.lighting += directDiffuse * result.mainLightFactor;
        result.rimMask = rimMask;
    #else
        result.lighting += GetToonAdditionalDiffuse(baseColor, normalDirection,
            lightDirection, attenuation, shadowAttenuation, max(lightColor, vec3_splat(0.0)), areaType);
    #endif
#endif

#if defined(LIGHTMAP)
    #if RENDER_QUALITY >= RENDER_QUALITY_HIGH && defined(LIGHTMAP_DIRECTIONALITY)
        vec3 lightMapDirection;
        vec4 lightMapColor = GetLightMapColor(vLightMapUV.xy, normalDirection, lightMapDirection);
    #else
        vec4 lightMapColor = GetLightMapColor(vLightMapUV.xy, normalDirection);
    #endif
    result.lighting += baseColor * lightMapColor.rgb;
#endif

#if defined(CLUSTER)
    #ifdef CLUSTER_VS
        if (vMrp.w > 0.0)
        {
            vec3 irradiance = vec3(dot(normalDirection, vVecIrrR.rgb), dot(normalDirection, vVecIrrG.rgb),
                dot(normalDirection, vec3(vVecIrrR.w, vVecIrrG.w, vMrpDir.w)));
            result.lighting += max(irradiance, vec3_splat(0.0)) * baseColor * 0.5;
        }
    #else
        #ifdef DEFERRED_CLUSTER
            uint cluster = getDeferredClusterIndex(gl_FragCoord.xy, sceneDepth);
        #else
            hvec4 realCoord = getRealCoord(gl_FragCoord);
            uint cluster = getClusterIndex(realCoord);
        #endif
        LightGrid grid = getLightGrid(cluster);
        LOOP
        for (uint i = 0u; i < grid.pointLights; ++i)
        {
            uint lightIndex = GetGridLightIndex(grid.offset, i);
            #ifdef CLUSTER_SPOTLIGHT
                SpotLight light = GetSpotLight(lightIndex);
            #else
                PointLight light = GetPointLight(lightIndex);
            #endif
            lightColor = light.intensity;
            attenuation = GI_PointLight_GetAttenAndLightDir(
                worldPos, light.position, light.range, lightDirection);
            #ifdef CLUSTER_SPOTLIGHT
                attenuation *= GetLightDirectionFalloff(
                    lightDirection, light.direction, light.cosOuterCone, light.invCosConeDiff);
            #endif
            result.lighting += GetToonAdditionalDiffuse(baseColor, normalDirection,
                lightDirection, attenuation, 1.0, max(lightColor, vec3_splat(0.0)), areaType);
        }
    #endif
#endif
#endif

    return result;
}

void EvaluateToonDirectLighting(ToonSurfaceParams toonParams, vec3 baseColor, vec3 specularColor, float roughness,
    float perceptualRoughness, hvec3 worldPos, vec3 normalDirection, vec3 rimNormalDirection, vec3 viewDirection,
    vec3 shadow, float areaType, float softness, vec2 screenUV, float currentLinearDepth, bool enableDepthEffects
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
    , out vec3 directLighting, out vec3 rimLighting)
{
    ToonDirectDiffuseLighting result = EvaluateToonDirectDiffuseLighting(toonParams, baseColor, worldPos,
        normalDirection, rimNormalDirection, viewDirection, shadow, areaType, softness, screenUV, currentLinearDepth, enableDepthEffects
#ifdef DEFERRED_CLUSTER
        , sceneDepth
#endif
    );
    directLighting = result.lighting;
    rimLighting = vec3_splat(0.0);

#ifdef TOON_FULL_SHADE
    directLighting += GetToonDirectSpecular(specularColor, roughness, perceptualRoughness,
        normalDirection, viewDirection, result.mainLightDirection)
        * result.mainShadowAttenuation * result.mainLightFactor;
    rimLighting = GetToonRimLighting(toonParams, result.rimMask, result.mainShadowAttenuation,
        result.mainLightColor);
#endif
}

vec3 EvaluateToonIndirectDiffuseLighting(vec3 diffuseColor, float occlusion)
{
    return GI_IndirectDiffuse(vec3_splat(0.0), occlusion) * diffuseColor;
}

void EvaluateToonIndirectLighting(vec3 diffuseColor, vec3 specularColor, float oneMinusReflectivity,
    float roughness, float perceptualRoughness, vec3 normalDirection, vec3 indirectNormalDirection,
    vec3 viewDirection, float occlusion,
    out vec3 indirectDiffuse, out vec3 indirectSpecular)
{
    indirectDiffuse = EvaluateToonIndirectDiffuseLighting(diffuseColor, occlusion);
    indirectSpecular = GI_IndirectSpecular(normalDirection, viewDirection, perceptualRoughness, occlusion);
    float NdotV = abs(dot(normalDirection, viewDirection));
#if UNITY_ENV_BRDF
    float surfaceReduction = 1.0 / (roughness * roughness + 1.0);
    float grazingTerm = clamp(1.0 - perceptualRoughness + (1.0 - oneMinusReflectivity),
        0.0, sce_EnvFresnelEdgeStrength);
    indirectSpecular *= surfaceReduction
        * FresnelLerp(specularColor, vec3_splat(grazingTerm), NdotV);
#else
    indirectSpecular *= EnvBRDFApprox(specularColor, perceptualRoughness, NdotV);
#endif
}

vec3 MetallicToonPBR(ToonSurfaceParams toonParams, vec3 baseColor, float metallic, float specular, float perceptualRoughness,
    hvec3 worldPos, vec3 normalDirection, vec3 indirectNormalDirection, vec3 viewDirection,
    vec3 shadow, float occlusion, float areaType, float softness, vec2 screenUV, float currentLinearDepth
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
)
{
#ifdef WEATHER_EFFECT
    WeatherEffect(baseColor, perceptualRoughness, metallic, normalDirection);
#endif
#if defined(PAINTABLE) && defined(PAINTABLE_UV_AVAILABLE)
    ApplyPaintMap(baseColor, metallic, perceptualRoughness);
#endif
    perceptualRoughness = mix(perceptualRoughness, cGlobalRoughness, cGlobalRoughnessOn);
    float oneMinusReflectivity;
    vec3 specularColor = vec3_splat(specular);
    vec3 diffuseColor = DiffuseAndSpecularFromMetallicEx(
        baseColor, metallic, specularColor, oneMinusReflectivity);
    float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);

    vec3 finalColor;
    vec3 rimLighting;
    EvaluateToonDirectLighting(toonParams, baseColor, specularColor, roughness, perceptualRoughness,
        worldPos, normalDirection, indirectNormalDirection, viewDirection, shadow, areaType, softness, screenUV, currentLinearDepth, true
#ifdef DEFERRED_CLUSTER
        , sceneDepth
#endif
        , finalColor, rimLighting);

#if defined(AMBIENT)
    // Forward 只有 litbase 带 AMBIENT；Deferred 每盏 Light Volume 都有，靠平行光 Replace 留下最后一次。
    vec3 indirectDiffuse;
    vec3 indirectSpecular;
    EvaluateToonIndirectLighting(diffuseColor, specularColor, oneMinusReflectivity,
        roughness, perceptualRoughness, normalDirection, indirectNormalDirection, viewDirection, occlusion,
        indirectDiffuse, indirectSpecular);
    // 间接漫反射只作暗部托底，逐通道 max 避免加法冲淡 Toon 明暗分区。
    finalColor = max(finalColor, indirectDiffuse) + indirectSpecular;
#endif
    // Rim 在 max 合成之后追加，避免被环境漫反射 max 吞掉
    finalColor += rimLighting;
    return finalColor;
}

vec3 MetallicToonOutline(ToonSurfaceParams toonParams, vec3 outlineAlbedo, hvec3 worldPos, vec3 normalDirection,
    vec3 indirectNormalDirection, vec3 viewDirection, vec3 shadow, float occlusion, float areaType, float softness,
    float outlineBrightness
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
)
{
#if RENDER_QUALITY < RENDER_QUALITY_HIGH
    return outlineAlbedo * max(outlineBrightness, 0.0);
#else
    ToonDirectDiffuseLighting direct = EvaluateToonDirectDiffuseLighting(toonParams, outlineAlbedo, worldPos,
        normalDirection, indirectNormalDirection, viewDirection, shadow, areaType, softness, vec2_splat(0.0), 0.0, false
#ifdef DEFERRED_CLUSTER
        , sceneDepth
#endif
    );
    vec3 indirectDiffuse = EvaluateToonIndirectDiffuseLighting(outlineAlbedo, occlusion);
    return max(direct.lighting, indirectDiffuse) * max(outlineBrightness, 0.0);
#endif
}

#ifdef SPLIT_LIGHTING
void MetallicToonPBR_Split(ToonSurfaceParams toonParams, vec3 baseColor, float metallic, float specular, float perceptualRoughness,
    hvec3 worldPos, vec3 normalDirection, vec3 indirectNormalDirection, vec3 viewDirection,
    vec3 shadow, float occlusion,
    float areaType, float softness, vec2 screenUV, float currentLinearDepth
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
    , out vec3 outSceneLighting, out vec3 outEnvSpecular)
{
#ifdef WEATHER_EFFECT
    WeatherEffect(baseColor, perceptualRoughness, metallic, normalDirection);
#endif
#if defined(PAINTABLE) && defined(PAINTABLE_UV_AVAILABLE)
    ApplyPaintMap(baseColor, metallic, perceptualRoughness);
#endif
    perceptualRoughness = mix(perceptualRoughness, cGlobalRoughness, cGlobalRoughnessOn);
    float oneMinusReflectivity;
    vec3 specularColor = vec3_splat(specular);
    vec3 diffuseColor = DiffuseAndSpecularFromMetallicEx(
        baseColor, metallic, specularColor, oneMinusReflectivity);
    float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);

    vec3 directLighting;
    vec3 rimLighting;
    EvaluateToonDirectLighting(toonParams, baseColor, specularColor, roughness, perceptualRoughness,
        worldPos, normalDirection, indirectNormalDirection, viewDirection, shadow, areaType, softness, screenUV, currentLinearDepth, true
#ifdef DEFERRED_CLUSTER
        , sceneDepth
#endif
        , directLighting, rimLighting);
    vec3 indirectDiffuse;
    EvaluateToonIndirectLighting(diffuseColor, specularColor, oneMinusReflectivity,
        roughness, perceptualRoughness, normalDirection, indirectNormalDirection, viewDirection, occlusion,
        indirectDiffuse, outEnvSpecular);
    outSceneLighting = max(directLighting, indirectDiffuse) + rimLighting;
}

void MetallicToonOutline_Split(ToonSurfaceParams toonParams, vec3 outlineAlbedo, hvec3 worldPos, vec3 normalDirection,
    vec3 indirectNormalDirection, vec3 viewDirection, vec3 shadow, float occlusion, float areaType, float softness,
    float outlineBrightness
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
    , out vec3 outSceneLighting)
{
#if RENDER_QUALITY < RENDER_QUALITY_HIGH
    outSceneLighting = outlineAlbedo * max(outlineBrightness, 0.0);
#else
    ToonDirectDiffuseLighting direct = EvaluateToonDirectDiffuseLighting(toonParams, outlineAlbedo, worldPos,
        normalDirection, indirectNormalDirection, viewDirection, shadow, areaType, softness, vec2_splat(0.0), 0.0, false
#ifdef DEFERRED_CLUSTER
        , sceneDepth
#endif
    );
    float brightness = max(outlineBrightness, 0.0);
    vec3 indirectDiffuse = EvaluateToonIndirectDiffuseLighting(outlineAlbedo, occlusion);
    outSceneLighting = max(direct.lighting, indirectDiffuse) * brightness;
#endif
}
#endif
