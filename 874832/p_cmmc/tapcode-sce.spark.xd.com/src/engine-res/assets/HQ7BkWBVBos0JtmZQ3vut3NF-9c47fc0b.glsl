#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"

$input vNormal, vWorldPos

#define RENDER_QUALITY 3

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#include "constants.sh"
#if defined(PERPIXEL)
#include "PBR/StandardPBR.sh"
#endif

void PS()
{
    vec3 baseColor = vec3(0.3, 0.3, 0.3);
#if defined(PERPIXEL)
    vec3 viewDirection = normalize(cCameraPosPS - vWorldPos.xyz);
    vec3 finalColor = MetallicPBR(baseColor, 0.0, 0.5, 0.5, vWorldPos.xyz, vNormal, viewDirection, vec3(1.0, 1.0, 1.0), 1.0);
    gl_FragColor = vec4(finalColor, 1.0);
#else
    gl_FragColor = vec4(baseColor, 1.0);
#endif
}
