#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position, a_texcoord1
    $output vWorldPos
#endif
#ifdef COMPILEPS
    $input vWorldPos
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "transform.sh"

#include "Sight/SightCommon.sh"
void VS()
{
    //给大点全屏
    hvec3 worldPos = hvec3(u_PlayerPosAndRadius.xy + a_texcoord1.xy * u_OrthoSize, 0.6 * u_PlayerPosAndRadius.z);
    gl_Position = GetClipPos(worldPos);
    vWorldPos = hvec4(worldPos.xyz, u_PlayerPosAndRadius.w * u_PlayerPosAndRadius.w);
}

void PS()
{
    hvec2 offset = u_PlayerPosAndRadius.xy - vWorldPos.xy;
    if (dot(offset, offset) < vWorldPos.w)
        discard;
    // CheckSkillDiscard(vWorldPos.xy);
    //这里不写入颜色，只是写模板,这样保证深度测试能过
    gl_FragColor = u_ShadowColor;
}

