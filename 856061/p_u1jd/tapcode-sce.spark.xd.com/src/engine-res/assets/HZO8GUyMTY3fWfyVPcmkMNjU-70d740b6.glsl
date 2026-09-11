/*
 * GTAO Bilateral Upsample
 *
 * Upsamples half-resolution AO to full resolution with depth-aware weighting.
 * Prevents AO halo bleeding across depth discontinuities.
 *
 * Simplified from SSRBilateralUpscale: single channel, depth-only weighting
 * (no normal comparison needed — AO is a low-frequency effect).
 */

#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

// Half-res AO (point sampled — we manually pick 4 nearest)
SAMPLER2D(u_HalfResAO0, 0);

// Full-res depth (for edge-aware weighting)
SAMPLER2D(u_Depth1, 1);

// Depth edge threshold (relative): controls sharpness of depth edges.
// Gaussian falloff: weight = exp(-(relDiff/threshold)^2)
// Smaller = sharper edges, larger = more blur across edges.
#define DEPTH_THRESHOLD 0.05

void PS()
{
    hvec2 uv = vTexCoord;

    // Full-res depth at this pixel (linearized for meaningful comparison)
    hfloat fullDepth = LinearizeDepth(texture2D(u_Depth1, uv).r, cNearClipPS, cFarClipPS);

    // Half-res texel size = 2x full-res texel size
    hvec2 halfTexel = cGBufferInvSize.xy * 2.0;

    // Find the 4 nearest half-res texel centers
    hvec2 halfTexCoord = uv / halfTexel - 0.5;
    hvec2 f = fract(halfTexCoord);
    hvec2 baseUV = (floor(halfTexCoord) + 0.5) * halfTexel;

    // 4 half-res texel center UVs
    hvec2 uv00 = baseUV;
    hvec2 uv10 = baseUV + hvec2_init(halfTexel.x, 0.0);
    hvec2 uv01 = baseUV + hvec2_init(0.0, halfTexel.y);
    hvec2 uv11 = baseUV + halfTexel;

    // Bilinear spatial weights
    hfloat ws00 = (1.0 - f.x) * (1.0 - f.y);
    hfloat ws10 = f.x * (1.0 - f.y);
    hfloat ws01 = (1.0 - f.x) * f.y;
    hfloat ws11 = f.x * f.y;

    // Sample half-res AO (point sampled, exact texel values)
    hfloat ao00 = texture2D(u_HalfResAO0, uv00).r;
    hfloat ao10 = texture2D(u_HalfResAO0, uv10).r;
    hfloat ao01 = texture2D(u_HalfResAO0, uv01).r;
    hfloat ao11 = texture2D(u_HalfResAO0, uv11).r;

    // Depth at each half-res position (from full-res depth, linearized)
    hfloat d00 = LinearizeDepth(texture2D(u_Depth1, uv00).r, cNearClipPS, cFarClipPS);
    hfloat d10 = LinearizeDepth(texture2D(u_Depth1, uv10).r, cNearClipPS, cFarClipPS);
    hfloat d01 = LinearizeDepth(texture2D(u_Depth1, uv01).r, cNearClipPS, cFarClipPS);
    hfloat d11 = LinearizeDepth(texture2D(u_Depth1, uv11).r, cNearClipPS, cFarClipPS);

    // Depth weights: Gaussian falloff based on relative depth difference
    hfloat invThresh2 = 1.0 / (DEPTH_THRESHOLD * DEPTH_THRESHOLD);
    hfloat rd00 = (d00 - fullDepth) / max(fullDepth, 0.001);
    hfloat rd10 = (d10 - fullDepth) / max(fullDepth, 0.001);
    hfloat rd01 = (d01 - fullDepth) / max(fullDepth, 0.001);
    hfloat rd11 = (d11 - fullDepth) / max(fullDepth, 0.001);

    hfloat w00 = ws00 * exp(-rd00 * rd00 * invThresh2);
    hfloat w10 = ws10 * exp(-rd10 * rd10 * invThresh2);
    hfloat w01 = ws01 * exp(-rd01 * rd01 * invThresh2);
    hfloat w11 = ws11 * exp(-rd11 * rd11 * invThresh2);

    // Weighted average
    hfloat totalWeight = w00 + w10 + w01 + w11;
    hfloat result;
    if (totalWeight > 0.0001)
    {
        result = (ao00 * w00 + ao10 * w10 + ao01 * w01 + ao11 * w11) / totalWeight;
    }
    else
    {
        // Fallback: pure bilinear (e.g., sky pixels)
        result = ao00 * ws00 + ao10 * ws10 + ao01 * ws01 + ao11 * ws11;
    }

    gl_FragColor = hvec4_init(result, result, result, 1.0);
}

#endif
