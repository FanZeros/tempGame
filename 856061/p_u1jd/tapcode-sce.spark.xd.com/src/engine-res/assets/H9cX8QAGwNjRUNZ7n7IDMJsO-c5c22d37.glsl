/*
 * GTAO Temporal Filter
 *
 * Accumulates AO across frames using motion vector reprojection.
 * Neighborhood min/max clamp prevents ghosting on moving objects.
 *
 * Simpler than SSR temporal: single-channel LDR, no HDR weighting,
 * no YCoCg transform, no Blackman-Harris kernel.
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

// Current AO (half-res, after spatial denoise, point sampled)
SAMPLER2D(u_CurrentAO0, 0);

// History AO (half-res, previous frame, bilinear for sub-pixel reprojection)
SAMPLER2D(u_HistoryAO1, 1);

// Motion vectors (full-res, bilinear interpolated)
SAMPLER2D(u_MotionVector2, 2);

// Depth buffer (full-res, for camera-only MV reconstruction)
SAMPLER2D(u_Depth3, 3);

// x = temporal blend factor (default 0.1: 10% current, 90% history)
uniform hvec4 u_TemporalParams;

// Camera-only reprojection matrices, same source/convention as MotionVector.glsl
// (set by View::ApplyMotionVectorParameters execution on the renderpath command).
uniform hmat4 u_InvViewProj;
uniform hmat4 u_PrevViewProj;

// 当前像素表面点若静止，它在上一帧相机下的期望线性视深（= prevClip.w，世界单位）。
// 与 MotionVector.glsl 同源的重投影数学；用于相机运动补偿的深度 disocclusion 判据。
hfloat ComputeExpectedPrevViewZ(hvec2 uv, hfloat depth)
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
    worldPos /= worldPos.w;
    hvec4 prevClipPos = mul(worldPos, u_PrevViewProj);
    return prevClipPos.w;
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 texel = cGBufferInvSize.xy;

    // Current AO
    hfloat currentAO = texture2D(u_CurrentAO0, uv).r;

    // Motion vector (half-res UV on full-res MV, bilinear gives smooth interpolation)
    hvec2 motion = texture2D(u_MotionVector2, uv).rg;

    // 当前帧线性视深（写入 G 通道，供下一帧做深度 disocclusion 判据）。
    // 物体贴地的接触 AO 与拖影值域重叠，颜色域 clamp 探测不到拖影，必须用几何信息拒绝。
    // 用深度而不用速度标记：速度模长对"静止后离开"的物体失明（角色停留时 velMark=0
    // 被一并写进历史，走开后差分恒 0），而深度换主（角色身体 → 地板）尺度无关、
    // 快慢无关，小体型/慢速角色（如 0.3x 缩放）同样能一帧识别。
    hfloat depth = texture2D(u_Depth3, uv).r;
    // ReconstructDepth 兼容标准/Reverse-Z（cDepthReconstruct 按相机双路填参），
    // 标准 Z 下与 LinearizeDepth 数值恒等
    hfloat currentViewZ = ReconstructDepth(depth) * cFarClipPS;

    // Reproject to previous frame
    hvec2 historyUV = uv - motion;

    // Out of screen: no history available
    if (any(lessThan(historyUV, vec2_splat(0.0))) ||
        any(greaterThan(historyUV, vec2_splat(1.0))))
    {
        gl_FragColor = hvec4_init(currentAO, currentViewZ, 0.0, 1.0);
        return;
    }

    // History AO (bilinear for sub-pixel reprojection accuracy); G = 历史内容的线性视深
    hvec2 historySample = texture2D(u_HistoryAO1, historyUV).rg;
    hfloat historyAO = historySample.r;
    hfloat historyViewZ = historySample.g;

    // Neighborhood min/max clamp (plus pattern: center + 4 cardinal)
    hfloat n0 = texture2D(u_CurrentAO0, uv + hvec2_init(-texel.x, 0.0)).r;
    hfloat n1 = texture2D(u_CurrentAO0, uv + hvec2_init( texel.x, 0.0)).r;
    hfloat n2 = texture2D(u_CurrentAO0, uv + hvec2_init(0.0, -texel.y)).r;
    hfloat n3 = texture2D(u_CurrentAO0, uv + hvec2_init(0.0,  texel.y)).r;

    hfloat nmin = min(currentAO, min(min(n0, n1), min(n2, n3)));
    hfloat nmax = max(currentAO, max(max(n0, n1), max(n2, n3)));

    // Clamp history to neighborhood bounds (prevents ghosting)
    hfloat rawHistoryAO = historyAO;
    historyAO = clamp(historyAO, nmin, nmax);

    // History-clip rejection: how far the history was pulled back into the neighborhood
    // bounds measures how stale it is (e.g. a character just moved off this pixel and the
    // history still holds its contact AO). Static scenes and pure camera motion keep the
    // history inside the bounds, so this stays 0 and accumulation is unaffected.
    hfloat clipAmount = abs(rawHistoryAO - historyAO);

    // UE 式速度收窄 clamp 窗口（PostProcessAmbientOcclusion.usf:1292）：以当前 AO 为中心的
    // 标量窗口，速度越大越窄，≥0.01 UV/帧完全拒绝历史。用总速度模长，对相机运动同样生效，
    // 是 SHIFT 高速平移的兜底——velReject 的速度差分在那种场景下两边饱和、信号归零。
    hfloat rangeVal = mix(0.1, 0.0, saturate(length(motion) * 100.0));
    historyAO = clamp(historyAO, currentAO - rangeVal, currentAO + rangeVal);

    // 深度 disocclusion（Lumen 表面路径同款，相对阈值 3%，相机运动已被重投影精确补偿）：
    // 历史内容的视深 ≠ 当前表面点在上一帧的期望视深 = 内容已换主（如角色身体占过的
    // 像素，历史深度是角色、期望深度是地板）→ 一帧重置。静止后走开的物体同样命中。
    // 代价：快速接近/远离相机的物体表面会自我拒绝（AO 退化为单帧+空间滤波），可接受。
    hfloat expectedPrevViewZ = ComputeExpectedPrevViewZ(uv, depth);
    hfloat depthReject = abs(historyViewZ - expectedPrevViewZ) > 0.03 * max(expectedPrevViewZ, 0.5)
        ? 1.0 : 0.0;

    // Blend: raise current-frame weight proportionally to the clip amount
    hfloat blendFactor = saturate(u_TemporalParams.x + clipAmount * 8.0 + depthReject);
    hfloat result = mix(historyAO, currentAO, blendFactor);

    gl_FragColor = hvec4_init(result, currentViewZ, 0.0, 1.0);
}

#endif
