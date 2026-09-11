// Froxel light scattering: 读 VBufferA 介质，注入方向光（级联阴影 + HG phase）
// 与点光/聚光的 in-scatter，写入 LightScattering (radiance.rgb + extinction.a)。
// 对应 UE5 VolumetricFog.usf 的 LightScatteringCS 阶段（暂无 SkyVisibility / 局部光阴影）。
//
// 矩阵约定：本引擎所有 uniform 矩阵（Matrix4 重载与裸 float 数组上传相同）
// 在 shader 侧一律用 mul(vec, matrix) 行向量乘，与 fragment 侧一致。
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"
#include "Common/bgfx_compute.sh"
#ifdef CLUSTER_FOG_LIGHT_GRID
#include "Cluster/clusterlights.sh"
#include "Cluster/clusters.sh"
#endif

// 只读体纹理一律走 SAMPLER3D + texelFetch：GL 后端 compute 的 imageLoad（IMAGE3D_RO）
// 读 3D 纹理返回零（写入 IMAGE3D_WR 正常），采样器路径跨后端可靠。
// DIR_LIGHT 变体 = 存在带阴影方向光；无变体时（室内/夜景）跳过 shadow 采样器与方向光注入。
SAMPLER3D(u_FroxelVBufferA0, 0);
IMAGE3D_WR(u_FroxelLightScattering1, rgba16f, 1);
#ifdef DIR_LIGHT
SAMPLER2DSHADOW(u_FroxelShadowMap2, 2);
#endif
SAMPLER3D(u_FroxelHistory3, 3);
SAMPLER3D(u_FroxelVBufferB4, 4);
#ifdef CONSERVATIVE_DEPTH
SAMPLER2D(u_FroxelConservativeDepth5, 5);
SAMPLER2D(u_FroxelPrevConservativeDepth6, 6);
#endif

uniform vec4 u_FroxelGridSize;          // xyz = froxel grid dims
uniform vec4 u_FroxelGridZParams;       // B, O, S
uniform vec4 u_FroxelCamPos;            // xyz = camera world position, w = far clip
uniform mat4 u_FroxelInvViewProj;
#ifdef CONSERVATIVE_DEPTH
uniform mat4 u_FroxelViewProj;
#endif
uniform vec4 u_FroxelSunDir;            // xyz = direction towards the light, w = phase g
uniform vec4 u_FroxelSunColor;          // rgb = color * intensity, w = use shadow
uniform vec4 u_FroxelSkySH[3];          // packed RGB L0+L1 diffuse irradiance SH
uniform vec4 u_FroxelSkyParams;         // x = volumetric intensity, y = sin angle, z = cos angle
uniform mat4 u_FroxelShadowMatrices[4];
uniform vec4 u_FroxelShadowSplits;      // 归一化 far splits（无级联时为大值）
uniform vec4 u_FroxelShadowDepthFade;   // q, r, fade start, 1 / fade range
uniform vec4 u_FroxelShadowMapSize;     // xy = inv size, z = num splits, w = unused
#ifndef CLUSTER_FOG_LIGHT_GRID
uniform vec4 u_FroxelLightCount;        // x = local light count
#endif
uniform vec4 u_FroxelTemporal;          // x = history 混合权重（首帧为 0），y = 时域启用标志（0 = 用户关闭，禁 miss 超采样），z = LightSoftFading（0 = 关闭）
uniform vec4 u_FroxelJitters[4];        // xyz = 全局 3D Halton(2,3,5) 抖动（[0]=本帧主样本，[1..3]=miss 超采样）
uniform mat4 u_FroxelPrevViewProj;
uniform vec4 u_FroxelCamForward;        // xyz = camera world forward (normalized)
#ifdef CLUSTER_FOG_LIGHT_GRID
uniform vec4 u_FroxelClusterViewSize;   // xy = viewport size used to build the shared cluster grid
#else
// 每灯 5 个 vec4（布局与 VolumetricFog.cpp 打包段严格一致）：
// L0 = pos.xyz + range；L1 = color.rgb + w（spot=invCosConeDiff / 矩形=cos(barn 角)，≥1.5 无遮光板）；
// L2 = dir.xyz + w 类型标记（spot=cosOuter(≥-1) / 点光=-2 / 矩形=-3 / 球管面积点光=-4）；
// L3 = 切线.xyz + halfWidth（矩形=半宽 / -4=轴向+半长）；
// L4 = 矩形=(barn 长度, 0, 0, halfHeight)（副切线由 cross 推导）；其余类型 L4.w 传源半径但当前不采样，预留
#define MaxFroxelLocalLights 16
uniform vec4 u_FroxelLights[80];
#endif

float FroxelSliceToDepth(float slice)
{
    return (exp2(slice / u_FroxelGridZParams.z) - u_FroxelGridZParams.y) / u_FroxelGridZParams.x;
}

float FroxelHenyeyGreenstein(float cosTheta, float g)
{
    float g2 = g * g;
    float denom = max(1.0 + g2 - 2.0 * g * cosTheta, 0.0001);
    return (1.0 - g2) / (12.5663706144 * denom * sqrt(denom));
}

vec3 FroxelEvaluateSkyLight(vec3 rayDir, float phaseG)
{
    if (u_FroxelSkyParams.x <= 0.0)
        return vec3(0.0, 0.0, 0.0);

    // 与 PBR/GI.sh 环境旋转同轴同方向；非单位查询向量把低频 phase 方向性折入 L1。
    vec3 skyDirection = rayDir * -phaseG;
    skyDirection.zx = vec2(
        dot(skyDirection.zx, vec2(u_FroxelSkyParams.z, -u_FroxelSkyParams.y)),
        dot(skyDirection.zx, u_FroxelSkyParams.yz));
    vec4 shDirection = vec4(skyDirection, 1.0);
    vec3 skyLighting = vec3(
        dot(u_FroxelSkySH[0], shDirection),
        dot(u_FroxelSkySH[1], shDirection),
        dot(u_FroxelSkySH[2], shDirection));
    return max(skyLighting, vec3(0.0, 0.0, 0.0)) * u_FroxelSkyParams.x;
}

// 距离衰减与 cluster 表面光照同款（Cluster/clusterlights.sh smoothAttenuation）：
// windowed inverse-square。softenSq = 近场软化偏置（点/聚光/球管面积光传网格 cellBiasSq；
// 矩形光不走此函数——用向量辐照度解析积分，自带有界近场）。
float FroxelSmoothAttenuation(float distance, float radius, float softenSq)
{
    float nom = clamp(1.0 - pow(distance / radius, 4.0), 0.0, 1.0);
    return nom * nom / max(distance * distance + softenSq, 0.0001);
}

#ifdef DIR_LIGHT
float FroxelSampleShadow(vec4 shadowPos)
{
    // 4-tap PCF，口径同 Volumetric/VolumetricFog.glsl 的 PCF_SHADOW 分支
    vec2 offsets = u_FroxelShadowMapSize.xy * shadowPos.w;
    vec4 inLight = vec4(
        shadow2DProj(u_FroxelShadowMap2, shadowPos),
        shadow2DProj(u_FroxelShadowMap2, vec4(shadowPos.x + offsets.x, shadowPos.yzw)),
        shadow2DProj(u_FroxelShadowMap2, vec4(shadowPos.x, shadowPos.y + offsets.y, shadowPos.zw)),
        shadow2DProj(u_FroxelShadowMap2, vec4(shadowPos.xy + offsets.xy, shadowPos.zw)));
    return dot(inLight, vec4(0.25, 0.25, 0.25, 0.25));
}

float FroxelDirShadow(vec4 worldPos, float depth01)
{
    vec4 shadowPos;
    if (depth01 < u_FroxelShadowSplits.x)
        shadowPos = mul(worldPos, u_FroxelShadowMatrices[0]);
    else if (depth01 < u_FroxelShadowSplits.y)
        shadowPos = mul(worldPos, u_FroxelShadowMatrices[1]);
    else if (depth01 < u_FroxelShadowSplits.z)
        shadowPos = mul(worldPos, u_FroxelShadowMatrices[2]);
    else
        shadowPos = mul(worldPos, u_FroxelShadowMatrices[3]);

    float inLight = FroxelSampleShadow(shadowPos);
    // depth fade，同 VolumetricDirShadowFade
    return min(inLight + max((depth01 - u_FroxelShadowDepthFade.z) * u_FroxelShadowDepthFade.w, 0.0), 1.0);
}
#endif

// 单点求矩形光几何因子：range 窗口 × barn 投影裁剪 × Lambert 向量辐照度解析积分 ×
// 边缘软化；被背面/range/门板完全裁剪时返回 0。
// 参数：worldPos = 采样点；posRange = 灯位置+range；cosBarn = cos(barn 角)（≥1.5 无门板）；
// dirN = 灯法线（发射方向）；tanW = 切线+halfWidth；bitanH = (barn 长, 0, 0, halfHeight)；
// softFadeDist = 边缘羽化宽度（UE LightVolumetricSoftFadeDistance = LightSoftFading ×
// Cell2DRadius；≤0 = 软化关闭 = UE r.VolumetricFog.LightSoftFading=0 的硬边行为）
float FroxelRectLightFactor(vec3 worldPos, vec4 posRange, float cosBarn, vec3 dirN, vec4 tanW,
                            vec4 bitanH, float softFadeDist)
{
    vec3 bitan = cross(dirN, tanW.xyz);
    vec3 rel = worldPos - posRange.xyz;
    // 灯空间坐标：x=切线（半宽轴）、y=副切线（半高轴）、z=法线（发光方向）
    vec3 sL = vec3(dot(rel, tanW.xyz), dot(rel, bitan), dot(rel, dirN));

    // 背面剔除（UE GetLocalLightAttenuation 对 rect 的二值剔除同款）
    if (sL.z <= 0.0)
        return 0.0;

    // 边缘软化（UE GetRectLightVolumetricSoftFading）：灯面/barn 锥面的硬可见性边界
    // 在粗网格 + 逐帧 jitter 下走样成闪烁，按 softFadeDist 羽化。宽度只用侧向尺度
    //（UE Cell2DRadius 口径，不含切片厚度）——大视距下切片厚过整根光束，
    // 用 3D cellRadius 会把光束整个抹掉
    bool softFadeEnabled = softFadeDist > 0.0;
    float faceFadeInv = 1.0 / max(softFadeDist, 1e-3);
    float softFade = softFadeEnabled ? clamp(sL.z * faceFadeInv, 0.0, 1.0) : 1.0;

    // range 窗口取中心距离口径（UE LightMask / 表面 GetLightRangeMask 同款，
    // 无 1/d²——距离衰减已含在向量辐照度积分内）
    float distSqr = dot(rel, rel);
    float invRangeSqr = 1.0 / (posRange.w * posRange.w);
    float rangeT = distSqr * invRangeSqr;
    float rangeMask = clamp(1.0 - rangeT * rangeT, 0.0, 1.0);
    rangeMask *= rangeMask;
    if (rangeMask <= 0.0)
        return 0.0;

    vec2 ext = vec2(tanW.w, bitanH.w);
    vec2 rectOff = vec2(0.0, 0.0);

    // barn door（遮光板）：UE RectLight.ush GetRect 同款投影裁剪——把门尖从采样点
    // 反投影回灯面，连续收缩可见矩形；能量衰减由「对裁剪后小矩形积分」自然给出
    if (cosBarn < 1.5)
    {
        float sinBarn = sqrt(max(1.0 - cosBarn * cosBarn, 0.0));
        float barnLen = bitanH.x;

        // barn 锥面羽化（UE GetRectLightVolumetricSoftFading 同款，软化关闭时跳过 =
        // UE USE_LIGHT_SOFT_FADING 关闭分支）：GetRect 投影裁剪在门尖深度以内是二值边界，
        // 四块门板内侧平面距离按羽化宽度 saturate 相乘，门尖以远渐隐。
        // 生效门限 = barnLenOrtho + FadeFroxelCount(4) × 羽化宽度（UE 同式）
        float barnLenOrtho = cosBarn * barnLen;
        if (softFadeEnabled && sL.z < barnLenOrtho + 4.0 * softFadeDist)
        {
            float tipFade = clamp((sL.z - barnLenOrtho) * (0.25 * faceFadeInv), 0.0, 1.0);
            // 门长不足一个格宽时门几乎不遮，直接视为全亮
            tipFade = mix(tipFade, 1.0, 1.0 - clamp(barnLen * faceFadeInv, 0.0, 1.0));
            float doorFade =
                clamp((sinBarn * sL.z - cosBarn * (sL.x - ext.x)) * faceFadeInv, 0.0, 1.0) *
                clamp((sinBarn * sL.z + cosBarn * (sL.x + ext.x)) * faceFadeInv, 0.0, 1.0) *
                clamp((sinBarn * sL.z - cosBarn * (sL.y - ext.y)) * faceFadeInv, 0.0, 1.0) *
                clamp((sinBarn * sL.z + cosBarn * (sL.y + ext.y)) * faceFadeInv, 0.0, 1.0);
            softFade *= mix(doorFade, 1.0, tipFade);
            if (softFade <= 0.0)
                return 0.0;
        }

        // 门尖深度与侧向外扩（采样点比门尖更贴灯面时按比例缩短生效段）
        float barnDepth = min(sL.z, cosBarn * barnLen);
        float dB = sinBarn * barnLen * (barnDepth / max(cosBarn * barnLen, 1e-4));
        // 采样点在 barn 视锥足印内时推到边缘（dS-dB ≤ 0 → 不裁剪）
        vec2 signS = sign(sL.xy);
        vec2 sxy = signS * max(abs(sL.xy), ext + vec2(dB, dB));
        // 门尖到采样点方向的正切 × 门尖深度 = 门在灯面上的投影遮挡量
        vec2 tanEta = (abs(sxy) - (ext + vec2(dB, dB))) / max(sL.z - barnDepth, 1e-3);
        vec2 dS = barnDepth * tanEta;
        // 只有采样点所在侧的门参与该轴裁剪
        vec2 minXY = clamp(-ext + (dS - vec2(dB, dB)) * max(vec2(0.0, 0.0), -signS), -ext, ext);
        vec2 maxXY = clamp(ext - (dS - vec2(dB, dB)) * max(vec2(0.0, 0.0), signS), -ext, ext);
        rectOff = 0.5 * (minXY + maxXY);
        vec2 newExt = 0.5 * (maxXY - minXY);
        if (newExt.x <= 0.0 || newExt.y <= 0.0)
            return 0.0;
        ext = newExt;
    }

    // 裁剪后矩形四角在「采样点为原点、(切线, 副切线, 距灯面深度)」坐标系下的位置
    //（四角共面 z = sL.z，UE RectIrradianceLambert 的 LocalPosition 优化路径同款）。
    // 无距离偏置（UE 口径：rect 光不走 Capsule 的 DistBiasSqr，积分本身有界 ≤π）
    vec2 lp = rectOff - sL.xy;
    float x0 = lp.x - ext.x;
    float x1 = lp.x + ext.x;
    float y0 = lp.y - ext.y;
    float y1 = lp.y + ext.y;
    float z0 = sL.z;
    float z0Sqr = z0 * z0;

    vec3 c0 = vec3(x0, y0, z0);
    vec3 c1 = vec3(x1, y0, z0);
    vec3 c2 = vec3(x1, y1, z0);
    vec3 c3 = vec3(x0, y1, z0);
    vec3 L0 = c0 * inversesqrt(dot(c0.xy, c0.xy) + z0Sqr);
    vec3 L1 = c1 * inversesqrt(dot(c1.xy, c1.xy) + z0Sqr);
    vec3 L2 = c2 * inversesqrt(dot(c2.xy, c2.xy) + z0Sqr);
    vec3 L3 = c3 * inversesqrt(dot(c3.xy, c3.xy) + z0Sqr);

    // 边积分权重：acos(x) ≈ sqrt(1-x)·(1.5708-0.175x)，normalize(cross) 合并进 rsqrt
    float c01 = dot(L0, L1);
    float c12 = dot(L1, L2);
    float c23 = dot(L2, L3);
    float c30 = dot(L3, L0);
    float w01 = (1.5708 - 0.175 * c01) * inversesqrt(max(c01 + 1.0, 1e-4));
    float w12 = (1.5708 - 0.175 * c12) * inversesqrt(max(c12 + 1.0, 1e-4));
    float w23 = (1.5708 - 0.175 * c23) * inversesqrt(max(c23 + 1.0, 1e-4));
    float w30 = (1.5708 - 0.175 * c30) * inversesqrt(max(c30 + 1.0, 1e-4));

    vec3 vecIrr = cross(L1, -w01 * L0 + w12 * L2) + cross(L3, w30 * L0 - w23 * L2);
    float baseIrr = 0.5 * length(vecIrr);

    return baseIrr * rangeMask * softFade;
}

#ifdef CLUSTER_FOG_LIGHT_GRID
uint FroxelGetClusterIndex(uvec3 froxel)
{
    vec2 froxelUv = (vec2(froxel.xy) + vec2(0.5, 0.5)) / u_FroxelGridSize.xy;
    vec2 viewPixel = froxelUv * u_FroxelClusterViewSize.xy;
    float centerDepth = FroxelSliceToDepth(float(froxel.z) + 0.5);
    uvec3 gridSize = getClusterGridSize();
    uvec3 indices = uvec3(uvec2(viewPixel / u_clusterSizes), getDeferredClusterZIndex(centerDepth));
    indices = min(indices, gridSize - uvec3(1u, 1u, 1u));
    return getClusterLinearIndex(indices);
}
#endif

vec3 FroxelEvaluateLocalLight(vec3 worldPos, vec3 rayDir, float phaseG, float lateralSize, float cellBiasSq,
                              vec4 posRange, vec4 colorInner, vec4 dirW, vec4 tanW, vec4 bitanH)
{
    if (dirW.w < -3.5)
    {
        // 球/管状面积点光（non-punctual point）：线段最近点距离，全向发光（无锥/无半球因子）。
        vec3 rel = worldPos - posRange.xyz;
        vec3 nearest = posRange.xyz + tanW.xyz * clamp(dot(rel, tanW.xyz), -tanW.w, tanW.w);
        vec3 toLight = nearest - worldPos;
        float d = length(toLight);
        if (d >= posRange.w)
            return vec3(0.0, 0.0, 0.0);

        vec3 lightDir = toLight / max(d, 0.0001);
        float att = FroxelSmoothAttenuation(d, posRange.w, cellBiasSq);
        float phase = FroxelHenyeyGreenstein(dot(lightDir, rayDir), phaseG);
        return colorInner.rgb * (att * phase);
    }

    if (dirW.w < -2.5)
    {
        // 矩形光：barn 投影裁剪 + Lambert 向量辐照度解析积分 + 边缘软化。
        float softFadeDist = u_FroxelTemporal.z * 1.41421 * lateralSize;
        float factor = FroxelRectLightFactor(worldPos, posRange, colorInner.w, dirW.xyz, tanW, bitanH,
                                             softFadeDist);
        if (factor <= 0.0)
            return vec3(0.0, 0.0, 0.0);

        vec3 rel = worldPos - posRange.xyz;
        vec3 lightDir = rel * (-inversesqrt(max(dot(rel, rel), 1e-8)));
        float phase = FroxelHenyeyGreenstein(dot(lightDir, rayDir), phaseG);
        return colorInner.rgb * (factor * phase);
    }

    vec3 toLight = posRange.xyz - worldPos;
    float d = length(toLight);
    if (d >= posRange.w)
        return vec3(0.0, 0.0, 0.0);

    vec3 lightDir = toLight / max(d, 0.0001);
    float att = FroxelSmoothAttenuation(d, posRange.w, cellBiasSq);
    float cone = 1.0;
    if (dirW.w > -1.5)
    {
        cone = clamp((dot(dirW.xyz, -lightDir) - dirW.w) * colorInner.w, 0.0, 1.0);
        cone = cone * cone;

        float softFadeDist = u_FroxelTemporal.z * 1.41421 * lateralSize;
        if (softFadeDist > 0.0 && dirW.w > 0.0)
        {
            float sinOuter = sqrt(max(1.0 - dirW.w * dirW.w, 0.0));
            float tanOuter = sinOuter / dirW.w;
            vec3 rel = -toLight;
            float distAlong = dot(dirW.xyz, rel);
            float aperture = distAlong * tanOuter;
            float distFromAxis = length(rel - dirW.xyz * distAlong);
            float coneDiff = aperture - distFromAxis;
            if (coneDiff < softFadeDist)
                cone *= clamp(coneDiff / max(softFadeDist, 1e-4), 0.0, 1.0);
        }
    }

    float phase = FroxelHenyeyGreenstein(dot(lightDir, rayDir), phaseG);
    return colorInner.rgb * (att * cone * phase);
}

// froxel 内偏移 offset（[0,1)³）处的视线方向（xy 面内）
vec3 FroxelRayDir(uvec3 froxel, vec2 xyOffset)
{
    vec2 uv = (vec2(froxel.xy) + xyOffset) / vec2(u_FroxelGridSize.xy);
// NDC y 约定：GLSL 后端不翻转（同 ReconstructWorldPosition 的分支）
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    vec2 ndc = vec2(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0);
#else
    vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
#endif
    vec4 rayPoint = mul(vec4(ndc, 0.0, 1.0), u_FroxelInvViewProj);
    rayPoint.xyz /= rayPoint.w;
    return normalize(rayPoint.xyz - u_FroxelCamPos.xyz);
}

// 单次散射采样：在 jitter（xy = 格内偏移、z = slice 内偏移，均 [0,1)）处求全部光源 in-scatter。
// UE LightScatteringCS 同构：光照采样位置带全局 3D Halton 逐帧抖动；history 重投影用
// froxel 中心（UE ComputeCellTranslatedWorldPosition(GridCoordinate, .5f)，不带抖动）。
// 切片按 view-Z 分布（UE ComputeDepthFromZSlice 同口径），world 位置沿视线推进到
// 该 view-Z 平面：dist = depth / dot(rayDir, forward)
vec3 FroxelComputeRadiance(uvec3 froxel, vec3 jitter, float phaseG)
{
    vec3 rayDir = FroxelRayDir(froxel, jitter.xy);
    float depth = FroxelSliceToDepth(float(froxel.z) + jitter.z);
    float dist = depth / max(dot(rayDir, u_FroxelCamForward.xyz), 0.0001);
    vec3 worldPos = u_FroxelCamPos.xyz + rayDir * dist;

    vec3 radiance = vec3(0.0, 0.0, 0.0);

#ifdef DIR_LIGHT
    // 方向光：phase + 级联阴影。HG 散射角 = 入射光子方向(-toLight)与出射方向(froxel→相机
    // = -rayDir)夹角，cosTheta = dot(toLight, rayDir)：看向光源为前向散射峰（银边效应）
    {
        float cosTheta = dot(normalize(u_FroxelSunDir.xyz), rayDir);
        float phase = FroxelHenyeyGreenstein(cosTheta, phaseG);
        // 级联选择按 view-Z 归一化（与主渲染 shadow split 口径一致）
        float depth01 = clamp(depth / max(u_FroxelCamPos.w, 0.0001), 0.0, 1.0);
        float shadow = mix(1.0, FroxelDirShadow(vec4(worldPos, 1.0), depth01), u_FroxelSunColor.w);
        radiance += u_FroxelSunColor.rgb * (phase * shadow);
    }
#endif

    // SkyLight 是无阴影的全局环境贡献，不进入 cluster light list。
    radiance += FroxelEvaluateSkyLight(rayDir, phaseG);

    // 局部光：点光/聚光/矩形光，解析衰减 + phase，暂无局部阴影。
    // 平方反比距离偏置（UE r.VolumetricFog.InverseSquaredLightDistanceBiasScale=1 同款）：
    // 雾网格粗采样下灯芯 froxel 的 1/d² 爆炸会被 bilinear/temporal 涂成大亮团/块状颗粒。
    // UE 口径：DistanceBias = max(CellRadius, 1cm)，CellRadius = froxel 全 3D 对角长
    // （VolumetricFog.usf 取到 +1,+1,+1 邻居的距离）。
    // slice view-Z 厚度 = d(depth)/d(slice) = (depth + O/B)·ln2/S（GridZParams.w 预存
    // ln2/S），换算成沿视线的世界长度 ×(dist/depth)
    float lateralSize = dist * u_FroxelGridSize.w;
    float sliceThickness = (depth + u_FroxelGridZParams.y / max(u_FroxelGridZParams.x, 0.0001)) *
                           u_FroxelGridZParams.w * (dist / max(depth, 0.0001));
    float cellRadius = max(sqrt(2.0 * lateralSize * lateralSize + sliceThickness * sliceThickness), 0.01);
    float cellBiasSq = cellRadius * cellRadius;

#ifdef CLUSTER_FOG_LIGHT_GRID
    LightGrid grid = getLightGrid(FroxelGetClusterIndex(froxel));
    for (uint i = 0u; i < grid.pointLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.offset, i);
#ifdef CLUSTER_SPOTLIGHT
        SpotLight light = GetSpotLight(lightIndex);
        if (light.volumetricFogIntensity <= 0.0)
            continue;
        vec4 posRange = vec4(light.position, light.range);
        vec4 colorInner = vec4(abs(light.intensity) * light.volumetricFogIntensity, light.invCosConeDiff);
        vec4 dirW = vec4(light.direction, light.cosOuterCone);
#else
        PointLight light = GetPointLight(lightIndex);
        if (light.volumetricFogIntensity <= 0.0)
            continue;
        vec4 posRange = vec4(light.position, light.range);
        vec4 colorInner = vec4(abs(light.intensity) * light.volumetricFogIntensity, 1.0);
        vec4 dirW = vec4(0.0, 0.0, 0.0, -2.0);
#endif
        radiance += FroxelEvaluateLocalLight(worldPos, rayDir, phaseG, lateralSize, cellBiasSq, posRange,
                                             colorInner, dirW, vec4(0.0, 0.0, 0.0, 0.0),
                                             vec4(0.0, 0.0, 0.0, 0.0));
    }

#if NONPUNCTUAL_LIGHTING
    for (uint i = 0u; i < grid.nonPunctualPointLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.nonPunctualPointLightsOffset, i);
        NonPunctualPointLight light = GetNonPunctualPointLight(lightIndex);
        if (light.volumetricFogIntensity <= 0.0)
            continue;
        vec4 posRange = vec4(light.position, light.range);
        vec4 colorInner = vec4(abs(light.intensity) * light.volumetricFogIntensity, 1.0);
        vec4 dirW = vec4(0.0, 0.0, 0.0, -4.0);
        vec4 axisLen = vec4(light.direction, light.length * 0.5);
        radiance += FroxelEvaluateLocalLight(worldPos, rayDir, phaseG, lateralSize, cellBiasSq, posRange,
                                             colorInner, dirW, axisLen, vec4(0.0, 0.0, 0.0, 0.0));
    }

    for (uint i = 0u; i < grid.rectLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.rectLightsOffset, i);
        RectLight light = GetRectLight(lightIndex);
        if (light.volumetricFogIntensity <= 0.0)
            continue;
        float fogBarnCos = light.barnCosAngle > 0.035 ? light.barnCosAngle : 2.0;
        vec4 posRange = vec4(light.position, light.range);
        vec4 colorInner = vec4(abs(light.intensity) * light.volumetricFogIntensity, fogBarnCos);
        vec4 dirW = vec4(light.direction, -3.0);
        vec4 tanW = vec4(light.tangent, light.halfWidth);
        vec4 bitanH = vec4(light.barnLength, 0.0, 0.0, light.halfHeight);
        radiance += FroxelEvaluateLocalLight(worldPos, rayDir, phaseG, lateralSize, cellBiasSq, posRange,
                                             colorInner, dirW, tanW, bitanH);
    }
#endif
#else
    int lightCount = int(u_FroxelLightCount.x);
    for (int i = 0; i < MaxFroxelLocalLights; ++i)
    {
        if (i >= lightCount)
            break;

        vec4 posRange = u_FroxelLights[i * 5 + 0];
        vec4 colorInner = u_FroxelLights[i * 5 + 1];
        vec4 dirW = u_FroxelLights[i * 5 + 2];
        vec4 tanW = u_FroxelLights[i * 5 + 3];
        vec4 bitanH = u_FroxelLights[i * 5 + 4];
        radiance += FroxelEvaluateLocalLight(worldPos, rayDir, phaseG, lateralSize, cellBiasSq, posRange,
                                             colorInner, dirW, tanW, bitanH);
    }
#endif

    return radiance;
}

#ifdef CONSERVATIVE_DEPTH
float FroxelClipToDeviceDepth(vec4 clipPos)
{
    float depth = clipPos.z / clipPos.w;
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    depth = depth * 0.5 + 0.5;
#endif
    return depth;
}

bool FroxelIsBehindConservativeDepth(float cellDepth, float sceneDepth)
{
#ifdef REVERSED_Z
    return sceneDepth > cellDepth;
#else
    return cellDepth > sceneDepth;
#endif
}

bool FroxelIsHistoryDepthValid(float cellDepth, float sceneDepth)
{
#ifdef REVERSED_Z
    return sceneDepth < cellDepth;
#else
    return sceneDepth > cellDepth;
#endif
}

vec3 FroxelConservativeWorldPosition(uvec3 froxel)
{
    vec3 rayDir = FroxelRayDir(froxel, vec2(0.5, 0.5));
    float depth = FroxelSliceToDepth(max(float(froxel.z) - 0.5, 0.0));
    float dist = depth / max(dot(rayDir, u_FroxelCamForward.xyz), 0.0001);
    return u_FroxelCamPos.xyz + rayDir * dist;
}

bool FroxelFixupHistoryUV(inout vec2 historyUv, float prevCellDepth)
{
    vec2 gridSizeXY = u_FroxelGridSize.xy;
    vec2 bilinearPos = historyUv * gridSizeXY - vec2(0.5, 0.5);
    ivec2 base = ivec2(floor(bilinearPos));
    vec2 weights = fract(bilinearPos);
    ivec2 maxCoord = ivec2(gridSizeXY) - ivec2(1, 1);

    ivec2 coord00 = clamp(base, ivec2(0, 0), maxCoord);
    ivec2 coord10 = clamp(base + ivec2(1, 0), ivec2(0, 0), maxCoord);
    ivec2 coord01 = clamp(base + ivec2(0, 1), ivec2(0, 0), maxCoord);
    ivec2 coord11 = clamp(base + ivec2(1, 1), ivec2(0, 0), maxCoord);

    bool valid00 = FroxelIsHistoryDepthValid(
        prevCellDepth, texelFetch(u_FroxelPrevConservativeDepth6, coord00, 0).r);
    bool valid10 = FroxelIsHistoryDepthValid(
        prevCellDepth, texelFetch(u_FroxelPrevConservativeDepth6, coord10, 0).r);
    bool valid01 = FroxelIsHistoryDepthValid(
        prevCellDepth, texelFetch(u_FroxelPrevConservativeDepth6, coord01, 0).r);
    bool valid11 = FroxelIsHistoryDepthValid(
        prevCellDepth, texelFetch(u_FroxelPrevConservativeDepth6, coord11, 0).r);

    if (valid00 && valid10 && valid01 && valid11)
        return true;

    if (valid00 && valid10)
    {
        historyUv.y = (float(coord00.y) + 0.5) / gridSizeXY.y;
        return true;
    }
    if (valid01 && valid11)
    {
        historyUv.y = (float(coord01.y) + 0.5) / gridSizeXY.y;
        return true;
    }
    if (valid00 && valid01)
    {
        historyUv.x = (float(coord00.x) + 0.5) / gridSizeXY.x;
        return true;
    }
    if (valid10 && valid11)
    {
        historyUv.x = (float(coord10.x) + 0.5) / gridSizeXY.x;
        return true;
    }

    float bestWeight = -1.0;
    ivec2 bestCoord = coord00;
    float weight00 = (1.0 - weights.x) * (1.0 - weights.y);
    float weight10 = weights.x * (1.0 - weights.y);
    float weight01 = (1.0 - weights.x) * weights.y;
    float weight11 = weights.x * weights.y;
    if (valid00 && weight00 > bestWeight)
    {
        bestWeight = weight00;
        bestCoord = coord00;
    }
    if (valid10 && weight10 > bestWeight)
    {
        bestWeight = weight10;
        bestCoord = coord10;
    }
    if (valid01 && weight01 > bestWeight)
    {
        bestWeight = weight01;
        bestCoord = coord01;
    }
    if (valid11 && weight11 > bestWeight)
    {
        bestWeight = weight11;
        bestCoord = coord11;
    }
    if (bestWeight < 0.0)
        return false;

    historyUv = (vec2(bestCoord) + vec2(0.5, 0.5)) / gridSizeXY;
    return true;
}
#endif

NUM_THREADS(4, 4, 4)
void main()
{
    uvec3 froxel = gl_GlobalInvocationID.xyz;
    uvec3 gridSize = uvec3(u_FroxelGridSize.xyz);
    if (froxel.x >= gridSize.x || froxel.y >= gridSize.y || froxel.z >= gridSize.z)
        return;

#ifdef CONSERVATIVE_DEPTH
    // Test the near side expanded half a slice towards the camera. If that point
    // is still behind the farthest scene depth in the expanded XY footprint,
    // the whole froxel is guaranteed occluded.
    vec3 conservativeWorldPos = FroxelConservativeWorldPosition(froxel);
    vec4 conservativeClip = mul(vec4(conservativeWorldPos, 1.0), u_FroxelViewProj);
    float cellDeviceDepth = FroxelClipToDeviceDepth(conservativeClip);
    float sceneDeviceDepth = texelFetch(u_FroxelConservativeDepth5, ivec2(froxel.xy), 0).r;
    if (FroxelIsBehindConservativeDepth(cellDeviceDepth, sceneDeviceDepth))
    {
        imageStore(u_FroxelLightScattering1, ivec3(froxel), vec4(0.0, 0.0, 0.0, 0.0));
        return;
    }
#endif

    vec4 media = texelFetch(u_FroxelVBufferA0, ivec3(froxel), 0);
    vec4 mediaB = texelFetch(u_FroxelVBufferB4, ivec3(froxel), 0);
    // 逐 froxel 加权 phase g（media pass 混合了全局与各雾体的 g），emissive 为恒定 in-scatter
    float phaseG = mediaB.a;

    vec3 radiance = FroxelComputeRadiance(froxel, u_FroxelJitters[0].xyz, phaseG);
    vec4 result = vec4(media.rgb * radiance + mediaB.rgb, media.a);

    // temporal：froxel 中心（不带抖动）重投影到上帧网格采样 history（UE 同款：
    // ComputeCellTranslatedWorldPosition(GridCoordinate, .5f) + ComputeHistoryVolumeUV——
    // slice 查找用上帧 clip.w = 上帧 view-Z）——抖动只影响光照采样位置，
    // history 读取位置固定，EMA 在原位累积成超采样
    float historyWeight = u_FroxelTemporal.x;
    bool historyHit = false;
    if (historyWeight > 0.0)
    {
        vec3 centerRay = FroxelRayDir(froxel, vec2(0.5, 0.5));
        float centerDepth = FroxelSliceToDepth(float(froxel.z) + 0.5);
        vec3 centerPos = u_FroxelCamPos.xyz +
                         centerRay * (centerDepth / max(dot(centerRay, u_FroxelCamForward.xyz), 0.0001));
        vec4 prevClip = mul(vec4(centerPos, 1.0), u_FroxelPrevViewProj);
        if (prevClip.w > 0.0001)
        {
            vec2 prevNdc = prevClip.xy / prevClip.w;
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
            vec2 prevUv = vec2(prevNdc.x * 0.5 + 0.5, prevNdc.y * 0.5 + 0.5);
#else
            vec2 prevUv = vec2(prevNdc.x * 0.5 + 0.5, 0.5 - prevNdc.y * 0.5);
#endif
            // 上帧 view-Z 即 clip.w（UE ComputeHistoryVolumeUVFromNDC 用 NDCPosition.w 同款；
            // 透视投影下可见点 w 恒正——RH 约定由投影矩阵翻转符号，与 UE 同假设。
            // 正交相机不在 froxel 管线支持范围内：FroxelRayDir 的反投影即假设透视）
            float prevDepth = prevClip.w;
            // 连续 slice 坐标 s -> 纹理 w = s/gridZ（texel k 中心 = (k+0.5)/gridZ 对应 s=k+0.5）。
            // log2 参数钳正：startDistance 较大时 O 为负，比雾起点更近的重投影点参数非正 →
            // NaN（依赖编译器 NaN 比较行为不可靠，口径同 C++ DepthToSlice）
            float prevSlice = log2(max(prevDepth * u_FroxelGridZParams.x + u_FroxelGridZParams.y, 1e-8)) * u_FroxelGridZParams.z;
            float prevW = prevSlice / u_FroxelGridSize.z;
            bool historyValid = prevUv.x >= 0.0 && prevUv.x <= 1.0 && prevUv.y >= 0.0 && prevUv.y <= 1.0 &&
                                prevW >= 0.0 && prevW <= 1.0;
#ifdef CONSERVATIVE_DEPTH
            if (historyValid)
            {
                vec4 prevConservativeClip = mul(vec4(conservativeWorldPos, 1.0), u_FroxelPrevViewProj);
                historyValid = prevConservativeClip.w > 0.0001 &&
                               FroxelFixupHistoryUV(prevUv, FroxelClipToDeviceDepth(prevConservativeClip));
            }
#endif
            if (historyValid)
            {
                vec4 history = texture3DLod(u_FroxelHistory3, vec3(prevUv, prevW), 0.0);
                result = mix(result, history, historyWeight);
                historyHit = true;
            }
        }
    }

    // history miss 超采样（UE HistoryMissSupersampleCount=4 同款）：首帧 / 重投影出界的
    // froxel 本帧内再取 3 个不同抖动的样本平均，掩盖时域收敛空洞（新露出区域即刻可用）。
    // 用户关闭时域（u_FroxelTemporal.y=0）时不超采样——此时抖动=体素中心，1× 确定性采样（UE 同款）
    if (u_FroxelTemporal.y > 0.5 && !historyHit)
    {
        radiance += FroxelComputeRadiance(froxel, u_FroxelJitters[1].xyz, phaseG);
        radiance += FroxelComputeRadiance(froxel, u_FroxelJitters[2].xyz, phaseG);
        radiance += FroxelComputeRadiance(froxel, u_FroxelJitters[3].xyz, phaseG);
        result = vec4(media.rgb * (radiance * 0.25) + mediaB.rgb, media.a);
    }

    imageStore(u_FroxelLightScattering1, ivec3(froxel), result);
}
#endif
#endif
