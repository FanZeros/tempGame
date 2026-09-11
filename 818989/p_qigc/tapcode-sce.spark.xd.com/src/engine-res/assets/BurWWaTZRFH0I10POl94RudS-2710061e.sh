#ifndef __FOG_SH__
#define __FOG_SH__

#if COMPILEPS
vec3 GetFog(vec3 color, float fogFactor)
{
    return mix(cFogColor, color, fogFactor);
}

vec3 GetLitFog(vec3 color, float fogFactor)
{
    return color * fogFactor;
}
// fogfactor 是1-fog 的权重
// fogParams(depthFogStart, depthFogRange, depthFogDensity, 0.0);
// fogParams2(fogFalloff * fogScale / 100.0, fogHeight, fog.heightFogDensity_, 0.0);
float GetFogFactor(float distance)
{
    vec3 param = cFogParams.xyz;
    float factor = clamp((distance - param.x)/param.y, 0.0, 1.0);
    return 1.0 - factor * param.z;
}

float GetHeightFogFactor(float distance, float height)
{
    vec3 param = cFogParams2.xyz;
    float fogFactor = GetFogFactor(distance);
    float heightFogFactor = (height - param.y) * param.x;
    heightFogFactor = 1.0 - param.z *clamp(exp(-(heightFogFactor * heightFogFactor)),step(height, param.y) - 0.00001, 1.0);
    return min(heightFogFactor, fogFactor);
}

vec3 GetFogOfWar(vec3 color, vec2 fogUV)
{
    float lstFOW = texture2DArrayLod(sFogOfWar, vec3(fogUV, cFOWLayer), 0.0).x;
    float nowFOW = texture2DArrayLod(sFogOfWar, vec3(fogUV, 1.0 - cFOWLayer), 0.0).x;
    float delta = nowFOW - lstFOW;
    float positiveDelta = max(delta, 0.0);
    float negativeDelta = min(delta, 0.0);
    float actualFOW = nowFOW - positiveDelta + positiveDelta * cFOWBlend;
    float FOWOpenSpeed = clamp(cFOWOpenSpeed, 0.0, 1.0);
    actualFOW = actualFOW - negativeDelta * FOWOpenSpeed;
    vec3 fogColor = (cFOWColor - cFOWRangeColor) * actualFOW + cFOWRangeColor + vec3(-1.0, -1.0, -1.0);
    fogColor = (1.0 - cFOWBrightness) * actualFOW * fogColor + vec3(1.0, 1.0, 1.0);
    return color * clamp(fogColor, vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0));
}
#endif

#endif















