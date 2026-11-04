// Small 2D drawing into 32-bit 0xAARRGGBB frame buffers (dp.h's): rectangles, lines, monospace
// bitmap text and images, no antialiasing. It only writes the frame, never reads it: as fast in
// memory the CPU does not cache. Header only, C or C++.
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C"
{
#endif

// Where to draw: width x height pixels, stride pixels from one row to the next. Everything outside
// is clipped.
typedef struct
{
    uint32_t *pixels;
    int stride;
    int width, height;
} ui_canvas_t;

// A monospace bitmap font (scripts/ui_assets.py): characters first to last, each height rows of
// row_bytes bytes, its leftmost pixel the first byte's MSB. Other characters are blanks.
typedef struct
{
    const uint8_t *bitmap;
    uint8_t width, height; // the cell
    uint8_t first, last;
    uint8_t row_bytes;
} ui_font_t;

// An image (scripts/ui_assets.py): width x height 0xAARRGGBB pixels, row after row. ui_image draws
// those with alpha 0x80 or more, opaque.
typedef struct
{
    const uint32_t *pixels;
    int width, height;
} ui_image_t;

// Opaque 0xAARRGGBB
static inline uint32_t ui_rgb(uint8_t r, uint8_t g, uint8_t b)
{
    return 0xFF000000u | (uint32_t)r << 16 | (uint32_t)g << 8 | b;
}

static inline void ui_fill(const ui_canvas_t *c, int x, int y, int w, int h, uint32_t color)
{
    int x1 = x + w, y1 = y + h;
    if (x < 0)
        x = 0;
    if (y < 0)
        y = 0;
    if (x1 > c->width)
        x1 = c->width;
    if (y1 > c->height)
        y1 = c->height;
    for (; y < y1; y++)
    {
        uint32_t *row = c->pixels + (ptrdiff_t)y * c->stride;
        for (int i = x; i < x1; i++)
            row[i] = color;
    }
}

// The rectangle's outline, t pixels thick, inside it
static inline void ui_frame(const ui_canvas_t *c, int x, int y, int w, int h, int t, uint32_t color)
{
    ui_fill(c, x, y, w, t, color);
    ui_fill(c, x, y + h - t, w, t, color);
    ui_fill(c, x, y + t, t, h - 2 * t, color);
    ui_fill(c, x + w - t, y + t, t, h - 2 * t, color);
}

// From (x0, y0) to (x1, y1), both ends drawn (Bresenham)
static inline void ui_line(const ui_canvas_t *c, int x0, int y0, int x1, int y1, uint32_t color)
{
    const int dx = x1 > x0 ? x1 - x0 : x0 - x1, sx = x0 < x1 ? 1 : -1;
    const int dy = y1 > y0 ? y0 - y1 : y1 - y0, sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    for (;;)
    {
        if ((unsigned)x0 < (unsigned)c->width && (unsigned)y0 < (unsigned)c->height)
            c->pixels[(ptrdiff_t)y0 * c->stride + x0] = color;
        if (x0 == x1 && y0 == y1)
            break;
        const int e2 = 2 * err;
        if (e2 >= dy)
        {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx)
        {
            err += dx;
            y0 += sy;
        }
    }
}

static inline int ui_text_width(const ui_font_t *f, int scale, const char *s)
{
    return (int)strlen(s) * f->width * scale;
}

// s with its top left at (x, y), each of the font's pixels scale x scale, the background left as it
// is. Returns the x after it.
static inline int ui_text(const ui_canvas_t *c, const ui_font_t *f, int x, int y, int scale, uint32_t color,
                          const char *s)
{
    const int cw = f->width * scale;
    for (; *s; s++, x += cw)
    {
        const unsigned code = (unsigned char)*s;
        if (code < f->first || code > f->last || x >= c->width || x + cw <= 0 || y >= c->height ||
            y + f->height * scale <= 0)
            continue;
        const uint8_t *row = f->bitmap + (size_t)(code - f->first) * f->height * f->row_bytes;
        for (int gy = 0; gy < f->height; gy++, row += f->row_bytes)
        {
            // Each run of set pixels, one fill
            for (int gx = 0; gx < f->width;)
            {
                if (!(row[gx >> 3] & (0x80 >> (gx & 7))))
                {
                    gx++;
                    continue;
                }
                const int start = gx;
                while (gx < f->width && (row[gx >> 3] & (0x80 >> (gx & 7))))
                    gx++;
                ui_fill(c, x + start * scale, y + gy * scale, (gx - start) * scale, scale, color);
            }
        }
    }
    return x;
}

// s centered on column cx
static inline void ui_text_center(const ui_canvas_t *c, const ui_font_t *f, int cx, int y, int scale,
                                  uint32_t color, const char *s)
{
    ui_text(c, f, cx - ui_text_width(f, scale, s) / 2, y, scale, color, s);
}

// image with its top left at (x, y)
static inline void ui_image(const ui_canvas_t *c, int x, int y, const ui_image_t *image)
{
    const int x0 = x < 0 ? -x : 0, y0 = y < 0 ? -y : 0;
    const int x1 = x + image->width > c->width ? c->width - x : image->width;
    const int y1 = y + image->height > c->height ? c->height - y : image->height;
    for (int iy = y0; iy < y1; iy++)
    {
        const uint32_t *src = image->pixels + (ptrdiff_t)iy * image->width;
        uint32_t *dst = c->pixels + (ptrdiff_t)(y + iy) * c->stride + x;
        for (int ix = x0; ix < x1; ix++)
            if (src[ix] >= 0x80000000u)
                dst[ix] = src[ix] | 0xFF000000u;
    }
}

#ifdef __cplusplus
}
#endif
