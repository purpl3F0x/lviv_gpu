#include "geometry_engine.h"
#include <algorithm>
#include <iostream>

// -----------------------------------------------------------------------------
// STEP 1: Vertex Shader
// -----------------------------------------------------------------------------
uint32_t GeometryEngine::computeLighting(const Vertex_ObjectSpace &vIn)
{
    // Transform to View Space
    Vec4 posEye4 = modelViewMatrix * Vec4(vIn.position, 1.0f);
    Vec3 posEye = Vec3(posEye4.x, posEye4.y, posEye4.z);

    // Transform normal to View Space using precomputed normalMatrix
    Vec3 normEye = transformNormal(normalMatrix, vIn.normal).normalize();

    // Lighting vectors
    Vec3 L;
    if (light0.position.w == 0.0f)
    {
        // Directional light
        L = Vec3(light0.position.x, light0.position.y, light0.position.z).normalize();
    }
    else
    {
        // Point light
        L = (Vec3(light0.position.x, light0.position.y, light0.position.z) - posEye).normalize();
    }

    Vec3 V = (Vec3(0, 0, 0) - posEye).normalize();
    Vec3 H = (L + V).normalize();

    // Compute terms
    float nDotL = std::max(0.0f, dot(normEye, L));
    float nDotH = std::max(0.0f, dot(normEye, H));

    Vec3 ambient(material.ambient.x * light0.ambient.x, material.ambient.y * light0.ambient.y,
                 material.ambient.z * light0.ambient.z);

    Vec3 diffuse(material.diffuse.x * light0.diffuse.x * nDotL, material.diffuse.y * light0.diffuse.y * nDotL,
                 material.diffuse.z * light0.diffuse.z * nDotL);

    Vec3 specular(0, 0, 0);
    if (nDotL > 0.0f && material.shininess > 0.0f)
    {
        float specFactor = std::pow(nDotH, material.shininess);
        specular = Vec3(material.specular.x * light0.specular.x * specFactor,
                        material.specular.y * light0.specular.y * specFactor,
                        material.specular.z * light0.specular.z * specFactor);
    }

    Vec3 matGlobalAmb(material.ambient.x * globalAmbient.x, material.ambient.y * globalAmbient.y,
                      material.ambient.z * globalAmbient.z);

    Vec3 finalColor = material.emissive + matGlobalAmb + ambient + diffuse + specular;

    // Clamp to [0, 1]
    finalColor.x = std::min(1.0f, std::max(0.0f, finalColor.x));
    finalColor.y = std::min(1.0f, std::max(0.0f, finalColor.y));
    finalColor.z = std::min(1.0f, std::max(0.0f, finalColor.z));

    uint8_t r = (uint8_t)(finalColor.x * 255.0f);
    uint8_t g = (uint8_t)(finalColor.y * 255.0f);
    uint8_t b = (uint8_t)(finalColor.z * 255.0f);
    return (255 << 24) | (r << 16) | (g << 8) | b;
}

Vertex_ClipSpace GeometryEngine::vertexShader(const Vertex_ObjectSpace &vIn)
{
    Vertex_ClipSpace vOut;

    // Transform position: Clip Space = Projection * View * Model * Object Space
    vOut.position = mvpMatrix * Vec4(vIn.position, 1.0f);

    if (lightingEnabled)
    {
        vOut.color = computeLighting(vIn);
    }
    else
    {
        vOut.color = vIn.color;
    }

    // Keep normal for output if needed (using old behavior)
    Vec4 norm4 = modelMatrix * Vec4(vIn.normal, 0.0f);
    vOut.normal = Vec3(norm4.x, norm4.y, norm4.z);

    vOut.texcoord = vIn.texcoord;

    return vOut;
}

void GeometryEngine::drawTriangle(const Vertex_ObjectSpace &v0, const Vertex_ObjectSpace &v1,
                                  const Vertex_ObjectSpace &v2)
{
    Vertex_ClipSpace c0 = vertexShader(v0);
    Vertex_ClipSpace c1 = vertexShader(v1);
    Vertex_ClipSpace c2 = vertexShader(v2);

    processTriangle(c0, c1, c2);
}

// -----------------------------------------------------------------------------
// STEP 2: Primitive Assembly & Clipping
// -----------------------------------------------------------------------------

namespace
{

enum class ClipPlane
{
    Left,
    Right,
    Bottom,
    Top,
    Near,
    Far
};

float distanceToPlane(const Vec4 &pos, ClipPlane plane)
{
    switch (plane)
    {
    case ClipPlane::Left:
        return pos.w + pos.x;
    case ClipPlane::Right:
        return pos.w - pos.x;
    case ClipPlane::Bottom:
        return pos.w + pos.y;
    case ClipPlane::Top:
        return pos.w - pos.y;
    case ClipPlane::Near:
        return pos.w + pos.z;
    case ClipPlane::Far:
        return pos.w - pos.z;
    }
    return 0.0f;
}

std::vector<Vertex_ClipSpace> clipAgainstPlane(const std::vector<Vertex_ClipSpace> &inVertices, ClipPlane plane)
{
    std::vector<Vertex_ClipSpace> outVertices;

    for (size_t i = 0; i < inVertices.size(); ++i)
    {
        size_t prev_i = (i == 0) ? inVertices.size() - 1 : i - 1;
        const auto &curr = inVertices[i];
        const auto &prev = inVertices[prev_i];

        float d_curr = distanceToPlane(curr.position, plane);
        float d_prev = distanceToPlane(prev.position, plane);

        bool curr_inside = d_curr >= 0.0f;
        bool prev_inside = d_prev >= 0.0f;

        if (curr_inside && prev_inside)
        {
            outVertices.push_back(curr);
        }
        else if (curr_inside && !prev_inside)
        {
            // Intersection
            float t = d_prev / (d_prev - d_curr);
            outVertices.push_back(lerp(prev, curr, t));
            outVertices.push_back(curr);
        }
        else if (!curr_inside && prev_inside)
        {
            // Intersection
            float t = d_prev / (d_prev - d_curr);
            outVertices.push_back(lerp(prev, curr, t));
        }
    }
    return outVertices;
}

} // namespace

void GeometryEngine::processTriangle(const Vertex_ClipSpace &v0, const Vertex_ClipSpace &v1, const Vertex_ClipSpace &v2)
{
    std::vector<Vertex_ClipSpace> polygon = {v0, v1, v2};

    ClipPlane planes[] = {ClipPlane::Left, ClipPlane::Right, ClipPlane::Bottom,
                          ClipPlane::Top,  ClipPlane::Near,  ClipPlane::Far};

    for (ClipPlane p : planes)
    {
        polygon = clipAgainstPlane(polygon, p);
        if (polygon.size() < 3)
            return; // Triangle culled
    }

    // Triangulate the resulting polygon using a triangle fan
    for (size_t i = 2; i < polygon.size(); ++i)
    {
        const Vertex_ClipSpace &c0 = polygon[0];
        const Vertex_ClipSpace &c1 = polygon[i - 1];
        const Vertex_ClipSpace &c2 = polygon[i];

        // Pass to next stage
        Vertex_ScreenSpace s0 = perspectiveDivideAndViewport(c0);
        Vertex_ScreenSpace s1 = perspectiveDivideAndViewport(c1);
        Vertex_ScreenSpace s2 = perspectiveDivideAndViewport(c2);

        // Backface Culling (Counter-Clockwise winding)
        float area = edgeFunction(tvec2<float>(s0.position.x, s0.position.y),
                                             tvec2<float>(s1.position.x, s1.position.y),
                                             tvec2<float>(s2.position.x, s2.position.y));
        if (std::abs((float)area) < 1e-5f)
        {
            continue; // Degenerate triangle
        }
        // Queue for binning on the Rasterizer Engine
        rasterizer->queueTriangle(s0, s1, s2);
    }
}

// -----------------------------------------------------------------------------
// STEP 3: Perspective Divide & Viewport Transform
// -----------------------------------------------------------------------------
Vertex_ScreenSpace GeometryEngine::perspectiveDivideAndViewport(const Vertex_ClipSpace &vIn)
{
    Vertex_ScreenSpace vOut;

    // Perspective Divide (NDC space: -1 to 1)
    float invW = 1.0f / (float)vIn.position.w;
    float ndcX = (float)vIn.position.x * invW;
    float ndcY = (float)vIn.position.y * invW;
    float ndcZ = (float)vIn.position.z * invW;

    // Viewport Transform (Screen space)
    // Map X: [-1, 1] -> [0, width]
    // Map Y: [-1, 1] -> [height, 0] (Flipped so +Y is top of the image)
    float posX = (ndcX + 1.0f) * (0.5f * viewportWidth);
    float posY = (1.0f - ndcY) * (0.5f * viewportHeight);

    // Map Z: [-1, 1] -> [0, 1] for OpenGL depth buffer convention
    float posZ = (ndcZ + 1.0f) * 0.5f;

    // Pre-multiply attributes by 1/w for perspective-correct interpolation later
    float norm_x = vIn.normal.x * invW;
    float norm_y = vIn.normal.y * invW;
    float norm_z = vIn.normal.z * invW;

    float tex_x = vIn.texcoord.x * invW;
    float tex_y = vIn.texcoord.y * invW;

    // Convert to final pipeline types
    vOut.position.x = (posX);
    vOut.position.y = (posY);
    vOut.position.z = (posZ);
    vOut.position.w = (invW); // Store 1/w for perspective-correct interpolation

    vOut.normal_over_w = tvec3<float>(norm_x, norm_y, norm_z);
    vOut.texcoord_over_w = tvec2<float>(tex_x, tex_y);
    vOut.color = vIn.color; // ARGB stays as uint32_t

    return vOut;
}
