// Rect area light support
// Diffuse: Karis approximation (UE RectIrradianceApproxKaris)
// Specular: LTC (Linearly Transformed Cosines, Heitz et al. 2016)

// LTC combined texture: slot 9, 64x128 atlas (top half = Mat, bottom half = Amp)
#ifndef URHO3D_MOBILE
SAMPLER2D(u_LTCCombined9, 9);
#define sLTCCombined u_LTCCombined9
#else
SAMPLER2D(u_LTCCombined7, 7);
#define sLTCCombined u_LTCCombined7
#endif

// ── Barn Door: GetRect (strict port of UE RectLight.ush:721-809) ──
// Computes the visible rectangle after barn door clipping for a given shading point.
// Modifies origin (L), halfWidth, halfHeight in-place via out parameters.

void GetRect(
    hvec3 toLight, hvec3 ax0, hvec3 ax1, hvec3 ax2,
    hfloat halfWidth, hfloat halfHeight,
    hfloat barnCosAngle, hfloat barnLength,
    out hvec3 outOrigin, out hfloat outHalfWidth, out hfloat outHalfHeight)
{
    outOrigin = toLight;
    outHalfWidth = halfWidth;
    outHalfHeight = halfHeight;

    // Only compute if barn door angle < 88 degrees (cosAngle > 0.035)
    if (barnCosAngle > 0.035)
    {
        hvec3 lightdPdv = -ax1;
        hvec3 lightdPdu = -ax0;
        hvec2 lightExtent = hvec2_init(halfWidth, halfHeight);

        // Project shading point into light local space.
        // Axis pairing follows lightExtent = (halfWidth, halfHeight):
        // ax0 = width axis (tangent), ax1 = height axis (bitangent), ax2 = plane normal —
        // same as UE Rect.Axis[0..2] vs Rect.Extent. Swapping ax0/ax1 makes barn doors
        // clip the long side of non-square lights by the short extent.
        hvec3 S_Light = hvec3_init(dot(ax0, toLight), dot(ax1, toLight), dot(ax2, toLight));

        // Barn door projection
        hfloat CosTheta = barnCosAngle;
        hfloat SinTheta = sqrt(1.0 - CosTheta * CosTheta);
        hfloat BarnDepth = min(S_Light.z, CosTheta * barnLength);
        hfloat S_ratio = BarnDepth / max(0.0001, CosTheta * barnLength);
        hfloat D_B = SinTheta * barnLength * S_ratio;

        // Clamp shading point onto closest edge if inside rect
        hvec2 SignS = sign(S_Light.xy);
        S_Light.xy = SignS * max(abs(S_Light.xy), lightExtent + hvec2_init(D_B, D_B));

        // Closest rect corner offset by barn door size
        hvec3 C = hvec3_init(SignS.x * (lightExtent.x + D_B), SignS.y * (lightExtent.y + D_B), BarnDepth);

        // Projected distance of barn door onto rect light
        hvec3 SProj = S_Light - C;
        hfloat CosEta = max(SProj.z, 0.001);
        hvec2 TanEta = abs(SProj.xy) / CosEta;
        hvec2 D_S = hvec2_init(BarnDepth, BarnDepth) * TanEta;

        // Compute clipped rect bounds
        hvec2 MinXY = clamp(-lightExtent + (D_S - hvec2_init(D_B, D_B)) * max(hvec2_init(0.0, 0.0), -SignS), -lightExtent, lightExtent);
        hvec2 MaxXY = clamp( lightExtent - (D_S - hvec2_init(D_B, D_B)) * max(hvec2_init(0.0, 0.0),  SignS), -lightExtent, lightExtent);
        hvec2 RectOffset = 0.5 * (MinXY + MaxXY);

        outHalfWidth  = 0.5 * (MaxXY.x - MinXY.x);
        outHalfHeight = 0.5 * (MaxXY.y - MinXY.y);
        outOrigin = toLight + lightdPdu * RectOffset.x + lightdPdv * RectOffset.y;
    }
}

// ── SmoothClamp (from UE CapsuleLight.ush) ──

hfloat RectSmoothMin(hfloat a, hfloat b, hfloat k)
{
    hfloat h = saturate(0.5 + (0.5 / k) * (b - a));
    return mix(b, a, h) - k * (h - h * h);
}

hfloat RectSmoothMax(hfloat a, hfloat b, hfloat k)
{
    return RectSmoothMin(a, b, -k);
}

hfloat RectSmoothClamp(hfloat x, hfloat lo, hfloat hi, hfloat k)
{
    return RectSmoothMin(RectSmoothMax(x, lo, k), hi, k);
}

// ── Karis Diffuse (from UE RectIrradianceApproxKaris) ──

hvec3 RectIrradianceKaris(hvec3 origin, hvec3 normal, hvec3 ax0, hvec3 ax1, hvec3 ax2,
                          hfloat extX, hfloat extY, out hfloat baseIrradiance, out hfloat outNdotL)
{
    // k must be proportional to rect size (UE uses k=16 with cm units, we use meters)
    hfloat smoothK = max(extX, extY) * 0.5;
    hfloat localX = RectSmoothClamp(dot(ax0, -origin), -extX, extX, smoothK);
    hfloat localY = RectSmoothClamp(dot(ax1, -origin), -extY, extY, smoothK);

    hvec3 closestPoint = origin + ax0 * localX + ax1 * localY;
    hvec3 oppositePoint = 2.0 * origin - closestPoint;

    hvec3 L0 = normalize(closestPoint);
    hvec3 L1 = normalize(oppositePoint);
    hvec3 L = normalize(L0 + L1);

    hfloat dist = dot(ax2, origin) / max(dot(ax2, L), 1e-6);
    hfloat distSqr = dist * dist;

    baseIrradiance = 4.0 * extX * extY *
        inversesqrt((1.2732 * extX * extX + distSqr) * (1.2732 * extY * extY + distSqr));
    baseIrradiance *= saturate(dot(ax2, L));

    hfloat sinAlphaSqr = baseIrradiance * M_INV_PI;
    outNdotL = SphereHorizonCosWrap(dot(normal, L), sinAlphaSqr);

    return L;
}

// ── LTC Edge Integration (from UE RectLight.ush) ──

hfloat LTCIntegrateEdge(hvec3 L0, hvec3 L1)
{
    hfloat c01 = dot(L0, L1);
    hfloat w01 = (0.8543985 + (0.4965155 + 0.0145206 * abs(c01)) * abs(c01)) / (3.4175940 + (4.1616724 + abs(c01)) * abs(c01));
    w01 = c01 > 0.0 ? w01 : 0.5 * inversesqrt(max(1.0 - c01 * c01, 1.0e-4)) - w01;
    return w01;
}

// LTC polygon irradiance for a quad (returns vector irradiance)
// Strict port of UE PolygonIrradiance (RectLight.ush:336-371)
hvec3 LTCPolygonIrradiance(hvec3 poly0, hvec3 poly1, hvec3 poly2, hvec3 poly3)
{
    hvec3 L0 = normalize(poly0);
    hvec3 L1 = normalize(poly1);
    hvec3 L2 = normalize(poly2);
    hvec3 L3 = normalize(poly3);

    hfloat w01 = LTCIntegrateEdge(L0, L1);
    hfloat w12 = LTCIntegrateEdge(L1, L2);
    hfloat w23 = LTCIntegrateEdge(L2, L3);
    hfloat w30 = LTCIntegrateEdge(L3, L0);

    hvec3 irr;
    irr  = cross(L1, -w01 * L0 + w12 * L2);
    irr += cross(L3,  w30 * L0 - w23 * L2);
    return irr;
}

// ── LTC Specular for GGX ──
// Strict port of UE GetRectLTC_GGX + RectApproxLTC (RectLight.ush:380-536)
// No SourceTexture support (Phase 1)

hvec3 RectSpecularLTC(hvec3 L, hvec3 normal, hvec3 viewDirection, hvec3 specularColor,
                      hfloat roughness, hvec3 ax0, hvec3 ax1, hvec3 ax2,
                      hfloat halfWidth, hfloat halfHeight)
{
    // ── GetRectLTC_GGX ──
    hfloat NoV = saturate(abs(dot(normal, viewDirection)) + 1e-5);

    hvec2 ltcUV = hvec2_init(roughness, sqrt(1.0 - NoV));
    ltcUV = ltcUV * (63.0 / 64.0) + (0.5 / 64.0);

    // Sample LTC combined atlas: top half = Mat (y 0..0.5), bottom half = Amp (y 0.5..1.0)
    hvec2 matUV = hvec2_init(ltcUV.x, ltcUV.y * 0.5);
    hvec2 ampUV = hvec2_init(ltcUV.x, ltcUV.y * 0.5 + 0.5);
    hvec4 ltcMat = texture2D(sLTCCombined, matUV);
    hvec4 ltcAmp = texture2D(sLTCCombined, ampUV);

    // LTC matrix (UE RectLight.ush:389-393)
    // LTC = | a  0  b |    a=ltcMat.x, b=ltcMat.z, c=ltcMat.y, d=ltcMat.w
    //       | 0  1  0 |
    //       | c  0  d |
    hfloat ma = ltcMat.x, mb = ltcMat.z, mc = ltcMat.y, md = ltcMat.w;

    // Inverse LTC matrix (UE RectLight.ush:395-402)
    hfloat ltcDet = ma * md - mc * mb;
    hfloat invDet = 1.0 / ltcDet;
    hfloat ima = md * invDet, imb = -mb * invDet, imc = -mc * invDet, imd = ma * invDet;

    // Fresnel scaling (UE RectLight.ush:407)
    hvec3 F0 = specularColor;
    hvec3 F90 = saturate(hvec3_init(50.0, 50.0, 50.0) * specularColor);
    hvec3 irrScale = F90 * ltcAmp.y + (ltcAmp.x - ltcAmp.y) * F0;

    // ── RectApproxLTC ──

    // Tangent frame (UE RectLight.ush:465-466)
    hvec3 T1 = normalize(viewDirection - normal * dot(normal, viewDirection));
    hvec3 T2 = cross(normal, T1);

    // Combined LTC * TangentBasis transform, applied per-component to avoid mat3 issues
    // TangentBasis * v = (dot(T1,v), dot(T2,v), dot(N,v))
    // LTC * t = (ma*t.x + mb*t.z, t.y, mc*t.x + md*t.z)
    #define LTC_FWD(v) hvec3_init( \
        ma * dot(T1, v) + mb * dot(normal, v), \
        dot(T2, v), \
        mc * dot(T1, v) + md * dot(normal, v))

    // Transform rect corners (UE RectLight.ush:472-476)
    hvec3 p0 = LTC_FWD(L - ax0 * halfWidth - ax1 * halfHeight);
    hvec3 p1 = LTC_FWD(L + ax0 * halfWidth - ax1 * halfHeight);
    hvec3 p2 = LTC_FWD(L + ax0 * halfWidth + ax1 * halfHeight);
    hvec3 p3 = LTC_FWD(L - ax0 * halfWidth + ax1 * halfHeight);
    #undef LTC_FWD

    // Polygon irradiance in LTC space (UE RectLight.ush:479)
    hvec3 irrVec = LTCPolygonIrradiance(p0, p1, p2, p3);

#if 0
    // ── UE approach (RectLight.ush:490-506) ──
    // Uses SphereHorizonCosWrap for horizon-aware NdotL.
    // Can produce hollow diamond artifact when polygon straddles z=0 plane in LTC space.
    hfloat LengthSqr = dot(irrVec, irrVec);
    hfloat InvLength = inversesqrt(LengthSqr);
    hfloat Length = LengthSqr * InvLength;
    hvec3 Ldir = irrVec * InvLength;
    hfloat SinAlphaSqr = Length;
    hfloat NoL = SphereHorizonCosWrap(Ldir.z, SinAlphaSqr);
    hfloat irradiance = SinAlphaSqr * NoL;
    irradiance = -min(-irradiance, 0.0); // Kill negative and NaN
#else
    // ── Three.js approach ──
    // irrVec.z is the cosine-weighted irradiance integral (normal-direction component).
    // Simpler, no hollow diamond artifact, no SphereHorizonCosWrap needed.
    hfloat irradiance = max(0.0, irrVec.z);
#endif

    return irradiance * irrScale;
}

// ── Core BRDF ──

hvec3 GetRectLightBRDF(hvec3 worldPos, hvec3 normal, hvec3 viewDirection,
                       hvec3 diffuseColor, hvec3 specularColor, hfloat roughness, hfloat perceptualRoughness,
                       hvec3 lightPos, hvec3 lightDir, hvec3 lightTangent,
                       hfloat halfWidth, hfloat halfHeight,
                       hfloat barnCosAngle, hfloat barnLength)
{
    // rectNormal = inward plane normal (UE Rect.Axis[2] convention, opposite to emission direction)
    hvec3 rectNormal = -lightDir;
    hvec3 bitangent = cross(lightTangent, rectNormal);
    hvec3 L = lightPos - worldPos;

    // Back-face cull: shading point must be on emitting side
    hfloat faceDot = dot(lightDir, -L);
    if (faceDot <= 0.0)
        return hvec3_init(0.0, 0.0, 0.0);

    // ── Barn Door clipping (UE GetRect, RectLight.ush:721-809) ──
    hvec3 clippedL;
    hfloat clippedHW, clippedHH;
    GetRect(L, lightTangent, bitangent, rectNormal,
            halfWidth, halfHeight, barnCosAngle, barnLength,
            clippedL, clippedHW, clippedHH);

    // Fully occluded by barn doors
    if (clippedHW <= 0.0 || clippedHH <= 0.0)
        return hvec3_init(0.0, 0.0, 0.0);

    // ── Diffuse: Karis approximation (uses clipped rect) ──
    hfloat baseIrradiance;
    hfloat NdotL_diff;
    RectIrradianceKaris(clippedL, normal, lightTangent, bitangent, rectNormal,
                        clippedHW, clippedHH, baseIrradiance, NdotL_diff);

    hvec3 diff = diffuseColor * M_INV_PI * baseIrradiance * NdotL_diff;

    // ── Specular: LTC (uses clipped rect) ──
    // No extra NoL multiply: the LTC clamped-cosine base already integrates the cosine
    // over the polygon (UE RectApproxLTC / Three.js both return the integral directly);
    // multiplying by center-direction NoL would double-attenuate grazing highlights.
    hvec3 spec = RectSpecularLTC(clippedL, normal, viewDirection, specularColor,
                                 roughness, lightTangent, bitangent, rectNormal,
                                 clippedHW, clippedHH);

    return diff + spec;
}

// ── Cluster path entry ──

#if NONPUNCTUAL_LIGHTING && defined(CLUSTER)
vec3 GetRectLighting(RectLight light, vec3 worldPos, vec3 normal, vec3 viewDirection,
                     vec3 diffuseColor, vec3 specularColor, float roughness, float perceptualRoughness)
{
    hvec3 L = light.position - worldPos;
    hfloat distSqr = dot(L, L);
    // RectLight: only range windowing, no 1/distSqr here.
    // Distance falloff is already in RectIrradianceKaris (baseIrradiance ~ area/r²)
    // and RectSpecularLTC (LTC integration). Adding 1/distSqr would cause 1/r⁴ double attenuation.
    hfloat falloff = GetLightRangeMask(light.range, distSqr);

    // Single-sided culling: binary like UE GetLocalLightAttenuation (dot < 0 ? 0 : mask).
    // The cosine term is already inside the Karis irradiance (saturate(dot(ax2, L))) —
    // multiplying a soft cosine here would double-attenuate off-axis shading points.
    hvec3 Ln = L / (sqrt(distSqr) + 1e-6);
    if (dot(light.direction, -Ln) <= 0.0 || falloff <= 0.0)
        return vec3_splat(0.0);

    vec3 brdf = GetRectLightBRDF(worldPos, normal, viewDirection,
                                  diffuseColor, specularColor, roughness, perceptualRoughness,
                                  light.position, light.direction, light.tangent,
                                  light.halfWidth, light.halfHeight,
                                  light.barnCosAngle, light.barnLength);

    return brdf * light.intensity * falloff;
}
#endif
