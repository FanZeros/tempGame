/*
 * Edge-Preserving Blur for SSAO/GTAO
 *
 * Uses bilateral filtering to blur AO while preserving depth discontinuities.
 * This prevents halos around object edges that would occur with simple Gaussian blur.
 *
 * Separable implementation (run twice: horizontal then vertical)
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

uniform hvec4 u_BlurParams;   // x=blurRadius, y=depthThreshold, z=isHorizontal, w=unused

void PS()
{
    hvec2 uv = vTexCoord;
    hvec2 texelSize = cGBufferInvSize.xy;

    // Gaussian weights for 5-tap blur
    hfloat weights[5];
    weights[0] = 0.2270270270;
    weights[1] = 0.1945945946;
    weights[2] = 0.1216216216;
    weights[3] = 0.0540540541;
    weights[4] = 0.0162162162;

    // Determine blur direction (separable filter)
    hvec2 blurDir;
    if (u_BlurParams.z > 0.5)
        blurDir = hvec2_init(1.0, 0.0);  // Horizontal pass
    else
        blurDir = hvec2_init(0.0, 1.0);  // Vertical pass

    hfloat blurRadius = u_BlurParams.x;
    hfloat depthThreshold = u_BlurParams.y;

    hfloat centerDepth = texture2D(u_Depth1, uv).r;
    hfloat centerAO = texture2D(u_AOBuffer0, uv).r;

    hfloat totalAO = centerAO * weights[0];
    hfloat totalWeight = weights[0];

    for (int i = 1; i < 5; i++)
    {
        hfloat offset = hfloat_init(i) * blurRadius;

        // Positive direction
        {
            hvec2 sampleUV = uv + blurDir * offset * texelSize;
            if (all(greaterThanEqual(sampleUV, vec2_splat(0.0))) &&
                all(lessThanEqual(sampleUV, vec2_splat(1.0))))
            {
                hfloat sampleDepth = texture2D(u_Depth1, sampleUV).r;
                hfloat sampleAO = texture2D(u_AOBuffer0, sampleUV).r;

                hfloat depthDiff = abs(centerDepth - sampleDepth);
                hfloat depthWeight = exp(-depthDiff * depthDiff / (depthThreshold * depthThreshold));

                hfloat weight = weights[i] * depthWeight;
                totalAO += sampleAO * weight;
                totalWeight += weight;
            }
        }

        // Negative direction
        {
            hvec2 sampleUV = uv - blurDir * offset * texelSize;
            if (all(greaterThanEqual(sampleUV, vec2_splat(0.0))) &&
                all(lessThanEqual(sampleUV, vec2_splat(1.0))))
            {
                hfloat sampleDepth = texture2D(u_Depth1, sampleUV).r;
                hfloat sampleAO = texture2D(u_AOBuffer0, sampleUV).r;

                hfloat depthDiff = abs(centerDepth - sampleDepth);
                hfloat depthWeight = exp(-depthDiff * depthDiff / (depthThreshold * depthThreshold));

                hfloat weight = weights[i] * depthWeight;
                totalAO += sampleAO * weight;
                totalWeight += weight;
            }
        }
    }

    hfloat finalAO = totalAO / max(totalWeight, 0.0001);

    gl_FragColor = hvec4_init(finalAO, finalAO, finalAO, 1.0);
}

#endif
