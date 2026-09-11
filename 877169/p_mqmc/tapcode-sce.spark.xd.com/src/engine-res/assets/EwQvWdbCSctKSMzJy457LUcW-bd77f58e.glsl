// NanoVG main fill shader, ported 1:1 from the embedded vs_nanovg_fill.sc + fs_nanovg_fill.sc
// into the engine's BLGL pipeline so it compiles per-platform into the shader cache (like SpineUI).

#include "varying_nanovg.def.sc"
#ifdef COMPILEVS
    $input a_position a_texcoord0
    $output v_position v_texcoord0
#endif
#ifdef COMPILEPS
    $input v_position v_texcoord0
#endif

#include "Common/common.sh"

#define EDGE_AA 1
#define NEED_HALF_TEXEL (BGFX_SHADER_LANGUAGE_HLSL < 4)

uniform hvec4 u_viewSize;
uniform hmat3 u_scissorMat;
uniform hmat3 u_paintMat;
uniform hvec4 u_innerCol;
uniform hvec4 u_outerCol;
uniform hvec4 u_scissorExtScale;
uniform hvec4 u_extentRadius;
uniform hvec4 u_params;
#if NEED_HALF_TEXEL
uniform hvec4 u_halfTexel;
#endif // NEED_HALF_TEXEL

#define u_scissorExt   (u_scissorExtScale.xy)
#define u_scissorScale (u_scissorExtScale.zw)
#define u_extent       (u_extentRadius.xy)
#define u_radius       (u_extentRadius.z)
#define u_feather      (u_params.x)
#define u_strokeMult   (u_params.y)
#define u_texType      (u_params.z)
#define u_type         (u_params.w)

#ifdef COMPILEPS
SAMPLER2D(s_tex, 0);

hfloat sdroundrect(hvec2 pt, hvec2 ext, hfloat rad)
{
    hvec2 ext2 = ext - hvec2_init(rad, rad);
    hvec2 d = abs(pt) - ext2;
    return min(max(d.x, d.y), 0.0) + length(max(d, hvec2_init(0.0, 0.0))) - rad;
}

// erf approximation (Abramowitz & Stegun 7.1.27): polynomial, no exp, no branches.
// Max abs error is about 3e-4. Gives a true Gaussian edge falloff for type 4.
hfloat nvgErf(hfloat x)
{
    hfloat s = sign(x);
    hfloat a = abs(x);
    hfloat v = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    v *= v;
    return s - s / (v * v);
}

hfloat scissorMask(hvec2 p)
{
    hvec2 sc = abs(mul(u_scissorMat, hvec3_init(p, 1.0)).xy) - u_scissorExt;
    sc = hvec2_init(0.5, 0.5) - sc * u_scissorScale;
    return clamp(sc.x, 0.0, 1.0) * clamp(sc.y, 0.0, 1.0);
}

hfloat strokeMask(hvec2 _texcoord)
{
#if EDGE_AA
    return min(1.0, (1.0 - abs(_texcoord.x * 2.0 - 1.0)) * u_strokeMult) * min(1.0, _texcoord.y);
#else
    return 1.0;
#endif // EDGE_AA
}
#endif // COMPILEPS

void VS()
{
#if !NEED_HALF_TEXEL
    const hvec4 u_halfTexel = hvec4_init(0.0, 0.0, 0.0, 0.0);
#endif // !NEED_HALF_TEXEL

    v_position  = a_position;
    v_texcoord0 = a_texcoord0 + u_halfTexel.xy;
    gl_Position = hvec4_init(2.0 * v_position.x / u_viewSize.x - 1.0, 1.0 - 2.0 * v_position.y / u_viewSize.y, 0.0, 1.0);
}

void PS()
{
    hvec4 result = hvec4_init(0.0, 0.0, 0.0, 0.0);
    hfloat scissor = scissorMask(v_position);
    hfloat strokeAlpha = strokeMask(v_texcoord0);

    BRANCH if (u_type == 0.0) // Gradient
    {
        hvec2 pt = mul(u_paintMat, hvec3_init(v_position, 1.0)).xy;
        hfloat d = clamp((sdroundrect(pt, u_extent, u_radius) + u_feather * 0.5) / u_feather, 0.0, 1.0);
        hvec4 color = mix(u_innerCol, u_outerCol, d);
        color *= strokeAlpha * scissor;
        result = color;
    }
    else
    {
        BRANCH if (u_type == 1.0) // Image
        {
            hvec2 pt = mul(u_paintMat, hvec3_init(v_position, 1.0)).xy / u_extent;
            hvec4 color = texture2D(s_tex, pt);
            if (u_texType == 1.0) color = hvec4_init(color.xyz * color.w, color.w);
            if (u_texType == 2.0) color = color.xxxx;
            color *= u_innerCol;
            color *= strokeAlpha * scissor;
            result = color;
        }
        else
        {
            BRANCH if (u_type == 2.0) // Stencil fill
            {
                result = hvec4_init(1.0, 1.0, 1.0, 1.0);
            }
            else
            {
                BRANCH if (u_type == 3.0) // Textured tris
                {
                    hvec4 color = texture2D(s_tex, v_texcoord0.xy);
                    if (u_texType == 1.0) color = hvec4_init(color.xyz * color.w, color.w);
                    if (u_texType == 2.0) color = color.xxxx;
                    color *= scissor;
                    result = color * u_innerCol;
                }
                else
                {
                    BRANCH if (u_type == 4.0) // Box gradient with Gaussian falloff
                    {
                        hvec2 pt = mul(u_paintMat, hvec3_init(v_position, 1.0)).xy;
                        hfloat dist = sdroundrect(pt, u_extent, u_radius);
                        hfloat sigma = max(u_feather * 0.5, 0.001);
                        hfloat d = 0.5 * (1.0 + nvgErf(dist / (1.4142135 * sigma)));
                        hvec4 color = mix(u_innerCol, u_outerCol, d);
                        color *= strokeAlpha * scissor;
                        result = color;
                    }
                }
            }
        }
    }

    gl_FragColor = result;
}
