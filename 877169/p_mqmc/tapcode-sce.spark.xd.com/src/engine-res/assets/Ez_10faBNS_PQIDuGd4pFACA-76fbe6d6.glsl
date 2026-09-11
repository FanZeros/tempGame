#if defined(PAINTABLE) && defined(PAINTABLE_UV_AVAILABLE)
void ApplyPaintMap(inout vec3 diffuseColor, inout float metallic, inout float roughness)
{
    vec4 paintColor = texture2DArray(sPaintMap, vec3(vPaintUV, 0.0));
    vec4 paintMaterial = texture2DArray(sPaintMap, vec3(vPaintUV, 1.0));

    diffuseColor = mix(diffuseColor, paintColor.rgb, paintColor.a);
    metallic = mix(metallic, paintMaterial.r, paintMaterial.b);
    roughness = mix(roughness, paintMaterial.g, paintMaterial.a);
}
#endif

vec3 MetallicPBR(
    vec3 diffuseColor, 
    float metallic, 
    float specular, 
    float roughness, 
    hvec3 worldPos, 
    vec3 normalDirection, 
    vec3 viewDirection, 
    vec3 shadow, 
    float occlusion
#ifdef USES_ANISOTROPY
    , float anisotropy
#endif
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
#ifdef CLEAR_COAT
    , float clearCoatStrength, float clearCoatRoughness
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
    , vec3 bottomNormalDirection        // 底层 substrate 法线（A1：normalDirection 为顶层 coat）
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , vec3 subsurfaceColor
#endif
)
{
#ifdef WEATHER_EFFECT
    WeatherEffect(diffuseColor, roughness, metallic, normalDirection);
#endif
#if defined(PAINTABLE) && defined(PAINTABLE_UV_AVAILABLE)
    ApplyPaintMap(diffuseColor, metallic, roughness);
#endif

    roughness = mix(roughness, cGlobalRoughness, cGlobalRoughnessOn);

    float oneMinusReflectivity;
    vec3 specularColor = vec3(specular, specular, specular);
#ifdef CLEAR_COAT
    // 保存原始 BaseColor 给 ApplyClearCoat Transmission（DiffuseAndSpecularFromMetallicEx 会改 diffuseColor）
    vec3 ccBaseColor = diffuseColor;
#endif
    diffuseColor = DiffuseAndSpecularFromMetallicEx(diffuseColor, metallic, specularColor, oneMinusReflectivity);
    return Standard_BRDF(diffuseColor, specularColor, oneMinusReflectivity, 1.0 - roughness, worldPos, normalDirection, viewDirection, shadow, occlusion
#ifdef USES_ANISOTROPY
    , anisotropy
#endif
#ifdef DEFERRED_CLUSTER
    , sceneDepth
#endif
#ifdef CLUSTER_VS
    , vVecIrrR, vVecIrrG, vMrp, vMrpDir
#endif
#ifdef CLEAR_COAT
    , clearCoatStrength, clearCoatRoughness
    , ccBaseColor, metallic
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
    , bottomNormalDirection
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , subsurfaceColor
#endif
    );
}

#ifdef SPLIT_LIGHTING
/**
 * @brief Metallic PBR Split Output Version
 * Separates scene lighting from environment specular/diffuse for the reflection
 * hierarchy system (SSR replaces env specular, SSGI replaces env diffuse).
 *
 * @param outSceneLighting Output: Scene lighting (direct_diffuse + direct_specular)
 * @param outEnvSpecular   Output: Environment specular only (IBL specular, replaced by SSR)
 * @param outEnvDiffuse    Output: Environment diffuse only (IBL diffuse * diffuseColor, replaced by SSGI)
 */
void MetallicPBR_Split(
    vec3 diffuseColor, float metallic, float specular, float roughness, hvec3 worldPos,
    vec3 normalDirection, vec3 viewDirection, vec3 shadow, float occlusion
#ifdef USES_ANISOTROPY
    , float anisotropy
#endif
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
#ifdef CLUSTER_VS
    , vec4 vecIrrR, vec4 vecIrrG, vec4 mrpIntensity, vec4 mrpDir
#endif
#ifdef CLEAR_COAT
    , float clearCoatStrength, float clearCoatRoughness
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
    , vec3 bottomNormalDirection        // 底层 substrate 法线（A1：normalDirection 为顶层 coat）
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , vec3 subsurfaceColor
#endif
    , out vec3 outSceneLighting
    , out vec3 outEnvSpecular
    , out vec3 outEnvDiffuse
)
{
#ifdef WEATHER_EFFECT
    WeatherEffect(diffuseColor, roughness, metallic, normalDirection);
#endif
#if defined(PAINTABLE) && defined(PAINTABLE_UV_AVAILABLE)
    ApplyPaintMap(diffuseColor, metallic, roughness);
#endif

    roughness = mix(roughness, cGlobalRoughness, cGlobalRoughnessOn);

    float oneMinusReflectivity;
    vec3 specularColor = vec3(specular, specular, specular);
#ifdef CLEAR_COAT
    vec3 ccBaseColor = diffuseColor;  // 保存原始（同 MetallicPBR）
#endif
    diffuseColor = DiffuseAndSpecularFromMetallicEx(diffuseColor, metallic, specularColor, oneMinusReflectivity);

    Standard_BRDF_Split(diffuseColor, specularColor, oneMinusReflectivity, 1.0 - roughness, worldPos,
        normalDirection, viewDirection, shadow, occlusion
#ifdef USES_ANISOTROPY
        , anisotropy
#endif
#ifdef DEFERRED_CLUSTER
        , sceneDepth
#endif
#ifdef CLUSTER_VS
        , vecIrrR, vecIrrG, mrpIntensity, mrpDir
#endif
#ifdef CLEAR_COAT
        , clearCoatStrength, clearCoatRoughness
        , ccBaseColor, metallic
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
        , bottomNormalDirection
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
        , subsurfaceColor
#endif
        , outSceneLighting
        , outEnvSpecular
        , outEnvDiffuse
    );
}
#endif // SPLIT_LIGHTING
