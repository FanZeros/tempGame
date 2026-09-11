#ifndef __SURFACE_GODOT_MATRICES_SH__
#define __SURFACE_GODOT_MATRICES_SH__

// UrhoX transforms vectors on the left. Godot exposes matrices for column-vector multiplication,
// so built-in matrices must be transposed before generated Godot-style code consumes them.
hmat4 SurfaceGodotMatrix(hmat4 engineMatrix)
{
    return transpose(engineMatrix);
}

hmat4 SurfaceGodotModelMatrix(hmat4 modelMatrix)
{
    return SurfaceGodotMatrix(modelMatrix);
}

// Matrix constructors selected by the AST. Indexed vectors are rows in HLSL and columns in GLSL;
// rebuilding them in the same order preserves orientation on either path. Arguments are evaluated once.
hmat2 SurfaceGodotMat2FromMat3(hmat3 value)
{
    return hmat2_init(value[0].xy, value[1].xy);
}

hmat2 SurfaceGodotMat2FromMat4(hmat4 value)
{
    return hmat2_init(value[0].xy, value[1].xy);
}

hmat3 SurfaceGodotMat3FromMat2(hmat2 value)
{
    return hmat3_init(hvec3_init(value[0], 0.0), hvec3_init(value[1], 0.0), hvec3_init(0.0, 0.0, 1.0));
}

hmat3 SurfaceGodotMat3FromMat4(hmat4 value)
{
    return hmat3_init(value[0].xyz, value[1].xyz, value[2].xyz);
}

hmat4 SurfaceGodotMat4FromMat2(hmat2 value)
{
    return hmat4_init(hvec4_init(value[0], 0.0, 0.0), hvec4_init(value[1], 0.0, 0.0),
        hvec4_init(0.0, 0.0, 1.0, 0.0), hvec4_init(0.0, 0.0, 0.0, 1.0));
}

hmat4 SurfaceGodotMat4FromMat3(hmat3 value)
{
    return hmat4_init(hvec4_init(value[0], 0.0), hvec4_init(value[1], 0.0), hvec4_init(value[2], 0.0),
        hvec4_init(0.0, 0.0, 0.0, 1.0));
}

// GLSL scalar construction fills only the diagonal, unlike an HLSL scalar-to-matrix cast.
hmat2 SurfaceGodotMat2Diagonal(hfloat value)
{
    return hmat2_init(value, 0.0, 0.0, value);
}

hmat3 SurfaceGodotMat3Diagonal(hfloat value)
{
    return hmat3_init(value, 0.0, 0.0, 0.0, value, 0.0, 0.0, 0.0, value);
}

hmat4 SurfaceGodotMat4Diagonal(hfloat value)
{
    return hmat4_init(value, 0.0, 0.0, 0.0, 0.0, value, 0.0, 0.0,
        0.0, 0.0, value, 0.0, 0.0, 0.0, 0.0, value);
}

// Expose the model matrix's linear part using Godot's column-vector convention. Correcting normals
// for non-uniform scale is intentionally outside this compatibility fix.
hmat3 SurfaceGodotModelNormalMatrix(hmat4 modelMatrix)
{
    hvec3 modelX = mul(hvec4_init(1.0, 0.0, 0.0, 0.0), modelMatrix).xyz;
    hvec3 modelY = mul(hvec4_init(0.0, 1.0, 0.0, 0.0), modelMatrix).xyz;
    hvec3 modelZ = mul(hvec4_init(0.0, 0.0, 1.0, 0.0), modelMatrix).xyz;

    #if BGFX_SHADER_LANGUAGE_METAL || BGFX_SHADER_LANGUAGE_HLSL
        return transpose(hmat3_init(modelX, modelY, modelZ));
    #else
        return hmat3_init(modelX, modelY, modelZ);
    #endif
}

// Matrix compound assignment cannot use a raw *= across shader languages. inout keeps complex
// lvalues single-evaluation while the return value preserves assignment-expression semantics.
hvec2 SurfaceGodotMulAssign(inout hvec2 lhs, hmat2 rhs) { lhs = mul(lhs, rhs); return lhs; }
hvec3 SurfaceGodotMulAssign(inout hvec3 lhs, hmat3 rhs) { lhs = mul(lhs, rhs); return lhs; }
hvec4 SurfaceGodotMulAssign(inout hvec4 lhs, hmat4 rhs) { lhs = mul(lhs, rhs); return lhs; }
hmat2 SurfaceGodotMulAssign(inout hmat2 lhs, hmat2 rhs) { lhs = mul(lhs, rhs); return lhs; }
hmat3 SurfaceGodotMulAssign(inout hmat3 lhs, hmat3 rhs) { lhs = mul(lhs, rhs); return lhs; }
hmat4 SurfaceGodotMulAssign(inout hmat4 lhs, hmat4 rhs) { lhs = mul(lhs, rhs); return lhs; }

#endif
