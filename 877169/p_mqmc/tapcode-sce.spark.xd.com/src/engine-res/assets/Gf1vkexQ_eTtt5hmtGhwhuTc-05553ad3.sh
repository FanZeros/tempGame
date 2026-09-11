#ifndef VOXEL_DDA_COMMON_SH_HEADER_GUARD
#define VOXEL_DDA_COMMON_SH_HEADER_GUARD

// NOTE dialect: in this codebase hvec*/hfloat compile to fp32 on the DX hlslcc path
// and vec*/float to min16float. Table rows, ray math and depth stay in hvec (fp32);
// never call length()/distance() (fp16 overloads overflow past ~256 voxels, T33).

hfloat VoxelDistanceToBox(hvec3 origin, hvec3 dir, hvec3 size, out int axis)
{
    axis = 0;
    if (all(greaterThanEqual(origin, hvec3_init(0.0, 0.0, 0.0)))
        && all(lessThanEqual(origin, size)))
        return 0.0;
    hvec3 invDir = hvec3_init(1.0, 1.0, 1.0) / dir;
    hvec3 sgn = step(dir, hvec3_init(0.0, 0.0, 0.0));
    hvec3 tmin = (sgn * size - origin) * invDir;
    if (tmin.y > tmin.x && tmin.y > tmin.z)
        axis = 1;
    else if (tmin.z > tmin.x)
        axis = 2;
    return max(max(tmin.x, tmin.y), tmin.z);
}

hfloat VoxelDistanceToBoxBack(hvec3 origin, hvec3 dir, hvec3 size)
{
    hvec3 invDir = hvec3_init(1.0, 1.0, 1.0) / dir;
    hvec3 sgn = step(hvec3_init(0.0, 0.0, 0.0), dir);
    hvec3 tmin = (sgn * size - origin) * invDir;
    return min(min(tmin.x, tmin.y), tmin.z);
}

#endif // VOXEL_DDA_COMMON_SH_HEADER_GUARD
