#pragma once

#include "pipeline_types.h"
#include "rasterizer.h"
#include <vector>

// -----------------------------------------------------------------------------
// Geometry Engine (Transform & Lighting)
// -----------------------------------------------------------------------------
class GeometryEngine
{
  public:
    Mat4 modelMatrix;
    Mat4 viewMatrix;
    Mat4 projectionMatrix;
    Mat4 mvpMatrix;       // Precalculated M * V * P
    Mat4 modelViewMatrix; // Precalculated V * M
    Mat4 normalMatrix;    // Precalculated inverse transpose of upper 3x3 of modelViewMatrix

    // OpenGL 1.x Lighting State
    bool lightingEnabled = false;
    Light light0;
    Material material;
    Vec3 globalAmbient = Vec3(0.2f, 0.2f, 0.2f);

    Rasterizer *rasterizer;
    int viewportWidth;
    int viewportHeight;

    GeometryEngine(Rasterizer *rast, int width, int height)
        : rasterizer(rast), viewportWidth(width), viewportHeight(height)
    {
    }

    void setModelMatrix(const Mat4 &m)
    {
        modelMatrix = m;
        updateMVP();
    }
    void setViewMatrix(const Mat4 &v)
    {
        viewMatrix = v;
        updateMVP();
    }
    void setProjectionMatrix(const Mat4 &p)
    {
        projectionMatrix = p;
        updateMVP();
    }

    // Main entry point for a triangle
    void drawTriangle(const Vertex_ObjectSpace &v0, const Vertex_ObjectSpace &v1, const Vertex_ObjectSpace &v2);

  private:
    void updateMVP()
    {
        mvpMatrix = projectionMatrix * viewMatrix * modelMatrix;
        modelViewMatrix = viewMatrix * modelMatrix;
        normalMatrix = getInverseTranspose3x3(modelViewMatrix);
    }

    // Pipeline Stages
    Vertex_ClipSpace vertexShader(const Vertex_ObjectSpace &vIn);
    uint32_t computeLighting(const Vertex_ObjectSpace &vIn);

    // Primitive Assembly & Clipping.
    void processTriangle(const Vertex_ClipSpace &v0, const Vertex_ClipSpace &v1, const Vertex_ClipSpace &v2);

    Vertex_ScreenSpace perspectiveDivideAndViewport(const Vertex_ClipSpace &vIn);

    // Helpers
    template <typename T> T edgeFunction(const tvec2<T> &a, const tvec2<T> &b, const tvec2<T> &c)
    {
        return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x);
    }
};
