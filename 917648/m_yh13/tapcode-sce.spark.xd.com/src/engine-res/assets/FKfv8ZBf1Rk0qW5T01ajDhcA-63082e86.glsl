/*
 * Scene Fog (deferred)
 *
 * Applies the Zone's depth fog + height fog to the deferred scene color as a
 * single full-screen pass, mirroring UE's dedicated fog pass (FogRendering.cpp /
 * HeightFogPixelShader.usf). The GBuffer encode branches deliberately drop fog
 * (fog is a per-view screen-space term, not a material property), and the
 * deferred lighting / SSR composite passes never re-apply it, so without this
 * pass every opaque lit pixel in CEMapDeferred.xml ends up unfogged.
 *
 * Named SceneFog rather than HeightFog because UrhoX combines two independent
 * terms: min(heightFogFactor, depthFogFactor) -- see fog.sh.
 *
 * Output is premultiplied fog: rgb = inscattering, a = coverage (1 - fogFactor).
 * Paired with blend="premulalpha" (ONE, INV_SRC_ALPHA) this evaluates to
 *   dst = fogColor * (1 - f) + dst * f = mix(fogColor, dst, f) == GetFog(dst, f)
 * i.e. bit-for-bit the same operation the forward shaders perform, without
 * having to read SceneColor back.
 *
 * Must run after the sky (postopaque) and before the alpha passes: alpha /
 * postalpha / particles / water fog themselves in their own forward shaders.
 *
 * Sky pixels (depth ~ far) get an elevation fade on top of skyFogIntensity:
 * full fog on/below the horizon, fading out toward the zenith. Soft width is
 * RenderPath parameter SkyFogHorizonSoftness (sin(elevation) units).
 *
 * Limitation: world position is reconstructed through the perspective far ray,
 * so orthographic cameras are not supported (a quad cannot select the ORTHO
 * variant the way StandardPBRDeferred does).
 */

#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vWorldPos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vWorldPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "fog.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    // vWorldPos carries the camera-relative FAR RAY (not a world position): the quad
    // geometry/transform is the same one the directional light volume uses, so this is
    // the proven path from StandardPBRDeferred's DIRLIGHT variant.
    vWorldPos = hvec4_init(GetFarRay(gl_Position), 0.0);
}

#ifdef COMPILEPS

// Readable depth RT (register 0)
SAMPLER2D(u_Depth0, 0);

// Zone.skyFogIntensity, uploaded by View::ApplySceneFogParameters.
// 1.0 = sky participates in fog (horizon melts into fog color)
// 0.0 = sky keeps its original color (legacy UrhoX behaviour, sky decoupled from fog)
// Combined with the elevation fade below: only the horizon band receives fog;
// the zenith keeps the skybox.
uniform hfloat u_SkyFogIntensity;

// Soft width of the horizon fog band in view-dir "up" units (sin(elevation)).
// From RenderPath <parameter name="SkyFogHorizonSoftness" /> via SetCommandShaderParameters.
// 0.25 ≈ 14.5°: full fog on/below the horizon, fades out toward the zenith.
// <= 0 falls back to the same default so a missing parameter does not hard-cut.
uniform hfloat u_SkyFogHorizonSoftness;

// Linear depth at (or beyond) the far plane counts as "nothing was rendered here".
#define SCENE_FOG_SKY_DEPTH 0.9999
#define SCENE_FOG_SKY_HORIZON_SOFTNESS_DEFAULT 0.25

void PS()
{
    hvec2 uv = vTexCoord;
    // cDepthReconstruct absorbs the reverse-Z / depth-mode differences, so this is
    // a linear 0..1 depth on every backend (same call StandardPBRDeferred makes).
    hfloat depth = ReconstructDepth(texture2D(u_Depth0, uv).r);

    hvec3 cameraToPixel = vWorldPos.xyz * depth;
    hvec3 worldPos = cCameraPosPS + cameraToPixel;

    // GetHeightFogFactor is min(heightFogFactor, depthFogFactor); with height fog
    // disabled the engine uploads a zero density (View::ApplySceneFogParameters), which collapses
    // the height term to 1.0 and leaves pure depth fog. Calling it unconditionally
    // avoids needing a HEIGHTFOG shader variant, which a quad cannot select.
    hfloat fogFactor = GetHeightFogFactor(length(cameraToPixel), __GET_HEIGHT__(worldPos));

    // Sky / background pixels.
    // Linear depth fog treats every far-plane ray the same, so a flat skyFogIntensity
    // scale paints the zenith as heavily as the horizon. Approximate UE-like
    // directionality with an elevation fade on sky only — geometry keeps the
    // existing GetHeightFogFactor path bit-identical to forward.
    //
    // skyFogIntensity=0 still fully decouples sky (legacy); =1 enables horizon melt.
    // mix (not lerp): lerp is only defined for HLSL / emscripten in bgfx_shader.sh
    if (depth >= SCENE_FOG_SKY_DEPTH)
    {
        // vWorldPos is the camera-relative FAR RAY (see VS); normalize → view direction.
        hfloat elev = __GET_HEIGHT__(normalize(vWorldPos.xyz));
        hfloat softness = u_SkyFogHorizonSoftness > 0.0
            ? u_SkyFogHorizonSoftness
            : SCENE_FOG_SKY_HORIZON_SOFTNESS_DEFAULT;
        // elev <= 0 (on/below horizon): full weight. elev → softness: fade to 0.
        hfloat horizonWeight = 1.0 - smoothstep(0.0, softness, max(elev, 0.0));
        hfloat skyWeight = u_SkyFogIntensity * horizonWeight;
        fogFactor = mix(1.0, fogFactor, skyWeight);
    }

    hfloat coverage = 1.0 - fogFactor;
    gl_FragColor = hvec4_init(cFogColor * coverage, coverage);
}

#endif
