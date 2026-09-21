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

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

//这个东西只在DX用，默认4xMSAA，如果后面要有不同的MSAA sample count，再加宏处理吧
void PS()
{
    ivec2 coord = vScreenPos.xy / cGBufferInvSize.xy;
    hfloat depth0 = texelFetch(u_DiffMapMS, coord, 0).x;
    hfloat depth1 = texelFetch(u_DiffMapMS, coord, 1).x;
    hfloat depth2 = texelFetch(u_DiffMapMS, coord, 2).x;
    hfloat depth3 = texelFetch(u_DiffMapMS, coord, 3).x;
    gl_FragDepth = min(min(depth0, depth1), min(depth2, depth3));
}

