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
    vWorldPos = hvec4(worldPos.xyz, 1.0);
}

void PS()
{
    hvec2 offset = u_PlayerPosAndRadius.xy - vWorldPos.xy;
    hfloat dist = sqrt(dot(offset, offset));
    hfloat radius = u_PlayerPosAndRadius.w;
    hfloat softRadius = radius - cSoftRadius;
    hfloat x = saturate((dist - softRadius) / (radius - softRadius));
    hfloat t = saturate(((((((-3.5014003585845273e+001 * x + 1.3235293405521651e+002) * x - 1.7892155871760215e+002) * x + 9.9302406405536999e+001) * x - 1.8016588796403184e+001) * x + 1.3520289245771870e+000) * x - 5.5753044766208237e-002) * x + 1.2340595995721142e-004);
    gl_FragColor = u_ShadowColor * t;
}

