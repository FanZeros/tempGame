#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position, a_texcoord1
    $output vWorldPos, vScreenPos
#endif
#ifdef COMPILEPS
    $input vWorldPos, vScreenPos
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
    hvec2 pos = vWorldPos.xy;
    hvec2 offset = pos - u_PlayerPosAndRadius.xy;
    float cosTheta = dot(normalize(offset), u_SkillDirAndRadius.xy);
    float cosRange = cSkillCosAngle;
    hfloat sqrDist = dot(offset, offset);
    //inside inner radius
    if (sqrDist < u_SkillDirAndRadius.z * u_SkillDirAndRadius.z)
        discard;
    //inside fan
    if(sqrDist < u_SkillDirAndRadius.w * u_SkillDirAndRadius.w && cosRange > 0.0 && cosTheta > cosRange)
        discard;
    gl_FragColor = u_ShadowColor;
}

