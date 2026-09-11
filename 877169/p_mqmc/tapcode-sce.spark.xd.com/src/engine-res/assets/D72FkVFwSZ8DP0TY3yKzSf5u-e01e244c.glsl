#include "varying_shadow.def.sc"
#include "urho3d_compatibility.sh"
#ifdef COMPILEVS
    $input a_position  _NORMAL _TEXCOORD0 _COLOR0 _TEXCOORD1 _ATANGENT _SKINNED _INSTANCED _INSTANCED_EXTRA1 _INSTANCED_EXTRA3
    $output vTexCoord, vWorldPos, vNodePos
#endif
#ifdef COMPILEPS
    $input vTexCoord, vWorldPos, vNodePos
#endif

#include "Common/common.sh"

#include "uniforms.sh"
#include "samplers.sh"
#include "transform.sh"
#ifdef SPEED_TREE
#include "Tile/WindEffect.sh"
#endif
#include "fog.sh"

void VS()
{
    hmat4 modelMatrix = iModelMatrix;
    hvec3 worldPos = GetWorldPos(modelMatrix);

    // // Project to plane
    // hvec3 _nodePos = iNodePosition;
    // // x, y表示物体2d位置，z表示物体所在地板的高度，w表示物体最高的部分离地高度（头顶离地高度）
    // hvec4 nodePos = hvec4_init(_nodePos.x, _nodePos.y, iGroundZ, min(iBBoxMaxZ - _nodePos.z, iBBoxMaxZ - iGroundZ));

    // 为了优化多个Drawable挂在同一个Node下阴影表现一致，重写了nodePos相关的逻辑
    // iGroundZ、iBBoxMaxZ、iBBoxMinZ、iObjectType的含义已经不是变量字面的意思了
    // iGroundZ：   Drawable所属单位的坐标X
    // iBBoxMaxZ:   Drawable所属单位的坐标Y
    // iBBoxMinZ:   Drawable所属单位在地板上坐标Z（贴地）
    // iObjectType: Drawable所属单位可投射阴影的长度（min(BBoxMaxz - NodePosZ, BBoxMaxZ - GroundZ)）
    hvec4 nodePos = hvec4_init(iGroundZ, iBBoxMaxZ, iBBoxMinZ, iObjectType);

    float height = nodePos.z;
    float opposite = worldPos.z - height;
    float cosTheta = -cLightDir.z;
    float hypotenuse = opposite / cosTheta;
    worldPos += cLightDir.xyz * hypotenuse;

    hvec3 eye = nodePos.xyz - cCameraPos;
    worldPos.z += sqrt(dot(eye, eye)) / 500.0;

    gl_Position = GetClipPos(worldPos);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vNodePos = nodePos;
    vTexCoord = GetTexCoord(iTexCoord);
}

void PS()
{
    float alpha;
    #ifdef ALPHAMASK
        #if defined(GRAYLEVEL_TWO) || defined(GRAYLEVEL_FIVE) || defined(UNIVERSAL)
            alpha = texture2D(sDiffMap, vTexCoord.xy).a;
        #else
            alpha = texture2D(sDiffMap, vTexCoord.xy).b;
        #endif
        if (alpha < 0.5)
            discard;
    #endif

    float _ShadowInvLen = 1.0 / (vNodePos.w * 1.5);
    vec4 _ShadowFadeParams = vec4(0.0, 1.5, 0.7, 0);

    vec3 deltaPos = vWorldPos.xyz - vNodePos.xyz;
    float len = sqrt(dot(deltaPos, deltaPos));
    alpha = max(pow(1.0 - clamp(len * _ShadowInvLen - _ShadowFadeParams.x, 0.0, 1.0), _ShadowFadeParams.y) * _ShadowFadeParams.z, 0.1);

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(distance(vWorldPos.xyz, cCameraPosPS), __GET_HEIGHT__(vWorldPos));
    #else
        float fogFactor = GetFogFactor(distance(vWorldPos.xyz, cCameraPosPS));
    #endif

    // Mix final color and fog
    gl_FragColor = vec4(GetFog(vec3(0.0, 0.0, 0.0), fogFactor), alpha);
}
