#include "varying_ue3water.def.sc"
#include "urho3d_compatibility.sh"
#ifdef WATER_SHADOWD
#define _WATER_VSHADOWPOS _VSHADOWPOS
#endif
#ifdef COMPILEVS
    $input a_position, a_color0, _INSTANCED
    $output vScreenPos, vUV1, vUV2, vEyeVec, vWorldPos, vTerrainDataUV, vWaterBlend _WATER_VSHADOWPOS
#endif
#ifdef COMPILEPS
    $input vScreenPos, vUV1, vUV2, vEyeVec, vWorldPos, vTerrainDataUV, vWaterBlend _WATER_VSHADOWPOS
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"
#ifdef COMPILEPS
#include "constants.sh"
#include "PBR/SimpleBRDF.sh"
#endif

#ifdef COMPILEVS
    uniform vec2 u_WaterSpeed;
    uniform vec2 u_WaveScaler;
    uniform float u_WaveDensity;
    uniform float u_WaterShadowOffset;
    #define cWaterSpeed u_WaterSpeed
    #define cWaveScalerX u_WaveScaler.x
    #define cWaveScalerY u_WaveScaler.y
    #define cWaveDensity u_WaveDensity
    #define cWaterShadowOffset u_WaterShadowOffset
#endif
#ifdef COMPILEPS
    SAMPLER2D(s_ColorBuffer0, 0);
    SAMPLER2D(s_tex1, 1);
    SAMPLERCUBE(s_tex2, 2);
    SAMPLER2D(s_tex3, 3);
    #ifdef COLOR_RAMP
        SAMPLER2D(s_tex4, 4);
        SAMPLER2D(s_tex5, 5);
    #endif
    uniform float u_NoiseStrength;
    uniform float u_NormalStrength;
    uniform float u_Transparency;
    uniform vec4 u_WaterColor0;
    uniform vec4 u_WaterColor1;
    uniform vec4 u_LightParam;
    uniform vec3 u_WaterTint;
    uniform vec4 u_WaterColor; //小地图用
    uniform vec2 u_BakeRefractionTiling;
    #define sRefractionMap s_ColorBuffer0
    #define sWaterNormalMap s_tex1
    #define sReflectionCube s_tex2
    #define sSceneDepthBuffer s_tex3
    #define sColorRamp s_tex4
    #define sWaterBottomRamp s_tex5
    #define cNoiseStrength u_NoiseStrength
    #define cNormalStrength u_NormalStrength
    #define cTransparency u_Transparency
    #define cWaterColor0 u_WaterColor0
    #define cWaterColor1 u_WaterColor1
    #define cSpecularGloss u_LightParam.x
    #define cSpecularFactor u_LightParam.y
    #define cFresnelFactor u_LightParam.z
    #define cReflection u_LightParam.w
    #define cWaterTint u_WaterTint
    #define cBakeRefractionTiling u_BakeRefractionTiling
    #ifdef COLOR_RAMP
        uniform vec2 u_WaterDepthParam;
        #define cMaxTerrainHeight u_WaterDepthParam.x
        #define cWaterBlendDepth u_WaterDepthParam.y
    #endif
    #ifdef SSR_WATER
        uniform hfloat u_SSRWaterIntensity;
    #endif

    // Get linear depth from depth buffer (D24S8 format)
    hfloat GetLinearDepth(vec2 uv)
    {
        hfloat depth = texture2D(sSceneDepthBuffer, uv).r;
        return LinearizeDepth(depth, cNearClipPS, cFarClipPS);
    }

    #ifdef SSR_WATER
        #define WATER_SSR_MAX_STEPS 32
        #define WATER_SSR_REFINEMENT_STEPS 4
        #define WATER_SSR_MAX_DISTANCE 15.0
        #define WATER_SSR_THICKNESS 1.0

        // Project view-space position to screen UV
        hvec2 WaterSSRProjectToUV(hvec3 viewPos)
        {
            hvec4 cp = mul(hvec4_init(viewPos.x, viewPos.y, viewPos.z, 1.0), cProj);
            hvec2 uv = cp.xy / cp.w * 0.5 + 0.5;
        #if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
            uv.y = 1.0 - uv.y;
        #endif
            return uv;
        }

        // Simplified screen-space ray trace for water reflections.
        // Based on SSRLinearTrace: linear march + binary refinement, 1/z depth interpolation.
        // Returns: vec4(hitColor.rgb, confidence)
        hvec4 TraceWaterSSR(hvec3 viewOrigin, hvec3 viewReflDir)
        {
            hfloat thickness = WATER_SSR_THICKNESS;
            hfloat maxDist = WATER_SSR_MAX_DISTANCE;

            // Ray end in view space
            hvec3 rayEnd = viewOrigin + viewReflDir * maxDist;

            // Clip to near plane (left-handed: z > 0 is forward)
            if (rayEnd.z < cNearClipPS)
            {
                if (abs(viewReflDir.z) < 0.0001)
                    return hvec4_init(0.0, 0.0, 0.0, 0.0);
                hfloat tClip = (cNearClipPS - viewOrigin.z) / viewReflDir.z;
                if (tClip <= 0.0)
                    return hvec4_init(0.0, 0.0, 0.0, 0.0);
                rayEnd = viewOrigin + viewReflDir * tClip;
            }

            // Project both endpoints to clip space
            hvec4 h0 = mul(hvec4_init(viewOrigin.x, viewOrigin.y, viewOrigin.z, 1.0), cProj);
            hvec4 h1 = mul(hvec4_init(rayEnd.x, rayEnd.y, rayEnd.z, 1.0), cProj);

            if (h0.w <= 0.0 || h1.w <= 0.0)
                return hvec4_init(0.0, 0.0, 0.0, 0.0);

            // To screen UV
            hvec2 uv0 = h0.xy / h0.w * 0.5 + 0.5;
            hvec2 uv1 = h1.xy / h1.w * 0.5 + 0.5;
        #if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
            uv0.y = 1.0 - uv0.y;
            uv1.y = 1.0 - uv1.y;
        #endif

            // 1/w for perspective-correct depth interpolation
            hfloat k0 = 1.0 / h0.w;
            hfloat k1 = 1.0 / h1.w;

            // Clip ray to screen bounds [0,1]
            {
                hvec2 uvDir = uv1 - uv0;
                hfloat tScreen = 1.0;
                if (uvDir.x > 0.0001)       tScreen = min(tScreen, (1.0 - uv0.x) / uvDir.x);
                else if (uvDir.x < -0.0001) tScreen = min(tScreen, -uv0.x / uvDir.x);
                if (uvDir.y > 0.0001)       tScreen = min(tScreen, (1.0 - uv0.y) / uvDir.y);
                else if (uvDir.y < -0.0001) tScreen = min(tScreen, -uv0.y / uvDir.y);
                tScreen = clamp(tScreen, 0.0, 1.0);
                uv1 = uv0 + uvDir * tScreen;
                k1 = mix(k0, k1, tScreen);
            }

            // ~1 pixel per step, capped at WATER_SSR_MAX_STEPS
            hvec2 screenSize = hvec2_init(1.0, 1.0) / cGBufferInvSize;
            hvec2 deltaPixels = (uv1 - uv0) * screenSize;
            hfloat pixelDist = max(abs(deltaPixels.x), abs(deltaPixels.y));
            if (pixelDist < 1.0)
                return hvec4_init(0.0, 0.0, 0.0, 0.0);

            int numSteps = min(int(ceil(pixelDist)), WATER_SSR_MAX_STEPS);
            hfloat stepT = 1.0 / hfloat(numSteps);

            // Phase 1: Linear march
            hfloat hitParamT = -1.0;
            hfloat hitDiff = 0.0;
            hfloat lastFrontT = 0.0;

            for (int i = 1; i <= WATER_SSR_MAX_STEPS; i++)
            {
                if (i > numSteps) break;
                hfloat t = stepT * hfloat(i);
                hvec2 sampleUV = mix(uv0, uv1, t);

                if (any(lessThan(sampleUV, vec2_splat(0.0))) || any(greaterThan(sampleUV, vec2_splat(1.0))))
                    break;

                hfloat rayZ = 1.0 / mix(k0, k1, t);
                hfloat sceneZ = GetLinearDepth(sampleUV);
                hfloat depthDiff = rayZ - sceneZ;

                if (depthDiff > 0.0 && depthDiff < thickness)
                {
                    hitParamT = t;
                    hitDiff = depthDiff;
                    break;
                }
                else if (depthDiff <= 0.0)
                {
                    lastFrontT = t;
                }
            }

            if (hitParamT < 0.0)
                return hvec4_init(0.0, 0.0, 0.0, 0.0);

            // Phase 2: Binary refinement
            hfloat lo = lastFrontT;
            hfloat hi = hitParamT;
            hvec2 refinedUV = mix(uv0, uv1, hitParamT);
            hfloat refinedDiff = hitDiff;

            for (int j = 0; j < WATER_SSR_REFINEMENT_STEPS; j++)
            {
                hfloat mid = (lo + hi) * 0.5;
                hvec2 midUV = mix(uv0, uv1, mid);
                hfloat midRayZ = 1.0 / mix(k0, k1, mid);
                hfloat midSceneZ = GetLinearDepth(midUV);
                hfloat midDiff = midRayZ - midSceneZ;

                if (midDiff > 0.0)
                {
                    hi = mid;
                    refinedUV = midUV;
                    refinedDiff = midDiff;
                }
                else
                {
                    lo = mid;
                }
            }

            // Confidence: edge fade × thickness fade × distance fade × self-intersection fade
            hfloat screenDistPx = length((refinedUV - uv0) * screenSize);
            hfloat selfIntFade = saturate((screenDistPx - 2.0) / 4.0);

            hvec2 edgeDist = min(refinedUV, 1.0 - refinedUV);
            hfloat edgeFade = saturate(min(edgeDist.x, edgeDist.y) * 6.0);

            hfloat thicknessFade = 1.0 - saturate(refinedDiff / thickness);
            hfloat distanceFade = 1.0 - saturate(hi);

            hfloat confidence = edgeFade * thicknessFade * distanceFade * selfIntFade;

            // Sample scene color at hit point
            hvec3 hitColor = texture2D(sRefractionMap, refinedUV).rgb;

            return hvec4_init(hitColor.x, hitColor.y, hitColor.z, confidence);
        }
    #endif // SSR_WATER
#endif

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    #ifdef SINGLE_LAYER_WATER
        // 场景真实世界坐标
        hvec3 worldPos = GetWorldPos(modelMatrix);
        // 块的世界坐标
        hvec3 blockWorldPos = worldPos - hvec3_init(cTerrainOffset, 0.0f);
    #else
        // 块的世界坐标
        hvec3 blockWorldPos = iPos.xyz;
        // 场景真实世界坐标
        hvec3 worldPos = blockWorldPos + hvec3_init(cTerrainOffset, 0.0f);
    #endif
    gl_Position = GetClipPos(worldPos);
    vWorldPos = hvec4_init(worldPos, GetDepth(gl_Position));
    vScreenPos = GetScreenPos(gl_Position);
    vUV1 = cWaveDensity * (blockWorldPos.xz / cWaveScalerX + cWaterSpeed * cElapsedTimeReal);
    vUV2 = cWaveDensity * (blockWorldPos.xz / cWaveScalerY + cWaterSpeed * cElapsedTimeReal);
    vEyeVec = hvec4_init(cCameraPos - worldPos, GetDepth(gl_Position));
    // Terrain data uv
    vTerrainDataUV = vec3(blockWorldPos.zx / cTerrainSize, 0.0);
    vWaterBlend = iColor.gba;

    #if defined(WATER_SHADOWD) && defined(SHADOW)
        hvec4 projWorldPos = hvec4_init(worldPos, 1.0);
        projWorldPos.y += cWaterShadowOffset;
        GetShadowPos(projWorldPos, vec3(0.0, 1.0, 0.0), vShadowPos);
    #endif
}

void PS()
{
    hvec3 eyeVec = normalize(vEyeVec.xyz);
    // texNormal 是Up-Z下烘焙得到得世界空间法线
    hvec3 texNormal = DecodeNormal(texture2D(sWaterNormalMap, vUV1)) + DecodeNormal(texture2D(sWaterNormalMap, vUV2));
    // 转到Up-Y空间
    hvec3 worldNormal = normalize(texNormal.yzx);

    float NdotV = clamp(dot(worldNormal, eyeVec), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, cFresnelFactor);
    vec2 noise = worldNormal.zx * cNoiseStrength; // worldNormal.zx作为distortion系数

    #if defined(BAKE_REFRACTION)
        vec2 refractUV = vWorldPos.zx / cBakeRefractionTiling;
        refractUV += noise;
    #elif !defined(URHO3D_MOBILE)
        vec2 refractUV = vScreenPos.xy / vScreenPos.w;
        // 世界空间下的深度
        hfloat sceneDepth = GetLinearDepth(refractUV + noise);
        // 避免扰动非水下物体
        if (sceneDepth > vScreenPos.w)
            refractUV += noise;
    #else
        // 移动端使用ColorFetch，放弃noise偏移了
        vec2 refractUV = vScreenPos.xy / vScreenPos.w;
    #endif

    #if defined(COLOR_RAMP)
        float waterDepthNormalized = min(max(sceneDepth - vScreenPos.w, 0.0) / cWaterBlendDepth, 1.0);
        vec4 refra = texture2D(sColorRamp, vec2(waterDepthNormalized, 0.5));
        #ifdef NOT_SUPPORT_SRGB
            refra = GammaToLinearSpace(refra);
        #endif
        fresnel = mix(0.0, fresnel, refra.a);
    #endif

    vec3 waterBottomColor = texture2D(sRefractionMap, refractUV).rgb * cWaterTint;
    #if defined(BAKE_REFRACTION) && defined(NOT_SUPPORT_SRGB)
        waterBottomColor = GammaToLinearSpace(waterBottomColor);
    #endif

    // 环境光diffuse
    #if defined(ENVCUBE)
        #if UNITY_SHOULD_SAMPLE_SH
            vec3 cubeN = worldNormal;
            cubeN.zx = vec2(dot(cubeN.zx, vec2(u_SinCosEnvCubeAngle.y, -u_SinCosEnvCubeAngle.x)), dot(cubeN.zx, u_SinCosEnvCubeAngle.xy));
            vec3 indirectDiffuse = ShadeSHPerPixel(cubeN, cAmbientColor.rgb, cEnvDiffTextureIntensity);
        #else
            vec3 indirectDiffuse = cAmbientColor.rgb;
        #endif
    #else
        vec3 indirectDiffuse = cAmbientColor.rgb;
    #endif

    #if defined(COLOR_RAMP)
        vec4 waterBottomRamp = texture2D(sWaterBottomRamp, vec2(sceneDepth, 0.5));
        #ifdef NOT_SUPPORT_SRGB
            waterBottomRamp = GammaToLinearSpace(waterBottomRamp);
        #endif
        waterBottomColor = mix(waterBottomColor, waterBottomRamp.rgb * (cLightColor.rgb * M_INV_PI + indirectDiffuse), waterBottomRamp.a);
    #endif

    #if defined(BAKE_REFRACTION)
        // 与主光强度关联
        vec3 refrCol = waterBottomColor * cLightColor.rgb * M_INV_PI;
    #else
        // 屏幕空间像素已经是经过光照计算
        vec3 refrCol = waterBottomColor;
    #endif

    #if defined(COLOR_RAMP)
        refrCol = mix(refrCol, refra.rgb * (cLightColor.rgb * M_INV_PI + indirectDiffuse), refra.a);
    #endif

    // 计算云阴影
    #ifdef CLOUD_SHADOW 
        vec4 shadowColor = texture2DArrayLod(sTerrainData, vTerrainDataUV.xyz, 0.0);
        refrCol = refrCol * shadowColor.rgb;
    #endif

    #if defined(WATER_SHADOWD) && defined(SHADOW)
        refrCol = refrCol * GetShadow(vShadowPos, vWorldPos.w);
    #endif

    #if defined(BAKE_REFRACTION)
        refrCol = refrCol + waterBottomColor * indirectDiffuse;
    #endif

    #if defined(ENVCUBE)
        // Use Y-Up
        vec3 worldNormalNoise = mix(hvec3_init(0.0, 1.0, 0.0), worldNormal, cNormalStrength);
        NdotV = clamp(dot(worldNormalNoise, eyeVec), 0.0, 1.0);
        vec3 viewReflection = 2.0 * NdotV * worldNormalNoise - eyeVec; // Same as: -reflect(viewDirection, worldNormalNoise);
        #if RENDER_QUALITY == RENDER_QUALITY_FULL
            // PC采样全贴图
            vec3 reflCol = textureCubeLod(sReflectionCube, viewReflection, 0.0).rgb;
        #elif RENDER_QUALITY == RENDER_QUALITY_HIGH
            // 高端机采样1/2贴图
            vec3 reflCol = textureCubeLod(sReflectionCube, viewReflection, 1.0).rgb;
        #elif RENDER_QUALITY == RENDER_QUALITY_MEDIUM
            // 中端机采样1/4贴图
            vec3 reflCol = textureCubeLod(sReflectionCube, viewReflection, 2.0).rgb;
        #else
            // 低端机采样1/8贴图
            vec3 reflCol = textureCubeLod(sReflectionCube, viewReflection, 3.0).rgb;
        #endif
        reflCol = GammaToLinearSpace(reflCol);
        // 与环境高光关联
        reflCol = reflCol * cWaterReflectionIntensity * M_PI;

        #ifdef SSR_WATER
            // Screen-space reflection: trace from water surface along reflection direction
            hvec3 vsPos = mul(hvec4_init(vWorldPos.x, vWorldPos.y, vWorldPos.z, 1.0), cView).xyz;
            hvec3 vsReflDir = normalize(mul(hvec4_init(viewReflection.x, viewReflection.y, viewReflection.z, 0.0), cView).xyz);
            hvec4 ssrResult = TraceWaterSSR(vsPos, vsReflDir);
            hfloat ssrAlpha = saturate(ssrResult.a * u_SSRWaterIntensity);
            // SSR replaces cubemap where confident (energy conservation)
            reflCol = mix(reflCol, ssrResult.rgb, ssrAlpha);
        #endif
    #else
        vec3 reflCol = cAmbientColor.xyz;
    #endif

    #if 0
        vec3 halfDir = normalize(cLightDirPS + eyeVec);
		float specPow = exp2(cSpecularGloss * 10.0);
        vec3 specular = pow(max(0, dot(halfDir, worldNormal)), specPow) * cSpecularFactor * depth * cLightColor.rgb;
    #else
        vec3 specular = vec3(0.0, 0.0, 0.0);
    #endif

    float reflIntensity = clamp(cReflection * fresnel, 0.0, 1.0);

    vec3 finalColor = mix(refrCol, reflCol, reflIntensity) + specular;

    // 计算云雾
    #ifdef CLOUD_SHADOW
        finalColor = mix(finalColor, cCloudFogColor, shadowColor.a);
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    // Mix final color and fog
    finalColor = GetFog(finalColor, fogFactor);

    // Fog of war
    #ifdef FOGOFWAR
        finalColor = GetFogOfWar(finalColor, vTerrainDataUV.xy);
    #endif

    // Final color
    #ifdef SINGLE_LAYER_WATER       
        gl_FragColor = vec4(finalColor, 1.0);
    #else
        gl_FragColor = vec4(finalColor, vWaterBlend.x * sqrt(sqrt(vWaterBlend.y + 0.05)) + vWaterBlend.z);
    #endif

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
	    gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
	#endif
    #ifdef PURE_MINIMAP
        gl_FragColor.rgb = u_WaterColor.rgb;
    #endif
}
