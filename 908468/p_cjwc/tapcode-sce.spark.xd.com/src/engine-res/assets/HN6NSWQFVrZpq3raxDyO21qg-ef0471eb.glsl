#define WRITE_CLUSTERS
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"

#include "Cluster/clustercommon.sh"
#include <Common/bgfx_compute.sh>
#include "Cluster/clusterlights.sh"
#include "Cluster/clusters.sh"

// compute shader to cull lights against cluster bounds
// builds a light grid that holds indices of lights for each cluster
// largely inspired by http://www.aortiz.me/2018/12/21/CG.html

// point lights only for now
bool LightIntersectsCluster(PointLight light, Cluster cluster);
#ifdef CLUSTER_SPOTLIGHT
bool LightIntersectsCluster(SpotLight light, Cluster cluster);
#endif

#define gl_WorkGroupSize uvec3(CLUSTERS_X_THREADS, CLUSTERS_Y_THREADS, CLUSTERS_Z_THREADS)
#define GROUP_SIZE uint(CLUSTERS_X_THREADS * CLUSTERS_Y_THREADS * CLUSTERS_Z_THREADS)

// light cache for the current workgroup
// group shared memory has lower latency than global memory

// there's no guarantee on the available shared memory
// as a guideline the minimum value of GL_MAX_COMPUTE_SHARED_MEMORY_SIZE is 32KB
// with a workgroup size of 16*8*4 this is 64 bytes per light
// however, using all available memory would limit the compute shader invocation to only 1 workgroup

// GROUP_SIZE 是 uint，倍数须带 u 后缀：glslang 编 ESSL 时不接受 uint 与 int 混算
SHARED hvec4 sharedLights[GROUP_SIZE * 3u];

// 索引参数一律 uint：调用方传的是 gl_LocalInvocationIndex 和 uint 循环变量，
// 声明成 int 会让 ESSL 的重载匹配失败（glslang 不做隐式 uint→int 转换）。
void EncodeSharedPointLight(uint idx, PointLight light)
{
    sharedLights[idx * 2u] = vec4(light.position, light.range);
    sharedLights[idx * 2u + 1u] = vec4(light.intensity, light.radius);
}

PointLight GetSharedPointLight(uint idx)
{
    PointLight light;
    hvec4 positionRangeVec = sharedLights[2u * idx + 0u];
    light.position = positionRangeVec.xyz;
    light.range = positionRangeVec.w;
    hvec4 intensityRadiusVec = sharedLights[2u * idx + 1u];
    light.intensity = intensityRadiusVec.xyz;
    light.radius = intensityRadiusVec.w;
    light.volumetricFogIntensity = 0.0;
    return light;
}

#ifdef CLUSTER_SPOTLIGHT
void EncodeSharedSpotLight(uint idx, SpotLight light)
{
    // 剔除半径与着色端衰减范围一致（衰减窗口函数在 range 处归零）
    sharedLights[idx * 3u] = hvec4_init(light.position, light.range);
    sharedLights[idx * 3u + 1u] = hvec4_init(light.intensity, light.cosOuterCone);
    sharedLights[idx * 3u + 2u] = hvec4_init(light.direction, light.invCosConeDiff);
}

SpotLight GetSharedSpotLight(uint idx)
{
    SpotLight light;
    hvec4 v1 = sharedLights[3u * idx + 0u];
    hvec4 v2 = sharedLights[3u * idx + 1u];
    hvec4 v3 = sharedLights[3u * idx + 2u];
    light.position = v1.xyz;
    light.intensity = v2.xyz;
    light.range = v1.w;
    light.cosOuterCone = v2.w;
    light.direction = v3.xyz;
    light.invCosConeDiff = v3.w;
    light.volumetricFogIntensity = 0.0;
    return light;
}
#endif


#if NONPUNCTUAL_LIGHTING
bool NonPunctualPointLightIntersectsCluster(NonPunctualPointLight light, Cluster cluster)
{
    vec3 closest = max(cluster.minBounds, min(light.position, cluster.maxBounds));
    vec3 dist = closest - light.position;
    return dot(dist, dist) <= (light.range * light.range);
}

void EncodeSharedNonPunctualPointLight(uint idx, NonPunctualPointLight light)
{
    sharedLights[idx * 3u] = hvec4_init(light.position, light.range);
    sharedLights[idx * 3u + 1u] = hvec4_init(light.intensity, light.packRadius);
    sharedLights[idx * 3u + 2u] = hvec4_init(light.direction, light.length);
}

NonPunctualPointLight GetSharedNonPunctualPointLight(uint idx)
{
    NonPunctualPointLight light;
    hvec4 positionRangeVec = sharedLights[3u * idx + 0u];
    light.position = positionRangeVec.xyz;
    light.range = positionRangeVec.w;
    hvec4 intensityRadiusVec = sharedLights[3u * idx + 1u];
    light.intensity = intensityRadiusVec.xyz;
    light.packRadius = intensityRadiusVec.w;
    hvec4 directionLengthVec = sharedLights[3u * idx + 2u];
    light.direction = directionLengthVec.xyz;
    light.length = directionLengthVec.w;
    light.volumetricFogIntensity = 0.0;
    return light;
}

bool RectLightIntersectsCluster(RectLight light, Cluster cluster)
{
    hvec3 closest = max(hvec3_init(cluster.minBounds), min(light.position, hvec3_init(cluster.maxBounds)));
    hvec3 dist = closest - light.position;
    return dot(dist, dist) <= (light.range * light.range);
}

// Shared memory for RectLight culling: only store position + range (1 vec4).
// Culling only needs these two fields (RectLightIntersectsCluster).
// Full 5 vec4 data is read from global buffer in the pixel shader.
void EncodeSharedRectLight(uint idx, RectLight light)
{
    sharedLights[idx] = hvec4_init(light.position, light.range);
}

RectLight GetSharedRectLight(uint idx)
{
    RectLight light;
    hvec4 d0 = sharedLights[idx];
    light.position = d0.xyz;
    light.range = d0.w;
    // Other fields not needed for culling, zero-init
    light.intensity = hvec3_init(0.0, 0.0, 0.0);
    light.halfWidth = 0.0;
    light.direction = hvec3_init(0.0, 0.0, 0.0);
    light.halfHeight = 0.0;
    light.tangent = hvec3_init(0.0, 0.0, 0.0);
    light.barnCosAngle = 0.0;
    light.barnLength = 0.0;
    light.volumetricFogIntensity = 0.0;
    return light;
}
#endif

// each thread handles one cluster
NUM_THREADS(CLUSTERS_X_THREADS, CLUSTERS_Y_THREADS, CLUSTERS_Z_THREADS)
void main()
{
    // local thread variables
    // hold the result of light culling for this cluster
    uint visibleLights[MAX_LIGHTS_PER_CLUSTER];
    uint visibleCount = 0u;

    uvec3 gridSize = getClusterGridSize();
    uvec3 clusterCoord = gl_GlobalInvocationID.xyz;
    bool activeCluster = clusterCoord.x < gridSize.x && clusterCoord.y < gridSize.y && clusterCoord.z < gridSize.z;
    uint clusterIndex = getClusterLinearIndex(clusterCoord);
    
    // we have a cache of GROUP_SIZE lights
    // have to run this loop several times if we have more than GROUP_SIZE lights
    uint lightCount = GetPointLightCount();
    uint lightBatchCount = (lightCount + GROUP_SIZE - 1u) / GROUP_SIZE;
    for (uint lightBatch = 0u; lightBatch < lightBatchCount; ++lightBatch)
    {
        uint lightOffset = lightBatch * GROUP_SIZE;
        // read GROUP_SIZE lights into shared memory
        // each thread copies one light
        uint batchSize = lightOffset < lightCount ? min(GROUP_SIZE, lightCount - lightOffset) : 0u;

        // 每次多线程取batchSize个灯，如果线程数量比batchsize多，只有前面的线程工作
        if(uint(gl_LocalInvocationIndex) < batchSize)
        {
            uint lightIndex = lightOffset + gl_LocalInvocationIndex;
#ifdef CLUSTER_SPOTLIGHT
            SpotLight light = GetSpotLight(lightIndex);
            light.position = mul(vec4(light.position, 1.0),u_view).xyz;
            light.direction = normalize(mul(vec4(light.direction, 0.0),u_view).xyz);
            EncodeSharedSpotLight(gl_LocalInvocationIndex, light);
#else
            PointLight light = GetPointLight(lightIndex);
            // transform to view space (expected by pointLightAffectsCluster)
            // do it here once rather than for each cluster later
            // 注意行列矩阵，sample和我们应该是反的
            light.position = mul(vec4(light.position, 1.0),u_view).xyz;
            EncodeSharedPointLight(gl_LocalInvocationIndex, light);
#endif
        }

        // wait for all threads to finish copying
        barrier();

        // each thread is one cluster and checks against all lights in the cache
        // 每个cluster算下取到的batchsize个灯里，有没有和该cluster有相交关系的，这里每个线程都在工作
        if (activeCluster)
        {
            Cluster cluster = getCluster(clusterIndex);
            for(uint i = 0u; i < batchSize; i++)
            {
#ifdef CLUSTER_SPOTLIGHT
                SpotLight light = GetSharedSpotLight(i);
#else
                PointLight light = GetSharedPointLight(i);
#endif
                if(visibleCount < uint(MAX_LIGHTS_PER_CLUSTER) && LightIntersectsCluster(light, cluster))
                {
                    visibleLights[visibleCount] = lightOffset + i;
                    visibleCount++;
                }
            }
        }

        // All readers must finish before the next batch overwrites sharedLights.
        barrier();
    }

    // wait for all threads to finish checking lights
    barrier();

    // get a unique index into the light index list where we can write this cluster's lights
    uint offset = 0u;
#if NONPUNCTUAL_LIGHTING
    //处理编辑器的非精确点光
    uint visibleNonPunctualLights[MAX_LIGHTS_PER_CLUSTER];
    uint visibleNonPunctualLightCount = 0u;
    lightCount = u_nonPunctualPointLightCount;
    lightBatchCount = (lightCount + GROUP_SIZE - 1u) / GROUP_SIZE;
    for (uint lightBatch = 0u; lightBatch < lightBatchCount; ++lightBatch)
    {
        uint lightOffset = lightBatch * GROUP_SIZE;
        uint batchSize = lightOffset < lightCount ? min(GROUP_SIZE, lightCount - lightOffset) : 0u;

        // 每次多线程取batchSize个灯，如果线程数量比batchsize多，只有前面的线程工作
        if(uint(gl_LocalInvocationIndex) < batchSize)
        {
            uint lightIndex = lightOffset + gl_LocalInvocationIndex;
            NonPunctualPointLight light = GetNonPunctualPointLight(lightIndex);
            // transform to view space (expected by pointLightAffectsCluster)
            // do it here once rather than for each cluster later
            // 注意行列矩阵，sample和我们应该是反的
            light.position = mul(vec4(light.position, 1.0),u_view).xyz;
            EncodeSharedNonPunctualPointLight(gl_LocalInvocationIndex, light);
        }

        // wait for all threads to finish copying
        barrier();

        // each thread is one cluster and checks against all lights in the cache
        // 每个cluster算下取到的batchsize个灯里，有没有和该cluster有相交关系的，这里每个线程都在工作
        if (activeCluster)
        {
            Cluster cluster = getCluster(clusterIndex);
            for(uint i = 0u; i < batchSize; i++)
            {
                NonPunctualPointLight light = GetSharedNonPunctualPointLight(i);
                if(visibleCount + visibleNonPunctualLightCount < uint(MAX_LIGHTS_PER_CLUSTER) &&
                   NonPunctualPointLightIntersectsCluster(light, cluster))
                {
                    visibleNonPunctualLights[visibleNonPunctualLightCount] = lightOffset + i;
                    visibleNonPunctualLightCount++;
                }
            }
        }

        barrier();
    }

    // RectLight culling
    uint visibleRectLights[MAX_LIGHTS_PER_CLUSTER];
    uint visibleRectLightCount = 0u;
    lightCount = u_rectLightCount;
    lightBatchCount = (lightCount + GROUP_SIZE - 1u) / GROUP_SIZE;
    for (uint lightBatch = 0u; lightBatch < lightBatchCount; ++lightBatch)
    {
        uint lightOffset = lightBatch * GROUP_SIZE;
        uint batchSize = lightOffset < lightCount ? min(GROUP_SIZE, lightCount - lightOffset) : 0u;
        if(uint(gl_LocalInvocationIndex) < batchSize)
        {
            uint lightIndex = lightOffset + gl_LocalInvocationIndex;
            RectLight light = GetRectLight(lightIndex);
            light.position = mul(vec4(light.position, 1.0),u_view).xyz;
            light.direction = normalize(mul(vec4(light.direction, 0.0),u_view).xyz);
            light.tangent = normalize(mul(vec4(light.tangent, 0.0),u_view).xyz);
            EncodeSharedRectLight(gl_LocalInvocationIndex, light);
        }
        barrier();
        if (activeCluster)
        {
            Cluster cluster = getCluster(clusterIndex);
            for(uint i = 0u; i < batchSize; i++)
            {
                RectLight light = GetSharedRectLight(i);
                if(visibleCount + visibleNonPunctualLightCount + visibleRectLightCount < uint(MAX_LIGHTS_PER_CLUSTER) &&
                   RectLightIntersectsCluster(light, cluster))
                {
                    visibleRectLights[visibleRectLightCount] = lightOffset + i;
                    visibleRectLightCount++;
                }
            }
        }
        barrier();
    }

    // wait for all threads to finish checking lights
    barrier();
    if (!activeCluster)
        return;
    atomicFetchAndAdd(b_globalIndex[0], visibleCount + visibleNonPunctualLightCount + visibleRectLightCount, offset);
#else//NONPUNCTUAL_LIGHTING
    if (!activeCluster)
        return;
    // 其实就是b_globalIndex[0] = visibleCount + offset;offset = b_globalIndex[0]
    // offset是局部变量，相当于每个线程有一个基于当前b_globalIndex的offset
    atomicFetchAndAdd(b_globalIndex[0], visibleCount, offset);
#endif//NONPUNCTUAL_LIGHTING
    // copy indices of lights
    for(uint i = 0u; i < visibleCount; i++)
    {
        b_clusterLightIndices[offset + i] = visibleLights[i];
    }

#if NONPUNCTUAL_LIGHTING
    for (uint i = 0u; i < visibleNonPunctualLightCount; i++)
    {
        b_clusterLightIndices[offset + visibleCount + i] = visibleNonPunctualLights[i];
    }
    for (uint i = 0u; i < visibleRectLightCount; i++)
    {
        b_clusterLightIndices[offset + visibleCount + visibleNonPunctualLightCount + i] = visibleRectLights[i];
    }
    // 下标显式转 int：glslang 编 ESSL 时不接受 int 字面量与 uint 的隐式混算
    int gridBase = 4 * int(clusterIndex);
    b_clusterLightGrid[gridBase] = offset;
    b_clusterLightGrid[gridBase + 1] = visibleCount;
    b_clusterLightGrid[gridBase + 2] = visibleRectLightCount;
    b_clusterLightGrid[gridBase + 3] = visibleNonPunctualLightCount;
#else//NONPUNCTUAL_LIGHTING
    // write light grid for this cluster
    int gridBase = 4 * int(clusterIndex);
    b_clusterLightGrid[gridBase] = offset;
    b_clusterLightGrid[gridBase + 1] = visibleCount;
    b_clusterLightGrid[gridBase + 2] = 0;
    b_clusterLightGrid[gridBase + 3] = 0;
#endif//NONPUNCTUAL_LIGHTING
}

// check if light radius extends into the cluster
bool LightIntersectsCluster(PointLight light, Cluster cluster)
{
    // NOTE: expects light.position to be in view space like the cluster bounds
    // global light list has world space coordinates, but we transform the
    // coordinates in the shared array of lights after copying

    // get closest point to sphere center
 
    vec3 closest = max(cluster.minBounds, min(light.position, cluster.maxBounds));
    //vec3 closest;
    //closest.x= max(cluster.minBounds.x, min(light.position.x, cluster.maxBounds.x));
    //closest.y= max(cluster.minBounds.y, min(light.position.y, cluster.maxBounds.y));
    //closest.z= max(cluster.minBounds.z, min(light.position.z, cluster.maxBounds.z));
    // check if point is inside the sphere
    vec3 dist = closest - light.position;
    return dot(dist, dist) <= (light.radius * light.radius);
}

#ifdef CLUSTER_SPOTLIGHT
bool LightIntersectsCluster(SpotLight light, Cluster cluster)
{
    vec3 closest = max(cluster.minBounds, min(light.position, cluster.maxBounds));
    // check if point is inside the sphere
    vec3 dist = closest - light.position;
    if (dot(dist, dist) > (light.range * light.range))
        return false;
    //点光的这个数值为-1，只有锥光需要继续算下去
    if (light.cosOuterCone < 0.0)
        return true;
    vec3 center = 0.5 * (cluster.minBounds + cluster.maxBounds);
    dist = center - light.position;
    vec3 M = normalize(cross(cross(light.direction, dist), light.direction));
    //这里可以不normalize,省个操作，因为后面是两个点乘比较等于是等比放缩了而已
    vec3 N = M - light.direction * sqrt(1.0 - light.cosOuterCone * light.cosOuterCone) / light.cosOuterCone;
    vec3 extents = 0.5 * (cluster.maxBounds - cluster.minBounds);
    return dot(dist, N) <= dot(extents, abs(N));
}
#endif //CLUSTER_SPOTLIGHT

#endif
#endif
