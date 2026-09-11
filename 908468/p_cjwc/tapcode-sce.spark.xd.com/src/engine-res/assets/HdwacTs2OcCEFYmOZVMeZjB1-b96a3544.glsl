#include "varying_scenepass.def.sc"
#if defined(ENVCUBEMAP)
    #define CLOSE_AO
#elif defined(SSAO) && !defined(AO)
    #define AO
    #define ADDITIONAL_AO
#endif
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA3
    #ifdef PERPIXEL
        $output vTexCoord _VTANGENT, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VLIGHTMAPUV
    #else
        $output vTexCoord _VTANGENT, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VLIGHTMAPUV
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord _VTANGENT, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _AOUV _VLIGHTMAPUV
    #else
        $input vTexCoord _VTANGENT, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR _AOUV _VLIGHTMAPUV
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
#ifdef LIGHTMAP
#include "LightMap.sh"
#endif
#ifdef COMPILEPS
#include "PBR/SimpleBRDF.sh"
#endif
#include "lambert.sh"

#ifdef VOXELJITTER
// Per-voxel brightness jitter amplitude for voxel palette rendering (see NoTextureVCol
// technique). The lattice frame (origin + voxel size) comes per-vertex in the
// tangent channel, so one shared material serves volumes of any voxel size, and a severed
// piece keeps the exact pattern it wore before the break.
uniform float u_VoxelJitter;
#endif

#ifdef VOXELPACKED
// Packed voxel route (VoxelChunkDrawable): the lattice frame moves off the vertex stream
// into one per-drawable constant — xyz = lattice origin + chunk origin (meters),
// w = voxel size. iPos is the chunk-local lattice integer, so
// iPos * w + xyz reproduces the legacy per-vertex vTangent value bit-for-bit.
uniform vec4 u_VoxelLatticeFrame;
#endif

#ifdef VOXELPALETTE
// This material's palette bank row offset (bank * 4) in the palette atlas; set per
// (world, bank) material clone. See VoxelPhysicsWorld::GetPaletteTexture.
uniform float u_VoxelPaletteBank;
// Palette atlas height in texels. Fed from the single C++ source of truth
// (VoxelPhysicsWorld::MAX_PALETTE_BANKS * 4, the same expression the texture is sized
// with) so the shader carries no literal copy that could silently drift.
uniform float u_VoxelPaletteAtlasHeight;
#endif

void VS()
{
    #ifdef NOUV
    vec2 iTexCoord = vec2(0.0, 0.0);
    #endif
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    vNormal *= cNormalOddNegativeScale;


    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #if defined(VOXELJITTER) && !defined(NORMALMAP)
        #ifdef VOXELPACKED
            // Same lattice frame, from the per-drawable constant instead of the tangent
            // stream: chunk-local corner * voxel size + (lattice origin + chunk origin).
            vTangent = vec4(iPos.xyz * u_VoxelLatticeFrame.w + u_VoxelLatticeFrame.xyz,
                u_VoxelLatticeFrame.w);
        #else
            // Not a UV tangent: the voxel mesher packs (spawn lattice origin, voxel size) here.
            // Object-space position plus that origin is a frame that is identical before and
            // after a piece breaks off, so the per-voxel hash downstream never pops or swims.
            vTangent = vec4(iPos.xyz + iTangent.xyz, iTangent.w);
        #endif
    #endif

    #ifdef NORMALMAP
        vec4 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w * cBitangentOddNegativeScale;
        vTexCoord = vec4(GetTexCoord(iTexCoord), bitangent.xy);
        vTangent = vec4(tangent.xyz, bitangent.z);
    #else
        vTexCoord = GetTexCoord(iTexCoord);
    #endif

    #if defined(AO) && !defined(CLOSE_AO)
        #if defined(SSAO)
            // SSAO 使用屏幕空间坐标，材质 AO 使用模型的第二套 UV。
            vAOUV = GetSSAOTexCoord(gl_Position);
        #else
            vAOUV = iTexCoord1.xy;
        #endif
    #endif

    #ifdef PERPIXEL

        // Per-pixel forward lighting
        hvec4 projWorldPos = hvec4_init(worldPos, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            GetShadowPos(projWorldPos, vNormal, vShadowPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = mul(projWorldPos, cLightMatrices[0]);
        #endif
    
        #ifdef POINTLIGHT
            vCubeMaskVec = mul(vec4(worldPos - cLightPos.xyz, 0.0), cLightMatrices[0]).xyz;
        #endif
    #else
        // Ambient & per-vertex lighting
        #if defined(LIGHTMAP) || (defined(AO) && !defined(ADDITIONAL_AO))
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
    // Get material diffuse albedo
    #ifdef DIFFMAP
        #ifdef NOT_SUPPORT_SRGB
            vec4 diffInput = GammaToLinearSpace(texture2D(sDiffMap, vTexCoord.xy));
        #else
            vec4 diffInput = texture2D(sDiffMap, vTexCoord.xy);
        #endif    
        #ifdef ALPHAMASK
            if (diffInput.a < 0.5)
                discard;
        #endif
        vec4 diffColor = cMatDiffColor * diffInput;
    #else
        vec4 diffColor = cMatDiffColor;
    #endif

    #if defined(VERTEXCOLOR) && !defined(VOXELPALETTE)
        diffColor *= vColor;
    #endif

    #ifdef VOXELPALETTE
        // Voxel palette path (details in the same-named block in PBRLitSolid.glsl): the
        // vertex colour carries an index, not a colour. R = index / 255, G = interior
        // flag → the bank's cut-face row. sDiffMap is the palette atlas (256 x banks*4);
        // u_VoxelPaletteBank is this material's bank row offset (bank * 4).
        // texture2D is a bgfx macro: each call must stay on ONE line (see PBRLitSolid).
        float voxelPalU = (floor(vColor.r * 255.0 + 0.5) + 0.5) / 256.0;
        float voxelPalRow0 = u_VoxelPaletteBank + 0.5;
        vec2 voxelAlbedoUV = vec2(voxelPalU,
            (voxelPalRow0 + (vColor.g > 0.5 ? 3.0 : 0.0)) / u_VoxelPaletteAtlasHeight);
        vec2 voxelEmissiveUV = vec2(voxelPalU, (voxelPalRow0 + 2.0) / u_VoxelPaletteAtlasHeight);
        vec4 voxelAlbedo = texture2D(sDiffMap, voxelAlbedoUV);
        vec4 voxelEmissive = texture2D(sDiffMap, voxelEmissiveUV);
        // sRGB -> linear decode; see the same-named block in PBRLitSolid.glsl (the
        // palette texture is plain RGBA8, no hardware sRGB view).
        voxelAlbedo = GammaToLinearSpace(voxelAlbedo);
        voxelEmissive.rgb = GammaToLinearSpace(voxelEmissive.rgb);
        diffColor *= voxelAlbedo;
    #endif

    #ifdef VOXELJITTER
        // Teardown-style per-voxel brightness variation. Done here, not in vertex colours:
        // greedy meshing gives one flat colour to a whole merged quad, so per-voxel detail can
        // only come from a per-pixel hash. The cell comes from the LATTICE frame the vertex
        // stream carries (vTangent = lattice-space position, w = voxel size), not from world
        // position — world cells would make the pattern crawl over tumbling debris and change
        // completely once a piece lands. Full precision (hvec/hfloat) is required: cell
        // indices reach the hundreds and the hash multiplies them by large constants, far
        // outside fp16 integer range.
        hvec3 jitterCell = floor(vTangent.xyz / vTangent.w);
        hfloat jitterHash =
            fract(sin(dot(jitterCell, hvec3_init(127.1, 311.7, 74.7))) * 43758.5453);
        diffColor.rgb *= 1.0 + u_VoxelJitter * (jitterHash - 0.5);
    #endif

    // Get material specular albedo
    #ifdef SPECMAP
        vec3 specColor = cMatSpecColor.rgb * texture2D(sSpecMap, vTexCoord.xy).rgb;
    #else
        vec3 specColor = cMatSpecColor.rgb;
    #endif

    // Get normal
    #ifdef NORMALMAP
        mat3 tbn = TR(mat3(vTangent.xyz, vec3(vTexCoord.zw, vTangent.w), vNormal));
        vec3 normal = normalize(mul(tbn, DecodeNormal(texture2D(sNormalMap, vTexCoord.xy))));
    #else
        vec3 normal = normalize(vNormal);
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    #if defined(MATERIALBAKE)
        vec3 bakeEmission = cMatEmissiveColor;
        #ifdef EMISSIVEMAP
            bakeEmission *= texture2D(sEmissiveMap, vTexCoord.xy).rgb;
        #endif
        #ifdef VOXELPALETTE
            bakeEmission += voxelEmissive.rgb * (voxelEmissive.a * 16.0);
        #endif
        float bakeOcclusion = 1.0;
        #if defined(AO) && !defined(ADDITIONAL_AO)
            bakeOcclusion = texture2D(sEmissiveMap, vTexCoord2).r;
        #endif
        EncodeGBufferBake(diffColor.rgb, diffColor.a, 0.85, 0.0, bakeOcclusion, normal, bakeEmission);
    #elif defined(PERPIXEL)
        #ifdef SHADOW
            hvec3 shadow = GetShadow(vShadowPos, vWorldPos.w) * hvec3_init(1.0, 1.0, 1.0);
        #else
            hvec3 shadow = hvec3_init(1.0, 1.0, 1.0);
        #endif
        vec3 pixelColor = LambertBRDF(diffColor.rgb, vec4(specColor, cMatSpecColor.a), vWorldPos.xyz, normal, shadow, 1.0);
        #ifdef AMBIENT
            pixelColor += cMatEmissiveColor;
            #ifdef VOXELPALETTE
                // row2: rgb = emissive colour, a = intensity/16 (restored to 0..16).
                pixelColor += voxelEmissive.rgb * (voxelEmissive.a * 16.0);
            #endif
            gl_FragColor = vec4(GetFog(pixelColor, fogFactor), diffColor.a);
        #else
            gl_FragColor = vec4(GetLitFog(pixelColor, fogFactor), diffColor.a);
        #endif

        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
	        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
	    #endif
    #elif defined(DEFERRED)
        #ifdef VOXELPALETTE
            EncodeGBufferLambert(diffColor.rgb, vec4(specColor, cMatSpecColor.a), normal,
                cMatEmissiveColor + voxelEmissive.rgb * (voxelEmissive.a * 16.0),
                SHADINGMODELID_LAMBERT_LIT);
        #else
            EncodeGBufferLambert(diffColor.rgb, vec4(specColor, cMatSpecColor.a), normal, cMatEmissiveColor, SHADINGMODELID_LAMBERT_LIT);
        #endif
    #else
        // Ambient & per-vertex lighting
        vec3 finalColor = vVertexLight * diffColor.rgb;
        #if defined(AO) && !defined(ADDITIONAL_AO)
            // If using AO, the vertex light ambient is black, calculate occluded ambient here
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * cAmbientColor.rgb * diffColor.rgb;
        #endif
        

        #ifdef ENVCUBEMAP
            // finalColor += cMatEnvMapColor * textureCube(sEnvCubeMap, reflect(vReflectionVec, normal)).rgb;
            finalColor += cMatEnvMapColor;
        #endif
        #ifdef LIGHTMAP
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * diffColor.rgb;
        #endif
        // 避免非Cluster管线，多光源重复累加自发光
        #if !defined(POINTLIGHT) && !defined(SPOTLIGHT)
            #ifdef EMISSIVEMAP
                finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, vTexCoord.xy).rgb;

                // 临时打个补丁，原来是想通过cMatEmissiveColor设置成(1,1,1,1)，cMatDiffColor设置成(0,0,0,0)来实现自发光，不计算光照但产生投影
                // 因为计算光照时cMatDiffColor.a是0，所以光照没有进行计算，详见像素着色器PERPIXEL里的内容
                // 后来发现cMatEmissiveColor是个float3，也就导致了最终算出来的oColor.a其实一直都是0，这就导致了如果最终渲出来的图片alpha都0
                // 如果被用于混合的话，就啥都看不到 ——石声威 2019年4月19日 12:18:40
                #ifdef DIFFMAP
                    diffColor.a = diffInput.a;
                #else
                    diffColor.a = 1.0;
                #endif
            #else
                finalColor += cMatEmissiveColor;
            #endif
            #ifdef VOXELPALETTE
                finalColor += voxelEmissive.rgb * (voxelEmissive.a * 16.0);
            #endif
        #endif

        gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);

        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
	        gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
	    #endif
    #endif
}
