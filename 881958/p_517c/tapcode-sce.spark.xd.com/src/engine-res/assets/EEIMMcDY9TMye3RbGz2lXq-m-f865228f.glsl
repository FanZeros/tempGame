#define WRITE_CLUSTERS
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"

#include "Cluster/clustercommon.sh"
#include "Common/bgfx_compute.sh"
#include "Cluster/clusters.sh"
#include "Cluster/clusterutil.sh"

#define gl_WorkGroupSize uvec3(CLUSTERS_X_THREADS, CLUSTERS_Y_THREADS, CLUSTERS_Z_THREADS)


NUM_THREADS(CLUSTERS_X_THREADS, CLUSTERS_Y_THREADS, CLUSTERS_Z_THREADS)
void main()
{
    uvec3 gridSize = getClusterGridSize();
    uvec3 clusterCoord = gl_GlobalInvocationID.xyz;
    if (clusterCoord.x >= gridSize.x || clusterCoord.y >= gridSize.y || clusterCoord.z >= gridSize.z)
        return;

    uint clusterIndex = getClusterLinearIndex(clusterCoord);

    vec4 minScreen = vec4( vec2(gl_GlobalInvocationID.xy)              * u_clusterSizes.xy, 1.0, 1.0);
    vec4 maxScreen = vec4((vec2(gl_GlobalInvocationID.xy) + vec2(1, 1)) * u_clusterSizes.xy, 1.0, 1.0);

    vec3 minEye = screen2Eye(minScreen).xyz;
    vec3 maxEye = screen2Eye(maxScreen).xyz;

#ifdef ORTHOGRAPHIC
    float clusterNear = lerp(u_zNear, u_zFar, float(clusterCoord.z) / u_clusterGridVec.z);
    float clusterFar = lerp(u_zNear, u_zFar, float(clusterCoord.z + 1u) / u_clusterGridVec.z);
#else
    float clusterNear = u_zNear * pow(u_zFar / u_zNear, float(clusterCoord.z) / u_clusterGridVec.z);
    float clusterFar  = u_zNear * pow(u_zFar / u_zNear, float(clusterCoord.z + 1u) / u_clusterGridVec.z);
#endif

#ifdef RIGHTHANDED
    // RH：u_view 把前方物体变到 view-space z<0（实测），灯光走 u_view 也在 z<0。
    // cluster z 切片深度(clusterNear/Far)默认按左手取正 → 包围盒会被钉到 +z，与灯光 -z 不同侧，
    // range/cone 剔除全错。故 RH 下把切片深度取负，让包围盒落到 -z 与灯光同侧；
    // screen2Eye 重建的 eye 已是 -z，minEye*clusterNear/minEye.z 的 xy 仍正确（负/负为正）。
    clusterNear = -clusterNear;
    clusterFar  = -clusterFar;
#endif

#ifdef ORTHOGRAPHIC
    vec3 minNear = vec3(minEye.xy, clusterNear);
    vec3 minFar  = vec3(minEye.xy, clusterFar);
    vec3 maxNear = vec3(maxEye.xy, clusterNear);
    vec3 maxFar  = vec3(maxEye.xy, clusterFar);
#else
    vec3 minNear = minEye * clusterNear / minEye.z;
    vec3 minFar  = minEye * clusterFar  / minEye.z;
    vec3 maxNear = maxEye * clusterNear / maxEye.z;
    vec3 maxFar  = maxEye * clusterFar  / maxEye.z;
#endif

    vec3 minBounds = min(min(minNear, minFar), min(maxNear, maxFar));
    vec3 maxBounds = max(max(minNear, minFar), max(maxNear, maxFar));

    b_clusters[2 * int(clusterIndex) + 0] = vec4(minBounds, 1.0);
    b_clusters[2 * int(clusterIndex) + 1] = vec4(maxBounds, 1.0);
}

#endif
#endif
