// #define KK_LIGHTING 1

// Kajiya-Kay 光照模型
vec3 TTShiftTangent(vec3 T, vec3 N, float shift)
{
    return normalize(T + N * shift);
}

#ifdef KK_LIGHTING
float StrandSpecular(vec3 T, vec3 V, vec3 L, float exponent)
{
    vec3 halfDir   = normalize(L + V);
    float dotTH    = dot(T, halfDir);
    float sinTH    = max(0.01, sqrt(1.0 - dotTH * dotTH));
    float dirAtten = smoothstep(-1, 0, dotTH);
    return dirAtten * pow(sinTH, exponent);
}
#else
float YYSpecular(vec3 T, vec3 V, vec3 L)
{
    vec3 halfDir   = L + V;
    float dotTH    = dot(T, halfDir);
    float sinTH    = sqrt(1.0 - dotTH * dotTH);
    return clamp(sinTH - _HairWidth, 0.0, 1.0);
}
#endif

vec3 HairSimulationBRDF(vec3 diffuseColor, float shift, vec3 viewDirection, vec3 shadow, float occlusion)
{
// 必须带NORMALMAP宏，否则没有切线无法计算
#ifdef NORMALMAP
    vec3 lightVec = cLightDirPS;
    vec3 lightColor = cLightColor.rgb;
    
    #ifdef KK_LIGHTING
        float primaryShift = 0.0;
        float secondaryShift = 0.1;
        vec3 specularColor1 = vec3(0.1, 0.1, 0.1);
        vec3 specularColor2 = vec3(0.0, 0.0, 0.0);
        float specExp1 = 0.5;
        float specExp2 = 0.5;

        vec3 normalDirection  = vNormal;
        vec3 tangentDirection = vTangent.xyz;

        // shift tangents 
        float _shift = shift - 0.5;
        vec3 t1 = TTShiftTangent(tangentDirection, normalDirection, primaryShift + _shift);
        vec3 t2 = TTShiftTangent(tangentDirection, normalDirection, secondaryShift + _shift);
        
        // diffuse lighting: the lerp shifts the shadow boundary for a softer look
        vec3 diffuse = saturate(mix(0.25, 1.0, dot(normalDirection, lightVec)));
        diffuse *= diffuseColor;

        // specular lighting 
        vec3 specular = specularColor1 * StrandSpecular(t1, viewDirection, lightVec, specExp1);
        // add 2nd specular term, modulated with noise texture
        float specMask = shift; // approximate sparkles using textures
        // 使用纹理近似闪光
        specular += specularColor2 * specMask * StrandSpecular(t2, viewDirection, lightVec, specExp2);
    #else
        #if 1
            vec3 row0 = vTangent.xyz;
            vec3 row1 = vec3(vTexCoord.zw, vTangent.w);
            vec3 row2 = vNormal;
            vec3 normalDirection  = vec3(dot(row0, vNormal), dot(row1, vNormal), dot(row2, vNormal));
            vec3 tangentDirection = cross(normalDirection, vec3(0.0, 1.0, 0.0));
            viewDirection         = vec3(dot(row0, viewDirection), dot(row1, viewDirection), dot(row2, viewDirection));
        #else
            vec3 normalDirection  = vNormal;
            vec3 tangentDirection = vTangent.xyz;
        #endif

        // shift tangents
        tangentDirection = TTShiftTangent(tangentDirection, normalDirection, shift - 0.5);

        // diffuse lighting: the lerp shifts the shadow boundary for a softer look
        vec3 diffuse = vec3_splat(saturate(mix(0.25, 1.0, dot(normalDirection, lightVec))));
        diffuse *= diffuseColor * mix(0.3, 0.45, luma(diffuseColor).x);

        // specular lighting
        vec3 specular = vec3_splat(YYSpecular(tangentDirection, viewDirection, vec3(-0.6324, 0.08569, 0.76929)) * _HairSpecular);
        // _HairSpecular  |  t
        //      1         | 1.0
        //      2         | 0.25
        //      3         | 0.0625
        //      4         | 0.0625
        //      5         | 0.0625
        float t = max(1.0 / pow(4.0, max(_HairSpecular - 1.0, 0.0)), 0.0625);
        specular = specular * (smoothstep(0.0, 7.0, luma(lightColor).x) + t) * 1.5;
    #endif
    
    // final color assembly
    vec3 finalColor = min((diffuse * lightColor + specular) * M_INV_PI, vec3(1.0, 1.0, 1.0));
    // finalColor *= occlusion;    // modulate color by ambient occlusion term

    return finalColor;
#else
    return vec3(0.0, 0.0, 0.0);
#endif
}
