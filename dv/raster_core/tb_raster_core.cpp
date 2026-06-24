#include "Vraster_core.h"
#include "Vraster_core___024root.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <queue>
#include <string>
#include <verilated.h>
#include <verilated_fst_c.h>

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

constexpr int NUM_TESTS = 10000; // 10k random tests

struct Vertex
{
    float x, y, z, w;
    float nx, ny, nz;
    uint32_t color;
    float u, v;
};

struct ReferenceOutput
{
    float e0_00;
    float e1_00;
    float e2_00;
    float e0_10;
    float e1_10;
    float e2_10;
    float e0_01;
    float e1_01;
    float e2_01;
    float e0_11;
    float e1_11;
    float e2_11;
    float e0_dx;
    float e0_dy;
    float e1_dx;
    float e1_dy;
    float e2_dx;
    float e2_dy;
    float invArea;
    Vertex v0, v1, v2;
    float minX_local;
    float minY_local;
    float width;
    float height;
    int tile_x_id;
    int tile_y_id;
};

// Helper for float packing into VlWide<10>
void pack_vertex(VlWide<10> &v_in, const Vertex &v)
{
    v_in[9] = *reinterpret_cast<const uint32_t *>(&v.x);
    v_in[8] = *reinterpret_cast<const uint32_t *>(&v.y);
    v_in[7] = *reinterpret_cast<const uint32_t *>(&v.z);
    v_in[6] = *reinterpret_cast<const uint32_t *>(&v.w);
    v_in[5] = *reinterpret_cast<const uint32_t *>(&v.nx);
    v_in[4] = *reinterpret_cast<const uint32_t *>(&v.ny);
    v_in[3] = *reinterpret_cast<const uint32_t *>(&v.nz);
    v_in[2] = v.color;
    v_in[1] = *reinterpret_cast<const uint32_t *>(&v.u);
    v_in[0] = *reinterpret_cast<const uint32_t *>(&v.v);
}

// Generate random float in a range
float rand_float(float min, float max)
{
    return min + static_cast<float>(rand()) / (static_cast<float>(RAND_MAX / (max - min)));
}

// Helper edge function
inline float edgeFunction(float ax, float ay, float bx, float by, float cx, float cy)
{
    return (cx - ax) * (by - ay) - (cy - ay) * (bx - ax);
}

inline int math_floor(float val)
{
    long long fixed_val = static_cast<long long>(std::round(val * 8388608.0f));
    return static_cast<int>(fixed_val >> 23);
}

inline int math_ceil(float val)
{
    long long fixed_val = static_cast<long long>(std::round(val * 8388608.0f));
    int fl = static_cast<int>(fixed_val >> 23);
    unsigned int frac = fixed_val & 0x7FFFFF;
    if (frac == 0)
    {
        return fl;
    }
    else
    {
        return fl + 1;
    }
}

// Direct software implementation of edge setup equations
ReferenceOutput run_software_rasterizer(const Vertex &v0, const Vertex &v1, const Vertex &v2, int tile_x_id,
                                        int tile_y_id)
{
    ReferenceOutput ref;

    // Tile bounds
    int binMinX = tile_x_id * 128;
    int binMinY = tile_y_id * 128;
    int binMaxX = binMinX + 127;
    int binMaxY = binMinY + 127;

    // Calculate the triangle's bounding box in screen space
    int triMinX = std::min({math_floor(v0.x), math_floor(v1.x), math_floor(v2.x)});
    int triMinY = std::min({math_floor(v0.y), math_floor(v1.y), math_floor(v2.y)});
    int triMaxX = std::max({math_ceil(v0.x), math_ceil(v1.x), math_ceil(v2.x)});
    int triMaxY = std::max({math_ceil(v0.y), math_ceil(v1.y), math_ceil(v2.y)});

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

    // Coordinates mapping
    float p_min_x = static_cast<float>(minX) + 0.5f;
    float p_min_y = static_cast<float>(minY) + 0.5f;

    // Triangle Area
    float area = edgeFunction(v0.x, v0.y, v1.x, v1.y, v2.x, v2.y);
    float invArea = 1.0f / area;

    // Edge equations at tile corner
    float e0_00 = edgeFunction(v1.x, v1.y, v2.x, v2.y, p_min_x, p_min_y);
    float e1_00 = edgeFunction(v2.x, v2.y, v0.x, v0.y, p_min_x, p_min_y);
    float e2_00 = edgeFunction(v0.x, v0.y, v1.x, v1.y, p_min_x, p_min_y);

    // X and Y derivatives
    float e0_dx = (v2.y - v1.y);
    float e1_dx = (v0.y - v2.y);
    float e2_dx = (v1.y - v0.y);

    // Step increments for each step in Y
    float e0_dy = (v1.x - v2.x);
    float e1_dy = (v2.x - v0.x);
    float e2_dy = (v0.x - v1.x);

    ref.e0_00 = e0_00;
    ref.e1_00 = e1_00;
    ref.e2_00 = e2_00;
    ref.e0_10 = e0_00 + e0_dx;
    ref.e1_10 = e1_00 + e1_dx;
    ref.e2_10 = e2_00 + e2_dx;
    ref.e0_01 = e0_00 + e0_dy;
    ref.e1_01 = e1_00 + e1_dy;
    ref.e2_01 = e2_00 + e2_dy;
    ref.e0_11 = e0_00 + e0_dx + e0_dy;
    ref.e1_11 = e1_00 + e1_dx + e1_dy;
    ref.e2_11 = e2_00 + e2_dx + e2_dy;
    ref.e0_dx = e0_dx;
    ref.e0_dy = e0_dy;
    ref.e1_dx = e1_dx;
    ref.e1_dy = e1_dy;
    ref.e2_dx = e2_dx;
    ref.e2_dy = e2_dy;
    ref.invArea = invArea;
    ref.v0 = v0;
    ref.v1 = v1;
    ref.v2 = v2;
    int maxX_clamped = (maxX <= minX) ? (minX + 1) : maxX;
    int maxY_clamped = (maxY <= minY) ? (minY + 1) : maxY;
    ref.minX_local = (float)(minY & 127);
    ref.minY_local = (float)(minX & 127);
    ref.width = (float)(maxX_clamped - minX);
    ref.height = (float)(maxY_clamped - minY);
    ref.tile_x_id = tile_x_id;
    ref.tile_y_id = tile_y_id;

    return ref;
}

// Compare float bit patterns and allow tiny epsilon due to potential compiler-specific FMA optimizations
bool compare_floats(float actual, float expected, const std::string &name, float tolerance = 1e-4f)
{
    if (std::isnan(actual) && std::isnan(expected))
        return true;

    // Direct bit comparison first
    uint32_t act_raw = *reinterpret_cast<uint32_t *>(&actual);
    uint32_t exp_raw = *reinterpret_cast<uint32_t *>(&expected);
    if (act_raw == exp_raw)
        return true;

    // Epsilon check
    float diff = std::abs(actual - expected);
    if (diff > tolerance)
    {
        // Relative tolerance check as backup
        if (expected != 0.0f && (diff / std::abs(expected)) < tolerance)
        {
            return true;
        }
        std::cout << "Mismatch in " << name << ": Actual = " << actual << " (0x" << std::hex << act_raw
                  << "), Expected = " << expected << " (0x" << exp_raw << std::dec << "), Diff = " << diff << "\n";
        return false;
    }
    return true;
}

int main(int argc, char **argv)
{
    srand(12345); // Seed for reproducible testing

    VerilatedContext *contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    contextp->traceEverOn(true);

    bool dump_trace = false;
    const char *fst_name = "waves.fst";

    for (int i = 1; i < argc; i++)
    {
        if (std::string(argv[i]) == "--trace")
        {
            dump_trace = true;
            if (i + 1 < argc && argv[i + 1][0] != '-')
            {
                fst_name = argv[i + 1];
                i++;
            }
        }
    }

    Vraster_core *top = new Vraster_core{contextp};
    VerilatedFstC *tfp = nullptr;
    if (dump_trace)
    {
        tfp = new VerilatedFstC;
        top->trace(tfp, 99);
        tfp->open(fst_name);
    }

    // Initial states
    top->clk = 0;
    top->rst_n = 0; // Assert reset
    top->valid_in = 0;
    top->tile_x_id = 0;
    top->tile_y_id = 0;
    top->ready_in = 0;

    // Evaluation at time 0
    top->eval();
    if (dump_trace)
        tfp->dump(0);

    std::queue<ReferenceOutput> expected_q;
    int passed = 0;
    int failed = 0;
    int tests_submitted = 0;

    // Sequencer states
    enum SeqState
    {
        SEQ_SEND_V0,
        SEQ_SEND_V1,
        SEQ_SEND_V2,
        SEQ_WAIT_CALC
    };
    SeqState seq_state = SEQ_SEND_V0;

    Vertex current_v0, current_v1, current_v2;
    int current_tile_x = 0;
    int current_tile_y = 0;

    // Stall test state variables
    bool stall_active = false;
    int stall_cycles_left = 0;
    ReferenceOutput expected_stalled;

    // Loop until all tests are processed
    while (!contextp->gotFinish() && (passed + failed < NUM_TESTS))
    {
        // 1. Toggle clock and advance time
        contextp->timeInc(1);
        top->clk = !top->clk;

        // 2. Drive reset
        if (contextp->time() < 20)
        {
            top->rst_n = 0;
        }
        else
        {
            top->rst_n = 1;
        }

        // 3. Evaluate model
        top->eval();
        if (dump_trace)
            tfp->dump(contextp->time());

        // 4. Read outputs and drive next inputs at positive clock edge AFTER evaluation
        if (top->clk && top->rst_n)
        {
            // Read and verify outputs
            if (top->valid_out)
            {
                if (!expected_q.empty() || stall_active)
                {
                    ReferenceOutput expected;
                    if (stall_active)
                    {
                        expected = expected_stalled;
                    }
                    else
                    {
                        expected = expected_q.front();
                    }

                    // Convert raw bits from ports to floats
                    float act_e0_00 = *reinterpret_cast<float *>(&top->out_e0_00);
                    float act_e1_00 = *reinterpret_cast<float *>(&top->out_e1_00);
                    float act_e2_00 = *reinterpret_cast<float *>(&top->out_e2_00);
                    float act_e0_10 = *reinterpret_cast<float *>(&top->out_e0_10);
                    float act_e1_10 = *reinterpret_cast<float *>(&top->out_e1_10);
                    float act_e2_10 = *reinterpret_cast<float *>(&top->out_e2_10);
                    float act_e0_01 = *reinterpret_cast<float *>(&top->out_e0_01);
                    float act_e1_01 = *reinterpret_cast<float *>(&top->out_e1_01);
                    float act_e2_01 = *reinterpret_cast<float *>(&top->out_e2_01);
                    float act_e0_11 = *reinterpret_cast<float *>(&top->out_e0_11);
                    float act_e1_11 = *reinterpret_cast<float *>(&top->out_e1_11);
                    float act_e2_11 = *reinterpret_cast<float *>(&top->out_e2_11);
                    float act_e0_dx = *reinterpret_cast<float *>(&top->out_e0_dx);
                    float act_e0_dy = *reinterpret_cast<float *>(&top->out_e0_dy);
                    float act_e1_dx = *reinterpret_cast<float *>(&top->out_e1_dx);
                    float act_e1_dy = *reinterpret_cast<float *>(&top->out_e1_dy);
                    float act_e2_dx = *reinterpret_cast<float *>(&top->out_e2_dx);
                    float act_e2_dy = *reinterpret_cast<float *>(&top->out_e2_dy);
                    float act_invArea = *reinterpret_cast<float *>(&top->out_invArea);
                    float act_minX_local = (float)top->out_minX_local;
                    float act_minY_local = (float)top->out_minY_local;
                    float act_width = (float)top->out_width;
                    float act_height = (float)top->out_height;

                    if (!stall_active)
                    {
                        std::cout << "[TEST " << (passed + failed) << "] Results:\n"
                                  << "  out_e0_00:  Actual = " << act_e0_00 << ", Expected = " << expected.e0_00 << "\n"
                                  << "  out_e1_00:  Actual = " << act_e1_00 << ", Expected = " << expected.e1_00 << "\n"
                                  << "  out_e2_00:  Actual = " << act_e2_00 << ", Expected = " << expected.e2_00 << "\n"
                                  << "  out_e0_10:   Actual = " << act_e0_10 << ", Expected = " << expected.e0_10
                                  << "\n"
                                  << "  out_e1_10:   Actual = " << act_e1_10 << ", Expected = " << expected.e1_10
                                  << "\n"
                                  << "  out_e2_10:   Actual = " << act_e2_10 << ", Expected = " << expected.e2_10
                                  << "\n"
                                  << "  out_invArea: Actual = " << act_invArea << ", Expected = " << expected.invArea
                                  << "\n";
                    }

                    bool match = true;
                    match &= compare_floats(act_e0_00, expected.e0_00, "out_e0_00", 2e-3f);
                    match &= compare_floats(act_e1_00, expected.e1_00, "out_e1_00", 2e-3f);
                    match &= compare_floats(act_e2_00, expected.e2_00, "out_e2_00", 2e-3f);
                    match &= compare_floats(act_e0_10, expected.e0_10, "out_e0_10", 2e-3f);
                    match &= compare_floats(act_e1_10, expected.e1_10, "out_e1_10", 2e-3f);
                    match &= compare_floats(act_e2_10, expected.e2_10, "out_e2_10", 2e-3f);
                    match &= compare_floats(act_e0_01, expected.e0_01, "out_e0_01", 2e-3f);
                    match &= compare_floats(act_e1_01, expected.e1_01, "out_e1_01", 2e-3f);
                    match &= compare_floats(act_e2_01, expected.e2_01, "out_e2_01", 2e-3f);
                    match &= compare_floats(act_e0_11, expected.e0_11, "out_e0_11", 2e-3f);
                    match &= compare_floats(act_e1_11, expected.e1_11, "out_e1_11", 2e-3f);
                    match &= compare_floats(act_e2_11, expected.e2_11, "out_e2_11", 2e-3f);
                    match &= compare_floats(act_e0_dx, expected.e0_dx, "out_e0_dx");
                    match &= compare_floats(act_e0_dy, expected.e0_dy, "out_e0_dy");
                    match &= compare_floats(act_e1_dx, expected.e1_dx, "out_e1_dx");
                    match &= compare_floats(act_e1_dy, expected.e1_dy, "out_e1_dy");
                    match &= compare_floats(act_e2_dx, expected.e2_dx, "out_e2_dx");
                    match &= compare_floats(act_e2_dy, expected.e2_dy, "out_e2_dy");
                    match &= compare_floats(act_invArea, expected.invArea, "out_invArea", 1e-3f);
                    match &= compare_floats(act_minX_local, expected.minX_local, "out_minX_local");
                    match &= compare_floats(act_minY_local, expected.minY_local, "out_minY_local");
                    match &= compare_floats(act_width, expected.width, "out_width");
                    match &= compare_floats(act_height, expected.height, "out_height");

                    if (!match)
                    {
                        failed++;
                        std::cout << "Mismatch found at test index " << (passed + failed - 1)
                                  << (stall_active ? " (during STALL)" : "") << "!\n";
                        std::cout << "Vertices: \n"
                                  << "  v0 = (" << expected.v0.x << ", " << expected.v0.y << ")\n"
                                  << "  v1 = (" << expected.v1.x << ", " << expected.v1.y << ")\n"
                                  << "  v2 = (" << expected.v2.x << ", " << expected.v2.y << ")\n"
                                  << "  tile_x = " << current_tile_x << ", tile_y = " << current_tile_y << "\n";
                        if (failed > 10)
                        {
                            tfp->close();
                            std::cout << "Too many failures! Terminating simulation.\n";
                            exit(1);
                        }
                    }

                    if (!stall_active)
                    {
                        // Decide if we should start a stall (e.g. 30% chance, up to 5 cycles)
                        if (rand() % 10 < 3)
                        {
                            stall_active = true;
                            stall_cycles_left = rand() % 5 + 1;
                            expected_stalled = expected;
                            top->ready_in = 0;
                        }
                        else
                        {
                            if (match)
                                passed++;
                            expected_q.pop();
                            top->ready_in = 1;
                        }
                    }
                    else
                    {
                        // Stall is active
                        stall_cycles_left--;
                        if (stall_cycles_left == 0)
                        {
                            if (match)
                                passed++;
                            expected_q.pop();
                            top->ready_in = 1;
                            stall_active = false;
                        }
                        else
                        {
                            top->ready_in = 0;
                        }
                    }
                }
                else
                {
                    std::cout << "valid_out asserted but expected queue is empty!\n";
                    failed++;
                    exit(1);
                }
            }
            else
            {
                top->ready_in = 0;
            }

            // Drive inputs
            if (top->ready_out)
            {
                if (seq_state == SEQ_SEND_V0 && tests_submitted < NUM_TESTS)
                {
                    // Generate new valid random triangle
                    float area_check = 0.0f;
                    do
                    {
                        current_v0.x = rand_float(0.0f, 4096.0f);
                        current_v0.y = rand_float(0.0f, 4096.0f);
                        current_v1.x = rand_float(0.0f, 4096.0f);
                        current_v1.y = rand_float(0.0f, 4096.0f);
                        current_v2.x = rand_float(0.0f, 4096.0f);
                        current_v2.y = rand_float(0.0f, 4096.0f);

                        area_check = (current_v2.x - current_v0.x) * (current_v1.y - current_v0.y) -
                                     (current_v2.y - current_v0.y) * (current_v1.x - current_v0.x);
                    } while (std::abs(area_check) < 10.0f); // Discard degenerate triangles

                    current_v0.z = rand_float(0.1f, 10.0f);
                    current_v0.w = rand_float(0.1f, 10.0f);
                    current_v1.z = rand_float(0.1f, 10.0f);
                    current_v1.w = rand_float(0.1f, 10.0f);
                    current_v2.z = rand_float(0.1f, 10.0f);
                    current_v2.w = rand_float(0.1f, 10.0f);

                    current_v0.nx = rand_float(-1.0f, 1.0f);
                    current_v0.ny = rand_float(-1.0f, 1.0f);
                    current_v0.nz = rand_float(-1.0f, 1.0f);
                    current_v1.nx = rand_float(-1.0f, 1.0f);
                    current_v1.ny = rand_float(-1.0f, 1.0f);
                    current_v1.nz = rand_float(-1.0f, 1.0f);
                    current_v2.nx = rand_float(-1.0f, 1.0f);
                    current_v2.ny = rand_float(-1.0f, 1.0f);
                    current_v2.nz = rand_float(-1.0f, 1.0f);

                    current_v0.color = rand();
                    current_v1.color = rand();
                    current_v2.color = rand();

                    current_v0.u = rand_float(0.0f, 1.0f);
                    current_v0.v = rand_float(0.0f, 1.0f);
                    current_v1.u = rand_float(0.0f, 1.0f);
                    current_v1.v = rand_float(0.0f, 1.0f);
                    current_v2.u = rand_float(0.0f, 1.0f);
                    current_v2.v = rand_float(0.0f, 1.0f);

                    current_tile_x = rand() % 32;
                    current_tile_y = rand() % 32;

                    // Run reference software
                    ReferenceOutput expected =
                        run_software_rasterizer(current_v0, current_v1, current_v2, current_tile_x, current_tile_y);
                    expected_q.push(expected);

                    // Drive top port
                    pack_vertex(top->vertex_in, current_v0);
                    top->tile_x_id = current_tile_x;
                    top->tile_y_id = current_tile_y;
                    top->valid_in = 1;

                    seq_state = SEQ_SEND_V1;
                    tests_submitted++;
                }
                else if (seq_state == SEQ_SEND_V1)
                {
                    pack_vertex(top->vertex_in, current_v1);
                    top->valid_in = 1;
                    seq_state = SEQ_SEND_V2;
                }
                else if (seq_state == SEQ_SEND_V2)
                {
                    pack_vertex(top->vertex_in, current_v2);
                    top->valid_in = 1;
                    seq_state = SEQ_WAIT_CALC;
                }
            }
            else
            {
                top->valid_in = 0;
                if (seq_state == SEQ_WAIT_CALC && top->valid_out)
                {
                    seq_state = SEQ_SEND_V0;
                }
            }
        }
    }

    // Run evaluation cycles to flush final consumption
    for (int i = 0; i < 10; ++i)
    {
        contextp->timeInc(1);
        top->clk = !top->clk;
        if (top->clk)
        {
            top->ready_in = 1;
            top->valid_in = 0;
        }
        top->eval();
        if (dump_trace)
            tfp->dump(contextp->time());
    }

    if (failed == 0)
    {
        std::cout << "SUCCESS! All " << passed << " random tests passed verification against software reference.\n";
    }
    else
    {
        std::cout << "FAILURE: " << failed << " mismatches occurred out of " << (passed + failed) << " tests.\n";
    }

    if (dump_trace)
    {
        tfp->close();
        delete tfp;
    }
    delete top;
    delete contextp;
    return (failed > 0) ? 1 : 0;
}
