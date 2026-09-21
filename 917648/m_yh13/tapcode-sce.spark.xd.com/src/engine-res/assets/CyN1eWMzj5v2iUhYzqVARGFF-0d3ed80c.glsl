#include "varying_cluster.def.sc"
#include "Common/bgfx_compute.sh"

// GLSL ES 3.1 只允许 r32f / r32i / r32ui 格式的 image 同时可读写，rgba8 必须声明 readonly
// 或 writeonly，所以这里按槽位拆成 RO / WR 而不用 RW。槽位角色是固定的：0 号恒为读源、
// 1 号恒为写目标（见 PostProcess/ComputeBlur.xml 的 unit 0 / unit 1），ComputeBlur 绑定时
// 的 IMAGE_READ / IMAGE_WRITE 与此一一对应。
#ifdef FIRST_PASS
SAMPLER2D(u_DiffMap, 0);
IMAGE2D_WR(u_ComputeBlur0, rgba8, 1);
#else
IMAGE2D_RO(u_ComputeBlur0, rgba8, 0);
IMAGE2D_WR(u_ComputeBlur1, rgba8, 1);
#endif

uniform hvec4 u_BlurParams;
uniform hvec4 u_TexSize;
#define cKernelHalf u_BlurParams.x
//kernel size = halfSize * 2 + 1

NUM_THREADS(64, 1, 1)
void main()
{
    // 像素坐标与循环边界统一用 int：GLSL ES 不在 int / uint / float 之间做隐式转换，混用
    // 编不过；HLSL 会隐式转并在构造 ivec2 时截断，所以两边取的是同一批整数坐标。
    int lineIndex = int(gl_GlobalInvocationID.x);
    ivec2 dim = ivec2(u_TexSize.xy);
    int kernelHalf = int(cKernelHalf);
    float scale = 1.0 / (2.0 * cKernelHalf + 1.0);

#ifdef BLUR_VERTICAL
    if (dim.x < lineIndex + 1)
        return;
    hvec3 colorSum = imageLoad(u_ComputeBlur0, ivec2(lineIndex, 0)).rgb * float(kernelHalf + 1);
    for (int y = 1; y <= kernelHalf; ++y )
    {
        colorSum += imageLoad(u_ComputeBlur0, ivec2(lineIndex, y)).rgb;
    }
    for (int y = 0; y < dim.y; ++y)
    {
        imageStore(u_ComputeBlur1, ivec2(lineIndex, y), vec4(colorSum * scale, 1.0));

        hvec3 left = imageLoad(u_ComputeBlur0, ivec2(lineIndex, max(y - kernelHalf, 0))).rgb;
        hvec3 right = imageLoad(u_ComputeBlur0, ivec2(lineIndex, min(y + kernelHalf + 1, dim.y - 1))).rgb;
        colorSum = colorSum - left + right;
    }
#else // HORIZONTAL
    if (dim.y < lineIndex + 1)
        return;
#ifdef FIRST_PASS
    // 构造要用 hvec2_init：GL 族里 hvec2 展开成 highp vec2，只能作类型名，不能当构造函数。
    hvec2 uv = hvec2_init(0.0, float(lineIndex)) / vec2(dim);
    hvec3 colorSum = texture2DLod(u_DiffMap, uv, 0.0).rgb * float(kernelHalf + 1);
#else
    hvec3 colorSum = imageLoad(u_ComputeBlur0, ivec2(0, lineIndex)).rgb * float(kernelHalf + 1);
#endif
    for (int x = 1; x <= kernelHalf; ++x )
    {
#ifdef FIRST_PASS
        uv = hvec2_init(float(x), float(lineIndex)) / vec2(dim);
        colorSum += texture2DLod(u_DiffMap, uv, 0.0).rgb;
#else
        colorSum += imageLoad(u_ComputeBlur0, ivec2(x, lineIndex)).rgb;
#endif
    }
    for (int x = 0; x < dim.x; ++x)
    {
#ifdef FIRST_PASS
        imageStore(u_ComputeBlur0, ivec2(x, lineIndex), vec4(colorSum * scale, 1.0));
#else
        imageStore(u_ComputeBlur1, ivec2(x, lineIndex), vec4(colorSum * scale, 1.0));
#endif

#ifdef FIRST_PASS
        uv = hvec2_init(float(max(x - kernelHalf - 1, 0)), float(lineIndex)) / vec2(dim);
        hvec3 left = texture2DLod(u_DiffMap, uv, 0.0).rgb;
        uv = hvec2_init(float(min(x + kernelHalf, dim.x - 1)), float(lineIndex)) / vec2(dim);
        hvec3 right = texture2DLod(u_DiffMap, uv, 0.0).rgb;
#else
        hvec3 left = imageLoad(u_ComputeBlur0, ivec2(max(x - kernelHalf, 0), lineIndex)).rgb;
        hvec3 right = imageLoad(u_ComputeBlur0, ivec2(min(x + kernelHalf + 1, dim.x - 1), lineIndex)).rgb;
#endif
        colorSum = colorSum - left + right;
    }
#endif
}
