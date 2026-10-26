#pragma once

#include "math3d.h"
#include <cstdint>
#include <vector>

// -----------------------------------------------------------------------------
// Pipeline Stage Types
// Defining explicit structs for each pipeline stage boundary.
// This is essential for RTL modeling where each stage communicates via
// well-defined struct/bus definitions.
// -----------------------------------------------------------------------------

struct Material
{
    Vec3 ambient = Vec3(0.2f, 0.2f, 0.2f);
    Vec3 diffuse = Vec3(0.8f, 0.8f, 0.8f);
    Vec3 specular = Vec3(0.0f, 0.0f, 0.0f);
    Vec3 emissive = Vec3(0.0f, 0.0f, 0.0f);
    float shininess = 0.0f;
};

struct Light
{
    Vec4 position = Vec4(0.0f, 0.0f, 1.0f, 0.0f); // w=0 directional, w=1 point
    Vec3 ambient = Vec3(0.0f, 0.0f, 0.0f);
    Vec3 diffuse = Vec3(1.0f, 1.0f, 1.0f);
    Vec3 specular = Vec3(1.0f, 1.0f, 1.0f);
};

enum TexWrapMode
{
    REPEAT = 0,
    CLAMP
};

struct Texture
{
    int width = 0;
    int height = 0;
    std::vector<uint32_t> pixels; // ARGB packed
    TexWrapMode wrapModeS = TexWrapMode::REPEAT;
    TexWrapMode wrapModeT = TexWrapMode::REPEAT;
};

enum TexEnvMode
{
    REPLACE = 0,
    MODULATE,
    DECAL,
    BLEND,
    ADD
};

struct TextureUnit
{
    bool enabled = false;
    const Texture *boundTexture = nullptr;
    TexEnvMode envMode = TexEnvMode::MODULATE;
    Vec4 envColor = Vec4(0.0f, 0.0f, 0.0f, 0.0f); // For BLEND mode
};

// -----------------------------------------------------------------------------

// Input vertex straight from the Vertex Buffer (Object Space)
struct Vertex_ObjectSpace
{
    Vec3 position;
    Vec3 normal;
    Vec2 texcoord;
    uint32_t color;
};

// Output of the Vertex Shader (Clip Space)
struct Vertex_ClipSpace
{
    Vec4 position; // gl_Position (x, y, z, w)
    Vec3 normal;   // Transformed normal
    Vec2 texcoord;
    uint32_t color;
};

inline Vertex_ClipSpace lerp(const Vertex_ClipSpace &a, const Vertex_ClipSpace &b, float t)
{
    Vertex_ClipSpace res;
    res.position = a.position + (b.position - a.position) * t;
    res.normal = a.normal + (b.normal - a.normal) * t;
    res.texcoord = a.texcoord + (b.texcoord - a.texcoord) * t;
    // ARGB, channel by channel (as sdk/lviv_gl/lviv_geom.c)
    res.color = 0;
    for (int shift = 0; shift < 32; shift += 8)
    {
        const float ca = float(a.color >> shift & 0xFF), cb = float(b.color >> shift & 0xFF);
        res.color |= uint32_t(ca + (cb - ca) * t + 0.5f) << shift;
    }
    return res;
}

// Output of the Perspective Divide and Viewport Transform (Screen Space)
struct Vertex_ScreenSpace
{
    tvec4<float> position; // x, y (screen coords), z (depth [0,1]), w (1/w from clip space)

    // For perspective correct interpolation, we pre-divide attributes by w.
    tvec3<float> normal_over_w;
    tvec2<float> texcoord_over_w;
    uint32_t color;
};

// Input to the Fragment Shader
struct Fragment_In
{
    Vec2 screenCoord; // x, y integer pixel coordinates
    float depth;      // z value for depth testing

    // Perspective-correct interpolated attributes
    tvec3<float> normal;
    tvec2<float> texcoord;
    uint32_t color; // ARGB
};
