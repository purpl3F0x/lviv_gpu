#include "rasterizer.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>

#include <ap_fixed.h>
#include <ap_int.h>

#include "gpu_triangle.h" // sdk/include: the record layout gpu_top unpacks

struct ColorU8
{
    uint8_t r, g, b, a;
};

ColorU8 unpackU8(uint32_t c);
uint32_t packU8(const ColorU8 &c);

// Helper forward declarations
Vec4 unpackColor(uint32_t c);
uint32_t packColor(const Vec4 &c);

namespace
{
} // namespace

void Rasterizer::dumpFrontendInputCsv(const std::string &path) const
{
    static constexpr std::array<const char *, 16> columns = {
        "v0_x",      "v0_y",      "v1_x", "v1_y", "v2_x", "v2_y", "bin_min_x", "bin_min_y",
        "bin_max_x", "bin_max_y", "v0_u", "v0_v", "v1_u", "v1_v", "v2_u",      "v2_v",
    };
    std::ofstream csv(path);
    if (!csv)
        throw std::runtime_error("Could not open frontend input CSV: " + path);

    csv << "transaction_id";
    for (const char *column : columns)
        csv << ',' << column;
    csv << '\n';

    csv << std::setprecision(std::numeric_limits<float>::max_digits10);
    for (size_t index = 0; index < frontend_vectors.size(); ++index)
    {
        csv << index;
        for (float value : frontend_vectors[index].inputs)
            csv << ',' << value;
        csv << '\n';
    }
}

void Rasterizer::dumpFrontendExpectedCsv(const std::string &path) const
{
    static constexpr std::array<const char *, 20> columns = {
        "invArea",    "w0",         "w1",         "w2",         "dx0_fx",     "dx1_fx",     "dx2_fx",
        "dy0_fx",     "dy1_fx",     "dy2_fx",     "bb_width",   "bb_height",  "minX_local", "minY_local",
        "v0_u_fixed", "v0_v_fixed", "v1_u_fixed", "v1_v_fixed", "v2_u_fixed", "v2_v_fixed",
    };
    std::ofstream csv(path);
    if (!csv)
        throw std::runtime_error("Could not open frontend expected-output CSV: " + path);

    csv << "transaction_id";
    for (const char *column : columns)
        csv << ',' << column;
    csv << '\n';

    csv << std::setprecision(std::numeric_limits<float>::max_digits10);
    for (size_t index = 0; index < frontend_vectors.size(); ++index)
    {
        csv << index;
        const auto &outputs = frontend_vectors[index].expected_outputs;
        csv << ',' << outputs.inv_area << ',' << outputs.w0 << ',' << outputs.w1 << ',' << outputs.w2 << ','
            << outputs.dx0 << ',' << outputs.dx1 << ',' << outputs.dx2 << ',' << outputs.dy0 << ',' << outputs.dy1
            << ',' << outputs.dy2 << ',' << outputs.bb_width << ',' << outputs.bb_height << ',' << outputs.min_x_local
            << ',' << outputs.min_y_local << ',' << outputs.v0_u << ',' << outputs.v0_v << ',' << outputs.v1_u << ','
            << outputs.v1_v << ',' << outputs.v2_u << ',' << outputs.v2_v;
        csv << '\n';
    }
}

// One row per (triangle, bin), in bin order: everything raster_core's frontend_data_in_t takes. The
// render state is the rasterizer's global state, written per row because the hardware takes it per
// triangle. Enum columns use the RTL encodings (gpu_types_pkg.sv); colors are ARGB hex.
Rasterizer::RasterCoreState Rasterizer::rasterCoreState() const
{
    // gpu_types_pkg.sv encodings
    constexpr int TexIdNone = 0x80, TexIdBound = 0;
    constexpr int FragmentColor = 5; // fragment_op_t COLOR; REPLACE..ADD match TexEnvMode
    constexpr int TextureClamp = 0, TextureTile = 1;
    constexpr int BlendZero = 0, BlendOne = 1, BlendSrcAlpha = 6, BlendOneMinusSrcAlpha = 7;
    constexpr int DepthLess = 1; // rasterizeTriangle passes z < stored

    const Texture *texture = textureUnit.enabled ? textureUnit.boundTexture : nullptr;
    return {
        texture ? TexIdBound : TexIdNone,
        texture && texture->wrapModeS == TexWrapMode::CLAMP ? TextureClamp : TextureTile,
        texture && texture->wrapModeT == TexWrapMode::CLAMP ? TextureClamp : TextureTile,
        texture ? static_cast<int>(textureUnit.envMode) : FragmentColor,
        alphaBlendingEnabled ? BlendSrcAlpha : BlendOne,
        alphaBlendingEnabled ? BlendOneMinusSrcAlpha : BlendZero,
        DepthLess,
    };
}

void Rasterizer::dumpRasterCoreCsv(const std::string &path) const
{
    const RasterCoreState state = rasterCoreState();

    std::ofstream csv(path);
    if (!csv)
        throw std::runtime_error("Could not open raster core CSV: " + path);

    csv << "transaction_id,bin_min_x,bin_min_y";
    for (int v = 0; v < 3; ++v)
        for (const char *field : {"x", "y", "z", "w", "u", "v", "color"})
            csv << ",v" << v << '_' << field;
    csv << ",tex_id,texture_mode_u,texture_mode_v,texture_function,sfactor_op,dfactor_op,depth_func\n";

    csv << std::setprecision(std::numeric_limits<float>::max_digits10);
    for (size_t index = 0; index < frontend_vectors.size(); ++index)
    {
        const FrontendVector &vector = frontend_vectors[index];
        csv << index << ',' << vector.inputs[6] << ',' << vector.inputs[7];
        for (const Vertex_ScreenSpace &vertex : vector.vertices)
        {
            csv << ',' << vertex.position.x << ',' << vertex.position.y << ',' << vertex.position.z << ','
                << vertex.position.w << ',' << vertex.texcoord_over_w.x << ',' << vertex.texcoord_over_w.y << ','
                << std::hex << std::setw(8) << std::setfill('0') << vertex.color << std::dec << std::setfill(' ');
        }
        csv << ',' << state.texId << ',' << state.modeU << ',' << state.modeV << ',' << state.textureFunction << ','
            << state.sfactor << ',' << state.dfactor << ',' << state.depthFunc << '\n';
    }
}

void Rasterizer::dumpGpuTopScene(const std::string &path) const
{
    if (num_bins_x * num_bins_y > 64)
        throw std::runtime_error("gpu_top scene: more than 64 bins for a 64-bit visibility word");
    const RasterCoreState state = rasterCoreState();

    std::ofstream out(path);
    if (!out)
        throw std::runtime_error("Could not open gpu_top scene: " + path);

    // The record as words in memory (little-endian), as tb/gpu_top loads them with $fscanf.
    out << std::hex << std::setfill('0');
    for (const SceneTriangle &triangle : scene_triangles)
    {
        gpu_triangle_t record{};
        for (int v = 0; v < 3; ++v)
        {
            const Vertex_ScreenSpace &vertex = triangle.vertices[v];
            record.v[v] = {vertex.position.x, vertex.position.y,       vertex.position.z,      vertex.position.w,
                           vertex.color,      vertex.texcoord_over_w.x, vertex.texcoord_over_w.y};
        }
        record.tex_id = static_cast<uint8_t>(state.texId);
        record.texture_mode =
            static_cast<uint8_t>(state.modeU << GPU_TEXTURE_MODE_U_SHIFT | state.modeV << GPU_TEXTURE_MODE_V_SHIFT);
        record.texture_function = static_cast<uint8_t>(state.textureFunction);
        record.blend = static_cast<uint8_t>(state.sfactor << GPU_SFACTOR_OP_SHIFT | state.dfactor << GPU_DFACTOR_OP_SHIFT);
        record.depth_func = static_cast<uint8_t>(state.depthFunc);

        uint32_t words[GPU_TRIANGLE_BYTES / 4];
        std::memcpy(words, &record, sizeof record);
        out << std::setw(16) << triangle.visibility;
        for (uint32_t word : words)
            out << ' ' << std::setw(8) << word;
        out << '\n';
    }
}

// -----------------------------------------------------------------------------
// STEP 4: Tile Binning
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
void Rasterizer::flush(bool dump_bins)
{
    binningPass();
    rasterizeBins(dump_bins);
    clearBins();
}

void Rasterizer::binningPass()
{
    // Resize the bitmask for each bin to accommodate all triangles
    for (int y = 0; y < num_bins_y; ++y)
    {
        for (int x = 0; x < num_bins_x; ++x)
        {
            bins[y][x].triangle_bits.resize(triangle_list.size(), false);
        }
    }

    double totalWidth = 0;
    double totalHeight = 0;
    double totalClampedWidth = 0;
    double totalClampedHeight = 0;
    size_t validTriangles = 0;

    for (size_t i = 0; i < triangle_list.size(); ++i)
    {
        const auto &tri = triangle_list[i];
        const Vertex_ScreenSpace &v0 = tri[0];
        const Vertex_ScreenSpace &v1 = tri[1];
        const Vertex_ScreenSpace &v2 = tri[2];

        // Raw BB
        float rawMinX = std::min({v0.position.x, v1.position.x, v2.position.x});
        float rawMaxX = std::max({v0.position.x, v1.position.x, v2.position.x});
        float rawMinY = std::min({v0.position.y, v1.position.y, v2.position.y});
        float rawMaxY = std::max({v0.position.y, v1.position.y, v2.position.y});

        totalWidth += (double)(rawMaxX - rawMinX);
        totalHeight += (double)(rawMaxY - rawMinY);
        validTriangles++;

        // Triangle bounding box
        int triMinX = std::max(0, math_floor(rawMinX));
        int triMinY = std::max(0, math_floor(rawMinY));
        int triMaxX = std::min(fb->width - 1, math_ceil(rawMaxX));
        int triMaxY = std::min(fb->height - 1, math_ceil(rawMaxY));

        if (triMinX > triMaxX || triMinY > triMaxY)
            continue;

        totalClampedWidth += (double)(triMaxX - triMinX);
        totalClampedHeight += (double)(triMaxY - triMinY);

        // Bins overlap
        int startBinX = triMinX / BIN_SIZE;
        int startBinY = triMinY / BIN_SIZE;
        int endBinX = triMaxX / BIN_SIZE;
        int endBinY = triMaxY / BIN_SIZE;

        // Find minZ for early LRZ rejection
        float minZ = std::min({(float)v0.position.z, (float)v1.position.z, (float)v2.position.z});
        float maxZ = std::max({(float)v0.position.z, (float)v1.position.z, (float)v2.position.z});

        for (int by = startBinY; by <= endBinY; ++by)
        {
            for (int bx = startBinX; bx <= endBinX; ++bx)
            {
                Bin &bin = bins[by][bx];

                const int binMinX = bx * BIN_SIZE;
                const int binMinY = by * BIN_SIZE;
                const int binMaxX = std::min(fb->width - 1, binMinX + BIN_SIZE - 1);
                const int binMaxY = std::min(fb->height - 1, binMinY + BIN_SIZE - 1);

                // 1. LRZ Early Rejection
                if (minZ > bin.lrz_val)
                {
                    continue; // Occluded
                }

                // Mark triangle in bin
                bin.triangle_bits[i] = true;

                // 2. LRZ Update
                tvec2<float> p0(v0.position.x, v0.position.y);
                tvec2<float> p1(v1.position.x, v1.position.y);
                tvec2<float> p2(v2.position.x, v2.position.y);

                float invArea = 1.0f / edgeFunction(p0, p1, p2);

                bool fullyCovers = true;
                tvec2<float> corners[4] = {{float(bx * BIN_SIZE), float(by * BIN_SIZE)},
                                           {float((bx + 1) * BIN_SIZE - 1), float(by * BIN_SIZE)},
                                           {float(bx * BIN_SIZE), float((by + 1) * BIN_SIZE - 1)},
                                           {float((bx + 1) * BIN_SIZE - 1), float((by + 1) * BIN_SIZE - 1)}};

                for (int c = 0; c < 4; ++c)
                {
                    float w0 = edgeFunction(p1, p2, corners[c]) * invArea;
                    float w1 = edgeFunction(p2, p0, corners[c]) * invArea;
                    float w2 = edgeFunction(p0, p1, corners[c]) * invArea;
                    if (w0 < 0 || w1 < 0 || w2 < 0)
                    {
                        fullyCovers = false;
                        break;
                    }
                }

                if (fullyCovers)
                {
                    bin.lrz_val = std::min(bin.lrz_val, maxZ);
                }
            }
        }
    }

    if (validTriangles > 0)
    {
        std::cout << "Average Raw BB Width: " << (totalWidth / validTriangles) << std::endl;
        std::cout << "Average Raw BB Height: " << (totalHeight / validTriangles) << std::endl;
        std::cout << "Average Clamped BB Width: " << (totalClampedWidth / validTriangles) << std::endl;
        std::cout << "Average Clamped BB Height: " << (totalClampedHeight / validTriangles) << std::endl;
    }
}

#include <cstdio>

extern void savePNG(const Framebuffer &fb, const char *filename);

void Rasterizer::rasterizeBins(bool dump_bins)
{
    // Which bins each triangle goes to, for the gpu_top scene (only up to 64 bins).
    std::vector<uint64_t> visibility(triangle_list.size(), 0);

    for (int y = 0; y < num_bins_y; ++y)
    {
        for (int x = 0; x < num_bins_x; ++x)
        {
            // On-chip tile memory (simulated)
            std::vector<uint32_t> tileColor(BIN_SIZE * BIN_SIZE);
            std::vector<float> tileDepth(BIN_SIZE * BIN_SIZE);
            const Bin &bin = bins[y][x];

            int binMinX = x * BIN_SIZE;
            int binMinY = y * BIN_SIZE;
            int binMaxX = std::min(fb->width - 1, binMinX + BIN_SIZE - 1);
            int binMaxY = std::min(fb->height - 1, binMinY + BIN_SIZE - 1);

            int tileW = binMaxX - binMinX + 1;
            int tileH = binMaxY - binMinY + 1;

            // Load Tile from Global Framebuffer
            for (int ty = 0; ty < tileH; ++ty)
            {
                for (int tx = 0; tx < tileW; ++tx)
                {
                    int globalIdx = (binMinY + ty) * fb->width + (binMinX + tx);
                    tileColor[ty * BIN_SIZE + tx] = fb->colorBuffer[globalIdx];
                    tileDepth[ty * BIN_SIZE + tx] = fb->depthBuffer[globalIdx];
                }
            }

            // Process all triangles for this tile
            bool bin_empty = true;
            for (size_t i = 0; i < bin.triangle_bits.size(); ++i)
            {
                if (bin.triangle_bits[i])
                {
                    bin_empty = false;
                    if (const int bit = y * num_bins_x + x; bit < 64)
                        visibility[i] |= uint64_t{1} << bit;
                    const auto &tri = triangle_list[i];
                    rasterizeTriangle(tri[0], tri[1], tri[2], binMinX, binMinY, binMaxX, binMaxY, tileColor.data(),
                                      tileDepth.data());
                }
            }

            if (bin_empty)
            {
                continue;
            }

            // Store Tile to Global Framebuffer
            for (int ty = 0; ty < tileH; ++ty)
            {
                for (int tx = 0; tx < tileW; ++tx)
                {
                    int globalIdx = (binMinY + ty) * fb->width + (binMinX + tx);
                    fb->colorBuffer[globalIdx] = tileColor[ty * BIN_SIZE + tx];
                    fb->depthBuffer[globalIdx] = tileDepth[ty * BIN_SIZE + tx];
                }
            }

            // if (dump_bins)
            // {
            //     static int frame_count = 0;
            //     char filename[256];
            //     snprintf(filename, sizeof(filename), "./frames/frame_%04d.png", frame_count++);
            //     savePNG(*fb, filename);
            // }
        }
    }

    for (size_t i = 0; i < triangle_list.size(); ++i)
        if (visibility[i])
            scene_triangles.push_back({triangle_list[i], visibility[i]});
}

// -----------------------------------------------------------------------------
// STEP 4: Rasterization (Edge Equations & Perspective-Correct Barycentric)
// -----------------------------------------------------------------------------
void Rasterizer::recordFrontendVector(const Vertex_ScreenSpace &v0, const Vertex_ScreenSpace &v1,
                                      const Vertex_ScreenSpace &v2, int binMinX, int binMinY, int binMaxX, int binMaxY,
                                      int bbMinX, int bbMinY, int bbMaxX, int bbMaxY, float invArea, edge_type w0,
                                      edge_type w1, edge_type w2, dx_type dx0, dx_type dx1, dx_type dx2, dx_type dy0,
                                      dx_type dy1, dx_type dy2)
{
    constexpr int addressBits = std::bit_width(static_cast<unsigned>(BIN_SIZE / 2 - 1));
    constexpr uint32_t addressMask = (uint32_t{1} << addressBits) - 1;
    const uint32_t minX = static_cast<uint32_t>(bbMinX) & 0xfff;
    const uint32_t minY = static_cast<uint32_t>(bbMinY) & 0xfff;
    const uint32_t maxX = static_cast<uint32_t>(bbMaxX) & 0xfff;
    const uint32_t maxY = static_cast<uint32_t>(bbMaxY) & 0xfff;
    const uint32_t minXLocal = (minX >> 1) & addressMask;
    const uint32_t minYLocal = (minY >> 1) & addressMask;
    const uint32_t maxXLocal = (maxX >> 1) & addressMask;
    const uint32_t maxYLocal = (maxY >> 1) & addressMask;

    FrontendVector vector{};
    vector.inputs = {
        v0.position.x,
        v0.position.y,
        v1.position.x,
        v1.position.y,
        v2.position.x,
        v2.position.y,
        static_cast<float>(binMinX),
        static_cast<float>(binMinY),
        static_cast<float>(binMaxX),
        static_cast<float>(binMaxY),
        v0.texcoord_over_w.x,
        v0.texcoord_over_w.y,
        v1.texcoord_over_w.x,
        v1.texcoord_over_w.y,
        v2.texcoord_over_w.x,
        v2.texcoord_over_w.y,
    };
    vector.expected_outputs = {
        invArea,
        w0,
        w1,
        w2,
        dx0,
        dx1,
        dx2,
        dy0,
        dy1,
        dy2,
        (maxXLocal - minXLocal) & addressMask,
        (maxYLocal - minYLocal) & addressMask,
        minXLocal,
        minYLocal,
        v0.texcoord_over_w.x,
        v0.texcoord_over_w.y,
        v1.texcoord_over_w.x,
        v1.texcoord_over_w.y,
        v2.texcoord_over_w.x,
        v2.texcoord_over_w.y,
    };
    vector.vertices = {v0, v1, v2};
    frontend_vectors.push_back(vector);
}

#ifndef RASTERIZER_EXTERNAL_RASTERIZE_TRIANGLE
void Rasterizer::rasterizeTriangle(const Vertex_ScreenSpace &v0, const Vertex_ScreenSpace &v1,
                                   const Vertex_ScreenSpace &v2, int binMinX, int binMinY, int binMaxX, int binMaxY,
                                   uint32_t *tileColor, float *tileDepth)
{

    // Toggle the type of the interpolation her
    // typedef ap_fixed<48, 24> interp_type;
    typedef float interp_type;
    // typedef ap_fixed<38, 14> bb_type;

    // --- STEP 1: Edge Equations Setup ---
    // This is incorrect cause we need to snap to grid, to do this properly
    const tvec2<edge_type> p0((dx_type)v0.position.x, (dx_type)v0.position.y);
    const tvec2<edge_type> p1((dx_type)v1.position.x, (dx_type)v1.position.y);
    const tvec2<edge_type> p2((dx_type)v2.position.x, (dx_type)v2.position.y);

    // Extract colors and pre-divide by w (using position.w which holds 1/w) for perspective-correct interpolation
    const ColorU8 uc0 = unpackU8(v0.color);
    const ColorU8 uc1 = unpackU8(v1.color);
    const ColorU8 uc2 = unpackU8(v2.color);
    const tvec4<ap_fixed<17, 9, AP_RND>> c0(uc0.r, uc0.g, uc0.b, uc0.a);
    const tvec4<ap_fixed<17, 9, AP_RND>> c1(uc1.r, uc1.g, uc1.b, uc1.a);
    const tvec4<ap_fixed<17, 9, AP_RND>> c2(uc2.r, uc2.g, uc2.b, uc2.a);

    // Triangle Area (for Barycentric normalization)
    edge_type area = edgeFunction(p0, p1, p2);
    // if (area == 0) return;
    // Calculate invArea precisely using the chosen interpolation type (done once per triangle)
    float invArea = interp_type(1.0f) / (float)area;

    // Calculate the triangle's bounding box in screen space
    int triMinX = std::min({p0.x, p1.x, p2.x});
    int triMinY = std::min({p0.y, p1.y, p2.y});
    int triMaxX = std::max({p0.x, p1.x, p2.x});
    int triMaxY = std::max({p0.y, p1.y, p2.y});

    // Align to 2x2 blocks: min is even (0, 2, 4...), max is odd (1, 3, 5...)
    triMinX = triMinX & ~1;
    triMinY = triMinY & ~1;
    triMaxX = triMaxX | 1;
    triMaxY = triMaxY | 1;

    // Intersect the triangle's bounding box with the tile's bounding box
    ap_uint<14> minX = std::max(binMinX, triMinX);
    ap_uint<14> minY = std::max(binMinY, triMinY);
    ap_uint<14> maxX = std::min(binMaxX, triMaxX);
    ap_uint<14> maxY = std::min(binMaxY, triMaxY);

    // // No Bounding Box Logic
    // minX = binMinX;
    // minY = binMinY;
    // maxX = binMaxX;
    // maxY = binMaxY;

    // Calculate initial edge functions at the center of the top-left pixel of the intersected bounding box
    tvec2<edge_type> p_min(dx_type(minX) + dx_type(0.5f), dx_type(minY) + dx_type(0.5f));

    // Track EXACT edge functions (unnormalized) to avoid precision loss across scanlines
    edge_type e0_row = edgeFunction(p1, p2, p_min);
    edge_type e1_row = edgeFunction(p2, p0, p_min);
    edge_type e2_row = edgeFunction(p0, p1, p_min);

    // Step increments for each step in X
    dx_type e0_dx = (p2.y - p1.y);
    dx_type e1_dx = (p0.y - p2.y);
    dx_type e2_dx = (p1.y - p0.y);

    // Step increments for each step in Y
    dx_type e0_dy = (p1.x - p2.x);
    dx_type e1_dy = (p2.x - p0.x);
    dx_type e2_dy = (p0.x - p1.x);

    recordFrontendVector(v0, v1, v2, binMinX, binMinY, binMaxX, binMaxY, minX, minY, maxX, maxY, invArea, e0_row,
                         e1_row, e2_row, e0_dx, e1_dx, e2_dx, e0_dy, e1_dy, e2_dy);

    edge_type e0_00 = e0_row;
    edge_type e1_00 = e1_row;
    edge_type e2_00 = e2_row;

    // edge_type e0_10 = e0_row + (edge_type)e0_dx;
    // edge_type e1_10 = e1_row + (edge_type)e1_dx;
    // edge_type e2_10 = e2_row + (edge_type)e2_dx;

    // edge_type e0_01 = e0_row + (edge_type)e0_dy;
    // edge_type e1_01 = e1_row + (edge_type)e1_dy;
    // edge_type e2_01 = e2_row + (edge_type)e2_dy;

    // edge_type e0_11 = e0_row + (edge_type)e0_dx + (edge_type)e0_dy;
    // edge_type e1_11 = e1_row + (edge_type)e1_dx + (edge_type)e1_dy;
    // edge_type e2_11 = e2_row + (edge_type)e2_dx + (edge_type)e2_dy;

    // --- HW STEP 2: Scanline Traversal / Rasterization ---
    // Rasterize within the intersected bounding box
    for (int y = minY; y <= maxY; ++y)
    {
        edge_type e0 = e0_row;
        edge_type e1 = e1_row;
        edge_type e2 = e2_row;

        for (int x = minX; x <= maxX; ++x)
        {

            pixel_draw_count++;

            // --- STEP 3: Inside/Outside Test ---
            if (e0 >= 0 && e1 >= 0 && e2 >= 0)
            {
                // --- STEP 4: Barycentric Coordinates ---
                interp_type iw0 = (interp_type)e0 * invArea;
                interp_type iw1 = (interp_type)e1 * invArea;
                interp_type iw2 = (interp_type)e2 * invArea;

                // --- STEP 5: Depth (Z) & Perspective (1/W) Interpolation ---
                interp_type z = iw0 * (interp_type)v0.position.z + iw1 * (interp_type)v1.position.z +
                                iw2 * (interp_type)v2.position.z;

                // --- STEP 6: Depth Test (Early Z) ---
                int tileIdx = (y - binMinY) * BIN_SIZE + (x - binMinX);

                if (z < tileDepth[tileIdx])
                {

                    tileDepth[tileIdx] = z; // Update depth

                    interp_type invW = iw0 * (interp_type)v0.position.w + iw1 * (interp_type)v1.position.w +
                                       iw2 * (interp_type)v2.position.w;

                    // --- STEP 7: Perspective-Correct Attribute Interpolation ---
                    // auto normal_over_w =
                    //     tvec3<interp_type>(v0.normal_over_w.x, v0.normal_over_w.y, v0.normal_over_w.z) * iw0 +
                    //     tvec3<interp_type>(v1.normal_over_w.x, v1.normal_over_w.y, v1.normal_over_w.z) * iw1 +
                    //     tvec3<interp_type>(v2.normal_over_w.x, v2.normal_over_w.y, v2.normal_over_w.z) * iw2;

                    // auto texcoord_over_w = tvec2<interp_type>(v0.texcoord_over_w.x, v0.texcoord_over_w.y) * iw0 +
                    //                        tvec2<interp_type>(v1.texcoord_over_w.x, v1.texcoord_over_w.y) * iw1 +
                    //                        tvec2<interp_type>(v2.texcoord_over_w.x, v2.texcoord_over_w.y) * iw2;

                    // auto color_interp = c0 * iw0 + c1 * iw1 + c2 * iw2;

                    interp_type w = interp_type(1.0f) / invW;

                    float t0_fp = iw0 * v0.position.w * w;
                    float t1_fp = iw1 * v1.position.w * w;
                    float t2_fp = iw2 * v2.position.w * w;

                    ap_fixed<25, 2, AP_RND> t0 = t0_fp;
                    ap_fixed<25, 2, AP_RND> t1 = t1_fp;
                    ap_fixed<25, 2, AP_RND> t2 = t2_fp;

                    ap_fixed<10, 2, AP_RND> t0_small = t0_fp;
                    ap_fixed<10, 2, AP_RND> t1_small = t1_fp;
                    ap_fixed<10, 2, AP_RND> t2_small = t2_fp;

                    // --- STEP 8: Programmable Fragment Shader Assembly ---
                    Fragment_In fIn;
                    fIn.screenCoord = tvec2<float>(x, y);
                    fIn.depth = z;
                    // fIn.normal = tvec3<float>(normal_over_w.x * w, normal_over_w.y * w, normal_over_w.z * w);
                    // fIn.texcoord = tvec2<float>(texcoord_over_w.x * w, texcoord_over_w.y * w);

                    fIn.texcoord.x = t0 * (ap_fixed<17, 4, AP_RND>)v0.texcoord_over_w.x +
                                     t1 * (ap_fixed<17, 4, AP_RND>)v1.texcoord_over_w.x +
                                     t2 * (ap_fixed<17, 4, AP_RND>)v2.texcoord_over_w.x;
                    fIn.texcoord.y = t0 * (ap_fixed<17, 4, AP_RND>)v0.texcoord_over_w.y +
                                     t1 * (ap_fixed<17, 4, AP_RND>)v1.texcoord_over_w.y +
                                     t2 * (ap_fixed<17, 4, AP_RND>)v2.texcoord_over_w.y;

                    auto color_interp_corrected = c0 * (ap_fixed<17, 9, AP_RND>)t0 + c1 * (ap_fixed<17, 9, AP_RND>)t1 +
                                                  c2 * (ap_fixed<17, 9, AP_RND>)t2;

                    // auto color_interp_corrected = color_interp * w;

                    ColorU8 c_interp_u8 = {(uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.x)),
                                           (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.y)),
                                           (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.z)),
                                           (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.w))};
                    fIn.color = packU8(c_interp_u8);

                    uint32_t finalColor = fragmentShader(fIn);

                    // --- STEP 9: Write to Framebuffer ---
                    tileColor[tileIdx] = blendFragment(finalColor, tileColor[tileIdx]);
                }
            }
            e0 += (edge_type)e0_dx;
            e1 += (edge_type)e1_dx;
            e2 += (edge_type)e2_dx;
        }
        e0_row += (edge_type)e0_dy;
        e1_row += (edge_type)e1_dy;
        e2_row += (edge_type)e2_dy;
    }
}
#endif

// -----------------------------------------------------------------------------
// STEP 5: Fragment Shader
// -----------------------------------------------------------------------------
uint32_t Rasterizer::blendFragment(uint32_t source, uint32_t destination) const
{
    if (!alphaBlendingEnabled)
        return source;

    const uint32_t sourceFactor = source >> 24;
    const uint32_t destinationFactor = 255 - sourceFactor;
    uint32_t result = 0;
    for (unsigned shift = 0; shift < 32; shift += 8)
    {
        const uint32_t sum =
            ((source >> shift) & 255) * sourceFactor + ((destination >> shift) & 255) * destinationFactor + 128;
        result |= std::min(255u, sum >> 8) << shift;
    }
    return result;
}

Vec4 unpackColor(uint32_t c)
{
    return Vec4(((c >> 16) & 0xFF) / 255.0f, ((c >> 8) & 0xFF) / 255.0f, (c & 0xFF) / 255.0f,
                ((c >> 24) & 0xFF) / 255.0f);
}

uint32_t packColor(const Vec4 &c)
{
    uint32_t a = std::max(0.0f, std::min(255.0f, c.w * 255.0f));
    uint32_t r = std::max(0.0f, std::min(255.0f, c.x * 255.0f));
    uint32_t g = std::max(0.0f, std::min(255.0f, c.y * 255.0f));
    uint32_t b = std::max(0.0f, std::min(255.0f, c.z * 255.0f));
    return (a << 24u) | (r << 16u) | (g << 8u) | (b << 0u);
}

ColorU8 unpackU8(uint32_t c)
{
    return {(uint8_t)((c >> 16) & 0xFF), (uint8_t)((c >> 8) & 0xFF), (uint8_t)(c & 0xFF), (uint8_t)((c >> 24) & 0xFF)};
}

uint32_t packU8(const ColorU8 &c)
{
    return ((uint32_t)c.a << 24) | ((uint32_t)c.r << 16) | ((uint32_t)c.g << 8) | (uint32_t)c.b;
}

uint32_t sampleTexture(const Texture *tex, const Vec2 &uv)
{
    if (!tex || tex->width <= 0 || tex->height <= 0)
        return 0xFFFFFFFF;

    float u = uv.x;
    float v = uv.y;

    // Apply Wrap Mode S
    switch (tex->wrapModeS)
    {
    case TexWrapMode::REPEAT:
        u = u - std::floor(u);
        break;
    case TexWrapMode::CLAMP:
        u = std::max(0.0f, std::min(1.0f, u));
        break;
    }

    // Apply Wrap Mode T
    switch (tex->wrapModeT)
    {
    case TexWrapMode::REPEAT:
        v = v - std::floor(v);
        break;
    case TexWrapMode::CLAMP:
        v = std::max(0.0f, std::min(1.0f, v));
        break;
    }

    int tx = (int)(u * tex->width);
    int ty = (int)(v * tex->height);
    tx = std::max(0, std::min(tex->width - 1, tx));
    ty = std::max(0, std::min(tex->height - 1, ty));

    uint32_t texel = tex->pixels[ty * tex->width + tx];
    return texel;
}

uint32_t Rasterizer::fragmentShader(const Fragment_In &fIn)
{
    uint32_t Cf_raw = fIn.color;

    if (textureUnit.enabled && textureUnit.boundTexture)
    {
        Vec2 uv((float)fIn.texcoord.x, (float)fIn.texcoord.y);
        uint32_t Ct_raw = sampleTexture(textureUnit.boundTexture, uv);

        ColorU8 Cf = unpackU8(Cf_raw);
        ColorU8 Ct = unpackU8(Ct_raw);
        ColorU8 Cc = unpackU8(packColor(textureUnit.envColor));
        ColorU8 Cv = Cf;

        switch (textureUnit.envMode)
        {
        case TexEnvMode::REPLACE:
            Cv = Ct;
            break;
        case TexEnvMode::MODULATE:
            Cv.r = (Cf.r * Ct.r + 128) >> 8;
            Cv.g = (Cf.g * Ct.g + 128) >> 8;
            Cv.b = (Cf.b * Ct.b + 128) >> 8;
            Cv.a = (Cf.a * Ct.a + 128) >> 8;
            break;
        case TexEnvMode::DECAL:
            Cv.r = ((255 - Ct.a) * Cf.r + Ct.a * Ct.r + 128) >> 8;
            Cv.g = ((255 - Ct.a) * Cf.g + Ct.a * Ct.g + 128) >> 8;
            Cv.b = ((255 - Ct.a) * Cf.b + Ct.a * Ct.b + 128) >> 8;
            Cv.a = Cf.a;
            break;
        case TexEnvMode::BLEND:
            Cv.r = ((255 - Ct.r) * Cf.r + Ct.r * Cc.r + 128) >> 8;
            Cv.g = ((255 - Ct.g) * Cf.g + Ct.g * Cc.g + 128) >> 8;
            Cv.b = ((255 - Ct.b) * Cf.b + Ct.b * Cc.b + 128) >> 8;
            Cv.a = (Cf.a * Ct.a + 128) >> 8;
            break;
        case TexEnvMode::ADD:
            Cv.r = std::min((int)255, (int)Cf.r + Ct.r);
            Cv.g = std::min((int)255, (int)Cf.g + Ct.g);
            Cv.b = std::min((int)255, (int)Cf.b + Ct.b);
            Cv.a = (Cf.a * Ct.a + 128) >> 8;
            break;
        }
        Cf_raw = packU8(Cv);
    }

    return Cf_raw;
}
