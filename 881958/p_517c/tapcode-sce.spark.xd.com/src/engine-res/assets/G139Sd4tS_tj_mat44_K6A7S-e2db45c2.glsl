#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#include "constants.sh"

#ifdef USEMASK
    #define _VTEXCOORDMASK , vTexCoordMask
#else
    #define _VTEXCOORDMASK 
#endif

#ifdef DISSOLVE
    #define _VDISSOLVE , vDissolve
    #define _VTEXCOORDDISSOLVE , vTexCoordDissolve
#else
    #define _VDISSOLVE 
    #define _VTEXCOORDDISSOLVE
#endif

#ifdef PLANESOFTPARTICLE
    #define _PLANEPOSZ , vPlanePosZ
#else
    #define _PLANEPOSZ 
#endif

#ifdef COMPILEVS
    $input a_position _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _TEXCOORD2 _ATANGENT _SKINNED _INSTANCED
    $output vTexCoordDiff _VTEXCOORDMASK _VTEXCOORDDISSOLVE vWorldPos _VSCREENPOS _VCOLOR ,vNormal  _VDISSOLVE _PLANEPOSZ
#endif
#ifdef COMPILEPS
    $input vTexCoordDiff _VTEXCOORDMASK _VTEXCOORDDISSOLVE vWorldPos _VSCREENPOS _VCOLOR ,vNormal _VDISSOLVE _PLANEPOSZ
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "fog.sh"

uniform vec4 u_uvDiffParams;
uniform vec4 u_EmitterTime;
uniform vec4 u_TexRotate1;
uniform vec4 u_TexRotate2;
uniform float u_SoftParticleFadeScale;

#define cUScalar (u_uvDiffParams.x)
#define cVScalar (u_uvDiffParams.y)
#define cUSpeed (u_uvDiffParams.z)
#define cVSpeed (u_uvDiffParams.w)
#define cEmitterTime (u_EmitterTime.x)

#define cDiffSin (u_TexRotate1.x)
#define cDiffCos (u_TexRotate1.y)
#define cMaskSin (u_TexRotate1.z)
#define cMaskCos (u_TexRotate1.w)
#define cDissolveSin (u_TexRotate2.x)
#define cDissolveCos (u_TexRotate2.y)

#define cSoftParticleFadeScale u_SoftParticleFadeScale
#ifdef USEMASK
    uniform vec4 u_uvMaskParams;
    #define cMaskUScalar (u_uvMaskParams.x)
    #define cMaskVScalar (u_uvMaskParams.y)
    #define cMaskUSpeed (u_uvMaskParams.z)
    #define cMaskVSpeed (u_uvMaskParams.w)
#endif

#ifdef DISSOLVE
    uniform float u_TexMultiply;
    uniform float u_Smooth;
    uniform vec4 u_uvDissolveParams;
    #define cTexMultiply u_TexMultiply
    #define cSmooth u_Smooth
    #define cDissolve (a_texcoord2.x)
    #define cDissolveUScalar (u_uvDissolveParams.x)
    #define cDissolveVScalar (u_uvDissolveParams.y)
    #define cDissolveUSpeed (u_uvDissolveParams.z)
    #define cDissolveVSpeed (u_uvDissolveParams.w)
#endif

#ifdef PLANESOFTPARTICLE
    #define cPlanePosZ (a_texcoord2.y)
    uniform float u_SoftFadeHeight;
    #define cSoftFadeHeight u_SoftFadeHeight
#endif

vec2 GetFinalUV(vec2 uvInput, float sinRot, float cosRot, float uScalar, float vScalar, float uOffset, float vOffset)
{
    vec2 finalUV =  uvInput - 0.5;
    finalUV = vec2(dot(finalUV, vec2(cosRot,sinRot)), dot(finalUV, vec2(-sinRot, cosRot))) + 0.5;
    finalUV = vec2(finalUV.x * uScalar + uOffset, finalUV.y * vScalar + vOffset);
    return finalUV;
}

void VS()
{
    hmat4 modelMatrix = iModelMatrix;

    #if defined (BILLBOARD) && defined (BILLBOARD_ROTATEAXIS)
        //先用modelMatrix算一下世界坐标(其实是不精确的),用来算相机朝向,拿到billboardRot后再算一遍准确的worldPos
        hvec3 basePos = mul(iPos, modelMatrix).xyz;
        hvec3 cameraDir = normalize(cCameraPos - basePos);
        hvec3 right = cCameraRight;
        hvec3 up = -normalize(cross(right, cameraDir));

        hmat3 billboardRot = TR(hmat3_init(
            right.x, up.x, -cameraDir.x,
            right.y, up.y, -cameraDir.y,
            right.z, up.z, -cameraDir.z
        ));
        hvec3 worldPos = basePos + mul(hvec3_init(iSize.x, iSize.y, 0.0), billboardRot);
    #else
        hvec3 worldPos = GetWorldPos(modelMatrix);
    #endif
    gl_Position = GetClipPos(worldPos);
    vec2 texCoord = GetTexCoord(iTexCoord);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    #if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE)
        vScreenPos = GetScreenPos(gl_Position);
    #endif

    #ifdef VERTEXCOLOR
        vColor = iColor;
    #endif

    #ifdef USEFRESNEL
        vNormal = GetWorldNormal(modelMatrix);
    #endif

    float uvTime = cElapsedTime;
    #ifdef USEEMITTERTIME
        uvTime = cEmitterTime;
    #endif

    vTexCoordDiff = GetFinalUV(texCoord, cDiffSin, cDiffCos, cUScalar, cVScalar, cUSpeed * uvTime, cVSpeed * uvTime);

    #ifdef USEMASK
        vTexCoordMask = GetFinalUV(texCoord, cMaskSin, cMaskCos, cMaskUScalar, cMaskVScalar, cMaskUSpeed * uvTime, cMaskVSpeed * uvTime);
    #endif

    #ifdef DISSOLVE
        vTexCoordDissolve = GetFinalUV(texCoord, cDissolveSin, cDissolveCos, cDissolveUScalar, cDissolveVScalar, cDissolveUSpeed * uvTime, cDissolveVSpeed * uvTime);
        vDissolve = cDissolve;
    #endif

    #ifdef PLANESOFTPARTICLE
        vPlanePosZ = cPlanePosZ;
    #endif
}

void PS()
{       
    #ifdef DIFFMAP
        #ifdef NOT_SUPPORT_SRGB
            vec4 diffInput = GammaToLinearSpace(texture2D(sDiffMap,  vTexCoordDiff));
        #else
            vec4 diffInput = texture2D(sDiffMap,  vTexCoordDiff);         
        #endif
        #ifdef ALPHAMASK
            if (diffColor.a < 0.5)
                discard;
        #endif
        vec4 diffColor = cMatDiffColor * diffInput;
    #else
        vec4 diffColor = cMatDiffColor;
    #endif

    #ifdef VERTEXCOLOR
        diffColor *= vColor;
    #endif

    #ifdef USEMASK
    	float maskColor = texture2D(sSpecMap, vTexCoordMask).r;
    	diffColor.a = clamp(diffColor.a * maskColor, 0.0, 1.0);
    #endif

    #ifdef USEFRESNEL
        hvec3 _WorldPos = vWorldPos.xyz;
        vec3 viewDirection = normalize(cCameraPosPS - _WorldPos);
        vec3 normalDirection = normalize(vNormal);
    
        float NdotV = clamp(dot(normalDirection, viewDirection), M_EPSILON, 1.0);
        float fresnel = 1.0 - NdotV;
    
        diffColor.rgb = diffColor.rgb * pow(fresnel, cFresnelExpo);
        diffColor.a *= fresnel;
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    // Soft particle fade
    // In expand mode depth test should be off. In that case do manual alpha discard test first to reduce fill rate
  
    #ifdef SOFTPARTICLES
        #ifdef EXPAND
            if (diffColor.a < 0.01)
                discard;
        #endif

        float particleDepth = vWorldPos.w;
        #ifdef HWDEPTH
            float depth = ReconstructDepth(texture2DProj(sDepthBuffer, vScreenPos).r);
        #else
            float depth = DecodeDepth(texture2DProj(sDepthBuffer, vScreenPos).rgb);
        #endif

        #ifdef EXPAND
            float diffZ = max(particleDepth - depth, 0.0) * (cFarClipPS - cNearClipPS);
            float fade = clamp(diffZ * cSoftParticleFadeScale, 0.0, 1.0);
        #else
            float diffZ = (depth - particleDepth) * (cFarClipPS - cNearClipPS);
            float fade = clamp(1.0 - diffZ * cSoftParticleFadeScale, 0.0, 1.0);
        #endif

        #ifndef ADDITIVE
            diffColor.a = max(diffColor.a - fade, 0.0);
        #else
            diffColor.rgb = max(diffColor.rgb - fade, vec3(0.0, 0.0, 0.0));
        #endif
    #endif
   
    
    #ifdef UE3SOFTPARTICLE
        #ifdef EXPAND
            if (diffColor.a < 0.01)
                discard;
        #endif

        float particleDepth = vWorldPos.w;
        #ifdef HWDEPTH
            float depth = ReconstructDepth(texture2DProj(sNormalMap, vScreenPos).r);
        #else
            float depth = DecodeDepth(texture2DProj(sNormalMap, vScreenPos).rgb);
        #endif

        float diffZ = max(depth - particleDepth, 0.0) * (cFarClipPS - cNearClipPS);
        float fade = clamp(diffZ * cSoftParticleFadeScale, 0.0, 1.0);
        diffColor.a *= fade;
    #endif

    #ifdef PLANESOFTPARTICLE
        float diffZ = max(__GET_HEIGHT__(vWorldPos) - vPlanePosZ, 0.0);
        float fade = clamp(diffZ / cSoftFadeHeight, 0.0, 1.0);
        diffColor.a *= (fade * fade);
    #endif
    
    vec4 finalColor = vec4(GetFog(diffColor.rgb, fogFactor), diffColor.a);

    #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
	    finalColor.rgb = LinearToGammaSpace(toAcesFilmic(finalColor.rgb));
    #elif defined(TONEMAP_IN_SHADERING)
        finalColor.rgb = toAcesFilmic(finalColor.rgb);
	#endif

   #ifdef DISSOLVE
        float dissolveSample = texture2D(sEmissiveMap, vTexCoordDissolve).r * cTexMultiply;
        float dissolveK = saturate(cSmooth * dissolveSample - mix(cSmooth,-1.0,vDissolve));
        //int dissolveK = (int(sign(dissolveSample - cDissolve))+1)/2;
        finalColor.a = dissolveK * finalColor.a;
        if (finalColor.a < 0.001)
                discard;
   #endif

   #ifdef VDM_PARTICLE
        float depth = vWorldPos.w;
        gl_FragData[0] = finalColor;
        gl_FragData[1] = vec4(depth, depth * depth, 1.0, 1.0);
   #else
        gl_FragColor = finalColor; 
   #endif
}
