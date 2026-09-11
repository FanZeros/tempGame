// SkyboxFog: Skybox cubemap shader that receives Exponential Height Fog along the
// view direction (UE-style horizon haze). Use technique DiffSkyboxFog.xml.
// At zenith the fake sample height is far above the height-fog layer, so the dome
// stays clear; at the horizon the height collapses near the camera and fog dominates.
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
#include "fog.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    gl_Position.z = gl_Position.w;
    vTexCoord = iPos.xyz;
}

void PS()
{
    vec4 sky = cMatDiffColor * GammaToLinearSpace(textureCube(sDiffCubeMap, vTexCoord));
    #ifdef HDRSCALE
        sky = pow(sky + clamp((vec4_splat(cAmbientColor.a - 1.0) * 0.1), 0.0, 0.25), max(vec4_splat(cAmbientColor.a), 1.0)) * clamp(vec4_splat(cAmbientColor.a), 0.0, 1.0);
    #endif

    // View-direction horizon haze (CryEngine TOD / Naughty Dog style).
    // The engine's GetHeightFogFactor is a Gaussian probe at a single height — it's
    // designed for ground objects with finite distance and falls off too fast above
    // heightStart to produce a usable horizon band on sky. So we synthesize the fog
    // factor directly from the view direction: zenith stays clear, horizon mixes in
    // cFogColor smoothly. Strength is driven by the larger of the Zone's distance
    // and height fog densities, so any non-zero fog density in the scene immediately
    // shows up on the sky without needing extra material parameters.
    const float SKY_MIN_OPACITY = 0.03;
    vec3  viewDir     = normalize(vTexCoord);
    float horizonness = 1.0 - clamp(__GET_HEIGHT__(viewDir), 0.0, 1.0);
    float horizonRamp = horizonness * horizonness;                  // soften toward zenith
    float maxDensity  = max(cFogParams.z, cFogParams2.z);           // dist or height density
    float fogFactor   = max(1.0 - horizonRamp * maxDensity, SKY_MIN_OPACITY);
    sky.rgb = GetFog(sky.rgb, fogFactor);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        sky.rgb = LinearToGammaSpace(toAcesFilmic(sky.rgb));
    #endif
    gl_FragColor = sky;
}
