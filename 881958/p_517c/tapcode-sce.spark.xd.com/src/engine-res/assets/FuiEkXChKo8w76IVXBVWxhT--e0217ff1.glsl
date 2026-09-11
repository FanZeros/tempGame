#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position, a_color0, a_normal, a_texcoord0 _SKINNED _INSTANCED
    $output vTexCoord, vWorldPos, vColor, vDeltaTime _VSCREENPOS
#endif
#ifdef COMPILEPS
    $input vTexCoord, vWorldPos, vColor, vDeltaTime
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "fog.sh"

#ifdef START_ELAPSED_TIME
uniform float u_StartElapsedTime;
#endif

#ifdef DISAPPEAR
uniform float u_DisappearTime;
#endif

#if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE)
    uniform float u_SoftParticleFadeScale;
#endif

#define cStartElapsedTime u_StartElapsedTime
#define cDisappearTime u_DisappearTime
#define cSoftParticleFadeScale u_SoftParticleFadeScale

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vTexCoord = GetTexCoord(iTexCoord);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

	#if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE)
        vScreenPos = GetScreenPos(gl_Position);
    #endif

    vColor = iColor;
    // 300 毫秒过渡透明度
    vDeltaTime.x = (cElapsedTimeReal - iNormal.x) / 0.3;
}

void PS()
{
    // Get material diffuse albedo
    #ifdef DIFFMAP
        vec4 diffColor = cMatDiffColor * LinearColor(texture2D(sDiffMap, vTexCoord));
        #ifdef ALPHAMASK
            if (diffColor.a < 0.5)
                discard;
        #endif
    #else
        vec4 diffColor = cMatDiffColor;
    #endif

    #if !defined(EDITOR)
        diffColor.a = mix(vColor.r, vColor.a, min(1.0, vDeltaTime.x));
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), v__GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    #if defined(MATERIALBAKE)
        EncodeGBufferBake(diffColor.rgb, diffColor.a, 0.85, 0.0, 1.0, GBufferFaceNormal(vWorldPos.xyz, cCameraPosPS), vec3_splat(0.0));
    #elif defined(DEFERRED)
        // Unlit passthrough encode (shadingModelID=0). No fog and no gamma/opacity here:
        // the deferred pipeline is linear HDR, the GBuffer is an opaque path, and the
        // SceneFog quad applies fog uniformly
        EncodeGBufferUnlit(diffColor.rgb, GBufferFaceNormal(vWorldPos.xyz, cCameraPosPS));
    #else
        gl_FragColor = vec4(GetFog(diffColor.rgb, fogFactor), diffColor.a);

        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
            gl_FragColor.rgb = LinearToGammaSpace(gl_FragColor.rgb);
        #endif

        #ifdef OPACITY
            gl_FragColor.a *= cOpacity;
        #else
            #ifdef DISAPPEAR
                #ifdef START_ELAPSED_TIME
                    float elapsedTime = cElapsedTimePS;
                    if (cStartElapsedTime > elapsedTime)
                        elapsedTime += 20.0;
                    float opacity = (1.0 - (elapsedTime - cStartElapsedTime) / cDisappearTime);
                    gl_FragColor.a *= step(0.0, opacity) * opacity;
                #endif
            #endif
        #endif
    #endif
}
