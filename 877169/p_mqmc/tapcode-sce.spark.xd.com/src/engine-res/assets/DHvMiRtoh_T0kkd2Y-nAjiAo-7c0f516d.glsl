#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position, a_texcoord1, i_data0
    $output vWorldPos
#endif
#ifdef COMPILEPS
    $input vWorldPos
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
 
#ifdef COMPILEVS
#define inClipLine i_data0
#endif

#include "Sight/SightCommon.sh"

void VS()
{
    hvec3 p1 = hvec3(inClipLine.xy, 0.0);
    hvec3 p2 = hvec3(inClipLine.zw, 0.0);
    hvec3 p01 = normalize(p1 - u_PlayerPosAndRadius.xyz);
    hvec3 p02 = normalize(p2 - u_PlayerPosAndRadius.xyz);
    hvec3 p1ex = p01 * 10000.0 + u_PlayerPosAndRadius.xyz;
    hvec3 p2ex = p02 * 10000.0 + u_PlayerPosAndRadius.xyz;
    //Quad UV是-1或1
    float l = step(a_texcoord1.x, -0.5);
    float r = step(0.5, a_texcoord1.x);
    float t = step(a_texcoord1.y, -0.5);
    float b = step(0.5, a_texcoord1.y);
    float lt = step(1.5, l + t);
    float lb = step(1.5, l + b);
    float rt = step(1.5, r + t);
    float rb = step(1.5, r + b);
    hvec3 pos = lt * p1 + rt * p1ex + lb * p2 + rb * p2ex;
    vWorldPos = hvec4(pos, u_PlayerPosAndRadius.w * u_PlayerPosAndRadius.w);
    gl_Position = GetClipPos(vWorldPos);
}

void PS()
{
    // CheckSkillDiscard(vWorldPos.xy);
    gl_FragColor = u_ShadowColor;
}