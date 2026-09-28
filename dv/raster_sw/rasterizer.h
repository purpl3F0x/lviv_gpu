#pragma once

#include "pipeline_types.h"
#include <array>
#include <vector>

// -----------------------------------------------------------------------------
// Framebuffer
// -----------------------------------------------------------------------------
struct Framebuffer
{
    int width;
    int height;
    std::vector<uint32_t> colorBuffer;
    std::vector<decltype(Vertex_ScreenSpace{}.position.z)> depthBuffer;

    Framebuffer(int w, int h) : width(w), height(h)
    {
        colorBuffer.resize(w * h, 0xFF000000);    // Initialize to opaque black
        depthBuffer.resize(width * height, 1.0f); // Max depth for OpenGL is 1.0
    }

    void clear(uint32_t clearColor, float clearDepth)
    {
        std::fill(colorBuffer.begin(), colorBuffer.end(), clearColor);
        std::fill(depthBuffer.begin(), depthBuffer.end(), clearDepth);
    }
};

struct Bin
{
    std::vector<bool> triangle_bits;
    float lrz_val;
};

// -----------------------------------------------------------------------------
// Rasterizer Context
// -----------------------------------------------------------------------------
class Rasterizer
{
  public:
    Framebuffer *fb;
    TextureUnit textureUnit;
    bool alphaBlendingEnabled = false;

    uint64_t pixel_draw_count = 0;

    // TBR State
    static const int BIN_SIZE = 128;
    int num_bins_x;
    int num_bins_y;
    std::vector<std::vector<Bin>> bins;
    std::vector<std::array<Vertex_ScreenSpace, 3>> triangle_list;

    Rasterizer(Framebuffer *framebuffer) : fb(framebuffer)
    {
        num_bins_x = (fb->width + BIN_SIZE - 1) / BIN_SIZE;
        num_bins_y = (fb->height + BIN_SIZE - 1) / BIN_SIZE;
        bins.resize(num_bins_y, std::vector<Bin>(num_bins_x));
        clearBins();
    }

    void clearBins()
    {
        for (int y = 0; y < num_bins_y; ++y)
        {
            for (int x = 0; x < num_bins_x; ++x)
            {
                bins[y][x].triangle_bits.clear();
                bins[y][x].lrz_val = 1.0f;
            }
        }
        triangle_list.clear();
    }

    // Receives triangles from the Geometry Engine
    void queueTriangle(const Vertex_ScreenSpace &s0, const Vertex_ScreenSpace &s1, const Vertex_ScreenSpace &s2)
    {
        triangle_list.push_back({s0, s1, s2});
    }

    // Execute the binned pipeline
    void flush(bool dump_bins);

  private:
    void binningPass();
    void rasterizeBins(bool dump_bins);

    void rasterizeTriangle(const Vertex_ScreenSpace &v0, const Vertex_ScreenSpace &v1, const Vertex_ScreenSpace &v2,
                           int minX, int minY, int maxX, int maxY, uint32_t *tileColor, float *tileDepth);

    uint32_t fragmentShader(const Fragment_In &fIn);
    uint32_t blendFragment(uint32_t source, uint32_t destination) const;

    // Helpers
    template <typename T> T edgeFunction(const tvec2<T> &a, const tvec2<T> &b, const tvec2<T> &c)
    {
        return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x);
    }
};
