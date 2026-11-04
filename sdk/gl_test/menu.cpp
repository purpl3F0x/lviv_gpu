#include "menu.h"

#include <cstdio>
#include <cstdlib>

#include "stb_image.h"
#include "ui_font_14x28.h"

namespace
{
// The VGA text mode's colors
const uint32_t black = ui_rgb(0x00, 0x00, 0x00), red = ui_rgb(0xAA, 0x00, 0x00), grey = ui_rgb(0xAA, 0xAA, 0xAA),
               cyan = ui_rgb(0x55, 0xFF, 0xFF), yellow = ui_rgb(0xFF, 0xFF, 0x55), white = ui_rgb(0xFF, 0xFF, 0xFF);

const ui_font_t &font = ui_font_14x28;

// The items' box: at most COLUMNS characters each, as many rows as fit
const int COLUMNS = 42;

// s centered on column cx, at most columns characters of it
void centered(const ui_canvas_t *c, int cx, int y, uint32_t color, const char *s, int columns)
{
    char line[128];
    std::snprintf(line, sizeof line, "%.*s", columns, s);
    ui_text_center(c, &font, cx, y, 1, color, line);
}

// The text mode's double line: two 2-pixel lines, 4 pixels apart
void double_frame(const ui_canvas_t *c, int x, int y, int w, int h, uint32_t color)
{
    ui_frame(c, x, y, w, h, 2, color);
    ui_frame(c, x + 6, y + 6, w - 12, h - 12, 2, color);
}

void double_line(const ui_canvas_t *c, int x, int y, int w, uint32_t color)
{
    ui_fill(c, x, y, w, 2, color);
    ui_fill(c, x, y + 6, w, 2, color);
}
} // namespace

void menu_draw(const ui_canvas_t *c, const menu_screen &m)
{
    const int cx = c->width / 2, ch = font.height, columns = (c->width - 64) / font.width;
    ui_fill(c, 0, 0, c->width, c->height, black);
    double_frame(c, 8, 8, c->width - 16, c->height - 16, grey);

    // From the top: the logo, the title, a double line
    int title_y = 24;
    if (m.logo)
    {
        ui_image(c, cx - m.logo->width / 2, title_y, m.logo);
        title_y += m.logo->height + 8;
    }
    centered(c, cx, title_y, white, m.title, columns);
    double_line(c, 14, title_y + ch + 8, c->width - 28, grey);

    // From the bottom: the keys under a double line, and over it the lines about the item and what
    // is shown
    const int keys_y = c->height - 28 - ch, now_y = keys_y - 32 - ch, about_y = now_y - 4 - ch;
    double_line(c, 14, keys_y - 20, c->width - 28, grey);
    centered(c, cx, keys_y, white, m.keys ? m.keys : "\x18\x19: Select    Enter: Choose    Esc: Exit", columns);
    centered(c, cx, now_y, grey, m.now, columns);
    centered(c, cx, about_y, white, m.about, columns);

    // Between them, the items' box: as many rows as fit, a window that follows the selected one
    const int top = title_y + ch + 28, rows_fit = (about_y - 12 - top - 32) / ch, rows = rows_fit > 1 ? rows_fit : 1;
    const int bw = (COLUMNS + 4) * font.width, bh = rows * ch + 32, bx = cx - bw / 2, by = top;
    double_frame(c, bx, by, bw, bh, white);
    const int first = m.selected < rows ? 0 : m.selected - rows + 1;
    for (int row = 0; row < rows && first + row < m.count; row++)
    {
        const int item = first + row, y = by + 16 + row * ch;
        if (item == m.selected)
            ui_fill(c, bx + 12, y, bw - 24, ch, red);
        centered(c, cx, y, item == m.selected ? white : yellow, m.items[item], COLUMNS);
    }
    // More above or below: arrows beside the box
    if (first > 0)
        ui_text(c, &font, bx + bw + 8, by + 16, 1, cyan, "\x18");
    if (first + rows < m.count)
        ui_text(c, &font, bx + bw + 8, by + 16 + (rows - 1) * ch, 1, cyan, "\x19");
}

ui_image_t menu_image(const void *data, size_t size)
{
    int w, h, channels;
    stbi_uc *rgba = stbi_load_from_memory(static_cast<const stbi_uc *>(data), (int)size, &w, &h, &channels, 4);
    uint32_t *pixels = rgba ? static_cast<uint32_t *>(std::malloc((size_t)w * h * sizeof(uint32_t))) : nullptr;
    if (!pixels)
    {
        stbi_image_free(rgba);
        return {nullptr, 0, 0};
    }
    for (size_t i = 0; i < (size_t)w * h; i++)
    {
        const stbi_uc *p = rgba + 4 * i;
        const uint32_t a = p[3];
        pixels[i] = ui_rgb((p[0] * a + 127) / 255, (p[1] * a + 127) / 255, (p[2] * a + 127) / 255);
    }
    stbi_image_free(rgba);
    return {pixels, w, h};
}

void test_pattern_draw(const ui_canvas_t *c)
{
    const int w = c->width, h = c->height;
    static const uint32_t bars[8] = {ui_rgb(255, 255, 255), ui_rgb(255, 255, 0), ui_rgb(0, 255, 255), ui_rgb(0, 255, 0),
                                     ui_rgb(255, 0, 255),   ui_rgb(255, 0, 0),   ui_rgb(0, 0, 255),   ui_rgb(0, 0, 0)};
    for (int i = 0; i < 8; i++)
        ui_fill(c, i * w / 8, 0, (i + 1) * w / 8 - i * w / 8, h / 2, bars[i]);

    const int grey_y = h / 2, ramp_y = grey_y + h / 6, ramp_h = h / 18, text_y = ramp_y + 3 * ramp_h;
    for (int i = 0; i < 16; i++)
    {
        const uint32_t v = i * 255 / 15;
        ui_fill(c, i * w / 16, grey_y, (i + 1) * w / 16 - i * w / 16, ramp_y - grey_y, ui_rgb(v, v, v));
    }
    for (int x = 0; x < w; x++)
    {
        const uint32_t v = (uint32_t)x * 255 / (w - 1);
        ui_fill(c, x, ramp_y, 1, ramp_h, ui_rgb(v, 0, 0));
        ui_fill(c, x, ramp_y + ramp_h, 1, ramp_h, ui_rgb(0, v, 0));
        ui_fill(c, x, ramp_y + 2 * ramp_h, 1, ramp_h, ui_rgb(0, 0, v));
    }

    ui_fill(c, 0, text_y, w, h - text_y, black);
    char size[32];
    std::snprintf(size, sizeof size, "%d x %d", w, h);
    ui_text_center(c, &font, w / 2, text_y + (h - text_y - font.height) / 2, 1, white, size);
    ui_frame(c, 0, 0, w, h, 1, white);
    ui_line(c, w / 2 - 24, h / 2, w / 2 + 24, h / 2, white);
    ui_line(c, w / 2, h / 2 - 24, w / 2, h / 2 + 24, white);
}
