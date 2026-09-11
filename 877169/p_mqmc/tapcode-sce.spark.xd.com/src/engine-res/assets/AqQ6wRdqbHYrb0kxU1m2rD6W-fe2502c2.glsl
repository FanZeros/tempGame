#include "EnvBake/varying_envbake.def.sc"
$input v_texcoord0

#include "Common/common.sh"

SAMPLERCUBE(s_tex0, 0);
#define s_source s_tex0

uniform hvec4 u_EnvBakeParams;  // x=roughness, y=faceSize, z=numSamples, w=srcFaceSize
uniform hvec4 u_EnvBakeFace;    // x=faceIndex

// ============================================================================
// Hammersley low-discrepancy sequence
// Reference: http://holger.dammertz.org/stuff/notes_HammersleyOnHemisphere.html
// ============================================================================

hfloat radicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    hfloat fbits = float(bits);
    return fbits * 2.3283064365386963e-10;
}

hvec2 hammersley(int i, int N)
{
    hfloat fi = float(i);
    hfloat fN = float(N);
    return hvec2_init(fi / fN, radicalInverse_VdC(uint(i)));
}

// ============================================================================
// GGX importance sampling (from EnvironmentBaker.cpp)
// ============================================================================

hvec3 importanceSampleGGX(hvec2 Xi, hfloat roughness, hvec3 N)
{
    hfloat a = roughness * roughness;

    hfloat phi = 2.0 * 3.14159265 * Xi.x;
    hfloat cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    hfloat sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // 切线空间半向量
    hvec3 H = hvec3_init(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    // 构建切线空间基
    hvec3 up = abs(N.z) < 0.999 ? hvec3_init(0.0, 0.0, 1.0) : hvec3_init(1.0, 0.0, 0.0);
    hvec3 tangentX = normalize(cross(up, N));
    hvec3 tangentY = cross(N, tangentX);

    // 切线空间→世界空间
    return normalize(tangentX * H.x + tangentY * H.y + N * H.z);
}

// ============================================================================
// Cubemap face direction (from EnvironmentBaker.cpp TexelDirection)
// ============================================================================

hvec3 texelDirection(int face, hvec2 uv)
{
    // uv 已是 [0,1]（GPU 光栅化天然 texel-centered），转换为 [-1,1]
    hfloat u = 2.0 * uv.x - 1.0;
    hfloat v = 2.0 * uv.y - 1.0;

    hvec3 dir;
    if (face == 0)      dir = hvec3_init( 1.0,   -v,   -u);  // +X
    else if (face == 1) dir = hvec3_init(-1.0,   -v,    u);  // -X
    else if (face == 2) dir = hvec3_init(   u,  1.0,    v);  // +Y
    else if (face == 3) dir = hvec3_init(   u, -1.0,   -v);  // -Y
    else if (face == 4) dir = hvec3_init(   u,   -v,  1.0);  // +Z
    else                dir = hvec3_init(  -u,   -v, -1.0);  // -Z

    return normalize(dir);
}

// ============================================================================
// Main: Specular GGX prefilter (from EnvironmentBaker.cpp PrefilterMip)
// ============================================================================

void main()
{
    hvec2 uv = v_texcoord0;
    int face = int(u_EnvBakeFace.x);
    hfloat roughness = u_EnvBakeParams.x;
    hfloat faceSize = u_EnvBakeParams.y;
    int numSamples = int(u_EnvBakeParams.z);
    hfloat srcFaceSize = u_EnvBakeParams.w;

    // texel → 3D direction
    hvec3 N = texelDirection(face, uv);

    // mip0 (roughness ≈ 0): 直接采样，无需卷积
    if (roughness < 0.001)
    {
        gl_FragColor = textureCubeLod(s_source, N, 0.0);
        return;
    }

    // GGX importance sampling loop
    hvec3 totalColor = hvec3_init(0.0, 0.0, 0.0);
    hfloat totalWeight = 0.0;
    hfloat solidAngleTexel = 4.0 * 3.14159265 / (6.0 * srcFaceSize * srcFaceSize);

    for (int i = 0; i < numSamples; ++i)
    {
        hvec2 Xi = hammersley(i, numSamples);
        hvec3 H = importanceSampleGGX(Xi, roughness, N);
        hfloat NdotH = max(dot(N, H), 0.0);
        hvec3 L = normalize(2.0 * NdotH * H - N);
        hfloat NdotL = dot(N, L);

        if (NdotL > 0.0)
        {
            // Beckmann D (与 CPU 路径 EnvironmentBaker.cpp 对齐)
            hfloat r2 = roughness * roughness;
            hfloat NdotH2 = NdotH * NdotH;
            hfloat D = exp(((NdotH2 - 1.0) / (r2 + 0.0001)) * NdotH2)
                      / (3.14159265 * r2 * NdotH2 * NdotH2 + 0.0001);
            hfloat pdf = D * NdotH / (4.0 * NdotH + 0.0001);
            hfloat fNumSamples = float(numSamples);
            hfloat solidAngleSample = 1.0 / (fNumSamples * pdf + 0.0001);
            hfloat lod = max(0.5 * log2(solidAngleSample / solidAngleTexel), 0.0);

            hvec3 sampleColor = textureCubeLod(s_source, L, lod).rgb;
            totalColor += sampleColor * NdotL;
            totalWeight += NdotL;
        }
    }

    if (totalWeight > 0.0)
        totalColor /= totalWeight;

    gl_FragColor = hvec4_init(totalColor.x, totalColor.y, totalColor.z, 1.0);
}
