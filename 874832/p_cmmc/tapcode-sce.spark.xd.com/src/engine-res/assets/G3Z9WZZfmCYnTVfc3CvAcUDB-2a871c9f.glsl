// 回归用例：求导内建与 textureGrad 的梯度操作数必须是 32 位。
//
// 复刻的是 Surface Shader 生成产物 surface_unlit_TextureBuiltinProbe_*.glsl 里的两行：
//     vec2 surfaceUV = GetTexCoord(iTexCoord);   // vec2 在 hlsl 编译族里是 half2
//     hvec2 dx = dFdx(surfaceUV);
//     texture2DGrad(sampler, surfaceUV, dx, dy)
//
// 这个用例专门盯两个容易复发的点，两者都只在 ios hlslcc=false 暴露（SPIR-V 校验），
// 且都是"结果变量写成全精度也救不了"的：
//   1. 实参精度。dFdx / dFdy 编成 OpDPdx / OpDPdy，规范要求操作数 32 位。生成器把
//      highp vec2 正确译成了 hvec2，所以结果变量是 32 位，但压不住传进去的实参。
//   2. 形参精度。bgfxTexture2DGrad 的梯度形参若声明成 vec2（=half2），会把调用点已经是
//      hvec2 的实参重新窄化回 half2，SampleGrad 的 Grad 操作数于是又变成 fp16。
//
// 因此这里刻意让实参保持 vec2、结果存 hvec2，与生成产物一致；改成 hvec2 传参就测不到了。
#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position
    $output vScreenPos
#endif
#ifdef COMPILEPS
    $input vScreenPos
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "post_process.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

void PS()
{
    vec2 uv = vScreenPos;

    // 实参是 vec2（half2），结果存 hvec2 —— 与生成产物同形
    hvec2 dx = dFdx(uv);
    hvec2 dy = dFdy(uv);
    hvec4 grad = texture2DGrad(sDiffMap, uv, dx, dy);

    // fwidth 走另一条路（内建 OpFwidth），一并覆盖
    vec2 w = fwidth(uv);

    gl_FragColor = vec4(grad.rgb + vec3(w.x, w.y, 0.0), 1.0);
}
