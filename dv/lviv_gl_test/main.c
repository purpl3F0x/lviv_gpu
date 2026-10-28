// lviv_gl on the host: draws a glTF file's scene (a .glb, or a .gltf with its buffers embedded) as
// gl_test draws it (sdk/gltf: its camera and lights), and writes the frame data as raster_sw's
// --gpu-top-scene does (a line per triangle: its tile mask, then its gpu_triangle_t record as 24
// words), for tb/gpu_top (+SCENE=), or the frame as the CPU draws it. The CPU draws each frame
// (sw_raster.c), and how long it all took is reported, to compare with the GPU.
//
// Usage: lviv_gl_test FILE OUT [FRAMES]
//   OUT     the last frame: OUT.png as the CPU draws it, else (OUT.hex) its data; - for none
//   FRAMES  that many frames, 1 if not given, the model turned a degree a frame as gl_test turns
//           it; their times: the front end's (to gpu_frame) and the CPU's drawing

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "gltf_scene.h"
#include "lviv_gl.h"
#include "sw_raster.h"

// stb_image_write (sdk/third_party/stb), for OUT.png
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define WIDTH 1280
#define HEIGHT 720

static const char *out_path;   // NULL: none
static int out_png;            // OUT a .png
static int frames = 1;         // FRAMES
static gpu_frame_t last_frame; // the last frame gpu_frame got, for OUT
static double raster_seconds;  // in sw_raster, all frames
static uint32_t pixels[HEIGHT * WIDTH];

static double seconds(void)
{
    struct timespec t;
    timespec_get(&t, TIME_UTC);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

static int write_hex(const gpu_frame_t *frame)
{
    FILE *out = fopen(out_path, "w");
    if (!out)
        return -1;
    for (uint32_t t = 0; t < frame->triangle_count; t++)
    {
        uint32_t words[GPU_TRIANGLE_BYTES / 4];
        memcpy(words, &frame->triangles[t], sizeof words);
        fprintf(out, "%016llx", (unsigned long long)frame->visibility[t]);
        for (int w = 0; w < GPU_TRIANGLE_BYTES / 4; w++)
            fprintf(out, " %08x", words[w]);
        fprintf(out, "\n");
    }
    return fclose(out) == 0 ? 0 : -1;
}

// stb wants R, G, B bytes; an ARGB word sits in memory as B, G, R, A
static int write_png(const gpu_frame_t *frame)
{
    static uint8_t rgb[HEIGHT * WIDTH * 3];
    for (uint32_t y = 0; y < frame->height; y++)
        for (uint32_t x = 0; x < frame->width; x++)
        {
            const uint32_t c = frame->frame[y * (frame->stride / 4) + x];
            uint8_t *p = &rgb[3 * (y * frame->width + x)];
            p[0] = (uint8_t)(c >> 16);
            p[1] = (uint8_t)(c >> 8);
            p[2] = (uint8_t)c;
        }
    return stbi_write_png(out_path, (int)frame->width, (int)frame->height, 3, rgb, (int)frame->width * 3) ? 0 : -1;
}

// The GPU driver (gpu.h), on the host: the frame kept for OUT, and drawn by the CPU
gpu_status_t gpu_frame(gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile)
{
    (void)gpu;
    *failed_tile = 0;
    last_frame = *frame;
    const double start = seconds();
    const gpu_status_t status = sw_raster_frame(frame);
    raster_seconds += seconds() - start;
    return status;
}

int gpu_set_texture(const gpu_t *gpu, uint32_t id, const uint32_t *texels, uint32_t log2_size)
{
    (void)gpu;
    return sw_raster_set_texture(id, texels, log2_size);
}

uint32_t gpu_texel_index(uint32_t x, uint32_t y)
{
    uint32_t index = 0;
    for (int bit = 0; bit < 11; bit++)
        index |= (x >> bit & 1u) << (2 * bit) | (y >> bit & 1u) << (2 * bit + 1);
    return index;
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

static gltf_scene_t *scene;

// A frame of the scene, turned as gl_test turns it, to gpu_frame
static int draw_frame(int frame)
{
    gltf_scene_draw(scene, (float)(frame % 360));
    const GLenum error = glGetError();
    if (error != GL_NO_ERROR)
    {
        fprintf(stderr, "GL error 0x%04x\n", error);
        return 1;
    }
    return lviv_gl_frame(pixels, WIDTH * 4, NULL) == GPU_OK ? 0 : 1;
}

// The frames, timed; the last one to OUT. Their average times, and the fastest frame's (less
// disturbed by whatever else the machine runs).
static int run(void)
{
    double total = 0.0, fastest = 1e30, fastest_raster = 1e30;
    raster_seconds = 0.0;
    for (int f = 0; f < frames; f++)
    {
        const double start = seconds(), raster_start = raster_seconds;
        if (draw_frame(f) != 0)
            return 1;
        const double frame_s = seconds() - start, raster_s = raster_seconds - raster_start;
        total += frame_s;
        fastest = frame_s < fastest ? frame_s : fastest;
        fastest_raster = raster_s < fastest_raster ? raster_s : fastest_raster;
    }
    const double frame_ms = total * 1e3 / frames, raster_ms = raster_seconds * 1e3 / frames;
    printf("%d frame%s: %.3f ms a frame (%.1f frames/s; fastest %.3f), front end %.3f ms, rasterizer (%s) %.3f ms "
           "(fastest %.3f)\n",
           frames, frames == 1 ? "" : "s", frame_ms, 1e3 / frame_ms, fastest * 1e3, frame_ms - raster_ms,
           sw_raster_simd(), raster_ms, fastest_raster * 1e3);
    if (out_path && (out_png ? write_png(&last_frame) : write_hex(&last_frame)) != 0)
    {
        perror(out_path);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    static gpu_t gpu;
    // gl_test's (lviv_frame.ld): 256 MiB, about 2.58 million triangles a frame
    static uint8_t frame_memory[256u << 20] __attribute__((aligned(64)));
    if (argc == 4)
        frames = atoi(argv[3]);
    if ((argc != 3 && argc != 4) || frames < 1)
    {
        fprintf(stderr, "usage: %s FILE OUT [FRAMES]: FILE a .gltf or .glb, OUT a .hex, a .png or -\n", argv[0]);
        return 1;
    }
    const char *path = argv[1];
    if (strcmp(argv[2], "-") != 0)
    {
        const size_t n = strlen(argv[2]);
        out_path = argv[2];
        out_png = n >= 4 && strcmp(argv[2] + n - 4, ".png") == 0;
    }

    size_t size;
    unsigned char *data = read_file(path, &size);
    if (!data)
    {
        perror(path);
        return 1;
    }
    char error[128];
    scene = gltf_scene_load(data, size, error, sizeof error);
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
    if (run() != 0)
        return 1;
    printf("%s: %u triangles from %d, %d texture%s, %d light%s, %s camera\n", path, lviv_gl_triangles(),
           gltf_scene_triangles(scene), gltf_scene_textures(scene), gltf_scene_textures(scene) == 1 ? "" : "s",
           gltf_scene_lights(scene), gltf_scene_lights(scene) == 1 ? "" : "s",
           gltf_scene_has_camera(scene) ? "its" : "the default");
    gltf_scene_free(scene);
    return 0;
}
