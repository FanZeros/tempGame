/*
 * TAA (Temporal Anti-Aliasing) Resolve — UE4 MainTemporalAAPS faithful port
 *
 * UE4 PostProcessTemporalCommon.usf configuration (AA_YCOCG=1 path):
 *   AA_FILTERED=1  — Blackman-Harris weighted plus-pattern spatial filter
 *   AA_YCOCG=1     — Work in YCoCg color space
 *   AA_BICUBIC=1   — Catmull-Rom bicubic history sampling (sharpness source)
 *   AA_TONE=1      — HDR perceptual weighting: 1/(Y+1) on YCoCg luminance
 *   AA_AABB=1      — But in AA_YCOCG path: simple component-wise clamp
 *   AA_CROSS=2     — X-pattern motion dilation at 2px
 *   AA_LOWPASS=0   — No wide lowpass (main TAA, not SSR temporal)
 *   AA_ALPHA=0     — Alpha not AA'd
 *   Blend=0.04     — Fixed 4% new frame (when AA_TONE=1)
 *
 * Pipeline position: after all scene rendering (HDR), before Bloom and Tonemapping.
 *
 * Sharpness comes from Catmull-Rom bicubic negative lobes in history sampling,
 * NOT from any explicit sharpening step.
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

// Current frame scene color - HDR, jittered (register 0)
SAMPLER2D(u_SceneColor0, 0);
// TAA history - previous frame's resolved output, bilinear filtered (register 1)
SAMPLER2D(u_TAAHistory1, 1);
// Motion vector buffer (register 2)
SAMPLER2D(u_MotionVector2, 2);
// Depth buffer (register 3)
SAMPLER2D(u_Depth3, 3);

// Render path parameters
uniform hfloat u_TAABlendFactor;

// TAA jitter offset in pixel space (+-0.5 pixels), set by C++ View per frame
uniform hvec2 u_JitterOffset;

// Camera-only reprojection matrices, same source/convention as MotionVector.glsl
// (set by View::ApplyTAAResolveParameters). Used to synthesize the dynamic-object marker.
uniform hmat4 u_InvViewProj;
uniform hmat4 u_PrevViewProj;

// Reverse-Z 双路支持（HiZInit.glsl 同款模式）：标准 Z 0=近/1=天空，reversed 相反。
// ComputeCameraMV 的矩阵往返无需分支——InvViewProj/PrevViewProj 来自 GetGPUProjection，
// Reverse-Z 重映射已烘进矩阵及其逆
#ifdef REVERSED_Z
    #define DEPTH_NEARER(a, b) ((a) > (b))
    #define IS_SKY_DEPTH(d) ((d) < 0.00001)
#else
    #define DEPTH_NEARER(a, b) ((a) < (b))
    #define IS_SKY_DEPTH(d) ((d) > 0.99999)
#endif

// ============================================================
// YCoCg color space (UE4 AA_YCOCG=1)
// ============================================================
hvec3 RGBToYCoCg(hvec3 c)
{
    return hvec3_init(
         c.r * 0.25 + c.g * 0.5 + c.b * 0.25,
         c.r * 0.5  - c.b * 0.5,
        -c.r * 0.25 + c.g * 0.5 - c.b * 0.25
    );
}

hvec3 YCoCgToRGB(hvec3 c)
{
    hfloat tmp = c.x - c.z;
    return hvec3_init(tmp + c.y, c.x + c.z, tmp - c.y);
}

// ============================================================
// UE4 HDR perceptual weighting (AA_TONE=1, AA_YCOCG=1)
// ============================================================
// HdrWeightY: weight by YCoCg luminance (Y channel)
// With Exposure = 1.0: weight = 1 / (Y + 1)
// Suppresses bright specular highlights during blending.
hfloat HdrWeightY(hfloat y)
{
    return 1.0 / (y + 1.0);
}

// ============================================================
// UE4 Blackman-Harris kernel (PostProcessTemporalAA.cpp)
// ============================================================
// Exponential approximation to Blackman-Harris 3.3 window:
//   weight = exp(-2.29 * ||(offset - jitter) * scale||^2)
// Default Sharpness = 0 -> scale = 1.0 + 0 * 0.5 = 1.0
hfloat BhWeight(hvec2 sampleOffset, hvec2 jitter, hfloat scale)
{
    hvec2 d = (sampleOffset - jitter) * scale;
    return exp(-2.29 * dot(d, d));
}

// ============================================================
// Bicubic Catmull-Rom history sampling (UE4 AA_BICUBIC=1)
// ============================================================
// Catmull-Rom cubic filter has negative lobes in the [1,2] range,
// which subtract neighboring pixels and create a mild high-pass boost.
// This is the PRIMARY source of UE4 TAA sharpness.
//
// 5-tap optimized: collapses 4x4 separable kernel into 5 bilinear taps
// by grouping center w1+w2 pairs. Corner terms (~1.6% weight) dropped.
hvec3 SampleHistoryBicubic(hvec2 uv, hvec2 texSize, hvec2 invTexSize)
{
    hvec2 coord = uv * texSize - 0.5;
    hvec2 f = fract(coord);
    coord = coord - f;

    // Catmull-Rom weights (alpha = -0.5)
    // w0 = -0.5*t^3 + t^2 - 0.5*t
    // w1 = 1.5*t^3 - 2.5*t^2 + 1
    // w2 = -1.5*t^3 + 2*t^2 + 0.5*t
    // w3 = 0.5*t^3 - 0.5*t^2
    hvec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    hvec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    hvec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    hvec2 w3 = f * f * (-0.5 + 0.5 * f);

    // Bilinear optimization: combine center pair (w1 + w2)
    hvec2 s12 = w1 + w2;
    hvec2 f12 = w2 / s12;

    // Sample positions in UV space
    hvec2 tc0  = (coord - 0.5) * invTexSize;
    hvec2 tc12 = (coord + 0.5 + f12) * invTexSize;
    hvec2 tc3  = (coord + 2.5) * invTexSize;

    // 5-tap cross pattern
    hvec3 result =
        texture2D(u_TAAHistory1, hvec2_init(tc12.x, tc12.y)).rgb * (s12.x * s12.y) +
        texture2D(u_TAAHistory1, hvec2_init(tc0.x,  tc12.y)).rgb * (w0.x  * s12.y) +
        texture2D(u_TAAHistory1, hvec2_init(tc3.x,  tc12.y)).rgb * (w3.x  * s12.y) +
        texture2D(u_TAAHistory1, hvec2_init(tc12.x, tc0.y)).rgb  * (s12.x * w0.y)  +
        texture2D(u_TAAHistory1, hvec2_init(tc12.x, tc3.y)).rgb  * (s12.x * w3.y);

    // Normalize (compensate for dropped corner terms)
    hfloat totalW = s12.x * s12.y
                  + w0.x * s12.y + w3.x * s12.y
                  + s12.x * w0.y + s12.x * w3.y;
    return result / totalW;
}

// ============================================================
// Dynamic-object marker (UE AA_DYNAMIC_ANTIGHOST, TemporalAA.usf:2147)
// ============================================================
// UrhoX 的 MotionVector buffer 没有"是否动态物体"标记位（rg16f 只存总运动），
// 这里用与 MotionVector.glsl 完全相同的数学从 depth 重建纯相机 MV，与采样到的
// 总 MV 比对：差值超阈值 = 该像素被 object velocity pass 覆盖且物体确实在动。
// 静态像素两者同源（同 depth、同矩阵、同指令序），残差仅剩 rg16f 存储量化。
hvec2 ComputeCameraMV(hvec2 uv, hfloat depth)
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
    hvec2 prevUV = prevClipPos.xy / prevClipPos.w * 0.5 + 0.5;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    prevUV.y = 1.0 - prevUV.y;
#endif
    return uv - prevUV;
}

bool IsDynamicTap(hvec2 tapUV, hvec2 texelSize)
{
    hfloat depth = texture2D(u_Depth3, tapUV).r;
    // 天空：MotionVector pass 写 0 而相机重投影非零，直接判静态避免误标
    if (IS_SKY_DEPTH(depth))
        return false;
    hvec2 mv = texture2D(u_MotionVector2, tapUV).rg;
    hvec2 deltaPx = (mv - ComputeCameraMV(tapUV, depth)) / texelSize;
    // 阈值 0.25px：远高于 rg16f 量化噪声，低于任何有意义的物体屏幕运动
    return dot(deltaPx, deltaPx) > 0.0625;
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 texelSize = cGBufferInvSize;

    // ================================================================
    // Stage 1: X-pattern motion vector dilation (UE4 AA_CROSS=2)
    // ================================================================
    // 4 diagonal corners at 2px distance + center pixel.
    // Closest depth selects motion vector (DEPTH_NEARER 兼容标准/Reverse-Z).
    // UE4 uses this wider pattern because TAA dilates edges beyond geometry.
    hfloat closestDepth = texture2D(u_Depth3, uv).r;
    hvec2 closestOffset = hvec2_init(0.0, 0.0);

    hfloat d0 = texture2D(u_Depth3, uv + hvec2_init(-2.0, -2.0) * texelSize).r;
    hfloat d1 = texture2D(u_Depth3, uv + hvec2_init( 2.0, -2.0) * texelSize).r;
    hfloat d2 = texture2D(u_Depth3, uv + hvec2_init(-2.0,  2.0) * texelSize).r;
    hfloat d3 = texture2D(u_Depth3, uv + hvec2_init( 2.0,  2.0) * texelSize).r;

    if (DEPTH_NEARER(d0, closestDepth)) { closestDepth = d0; closestOffset = hvec2_init(-2.0, -2.0) * texelSize; }
    if (DEPTH_NEARER(d1, closestDepth)) { closestDepth = d1; closestOffset = hvec2_init( 2.0, -2.0) * texelSize; }
    if (DEPTH_NEARER(d2, closestDepth)) { closestDepth = d2; closestOffset = hvec2_init(-2.0,  2.0) * texelSize; }
    if (DEPTH_NEARER(d3, closestDepth)) { closestDepth = d3; closestOffset = hvec2_init( 2.0,  2.0) * texelSize; }

    hvec2 motionVec = texture2D(u_MotionVector2, uv + closestOffset).rg;
    hvec2 historyUV = uv - motionVec;
    bool historyValid = all(greaterThanEqual(historyUV, vec2_splat(0.0)))
                     && all(lessThanEqual(historyUV, vec2_splat(1.0)));

    // ================================================================
    // Stage 1.5: Dynamic anti-ghost (UE AA_DYNAMIC_ANTIGHOST)
    // ================================================================
    // 不对称判据：上一帧是动态（history.a>0）而本帧十字邻域全为静态 = 物体刚离开、
    // 背景 disocclude，历史残留物体颜色 → 整体丢弃历史（"静态→动态"方向不杀，
    // velocity 重投影本来就能对上）。当前帧 5-tap 十字取 OR：容忍边缘单像素判定
    // 抖动，保守方向 = 倾向保留历史。历史 alpha>0 且中心静态时才展开 4 个角 tap。
    bool centerDynamic = IsDynamicTap(uv, texelSize);
    if (historyValid && !centerDynamic)
    {
        hfloat historyDynamic = texture2D(u_TAAHistory1, historyUV).a;
        if (historyDynamic > 0.0)
        {
            bool anyDynamic =
                   IsDynamicTap(uv + hvec2_init( 0.0, -1.0) * texelSize, texelSize)
                || IsDynamicTap(uv + hvec2_init(-1.0,  0.0) * texelSize, texelSize)
                || IsDynamicTap(uv + hvec2_init( 1.0,  0.0) * texelSize, texelSize)
                || IsDynamicTap(uv + hvec2_init( 0.0,  1.0) * texelSize, texelSize);
            if (!anyDynamic)
                historyValid = false;   // UE: IgnoreHistory → history=filtered, blend=1
        }
    }

    // ================================================================
    // Stage 2: Sample plus-pattern neighborhood (UE4 AA_YCOCG path)
    // ================================================================
    // UE4 AA_YCOCG=1: only plus pattern (5 taps) for filter and bounds.
    hvec3 s_top    = max(texture2D(u_SceneColor0, uv + hvec2_init( 0.0, -1.0) * texelSize).rgb, vec3_splat(0.0));
    hvec3 s_left   = max(texture2D(u_SceneColor0, uv + hvec2_init(-1.0,  0.0) * texelSize).rgb, vec3_splat(0.0));
    hvec3 s_center = max(texture2D(u_SceneColor0, uv).rgb, vec3_splat(0.0));
    hvec3 s_right  = max(texture2D(u_SceneColor0, uv + hvec2_init( 1.0,  0.0) * texelSize).rgb, vec3_splat(0.0));
    hvec3 s_bottom = max(texture2D(u_SceneColor0, uv + hvec2_init( 0.0,  1.0) * texelSize).rgb, vec3_splat(0.0));

    // ================================================================
    // Stage 3: Convert to YCoCg（raw，不预乘 HDR 权重）
    // ================================================================
    // UE 结构（TemporalAA.usf:1621-1675, 2281-2291）：颜色全程 raw YCoCg，
    // HdrWeight 只出现在①滤波权重②最终 WeightedLerpFactors；无显式 tonemap 往返。
    // 此前把权重预乘进颜色再末端 Karis 逆变换是结构性偏差，已按 UE 重构。
    hvec3 n0 = RGBToYCoCg(s_top);
    hvec3 n1 = RGBToYCoCg(s_left);
    hvec3 n2 = RGBToYCoCg(s_center);
    hvec3 n3 = RGBToYCoCg(s_right);
    hvec3 n4 = RGBToYCoCg(s_bottom);

    // ================================================================
    // Stage 4: 空间滤波（AA_FILTERED=1, plus 5-tap）
    // ================================================================
    // 核 = 高斯 σ=0.47（exp(-2.29 d²)，UE TemporalAA.cpp:447——不是 Blackman-Harris，
    // UE 自己也没有 BH），按 jitter 重新居中；权重 = 空间 × HDR（UE usf:1621-1642），
    // Filtered = Σw·c / Σw（归一化加权平均，灭 firefly 的机制）。
    // u_JitterOffset 是投影矩阵抖动（NDC 空间，+y 向上）的像素值原样直传；
    // 重心化需要的是"画面内容在本 RT UV 空间里的位移"：GL 系（bottom-left 原点）
    // UV +v 与 NDC +y 同向，直用；D3D/Metal/Vulkan（top-left 原点）反向，Y 取负。
    // 漏掉这一步 = D3D 下滤波核每帧带最高 1px 垂直错位——静止时 4% 混合率看不出，
    // 运动中 blend 升至 0.2 即边缘爬锯齿（实测 DX 锯齿严重而 GL 正常的根因）。
    hvec2 jitter = u_JitterOffset;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    jitter.y = -jitter.y;
#endif
    hfloat bhScale = 1.0;

    hfloat pw0 = BhWeight(hvec2_init( 0.0, -1.0), jitter, bhScale) * HdrWeightY(n0.x);
    hfloat pw1 = BhWeight(hvec2_init(-1.0,  0.0), jitter, bhScale) * HdrWeightY(n1.x);
    hfloat pw2 = BhWeight(hvec2_init( 0.0,  0.0), jitter, bhScale) * HdrWeightY(n2.x);
    hfloat pw3 = BhWeight(hvec2_init( 1.0,  0.0), jitter, bhScale) * HdrWeightY(n3.x);
    hfloat pw4 = BhWeight(hvec2_init( 0.0,  1.0), jitter, bhScale) * HdrWeightY(n4.x);

    hfloat totalPW = pw0 + pw1 + pw2 + pw3 + pw4;
    hvec3 filtered = (n0 * pw0 + n1 * pw1 + n2 * pw2 + n3 * pw3 + n4 * pw4) / totalPW;

    // ================================================================
    // Stage 5: Plus-pattern min/max in YCoCg (AA_YCOCG=1)
    // ================================================================
    // UE4 AA_YCOCG path: simple min/max, NOT mu+-sigma (AA_ROUND).
    hvec3 nMin = min(min(min(n0, n1), n2), min(n3, n4));
    hvec3 nMax = max(max(max(n0, n1), n2), max(n3, n4));

    // ================================================================
    // Stage 6: Bicubic Catmull-Rom history sampling (AA_BICUBIC=1)
    // ================================================================
    // Negative lobes of Catmull-Rom provide natural sharpening.
    // This is the primary source of UE4 TAA sharpness — no explicit sharpen step.
    hvec3 history;
    hfloat lumaHistoryPreClamp = 0.0;
    hfloat historyClipAmount_ = 0.0;
    if (historyValid)
    {
        hvec2 texSize = 1.0 / texelSize;
        history = SampleHistoryBicubic(historyUV, texSize, texelSize);
        history = max(history, vec3_splat(0.0));

        // raw YCoCg（不预乘权重）
        history = RGBToYCoCg(history);

        // UE usf:2167-2174：luma 贡献下限用 **clamp 前** 的 LumaHistory
        lumaHistoryPreClamp = history.x;

        // ============================================================
        // Stage 7: Simple YCoCg clamp (AA_YCOCG=1, not ray-AABB)
        // ============================================================
        // UE Main HIGH：plus 5-tap YCoCg 逐通道硬 min/max，无 AA_CLIP/variance
        hvec3 rawHistory = history;
        history = clamp(history, nMin, nMax);

        // 【非 UE，用户验证机制 + Lumen 式归一化改良，勿删】history-clip 拒绝：
        // clamp 拉回量驱动 blend 提升，但按邻域盒宽度归一化（同 SSR denoiser 的
        // confidence 归一化，LumenReflectionDenoiserTemporal.usf:451-471 思路）——
        // 平坦区盒窄，鬼影拉回相对巨大 → 一帧杀掉（拖镜头残影场景）；
        // 剪影边缘盒宽（横跨前景背景对比），重采样拉回相对很小 → 不触发，
        // 边缘时域积累得以保留（转镜头锯齿场景）。绝对量版本会把两者一起杀，
        // 是"鬼影 vs 边缘锯齿"跷跷板的根源。
        hfloat pullLen = length(rawHistory - history);
        hfloat boxExtent = max(length(nMax - nMin), 0.05);
        historyClipAmount_ = saturate((pullLen / boxExtent - 0.3) * 4.0);
    }
    else
    {
        history = filtered;
        lumaHistoryPreClamp = filtered.x;
    }

    // ================================================================
    // Stage 8: BlendFinal 完整栈（UE TemporalAA.usf:2225-2270 整段移植）
    // ================================================================
    hfloat blendFactor = u_TAABlendFactor;   // = 1 * CurrentFrameWeight(0.04)

    // 速度 lerp：20px/帧饱和封顶 0.2 = 加速收敛而非重置，运动边缘仍有 ~5 帧积累。
    // UE 的 Velocity 是 2×像素/帧（/40 饱和），换算成像素单位即 /20。
    // MB 已就位提供 UE 同款高速掩蔽，此行按原版恢复
    hfloat velocityPx = length(motionVec / texelSize);
    blendFactor = mix(blendFactor, 0.2, saturate(velocityPx / 20.0));

    // luma 贡献下限（相对差 <1% 时 floor→1，防 HDR 高亮区 0.04 混合率收敛无限慢）
    blendFactor = max(blendFactor, saturate(0.01 * lumaHistoryPreClamp / abs(filtered.x - lumaHistoryPreClamp)));

    // 【非 UE，用户验证】history-clip 拒绝叠加（见 Stage 7 注释）
    blendFactor = max(blendFactor, saturate(u_TAABlendFactor + historyClipAmount_));

    // GLSL saturate(NaN) 兜底（UE usf:2244-2247 同款）
    blendFactor = -min(-blendFactor, 0.0);

    if (!historyValid)
        blendFactor = 1.0;

    // ================================================================
    // Stage 9: HDR 权重加权 lerp（UE WeightedLerpFactors，usf:682-690 + 2281-2291）
    // ================================================================
    // 无显式 tonemap 往返：w = 1/(Y+1) 归一化加权平均，代数上等价于可逆
    // tonemap 空间 lerp 再变回
    hfloat wHist = HdrWeightY(history.x);
    hfloat wFilt = HdrWeightY(filtered.x);
    hfloat blendA = (1.0 - blendFactor) * wHist;
    hfloat blendB = blendFactor * wFilt;
    hfloat rcpBlend = 1.0 / max(blendA + blendB, 1.0e-6);
    hvec3 result = history * (blendA * rcpBlend) + filtered * (blendB * rcpBlend);

    // YCoCg to RGB
    result = YCoCgToRGB(result);

    // NaN protection
    result = max(result, vec3_splat(0.0));

    // UE AA_DYNAMIC_ANTIGHOST：alpha 存本帧中心 tap 的动态标记（1-bit 元数据，
    // 不参与颜色混合），随 TAA Copy 进入 TAAHistory 供下一帧做不对称丢弃判据。
    // 下游（postprocess/SSR trace/HCB）均只消费 rgb，alpha 通道是空闲的。
    gl_FragColor = hvec4_init(result.x, result.y, result.z, centerDynamic ? 1.0 : 0.0);
}

#endif
