// lviv_gl on the host: draws an OBJ file as dv/raster_sw reads it (its objs/suzanne.obj), with
// raster_sw's camera, light, material and render state, and writes the frame data as raster_sw's
// --gpu-top-scene does (a line per triangle: its tile mask, then its gpu_triangle_t record as 24
// words), for comparing with raster_sw's gpu_top_scene.hex and for tb/gpu_top (+SCENE=).
//
// Usage: lviv_gl_test geom|gl FILE.obj OUT.hex, or lviv_gl_test gltf FILE OUT.hex
//   geom  through lviv_geom directly, raster_sw's stream: nothing culled, clockwise triangles kept
//         (the core drops them)
//   gl    through the GL API: gluPerspective, gluLookAt, glLight, glMaterial, vertex arrays,
//         back faces culled
//   gltf  a glTF file's scene instead, as gl_test draws it (sdk/gltf: its camera and lights)

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gltf_scene.h"
#include "lviv_geom.h"
#include "lviv_gl.h"

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

// The model geom and gl draw: an OBJ file as raster_sw's loadOBJ (dv/raster_sw/main.cpp) reads
// it, polygons split into fans from their first corner, a vertex per corner: the position and
// normal the corner names (0, 0, 1 if none), the color from the normal and texture coordinates
// mapped from x and y (not the file's)
#define MODEL_VERTICES (3 * CAPACITY)

static struct
{
    int vertices;
    float positions[MODEL_VERTICES][3], normals[MODEL_VERTICES][3], texcoords[MODEL_VERTICES][2];
    uint8_t colors[MODEL_VERTICES][4]; // R, G, B, A
} model;

typedef struct
{
    const float *position, *normal; // normal NULL if the corner names none
} corner_t;

static void add_vertex(corner_t corner)
{
    static const float none[3] = {0.0f, 0.0f, 1.0f};
    const float *p = corner.position, *n = corner.normal ? corner.normal : none;
    const int i = model.vertices++;
    memcpy(model.positions[i], p, sizeof model.positions[i]);
    memcpy(model.normals[i], n, sizeof model.normals[i]);
    for (int k = 0; k < 3; k++)
        model.colors[i][k] = (uint8_t)(fabsf(n[k]) * 255.0f);
    model.colors[i][3] = 255;
    // Planar, 4 times across (its uvScale)
    model.texcoords[i][0] = (p[0] * 0.5f + 0.5f) * 4.0f;
    model.texcoords[i][1] = (p[1] * 0.5f + 0.5f) * 4.0f;
}

static int load_obj(const char *path)
{
    static float positions[MODEL_VERTICES][3], normals[MODEL_VERTICES][3];
    int position_count = 0, normal_count = 0, line_number = 0;
    const char *error = NULL;
    FILE *in = fopen(path, "r");
    if (!in)
    {
        perror(path);
        return -1;
    }
    char line[1024];
    while (!error && fgets(line, sizeof line, in))
    {
        line_number++;
        if (!strchr(line, '\n') && !feof(in))
        {
            error = "line too long";
            break;
        }
        const char *type = strtok(line, " \t\r\n");
        if (!type)
            continue;
        if (strcmp(type, "v") == 0 || strcmp(type, "vn") == 0)
        {
            int *count = type[1] ? &normal_count : &position_count;
            if (*count == MODEL_VERTICES)
                error = "too many vertices";
            else
            {
                float *v = type[1] ? normals[*count] : positions[*count];
                for (int k = 0; k < 3; k++)
                {
                    const char *value = strtok(NULL, " \t\r\n");
                    v[k] = value ? strtof(value, NULL) : 0.0f;
                }
                (*count)++;
            }
        }
        else if (strcmp(type, "f") == 0)
        {
            corner_t first = {NULL, NULL}, previous = {NULL, NULL};
            char *token;
            for (int corners = 0; !error && (token = strtok(NULL, " \t\r\n")) != NULL; corners++)
            {
                // position, position/texture coordinates, position/texture coordinates/normal or
                // position//normal, numbered from 1
                const long p = strtol(token, NULL, 10);
                const char *slash = strchr(token, '/'), *last_slash = strrchr(token, '/');
                const long n = slash != last_slash ? strtol(last_slash + 1, NULL, 10) : 0;
                if (p < 1 || p > position_count)
                    error = "no such vertex";
                else if (corners >= 2 && model.vertices + 3 > MODEL_VERTICES)
                    error = "too many triangles";
                else
                {
                    const corner_t corner = {positions[p - 1], n >= 1 && n <= normal_count ? normals[n - 1] : NULL};
                    if (corners == 0)
                        first = corner;
                    else if (corners >= 2)
                    {
                        add_vertex(first);
                        add_vertex(previous);
                        add_vertex(corner);
                    }
                    previous = corner;
                }
            }
        }
    }
    fclose(in);
    if (error)
        fprintf(stderr, "%s:%d: %s\n", path, line_number, error);
    else if (model.vertices == 0)
        fprintf(stderr, "%s: no triangles\n", path);
    return error || model.vertices == 0 ? -1 : 0;
}

// raster_sw's camera (main.cpp): the model's bounding box, looked at from 1.5 spans along +z
static void camera(lviv_vec3_t *eye, lviv_vec3_t *center)
{
    float lo[3] = {1e9f, 1e9f, 1e9f}, hi[3] = {-1e9f, -1e9f, -1e9f};
    for (int i = 0; i < model.vertices; i++)
        for (int k = 0; k < 3; k++)
        {
            lo[k] = fminf(lo[k], model.positions[i][k]);
            hi[k] = fmaxf(hi[k], model.positions[i][k]);
        }
    *center = (lviv_vec3_t){(lo[0] + hi[0]) * 0.5f, (lo[1] + hi[1]) * 0.5f, (lo[2] + hi[2]) * 0.5f};
    const float span = fmaxf(hi[0] - lo[0], fmaxf(hi[1] - lo[1], hi[2] - lo[2]));
    *eye = (lviv_vec3_t){center->x, center->y, center->z + span * 1.5f};
}

static lviv_vertex_t vertex(int i)
{
    const uint8_t *c = model.colors[i];
    return (lviv_vertex_t){
        {model.positions[i][0], model.positions[i][1], model.positions[i][2]},
        {model.normals[i][0], model.normals[i][1], model.normals[i][2]},
        {model.texcoords[i][0], model.texcoords[i][1]},
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
    for (int i = 0; i + 2 < model.vertices; i += 3)
    {
        const lviv_vertex_t v0 = vertex(i), v1 = vertex(i + 1), v2 = vertex(i + 2);
        lviv_geom_triangle(&g, &s, &v0, &v1, &v2);
    }
    printf("geom: %u triangles in %d tiles from %d, %u dropped\n", g.count, g.tiles_x * g.tiles_y, model.vertices / 3,
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
    glVertexPointer(3, GL_FLOAT, 0, model.positions);
    glNormalPointer(GL_FLOAT, 0, model.normals);
    glColorPointer(4, GL_UNSIGNED_BYTE, 0, model.colors);
    glTexCoordPointer(2, GL_FLOAT, 0, model.texcoords);
    glDrawArrays(GL_TRIANGLES, 0, model.vertices);

    const GLenum error = glGetError();
    if (error != GL_NO_ERROR)
    {
        fprintf(stderr, "gl: error 0x%04x\n", error);
        return 1;
    }
    if (lviv_gl_frame(frame, WIDTH * 4, NULL) != GPU_OK)
        return 1;
    printf("gl: %u triangles from %d\n", lviv_gl_triangles(), model.vertices / 3);
    return 0;
}

// The file at path, whole, with the padding gltf_scene_load reads after it
static unsigned char *read_file(const char *path, size_t *size)
{
    FILE *in = fopen(path, "rb");
    if (!in)
        return NULL;
    unsigned char *data = NULL;
    if (fseek(in, 0, SEEK_END) == 0)
    {
        const long n = ftell(in);
        data = n >= 0 ? calloc((size_t)n + GLTF_SCENE_PADDING, 1) : NULL;
        *size = (size_t)n;
        if (data && (fseek(in, 0, SEEK_SET) != 0 || fread(data, 1, *size, in) != *size))
        {
            free(data);
            data = NULL;
        }
    }
    fclose(in);
    return data;
}

static int draw_gltf(const char *path)
{
    static gpu_t gpu;
    static uint32_t frame[1];
    static uint8_t frame_memory[65536 * LVIV_GL_TRIANGLE_BYTES] __attribute__((aligned(64)));
    size_t size;
    unsigned char *data = read_file(path, &size);
    if (!data)
    {
        perror(path);
        return 1;
    }
    char error[128];
    gltf_scene_t *scene = gltf_scene_load(data, size, error, sizeof error);
    free(data);
    if (!scene)
    {
        fprintf(stderr, "%s: %s\n", path, error);
        return 1;
    }

    if (lviv_gl_init(&gpu, WIDTH, HEIGHT, frame_memory, sizeof frame_memory) != 0)
        return 1;
    glClearColor(0x63 / 255.0f, 0x63 / 255.0f, 0x63 / 255.0f, 1.0f); // gl_test's
    gltf_scene_setup(scene, WIDTH, HEIGHT);
    gltf_scene_draw(scene, 0.0f);
    const GLenum gl_error = glGetError();
    if (gl_error != GL_NO_ERROR)
    {
        fprintf(stderr, "gltf: error 0x%04x\n", gl_error);
        return 1;
    }
    if (lviv_gl_frame(frame, WIDTH * 4, NULL) != GPU_OK)
        return 1;
    printf("gltf: %u triangles from %d, %d texture%s, %d light%s, %s camera\n", lviv_gl_triangles(),
           gltf_scene_triangles(scene), gltf_scene_textures(scene), gltf_scene_textures(scene) == 1 ? "" : "s",
           gltf_scene_lights(scene), gltf_scene_lights(scene) == 1 ? "" : "s",
           gltf_scene_has_camera(scene) ? "its" : "the default");
    gltf_scene_free(scene);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "gltf") == 0)
    {
        out_path = argv[3];
        return draw_gltf(argv[2]);
    }
    if (argc != 4 || (strcmp(argv[1], "geom") != 0 && strcmp(argv[1], "gl") != 0))
    {
        fprintf(stderr, "usage: %s geom|gl FILE.obj OUT.hex, or %s gltf FILE OUT.hex\n", argv[0], argv[0]);
        return 1;
    }
    out_path = argv[3];
    if (load_obj(argv[2]) != 0)
        return 1;
    return strcmp(argv[1], "geom") == 0 ? draw_geom() : draw_gl();
}
