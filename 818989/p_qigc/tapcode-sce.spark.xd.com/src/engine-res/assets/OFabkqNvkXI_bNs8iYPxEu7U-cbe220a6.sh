#ifndef CLEAR_COAT_HEADER_GUARD
#define CLEAR_COAT_HEADER_GUARD

// =============================================================================
//  Clear Coat 共享实现 — 顶层独立 GGX 高光 + 底层能量补偿
//
//  UE 出处（算法对照）：
//    Engine/Shaders/Private/ShadingModels.ush
//      → ClearCoatBxDF()             直接光清漆 BRDF（参考我们 ApplyClearCoat）
//      → ClearCoat_EnvBRDFApprox()   IBL 清漆能量补偿
//    Engine/Shaders/Private/BRDF.ush
//      → D_GGX / Vis_SmithJointApprox / F_Schlick   底层数学
//    GUID: UESHADERMETADATA_VERSION E745A0A0-E5E2-4976-B407-F7C36FCE9880
//
//  我们的简化：
//    - F0 固定 0.04（IOR 1.5），UE 同
//    - 顶层 IBL roughness 走独立 LOD 选择，等价 UE GGX 预过滤 cubemap
//    - 不做 UE 的 "底层 metallic IOR matching"（高光略偏色差，肉眼不显）
//
//  参数化：clearCoatStrength / clearCoatRoughness 都是函数参数，调用方传入，
//          PS 调用 BRDF 前可任意覆盖。
//
//  函数：
//      ApplyClearCoat        — 直接光 / 点光 / 胶囊光通用 (任何 D·V·F BRDF 输出)
//      ApplyClearCoatIBL     — IBL specular (按 clearCoatRoughness 单独采 cubemap)
//
//  Lifecycle：
//      函数 inout 修改底层 diffuse/spec（清漆 fresnel 衰减），同时把顶层
//      coatSpec 直接累加到 spec，调用方一行替代成几十行 ApplyClearCoat 代码块。
//
//  依赖：samplers.sh (sEnvSpecular) + uniforms.sh (u_SinCosEnvCubeAngle,
//        cEnvSpecTextureIntensity, cAmbientOcclusionIntensity)
//        PBRCommon.glsl (GGXTerm, SmithJointGGXVisibilityTerm,
//                         PerceptualRoughnessToRoughness)
// =============================================================================

#ifdef CLEAR_COAT

// SimpleClearCoatTransmittance — UE BRDF.ush:753-781 1:1 移植
// 模拟"光穿过清漆 → 击中金属底 → 反射 → 再穿出清漆"过程中的 BaseColor 染色吸收
// coverage = metallic（非金属 substrate 时 Transmission = 1）
vec3 ComputeClearCoatTransmittance(float NoL, float NoV_refracted, float metallic, vec3 baseColor)
{
    vec3 transmittance = vec3_splat(1.0);
    float coverage = metallic;
    if (coverage > 0.0)
    {
        const float layerThickness = 1.0;
        // ThinDistance = LayerThickness * (rcp(NoV) + rcp(NoL))
        float thinDistance = layerThickness * (1.0 / max(NoV_refracted, 0.001) + 1.0 / max(NoL, 0.001));
        // TransmittanceColor = Diffuse_Lambert(BaseColor) = BaseColor / π
        vec3 transmittanceColor = baseColor * M_INV_PI;
        // ExtinctionCoefficient = -log(max(TransmittanceColor, 0.0001)) / (2 * LayerThickness)
        vec3 extinction = -log(max(transmittanceColor, vec3_splat(0.0001))) / (2.0 * layerThickness);
        // OpticalDepth = ExtinctionCoefficient * max(ThinDistance - 2*LayerThickness, 0)
        vec3 opticalDepth = extinction * max(thinDistance - 2.0 * layerThickness, 0.0);
        transmittance = exp(-opticalDepth);
        // 按 Metallic coverage 在 1 和 transmittance 之间 lerp
        transmittance = mix(vec3_splat(1.0), transmittance, coverage);
    }
    return transmittance;
}

// 直接光 ClearCoat 完整 BRDF 合成 — 对齐 UE ShadingModels.ush::ClearCoatBxDF (line 353-560)
// 双法线（对齐 UE）：顶层清漆 lobe 用顶层点积(coatN*)，底层 substrate lobe 用底层点积(botN*)；
// 折射在清漆界面发生，用顶层点积。
// out: finalDiff / finalSpec 已含 per-lobe NoL（顶层乘 coatNdotL、底层乘 botNdotL），caller 不再乘 NoL
void ApplyClearCoat(out vec3 finalDiff, out vec3 finalSpec,
                    float coatNdotH, float coatNdotV, float coatNdotL,  // 顶层 coat 法线点积
                    float botNdotH, float botNdotL,                     // 底层 substrate 法线点积
                    float VdotH,
                    vec3 substrateLambertDiff,    // = diffuseColor*INV_PI 或 Disney_Diffuse 输出（无 NoL）
                    vec3 substrateSpecularColor,  // 底层 F0
                    vec3 baseColor,                // 原始 BaseColor（for Transmission）
                    float metallic,                // 底层金属度（for Transmission coverage）
                    float baseLinearR,             // 底层 linear roughness = R²
                    float clearCoatStrength, float clearCoatRoughness)
{
    float ccPerceptualR = max(clearCoatRoughness, 0.02);
    float ccLinearR = PerceptualRoughnessToRoughness(ccPerceptualR);

    // ─── 顶层（清漆，用顶层法线点积）─── UE 行 401-420
    float Fc = pow(1.0 - VdotH, 5.0);
    float F_top = Fc + (1.0 - Fc) * 0.04;
    float topD = GGXTerm(coatNdotH, ccLinearR);
    float topVis = SmithJointGGXVisibilityTerm(coatNdotL, coatNdotV, ccLinearR);
    vec3 topCoatSpec = vec3_splat(clearCoatStrength * topD * topVis * F_top);

    // ─── RefractClearCoatContext（折射在清漆界面，用顶层点积）─── UE 行 330-350
    //   eta = 1/1.5
    //   refractBlend = (0.63 - 0.22*VoH)*VoH - 0.745
    //   NoV_bot = clamp(eta*coatNoV - refractBlend*coatNoH, 0.001, 1)
    //   VoH_bot = saturate(eta*VoH - refractBlend)
    const float eta = 1.0 / 1.5;
    float refractBlend = (0.63 - 0.22 * VdotH) * VdotH - 0.745;
    float refractProj = refractBlend * coatNdotH;
    float bottomNdotV = clamp(eta * coatNdotV - refractProj, 0.001, 1.0);
    float bottomVdotH = saturate(eta * VdotH - refractBlend);

    // ─── 底层 BRDF (折射后) ─── UE 行 540-549
    //   D2 = D_GGX(a2_bot, botNoH)            — 用底层法线 NoH
    //   Vis2 = Vis(a2_bot, bottomNoV, botNoL) — NoV 折射, NoL 用底层法线
    float D2 = GGXTerm(botNdotH, baseLinearR);
    float Vis2 = SmithJointGGXVisibilityTerm(botNdotL, bottomNdotV, baseLinearR);

    // F 两个版本：DefaultLit 用原始 VoH，F_Bot 用折射 VoH
    vec3 F_DefaultLit = substrateSpecularColor + (vec3_splat(1.0) - substrateSpecularColor) * Fc;
    vec3 F_Bot        = substrateSpecularColor + (vec3_splat(1.0) - substrateSpecularColor) * pow(1.0 - bottomVdotH, 5.0);

    // Transmission — 金属底色吸收（底层 NoL + 折射 NoV）
    vec3 transmission = ComputeClearCoatTransmittance(botNdotL, bottomNdotV, metallic, baseColor);

    // FresnelCoeff = (1-F_top)² (直接光路径；IBL 那条用 (1-F) 一次方)
    float fresnelCoeff = (1.0 - F_top) * (1.0 - F_top);

    // ─── 合成 Specular —— per-lobe NoL：顶层乘 coatNdotL、底层乘 botNdotL ─── UE 行 553-556
    //   TopCoat       = clearCoatStrength * topD * topVis * F_top   (× 顶层 NoL)
    //   CommonSpecular = D2 * Vis2                                   (× 底层 NoL)
    //   Lighting.Specular = TopCoat·coatNoL + CommonSpec·botNoL · lerp(DefSpec, RefrSpec, ClearCoat)
    float commonScale = D2 * Vis2;
    vec3 defaultSpec = F_DefaultLit;
    vec3 refractedSpec = vec3_splat(fresnelCoeff) * transmission * F_Bot;
    finalSpec = topCoatSpec * coatNdotL
              + (vec3_splat(commonScale) * mix(defaultSpec, refractedSpec, clearCoatStrength)) * botNdotL;

    // ─── 合成 Diffuse（底层，乘 botNdotL）─── UE 行 506-508
    //   DefaultDiffuse = Lambert(DiffuseColor)
    //   RefractedDiffuse = FresnelCoeff * Transmission * DefaultDiffuse
    //   Lighting.Diffuse = lerp(DefaultDiffuse, RefractedDiffuse, ClearCoat) · botNoL
    vec3 defaultDiff = substrateLambertDiff;
    vec3 refractedDiff = vec3_splat(fresnelCoeff) * transmission * substrateLambertDiff;
    finalDiff = mix(defaultDiff, refractedDiff, clearCoatStrength) * botNdotL;
}

#ifdef ENVCUBE
// IBL specular 清漆 — 按 clearCoatRoughness 单独选 cubemap LOD（"清漆映景"）
// inout: indDiff/indSpec 被衰减；indSpec 加上顶层 cubemap 反射
void ApplyClearCoatIBL(inout vec3 indDiff, inout vec3 indSpec,
                       vec3 normalDirection, vec3 viewDirection,
                       float NdotV, float occlusion,
                       float clearCoatStrength, float clearCoatRoughness)
{
    // 沿用 GI_Indirect 的 mip 映射：pertubed = perceptual * (1.7 - 0.7*p)，mip = pertubed * 6
    float perceptualR = max(clearCoatRoughness, 0.02);
    float ccPertubed = perceptualR * (1.7 - 0.7 * perceptualR);
    float mip = ccPertubed * 6.0;

    vec3 viewReflection = 2.0 * NdotV * normalDirection - viewDirection;
    // 复用 zone 的 specular cubemap 旋转矩阵 u_SinCosEnvCubeAngle.zw
    vec3 cubeR = viewReflection;
    cubeR.zx = vec2(dot(cubeR.zx, vec2(u_SinCosEnvCubeAngle.w, -u_SinCosEnvCubeAngle.z)),
                    dot(cubeR.zx, u_SinCosEnvCubeAngle.zw));
    vec4 filterGGX = textureCubeLod(sEnvSpecular, cubeR, mip);
    #ifndef URHO3D_MOBILE
        vec3 env = filterGGX.xyz * cEnvSpecTextureIntensity;
    #else
        vec3 env = filterGGX.xyz * filterGGX.w * 6.0 * cEnvSpecTextureIntensity;
    #endif

    // 顶层 IBL 反射：Karis EnvBRDFApprox (F0=0.04)，对齐 UE
    // Engine/Shaders/Private/ReflectionEnvironmentPixelShader.usf:263 路径
    //   F = EnvBRDF(0.04, ClearCoatRoughness, NoV).x = 0.04*AB.x + AB.y
    //   F *= ClearCoat
    vec4 envC0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    vec4 envC1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 envR = perceptualR * envC0 + envC1;
    float a004 = min(envR.x * envR.x, exp2(-9.28 * NdotV)) * envR.x + envR.y;
    vec2 envAB = vec2(-1.04, 1.04) * a004 + envR.zw;
    float coatScale = 0.04 * envAB.x + envAB.y;
    // 顶层乘 SpecularOcclusion（UE deferred Color.a *= SpecularOcclusion 后传 GatherRadiance）
    // 但不乘 cAmbientOcclusionIntensity（UE 无等价物，是 UrhoX 自有美术系数）
    vec3 indirect = env * (coatScale * clearCoatStrength) * occlusion;

    // 底层 IBL 按 (1-F) 一次方衰减，**不是 (1-F)²**
    // 出处：Engine/Shaders/Private/ReflectionEnvironmentPixelShader.usf:268-269
    //   float LayerAttenuation = (1 - F);
    //   Color.rgb *= LayerAttenuation;
    // 这是 UE deferred 唯一权威实现；旧 (1-F)² 偏暗一次方，导致底层反射比 UE 弱
    float Fc = pow(1.0 - NdotV, 5.0);
    float F = (Fc + (1.0 - Fc) * 0.04) * clearCoatStrength;
    float layerAttenuation = 1.0 - F;
    indDiff *= layerAttenuation;
    indSpec = indSpec * layerAttenuation + indirect;
}
#endif // ENVCUBE

#endif // CLEAR_COAT

// =============================================================================
//  调用宏 — 一行解决，自动处理：
//    1. hvec3 / vec3 类型兼容（先 copy 到临时 vec3，inout 完写回，规避 GLES
//       inout 类型严格匹配）
//    2. #ifdef CLEAR_COAT / #ifdef ENVCUBE 条件内化（不开宏时展开成空）
//    3. 顶/底两套 NdotX 在宏内部分别从 coatN（顶层）、botN（底层）现算 ——
//       调用方传两条法线：coatN=顶层 coat 法线、botN=底层 substrate 法线。
//       不开 CLEAR_COAT_BOTTOM_NORMAL 时调用方传同一条（botN==coatN，退化单法线）。
// =============================================================================
#ifdef CLEAR_COAT
    // 直接光 ApplyClearCoat：覆盖 (out) diff/spec，完整 UE 双法线合成
    // 注意：substrateLambertDiff 必须先 copy 到临时变量再传，避免 diff 与
    // substrateLambertDiff 是同一变量时读写顺序问题
    #define APPLY_CLEAR_COAT(diff, spec, coatN, botN, viewDir, lightDir, halfDir, \
                             substrateLambertDiff, substrateSpecularColor, baseColor, metallic, baseLinearR, \
                             clearCoatStrength, clearCoatRoughness) { \
        float _ccCoatNdotH = clamp(dot(coatN, halfDir), M_EPSILON, 1.0); \
        float _ccCoatNdotV = abs(dot(coatN, viewDir)) + 1e-5; \
        float _ccCoatNdotL = clamp(dot(coatN, lightDir), M_EPSILON, 1.0); \
        float _ccBotNdotH = clamp(dot(botN, halfDir), M_EPSILON, 1.0); \
        float _ccBotNdotL = clamp(dot(botN, lightDir), M_EPSILON, 1.0); \
        float _ccVdotH = clamp(dot(viewDir, halfDir), M_EPSILON, 1.0); \
        vec3 _ccSubstrateLambert = vec3(substrateLambertDiff); \
        vec3 _clearCoatDiff = vec3_splat(0.0); vec3 _clearCoatSpec = vec3_splat(0.0); \
        ApplyClearCoat(_clearCoatDiff, _clearCoatSpec, _ccCoatNdotH, _ccCoatNdotV, _ccCoatNdotL, _ccBotNdotH, _ccBotNdotL, _ccVdotH, \
                       _ccSubstrateLambert, substrateSpecularColor, baseColor, metallic, baseLinearR, \
                       clearCoatStrength, clearCoatRoughness); \
        diff = _clearCoatDiff; spec = _clearCoatSpec; }
#else
    #define APPLY_CLEAR_COAT(diff, spec, coatN, botN, viewDir, lightDir, halfDir, \
                             substrateLambertDiff, substrateSpecularColor, baseColor, metallic, baseLinearR, \
                             clearCoatStrength, clearCoatRoughness)
#endif

#if defined(CLEAR_COAT) && defined(ENVCUBE)
    // 顶层 NdotV 在宏里现算（顶层法线 dot view），上层 caller 不用再单独算。
    #define APPLY_CLEAR_COAT_IBL(indDiff, indSpec, coatN, viewDir, occlusion, \
                                 clearCoatStrength, clearCoatRoughness) { \
        float _ccIblNdotV = clamp(dot(coatN, viewDir), 0.0, 1.0); \
        vec3 _clearCoatIndDiff = vec3(indDiff); vec3 _clearCoatIndSpec = vec3(indSpec); \
        ApplyClearCoatIBL(_clearCoatIndDiff, _clearCoatIndSpec, coatN, viewDir, _ccIblNdotV, occlusion, \
                          clearCoatStrength, clearCoatRoughness); \
        indDiff = _clearCoatIndDiff; indSpec = _clearCoatIndSpec; }
#else
    #define APPLY_CLEAR_COAT_IBL(indDiff, indSpec, coatN, viewDir, occlusion, \
                                 clearCoatStrength, clearCoatRoughness)
#endif

#endif // CLEAR_COAT_HEADER_GUARD
