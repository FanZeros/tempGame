#ifndef __POSTPROCESS_SH__
#define __POSTPROCESS_SH__

#if COMPILEPS
//#define LumWeights vec3(0.2126, 0.7152, 0.0722) // moved below

vec2 Noise(vec2 coord)
{
    float noiseX = clamp(fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453), 0.0, 1.0);
    float noiseY = clamp(fract(sin(dot(coord, vec2(12.9898, 78.233) * 2.0)) * 43758.5453), 0.0, 1.0);
    return vec2(noiseX, noiseY);
}

// Adapted: http://callumhay.blogspot.com/2010/09/gaussian-blur-shader-glsl.html
vec4 GaussianBlur(int blurKernelSize, vec2 blurDir, vec2 blurRadius, float sigma, sampler2D texSampler, vec2 texCoord)
{
    int blurKernelSizeHalfSize = blurKernelSize / 2;

    // Incremental Gaussian Coefficent Calculation (See GPU Gems 3 pp. 877 - 889)
    vec3 gaussCoeff;
    gaussCoeff.x = 1.0 / (sqrt(2.0 * M_PI) * sigma);
    gaussCoeff.y = exp(-0.5 / (sigma * sigma));
    gaussCoeff.z = gaussCoeff.y * gaussCoeff.y;

    vec2 blurVec = blurRadius * blurDir;
    vec4 avgValue = vec4_splat(0.0);
    float gaussCoeffSum = 0.0;

    avgValue += texture2D(texSampler, texCoord) * gaussCoeff.x;
    gaussCoeffSum += gaussCoeff.x;
    gaussCoeff.xy *= gaussCoeff.yz;

    for (int i = 1; i <= blurKernelSizeHalfSize; i++)
    {
        avgValue += texture2D(texSampler, texCoord - float(i) * blurVec) * gaussCoeff.x;
        avgValue += texture2D(texSampler, texCoord + float(i) * blurVec) * gaussCoeff.x;

        gaussCoeffSum += 2.0 * gaussCoeff.x;
        gaussCoeff.xy *= gaussCoeff.yz;
    }

    return avgValue / gaussCoeffSum;
}

float GetColorLum(vec3 color)
{
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 SetSaturation(vec3 color, float saturation)
{
    float luma = GetColorLum(color);
	return vec3_splat(luma) + saturation * (color - vec3_splat(luma));
}

vec4 ExtractBright(vec4 color, float threshold)
{
    float luma = GetColorLum(color.rgb);
    float luma2 = max(0.0, luma - threshold);
    hfloat lumdivide = luma2 / (luma + 1e-4);
    return vec4(color.rgb * lumdivide, color.a);
}

#define LumWeights vec3(0.2126, 0.7152, 0.0722)

vec3 ReinhardEq3Tonemap(vec3 x)
{
    return x / (1.0 + x);
}

vec3 ReinhardEq4Tonemap(vec3 x, float white)
{
    return x * (1.0 + x / white) / (1.0 + x);
}

// Unchared2 tone mapping (See http://filmicgames.com)
const float A = 0.15;
const float B = 0.50;
const float C = 0.10;
const float D = 0.20;
const float E = 0.02;
const float F = 0.30;

vec3 Uncharted2Tonemap(vec3 x)
{
   return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}

#ifndef URHO3D_MOBILE
vec3 ColorCorrection(vec3 color, sampler3D lut)
{
    float lutSize = 16.0;
    float scale = (lutSize - 1.0) / lutSize;
    float offset = 1.0 / (2.0 * lutSize);
    return texture3D(lut, clamp(color, 0.0, 1.0) * scale + offset).rgb;
}
#endif // URHO3D_MOBILE

#endif // COMPILEPS

#ifdef VIGNETTE
#if COMPILEVS

// Scale {-1 to 1} of the viewport space to vignette circle space.
// Vignette space is scaled such that regardless of viewport aspect ratio, 
// corners are at the same brightness on a circle.
vec2 VignetteSpace(vec2 Pos, float AspectRatio)
{
    // could be optimized but this computation should be done in the vertex shader (3 or 4 vertices)
    float Scale = sqrt(2.0) / sqrt(1.0 + AspectRatio * AspectRatio);
    return Pos * vec2(1.0, AspectRatio) * Scale;
}

#endif // COMPILEVS

#if COMPILEPS

// Generate a mask to darken the screen borders.
// (Camera artifact and artistic effect)
// @param VignetteCircleSpacePos from VignetteSpace()
float ComputeVignetteMask(vec2 VignetteCircleSpacePos, float Intensity)
{
    // Natural vignetting
    // cosine-fourth law
    VignetteCircleSpacePos *= Intensity;
    float Tan2Angle = dot( VignetteCircleSpacePos, VignetteCircleSpacePos );
    float Cos4Angle = Square( rcp( Tan2Angle + 1.0 ) );
    return Cos4Angle;
}

#endif // COMPILEPS
#endif // VIGNETTE

#endif