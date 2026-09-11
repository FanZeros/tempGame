/*
 * SSR Reflection Composite Shader
 * Implements reflection hierarchy system for energy-conserving reflections.
 *
 * Reflection Hierarchy (priority high to low):
 *   1. SSR (Screen Space Reflections)
 *   2. IBL Specular (global environment fallback)
 *
 * Key principle: SSR REPLACES IBL specular (not adds to it) for energy conservation.
 */

#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "ScreenSpace/ScreenSpaceCommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

// Scene lighting: direct_all + IBL_diffuse + emissive (register 0)
SAMPLER2D(u_SceneLighting0, 0);
// Environment specular: IBL_specular only, SSR fallback (register 1)
SAMPLER2D(u_EnvSpecular1, 1);
// SSR Buffer (register 2)
SAMPLER2D(u_SSRBuffer2, 2);
// GBufferA - normal (register 3)
SAMPLER2D(u_Normal3, 3);
// GBufferB - metallic, specular, roughness (register 4)
SAMPLER2D(u_GBufferB4, 4);
// GBufferC - base color (register 5)
SAMPLER2D(u_BaseColor5, 5);
// Depth (register 6)
SAMPLER2D(u_Depth6, 6);
#ifdef SSGI_COMPOSITE
// Environment diffuse: IBL_diffuse only, SSGI fallback (register 7)
SAMPLER2D(u_EnvDiffuse7, 7);
// SSGI upscaled result: rgb = bounce radiance, a = ambient visibility (register 9; stage 8 is reserved by BU_CLUSTERS_LIGHTGRID and silently dropped)
SAMPLER2D(u_SSGI9, 9);
#endif

// Render path parameters (names must match XML <parameter name="..."> with u_ prefix)
uniform hfloat u_SSRIntensity;
#ifdef SSGI_COMPOSITE
// Zone.ssgiIntensity via View::ApplySSGIParameters: lerp between probe-only ambient (0)
// and the full SSGI result (1); values above 1 extrapolate (contrast knob)
uniform hfloat u_SSGIIntensity;
#endif

#ifdef SSGI_COMPOSITE
// Deferred shading model ids (screen_pos.sh); SSGI applies only to the models whose
// indirect diffuse was split into EnvDiffuse, otherwise ambient would be added twice.
#define COMPOSITE_SHADINGMODELID_PBR_LIT 1.0
#endif

// UE BRDF.ush EnvBRDFApprox [Lazarov 2013], including the F90 = saturate(50 * F0.g)
// gate ("anything less than 2% is physically impossible and is considered shadowing").
// Note the deferred IBL path weights EnvSpecular with the UNITY_ENV_BRDF branch of
// DisneyBRDF.glsl instead; using the UE term for SSR is a deliberate choice (this SSR
// is a UE port), the mismatch at hit/miss transitions is small.
hvec3 SsrEnvBRDFApprox(hvec3 specularColor, hfloat roughness, hfloat NoV)
{
    hvec4 c0 = hvec4_init(-1.0, -0.0275, -0.572, 0.022);
    hvec4 c1 = hvec4_init(1.0, 0.0425, 1.04, -0.04);
    hvec4 r = roughness * c0 + c1;
    hfloat a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    hvec2 AB = hvec2_init(-1.04, 1.04) * a004 + hvec2_init(r.z, r.w);
    hfloat F90 = saturate(50.0 * specularColor.g);
    return specularColor * AB.x + F90 * AB.y;
}

void PS()
{
    hvec2 uv = vTexCoord;

    hvec3 sceneLighting = texture2D(u_SceneLighting0, uv).rgb;
    hvec3 envSpecular = texture2D(u_EnvSpecular1, uv).rgb;

    hvec4 ssrResult = texture2D(u_SSRBuffer2, uv);

    hfloat ssrAlpha = saturate(ssrResult.a * u_SSRIntensity);

    // SSR RGB is raw scene radiance while the EnvSpecular fallback already contains the
    // specular BRDF weighting from the deferred IBL path, so SSR must be weighted too or
    // it over-brightens dielectrics and loses F0 tinting on metals (UE does this in
    // ReflectionEnvironmentPixelShader.usf: Color.rgb *= EnvBRDF(SpecularColor, Roughness, NoV)).
    // Note: AO is applied to captures/IBL only, never to SSR — same as UE.
    hvec3 ssrRadiance = ssrResult.rgb;
    BRANCH
    if (ssrAlpha > 0.0)
    {
        hfloat depth = texture2D(u_Depth6, uv).r;
        hvec3 viewPos = ReconstructViewPos(uv, depth);
        hvec3 worldNormal = DecodeGBufferNormal(texture2D(u_Normal3, uv).rgb);
        hvec3 normal = normalize(mul(hvec4_init(worldNormal.x, worldNormal.y, worldNormal.z, 0.0), cView).xyz);
        hfloat NoV = saturate(dot(normal, -normalize(viewPos)));

        hvec4 gbufferB = texture2D(u_GBufferB4, uv);
        hvec3 baseColor = texture2D(u_BaseColor5, uv).rgb;
        // Same F0 derivation as PBRCommon.glsl DiffuseAndSpecularFromMetallicEx
        hvec3 specularColor = mix(0.08 * hvec3_init(gbufferB.g, gbufferB.g, gbufferB.g), baseColor, gbufferB.r);

        ssrRadiance *= SsrEnvBRDFApprox(specularColor, gbufferB.b, NoV);
    }

    // Pre-multiplied alpha composite: SSR RGB is already color * confidence.
    // env * (1 - alpha) + premultiplied_rgb * intensity
    hvec3 finalReflection = envSpecular * (1.0 - ssrAlpha) + ssrRadiance * u_SSRIntensity;

#ifdef SSGI_COMPOSITE
    // SSGI variant (SPLIT_ENV_DIFFUSE lighting): SceneLighting excludes IBL diffuse, which
    // arrives via EnvDiffuse. UE DiffuseIndirectComposite.usf semantics — the SSGI ambient
    // visibility (a) attenuates the IBL fallback and the bounce radiance is added weighted
    // by GBuffer DiffuseColor (= BaseColor * (1 - Metallic), UE GBuffer definition).
    hvec3 diffuseIndirect = texture2D(u_EnvDiffuse7, uv).rgb;

    hvec4 gbufferBFull = texture2D(u_GBufferB4, uv);
    hfloat shadingModelID = gbufferBFull.a * 255.0;
    bool ssgiModel = abs(shadingModelID - COMPOSITE_SHADINGMODELID_PBR_LIT) < 0.5;

    BRANCH
    if (ssgiModel)
    {
        hvec4 ssgi = texture2D(u_SSGI9, uv);
        hvec3 baseColorFull = texture2D(u_BaseColor5, uv).rgb;
        hvec3 gbufferDiffuseColor = baseColorFull * (1.0 - gbufferBFull.r);
        hvec3 ssgiResult = diffuseIndirect * saturate(ssgi.a) + ssgi.rgb * gbufferDiffuseColor;
        // Intensity knob: blend from the probe-only fallback towards the SSGI result.
        // Intensity > 1 extrapolates (2*ssgiResult - diffuseIndirect), which can go
        // negative when the probe ambient outweighs the bounce — clamp before the HDR add.
        diffuseIndirect = max(mix(diffuseIndirect, ssgiResult, u_SSGIIntensity), hvec3_init(0.0, 0.0, 0.0));
    }

    hvec3 finalColor = sceneLighting + finalReflection + diffuseIndirect;
#else
    // SSGI off: the lighting pass folded IBL diffuse back into SceneLighting
    // (no SPLIT_ENV_DIFFUSE), nothing extra to add here.
    hvec3 finalColor = sceneLighting + finalReflection;
#endif

    gl_FragColor = hvec4_init(finalColor.x, finalColor.y, finalColor.z, 1.0);
}

#endif
