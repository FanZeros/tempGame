#ifndef VOXEL_SHADOW_VOLUME_SH_HEADER_GUARD
#define VOXEL_SHADOW_VOLUME_SH_HEADER_GUARD

#ifdef VOXEL_SHADOW_VOLUME

// Port of Teardown raytracing.h:
//   raycastShadowVolume          (Accurate)
//   raycastShadowVolumeSparse    (Sparse, lighting default)
//   raycastShadowVolumeSuperSparse
// plus jitterPosition. uShadowVolume is R8UI .x; ours is RG8, bitmask in .g (UNORM).
//
// u_VoxelShadowQuery: 0 Accurate, 1 Sparse, 2 SuperSparse. Runtime switch, one variant.
SAMPLER3D(u_VoxelShadowVolume, 6);
// Teardown uBlueNoise: baked 128² RGB LUT, nearest/wrap. Unit 7 = TU_CUSTOM2 (desktop).
SAMPLER2D(u_VoxelShadowBlueNoise, 7);

uniform hvec3 u_VoxelShadowOrigin;
uniform hvec3 u_VoxelShadowResolution;
uniform hfloat u_VoxelShadowTexelSize;
uniform hvec3 u_VoxelShadowInvRes;
uniform hfloat u_VoxelShadowQuery;
// 0 = no random tangent jitter. 1 = full Teardown jitterPosition (blueNoise + TAA).
uniform hfloat u_VoxelShadowJitter;
// Teardown mubFrameParams.a (FrameRnd). We pass the TAA frame counter.
uniform hfloat u_VoxelShadowFrameRnd;

// Teardown common.h
#define VOXEL_SHADOW_BLUENOISE_SIZE 128.0
#define VOXEL_SHADOW_ALPHA1 0.618034005
#define VOXEL_SHADOW_ALPHA2_X 0.75487762
#define VOXEL_SHADOW_ALPHA2_Y 0.56984027
#define VOXEL_SHADOW_ALPHA3_X 0.819172502
#define VOXEL_SHADOW_ALPHA3_Y 0.671043575
#define VOXEL_SHADOW_ALPHA3_Z 0.549700439

hvec2 g_VoxelShadowBlueNoiseTc;

hvec4 VoxelShadowSampleBlueNoise(hvec2 uv)
{
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    return texture2D(u_VoxelShadowBlueNoise, vec2(uv));
#else
    return u_VoxelShadowBlueNoise.m_texture.Sample(u_VoxelShadowBlueNoise.m_sampler, uv);
#endif
}

void VoxelShadowBlueNoiseInit()
{
    g_VoxelShadowBlueNoiseTc = hvec2_init(gl_FragCoord.x, gl_FragCoord.y)
        / VOXEL_SHADOW_BLUENOISE_SIZE;
}

hfloat VoxelShadowBlueNoise()
{
    hfloat n = VoxelShadowSampleBlueNoise(g_VoxelShadowBlueNoiseTc).r;
    hfloat v = fract(n + VOXEL_SHADOW_ALPHA1 * u_VoxelShadowFrameRnd);
    g_VoxelShadowBlueNoiseTc += hvec2_init(VOXEL_SHADOW_ALPHA2_X, VOXEL_SHADOW_ALPHA2_Y);
    return v;
}

hvec3 VoxelShadowBlueNoise3()
{
    hvec3 n = VoxelShadowSampleBlueNoise(g_VoxelShadowBlueNoiseTc).rgb;
    hvec3 v = fract(n + hvec3_init(VOXEL_SHADOW_ALPHA3_X, VOXEL_SHADOW_ALPHA3_Y, VOXEL_SHADOW_ALPHA3_Z)
        * u_VoxelShadowFrameRnd);
    g_VoxelShadowBlueNoiseTc += hvec2_init(VOXEL_SHADOW_ALPHA2_X, VOXEL_SHADOW_ALPHA2_Y);
    return v;
}

int VoxelShadowFetchBits(hvec3 uv, hfloat mip)
{
    hfloat lod = max(mip, 0.0);
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    return int(texture3DLod(u_VoxelShadowVolume, vec3(uv), lod).g * 255.0 + 0.5);
#else
    return int(u_VoxelShadowVolume.m_texture.SampleLevel(
        u_VoxelShadowVolume.m_sampler, uv, lod).g * 255.0 + 0.5);
#endif
}

int VoxelShadowSubBit(hvec3 uv)
{
    int bit = 0;
    bit += fract(uv.x * u_VoxelShadowResolution.x) > 0.5 ? 1 : 0;
    bit += fract(uv.y * u_VoxelShadowResolution.y) > 0.5 ? 2 : 0;
    bit += fract(uv.z * u_VoxelShadowResolution.z) > 0.5 ? 4 : 0;
    return bit;
}

// Amanatides–Woo DDA. Teardown raycastShadowVolume.
hfloat RaycastVoxelShadowVolumeAccurate(hvec3 originWorld, hvec3 dir, hfloat maxDist)
{
    hvec3 origin = originWorld - u_VoxelShadowOrigin;
    hvec3 invDir = hvec3_init(1.0, 1.0, 1.0) / (abs(dir) + hvec3_init(1e-5, 1e-5, 1e-5));
    hvec3 tSign = sign(dir);
    hvec3 zSign = step(hvec3_init(0.0, 0.0, 0.0), tSign);
    hfloat volumeTexelSize = u_VoxelShadowTexelSize;
    hvec3 invRes = u_VoxelShadowInvRes;
    hvec3 res = u_VoxelShadowResolution;

    int mip = -1;
    hfloat t = 0.0;
    int guard = 0;

    LOOP
    while (t < maxDist && guard < 2048)
    {
        ++guard;
        BRANCH
        if (mip == -1)
        {
            hfloat texelSize = volumeTexelSize * 0.5;
            hvec3 invResolution = invRes * 0.5;
            hvec3 tDelta = invDir * texelSize;
            hvec3 tPos = (origin + dir * t) / texelSize;
            hvec3 ti = floor(tPos);
            hvec3 tMax = (invDir * (zSign + tSign * (ti - tPos))) * texelSize
                + hvec3_init(t, t, t);
            ti = (ti + hvec3_init(0.5, 0.5, 0.5)) * invResolution;
            hvec3 tStep = tSign * invResolution;
            int c = 0;
            LOOP
            while (t < maxDist && c++ < 8 && guard < 2048)
            {
                ++guard;
                int a = VoxelShadowFetchBits(ti, 0.0);
                BRANCH
                if (a != 0)
                {
                    BRANCH
                    if ((a & (1 << VoxelShadowSubBit(ti))) != 0)
                        return t;
                }
                hvec3 cmp = step(tMax.xyz, tMax.zxy) * step(tMax.xyz, tMax.yzx);
                t = dot(tMax, cmp);
                tMax += tDelta * cmp;
                ti += tStep * cmp;
            }
            mip = 0;
        }
        else
        {
            hfloat mipScale = float(1 << mip);
            hfloat texelSize = volumeTexelSize * mipScale;
            hvec3 invResolution = invRes * mipScale;
            hvec3 tDelta = invDir * texelSize;
            hvec3 tPos = (origin + dir * t) / texelSize;
            hvec3 ti = floor(tPos);
            hvec3 tMax = (invDir * (zSign + tSign * (ti - tPos))) * texelSize
                + hvec3_init(t, t, t);
            ti = (ti + hvec3_init(0.5, 0.5, 0.5)) * invResolution;
            hvec3 tStep = tSign * invResolution;
            int c = (mip < 2) ? 8 : 1024;
            LOOP
            while (t < maxDist && guard < 2048)
            {
                ++guard;
                BRANCH
                if (c-- == 0)
                {
                    mip += 1;
                    break;
                }
                int a = VoxelShadowFetchBits(ti, float(mip));
                BRANCH
                if (a != 0)
                {
                    mip -= 1;
                    break;
                }
                hvec3 cmp = step(tMax.xyz, tMax.zxy) * step(tMax.xyz, tMax.yzx);
                t = dot(tMax, cmp);
                tMax += tDelta * cmp;
                ti += tStep * cmp;
            }
        }
    }
    return maxDist;
}

// Fixed-step lod refine/coarsen. Teardown raycastShadowVolumeSparse (diffuselight).
hfloat RaycastVoxelShadowVolumeSparse(hvec3 originWorld, hvec3 dir, hfloat maxDist)
{
    hfloat volumeTexelSize = u_VoxelShadowTexelSize;
    hfloat invVolumeTexelSize = 1.0 / max(volumeTexelSize, 1e-5);
    hvec3 origin = originWorld - u_VoxelShadowOrigin;
    hfloat stepLen = volumeTexelSize;
    hvec3 stepDir = dir * u_VoxelShadowInvRes;
    hvec3 pos = origin * invVolumeTexelSize * u_VoxelShadowInvRes;

    stepDir *= 0.5;
    stepLen *= 0.5;
    int lod = -1;
    hfloat d = 0.0;
    int guard = 0;

    LOOP
    while (d < maxDist && guard < 2048)
    {
        ++guard;
        int c = VoxelShadowFetchBits(pos, float(lod));
        BRANCH
        if (lod == -1)
        {
            BRANCH
            if (c != 0)
            {
                BRANCH
                if ((c & (1 << VoxelShadowSubBit(pos))) != 0)
                    return d;
                pos += stepDir;
                d += stepLen;
            }
            else
            {
                lod += 1;
                stepDir *= 2.0;
                stepLen *= 2.0;
                pos += stepDir;
                d += stepLen;
            }
        }
        else
        {
            BRANCH
            if (c != 0)
            {
                stepDir *= 0.5;
                stepLen *= 0.5;
                lod -= 1;
                pos -= stepDir;
                d -= stepLen;
            }
            else
            {
                BRANCH
                if (lod < 2)
                {
                    int coarse = VoxelShadowFetchBits(pos, float(lod + 1));
                    BRANCH
                    if (coarse == 0)
                    {
                        lod += 1;
                        stepDir *= 2.0;
                        stepLen *= 2.0;
                    }
                }
                pos += stepDir;
                d += stepLen;
            }
        }
    }
    return maxDist;
}

// Distance-banded lod, no refine. Teardown raycastShadowVolumeSuperSparse (ambient).
hfloat RaycastVoxelShadowVolumeSuperSparse(hvec3 originWorld, hvec3 dir, hfloat maxDist)
{
    hfloat volumeTexelSize = u_VoxelShadowTexelSize;
    hfloat invVolumeTexelSize = 1.0 / max(volumeTexelSize, 1e-5);
    hvec3 origin = originWorld - u_VoxelShadowOrigin;
    hfloat stepLen = volumeTexelSize;
    hvec3 stepDir = dir * u_VoxelShadowInvRes;
    hvec3 pos = origin * invVolumeTexelSize * u_VoxelShadowInvRes;
    hfloat baseDistance = 0.5;
    hfloat d = 0.0;
    int guard = 0;

    stepDir *= 0.5;
    stepLen *= 0.5;
    LOOP
    while (d < baseDistance && guard < 2048)
    {
        ++guard;
        int c = VoxelShadowFetchBits(pos, 0.0);
        BRANCH
        if ((c & (1 << VoxelShadowSubBit(pos))) != 0)
            return d;
        pos += stepDir;
        d += stepLen;
    }

    stepDir *= 2.0;
    stepLen *= 2.0;
    LOOP
    while (d < baseDistance * 2.0 && guard < 2048)
    {
        ++guard;
        BRANCH
        if (VoxelShadowFetchBits(pos, 0.0) != 0)
            return d;
        pos += stepDir;
        d += stepLen;
    }

    stepDir *= 2.0;
    stepLen *= 2.0;
    LOOP
    while (d < baseDistance * 4.0 && guard < 2048)
    {
        ++guard;
        BRANCH
        if (VoxelShadowFetchBits(pos, 1.0) != 0)
            return d;
        pos += stepDir;
        d += stepLen;
    }

    stepDir *= 2.0;
    stepLen *= 2.0;
    LOOP
    while (d < maxDist && guard < 2048)
    {
        ++guard;
        BRANCH
        if (VoxelShadowFetchBits(pos, 2.0) != 0)
            return d;
        pos += stepDir;
        d += stepLen;
    }
    return maxDist;
}

hfloat GetVoxelShadowVolumeVisibility(hvec3 worldPos, vec3 normal, vec3 lightDir)
{
    hfloat ts = u_VoxelShadowTexelSize;
    hvec3 n = normalize(hvec3_init(normal.x, normal.y, normal.z));
    hvec3 l = normalize(hvec3_init(lightDir.x, lightDir.y, lightDir.z));

    // Teardown jitterPosition + scenecommon.h blueNoise / blueNoise3.
    VoxelShadowBlueNoiseInit();
    hvec3 jitter = hvec3_init(0.0, 0.0, 0.0);
    BRANCH
    if (u_VoxelShadowJitter > 1e-5)
    {
        jitter = VoxelShadowBlueNoise3() - hvec3_init(0.5, 0.5, 0.5);
        jitter -= n * dot(n, jitter);
        hfloat jlen = sqrt(dot(jitter, jitter));
        hfloat n0 = VoxelShadowBlueNoise();
        BRANCH
        if (jlen > 1e-5)
            jitter = jitter / jlen * (ts * 0.5 * n0 * u_VoxelShadowJitter);
    }

    hfloat ndl = max(dot(l, n), 0.0);
    hvec3 origin = worldPos + jitter + l * (ts * 0.5)
        + n * (ts * (0.6 * clamp(1.0 - ndl, 0.2, 0.8)));

    hfloat maxDist = min(cFarClipPS, 256.0);
    hfloat q = u_VoxelShadowQuery;
    hfloat hitT = maxDist;
    BRANCH
    if (q < 0.5)
        hitT = RaycastVoxelShadowVolumeAccurate(origin, l, maxDist);
    else
    {
        BRANCH
        if (q < 1.5)
            hitT = RaycastVoxelShadowVolumeSparse(origin, l, maxDist);
        else
            hitT = RaycastVoxelShadowVolumeSuperSparse(origin, l, maxDist);
    }
    return (hitT < maxDist) ? 0.0 : 1.0;
}

#endif // VOXEL_SHADOW_VOLUME

#endif // VOXEL_SHADOW_VOLUME_SH_HEADER_GUARD
