// 回归用例：数组初始化与标量 splat 这两处方言差异，必须走宏、不能直接写死一族的语法。
//
// 复刻的是 Surface Shader 生成产物里的两类行：
//     surface_unlit_StructArrayProbe_*.glsl：const hvec3 palette[2] = <数组初始化>
//     surface_unlit_PrecisionProbe_*.glsl：  hvec3 scalar_rgb = <标量 splat>
//
// 两处都没有两族通用的写法，各自只有一族接受：
//   1. 数组初始化。GLSL 只认构造式 `ctor[](...)`，HLSL 只认花括号 `{...}`。
//      构造位置还不允许精度限定符，所以传给 ARRAY_INIT_BEGIN 的必须是 hvecN_init 这类
//      无精度别名，写 hvec3（= highp vec3）在 GL 族会报语法错。
//   2. 标量 splat。HLSL 的单标量数值构造非法（float3(x) 报 X3014），只能 (x).xxx；
//      GLSL ES 反过来不接受标量 swizzle。
//
// 因此这里刻意用 ARRAY_INIT_* / hvecN_splat 宏，且数组元素类型保持 hvec3_init。
// 把宏换成任一族的字面语法就只能在那一族编过，也就测不到另一族了。
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

struct ColorPair
{
    hvec3 primary;
    hvec3 secondary;
};

// 全局 const 数组，与 StructArrayProbe 的生成产物同形。必须套 CONST 宏：HLSL 里不带 static 的
// 全局 const 会被当成 uniform，初始化列表被忽略、读出来全 0（编得过、但渲染成纯黑）。
// 这一条编译期抓不到，改成裸 const 仍然六族全绿 —— 判据在渲染结果，见 shader-gallery 的对应格子。
CONST(hvec3 palette[2]) = ARRAY_INIT_BEGIN(hvec3_init) hvec3_init(0.1, 0.35, 0.95), hvec3_init(0.95, 0.85, 0.2) ARRAY_INIT_END();

ColorPair make_pair(hvec3 a, hvec3 b)
{
    ColorPair pair;
    pair.primary = a;
    pair.secondary = b;
    return pair;
}

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

void PS()
{
    hvec2 uv = vScreenPos;

    // 函数体内的局部数组，与 StructArrayLocal 的生成产物同形
    hvec3 localPalette[2] = ARRAY_INIT_BEGIN(hvec3_init) palette[0], palette[1] ARRAY_INIT_END();
    ColorPair pair = make_pair(localPalette[0], localPalette[1]);

    // 标量 splat：vec3 与 vec4 两种宽度都覆盖
    hfloat weight = 0.65;
    hvec3 scalarRgb = hvec3_splat(uv.x);
    hvec4 scalarRgba = hvec4_splat(weight);

    hvec3 color = mix(pair.primary, pair.secondary, step(0.5, uv.x));
    gl_FragColor = hvec4_init(color + scalarRgb * 0.0, 1.0) + scalarRgba * 0.0;
}
