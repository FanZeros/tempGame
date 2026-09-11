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

#if defined(BLIT_COLOR_AND_DEPTH)
SAMPLER2D(u_DepthBuffer1, 1);
#endif

#if defined(BLIT_DEPTH)
SAMPLER2D(u_DepthBuffer0, 0);
#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

void PS()
{
#if defined(BLIT_COLOR_AND_DEPTH)
    gl_FragColor = texture2D(sDiffMap, vScreenPos);
    gl_FragDepth = texture2D(u_DepthBuffer1, vScreenPos).r;
#elif defined(BLIT_DEPTH)
    gl_FragDepth = texture2D(u_DepthBuffer0, vScreenPos).r;
#else
    gl_FragColor = texture2D(sDiffMap, vScreenPos);
#endif
}

