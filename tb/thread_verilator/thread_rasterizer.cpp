#include "../../dv/raster_sw/rasterizer.h"

#include <ap_fixed.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <utility>
#include <vector>

#include <verilated.h>
#include "Vthread_verilator_wrap.h"

namespace {

constexpr int BIN_SIZE_HW = Rasterizer::BIN_SIZE;
constexpr int THREAD_PIXEL_ADDR_SPACE = BIN_SIZE_HW * BIN_SIZE_HW;
constexpr int HW_THREADS = 4;
constexpr int THREAD_TILE_W = BIN_SIZE_HW / 2;
constexpr int THREAD_TILE_H = BIN_SIZE_HW / 2;
constexpr int THREAD_TILE_SHIFT = std::countr_zero(static_cast<unsigned>(THREAD_TILE_W));
constexpr uint32_t THREAD_TILE_MASK = static_cast<uint32_t>(THREAD_TILE_W - 1);
static_assert((THREAD_TILE_W & (THREAD_TILE_W - 1)) == 0, "THREAD_TILE_W must be power-of-two");
constexpr const char* ANSI_RED = "\x1b[31m";
constexpr const char* ANSI_YELLOW = "\x1b[33m";
constexpr const char* ANSI_RESET = "\x1b[0m";

std::vector<uint32_t> g_ref_color_buffer;
std::vector<float> g_ref_depth_buffer;

static uint32_t fbits(float v)
{
    uint32_t u = 0;
    std::memcpy(&u, &v, sizeof(u));
    return u;
}

static float fr(uint32_t u)
{
    float v = 0.0f;
    std::memcpy(&v, &u, sizeof(v));
    return v;
}

static uint32_t to_uq5_13(float v)
{
    float c = std::min(31.9998779f, std::max(0.0f, v));
    uint32_t q = static_cast<uint32_t>(c * 8192.0f + 0.5f);
    if (q > 0x3FFFFu) {
        q = 0x3FFFFu;
    }
    return q;
}

struct ThreadToken {
    uint32_t thread_id;
    uint32_t addr;
    uint32_t tex_id;
    uint32_t texture_mode_u;
    uint32_t texture_mode_v;
    uint32_t texture_function;
    uint32_t inv_area;
    uint32_t e2;
    uint32_t e1;
    uint32_t e0;
    uint32_t v2_v;
    uint32_t v2_u;
    uint32_t v2_w;
    uint32_t v2_z;
    uint32_t v1_v;
    uint32_t v1_u;
    uint32_t v1_w;
    uint32_t v1_z;
    uint32_t v0_v;
    uint32_t v0_u;
    uint32_t v0_w;
    uint32_t v0_z;
    uint32_t v0_color_a;
    uint32_t v0_color_r;
    uint32_t v0_color_g;
    uint32_t v0_color_b;
    uint32_t v1_color_a;
    uint32_t v1_color_r;
    uint32_t v1_color_g;
    uint32_t v1_color_b;
    uint32_t v2_color_a;
    uint32_t v2_color_r;
    uint32_t v2_color_g;
    uint32_t v2_color_b;
};

class ThreadRasterCore {
  public:
    ThreadRasterCore()
    {
        Verilated::traceEverOn(false);
                for (int i = 0; i < HW_THREADS; ++i) {
                        dut_[i] = new Vthread_verilator_wrap();
                }
        resetInternal();
    }

    ~ThreadRasterCore()
    {
        for (int i = 0; i < HW_THREADS; ++i) {
            delete dut_[i];
        }
    }

    void resetInternal()
    {
        for (int t = 0; t < HW_THREADS; ++t) {
            dut_[t]->clk = 0;
            dut_[t]->rst_n = 0;
            dut_[t]->valid_in = 0;
            clearInputToken(t);
            dut_[t]->z_rd_data = fbits(1.0f);
        }

        for (int i = 0; i < 8; ++i) {
            tickHalf(0);
            tickHalf(1);
        }

        for (int t = 0; t < HW_THREADS; ++t) {
            dut_[t]->rst_n = 1;
        }
        for (int i = 0; i < 4; ++i) {
            tickHalf(0);
            tickHalf(1);
        }
    }

    void run(const std::vector<ThreadToken>& tokens, int binMinX, int binMinY, uint32_t* tileColor,
             float* tileDepth, std::vector<std::pair<uint32_t, uint32_t>>* fb_writes)
    {
        // Reset once per bin so z-buffer is scrubbed for each tile, but not per triangle.
        if (!has_active_bin_ || active_bin_min_x_ != binMinX || active_bin_min_y_ != binMinY) {
            resetInternal();
            has_active_bin_ = true;
            active_bin_min_x_ = binMinX;
            active_bin_min_y_ = binMinY;
        }

        std::array<std::vector<ThreadToken>, HW_THREADS> perThreadTokens;
        for (const auto& tok : tokens) {
            uint32_t tid = tok.thread_id & 0x3u;
            perThreadTokens[tid].push_back(tok);
        }

        for (int tid = 0; tid < HW_THREADS; ++tid) {
            size_t zready_guard = 0;
            while (dut_[tid]->z_buf_ready == 0) {
                tickHalfSingle(tid, 0);
                dut_[tid]->valid_in = 0;
                clearInputToken(tid);
                driveZReadData(tid);
                tickHalfSingle(tid, 1);
                captureWrites(tid, tileColor, tileDepth, fb_writes);

                zready_guard++;
                if (zready_guard > 300000) {
                    std::cerr << "[THREAD_CMP][ERROR] z_buffer_ram not ready after reset (tid=" << tid << ")"
                              << std::endl;
                    break;
                }
            }

            size_t idx = 0;
            size_t stall_guard = 0;

            while (idx < perThreadTokens[tid].size()) {
                tickHalfSingle(tid, 0);

                bool can_send = (dut_[tid]->ready_out != 0) && (dut_[tid]->z_buf_ready != 0);
                if (can_send) {
                    dut_[tid]->valid_in = 1;
                    driveToken(tid, perThreadTokens[tid][idx]);
                } else {
                    dut_[tid]->valid_in = 0;
                    clearInputToken(tid);
                }

                driveZReadData(tid);
                tickHalfSingle(tid, 1);

                captureWrites(tid, tileColor, tileDepth, fb_writes);

                if (can_send) {
                    idx++;
                    stall_guard = 0;
                } else {
                    stall_guard++;
                    if (stall_guard > 200000) {
                        break;
                    }
                }
            }

            dut_[tid]->valid_in = 0;
            clearInputToken(tid);

            for (int i = 0; i < 256; ++i) {
                tickHalfSingle(tid, 0);
                driveZReadData(tid);
                tickHalfSingle(tid, 1);
                captureWrites(tid, tileColor, tileDepth, fb_writes);
            }
        }
    }

    static ThreadRasterCore& instance()
    {
        static ThreadRasterCore inst;
        return inst;
    }

  private:
    std::array<Vthread_verilator_wrap*, HW_THREADS> dut_{};
    bool has_active_bin_ = false;
    int active_bin_min_x_ = 0;
    int active_bin_min_y_ = 0;

    void tickHalf(int clk)
    {
        for (int t = 0; t < HW_THREADS; ++t) {
            dut_[t]->clk = clk;
            dut_[t]->eval();
        }
    }

    void tickHalfSingle(int tid, int clk)
    {
        dut_[tid]->clk = clk;
        dut_[tid]->eval();
    }

    static uint32_t tileAddrFromThreadAddr(uint32_t tid, uint32_t localAddr)
    {
        uint32_t x_local = (localAddr & THREAD_TILE_MASK);
        uint32_t y_local = ((localAddr >> THREAD_TILE_SHIFT) & THREAD_TILE_MASK);
        uint32_t x = (x_local << 1) | (tid & 0x1u);
        uint32_t y = (y_local << 1) | ((tid >> 1) & 0x1u);
        return y * static_cast<uint32_t>(BIN_SIZE_HW) + x;
    }

    void driveZReadData(int tid)
    {
        // z_rd_data is driven by z_buffer_ram inside the wrapper.
        dut_[tid]->z_rd_data = fbits(1.0f);
    }

    void captureWrites(int tid, uint32_t* tileColor, float* tileDepth,
                       std::vector<std::pair<uint32_t, uint32_t>>* fb_writes)
    {
        if (dut_[tid]->z_buf_ready && dut_[tid]->z_wr_en) {
            uint32_t localAddr = static_cast<uint32_t>(dut_[tid]->z_wr_addr);
            uint32_t idx = tileAddrFromThreadAddr(static_cast<uint32_t>(tid), localAddr);
            if (idx < THREAD_PIXEL_ADDR_SPACE) {
                tileDepth[idx] = fr(static_cast<uint32_t>(dut_[tid]->z_wr_data));
            }
        }

        if (dut_[tid]->out_fb_we) {
            uint32_t localAddr = static_cast<uint32_t>(dut_[tid]->out_fb_addr);
            uint32_t idx = tileAddrFromThreadAddr(static_cast<uint32_t>(tid), localAddr);
            if (idx < THREAD_PIXEL_ADDR_SPACE) {
                tileColor[idx] = static_cast<uint32_t>(dut_[tid]->out_fb_color);
                if (fb_writes) {
                    fb_writes->push_back({idx, static_cast<uint32_t>(dut_[tid]->out_fb_color)});
                }
            }
        }
    }

    void driveToken(int tid, const ThreadToken& t)
    {
        dut_[tid]->in_addr = t.addr;
        dut_[tid]->in_tex_id = t.tex_id;
        dut_[tid]->in_texture_mode_u = t.texture_mode_u;
        dut_[tid]->in_texture_mode_v = t.texture_mode_v;
        dut_[tid]->in_texture_function = t.texture_function;
        dut_[tid]->in_inv_area = t.inv_area;
        dut_[tid]->in_e2 = t.e2;
        dut_[tid]->in_e1 = t.e1;
        dut_[tid]->in_e0 = t.e0;
        dut_[tid]->in_v2_v = t.v2_v;
        dut_[tid]->in_v2_u = t.v2_u;
        dut_[tid]->in_v2_w = t.v2_w;
        dut_[tid]->in_v2_z = t.v2_z;
        dut_[tid]->in_v1_v = t.v1_v;
        dut_[tid]->in_v1_u = t.v1_u;
        dut_[tid]->in_v1_w = t.v1_w;
        dut_[tid]->in_v1_z = t.v1_z;
        dut_[tid]->in_v0_v = t.v0_v;
        dut_[tid]->in_v0_u = t.v0_u;
        dut_[tid]->in_v0_w = t.v0_w;
        dut_[tid]->in_v0_z = t.v0_z;
        dut_[tid]->in_v0_color_a = t.v0_color_a;
        dut_[tid]->in_v0_color_r = t.v0_color_r;
        dut_[tid]->in_v0_color_g = t.v0_color_g;
        dut_[tid]->in_v0_color_b = t.v0_color_b;
        dut_[tid]->in_v1_color_a = t.v1_color_a;
        dut_[tid]->in_v1_color_r = t.v1_color_r;
        dut_[tid]->in_v1_color_g = t.v1_color_g;
        dut_[tid]->in_v1_color_b = t.v1_color_b;
        dut_[tid]->in_v2_color_a = t.v2_color_a;
        dut_[tid]->in_v2_color_r = t.v2_color_r;
        dut_[tid]->in_v2_color_g = t.v2_color_g;
        dut_[tid]->in_v2_color_b = t.v2_color_b;
    }

    void clearInputToken(int tid)
    {
        dut_[tid]->in_addr = 0;
        dut_[tid]->in_tex_id = 0;
        dut_[tid]->in_texture_mode_u = 0;
        dut_[tid]->in_texture_mode_v = 0;
        dut_[tid]->in_texture_function = 4;
        dut_[tid]->in_inv_area = fbits(1.0f);
        dut_[tid]->in_e2 = 0;
        dut_[tid]->in_e1 = 0;
        dut_[tid]->in_e0 = 0;
        dut_[tid]->in_v2_v = 0;
        dut_[tid]->in_v2_u = 0;
        dut_[tid]->in_v2_w = fbits(1.0f);
        dut_[tid]->in_v2_z = 0;
        dut_[tid]->in_v1_v = 0;
        dut_[tid]->in_v1_u = 0;
        dut_[tid]->in_v1_w = fbits(1.0f);
        dut_[tid]->in_v1_z = 0;
        dut_[tid]->in_v0_v = 0;
        dut_[tid]->in_v0_u = 0;
        dut_[tid]->in_v0_w = fbits(1.0f);
        dut_[tid]->in_v0_z = 0;
        dut_[tid]->in_v0_color_a = 0;
        dut_[tid]->in_v0_color_r = 0;
        dut_[tid]->in_v0_color_g = 0;
        dut_[tid]->in_v0_color_b = 0;
        dut_[tid]->in_v1_color_a = 0;
        dut_[tid]->in_v1_color_r = 0;
        dut_[tid]->in_v1_color_g = 0;
        dut_[tid]->in_v1_color_b = 0;
        dut_[tid]->in_v2_color_a = 0;
        dut_[tid]->in_v2_color_r = 0;
        dut_[tid]->in_v2_color_g = 0;
        dut_[tid]->in_v2_color_b = 0;
    }
};

struct ColorU8 {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
};

static bool colorsCloseEnough(const ColorU8& lhs, const ColorU8& rhs)
{
    constexpr int kColorTolerance = 2;
    return std::abs(int(lhs.r) - int(rhs.r)) <= kColorTolerance &&
           std::abs(int(lhs.g) - int(rhs.g)) <= kColorTolerance &&
           std::abs(int(lhs.b) - int(rhs.b)) <= kColorTolerance &&
           std::abs(int(lhs.a) - int(rhs.a)) <= kColorTolerance;
}

static ColorU8 unpackU8(uint32_t c)
{
    ColorU8 out;
    out.r = static_cast<uint8_t>((c >> 16) & 0xFF);
    out.g = static_cast<uint8_t>((c >> 8) & 0xFF);
    out.b = static_cast<uint8_t>(c & 0xFF);
    out.a = static_cast<uint8_t>((c >> 24) & 0xFF);
    return out;
}

static uint32_t packU8(const ColorU8& c)
{
    return (static_cast<uint32_t>(c.a) << 24)
         | (static_cast<uint32_t>(c.r) << 16)
         | (static_cast<uint32_t>(c.g) << 8)
         | static_cast<uint32_t>(c.b);
}

static uint32_t texOpFromMode(const Rasterizer& rz)
{
    if (!rz.textureUnit.enabled || !rz.textureUnit.boundTexture) {
        return 0; // REPLACE (match RTL no-texture path)
    }

    switch (rz.textureUnit.envMode) {
    case TexEnvMode::REPLACE:
        return 0;
    case TexEnvMode::MODULATE:
        return 1;
    case TexEnvMode::DECAL:
        return 2;
    case TexEnvMode::BLEND:
        return 3;
    case TexEnvMode::ADD:
    default:
        return 4;
    }
}

} // namespace

void Rasterizer::rasterizeTriangle(const Vertex_ScreenSpace& v0, const Vertex_ScreenSpace& v1,
                                   const Vertex_ScreenSpace& v2, int binMinX, int binMinY, int binMaxX, int binMaxY,
                                   uint32_t* tileColor, float* tileDepth)
{
    typedef float interp_type;

    const tvec2<interp_type> p0(v0.position.x, v0.position.y);
    const tvec2<interp_type> p1(v1.position.x, v1.position.y);
    const tvec2<interp_type> p2(v2.position.x, v2.position.y);

    interp_type area = edgeFunction(p0, p1, p2);
    interp_type invArea = interp_type(1.0f) / area;

    typedef float bb_type;
    typedef int p_min_type;

    p_min_type triMinX = std::min(
        {math_floor((bb_type)v0.position.x), math_floor((bb_type)v1.position.x), math_floor((bb_type)v2.position.x)});
    p_min_type triMinY = std::min(
        {math_floor((bb_type)v0.position.y), math_floor((bb_type)v1.position.y), math_floor((bb_type)v2.position.y)});
    p_min_type triMaxX = std::max(
        {math_ceil((bb_type)v0.position.x), math_ceil((bb_type)v1.position.x), math_ceil((bb_type)v2.position.x)});
    p_min_type triMaxY = std::max(
        {math_ceil((bb_type)v0.position.y), math_ceil((bb_type)v1.position.y), math_ceil((bb_type)v2.position.y)});

    triMinX = triMinX & ~1;
    triMinY = triMinY & ~1;
    triMaxX = triMaxX | 1;
    triMaxY = triMaxY | 1;

    int minX = std::max(binMinX, triMinX);
    int minY = std::max(binMinY, triMinY);
    int maxX = std::min(binMaxX, triMaxX);
    int maxY = std::min(binMaxY, triMaxY);

    // Preserve triangle-vs-bin intersection bounds to avoid long full-bin
    // edge-equation walks that can accumulate numeric drift at large bin sizes.

    tvec2<interp_type> p_min(p_min_type(minX) + p_min_type(0.5f), p_min_type(minY) + p_min_type(0.5f));

    interp_type e0_row = edgeFunction(p1, p2, p_min);
    interp_type e1_row = edgeFunction(p2, p0, p_min);
    interp_type e2_row = edgeFunction(p0, p1, p_min);

    interp_type e0_dx = (p2.y - p1.y);
    interp_type e1_dx = (p0.y - p2.y);
    interp_type e2_dx = (p1.y - p0.y);

    interp_type e0_dy = (p1.x - p2.x);
    interp_type e1_dy = (p2.x - p0.x);
    interp_type e2_dy = (p0.x - p1.x);

    ColorU8 uc0 = unpackU8(v0.color);
    ColorU8 uc1 = unpackU8(v1.color);
    ColorU8 uc2 = unpackU8(v2.color);
    const tvec4<ap_fixed<17, 9, AP_RND>> c0(uc0.r, uc0.g, uc0.b, uc0.a);
    const tvec4<ap_fixed<17, 9, AP_RND>> c1(uc1.r, uc1.g, uc1.b, uc1.a);
    const tvec4<ap_fixed<17, 9, AP_RND>> c2(uc2.r, uc2.g, uc2.b, uc2.a);

    std::vector<ThreadToken> tokens;
    tokens.reserve((maxX - minX + 1) * (maxY - minY + 1));

    const bool compare_ref = true;

    std::vector<uint32_t> refColor;
    std::vector<float> refDepth;
    std::vector<std::pair<uint32_t, uint32_t>> refWrites;
    if (compare_ref) {
        const size_t fbSize = static_cast<size_t>(fb->width) * static_cast<size_t>(fb->height);
        if (g_ref_color_buffer.size() != fbSize || g_ref_depth_buffer.size() != fbSize) {
            g_ref_color_buffer = fb->colorBuffer;
            g_ref_depth_buffer = fb->depthBuffer;
        }

        refColor.assign(tileColor, tileColor + THREAD_PIXEL_ADDR_SPACE);
        refDepth.assign(tileDepth, tileDepth + THREAD_PIXEL_ADDR_SPACE);
        refWrites.reserve((maxX - minX + 1) * (maxY - minY + 1));
    }

    uint32_t op = texOpFromMode(*this);

    for (int y = minY; y <= maxY; ++y) {
        interp_type e0 = e0_row;
        interp_type e1 = e1_row;
        interp_type e2 = e2_row;

        for (int x = minX; x <= maxX; ++x) {
            pixel_draw_count++;

            if (e0 >= 0 && e1 >= 0 && e2 >= 0) {
                int tileIdx = (y - binMinY) * BIN_SIZE + (x - binMinX);
                if (tileIdx >= 0 && tileIdx < THREAD_PIXEL_ADDR_SPACE) {
                    int tileX = x - binMinX;
                    int tileY = y - binMinY;
                    uint32_t threadId = static_cast<uint32_t>(((tileY & 1) << 1) | (tileX & 1));
                    uint32_t localX = static_cast<uint32_t>(tileX >> 1);
                    uint32_t localY = static_cast<uint32_t>(tileY >> 1);

                    ThreadToken t{};
                    t.thread_id = threadId;
                    t.addr = (localY << THREAD_TILE_SHIFT) | localX;
                    t.tex_id = 0;
                    t.texture_mode_u = 0;
                    t.texture_mode_v = 0;
                    t.texture_function = op;
                    t.inv_area = fbits(invArea);
                    t.e0 = fbits(e0);
                    t.e1 = fbits(e1);
                    t.e2 = fbits(e2);

                    t.v0_z = fbits(v0.position.z);
                    t.v1_z = fbits(v1.position.z);
                    t.v2_z = fbits(v2.position.z);
                    t.v0_w = fbits(v0.position.w);
                    t.v1_w = fbits(v1.position.w);
                    t.v2_w = fbits(v2.position.w);

                    t.v0_u = to_uq5_13(v0.texcoord_over_w.x);
                    t.v1_u = to_uq5_13(v1.texcoord_over_w.x);
                    t.v2_u = to_uq5_13(v2.texcoord_over_w.x);
                    t.v0_v = to_uq5_13(v0.texcoord_over_w.y);
                    t.v1_v = to_uq5_13(v1.texcoord_over_w.y);
                    t.v2_v = to_uq5_13(v2.texcoord_over_w.y);

                    t.v0_color_a = uc0.a;
                    t.v0_color_r = uc0.r;
                    t.v0_color_g = uc0.g;
                    t.v0_color_b = uc0.b;
                    t.v1_color_a = uc1.a;
                    t.v1_color_r = uc1.r;
                    t.v1_color_g = uc1.g;
                    t.v1_color_b = uc1.b;
                    t.v2_color_a = uc2.a;
                    t.v2_color_r = uc2.r;
                    t.v2_color_g = uc2.g;
                    t.v2_color_b = uc2.b;

                    tokens.push_back(t);

                    if (compare_ref) {
                        interp_type iw0 = e0 * invArea;
                        interp_type iw1 = e1 * invArea;
                        interp_type iw2 = e2 * invArea;
                        interp_type z = iw0 * (interp_type)v0.position.z + iw1 * (interp_type)v1.position.z +
                                        iw2 * (interp_type)v2.position.z;

                        if (z < refDepth[tileIdx]) {
                            refDepth[tileIdx] = z;

                            interp_type invW = iw0 * (interp_type)v0.position.w +
                                               iw1 * (interp_type)v1.position.w +
                                               iw2 * (interp_type)v2.position.w;
                            interp_type w = interp_type(1.0f) / invW;

                            float t0_fp = iw0 * v0.position.w * w;
                            float t1_fp = iw1 * v1.position.w * w;
                            float t2_fp = iw2 * v2.position.w * w;

                            ap_fixed<25, 2, AP_RND> t0 = t0_fp;
                            ap_fixed<25, 2, AP_RND> t1 = t1_fp;
                            ap_fixed<25, 2, AP_RND> t2 = t2_fp;

                            Fragment_In fIn;
                            fIn.screenCoord = tvec2<float>(x, y);
                            fIn.depth = z;
                            fIn.texcoord.x = t0 * (ap_fixed<17, 4, AP_RND>)v0.texcoord_over_w.x +
                                             t1 * (ap_fixed<17, 4, AP_RND>)v1.texcoord_over_w.x +
                                             t2 * (ap_fixed<17, 4, AP_RND>)v2.texcoord_over_w.x;
                            fIn.texcoord.y = t0 * (ap_fixed<17, 4, AP_RND>)v0.texcoord_over_w.y +
                                             t1 * (ap_fixed<17, 4, AP_RND>)v1.texcoord_over_w.y +
                                             t2 * (ap_fixed<17, 4, AP_RND>)v2.texcoord_over_w.y;

                            auto color_interp_corrected =
                                c0 * (ap_fixed<17, 9, AP_RND>)t0 +
                                c1 * (ap_fixed<17, 9, AP_RND>)t1 +
                                c2 * (ap_fixed<17, 9, AP_RND>)t2;

                            ColorU8 c_interp_u8 = {
                                (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.x)),
                                (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.y)),
                                (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.z)),
                                (uint8_t)std::max(0, std::min(255, (int)color_interp_corrected.w))};
                            fIn.color = packU8(c_interp_u8);

                            uint32_t refFinalColor = fragmentShader(fIn);
                            refColor[tileIdx] = refFinalColor;
                            refWrites.push_back({static_cast<uint32_t>(tileIdx), refFinalColor});
                        }
                    }
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

    std::vector<std::pair<uint32_t, uint32_t>> hwWrites;
    hwWrites.reserve(tokens.size());
    // Keep the DUT running across triangles; per-triangle reset would force
    // a full z-buffer scrub each time and make simulation appear to hang.
    ThreadRasterCore::instance().run(tokens, binMinX, binMinY, tileColor, tileDepth,
                                     compare_ref ? &hwWrites : nullptr);

    if (compare_ref) {
        int finalColorMismatch = 0;
        int finalDepthMismatch = 0;
        for (int i = 0; i < THREAD_PIXEL_ADDR_SPACE; ++i) {
            if (!colorsCloseEnough(unpackU8(tileColor[i]), unpackU8(refColor[i]))) {
                finalColorMismatch++;
            }
            if (std::abs(tileDepth[i] - refDepth[i]) > 1e-4f) {
                finalDepthMismatch++;
            }
        }

        std::vector<int> hwWriteHits(THREAD_PIXEL_ADDR_SPACE, 0);
        std::vector<int> refWriteHits(THREAD_PIXEL_ADDR_SPACE, 0);
        for (const auto& w : hwWrites) {
            if (w.first < static_cast<uint32_t>(THREAD_PIXEL_ADDR_SPACE)) {
                hwWriteHits[w.first]++;
            }
        }
        for (const auto& w : refWrites) {
            if (w.first < static_cast<uint32_t>(THREAD_PIXEL_ADDR_SPACE)) {
                refWriteHits[w.first]++;
            }
        }

        int writeMismatch = 0;
        for (int i = 0; i < THREAD_PIXEL_ADDR_SPACE; ++i) {
            writeMismatch += std::abs(hwWriteHits[i] - refWriteHits[i]);
        }

        std::cout << "[THREAD_CMP] tokens=" << tokens.size()
                  << " ref_writes=" << refWrites.size()
                  << " hw_writes=" << hwWrites.size()
                  << " write_mismatch=" << writeMismatch
                  << " final_color_mismatch=" << finalColorMismatch
                  << " final_depth_mismatch=" << finalDepthMismatch
                  << "\n";

        if ((writeMismatch > 0 || finalColorMismatch > 0 || finalDepthMismatch > 0) && !hwWrites.empty() &&
            !refWrites.empty()) {
            size_t shown = 0;
            for (int i = 0; i < THREAD_PIXEL_ADDR_SPACE && shown < 8; ++i) {
                if (hwWriteHits[i] != refWriteHits[i]) {
                    std::cout << ANSI_RED << "[THREAD_CMP][WRITE_COUNT] addr=" << i
                              << " hw_hits=" << hwWriteHits[i]
                              << " ref_hits=" << refWriteHits[i]
                              << ANSI_RESET << "\n";
                    shown++;
                }
            }
        }

        const int tileW = binMaxX - binMinX + 1;
        const int tileH = binMaxY - binMinY + 1;
        for (int ty = 0; ty < tileH; ++ty) {
            for (int tx = 0; tx < tileW; ++tx) {
                const int localIdx = ty * BIN_SIZE + tx;
                const int globalIdx = (binMinY + ty) * fb->width + (binMinX + tx);
                g_ref_color_buffer[globalIdx] = refColor[localIdx];
                g_ref_depth_buffer[globalIdx] = refDepth[localIdx];
            }
        }
    }
}

bool threadCmpExportReferenceFramebuffer(Framebuffer* outFb)
{
    if (outFb == nullptr) {
        return false;
    }

    const size_t fbSize = static_cast<size_t>(outFb->width) * static_cast<size_t>(outFb->height);
    if (g_ref_color_buffer.size() != fbSize || g_ref_depth_buffer.size() != fbSize) {
        return false;
    }

    outFb->colorBuffer = g_ref_color_buffer;
    outFb->depthBuffer = g_ref_depth_buffer;
    return true;
}
