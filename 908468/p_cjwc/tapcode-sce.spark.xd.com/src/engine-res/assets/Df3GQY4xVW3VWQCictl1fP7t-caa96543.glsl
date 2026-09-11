#include "varying_scenepass_outsurface.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position, a_normal _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    $output vWorldPos, vNormal, vColor
#endif
#ifdef COMPILEPS
    $input vWorldPos, vNormal, vColor
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "constants.sh"


void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vNormal = GetWorldNormal(modelMatrix);
    vColor = iHighlightColor;
}

void PS()
{
    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);
    vec3 normalDirection = normalize(vNormal);

    float NdotV = clamp(dot(normalDirection, viewDirection), M_EPSILON, 1.0);
    float fresnel = 1.0 - NdotV * vColor.w;

    gl_FragColor.rgb = vColor.xyz * pow(fresnel, 0.9) * 2.0;
    gl_FragColor.a = fresnel;
}
