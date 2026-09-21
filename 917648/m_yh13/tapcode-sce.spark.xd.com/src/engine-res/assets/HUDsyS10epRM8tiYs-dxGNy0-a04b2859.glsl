/*
 * Motion Blur Tile Gather/Dilate（UE MotionBlurTileGather.usf:30-91 移植）
 *
 * tile 分辨率：7×7(±3) 邻域，邻居沿自身速度方向的 swept-quad OBB 覆盖本 tile
 * 中心才并入归约（非无脑 max，保证膨胀严格沿速度方向）。
 * 硬约束：gather ±3 tile ⇒ 速度像素上限 96px（参数下发端已 clamp）。
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

// tile 归约结果（Min.xy, Max.xy 笛卡尔像素）
SAMPLER2D(u_VelocityTile0, 0);

void PS()
{
    hvec2 texel = cGBufferInvSize.xy;   // tile-res texel
    hvec2 uv = vTexCoord;

    hvec4 center = texture2D(u_VelocityTile0, uv);
    hvec2 minVel = center.xy;
    hvec2 maxVel = center.zw;
    hfloat minLen = length(minVel);
    hfloat maxLen = length(maxVel);

    // VelocityScaleForFlattenTiles = 1/16（无上采样，像素 → tile 单位）
    const hfloat kPxToTile = 1.0 / 16.0;

    LOOP
    for (int y = -3; y <= 3; y++)
    {
        LOOP
        for (int x = -3; x <= 3; x++)
        {
            if (x == 0 && y == 0) continue;
            hvec2 nUV = uv + hvec2_init(hfloat_init(x), hfloat_init(y)) * texel;
            if (any(lessThan(nUV, vec2_splat(0.0))) || any(greaterThan(nUV, vec2_splat(1.0))))
                continue;

            hvec4 n = texture2D(u_VelocityTile0, nUV);
            hvec2 nMaxTile = n.zw * kPxToTile;

            hfloat lenSqr = dot(nMaxTile, nMaxTile);
            hfloat lenInv = inversesqrt(lenSqr + 1.0e-8);
            hfloat len = lenSqr * lenInv;
            hvec2 dir = nMaxTile * lenInv;

            // swept-quad OBB 覆盖测试（0.99 给邻居留 epsilon，UE 原注释）
            hfloat pixelExtent = abs(dir.x) + abs(dir.y);
            hvec2 quadExtent = hvec2_init(len, 0.0) + vec2_splat(pixelExtent * 0.99);

            hvec2 offset = hvec2_init(hfloat_init(x), hfloat_init(y));
            hvec2 onQuad = hvec2_init(dot(dir, offset), dot(hvec2_init(-dir.y, dir.x), offset));

            if (all(lessThan(abs(onQuad), quadExtent)))
            {
                hfloat nMaxLen = length(n.zw);
                hfloat nMinLen = length(n.xy);
                if (nMaxLen > maxLen) { maxLen = nMaxLen; maxVel = n.zw; }
                if (nMinLen < minLen) { minLen = nMinLen; minVel = n.xy; }
            }
        }
    }

    gl_FragColor = hvec4_init(minVel.x, minVel.y, maxVel.x, maxVel.y);
}

#endif
