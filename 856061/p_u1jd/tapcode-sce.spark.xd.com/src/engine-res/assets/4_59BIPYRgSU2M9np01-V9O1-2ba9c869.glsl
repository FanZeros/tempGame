// SURFACE_SLOT_FEATURE_MACROS
#ifdef SURFACE_USES_NORMAL_MAP
    #ifndef NORMALMAP
        #define NORMALMAP
    #endif
#endif

#include "varying_surface_depth.def.sc"
#include "urho3d_compatibility.sh"
#include "SurfaceShaderCompatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA2 _INSTANCED_EXTRA3
    $output vTexCoord /* SURFACE_SLOT_VARYING_LIST */
#endif
#ifdef COMPILEPS
    $input vTexCoord /* SURFACE_SLOT_VARYING_LIST */
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "SurfaceGodotMatrices.sh"
#include "constants.sh"

// SURFACE_SLOT_CUSTOM_DECLARATIONS
// Vertex-only auxiliary template for the "depth" pass: replays the
// SurfacePBR.glsl vertex() prologue so vertex-animated surface shaders write
// a Pre-Z position that matches the animated color-pass geometry instead of
// the fixed Depth.glsl (which knows nothing about SurfaceShader vertex()).

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

    gl_Position = GetClipPos(worldPos);
    vTexCoord = vec3(GetTexCoord(iTexCoord), GetDepth(gl_Position));

    #undef iPos
    #undef iNormal
    #undef iTangent
    #define iPos a_position
    #define iNormal a_normal
    #define iTangent a_tangent
}

void PS()
{
    gl_FragColor = vec4(EncodeDepth(vTexCoord.z), 1.0);
}
