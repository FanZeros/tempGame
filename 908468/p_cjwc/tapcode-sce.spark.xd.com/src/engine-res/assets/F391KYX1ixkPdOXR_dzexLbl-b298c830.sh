#ifdef COMPILEVS

#define ENGINE_ELAPSE_CYCLE 20.0

//引擎按20一个周期，我们把它scale到一个目标的函数周期
float GetElapsedTime(float speed, float period)
{
	float frequency = 1.0 / period;
	int n = int(ENGINE_ELAPSE_CYCLE * speed * frequency);
	float x = float(n) * period / (ENGINE_ELAPSE_CYCLE * speed);
	return cElapsedTime * speed * x;
}

hvec3 GetLowNoise(hvec2 pos, hvec2 scale, hfloat speed, hvec3 strength)
{
	hfloat t = dot(pos, scale) + GetElapsedTime(speed, 2.0 * M_PI); //DOT + SMAD
	return sin(t) * strength;
}

hvec3 GetHighNoise(hvec2 pos, hvec2 scale, hfloat speed, hvec3 strength, hfloat interval)
{
	hfloat t = dot(pos, scale) + GetElapsedTime(speed, 2.0 * M_PI); //DOT + SMAD
	hfloat period = fract(dot(pos.xy, vec2(8.0, 1.0)) + floor(t * 0.5 * M_INV_PI) / (interval + 1.0));
	hfloat periodMask = step(interval, period * (interval + 1.0));
	return periodMask * sin(t) * strength;
}

hvec3 GetWindEffectPosition(hvec3 worldPos, hvec3 objectPos)
{
	return hvec3_init(0, 0, 0); // TODO: fix Z-up → Y-up coordinate adaptation
	hvec3 posOffset = (objectPos.xyz + hvec3_init(0, 0, cWindOffset) - worldPos);
	hfloat distance = sqrt(dot(posOffset, posOffset));
	hfloat distanceRate = distance * 0.01;
	hfloat falloff = clamp(distanceRate * distanceRate, 0.0, 1.0) * step(posOffset.z, -10.0);

	//低频部分
	vec2 lowSeed = vec2(1.0, 1.0)  / vec2(cWindLowGrain, cWindLowGrain);
	vec3 noise = GetLowNoise(worldPos.xx, lowSeed, cWindLowFrequency, cWindLowStrength);
	//避免正弦波浪的整体效果，再叠一层，频率hack一下
	noise += GetLowNoise(worldPos.yy, lowSeed, cWindLowFrequency * 1.3, cWindLowStrength);
#if RENDER_QUALITY >= RENDER_QUALITY_MEDIUM
	//高频部分
	vec2 highSeed = vec2(1.0, 1.0)  / vec2(cWindHighGrain, cWindHighGrain);
	noise += GetHighNoise(worldPos.xy, highSeed, cWindHighFrequency, cWindHighStrength, cWindHighTimeInterval);
#endif

	hvec3 totalOffset = cWindPower * falloff * noise;

	return totalOffset;
}

#endif