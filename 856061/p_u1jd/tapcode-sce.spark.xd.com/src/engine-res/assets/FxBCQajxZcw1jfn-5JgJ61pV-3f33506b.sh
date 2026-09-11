#ifndef __LIGHTING_SH__
#define __LIGHTING_SH__

#ifdef SHADOW
#if defined(DIRLIGHT) && (!defined(MOBILE_SHADOW) || defined(WEBGL))
    #ifdef DESKTOP_SHADOW_CASCADE
        #define _ISHADOWPOS const hvec4 iShadowPos0, const hvec4 iShadowPos1,  const hvec4 iShadowPos2, const hvec4 iShadowPos3
        #define _OSHADOWPOS out hvec4 shadowPos0, out hvec4 shadowPos1, out hvec4 shadowPos2, out hvec4 shadowPos3
        #define iShadowPos iShadowPos0, iShadowPos1, iShadowPos2, iShadowPos3
    #else
        #define _ISHADOWPOS const hvec4 iShadowPos0, const hvec4 iShadowPos1
        #define _OSHADOWPOS out hvec4 shadowPos0, out hvec4 shadowPos1
        #define iShadowPos iShadowPos0, iShadowPos1
    #endif
#else
    #define _ISHADOWPOS const hvec4 iShadowPos0
    #define iShadowPos iShadowPos0
    #define _OSHADOWPOS out hvec4 shadowPos0
#endif
#else
    #define _ISHADOWPOS
#endif

#if COMPILEVS
vec3 GetAmbient(float zonePos)
{
    return cAmbientStartColor + zonePos * cAmbientEndColor;
}

#ifdef NUMVERTEXLIGHTS
float GetVertexLight(int index, hvec3 worldPos, vec3 normal)
{
    vec3 lightDir = cVertexLights[index * 3 + 1].xyz;
    vec3 lightPos = cVertexLights[index * 3 + 2].xyz;
    float invRange = cVertexLights[index * 3].w;
    float cutoff = cVertexLights[index * 3 + 1].w;
    float invCutoff = cVertexLights[index * 3 + 2].w;

    // Directional light
    if (invRange == 0.0)
    {
        #ifdef TRANSLUCENT
            float NdotL = abs(dot(normal, lightDir));
        #else
            float NdotL = max(dot(normal, lightDir), 0.0);
        #endif
        return NdotL;
    }
    // Point/spot light
    else
    {
        vec3 lightVec = (lightPos - worldPos) * invRange;
        float lightDist = length(lightVec);
        vec3 localDir = lightVec / lightDist;
        #ifdef TRANSLUCENT
            float NdotL = abs(dot(normal, localDir));
        #else
            float NdotL = max(dot(normal, localDir), 0.0);
        #endif
        float atten = clamp(1.0 - lightDist * lightDist, 0.0, 1.0);
        float spotEffect = dot(localDir, lightDir);
        float spotAtten = clamp((spotEffect - cutoff) * invCutoff, 0.0, 1.0);
        return NdotL * atten * spotAtten;
    }
}

float GetVertexLightVolumetric(int index, hvec3 worldPos)
{
    vec3 lightDir = cVertexLights[index * 3 + 1].xyz;
    vec3 lightPos = cVertexLights[index * 3 + 2].xyz;
    float invRange = cVertexLights[index * 3].w;
    float cutoff = cVertexLights[index * 3 + 1].w;
    float invCutoff = cVertexLights[index * 3 + 2].w;

    // Directional light
    if (invRange == 0.0)
        return 1.0;
    // Point/spot light
    else
    {
        vec3 lightVec = (lightPos - worldPos) * invRange;
        float lightDist = length(lightVec);
        vec3 localDir = lightVec / lightDist;
        float atten = clamp(1.0 - lightDist * lightDist, 0.0, 1.0);
        float spotEffect = dot(localDir, lightDir);
        float spotAtten = clamp((spotEffect - cutoff) * invCutoff, 0.0, 1.0);
        return atten * spotAtten;
    }
}
#endif

#ifdef SHADOW

#if defined(DIRLIGHT) && (!defined(MOBILE_SHADOW) || defined(WEBGL))
    #ifdef DESKTOP_SHADOW_CASCADE
        #define NUMCASCADES 4
    #else
        #define NUMCASCADES 2
    #endif
#else
    #define NUMCASCADES 1
#endif

void GetShadowPos(hvec4 projWorldPos, vec3 normal, _OSHADOWPOS)
{
    // Shadow projection: transform from world space to shadow space
    #ifdef NORMALOFFSET
        #ifdef DIRLIGHT
            float cosAngle = clamp(1.0 - dot(normal, cLightDir), 0.0, 1.0);
        #else
            float cosAngle = clamp(1.0 - dot(normal, normalize(cLightPos.xyz - projWorldPos.xyz)), 0.0, 1.0);
        #endif

        #if defined(DIRLIGHT)
            shadowPos0 = mul(vec4(projWorldPos.xyz + cosAngle * cNormalOffsetScale.x * normal, 1.0), cLightMatrices[0]);
            #if defined(DESKTOP_SHADOW_CASCADE) || defined(MOBILE_SHADOW_CASCADE)
                shadowPos1 = mul(vec4(projWorldPos.xyz + cosAngle * cNormalOffsetScale.y * normal, 1.0), cLightMatrices[1]);
            #endif
            #if defined(DESKTOP_SHADOW_CASCADE)
                shadowPos2 = mul(vec4(projWorldPos.xyz + cosAngle * cNormalOffsetScale.z * normal, 1.0), cLightMatrices[2]);
                shadowPos3 = mul(vec4(projWorldPos.xyz + cosAngle * cNormalOffsetScale.w * normal, 1.0), cLightMatrices[3]);
            #endif
        #elif defined(SPOTLIGHT)
            shadowPos0 = mul(vec4(projWorldPos.xyz + cosAngle * cNormalOffsetScale.x * normal, 1.0), cLightMatrices[1]);
        #else
            shadowPos0 = vec4(projWorldPos.xyz + cosAngle * cNormalOffsetScale.x * normal - cLightPos.xyz, 0.0);
        #endif
    #else
        #if defined(DIRLIGHT)
            shadowPos0 = mul(projWorldPos, cLightMatrices[0]);
            #if defined(DESKTOP_SHADOW_CASCADE) || defined(MOBILE_SHADOW_CASCADE)
                shadowPos1 = mul(projWorldPos, cLightMatrices[1]);
            #endif
            #if defined(DESKTOP_SHADOW_CASCADE)
                shadowPos2 = mul(projWorldPos, cLightMatrices[2]);
                shadowPos3 = mul(projWorldPos, cLightMatrices[3]);
            #endif
        #elif defined(SPOTLIGHT)
            shadowPos0 = mul(projWorldPos, cLightMatrices[1]);
        #else
            shadowPos0 = vec4(projWorldPos.xyz - cLightPos.xyz, 0.0);
        #endif
    #endif
}

#endif
#endif

#if COMPILEPS
float GetDiffuse(vec3 normal, hvec3 worldPos, out vec3 lightDir)
{
    #ifdef DIRLIGHT
        lightDir = cLightDirPS;
        #ifdef TRANSLUCENT
            return abs(dot(normal, lightDir));
        #else
            return max(dot(normal, lightDir), 0.0);
        #endif
    #else
        vec3 toLight = cLightPosPS.xyz - worldPos;
        float distSqr = dot(toLight, toLight);
        float falloff = 1.0 / max(distSqr, 0.0001);
        // cLightPosPS.w is 1 / AttenuationRadius
        float lightRadiusMask = Square(saturate(1.0 - Square(distSqr * (cLightPosPS.w * cLightPosPS.w))));
        falloff *= lightRadiusMask;
        // <==> normalize(toLight)
        lightDir = toLight / sqrt(distSqr);
        return falloff;
    #endif
}

float GetAtten(vec3 normal, hvec3 worldPos, out vec3 lightDir)
{
    lightDir = cLightDirPS;
    return clamp(dot(normal, lightDir), 0.0, 1.0);
}

float GetAttenPoint(vec3 normal, hvec3 worldPos, out vec3 lightDir)
{
    vec3 lightVec = (cLightPosPS.xyz - worldPos) * cLightPosPS.w;
    float lightDist = length(lightVec);
    float falloff = pow(clamp(1.0 - pow(lightDist / 1.0, 4.0), 0.0, 1.0), 2.0) * 3.14159265358979323846 / (4.0 * 3.14159265358979323846)*(pow(lightDist, 2.0) + 1.0);
    lightDir = lightVec / lightDist;
    return clamp(dot(normal, lightDir), 0.0, 1.0) * falloff;

}

float GetAttenSpot(vec3 normal, hvec3 worldPos, out vec3 lightDir)
{
    vec3 lightVec = (cLightPosPS.xyz - worldPos) * cLightPosPS.w;
    float lightDist = length(lightVec);
    float falloff = pow(clamp(1.0 - pow(lightDist / 1.0, 4.0), 0.0, 1.0), 2.0) / (pow(lightDist, 2.0) + 1.0);

    lightDir = lightVec / lightDist;
    return clamp(dot(normal, lightDir), 0.0, 1.0) * falloff;

}

float GetDiffuseVolumetric(hvec3 worldPos)
{
    #ifdef DIRLIGHT
        return 1.0;
    #else
        vec3 lightVec = (cLightPosPS.xyz - worldPos) * cLightPosPS.w;
        float lightDist = length(lightVec);
        return texture2D(sLightRampMap, vec2(lightDist, 0.0)).r;
    #endif
}

float GetSpecular(vec3 normal, vec3 eyeVec, vec3 lightDir, float specularPower)
{
    vec3 halfVec = normalize(normalize(eyeVec) + lightDir);  
    return pow(max(dot(normal, halfVec), 0.0), specularPower);
}

float GetIntensity(vec3 color)
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

#ifdef SHADOW

#if defined(DIRLIGHT) && (!defined(MOBILE_SHADOW) || defined(WEBGL))
    #ifdef DESKTOP_SHADOW_CASCADE
        #define NUMCASCADES 4
    #else
        #define NUMCASCADES 2
    #endif
#else
    #define NUMCASCADES 1
#endif

#ifdef VSM_SHADOW
float ReduceLightBleeding(float min, float p_max)  
{  
    return clamp((p_max - min) / (1.0 - min), 0.0, 1.0);  
}

float Chebyshev(vec2 Moments, float depth)  
{  
    //One-tailed inequality valid if depth > Moments.x  
    float p = float(depth <= Moments.x);  
    //Compute variance.  
    float Variance = Moments.y - (Moments.x * Moments.x); 

    float minVariance = cVSMShadowParams.x;
    Variance = max(Variance, minVariance);
    //Compute probabilistic upper bound.  
    float d = depth - Moments.x;  
    float p_max = Variance / (Variance + d*d); 
    // Prevent light bleeding
    p_max = ReduceLightBleeding(cVSMShadowParams.y, p_max);

    return max(p, p_max);
}
#endif

#ifndef MOBILE_SHADOW
hfloat GetShadow(hvec4 shadowPos)
{
    #if defined(SIMPLE_SHADOW)
        // Take one sample
        hfloat inLight = shadow2DProj(sShadowMap, shadowPos);
        return cShadowIntensity.y + cShadowIntensity.x * inLight;
    #elif defined(PCF_SHADOW)
        // Take sixteen samples and average them. ShadowIntensity is pre-divided by 4 on the C++ side.
        // Note: in case of sampling a point light cube shadow, we optimize out the w divide as it has already been performed
        #ifndef POINTLIGHT
            hvec2 offsets = cShadowMapInvSize * shadowPos.w;
        #else
            hvec2 offsets = cShadowMapInvSize;
        #endif
        hfloat inLight =
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 1.5 * offsets.x, shadowPos.y - 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 0.5 * offsets.x, shadowPos.y - 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 0.5 * offsets.x, shadowPos.y - 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 1.5 * offsets.x, shadowPos.y - 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 1.5 * offsets.x, shadowPos.y - 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 0.5 * offsets.x, shadowPos.y - 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 0.5 * offsets.x, shadowPos.y - 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 1.5 * offsets.x, shadowPos.y - 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 1.5 * offsets.x, shadowPos.y + 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 0.5 * offsets.x, shadowPos.y + 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 0.5 * offsets.x, shadowPos.y + 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 1.5 * offsets.x, shadowPos.y + 0.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 1.5 * offsets.x, shadowPos.y + 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x - 0.5 * offsets.x, shadowPos.y + 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 0.5 * offsets.x, shadowPos.y + 1.5 * offsets.y, shadowPos.zw)) +
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + 1.5 * offsets.x, shadowPos.y + 1.5 * offsets.y, shadowPos.zw));
        return cShadowIntensity.y + inLight * cShadowIntensity.x * 0.25;
    #elif defined(VSM_SHADOW)
        vec2 samples = texture2D(sShadowMap, shadowPos.xy / shadowPos.w).rg; 
        return cShadowIntensity.y + cShadowIntensity.x * Chebyshev(samples, shadowPos.z / shadowPos.w);
    #else
        return 1.0;
    #endif
}
#else
hfloat GetShadow(hvec4 shadowPos)
{
    #if defined(SIMPLE_SHADOW)
        // Take one sample
        return cShadowIntensity.y + (shadow2DProj(sShadowMap, shadowPos) * shadowPos.w > shadowPos.z ? cShadowIntensity.x : 0.0);
    #elif defined(PCF_SHADOW)
    // #if BGFX_SHADER_LANGUAGE_METAL
    #if 0
        return cShadowIntensity.y + shadow2DProj(sShadowMap, shadowPos) * cShadowIntensity.x * 4.0;
    #else
        // Take four samples and average them
        hvec2 offsets = cShadowMapInvSize;
        hvec4 inLight = hvec4_init(
            shadow2DProj(sShadowMap, shadowPos),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x + offsets.x, shadowPos.yzw)),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.x, shadowPos.y + offsets.y, shadowPos.zw)),
            shadow2DProj(sShadowMap, hvec4_init(shadowPos.xy + offsets.xy, shadowPos.zw))
        );
        return cShadowIntensity.y + dot(inLight, hvec4_init(cShadowIntensity.x, cShadowIntensity.x, cShadowIntensity.x, cShadowIntensity.x));
    #endif
    #elif defined(VSM_SHADOW)
        vec2 samples = texture2D(sShadowMap, shadowPos.xy / shadowPos.w).rg; 
        return cShadowIntensity.y + cShadowIntensity.x * Chebyshev(samples, shadowPos.z / shadowPos.w);
    #endif
}
#endif

#ifdef POINTLIGHT
float GetPointShadow(hvec3 lightVec)
{
    vec3 axis = textureCube(sFaceSelectCubeMap, lightVec).rgb;
    float depth = abs(dot(lightVec, axis));

    // Expand the maximum component of the light vector to get full 0.0 - 1.0 UV range from the cube map,
    // and to avoid sampling across faces. Some GPU's filter across faces, while others do not, and in this
    // case filtering across faces is wrong
    vec3 factor = vec3_splat(1.0 / 256.0);
    lightVec += factor * axis * lightVec;

    // Read the 2D UV coordinates, adjust according to shadow map size and add face offset
    vec4 indirectPos = textureCube(sIndirectionCubeMap, lightVec);
    indirectPos.xy *= cShadowCubeAdjust.xy;
    indirectPos.xy += vec2(cShadowCubeAdjust.z + indirectPos.z * 0.5, cShadowCubeAdjust.w + indirectPos.w);

    vec4 shadowPos = vec4(indirectPos.xy, cShadowDepthFade.x + cShadowDepthFade.y / depth, 1.0);
    return GetShadow(shadowPos);
}
#endif // POINTLIGHT

#ifdef DIRLIGHT
float GetDirShadowFade(float inLight, hfloat depth)
{
    return min(inLight + max((depth - cShadowDepthFade.z) * cShadowDepthFade.w, 0.0), 1.0);
}

float GetDirShadow(_ISHADOWPOS, hfloat depth)
{
#if defined(DESKTOP_SHADOW_CASCADE) // 桌面ShadowCascade级联=4
    hvec4 shadowPos;
    if (depth < cShadowSplits.x)
        shadowPos = iShadowPos0;
    else if (depth < cShadowSplits.y)
        shadowPos = iShadowPos1;
    else if (depth < cShadowSplits.z)
        shadowPos = iShadowPos2;
    else
        shadowPos = iShadowPos3;
#elif defined(MOBILE_SHADOW_CASCADE) // 移动端ShadowCascade级联=2
    hvec4 shadowPos;
    if (depth < cShadowSplits.x)
        shadowPos = iShadowPos0;
    else
        shadowPos = iShadowPos1;
#else
    hvec4 shadowPos = iShadowPos0;
#endif
        
    return GetDirShadowFade(GetShadow(shadowPos), depth);
}

#ifndef URHO3D_MOBILE
float GetDirShadowDeferred(hvec4 projWorldPos, vec3 normal, hfloat depth)
{
    hvec4 shadowPos;

    #ifdef NORMALOFFSET
        float cosAngle = clamp(1.0 - dot(normal, cLightDirPS), 0.0, 1.0);
        if (depth < cShadowSplits.x)
            shadowPos = mul(hvec4_init(projWorldPos.xyz + cosAngle * cNormalOffsetScalePS.x * normal, 1.0), cLightMatricesPS[0]);
        else if (depth < cShadowSplits.y)
            shadowPos = mul(hvec4_init(projWorldPos.xyz + cosAngle * cNormalOffsetScalePS.y * normal, 1.0), cLightMatricesPS[1]);
        else if (depth < cShadowSplits.z)
            shadowPos = mul(hvec4_init(projWorldPos.xyz + cosAngle * cNormalOffsetScalePS.z * normal, 1.0), cLightMatricesPS[2]);
        else
            shadowPos = mul(hvec4_init(projWorldPos.xyz + cosAngle * cNormalOffsetScalePS.w * normal, 1.0), cLightMatricesPS[3]);
    #else
        if (depth < cShadowSplits.x)
            shadowPos = mul(projWorldPos, cLightMatricesPS[0]);
        else if (depth < cShadowSplits.y)
            shadowPos = mul(projWorldPos, cLightMatricesPS[1]);
        else if (depth < cShadowSplits.z)
            shadowPos = mul(projWorldPos, cLightMatricesPS[2]);
        else
            shadowPos = mul(projWorldPos, cLightMatricesPS[3]);
    #endif

    return GetDirShadowFade(GetShadow(shadowPos), depth);
}
#endif // URHO3D_MOBILE
#endif // DIRLIGHT

float GetShadow(_ISHADOWPOS, hfloat depth)
{
    #if defined(DIRLIGHT)
        return GetDirShadow(iShadowPos, depth);
    #elif defined(SPOTLIGHT)
        return GetShadow(iShadowPos);
    #else
        return GetPointShadow(iShadowPos.xyz);
    #endif
}

#ifndef URHO3D_MOBILE
float GetShadowDeferred(hvec4 projWorldPos, vec3 normal, hfloat depth)
{
    #ifdef DIRLIGHT
        return GetDirShadowDeferred(projWorldPos, normal, depth);
    #else
        #ifdef NORMALOFFSET
            float cosAngle = clamp(1.0 - dot(normal, normalize(cLightPosPS.xyz - projWorldPos.xyz)), 0.0, 1.0);
            projWorldPos.xyz += cosAngle * cNormalOffsetScalePS.x * normal;
        #endif

        #ifdef SPOTLIGHT
            hvec4 shadowPos = mul(projWorldPos, cLightMatricesPS[1]);
            return GetShadow(shadowPos);
        #else
            hvec3 shadowPos = projWorldPos.xyz - cLightPosPS.xyz;
            return GetPointShadow(shadowPos);
        #endif
    #endif
}
#endif // URHO3D_MOBILE
#endif
#endif

#endif
