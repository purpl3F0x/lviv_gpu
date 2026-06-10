#pragma once
#include <cstdint>

enum TexEnvMode {
    REPLACE = 0,
    MODULATE = 1,
    DECAL = 2,
    BLEND = 3,
    ADD = 4,
    COLOR = 5
};

struct ColorU8 {
    uint8_t a, r, g, b;
};

inline ColorU8 unpackU8(uint32_t c) {
    return {
        static_cast<uint8_t>((c >> 24) & 0xFF),
        static_cast<uint8_t>((c >> 16) & 0xFF),
        static_cast<uint8_t>((c >> 8) & 0xFF),
        static_cast<uint8_t>(c & 0xFF)
    };
}

inline uint32_t packU8(const ColorU8& c) {
    return (c.a << 24) | (c.r << 16) | (c.g << 8) | c.b;
}
