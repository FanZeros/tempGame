// Froxel final integration: 沿 Z 累积 LightScattering，输出每 slice 的
// (accumulated scattering.rgb + transmittance.a)，供 composite 按 scene depth 采样。
// 对应 UE5 VolumetricFog.usf 的 FinalIntegrationCS：
//   - 能量守恒切片积分（Frostbite "Physically Based and Unified Volumetric Rendering"，
//     UE ENERGY_CONSERVING_INTEGRATION=1 分支）：每切片解析积出
//     ∫ S·T(t) dt = S·(1 - e^(-σ·len))/σ，而非左端点矩形近似 S·T·len——
//     厚切片/高消光下矩形近似会系统性高估亮度且透射率不闭合
//   - 切片按 view-Z 分布（UE ComputeDepthFromZSlice 同口径），步长取该像素
//     视线穿过切片的斜向长度 = Δdepth × |ray/dot(ray,forward)|（UE 逐层
//     ComputeCellTranslatedWorldPosition 差分同义）
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"
#include "Common/bgfx_compute.sh"

// 只读走 SAMPLER3D + texelFetch（GL 后端 compute 的 IMAGE3D_RO 读 3D 纹理返回零）
SAMPLER3D(u_FroxelLightScattering0, 0);
IMAGE3D_WR(u_FroxelIntegrated1, rgba16f, 1);

uniform vec4 u_FroxelGridSize;      // xyz = froxel grid dims
uniform vec4 u_FroxelGridZParams;   // B, O, S: slice = log2(viewZ * B + O) * S
uniform vec4 u_FroxelCamPos;        // xyz = camera world position
uniform vec4 u_FroxelCamForward;    // xyz = camera world forward (normalized)
uniform mat4 u_FroxelInvViewProj;

float FroxelSliceToDepth(float slice)
{
    return (exp2(slice / u_FroxelGridZParams.z) - u_FroxelGridZParams.y) / u_FroxelGridZParams.x;
}

NUM_THREADS(8, 8, 1)
void main()
{
    uvec2 texel = gl_GlobalInvocationID.xy;
    uvec3 gridSize = uvec3(u_FroxelGridSize.xyz);
    if (texel.x >= gridSize.x || texel.y >= gridSize.y)
        return;

    // 该像素列的视线：Δdepth → 世界空间斜向长度的换算系数 |ray / dot(ray, forward)|
    vec2 uv = (vec2(texel) + vec2(0.5, 0.5)) / vec2(gridSize.xy);
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    vec2 ndc = vec2(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0);
#else
    vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
#endif
    vec4 rayPoint = mul(vec4(ndc, 0.0, 1.0), u_FroxelInvViewProj);
    rayPoint.xyz /= rayPoint.w;
    vec3 ray = rayPoint.xyz - u_FroxelCamPos.xyz;
    float rayScale = length(ray) / max(dot(ray, u_FroxelCamForward.xyz), 0.0001);

    vec3 accum = vec3(0.0, 0.0, 0.0);
    float transmittance = 1.0;
    float d0 = FroxelSliceToDepth(0.0);

    for (uint z = 0u; z < gridSize.z; ++z)
    {
        float d1 = FroxelSliceToDepth(float(z) + 1.0);
        float len = max(d1 - d0, 0.0) * rayScale;

        vec4 s = texelFetch(u_FroxelLightScattering0, ivec3(texel, z), 0);

        // 能量守恒切片积分（UE / Frostbite 同式）：
        //   sliceT = e^(-σ·len)；∫slice S·T dt = S·(1 - sliceT)/σ
        // 分母钳位是 UE FinalIntegrationCS 原式（max(w, .00001f)）。注意钳位副作用：
        // σ ≥ 1e-5 时公式随 σ 减小光滑趋近解析极限 S·len；σ < 1e-5 后分子继续变小而
        // 分母被钳住，切片贡献按 σ/1e-5 线性衰减到 0（非收敛到 S·len）。这是 UE 原生
        // 行为：默认分支（r.SupportExpFogMatchesVolumetricFog=0）下全局雾 emissive 同样
        // 裸值注入、同样被此钳位压黑，无需特例。UE 唯一无条件乘密度的是 LFV emissive
        //（MaterialSetupCS 乘 LFVExtinction），该偏差记在 MediaCS 注入侧的技术债条目里
        float extinction = max(s.a, 0.0);
        float sliceTransmittance = exp(-extinction * len);
        vec3 scatteringIntegrated = s.rgb * (1.0 - sliceTransmittance) / max(extinction, 0.00001);

        accum += scatteringIntegrated * transmittance;
        transmittance *= sliceTransmittance;

        imageStore(u_FroxelIntegrated1, ivec3(texel, z), vec4(accum, transmittance));
        d0 = d1;
    }
}
#endif
#endif
