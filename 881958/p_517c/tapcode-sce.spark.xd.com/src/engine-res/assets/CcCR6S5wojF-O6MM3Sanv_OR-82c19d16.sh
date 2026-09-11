/*
 * Screen Space Common Functions
 * Shared utilities for all screen-space effects (SSR, SSAO, etc.)
 *
 * All computations use full precision ('hfloat'/'hvec'/'hmat4') to avoid
 * fp16 quantization artifacts. Engine convention: float/vec* = half, h* = full.
 */

#ifndef SCREEN_SPACE_COMMON_SH
#define SCREEN_SPACE_COMMON_SH

// Reconstruct view-space position from UV and depth
hvec3 ReconstructViewPos(hvec2 uv, hfloat depth)
{
    // GL clip space Z is [-1,1], depth buffer stores [0,1] -> remap
    // DX clip space Z is [0,1], depth buffer stores [0,1] -> no remap
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

    hvec4 viewPos = mul(clipPos, cInvProj);
    return viewPos.xyz / viewPos.w;
}

// Decode normal from GBuffer
hvec3 DecodeGBufferNormal(hvec3 encoded)
{
    return normalize(hvec3_init(encoded.x, encoded.y, encoded.z) * 2.0 - 1.0);
}

// Interleaved Gradient Noise (Jimenez, SIGGRAPH 2014)
// Produces well-distributed screen-space noise with minimal visible pattern.
// Superior to white noise for stochastic effects because the low-frequency
// structure is easily removed by temporal filtering.
hfloat InterleavedGradientNoise(hvec2 screenPos)
{
    hvec3 magic = hvec3_init(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(screenPos, magic.xy)));
}

#endif // SCREEN_SPACE_COMMON_SH
