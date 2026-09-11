/*
 * Motion Blur Apply（UE MotionBlurApply.usf 移植，1-direction / full-res / quad 化）
 *
 * 读 TAAHistory（本帧 TAA 输出副本）写 viewport。McGuire 重建滤波：
 * bSkip / bFastPath（均匀 gather）/ 加权主路径（深度感知 scatter-as-gather），
 * 中心权重 = 1 − 归一化累计权重（无显式 center tap）。
 * 蓝图：docs/plans/motion-blur-ue5.md §4；易错点：SOFT_Z_EXTENT 深度单位（我们米制）。
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

SAMPLER2D(u_Color0, 0);            // TAAHistory（本帧 TAA 输出）
SAMPLER2D(u_VelocityFlatten1, 1);  // (lenPx, angle01, linearZ)
SAMPLER2D(u_VelocityTile2, 2);     // 膨胀后 (Min.xy, Max.xy) 像素

// x = MaxSampleCount（质量档 4/8/12/16），y = DepthScale（1/软深度宽度，米制，默认 100 = 1cm）
// zw = tile 纹理 inv size
uniform hvec4 u_MBApplyParams;

#define MB_MINIMAL_PIXEL_VELOCITY 0.5

hfloat InterleavedGradientNoiseMB(hvec2 pixelPos, hfloat frame)
{
    hvec3 magic = hvec3_init(0.06711056, 0.00583715, 52.9829189);
    hvec2 p = pixelPos + frame * hvec2_init(47.0, 17.0) * 0.695;
    return fract(magic.z * fract(dot(p, magic.xy)));
}

// UE ComputeSampleConvolutionWeight（1-direction：方向权重恒 1）
hfloat SampleConvolutionWeight(hfloat sampleSpreadLen, hfloat offsetLength, hfloat pixelToSampleScale)
{
    return saturate(pixelToSampleScale * sampleSpreadLen - max(offsetLength - 1.0, 0.0));
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 texel = cGBufferInvSize.xy;
    hvec2 pixelPos = uv / texel;

    hvec4 centerColor = texture2D(u_Color0, uv);

    // ---- tile 速度采样 + ±0.25 tile 抖动（不做会有 16px 块状接缝，UE usf:299-320）----
    hfloat random  = InterleavedGradientNoiseMB(pixelPos, 0.0);
    hfloat random2 = InterleavedGradientNoiseMB(pixelPos, 1.0);
    hvec2 tileJitter = (hvec2_init(random, random2) - 0.5) * 0.5;
    hvec2 tileUV = (pixelPos / 16.0 + tileJitter) * u_MBApplyParams.zw;
    tileUV = clamp(tileUV, vec2_splat(0.0), vec2_splat(1.0));
    hvec4 tileVel = texture2D(u_VelocityTile2, tileUV);
    hvec2 minVelPx = tileVel.xy;
    hvec2 maxVelPx = tileVel.zw;

    hfloat maxLen = length(maxVelPx);

    // bSkip：无可感运动，原样输出
    BRANCH
    if (maxLen < MB_MINIMAL_PIXEL_VELOCITY)
    {
        gl_FragColor = centerColor;
        return;
    }

    // 采样数：clamp(4*ceil(len/4), 4, MaxSampleCount)（逐像素，放弃 wave 标量化）
    hfloat maxSampleCount = u_MBApplyParams.x;
    hfloat sampleCountF = clamp(4.0 * ceil(maxLen / 4.0), 4.0, maxSampleCount);
    int sampleCount = int(sampleCountF);
    hfloat invSampleCount = 1.0 / sampleCountF;

    hvec2 searchVector = maxVelPx * texel;   // 像素 → color UV

    // bFastPath：tile 内运动接近均匀 → 无权重均匀 gather，FullResBlend=0
    hfloat minLenSqr = dot(minVelPx, minVelPx);
    BRANCH
    if (minLenSqr > 0.4 * maxLen * maxLen)
    {
        hvec4 colorAccum = vec4_splat(0.0);
        LOOP
        for (int i = 0; i < sampleCount; i += 2)
        {
            hvec2 offsetLength = hfloat_init(i / 2) + 0.5 + hvec2_init(random - 0.5, 0.5 - random);
            hvec2 offsetFraction = offsetLength * (2.0 * invSampleCount);
            hvec2 uv0 = clamp(uv + offsetFraction.x * searchVector, vec2_splat(0.0), vec2_splat(1.0));
            hvec2 uv1 = clamp(uv - offsetFraction.y * searchVector, vec2_splat(0.0), vec2_splat(1.0));
            colorAccum += texture2D(u_Color0, uv0);
            colorAccum += texture2D(u_Color0, uv1);
        }
        gl_FragColor = colorAccum * invSampleCount;
        return;
    }

    // ---- 加权主路径（scatter-as-gather，UE usf:496-583）----
    hfloat totalSteps = sampleCountF * 0.5;
    hfloat pixelToSampleScale = totalSteps / max(maxLen, 0.001);
    hfloat depthScale = u_MBApplyParams.y;

    hvec3 centerVD = texture2D(u_VelocityFlatten1, uv).xyz;
    hfloat centerDepth = centerVD.z;
    hfloat centerSpreadLen = centerVD.x;

    hvec4 colorAccum = vec4_splat(0.0);
    hfloat weightAccum = 0.0;

    LOOP
    for (int stepId = 0; stepId < int(totalSteps); stepId++)
    {
        hvec2 offsetLength = hfloat_init(stepId) + 0.5 + hvec2_init(random - 0.5, 0.5 - random);
        hvec2 offsetFraction = offsetLength / totalSteps;
        hfloat weightOffsetLength = hfloat_init(stepId) + 0.5;

        hvec2 sUV0 = clamp(uv + offsetFraction.x * searchVector, vec2_splat(0.0), vec2_splat(1.0));
        hvec2 sUV1 = clamp(uv - offsetFraction.y * searchVector, vec2_splat(0.0), vec2_splat(1.0));

        hvec3 vd0 = texture2D(u_VelocityFlatten1, sUV0).xyz;
        hvec3 vd1 = texture2D(u_VelocityFlatten1, sUV1).xyz;
        hvec4 c0 = texture2D(u_Color0, sUV0);
        hvec4 c1 = texture2D(u_Color0, sUV1);

        // ComputeCenterOrSampleWeight（usf:227-249）：深度选择 center/sample 的卷积权重
        hfloat centerW0 = saturate(0.5 + depthScale * (vd0.z - centerDepth));
        hfloat sampleW0 = 1.0 - centerW0;
        hfloat w0 = centerW0 * SampleConvolutionWeight(centerSpreadLen, weightOffsetLength, pixelToSampleScale)
                  + sampleW0 * SampleConvolutionWeight(vd0.x, weightOffsetLength, pixelToSampleScale);

        hfloat centerW1 = saturate(0.5 + depthScale * (vd1.z - centerDepth));
        hfloat sampleW1 = 1.0 - centerW1;
        hfloat w1 = centerW1 * SampleConvolutionWeight(centerSpreadLen, weightOffsetLength, pixelToSampleScale)
                  + sampleW1 * SampleConvolutionWeight(vd1.x, weightOffsetLength, pixelToSampleScale);

        // 成对镜像 hole-filling（UE MotionBlurApply.usf:580-582 逐字同构）：
        //   Mirror = bool2(Depth0 > Depth1, VelLen0 < VelLen1)
        //   W0 = all(Mirror) ? W1 : W0;
        //   W1 = any(Mirror) ? W1 : W0;   // 注意此处 W0 是上一行更新后的值
        // 展开真值表 (mA,mB)→(w0m,w1m)：FF→(w0,w0) TF→(w0,w1) FT→(w0,w1) TT→(w1,w1)，
        // 下两行逐组合与之相等。深度极性无需翻转：UE flatten 存的是
        // ConvertFromDeviceZ(DeviceZ) = 线性场景深度（大 = 远），与本实现 linearZ 同向
        bool mA = vd0.z > vd1.z;
        bool mB = vd0.x < vd1.x;
        hfloat w0m = (mA && mB) ? w1 : w0;
        hfloat w1m = (mA || mB) ? w1 : w0m;

        colorAccum += w0m * c0 + w1m * c1;
        weightAccum += w0m + w1m;
    }

    colorAccum *= invSampleCount;
    weightAccum *= invSampleCount;

    // 中心权重 = 权重亏空（UE usf:698-712 + :1038）
    hfloat fullResBlend = saturate(1.0 - weightAccum);
    gl_FragColor = centerColor * fullResBlend + colorAccum;
}

#endif
