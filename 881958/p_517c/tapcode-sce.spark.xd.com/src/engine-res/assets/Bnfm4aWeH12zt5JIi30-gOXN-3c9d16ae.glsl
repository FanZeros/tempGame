/*
 * Motion Vector Generation Shader
 * Generates per-pixel motion vectors via depth reprojection.
 *
 * Uses the current frame's inverse ViewProj (custom u_InvViewProj) to
 * reconstruct world position, then projects with previous frame's ViewProj
 * (set by C++ engine) to find the previous screen position.
 *
 * Motion Vector = CurrentUV - PreviousUV
 *
 * Output: RG16F texture
 *   R = horizontal motion (positive = moved right)
 *   G = vertical motion (positive = moved down)
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

// Depth buffer (register 0)
SAMPLER2D(u_Depth0, 0);

// Custom ViewProj matrices from C++ (correct Urho3D column-vector convention)
// bgfx built-in u_viewProj/u_invViewProj use bx row-vector convention — unusable
uniform hmat4 u_InvViewProj;
uniform hmat4 u_PrevViewProj;

void PS()
{
    hvec2 uv = vTexCoord;
    hfloat depth = texture2D(u_Depth0, uv).r;

    // Skip sky/background (depth at far plane)
    if (depth > 0.99999)
    {
        gl_FragColor = hvec4_init(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Reconstruct current frame clip-space position
    // GL clip space Z is [-1,1], depth buffer stores [0,1] -> remap
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    hfloat clipZ = depth * 2.0 - 1.0;
#else
    hfloat clipZ = depth;
#endif
    hvec4 clipPos = hvec4_init(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, clipZ, 1.0);

    // D3D11: UV.y=0 is top, clip.y=+1 is top -> need Y flip
    // GL: UV.y=0 is bottom, clip.y=-1 is bottom -> no flip needed
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    clipPos.y = -clipPos.y;
#endif

    // Reconstruct world position using custom InvViewProj (Urho3D convention)
    hvec4 worldPos = mul(clipPos, u_InvViewProj);
    worldPos /= worldPos.w;

    // Project world position to previous frame screen space
    hvec4 prevClipPos = mul(worldPos, u_PrevViewProj);
    hvec2 prevUV = prevClipPos.xy / prevClipPos.w * 0.5 + 0.5;

#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    prevUV.y = 1.0 - prevUV.y;
#endif

    // Motion Vector = current position - previous position
    hvec2 motionVector = uv - prevUV;

    // Clamp to reasonable range
    motionVector = clamp(motionVector, vec2_splat(-0.5), vec2_splat(0.5));

    gl_FragColor = hvec4_init(motionVector.x, motionVector.y, 0.0, 1.0);
}

#endif
