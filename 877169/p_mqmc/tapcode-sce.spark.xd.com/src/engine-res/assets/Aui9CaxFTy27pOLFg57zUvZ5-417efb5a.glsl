#include "varying_skybox.def.sc"
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
    #ifdef NOT_SUPPORT_SRGB
        vec4 sky = cMatDiffColor * GammaToLinearSpace(textureCube(sDiffCubeMap, vTexCoord));
    #else
        vec4 sky = cMatDiffColor * textureCube(sDiffCubeMap, vTexCoord);
    #endif
    #ifdef HDRSCALE
        sky = pow(sky + clamp((vec4_splat(cAmbientColor.a - 1.0) * 0.1), 0.0, 0.25), max(vec4_splat(cAmbientColor.a), 1.0)) * clamp(vec4_splat(cAmbientColor.a), 0.0, 1.0);
    #endif
    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        sky.rgb = LinearToGammaSpace(toAcesFilmic(sky.rgb));
    #endif
    gl_FragColor = sky;
}
