void SurfaceAlphaScissor(float alpha, float alphaScissorThreshold)
{
#ifdef SURFACE_USES_ALPHA_SCISSOR
    if (alpha < alphaScissorThreshold)
        discard;
#endif
}
