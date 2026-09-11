#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED
    $output vWorldPos, vScreenPos _VCOLOR _VCLIP
#endif
#ifdef COMPILEPS
    $input vWorldPos, vScreenPos _VCOLOR _VCLIP
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
    
    #if defined(DIFFMAP)
        vWorldPos = vec4(0, 0, 0,GetDepth(gl_Position));
        vScreenPos = GetScreenPos(gl_Position);
    #endif
    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif
}

void PS()
{
    vec4 diffColor = cMatDiffColor;

    #ifdef VERTEXCOLOR
        diffColor *= vColor;
    #endif

    #if defined(DIFFMAP)
        vec4 depthInput = texture2DProj(sDiffMap, vScreenPos);
        float depthBG = DecodeDepth(depthInput.rgb);
        if (vWorldPos.w > depthBG + 0.0001)
        {
            if (diffColor.a > 0.9)
                diffColor = vec4(1, 0.84, 0, 0.8);
            else
                diffColor.a *= 0.2;
        }
    #endif
    diffColor.rgb = LinearToGammaSpace(diffColor.rgb);
    gl_FragColor = diffColor;
}

