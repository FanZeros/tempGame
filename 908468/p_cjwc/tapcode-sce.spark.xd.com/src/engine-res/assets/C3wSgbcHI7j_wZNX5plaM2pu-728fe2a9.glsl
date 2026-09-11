// Froxel media setup: 把 Zone 的指数高度介质写入 VBufferA (scattering.rgb + extinction.a)。
// 对应 UE5 VolumetricFog.usf 的 MaterialSetupCS 阶段。
//
// 深度切片按 view-Z 线性深度分布（UE ComputeDepthFromZSlice / ComputeCellTranslatedWorldPosition
// 同口径）：slice -> viewZ 映射与 C++ VolumetricFogGrid::SliceToDepth 相同，世界位置沿视线
// 推进到该 view-Z 平面（Δdepth × |ray|/dot(ray, forward)）。
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"
#include "Common/bgfx_compute.sh"

IMAGE3D_WR(u_FroxelVBufferA0, rgba16f, 0);
IMAGE3D_WR(u_FroxelVBufferB1, rgba16f, 1);

uniform vec4 u_FroxelGridSize;         // xyz = froxel grid dims
uniform vec4 u_FroxelGridZParams;      // B, O, S: slice = log2(viewZ * B + O) * S
uniform vec4 u_FroxelCamPos;           // xyz = camera world position
uniform vec4 u_FroxelCamForward;       // xyz = camera world forward (normalized)
uniform mat4 u_FroxelInvViewProj;
uniform vec4 u_FroxelFogParams;        // density, world fog height, height falloff, local fog volume count
uniform vec4 u_FroxelScatteringColor;  // rgb, w = global phase g
uniform vec4 u_FroxelAbsorption;       // rgb, intensity
uniform vec4 u_FroxelEmissiveColor;    // rgb = global media emissive
// 每体 6 个 vec4：worldToLocal 行 0/1/2（显式点积变换，规避矩阵约定）、
// albedo.rgb + radialExtinction、[radialFalloff, heightFalloff, heightExtinction, phaseG]、emissive.rgb
#define MaxFroxelFogVolumes 16
uniform vec4 u_FroxelFogVolumes[96];

float FroxelSliceToDepth(float slice)
{
    return (exp2(slice / u_FroxelGridZParams.z) - u_FroxelGridZParams.y) / u_FroxelGridZParams.x;
}

NUM_THREADS(4, 4, 4)
void main()
{
    uvec3 froxel = gl_GlobalInvocationID.xyz;
    uvec3 gridSize = uvec3(u_FroxelGridSize.xyz);
    if (froxel.x >= gridSize.x || froxel.y >= gridSize.y || froxel.z >= gridSize.z)
        return;

    // froxel 中心像素 -> NDC -> 反投影取视线方向。NDC z 取 0 落在视锥内部，
    // 对 D3D [0,1] 和 GL [-1,1] 两种深度约定都有效，方向与具体深度值无关。
    vec2 uv = (vec2(froxel.xy) + vec2(0.5, 0.5)) / vec2(gridSize.xy);
// NDC y 约定：GLSL 后端不翻转（同 ReconstructWorldPosition 的分支）
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    vec2 ndc = vec2(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0);
#else
    vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
#endif
    vec4 rayPoint = mul(vec4(ndc, 0.0, 1.0), u_FroxelInvViewProj);
    rayPoint.xyz /= rayPoint.w;
    vec3 rayDir = normalize(rayPoint.xyz - u_FroxelCamPos.xyz);

    // view-Z -> 沿视线的世界距离（UE ComputeCellTranslatedWorldPosition 的
    // clip 反投影同义：固定 NDC.xy 下 world 点落在 viewZ 平面上）
    float depth = FroxelSliceToDepth(float(froxel.z) + 0.5);
    float dist = depth / max(dot(rayDir, u_FroxelCamForward.xyz), 0.0001);
    vec3 worldPos = u_FroxelCamPos.xyz + rayDir * dist;

    // 指数高度介质，与 Volumetric/VolumetricFog.glsl 的 VolumetricHeightDensity 保持一致；
    // exp2 底与 UE MaterialSetupCS 同款（UE 场景 HeightFalloff 面板值换算 = ÷10，无 ln2 因子）
    float heightTerm = (u_FroxelFogParams.y - worldPos.y) * u_FroxelFogParams.z;
    float density = u_FroxelFogParams.x * exp2(clamp(heightTerm, -20.0, 20.0));

    vec3 scattering = u_FroxelScatteringColor.rgb * density;
    vec3 absorption = u_FroxelAbsorption.rgb * u_FroxelAbsorption.w;
    float extinction = density * (1.0 + (absorption.r + absorption.g + absorption.b) / 3.0);

    // 逐 froxel 加权 phase g（VBufferB.a）：按标量密度贡献加权混合全局与各雾体的 g
    float globalG = u_FroxelScatteringColor.w;
    float gWeightSum = globalG * density;
    float densitySum = density;
    vec3 emissive = u_FroxelEmissiveColor.rgb;

    // LocalFogVolume 注入：node 空间单位球，径向分量 + 高度分量（自球底衰减），共用径向软边
    int volumeCount = int(u_FroxelFogParams.w);
    vec4 p4 = vec4(worldPos, 1.0);
    for (int i = 0; i < MaxFroxelFogVolumes; ++i)
    {
        if (i >= volumeCount)
            break;

        vec3 localPos = vec3(dot(u_FroxelFogVolumes[i * 6 + 0], p4), dot(u_FroxelFogVolumes[i * 6 + 1], p4),
                             dot(u_FroxelFogVolumes[i * 6 + 2], p4));
        float r = length(localPos);
        if (r >= 1.0)
            continue;

        vec4 albedoExt = u_FroxelFogVolumes[i * 6 + 3];
        vec4 falloffs = u_FroxelFogVolumes[i * 6 + 4];
        vec4 volEmissive = u_FroxelFogVolumes[i * 6 + 5];

        float shape = pow(1.0 - r, falloffs.x);
        float h01 = clamp((localPos.y + 1.0) * 0.5, 0.0, 1.0);
        float d = shape * (albedoExt.w + falloffs.z * exp2(clamp(-falloffs.y * h01, -20.0, 0.0)));

        scattering += albedoExt.rgb * d;
        extinction += d;
        gWeightSum += falloffs.w * d;
        densitySum += d;
        emissive += volEmissive.rgb * shape;
    }

    float phaseG = densitySum > 0.00001 ? gWeightSum / densitySum : globalG;

    imageStore(u_FroxelVBufferA0, ivec3(froxel), vec4(scattering, extinction));
    imageStore(u_FroxelVBufferB1, ivec3(froxel), vec4(emissive, phaseG));
}
#endif
#endif
