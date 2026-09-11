/*
 * Motion Blur Velocity Flatten (UE MotionBlurVelocityFlatten.usf 移植，quad 化)
 *
 * 全分辨率：MV(UV-delta) + depth → (速度像素长, 角度[0,1], 线性视深) RGBA16F。
 * 我们的 MV 已是全量总运动（相机 quad + object velocity 覆盖写），
 * UE 的"静态像素用 ClipToPrevClip 重建相机运动"分支整体不需要。
 * 蓝图与易错点：docs/plans/motion-blur-ue5.md §2
 */

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

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

#define MB_PI 3.14159265

// Reverse-Z 双路支持（HiZInit.glsl 同款模式）：标准 Z 0=近，reversed 1=近。
// 线性化统一走 ReconstructDepth（cDepthReconstruct 按相机 UseReverseZ 双路填参），
// 不用 LinearizeDepth（硬编码标准 Z 公式）
#ifdef REVERSED_Z
    #define MB_NEARER(a, b) ((a) > (b))
    #define MB_NEAREST(a, b) max(a, b)
#else
    #define MB_NEARER(a, b) ((a) < (b))
    #define MB_NEAREST(a, b) min(a, b)
#endif

SAMPLER2D(u_MotionVector0, 0);
SAMPLER2D(u_Depth1, 1);

// xy = UV-delta → 像素的缩放（含 W/H × Amount × 0.5 × TimeScale，View 下发）
// z  = 速度像素长度上限（含 gather ±3 tile 的 96px 硬 clamp）
uniform hvec4 u_MBVelocityParams;

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 texel = cGBufferInvSize.xy;

    // 最近深度偏移（UE usf:99-134，前景轮廓质量关键）：3×3 四对角取最近深度
    // 像素的 MV/depth。比较方向经 MB_NEARER/MB_NEAREST 兼容标准/Reverse-Z
    hfloat dC = texture2D(u_Depth1, uv).r;
    hfloat d0 = texture2D(u_Depth1, uv + hvec2_init(-texel.x, -texel.y)).r;
    hfloat d1 = texture2D(u_Depth1, uv + hvec2_init( texel.x, -texel.y)).r;
    hfloat d2 = texture2D(u_Depth1, uv + hvec2_init(-texel.x,  texel.y)).r;
    hfloat d3 = texture2D(u_Depth1, uv + hvec2_init( texel.x,  texel.y)).r;

    hvec2 offs = texel;
    hfloat offsXx = texel.x;
    if (MB_NEARER(d0, d1)) { offsXx = -texel.x; }
    if (MB_NEARER(d2, d3)) { offs.x = -texel.x; }
    hfloat d01 = MB_NEAREST(d0, d1);
    hfloat d23 = MB_NEAREST(d2, d3);
    if (MB_NEARER(d01, d23)) { offs.y = -texel.y; offs.x = offsXx; }

    hvec2 sampleUV = MB_NEARER(MB_NEAREST(d01, d23), dC) ? uv + offs : uv;

    hvec2 mv = texture2D(u_MotionVector0, sampleUV).rg;
    hfloat depth = texture2D(u_Depth1, sampleUV).r;

    // UV-delta → 像素，clamp 长度上限
    hvec2 velPx = mv * u_MBVelocityParams.xy;
    hfloat len = length(velPx);
    // NaN 双保险（UE 历史踩过驱动坑）
    hfloat angle = len > 0.0 ? atan2(velPx.y, velPx.x) : 0.0;
    if (angle != angle) angle = 0.0;
    len = min(len, u_MBVelocityParams.z);

    // 编码：(像素长, 角度→[0,1], 线性视深[米])。ReconstructDepth 返回 z_eye/far，
    // 标准 Z 下与 LinearizeDepth 数值恒等，Reverse-Z 下经 cDepthReconstruct 自动正确
    hfloat linearZ = ReconstructDepth(depth) * cFarClipPS;
    gl_FragColor = hvec4_init(len, angle * (0.5 / MB_PI) + 0.5, linearZ, 1.0);
}

#endif
