#include "MaterialBake/VaryingMaterialBake.def.sc"
$input a_position, a_texcoord0
$output v_texcoord0

#include "Common/common.sh"

// UV-space material-bake VS: a_position.xy carries the raw UV (bake VB built on the
// C++ side); expand it to NDC here -- no MVP transform, rasterization happens directly
// in UV space. The Y-direction difference between GL-family (originBottomLeft) and D3D
// backends is handled here so that row 0 of the readback image always corresponds to
// v=0 (the CPU-side sampling convention).
// See docs/design/hlod-world-partition-design.md section 3.3.1.
void main()
{
    float x = a_position.x * 2.0 - 1.0;
    float y = 1.0 - a_position.y * 2.0;
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    y = -y;
#endif
    gl_Position = vec4(x, y, 0.0, 1.0);
    v_texcoord0 = a_texcoord0;
}
