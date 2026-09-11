#ifndef CLUSTER_LIGHTS_SH_HEADER_GUARD
#define CLUSTER_LIGHTS_SH_HEADER_GUARD

#include <Common/bgfx_compute.sh>
#include "Cluster/clustersamplers.sh"

uniform hvec4 u_lightCountVec;
#define u_pointLightCount uint(u_lightCountVec.x + 0.1)
#define u_spotLightCount uint(u_lightCountVec.y + 0.1)
#define u_nonPunctualPointLightCount uint(u_lightCountVec.z + 0.1)
#define u_rectLightCount uint(u_lightCountVec.w + 0.1)

uniform hvec4 u_lightOffsetVec;
#define u_pointLightOffset uint(u_lightOffsetVec.x + 0.1)
#define u_spotLightOffset uint(u_lightOffsetVec.y + 0.1)
#define u_nonPunctualPointLightOffset uint(u_lightOffsetVec.z + 0.1)
#define u_rectLightOffset uint(u_lightOffsetVec.w + 0.1)

#ifndef URHO3D_MOBILE
    #define CLUSTER_LIGHTS_UNIFORM_BUFFER_SIZE 2000u
#else
    #define CLUSTER_LIGHTS_UNIFORM_BUFFER_SIZE 600u
#endif

// for each light:
//   vec4 position (w is padding)
//   vec4 intensity + radius (xyz is intensity, w is radius)
#if BGFX_SHADER_LANGUAGE_METAL || BX_PLATFORM_WINDOWS_DIRECTX
    BUFFER_RO(b_clusterLights, hvec4, SAMPLER_LIGHTS_POINTLIGHTS);
#else
    UNIFORM_BUFFER_OBJECT(b_clusterLights, hvec4, SAMPLER_LIGHTS_POINTLIGHTS, CLUSTER_LIGHTS_UNIFORM_BUFFER_SIZE);
#endif


struct PointLight
{
    hvec3 position;
    hfloat range;
    hvec3 intensity;
    hfloat radius;
    hfloat volumetricFogIntensity;
};

struct AmbientLight
{
    vec3 irradiance;
};

// primary source:
// https://seblagarde.files.wordpress.com/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf
// also really good:
// https://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf

float distanceAttenuation(float distance)
{
    // only for point lights

    // physics: inverse square falloff
    // to keep irradiance from reaching infinity at really close distances, stop at 1cm
    return 1.0 / max(distance * distance, 0.01 * 0.01);
}

float smoothAttenuation(float distance, float radius)
{
    // window function with smooth transition to 0
    // radius is arbitrary (and usually artist controlled)
    float nom = saturate(1.0 - pow(distance / radius, 4.0));
    return nom * nom * distanceAttenuation(distance);
}

uint GetPointLightCount()
{
    return u_pointLightCount;
}

PointLight GetPointLight(uint i)
{
    PointLight light;
    hvec4 positionRangeVec = b_clusterLights[3 * int(i) + 0];
    light.position = positionRangeVec.xyz;
    light.range = positionRangeVec.w;
    hvec4 intensityRadiusVec = b_clusterLights[3 * int(i) + 1];
    light.intensity = intensityRadiusVec.xyz;
    light.radius = intensityRadiusVec.w;
    light.volumetricFogIntensity = b_clusterLights[3 * int(i) + 2].x;
    return light;
}

#ifdef CLUSTER_SPOTLIGHT
struct SpotLight
{    
    hvec3 position;
    hfloat range;
    hvec3 intensity;
    hfloat cosOuterCone;
    hvec3 direction;
    hfloat invCosConeDiff;
    hfloat volumetricFogIntensity;
};

SpotLight GetSpotLight(uint i)
{
    SpotLight light;
    hvec4 v1 = b_clusterLights[4 * int(i) + 0];
    hvec4 v2 = b_clusterLights[4 * int(i) + 1];
    hvec4 v3 = b_clusterLights[4 * int(i) + 2];
    light.position = v1.xyz;
    light.range = v1.w;
    light.intensity = v2.xyz;
    light.cosOuterCone = v2.w;
    light.direction = v3.xyz;
    light.invCosConeDiff = v3.w;
    light.volumetricFogIntensity = b_clusterLights[4 * int(i) + 3].x;
    return light;
}
#endif

#if NONPUNCTUAL_LIGHTING

struct RectLight
{
    hvec3 position;
    hfloat range;
    hvec3 intensity;
    hfloat halfWidth;
    hvec3 direction;
    hfloat halfHeight;
    hvec3 tangent;
    hfloat barnCosAngle;
    hfloat barnLength;
    hfloat volumetricFogIntensity;
};

RectLight GetRectLight(uint i)
{
    RectLight light;
    uint offset = u_rectLightOffset + 5u * i;
    hvec4 d0 = b_clusterLights[offset + 0u];
    hvec4 d1 = b_clusterLights[offset + 1u];
    hvec4 d2 = b_clusterLights[offset + 2u];
    hvec4 d3 = b_clusterLights[offset + 3u];
    hvec4 d4 = b_clusterLights[offset + 4u];
    light.position   = d0.xyz;  light.range      = d0.w;
    light.intensity  = d1.xyz;  light.halfWidth  = d1.w;
    light.direction  = d2.xyz;  light.halfHeight = d2.w;
    light.tangent    = d3.xyz;  light.barnCosAngle = d3.w;
    light.barnLength = d4.x;
    light.volumetricFogIntensity = d4.y;
    return light;
}

struct NonPunctualPointLight
{
    hvec3 position;
    hfloat range;
    hvec3 intensity;
    hfloat packRadius;
    hvec3 direction;
    hfloat length;
    hfloat volumetricFogIntensity;
};

NonPunctualPointLight GetNonPunctualPointLight(uint i)
{
    NonPunctualPointLight light;
    uint offset = u_nonPunctualPointLightOffset + 4u * i;
    hvec4 positionRangeVec = b_clusterLights[offset + 0u];
    light.position = positionRangeVec.xyz;
    light.range = positionRangeVec.w;
    hvec4 intensityRadiusVec = b_clusterLights[offset + 1u];
    light.intensity = intensityRadiusVec.xyz;
    light.packRadius = intensityRadiusVec.w;
    hvec4 directionLengthVec = b_clusterLights[offset + 2u];
    light.direction = directionLengthVec.xyz;
    light.length = directionLengthVec.w;
    light.volumetricFogIntensity = b_clusterLights[offset + 3u].x;
    return light;
}

#endif

#endif // LIGHTS_SH_HEADER_GUARD
