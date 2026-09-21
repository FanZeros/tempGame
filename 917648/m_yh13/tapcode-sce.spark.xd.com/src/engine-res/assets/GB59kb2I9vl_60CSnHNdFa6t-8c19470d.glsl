/*
 * Motion Blur Tile Reduce（UE VelocityFlatten 的 LDS tile 归约 quad 化）
 *
 * tile 分辨率（ceil(res/16)）：每 tile 像素循环 16×16 flatten 像素，
 * 按速度像素长度归约 min/max（1-direction），输出笛卡尔 (Min.xy, Max.xy) RGBA16F。
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

// flatten 全分辨率纹理（r=速度像素长, g=角度01）
SAMPLER2D(u_VelocityFlatten0, 0);

// xy = flatten 纹理 inv size（全分辨率 texel），zw = flatten 纹理尺寸
uniform hvec4 u_MBFlattenInvSize;

void PS()
{
    // 本 tile 对应的 flatten 像素起点（tile 渲染目标 1 像素 = 16×16 flatten 像素）
    hvec2 tileCoord = floor(vTexCoord / cGBufferInvSize.xy);   // 当前 tile 整数坐标
    hvec2 basePx = tileCoord * 16.0;

    hvec2 minVel = vec2_splat(0.0);
    hvec2 maxVel = vec2_splat(0.0);
    hfloat minLen = 1.0e9;
    hfloat maxLen = -1.0;

    LOOP
    for (int y = 0; y < 16; y++)
    {
        LOOP
        for (int x = 0; x < 16; x++)
        {
            hvec2 px = basePx + hvec2_init(hfloat_init(x) + 0.5, hfloat_init(y) + 0.5);
            hvec2 uv = min(px * u_MBFlattenInvSize.xy, vec2_splat(1.0));
            hvec2 lenAngle = texture2D(u_VelocityFlatten0, uv).rg;
            hfloat len = lenAngle.r;
            hfloat angle = lenAngle.g * (2.0 * MB_PI) - MB_PI;
            hvec2 vel = hvec2_init(cos(angle), sin(angle)) * len;
            if (len > maxLen) { maxLen = len; maxVel = vel; }
            if (len < minLen) { minLen = len; minVel = vel; }
        }
    }

    gl_FragColor = hvec4_init(minVel.x, minVel.y, maxVel.x, maxVel.y);
}

#endif
