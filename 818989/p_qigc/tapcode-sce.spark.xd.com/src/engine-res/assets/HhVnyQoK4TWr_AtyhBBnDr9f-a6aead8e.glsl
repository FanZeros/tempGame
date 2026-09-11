/*
 * SSR Spatial Denoise Shader
 * Edge-aware bilateral blur to smooth per-pixel noise from jittered SSR trace.
 * Uses depth similarity to preserve edges at depth discontinuities.
 *
 * 5x5 Gaussian bilateral filter:
 *   - Gaussian spatial weights (sigma ~1.5)
 *   - Depth-based edge preservation
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

// SSR input (register 0)
SAMPLER2D(u_SSRInput0, 0);
// Depth buffer (register 1)
SAMPLER2D(u_Depth1, 1);

void PS()
{
    vec2 uv = vTexCoord;
    vec2 texelSize = cGBufferInvSize;

    float centerDepth = LinearizeDepth(texture2D(u_Depth1, uv).r, cNearClipPS, cFarClipPS);
    vec4 centerColor = texture2D(u_SSRInput0, uv);

    // Skip sky/background
    if (centerDepth >= cFarClipPS * 0.99)
    {
        gl_FragColor = centerColor;
        return;
    }

    vec4 totalColor = centerColor;
    float totalWeight = 1.0;

    // Depth-relative threshold: farther objects tolerate larger depth differences
    float depthThreshold = centerDepth * 0.1;

    // 5x5 edge-aware bilateral blur with Gaussian spatial weights
    // Gaussian sigma ~1.5: exp(-d^2 / (2 * 1.5^2)) = exp(-d^2 / 4.5)
    for (int y = -2; y <= 2; y++)
    {
        for (int x = -2; x <= 2; x++)
        {
            if (x == 0 && y == 0) continue;

            vec2 sampleUV = uv + vec2(float(x), float(y)) * texelSize;
            vec4 sampleColor = texture2D(u_SSRInput0, sampleUV);
            float sampleDepth = LinearizeDepth(texture2D(u_Depth1, sampleUV).r, cNearClipPS, cFarClipPS);

            // Depth similarity: reject samples across depth edges
            float depthDiff = abs(centerDepth - sampleDepth);
            float depthWeight = 1.0 - saturate(depthDiff / depthThreshold);

            // Gaussian spatial weight
            float dist2 = float(x * x + y * y);
            float spatialWeight = exp(-dist2 / 4.5);

            float weight = depthWeight * spatialWeight;
            totalColor += sampleColor * weight;
            totalWeight += weight;
        }
    }

    gl_FragColor = totalColor / totalWeight;
}

#endif
