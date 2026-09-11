#ifndef __URHO3D_COMPATIBILITY_SH__
#define __URHO3D_COMPATIBILITY_SH__

// VOXELPACKED: the packed voxel vertex has no normal stream — the face index rides
// a_position.w and transform.sh decodes it into iNormal, so a_normal must not be declared.
#if !defined(BILLBOARD) && !defined(TRAILFACECAM) && !defined(BASIC) && !defined(VOXELPACKED)
#define _NORMAL , a_normal
#elif defined(BASIC) && (defined(DIRBILLBOARD) || defined(TRAILBONE))
#define _NORMAL , a_normal
#else
#define _NORMAL
#endif

#if !defined(NOUV) && !defined(BASIC)
#define _TEXCOORD0 , a_texcoord0
#define _VTEXCOORD , vTexCoord
#elif defined(BASIC) && (defined(DIFFMAP) || defined(ALPHAMAP))
#define _TEXCOORD0 , a_texcoord0
#define _VTEXCOORD , vTexCoord
#else
#define _TEXCOORD0
#define _VTEXCOORD
#endif

#ifdef VERTEXCOLOR
#define _COLOR0 , a_color0
#elif defined(VERTEX_ANIMATION)
#define _COLOR0 , a_color0
#else
#define _COLOR0
#endif

#ifdef VERTEXCOLOR
#define _VCOLOR , vColor
#else
#define _VCOLOR
#endif

// VOXELJITTER repurposes the tangent stream as a per-volume lattice frame (see LitSolid.glsl).
// VOXELPACKED has no tangent stream at all: the frame arrives in u_VoxelLatticeFrame instead,
// so the attribute must not be declared or bgfx would bind a dummy stream for nothing.
#if (defined(NORMALMAP) || defined(SURFACE_USES_NORMAL_MAP) || defined(SURFACE_USES_TANGENT) || defined(TRAILFACECAM) || defined(TRAILBONE) || defined(VOXELJITTER)) && !defined(BILLBOARD) && !defined(DIRBILLBOARD) && !defined(VOXELPACKED)
#define _ATANGENT , a_tangent
#else
#define _ATANGENT
#endif

// Packed voxel vertices have no secondary UV stream. Keep iTexCoord1 available to shared
// AO/lightmap code as a constant, matching the NOUV convention for iTexCoord.
#if (defined(LIGHTMAP) || defined(AO) || defined(PAINTABLE) || defined(BILLBOARD) || defined(DIRBILLBOARD) || (defined(BASIC) && defined(MASK))) && !defined(VOXELPACKED)
#define _TEXCOORD1 , a_texcoord1
#else
#define _TEXCOORD1
#endif

#if defined(DISSOLVE) || defined(PLANESOFTPARTICLE)
#define _TEXCOORD2 , a_texcoord2
#else 
#define _TEXCOORD2
#endif

#if defined(SKINNED) || defined(SKIN_MATRIX_TEXTURE)
#define _SKINNED , a_weight, a_indices
#else
#define _SKINNED
#endif

#ifdef INSTANCED
    #if !defined(LIGHTMAP) && !defined(INSTANCED_STROKE_PARAMS)
        #define _INSTANCED , i_data0, i_data1, i_data2
        #define _INSTANCED_EXTRA1 , i_data3
        #define _INSTANCED_EXTRA2
    #else
        #define _INSTANCED , i_data0, i_data1, i_data2
        #define _INSTANCED_EXTRA1 , i_data3
        #define _INSTANCED_EXTRA2 , i_data4
    #endif
    #if defined(SKIN_MATRIX_TEXTURE) || defined(SURFACE_USES_INSTANCE_CUSTOM)
        #define _INSTANCED_EXTRA3 , i_data5
    #else
        #define _INSTANCED_EXTRA3
    #endif
#else
    #define _INSTANCED
    #define _INSTANCED_EXTRA1
    #define _INSTANCED_EXTRA2
    #define _INSTANCED_EXTRA3
#endif

#if defined(DIRLIGHT) && (!defined(MOBILE_SHADOW) || defined(WEBGL))
#ifdef DESKTOP_SHADOW_CASCADE
#define _NUMCASCADES 4
#else
#define _NUMCASCADES 2
#endif
#else
#define _NUMCASCADES 1
#endif

#if defined(NORMALMAP) || defined(SURFACE_USES_NORMAL_MAP) || defined(SURFACE_USES_FRAGMENT_TANGENT) || defined(VOXELJITTER)
#define _VTANGENT , vTangent
#else
#define _VTANGENT
#endif

#ifdef SURFACE_USES_FRAGMENT_NORMAL
#define _VSURFACENORMAL , vNormal
#else
#define _VSURFACENORMAL
#endif

#ifdef SHADOW
#if defined(DIRLIGHT) && (!defined(MOBILE_SHADOW) || defined(WEBGL))
    #ifdef DESKTOP_SHADOW_CASCADE
        #define _VSHADOWPOS , vShadowPos0, vShadowPos1, vShadowPos2, vShadowPos3
        #define vShadowPos vShadowPos0, vShadowPos1, vShadowPos2, vShadowPos3
    #else
        #define _VSHADOWPOS , vShadowPos0, vShadowPos1
        #define vShadowPos vShadowPos0, vShadowPos1
    #endif
#else
    #define _VSHADOWPOS , vShadowPos0
    #define vShadowPos vShadowPos0
#endif
#else
    #define _VSHADOWPOS
#endif

#ifdef SPOTLIGHT
#define _VSPOTPOS , vSpotPos
#else
#define _VSPOTPOS
#endif

#ifdef POINTLIGHT
#define _VCUBEMASKVEC , vCubeMaskVec
#else
#define _VCUBEMASKVEC
#endif

#ifdef ENVCUBEMAP
#define _VREFLECTIONVEC , vReflectionVec
#else
#define _VREFLECTIONVEC
#endif

#if defined(LIGHTMAP) || defined(AO) || (defined(BASIC) && defined(MASK))
#define _VTEXCOORD2 , vTexCoord2
#else
#define _VTEXCOORD2
#endif

#if defined(NO_SPEC_UV_ANIMATION)
#define _VTEXCOORD3 , vTexCoord3
#else
#define _VTEXCOORD3
#endif

#if defined(PAINTABLE)
#define _VTERRAINDATAUV
#define _VPAINTUV , vPaintUV
#else
#define _VTERRAINDATAUV , vTerrainDataUV
#define _VPAINTUV
#endif

#if defined(PLANT_ANIMATION)
#define _VPLANTMASK , vPlantMask
#else
#define _VPLANTMASK
#endif

#if defined(LIGHTMAP)
#define _VLIGHTMAPUV , vLightMapUV
#else
#define _VLIGHTMAPUV
#endif

#ifdef ORTHO
#define _VNEARRAY , vNearRay
#else
#define _VNEARRAY
#endif

#if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE) || (defined(BASIC) && defined(ROUND)) || defined(SURFACE_USES_SCREENPOS)
#define _VSCREENPOS , vScreenPos
#else
#define _VSCREENPOS
#endif

#ifdef CLIPPLANE
#define _VCLIP //, vClip
#else
#define _VCLIP
#endif

#ifdef SPEED_TREE
//#define _OBJECTPOS , a_objectpos
#define _OBJECTPOS
#else
#define _OBJECTPOS
#endif

#if defined(BLEND1)
#define _BLEND , vBlend1Idx
#elif defined(BLEND2)
#define _BLEND , vBlend2, vBlendUV2
#elif defined(BLEND3)
#define _BLEND , vBlend3, vBlendUV2, vBlendUV3
#elif defined(BLEND9)
#define _BLEND , vBlend3, vBlend3_1, vBlend3_2, vBlendUV2, vBlendUV3, vBlendUV4, vBlendUV5, vBlendUV6, vBlendUV7, vBlendUV8, vBlendUV9
#elif defined(CLIFF1)
#define _BLEND , vBlendUV2 , vBlendCliff2
#elif defined(CLIFF2)
#define _BLEND , vBlendUV2 , vBlendUV3, vBlendCliff2
#else
#define _BLEND
#endif

#if defined(AO) && !defined(CLOSE_AO)
#define _AOUV , vAOUV
#else
#define _AOUV
#endif


// #define CLUSTER_VS //for test
#if defined(CLUSTER_VS)
#define _VCLUSTERVS , vVecIrrR, vVecIrrG, vMrpDir, vMrp
#else
#define _VCLUSTERVS
#endif

#ifdef VOXELPACKED
// Packed voxel vertex (VoxelChunkDrawable, 8 bytes): a_position is UBYTE4_NORM carrying
// the chunk-local lattice corner in xyz (0..32) and the face index in w (0..5, in
// VoxelGrid face order -X,+X,-Y,+Y,-Z,+Z). Decoding here — at the attribute macro seam —
// means every pass (scene, depth, shadow) inherits it through GetWorldPos/GetWorldNormal
// untouched. The chunk-origin translation and voxel-size scale live in the model matrix
// (VoxelChunkDrawable composes them per frame), so the decoded integer IS object space.
// a_color0 keeps the legacy meaning (r = palette index, g = interior) unchanged.
#define _VOXEL_FACE floor(a_position.w * 255.0 + 0.5)
#define _VOXEL_AXIS floor(_VOXEL_FACE * 0.5)
#define _VOXEL_SIGN ((_VOXEL_FACE - _VOXEL_AXIS * 2.0) * 2.0 - 1.0)
#define iPos vec4(floor(a_position.xyz * 255.0 + 0.5), 1.0)
#define iNormal (_VOXEL_SIGN * vec3(_VOXEL_AXIS < 0.5 ? 1.0 : 0.0, (_VOXEL_AXIS > 0.5 && _VOXEL_AXIS < 1.5) ? 1.0 : 0.0, _VOXEL_AXIS > 1.5 ? 1.0 : 0.0))
#else
#define iPos a_position
#define iNormal a_normal
#endif
#define iTexCoord a_texcoord0
#define iColor a_color0
#define iColor2 a_color1
#define iColor3 a_color2
#define iColor4 a_color3
#ifdef VOXELPACKED
#define iTexCoord1 hvec2_init(0.0, 0.0)
#else
#define iTexCoord1 a_texcoord1
#endif
#if defined(BILLBOARD) || defined(DIRBILLBOARD)
// Billboard tangents are reconstructed by GetWorldTangent() from the camera-facing frame.
#define iTangent hvec4_init(1.0, 0.0, 0.0, 1.0)
#elif defined(VOXELPACKED)
// Packed voxel vertices have axis-aligned normals but no tangent stream. Pick an object-space
// axis perpendicular to the decoded face normal so TANGENT/BINORMAL remain deterministic.
#define iTangent hvec4_init(abs(iNormal.y) > 0.5 ? 1.0 : 0.0, abs(iNormal.y) > 0.5 ? 0.0 : 1.0, 0.0, 1.0)
#else
#define iTangent a_tangent
#endif
#define iBlendWeights a_weight
#define iBlendIndices a_indices
#define iSize a_texcoord1
#define iTexCoord4 i_data0
#define iTexCoord5 i_data1
#define iTexCoord6 i_data2
#define iObjectIndex i_data3
#define iTexCoord7 i_data4
#endif
