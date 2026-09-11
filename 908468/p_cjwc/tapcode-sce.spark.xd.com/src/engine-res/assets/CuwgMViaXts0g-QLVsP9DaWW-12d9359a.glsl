#include "varying_surface_fog.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _INSTANCED
    $output vWorldPos
#endif
#ifdef COMPILEPS
    $input vWorldPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "SurfaceGodotMatrices.sh"

// SURFACE_FOG_SLOT_CUSTOM_DECLARATIONS

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vWorldPos = vec4(worldPos, 1.0);
}

void PS()
{
    vec3 fogWorldPosition = vWorldPos.xyz;
    vec3 fogObjectPosition = vec3(0.0, 0.0, 0.0);
    vec3 fogUVW = vec3(0.0, 0.0, 0.0);
    vec3 fogSize = vec3(1.0, 1.0, 1.0);
    float fogSDF = 0.0;

    vec3 fogAlbedo = vec3(1.0, 1.0, 1.0);
    float fogDensity = 0.0;
    vec3 fogEmission = vec3(0.0, 0.0, 0.0);

    // SURFACE_FOG_SLOT_BODY

    // Placeholder until the volumetric fog renderer consumes fog outputs.
    gl_FragColor = vec4(fogAlbedo + fogEmission, fogDensity);
}
