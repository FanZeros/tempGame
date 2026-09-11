// Build one conservative farthest scene depth value for each froxel XY column.
// The sampled footprint is expanded by half a froxel, matching UE's
// GenerateConservativeDepthBuffer pass and keeping bilinear fog filtering safe.
#ifdef COMPILECS
#ifdef BGFX_SHADER
#include "varying_cluster.def.sc"
#include "Common/bgfx_compute.sh"

SAMPLER2D(u_FroxelFarthestHiZ0, 0);
#ifdef REVERSED_Z
IMAGE2D_WR(u_FroxelConservativeDepth1, r16f, 1);
#else
IMAGE2D_WR(u_FroxelConservativeDepth1, r32f, 1);
#endif

uniform vec4 u_FroxelConservativeGrid; // xy = froxel grid size, z = full-res pixels per froxel, w = max HZB mip
uniform vec4 u_FroxelConservativeHZB;  // xy = full-res view size, zw = HZB mip-0 size

NUM_THREADS(8, 8, 1)
void main()
{
    uvec2 froxel = gl_GlobalInvocationID.xy;
    uvec2 gridSize = uvec2(u_FroxelConservativeGrid.xy);
    if (froxel.x >= gridSize.x || froxel.y >= gridSize.y)
        return;

    float pixelSize = u_FroxelConservativeGrid.z;
    ivec2 viewSize = ivec2(u_FroxelConservativeHZB.xy);

    // Pixel-center footprint of [tile - 0.5, tile + 1.5], inclusive.
    vec2 tile = vec2(froxel);
    ivec2 pixelMin = ivec2(floor((tile - vec2(0.5, 0.5)) * pixelSize + vec2(0.5, 0.5)));
    ivec2 pixelMax = ivec2(floor((tile + vec2(1.5, 1.5)) * pixelSize - vec2(0.5, 0.5)));
    pixelMin = clamp(pixelMin, ivec2(0, 0), viewSize - ivec2(1, 1));
    pixelMax = clamp(pixelMax, pixelMin, viewSize - ivec2(1, 1));

    // HZB mip 0 is half resolution. Select the finest mip where at most a 4x4
    // footprint covers the expanded rectangle, including power-of-two alignment.
    ivec2 hzbMin = pixelMin / 2;
    ivec2 hzbMax = pixelMax / 2;
    int maxMip = int(u_FroxelConservativeGrid.w);
    int mipLevel = 0;
    int mipScale = 1;
    for (int candidate = 0; candidate < 16; ++candidate)
    {
        ivec2 mipMin = hzbMin / mipScale;
        ivec2 mipMax = hzbMax / mipScale;
        if ((mipMax.x - mipMin.x <= 3 && mipMax.y - mipMin.y <= 3) || mipLevel >= maxMip)
            break;
        ++mipLevel;
        mipScale *= 2;
    }

    ivec2 mipMin = hzbMin / mipScale;
    ivec2 mipMax = hzbMax / mipScale;
    ivec2 mipSize = max(ivec2(u_FroxelConservativeHZB.zw) / mipScale, ivec2(1, 1));
    mipMin = clamp(mipMin, ivec2(0, 0), mipSize - ivec2(1, 1));
    mipMax = clamp(mipMax, mipMin, mipSize - ivec2(1, 1));

#ifdef REVERSED_Z
    float farthestDepth = 1.0;
#else
    float farthestDepth = 0.0;
#endif
    for (int y = 0; y < 4; ++y)
    {
        for (int x = 0; x < 4; ++x)
        {
            ivec2 sampleTexel = min(mipMin + ivec2(x, y), mipMax);
            vec2 uv = (vec2(sampleTexel) + vec2(0.5, 0.5)) / vec2(mipSize);
            float depth = texture2DLod(u_FroxelFarthestHiZ0, uv, float(mipLevel)).r;
#ifdef REVERSED_Z
            farthestDepth = min(farthestDepth, depth);
#else
            farthestDepth = max(farthestDepth, depth);
#endif
        }
    }

    imageStore(u_FroxelConservativeDepth1, ivec2(froxel), vec4(farthestDepth, 0.0, 0.0, 0.0));
}
#endif
#endif
