// UE4的环境高光BRDF
vec3 EnvBRDFApprox( vec3 SpecularColor, float Roughness, float NoV )
{
	// [ Lazarov 2013, "Getting More Physical in Call of Duty: Black Ops II" ]
	// Adaptation to fit our G term.
	const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
	const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
	vec4 r = Roughness * c0 + c1;
	float a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
	vec2 AB = vec2( -1.04, 1.04 ) * a004 + r.zw;

	// Anything less than 2% is physically impossible and is instead considered to be shadowing
	// Note: this is needed for the 'specular' show flag to work, since it uses a SpecularColor of 0
	AB.y *= saturate( 50.0 * SpecularColor.g );

	return SpecularColor * AB.x + AB.y;
}

#ifdef TWO_SIDED_FOLIAGE
// 植被透射项 — UE Two-Sided Foliage 简化版（ShadingModels.ush:945-957）
// subsurfaceColor 全 0 时退化为 diffuseColor，避免美术忘填导致 transmission 项白算
// 调用方传 subsurfaceColor（默认从 pipline.subsurfaceColor = cSubsurfaceColor，PS 可覆盖）
vec3 ComputeFoliageTransmission(vec3 diffuseColor, vec3 N, vec3 V, vec3 L,
                                vec3 subsurfaceColor)
{
    vec3 ssColor = (dot(subsurfaceColor, subsurfaceColor) < 1e-4)
                   ? diffuseColor
                   : subsurfaceColor;

    // Wrap diffuse（http://blog.stevemcauley.com/2011/12/03/energy-conserving-wrapped-diffuse/）
    const float wrap = 0.5;
    float wrapNoL = saturate((-dot(N, L) + wrap) / ((1.0 + wrap) * (1.0 + wrap)));

    // Forward scatter peak — 由 UE 原版的 0.6 (a²=0.36) 改为 1.0 (a²=1.0)
    // 原因：UE 0.6 在 -VoL→1 时峰值 ≈0.88，配合 HDR lightColor 在 UrhoX (无 ACES tonemap +
    // 无 SubsurfaceProfile 强度归一) 下会形成 specular spike → 叶片白色 sparkle 闪烁过曝
    // 改为 1.0 后峰值降到 ≈0.318 (-64%)，lobe 变宽，透光均匀分布在背光面
    float scatter = GGXTerm(saturate(-dot(V, L)), 1.0);

    // saturate 兜底：防多光源累加 / HDR lightColor 突破 ssColor 本身的颜色上限
    return saturate(wrapNoL * scatter) * ssColor;
}
#endif

vec3 GetLightingColor(vec3 diffuseColor, vec3 specularColor, float roughness, float perceptualRoughness, vec3 normalDirection, vec3 viewDirection, vec3 lightDirection, float NdotV
#ifdef USES_ANISOTROPY
    , float XdotV, float YdotV, float ax, float ay, vec3 X, vec3 Y
#endif
#ifdef CLEAR_COAT
    , float clearCoatStrength, float clearCoatRoughness
    , vec3 baseColor, float metallic    // ← ApplyClearCoat 内部算 Transmission 需要
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
    , vec3 bottomNormalDirection        // 底层 substrate 法线（A1：normalDirection 为顶层 coat）
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , vec3 subsurfaceColor
#endif
)
{
// necessary preprocess
    vec3 lightVec = normalize(lightDirection);
    vec3 halfDirection = normalize(viewDirection + lightDirection);

#if defined(CLEAR_COAT) && !defined(CLEAR_COAT_BOTTOM_NORMAL)
    // 单法线退化：底层 = 顶层 normalDirection（行为等价于改造前）
    vec3 bottomNormalDirection = normalDirection;
#endif
#ifdef CLEAR_COAT
    // A1：保存顶层 coat 法线，再把主法线变量切到底层 —— 下面所有 base 计算
    //     （NdotL/NdotH/漫反射，以及入参 NdotV）自动走底层法线，无需逐行改；
    //     顶层 coat lobe 单独用 clearCoatNormal。单法线时 bottomNormalDirection==normalDirection，退化等价。
    vec3 clearCoatNormal = normalDirection;
    normalDirection = bottomNormalDirection;
#endif

    float VdotH = clamp(dot(viewDirection, halfDirection), M_EPSILON, 1.0);
    float NdotH = clamp(dot(normalDirection, halfDirection), M_EPSILON, 1.0);
    float NdotL = clamp(dot(normalDirection, lightVec), M_EPSILON, 1.0);
    float LdotH = clamp(dot(lightVec, halfDirection), M_EPSILON, 1.0);

#ifdef USES_ANISOTROPY
    float VdotL = dot(viewDirection, lightVec);
    float InvLenH = inversesqrt( 2.0 + 2.0 * VdotL );

    #if 0
        float XdotL = clamp(dot(X, lightVec), M_EPSILON, 1.0);
        float YdotL = clamp(dot(Y, lightVec), M_EPSILON, 1.0);
    #else
        float XdotL = dot(X, lightVec);
        float YdotL = dot(Y, lightVec);
    #endif

    // float XdotH = clamp(dot(X, halfDirection), M_EPSILON, 1.0);
    // float YdotH = clamp(dot(Y, halfDirection), M_EPSILON, 1.0);
    float XdotH = (XdotL + XdotV) * InvLenH;
    float YdotH = (YdotL + YdotV) * InvLenH;
#endif

// Diffuse (Lambert / Disney) — 不含 NoL
#if USE_DIFFUSE_LAMBERT_BRDF
    vec3 directDiffuse = diffuseColor * M_INV_PI;
#else
    vec3 directDiffuse = DisneyDiffuse(NdotV, NdotL, LdotH, perceptualRoughness) * diffuseColor * M_INV_PI;
#endif // USE_DIFFUSE_LAMBERT_BRDF

// 低画质关闭动态光的 pbr 高光计算
#if RENDER_QUALITY > RENDER_QUALITY_LOW

    #ifdef CLEAR_COAT
        // ───── ClearCoat path ─────
        // UE ShadingModels.ush::ClearCoatBxDF 完整合成（折射 context + Transmission + lerp）
        // ApplyClearCoat 内部重新算 substrate D2/Vis2（折射 NoV），不复用普通 substrate D*V*F
        // directDiffuse 被覆盖为 lerp(default, refracted, ClearCoat) 结果
        vec3 directSpecular;
        APPLY_CLEAR_COAT(directDiffuse, directSpecular, clearCoatNormal, normalDirection, viewDirection, lightVec, halfDirection, directDiffuse, specularColor, baseColor, metallic, roughness, clearCoatStrength, clearCoatRoughness);
    #else
        // ───── 标准 substrate path ─────
        #ifdef USES_ANISOTROPY
            roughness = max(roughness, 0.002);
            float V = Vis_SmithJointAniso(ax, ay, NdotV, NdotL, XdotV, XdotL, YdotV, YdotL);
            float D = D_GGXaniso(ax, ay, NdotH, XdotH, YdotH);
        #elif UNITY_BRDF_GGX
            roughness = max(roughness, 0.002);
            float V = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness);
            float D = GGXTerm(NdotH, roughness);
        #else
            float V = SmithBeckmannVisibilityTerm(NdotL, NdotV, roughness);
            float D = NDFBlinnPhongNormalizedTerm(NdotH, PerceptualRoughnessToSpecPower(perceptualRoughness));
        #endif
        vec3 F = FresnelTerm(specularColor, LdotH);
        vec3 directSpecular = V * D * F;
    #endif
#else
    vec3 directSpecular = vec3_splat(0.0);
    #ifdef CLEAR_COAT
        // 低画质未走 APPLY_CLEAR_COAT（per-lobe NoL 本应在宏内乘）→ 给漫反射手动补底层 NoL，
        // 否则下面 CLEAR_COAT 的 return 直接求和会漏乘 NoL。
        directDiffuse *= NdotL;
    #endif
#endif // RENDER_QUALITY > RENDER_QUALITY_LOW

// Diffuse + Specular, NdotL挪到最后乘了
#ifdef CLEAR_COAT
    // per-lobe NoL 已在 ApplyClearCoat 内按层乘（顶层 coatNoL / 底层 botNoL），不再外乘
    return directDiffuse + directSpecular;
#elif defined(TWO_SIDED_FOLIAGE)
    // 透射项 (不乘 NdotL — 已用 -NdotL 做权重；调用方乘 lightColor * attenuation 等价 UE FalloffColor * Falloff)
    vec3 transmission = ComputeFoliageTransmission(diffuseColor, normalDirection, viewDirection, lightVec, subsurfaceColor);
    return (directDiffuse + directSpecular) * NdotL + transmission;
#else
    return (directDiffuse + directSpecular) * NdotL;
#endif
}

vec3 GetSpecularColor(vec3 specularColor, float roughness, float perceptualRoughness, vec3 normalDirection, vec3 viewDirection, vec3 lightDirection, float NdotV)
{
// necessary preprocess
    vec3 lightVec = normalize(lightDirection);
    vec3 halfDirection = normalize(viewDirection + lightVec);

    //float NdotH = clamp(dot(normalDirection, halfDirection), M_EPSILON, 1.0);
    float NdotL = clamp(dot(normalDirection, lightVec), M_EPSILON, 1.0);
    //float LdotH = clamp(dot(lightVec, halfDirection), M_EPSILON, 1.0);


// 低画质关闭动态光的pbr高光计算
#if RENDER_QUALITY > RENDER_QUALITY_LOW
// VDF高光项
    #if UNITY_BRDF_GGX
        roughness = max(roughness, 0.002);
        float VD = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness) * NdotL; //V * NdotL
        NdotL = clamp(dot(normalDirection, halfDirection), M_EPSILON, 1.0); //NdotL = NdotH
        VD = GGXTerm(NdotL, roughness) * VD; //V*D*NdotL
    #else
        float VD = SmithBeckmannVisibilityTerm(NdotL, NdotV, roughness) * NdotL;
        NdotL = clamp(dot(normalDirection, halfDirection), M_EPSILON, 1.0); //NdotL = NdotH
        VD = NDFBlinnPhongNormalizedTerm(NdotL, PerceptualRoughnessToSpecPower(perceptualRoughness)) * VD;
    #endif
    NdotL = clamp(dot(lightVec, halfDirection), M_EPSILON, 1.0);//NdotL = LdotH
    specularColor = FresnelTerm(specularColor, NdotL); //specularColor = F
    
// Specular
    specularColor = VD * specularColor;
#else
    specularColor = vec3_splat(0.0);
#endif // RENDER_QUALITY > RENDER_QUALITY_LOW

    return specularColor;
}

/**
 * @brief 从Unity改一版的的迪士尼BRDF
          注意：为了节省计算量，目前只对主光做各向异性
 * 之所以不直接用Unity源码是因为计算灯光衰减、间接光照这部分每个引擎都不太一样
 * 综上来说，BRDF部分还是Unity代码，只不过gi部分适配了Urho3D
 * @param diffuseColor              - 已经经过能量守恒的漫反色颜色（和高光做了比例）
 * @param spefularColor             - 高光颜色
 * @param oneMinusReflectivity      - 1.0 - 反色率
 * @param gloss                     - 光滑度（perceptualRoughness => 粗糙度比例（等价于1 - 光滑度，光滑度为贴图输入或者shader参数））
 * @param normalDirection           - 法线向量
 * @param viewDirection             - 物体到相机的向量
 * @param shadow                    - 阴影衰减
 * @param occlusion                 - 材质传入的环境光遮蔽
 */
vec3 Disney_BRDF(vec3 diffuseColor, vec3 specularColor, float oneMinusReflectivity, float gloss, hvec3 worldPos, vec3 normalDirection, vec3 viewDirection, vec3 shadow, float occlusion
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
    , vec3 baseColor, float metallic    // ← UE ClearCoatBxDF Transmission 需要原始 BaseColor + metallic
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
    , vec3 bottomNormalDirection        // 底层 substrate 法线（A1：normalDirection 为顶层 coat）
#endif// CLEAR_COAT_BOTTOM_NORMAL
#endif
#ifdef TWO_SIDED_FOLIAGE
    , vec3 subsurfaceColor
#endif
)
{
    vec3 finalColor = vec3_splat(0.0);

// roughness
    float perceptualRoughness = 1.0 - gloss;
    float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);

#ifdef CLEAR_COAT
    // 底层 "hit roughness"：光线进清漆 → 折射散开 → 击中底层 → 再出来，
    // 视觉上底层比无清漆时更模糊。UE Engine/Shaders/Private/ShadingModels.ush::ClearCoatBxDF。
    // 公式：把基底 roughness 朝 max(基底, 清漆) 抬升，权重 = clearCoatStrength。
    // 既影响下游直接光 BRDF，也影响 GI_Indirect 的 EnvBRDFApprox（底层 IBL）。
    perceptualRoughness = mix(perceptualRoughness, max(perceptualRoughness, clearCoatRoughness), clearCoatStrength);
    roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
#endif

#if defined(CLEAR_COAT) && !defined(CLEAR_COAT_BOTTOM_NORMAL)
    // 单法线退化：底层 = 顶层 normalDirection（行为等价于改造前）
    vec3 bottomNormalDirection = normalDirection;
#endif
    // 顶层 coat 法线快照：无条件声明，非 CC 时即 normalDirection（GetLightingColor
    // 调用统一传它，零回归）；CC 时保留顶层，随后把主法线切到底层。
    vec3 clearCoatNormal = normalDirection;
#ifdef CLEAR_COAT
    // A1：主法线切底层 —— NdotV / GI_Indirect / 基底 EnvBRDF 自动走底层；
    //     清漆 lobe/IBL 用 clearCoatNormal。单法线时 bottomNormalDirection==normalDirection，退化等价。
    normalDirection = bottomNormalDirection;
#endif

    float NdotV = abs(dot(normalDirection, viewDirection));

#ifdef USES_ANISOTROPY
    float ax = 0.0;
    float ay = 0.0;
    GetAnisotropicRoughness(perceptualRoughness, anisotropy, ax, ay);

    // X: Tangent => vTangent.xyz
    // Y: Bnormal => vTexCoord.zw vTangent.w
    vec3 X = vTangent.xyz;
    vec3 Y = vec3(vTexCoord.zw, vTangent.w);

    float XdotV = dot(X, viewDirection);
    float YdotV = dot(Y, viewDirection);
#endif

#if defined(PERPIXEL)
    hvec3 lightColor;
    vec3 lightDirection;
    hfloat attenuation;
    hvec3 lightingColor;

#if (defined(DIRLIGHT) && !defined(CLUSTER_BASE)) || !defined(CLUSTER)
// GI => light color, light dir, light attenuation
    lightColor = GI_GetLightColor();
    attenuation = GI_GetAttenAndLightDir(worldPos, lightDirection);

#ifdef RECTLIGHT
    // cLightDirPS is BACK direction (engine convention), negate to get emission direction
    // cLightRectParams = (halfWidth, halfHeight, barnCosAngle, barnLength)
    lightingColor = GetRectLightBRDF(worldPos, normalDirection, viewDirection,
                        diffuseColor, specularColor, roughness, perceptualRoughness,
                        cLightPosPS.xyz, -cLightDirPS, cLightTangent,
                        cLightRectParams.x, cLightRectParams.y,
                        cLightRectParams.z, cLightRectParams.w);
    finalColor += lightingColor * lightColor * (attenuation * shadow);
#else
    lightingColor = GetLightingColor(diffuseColor, specularColor, roughness, perceptualRoughness, clearCoatNormal, viewDirection, lightDirection, NdotV
    #ifdef USES_ANISOTROPY
        , XdotV, YdotV, ax, ay, X, Y
    #endif
    #ifdef CLEAR_COAT
        , clearCoatStrength, clearCoatRoughness
        , baseColor, metallic
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
        , bottomNormalDirection
#endif// CLEAR_COAT_BOTTOM_NORMAL
    #endif
    #ifdef TWO_SIDED_FOLIAGE
        , subsurfaceColor
    #endif
    );
    finalColor += lightingColor * lightColor * (attenuation * shadow);
#endif // RECTLIGHT
#endif // DIRLIGHT || !CLUSTER

#if defined(LIGHTMAP)

#if defined(SPEED_GRASS)
    vec4 lightMapColor = GetLambertGrassLightMapColor(vLightMapUV.xy, normalDirection, worldPos);
    finalColor += diffuseColor * lightMapColor.rgb;
#else// SPEED_GRASS

#if RENDER_QUALITY >= RENDER_QUALITY_HIGH && defined(LIGHTMAP_DIRECTIONALITY)
    vec3 lightMapDir;
    vec4 lightMapColor = GetLightMapColor(vLightMapUV.xy, normalDirection, lightMapDir);
    finalColor += lightMapColor.rgb * (diffuseColor + M_PI * GetSpecularColor(specularColor, roughness, perceptualRoughness, normalDirection, viewDirection, lightMapDir, NdotV));
#else// RENDER_QUALITY >= RENDER_QUALITY_HIGH && defined(LIGHTMAP_DIRECTIONALITY)
    vec4 lightMapColor = GetLightMapColor(vLightMapUV.xy, normalDirection);
    finalColor += diffuseColor * lightMapColor.rgb;
#endif// RENDER_QUALITY >= RENDER_QUALITY_HIGH && defined(LIGHTMAP_DIRECTIONALITY)

#endif// SPEED_GRASS

#endif// LIGHTMAP

#if defined(CLUSTER)
// Cluster render for pointlight

#ifdef CLUSTER_VS
    if (mrpIntensity.w > 0.0) {
        vec3 Ndote = vec3(dot(normalDirection, vecIrrR.rgb), dot(normalDirection, vecIrrG.rgb), dot(normalDirection, vec3(vecIrrR.w, vecIrrG.w, mrpDir.w)));
        finalColor += Ndote * diffuseColor * M_INV_PI;
        finalColor += mrpIntensity.xyz * GetSpecularColor(specularColor, roughness, perceptualRoughness, normalDirection, viewDirection, mrpDir.xyz, NdotV);
    }
#else
    #ifdef DEFERRED_CLUSTER
        uint cluster = getDeferredClusterIndex(gl_FragCoord.xy, sceneDepth);
    #else
        // 这里从gl_FragCoord减去viewport的起点，得到viewport坐标
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

    // GI => light color, light dir, light attenuation
        lightColor = light.intensity;
        attenuation = GI_PointLight_GetAttenAndLightDir(worldPos, light.position, light.range, lightDirection);

#ifdef CLUSTER_SPOTLIGHT
        attenuation *= GetLightDirectionFalloff(lightDirection, light.direction, light.cosOuterCone, light.invCosConeDiff);
#endif
        lightingColor = GetLightingColor(diffuseColor, specularColor, roughness, perceptualRoughness, clearCoatNormal, viewDirection, lightDirection, NdotV
        #ifdef USES_ANISOTROPY
            , XdotV, YdotV, ax, ay, X, Y
        #endif
        #ifdef CLEAR_COAT
            , clearCoatStrength, clearCoatRoughness
            , baseColor, metallic
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
            , bottomNormalDirection
#endif // CLEAR_COAT_BOTTOM_NORMAL
        #endif
        #ifdef TWO_SIDED_FOLIAGE
            , subsurfaceColor
        #endif
        );

        finalColor += lightingColor * lightColor * attenuation;
    }

#if NONPUNCTUAL_LIGHTING
    LOOP
    for (uint i = 0u; i < grid.nonPunctualPointLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.nonPunctualPointLightsOffset, i);
        NonPunctualPointLight light = GetNonPunctualPointLight(lightIndex);

        //capsule light
        if (light.length > 0.0)
        {
            finalColor += GetCapsuleLighting(light, worldPos, normalDirection, viewDirection, diffuseColor, specularColor, roughness, perceptualRoughness
            #ifdef CLEAR_COAT
                , clearCoatStrength, clearCoatRoughness
                , baseColor, metallic
            #endif
            );
        }
        else if (light.packRadius > 0.0)
        {
            finalColor += GetSphereLighting(light, worldPos, normalDirection, viewDirection, diffuseColor, specularColor, roughness, perceptualRoughness
            #ifdef CLEAR_COAT
                , clearCoatStrength, clearCoatRoughness
                , baseColor, metallic
            #endif
            );
        }
    }

    LOOP
    for (uint i = 0u; i < grid.rectLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.rectLightsOffset, i);
        RectLight rectLight = GetRectLight(lightIndex);
        finalColor += GetRectLighting(rectLight, worldPos, normalDirection, viewDirection, diffuseColor, specularColor, roughness, perceptualRoughness);
    }
#endif

#endif //CLUSTER_VS
#endif // CLUSTER
#endif // PERPIXEL

#if defined(AMBIENT)
    // AO
    #if defined(AO) && !defined(CLOSE_AO)
        #if defined(DEFERRED)
            occlusion = occlusion * texture2D(sAOMap, vScreenPos.xy).r;
        #else
            #if defined(SSAO)
                // 这里有一个trick，hlslcc翻译的时候，gl_FragCoord是当作dx标准，所以gl_FragCoord.w并不是gl文档描述的1/w，它就是w
                // https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/gl_FragCoord.xhtml
                // gl_FragCoord is an input variable that contains the window relative coordinate (x, y, z, 1/w) values for the fragment
                #if !BGFX_SHADER_LANGUAGE_GLSL
                    occlusion = occlusion * texture2D(sAOMap, vAOUV / gl_FragCoord.w * 0.5 + 0.5).r;
                #else
                    occlusion = occlusion * texture2D(sAOMap, vAOUV * gl_FragCoord.w * 0.5 + 0.5).r;
                #endif
            #else
                occlusion = occlusion * texture2D(sAOMap, vAOUV).r;
            #endif
        #endif
    #endif

// Indirect Diffuse, Indirect Specular
    vec3 indirectDiffuse;
    vec3 indirectSpecular;
    GI_Indirect(normalDirection, viewDirection, perceptualRoughness, occlusion, indirectDiffuse, indirectSpecular);

// Indirect Diffuse
    indirectDiffuse *= diffuseColor;

    #if defined(CLEAR_COAT)
    // ClearCoat 底层 EnvBRDF — 对齐 UE Deferred 路径
    // Engine/Shaders/Private/ReflectionEnvironmentPixelShader.usf:254-255
    //   AB = PreIntegratedGF.SampleLevel(...).rg                     (Karis 拟合)
    //   Color *= SpecularColor * AB.x + AB.y * saturate(50*Sc.g) * (1 - ClearCoat)
    // 关键：F90 项 (AB.y) 按 (1 - ClearCoat) 抑制，避免清漆下底层 grazing 鳞鼓过亮
        vec4 _ccEnvC0 = vec4(-1.0, -0.0275, -0.572, 0.022);
        vec4 _ccEnvC1 = vec4(1.0, 0.0425, 1.04, -0.04);
        vec4 _ccEnvR = perceptualRoughness * _ccEnvC0 + _ccEnvC1;
        float _ccA004 = min(_ccEnvR.x * _ccEnvR.x, exp2(-9.28 * NdotV)) * _ccEnvR.x + _ccEnvR.y;
        vec2 _ccAB = vec2(-1.04, 1.04) * _ccA004 + _ccEnvR.zw;
        indirectSpecular = indirectSpecular * (specularColor * _ccAB.x + _ccAB.y * saturate(50.0 * specularColor.g) * (1.0 - clearCoatStrength));
    #elif UNITY_ENV_BRDF
    // Indirect Specular (Unity3D EnvBRDFApprox)
        float surfaceReduction = 1.0 / (roughness * roughness + 1.0);
        // float grazingTerm = saturate(gloss + (1.0 - oneMinusReflectivity));
        // 菲尼尔边缘颜色过大问题：增加参数sce_EnvFresnelEdgeStrength限制边缘菲尼的最大强度
        float grazingTerm = clamp(gloss + (1.0 - oneMinusReflectivity), 0.0, sce_EnvFresnelEdgeStrength);
        indirectSpecular = indirectSpecular * surfaceReduction * FresnelLerp(specularColor, vec3_splat(grazingTerm), NdotV);
    #else
    // Indirect Specular (UE4 EnvBRDFApprox)
        indirectSpecular = indirectSpecular * EnvBRDFApprox(specularColor, perceptualRoughness, NdotV);
    #endif // CLEAR_COAT / UNITY_ENV_BRDF

    APPLY_CLEAR_COAT_IBL(indirectDiffuse, indirectSpecular, clearCoatNormal, viewDirection, occlusion, clearCoatStrength, clearCoatRoughness);
    finalColor += indirectDiffuse + indirectSpecular;
#endif // AMBIENT

    return finalColor;
}

#ifdef SPLIT_LIGHTING
/**
 * @brief Disney BRDF Split Output Version
 * Separates scene lighting from environment specular/diffuse for the reflection
 * hierarchy system (SSR replaces env specular, SSGI replaces env diffuse).
 * Used by deferred lighting pass when SPLIT_LIGHTING is defined.
 *
 * @param outSceneLighting Output: Scene lighting (direct_diffuse + direct_specular)
 * @param outEnvSpecular   Output: Environment specular only (IBL specular, replaced by SSR)
 * @param outEnvDiffuse    Output: Environment diffuse only (IBL diffuse * diffuseColor, replaced by SSGI)
 */
void Disney_BRDF_Split(
    vec3 diffuseColor, vec3 specularColor, float oneMinusReflectivity, float gloss,
    hvec3 worldPos, vec3 normalDirection, vec3 viewDirection, vec3 shadow, float occlusion
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
    , vec3 baseColor, float metallic    // ← UE ClearCoatBxDF Transmission 需要
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
    outSceneLighting = vec3_splat(0.0);
    outEnvSpecular = vec3_splat(0.0);
    outEnvDiffuse = vec3_splat(0.0);

// roughness
    float perceptualRoughness = 1.0 - gloss;
    float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);

#ifdef CLEAR_COAT
    // 底层 "hit roughness" — 见 Disney_BRDF 同步注释
    perceptualRoughness = mix(perceptualRoughness, max(perceptualRoughness, clearCoatRoughness), clearCoatStrength);
    roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
#endif

#if defined(CLEAR_COAT) && !defined(CLEAR_COAT_BOTTOM_NORMAL)
    vec3 bottomNormalDirection = normalDirection;   // 单法线退化：底=顶
#endif
    // 顶层 coat 法线快照（见 Disney_BRDF 同位注释；非 CC 时即 normalDirection）
    vec3 clearCoatNormal = normalDirection;
#ifdef CLEAR_COAT
    normalDirection = bottomNormalDirection;        // A1：主法线切底层
#endif

    float NdotV = abs(dot(normalDirection, viewDirection));

#ifdef USES_ANISOTROPY
    float ax = 0.0;
    float ay = 0.0;
    GetAnisotropicRoughness(perceptualRoughness, anisotropy, ax, ay);
    vec3 X = vTangent.xyz;
    vec3 Y = vec3(vTexCoord.zw, vTangent.w);
    float XdotV = dot(X, viewDirection);
    float YdotV = dot(Y, viewDirection);
#endif

#if defined(PERPIXEL)
    hvec3 lightColor;
    vec3 lightDirection;
    hfloat attenuation;

#if (defined(DIRLIGHT) && !defined(CLUSTER_BASE)) || !defined(CLUSTER)
    lightColor = GI_GetLightColor();
    attenuation = GI_GetAttenAndLightDir(worldPos, lightDirection);

    // Calculate direct lighting with separated diffuse/specular
    vec3 lightVec = normalize(lightDirection);
    vec3 halfDirection = normalize(viewDirection + lightDirection);
    float VdotH = clamp(dot(viewDirection, halfDirection), M_EPSILON, 1.0);
    float NdotH = clamp(dot(normalDirection, halfDirection), M_EPSILON, 1.0);
    float NdotL = clamp(dot(normalDirection, lightVec), M_EPSILON, 1.0);
    float LdotH = clamp(dot(lightVec, halfDirection), M_EPSILON, 1.0);

#ifdef USES_ANISOTROPY
    float VdotL = dot(viewDirection, lightVec);
    float InvLenH = inversesqrt(2.0 + 2.0 * VdotL);
    float XdotL = dot(X, lightVec);
    float YdotL = dot(Y, lightVec);
    float XdotH = (XdotL + XdotV) * InvLenH;
    float YdotH = (YdotL + YdotV) * InvLenH;
#endif

    // Direct Diffuse
#if USE_DIFFUSE_LAMBERT_BRDF
    vec3 directDiffuse = diffuseColor * M_INV_PI;
#else
    vec3 directDiffuse = DisneyDiffuse(NdotV, NdotL, LdotH, perceptualRoughness) * diffuseColor * M_INV_PI;
#endif

    // Direct Specular
#if RENDER_QUALITY > RENDER_QUALITY_LOW
    #ifdef CLEAR_COAT
        // ClearCoat path：UE 完整合成（折射 context + Transmission + lerp）
        vec3 directSpecular;
        APPLY_CLEAR_COAT(directDiffuse, directSpecular, clearCoatNormal, normalDirection, viewDirection, lightVec, halfDirection, directDiffuse, specularColor, baseColor, metallic, roughness, clearCoatStrength, clearCoatRoughness);
    #else
        #ifdef USES_ANISOTROPY
            roughness = max(roughness, 0.002);
            float V = Vis_SmithJointAniso(ax, ay, NdotV, NdotL, XdotV, XdotL, YdotV, YdotL);
            float D = D_GGXaniso(ax, ay, NdotH, XdotH, YdotH);
        #elif UNITY_BRDF_GGX
            roughness = max(roughness, 0.002);
            float V = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness);
            float D = GGXTerm(NdotH, roughness);
        #else
            float V = SmithBeckmannVisibilityTerm(NdotL, NdotV, roughness);
            float D = NDFBlinnPhongNormalizedTerm(NdotH, PerceptualRoughnessToSpecPower(perceptualRoughness));
        #endif
        vec3 F = FresnelTerm(specularColor, LdotH);
        vec3 directSpecular = V * D * F;
    #endif
#else
    vec3 directSpecular = vec3_splat(0.0);
    #ifdef CLEAR_COAT
        // 低画质未走 APPLY_CLEAR_COAT（per-lobe NoL 本应在宏内乘）→ 给漫反射手动补底层 NoL，
        // 否则 CC 的 lightAtten 不含 NdotL，整体会漏乘。
        directDiffuse *= NdotL;
    #endif
#endif

    // CC：per-lobe NoL 已在 ApplyClearCoat 内按层乘，lightAtten 不再乘 NdotL；
    // 非 CC（含 Foliage）维持 *NdotL。
#ifdef CLEAR_COAT
    vec3 lightAtten = lightColor * (attenuation * shadow);
    outSceneLighting += (directDiffuse + directSpecular) * lightAtten;
#else
    vec3 lightAtten = lightColor * (attenuation * shadow) * NdotL;
    outSceneLighting += (directDiffuse + directSpecular) * lightAtten;
#endif

    #ifdef TWO_SIDED_FOLIAGE
        // 透射项归 sceneLighting（直接光的一部分，不该被 SSR 替换）
        vec3 transmission = ComputeFoliageTransmission(diffuseColor, normalDirection, viewDirection, lightVec, subsurfaceColor);
        outSceneLighting += transmission * lightColor * (attenuation * shadow);
    #endif
#endif // DIRLIGHT || !CLUSTER

#if defined(LIGHTMAP)
    // Lightmap contribution
#if defined(SPEED_GRASS)
    vec4 lightMapColor = GetLambertGrassLightMapColor(vLightMapUV.xy, normalDirection, worldPos);
    outSceneLighting += diffuseColor * lightMapColor.rgb;
#else
#if RENDER_QUALITY >= RENDER_QUALITY_HIGH && defined(LIGHTMAP_DIRECTIONALITY)
    vec3 lightMapDir;
    vec4 lightMapColor = GetLightMapColor(vLightMapUV.xy, normalDirection, lightMapDir);
    outSceneLighting += lightMapColor.rgb * diffuseColor;
    outSceneLighting += lightMapColor.rgb * M_PI * GetSpecularColor(specularColor, roughness, perceptualRoughness, normalDirection, viewDirection, lightMapDir, NdotV);
#else
    vec4 lightMapColor = GetLightMapColor(vLightMapUV.xy, normalDirection);
    outSceneLighting += diffuseColor * lightMapColor.rgb;
#endif
#endif
#endif // LIGHTMAP

#if defined(CLUSTER)
    // Cluster lights
#ifdef CLUSTER_VS
    if (mrpIntensity.w > 0.0) {
        vec3 Ndote = vec3(dot(normalDirection, vecIrrR.rgb), dot(normalDirection, vecIrrG.rgb), dot(normalDirection, vec3(vecIrrR.w, vecIrrG.w, mrpDir.w)));
        outSceneLighting += Ndote * diffuseColor * M_INV_PI;
        // Cluster VS specular is direct lighting → goes to outSceneLighting
        outSceneLighting += mrpIntensity.xyz * GetSpecularColor(specularColor, roughness, perceptualRoughness, normalDirection, viewDirection, mrpDir.xyz, NdotV);
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
        attenuation = GI_PointLight_GetAttenAndLightDir(worldPos, light.position, light.range, lightDirection);

#ifdef CLUSTER_SPOTLIGHT
        attenuation *= GetLightDirectionFalloff(lightDirection, light.direction, light.cosOuterCone, light.invCosConeDiff);
#endif
        vec3 lightingColor = GetLightingColor(diffuseColor, specularColor, roughness, perceptualRoughness, clearCoatNormal, viewDirection, lightDirection, NdotV
        #ifdef USES_ANISOTROPY
            , XdotV, YdotV, ax, ay, X, Y
        #endif
        #ifdef CLEAR_COAT
            , clearCoatStrength, clearCoatRoughness
            , baseColor, metallic
#ifdef   CLEAR_COAT_BOTTOM_NORMAL
            , bottomNormalDirection
#endif// CLEAR_COAT_BOTTOM_NORMAL
        #endif
        #ifdef TWO_SIDED_FOLIAGE
            , subsurfaceColor
        #endif
        );
        // Cluster lights are direct lighting → all goes to outSceneLighting
        vec3 clusterContrib = lightingColor * lightColor * attenuation;
        outSceneLighting += clusterContrib;
    }

#if NONPUNCTUAL_LIGHTING
    LOOP
    for (uint i = 0u; i < grid.nonPunctualPointLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.nonPunctualPointLightsOffset, i);
        NonPunctualPointLight light = GetNonPunctualPointLight(lightIndex);

        vec3 nonPunctualContrib = vec3_splat(0.0);
        if (light.length > 0.0)
        {
            nonPunctualContrib = GetCapsuleLighting(light, worldPos, normalDirection, viewDirection, diffuseColor, specularColor, roughness, perceptualRoughness
            #ifdef CLEAR_COAT
                , clearCoatStrength, clearCoatRoughness
                , baseColor, metallic
            #endif
            );
        }
        else if (light.packRadius > 0.0)
        {
            nonPunctualContrib = GetSphereLighting(light, worldPos, normalDirection, viewDirection, diffuseColor, specularColor, roughness, perceptualRoughness
            #ifdef CLEAR_COAT
                , clearCoatStrength, clearCoatRoughness
                , baseColor, metallic
            #endif
            );
        }
        // Non-punctual lights are direct lighting → all goes to outSceneLighting
        outSceneLighting += nonPunctualContrib;
    }

    LOOP
    for (uint i = 0u; i < grid.rectLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.rectLightsOffset, i);
        RectLight rectLight = GetRectLight(lightIndex);
        outSceneLighting += GetRectLighting(rectLight, worldPos, normalDirection, viewDirection, diffuseColor, specularColor, roughness, perceptualRoughness);
    }
#endif
#endif // !CLUSTER_VS
#endif // CLUSTER
#endif // PERPIXEL

#if defined(AMBIENT)
    // AO
    #if defined(AO) && !defined(CLOSE_AO)
        #if defined(DEFERRED)
            occlusion = occlusion * texture2D(sAOMap, vScreenPos).r;
        #else
            #if defined(SSAO)
                #if !BGFX_SHADER_LANGUAGE_GLSL
                    occlusion = occlusion * texture2D(sAOMap, vAOUV / gl_FragCoord.w * 0.5 + 0.5).r;
                #else
                    occlusion = occlusion * texture2D(sAOMap, vAOUV * gl_FragCoord.w * 0.5 + 0.5).r;
                #endif
            #else
                occlusion = occlusion * texture2D(sAOMap, vAOUV).r;
            #endif
        #endif
    #endif

    // Indirect Diffuse, Indirect Specular
    vec3 indirectDiffuse;
    vec3 indirectSpecular;
    GI_Indirect(normalDirection, viewDirection, perceptualRoughness, occlusion, indirectDiffuse, indirectSpecular);

    // Indirect Diffuse
    indirectDiffuse *= diffuseColor;

    #if defined(CLEAR_COAT)
    // ClearCoat 底层 EnvBRDF — 对齐 UE Deferred（详见 Disney_BRDF 同位置注释）
        vec4 _ccEnvC0 = vec4(-1.0, -0.0275, -0.572, 0.022);
        vec4 _ccEnvC1 = vec4(1.0, 0.0425, 1.04, -0.04);
        vec4 _ccEnvR = perceptualRoughness * _ccEnvC0 + _ccEnvC1;
        float _ccA004 = min(_ccEnvR.x * _ccEnvR.x, exp2(-9.28 * NdotV)) * _ccEnvR.x + _ccEnvR.y;
        vec2 _ccAB = vec2(-1.04, 1.04) * _ccA004 + _ccEnvR.zw;
        indirectSpecular = indirectSpecular * (specularColor * _ccAB.x + _ccAB.y * saturate(50.0 * specularColor.g) * (1.0 - clearCoatStrength));
    #elif UNITY_ENV_BRDF
        float surfaceReduction = 1.0 / (roughness * roughness + 1.0);
        float grazingTerm = clamp(gloss + (1.0 - oneMinusReflectivity), 0.0, sce_EnvFresnelEdgeStrength);
        indirectSpecular = indirectSpecular * surfaceReduction * FresnelLerp(specularColor, vec3_splat(grazingTerm), NdotV);
    #else
        indirectSpecular = indirectSpecular * EnvBRDFApprox(specularColor, perceptualRoughness, NdotV);
    #endif

    APPLY_CLEAR_COAT_IBL(indirectDiffuse, indirectSpecular, clearCoatNormal, viewDirection, occlusion, clearCoatStrength, clearCoatRoughness);
    outEnvDiffuse += indirectDiffuse;    // This is the IBL Diffuse, serves as SSGI fallback
    outEnvSpecular += indirectSpecular;  // This is the IBL Specular, serves as SSR fallback
#endif // AMBIENT
}
#endif // SPLIT_LIGHTING
