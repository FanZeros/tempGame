#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#define M_DEGTORAD_2 M_PI / 360.0

vec4 Q_fromAngle(float pitch, float roll, float yaw)
{
    pitch *= M_DEGTORAD_2;
    roll *= M_DEGTORAD_2;
    yaw *= M_DEGTORAD_2;
    float sinX = sin(pitch);
    float cosX = cos(pitch);
    float sinY = sin(roll);
    float cosY = cos(roll);
    float sinZ = sin(yaw);
    float cosZ = cos(yaw);

    float w = cosY * cosX * cosZ + sinY * sinX * sinZ;
    float x = cosY * sinX * cosZ + sinY * cosX * sinZ;
    float y = sinY * cosX * cosZ - cosY * sinX * sinZ;
    float z = cosY * cosX * sinZ - sinY * sinX * cosZ;
    return vec4(w, x, y, z);
}

// convert rotate matrix to quaternion
hvec4 Q_fromMatrix(hmat4 mat)
{
    hfloat t = mat[0][0] + mat[1][1] + mat[2][2];
    hfloat w, x, y, z;

    if (t > 0.0)
    {
        hfloat invS = 0.5 / sqrt(1.0 + t);

        x = (mat[2][1] - mat[1][2]) * invS;
        y = (mat[0][2] - mat[2][0]) * invS;
        z = (mat[1][0] - mat[0][1]) * invS;
        w = 0.25 / invS;
    }
    else
    {
        if (mat[0][0] > mat[1][1] && mat[0][0] > mat[2][2])
        {
            hfloat invS = 0.5 / sqrt(1.0 + mat[0][0] - mat[1][1] - mat[2][2]);

            x = 0.25 / invS;
            y = (mat[0][1] + mat[1][0]) * invS;
            z = (mat[2][0] + mat[0][2]) * invS;
            w = (mat[2][1] - mat[1][2]) * invS;
        }
        else if (mat[1][1] > mat[2][2])
        {
            hfloat invS = 0.5 / sqrt(1.0 + mat[1][1] - mat[0][0] - mat[2][2]);

            x = (mat[0][1] + mat[1][0]) * invS;
            y = 0.25 / invS;
            z = (mat[1][2] + mat[2][1]) * invS;
            w = (mat[0][2] - mat[2][0]) * invS;
        }
        else
        {
            hfloat invS = 0.5 / sqrt(1.0 + mat[2][2] - mat[0][0] - mat[1][1]);

            x = (mat[0][2] + mat[2][0]) * invS;
            y = (mat[1][2] + mat[2][1]) * invS;
            z = 0.25 / invS;
            w = (mat[1][0] - mat[0][1]) * invS;
        }
    }

    return vec4(w, x, y, z);
}

// convert quaternion to rotate matrix
hmat4 Q_toMatrix(hvec4 q)
{
    hfloat w = q.x;
    hfloat x = q.y;
    hfloat y = q.z;
    hfloat z = q.w;
    return mat4(
        1.0 - 2.0 * y * y - 2.0 * z * z, 2.0 * x * y - 2.0 * w * z, 2.0 * x * z + 2.0 * w * y, 0.0,
        2.0 * x * y + 2.0 * w * z, 1.0 - 2.0 * x * x - 2.0 * z * z, 2.0 * y * z - 2.0 * w * x, 0.0,
        2.0 * x * z - 2.0 * w * y, 2.0 * y * z + 2.0 * w * x, 1.0 - 2.0 * x * x - 2.0 * y * y, 0.0,
        0.0, 0.0, 0.0, 1.0
    );
}

vec4 Q_normalize(vec4 q)
{
    float lenSquared = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
    if (lenSquared != 1.0 && lenSquared > 0.0)
    {
        float invLen = 1.0 / sqrt(lenSquared);
        return q * invLen;
    }
    else
        return q;
}

// quaternion lerp
hvec4 Q_SLerp(hvec4 a, hvec4 b, hfloat t)
{
    hfloat cosAngle = dot(a, b);
    hfloat sign = 1.0;

    if (cosAngle < 0.0)
    {
        cosAngle = -cosAngle;
        sign = -1.0;
    }

    hfloat angle = acos(cosAngle);
    hfloat sinAngle = sin(angle);
    hfloat t1, t2;

    if (sinAngle > 0.001)
    {
        float invSinAngle = 1.0 / sinAngle;
        t1 = sin((1.0 - t) * angle) * invSinAngle;
        t2 = sin(t * angle) * invSinAngle;
    }
    else
    {
        t1 = 1.0 - t;
        t2 = t;
    }

    return a * t1 + (b * sign) * t2;
}