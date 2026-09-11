#ifndef __LIGHTMAP_SH__
#define __LIGHTMAP_SH__

#define TILE_BLOCK_SIZE 8.f

#ifdef COMPILEVS
vec2 GetLightMapUV(vec2 uv)
{
    //CLIFF虽然会有instance的宏但没有instance的数据
    #if defined(INSTANCED) && !defined(CLIFF1) && !defined(CLIFF2)
        vec4 bias = iLightMapBias;
    #else
        vec4 bias = cLightMapBias;
    #endif
    
    vec2 lightMapUV = uv * bias.zw + bias.xy;
#ifdef LIGHTMAP_DIRECTIONALITY
    lightMapUV.y = lightMapUV.y * 0.5;
#endif
    return lightMapUV;
}
vec2 GetTileLightMapUV(vec2 pos, vec2 tileSize)
{
    #if defined(INSTANCED)
        vec4 bias = iLightMapBias;
    #else
        vec4 bias = cLightMapBias;
    #endif
    vec2 blockSize = TILE_BLOCK_SIZE * tileSize;
    vec2 blockIndex = pos / blockSize;
    vec2 lightMapUV = (blockIndex - bias.xy) * bias.zw;
#ifdef LIGHTMAP_DIRECTIONALITY
    //避免地形溢出到方向的半图，其他2U边缘会padding所以不会有问题
    lightMapUV.y = clamp(lightMapUV.y * 0.5, 0.001, 0.499);
#endif
    return lightMapUV;
}
#endif

#ifdef COMPILEPS
vec4 GetLightMapColor(vec2 uv, vec3 normalDirection
#if RENDER_QUALITY >= RENDER_QUALITY_HIGH && defined(LIGHTMAP_DIRECTIONALITY)
, out vec3 lightMapDir
#endif
)
{
//悬崖打散了重新分的2U，用自动的mipmap容易出接缝（除非后续做手动mipmap)
#if defined(CLIFF1) || defined(CLIFF2)
    vec4 lightMapColor = texture2DLod(sLightMap, uv, 0.0);
    //悬崖一些不受光的三角面会给-1的uv，但是可能会被clamp到0，这里裁剪掉
    float cullmask = step(-0.1, uv.x);
#else
    vec4 lightMapColor = texture2D(sLightMap, uv);
    float cullmask = 1.0;
#endif
    lightMapColor.rgb = cLightMapScale0 * lightMapColor.rgb * lightMapColor.w;
#ifdef LIGHTMAP_DIRECTIONALITY
    uv.y = uv.y + 0.5;
#if defined(CLIFF1) || defined(CLIFF2)
    vec4 sh = texture2DLod(sLightMap, uv, 0.0);
#else
    vec4 sh = texture2D(sLightMap, uv);
#endif
    sh.rgb = 2.0 * sh.rgb * cLightMapScale1 * sh.w - float(1.0).xxx;
    float directionality = dot(normalDirection, sh.zxy);
    directionality = max(directionality, 0.0);
#if RENDER_QUALITY >= RENDER_QUALITY_HIGH
    lightMapDir = sh.zxy;
#endif

    lightMapColor.rgb = cullmask * (directionality * sh.w + 1.0 - sh.w) * lightMapColor.rgb;
#endif
    return lightMapColor;
}

#if defined(SPEED_GRASS) || defined(SCE_GRASS)
vec4 GetGrassLightMapColor(vec2 uv, vec3 normalDirection, vec3 pos)
{
    vec4 lightMapColor = texture2D(sLightMap, uv);
    lightMapColor.rgb = cLightMapScale0 * lightMapColor.rgb * lightMapColor.w;
    float corr = 1.0;
#ifdef LIGHTMAP_DIRECTIONALITY
    float lum = vec3(0.3, 0.6, 0.1) * lightMapColor.rgb;
    //这大概相当于20cm的偏移
    vec2 deltaUV = uv + vec2(0.001, 0.001);
    vec4 relativeColor = texture2D(sLightMap, deltaUV);
    relativeColor.rgb = cLightMapScale0 * relativeColor.rgb * relativeColor.w;
    float relativeLum = vec3(0.3, 0.6, 0.1) * relativeColor.rgb;
    uv.y = uv.y + 0.5;
    deltaUV.y = deltaUV.y + 0.5;
    vec4 sh = texture2D(sLightMap, uv);

    sh.xyz = 2.0 * sh.xyz * cLightMapScale1 * sh.w - float(1.0).xxx;
    float ndl = max(sh.y, 0.01);
    //hack
    vec4 relativeDirection = texture2D(sLightMap, deltaUV);
    relativeDirection.xyz = 2.0 * relativeDirection.xyz * cLightMapScale1 * relativeDirection.w - float(1.0).xxx;
    float cosTheta = clamp(dot(relativeDirection.xyz, sh.xyz), 0.0, 1.0);
    hfloat k = (lum + 1e-4) / (relativeLum + 1e-4);
    hfloat rtk = sqrt(k);
    hfloat distSqr = 6000.0 / (1.0 + k - 2.0 * rtk * cosTheta + 1e-4);
    float dist = sqrt(distSqr);
    float mask = 0.01 / (lum + 1e-4);
    mask = clamp(1.0 - mask * mask, 0.0, 1.0);
    mask = mask * mask;
    vec3 dir = dist * sh.zxy;
    dir.z -= pos.z;
    float distSqr1 = dot(dir, dir);
    corr = 1.0 * (mask * distSqr / (ndl * distSqr1 + 1e-4));

    float directionality = dot(normalDirection, sh.zxy);
    directionality = max(directionality, 0.0);
    lightMapColor.rgb = (directionality * sh.w + 1.0 - sh.w) * lightMapColor.rgb;
#endif // LIGHTMAP_DIRECTIONALITY
    return lightMapColor * corr;
}

vec4 GetLambertGrassLightMapColor(vec2 uv, vec3 normalDirection, vec3 pos)
{
    vec4 lightMapColor = texture2D(sLightMap, uv);
    lightMapColor.rgb = cLightMapScale0 * lightMapColor.rgb * lightMapColor.w;
    
#ifdef LIGHTMAP_DIRECTIONALITY
    uv.y = uv.y + 0.5;
    vec4 sh = texture2D(sLightMap, uv);
    vec3 dir0 = normalize(2.0 * sh.zxy * cLightMapScale1 * sh.w - float(1.0).xxx);
    float lum = dot(vec3(0.3, 0.6, 0.1), lightMapColor.rgb);
    vec2 posxdiff = dFdx(pos.xy);
    vec2 posydiff = dFdy(pos.xy);
    float lumdiff = abs(dFdx(lum));

    vec2 crosstmp = abs(posxdiff.xy * posydiff.yx);
    float diffArea = abs(crosstmp.x - crosstmp.y);
    float l = sqrt(diffArea);
    float k = 1.0 - lumdiff / (lum + lumdiff + 1e-4);
    
    float mask = 0.01 / (lum + 1e-4);
    mask = clamp(1.0 - mask * mask, 0.0, 1.0);
    mask = mask * mask;
    float ndl = max(dir0.z, 0.01);
    float gndl = dot(normalDirection, dir0);
    
    float cosAlpha = dot(dir0, normalize(vec3(dir0.xy, 0.0)));
    float sinAlpha = sqrt(1.0 - cosAlpha * cosAlpha);
    float x = (1.0 - k) / (1.0 + (cosAlpha + sqrt(saturate(k - sinAlpha * sinAlpha))) * l);
    //比起亮度准确，更追求平滑均匀一些
    float sin2Alpha = clamp(sinAlpha - pos.z * x, 0.7 * sinAlpha, sinAlpha);
    float rate = cosAlpha * cosAlpha + sin2Alpha * sin2Alpha + 1e-4;
    lightMapColor.rgb = lightMapColor.rgb * mask * (gndl / (rate * ndl));
#endif
    return lightMapColor;
}
#endif

#endif //COMPILEPS

#endif
