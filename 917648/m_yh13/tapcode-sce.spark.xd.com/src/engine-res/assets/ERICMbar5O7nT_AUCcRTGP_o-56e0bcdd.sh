/*
 * XeGTAO Common Functions
 *
 * Faithful port of Intel's XeGTAO (GameTechDev/XeGTAO, MIT License).
 * Based on "Practical Realtime Strategies for Accurate Indirect Occlusion"
 * Jorge Jimenez, Xian-Chun Wu, Angelo Pesce, Adrian Jarabo — SIGGRAPH 2016
 *
 * All computations use full precision (hfloat/hvec*) to avoid fp16 artifacts.
 */

#ifndef GTAO_COMMON_SH
#define GTAO_COMMON_SH

#include "ScreenSpace/ScreenSpaceCommon.sh"

// Constants
#define PI 3.14159265359
#define HALF_PI 1.57079632679

// XeGTAO default tuning constants (from XeGTAO.h / vaGTAO.hlsl)
#define XE_GTAO_RADIUS_MULTIPLIER          1.457
#define XE_GTAO_FALLOFF_RANGE              0.615
#define XE_GTAO_SAMPLE_DISTRIBUTION_POWER  2.0
#define XE_GTAO_PIXEL_TOO_CLOSE_THRESHOLD  1.3
#define XE_GTAO_DEPTH_MIP_SAMPLING_OFFSET  3.30

// Fast acos approximation (polynomial fit, ~0.01 max error)
// XeGTAO uses this to avoid expensive acos() in the inner loop.
hfloat XeGTAO_FastACos(hfloat inX)
{
    hfloat x = abs(inX);
    hfloat res = -0.156583 * x + HALF_PI;
    res *= sqrt(1.0 - x);
    return (inX >= 0.0) ? res : PI - res;
}

// ====================================================================
// Hilbert curve index (XeGTAO.h — HilbertIndex)
// Maps 2D pixel coordinates to a 1D index along the Hilbert space-filling
// curve within a 64x64 tile. The Hilbert curve has excellent spatial
// distribution: neighboring pixels map to very different indices,
// eliminating the directional banding artifacts of IGN noise.
// ====================================================================
#define XE_HILBERT_LEVEL  6
#define XE_HILBERT_WIDTH  64

int XeGTAO_HilbertIndex(int posX, int posY)
{
    int index = 0;
    for (int curLevel = XE_HILBERT_WIDTH / 2; curLevel > 0; curLevel /= 2)
    {
        int regionX = ((posX & curLevel) > 0) ? 1 : 0;
        int regionY = ((posY & curLevel) > 0) ? 1 : 0;
        index += curLevel * curLevel * ((3 * regionX) ^ regionY);
        if (regionY == 0)
        {
            if (regionX == 1)
            {
                posX = (XE_HILBERT_WIDTH - 1) - posX;
                posY = (XE_HILBERT_WIDTH - 1) - posY;
            }
            int temp = posX;
            posX = posY;
            posY = temp;
        }
    }
    return index;
}

// ====================================================================
// SpatioTemporalNoise (vaGTAO.hlsl — SpatioTemporalNoise)
// Combines Hilbert curve index with R2 quasi-random sequence for
// well-distributed 2D noise with temporal variation.
// R2 constants: generalized golden ratio for 2D quasi-random sampling.
// Ref: http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
// ====================================================================
hvec2 XeGTAO_SpatioTemporalNoise(int pixX, int pixY, int temporalIndex)
{
    int hilbert = XeGTAO_HilbertIndex(pixX & (XE_HILBERT_WIDTH - 1),
                                       pixY & (XE_HILBERT_WIDTH - 1));
    hilbert += 288 * (temporalIndex & 63);
    return fract(hvec2_init(0.5, 0.5) + hfloat_init(hilbert)
        * hvec2_init(0.75487766624669276, 0.56984029099805327));
}

#endif // GTAO_COMMON_SH
