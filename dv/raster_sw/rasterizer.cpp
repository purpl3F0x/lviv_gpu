#include "rasterizer.h"
#include "Vraster_core.h"
#include "verilated.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>


extern "C" double dpi_bits_to_float(uint32_t bits)
{
    union {
        uint32_t i;
        float f;
    } u;
    u.i = bits;
    return (double)u.f;
}

extern "C" uint32_t dpi_float_to_bits(double val)
{
    union {
        uint32_t i;
        float f;
    } u;
    u.f = (float)val;
    return u.i;
}

// Statically instantiated Verilator objects for hardware verification
static VerilatedContext *s_contextp = nullptr;
static Vraster_core *s_top = nullptr;
int s_failed_count = 0;

static void init_verilator()
{
    if (!s_contextp)
    {
        s_contextp = new VerilatedContext();
        s_top = new Vraster_core{s_contextp};

        // Assert reset
        s_top->clk = 0;
        s_top->rst_n = 0;
        s_top->valid_in = 0;
        s_top->ready_in = 0;
        s_top->eval();

        // Toggle clock a few times
        for (int i = 0; i < 10; ++i)
        {
            s_top->clk = 1;
            s_top->eval();
            s_top->clk = 0;
            s_top->eval();
        }

        s_top->rst_n = 1;
        s_top->eval();
    }
}

static void step_clock()
{
    s_contextp->timeInc(1);
    s_top->clk = 1;
    s_top->eval();

    s_contextp->timeInc(1);
    s_top->clk = 0;
    s_top->eval();
}

static void pack_vertex_sw(VlWide<10> &v_in, const Vertex_ScreenSpace &v)
{
    v_in[9] = *reinterpret_cast<const uint32_t *>(&v.position.x);
    v_in[8] = *reinterpret_cast<const uint32_t *>(&v.position.y);
    v_in[7] = *reinterpret_cast<const uint32_t *>(&v.position.z);
    v_in[6] = *reinterpret_cast<const uint32_t *>(&v.position.w);
    v_in[5] = *reinterpret_cast<const uint32_t *>(&v.normal_over_w.x);
    v_in[4] = *reinterpret_cast<const uint32_t *>(&v.normal_over_w.y);
    v_in[3] = *reinterpret_cast<const uint32_t *>(&v.normal_over_w.z);
    v_in[2] = v.color;
    v_in[1] = *reinterpret_cast<const uint32_t *>(&v.texcoord_over_w.x);
    v_in[0] = *reinterpret_cast<const uint32_t *>(&v.texcoord_over_w.y);
}

static bool compare_floats_sw(float actual, float expected, const std::string &name, float tolerance = 1e-4f)
{
    if (std::isnan(actual) && std::isnan(expected))
        return true;

    uint32_t act_raw = *reinterpret_cast<uint32_t *>(&actual);
    uint32_t exp_raw = *reinterpret_cast<uint32_t *>(&expected);
    if (act_raw == exp_raw)
        return true;

    float diff = std::abs(actual - expected);
    if (diff > tolerance)
    {
        if (expected != 0.0f && (diff / std::abs(expected)) < tolerance)
        {
            return true;
        }
        std::cout << "  Mismatch in " << name << ": Actual = " << actual << " (0x" << std::hex << act_raw
                  << "), Expected = " << expected << " (0x" << exp_raw << std::dec << "), Diff = " << diff << "\n";
        return false;
    }
    return true;
}

static void verify_hardware_triangle(const Vertex_ScreenSpace &v0, const Vertex_ScreenSpace &v1,
                                     const Vertex_ScreenSpace &v2, int tile_x_id, int tile_y_id, float e0_row,
                                     float e1_row, float e2_row, float e0_dx, float e0_dy, float e1_dx, float e1_dy,
                                     float e2_dx, float e2_dy, float invArea, int minX, int minY, int maxX, int maxY)
{
    init_verilator();

    // Wait until ready_out is high
    int timeout = 0;
    while (!s_top->ready_out)
    {
        s_top->valid_in = 0;
        step_clock();
        if (++timeout > 1000)
        {
            std::cerr << "Timeout waiting for ready_out in SW rasterizer integration!" << std::endl;
            exit(1);
        }
    }

    // Send V0
    pack_vertex_sw(s_top->vertex_in, v0);
    s_top->tile_x_id = tile_x_id;
    s_top->tile_y_id = tile_y_id;
    s_top->valid_in = 1;
    step_clock();

    // Send V1
    pack_vertex_sw(s_top->vertex_in, v1);
    s_top->valid_in = 1;
    step_clock();

    // Send V2
    pack_vertex_sw(s_top->vertex_in, v2);
    s_top->valid_in = 1;
    step_clock();

    // Clear valid_in
    s_top->valid_in = 0;

    // Wait for valid_out
    timeout = 0;
    while (!s_top->valid_out)
    {
        step_clock();
        if (++timeout > 1000)
        {
            std::cerr << "Timeout waiting for valid_out in SW rasterizer integration!" << std::endl;
            exit(1);
        }
    }

    // Retrieve outputs
    float act_e0_row = *reinterpret_cast<float *>(&s_top->out_e0_00);
    float act_e1_row = *reinterpret_cast<float *>(&s_top->out_e1_00);
    float act_e2_row = *reinterpret_cast<float *>(&s_top->out_e2_00);
    float act_e0_10 = *reinterpret_cast<float *>(&s_top->out_e0_10);
    float act_e1_10 = *reinterpret_cast<float *>(&s_top->out_e1_10);
    float act_e2_10 = *reinterpret_cast<float *>(&s_top->out_e2_10);
    float act_e0_01 = *reinterpret_cast<float *>(&s_top->out_e0_01);
    float act_e1_01 = *reinterpret_cast<float *>(&s_top->out_e1_01);
    float act_e2_01 = *reinterpret_cast<float *>(&s_top->out_e2_01);
    float act_e0_11 = *reinterpret_cast<float *>(&s_top->out_e0_11);
    float act_e1_11 = *reinterpret_cast<float *>(&s_top->out_e1_11);
    float act_e2_11 = *reinterpret_cast<float *>(&s_top->out_e2_11);
    float act_e0_dx = *reinterpret_cast<float *>(&s_top->out_e0_dx_2x);
    float act_e0_dy = *reinterpret_cast<float *>(&s_top->out_e0_dy_2x);
    float act_e1_dx = *reinterpret_cast<float *>(&s_top->out_e1_dx_2x);
    float act_e1_dy = *reinterpret_cast<float *>(&s_top->out_e1_dy_2x);
    float act_e2_dx = *reinterpret_cast<float *>(&s_top->out_e2_dx_2x);
    float act_e2_dy = *reinterpret_cast<float *>(&s_top->out_e2_dy_2x);
    float act_invArea = *reinterpret_cast<float *>(&s_top->out_invArea);
    float act_minX_local = (float)s_top->out_minX_local;
    float act_minY_local = (float)s_top->out_minY_local;
    float act_width = (float)s_top->out_width;
    float act_height = (float)s_top->out_height;

    float p_min_x_even = (float)minX + 0.5f;
    float p_min_y_even = (float)minY + 0.5f;

    auto edgeFunc = [](float ax, float ay, float bx, float by, float cx, float cy) {
        return (cx - ax) * (by - ay) - (cy - ay) * (bx - ax);
    };

    float exp_e0_row = edgeFunc(v1.position.x, v1.position.y, v2.position.x, v2.position.y, p_min_x_even, p_min_y_even);
    float exp_e1_row = edgeFunc(v2.position.x, v2.position.y, v0.position.x, v0.position.y, p_min_x_even, p_min_y_even);
    float exp_e2_row = edgeFunc(v0.position.x, v0.position.y, v1.position.x, v1.position.y, p_min_x_even, p_min_y_even);

    float exp_e0_10 = exp_e0_row + e0_dx;
    float exp_e1_10 = exp_e1_row + e1_dx;
    float exp_e2_10 = exp_e2_row + e2_dx;

    float exp_e0_01 = exp_e0_row + e0_dy;
    float exp_e1_01 = exp_e1_row + e1_dy;
    float exp_e2_01 = exp_e2_row + e2_dy;

    float exp_e0_11 = exp_e0_row + e0_dx + e0_dy;
    float exp_e1_11 = exp_e1_row + e1_dx + e1_dy;
    float exp_e2_11 = exp_e2_row + e2_dx + e2_dy;

    float exp_minX_local = (float)(minX & 127);
    float exp_minY_local = (float)(minY & 127);
    float exp_width = (float)(maxX - minX);
    float exp_height = (float)(maxY - minY);

    float exp_e0_dx_2x = e0_dx + e0_dx;
    float exp_e0_dy_2x = e0_dy + e0_dy;
    float exp_e1_dx_2x = e1_dx + e1_dx;
    float exp_e1_dy_2x = e1_dy + e1_dy;
    float exp_e2_dx_2x = e2_dx + e2_dx;
    float exp_e2_dy_2x = e2_dy + e2_dy;

    // Check match
    bool match = true;
    match &= compare_floats_sw(act_e0_row, exp_e0_row, "out_e0_row", 2e-3f);
    match &= compare_floats_sw(act_e1_row, exp_e1_row, "out_e1_row", 2e-3f);
    match &= compare_floats_sw(act_e2_row, exp_e2_row, "out_e2_row", 2e-3f);
    match &= compare_floats_sw(act_e0_10, exp_e0_10, "out_e0_10", 2e-3f);
    match &= compare_floats_sw(act_e1_10, exp_e1_10, "out_e1_10", 2e-3f);
    match &= compare_floats_sw(act_e2_10, exp_e2_10, "out_e2_10", 2e-3f);
    match &= compare_floats_sw(act_e0_01, exp_e0_01, "out_e0_01", 2e-3f);
    match &= compare_floats_sw(act_e1_01, exp_e1_01, "out_e1_01", 2e-3f);
    match &= compare_floats_sw(act_e2_01, exp_e2_01, "out_e2_01", 2e-3f);
    match &= compare_floats_sw(act_e0_11, exp_e0_11, "out_e0_11", 2e-3f);
    match &= compare_floats_sw(act_e1_11, exp_e1_11, "out_e1_11", 2e-3f);
    match &= compare_floats_sw(act_e2_11, exp_e2_11, "out_e2_11", 2e-3f);
    match &= compare_floats_sw(act_e0_dx, exp_e0_dx_2x, "out_e0_dx_2x");
    match &= compare_floats_sw(act_e0_dy, exp_e0_dy_2x, "out_e0_dy_2x");
    match &= compare_floats_sw(act_e1_dx, exp_e1_dx_2x, "out_e1_dx_2x");
    match &= compare_floats_sw(act_e1_dy, exp_e1_dy_2x, "out_e1_dy_2x");
    match &= compare_floats_sw(act_e2_dx, exp_e2_dx_2x, "out_e2_dx_2x");
    match &= compare_floats_sw(act_e2_dy, exp_e2_dy_2x, "out_e2_dy_2x");
    match &= compare_floats_sw(act_invArea, invArea, "out_invArea", 1e-3f);
    match &= compare_floats_sw(act_minX_local, exp_minX_local, "out_minX_local");
    match &= compare_floats_sw(act_minY_local, exp_minY_local, "out_minY_local");
    match &= compare_floats_sw(act_width, exp_width, "out_width");
    match &= compare_floats_sw(act_height, exp_height, "out_height");

    if (!match)
    {
        s_failed_count++;
        std::cout << "Mismatch found at tile (" << tile_x_id << ", " << tile_y_id << ")!\n";
        std::cout << "Vertices: \n"
                  << "  v0 = (" << v0.position.x << ", " << v0.position.y << ")\n"
                  << "  v1 = (" << v1.position.x << ", " << v1.position.y << ")\n"
                  << "  v2 = (" << v2.position.x << ", " << v2.position.y << ")\n";
        if (s_failed_count > 10)
        {
            std::cout << "Too many failures! Terminating simulation.\n";
            exit(1);
        }
    }

    // Handshake complete - set ready_in to clear valid_out
    s_top->ready_in = 1;
    step_clock();
    s_top->ready_in = 0;
}

struct ColorU8
{
    uint8_t r, g, b, a;
};

ColorU8 unpackU8(uint32_t c);
uint32_t packU8(const ColorU8 &c);

// Helper forward declarations
Vec4 unpackColor(uint32_t c);
uint32_t packColor(const Vec4 &c);

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

    for (size_t i = 0; i < triangle_list.size(); ++i)
    {
        const auto &tri = triangle_list[i];
        const Vertex_ScreenSpace &v0 = tri[0];
        const Vertex_ScreenSpace &v1 = tri[1];
        const Vertex_ScreenSpace &v2 = tri[2];

        // Triangle bounding box
        int triMinX = std::max(0, math_floor(std::min({v0.position.x, v1.position.x, v2.position.x})));
        int triMinY = std::max(0, math_floor(std::min({v0.position.y, v1.position.y, v2.position.y})));
        int triMaxX = std::min(fb->width - 1, math_ceil(std::max({v0.position.x, v1.position.x, v2.position.x})));
        int triMaxY = std::min(fb->height - 1, math_ceil(std::max({v0.position.y, v1.position.y, v2.position.y})));

        if (triMinX > triMaxX || triMinY > triMaxY)
            continue;

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
}

#include <cstdio>

extern void savePNG(const Framebuffer &fb, const char *filename);

void Rasterizer::rasterizeBins(bool dump_bins)
{
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
}

// -----------------------------------------------------------------------------
// STEP 4: Rasterization (Edge Equations & Perspective-Correct Barycentric)
// -----------------------------------------------------------------------------
void Rasterizer::rasterizeTriangle(const Vertex_ScreenSpace &v0, const Vertex_ScreenSpace &v1,
                                   const Vertex_ScreenSpace &v2, int binMinX, int binMinY, int binMaxX, int binMaxY,
                                   uint32_t *tileColor, float *tileDepth)
{

    // Toggle the type of the interpolation her
    // typedef ap_fixed<44, 21> interp_type;
    typedef float interp_type;
    // typedef ap_fixed<38, 14> bb_type;

    // --- STEP 1: Edge Equations Setup ---
    const tvec2<interp_type> p0(v0.position.x, v0.position.y);
    const tvec2<interp_type> p1(v1.position.x, v1.position.y);
    const tvec2<interp_type> p2(v2.position.x, v2.position.y);

    // Extract colors for linear interpolation (using 8-bit channels 0-255)
    const ColorU8 uc0 = unpackU8(v0.color);
    const ColorU8 uc1 = unpackU8(v1.color);
    const ColorU8 uc2 = unpackU8(v2.color);
    const tvec4<interp_type> c0(uc0.r, uc0.g, uc0.b, uc0.a);
    const tvec4<interp_type> c1(uc1.r, uc1.g, uc1.b, uc1.a);
    const tvec4<interp_type> c2(uc2.r, uc2.g, uc2.b, uc2.a);

    // Triangle Area (for Barycentric normalization)
    interp_type area = edgeFunction(p0, p1, p2);
    // if (area == 0) return;
    // Calculate invArea precisely using the chosen interpolation type (done once per triangle)
    interp_type invArea = interp_type(1.0f) / (interp_type)area;

    // Calculate the triangle's bounding box in screen space
    int triMinX = std::min({math_floor(v0.position.x), math_floor(v1.position.x), math_floor(v2.position.x)});
    int triMinY = std::min({math_floor(v0.position.y), math_floor(v1.position.y), math_floor(v2.position.y)});
    int triMaxX = std::max({math_ceil(v0.position.x), math_ceil(v1.position.x), math_ceil(v2.position.x)});
    int triMaxY = std::max({math_ceil(v0.position.y), math_ceil(v1.position.y), math_ceil(v2.position.y)});

    // Align to 2x2 blocks: min is even (0, 2, 4...), max is odd (1, 3, 5...)
    triMinX = triMinX & ~1;
    triMinY = triMinY & ~1;
    triMaxX = triMaxX | 1;
    triMaxY = triMaxY | 1;

    // Intersect the triangle's bounding box with the tile's bounding box
    int minX = std::max(binMinX, triMinX);
    int minY = std::max(binMinY, triMinY);
    int maxX = std::min(binMaxX, triMaxX);
    int maxY = std::min(binMaxY, triMaxY);

    // Calculate initial edge functions at the center of the top-left pixel of the intersected bounding box
    tvec2<interp_type> p_min(interp_type(minX) + interp_type(0.5f), interp_type(minY) + interp_type(0.5f));

    // Track EXACT edge functions (unnormalized) to avoid precision loss across scanlines
    interp_type e0_row = edgeFunction(p1, p2, p_min);
    interp_type e1_row = edgeFunction(p2, p0, p_min);
    interp_type e2_row = edgeFunction(p0, p1, p_min);

    // Step increments for each step in X
    interp_type e0_dx = (p2.y - p1.y);
    interp_type e1_dx = (p0.y - p2.y);
    interp_type e2_dx = (p1.y - p0.y);

    // Step increments for each step in Y
    interp_type e0_dy = (p1.x - p2.x);
    interp_type e1_dy = (p2.x - p0.x);
    interp_type e2_dy = (p0.x - p1.x);

    // Call Verilator verification
    verify_hardware_triangle(v0, v1, v2, binMinX / BIN_SIZE, binMinY / BIN_SIZE, (float)e0_row, (float)e1_row,
                             (float)e2_row, (float)e0_dx, (float)e0_dy, (float)e1_dx, (float)e1_dy, (float)e2_dx,
                             (float)e2_dy, (float)invArea, minX, minY, maxX, maxY);

    // --- HW STEP 2: Scanline Traversal / Rasterization ---
    // Rasterize within the intersected bounding box
    for (int y = minY; y <= maxY; ++y)
    {
        interp_type e0 = e0_row;
        interp_type e1 = e1_row;
        interp_type e2 = e2_row;

        for (int x = minX; x <= maxX; ++x)
        {
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
                    auto normal_over_w =
                        tvec3<interp_type>(v0.normal_over_w.x, v0.normal_over_w.y, v0.normal_over_w.z) * iw0 +
                        tvec3<interp_type>(v1.normal_over_w.x, v1.normal_over_w.y, v1.normal_over_w.z) * iw1 +
                        tvec3<interp_type>(v2.normal_over_w.x, v2.normal_over_w.y, v2.normal_over_w.z) * iw2;

                    auto texcoord_over_w = tvec2<interp_type>(v0.texcoord_over_w.x, v0.texcoord_over_w.y) * iw0 +
                                           tvec2<interp_type>(v1.texcoord_over_w.x, v1.texcoord_over_w.y) * iw1 +
                                           tvec2<interp_type>(v2.texcoord_over_w.x, v2.texcoord_over_w.y) * iw2;

                    auto color_interp = c0 * iw0 + c1 * iw1 + c2 * iw2;

                    interp_type w = interp_type(1.0f) / invW;

                    // --- STEP 8: Programmable Fragment Shader Assembly ---
                    Fragment_In fIn;
                    fIn.screenCoord = tvec2<float>(x, y);
                    fIn.depth = z;
                    fIn.normal = tvec3<float>(normal_over_w.x * w, normal_over_w.y * w, normal_over_w.z * w);
                    fIn.texcoord = tvec2<float>(texcoord_over_w.x * w, texcoord_over_w.y * w);

                    ColorU8 c_interp_u8 = {(uint8_t)std::max(0, std::min(255, (int)color_interp.x)),
                                           (uint8_t)std::max(0, std::min(255, (int)color_interp.y)),
                                           (uint8_t)std::max(0, std::min(255, (int)color_interp.z)),
                                           (uint8_t)std::max(0, std::min(255, (int)color_interp.w))};
                    fIn.color = packU8(c_interp_u8);

                    uint32_t finalColor = fragmentShader(fIn);

                    // --- STEP 9: Write to Framebuffer ---
                    tileColor[tileIdx] = finalColor;
                }
            }
            e0 += e0_dx;
            e1 += e1_dx;
            e2 += e2_dx;
        }
        e0_row += e0_dy;
        e1_row += e1_dy;
        e2_row += e2_dy;
    }
}

// -----------------------------------------------------------------------------
// STEP 5: Fragment Shader
// -----------------------------------------------------------------------------
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
