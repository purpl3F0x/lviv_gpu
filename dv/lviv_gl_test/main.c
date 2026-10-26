// lviv_gl on the host: draws sdk/include/models/suzanne.h with dv/raster_sw's camera, light,
// material and render state, and writes the frame data as raster_sw's --gpu-top-scene does (a line
// per triangle: its tile mask, then its gpu_triangle_t record as 24 words), for comparing with
// raster_sw's gpu_top_scene.hex and for tb/gpu_top (+SCENE=).
//
// Usage: lviv_gl_test geom|gl OUT.hex
//   geom  through lviv_geom directly, raster_sw's stream: nothing culled, clockwise triangles kept
//         (the core drops them)
//   gl    through the GL API: gluPerspective, gluLookAt, glLight, glMaterial, vertex arrays,
//         back faces culled

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "lviv_geom.h"
#include "lviv_gl.h"
#include "models/suzanne.h"

#define WIDTH 1280
#define HEIGHT 720
#define CAPACITY 4096

static const char *out_path;

static int write_hex(const gpu_triangle_t *triangles, const uint64_t *visibility, uint32_t count)
{
    FILE *out = fopen(out_path, "w");
    if (!out)
        return -1;
    for (uint32_t t = 0; t < count; t++)
    {
        uint32_t words[GPU_TRIANGLE_BYTES / 4];
        memcpy(words, &triangles[t], sizeof words);
        fprintf(out, "%016llx", (unsigned long long)visibility[t]);
        for (int w = 0; w < GPU_TRIANGLE_BYTES / 4; w++)
            fprintf(out, " %08x", words[w]);
        fprintf(out, "\n");
    }
    fclose(out);
    return 0;
}

// The GPU driver (gpu.h), on the host: the frame's data to the .hex file
gpu_status_t gpu_frame(gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile)
{
    (void)gpu;
    *failed_tile = 0;
    return write_hex(frame->triangles, frame->visibility, frame->triangle_count) == 0 ? GPU_OK : GPU_TIMEOUT;
}

int gpu_set_texture(const gpu_t *gpu, uint32_t id, const uint32_t *texels, uint32_t log2_size)
{
    (void)gpu;
    (void)id;
    (void)texels;
    (void)log2_size;
    return 0;
}

uint32_t gpu_texel_index(uint32_t x, uint32_t y)
{
    uint32_t index = 0;
    for (int bit = 0; bit < 11; bit++)
        index |= (x >> bit & 1u) << (2 * bit) | (y >> bit & 1u) << (2 * bit + 1);
    return index;
}

// raster_sw's camera (main.cpp): the model's bounding box, looked at from 1.5 spans along +z
static void camera(lviv_vec3_t *eye, lviv_vec3_t *center)
{
    float lo[3] = {1e9f, 1e9f, 1e9f}, hi[3] = {-1e9f, -1e9f, -1e9f};
    for (int i = 0; i < SUZANNE_VERTICES; i++)
        for (int k = 0; k < 3; k++)
        {
            lo[k] = fminf(lo[k], suzanne_positions[i][k]);
            hi[k] = fmaxf(hi[k], suzanne_positions[i][k]);
        }
    *center = (lviv_vec3_t){(lo[0] + hi[0]) * 0.5f, (lo[1] + hi[1]) * 0.5f, (lo[2] + hi[2]) * 0.5f};
    const float span = fmaxf(hi[0] - lo[0], fmaxf(hi[1] - lo[1], hi[2] - lo[2]));
    *eye = (lviv_vec3_t){center->x, center->y, center->z + span * 1.5f};
}

static lviv_vertex_t vertex(int i)
{
    const uint8_t *c = suzanne_colors[i];
    return (lviv_vertex_t){
        {suzanne_positions[i][0], suzanne_positions[i][1], suzanne_positions[i][2]},
        {suzanne_normals[i][0], suzanne_normals[i][1], suzanne_normals[i][2]},
        {suzanne_texcoords[i][0], suzanne_texcoords[i][1]},
        (uint32_t)c[3] << 24 | (uint32_t)c[0] << 16 | (uint32_t)c[1] << 8 | c[2],
    };
}

static int draw_geom(void)
{
    static gpu_triangle_t triangles[CAPACITY];
    static uint64_t visibility[CAPACITY];
    lviv_vec3_t eye, center;
    camera(&eye, &center);

    lviv_state_t s;
    memset(&s, 0, sizeof s);
    lviv_mat4_identity(&s.modelview);
    lviv_mat4_look_at(&s.modelview, eye, center, (lviv_vec3_t){0, 1, 0});
    lviv_mat4_identity(&s.projection);
    lviv_mat4_perspective(&s.projection, 45.0f * 3.14159f / 180.0f, (float)WIDTH / (float)HEIGHT, 0.1f, 1000.0f);
    s.viewport_width = WIDTH;
    s.viewport_height = HEIGHT;
    s.lighting = 1;
    s.lights[0] = (lviv_light_t){{1.0f, 1.0f, 1.0f, 0.0f}, {0.1f, 0.1f, 0.1f}, {1.0f, 1.0f, 1.0f}, {1.0f, 1.0f, 1.0f}};
    s.light_count = 1;
    s.material = (lviv_material_t){{0.5f, 0.5f, 0.5f}, {1.0f, 1.0f, 1.0f}, {1.0f, 1.0f, 1.0f}, {0, 0, 0}, 32.0f};
    s.global_ambient = (lviv_vec3_t){0.2f, 0.2f, 0.2f};
    s.cull = LVIV_CULL_NONE;
    s.front_ccw = 1;
    s.flip_clockwise = 0;
    s.lrz = 1;
    // Untextured, opaque, depth less (Rasterizer::rasterCoreState)
    s.tex_id = GPU_TEX_ID_NONE;
    s.texture_mode = 1u << GPU_TEXTURE_MODE_U_SHIFT | 1u << GPU_TEXTURE_MODE_V_SHIFT;
    s.texture_function = 5;                                            // COLOR
    s.blend = 1u << GPU_SFACTOR_OP_SHIFT | 0u << GPU_DFACTOR_OP_SHIFT; // ONE, ZERO
    s.depth_func = 1;                                                  // LESS

    lviv_geom_t g;
    if (lviv_geom_begin(&g, triangles, visibility, CAPACITY, WIDTH, HEIGHT) != 0)
        return 1;
    lviv_geom_matrices(&g, &s);
    for (int i = 0; i + 2 < SUZANNE_VERTICES; i += 3)
    {
        const lviv_vertex_t v0 = vertex(i), v1 = vertex(i + 1), v2 = vertex(i + 2);
        lviv_geom_triangle(&g, &s, &v0, &v1, &v2);
    }
    printf("geom: %u triangles in %d tiles from %d, %u dropped\n", g.count, g.tiles_x * g.tiles_y, SUZANNE_VERTICES / 3,
           g.dropped);
    return write_hex(triangles, visibility, g.count) == 0 ? 0 : 1;
}

static int draw_gl(void)
{
    static gpu_t gpu;
    static uint32_t frame[1];
    static uint8_t frame_memory[4096 * LVIV_GL_TRIANGLE_BYTES] __attribute__((aligned(64)));
    lviv_vec3_t eye, center;
    camera(&eye, &center);

    if (lviv_gl_init(&gpu, WIDTH, HEIGHT, frame_memory, sizeof frame_memory) != 0)
        return 1;
    glViewport(0, 0, WIDTH, HEIGHT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45.0, (double)WIDTH / HEIGHT, 0.1, 1000.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // The light in eye space: set with the identity modelview
    const GLfloat light_position[] = {1, 1, 1, 0}, light_ambient[] = {0.1f, 0.1f, 0.1f, 1}, white[] = {1, 1, 1, 1};
    const GLfloat material_ambient[] = {0.5f, 0.5f, 0.5f, 1};
    glLightfv(GL_LIGHT0, GL_POSITION, light_position);
    glLightfv(GL_LIGHT0, GL_AMBIENT, light_ambient);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
    glLightfv(GL_LIGHT0, GL_SPECULAR, white);
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, material_ambient);
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, white);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, white);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 32.0f);
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glEnable(GL_CULL_FACE);

    glClearColor(0x63 / 255.0f, 0x63 / 255.0f, 0x63 / 255.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    gluLookAt(eye.x, eye.y, eye.z, center.x, center.y, center.z, 0, 1, 0);

    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glVertexPointer(3, GL_FLOAT, 0, suzanne_positions);
    glNormalPointer(GL_FLOAT, 0, suzanne_normals);
    glColorPointer(4, GL_UNSIGNED_BYTE, 0, suzanne_colors);
    glTexCoordPointer(2, GL_FLOAT, 0, suzanne_texcoords);
    glDrawArrays(GL_TRIANGLES, 0, SUZANNE_VERTICES);

    const GLenum error = glGetError();
    if (error != GL_NO_ERROR)
    {
        fprintf(stderr, "gl: error 0x%04x\n", error);
        return 1;
    }
    if (lviv_gl_frame(frame, WIDTH * 4, NULL) != GPU_OK)
        return 1;
    printf("gl: %u triangles from %d\n", lviv_gl_triangles(), SUZANNE_VERTICES / 3);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 3 || (strcmp(argv[1], "geom") != 0 && strcmp(argv[1], "gl") != 0))
    {
        fprintf(stderr, "usage: %s geom|gl OUT.hex\n", argv[0]);
        return 1;
    }
    out_path = argv[2];
    return strcmp(argv[1], "geom") == 0 ? draw_geom() : draw_gl();
}
