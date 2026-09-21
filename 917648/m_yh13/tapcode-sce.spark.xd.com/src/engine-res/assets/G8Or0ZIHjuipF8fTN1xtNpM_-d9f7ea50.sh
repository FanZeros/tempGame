#ifndef CLUSTERS_SH_HEADER_GUARD
#define CLUSTERS_SH_HEADER_GUARD

#include <Common/bgfx_shader.sh>
#include <Common/bgfx_compute.sh>
#include "Cluster/clustersamplers.sh"
#include "Cluster/clusterutil.sh"

// taken from Doom
// http://advances.realtimerendering.com/s2016/Siggraph2016_idTech6.pdf

// workgroup size of the culling compute shader
// D3D compute shaders only allow up to 1024 threads per workgroup
// GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS also only guarantees 1024
#define CLUSTERS_X_THREADS 16
#define CLUSTERS_Y_THREADS 8
#define CLUSTERS_Z_THREADS 1

#ifndef URHO3D_MOBILE
    #define MAX_LIGHTS_PER_CLUSTER 150
#else
    #define MAX_LIGHTS_PER_CLUSTER 50
#endif

// cluster size in screen coordinates (pixels)
uniform hvec4 u_clusterSizesVec;

#define u_clusterSizes u_clusterSizesVec.xy
#define u_clusterOrigin u_clusterSizesVec.zw

// xyz = logical cluster grid dimensions. Desktop dimensions are viewport-dependent;
// mobile keeps the legacy 16 x 8 x 24 grid but uses the same addressing path.
uniform vec4 u_clusterGridVec;

uniform hvec4 u_zNearFarVec;
#define u_zNear u_zNearFarVec.x
#define u_zFar u_zNearFarVec.y

#ifdef WRITE_CLUSTERS
    #define CLUSTER_BUFFER BUFFER_RW
#else
    #define CLUSTER_BUFFER BUFFER_RO
#endif

// light indices belonging to clusters
CLUSTER_BUFFER(b_clusterLightIndices, uint, SAMPLER_CLUSTERS_LIGHTINDICES);
// for each cluster: (start index in b_clusterLightIndices, number of point lights, empty, empty)
CLUSTER_BUFFER(b_clusterLightGrid, uint, SAMPLER_CLUSTERS_LIGHTGRID);


// these are only needed for building clusters and light culling, not in the fragment shader
#ifdef WRITE_CLUSTERS
// list of clusters (2 vec4's each, min + max pos for AABB)
    CLUSTER_BUFFER(b_clusters, hvec4, SAMPLER_CLUSTERS_CLUSTERS);
    // atomic counter for building the light grid
    // must be reset to 0 every frame
    CLUSTER_BUFFER(b_globalIndex, uint, SAMPLER_CLUSTERS_ATOMICINDEX);
#endif

struct Cluster
{
    vec3 minBounds;
    vec3 maxBounds;
};

struct LightGrid
{
    uint offset;
    uint pointLights;
#if NONPUNCTUAL_LIGHTING
    uint nonPunctualPointLightsOffset;
    uint nonPunctualPointLights;
    uint rectLightsOffset;
    uint rectLights;
#endif

};

uvec3 getClusterGridSize()
{
    return uvec3(uint(u_clusterGridVec.x), uint(u_clusterGridVec.y), uint(u_clusterGridVec.z));
}

uint getClusterLinearIndex(uvec3 indices)
{
    uvec3 gridSize = getClusterGridSize();
    return (gridSize.x * gridSize.y) * indices.z + gridSize.x * indices.y + indices.x;
}

#ifdef WRITE_CLUSTERS
Cluster getCluster(uint index)
{
    Cluster cluster;
    cluster.minBounds = b_clusters[2 * int(index) + 0].xyz;
    cluster.maxBounds = b_clusters[2 * int(index) + 1].xyz;
    return cluster;
}
#endif

LightGrid getLightGrid(uint cluster)
{
    // 下标显式转 int：glslang 编 ESSL 时不接受 int 字面量与 uint 的隐式混算
    int base = 4 * int(cluster);
    uvec4 gridvec = uvec4(b_clusterLightGrid[base], b_clusterLightGrid[base + 1], b_clusterLightGrid[base + 2], b_clusterLightGrid[base + 3]);
    LightGrid grid;
    grid.offset = gridvec.x;
    grid.pointLights = gridvec.y;
#if NONPUNCTUAL_LIGHTING
    grid.nonPunctualPointLightsOffset = gridvec.x + gridvec.y;
    grid.nonPunctualPointLights = gridvec.w;
    grid.rectLightsOffset = gridvec.x + gridvec.y + gridvec.w;
    grid.rectLights = gridvec.z;
#endif
    return grid;
}

uint GetGridLightIndex(uint start, uint offset)
{
    return b_clusterLightIndices[start + offset];
}

// cluster depth index from depth in screen coordinates (gl_FragCoord.z)
uint getClusterZIndex(hfloat screenDepth)
{
    uvec3 gridSize = getClusterGridSize();
    // this can be calculated on the CPU and passed as a uniform
    // only leaving it here to keep most of the relevant code in the shaders for learning purposes
    // 总的数量（可以理解为far-near，比如far在10，near在1，scale就是9）
    hfloat scale = hfloat_init(u_clusterGridVec.z) / log(u_zFar / u_zNear);
    // near的位置
    hfloat bias = -(hfloat_init(u_clusterGridVec.z) * log(u_zNear) / log(u_zFar / u_zNear));

    hfloat eyeDepth = screen2EyeDepth(screenDepth, u_zNear, u_zFar);
    //float eyeDepth = screen2Eye(vec4(0, 0, screenDepth, 1)).z;
    // (如当前是5.5，near在1，far在10 ，则一共9个，index就是4)
    uint zIndex = uint(max(log(eyeDepth) * scale + bias, 0.0));
    return min(zIndex, gridSize.z - 1u);
}

// cluster index from fragment position in window coordinates (gl_FragCoord)
uint getClusterIndex(hvec4 fragCoord)
{
    uvec3 gridSize = getClusterGridSize();
    uint zIndex = getClusterZIndex(min(0.999999,fragCoord.z));
    uvec3 indices = uvec3(uvec2(fragCoord.xy / u_clusterSizes.xy), zIndex);
    indices = min(indices, gridSize - uvec3(1u, 1u, 1u));
    return getClusterLinearIndex(indices);
}

hvec4 getRealCoord(hvec4 fragCoord)
{
    hvec4 realCoord = hvec4_init(fragCoord.xy - u_clusterOrigin, fragCoord.zw);
    return realCoord;
}

// eyeDepth <=> sceneDepth ( LinearDepth )
uint getDeferredClusterZIndex(hfloat eyeDepth)
{
    uvec3 gridSize = getClusterGridSize();
    hfloat scale = hfloat_init(u_clusterGridVec.z) / log(u_zFar / u_zNear);
    hfloat bias = -(hfloat_init(u_clusterGridVec.z) * log(u_zNear) / log(u_zFar / u_zNear));
    uint zIndex = uint(max(log(eyeDepth) * scale + bias, 0.0));
    return min(zIndex, gridSize.z - 1u);
}

uint getDeferredClusterIndex(hvec2 fragCoordXY, hfloat sceneDepth)
{
    uvec3 gridSize = getClusterGridSize();
    uint zIndex = getDeferredClusterZIndex(sceneDepth);
    uvec3 indices = uvec3(uvec2((fragCoordXY - u_clusterOrigin) / u_clusterSizes), zIndex);
    indices = min(indices, gridSize - uvec3(1u, 1u, 1u));
    return getClusterLinearIndex(indices);
}

#if defined(CLUSTER_VS) && defined(COMPILEVS)
uint getClusterIndexClip(hvec4 clipPos)
{
    uvec3 gridSize = getClusterGridSize();
    clipPos.xyz = clipPos.xyz / clipPos.w;
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    uint zIndex = getClusterZIndex(min(0.999999,clipPos.z * 0.5 + 0.5));
#else
    uint zIndex = getClusterZIndex(min(0.999999,clipPos.z));
#endif
    uint xIndex = uint((clipPos.x * 0.5 + 0.5) * u_clusterGridVec.x);
    uint yIndex = uint((clipPos.y * 0.5 + 0.5) * u_clusterGridVec.y);
    uvec3 indices = uvec3(xIndex, yIndex, zIndex);
    uvec3 minIndex = uvec3(0u,0u,0u);
    uvec3 maxIndex = gridSize - uvec3(1u, 1u, 1u);
    indices = clamp(indices, minIndex, maxIndex);
    return getClusterLinearIndex(indices);
}

void getClusterLightVS(hvec4 clipPos, vec3 viewDirection, out vec3 vecIrrR, out vec3 vecIrrG, out vec3 vecIrrB, out vec3 mrpDir, out vec4 mrp)
{    
    uint cluster = getClusterIndexClip(clipPos);
    LightGrid grid = getLightGrid(cluster);
    hfloat attenuation;
    float radius;
    float factor;
    float contrib;
    vec3 lightColor;
    vec3 lightDirection = vec3(0.0,0.0,0.0);
    vec3 normal = normalize(vNormal);
    vec3 reflectDir = -viewDirection + 2.0 * dot(viewDirection, normal) * normal;
    vec3 illum = vec3(0.3, 0.6, 0.1);
    mrpDir = vec3(0.0,0.0,0.0);
    mrp = vec4(0.0,0.0,0.0,0.0);
    vecIrrR = vec3(0.0,0.0,0.0);
    vecIrrG = vec3(0.0,0.0,0.0);
    vecIrrB = vec3(0.0,0.0,0.0);
    for (uint i = 0u; i < grid.pointLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.offset, i);
        PointLight light = GetPointLight(lightIndex);
        attenuation = GI_PointLight_GetAttenAndLightDir(vWorldPos.xyz, light.position, light.radius, lightDirection);
        lightColor = light.intensity * attenuation;
        vecIrrR += lightColor.rrr * lightDirection;
        vecIrrG += lightColor.ggg * lightDirection;
        vecIrrB += lightColor.bbb * lightDirection;

        factor = clamp(dot(lightDirection, reflectDir), M_EPSILON, 1.0);
        lightColor *= factor;
        mrp.xyz += lightColor;
        contrib = dot(lightColor, illum);
        mrpDir.xyz += lightDirection * contrib;

        //if (factor > M_EPSILON) {
            //viewDirection = lightDirection - factor * reflectDir;
            //radius = dot(viewDirection, viewDirection);
            //factor = radius;
            //mrp.w = factor > mrp.w ? factor : mrp.w;
        //}
        mrp.w = 1.0;
    }
}

void getClusterPlaneIrradianceApproximateVS(hvec4 clipPos, out vec3 approxIrr, out vec3 mrpDir)
{
    uint cluster = getClusterIndexClip(clipPos);
    LightGrid grid = getLightGrid(cluster);
    hfloat attenuation;
    float radius;
    float factor;
    float contrib;
    vec3 lightColor;
    vec3 lightDirection = vec3(0.0,0.0,1.0);
    vec3 normal = normalize(vNormal);
    vec3 illum = vec3(0.3, 0.6, 0.1);
    mrpDir = vec3(0.0,0.0,0.0);
    approxIrr = vec3(0.0,0.0,0.0);
    for (uint i = 0u; i < grid.pointLights; ++i)
    {
        uint lightIndex = GetGridLightIndex(grid.offset, i);
        PointLight light = GetPointLight(lightIndex);
        attenuation = GI_PointLight_GetAttenAndLightDir(vWorldPos.xyz, light.position, light.radius, lightDirection);
        lightColor = light.intensity * attenuation;

        factor = clamp(dot(lightDirection, normal), M_EPSILON, 1.0);
        lightColor *= factor;
        approxIrr += lightColor;
        contrib = dot(lightColor, illum);
        mrpDir.xyz += lightDirection * contrib;
    }
    mrpDir.xyz = normalize(mrpDir.xyz);
}
#endif // CLUSTER_VS

#endif // CLUSTERS_SH_HEADER_GUARD
