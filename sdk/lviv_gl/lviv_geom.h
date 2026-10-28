// lviv_gl's transform and data building, between the GL API and the GPU driver: object-space
// triangles in, the GPU's frame data out (gpu_triangle_t records and their tile masks, as the
// visibility DMA reads them), and the matrices of GL's matrix calls. Ported from dv/raster_sw:
// GeometryEngine (vertex transform, lighting, clipping, viewport) and Rasterizer's binning (tile
// masks, low-resolution z) and record packing. C++ on GLM (lviv_geom.cpp, sdk/third_party/glm)
// behind this C interface. It uses no BSP headers, so it builds on the host too.
//
// A triangle is culled and binned as it comes, as the GPU sees it, in its frontend's fixed point:
// dropped if its area there is 0, sent to the tiles its bounding box overlaps (clamped to the
// frame), less those an earlier triangle covers wholly and in front of it (lrz). Only triangles in
// a tile at all are kept, in the order they came.
#pragma once

#include <stdint.h>

#include "gpu_triangle.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define LVIV_TILE_SIZE 128
#define LVIV_MAX_TILES 64 // bits in a tile mask
#define LVIV_MAX_LIGHTS 8 // GL_LIGHT0 to GL_LIGHT7 (GL's GL_MAX_LIGHTS)

// Vectors and matrices in C. Matrices are column-major, as OpenGL's (and GLM's).
typedef struct
{
    float x, y;
} lviv_vec2_t;

typedef struct
{
    float x, y, z;
} lviv_vec3_t;

typedef struct
{
    float x, y, z, w;
} lviv_vec4_t;

typedef struct
{
    float m[4][4]; // m[column][row]
} lviv_mat4_t;

// The matrices of GL's matrix calls: m = identity, or m times the call's matrix (m * by,
// glTranslate, glScale, glRotate about an axis of any length but 0, glFrustum, glOrtho,
// gluPerspective, gluLookAt). Angles in radians.
void lviv_mat4_identity(lviv_mat4_t *m);
void lviv_mat4_multiply(lviv_mat4_t *m, const lviv_mat4_t *by);
void lviv_mat4_translate(lviv_mat4_t *m, float x, float y, float z);
void lviv_mat4_scale(lviv_mat4_t *m, float x, float y, float z);
void lviv_mat4_rotate(lviv_mat4_t *m, float angle, float x, float y, float z);
void lviv_mat4_frustum(lviv_mat4_t *m, double left, double right, double bottom, double top, double z_near,
                       double z_far);
void lviv_mat4_ortho(lviv_mat4_t *m, double left, double right, double bottom, double top, double z_near, double z_far);
void lviv_mat4_perspective(lviv_mat4_t *m, float fovy, float aspect, float z_near, float z_far);
void lviv_mat4_look_at(lviv_mat4_t *m, lviv_vec3_t eye, lviv_vec3_t center, lviv_vec3_t up);
// m * v
lviv_vec4_t lviv_mat4_transform(const lviv_mat4_t *m, lviv_vec4_t v);

// A vertex as it is drawn: object space, the color ARGB
typedef struct
{
    lviv_vec3_t position;
    lviv_vec3_t normal;
    lviv_vec2_t texcoord;
    uint32_t color;
} lviv_vertex_t;

typedef struct
{
    lviv_vec4_t position; // eye space; w 0: a direction, else 1
    lviv_vec3_t ambient, diffuse, specular;
    // A positional light's spotlight: its direction (eye space, of length 1), exponent and cutoff
    // (degrees: 180 for none, else 0 to 90; and its cosine); and its attenuation by the distance d,
    // 1 / (constant + linear d + quadratic d^2)
    lviv_vec3_t spot_direction;
    float spot_exponent, spot_cutoff, spot_cos_cutoff;
    float constant_attenuation, linear_attenuation, quadratic_attenuation;
} lviv_light_t;

typedef struct
{
    lviv_vec3_t ambient, diffuse, specular, emissive;
    float shininess;
} lviv_material_t;

typedef enum
{
    LVIV_CULL_NONE,
    LVIV_CULL_BACK,
    LVIV_CULL_FRONT,
    LVIV_CULL_FRONT_AND_BACK,
} lviv_cull_t;

// What a triangle is drawn with
typedef struct
{
    lviv_mat4_t modelview, projection;
    int viewport_x, viewport_y, viewport_width, viewport_height; // glViewport's: from the bottom left
    int lighting;
    lviv_light_t lights[LVIV_MAX_LIGHTS]; // the lights that are on: light_count of them
    int light_count;
    lviv_material_t material;
    lviv_vec3_t global_ambient;
    lviv_cull_t cull;
    int front_ccw; // front faces counter-clockwise (GL_CCW)
    // Swap two vertices of a triangle clockwise on the screen, which the core does not draw. GL
    // draws every triangle it does not cull; 0 keeps raster_sw's stream, whose clockwise triangles
    // the core drops.
    int flip_clockwise;
    // Drop a triangle from a tile that an earlier one covers wholly in front of it: right with a
    // depth test that passes nearer fragments only, and depth writes.
    int lrz;
    // The record's render state (gpu_types_pkg.sv encodings)
    uint8_t tex_id, texture_mode, texture_function, blend, depth_func;
} lviv_state_t;

// A frame being built
typedef struct
{
    gpu_triangle_t *triangles; // capacity of them, 32-byte aligned
    uint64_t *visibility;      // their tile masks, 16-byte aligned
    uint32_t capacity, count;
    uint32_t dropped; // triangles in a tile that did not fit
    int width, height, tiles_x, tiles_y;
    float lrz[LVIV_MAX_TILES]; // per tile, the farthest depth of what covers it wholly
    // From the state's matrices (lviv_geom_matrices): projection * modelview, and the inverse
    // transpose of the modelview's upper 3 x 3 (for normals) in the upper 3 x 3
    lviv_mat4_t mvp, normal_matrix;
} lviv_geom_t;

// A frame of width x height pixels (at most LVIV_MAX_TILES tiles) into these buffers. Returns 0, or
// -1 if the frame has more tiles.
int lviv_geom_begin(lviv_geom_t *g, gpu_triangle_t *triangles, uint64_t *visibility, uint32_t capacity, int width,
                    int height);

// After the state's modelview or projection changed.
void lviv_geom_matrices(lviv_geom_t *g, const lviv_state_t *s);

void lviv_geom_triangle(lviv_geom_t *g, const lviv_state_t *s, const lviv_vertex_t *v0, const lviv_vertex_t *v1,
                        const lviv_vertex_t *v2);

#ifdef __cplusplus
}
#endif
