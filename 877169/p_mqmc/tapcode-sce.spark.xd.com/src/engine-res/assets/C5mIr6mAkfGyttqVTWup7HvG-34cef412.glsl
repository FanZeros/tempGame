// SURFACE_SLOT_FEATURE_MACROS
#ifdef SURFACE_USES_NORMAL_MAP
    #ifndef NORMALMAP
        #define NORMALMAP
    #endif
#endif

#define VELOCITY_PASS

#include "varying_surface_velocity.def.sc"
#include "urho3d_compatibility.sh"
#include "SurfaceShaderCompatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    $output vTexCoord, vCurrClip, vPrevClip /* SURFACE_SLOT_VARYING_LIST */
#endif
#ifdef COMPILEPS
    $input vTexCoord, vCurrClip, vPrevClip /* SURFACE_SLOT_VARYING_LIST */
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "SurfaceGodotMatrices.sh"
#include "constants.sh"

// Unjittered matrices (ApplyMotionVectorParameters); rigid prev model (Batch::Prepare velocity).
uniform hmat4 u_UnjitteredViewProj;
uniform hmat4 u_PrevViewProj;
uniform hmat4 u_PrevModel;

// SURFACE_SLOT_CUSTOM_DECLARATIONS
// Vertex-only auxiliary template for the "velocity" pass: same vertex()
// replay as SurfaceDepth.glsl. The vertex()-driven offset (animated minus
// unanimated world position) is reapplied to the previous-frame position
// as a rigid approximation, so per-frame procedural motion itself does not
// show up in the vector — only the object's rigid/skinned motion does, same
// limitation as the fixed ScreenSpace/MotionVector/Velocity.glsl this
// replaces.

void VS()
{
    #ifdef NOUV
        vec2 iTexCoord = vec2(0.0, 0.0);
    #endif
    hmat4 modelMatrix = iModelMatrix;

    hvec3 surfaceOriginalWorldPos = GetWorldPos(modelMatrix);

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

    #ifdef SURFACE_WORLD_VERTEX_COORDS
        hvec3 surfacePosition = worldPos;
        vec3 surfaceNormal = GetWorldNormal(modelMatrix);
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
    #endif

    #undef iPos
    #undef iNormal
    #undef iTangent
    #define iPos a_position
    #define iNormal a_normal
    #define iTangent a_tangent

    hvec3 surfaceVertexOffset = worldPos - surfaceOriginalWorldPos;

    gl_Position = GetClipPos(worldPos);

    #if defined(SKIN_MATRIX_TEXTURE)
        hmat4 prevM = TR(GetSkinMatrixFromPrevTexture(iBlendWeights, iBlendIndices));
        hvec3 prevWorldPos = mul(iPos, prevM).xyz + surfaceVertexOffset;
    #else
        hmat4 prevM = u_PrevModel;
        hvec3 prevWorldPos = mul(iPos, prevM).xyz + surfaceVertexOffset;
    #endif

    vCurrClip = mul(hvec4_init(worldPos, 1.0), u_UnjitteredViewProj);
    vPrevClip = mul(hvec4_init(prevWorldPos, 1.0), u_PrevViewProj);
    vTexCoord = GetTexCoord(iTexCoord);
}

void PS()
{
    hvec2 currNDC = vCurrClip.xy / max(vCurrClip.w, 1e-6);
    hvec2 prevNDC = vPrevClip.xy / max(vPrevClip.w, 1e-6);
    hvec2 currUV = currNDC * 0.5 + 0.5;
    hvec2 prevUV = prevNDC * 0.5 + 0.5;

    // D3D：clip.y 与 UV.y 方向相反（与 MotionVector.glsl / Velocity.glsl 一致）
    #if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
        currUV.y = 1.0 - currUV.y;
        prevUV.y = 1.0 - prevUV.y;
    #endif

    hvec2 motion = clamp(currUV - prevUV, vec2_splat(-0.5), vec2_splat(0.5));
    gl_FragColor = hvec4_init(motion.x, motion.y, 0.0, 1.0);
}
