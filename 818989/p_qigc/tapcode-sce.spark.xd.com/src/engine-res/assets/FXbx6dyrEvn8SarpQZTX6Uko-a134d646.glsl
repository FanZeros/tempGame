vec3 SpecularPBR(vec3 diffuseColor, vec3 specularColor, float gloss, hvec3 worldPos, vec3 normalDirection, vec3 viewDirection, vec3 shadow, float occlusion
#ifdef USES_ANISOTROPY
    , float anisotropy
#endif
#ifdef DEFERRED_CLUSTER
    , hfloat sceneDepth
#endif
#ifdef CLEAR_COAT
    , float clearCoatStrength, float clearCoatRoughness
#ifdef    CLEAR_COAT_BOTTOM_NORMAL
    , vec3 bottomNormalDirection        // 底层 substrate 法线（A1：normalDirection 为顶层 coat）
#endif // CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , vec3 subsurfaceColor
#endif
)
{
    float oneMinusReflectivity;
    diffuseColor = EnergyConservationBetweenDiffuseAndSpecular(diffuseColor, specularColor, oneMinusReflectivity);
    return Standard_BRDF(diffuseColor, specularColor, oneMinusReflectivity, gloss, worldPos, normalDirection, viewDirection, shadow, occlusion
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
    , diffuseColor, 0.0    // SpecularWorkflow 无金属概念 → Transmission coverage=0 → 退化为 1（无效果）
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
    , bottomNormalDirection
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , subsurfaceColor
#endif
    );
}
