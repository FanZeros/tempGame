#ifdef COMPILEVS

uniform hvec4 u_PlantVariation;
uniform hvec4 u_WindNormalScale;
SAMPLER2D(u_SpecMap, 2);
#define sNoiseMap u_SpecMap
hvec3 GetPlantVariation(hvec3 worldPos)
{
    vec2 tileUV =  worldPos.xy * (1.0 / u_PlantVariation.x);//u_PlantVariationTiling.x);//Tiling
	hfloat maskedTimePS = cElapsedTimeReal * u_PlantVariation.y;
    hvec2 noiseUV = tileUV.xy + hvec2_init(maskedTimePS, maskedTimePS);//texture2D(_MaskTextureMap, tileUV).b;
	vec3 noise = texture2DLod(sNoiseMap, frac(noiseUV * u_PlantVariation.z), 0.0).rgb;

	float alpha = pow(vTexCoord.y, u_WindNormalScale.w);//Grounding Strength
	float noiseStrength = lerp(noise.xyz * u_PlantVariation.w, vec3_splat(0.0), alpha);
	vPlantMask.xy = noiseStrength * u_WindNormalScale.xy;
	return noiseStrength;
	// vPlantMask.x = variationMask * variationMask2;// * variationMask2;
}

#endif
