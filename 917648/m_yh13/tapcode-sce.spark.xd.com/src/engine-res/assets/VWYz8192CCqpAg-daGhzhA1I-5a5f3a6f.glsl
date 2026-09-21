#include "MaterialBake/VaryingMaterialBake.def.sc"
$input v_texcoord0

#include "Common/common.sh"

// UV-space material-bake PS: bake the PBR inputs that actually feed rendering into
// 3 MRTs in UV space. The sampling logic mirrors the material-value path of
// PBRLitSolid.glsl (same DIFFMAP/METALLIC/EMISSIVEMAP define names) but performs no
// lighting -- the outputs are the material parameters themselves, consumed by
// offline tools to sample material properties.
//
// This is the heuristic fallback path (and the coverage-mask pass) of UVSpaceBaker;
// the primary path renders with the material's own shader via MATERIALBAKE.
// Alpha testing belongs to that path; this fallback also supplies unmasked UV coverage.
//
// MRT layout (aligned with the EncodeGBufferBake semantics in screen_pos.sh, normal
// slot omitted):
//   RT0.rgb = baseColor (MatDiffColor already multiplied)  RT0.a = coverage (1 = valid
//             UV area, used by dilation)
//   RT1.r   = roughness  RT1.g = metallic  RT1.b = occlusion  RT1.a = coverage
//   RT2.rgb = emissive   RT2.a = coverage

SAMPLER2D(s_tex0, 0);   // diffuse
SAMPLER2D(s_tex1, 1);   // packed roughness/metallic/occlusion (= the material's specular slot)
SAMPLER2D(s_tex2, 2);   // emissive

uniform vec4 u_MaterialBakeDiffColor;      // cMatDiffColor
uniform vec4 u_MaterialBakeEmissiveColor;  // cMatEmissiveColor.rgb
uniform vec4 u_MaterialBakeFactors;        // x=roughness(factor), y=metallic(factor), z/w reserved

void main()
{
    vec2 uv = v_texcoord0;

#ifdef DIFFMAP
    vec4 diffInput = texture2D(s_tex0, uv);
    vec4 baseColor = u_MaterialBakeDiffColor * diffInput;
#else
    vec4 baseColor = u_MaterialBakeDiffColor;
#endif

#ifdef METALLIC
    vec4 roughMetalSrc = texture2D(s_tex1, uv);
    float roughness = roughMetalSrc.r * u_MaterialBakeFactors.x;
    float metallic  = roughMetalSrc.g * u_MaterialBakeFactors.y;
    float occlusion = roughMetalSrc.b;
#else
    float roughness = u_MaterialBakeFactors.x;
    float metallic  = u_MaterialBakeFactors.y;
    float occlusion = 1.0;
#endif

#ifdef EMISSIVEMAP
    vec3 emissive = u_MaterialBakeEmissiveColor.rgb * texture2D(s_tex2, uv).rgb;
#else
    vec3 emissive = u_MaterialBakeEmissiveColor.rgb;
#endif

    gl_FragData[0] = vec4(baseColor.rgb, 1.0);
    gl_FragData[1] = vec4(roughness, metallic, occlusion, 1.0);
    gl_FragData[2] = vec4(emissive, 1.0);
}
