
uniform hvec4 u_PlayerPosAndRadius;
uniform hvec2 u_OrthoSize;
#ifdef COMPILEPS
uniform vec4 u_ShadowColor;
uniform hvec4 u_SkillDirAndRadius;
uniform hvec2 u_SkillCosAngleAndSoftRadius;
#define cSkillCosAngle u_SkillCosAngleAndSoftRadius.x
#define cSoftRadius u_SkillCosAngleAndSoftRadius.y

void CheckSkillDiscard(hvec2 pos)
{
    hvec2 offset = pos - u_PlayerPosAndRadius.xy;
    float cosTheta = dot(normalize(offset), u_SkillDirAndRadius.xy);
    float cosRange = cSkillCosAngle;
    if(dot(offset, offset) < u_SkillDirAndRadius.w * u_SkillDirAndRadius.w && cosRange > 0.0 && cosTheta > cosRange)
        discard;
}
#endif