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

uniform hvec4 u_HistogramRowsInvSize;
#define cHistogramRowsInvSize vec2(u_HistogramRowsInvSize.xy)

#define HISTOGRAM_ROWS 128

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
    // Output is 16x1. Each fragment sums one column across 128 rows.
    float col = floor(gl_FragCoord.x);
    float colU = (col + 0.5) * cHistogramRowsInvSize.x;

    vec4 sum = vec4(0.0, 0.0, 0.0, 0.0);
    LOOP for (int row = 0; row < HISTOGRAM_ROWS; row++)
    {
        float rowV = (float(row) + 0.5) * cHistogramRowsInvSize.y;
        sum += texture2D(sDiffMap, vec2(colU, rowV));
    }

    gl_FragColor = sum;
}
