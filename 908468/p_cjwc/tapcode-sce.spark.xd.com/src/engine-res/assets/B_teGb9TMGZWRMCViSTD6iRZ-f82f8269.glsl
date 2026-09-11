#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"

$input a_position, a_normal
$output vNormal, vWorldPos

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "constants.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    vNormal = GetWorldNormal(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vWorldPos = hvec4_init(worldPos, GetDepth(gl_Position));
}
