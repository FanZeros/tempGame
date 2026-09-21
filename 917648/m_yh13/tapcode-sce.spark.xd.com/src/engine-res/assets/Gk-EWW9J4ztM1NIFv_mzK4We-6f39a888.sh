#ifndef __SURFACE_OUTLINE_SH__
#define __SURFACE_OUTLINE_SH__

#if COMPILEVS && (defined(SURFACE_TOON_OUTLINE) || defined(SURFACE_GENERIC_OUTLINE) || defined(VELOCITY_PASS))

#if SURFACE_SHADER_ABI_VERSION >= 2

hvec4 DecodeSurfaceOutlineColor(hfloat packedColor)
{
    uint packedBits = floatBitsToUint(packedColor);
    uint rgb = (packedBits & 0x007fffffu) | ((packedBits >> 8u) & 0x00800000u);
    uint encodedAlpha = (packedBits >> 23u) & 0xffu;
    uint alpha7 = encodedAlpha > 0u ? min(encodedAlpha - 1u, 127u) : 0u;
    return hvec4_init(
        float(rgb & 0xffu) / 255.0,
        float((rgb >> 8u) & 0xffu) / 255.0,
        float((rgb >> 16u) & 0xffu) / 255.0,
        float(alpha7) / 127.0);
}

hvec4 GetSurfaceOutlineColor()
{
    return DecodeSurfaceOutlineColor(iSurfaceOutlinePackedColor);
}

hvec3 ExpandSurfaceOutline(hvec3 worldPos, hvec3 worldNormal, hmat4 modelMatrix)
{
    hvec3 strokeNormal = iColor.xyz * 2.0 - 1.0;
    hvec3 smoothStrokeNormal = normalize(mul(hvec4_init(strokeNormal, 0.0), modelMatrix).xyz);
    hfloat smoothNormal = iSurfaceOutlineThicknessAndSmoothNormal < 0.0 ? 1.0 : 0.0;
    hvec3 outlineNormal = normalize(mix(worldNormal, smoothStrokeNormal, smoothNormal));
    return worldPos + outlineNormal * abs(iSurfaceOutlineThicknessAndSmoothNormal);
}

hfloat SurfaceOutlineZBias(hvec4 clipPos)
{
    return iSurfaceOutlineZBias * clipPos.w;
}

#else

hvec4 GetSurfaceOutlineColor()
{
    return hvec4_init(iStrokeColor.r, iStrokeColor.g, iStrokeColor.b, iStrokeColorInfluence);
}

hvec3 ExpandSurfaceOutline(hvec3 worldPos, hvec3 worldNormal, hmat4 modelMatrix)
{
    hvec3 strokeNormal = iColor.xyz * 2.0 - 1.0;
    hvec3 smoothStrokeNormal = normalize(mul(hvec4_init(strokeNormal, 0.0), modelMatrix).xyz);
    hvec3 outlineNormal = normalize(mix(worldNormal, smoothStrokeNormal, iStrokeColor.a));
    return worldPos + outlineNormal * max(iStrokeThickness, 0.0);
}

hfloat SurfaceOutlineZBias(hvec4 clipPos)
{
    return iStrokeZBias * clipPos.w;
}

#endif

#endif

vec3 MixSurfaceOutlineColor(vec3 surfaceColor, vec3 outlineColor, float colorInfluence, float brightness)
{
#if SURFACE_SHADER_ABI_VERSION >= 2
    return mix(surfaceColor, outlineColor * max(brightness, 0.0), saturate(colorInfluence));
#else
    return mix(surfaceColor, outlineColor, saturate(colorInfluence)) * max(brightness, 0.0);
#endif
}

#endif
