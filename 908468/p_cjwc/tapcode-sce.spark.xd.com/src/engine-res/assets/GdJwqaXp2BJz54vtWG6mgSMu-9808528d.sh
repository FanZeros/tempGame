float SphereHorizonCosWrap( float NoL, float sinAlphaSqr )
{
	float sinAlpha = sqrt( sinAlphaSqr );

	if( NoL < sinAlpha )
	{
		NoL = max(NoL, -sinAlpha);
		NoL = Square(sinAlpha + NoL) / (4.0 * sinAlpha);
	}

	return NoL;
}

float NewRoughness(float roughness, float sinAlpha, float VoH)
{
    return roughness + 0.25 * sinAlpha * (3.0 * sqrt(roughness) + sinAlpha) / (VoH + 0.001);
}

float EnergyNormalization(inout float roughness, float VoH, float sinAlpha, float softSinAlpha, float cosSubtended)
{
	if(softSinAlpha > 0.0)
	{
		// Modify Roughness
		roughness = clamp(roughness + (softSinAlpha * softSinAlpha) / (VoH * 3.6 + 0.4), 0.0, 1.0);
	}

	float sphereRoughness = roughness;
	float energy = 1.0;
	if(sinAlpha > 0.0)
	{
		sphereRoughness = NewRoughness(roughness, sinAlpha, VoH);
		energy = roughness / sphereRoughness;
	}

    if (cosSubtended < 1.0)
    {
        float tanHalfAlpha = sqrt((1.0 - cosSubtended) / (1.0 + cosSubtended));
        float lineRoughness = NewRoughness(sphereRoughness, tanHalfAlpha, VoH);
        energy *= sqrt(sphereRoughness / lineRoughness);
    }

	return energy;
}

// Closest point on line segment to ray
vec3 ClosestPointLineToRay(vec3 Line0, vec3 Line1, float Length, vec3 R)
{
	vec3 L0 = Line0;
	vec3 L1 = Line1;
	vec3 Line01 = Line1 - Line0;

	// Shortest distance
	float A = Square( Length );
	float B = dot( R, Line01 );
	float t = saturate( dot( Line0, B*R - Line01 ) / (A - B*B) );

	return Line0 + t * Line01;
}

// Closest point on sphere to ray
vec3 ClosestPointSphereToRay(vec3 L, float radius, vec3 R)
{
    vec3 closestPointOnRay = dot(L, R) * R;
    vec3 centerToRay = closestPointOnRay - L;
    float distToRay = sqrt(dot(centerToRay, centerToRay));
    return L + centerToRay * clamp(radius / (distToRay + 1e-4), 0.0, 1.0);
}

#if NONPUNCTUAL_LIGHTING && defined(CLUSTER)
vec3 GetCapsuleLighting(NonPunctualPointLight light, vec3 worldPos, vec3 normal, vec3 viewDirection, vec3 diffuseColor, vec3 specularColor, float roughness, float perceptualRoughness
#ifdef CLEAR_COAT
    , float clearCoatStrength, float clearCoatRoughness
    , vec3 baseColor, float metallic    // ← ApplyClearCoat Transmission 需要
#endif
)
{
    uint uSoftRadius = uint(light.packRadius * 0.001);
    hfloat radius = light.packRadius - 1000.0 * uSoftRadius;
    hfloat softRadius = (hfloat)uSoftRadius * 0.001;

    hvec3 L = light.position - worldPos;
    hvec3 L01 = light.direction * light.length;
    hvec3 L0 = L - 0.5 * L01;
    hvec3 L1 = L + 0.5 * L01;
    L01 = L1 - L0;

    hfloat Length0Sqr = dot(L0, L0);
    hfloat Length0 = sqrt(Length0Sqr);
    hfloat Length1Sqr = dot(L1, L1);
    hfloat Length1 = sqrt(Length1Sqr);
    hfloat Length01 = Length0 * Length1;

    hfloat NdotL = 0.5 * (dot(normal, L0) / Length0 + dot(normal, L1) / Length1);
    hfloat distSqr = dot(L, L);
    hfloat rangeMask = GetLightRangeMask(light.range, distSqr);

    hfloat NdotV = abs(dot(normal, viewDirection));
    hfloat cosSubtended = dot(L0, L1) / Length01;
    hfloat falloff = 1.0 / (Length01 * (0.5 * cosSubtended + 0.5 + 1.0 / (Length01 + 1e-4)));
    if(radius > 0.0)
    {
        NdotL = SphereHorizonCosWrap(NdotL, saturate(radius * radius * falloff));
    }
    hvec3 diff = diffuseColor * M_INV_PI;
    //Specular
    hvec3 reflectDir = -viewDirection + 2.0 * dot(viewDirection, normal) * normal;
    L = ClosestPointLineToRay(L0, L1, light.length, reflectDir);
    L = ClosestPointSphereToRay(L, radius, reflectDir);
    distSqr = dot(L, L);
    hfloat invDist = 1.0 / sqrt(distSqr + 1e-4);
    falloff *= rangeMask;
    L = normalize(L);
    hvec3 H = normalize(L + viewDirection);
    hfloat VdotH = dot(viewDirection, H);
    hfloat NdotH = clamp(dot(normal, H), M_EPSILON, 1.0);
    roughness = max(roughness, 0.002);
    hfloat V = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness);
    hfloat D = GGXTerm(NdotH, roughness);
    hvec3 F = FresnelTerm(specularColor, VdotH);
    hvec3 spec = V * D * F;
    // EnergyNormalization 会就地抬升 roughness（area-light 几何近似），但 ClearCoat 底层
    // D2/Vis2 必须用材质原始 R（对齐 UE ShadingModels.ush::ClearCoatBxDF 用 GBuffer BaseRoughness），
    // 否则胶囊光+ClearCoat 下底层比方向光更糊。先保存原值再调。
    float origRoughness = roughness;
    spec *= EnergyNormalization(roughness, VdotH, radius * invDist * (1.0 - roughness), softRadius * invDist, cosSubtended);
    // NOTE: capsule/sphere 路径无独立 coat normal，开 CLEAR_COAT_BOTTOM_NORMAL 时
    // 这里清漆层会用 base normal（轻微误差，胶囊光下车漆肉眼难辨；按需后续扩签名）
    APPLY_CLEAR_COAT(diff, spec, normal, normal, viewDirection, L, H, diff, specularColor, baseColor, metallic, origRoughness, clearCoatStrength, clearCoatRoughness);
#ifdef CLEAR_COAT
    // per-lobe NoL 已在 APPLY_CLEAR_COAT 宏内按层乘，外层不再乘
    return (diff + spec) * light.intensity * falloff;
#else
    return (diff + spec) * light.intensity * falloff * NdotL;
#endif
}

vec3 GetSphereLighting(NonPunctualPointLight light, vec3 worldPos, vec3 normal, vec3 viewDirection, vec3 diffuseColor, vec3 specularColor, float roughness, float perceptualRoughness
#ifdef CLEAR_COAT
    , float clearCoatStrength, float clearCoatRoughness
    , vec3 baseColor, float metallic    // ← ApplyClearCoat Transmission 需要
#endif
)
{
    uint uSoftRadius = uint(light.packRadius * 0.001);
    hfloat radius = light.packRadius - 1000.0 * uSoftRadius;
    hfloat softRadius = (hfloat)uSoftRadius * 0.001;

    hvec3 lightVec = light.position - worldPos.xyz;
    hfloat distSqr = dot(lightVec, lightVec);
    hfloat rangeMask = GetLightRangeMask(light.range, distSqr);
    hfloat falloff = rangeMask / max(distSqr, 0.0001);
    hfloat invDist = 1.0 / sqrt(distSqr + 1e-4);
    hfloat sinAlphaSqr = saturate(radius * radius / max(distSqr, 0.0001));

    hvec3 lightDirection = lightVec * invDist;
    hfloat NdotL = dot(normal, lightDirection);
    NdotL = SphereHorizonCosWrap(NdotL, sinAlphaSqr);
    hfloat NdotV = abs(dot(normal, viewDirection));

    hvec3 diff = diffuseColor * M_INV_PI;

    //Specular
    hvec3 reflectDir = -viewDirection + 2.0 * dot(viewDirection, normal) * normal;
    hvec3 closestPointOnSphere = ClosestPointSphereToRay(lightVec, radius, reflectDir);

    hvec3 L = normalize(closestPointOnSphere);
    hvec3 H = normalize(L + viewDirection);
    hfloat VdotH = dot(viewDirection, H);
    hfloat NdotH = clamp(dot(normal, H), M_EPSILON, 1.0);
    roughness = max(roughness, 0.002);
    hfloat V = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness);
    hfloat D = GGXTerm(NdotH, roughness);
    hvec3 F = FresnelTerm(specularColor, VdotH);
    hvec3 spec = V * D * F;
    // 同 GetCapsuleLighting：保存原始 R 给 ClearCoat 底层 D2/Vis2 用
    float origRoughness = roughness;
    spec *= EnergyNormalization(roughness, VdotH, radius * invDist * (1.0 - roughness), softRadius * invDist, 1.0);
    // NOTE: 同 GetCapsuleLighting，无独立 coat normal
    APPLY_CLEAR_COAT(diff, spec, normal, normal, viewDirection, L, H, diff, specularColor, baseColor, metallic, origRoughness, clearCoatStrength, clearCoatRoughness);
#ifdef CLEAR_COAT
    // per-lobe NoL 已在 APPLY_CLEAR_COAT 宏内按层乘，外层不再乘
    return (diff + spec) * light.intensity * falloff;
#else
    return (diff + spec) * light.intensity * falloff * NdotL;
#endif
}
#endif