// gl_test's setup screen and test pattern, drawn with ui.h.
#pragma once

#include <cstddef>

#include "ui.h"

// A setup screen in the BIOS's style, everything centered: the logo and the title; the items in a
// double frame, as many as fit (a window that follows the selected one), the selected one
// highlighted; a line about it, one on what is shown, and the keys.
struct menu_screen
{
    const char *title;
    const char *const *items;
    int count;
    int selected;
    const char *about;       // the selected item, or what went wrong
    const char *now;         // what is shown when the menu is not
    const ui_image_t *logo;  // at its own size, or none (NULL)
    const char *keys;        // the keys' line (NULL: select, choose, exit)
};

void menu_draw(const ui_canvas_t *c, const menu_screen &m);

// A PNG or JPEG file's data (stb_image) as an image for the black screen: blended onto black, opaque,
// its edges smooth. Its pixels from malloc (free() them); none (NULL) if it does not decode.
ui_image_t menu_image(const void *data, size_t size);

// Color bars, grey steps, red, green and blue ramps, the size, a frame at the screen's edge and a
// cross at its center
void test_pattern_draw(const ui_canvas_t *c);
