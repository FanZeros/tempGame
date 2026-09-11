// #define unity_ColorSpaceDielectricSpec vec4(0.04, 0.04, 0.04, 1.0 - 0.04)
// 这个shader最早是参考Unity3D Bultin管线写的，后来在解决引擎色差问题时顺便看到了UE4和Unity3D最新的shader，所以修正一下这个微小的误差
// 参照标准：
// 1.UE4管线：
//   DefferedShadingCommon.usf => GBuffer.DiffuseColor = GBuffer.BaseColor - GBuffer.BaseColor * GBuffer.Metallic
//   ShaderingCommon.ush => ComputeF0 => DielectricSpecularToF0，UE4中Specular默认值为0.5，所以DefaultSpecularValue = 0.08 * 0.5 = 0.04
// 2.Unity3D HDRP管线：
//   com.unity.render-pipelines.core@7.3.1\ShaderLibrary\CommonMaterial.hlsl ComputeDiffuseColor => diffuseColor = baseColor * (1.0 - metallic)
//   com.unity.render-pipelines.core@7.3.1\ShaderLibrary\CommonMaterial.hlsl ComputeFresnel0 => dielectricF0 = 0.04
#define unity_ColorSpaceDielectricSpec vec4(0.04, 0.04, 0.04, 1.0)
#define sce_EnvFresnelEdgeStrength 0.02

#ifndef UNITY_CONSERVE_ENERGY
    #define UNITY_CONSERVE_ENERGY 1
#endif
#ifndef UNITY_CONSERVE_ENERGY_MONOCHROME
    #define UNITY_CONSERVE_ENERGY_MONOCHROME 1
#endif

#define USE_DIFFUSE_LAMBERT_BRDF 1
#define UNITY_BRDF_GGX 1
// 经过颜色，Unity和UE4的EnvBRDF几乎没有太大的差别，反而Unity3D更省
#define UNITY_ENV_BRDF 1
#define UNITY_SAMPLE_FULL_SH_PER_PIXEL 1
#define UNITY_SHOULD_SAMPLE_SH 1
#define SHADER_TARGET 666

uniform vec4 u_SHAr;
uniform vec4 u_SHAg;
uniform vec4 u_SHAb;

uniform vec4 u_SHBr;
uniform vec4 u_SHBg;
uniform vec4 u_SHBb;

uniform vec4 u_SHC;

#define _SHAr u_SHAr
#define _SHAg u_SHAg
#define _SHAb u_SHAb

#define _SHBr u_SHBr
#define _SHBg u_SHBg
#define _SHBb u_SHBb

#define _SHC u_SHC

float PerceptualRoughnessToRoughness(float perceptualRoughness)
{
    return perceptualRoughness * perceptualRoughness;
}

float PerceptualRoughnessToSpecPower(float perceptualRoughness)
{
    float m = PerceptualRoughnessToRoughness(perceptualRoughness);   // m is the true academic roughness.
    float sq = max(1e-4f, m*m);
    float n = (2.0 / sq) - 2.0;                          // https://dl.dropboxusercontent.com/u/55891920/papers/mm_brdf.pdf
    n = max(n, 1e-4f);                                   // prevent possible cases of pow(0,0), which could happen when roughness is 1.0 and NdotH is zero
    return n;
}

float SpecularStrength(vec3 specular)
{
    // #if (SHADER_TARGET < 30)
    //     // SM2.0: instruction count limitation
    //     // SM2.0: simplified SpecularStrength
    //     return specular.r; // Red channel - because most metals are either monocrhome or with redish/yellowish tint
    // #else
        return max(max(specular.r, specular.g), specular.b);
    // #endif
}

vec3 EnergyConservationBetweenDiffuseAndSpecular(vec3 albedo, vec3 specColor, out float oneMinusReflectivity)
{
    oneMinusReflectivity = 1.0 - SpecularStrength(specColor);
    #if !UNITY_CONSERVE_ENERGY
        return albedo;
    #elif UNITY_CONSERVE_ENERGY_MONOCHROME
        return albedo * oneMinusReflectivity;
    #else
        return albedo * (vec3(1.0,1.0,1.0) - specColor);
    #endif
}

float OneMinusReflectivityFromMetallic(float metallic)
{
    // We’ll need oneMinusReflectivity, so
    //   1-reflectivity = 1-lerp(dielectricSpec, 1, metallic) = lerp(1-dielectricSpec, 0, metallic)
    // store (1-dielectricSpec) in unity_ColorSpaceDielectricSpec.a, then
    //   1-reflectivity = lerp(alpha, 0, metallic) = alpha + metallic*(0 - alpha) =
    //                  = alpha - metallic * alpha
    float oneMinusDielectricSpec = unity_ColorSpaceDielectricSpec.a;
    return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
}

vec3 DiffuseAndSpecularFromMetallic(vec3 albedo, float metallic, out vec3 specColor, out float oneMinusReflectivity)
{
    specColor = mix(unity_ColorSpaceDielectricSpec.rgb, albedo, metallic);
    oneMinusReflectivity = OneMinusReflectivityFromMetallic(metallic);
    return albedo * oneMinusReflectivity;
}

vec3 DiffuseAndSpecularFromMetallicEx(vec3 albedo, float metallic, inout vec3 specColor, out float oneMinusReflectivity)
{
    specColor = mix(0.08 * specColor, albedo, metallic);
    oneMinusReflectivity = OneMinusReflectivityFromMetallic(metallic);
    return albedo * oneMinusReflectivity;
}

// Convert a roughness and an anisotropy factor into GGX alpha values respectively for the major and minor axis of the tangent frame
void GetAnisotropicRoughness(float Alpha, float Anisotropy, out float ax, out float ay)
{
#if 1
	// Anisotropic parameters: ax and ay are the roughness along the tangent and bitangent	
	// Kulla 2017, "Revisiting Physically Based Shading at Imageworks"
	ax = max(Alpha * (1.0 + Anisotropy), 0.001);
	ay = max(Alpha * (1.0 - Anisotropy), 0.001);
#else
	float K = sqrt(1.0f - 0.95f * Anisotropy);
	ax = max(Alpha / K, 0.001f);
	ay = max(Alpha * K, 0.001f);
#endif
}

// Microfacet specular = D*G*F / (4*NoL*NoV) = D*Vis*F
// Vis = G / (4*NoL*NoV)

// ------------------------------------------- 高光D项 - Begin -------------------------------------------------------------
// GGX D 项 — 对齐 UE BRDF.ush::D_GGX
// 移动端 half 将 d² 兜底到最小正规数；桌面保留原始计算路径
float GGXTerm (float NdotH, float roughness)
{
    float a2 = roughness * roughness;
    float d = (NdotH * a2 - NdotH) * NdotH + 1.0;
#ifdef URHO3D_MOBILE
    // half 最小正规数为 6.10352e-5，移动端使用 8e-5 兜底，避免精度下溢和高光过爆
    float dd = max(d * d, 8e-5);
    return M_INV_PI * a2 / dd;
#else
    d = max(d, 1e-4);    // 桌面 fp32 极小下限，仅防数值异常
    return M_INV_PI * a2 / (d * d + 0.00002);
#endif
}

float NDFBlinnPhongNormalizedTerm(float NdotH, float n)
{
    // norm = (n+2)/(2*pi)
    float normTerm = (n + 2.0) * (0.5 * M_INV_PI);

    float specTerm = pow(NdotH, n);
    return specTerm * normTerm;
}

// Anisotropic GGX
// [Burley 2012, "Physically-Based Shading at Disney"]
float D_GGXaniso( float ax, float ay, float NoH, float XoH, float YoH )
{
// The two formulations are mathematically equivalent
#if 1
	float a2 = ax * ay;
	vec3 V = vec3(ay * XoH, ax * YoH, a2 * NoH);
	float S = dot(V, V);
#ifdef URHO3D_MOBILE
	// TODO: 当前公式在 half 下同时存在 S ~ a2^2 下溢和 Square(a2 / S) 上溢风险。
	// 此处只兜底除零，可能压低光滑各向异性高光；后续应改用下方归一化等价式。
	S = max(S, 8e-5); // 避免 half 次正规数 FTZ 后 a2 / S 变成 0/0
#endif

	return M_INV_PI * a2 * Square(a2 / S);
#else
	float d = XoH*XoH / (ax*ax) + YoH*YoH / (ay*ay) + NoH*NoH;
	return 1.0f / ( M_PI * ax*ay * d*d );
#endif
}

// ------------------------------------------- 高光D项 - End ----------------------------------------------------------------

// ------------------------------------------- 高光Vis项 - Begin --------------------------------------------------------------
float SmithJointGGXVisibilityTerm(float NdotL, float NdotV, float roughness)
{
#if 0
    // Original formulation:
    //  lambda_v    = (-1 + sqrt(a2 * (1 - NdotL2) / NdotL2 + 1)) * 0.5f;
    //  lambda_l    = (-1 + sqrt(a2 * (1 - NdotV2) / NdotV2 + 1)) * 0.5f;
    //  G           = 1 / (1 + lambda_v + lambda_l);

    // Reorder code to be more optimal
    float a          = roughness;
    float a2         = a * a;

    float lambdaV    = NdotL * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
    float lambdaL    = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);

    // Simplify visibility term: (2.0f * NdotL * NdotV) /  ((4.0f * NdotL * NdotV) * (lambda_v + lambda_l + 1e-5f));
    return 0.5f / (lambdaV + lambdaL + 1e-5f);  // This function is not intended to be running on Mobile,
                                                // therefore epsilon is smaller than can be represented by half
#else
    // Approximation of the above formulation (simplify the sqrt, not mathematically correct but close enough)
    float a = roughness;
    float lambdaV = NdotL * (NdotV * (1.0 - a) + a);
    float lambdaL = NdotV * (NdotL * (1.0 - a) + a);

    return 0.5 / (lambdaV + lambdaL + 1e-4);
#endif
}

// Generic Smith-Schlick visibility term
float SmithVisibilityTerm(float NdotL, float NdotV, float k)
{
    float gL = NdotL * (1.0 - k) + k;
    float gV = NdotV * (1.0 - k) + k;
    return 1.0 / (gL * gV + 1e-4f); // This function is not intended to be running on Mobile,
                                    // therefore epsilon is smaller than can be represented by half
}

// Smith-Schlick derived for Beckmann
float SmithBeckmannVisibilityTerm(float NdotL, float NdotV, float roughness)
{
    float c = 0.797884560802865f; // c = sqrt(2 / Pi)
    float k = roughness * c;
    return SmithVisibilityTerm(NdotL, NdotV, k) * 0.25f; // * 0.25 is the 1/4 of the visibility term
}

// [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
float Vis_SmithJointAniso(float ax, float ay, float NoV, float NoL, float XoV, float XoL, float YoV, float YoL)
{
	float Vis_SmithV = NoL * length(vec3(ax * XoV, ay * YoV, NoV));
	float Vis_SmithL = NoV * length(vec3(ax * XoL, ay * YoL, NoL));
	float Vis_Smith = Vis_SmithV + Vis_SmithL;
#ifdef URHO3D_MOBILE
	Vis_Smith = max(Vis_Smith, 1e-4); // 避免两个 length 同时 FTZ 后除零
#endif
	return 0.5 / Vis_Smith;
}

// -------------------------------------------- 高光Vis项 - End --------------------------------------------------------------

// -------------------------------------------- 高光F项 - Begin ----------------------------------------------------
// 等价：
// 1.Unity3D HDRP管线 BSDF.hlsl
// 2.UE4 BRDF.usf F_Schlick (略微差别：Anything less than 2% is physically impossible and is instead considered to be shadowing)
/*
Unity3D HDRP管线 BSDF.hlsl代码如下
real3 F_Schlick(real3 f0, real f90, real u)
{
    real x = 1.0 - u;
    real x2 = x * x;
    real x5 = x * x2 * x2;
    return f0 * (1.0 - x5) + (f90 * x5);        // sub mul mul mul sub mul mad*3
}

real3 F_Schlick(real3 f0, real u)
{
    return F_Schlick(f0, 1.0, u);               // sub mul mul mul sub mad*3
}
*/

vec3 FresnelTerm(vec3 F0, float cosA)
{
    float t = Pow5(1.0 - cosA);   // ala Schlick interpoliation
    return F0 + (1.0 - F0) * t;
}

vec3 FresnelLerp(vec3 F0, vec3 F90, float cosA)
{
    float t = Pow5 (1.0 - cosA);   // ala Schlick interpoliation
    return mix(F0, F90, t);
}
// -------------------------------------------- 高光F项 - End ------------------------------------------------------

// 原本想用这种漫反射模型，但是UE和Unity都没用，于是换成下面的迪士尼漫反射
// 纠正一个错误，UE4默认用的是Lambert的Diffuse模型
float BurleyDiffuse(float NdotV, float NdotL, float VdotH, float perceptualRoughness)
{
    float energyBias = mix(perceptualRoughness, 0.0, 0.5);
    float energyFactor = mix(perceptualRoughness, 1.0, 1.0 / 1.51);
    float fd90 = energyBias + 2.0 * VdotH * VdotH * perceptualRoughness;
    float f0 = 1.0;
    float lightScatter = f0 + (fd90 - f0) * Pow5(1.0 - NdotL);
    float viewScatter = f0 + (fd90 - f0) * Pow5(1.0 - NdotV);

    return  lightScatter * viewScatter * energyFactor;
}

// Note: Disney diffuse must be multiply by diffuseAlbedo / PI. This is done outside of this function.
float DisneyDiffuse(float NdotV, float NdotL, float LdotH, float perceptualRoughness)
{
    float fd90 = 0.5 + 2.0 * LdotH * LdotH * perceptualRoughness;
    // Two schlick fresnel term
    float lightScatter   = (1.0 + (fd90 - 1.0) * Pow5(1.0 - NdotL));
    float viewScatter    = (1.0 + (fd90 - 1.0) * Pow5(1.0 - NdotV));

    return lightScatter * viewScatter;
}

// normal should be normalized, w=1.0
vec3 SHEvalLinearL0L1 (vec4 normal)
{
    vec3 x;

    // Linear (L1) + constant (L0) polynomial terms
    x.r = dot(_SHAr,normal);
    x.g = dot(_SHAg,normal);
    x.b = dot(_SHAb,normal);

    return x;
}

// normal should be normalized, w=1.0
vec3 SHEvalLinearL2(vec4 normal)
{
    vec3 x1, x2;
    // 4 of the quadratic (L2) polynomials
    vec4 vB = normal.xyzz * normal.yzzx;
    x1.r = dot(_SHBr,vB);
    x1.g = dot(_SHBg,vB);
    x1.b = dot(_SHBb,vB);

    // Final (5th) quadratic (L2) polynomial
    float vC = normal.x*normal.x - normal.y*normal.y;
    x2 = _SHC.rgb * vC;

    return x1 + x2;
}

vec3 ShadeSHPerPixel(vec3 normal, vec3 ambient, float shIntensity)
{
    vec3 ambient_contrib = vec3_splat(0.0);

    // 顶点球谐
    #if VERTEX_SH
        ambient += max(vec3(0.0, 0.0, 0.0), vAmbientColor.rgb * shIntensity);
    // 只有high及以上渲染质量才开全sh
    #elif UNITY_SAMPLE_FULL_SH_PER_PIXEL && RENDER_QUALITY >= RENDER_QUALITY_HIGH
        // Completely per-pixel
        ambient_contrib = SHEvalLinearL0L1(vec4(normal, 1.0));
        ambient_contrib += SHEvalLinearL2(vec4(normal, 1.0));
        // 混合球谐（移动端平片地表使用顶点球谐，而悬崖使用像素球谐，边界处存在硬边，所以使用混合球谐让它过度柔和）
        #if VERTEX_PIXEL_SH_BLEND
            ambient_contrib = mix(ambient_contrib, vAmbientColor.rgb, vAmbientColor.a);
        #endif
        ambient += max(vec3(0.0, 0.0, 0.0), ambient_contrib * shIntensity);
    #else
        // L2 per-vertex, L0..L1 & gamma-correction per-pixel
        // Ambient in this case is expected to be always Linear, see ShadeSHPerVertex()
        ambient_contrib = SHEvalLinearL0L1(vec4(normal, 1.0));
        // 混合球谐（移动端平片地表使用顶点球谐，而悬崖使用像素球谐，边界处存在硬边，所以使用混合球谐让它过度柔和）
        #if VERTEX_PIXEL_SH_BLEND
            ambient_contrib = mix(ambient_contrib, vAmbientColor.rgb, vAmbientColor.a);
        #endif
        ambient = max(vec3(0, 0, 0), ambient + ambient_contrib * shIntensity);     // include L2 contribution in vertex shader before clamp.
    #endif

    return ambient;
}

float PositiveClampedPow(float X, float Y)
{
	return pow(max(X, 0.000001), Y);
}

vec2 PositiveClampedPow(vec2 X, float Y)
{
    return pow(max(X, vec2_splat(0.000001)), vec2_splat(Y));
}

vec3 PositiveClampedPow(vec3 X, float Y)
{
    return pow(max(X, vec3_splat(0.000001)), vec3_splat(Y));
}

#if defined(GAO)
// height => medium float 够用了 
float GroundAO(vec3 normalDirection, float groundZ)
{
    float ceoff = (1.0 - clamp(-normalDirection.z, 0.0, 1.0)); // <==> dot(normalDirection, vec3(0.0, 0.0, -1.0))
    float groundAO = (1.0 - 10.0 / max(__GET_HEIGHT__(vWorldPos) - groundZ, 10.0)) * ceoff;
    return groundAO;
}
#endif
