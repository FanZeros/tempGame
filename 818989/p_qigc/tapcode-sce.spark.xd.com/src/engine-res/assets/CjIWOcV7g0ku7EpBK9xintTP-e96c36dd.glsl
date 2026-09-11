#define WRITE_CLUSTERS
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"

#include "Cluster/clustercommon.sh"
#include <Common/bgfx_compute.sh>
#include "Cluster/clusters.sh"

NUM_THREADS(1, 1, 1)
void main()
{
    if(gl_GlobalInvocationID.x == 0u)
    {
        // reset the atomic counter for the light grid generation
        // writable compute buffers can't be updated by CPU so do it here
        b_globalIndex[0] = 0u;
    }
}

#endif
#endif
