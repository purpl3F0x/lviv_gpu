#include <stdint.h>

extern "C" double dpi_bits_to_float(uint32_t bits) {
    union { uint32_t i; float f; } u;
    u.i = bits;
    return (double)u.f;
}

extern "C" uint32_t dpi_float_to_bits(double val) {
    union { uint32_t i; float f; } u;
    u.f = (float)val;
    return u.i;
}