#include "../common/raster_types.h"
#include <algorithm>
#include <iostream>

constexpr int NUM_TESTS = 1000000;

int golden_fragment_shader(int pixel, int tex, int env, char op)
{
    ColorU8 Cf = unpackU8(pixel);
    ColorU8 Ct = unpackU8(tex);
    ColorU8 Cc = unpackU8(env);
    ColorU8 Cv = Cf;

    switch (op)
    {
    case REPLACE:
        Cv = Ct;
        break;
    case MODULATE:
        Cv.r = (Cf.r * Ct.r + 128) >> 8;
        Cv.g = (Cf.g * Ct.g + 128) >> 8;
        Cv.b = (Cf.b * Ct.b + 128) >> 8;
        Cv.a = (Cf.a * Ct.a + 128) >> 8;
        break;
    case DECAL:
        Cv.r = ((255 - Ct.a) * Cf.r + Ct.a * Ct.r + 128) >> 8;
        Cv.g = ((255 - Ct.a) * Cf.g + Ct.a * Ct.g + 128) >> 8;
        Cv.b = ((255 - Ct.a) * Cf.b + Ct.a * Ct.b + 128) >> 8;
        Cv.a = Cf.a;
        break;
    case BLEND:
        Cv.r = ((255 - Ct.r) * Cf.r + Ct.r * Cc.r + 128) >> 8;
        Cv.g = ((255 - Ct.g) * Cf.g + Ct.g * Cc.g + 128) >> 8;
        Cv.b = ((255 - Ct.b) * Cf.b + Ct.b * Cc.b + 128) >> 8;
        Cv.a = (Cf.a * Ct.a + 128) >> 8;
        break;
    case ADD:
        Cv.r = std::min(255, (int)Cf.r + Ct.r);
        Cv.g = std::min(255, (int)Cf.g + Ct.g);
        Cv.b = std::min(255, (int)Cf.b + Ct.b);
        Cv.a = (Cf.a * Ct.a + 128) >> 8;
        break;
    case COLOR:
        Cv.r = Cf.r;
        Cv.g = Cf.g;
        Cv.b = Cf.b;
        Cv.a = Cf.a;
        break;
    }

    return packU8(Cv);
}

void check_fragment_shader_output(int actual, int expected, int *passed, int *failed)
{
    if (actual != expected)
    {
        std::cout << "Mismatch at test " << (*passed + *failed) << ": Expected 0x" << std::hex << expected
                  << " but got 0x" << actual << std::dec << "\n";
        (*failed)++;
        if (*failed > 10)
        {
            std::cout << "Too many failures!\n";
            exit(1);
        }
    }
    else
    {
        (*passed)++;
    }
}

#include "Vfragment_shader.h"
#include <cstdlib>
#include <queue>
#include <verilated.h>
#include <verilated_vcd_c.h>

int main(int argc, char **argv)
{
    // Create Verilator simulation context
    VerilatedContext *contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    contextp->traceEverOn(true); // enable tracing

    bool dump_trace = false;
    const char *vcd_name = "waves.vcd";

    for (int i = 1; i < argc; i++)
    {
        // Should we trace ??
        if (std::string(argv[i]) == "--trace")
        {
            dump_trace = true;
            if (i + 1 < argc && argv[i + 1][0] != '-')
            {
                vcd_name = argv[i + 1];
                i++;
            }
        }
    }

    // Create top-level module
    Vfragment_shader *top = new Vfragment_shader{contextp};

    // Create VCD trace
    VerilatedVcdC *tfp = nullptr;
    if (dump_trace)
    {
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99); // trace 99 levels deep
        tfp->open(vcd_name); // waveform file
    }

    // Initialize simulation at time 0
    top->clk = 0;
    top->rst_n = 0;
    top->valid_in = 0;
    top->pixel_color = 0;
    top->texture_color = 0;
    top->env_color = 0;
    top->op = 0;

    top->eval();
    if (dump_trace)
    {
        tfp->dump(0);
    }

    std::queue<int> expected_q;
    int passed = 0;
    int failed = 0;
    int test_gen = 0;

    // Main simulation loop
    while (!contextp->gotFinish() && (passed + failed < NUM_TESTS))
    {
        contextp->timeInc(1);
        top->clk = !top->clk; // toggle clock

        if (contextp->time() < 12)
        {
            top->rst_n = 0; // assert reset
            top->valid_in = 0;
        }
        else
        {
            top->rst_n = 1; // release reset
        }

        // On positive edge
        if (top->clk && top->rst_n)
        {
            // Sink: Read output
            if (top->valid_out)
            {
                if (!expected_q.empty())
                {
                    int expected = expected_q.front();
                    expected_q.pop();
                    check_fragment_shader_output(top->fragment_color, expected, &passed, &failed);
                }
                else
                {
                    std::cout << "Received data but expected queue is empty!\n";
                    failed++;
                }
            }

            // Source: Drive inputs randomly
            if (test_gen < NUM_TESTS)
            {
                if (rand() % 5 != 0) // 80% valid
                {
                    top->valid_in = 1;
                    top->pixel_color = (rand() << 16) ^ rand();
                    top->texture_color = (rand() << 16) ^ rand();
                    top->env_color = (rand() << 16) ^ rand();
                    top->op = rand() % 6; // 0 to 5

                    int expected =
                        golden_fragment_shader(top->pixel_color, top->texture_color, top->env_color, top->op);
                    expected_q.push(expected);
                    test_gen++;
                }
                else
                {
                    top->valid_in = 0;
                }
            }
            else
            {
                top->valid_in = 0;
            }
        }

        top->eval();
        if (dump_trace)
        {
            tfp->dump(contextp->time());
        }
    }

    if (failed == 0)
    {
        std::cout << "SUCCESS! All " << passed << " tests passed.\n";
    }

    // Close trace and clean up
    if (dump_trace)
    {
        tfp->close();
        delete tfp;
    }
    int errors = (int)contextp->errorCount();
    delete top;
    delete contextp;
    return (errors > 0 || failed > 0) ? 1 : 0;
}
