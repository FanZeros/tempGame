/*
 * SSR Bilateral Upscale Shader
 * Upsamples half-resolution SSR result to full resolution using
 * depth + normal aware bilateral filtering.
 *
 * For each full-res pixel, samples the 4 nearest half-res texels
 * and weights by bilinear position, depth similarity, and normal similarity.
 * This preserves sharp edges at depth/normal discontinuities while
 * smoothly interpolating in flat regions.
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
#include "ScreenSpace/ScreenSpaceCommon.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

// Half-res SSR result (register 0)
SAMPLER2D(u_SSRHalf0, 0);
// Full-res depth buffer (register 1)
SAMPLER2D(u_Depth1, 1);
// Full-res GBufferA - normals (register 2)
SAMPLER2D(u_Normal2, 2);

// Depth weight threshold: controls how aggressively depth edges are preserved.
// Smaller = sharper edges but more aliasing; larger = smoother but may bleed.
#define DEPTH_THRESHOLD 0.05
// Normal weight power: higher = sharper normal boundaries
#define NORMAL_POWER 2.0

void PS()
{
    hvec2 uv = vTexCoord;

    // Full-res reference depth and normal at this pixel
    hfloat fullDepth = LinearizeDepth(texture2D(u_Depth1, uv).r, cNearClipPS, cFarClipPS);
    hvec3 fullNormal = DecodeGBufferNormal(texture2D(u_Normal2, uv).rgb);

    // Half-res texel size = 2x full-res texel size
    hvec2 halfTexelSize = cGBufferInvSize * 2.0;

    // Find the 4 nearest half-res texel centers.
    // Convert full-res UV to half-res texel coordinates,
    // then find the 2x2 neighborhood that brackets this position.
    hvec2 halfTexCoord = uv / halfTexelSize - 0.5;
    hvec2 f = fract(halfTexCoord);
    hvec2 baseUV = (floor(halfTexCoord) + 0.5) * halfTexelSize;

    // 4 half-res texel center UVs
    hvec2 uv00 = baseUV;
    hvec2 uv10 = baseUV + hvec2_init(halfTexelSize.x, 0.0);
    hvec2 uv01 = baseUV + hvec2_init(0.0, halfTexelSize.y);
    hvec2 uv11 = baseUV + halfTexelSize;

    // Bilinear spatial weights
    hfloat ws00 = (1.0 - f.x) * (1.0 - f.y);
    hfloat ws10 = f.x * (1.0 - f.y);
    hfloat ws01 = (1.0 - f.x) * f.y;
    hfloat ws11 = f.x * f.y;

    // Sample half-res SSR colors
    hvec4 c00 = texture2D(u_SSRHalf0, uv00);
    hvec4 c10 = texture2D(u_SSRHalf0, uv10);
    hvec4 c01 = texture2D(u_SSRHalf0, uv01);
    hvec4 c11 = texture2D(u_SSRHalf0, uv11);

    // Depth at each half-res texel center (sampled from full-res depth)
    hfloat d00 = LinearizeDepth(texture2D(u_Depth1, uv00).r, cNearClipPS, cFarClipPS);
    hfloat d10 = LinearizeDepth(texture2D(u_Depth1, uv10).r, cNearClipPS, cFarClipPS);
    hfloat d01 = LinearizeDepth(texture2D(u_Depth1, uv01).r, cNearClipPS, cFarClipPS);
    hfloat d11 = LinearizeDepth(texture2D(u_Depth1, uv11).r, cNearClipPS, cFarClipPS);

    // Depth weights: Gaussian falloff based on relative depth difference
    hfloat invThresh2 = 1.0 / (DEPTH_THRESHOLD * DEPTH_THRESHOLD);
    hfloat relDiff00 = (d00 - fullDepth) / max(fullDepth, 0.001);
    hfloat relDiff10 = (d10 - fullDepth) / max(fullDepth, 0.001);
    hfloat relDiff01 = (d01 - fullDepth) / max(fullDepth, 0.001);
    hfloat relDiff11 = (d11 - fullDepth) / max(fullDepth, 0.001);

    hfloat wd00 = exp(-relDiff00 * relDiff00 * invThresh2);
    hfloat wd10 = exp(-relDiff10 * relDiff10 * invThresh2);
    hfloat wd01 = exp(-relDiff01 * relDiff01 * invThresh2);
    hfloat wd11 = exp(-relDiff11 * relDiff11 * invThresh2);

    // Normal weights: dot product similarity
    hvec3 n00 = DecodeGBufferNormal(texture2D(u_Normal2, uv00).rgb);
    hvec3 n10 = DecodeGBufferNormal(texture2D(u_Normal2, uv10).rgb);
    hvec3 n01 = DecodeGBufferNormal(texture2D(u_Normal2, uv01).rgb);
    hvec3 n11 = DecodeGBufferNormal(texture2D(u_Normal2, uv11).rgb);

    hfloat wn00 = pow(max(dot(fullNormal, n00), 0.0), NORMAL_POWER);
    hfloat wn10 = pow(max(dot(fullNormal, n10), 0.0), NORMAL_POWER);
    hfloat wn01 = pow(max(dot(fullNormal, n01), 0.0), NORMAL_POWER);
    hfloat wn11 = pow(max(dot(fullNormal, n11), 0.0), NORMAL_POWER);

    // Combined weights: spatial * depth * normal
    hfloat w00 = ws00 * wd00 * wn00;
    hfloat w10 = ws10 * wd10 * wn10;
    hfloat w01 = ws01 * wd01 * wn01;
    hfloat w11 = ws11 * wd11 * wn11;

    // Normalize and accumulate
    hfloat totalWeight = w00 + w10 + w01 + w11;
    if (totalWeight > 0.0001)
    {
        hfloat invTotal = 1.0 / totalWeight;
        gl_FragColor = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) * invTotal;
    }
    else
    {
        // Fallback: no valid neighbor (e.g., sky pixels)
        gl_FragColor = c00 * ws00 + c10 * ws10 + c01 * ws01 + c11 * ws11;
    }
}

#endif
