// SURFACE_SKY_SLOT_FEATURE_MACROS
#include "varying_surface_sky.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _INSTANCED
    $output vTexCoord
#endif
#ifdef COMPILEPS
    $input vTexCoord
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "SurfaceShaderCompatibility.sh"
#include "SurfaceGodotMatrices.sh"

// SURFACE_SKY_SLOT_CUSTOM_DECLARATIONS

vec2 DirectionToSkyCoords(vec3 dir)
{
    float absX = max(abs(dir.x), 0.000001);
    float longitude = atan(dir.z / absX);
    if (dir.x < 0.0)
        longitude = dir.z >= 0.0 ? 3.14159265 - longitude : -3.14159265 - longitude;

    float u = longitude * (0.5 / 3.14159265) + 0.5;
    float v = asin(clamp(dir.y, -1.0, 1.0)) / 3.14159265 + 0.5;
    return vec2(u, v);
}

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    gl_Position.z = gl_Position.w * cFarClipDepth;
    vTexCoord = iPos.xyz;
}

void PS()
{
    vec3 skyEyeDir = normalize(vTexCoord);
    vec2 skyCoords = DirectionToSkyCoords(skyEyeDir);
    vec2 skyScreenUV = gl_FragCoord.xy * cGBufferInvSize;

    vec3 skyColor = vec3(0.0, 0.0, 0.0);
    float skyAlpha = 1.0;

    // SURFACE_SKY_SLOT_BODY

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        skyColor = LinearToGammaSpace(toAcesFilmic(skyColor));
    #endif
    gl_FragColor = vec4(skyColor, skyAlpha);
}
