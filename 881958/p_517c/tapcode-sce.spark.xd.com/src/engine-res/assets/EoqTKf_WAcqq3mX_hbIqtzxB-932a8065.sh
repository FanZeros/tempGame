#include "PBR/PBRCommon.glsl"
#ifdef COMPILEPS
#include "PBR/GI.sh"
#include "PBR/ClearCoat.sh"      // 必须在 CapsuleLight.sh / Disney_BRDF 之前

// 非punctual 光（胶囊光 / 面光）Win下执行，其他平台 NONPUNCTUAL_LIGHTING 为false
// compute shader 不含本文件，那侧由引擎在 RENDER_QUALITY_FULL 时显式传入此宏。
#define NONPUNCTUAL_LIGHTING (RENDER_QUALITY > RENDER_QUALITY_HIGH)

#if defined (CLUSTER)
#include "Cluster/clusterlights.sh"
#include "Cluster/clusters.sh"
#endif


#if NONPUNCTUAL_LIGHTING
#include "PBR/CapsuleLight.sh"
#include "PBR/RectLight.sh"
#elif defined(RECTLIGHT)
#include "PBR/RectLight.sh"
#endif

// Product BRDF path is Disney only (Cook-Torrance optional chain removed).
#include "PBR/DisneyBRDF.glsl"
#define Standard_BRDF Disney_BRDF

// Split lighting support for reflection hierarchy system
#ifdef SPLIT_LIGHTING
#define Standard_BRDF_Split Disney_BRDF_Split
#endif // SPLIT_LIGHTING

#endif
