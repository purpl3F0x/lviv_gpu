#include "../../dv/raster_sw/rasterizer.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <utility>
#include <vector>

#include <verilated.h>
#include "Vthread_verilator_wrap.h"
#include "Vthread_verilator_wrap___024root.h"
#include "../../dv/raster_sw/stb_image_write.h"

namespace {

// Software-computed reference image, filled in parallel with the DUT
// comparison so the two can be visually diffed (output_ref.png/output_dut.png).
std::vector<uint32_t> g_ref_color;
int g_ref_width = 0;
int g_ref_height = 0;

constexpr int BIN_SIZE_HW = Rasterizer::BIN_SIZE;
constexpr int THREAD_PIXEL_ADDR_SPACE = BIN_SIZE_HW * BIN_SIZE_HW;
constexpr int HW_THREADS = 4;
constexpr int THREAD_TILE_W = BIN_SIZE_HW / 2;
constexpr int THREAD_TILE_SHIFT = std::countr_zero(static_cast<unsigned>(THREAD_TILE_W));
constexpr uint32_t THREAD_TILE_MASK = static_cast<uint32_t>(THREAD_TILE_W - 1);
static_assert((THREAD_TILE_W & (THREAD_TILE_W - 1)) == 0, "THREAD_TILE_W must be power-of-two");

static uint32_t fbits(float v)
{
    uint32_t u = 0;
    std::memcpy(&u, &v, sizeof(u));
    return u;
}

static float fr(uint32_t bits)
{
    float value = 0.0f;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

struct ColorU8 {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
};

static ColorU8 unpackU8(uint32_t c)
{
    return {
        static_cast<uint8_t>((c >> 16) & 0xFF),
        static_cast<uint8_t>((c >> 8) & 0xFF),
        static_cast<uint8_t>(c & 0xFF),
        static_cast<uint8_t>((c >> 24) & 0xFF)
    };
}

static uint32_t packU8(const ColorU8& c)
{
    return (static_cast<uint32_t>(c.a) << 24) |
           (static_cast<uint32_t>(c.r) << 16) |
           (static_cast<uint32_t>(c.g) << 8) |
           static_cast<uint32_t>(c.b);
}

static bool colorsCloseEnough(const ColorU8& lhs, const ColorU8& rhs)
{
    constexpr int kColorTolerance = 3;
    return std::abs(int(lhs.r) - int(rhs.r)) <= kColorTolerance &&
           std::abs(int(lhs.g) - int(rhs.g)) <= kColorTolerance &&
           std::abs(int(lhs.b) - int(rhs.b)) <= kColorTolerance &&
           std::abs(int(lhs.a) - int(rhs.a)) <= kColorTolerance;
}

// Quantizes to the RTL's actual SQ5.13 signed format (fx_texture_mul.sv sign-extends
// from bit 17), so negative per-vertex UVs (e.g. mesh vertices outside [-1,1]) survive.
static uint32_t to_sq5_13(float v)
{
    float c = std::min(15.9998779f, std::max(-16.0f, v));
    int32_t q = static_cast<int32_t>(std::lround(c * 8192.0f));
    if (q > 0x1FFFF) {
        q = 0x1FFFF;
    } else if (q < -0x20000) {
        q = -0x20000;
    }
    return static_cast<uint32_t>(q) & 0x3FFFFu;
}

// Bit-interleave (x, y) into the same swizzled pixel-word address that
// texture_address_generator.sv produces (bit i of x -> bit 2i, bit i of y -> bit 2i+1),
// matching MaxTexLog2=11 in the RTL.
static uint32_t interleaveTexelAddress(uint32_t x, uint32_t y)
{
    uint32_t word = 0;
    for (int i = 0; i < 11; ++i) {
        word |= ((x >> i) & 1u) << (2 * i);
        word |= ((y >> i) & 1u) << (2 * i + 1);
    }
    return word;
}

// Matches the software reference's sampleTexture() REPEAT wrap: u - floor(u),
// always in [0,1) regardless of sign. Left as a float; comparison against the
// HW's 12-bit u_norm_s1/v_norm_s1 register converts the register to a float
// instead of pre-quantizing this side, so the check reflects the actual
// software value rather than a second, possibly-inconsistent quantization.
static float computeExpectedUvFrac(float coord)
{
    return coord - std::floor(coord);
}

struct ThreadToken {
    uint32_t thread_id;
    uint32_t addr;
    uint32_t tex_id;
    uint32_t texture_mode_u;
    uint32_t texture_mode_v;
    uint32_t texture_function;
    uint32_t sfactor_op = 1;
    uint32_t dfactor_op = 0;
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

    // Software-computed (float) normalized UV fraction that the HW's
    // texture_address_generator's u_norm_s1/v_norm_s1 registers should match.
    float expected_u_frac = 0.0f;
    float expected_v_frac = 0.0f;
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
            dut_[t]->in_fb_rd_color = 0;
            framebuffer_read_pipe_[t].fill(0);
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

        int uvChecked = 0;
        int uvMismatch = 0;

        for (int tid = 0; tid < HW_THREADS; ++tid) {
            size_t zready_guard = 0;
            while (dut_[tid]->z_buf_ready == 0) {
                tickHalfSingle(tid, 0);
                dut_[tid]->valid_in = 0;
                clearInputToken(tid);
                driveZReadData(tid);
                driveFramebufferRead(tid, tileColor);
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
            size_t sentCount = 0;

            // In-order FIFO tracking of the address generator's normalize_uv()
            // registers: compare once per accepted token at the address stage.
            size_t uvIdx = 0;

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
                driveFramebufferRead(tid, tileColor);
                tickHalfSingle(tid, 1);

                captureWrites(tid, tileColor, tileDepth, fb_writes);
                checkUvNorm(tid, perThreadTokens[tid], uvIdx, sentCount, uvChecked, uvMismatch);

                if (can_send) {
                    idx++;
                    sentCount++;
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

            // Drain until the thread's own emptiness counter confirms every
            // in-flight token (including cache-miss-stalled ones) has fully
            // completed, rather than guessing a fixed number of idle cycles.
            size_t drain_guard = 0;
            while (!dut_[tid]->empty ) {
                tickHalfSingle(tid, 0);
                driveZReadData(tid);
                driveFramebufferRead(tid, tileColor);
                tickHalfSingle(tid, 1);
                captureWrites(tid, tileColor, tileDepth, fb_writes);
                checkUvNorm(tid, perThreadTokens[tid], uvIdx, sentCount, uvChecked, uvMismatch);

                drain_guard++;
                if (drain_guard > 1000000) {
                    std::cerr << "[THREAD_CMP][ERROR] thread never reported empty (tid=" << tid << ")"
                              << std::endl;
                    break;
                }
            }

            // After empty rises, require a short quiet window so delayed
            // cache/fragment events cannot spill into the next run.
            constexpr size_t kPostEmptyQuietCycles = 16;
            size_t quiet_count = 0;
            size_t quiet_guard = 0;
            while (quiet_count < kPostEmptyQuietCycles || uvIdx < sentCount || hasInternalPendingWork(tid)) {
                bool had_activity = false;
                tickHalfSingle(tid, 0);
                driveZReadData(tid);
                driveFramebufferRead(tid, tileColor);
                tickHalfSingle(tid, 1);

                had_activity = (dut_[tid]->uv_sample_fire != 0)
                            || (dut_[tid]->out_fb_valid != 0)
                            || (dut_[tid]->out_fb_we != 0)
                            || (dut_[tid]->z_wr_en != 0);

                captureWrites(tid, tileColor, tileDepth, fb_writes);
                checkUvNorm(tid, perThreadTokens[tid], uvIdx, sentCount, uvChecked, uvMismatch);

                // Keep draining until every sent token has produced a UV sample.
                if (uvIdx < sentCount) {
                    had_activity = true;
                }

                if (had_activity) {
                    quiet_count = 0;
                } else {
                    quiet_count++;
                }

                quiet_guard++;
                if (quiet_guard > 300000) {
                    std::cerr << "[THREAD_CMP][ERROR] post-empty quiet window timeout (tid="
                              << tid << ")" << std::endl;
                    break;
                }
            }
        }

        if (uvMismatch > 0) {
            std::cout << "[UV_CMP] checked=" << uvChecked << " mismatch=" << uvMismatch << '\n';
        }
    }

    bool hasInternalPendingWork(int tid)
    {
        auto *root = dut_[tid]->rootp;
        // return (root->thread_verilator_wrap__DOT__u_thread__DOT__l1_request_inflight != 0)
        return 0 
            || (dut_[tid]->out_fb_valid != 0)
            || (dut_[tid]->z_wr_en != 0);
    }
    static ThreadRasterCore& instance()
    {
        static ThreadRasterCore inst;
        return inst;
    }

    // Programs tex_id=0 with base address 0 and the given power-of-two size,
    // then backdoor-writes the swizzled pixel data straight into each per-
    // thread AXI RAM's mem[] storage (no AXI protocol/clocking needed).
    void programTexture(const std::vector<uint32_t>& pixelsArgb, int width, int height)
    {
        int sizeLog2 = std::countr_zero(static_cast<unsigned>(width));
        constexpr uint32_t kUnusedTexelColor = 0xFFFF0000u;
        for (int t = 0; t < HW_THREADS; ++t) {
            fillAxiRamAllWords(t, kUnusedTexelColor);
            writeLutAddr(t, 0, 0);
            writeLutSize(t, 0, static_cast<uint32_t>(sizeLog2));
        }

        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                uint32_t wordAddr = interleaveTexelAddress(static_cast<uint32_t>(x), static_cast<uint32_t>(y));
                uint32_t lane = wordAddr & 0x3u;
                uint32_t beat = wordAddr >> 2;
                uint32_t pixel = pixelsArgb[static_cast<size_t>(y) * width + x];
                for (int t = 0; t < HW_THREADS; ++t) {
                    writeAxiRamWord(t, lane, beat, pixel);
                }
            }
        }
    }

  private:
    std::array<Vthread_verilator_wrap*, HW_THREADS> dut_{};
    static constexpr size_t kFramebufferReadLatency = 3;
    std::array<std::array<uint32_t, kFramebufferReadLatency>, HW_THREADS> framebuffer_read_pipe_{};
        std::array<uint8_t, HW_THREADS> prev_out_fb_we_{};
        std::array<uint8_t, HW_THREADS> prev_z_wr_en_{};
        std::array<uint32_t, HW_THREADS> prev_out_fb_addr_{};
        std::array<uint32_t, HW_THREADS> prev_out_fb_color_{};
        std::array<uint32_t, HW_THREADS> prev_z_wr_addr_{};
        std::array<uint32_t, HW_THREADS> prev_z_wr_data_{};
        std::array<uint8_t, HW_THREADS> prev_z_buf_ready_{};
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

        // Latch output-side signals on the active edge; consumers use the
        // previous-cycle snapshot to avoid same-cycle observation races.
        if (clk == 1) {
            prev_out_fb_we_[tid] = static_cast<uint8_t>(dut_[tid]->out_fb_we != 0);
            prev_z_wr_en_[tid] = static_cast<uint8_t>(dut_[tid]->z_wr_en != 0);
            prev_out_fb_addr_[tid] = static_cast<uint32_t>(dut_[tid]->out_fb_addr);
            prev_out_fb_color_[tid] = static_cast<uint32_t>(dut_[tid]->out_fb_color);
            prev_z_wr_addr_[tid] = static_cast<uint32_t>(dut_[tid]->z_wr_addr);
            prev_z_wr_data_[tid] = static_cast<uint32_t>(dut_[tid]->z_wr_data);
            prev_z_buf_ready_[tid] = static_cast<uint8_t>(dut_[tid]->z_buf_ready != 0);
        }
    }

    void writeLutAddr(int tid, uint32_t idx, uint32_t addr)
    {
        tickHalfSingle(tid, 0);
        dut_[tid]->lut_wr_addr = idx;
        dut_[tid]->lut_wr_data = addr;
        dut_[tid]->lut_addr_wr_en = 1;
        dut_[tid]->lut_size_wr_en = 0;
        tickHalfSingle(tid, 1);
        tickHalfSingle(tid, 0);
        dut_[tid]->lut_addr_wr_en = 0;
        tickHalfSingle(tid, 1);
    }

    void writeLutSize(int tid, uint32_t idx, uint32_t sizeLog2)
    {
        tickHalfSingle(tid, 0);
        dut_[tid]->lut_wr_addr = idx;
        dut_[tid]->lut_wr_data = sizeLog2;
        dut_[tid]->lut_size_wr_en = 1;
        dut_[tid]->lut_addr_wr_en = 0;
        tickHalfSingle(tid, 1);
        tickHalfSingle(tid, 0);
        dut_[tid]->lut_size_wr_en = 0;
        tickHalfSingle(tid, 1);
    }

    // Pokes the AXI RAM's backing mem[] storage directly (bypassing the AXI
    // read/write protocol entirely); lane selects which of the 4 per-beat
    // 32-bit RAMs holds this word, beatIndex is the 16-byte-beat address.
    void writeAxiRamWord(int tid, uint32_t lane, uint32_t beatIndex, uint32_t data)
    {
        auto *root = dut_[tid]->rootp;
        switch (lane & 0x3u) {
        case 0: root->thread_verilator_wrap__DOT__u_tex_axi_ram0__DOT__mem[beatIndex] = data; break;
        case 1: root->thread_verilator_wrap__DOT__u_tex_axi_ram1__DOT__mem[beatIndex] = data; break;
        case 2: root->thread_verilator_wrap__DOT__u_tex_axi_ram2__DOT__mem[beatIndex] = data; break;
        default: root->thread_verilator_wrap__DOT__u_tex_axi_ram3__DOT__mem[beatIndex] = data; break;
        }
    }

    void fillAxiRamAllWords(int tid, uint32_t data)
    {
        auto *root = dut_[tid]->rootp;
        const uint32_t wordsPerLane = static_cast<uint32_t>(
            sizeof(root->thread_verilator_wrap__DOT__u_tex_axi_ram0__DOT__mem)
            / sizeof(root->thread_verilator_wrap__DOT__u_tex_axi_ram0__DOT__mem[0]));

        for (uint32_t beat = 0; beat < wordsPerLane; ++beat) {
            root->thread_verilator_wrap__DOT__u_tex_axi_ram0__DOT__mem[beat] = data;
            root->thread_verilator_wrap__DOT__u_tex_axi_ram1__DOT__mem[beat] = data;
            root->thread_verilator_wrap__DOT__u_tex_axi_ram2__DOT__mem[beat] = data;
            root->thread_verilator_wrap__DOT__u_tex_axi_ram3__DOT__mem[beat] = data;
        }
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

    void driveFramebufferRead(int tid, const uint32_t* tileColor)
    {
        auto& pipe = framebuffer_read_pipe_[tid];
        dut_[tid]->in_fb_rd_color = pipe.back();
        for (size_t stage = pipe.size() - 1; stage > 0; --stage)
            pipe[stage] = pipe[stage - 1];
        pipe[0] = 0;
        if (dut_[tid]->out_fb_rd_en) {
            const uint32_t address = tileAddrFromThreadAddr(
                static_cast<uint32_t>(tid), dut_[tid]->out_fb_rd_addr);
            if (address >= THREAD_PIXEL_ADDR_SPACE)
                throw std::out_of_range("Framebuffer read address outside tile");
            pipe[0] = tileColor[address];
        }
    }

    void captureWrites(int tid, uint32_t* tileColor, float* tileDepth,
                       std::vector<std::pair<uint32_t, uint32_t>>* fb_writes)
    {
        if (prev_z_buf_ready_[tid] && prev_z_wr_en_[tid]) {
            uint32_t localAddr = prev_z_wr_addr_[tid];
            uint32_t idx = tileAddrFromThreadAddr(static_cast<uint32_t>(tid), localAddr);
            if (idx < THREAD_PIXEL_ADDR_SPACE) {
                tileDepth[idx] = fr(prev_z_wr_data_[tid]);
            }
        }

        if (prev_out_fb_we_[tid]) {
            uint32_t localAddr = prev_out_fb_addr_[tid];
            uint32_t idx = tileAddrFromThreadAddr(static_cast<uint32_t>(tid), localAddr);
            if (idx < THREAD_PIXEL_ADDR_SPACE) {
                tileColor[idx] = prev_out_fb_color_[tid];
                if (fb_writes) {
                    fb_writes->push_back({idx, prev_out_fb_color_[tid]});
                }
            }
        }
    }

    // Matches one sampled (u_norm_s1, v_norm_s1) pair per accepted token at
    // the texture-address stage, using wrapper-exported uv_sample_fire.
    void checkUvNorm(int tid, const std::vector<ThreadToken>& tidTokens, size_t& uvIdx,
                     size_t sentCount, int& uvChecked, int& uvMismatch)
    {
        // Truncation quantization step of the HW's 12-bit u_norm_s1/v_norm_s1
        // registers (1/4096); allow up to one step of slack when comparing
        // against the software's un-quantized float fraction.
        constexpr float kUvNormTolerance = 0.001f;

        uint32_t uNorm = static_cast<uint32_t>(dut_[tid]->uv_sample_u);
        uint32_t vNorm = static_cast<uint32_t>(dut_[tid]->uv_sample_v);

        if (!dut_[tid]->uv_sample_fire) {
            return;
        }

        if (uvIdx >= sentCount || uvIdx >= tidTokens.size()) {
            return;
        }

        const ThreadToken& tok = tidTokens[uvIdx];
        uvChecked++;
        const float gotUFrac = static_cast<float>(uNorm) / 4096.0f;
        const float gotVFrac = static_cast<float>(vNorm) / 4096.0f;
        if (std::fabs(gotUFrac - tok.expected_u_frac) > kUvNormTolerance ||
            std::fabs(gotVFrac - tok.expected_v_frac) > kUvNormTolerance) {
            uvMismatch++;
            if (uvMismatch <= 8) {
                std::cerr << "[UV_CMP][MISMATCH] tid=" << tid << " idx=" << uvIdx
                          << " expected_u=" << tok.expected_u_frac << " got_u=" << gotUFrac
                          << " expected_v=" << tok.expected_v_frac << " got_v=" << gotVFrac << '\n';
            }
        }
        uvIdx++;
    }

    void driveToken(int tid, const ThreadToken& t)
    {
        dut_[tid]->in_addr = t.addr;
        dut_[tid]->in_tex_id = t.tex_id;
        dut_[tid]->in_texture_mode_u = t.texture_mode_u;
        dut_[tid]->in_texture_mode_v = t.texture_mode_v;
        dut_[tid]->in_texture_function = t.texture_function;
        dut_[tid]->in_sfactor_op = t.sfactor_op;
        dut_[tid]->in_dfactor_op = t.dfactor_op;
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
        dut_[tid]->in_texture_function = 5; 
        dut_[tid]->in_sfactor_op = 1;
        dut_[tid]->in_dfactor_op = 0;
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

// Called once (before any triangles are rasterized) to program tex_id=0's
// LUT entry and the swizzled texture data into every HW thread's AXI RAM.
void threadCmpProgramTexture(const std::vector<uint32_t>& pixelsArgb, int width, int height)
{
    ThreadRasterCore::instance().programTexture(pixelsArgb, width, height);
}

void threadCmpSaveReferenceImage(const char* path)
{
    if (g_ref_width <= 0 || g_ref_height <= 0) {
        return;
    }
    stbi_write_png(path, g_ref_width, g_ref_height, 4, g_ref_color.data(), g_ref_width * 4);
}

void Rasterizer::rasterizeTriangle(const Vertex_ScreenSpace& v0, const Vertex_ScreenSpace& v1,
                                   const Vertex_ScreenSpace& v2, int binMinX, int binMinY, int binMaxX, int binMaxY,
                                   uint32_t* tileColor, float* tileDepth)
{
    typedef float interp_type;

    const tvec2<interp_type> p0(v0.position.x, v0.position.y);
    const tvec2<interp_type> p1(v1.position.x, v1.position.y);
    const tvec2<interp_type> p2(v2.position.x, v2.position.y);
    const ColorU8 uc0 = unpackU8(v0.color);
    const ColorU8 uc1 = unpackU8(v1.color);
    const ColorU8 uc2 = unpackU8(v2.color);
    const tvec4<ap_fixed<17, 9, AP_RND>> c0(uc0.r, uc0.g, uc0.b, uc0.a);
    const tvec4<ap_fixed<17, 9, AP_RND>> c1(uc1.r, uc1.g, uc1.b, uc1.a);
    const tvec4<ap_fixed<17, 9, AP_RND>> c2(uc2.r, uc2.g, uc2.b, uc2.a);

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

    std::vector<ThreadToken> tokens;
    tokens.reserve((maxX - minX + 1) * (maxY - minY + 1));
    std::vector<float> expectedDepth(tileDepth, tileDepth + THREAD_PIXEL_ADDR_SPACE);
    std::vector<std::pair<uint32_t, uint32_t>> expectedWrites;
    expectedWrites.reserve(tokens.capacity());

    if (g_ref_width != fb->width || g_ref_height != fb->height) {
        g_ref_width = fb->width;
        g_ref_height = fb->height;
        g_ref_color = fb->colorBuffer;
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
                    t.texture_mode_u = 1; // TEXTURE_TILE, matches Texture::wrapModeS default (REPEAT)
                    t.texture_mode_v = 1; // TEXTURE_TILE, matches Texture::wrapModeT default (REPEAT)
                    t.texture_function = op;
                    t.sfactor_op = alphaBlendingEnabled ? 6 : 1;
                    t.dfactor_op = alphaBlendingEnabled ? 7 : 0;
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

                    t.v0_u = to_sq5_13(v0.texcoord_over_w.x);
                    t.v1_u = to_sq5_13(v1.texcoord_over_w.x);
                    t.v2_u = to_sq5_13(v2.texcoord_over_w.x);
                    t.v0_v = to_sq5_13(v0.texcoord_over_w.y);
                    t.v1_v = to_sq5_13(v1.texcoord_over_w.y);
                    t.v2_v = to_sq5_13(v2.texcoord_over_w.y);

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

                    const interp_type iw0 = e0 * invArea;
                    const interp_type iw1 = e1 * invArea;
                    const interp_type iw2 = e2 * invArea;
                    const interp_type z = iw0 * static_cast<interp_type>(v0.position.z) +
                                          iw1 * static_cast<interp_type>(v1.position.z) +
                                          iw2 * static_cast<interp_type>(v2.position.z);

                    // Perspective weights are needed for every token (HW interpolates
                    // UVs regardless of the z-test outcome), not just the current z-winner.
                    const interp_type invW = iw0 * static_cast<interp_type>(v0.position.w) +
                                             iw1 * static_cast<interp_type>(v1.position.w) +
                                             iw2 * static_cast<interp_type>(v2.position.w);
                    const interp_type w = interp_type(1.0f) / invW;
                    const ap_fixed<25, 2, AP_RND> t0 = iw0 * v0.position.w * w;
                    const ap_fixed<25, 2, AP_RND> t1 = iw1 * v1.position.w * w;
                    const ap_fixed<25, 2, AP_RND> t2 = iw2 * v2.position.w * w;

                    // Same perspective-correct interpolation the software fragment
                    // shader path uses (matches fIn.texcoord below), so the expected
                    // normalized UV mirrors sampleTexture()'s float-based REPEAT wrap.
                    const float texcoord_x = static_cast<float>(t0 * (ap_fixed<17, 4, AP_RND>)v0.texcoord_over_w.x +
                                                                 t1 * (ap_fixed<17, 4, AP_RND>)v1.texcoord_over_w.x +
                                                                 t2 * (ap_fixed<17, 4, AP_RND>)v2.texcoord_over_w.x);
                    const float texcoord_y = static_cast<float>(t0 * (ap_fixed<17, 4, AP_RND>)v0.texcoord_over_w.y +
                                                                 t1 * (ap_fixed<17, 4, AP_RND>)v1.texcoord_over_w.y +
                                                                 t2 * (ap_fixed<17, 4, AP_RND>)v2.texcoord_over_w.y);

                    tokens.back().expected_u_frac = computeExpectedUvFrac(texcoord_x);
                    tokens.back().expected_v_frac = computeExpectedUvFrac(texcoord_y);

                    Fragment_In fIn;
                    fIn.screenCoord = tvec2<float>(x, y);
                    fIn.depth = z;
                    fIn.texcoord.x = texcoord_x;
                    fIn.texcoord.y = texcoord_y;

                    const auto color_interp =
                        c0 * (ap_fixed<17, 9, AP_RND>)t0 +
                        c1 * (ap_fixed<17, 9, AP_RND>)t1 +
                        c2 * (ap_fixed<17, 9, AP_RND>)t2;
                    fIn.color = packU8({
                        static_cast<uint8_t>(std::clamp(static_cast<int>(color_interp.x), 0, 255)),
                        static_cast<uint8_t>(std::clamp(static_cast<int>(color_interp.y), 0, 255)),
                        static_cast<uint8_t>(std::clamp(static_cast<int>(color_interp.z), 0, 255)),
                        static_cast<uint8_t>(std::clamp(static_cast<int>(color_interp.w), 0, 255))});
                    const uint32_t expectedFragmentColor = fragmentShader(fIn);

                    if (z < expectedDepth[tileIdx]) {
                        expectedDepth[tileIdx] = z;

                        const size_t referenceIndex = static_cast<size_t>(y) * g_ref_width + x;
                        const uint32_t expectedColor = blendFragment(
                            expectedFragmentColor, g_ref_color[referenceIndex]);
                        expectedWrites.push_back({static_cast<uint32_t>(tileIdx), expectedColor});
                        g_ref_color[referenceIndex] = expectedColor;
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
    ThreadRasterCore::instance().run(tokens, binMinX, binMinY, tileColor, tileDepth, &hwWrites);

    std::sort(expectedWrites.begin(), expectedWrites.end());
    std::sort(hwWrites.begin(), hwWrites.end());

    int writeMismatch = 0;
    size_t i = 0;
    size_t j = 0;
    while (i < expectedWrites.size() && j < hwWrites.size()) {
        const auto& exp = expectedWrites[i];
        const auto& got = hwWrites[j];

        if (exp.first == got.first) {
            if (!colorsCloseEnough(unpackU8(exp.second), unpackU8(got.second))) {
                writeMismatch++;
                if (writeMismatch <= 8) {
                    std::cerr << "[THREAD_CMP][WRITE][COLOR] addr=" << exp.first
                              << " expected=" << std::hex << exp.second
                              << " got=" << got.second << std::dec << '\n';
                }
            }
            ++i;
            ++j;
        } else if (exp.first < got.first) {
            writeMismatch++;
            if (writeMismatch <= 8) {
                std::cerr << "[THREAD_CMP][WRITE][MISSING] addr=" << exp.first
                          << " color=" << std::hex << exp.second << std::dec << '\n';
            }
            ++i;
        } else {
            writeMismatch++;
            if (writeMismatch <= 8) {
                std::cerr << "[THREAD_CMP][WRITE][EXTRA] addr=" << got.first
                          << " color=" << std::hex << got.second << std::dec << '\n';
            }
            ++j;
        }
    }

    while (i < expectedWrites.size()) {
        writeMismatch++;
        if (writeMismatch <= 8) {
            std::cerr << "[THREAD_CMP][WRITE][MISSING] addr=" << expectedWrites[i].first
                      << " color=" << std::hex << expectedWrites[i].second << std::dec << '\n';
        }
        ++i;
    }

    while (j < hwWrites.size()) {
        writeMismatch++;
        if (writeMismatch <= 8) {
            std::cerr << "[THREAD_CMP][WRITE][EXTRA] addr=" << hwWrites[j].first
                      << " color=" << std::hex << hwWrites[j].second << std::dec << '\n';
        }
        ++j;
    }
    if (writeMismatch > 0) {
        std::cout << "[THREAD_CMP] tokens=" << tokens.size()
                  << " expected_writes=" << expectedWrites.size()
                  << " hw_writes=" << hwWrites.size()
                  << " write_mismatch=" << writeMismatch << '\n';
    }
}

