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
#include "post_process.sh"

#ifdef COMPILEPS

uniform hvec4 u_HistogramParams;    // x = scale, y = bias, z = logMin, w = logMax
uniform hvec4 u_UEExposureLuminanceWeights;
uniform hvec4 u_HDR128InvSize;

#define cHistogramScale     u_HistogramParams.x
#define cHistogramBias      u_HistogramParams.y
#define cHDR128InvSize      vec2(u_HDR128InvSize.xy)
#define cUELuminanceWeights vec3(u_UEExposureLuminanceWeights.xyz)

#define HISTOGRAM_SIZE 64
#define HDR128_WIDTH   128

float ComputeHistogramPosition(float luminance)
{
    float logLum = log2(max(luminance, 1e-10));
    return clamp(logLum * cHistogramScale + cHistogramBias, 0.0, float(HISTOGRAM_SIZE - 1));
}

#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

void PS()
{
    float fragX = floor(gl_FragCoord.x);
    float row = floor(gl_FragCoord.y);

    float binStart = fragX * 4.0;
    vec4 binTargets = vec4(binStart, binStart + 1.0, binStart + 2.0, binStart + 3.0);

    vec4 counts = vec4(0.0, 0.0, 0.0, 0.0);
    float rowV = (row + 0.5) * cHDR128InvSize.y;

    LOOP for (int i = 0; i < HDR128_WIDTH; i++)
    {
        float colU = (float(i) + 0.5) * cHDR128InvSize.x;
        vec3 color = texture2D(sDiffMap, vec2(colU, rowV)).rgb;
        float lum = dot(color, cUELuminanceWeights);
        float fbin = ComputeHistogramPosition(lum);

        float binLow = floor(fbin);
        float fracW = fract(fbin);

        vec4 lowMatch = step(abs(vec4_splat(binLow) - binTargets), vec4_splat(0.5));
        vec4 highMatch = step(abs(vec4_splat(binLow + 1.0) - binTargets), vec4_splat(0.5));

        counts += lowMatch * (1.0 - fracW) + highMatch * fracW;
    }

    gl_FragColor = counts;
}
