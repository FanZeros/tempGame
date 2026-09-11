// DOF.glsl - Depth of Field post-process shader
// Supports: Focal distance, focal range, bokeh-style blur

#ifdef BGFX_SHADER
#include "varying_quad.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position
    $output vScreenPos
#endif
#ifdef COMPILEPS
    $input vScreenPos
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"

#else

#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"

varying vec2 vScreenPos;

#endif

// ==================== DOF Uniforms ====================
#ifdef COMPILEPS

// DOF parameters
// x: focalDistance, y: focalRange, z: maxBlur, w: blurQuality (0=low, 1=medium, 2=high)
uniform vec4 u_DOFParams1;
// x: nearBlurScale, y: farBlurScale, z: bokehBrightness, w: unused
uniform vec4 u_DOFParams2;
// xy: screen texel size (1/width, 1/height), zw: unused
uniform vec4 u_DOFParams3;

#define cFocalDistance u_DOFParams1.x
#define cFocalRange u_DOFParams1.y
#define cMaxBlur u_DOFParams1.z
#define cBlurQuality u_DOFParams1.w
#define cNearBlurScale u_DOFParams2.x
#define cFarBlurScale u_DOFParams2.y
#define cBokehBrightness u_DOFParams2.z
#define cTexelSize u_DOFParams3.xy

// ==================== Poisson Disk Samples ====================
// Use functions instead of const arrays for HLSL compatibility

vec2 GetPoissonSample16(int i)
{
    if (i == 0) return vec2(-0.94201624, -0.39906216);
    if (i == 1) return vec2(0.94558609, -0.76890725);
    if (i == 2) return vec2(-0.094184101, -0.92938870);
    if (i == 3) return vec2(0.34495938, 0.29387760);
    if (i == 4) return vec2(-0.91588581, 0.45771432);
    if (i == 5) return vec2(-0.81544232, -0.87912464);
    if (i == 6) return vec2(-0.38277543, 0.27676845);
    if (i == 7) return vec2(0.97484398, 0.75648379);
    if (i == 8) return vec2(0.44323325, -0.97511554);
    if (i == 9) return vec2(0.53742981, -0.47373420);
    if (i == 10) return vec2(-0.26496911, -0.41893023);
    if (i == 11) return vec2(0.79197514, 0.19090188);
    if (i == 12) return vec2(-0.24188840, 0.99706507);
    if (i == 13) return vec2(-0.81409955, 0.91437590);
    if (i == 14) return vec2(0.19984126, 0.78641367);
    return vec2(0.14383161, -0.14100790);
}

vec2 GetPoissonSample8(int i)
{
    if (i == 0) return vec2(-0.326212, -0.405805);
    if (i == 1) return vec2(-0.840144, -0.073580);
    if (i == 2) return vec2(-0.695914, 0.457137);
    if (i == 3) return vec2(-0.203345, 0.620716);
    if (i == 4) return vec2(0.962340, -0.194983);
    if (i == 5) return vec2(0.473434, -0.480026);
    if (i == 6) return vec2(0.519456, 0.767022);
    return vec2(0.185461, -0.893124);
}

vec2 GetPoissonSample4(int i)
{
    if (i == 0) return vec2(-0.5, -0.5);
    if (i == 1) return vec2(0.5, -0.5);
    if (i == 2) return vec2(-0.5, 0.5);
    return vec2(0.5, 0.5);
}

// ==================== Helper Functions ====================

// Get linear depth from depth buffer (D24S8 format)
float GetLinearDepth(vec2 uv)
{
    float depth = texture2D(sNormalMap, uv).r;
    return LinearizeDepth(depth, cNearClipPS, cFarClipPS);
}

// Calculate Circle of Confusion (CoC)
// Returns: negative = near blur, positive = far blur, 0 = in focus
float CalculateCoC(float depth)
{
    float diff = depth - cFocalDistance;
    float coc;

    if (diff < 0.0)
    {
        // Near field (in front of focal plane)
        coc = diff / cFocalRange * cNearBlurScale;
    }
    else
    {
        // Far field (behind focal plane)
        coc = diff / cFocalRange * cFarBlurScale;
    }

    // Clamp to max blur radius
    return clamp(coc, -1.0, 1.0);
}

// Get absolute CoC for blur radius
float GetBlurRadius(float coc)
{
    return abs(coc) * cMaxBlur;
}

// ==================== DOF Blur ====================

vec3 ApplyDOF_Low(vec2 uv, float centerCoC)
{
    float radius = GetBlurRadius(centerCoC);

    if (radius < 0.5)
        return texture2D(sDiffMap, uv).rgb;

    vec3 result = vec3_splat(0.0);
    float totalWeight = 0.0;

    for (int i = 0; i < 4; i++)
    {
        vec2 offset = GetPoissonSample4(i) * radius * cTexelSize;
        vec2 sampleUV = uv + offset;

        float sampleDepth = GetLinearDepth(sampleUV);
        float sampleCoC = CalculateCoC(sampleDepth);
        float sampleRadius = GetBlurRadius(sampleCoC);

        // Weight: prevent sharp objects from being blurred by blurry background
        float weight = 1.0;
        if (sampleCoC * centerCoC < 0.0)
        {
            // Different sign = one near, one far
            weight = 0.5;
        }
        else if (sampleRadius < radius * 0.5)
        {
            // Sharp sample shouldn't contribute much to blurry result
            weight = sampleRadius / (radius * 0.5 + 0.001);
        }

        result += texture2D(sDiffMap, sampleUV).rgb * weight;
        totalWeight += weight;
    }

    return result / max(totalWeight, 0.001);
}

vec3 ApplyDOF_Medium(vec2 uv, float centerCoC)
{
    float radius = GetBlurRadius(centerCoC);

    if (radius < 0.5)
        return texture2D(sDiffMap, uv).rgb;

    vec3 result = vec3_splat(0.0);
    float totalWeight = 0.0;

    for (int i = 0; i < 8; i++)
    {
        vec2 offset = GetPoissonSample8(i) * radius * cTexelSize;
        vec2 sampleUV = uv + offset;

        float sampleDepth = GetLinearDepth(sampleUV);
        float sampleCoC = CalculateCoC(sampleDepth);
        float sampleRadius = GetBlurRadius(sampleCoC);

        float weight = 1.0;
        if (sampleCoC * centerCoC < 0.0)
        {
            weight = 0.5;
        }
        else if (sampleRadius < radius * 0.5)
        {
            weight = sampleRadius / (radius * 0.5 + 0.001);
        }

        // Bokeh brightness boost for bright spots
        vec3 sampleColor = texture2D(sDiffMap, sampleUV).rgb;
        float brightness = dot(sampleColor, vec3(0.299, 0.587, 0.114));
        float bokehWeight = 1.0 + brightness * cBokehBrightness * abs(centerCoC);

        result += sampleColor * weight * bokehWeight;
        totalWeight += weight * bokehWeight;
    }

    return result / max(totalWeight, 0.001);
}

vec3 ApplyDOF_High(vec2 uv, float centerCoC)
{
    float radius = GetBlurRadius(centerCoC);

    if (radius < 0.5)
        return texture2D(sDiffMap, uv).rgb;

    vec3 result = vec3_splat(0.0);
    float totalWeight = 0.0;

    for (int i = 0; i < 16; i++)
    {
        vec2 offset = GetPoissonSample16(i) * radius * cTexelSize;
        vec2 sampleUV = uv + offset;

        float sampleDepth = GetLinearDepth(sampleUV);
        float sampleCoC = CalculateCoC(sampleDepth);
        float sampleRadius = GetBlurRadius(sampleCoC);

        float weight = 1.0;
        if (sampleCoC * centerCoC < 0.0)
        {
            weight = 0.5;
        }
        else if (sampleRadius < radius * 0.5)
        {
            weight = sampleRadius / (radius * 0.5 + 0.001);
        }

        // Bokeh brightness boost
        vec3 sampleColor = texture2D(sDiffMap, sampleUV).rgb;
        float brightness = dot(sampleColor, vec3(0.299, 0.587, 0.114));
        float bokehWeight = 1.0 + brightness * cBokehBrightness * abs(centerCoC);

        result += sampleColor * weight * bokehWeight;
        totalWeight += weight * bokehWeight;
    }

    return result / max(totalWeight, 0.001);
}

// Main DOF function
vec3 ApplyDOF(vec2 uv)
{
    float depth = GetLinearDepth(uv);
    float coc = CalculateCoC(depth);

    // Select quality level
    if (cBlurQuality < 0.5)
        return ApplyDOF_Low(uv, coc);
    else if (cBlurQuality < 1.5)
        return ApplyDOF_Medium(uv, coc);
    else
        return ApplyDOF_High(uv, coc);
}

#endif // COMPILEPS

// ==================== Vertex Shader ====================

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vScreenPos = GetScreenPosPreDiv(gl_Position);
}

// ==================== Pixel Shader ====================

void PS()
{
    vec3 color = ApplyDOF(vScreenPos);
    gl_FragColor = vec4(color, 1.0);
}
