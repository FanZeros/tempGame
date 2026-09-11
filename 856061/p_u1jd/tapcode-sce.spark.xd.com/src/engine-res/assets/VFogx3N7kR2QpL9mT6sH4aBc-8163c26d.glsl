#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "ScreenSpace/ScreenSpaceCommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

SAMPLER2D(u_DepthBuffer0, 0);

uniform hvec4 u_VolumetricFogParams;            // density, height, height falloff, start distance
uniform hvec4 u_VolumetricFogParams2;           // view distance, max opacity, phase g, use shadow
uniform hvec4 u_VolumetricFogParams3;           // shaft contrast, edge threshold, edge softness, occlusion threshold
uniform hvec4 u_VolumetricFogParams4;           // ground fade height, ground fade range, distance fade length, surface fade range
uniform hvec4 u_VolumetricFogScatteringColor;   // rgb
uniform hvec4 u_VolumetricFogAbsorption;        // rgb, intensity
uniform hvec4 u_FroxelSkySH[3];                 // packed RGB L0+L1 diffuse irradiance SH
uniform hvec4 u_FroxelSkyParams;                // x = volumetric intensity, y = sin angle, z = cos angle
uniform hfloat u_FrameIndex;
uniform hvec2 u_JitterOffset;
uniform hmat4 u_InvViewProj;

#if defined(VOLUMETRIC_FOG_FROXEL_DEBUG) || defined(VOLUMETRIC_FOG_FROXEL_COMPOSITE)
SAMPLER3D(u_FroxelVBufferA5, 5);
uniform hvec4 u_FroxelGridParams;               // B, O, S, grid size Z
uniform hvec4 u_FroxelCamForward;               // xyz = camera world forward (normalized)
#endif

#define VOLUMETRIC_FOG_STEPS 32

#ifdef VSM_SHADOW
hfloat VolumetricReduceLightBleeding(hfloat minValue, hfloat pMax)
{
    return clamp((pMax - minValue) / (1.0 - minValue), 0.0, 1.0);
}

hfloat VolumetricChebyshev(hvec2 moments, hfloat depth)
{
    hfloat p = step(depth, moments.x);
    hfloat variance = max(moments.y - moments.x * moments.x, cVSMShadowParams.x);
    hfloat d = depth - moments.x;
    hfloat pMax = variance / (variance + d * d);
    pMax = VolumetricReduceLightBleeding(cVSMShadowParams.y, pMax);
    return max(p, pMax);
}
#endif

hfloat VolumetricSampleShadow(hvec4 shadowPos)
{
#ifndef MOBILE_SHADOW
    #if defined(SIMPLE_SHADOW)
        return shadow2DProj(sShadowMap, shadowPos);
    #elif defined(PCF_SHADOW)
        hvec2 offsets = cShadowMapInvSize * shadowPos.w;
        hvec4 inLight = hvec4_init(
            shadow2DProj(sShadowMap, shadowPos),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + offsets.x, shadowPos.yzw)),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x, shadowPos.y + offsets.y, shadowPos.zw)),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.xy + offsets.xy, shadowPos.zw))
        );
        return dot(inLight, hvec4_init(0.25, 0.25, 0.25, 0.25));
    #elif defined(VSM_SHADOW)
        hvec2 samples = texture2D(sShadowMap, shadowPos.xy / shadowPos.w).rg;
        return VolumetricChebyshev(samples, shadowPos.z / shadowPos.w);
    #else
        return 1.0;
    #endif
#else
    #if defined(SIMPLE_SHADOW)
        return shadow2DProj(sShadowMap, shadowPos) * shadowPos.w > shadowPos.z ? 1.0 : 0.0;
    #elif defined(PCF_SHADOW)
        hvec2 offsets = cShadowMapInvSize;
        hvec4 inLight = hvec4_init(
            shadow2DProj(sShadowMap, shadowPos),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + offsets.x, shadowPos.yzw)),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x, shadowPos.y + offsets.y, shadowPos.zw)),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.xy + offsets.xy, shadowPos.zw))
        );
        return dot(inLight, hvec4_init(0.25, 0.25, 0.25, 0.25));
    #elif defined(VSM_SHADOW)
        hvec2 samples = texture2D(sShadowMap, shadowPos.xy / shadowPos.w).rg;
        return VolumetricChebyshev(samples, shadowPos.z / shadowPos.w);
    #else
        return 1.0;
    #endif
#endif
}

hfloat VolumetricDirShadowFade(hfloat inLight, hfloat depth)
{
    return min(inLight + max((depth - cShadowDepthFade.z) * cShadowDepthFade.w, 0.0), 1.0);
}

hfloat VolumetricDirShadow(hvec4 worldPos, hfloat depth)
{
#if defined(DESKTOP_SHADOW_CASCADE)
    hvec4 shadowPos;
    if (depth < cShadowSplits.x)
        shadowPos = mul(worldPos, cLightMatricesPS[0]);
    else if (depth < cShadowSplits.y)
        shadowPos = mul(worldPos, cLightMatricesPS[1]);
    else if (depth < cShadowSplits.z)
        shadowPos = mul(worldPos, cLightMatricesPS[2]);
    else
        shadowPos = mul(worldPos, cLightMatricesPS[3]);
#elif defined(MOBILE_SHADOW_CASCADE)
    hvec4 shadowPos;
    if (depth < cShadowSplits.x)
        shadowPos = mul(worldPos, cLightMatricesPS[0]);
    else
        shadowPos = mul(worldPos, cLightMatricesPS[1]);
#else
    hvec4 shadowPos = mul(worldPos, cLightMatricesPS[0]);
#endif

    return VolumetricDirShadowFade(VolumetricSampleShadow(shadowPos), depth);
}

hfloat VolumetricShadowOcclusion(hfloat shadow)
{
    return saturate(1.0 - shadow);
}

#ifdef VOLUMETRIC_FOG_SHAFT
hfloat VolumetricReceiverFade(hvec3 samplePos, hvec3 receiverPos, hvec3 lightTravelDir, hfloat fadeRange)
{
    if (fadeRange <= 0.0001)
        return 1.0;

    hfloat receiverDistance = max(dot(receiverPos - samplePos, lightTravelDir), 0.0);
    return smoothstep(0.0, fadeRange, receiverDistance);
}
#endif

hvec4 ReconstructWorldPosition(hvec2 uv, hfloat depth)
{
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    hfloat clipZ = depth * 2.0 - 1.0;
#else
    hfloat clipZ = depth;
#endif

    hvec4 clipPos = hvec4_init(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, clipZ, 1.0);
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    clipPos.y = -clipPos.y;
#endif

    hvec4 worldPos = mul(clipPos, u_InvViewProj);
    return worldPos / worldPos.w;
}

hfloat VolumetricHeightDensity(hvec3 worldPos)
{
    // exp2 底与 UE / froxel media pass 同款（两条路径高度衰减语义一致）
    hfloat heightTerm = (u_VolumetricFogParams.y - worldPos.y) * u_VolumetricFogParams.z;
    return u_VolumetricFogParams.x * exp2(clamp(heightTerm, -20.0, 20.0));
}

hfloat HenyeyGreenstein(hfloat cosTheta, hfloat g)
{
    hfloat g2 = g * g;
    hfloat denom = max(1.0 + g2 - 2.0 * g * cosTheta, 0.0001);
    return (1.0 - g2) / (12.5663706144 * denom * sqrt(denom));
}

hvec3 VolumetricEvaluateSkyLight(hvec3 rayDir, hfloat phaseG)
{
    if (u_FroxelSkyParams.x <= 0.0)
        return hvec3_init(0.0, 0.0, 0.0);

    // 与 PBR/GI.sh 环境旋转同轴同方向；非单位查询向量把低频 phase 方向性折入 L1。
    hvec3 skyDirection = rayDir * -phaseG;
    skyDirection.zx = hvec2_init(
        dot(skyDirection.zx, hvec2_init(u_FroxelSkyParams.z, -u_FroxelSkyParams.y)),
        dot(skyDirection.zx, u_FroxelSkyParams.yz));
    hvec4 shDirection = hvec4_init(skyDirection, 1.0);
    hvec3 skyLighting = hvec3_init(
        dot(u_FroxelSkySH[0], shDirection),
        dot(u_FroxelSkySH[1], shDirection),
        dot(u_FroxelSkySH[2], shDirection));
    return max(skyLighting, hvec3_init(0.0, 0.0, 0.0)) * u_FroxelSkyParams.x;
}

void PS()
{
    hvec2 uv = vTexCoord;
    hfloat rawDepth = texture2D(u_DepthBuffer0, uv).r;
#if defined(VOLUMETRIC_FOG_FROXEL_DEBUG) || defined(VOLUMETRIC_FOG_FROXEL_COMPOSITE)
    // froxel 合成对天空/无几何像素同样生效（UE 语义）：clamp 到远平面距离取全量积分，不早退
    rawDepth = min(rawDepth, 0.99999);
#else
    if (rawDepth > 0.99999)
    {
        gl_FragColor = hvec4_init(0.0, 0.0, 0.0, 0.0);
        return;
    }
#endif

    hvec4 sceneWorld = ReconstructWorldPosition(uv, rawDepth);
    hvec3 cameraPos = cCameraPosPS;
    hvec3 ray = sceneWorld.xyz - cameraPos;
    hfloat sceneDistance = length(ray);
    if (sceneDistance <= 0.0001)
    {
        gl_FragColor = hvec4_init(0.0, 0.0, 0.0, 0.0);
        return;
    }

    hvec3 rayDir = ray / sceneDistance;

#if defined(VOLUMETRIC_FOG_FROXEL_DEBUG) || defined(VOLUMETRIC_FOG_FROXEL_COMPOSITE)
    // froxel 切片按 view-Z 分布（UE ComputeNormalizedZSliceFromDepth 同口径）
    hfloat sceneViewZ = dot(ray, u_FroxelCamForward.xyz);
#endif

#ifdef VOLUMETRIC_FOG_FROXEL_DEBUG
    // 调试：可视化 froxel VBufferA 在场景表面处的介质（view-Z slice 映射与 FroxelMediaCS 一致）。
    // log2 参数钳正：startDistance 较大时 GridZParams 的 O 为负，比雾起点更近的几何
    // 会使参数非正 → NaN（口径同 C++ VolumetricFogGrid::DepthToSlice）
    hfloat debugSlice = log2(max(sceneViewZ * u_FroxelGridParams.x + u_FroxelGridParams.y, 1e-8)) * u_FroxelGridParams.z;
    hfloat debugW = clamp(debugSlice / u_FroxelGridParams.w, 0.0, 1.0);
    hvec4 debugMedia = texture3DLod(u_FroxelVBufferA5, vec3(uv, debugW), 0.0);
    gl_FragColor = hvec4_init(debugMedia.r, debugMedia.g, debugMedia.b, 1.0);
    return;
#endif

#ifdef VOLUMETRIC_FOG_FROXEL_COMPOSITE
    // froxel 合成（UE 语义，premultiplied alpha 混合）：
    //   rgb = 积分 in-scatter，a = min(1 - transmittance, maxOpacity)
    //   dst = src.rgb + dst.rgb * (1 - src.a)，场景被介质透射率真实遮挡。
    // 累积场采样：integrated[k] = 到 slice k 远边界的积分，对场景所在连续坐标 s
    // 取 w=(s-0.5)/gridZ 使 bilinear 在 [integral(0..s_floor), integral(0..s_floor+1)] 间按段内比例插值
    // log2 参数钳正：startDistance 较大时 O 为负，雾起点前的几何会得到非正参数 → NaN，
    // GLSL min/max 对 NaN 行为未定义 → froxelW 未定义 → 近处几何上出现随机雾。
    // 钳后这些像素采样 slice 0（含起点前极薄一段积分，切片厚度下可忽略）
    hfloat froxelSlice = log2(max(sceneViewZ * u_FroxelGridParams.x + u_FroxelGridParams.y, 1e-8)) * u_FroxelGridParams.z;
    hfloat froxelW = clamp((froxelSlice - 0.5) / u_FroxelGridParams.w, 0.0, 1.0);
    hvec4 froxelIntegrated = texture3DLod(u_FroxelVBufferA5, vec3(uv, froxelW), 0.0);
    hfloat froxelOpacity = clamp(1.0 - froxelIntegrated.w, 0.0, u_VolumetricFogParams2.y);
    gl_FragColor = hvec4_init(froxelIntegrated.x, froxelIntegrated.y, froxelIntegrated.z, froxelOpacity);
    return;
#endif

    hfloat startDistance = min(u_VolumetricFogParams.w, sceneDistance);
    hfloat endDistance = min(sceneDistance, u_VolumetricFogParams2.x);
    hfloat rayLength = endDistance - startDistance;
    if (rayLength <= 0.0001)
    {
        gl_FragColor = hvec4_init(0.0, 0.0, 0.0, 0.0);
        return;
    }

    hvec2 pixelCoord = uv / cGBufferInvSize + u_JitterOffset;
    hfloat jitter = InterleavedGradientNoise(pixelCoord + hvec2_init(u_FrameIndex * 17.0, u_FrameIndex * 29.0));
    hfloat stepLength = rayLength / hfloat_init(VOLUMETRIC_FOG_STEPS);
    hfloat phase = 0.0;
    hfloat useShadow = 0.0;
#ifdef DIRLIGHT
    // HG 散射角约定：cosTheta = dot(toLight, rayDir)，看向光源为前向散射峰（此前反号，
    // 光在身后时雾反而最亮；froxel 光照 CS 同步修正）
    hfloat cosTheta = dot(normalize(cLightDirPS), rayDir);
    phase = HenyeyGreenstein(cosTheta, u_VolumetricFogParams2.z);
    useShadow = u_VolumetricFogParams2.w;
#endif
#ifdef VOLUMETRIC_FOG_SHAFT
    hfloat shaftContrast = saturate(u_VolumetricFogParams3.x);
    hfloat shaftGroundFadeHeight = u_VolumetricFogParams4.x;
    hfloat shaftGroundFadeRange = max(u_VolumetricFogParams4.y, 0.0);
    hfloat shaftDistanceFadeLength = max(u_VolumetricFogParams4.z, 0.0);
    hfloat shaftSurfaceFadeRange = max(u_VolumetricFogParams4.w, 0.0);
    hfloat shaftEdgeThreshold = saturate(u_VolumetricFogParams3.y);
    hfloat shaftEdgeSoftness = max(u_VolumetricFogParams3.z, 0.0001);
    hfloat shaftOcclusionThreshold = saturate(u_VolumetricFogParams3.w);
#endif

    hvec3 transmittance = hvec3_init(1.0, 1.0, 1.0);
    hvec3 scattering = hvec3_init(0.0, 0.0, 0.0);
    hvec3 skyScattering = hvec3_init(0.0, 0.0, 0.0);
    hvec3 scatteringColor = hvec3_init(0.0, 0.0, 0.0);
#ifdef DIRLIGHT
    scatteringColor = u_VolumetricFogScatteringColor.rgb * cLightColor.rgb;
#endif
    hvec3 skyScatteringColor =
        u_VolumetricFogScatteringColor.rgb * VolumetricEvaluateSkyLight(rayDir, u_VolumetricFogParams2.z);
    hvec3 absorptionColor = u_VolumetricFogAbsorption.rgb * u_VolumetricFogAbsorption.w;
#ifdef VOLUMETRIC_FOG_SHAFT
    hfloat shadowOcclusionMin = 1.0;
    hfloat shadowOcclusionMax = 0.0;
    hfloat shadowOcclusionSum = 0.0;
    hfloat receiverFadeRange = shaftDistanceFadeLength;
    hfloat shaftRunFadeRange = shaftSurfaceFadeRange;
    hvec3 lightTravelDir = -normalize(cLightDirPS);
    hfloat shaftLitRun = shaftRunFadeRange;
#endif

    for (int i = 0; i < VOLUMETRIC_FOG_STEPS; ++i)
    {
        hfloat sampleDistance = startDistance + (hfloat_init(i) + jitter) * stepLength;
        hvec3 samplePos = cameraPos + rayDir * sampleDistance;
        hfloat density = VolumetricHeightDensity(samplePos);

        hfloat shadow = 0.0;
#ifdef DIRLIGHT
        hvec4 sampleWorld = hvec4_init(samplePos.x, samplePos.y, samplePos.z, 1.0);
        hfloat viewDepth01 = saturate(sampleDistance / max(cFarClipPS, 0.0001));
        shadow = lerp(1.0, VolumetricDirShadow(sampleWorld, viewDepth01), useShadow);
#endif
#ifdef VOLUMETRIC_FOG_SHAFT
        hfloat shadowOcclusion = VolumetricShadowOcclusion(shadow);
        shadowOcclusion = lerp(0.0, shadowOcclusion, useShadow);
        shadowOcclusionMin = min(shadowOcclusionMin, shadowOcclusion);
        shadowOcclusionMax = max(shadowOcclusionMax, shadowOcclusion);
        shadowOcclusionSum += shadowOcclusion;
#endif

        hvec3 extinction = hvec3_init(density, density, density) + absorptionColor * density;
        hvec3 stepTransmittance = exp(-extinction * stepLength);
#ifdef VOLUMETRIC_FOG_SHAFT
        hfloat shaftGroundFade = 1.0;
        if (shaftGroundFadeRange > 0.0001)
            shaftGroundFade = smoothstep(shaftGroundFadeHeight, shaftGroundFadeHeight + shaftGroundFadeRange, samplePos.y);
        hfloat shaftDistanceFade = 1.0;
        if (receiverFadeRange > 0.0001)
            shaftDistanceFade = VolumetricReceiverFade(samplePos, sceneWorld.xyz, lightTravelDir, receiverFadeRange);
        if (shaftRunFadeRange > 0.0001)
        {
            hfloat shadowReset = smoothstep(shaftOcclusionThreshold, shaftOcclusionThreshold + shaftEdgeSoftness, shadowOcclusion);
            shaftLitRun = lerp(shaftLitRun + stepLength, 0.0, shadowReset);
            hfloat shaftRunFade = 1.0 - smoothstep(shaftRunFadeRange * 0.25, shaftRunFadeRange, shaftLitRun);
            shaftDistanceFade = min(shaftDistanceFade, shaftRunFade);
        }
        hfloat shaftFadeWeight = shaftContrast * useShadow;
        hfloat sampleShaftFade = 1.0 + shaftFadeWeight * (shaftGroundFade * shaftDistanceFade - 1.0);
#endif

#ifdef VOLUMETRIC_FOG_SHAFT
        scattering += transmittance * scatteringColor * (density * phase * shadow * stepLength * sampleShaftFade);
#else
        scattering += transmittance * scatteringColor * (density * phase * shadow * stepLength);
#endif
        // SkyLight 第一阶段固定 SkyVisibility=1，不受方向光阴影与 shaft fade 调制。
        skyScattering += transmittance * skyScatteringColor * (density * stepLength);
        transmittance *= stepTransmittance;
    }

#ifdef VOLUMETRIC_FOG_SHAFT
    // MC-like shafts need shadow variation along the ray. Uniformly lit outdoor fog is suppressed here.
    hfloat shadowOcclusionRange = max(shadowOcclusionMax - shadowOcclusionMin, 0.0);
    hfloat shadowOcclusionMean = shadowOcclusionSum / hfloat_init(VOLUMETRIC_FOG_STEPS);
    hfloat mixedShadowAmount = min(shadowOcclusionMean, 1.0 - shadowOcclusionMean);
    hfloat edgeMask = smoothstep(shaftEdgeThreshold, shaftEdgeThreshold + shaftEdgeSoftness, shadowOcclusionRange);
    hfloat mixedMask = smoothstep(shaftOcclusionThreshold, shaftOcclusionThreshold + shaftEdgeSoftness * 0.5, mixedShadowAmount);
    hfloat shaftMask = lerp(1.0, edgeMask * mixedMask, useShadow);
    scattering *= lerp(1.0, shaftMask, shaftContrast);
#endif
    scattering += skyScattering;
    scattering *= u_VolumetricFogParams2.y;
    gl_FragColor = hvec4_init(scattering.x, scattering.y, scattering.z, 1.0);
}

#endif
