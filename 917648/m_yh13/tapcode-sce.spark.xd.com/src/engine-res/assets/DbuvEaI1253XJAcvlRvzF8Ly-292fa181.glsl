// SURFACE_SLOT_FEATURE_MACROS
#ifdef SURFACE_USES_NORMAL_MAP
    #ifndef NORMALMAP
        #define NORMALMAP
    #endif
#endif

#define VELOCITY_PASS
#define INSTANCED_STROKE_PARAMS

#include "varying_surface_velocity.def.sc"
#include "urho3d_compatibility.sh"
#include "SurfaceShaderCompatibility.sh"
#ifdef COMPILEVS
    $input a_position, a_color0 _NORMAL _TEXCOORD0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    $output vTexCoord, vCurrClip, vPrevClip _VCOLOR /* SURFACE_SLOT_VARYING_LIST */
#endif
#ifdef COMPILEPS
    $input vTexCoord, vCurrClip, vPrevClip _VCOLOR /* SURFACE_SLOT_VARYING_LIST */
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "SurfaceGodotMatrices.sh"
#include "SurfaceOutline.sh"
#include "SurfaceAlphaScissor.sh"
#include "constants.sh"

uniform hmat4 u_UnjitteredViewProj;
uniform hmat4 u_PrevViewProj;
uniform hmat4 u_PrevModel;

// Keep this vertex-stage scaffold aligned with the main Surface templates:
// custom vertex() order, object/world-space paths, skinning, inputs, and varyings.
// SURFACE_SLOT_CUSTOM_DECLARATIONS

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

    hvec3 surfaceOriginalWorldPos = GetWorldPos(modelMatrix);
    hvec3 bodyWorldPos = surfaceOriginalWorldPos;
    hvec3 bodyWorldNormal = GetWorldNormal(modelMatrix) * cNormalOddNegativeScale;

    #ifdef SURFACE_WORLD_VERTEX_COORDS
        hvec3 surfacePosition = bodyWorldPos;
        vec3 surfaceNormal = bodyWorldNormal;
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
        bodyWorldPos = surfacePosition;
        bodyWorldNormal = normalize(surfaceNormal);
    #endif

    #ifdef SURFACE_USES_COLOR
        vColor = surfaceColor;
    #elif defined(VERTEXCOLOR)
        vColor = iColor;
    #endif

    hvec3 currentOutlineWorldPos = ExpandSurfaceOutline(bodyWorldPos, bodyWorldNormal, modelMatrix);

    hvec3 surfaceVertexOffset = bodyWorldPos - surfaceOriginalWorldPos;
    hvec4 previousVertexPos = surfaceVertexPos;
    #if defined(SKIN_MATRIX_TEXTURE)
        hmat4 prevM = TR(GetSkinMatrixFromPrevTexture(iBlendWeights, iBlendIndices));
    #else
        hmat4 prevM = u_PrevModel;
    #endif
    hvec3 previousBodyWorldPos = mul(previousVertexPos, prevM).xyz + surfaceVertexOffset;
    #ifdef SURFACE_WORLD_VERTEX_COORDS
        hvec3 previousBodyWorldNormal = bodyWorldNormal;
    #else
        hvec3 previousBodyWorldNormal = normalize(mul(hvec4_init(surfaceVertexNormal, 0.0), prevM).xyz)
            * cNormalOddNegativeScale;
    #endif
    // Previous-frame material state is unavailable. Reuse the current custom
    // vertex offset and outline parameters; model, skin, and camera history remain exact.
    // TIME, animated uniforms/textures, and outline-parameter changes are approximated.
    hvec3 previousOutlineWorldPos = ExpandSurfaceOutline(previousBodyWorldPos, previousBodyWorldNormal, prevM);

    #undef iPos
    #undef iNormal
    #undef iTangent
    #define iPos a_position
    #define iNormal a_normal
    #define iTangent a_tangent

    gl_Position = GetClipPos(currentOutlineWorldPos);
    gl_Position.z += SurfaceOutlineZBias(gl_Position);
    vCurrClip = mul(hvec4_init(currentOutlineWorldPos, 1.0), u_UnjitteredViewProj);
    vPrevClip = mul(hvec4_init(previousOutlineWorldPos, 1.0), u_PrevViewProj);
    vTexCoord = GetTexCoord(iTexCoord);
}

void PS()
{
    vec3 surfaceAlbedo = vec3(1.0, 1.0, 1.0);
    float surfaceAlpha = 1.0;
    float surfaceAlphaScissorThreshold = 0.0;
    float surfaceDitherOpacity = 1.0;
    float surfaceRoughness = 1.0;
    float surfaceMetallic = 0.0;
    float surfaceOcclusion = 1.0;
    float surfaceSpecular = 0.5;
    float surfaceToonAreaType = 0.0;
    float surfaceSoftness = 0.0;
    vec3 surfaceEmission = vec3(0.0, 0.0, 0.0);
    #ifdef SURFACE_USES_NORMAL_MAP
        vec3 surfaceNormalMap = vec3(0.5, 0.5, 1.0);
    #endif
    vec2 surfaceUV = vTexCoord.xy;
    vec2 surfaceUV2 = vec2(0.0, 0.0);
    #ifdef SURFACE_USES_COLOR
        vec4 surfaceColor = vColor;
    #endif
    // SURFACE_SLOT_FRAGMENT_MATERIAL_BODY
    // 与本体一致：镂空处不写运动向量，避免 TAA 在洞边拉残影。
    SurfaceAlphaScissor(surfaceAlpha, surfaceAlphaScissorThreshold);

    hvec2 currNDC = vCurrClip.xy / max(vCurrClip.w, 1e-6);
    hvec2 prevNDC = vPrevClip.xy / max(vPrevClip.w, 1e-6);
    hvec2 currUV = currNDC * 0.5 + 0.5;
    hvec2 prevUV = prevNDC * 0.5 + 0.5;

    #if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
        currUV.y = 1.0 - currUV.y;
        prevUV.y = 1.0 - prevUV.y;
    #endif

    hvec2 motion = clamp(currUV - prevUV, vec2_splat(-0.5), vec2_splat(0.5));
    gl_FragColor = hvec4_init(motion.x, motion.y, 0.0, 1.0);
}
