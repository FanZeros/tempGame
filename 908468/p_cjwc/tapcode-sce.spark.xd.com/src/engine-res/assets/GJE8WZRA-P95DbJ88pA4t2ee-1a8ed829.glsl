#include "varying_scenepass.def.sc"
#include "urho3d_compatibility.sh"
#include "constants.sh"
// 用了_INSTANCE2, _INSTANCE已经被占用了
#ifdef INSTANCED
    #define _INSTANCED2 , i_data0, i_data1, i_data2, i_data3, i_data4, i_data5
#else
    #define _INSTANCED2
#endif

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
    $input a_position, a_color0, a_normal, a_texcoord0 _INSTANCED2
    $output vTexCoordDiff _VTEXCOORDMASK _VTEXCOORDDISSOLVE vWorldPos, vColor _VSCREENPOS, vNormal _VDISSOLVE _PLANEPOSZ
#endif
#ifdef COMPILEPS
    $input vTexCoordDiff _VTEXCOORDMASK _VTEXCOORDDISSOLVE vWorldPos, vColor _VSCREENPOS, vNormal _VDISSOLVE _PLANEPOSZ
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#include "screen_pos.sh"
#include "lighting.sh"
#include "fog.sh"

#ifdef COMPILEVS
#ifdef INSTANCED
    #define cColorInstance i_data3
    #define cUVInstance i_data4
    #define cEmitterTime (i_data5.x)
#else
	uniform vec4 u_ColorInstance;
	uniform vec4 u_UVInstance;
    uniform vec4 u_EmitterTime;
    #define cColorInstance u_ColorInstance
    #define cUVInstance u_UVInstance
    #define cEmitterTime (u_EmitterTime.x)
#endif
#endif

#if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE)
    uniform float u_SoftParticleFadeScale;
#endif

uniform hvec4 u_uvDiffParams;
uniform vec4 u_TexRotate1;
uniform vec4 u_TexRotate2;

#define cSoftParticleFadeScale u_SoftParticleFadeScale
#define cUScalar (u_uvDiffParams.x)
#define cVScalar (u_uvDiffParams.y)
#define cUSpeed (u_uvDiffParams.z)
#define cVSpeed (u_uvDiffParams.w)

#define cDiffSin (u_TexRotate1.x)
#define cDiffCos (u_TexRotate1.y)
#define cMaskSin (u_TexRotate1.z)
#define cMaskCos (u_TexRotate1.w)
#define cDissolveSin (u_TexRotate2.x)
#define cDissolveCos (u_TexRotate2.y)

#ifdef USEMASK
    uniform vec4 u_uvMaskParams;
    #define cMaskUScalar (u_uvMaskParams.x)
    #define cMaskVScalar (u_uvMaskParams.y)
    #define cMaskUSpeed (u_uvMaskParams.z)
    #define cMaskVSpeed (u_uvMaskParams.w)
#endif

#ifdef DISSOLVE
    #ifdef INSTANCED
        #define cDissolve (i_data5.y)
    #else
        #define cDissolve (u_EmitterTime.y)
    #endif
    uniform float u_TexMultiply;
    uniform float u_Smooth;
    uniform vec4 u_uvDissolveParams;
    #define cTexMultiply u_TexMultiply
    #define cSmooth u_Smooth
    #define cDissolveUScalar (u_uvDissolveParams.x)
    #define cDissolveVScalar (u_uvDissolveParams.y)
    #define cDissolveUSpeed (u_uvDissolveParams.z)
    #define cDissolveVSpeed (u_uvDissolveParams.w)
#endif

#ifdef PLANESOFTPARTICLE
    #ifdef INSTANCED
        #define cPlanePosZ (i_data5.z)
    #else
        #define cPlanePosZ (u_EmitterTime.z)
    #endif
    uniform float u_SoftFadeHeight;
    #define cSoftFadeHeight u_SoftFadeHeight
#endif


#ifdef USENOISE
    // 先支持顶点扰动 后面可以提供顶点扰动与纹理扰动的选择
    // #define USENOISE_V
    // #define USENOISE_P
    
    #ifdef COMPILEVS
    SAMPLER2D(u_NormalMap, 1);
    #define sNormalMap u_NormalMap
    #endif    
    
    //噪波图 这里利用的是法线贴图通道 后面Noise如果需要通用化再统一增加新通道
    // SAMPLER2D(u_NoiseMap6, 6);
    #define sNoiseMap sNormalMap
    
    uniform vec4 u_uvNoiseParams;
	uniform float u_NoiseIntensity;
    // uniform u_NoiseRotation; //TODO:基于极坐标的漩涡效果
    #define cNoiseUScaler (u_uvNoiseParams.x)
    #define cNoiseVScalar (u_uvNoiseParams.y)
    #define cNoiseUSpeed (u_uvNoiseParams.z)
    #define cNoiseVSpeed (u_uvNoiseParams.w)
    #define cNoiseIntensity (u_NoiseIntensity)
    #define cNoiseSin (u_TexRotate1.x) // 与diffuse旋转一致
    #define cNoiseCos (u_TexRotate1.y) // 与diffuse旋转一致
    
    // #define _VTEXCOORDNOISE , vTexCoordNoise
// #else
    // #define _VTEXCOORDNOISE
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
    float uvTime = cElapsedTime;

    // 先行计算UV BEGIN 
    #ifdef CEINSTANCEMESH
	    vec2 TexCoord = iTexCoord;
        TexCoord = GetTexCoord(iTexCoord);
    #else
        vec2 TexCoord;
        TexCoord.x = cUVInstance.x + (cUVInstance.z-cUVInstance.x)*iTexCoord.x;
        TexCoord.y = cUVInstance.y + (cUVInstance.w-cUVInstance.y)*iTexCoord.y;
    #endif
    // 先行计算UV END 

    // 顶点局部坐标变换 BEGIN
    #ifdef USENOISE
        float noiseUCycleTime = fmod(uvTime, 1 / max(M_EPSILON, abs(cNoiseUSpeed)));
        float noiseVCycleTime = fmod(uvTime, 1 / max(M_EPSILON, abs(cNoiseVSpeed)));
        vec2 vTexCoordNoise = GetFinalUV(TexCoord, cNoiseSin, cNoiseCos, cNoiseUScaler, cNoiseVScalar, cNoiseUSpeed * noiseUCycleTime, cNoiseVSpeed * noiseVCycleTime);
        vec3 vertexValue = iNormal * texture2DLod(sNoiseMap, vTexCoordNoise, 0.0).r * u_NoiseIntensity;
        iPos.xyz += vertexValue;
    #endif
    // 顶点局部坐标变换 END

    // 顶点世界坐标变换+顶点色应用 BEGIN
    //--- CEInstanceMesh version code Begin
    #ifdef CEINSTANCEMESH
        hmat4 modelMatrix = iModelMatrix;
        //对于merge的，先将旋转和scale信息清除，这样在GetWorldPos函数中才能正确算出mirror位置
        modelMatrix[0][0] = 1;
        modelMatrix[0][1] = 0;
        modelMatrix[0][2] = 0;
        
        modelMatrix[1][0] = 0;
        modelMatrix[1][1] = 1;
        modelMatrix[1][2] = 0;
        
        modelMatrix[2][0] = 0;
        modelMatrix[2][1] = 0;
        modelMatrix[2][2] = 1;
        
        modelMatrix[3][0] = 0;
        modelMatrix[3][1] = 0;
        modelMatrix[3][2] = 0;
        modelMatrix[3][3] = 1;

        hvec3 worldPos = GetWorldPos(modelMatrix);

        gl_Position = GetClipPos(worldPos);
        vWorldPos = vec4(worldPos, GetDepth(gl_Position));
        vColor = iColor;
        #if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE)
            vScreenPos = GetScreenPos(gl_Position);
        #endif
    #else
    //--- CEInstanceMesh version code End
        hmat4 modelMatrix = iModelMatrix;
        hvec3 worldPos = GetWorldPos(modelMatrix);
        gl_Position = GetClipPos(worldPos);
        vWorldPos = vec4(worldPos, GetDepth(gl_Position));

	    vColor = vec4(1.0,1.0,1.0,1.0);

        #ifdef VERTEXCOLOR
            vColor = iColor;
        #endif

        #if defined(SOFTPARTICLES) || defined(UE3SOFTPARTICLE)
            vScreenPos = GetScreenPos(gl_Position);
        #endif
    
	    vColor *= cColorInstance;
    #endif
    // 顶点世界坐标变换+顶点色应用 END

    #ifdef USEFRESNEL
        vNormal = GetWorldNormal(modelMatrix);
    #endif

    #ifdef CEINSTANCEMESH //这个宏估计没地方设了，先放着吧
        float uOffset = cUSpeed * uvTime;
        float vOffset = cVSpeed * uvTime;
    #else
        float uOffset = cUSpeed * cEmitterTime;
        float vOffset = cVSpeed * cEmitterTime;
    #endif
    vTexCoordDiff = GetFinalUV(TexCoord, cDiffSin, cDiffCos, cUScalar, cVScalar, uOffset, vOffset);

    #ifdef USEMASK
        vTexCoordMask = GetFinalUV(TexCoord, cMaskSin, cMaskCos, cMaskUScalar, cMaskVScalar, cMaskUSpeed * uvTime, cMaskVSpeed * uvTime);
    #endif

    #ifdef DISSOLVE
        vDissolve = cDissolve;
        vTexCoordDissolve = GetFinalUV(TexCoord, cDissolveSin, cDissolveCos, cDissolveUScalar, cDissolveVScalar, cDissolveUSpeed * uvTime, cDissolveVSpeed * uvTime);
    #endif

    #ifdef PLANESOFTPARTICLE
        vPlanePosZ = cPlanePosZ;
    #endif
}

void PS()
{   
    // Get material diffuse albedo
    #ifdef DIFFMAP
        #ifdef NOT_SUPPORT_SRGB
            vec4 diffColor = cMatDiffColor * GammaToLinearSpace(texture2D(sDiffMap, vTexCoordDiff));
        #else
            vec4 diffColor = cMatDiffColor * texture2D(sDiffMap, vTexCoordDiff);
        #endif
        #ifdef ALPHAMASK
            if (diffColor.a < 0.5)
                discard;
        #endif
    #else
        vec4 diffColor = cMatDiffColor;
    #endif
    
    diffColor *= vColor;

    #ifdef USEMASK
    	float maskColor = texture2D(sSpecMap, vTexCoordMask).r;
    	diffColor.a = clamp(diffColor.a * maskColor, 0.0, 1.0);
    #endif

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    #ifndef CLOSESOFT
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
    #endif

    #ifdef PLANESOFTPARTICLE
        float diffZ = max(__GET_HEIGHT__(vWorldPos) - vPlanePosZ, 0.0);
        float fade = clamp(diffZ / cSoftFadeHeight, 0.0, 1.0);
        diffColor.a *= (fade * fade);
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

    // Dissolve 是可见性裁剪而非颜色修饰，必须在 DEFERRED/forward 分支之前执行：
    // deferred 下溶解掉的片元靠 discard 使 GBuffer/Pre-Z 写入作废，否则消失的部分
    // 仍是实体、还会遮挡后方几何（forward 侧数值不变：finalColor.a 即 diffColor.a）
    #ifdef DISSOLVE
        float dissolveSample = texture2D(sEmissiveMap, vTexCoordDissolve).r * cTexMultiply;
        float dissolveK = saturate(cSmooth * dissolveSample - mix(cSmooth,-1.0,vDissolve));
        //int dissolveK = (int(sign(dissolveSample - cDissolve))+1)/2;
        diffColor.a *= dissolveK;
        if (diffColor.a < 0.001)
            discard;
    #endif

    #if defined(MATERIALBAKE)
        EncodeGBufferBake(diffColor.rgb, diffColor.a, 0.85, 0.0, 1.0, GBufferFaceNormal(vWorldPos.xyz, cCameraPosPS), vec3_splat(0.0));
    #elif defined(DEFERRED)
        // Unlit 直通编码（shadingModelID=0）。不带雾、不做 gamma/tonemap——
        // 延迟管线是线性 HDR，雾由 SceneFog quad 统一施加。
        // 旧分支写完 GBuffer 后还会掉进下面的 finalColor 尾部逻辑覆写 RT0/RT1，
        // 因此 gamma/VDM 尾部收进 forward 分支（dissolve 见上，两条路径共用）
        EncodeGBufferUnlit(diffColor.rgb, GBufferFaceNormal(vWorldPos.xyz, cCameraPosPS));
    #else
        vec4 finalColor = vec4(GetFog(diffColor.rgb, fogFactor), diffColor.a);

        #if defined(GAMMA_IN_SHADERING) || defined(USEGAMMA)
            finalColor.rgb = LinearToGammaSpace(toAcesFilmic(finalColor.rgb));
        #elif defined(TONEMAP_IN_SHADERING)
            finalColor.rgb = toAcesFilmic(finalColor.rgb);
        #endif

        #ifdef VDM_PARTICLE
            float depth = vWorldPos.w;
            gl_FragData[0] = finalColor;
            gl_FragData[1] = vec4(depth, depth * depth, 1.0, 1.0);
        #else
            gl_FragColor = finalColor;
        #endif
    #endif
}

