#include "varying_cluster.def.sc"
#include <Common/bgfx_shader.sh>
#include <Common/bgfx_compute.sh>
#include "uniforms.sh"

BUFFER_WR_TYPED(outVertices, float, 0);
BUFFER_RO_TYPED(inVertices, float, 1);

#if defined(CS_POSITION) || defined(CS_NORMAL) || defined(CS_TANGENT)
BUFFER_RO(inMatrices, vec4, 2);
#endif

#if BGFX_SHADER_LANGUAGE_METAL || BGFX_SHADER_LANGUAGE_HLSL
    #define TR(_mat) transpose(_mat)
#else
    #define TR(_mat) _mat
#endif

NUM_THREADS(SKINNED_THREAD,1,1)
void main()
{
    if (gl_GlobalInvocationID.x > cVertexCount * cNumBlocks)
        return;

    uint blockIndex = gl_GlobalInvocationID.x / cVertexCount;
    uint vertexOffset = blockIndex * cVertexCount * cVertexSize;
    uint martixOffset = blockIndex * cNumMatrices + cMatricesOffset;
    uint vertexStart = gl_GlobalInvocationID.x * cVertexSize - vertexOffset;
    uint vertexEnd = (gl_GlobalInvocationID.x + 1u) * cVertexSize - vertexOffset;

    for (uint i = vertexStart; i < vertexEnd; ++i)
    {
        outVertices[i + vertexOffset] = inVertices[i];
    }

#if defined(CS_POSITION) || defined(CS_NORMAL) || defined(CS_TANGENT)
    // 矩阵索引是一个ubyte4的结构，要把float按照二进制内存布局转到int
    uint indices = uint(floatBitsToInt(inVertices[vertexStart + cIndicesOffset]));

    // 解码int，每8个bits是一个索引值
    // inMatrices是多个数量相同的骨骼矩阵串起来的，所以需要加上偏移量martixOffset
    uint idx1 = uint((indices >>  0u) & 255u) + martixOffset;
    uint idx2 = uint((indices >>  8u) & 255u) + martixOffset;
    uint idx3 = uint((indices >> 16u) & 255u) + martixOffset;
    uint idx4 = uint((indices >> 24u) & 255u) + martixOffset;

    mat4 mat_1 = TR(mat4(inMatrices[idx1 * 3u],
                    inMatrices[idx1 * 3u + 1u],
                    inMatrices[idx1 * 3u + 2u],
                    vec4(0.0, 0.0, 0.0, 1.0)));
    mat4 mat_2 = TR(mat4(inMatrices[idx2 * 3u],
                    inMatrices[idx2 * 3u + 1u],
                    inMatrices[idx2 * 3u + 2u],
                    vec4(0.0, 0.0, 0.0, 1.0)));
    mat4 mat_3 = TR(mat4(inMatrices[idx3 * 3u],
                    inMatrices[idx3 * 3u + 1u],
                    inMatrices[idx3 * 3u + 2u],
                    vec4(0.0, 0.0, 0.0, 1.0)));
    mat4 mat_4 = TR(mat4(inMatrices[idx4 * 3u],
                    inMatrices[idx4 * 3u + 1u],
                    inMatrices[idx4 * 3u + 2u],
                    vec4(0.0, 0.0, 0.0, 1.0)));

    vec4 weight = vec4(inVertices[vertexStart + cWeightOffset],
                    inVertices[vertexStart + cWeightOffset + 1u],
                    inVertices[vertexStart + cWeightOffset + 2u],
                    inVertices[vertexStart + cWeightOffset + 3u]);

    mat4 transform = mul(weight.x, mat_1) + mul(weight.y, mat_2) + mul(weight.z, mat_3) + mul(weight.w, mat_4);
#endif

#ifdef CS_POSITION
    vec3 position = vec3(inVertices[vertexStart + cPositionOffset],
                        inVertices[vertexStart + cPositionOffset + 1u],
                        inVertices[vertexStart + cPositionOffset + 2u]);
    position = mul(vec4(position, 1.0), transform).xyz;
    outVertices[vertexOffset + vertexStart + cPositionOffset] = position.x;
    outVertices[vertexOffset + vertexStart + cPositionOffset + 1u] = position.y;
    outVertices[vertexOffset + vertexStart + cPositionOffset + 2u] = position.z;
#endif

#ifdef CS_NORMAL
    vec3 normal = vec3(inVertices[vertexStart + cNormalOffset],
                        inVertices[vertexStart + cNormalOffset + 1u],
                        inVertices[vertexStart + cNormalOffset + 2u]);
    normal = mul(vec4(normal, 0.0), transform).xyz;
    outVertices[vertexOffset + vertexStart + cNormalOffset] = normal.x;
    outVertices[vertexOffset + vertexStart + cNormalOffset + 1u] = normal.y;
    outVertices[vertexOffset + vertexStart + cNormalOffset + 2u] = normal.z;
#endif

#ifdef CS_TANGENT
    vec3 tangent = vec3(inVertices[vertexStart + cTangentOffset],
                        inVertices[vertexStart + cTangentOffset + 1u],
                        inVertices[vertexStart + cTangentOffset + 2u]);
    tangent = mul(vec4(tangent, 0.0), transform).xyz;
    outVertices[vertexOffset + vertexStart + cTangentOffset] = tangent.x;
    outVertices[vertexOffset + vertexStart + cTangentOffset + 1u] = tangent.y;
    outVertices[vertexOffset + vertexStart + cTangentOffset + 2u] = tangent.z;
#endif
}
