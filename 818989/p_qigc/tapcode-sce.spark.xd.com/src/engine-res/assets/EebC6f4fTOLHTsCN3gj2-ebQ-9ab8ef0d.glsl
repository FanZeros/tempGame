#ifdef BGFX_SHADER
#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED
    $output vTexCoord, vWorldPos _VCOLOR
#endif
#ifdef COMPILEPS
    $input vTexCoord, vWorldPos _VCOLOR
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "fog.sh"

#else

#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"
#include "Fog.glsl"

varying vec2 vTexCoord;
varying vec4 vWorldPos;
#ifdef VERTEXCOLOR
    varying vec4 vColor;
#endif

#endif

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    #ifndef NOUV
        vTexCoord = GetTexCoord(iTexCoord);
    #endif
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

}

void PS()
{
    // Get material diffuse albedo
    #ifdef DIFFMAP
        #ifdef NOT_SUPPORT_SRGB
            vec4 diffColor = cMatDiffColor * GammaToLinearSpace(texture2D(sDiffMap, vTexCoord));
        #else
            vec4 diffColor = cMatDiffColor * texture2D(sDiffMap, vTexCoord);
        #endif
        #ifdef ALPHAMASK
            if (diffColor.a < 0.5)
                discard;
        #endif
    #else
        vec4 diffColor = cMatDiffColor;
    #endif

    #ifdef VERTEXCOLOR
        diffColor *= vColor;
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    #if defined(MATERIALBAKE)
        EncodeGBufferBake(diffColor.rgb, diffColor.a, 0.85, 0.0, 1.0, GBufferFaceNormal(vWorldPos.xyz, cCameraPosPS), vec3_splat(0.0));
    #elif defined(DEFERRED)
        // Unlit passthrough encode (shadingModelID=0, resolve outputs RT3 color as-is).
        // No fog and no gamma here: the deferred pipeline is linear HDR and the SceneFog
        // quad applies fog uniformly to all opaque pixels
        EncodeGBufferUnlit(diffColor.rgb, GBufferFaceNormal(vWorldPos.xyz, cCameraPosPS));
    #else
        gl_FragColor = vec4(GetFog(diffColor.rgb, fogFactor), diffColor.a);

        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
            gl_FragColor.rgb = LinearToGammaSpace(toAcesFilmic(gl_FragColor.rgb));
        #endif
    #endif
}
