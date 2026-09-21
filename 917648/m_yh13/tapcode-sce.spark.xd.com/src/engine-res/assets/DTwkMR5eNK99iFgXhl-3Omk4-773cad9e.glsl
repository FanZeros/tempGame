#define BASIC
#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _TEXCOORD0 _COLOR0 _TEXCOORD1
    $output _VTEXCOORD _VCOLOR _VTEXCOORD2 _VSCREENPOS
#endif
#ifdef COMPILEPS
    $input _VTEXCOORD _VCOLOR _VTEXCOORD2 _VSCREENPOS
#endif

#include "Common/common.sh"
#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    
    #if defined(DIFFMAP) || defined(ALPHAMAP)
        vTexCoord = iTexCoord;
    #endif
    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif
    #ifdef MASK
        vTexCoord2 = iTexCoord1;
    #endif
    #ifdef ROUND
        // 减去圆角遮罩中心
        vScreenPos.xy = iPos.xy - cLightPos.xy;
    #endif
}

void PS()
{
	#ifdef VERTEXCOLOR
        // 除了图片颜色混合都不转线性了（为了减少误差）
        #if defined(GAMMA_IN_SHADERING) && defined(DIFFMAP)
            vec4 iColor = GammaToLinearSpace(vColor);
        #else
            vec4 iColor = vColor;
        #endif
    #endif
	
    // 只有颜色
    #if defined(VERTEXCOLOR) && !defined(DIFFMAP) && !defined(ALPHAMAP)
        gl_FragColor = iColor;

    // 只有图片
    #elif defined(DIFFMAP) && !defined(VERTEXCOLOR)
        gl_FragColor = texture2D(sDiffMap, vTexCoord);

    // 既有颜色又有图片
    #elif defined(DIFFMAP) && defined(VERTEXCOLOR) && defined(MIXCOLOR)
        #if defined(TINTBLACK)
            vec4 texColor = texture2D(sDiffMap, vTexCoord);
            gl_FragColor.a = texColor.a * iColor.a;
            gl_FragColor.rgb = ((texColor.a - 1.0) * cMatSpecColor.a + 1.0 - texColor.rgb) * cMatSpecColor.rgb + texColor.rgb * iColor.rgb;
        #else
            gl_FragColor = texture2D(sDiffMap, vTexCoord) * iColor;
        #endif

    // 既有颜色又有图片
    #elif defined(DIFFMAP) && defined(VERTEXCOLOR) && !defined(BMPFONT)
        vec4 diffInput = texture2D(sDiffMap, vTexCoord);
        float srcA = diffInput.a;
        float dstA = iColor.a;
        float finalA = srcA + dstA * (1.0 - srcA);
        gl_FragColor = (diffInput * srcA + iColor * dstA * (1.0 - srcA)) / max(finalA, 0.0001);
        gl_FragColor.a = finalA;

    // 只用于渲染位图字
    #elif defined(BMPFONT)
        vec4 alphaInput = texture2D(sDiffMap, vTexCoord);
        gl_FragColor = vec4(iColor.rgb, (alphaInput.r + alphaInput.g + alphaInput.b) / 3.0);

    // 文字
    #elif defined(ALPHAMAP)
        float alphaInput = texture2D(sDiffMap, vTexCoord).a;
        #if defined(URHO3D_EMSCRIPTEN) || defined(WEBGL)
            // WebGL2: Use premultiplied alpha to avoid black halo at glyph edges
            float finalAlpha = iColor.a * alphaInput;
            gl_FragColor = vec4(iColor.rgb * finalAlpha, finalAlpha);
        #else
            gl_FragColor = vec4(iColor.rgb, iColor.a * alphaInput);
        #endif
    #endif

    #if defined(MASK)
        vec4 maskInput = texture2D(sNormalMap, vTexCoord2);
        gl_FragColor.a = min(gl_FragColor.a, maskInput.a);
    #endif

    #if defined(OPACITY)
        float opacity = cMatDiffColor.a;
        gl_FragColor.a = gl_FragColor.a * opacity;
    #endif

    #if defined(ROUND)
        // 四角圆角相同
        vec2 disVector = max(abs(vScreenPos.xy) - cLightPosPS.xy, 0.0);
        gl_FragColor.a *= clamp(cLightPosPS.z - length(disVector.xy), 0.0, 1.0);
    #endif

    #if defined(GRAY)
        // 用 vec3_splat 而不是对标量做 .xxx：标量 swizzle 在 GLSL ES 非法（HLSL 与桌面 GLSL
        // 允许），端上现编按 ES 规范编译时会报 'scalar swizzle' not supported with profile: es
        gl_FragColor.rgb = vec3_splat(dot(gl_FragColor.rgb, vec3(0.2126, 0.7152, 0.0722)));
    #endif

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
        // 除了图片颜色混合都不反gamma了（为了减少误差）
        #if defined(DIFFMAP) && !defined(TINTBLACK)
            gl_FragColor.rgb = LinearToGammaSpace(gl_FragColor.rgb);
        #endif
	#endif

    
}
