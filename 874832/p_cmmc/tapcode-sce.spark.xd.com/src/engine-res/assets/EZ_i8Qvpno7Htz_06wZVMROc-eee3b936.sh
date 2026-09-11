#ifdef COMPILEVS

#include "PBR/PBRCommon.glsl"

uniform hvec4 u_TimeSpeed;
uniform hvec4 u_GradientZPower;
uniform hvec4 u_WPO;
uniform hvec4 u_SprayStrength;
uniform hvec4 u_GrassScale;

#define cTimeSpeed u_TimeSpeed.x
#define cGradientZPower u_GradientZPower.x
#define cWPO u_WPO.xyz
#define cSprayStrength u_SprayStrength.xyz
#define cGrassScale u_GrassScale.x

#ifndef VERTEX_NORMALMAP_SLOT
    SAMPLER2D(u_NormalMap, 1);
    #define sNormalMap u_NormalMap
#elif VERTEX_NORMALMAP_SLOT == 0
    SAMPLER2D(u_DiffMap, 0);
    #define sNormalMap u_DiffMap
#elif VERTEX_NORMALMAP_SLOT == 1
    SAMPLER2D(u_NormalMap, 1);
    #define sNormalMap u_NormalMap
#elif VERTEX_NORMALMAP_SLOT == 2
    SAMPLER2D(u_SpecMap, 2);
    #define sNormalMap u_SpecMap
#elif VERTEX_NORMALMAP_SLOT == 3
    SAMPLER2D(u_EmissiveMap, 3);
    #define sNormalMap u_EmissiveMap
#endif

// 这方法是从虚幻抄过来改的
/** Rotates Position about the given axis by the given angle, in radians, and returns the offset to Position. */
vec3 RotateAboutAxis(vec3 NormalizedRotationAxis, float Angle, vec3 PositionOnAxis, vec3 Position)
{
	// Project Position onto the rotation axis and find the closest point on the axis to Position
	vec3 ClosestPointOnAxis = PositionOnAxis + NormalizedRotationAxis * dot(NormalizedRotationAxis, Position - PositionOnAxis);
	// Construct orthogonal axes in the plane of the rotation
	vec3 UAxis = Position - ClosestPointOnAxis;
	vec3 VAxis = cross(NormalizedRotationAxis, UAxis);
    float CosAngle = cos(Angle);
    float SinAngle = sin(Angle);
	// Rotate using the orthogonal axes
	vec3 R = UAxis * CosAngle + VAxis * SinAngle;
	// Reconstruct the rotated world space position
	vec3 RotatedPosition = ClosestPointOnAxis + R;
	// Convert from position to a position offset
	return RotatedPosition - Position;
}

vec3 GetWindEffect(hvec3 worldPos, vec2 texCoord, inout vec3 ioNormal)
{
    return vec3_splat(0.0); // TODO: fix Z-up → Y-up coordinate adaptation
    float mixPercent = saturate(PositiveClampedPow(1.0 - texCoord.g, cGradientZPower));

// XY偏移
    hfloat _time = cTimeSpeed * cElapsedTimeReal;
    hvec2 uv = worldPos.xy / (320.0 * cGrassScale);
    hvec2 uv1 = uv + hvec2_init(1.0, 0.0) * _time;
    hvec2 uv2 = uv + hvec2_init(0.0, 1.0) * _time;
    uv1 = fract(uv1);
    uv2 = fract(uv2);
    vec3 texNormal = texture2DLod(sNormalMap, uv1,0.0).rgb * 2.0 - 1.0 + texture2DLod(sNormalMap, uv2,0.0).rgb * 2.0 - 1.0;

// 世界坐标细化
    vec3 posOffset = RotateAboutAxis(normalize(ioNormal), normalize(texNormal).r * 6.28318548, vec3(0.0, 0.0, -50.0), vec3(0.0, 0.0, 0.0));
    posOffset = posOffset * cWPO;
    posOffset = mix(vec3_splat(0.0), posOffset, mixPercent);

// normal麦浪
    ioNormal = vec3(10.0, 10.0, 1.0) * texNormal;
    ioNormal = mix(vec3(0.0, 0.0, 1.0), ioNormal, mixPercent);
    ioNormal = ioNormal + cSprayStrength + cLightDir * 0.5;

    return posOffset;
}

vec3 SimpleVertexAnimation(hvec3 worldPos, hfloat weight, vec3 inNormal)
{
    return vec3_splat(0.0); // TODO: fix Z-up → Y-up coordinate adaptation
    float mixPercent = saturate(PositiveClampedPow(weight, cGradientZPower));

// XY偏移
    // 有的材质的speed设置的太小(0.013)，在一个引擎周期(20s)内还完不成一次周期，没法scale，这里只能先避免编译half来解决卡顿
    // float _time = GetElapsedTime(cTimeSpeed, 1.0);
    hfloat _time = cTimeSpeed * cElapsedTimeReal;
    hvec2 uv = worldPos.xy / (320.0 * cGrassScale);
    hvec2 uv1 = uv + hvec2_init(1.0, 0.0) * _time;
    hvec2 uv2 = uv + hvec2_init(0.0, 1.0) * _time;
    uv1 = fract(uv1);
    uv2 = fract(uv2);
    vec3 texNormal = texture2DLod(sNormalMap, uv1,0.0).rgb * 2.0 - 1.0 + texture2DLod(sNormalMap, uv2,0.0).rgb * 2.0 - 1.0;

// 世界坐标细化
    vec3 posOffset = RotateAboutAxis(inNormal, normalize(texNormal).r * 6.28318548, vec3(0.0, 0.0, -50.0), vec3(0.0, 0.0, 0.0));
    posOffset = posOffset * cWPO;
    posOffset = mix(vec3_splat(0.0), posOffset, mixPercent);

    return posOffset;
}

#endif
