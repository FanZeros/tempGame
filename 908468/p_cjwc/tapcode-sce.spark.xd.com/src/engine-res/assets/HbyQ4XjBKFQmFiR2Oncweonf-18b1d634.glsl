#ifdef WEATHER_EFFECT

void WeatherEffect(inout vec3 diffuseColor, inout float roughness, inout float metallic, inout vec3 normalDirection)
{
    vec3 weatherColor  = texture2DArray(sWeatherMap1, vec3(vTerrainDataUV.zw, cWeatherSampleLayer));   // layer=0 => base color
    vec4 weatherNormal = texture2DArray(sWeatherMap2, vec3(vTerrainDataUV.zw, cWeatherSampleLayer));   // layer=1 => mix => rg: normal, b: roughness, a: metallic
    float weatherRoughness = weatherNormal.b;
    float weatherMetallic  = weatherNormal.a;
    weatherNormal.xyz = DecodeNormal(weatherNormal);

    float factor0 = 1.0 - clamp((__GET_HEIGHT__(vWorldPos) - vDrawableInfo.x) / cWeatherHeightBlend, 0.0, 1.0);
    float factor1 = CheapContrast(max(vNormal.z, factor0) - cWeatherOffset, cWeatherContrast);
    float factor2 = CheapContrast(max(normalDirection.z, factor0) - cWeatherOffset, cWeatherContrast);

    diffuseColor    = mix(mix(diffuseColor,    weatherColor,     factor1), weatherColor,     factor2);
    roughness       = mix(mix(roughness,       weatherRoughness, factor1), weatherRoughness, factor2);
    metallic        = mix(mix(metallic,        weatherMetallic,  factor1), weatherMetallic,  factor2);
    normalDirection = mix(normalDirection, weatherNormal.xyz,    factor1);
}
#endif
