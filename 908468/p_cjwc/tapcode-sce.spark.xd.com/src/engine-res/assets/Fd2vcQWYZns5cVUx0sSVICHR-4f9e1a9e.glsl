/*
 * XeGTAO Denoise — Edge-Weighted Spatial Filter
 *
 * Faithful port of Intel's XeGTAO_Denoise (GameTechDev/XeGTAO, MIT License).
 *
 * Key differences from a naive bilateral blur:
 *   - Slope-aware edge detection (XeGTAO_CalculateEdges): slopes are NOT edges
 *   - Non-separable 3x3 kernel with diagonal weights via L-shaped paths
 *   - Leak prevention heuristic: prevents over-darkening at thin features
 *   - Single pass (not separable H+V which creates diamond artifacts at 45-deg edges)
 *
 * Differences from XeGTAO:
 *   - Pixel shader instead of compute shader (no GatherRed, no 2-pixel-per-thread)
 *   - Edge computed on-the-fly from depth buffer (no separate edge texture)
 *   - Bilateral edge product approximated with center edges only
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

// AO buffer (register 0)
SAMPLER2D(u_AOBuffer0, 0);

// Depth buffer (register 1)
SAMPLER2D(u_Depth1, 1);

// x = DenoiseBlurBeta (1.2 for final pass, 0.24 for non-final)
uniform hvec4 u_BlurParams;

// XeGTAO_CalculateEdges — slope-aware depth edge detection
// Returns edge weights per direction (L,R,T,B) in [0,1]:
//   1.0 = smooth surface (full blur across)
//   0.0 = hard depth discontinuity (no blur across)
//
// Key insight: a surface SLOPE produces uniform depth differences in
// opposite directions. By subtracting the estimated slope, we distinguish
// actual edges (one-sided depth jumps) from slopes (two-sided gradients).
hvec4 CalculateEdges(hfloat centerZ, hfloat leftZ, hfloat rightZ, hfloat topZ, hfloat bottomZ)
{
    hvec4 edgesLRTB = hvec4_init(leftZ, rightZ, topZ, bottomZ) - centerZ;

    // Estimate surface slope from opposite-neighbor differences
    hfloat slopeLR = (edgesLRTB.y - edgesLRTB.x) * 0.5;
    hfloat slopeTB = (edgesLRTB.w - edgesLRTB.z) * 0.5;

    // Subtract expected slope contribution
    hvec4 slopeAdj = edgesLRTB + hvec4_init(slopeLR, -slopeLR, slopeTB, -slopeTB);

    // Take the smaller of raw vs slope-adjusted: slopes → ~0, edges → large
    hvec4 absEdge = min(abs(edgesLRTB), abs(slopeAdj));

    // Convert to 0-1 weight (XeGTAO: threshold relative to depth)
    return saturate(hvec4_init(1.3, 1.3, 1.3, 1.3) - absEdge / max(centerZ * 0.040, 0.0001));
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 texel = cGBufferInvSize.xy;

    // ================================================================
    // 1. Edge computation from depth (5 depth reads)
    // ================================================================
    hfloat depthC = LinearizeDepth(texture2D(u_Depth1, uv).r, cNearClipPS, cFarClipPS);
    hfloat depthL = LinearizeDepth(texture2D(u_Depth1, uv + hvec2_init(-texel.x, 0.0)).r, cNearClipPS, cFarClipPS);
    hfloat depthR = LinearizeDepth(texture2D(u_Depth1, uv + hvec2_init( texel.x, 0.0)).r, cNearClipPS, cFarClipPS);
    hfloat depthT = LinearizeDepth(texture2D(u_Depth1, uv + hvec2_init(0.0, -texel.y)).r, cNearClipPS, cFarClipPS);
    hfloat depthB = LinearizeDepth(texture2D(u_Depth1, uv + hvec2_init(0.0,  texel.y)).r, cNearClipPS, cFarClipPS);

    hvec4 edgesLRTB = CalculateEdges(depthC, depthL, depthR, depthT, depthB);

    // ================================================================
    // 2. Leak prevention heuristic (XeGTAO)
    // ================================================================
    // When a pixel is mostly surrounded by edges (thin feature), add a
    // small blur amount back to prevent over-darkening.
    hfloat edgeSum = dot(edgesLRTB, hvec4_init(1.0, 1.0, 1.0, 1.0));
    hfloat edginess = saturate((4.0 - 2.5 - edgeSum) / (4.0 - 2.5)) * 0.5;
    edgesLRTB = saturate(edgesLRTB + edginess);

    // ================================================================
    // 3. Diagonal weights via L-shaped paths (XeGTAO)
    // ================================================================
    // XeGTAO uses bilateral product (center edge × neighbor edge) for
    // cardinal weights, then combines two L-shaped paths for diagonals.
    // We approximate: center edges only, diagonal = product of two cardinals.
    hfloat diagWeight = 0.85 * 0.5;
    hfloat wTL = diagWeight * edgesLRTB.x * edgesLRTB.z;  // left × top
    hfloat wTR = diagWeight * edgesLRTB.y * edgesLRTB.z;  // right × top
    hfloat wBL = diagWeight * edgesLRTB.x * edgesLRTB.w;  // left × bottom
    hfloat wBR = diagWeight * edgesLRTB.y * edgesLRTB.w;  // right × bottom

    // ================================================================
    // 4. Read AO values (9 reads)
    // ================================================================
    hfloat aoC  = texture2D(u_AOBuffer0, uv).r;
    hfloat aoL  = texture2D(u_AOBuffer0, uv + hvec2_init(-texel.x,  0.0)).r;
    hfloat aoR  = texture2D(u_AOBuffer0, uv + hvec2_init( texel.x,  0.0)).r;
    hfloat aoT  = texture2D(u_AOBuffer0, uv + hvec2_init( 0.0, -texel.y)).r;
    hfloat aoB  = texture2D(u_AOBuffer0, uv + hvec2_init( 0.0,  texel.y)).r;
    hfloat aoTL = texture2D(u_AOBuffer0, uv + hvec2_init(-texel.x, -texel.y)).r;
    hfloat aoTR = texture2D(u_AOBuffer0, uv + hvec2_init( texel.x, -texel.y)).r;
    hfloat aoBL = texture2D(u_AOBuffer0, uv + hvec2_init(-texel.x,  texel.y)).r;
    hfloat aoBR = texture2D(u_AOBuffer0, uv + hvec2_init( texel.x,  texel.y)).r;

    // ================================================================
    // 5. Edge-weighted average (XeGTAO denoise kernel)
    // ================================================================
    hfloat blurBeta = u_BlurParams.x;

    hfloat sumWeight = blurBeta;
    hfloat sum = aoC * blurBeta;

    // Cardinal neighbors
    sum += aoL * edgesLRTB.x;   sumWeight += edgesLRTB.x;
    sum += aoR * edgesLRTB.y;   sumWeight += edgesLRTB.y;
    sum += aoT * edgesLRTB.z;   sumWeight += edgesLRTB.z;
    sum += aoB * edgesLRTB.w;   sumWeight += edgesLRTB.w;

    // Diagonal neighbors
    sum += aoTL * wTL;   sumWeight += wTL;
    sum += aoTR * wTR;   sumWeight += wTR;
    sum += aoBL * wBL;   sumWeight += wBL;
    sum += aoBR * wBR;   sumWeight += wBR;

    hfloat finalAO = sum / max(sumWeight, 0.0001);

    gl_FragColor = hvec4_init(finalAO, finalAO, finalAO, 1.0);
}

#endif
