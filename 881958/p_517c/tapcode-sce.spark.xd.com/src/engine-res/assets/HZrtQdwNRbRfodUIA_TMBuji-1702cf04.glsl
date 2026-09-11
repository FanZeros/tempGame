/// TileTerrainBlend — ID+Weight Control Map terrain blending shader (BGFX).
///
/// Samples a Control Map texture (R=bottomID, G=topID, B=blendWeight) using texelFetch
/// to avoid hardware interpolation of integer IDs. Performs manual bilinear interpolation
/// of weights, then samples a Texture2DArray with the 3 unique layer IDs.
///
/// Reference: Delta Force GDC 2025, adapted for irregular merged meshes (2x2 texelFetch).

#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED
    #ifdef PERPIXEL
        $output vTexCoord , vTangent, vNormal, vWorldPos, vDetailTexCoord _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV
    #else
        $output vTexCoord , vTangent, vNormal, vWorldPos, vVertexLight, vScreenPos, vDetailTexCoord _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord , vTangent, vNormal, vWorldPos, vDetailTexCoord _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV
    #else
        $input vTexCoord , vTangent, vNormal, vWorldPos, vVertexLight, vScreenPos, vDetailTexCoord _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV
    #endif
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#include "constants.sh"
#ifdef COMPILEPS
#ifdef LIGHTMAP
#include "LightMap.sh"
#endif
#include "PBR/StandardPBR.sh"
#endif

// ---- TileTerrainBlend samplers ----
SAMPLER2D(u_ControlMap0, 0);           // Control map (RGBA8, MUST be point-filtered)
SAMPLER2DARRAY(u_TerrainAlbedo1, 1);   // Terrain layer albedo array
SAMPLER2DARRAY(u_TerrainMix2, 2);      // Terrain layer normal + metallic/roughness array

#define sControlMap u_ControlMap0
#define sAlbedoArray u_TerrainAlbedo1
#define sMixArray u_TerrainMix2

// ---- TileTerrainBlend uniforms ----
uniform vec4 u_ControlMapParams;   // (originX, originZ, 1.0/gridSpacing, 0)
uniform vec2 u_ControlMapSize;     // (width, height) in texels
uniform hvec2 u_DetailTiling;       // world-space tiling (e.g., 0.39 ≈ 1 tile per 2.56m)

#define cControlMapParams u_ControlMapParams
#define cControlMapSize u_ControlMapSize
#define cDetailTiling u_DetailTiling

// ---- AccumWeight: priority-exclusive weight accumulation ----
// Each value matches ONLY the first slot whose ID equals it, preventing
// double-counting when fewer than 3 unique IDs exist (id0==id1 or id1==id2).
#ifdef COMPILEPS
void AccumWeight(int val, float weight, int id0, int id1,
                 inout float w0, inout float w1, inout float w2)
{
    float m0 = float(val == id0);
    float m1 = (1.0 - m0) * float(val == id1);
    float m2 = 1.0 - m0 - m1;
    w0 += m0 * weight;
    w1 += m1 * weight;
    w2 += m2 * weight;
}
#endif

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vTexCoord.xy = GetTexCoord(iTexCoord);
    // Detail UV from world position (not mesh UV) for seamless tiling across merged meshes
    vDetailTexCoord = cDetailTiling * worldPos.xz;

    // TBN
    vec4 tangent = GetWorldTangent(modelMatrix);
    vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w;
    vTexCoord.zw = bitangent.xy;
    vTangent = vec4(tangent.xyz, bitangent.z);

    #if defined(AO)
        #if defined(SSAO)
            vAOUV = GetSSAOTexCoord(gl_Position);
        #else
            vAOUV = vec2(0.0, 0.0);
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

        vScreenPos = GetScreenPos(gl_Position);

        #ifdef ENVCUBEMAP
            vReflectionVec = worldPos - cCameraPos;
        #endif
    #endif
}

void PS()
{
    // =========================================================================
    // Control Map + Terrain Array blend (texelFetch, no hardware interpolation)
    // =========================================================================

    // 1. World position -> Control Map floating-point texel coordinate
    vec2 mapCoord = (vWorldPos.xz - cControlMapParams.xy) * cControlMapParams.z;
    ivec2 iMapSize = ivec2(cControlMapSize);

    // 2. Four neighboring texel coordinates (clamped to texture bounds)
    ivec2 t00 = clamp(ivec2(floor(mapCoord)),     ivec2(0, 0), iMapSize - ivec2(1, 1));
    ivec2 t10 = clamp(t00 + ivec2(1, 0),          ivec2(0, 0), iMapSize - ivec2(1, 1));
    ivec2 t01 = clamp(t00 + ivec2(0, 1),          ivec2(0, 0), iMapSize - ivec2(1, 1));
    ivec2 t11 = clamp(t00 + ivec2(1, 1),          ivec2(0, 0), iMapSize - ivec2(1, 1));

    // 3. texelFetch — no hardware interpolation, preserves discrete IDs
    vec4 c00 = texelFetch(sControlMap, t00, 0);
    vec4 c10 = texelFetch(sControlMap, t10, 0);
    vec4 c01 = texelFetch(sControlMap, t01, 0);
    vec4 c11 = texelFetch(sControlMap, t11, 0);

    // 4. Decode IDs and blend weights (R=bottomID, G=topID, B=blendWeight)
    int b00 = int(c00.r * 255.0 + 0.5); int u00 = int(c00.g * 255.0 + 0.5); float bl00 = c00.b;
    int b10 = int(c10.r * 255.0 + 0.5); int u10 = int(c10.g * 255.0 + 0.5); float bl10 = c10.b;
    int b01 = int(c01.r * 255.0 + 0.5); int u01 = int(c01.g * 255.0 + 0.5); float bl01 = c01.b;
    int b11 = int(c11.r * 255.0 + 0.5); int u11 = int(c11.g * 255.0 + 0.5); float bl11 = c11.b;

    // 5. Extract 3 unique IDs via min/mid/max
    int id0 = min(min(min(b00, u00), min(b10, u10)), min(min(b01, u01), min(b11, u11)));
    int id2 = max(max(max(b00, u00), max(b10, u10)), max(max(b01, u01), max(b11, u11)));
    int id1 = id0;  // default = min (when <= 2 unique IDs)
    id1 = (b00 > id0 && b00 < id2) ? b00 : id1;
    id1 = (u00 > id0 && u00 < id2) ? u00 : id1;
    id1 = (b10 > id0 && b10 < id2) ? b10 : id1;
    id1 = (u10 > id0 && u10 < id2) ? u10 : id1;
    id1 = (b01 > id0 && b01 < id2) ? b01 : id1;
    id1 = (u01 > id0 && u01 < id2) ? u01 : id1;
    id1 = (b11 > id0 && b11 < id2) ? b11 : id1;
    id1 = (u11 > id0 && u11 < id2) ? u11 : id1;

    // 6. Bilinear interpolation weights
    vec2 f = fract(mapCoord);
    float bw00 = (1.0 - f.x) * (1.0 - f.y);
    float bw10 = f.x         * (1.0 - f.y);
    float bw01 = (1.0 - f.x) * f.y;
    float bw11 = f.x         * f.y;

    // 7. Priority-exclusive weight accumulation (8 ID values = 4 texels x 2 per texel)
    float w0 = 0.0, w1 = 0.0, w2 = 0.0;
    AccumWeight(b00, bw00 * (1.0 - bl00), id0, id1, w0, w1, w2);
    AccumWeight(u00, bw00 * bl00,         id0, id1, w0, w1, w2);
    AccumWeight(b10, bw10 * (1.0 - bl10), id0, id1, w0, w1, w2);
    AccumWeight(u10, bw10 * bl10,         id0, id1, w0, w1, w2);
    AccumWeight(b01, bw01 * (1.0 - bl01), id0, id1, w0, w1, w2);
    AccumWeight(u01, bw01 * bl01,         id0, id1, w0, w1, w2);
    AccumWeight(b11, bw11 * (1.0 - bl11), id0, id1, w0, w1, w2);
    AccumWeight(u11, bw11 * bl11,         id0, id1, w0, w1, w2);

    // 8. Sample Texture2DArray and blend
    //    Flat XZ sampling for all 3 IDs
    vec4 albedo0  = texture2DArray(sAlbedoArray, vec3(vDetailTexCoord, float(id0)));
    vec4 albedo1  = texture2DArray(sAlbedoArray, vec3(vDetailTexCoord, float(id1)));
    vec4 albedo2  = texture2DArray(sAlbedoArray, vec3(vDetailTexCoord, float(id2)));
    #ifdef NOT_SUPPORT_SRGB
        albedo0 = GammaToLinearSpace(albedo0);
        albedo1 = GammaToLinearSpace(albedo1);
        albedo2 = GammaToLinearSpace(albedo2);
    #endif
    vec4 mixColor0 = texture2DArray(sMixArray, vec3(vDetailTexCoord, float(id0)));
    vec4 mixColor1 = texture2DArray(sMixArray, vec3(vDetailTexCoord, float(id1)));
    vec4 mixColor2 = texture2DArray(sMixArray, vec3(vDetailTexCoord, float(id2)));

    //    Blend flat terrain (XZ plane) using control map weights
    vec4 flatBaseColor  = w0 * albedo0 + w1 * albedo1 + w2 * albedo2;
    vec3 flatNormal     = w0 * DecodeNormal(mixColor0) + w1 * DecodeNormal(mixColor1) + w2 * DecodeNormal(mixColor2);
    vec2 flatMetalRough = w0 * mixColor0.wz + w1 * mixColor1.wz + w2 * mixColor2.wz;

    //    Cliff tri-planar: sample layer 0 from XY and ZY projections
    vec4 cliffAlbXY = texture2DArray(sAlbedoArray, vec3(cDetailTiling * vWorldPos.xy, 0.0));
    vec4 cliffAlbZY = texture2DArray(sAlbedoArray, vec3(cDetailTiling * vWorldPos.zy, 0.0));
    #ifdef NOT_SUPPORT_SRGB
        cliffAlbXY = GammaToLinearSpace(cliffAlbXY);
        cliffAlbZY = GammaToLinearSpace(cliffAlbZY);
    #endif
    vec4 cliffMixXY = texture2DArray(sMixArray,    vec3(cDetailTiling * vWorldPos.xy, 0.0));
    vec4 cliffMixZY = texture2DArray(sMixArray,    vec3(cDetailTiling * vWorldPos.zy, 0.0));

    //    Tri-planar blend: flat XZ result + cliff XY/ZY by geometry normal
    vec3 aN = pow(abs(vNormal), vec3_splat(4.0));
    vec3 triW = aN / (aN.x + aN.y + aN.z + 1e-5);

    vec4 baseColor         = flatBaseColor  * triW.y + cliffAlbXY * triW.z + cliffAlbZY * triW.x;
    vec3 normalDirection   = flatNormal     * triW.y + DecodeNormal(cliffMixXY) * triW.z + DecodeNormal(cliffMixZY) * triW.x;
    vec2 metallicRoughness = flatMetalRough * triW.y + cliffMixXY.wz * triW.z + cliffMixZY.wz * triW.x;

    // Get view dir (eyes dir)
    hvec3 _WorldPos = vWorldPos.xyz;
    vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);

    // Transform normal to worldspace
    mat3 tbn = TR(mat3(vTangent.xyz, vec3(vTexCoord.zw, vTangent.w), vNormal));
    normalDirection = normalize(mul(tbn, normalDirection));

    // Get shadow
    #ifdef SHADOW
        vec3 shadowColor = GetShadow(vShadowPos, vWorldPos.w) * vec3(1.0, 1.0, 1.0);
    #else
        vec3 shadowColor = vec3(1.0, 1.0, 1.0);
    #endif

// Deferred
#if defined(MATERIALBAKE)
    EncodeGBufferBake(baseColor.rgb, baseColor.a, metallicRoughness.y, metallicRoughness.x, 1.0, normalDirection, vec3_splat(0.0));
#elif defined(DEFERRED)
    EncodeGBufferPBR(baseColor.rgb, metallicRoughness.x, 0.5, metallicRoughness.y, normalDirection, shadowColor, SHADINGMODELID_PBR_LIT);
#else
    // PBR calc
    vec3 finalColor = MetallicPBR(baseColor.rgb, metallicRoughness.x, 0.5, metallicRoughness.y, vWorldPos.xyz, normalDirection, viewDirection, shadowColor, 1.0);

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    // Mix final color and fog
    finalColor = GetFog(finalColor, fogFactor);

    // Gamma in shadering
    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        finalColor = LinearToGammaSpace(toAcesFilmic(finalColor));
    #endif

    gl_FragColor = vec4(finalColor, 1.0);
#endif
}
