#include "varying_deferred.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos, vFarRay _VNEARRAY
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos, vFarRay _VNEARRAY
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#include "constants.sh"
SAMPLER2D(u_GBuffer0, 0);
SAMPLER2D(u_GBuffer1, 1);
SAMPLER2D(u_GBuffer2, 2);
SAMPLER2D(u_GBuffer3, 3);
SAMPLER2D(u_GBuffer4, 4);
#ifdef LIGHTMAP
#include "LightMap.sh"
#endif
#ifdef COMPILEPS
// 延迟运行时分发：同一编译产物按 GBuffer shading model ID 选择 PBR、Toon 或 Toon Outline。
#include "PBR/StandardPBR.sh"
#include "Toon/ToonLighting.sh"
#include "lambert.sh"
#include "Voxel/VoxelShadowVolume.sh"
#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    #ifdef DIRLIGHT
        vScreenPos = GetScreenPosPreDiv(gl_Position);
        vFarRay = GetFarRay(gl_Position);
        #ifdef ORTHO
            vNearRay = GetNearRay(gl_Position);
        #endif
    #else
        vScreenPos = GetScreenPos(gl_Position);
        vFarRay = GetFarRay(gl_Position) * gl_Position.w;
        #ifdef ORTHO
            vNearRay = GetNearRay(gl_Position) * gl_Position.w;
        #endif
    #endif
}

void PS()
{
    // If rendering a directional light quad, optimize out the w divide
    hfloat sourceDepth = texture2D(u_GBuffer4, vScreenPos).r;
    hfloat depth = ReconstructDepth(sourceDepth);
    #ifdef ORTHO
        hvec3 worldPos = mix(vNearRay, vFarRay, depth);
    #else
        hvec3 worldPos = vFarRay * depth;
    #endif
    vec4 encodedNormalArea = texture2D(u_GBuffer0, vScreenPos);
    vec3 normalDirection = normalize(DecodeNormal(encodedNormalArea.rgb));
    vec4 metallicSpecularRoughnessID = texture2D(u_GBuffer1, vScreenPos);
    vec4 baseColor = texture2D(u_GBuffer2, vScreenPos);
    vec3 emissiveColor = texture2D(u_GBuffer3, vScreenPos).rgb;

    // Position acquired via near/far ray is relative to camera. Bring position to world space
    hvec3 eyeVec = -worldPos;
    worldPos += cCameraPosPS;

    hvec4 projWorldPos = hvec4_init(worldPos, 1.0);

    #ifdef SHADOW
        float shadow = GetShadowDeferred(projWorldPos, normalDirection, depth);
    #else
        float shadow = 1.0;
    #endif

    #if defined(VOXEL_SHADOW_VOLUME) && defined(DIRLIGHT)
        shadow = min(shadow, GetVoxelShadowVolumeVisibility(worldPos.xyz, normalDirection, cLightDirPS));
    #endif

    vec3 viewDirection = normalize(eyeVec);
    uint shadingModelID = uint(round(metallicSpecularRoughnessID.a * 255.0));
    vec2 screenUV = vScreenPos.xy;
#ifndef DIRLIGHT
    screenUV /= max(vScreenPos.w, 0.0001);
#endif
#ifdef SPLIT_LIGHTING
    // ========================================
    // Split output mode: Output to three RenderTargets
    // Used by reflection hierarchy system (SSR replaces env specular, SSGI replaces env diffuse)
    // ========================================
    vec3 sceneLighting = emissiveColor;  // Emissive goes into scene lighting
    vec3 envSpecular = vec3(0.0, 0.0, 0.0);
    vec3 envDiffuse = vec3(0.0, 0.0, 0.0);

    switch (shadingModelID)
    {
        case SHADINGMODELID_TOON_LIT:
        {
            vec3 sceneLit, envSpec;
            MetallicToonPBR_Split(
                GetZoneToonSurfaceParams(),
                baseColor.rgb,
                metallicSpecularRoughnessID.r,
                metallicSpecularRoughnessID.g,
                metallicSpecularRoughnessID.b,
                worldPos,
                normalDirection,
                normalDirection,
                viewDirection,
                vec3(shadow, shadow, shadow),
                1.0,
                round(encodedNormalArea.a * 3.0), // toonAreaType
                baseColor.a, // toonSoftness
                screenUV,
                // Depth Rim 的深度比较必须与偏移采样点同为线性视空间单位，
                // 不能传 ReconstructDepth 的 0~1 归一化值
                LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
#ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
#endif
                , sceneLit,
                envSpec
            );
            sceneLighting += sceneLit;
            envSpecular = envSpec;
            break;
        }

        case SHADINGMODELID_TOON_OUTLINE:
        {
            vec3 sceneLit;
            MetallicToonOutline_Split(
                GetZoneToonSurfaceParams(),
                baseColor.rgb,
                worldPos,
                normalDirection,
                normalDirection,
                viewDirection,
                vec3(shadow, shadow, shadow),
                1.0,
                round(encodedNormalArea.a * 3.0), // toonAreaType
                baseColor.a, // toonSoftness
                metallicSpecularRoughnessID.g
#ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
#endif
                , sceneLit
            );
            sceneLighting += sceneLit;
            break;
        }

        case SHADINGMODELID_PBR_LIT:
        {
            vec3 sceneLit, envSpec, envDiff;
            MetallicPBR_Split(
                baseColor.rgb,
                metallicSpecularRoughnessID.r,  // metallic
                metallicSpecularRoughnessID.g,  // specular
                metallicSpecularRoughnessID.b,  // roughness
                worldPos,
                normalDirection,
                viewDirection,
                vec3(shadow, shadow, shadow),
                1.0  // occlusion
#ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
#endif
                , sceneLit  // out: direct_diffuse + direct_specular
                , envSpec   // out: IBL_specular only
                , envDiff   // out: IBL_diffuse only
            );
            sceneLighting += sceneLit;
            envSpecular = envSpec;
            envDiffuse = envDiff;
            break;
        }

        case SHADINGMODELID_LAMBERT_LIT:
        {
            // Lambert has no specular reflection, all goes into scene lighting.
            // Note: Lambert ambient is NOT split into EnvDiffuse — the SSGI composite
            // must skip non-PBR/TOON shading models or Lambert would get double ambient.
            sceneLighting += LambertBRDF(
                baseColor.rgb,
                vec4(metallicSpecularRoughnessID.rgb, baseColor.a * 255.0),
                worldPos,
                normalDirection,
                vec3(shadow, shadow, shadow),
                1.0
#ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
#endif
            );
            break;
        }
    }

    // MRT output for reflection hierarchy system
    // RT0: Resolved scene lighting + emissive
    // RT1: Env specular = IBL_specular only (SSR replaces this when available)
    // SPLIT_ENV_DIFFUSE (SSGI on): RT2 = PBR IBL_diffuse only (SSGI replaces it in composite).
    // Without it (SSGI off) the diffuse folds back into RT0 — saves the extra RT
    // bandwidth/allocation on the disabled path.
#ifdef SPLIT_ENV_DIFFUSE
    gl_FragData[0] = vec4(sceneLighting, 1.0);
    gl_FragData[1] = vec4(envSpecular, 1.0);
    gl_FragData[2] = vec4(envDiffuse, 1.0);
#else
    gl_FragData[0] = vec4(sceneLighting + envDiffuse, 1.0);
    gl_FragData[1] = vec4(envSpecular, 1.0);
#endif

#else
    // ========================================
    // Traditional mode: Single output (backward compatible)
    // ========================================
    gl_FragColor = vec4(emissiveColor, 1.0);

    switch (shadingModelID)
    {
        case SHADINGMODELID_TOON_LIT:
            gl_FragColor.rgb += MetallicToonPBR(GetZoneToonSurfaceParams(), baseColor.rgb,
                metallicSpecularRoughnessID.r, metallicSpecularRoughnessID.g,
                metallicSpecularRoughnessID.b, worldPos, normalDirection, normalDirection, viewDirection,
                vec3(shadow, shadow, shadow), 1.0, round(encodedNormalArea.a * 3.0), baseColor.a
                // 线性视空间深度，与 Depth Rim 偏移采样点同单位
                , screenUV, LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
            #ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
            #endif
            );
            break;

        case SHADINGMODELID_TOON_OUTLINE:
            gl_FragColor.rgb += MetallicToonOutline(GetZoneToonSurfaceParams(), baseColor.rgb,
                worldPos, normalDirection, normalDirection, viewDirection,
                vec3(shadow, shadow, shadow), 1.0, round(encodedNormalArea.a * 3.0), baseColor.a,
                metallicSpecularRoughnessID.g
            #ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
            #endif
            );
            break;

        case SHADINGMODELID_PBR_LIT:
            gl_FragColor.rgb += MetallicPBR(baseColor.rgb, metallicSpecularRoughnessID.r, metallicSpecularRoughnessID.g, metallicSpecularRoughnessID.b, worldPos, normalDirection, viewDirection, vec3(shadow, shadow, shadow), 1.0
            #ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
            #endif
            );
            break;

        case SHADINGMODELID_LAMBERT_LIT:
            gl_FragColor.rgb += LambertBRDF(baseColor.rgb, vec4(metallicSpecularRoughnessID.rgb, baseColor.a * 255.0), worldPos, normalDirection, vec3(shadow, shadow, shadow), 1.0
            #ifdef DEFERRED_CLUSTER
                , LinearizeDepth(sourceDepth, cNearClipPS, cFarClipPS)
            #endif
            );
            break;
    }
#endif // SPLIT_LIGHTING
}
