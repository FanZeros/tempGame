float GetToonDither4x4(vec2 pixelPosition)
{
    vec2 cell = mod(floor(pixelPosition), 4.0);
    float row0 = mix(mix(0.0, 8.0, step(0.5, cell.x)), mix(2.0, 10.0, step(2.5, cell.x)), step(1.5, cell.x));
    float row1 = mix(mix(12.0, 4.0, step(0.5, cell.x)), mix(14.0, 6.0, step(2.5, cell.x)), step(1.5, cell.x));
    float row2 = mix(mix(3.0, 11.0, step(0.5, cell.x)), mix(1.0, 9.0, step(2.5, cell.x)), step(1.5, cell.x));
    float row3 = mix(mix(15.0, 7.0, step(0.5, cell.x)), mix(13.0, 5.0, step(2.5, cell.x)), step(1.5, cell.x));
    float top = mix(row0, row1, step(0.5, cell.y));
    float bottom = mix(row2, row3, step(2.5, cell.y));
    return (mix(top, bottom, step(1.5, cell.y)) + 0.5) / 16.0;
}

// Discard Toon opaque pixels that fail the screen-space dither fade.
void ToonDitherClip(float ditherOpacity, vec2 pixelPosition)
{
#ifdef SURFACE_USES_DITHER_OPACITY
    if (saturate(ditherOpacity) < GetToonDither4x4(pixelPosition))
        discard;
#endif
}
