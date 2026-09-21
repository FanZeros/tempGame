#ifdef COMPILEPS
vec2 GetBlendTwoFactor(vec2 height, vec2 weight)
{
    vec2 _height = height + weight;
    float maxHW = max(_height.x, _height.y) - 0.2;
    vec2 _weight = max(_height - maxHW, vec2(0.0001, 0.0001));
    vec2 blendFactor = _weight / (_weight.x + _weight.y);
    return blendFactor;
}

vec3 GetBlendThreeFactor(vec3 height, vec3 weight)
{
    vec3 _height = height + weight;
    float maxHW = max(max(_height.x, _height.y), _height.z) - 0.2;
    vec3 _weight = max(_height - maxHW, vec3(0.0001, 0.0001, 0.0001));
    vec3 blendFactor = _weight / (_weight.x + _weight.y + _weight.z);
    return blendFactor;
}

vec2 GetBlendTwoFactorEx(vec2 height, vec2 weight)
{
    height = max(height, vec2(0.0001, 0.0001));
    vec2 hw = height * weight;
    float maxHW = max(hw.x, hw.y) * 0.3;
    vec2 ww = max(hw - maxHW, vec2(0.0, 0.0)) * weight;
    float wwSum = ww.x + ww.y;
    return ww / wwSum;
}

vec3 GetBlendThreeFactorEx(vec3 height, vec3 weight)
{
    height = max(height, vec3(0.0001, 0.0001, 0.0001));
    vec3 hw = height * weight;
    float maxHW = max(max(hw.x, hw.y), hw.z) * 0.3;
    vec3 ww = max(hw - maxHW, vec3(0.0, 0.0, 0.0)) * weight;
    return ww / (ww.x + ww.y + ww.z);
}

vec4 GetBlendFourFactorEx(vec4 height, vec4 weight)
{
    height = max(height, vec4(0.0001, 0.0001, 0.0001, 0.0001));
    vec4 hw = height * weight;
    float maxHW = max(max(max(hw.x, hw.y), hw.z), hw.w) * 0.3;
    vec4 ww = max(hw - maxHW, vec4(0.0, 0.0, 0.0, 0.0)) * weight;
    return ww / (ww.x + ww.y + ww.z + ww.w);
}

void GetBlendNineFactorEX(vec3 height1, vec3 height2, vec3 height3, vec3 weight1, vec3 weight2, vec3 weight3, out vec3 blendFactor1, out vec3 blendFactor2, out vec3 blendFactor3)
{
#if 1
    height1 = max(height1, vec3(0.0001, 0.0001, 0.0001));
    height2 = max(height2, vec3(0.0001, 0.0001, 0.0001));
    height3 = max(height3, vec3(0.0001, 0.0001, 0.0001));

    vec3 hw1 = height1 * weight1;
    vec3 hw2 = height2 * weight2;
    vec3 hw3 = height3 * weight3;
    float maxHW = max(max(hw1.x, hw1.y), max(hw1.z, hw2.x));
    maxHW = max(max(maxHW, hw2.y), max(hw2.z, hw3.x));
    maxHW = max(max(maxHW, hw3.y), hw3.z);
    maxHW *= 0.3;
    
    vec3 ww1 = max(hw1 - maxHW, vec3(0.0, 0.0, 0.0)) * weight1;
    vec3 ww2 = max(hw2 - maxHW, vec3(0.0, 0.0, 0.0)) * weight2;
    vec3 ww3 = max(hw3 - maxHW, vec3(0.0, 0.0, 0.0)) * weight3;

    float wwSum = ww1.x + ww1.y + ww1.z + 
                  ww2.x + ww2.y + ww2.z +
                  ww3.x + ww3.y + ww3.z;

    blendFactor1 = ww1 / wwSum;
    blendFactor2 = ww2 / wwSum;
    blendFactor3 = ww3 / wwSum;
#endif

#if 0
    height1 = max(height1, vec3(0.0001, 0.0001, 0.0001));
    height2 = max(height2, vec3(0.0001, 0.0001, 0.0001));
    height3 = max(height3, vec3(0.0001, 0.0001, 0.0001));

    vec3 hw1 = height1 * weight1;
    vec3 hw2 = height2 * weight2;
    vec3 hw3 = height3 * weight3;
    float maxHW = max(max(hw1.x, hw1.y), max(hw1.z, hw2.x));
    maxHW = max(max(maxHW, hw2.y), max(hw2.z, hw3.x));
    maxHW = max(max(maxHW, hw3.y), hw3.z);
    
    vec3 ww1 = max(hw1 - maxHW + 0.3, vec3(0.0, 0.0, 0.0)) * weight1;
    vec3 ww2 = max(hw2 - maxHW + 0.3, vec3(0.0, 0.0, 0.0)) * weight2;
    vec3 ww3 = max(hw3 - maxHW + 0.3, vec3(0.0, 0.0, 0.0)) * weight3;

    float wwSum = ww1.x + ww1.y + ww1.z + 
                  ww2.x + ww2.y + ww2.z +
                  ww3.x + ww3.y + ww3.z;

    blendFactor1 = ww1 / wwSum;
    blendFactor2 = ww2 / wwSum;
    blendFactor3 = ww3 / wwSum;
#endif
}
#endif

#ifdef TERRAIN_CLIFF_LANDSCAPE
    SAMPLER2D(u_MaterialParameters4, 4);
    #define cMaterialParametersMap u_MaterialParameters4
#else
    SAMPLER2D(u_MaterialParameters2, 2);
    #define cMaterialParametersMap u_MaterialParameters2
#endif

// MAX_MIX_MATERIAL 由 TerrainMaterialSet 运行时按材质数注入（MAX_MIX_MATERIAL=N）；
// 编辑器/独立强制重编等无 terrain material set 上下文的场景给个默认值，保证 shader 可独立编译
// （运行时注入的真实值会覆盖本默认、并生成各自独立的变体 hash，不影响实际渲染）。
#ifndef MAX_MIX_MATERIAL
#define MAX_MIX_MATERIAL 1
#endif

#ifdef COMPILEVS
vec4 ShaderParameters_GetTileScaleAndRot(float index)
{
    // x = (0.0 + 0.5) / 2.0
    vec4 xyzw = texture2DLod(cMaterialParametersMap, vec2(0.25, (index + 0.5) / MAX_MIX_MATERIAL), 0.0);
    // 0~1 => -1~1
    xyzw.zw = xyzw.zw * 2.0 - 1.0;
    return xyzw;
}
#endif

#ifdef COMPILEPS
vec4 ShaderParameters_GetColorRoughnessFactor(float index)
{
    // x = (1.0 + 0.5) / 2.0
    return texture2DLod(cMaterialParametersMap, vec2(0.75, (index + 0.5) / MAX_MIX_MATERIAL), 0.0);
}
#endif
