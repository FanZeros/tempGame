#include "varying_cs.def.sc"
#include <Common/bgfx_compute.sh>

SAMPLER2D(s_InTexture0, 0);
IMAGE2D_RW_HLSLCC(s_OutTexture1, rgba8, highp, 1);

uniform vec4 u_TexelSize;

NUM_THREADS(8, 8, 1)
void main()
{
    vec2 UV = u_TexelSize.xy * (gl_GlobalInvocationID.xy + 0.5f);

    vec4 outColor = texture2DLod(s_InTexture0, UV, 0);

#if GENMIPS_SWIZZLE
    imageStore(s_OutTexture1, gl_GlobalInvocationID.xy, outColor.zyxw);
#else
    imageStore(s_OutTexture1, gl_GlobalInvocationID.xy, outColor);
#endif
}
