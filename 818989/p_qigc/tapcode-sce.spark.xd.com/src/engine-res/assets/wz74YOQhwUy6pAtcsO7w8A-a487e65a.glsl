// SURFACE_SLOT_FEATURE_MACROS
#ifdef SURFACE_USES_NORMAL_MAP
    #ifndef NORMALMAP
        #define NORMALMAP
    #endif
#endif

#ifdef SURFACE_GENERIC_OUTLINE
    #define INSTANCED_STROKE_PARAMS
#endif
#include "varying_surface_pbr.def.sc"
#include "urho3d_compatibility.sh"
#include "SurfaceShaderCompatibility.sh"
#ifdef COMPILEVS
    #ifdef SURFACE_GENERIC_OUTLINE
        $input a_position, a_color0 _NORMAL _TEXCOORD0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    #else
        $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    #endif
    #ifdef PERPIXEL
        #ifdef SURFACE_GENERIC_OUTLINE
            $output vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _VOUTLINECOLOR, vOutlineParams _AOUV _VCLUSTERVS _VLIGHTMAPUV _VSCREENPOS /* SURFACE_SLOT_VARYING_LIST */
        #else
            $output vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV _VSCREENPOS /* SURFACE_SLOT_VARYING_LIST */
        #endif
    #else
        #ifdef SURFACE_GENERIC_OUTLINE
            $output vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _VOUTLINECOLOR, vOutlineParams _AOUV _VCLUSTERVS _VLIGHTMAPUV /* SURFACE_SLOT_VARYING_LIST */
        #else
            $output vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV /* SURFACE_SLOT_VARYING_LIST */
        #endif
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        #ifdef SURFACE_GENERIC_OUTLINE
            $input vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _VOUTLINECOLOR, vOutlineParams _AOUV _VCLUSTERVS _VLIGHTMAPUV _VSCREENPOS /* SURFACE_SLOT_VARYING_LIST */
        #else
            $input vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV _VSCREENPOS /* SURFACE_SLOT_VARYING_LIST */
        #endif
    #else
        #ifdef SURFACE_GENERIC_OUTLINE
            $input vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _VOUTLINECOLOR, vOutlineParams _AOUV _VCLUSTERVS _VLIGHTMAPUV /* SURFACE_SLOT_VARYING_LIST */
        #else
            $input vTexCoord _VTANGENT, vNormal, vWorldPos _VPAINTUV, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VCLUSTERVS _VLIGHTMAPUV /* SURFACE_SLOT_VARYING_LIST */
        #endif
    #endif
#endif

#ifdef PAINTABLE
#define PAINTABLE_UV_AVAILABLE 1
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "SurfaceGodotMatrices.sh"
#ifdef SURFACE_GENERIC_OUTLINE
    #include "SurfaceOutline.sh"
#endif
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#include "constants.sh"
#ifdef LIGHTMAP
    #include "LightMap.sh"
#endif
#if defined(COMPILEVS) && defined(CLUSTER_VS)
    #include "PBR/GI.sh"
    #include "Cluster/clusterlights.sh"
    #include "Cluster/clusters.sh"
#endif

#if COMPILEPS
    hfloat SurfaceGodotRawDepthFromLinear(hfloat linearDepth)
    {
        #if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
            hfloat clipZ = (cFarClipPS + cNearClipPS - (2.0 * cNearClipPS * cFarClipPS) / max(linearDepth, 0.0001)) / (cFarClipPS - cNearClipPS);
            return clipZ * 0.5 + 0.5;
        #else
            return (cFarClipPS - (cNearClipPS * cFarClipPS) / max(linearDepth, 0.0001)) / (cFarClipPS - cNearClipPS);
        #endif
    }
#endif

#if COMPILEPS && defined(SURFACE_USES_GODOT_PROJECTION)
    hfloat SurfaceGodotLinearDepth(hfloat rawDepth)
    {
        return LinearizeDepth(rawDepth, cNearClipPS, cFarClipPS);
    }

    hvec4 SurfaceGodotInvProjectionMul(hvec4 ndc)
    {
        hvec4 clipPos = ndc;
        #if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
            clipPos.z = clipPos.z * 2.0 - 1.0;
        #else
            clipPos.y = -clipPos.y;
        #endif
        hvec4 viewPos = mul(clipPos, cInvProj);
        hfloat linearDepth = SurfaceGodotLinearDepth(ndc.z);
        hfloat depthScale = linearDepth / max(abs(viewPos.z), 0.0001);
        viewPos.xyz *= depthScale;
        viewPos.z = -linearDepth;
        viewPos.w = 1.0;
        return viewPos;
    }

#endif

// SURFACE_SLOT_CUSTOM_DECLARATIONS
// Generated declarations use UrhoX-side names only. Godot-style built-ins are
// lowered before insertion, e.g. ALBEDO -> surfaceAlbedo and UV -> surfaceUV.

#if COMPILEPS
    #include "PBR/StandardPBR.sh"
    #include "SurfaceAlphaScissor.sh"

    uniform float u_Anisotropy;

    #define cAnisotropy u_Anisotropy
#endif

#if COMPILEPS && defined(SURFACE_USES_NORMAL_MAP)
    vec3 GetSurfaceWorldNormalFromMap(vec3 normalMap)
    {
        vec3 tangent = vTangent.xyz;
        vec3 bitangent = vec3(vTexCoord.zw, vTangent.w);
        mat3 tbn = TR(mat3(tangent, bitangent, vNormal));
        return normalize(mul(tbn, normalMap));
    }
#endif

void VS()
{
    #ifdef NOUV
        vec2 iTexCoord = vec2(0.0, 0.0);
    #endif
    hmat4 modelMatrix = iModelMatrix;

    hvec4 surfaceVertexPos = iPos;
    hvec3 surfaceVertexNormal = iNormal;
    #if defined(NORMALMAP) || defined(SURFACE_USES_TANGENT) || defined(DIRBILLBOARD)
        hvec4 surfaceVertexTangent = iTangent;
    #else
        hvec4 surfaceVertexTangent = hvec4_init(1.0, 0.0, 0.0, 1.0);
    #endif

    #ifndef SURFACE_WORLD_VERTEX_COORDS
        vec2 surfaceUV = GetTexCoord(iTexCoord);
        vec2 surfaceUV2 = vec2(0.0, 0.0);
        DECLARE_SURFACE_COLOR_INPUTS
        hvec3 surfacePosition = surfaceVertexPos.xyz;
        vec3 surfaceNormal = surfaceVertexNormal;
        vec3 surfaceTangent = surfaceVertexTangent.xyz;
        vec3 surfaceBinormal = cross(surfaceNormal, surfaceTangent) * surfaceVertexTangent.w;
        // SURFACE_SLOT_VERTEX_OBJECT_BODY
        surfaceVertexPos.xyz = surfacePosition;
        surfaceVertexNormal = surfaceNormal;
        surfaceVertexTangent.xyz = surfaceTangent;
    #endif

    // SURFACE_SLOT_VERTEX_VARYING_BODY

    #undef iPos
    #undef iNormal
    #undef iTangent
    #define iPos surfaceVertexPos
    #define iNormal surfaceVertexNormal
    #define iTangent surfaceVertexTangent

    hvec3 worldPos = GetWorldPos(modelMatrix);
    vNormal = GetWorldNormal(modelMatrix);

    vNormal *= cNormalOddNegativeScale;

    #ifdef SURFACE_WORLD_VERTEX_COORDS
        hvec3 surfacePosition = worldPos;
        vec3 surfaceNormal = vNormal;
        #if defined(NORMALMAP) || defined(SURFACE_USES_TANGENT) || defined(DIRBILLBOARD)
            vec4 surfaceWorldTangent = GetWorldTangent(modelMatrix);
        #else
            vec4 surfaceWorldTangent = vec4(1.0, 0.0, 0.0, 1.0);
        #endif
        vec3 surfaceTangent = surfaceWorldTangent.xyz;
        vec3 surfaceBinormal = cross(surfaceNormal, surfaceTangent) * surfaceWorldTangent.w;
        vec2 surfaceUV = GetTexCoord(iTexCoord);
        vec2 surfaceUV2 = vec2(0.0, 0.0);
        DECLARE_SURFACE_COLOR_INPUTS
        // SURFACE_SLOT_VERTEX_WORLD_BODY
        worldPos = surfacePosition;
        vNormal = normalize(surfaceNormal);
        surfaceWorldTangent.xyz = normalize(surfaceTangent);
    #endif

    #ifdef SURFACE_GENERIC_OUTLINE
        worldPos = ExpandSurfaceOutline(worldPos, vNormal, modelMatrix);
    #endif

    gl_Position = GetClipPos(worldPos);
    #ifdef SURFACE_GENERIC_OUTLINE
        gl_Position.z += SurfaceOutlineZBias(gl_Position);
    #endif
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    #if defined(SURFACE_USES_SCREENPOS) || !defined(PERPIXEL)
        vScreenPos = GetScreenPos(gl_Position);
    #endif

    #ifdef SURFACE_USES_COLOR
        vColor = surfaceColor;
    #elif defined(VERTEXCOLOR)
        vColor = iColor;
    #endif
    #ifdef SURFACE_GENERIC_OUTLINE
        hvec4 outlineColor = GetSurfaceOutlineColor();
        vOutlineColor = vec4(outlineColor.rgb, 1.0);
        vOutlineParams = vec2(outlineColor.a, iSurfaceOutlineBrightness);
    #endif

    #if defined(NORMALMAP) || defined(SURFACE_USES_NORMAL_MAP) || defined(SURFACE_USES_FRAGMENT_TANGENT) || defined(DIRBILLBOARD)
        #ifdef SURFACE_WORLD_VERTEX_COORDS
            vec4 tangent = surfaceWorldTangent;
        #else
            vec4 tangent = GetWorldTangent(modelMatrix);
        #endif
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w * cBitangentOddNegativeScale;
        vTexCoord = vec4(GetTexCoord(iTexCoord), bitangent.xy);
        vTangent = vec4(tangent.xyz, bitangent.z);
    #else
        vTexCoord.xy = GetTexCoord(iTexCoord);
    #endif

    #ifdef PAINTABLE
        vPaintUV = iTexCoord1.xy;
    #endif

    #if defined(AO)
        #if defined(SSAO)
            vAOUV = GetSSAOTexCoord(gl_Position);
        #else
            vAOUV = iTexCoord1.xy;
        #endif
    #endif

    #if defined(LIGHTMAP)
        #if defined(SPEED_GRASS) || defined(SCE_GRASS)
            vLightMapUV = GetTileLightMapUV(vWorldPos.xy - cTerrainOffset, vec2(256.0, 256.0));
        #else
            vLightMapUV = GetLightMapUV(iTexCoord1.xy);
        #endif
    #endif

    #ifdef PERPIXEL
        // Per-pixel forward lighting
        vec4 projWorldPos = vec4(worldPos, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            GetShadowPos(projWorldPos, vNormal, vShadowPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = mul(projWorldPos, cLightMatrices[0]);
        #endif

        #ifdef POINTLIGHT
            vCubeMaskVec = mul((worldPos - cLightPos.xyz), mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz));
        #endif
    #else
        // Ambient & per-vertex lighting
        #if defined(LIGHTMAP) || defined(AO)
            // If using lightmap, disregard zone ambient light
            // If using AO, calculate ambient in the PS
            vVertexLight = vec3(0.0, 0.0, 0.0);
            vTexCoord2 = iTexCoord1;
        #else
            vVertexLight = GetAmbient(GetZonePos(worldPos));
        #endif

        #ifdef NUMVERTEXLIGHTS
            for (int i = 0; i < NUMVERTEXLIGHTS; ++i)
                vVertexLight += GetVertexLight(i, worldPos, vNormal) * cVertexLights[i * 3].rgb;
        #endif
        #ifdef ENVCUBEMAP
            vReflectionVec = worldPos - cCameraPos;
        #endif
    #endif

    #undef iPos
    #undef iNormal
    #undef iTangent
    #define iPos a_position
    #define iNormal a_normal
    #define iTangent a_tangent
}

void PS()
{
    // Surface material defaults. Generated fragment code owns all texture sampling and material output mapping.
    // Godot-style material outputs are lowered to UrhoX-side surface* variables
    // before this slot is inserted.
    vec3 surfaceAlbedo = vec3(1.0, 1.0, 1.0);
    float surfaceAlpha = 1.0;
    float surfaceAlphaScissorThreshold = 0.0;
    float surfaceRoughness = 1.0;
    float surfaceMetallic = 0.0;
    float surfaceOcclusion = 1.0;
    float surfaceSpecular = 0.5;
    float surfaceToonAreaType = 0.0;
    float surfaceSoftness = 0.0;
    vec3 surfaceBacklight = vec3(0.0, 0.0, 0.0);
    #ifdef CLEAR_COAT
        float surfaceClearCoat = 0.0;
        float surfaceClearCoatRoughness = 0.0;
    #endif
    vec3 surfaceNormal = normalize(vNormal);
    #ifdef SURFACE_USES_FRAGMENT_TANGENT
        vec3 surfaceTangent = normalize(vTangent.xyz);
        vec3 surfaceBinormal = -normalize(vec3(vTexCoord.zw, vTangent.w));
    #endif
    vec3 surfaceEmission = vec3(0.0, 0.0, 0.0);
    vec2 surfaceUV = vTexCoord.xy;
    vec2 surfaceUV2 = vec2(0.0, 0.0);
    #ifdef SURFACE_USES_SCREENPOS
        hvec2 surfaceScreenUV = vScreenPos.xy / vScreenPos.w;
        hvec4 surfaceFragCoord = hvec4_init(0.0, 0.0, 0.0, 0.0);
        surfaceFragCoord.xy = gl_FragCoord.xy;
        surfaceFragCoord.z = SurfaceGodotRawDepthFromLinear(vScreenPos.w);
        surfaceFragCoord.w = 1.0 / max(vScreenPos.w, 0.0001);
    #endif
    hvec2 surfaceViewportSize = hvec2_init(1.0, 1.0) / cGBufferInvSize;
    hmat4 surfaceGodotInvProjectionMatrix = cInvProj;
    hmat4 modelMatrix = cModel;
    #ifdef SURFACE_USES_COLOR
        vec4 surfaceColor = vColor;
    #endif
    hvec3 surfacePosition = vWorldPos.xyz;
    hvec3 surfaceViewDir = normalize(cCameraPosPS - surfacePosition);
    #ifdef SURFACE_USES_NORMAL_MAP
        vec3 surfaceNormalMap = vec3(0.5, 0.5, 1.0);
    #endif
    // SURFACE_SLOT_FRAGMENT_MATERIAL_BODY
    SurfaceAlphaScissor(surfaceAlpha, surfaceAlphaScissorThreshold);
    #if defined(SURFACE_DEPTH_ONLY)
        gl_FragColor = vec4_splat(1.0);
        return;
    #elif defined(SURFACE_SHADOW_ONLY)
        #ifdef VSM_SHADOW
            float shadowDepth = gl_FragCoord.z;
            gl_FragColor = vec4(shadowDepth, shadowDepth * shadowDepth, 1.0, 1.0);
        #else
            gl_FragColor = vec4_splat(1.0);
        #endif
        return;
    #endif
    #ifdef SURFACE_USES_NORMAL_MAP
        surfaceNormal = GetSurfaceWorldNormalFromMap(surfaceNormalMap * 2.0 - 1.0);
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    vec4 shadowColor = vec4(1.0, 1.0, 1.0, 1.0);

    // Get shadow
    #ifdef SHADOW
        shadowColor.rgb = shadowColor.rgb * GetShadow(vShadowPos, vWorldPos.w);
    #endif

    #if defined(MATERIALBAKE)
        EncodeGBufferBake(surfaceAlbedo, surfaceAlpha, surfaceRoughness, surfaceMetallic, surfaceOcclusion, surfaceNormal, surfaceEmission);
    #elif defined(DEFERRED)
        #ifdef SURFACE_GENERIC_OUTLINE
            EncodeGBufferUnlit(MixSurfaceOutlineColor(surfaceAlbedo, vOutlineColor.rgb, vOutlineParams.x, vOutlineParams.y), surfaceNormal);
        #endif
    #elif defined(SURFACE_GENERIC_OUTLINE)
        vec3 finalColor = MixSurfaceOutlineColor(surfaceAlbedo, vOutlineColor.rgb, vOutlineParams.x, vOutlineParams.y);
        finalColor = GetFog(finalColor, fogFactor);
        gl_FragColor = vec4(finalColor, surfaceAlpha);
        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
            gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
        #endif
    #else
        // Godot light() is forward-only; SurfaceShaderCodegen does not generate deferred/material passes.
        vec3 finalColor = vec3(0.0, 0.0, 0.0);
        vec3 directDiffuseColor = surfaceAlbedo;
        float directOneMinusReflectivity = 1.0;
        vec3 directSpecularColor = vec3(surfaceSpecular, surfaceSpecular, surfaceSpecular);
        directDiffuseColor = DiffuseAndSpecularFromMetallicEx(
            directDiffuseColor, surfaceMetallic, directSpecularColor, directOneMinusReflectivity);
        float directPerceptualRoughness = surfaceRoughness;
        float directRoughness = PerceptualRoughnessToRoughness(directPerceptualRoughness);
        float directNdotV = clamp(dot(surfaceNormal, surfaceViewDir), 0.0, 1.0);

        vec3 surfaceLightDir = vec3(0.0, 0.0, 1.0);
        vec3 surfaceLightColor = vec3(0.0, 0.0, 0.0);
        bool surfaceLightIsDirectional = false;
        float surfaceAttenuation = 0.0;
        float surfaceSpecularAmount = surfaceSpecular;
        vec3 surfaceDiffuseLight = vec3(0.0, 0.0, 0.0);
        vec3 surfaceSpecularLight = vec3(0.0, 0.0, 0.0);

        #if defined(PERPIXEL)
            hvec3 lightColor;
            vec3 lightDirection;
            hfloat attenuation;

            #if (defined(DIRLIGHT) && !defined(CLUSTER_BASE)) || !defined(CLUSTER)
                lightColor = GI_GetLightColor();
                attenuation = GI_GetAttenAndLightDir(surfacePosition, lightDirection);
                surfaceLightDir = lightDirection;
                surfaceLightColor = lightColor;
                #ifdef DIRLIGHT
                    surfaceLightIsDirectional = true;
                #else
                    surfaceLightIsDirectional = false;
                #endif
                surfaceAttenuation = attenuation * shadowColor.r;
                surfaceDiffuseLight = vec3(0.0, 0.0, 0.0);
                surfaceSpecularLight = vec3(0.0, 0.0, 0.0);
                // SURFACE_SLOT_LIGHT_BODY
                finalColor += surfaceDiffuseLight + surfaceSpecularLight;
            #endif

            #if defined(CLUSTER)
                #ifdef CLUSTER_VS
                    // CLUSTER_VS is an approximation path; Godot light() needs per-light execution.
                #else
                    hvec4 realCoord = getRealCoord(gl_FragCoord);
                    uint cluster = getClusterIndex(realCoord);
                    LightGrid grid = getLightGrid(cluster);
                    LOOP
                    for (uint i = 0u; i < grid.pointLights; ++i)
                    {
                        uint lightIndex = GetGridLightIndex(grid.offset, i);
                        #ifdef CLUSTER_SPOTLIGHT
                            SpotLight light = GetSpotLight(lightIndex);
                        #else
                            PointLight light = GetPointLight(lightIndex);
                        #endif

                        lightColor = light.intensity;
                        attenuation = GI_PointLight_GetAttenAndLightDir(surfacePosition, light.position, light.range, lightDirection);
                        #ifdef CLUSTER_SPOTLIGHT
                            attenuation *= GetLightDirectionFalloff(
                                lightDirection, light.direction, light.cosOuterCone, light.invCosConeDiff);
                        #endif

                        surfaceLightDir = lightDirection;
                        surfaceLightColor = lightColor;
                        surfaceLightIsDirectional = false;
                        surfaceAttenuation = attenuation;
                        surfaceDiffuseLight = vec3(0.0, 0.0, 0.0);
                        surfaceSpecularLight = vec3(0.0, 0.0, 0.0);
                        // SURFACE_SLOT_LIGHT_BODY
                        finalColor += surfaceDiffuseLight + surfaceSpecularLight;
                    }
                #endif
            #endif
        #endif

        #if defined(AMBIENT)
            #if defined(AO) && !defined(CLOSE_AO)
                #if defined(SSAO)
                    #if !BGFX_SHADER_LANGUAGE_GLSL
                        surfaceOcclusion = surfaceOcclusion * texture2D(sAOMap, vAOUV / gl_FragCoord.w * 0.5 + 0.5).r;
                    #else
                        surfaceOcclusion = surfaceOcclusion * texture2D(sAOMap, vAOUV * gl_FragCoord.w * 0.5 + 0.5).r;
                    #endif
                #else
                    surfaceOcclusion = surfaceOcclusion * texture2D(sAOMap, vAOUV).r;
                #endif
            #endif

            vec3 indirectDiffuse;
            vec3 indirectSpecular;
            GI_Indirect(surfaceNormal, surfaceViewDir, directPerceptualRoughness, surfaceOcclusion, indirectDiffuse, indirectSpecular);
            indirectDiffuse *= directDiffuseColor;

            #if UNITY_ENV_BRDF
                float surfaceReduction = 1.0 / (directRoughness * directRoughness + 1.0);
                float grazingTerm = clamp(1.0 - directPerceptualRoughness + (1.0 - directOneMinusReflectivity), 0.0, sce_EnvFresnelEdgeStrength);
                indirectSpecular = indirectSpecular * surfaceReduction * FresnelLerp(directSpecularColor, vec3_splat(grazingTerm), directNdotV);
            #else
                indirectSpecular = indirectSpecular * EnvBRDFApprox(directSpecularColor, directPerceptualRoughness, directNdotV);
            #endif

            #ifdef CLEAR_COAT
                APPLY_CLEAR_COAT_IBL(indirectDiffuse, indirectSpecular, surfaceNormal, surfaceViewDir, surfaceOcclusion, surfaceClearCoat, surfaceClearCoatRoughness);
            #endif
            finalColor += indirectDiffuse + indirectSpecular;
        #endif

        // Add emissive color
        #ifdef AMBIENT
            finalColor += surfaceEmission;
        #endif

        // Mix final color and fog
        finalColor = GetFog(finalColor, fogFactor);

        // Final color
        gl_FragColor = vec4(finalColor, surfaceAlpha);

        // Gamma in shadering
        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
            gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
        #endif
    #endif
}
