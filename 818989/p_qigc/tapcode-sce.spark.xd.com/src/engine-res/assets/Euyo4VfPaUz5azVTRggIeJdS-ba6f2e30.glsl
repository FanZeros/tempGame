#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED
    #ifdef PERPIXEL
        $output vTexCoord _VTANGENT, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _VTEXCOORD2
    #else
        $output vTexCoord _VTANGENT, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR
    #endif
#endif
#ifdef COMPILEPS
    #ifdef PERPIXEL
        $input vTexCoord _VTANGENT, vNormal, vWorldPos _VSHADOWPOS _VSPOTPOS _VCUBEMASKVEC _VCOLOR _VTEXCOORD2
    #else
        $input vTexCoord _VTANGENT, vNormal, vWorldPos, vVertexLight, vScreenPos _VREFLECTIONVEC _VTEXCOORD2 _VCOLOR
    #endif
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #ifdef NORMALMAP
        vec4 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w;
        vTexCoord = vec4(GetTexCoord(iTexCoord), bitangent.xy);
        vTangent = vec4(tangent.xyz, bitangent.z);
    #else
        vTexCoord = GetTexCoord(iTexCoord);
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
            // 这里没有加TR，也许效果会不对，没测到先不改了
            vCubeMaskVec = mul((worldPos - cLightPos.xyz), mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz));
        #endif

        #if defined(LIGHTMAP) || defined(AO)
            // If using lightmap, disregard zone ambient light
            // If using AO, calculate ambient in the PS
            vTexCoord2 = iTexCoord1;
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
    // Get material diffuse albedo
    #ifdef DIFFMAP
        vec4 diffInput = LinearColor(texture2D(sDiffMap, vTexCoord.xy));
        #ifdef ALPHAMASK
            if (diffInput.a < 0.5)
                discard;
        #endif
        vec4 diffColor = cMatDiffColor * diffInput;
    #else
        vec4 diffColor = cMatDiffColor;
    #endif

    #ifdef VERTEXCOLOR
        diffColor *= vColor;
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
        vec3 normal = normalize(tbn * DecodeNormal(texture2D(sNormalMap, vTexCoord.xy)));
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
        float bakeOcclusion = 1.0;
        #if defined(AO) && !defined(ADDITIONAL_AO)
            bakeOcclusion = texture2D(sEmissiveMap, vTexCoord2).r;
        #endif
        EncodeGBufferBake(diffColor.rgb, diffColor.a, 0.85, 0.0, bakeOcclusion, normal, bakeEmission);
    #elif defined(PERPIXEL)
        // Per-pixel forward lighting
        vec3 lightColor;
        vec3 lightDir;
        vec3 finalColor;
        float shadow = 1.0;

        #ifdef SHADOW
            shadow = clamp(GetShadow(vShadowPos, vWorldPos.w) + 0.2, 0.0, 1.0);
        #endif

         #ifdef LIGHTMAP
            vec3 lightmapcolor = texture2D(sEmissiveMap, vTexCoord2).rgb;
            finalColor = lightmapcolor.rgb * diffColor.rgb * shadow;
        #else
            finalColor = diffColor.rgb * shadow;
        #endif
            
        #ifdef AMBIENT
            finalColor += cAmbientColor.rgb * diffColor.rgb;
            finalColor += cMatEmissiveColor;
            gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);
        #else
            gl_FragColor = vec4(GetLitFog(finalColor, fogFactor), diffColor.a);
        #endif
    #elif defined(DEFERRED)
        // Lightmap = pre-baked lighting, so encode as unlit passthrough (shadingModelID=0)
        // and the resolve adds no realtime light on top. Color assembly matches forward,
        // but without fog — GBuffer encode branches drop fog by convention and the SceneFog
        // quad re-applies it (see CEMapDeferred.xml)
        vec3 finalColor = vVertexLight * diffColor.rgb;
        #ifdef AO
            // If using AO, the vertex light ambient is black, calculate occluded ambient here
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * cAmbientColor.rgb * diffColor.rgb;
        #endif

        #ifdef ENVCUBEMAP
            finalColor += cMatEnvMapColor * textureCube(sEnvCubeMap, reflect(vReflectionVec, normal)).rgb;
        #endif
        #ifdef LIGHTMAP
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * diffColor.rgb;
        #endif
        #ifdef EMISSIVEMAP
            finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, vTexCoord.xy).rgb;
        #else
            finalColor += cMatEmissiveColor;
        #endif

        EncodeGBufferUnlit(finalColor, normal);
    #else
        // Ambient & per-vertex lighting
        vec3 finalColor = vec3(0.0, 0.0, 0.0);

        #ifdef LIGHTMAP
            //vec3 lightcolor = texture2D(sEmissiveMap, vTexCoord2).rgb;
            
            //float diff = GetDiffuse(normal, vWorldPos.xyz, lightDir);
           
           // #ifdef SPECULAR
           //     float spec = GetSpecular(normal, cCameraPosPS - vWorldPos.xyz, lightDir, cMatSpecColor.a);
          //      finalColor = diff * lightColor * (diffColor.rgb + spec * specColor * cLightColor.a);
          //  #else
         //       finalColor = diff * lightColor * diffColor.rgb;
         //   #endif

            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb;// * diffColor.rgb;

            //float gray = 0.2125 * finalColor.r + 0.7154 * finalColor.g + 0.0721 * finalColor.b;
            //vec4 grayColor = vec4(gray, gray, gray, 0);
            //float _Saturation = 1.5;
            //finalColor = mix(grayColor, vec4(finalColor,0), _Saturation);

            //finalColor = color1.rgb  * diffColor.rgb;
            //vec3 color2 = vec3(clamp(color1.r* 1.2, 0, 1), clamp(color1.g* 1.2, 0, 1), clamp(color1.b* 1.2, 0, 1));
            finalColor = finalColor.rgb  * diffColor.rgb;
        #endif
    #endif

    #ifndef MATERIALBAKE
    gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
	    gl_FragColor.rgb = LinearToGammaSpace(gl_FragColor.rgb);
    #endif
    #endif
}
