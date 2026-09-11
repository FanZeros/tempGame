#ifndef VOXEL_DDA_OCCUPANCY_SH_HEADER_GUARD
#define VOXEL_DDA_OCCUPANCY_SH_HEADER_GUARD

#ifdef COMPILEPS
#ifdef VOXEL_SPARSE4
SAMPLER2D(u_VoxelDdaTable, 6);
SAMPLER2D(u_VoxelDdaDirectory, 7);
#define sVoxelDdaTable u_VoxelDdaTable
#define sVoxelDdaDirectory u_VoxelDdaDirectory

void VoxelSparse4Advance(inout hfloat t, hvec3 tMax, out hvec3 cmp)
{
    // Absolute boundary times avoid accumulated DDA error. Cross every boundary that
    // is already at/before the current walker time. If fp32 quantization rounds the
    // minimum to an unchanged t, the integer walker still crosses those axes below.
    // A fixed epsilon could skip a real thin interval.
    // Deliberately do not fuzz ordinary ties: a real sub-1e-4 interval may contain a
    // solid voxel and must still be sampled.
    hfloat nextT = min(tMax.x, min(tMax.y, tMax.z));
    hfloat reachedT = max(nextT, t);
    cmp = step(tMax, hvec3_init(reachedT, reachedT, reachedT));
    t = reachedT;
}

void FetchSparse4Directory(ivec3 macroCoord, ivec3 macroDim, int directoryBase,
    out int slotPlusOne, out int occupancyMask)
{
    int logicalIndex =
        (macroCoord.z * macroDim.y + macroCoord.y) * macroDim.x + macroCoord.x;
    int directoryIndex = directoryBase + logicalIndex;
    ivec2 directoryCoord = ivec2(directoryIndex & 4095, directoryIndex >> 12);
    vec4 encoded = texelFetch(sVoxelDdaDirectory, directoryCoord, 0);

    // Convert each normalized byte to a full-width integer before combining it.
    // In particular, never form the 24-bit value through min16 float arithmetic.
    int byteR = int(floor(encoded.r * 255.0 + 0.5));
    int byteG = int(floor(encoded.g * 255.0 + 0.5));
    int byteB = int(floor(encoded.b * 255.0 + 0.5));
    int byteA = int(floor(encoded.a * 255.0 + 0.5));
    slotPlusOne = byteR | (byteG << 8) | (byteB << 16);
    occupancyMask = byteA;
}

// Sparse4 explicit hierarchy: Directory macrobrick (4^3), its 2^3 conservative
// mask, then one exact Pool voxel. The Directory handle/mask are fetched only when
// the clamped fetch position enters a different macrobrick.
hfloat RaycastSparse4Occupancy(hvec3 origin, hvec3 dir, hfloat maxDist, int entryAxis,
    hvec3 dim, int directoryBase, out vec4 hitSamp, out int hitAxis)
{
    // Keep traversal state as an exact integer voxel coordinate. Reconstructing it
    // from origin + dir * t at every hierarchy change is ambiguous on a negative
    // boundary and can oscillate when two tied axes round to opposite sides.
    hvec3 rayOrigin = origin;
    hvec3 rayDir = dir;
    hvec3 invAbs = hvec3_init(1.0, 1.0, 1.0)
        / max(abs(rayDir), hvec3_init(1e-8, 1e-8, 1e-8));
    hvec3 tSign = sign(rayDir);
    hvec3 zSign = step(hvec3_init(0.0, 0.0, 0.0), tSign);
    hvec3 cmp = hvec3_init(0.0, 0.0, 0.0);
    hvec3 walkerVoxel = floor(rayOrigin);
    hvec3 originFraction = rayOrigin - walkerVoxel;
    hvec3 negativeDirection = hvec3_init(1.0, 1.0, 1.0) - zSign;
    // Only an exact half-open boundary belongs to the preceding cell for a negative
    // ray. A spatial/time epsilon here could skip a genuinely occupied start voxel.
    hvec3 startsOnBoundary = step(originFraction,
        hvec3_init(0.0, 0.0, 0.0));
    walkerVoxel -= negativeDirection * startsOnBoundary;
    hitSamp = vec4(0.0, 0.0, 0.0, 0.0);
    hitAxis = entryAxis;

    ivec3 volumeDim = ivec3(int(dim.x + 0.5), int(dim.y + 0.5), int(dim.z + 0.5));
    ivec3 macroDim = ivec3(
        (volumeDim.x + 3) >> 2, (volumeDim.y + 3) >> 2, (volumeDim.z + 3) >> 2);
    ivec3 cachedMacro = ivec3(-1, -1, -1);
    int cachedSlotPlusOne = 0;
    int cachedOccupancyMask = 0;

    hfloat t = 0.0;
    int guard = 0;
    const int maxSteps = 2048;

    LOOP
    while (t < maxDist && guard < maxSteps)
    {
        ++guard;
        hvec3 fetchPos = clamp(walkerVoxel, hvec3_init(0.0, 0.0, 0.0),
            dim - hvec3_init(1.0, 1.0, 1.0));
        ivec3 fetchVoxel = ivec3(int(fetchPos.x), int(fetchPos.y), int(fetchPos.z));
        ivec3 macroCoord = ivec3(fetchVoxel.x >> 2, fetchVoxel.y >> 2, fetchVoxel.z >> 2);

        BRANCH
        if (macroCoord.x != cachedMacro.x || macroCoord.y != cachedMacro.y
            || macroCoord.z != cachedMacro.z)
        {
            cachedMacro = macroCoord;
            FetchSparse4Directory(
                cachedMacro, macroDim, directoryBase, cachedSlotPlusOne, cachedOccupancyMask);
        }

        hfloat cellSize = 4.0;
        BRANCH
        if (cachedSlotPlusOne != 0)
        {
            ivec3 localVoxel = fetchVoxel - cachedMacro * 4;
            int maskBit = (localVoxel.x >> 1) | ((localVoxel.y >> 1) << 1)
                | ((localVoxel.z >> 1) << 2);
            BRANCH
            if ((cachedOccupancyMask & (1 << maskBit)) != 0)
            {
                int slot = cachedSlotPlusOne - 1;
                ivec3 slotCoord = ivec3(slot & 63, (slot >> 6) & 63, slot >> 12);
                ivec3 poolCoord = slotCoord * 4 + localVoxel;
                vec4 samp = texelFetch(sVolumeMap, poolCoord, 0);
                BRANCH
                if (samp.g > 0.0)
                {
                    hitSamp = samp;
                    int stepped = int(cmp.y + cmp.z * 2.0);
                    hitAxis = (cmp.x + cmp.y + cmp.z > 0.5) ? stepped : entryAxis;
                    return t;
                }
                cellSize = 1.0;
            }
            else
                cellSize = 2.0;
        }

        // Select the next boundary from the UNCLAMPED integer walker. Boundary
        // times are measured from the original ray origin rather than reconstructed
        // as a small delta plus a large t, avoiding cancellation at distant cells.
        hvec3 cellCoord = floor(walkerVoxel / cellSize);
        hvec3 boundary = (cellCoord + zSign) * cellSize;
        hvec3 tMax = abs(boundary - rayOrigin) * invAbs;
        VoxelSparse4Advance(t, tMax, cmp);

        // For axes crossed this step, derive the forward-side voxel exactly from
        // the integer boundary. Other axes may legitimately move across several
        // fine voxels during a 2/4-cell skip, so reconstruct those from t without
        // ever letting fp32 cancellation move them backwards along the ray.
        hvec3 nextVoxel = floor(rayOrigin + rayDir * t);
        nextVoxel = min(nextVoxel, walkerVoxel) * negativeDirection
            + max(nextVoxel, walkerVoxel) * zSign;
        hvec3 crossedVoxel = (cellCoord + zSign) * cellSize
            - (hvec3_init(1.0, 1.0, 1.0) - zSign);
        walkerVoxel = nextVoxel * (hvec3_init(1.0, 1.0, 1.0) - cmp)
            + crossedVoxel * cmp;
    }
    return maxDist;
}
#else
SAMPLER2D(u_VoxelDdaTable, 6);
#define sVoxelDdaTable u_VoxelDdaTable

// Coarse levels are hardware 3D mips; ti is already in mip space with the same
// floor(dim >> mip) footprint the GPU uses (odd tail folds into the last cell).
// atlasBase is the volume's mip-0 texel offset in the shared atlas page; offsets and
// quantized sizes are 4-aligned so (base >> mip) is exact and coarse texels never
// straddle two bricks. texelFetch is point sampling — no filter bleed across bricks.
vec4 SampleOccupancyLod(hvec3 ti, int mip, ivec3 atlasBase)
{
    ivec3 base = ivec3(atlasBase.x >> mip, atlasBase.y >> mip, atlasBase.z >> mip);
    return texelFetch(sVolumeMap, base + ivec3(int(ti.x), int(ti.y), int(ti.z)), mip);
}

// Desktop Teardown textureLod is clamp-to-edge. Starting at minDist-0.001 puts ti
// just outside the box; treating that as empty then stepping a mip-2 cell (4 voxels)
// skips a 1-voxel-thick ground tile. Clamp the fetch only — the DDA walker stays free.
vec4 SampleOccupancyLodClamp(hvec3 ti, int mip, ivec3 atlasBase, hvec3 mipDim)
{
    hvec3 c = clamp(floor(ti), hvec3_init(0.0, 0.0, 0.0),
        mipDim - hvec3_init(1.0, 1.0, 1.0));
    return SampleOccupancyLod(c, mip, atlasBase);
}

void VoxelDdaAdvance(inout hfloat t, inout hvec3 tMax, inout hvec3 ti, inout hvec3 cmp,
    hvec3 tDelta, hvec3 tSign)
{
    // Teardown gbuffervox / raytracing.h: no clamp on t. Ties can make
    // dot(tMax, cmp) = k*tMin; the next step assigns t from tMax again.
    cmp = step(tMax.xyz, tMax.zxy) * step(tMax.xyz, tMax.yzx);
#if 1
    t = dot(tMax, cmp);
#else
    hfloat nextT = dot(tMax, cmp);
    if (nextT <= t)
        nextT = t + 1e-4;
    t = nextT;
#endif
    tMax += tDelta * cmp;
    ti += tSign * cmp;
}

// Teardown gbuffervox raycastVolume (#else): start mip 2, nonempty refines,
// empty uses a step budget then coarsens. ti is mip-space for texelFetch.
// Atlas only has mip 0–2, so coarsen stops at 2 (theirs can go higher).
hfloat RaycastOccupancy(hvec3 origin, hvec3 dir, hfloat maxDist, int entryAxis,
    hvec3 dim, ivec3 atlasBase, out vec4 hitSamp, out int hitAxis)
{
    hvec3 invAbs = hvec3_init(1.0, 1.0, 1.0) / (abs(dir) + hvec3_init(1e-5, 1e-5, 1e-5));
    hvec3 tSign = sign(dir);
    hvec3 zSign = step(hvec3_init(0.0, 0.0, 0.0), tSign);
    hvec3 cmp = hvec3_init(0.0, 0.0, 0.0);
    hitSamp = vec4(0.0, 0.0, 0.0, 0.0);
    hitAxis = entryAxis;

    int mip = 2;
    hfloat t = 0.0;
    int guard = 0;
    const int maxSteps = 2048;

    LOOP
    while (t < maxDist && guard < maxSteps)
    {
        ++guard;
        BRANCH
        if (mip == 0)
        {
            hfloat cell = 1.0;
            hvec3 tPos = (origin + dir * t) / cell;
            hvec3 ti = floor(tPos);
            hvec3 tMax = invAbs * (zSign + tSign * (ti - tPos)) * cell
                + hvec3_init(t, t, t);
            hvec3 tDelta = invAbs * cell;
            int c = 0;
            LOOP
            while (t < maxDist && c++ < 12 && guard < maxSteps)
            {
                ++guard;
                vec4 samp = SampleOccupancyLodClamp(ti, 0, atlasBase, dim);
                BRANCH
                if (samp.g > 0.0)
                {
                    hitSamp = samp;
                    int stepped = int(cmp.y + cmp.z * 2.0);
                    hitAxis = (cmp.x + cmp.y + cmp.z > 0.5) ? stepped : entryAxis;
                    return t;
                }
                VoxelDdaAdvance(t, tMax, ti, cmp, tDelta, tSign);
            }
            mip = 1;
        }
        else
        {
            hfloat cell = float(1 << mip);
            hvec3 mipDim = max(floor(dim / cell), hvec3_init(1.0, 1.0, 1.0));
            hvec3 tPos = (origin + dir * t) / cell;
            hvec3 ti = floor(tPos);
            hvec3 tMax = invAbs * (zSign + tSign * (ti - tPos)) * cell
                + hvec3_init(t, t, t);
            hvec3 tDelta = invAbs * cell;
            int c = (mip < 2) ? 12 : 1024;
            LOOP
            while (t < maxDist && guard < maxSteps)
            {
                ++guard;
                BRANCH
                if (c-- == 0)
                {
                    BRANCH
                    if (mip < 2)
                        mip += 1;
                    break;
                }
                vec4 samp = SampleOccupancyLodClamp(ti, mip, atlasBase, mipDim);
                BRANCH
                if (samp.g > 0.0)
                {
                    mip -= 1;
                    break;
                }
                VoxelDdaAdvance(t, tMax, ti, cmp, tDelta, tSign);
            }
        }
    }
    return maxDist;
}
#endif // VOXEL_SPARSE4
#endif // COMPILEPS

#endif // VOXEL_DDA_OCCUPANCY_SH_HEADER_GUARD
