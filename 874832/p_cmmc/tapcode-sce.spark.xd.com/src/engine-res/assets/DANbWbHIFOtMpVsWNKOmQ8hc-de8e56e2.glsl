#include "EnvBake/varying_envbake.def.sc"
$input a_position
$output v_texcoord0

#include "Common/common.sh"

void main()
{
    vec4 worldPos = mul(a_position, u_model[0]);
    worldPos.w = 1.0;
    gl_Position = mul(mul(worldPos, u_view), u_proj);

#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    v_texcoord0 = hvec2_init(
        gl_Position.x / gl_Position.w * 0.5 + 0.5,
        gl_Position.y / gl_Position.w * 0.5 + 0.5);
#else
    v_texcoord0 = hvec2_init(
        gl_Position.x / gl_Position.w * 0.5 + 0.5,
        -gl_Position.y / gl_Position.w * 0.5 + 0.5);
#endif
}
