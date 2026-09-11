/*
 * Reflections denoiser temporal accumulation stage.
 * Uses the UE reflections history layout:
 *   RT0: normalized color
 *   RT1.r: sample count, RT1.g: confusion factor
 */

#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"

#ifdef COMPILEVS
    $input a_position
    $output vTexCoord, vScreenPos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vScreenPos
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetQuadTexCoord(gl_Position);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

#ifdef COMPILEPS

#include "ScreenSpace/SSR/SSRDenoiseCommon.sh"

// Scene samplers (depth=5, normal=6, gbufferB=7) come from SSRDenoiseCommon.sh.
SAMPLER2D(u_CurrentColor0, 0);
SAMPLER2D(u_CurrentMeta1, 1);
SAMPLER2D(u_HistoryColor2, 2);
SAMPLER2D(u_HistoryMeta3, 3);
SAMPLER2D(u_MotionVector4, 4);

uniform hfloat u_TemporalBlend;

// Camera-only reprojection matrices, same source/convention as MotionVector.glsl
// (set by View::ApplyMotionVectorParameters execution on the renderpath command).
uniform hmat4 u_InvViewProj;
uniform hmat4 u_PrevViewProj;

#define StoreTemporalResult(color, meta) \
    gl_FragData[0] = color; \
    gl_FragData[1] = meta

// Exact inverse of transform.sh LinearizeDepth: view-space Z (world units) -> device depth.
hfloat DelinearizeDepth(hfloat viewZ, hfloat zNear, hfloat zFar)
{
#if BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC
    hfloat z_n = (zFar + zNear - 2.0 * zNear * zFar / viewZ) / (zFar - zNear);
    return z_n * 0.5 + 0.5;
#else
    return (zFar - zNear * zFar / viewZ) / (zFar - zNear);
#endif
}

// Reproject a screen position at the given device depth through the previous camera
// (camera motion only; same math/convention as MotionVector.glsl).
hvec2 CameraReprojectPrevUV(hvec2 uv, hfloat deviceZ)
{
#if (BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    hfloat clipZ = deviceZ * 2.0 - 1.0;
#else
    hfloat clipZ = deviceZ;
#endif
    hvec4 clipPos = hvec4_init(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, clipZ, 1.0);
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    clipPos.y = -clipPos.y;
#endif
    hvec4 worldPos = mul(clipPos, u_InvViewProj);
    worldPos /= worldPos.w;
    hvec4 prevClipPos = mul(worldPos, u_PrevViewProj);
    hvec2 prevUV = prevClipPos.xy / prevClipPos.w * 0.5 + 0.5;
#if !(BGFX_SHADER_LANGUAGE_GLSL || BGFX_SHADER_LANGUAGE_GLSL_HLSLCC)
    prevUV.y = 1.0 - prevUV.y;
#endif
    return prevUV;
}

// Lumen GetSpecularDominantDirFactor (LumenReflectionDenoiserCommon.ush:37-41,
// Frostbite PBR 3.0 approximation): >= 0.5 means the GGX lobe still points along
// the mirror direction, i.e. roughness <~ 0.33.
hfloat SpecularDominantDirFactor(hfloat roughness)
{
    hfloat s = saturate(1.0 - roughness);
    return s * (sqrt(s) + roughness);
}

hvec4 ClampHistoryToVarianceBoundary(hvec2 uv, hvec4 historyColor, out hfloat outClampNormDist)
{
    hvec4 sum = vec4_splat(0.0);
    hvec4 sumSq = vec4_splat(0.0);

    LOOP
    for (int y = -1; y <= 1; y++)
    {
        LOOP
        for (int x = -1; x <= 1; x++)
        {
            hvec2 sampleUV = uv + hvec2_init(hfloat_init(x), hfloat_init(y)) * cGBufferInvSize.xy;
            sampleUV = clamp(sampleUV, vec2_splat(0.0), vec2_splat(1.0));
            hvec4 sampleColor = texture2D(u_CurrentColor0, sampleUV);
            sum += sampleColor;
            sumSq += sampleColor * sampleColor;
        }
    }

    hvec4 mean = sum * (1.0 / 9.0);
    hvec4 variance = max(sumSq * (1.0 / 9.0) - mean * mean, vec4_splat(0.0));
    hvec4 sigma = sqrt(variance);
    // Lumen default: TemporalNeighborhoodClampScale = 1.0（cvar 注释原话
    // "Higher values reduce noise, but also increase ghosting"）。此前自调的 1.5
    // 会把运动倒影的白色残影留在宽松界内切不掉，噪声增量交给 TAA 收
    hvec4 extent = sigma * 1.0;
    hvec4 clamped = clamp(historyColor, mean - extent, mean + extent);

    // Lumen: the distance the clamp had to pull the history, normalized by the
    // neighborhood extent, feeds the confidence (LumenReflectionDenoiserTemporal.usf:451-471)
    hvec3 nd = abs(clamped.rgb - historyColor.rgb) / max(extent.rgb, vec3_splat(0.1));
    outClampNormDist = length(nd);
    return clamped;
}

void PS()
{
    hvec2 uv = vTexCoord;
    hvec4 currentColor = texture2D(u_CurrentColor0, uv);
    hvec4 currentMeta = texture2D(u_CurrentMeta1, uv);

    BRANCH
    if (currentMeta.r <= 0.0 || currentMeta.g == SSR_DENOISER_INVALID_CONFUSION_FACTOR)
    {
        StoreTemporalResult(currentColor, currentMeta);
        return;
    }

    hvec2 totalMV = texture2D(u_MotionVector4, uv).rg;
    hvec2 historyUV = uv - totalMV;

    // Lumen dual reprojection (LumenReflectionDenoiserTemporal.usf:349-371): the
    // reflected image parallaxes with the *virtual* depth (surface depth + ray length),
    // not with the surface. Prefer the hit-distance reprojected history for shiny
    // surfaces; fall back to plain surface motion when it fails.
    hfloat roughness = SampleRoughness(uv);
    hvec3 viewPos = SampleViewPos(uv);
    hfloat confusion = currentMeta.g;
    bool preferredFailed = false;
    bool usedVirtualHistory = false;
    BRANCH
    if (SpecularDominantDirFactor(roughness) >= 0.5 && confusion > 0.0 && confusion < 0.999)
    {
        // Recover ray length from the confusion factor (UE DenoisingCommon.ush:17-22):
        // c = hit / (dist + hit)  =>  hit = c * dist / (1 - c)
        hfloat viewDist = length(viewPos);
        hfloat hitDist = confusion * viewDist / (1.0 - confusion);

        // Virtual image depth: same screen position, view Z + ray length
        // (Lumen: ConvertToDeviceZ(SceneDepth + ReflectionHitDistance), usf:323-325)
        hfloat deviceZ = texture2D(u_DenoiseDepth5, uv).r;
        hfloat virtualDeviceZ = DelinearizeDepth(viewPos.z + hitDist, cNearClipPS, cFarClipPS);

        // LumenPosition.ush:62-85 four-param GetHistoryScreenPosition: camera parallax
        // evaluated at the virtual depth, then the surface's own object motion added
        // *incrementally* (object velocity = total MV - camera MV at surface depth).
        hvec2 cameraVirtualMV = uv - CameraReprojectPrevUV(uv, virtualDeviceZ);
        hvec2 objectMV = totalMV - (uv - CameraReprojectPrevUV(uv, deviceZ));
        // Equivalent of UE's dynamic-pixel gate (EncodedVelocity.x > 0): our MV buffer
        // carries no dynamic bit, so treat sub-quarter-pixel residue as static noise
        hvec2 objectPx = objectMV / cGBufferInvSize.xy;
        if (dot(objectPx, objectPx) < 0.0625)
            objectMV = vec2_splat(0.0);

        hvec2 virtualUV = uv - (cameraVirtualMV + objectMV);
        BRANCH
        if (all(greaterThanEqual(virtualUV, vec2_splat(0.0))) && all(lessThanEqual(virtualUV, vec2_splat(1.0))))
        {
            historyUV = virtualUV;
            usedVirtualHistory = true;
        }
        else
            preferredFailed = true;   // Lumen: bPreferredHistoryFailed -> Confidence = 0
    }

    bool historyValid = all(greaterThanEqual(historyUV, vec2_splat(0.0))) && all(lessThanEqual(historyUV, vec2_splat(1.0)));

    hvec4 historyColor = currentColor;
    hvec4 historyMeta = currentMeta;
    BRANCH
    if (historyValid)
    {
        historyColor = texture2D(u_HistoryColor2, historyUV);
        historyMeta = texture2D(u_HistoryMeta3, historyUV);
        historyValid = historyMeta.r > 0.0 && historyMeta.g != SSR_DENOISER_INVALID_CONFUSION_FACTOR;
    }

    BRANCH
    if (!historyValid)
    {
        // Restart accumulation: meta.r becomes the temporal sample count from here on
        // (the pre-convolution pass' weight sum has a different scale, do not carry it over).
        StoreTemporalResult(currentColor, hvec4_init(1.0, currentMeta.g, 0.0, 1.0));
        return;
    }

    // Geometric history weights only on the surface-motion path. The virtual path
    // compares a *different* surface location by design; Lumen disables its depth test
    // there (REFLECT_HIT_DEPTH_TEST 0, "couldn't find a spot where it would reduce
    // leaking") and relies on the neighborhood clamp + confidence instead.
    hfloat historyWeight = 1.0;
    BRANCH
    if (!usedVirtualHistory)
    {
        hvec3 currentNormal = SampleViewNormal(uv);
        hvec3 historyViewPos = SampleViewPos(historyUV);
        hvec3 historyNormal = SampleViewNormal(historyUV);
        hfloat historyRoughness = SampleRoughness(historyUV);

        hfloat tokoyashiWeight = SsrDenoiseTokoyashiWeight(
            viewPos, currentNormal, roughness,
            historyViewPos, historyNormal, historyRoughness);

        hfloat depthDelta = abs(viewPos.z - historyViewPos.z);
        hfloat depthWeight = saturate(1.0 - depthDelta / max(viewPos.z * 0.01, 0.01));
        historyWeight = tokoyashiWeight * depthWeight;
    }

    hfloat clampNormDist = 0.0;
    historyColor = ClampHistoryToVarianceBoundary(uv, historyColor, clampNormDist);

    // Lumen confidence model (LumenReflectionDenoiserTemporal.usf:451-491): geometric
    // weights and the clamp pull distance discount the accumulated *frame counter*
    // instead of the blend alpha -- low confidence rewinds accumulation to an earlier
    // stage rather than hard-rejecting, which is much smoother on transitions.
    hfloat confidence = historyWeight * saturate(1.0 - clampNormDist);
    if (preferredFailed)
        confidence = 0.0;
    // Blend a bit of history even at zero confidence to smoothen transitions (usf:482-484)
    confidence = 0.75 * confidence + 0.25;

    // Mirror short history (usf:383-386): near-mirror surfaces accumulate at most ~2
    // frames -- the reflected content itself may move and no surface reprojection can
    // track it; bounding the history keeps such residual ghosts to a couple frames
    // (cleaned up by TAA). Base cap = Lumen default MaxFramesAccumulated = 12
    // （此前自调 32 会让运动倒影残影衰减慢 2.7 倍）
    hfloat maxFrames = mix(2.0, 12.0, saturate(roughness / 0.05));

    hfloat numFrames = min(min(historyMeta.r, maxFrames) * confidence + 1.0, maxFrames);
    hfloat currentBlend = saturate(max(u_TemporalBlend, 1.0 / numFrames));
    hvec4 outColor = mix(historyColor, currentColor, currentBlend);
    hfloat outConfusion = min(historyMeta.g, currentMeta.g);
    StoreTemporalResult(SsrDenoiseClampColorForEncoding(outColor), hvec4_init(numFrames, outConfusion, 0.0, 1.0));
}

#endif
