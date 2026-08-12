#pragma once

#include <cmath>

// Define our base scalar type for easy substitution later (e.g. to fixed point
// for RTL)
#include <ap_fixed.h>

// Generic float/double implementations
template <typename T> inline int math_floor(T val)
{
    return static_cast<int>(std::floor(val));
}

template <typename T> inline int math_ceil(T val)
{
    return static_cast<int>(std::ceil(val));
}

// Specializations for ap_fixed
template <int W, int I> inline int math_floor(ap_fixed<W, I> val)
{
    int i = val.to_int();
    if (val < 0 && val != ap_fixed<W, I>(i))
        return i - 1;
    return i;
}

template <int W, int I> inline int math_ceil(ap_fixed<W, I> val)
{
    int i = val.to_int();
    if (val > 0 && val != ap_fixed<W, I>(i))
        return i + 1;
    return i;
}

template <int W, int I> inline int math_floor(ap_ufixed<W, I> val)
{
    return val.to_int();
}

template <int W, int I> inline int math_ceil(ap_ufixed<W, I> val)
{
    int i = val.to_int();
    if (val > 0 && val != ap_ufixed<W, I>(i))
        return i + 1;
    return i;
}

template <typename T> struct tvec2
{
    T x, y;
    tvec2() : x(0), y(0)
    {
    }
    tvec2(T _x, T _y) : x(_x), y(_y)
    {
    }

    tvec2 operator+(const tvec2 &v) const
    {
        return tvec2(x + v.x, y + v.y);
    }
    tvec2 operator-(const tvec2 &v) const
    {
        return tvec2(x - v.x, y - v.y);
    }
    tvec2 operator*(T s) const
    {
        return tvec2(x * s, y * s);
    }
    tvec2 operator/(T s) const
    {
        return tvec2(x / s, y / s);
    }
};
using Vec2 = tvec2<float>;

template <typename T> struct tvec3
{
    T x, y, z;
    tvec3() : x(0), y(0), z(0)
    {
    }
    tvec3(T _x, T _y, T _z) : x(_x), y(_y), z(_z)
    {
    }

    tvec3 operator+(const tvec3 &v) const
    {
        return tvec3(x + v.x, y + v.y, z + v.z);
    }
    tvec3 operator-(const tvec3 &v) const
    {
        return tvec3(x - v.x, y - v.y, z - v.z);
    }
    tvec3 operator*(T s) const
    {
        return tvec3(x * s, y * s, z * s);
    }
    tvec3 operator/(T s) const
    {
        return tvec3(x / s, y / s, z / s);
    }

    T length() const
    {
        return std::sqrt(x * x + y * y + z * z);
    }
    tvec3 normalize() const
    {
        T l = length();
        return l > 0 ? (*this / l) : *this;
    }
};
using Vec3 = tvec3<float>;

template <typename T> struct tvec4
{
    T x, y, z, w;
    tvec4() : x(0), y(0), z(0), w(0)
    {
    }
    tvec4(T _x, T _y, T _z, T _w) : x(_x), y(_y), z(_z), w(_w)
    {
    }
    tvec4(const tvec3<T> &v, T _w) : x(v.x), y(v.y), z(v.z), w(_w)
    {
    }

    tvec4 operator+(const tvec4 &v) const
    {
        return tvec4(x + v.x, y + v.y, z + v.z, w + v.w);
    }
    tvec4 operator-(const tvec4 &v) const
    {
        return tvec4(x - v.x, y - v.y, z - v.z, w - v.w);
    }
    tvec4 operator*(T s) const
    {
        return tvec4(x * s, y * s, z * s, w * s);
    }
    tvec4 operator/(T s) const
    {
        return tvec4(x / s, y / s, z / s, w / s);
    }

    tvec3<T> xyz() const
    {
        return tvec3<T>(x, y, z);
    }
};
using Vec4 = tvec4<float>;

template <typename T> inline T dot(const tvec3<T> &a, const tvec3<T> &b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

template <typename T> inline tvec3<T> cross(const tvec3<T> &a, const tvec3<T> &b)
{
    return tvec3<T>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

// Column-major 4x4 matrix (OpenGL convention)
// m[col][row]
struct Mat4
{
    float m[4][4];

    Mat4()
    {
        for (int i = 0; i < 4; ++i)
            for (int j = 0; j < 4; ++j)
                m[i][j] = (i == j) ? 1.0f : 0.0f;
    }

    Mat4 operator*(const Mat4 &b) const
    {
        Mat4 res;
        for (int c = 0; c < 4; ++c)
        {
            for (int r = 0; r < 4; ++r)
            {
                res.m[c][r] = m[0][r] * b.m[c][0] + m[1][r] * b.m[c][1] + m[2][r] * b.m[c][2] + m[3][r] * b.m[c][3];
            }
        }
        return res;
    }

    Vec4 operator*(const Vec4 &v) const
    {
        return Vec4(m[0][0] * v.x + m[1][0] * v.y + m[2][0] * v.z + m[3][0] * v.w,
                    m[0][1] * v.x + m[1][1] * v.y + m[2][1] * v.z + m[3][1] * v.w,
                    m[0][2] * v.x + m[1][2] * v.y + m[2][2] * v.z + m[3][2] * v.w,
                    m[0][3] * v.x + m[1][3] * v.y + m[2][3] * v.z + m[3][3] * v.w);
    }
};

inline Mat4 getInverseTranspose3x3(const Mat4 &mat)
{
    // Extract 3x3
    float m00 = mat.m[0][0], m10 = mat.m[1][0], m20 = mat.m[2][0];
    float m01 = mat.m[0][1], m11 = mat.m[1][1], m21 = mat.m[2][1];
    float m02 = mat.m[0][2], m12 = mat.m[1][2], m22 = mat.m[2][2];

    // Cofactors
    float c00 = (m11 * m22 - m21 * m12);
    float c01 = -(m10 * m22 - m20 * m12);
    float c02 = (m10 * m21 - m20 * m11);

    float c10 = -(m01 * m22 - m21 * m02);
    float c11 = (m00 * m22 - m20 * m02);
    float c12 = -(m00 * m21 - m20 * m01);

    float c20 = (m01 * m12 - m11 * m02);
    float c21 = -(m00 * m12 - m10 * m02);
    float c22 = (m00 * m11 - m10 * m01);

    float det = m00 * c00 + m10 * c10 + m20 * c20;

    Mat4 res; // Identity
    if (std::abs(det) < 1e-6f)
        return res;

    float invD = 1.0f / det;
    res.m[0][0] = c00 * invD;
    res.m[1][0] = c01 * invD;
    res.m[2][0] = c02 * invD;
    res.m[0][1] = c10 * invD;
    res.m[1][1] = c11 * invD;
    res.m[2][1] = c12 * invD;
    res.m[0][2] = c20 * invD;
    res.m[1][2] = c21 * invD;
    res.m[2][2] = c22 * invD;

    return res;
}

inline Vec3 transformNormal(const Mat4 &normalMat, const Vec3 &n)
{
    // Multiply 3x3
    return Vec3(normalMat.m[0][0] * n.x + normalMat.m[1][0] * n.y + normalMat.m[2][0] * n.z,
                normalMat.m[0][1] * n.x + normalMat.m[1][1] * n.y + normalMat.m[2][1] * n.z,
                normalMat.m[0][2] * n.x + normalMat.m[1][2] * n.y + normalMat.m[2][2] * n.z);
}

// Math utilities
inline Mat4 lookAt(const Vec3 &eye, const Vec3 &center, const Vec3 &up)
{
    Vec3 f = (center - eye).normalize();
    Vec3 u = up.normalize();
    Vec3 s = cross(f, u).normalize();
    u = cross(s, f);

    Mat4 res;
    res.m[0][0] = s.x;
    res.m[1][0] = s.y;
    res.m[2][0] = s.z;
    res.m[0][1] = u.x;
    res.m[1][1] = u.y;
    res.m[2][1] = u.z;
    res.m[0][2] = -f.x;
    res.m[1][2] = -f.y;
    res.m[2][2] = -f.z;
    res.m[3][0] = -dot(s, eye);
    res.m[3][1] = -dot(u, eye);
    res.m[3][2] = dot(f, eye);
    return res;
}

inline Mat4 perspective(float fovy, float aspect, float zNear, float zFar)
{
    float tanHalfFovy = std::tan(fovy / 2.0f);

    Mat4 res;
    res.m[0][0] = 1.0f / (aspect * tanHalfFovy);
    res.m[1][1] = 1.0f / (tanHalfFovy);
    res.m[2][2] = -(zFar + zNear) / (zFar - zNear);
    res.m[2][3] = -1.0f;
    res.m[3][2] = -(2.0f * zFar * zNear) / (zFar - zNear);
    res.m[3][3] = 0.0f;
    return res;
}
