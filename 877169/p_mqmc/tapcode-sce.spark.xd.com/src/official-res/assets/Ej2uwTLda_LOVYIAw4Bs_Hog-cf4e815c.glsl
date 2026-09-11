// CelToon — 二/三分卡通 + Rim 提亮 + 可选 PBR toon spec
//
// 同时支持两种 Technique：
//   Technique/CelToon.xml    : 纯卡通（无 spec）
//   Technique/CelToonPBR.xml : 启用 CELPBR 分支，加 toon-PBR 高光（金属/粗糙）
//
// 关键 defines：
//   NORMALMAP    — 走切线空间法线（自带 packed/RGB 兼容 + NormalStrength 平滑）
//   CELPBR       — 启用 PBR toon spec lobe + 能量守恒
//   METALLIC     — CELPBR 下从 sSpecMap (R=Rough G=Metal B=AO) 采样；否则用参数
//   ALPHAMASK    — alpha < 0.5 时 discard

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

#if COMPILEPS
uniform vec4 u_ShadowColor;
uniform vec4 u_MidColor;        // 三分中间调（z>0 启用）
uniform vec4 u_LightThreshold;  // x=亮阈值, y=软边, z=中阈值, w=法线强度(0=纯几何, 1=贴图全部)
uniform vec4 u_RimColor;        // rgb=tint, a=强度
uniform vec4 u_RimParams;       // x=宽度, y=软边, z=rim 亮度上限, w=亮面增益(0或负=1.0/不增益, 1.2 推荐)
#define cShadowColor    u_ShadowColor
#define cMidColor       u_MidColor
#define cLightThreshold u_LightThreshold.x
#define cLightSoftness  u_LightThreshold.y
#define cMidThreshold   u_LightThreshold.z
#define cNormalStrength u_LightThreshold.w
#define cRimColor       u_RimColor
#define cRimWidth       u_RimParams.x
#define cRimSoftness    u_RimParams.y
#define cRimMaxBright   u_RimParams.z
#define cLightBoostRaw  u_RimParams.w

#ifdef CELPBR
uniform vec4 u_PBRSpec;          // x=Metallic 参数, y=Roughness 参数, z=spec强度, w=spec软度
uniform vec4 u_PBRTexBlend;      // x=Rough 贴图混合, y=Metal 贴图混合, z=AO 强度, w=金属漫反射衰减(0=不衰减,1=严格 PBR,0.5 推荐)
#define cMetallicParam  u_PBRSpec.x
#define cRoughnessParam u_PBRSpec.y
#define cSpecStrength   u_PBRSpec.z
#define cSpecSoftness   u_PBRSpec.w
#define cRoughTexBlend  u_PBRTexBlend.x
#define cMetalTexBlend  u_PBRTexBlend.y
#define cAOStrength     u_PBRTexBlend.z
#define cMetalDimming   u_PBRTexBlend.w
#endif
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

    #if defined(NORMALMAP)
        vec4 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w * cBitangentOddNegativeScale;
        vTexCoord = vec4(GetTexCoord(iTexCoord), bitangent.xy);
        vTangent = vec4(tangent.xyz, bitangent.z);
    #else
        vTexCoord = GetTexCoord(iTexCoord);
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
        vVertexLight = GetAmbient(GetZonePos(worldPos));
        #ifdef NUMVERTEXLIGHTS
            for (int i = 0; i < NUMVERTEXLIGHTS; ++i)
                vVertexLight += GetVertexLight(i, worldPos, vNormal) * cVertexLights[i * 3].rgb;
        #endif
        vScreenPos = GetScreenPos(gl_Position);
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
        vec4 baseColor = cMatDiffColor * diffInput;
    #else
        vec4 baseColor = cMatDiffColor;
    #endif

    #ifdef ALPHAMASK
        if (baseColor.a < 0.5) discard;
    #endif

    #ifdef VERTEXCOLOR
        baseColor *= vColor;
    #endif

    // ===== 法线 =====
    #ifdef NORMALMAP
        vec3 tangent = vTangent.xyz;
        vec3 bitangent = vec3(vTexCoord.zw, vTangent.w);
        mat3 tbn = TR(mat3(tangent, bitangent, vNormal));
        // BC5 packed / RGB normal 通用：从 R+G 取 X/Y 并重建 Z
        vec4 nrmTex = texture2D(sNormalMap, vTexCoord.xy);
        vec3 nrmTS;
        nrmTS.xy = nrmTex.rg * 2.0 - 1.0;
        nrmTS.z  = sqrt(max(1.0 - dot(nrmTS.xy, nrmTS.xy), 0.0));
        // 二次元平滑：cel/rim 用的法线往 (0,0,1)（几何法线）拉近
        float nStrength = clamp(cNormalStrength, 0.0, 1.0);
        vec3 nrmTS_smooth = normalize(mix(vec3(0.0, 0.0, 1.0), nrmTS, nStrength));
        vec3 normalDirection = normalize(mul(tbn, nrmTS_smooth));
        #ifdef CELPBR
            // spec 法线：用 nrmTS 与 nrmTS_smooth 中间值，保留质感同时削减高频噪波
            vec3 nrmTS_specSmooth = normalize(mix(nrmTS_smooth, nrmTS, 0.6));
            vec3 normalDirectionSpec = normalize(mul(tbn, nrmTS_specSmooth));
        #endif
    #else
        vec3 normalDirection = normalize(vNormal);
        #ifdef CELPBR
            vec3 normalDirectionSpec = normalDirection;
        #endif
    #endif

    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);

    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(_WorldPos, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(_WorldPos, cCameraPosPS));
    #endif

    vec3 finalColor = vec3(0.0, 0.0, 0.0);

    #ifdef PERPIXEL
        vec3 lightDir;
        float diff = GetDiffuse(normalDirection, _WorldPos, lightDir);

        float halfSoft = max(cLightSoftness, 0.001);
        float celTerm = smoothstep(cLightThreshold - halfSoft,
                                   cLightThreshold + halfSoft,
                                   diff);

        float shadowTerm = 1.0;
        #ifdef SHADOW
            shadowTerm = GetShadow(vShadowPos, vWorldPos.w);
        #endif
        celTerm *= shadowTerm;

        // ============ Cel-PBR 光照模型（仅 CELPBR）============
        // 流程：采 metallic/roughness/AO → Fresnel-Schlick → 能量守恒 kD → 漫反射 + toon spec
        #ifdef CELPBR
            float roughness, metallic, occlusion;
            #ifdef METALLIC
                // 用更高 mip 等级采样 ⇒ 引擎自动模糊去噪（前提：贴图有 mipmap）
                vec4 specSrc = texture2DLod(sSpecMap, vTexCoord.xy, 2.0);
                float roughTex = clamp(specSrc.r, 0.0, 1.0);
                float metalTex = clamp(specSrc.g, 0.0, 1.0);
                roughness = mix(cRoughnessParam, roughTex, clamp(cRoughTexBlend, 0.0, 1.0));
                metallic  = mix(cMetallicParam,  metalTex, clamp(cMetalTexBlend, 0.0, 1.0));
                occlusion = mix(1.0, clamp(specSrc.b, 0.0, 1.0), clamp(cAOStrength, 0.0, 1.0));
            #else
                roughness = clamp(cRoughnessParam, 0.0, 1.0);
                metallic  = clamp(cMetallicParam,  0.0, 1.0);
                occlusion = 1.0;
            #endif

            // 金属锐化：>0.15 快速跳到 ~1.0，避免脏污像素被误判半金属
            metallic = smoothstep(0.15, 0.5, metallic);

            // ---- Fresnel-Schlick ----
            // F0 = 介质(0.04) ↔ 金属(baseColor)。F 加入 VoH 视角依赖，仅用于 spec 着色。
            vec3 F0 = mix(vec3(0.04, 0.04, 0.04), baseColor.rgb, metallic);
            vec3 halfDir = normalize(lightDir + viewDirection);
            float NoH = max(dot(normalDirectionSpec, halfDir), 0.0);
            float VoH = max(dot(viewDirection,        halfDir), 0.0);
            vec3 F   = F0 + (vec3(1.0, 1.0, 1.0) - F0) * pow(1.0 - VoH, 5.0);  // for spec only

            // ---- 能量守恒（卡通柔化版）----
            // 关键修正：kD 用 F0（head-on Fresnel）而非视角依赖的 F
            // 原因：真实 PBR 中边缘 Fresnel 抢走的能量靠连续 spec 补回；cel 的 spec 是二值块，
            //       块外不补偿。如果 kD 跟 F 走，深色 baseColor 在边缘就被衰减到接近 0 → 比 PBR 更暗。
            // 用 F0 替代后，kD 仅取决于材质属性（metallic/F0），不随视角变化，避免边缘漆黑。
            float metalDim = clamp(cMetalDimming, 0.0, 1.0);
            vec3 kD = (vec3(1.0, 1.0, 1.0) - F0) * (1.0 - metallic * metalDim);
            vec3 diffuseScale = kD * occlusion;
        #else
            // 非 PBR cel 路径默认削减 50%：cel 没有 BRDF/AO 衰减，跟有 occlusion 的 PBR 路径相比
            // 同 baseColor 下亮面会高一截。0.5 是经验值，让 cel 默认表现接近 PBR 平均亮度。
            vec3 diffuseScale = vec3(0.5, 0.5, 0.5);
        #endif

        // ===== 二/三分着色 =====
        float lightBoost = (cLightBoostRaw > 0.001) ? cLightBoostRaw : 1.0;
        // 之前 PBR 路径有 lightBoost * mix(0.65, 1.0, roughness) 的 diffuse 削减（防 spec + diffuse 双亮），
        // 但跟 Cel 路径 vec3(0.5) 削减叠加后 PBR 整体偏暗。统一不削，保留 Cel/PBR 亮度对称。
        float lightBoostFinal = lightBoost;
        vec3 shadowSide = baseColor.rgb * cShadowColor.rgb * diffuseScale;
        vec3 midSide    = baseColor.rgb * cMidColor.rgb    * diffuseScale;
        vec3 lightSide  = baseColor.rgb * cLightColor.rgb  * diffuseScale * lightBoostFinal;

        vec3 lit;
        if (cMidThreshold > 0.001 && cMidThreshold < cLightThreshold)
        {
            float midRaw = smoothstep(cMidThreshold - halfSoft,
                                      cMidThreshold + halfSoft,
                                      diff);
            float midTerm = midRaw * shadowTerm;
            lit = lerp(shadowSide, midSide, midTerm);
            lit = lerp(lit, lightSide, celTerm);
        }
        else
        {
            lit = lerp(shadowSide, lightSide, celTerm);
        }

        // ===== 深色提亮补偿（诊断关闭中）=====
        // 真实 PBR 通过 IBL diffuse + 球谐间接光抬升暗色总亮度（约占暗色总亮度 30~40%）
        // cel 没有这部分能量补偿，深色 baseColor 比 PBR 偏暗很多。
        // [诊断中：临时关闭 pow，验证是否过亮根因]
        // lit = pow(max(lit, vec3(0.0, 0.0, 0.0)), vec3(0.85, 0.85, 0.85));

        // ===== Toon spec（仅 CELPBR）=====
        #ifdef CELPBR
            // Blinn-Phong shape，roughness 决定块大小
            float specPower = mix(256.0, 4.0, roughness * roughness);
            float specRaw   = pow(NoH, specPower);
            // 外层吸收一点法线高频噪波避免边缘燥，内层保持锐利
            float outerSoft = mix(0.005, 0.012, roughness);
            float innerSoft = mix(0.001, 0.003, roughness);
            float thr_outer = mix(0.04, 0.002, roughness);
            float thr_inner = mix(0.97, 0.85,  roughness);
            float outerMask = smoothstep(thr_outer - outerSoft, thr_outer + outerSoft, specRaw);
            float innerMask = smoothstep(thr_inner - innerSoft, thr_inner + innerSoft, specRaw);
            float specMagnitude = outerMask * 0.45 + innerMask * 0.55;
            // 金属额外加成（温和 1.2x，避免油腻）
            float metalSpecBoost = mix(1.0, 1.2, metallic);
            vec3 specularContrib = F * specMagnitude * cLightColor.rgb * cSpecStrength * metalSpecBoost * occlusion * celTerm;
            lit += specularContrib;
        #endif

        // ===== Rim =====
        float rimFresnel = 1.0 - max(dot(normalDirection, viewDirection), 0.0);
        float rimThreshold = 1.0 - clamp(cRimWidth, 0.0, 1.0);
        float rimSoft = max(cRimSoftness, 0.001);
        float rimMask = smoothstep(rimThreshold - rimSoft,
                                   rimThreshold + rimSoft,
                                   rimFresnel);
        rimMask *= cRimColor.a * celTerm;
        vec3 rimBoost = lit * cRimColor.rgb * rimMask;
        if (cRimMaxBright > 0.001) {
            vec3 headroom = max(vec3(cRimMaxBright, cRimMaxBright, cRimMaxBright) - lit, vec3(0.0, 0.0, 0.0));
            rimBoost = min(rimBoost, headroom);
        }
        lit += rimBoost;

        finalColor = lit;

        // ===== Emissive =====
        // 独立于 cel 二分调色叠加，避免暗面把自发光区域吃掉。
        // 仅在 base/litbase pass（AMBIENT）执行；light pass 不加，防止多光源下重复累加。
        // 三种来源（按优先级）：
        //   EMISSIVE_FROM_DIFFUSE_ALPHA — 项目惯例：baseColor 贴图的 alpha 通道是 emissive mask，
        //                                  emissive 颜色直接取 baseColor.rgb（发光色画在 diffuse 里），
        //                                  MatEmissiveColor 当作强度倍乘。要求材质有 DIFFMAP。
        //   EMISSIVEMAP                  — 标准 Urho3D 用法：单独的 emissive 贴图。
        //   else                         — 纯参数 cMatEmissiveColor。
        #ifdef AMBIENT
            #if defined(EMISSIVE_FROM_DIFFUSE_ALPHA) && defined(DIFFMAP)
                finalColor += diffInput.rgb * diffInput.a * cMatEmissiveColor.rgb;
            #elif defined(EMISSIVEMAP)
                finalColor += cMatEmissiveColor.rgb * texture2D(sEmissiveMap, vTexCoord.xy).rgb;
            #else
                finalColor += cMatEmissiveColor.rgb;
            #endif
        #endif
    #else
        finalColor = baseColor.rgb * vVertexLight;

        #ifdef AMBIENT
            #if defined(EMISSIVE_FROM_DIFFUSE_ALPHA) && defined(DIFFMAP)
                finalColor += diffInput.rgb * diffInput.a * cMatEmissiveColor.rgb;
            #elif defined(EMISSIVEMAP)
                finalColor += cMatEmissiveColor.rgb * texture2D(sEmissiveMap, vTexCoord.xy).rgb;
            #else
                finalColor += cMatEmissiveColor.rgb;
            #endif
        #endif
    #endif

    finalColor = GetFog(finalColor, fogFactor);

    gl_FragColor = vec4(finalColor, baseColor.a);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
    #endif
}
