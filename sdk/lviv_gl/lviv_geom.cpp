// lviv_geom.h's C interface, in C++ on GLM.
#include "lviv_geom.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_inverse.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

// The vectors are converted one component at a time (GLM's may be padded: its aligned vec3 is 16
// bytes); a matrix is copied as its 16 floats, column by column.
static_assert(sizeof(lviv_mat4_t) == sizeof(glm::mat4), "lviv_mat4_t is laid out as glm::mat4");

static glm::vec2 to_glm(lviv_vec2_t v)
{
    return glm::vec2(v.x, v.y);
}

static glm::vec3 to_glm(lviv_vec3_t v)
{
    return glm::vec3(v.x, v.y, v.z);
}

static glm::vec4 to_glm(lviv_vec4_t v)
{
    return glm::vec4(v.x, v.y, v.z, v.w);
}

static glm::mat4 to_glm(const lviv_mat4_t &m)
{
    return glm::make_mat4(&m.m[0][0]);
}

static void store(lviv_mat4_t *m, const glm::mat4 &r)
{
    std::memcpy(m->m, glm::value_ptr(r), sizeof m->m);
}

//
// GL's matrices
//

void lviv_mat4_identity(lviv_mat4_t *m)
{
    store(m, glm::mat4(1.0f));
}

void lviv_mat4_multiply(lviv_mat4_t *m, const lviv_mat4_t *by)
{
    store(m, to_glm(*m) * to_glm(*by));
}

void lviv_mat4_translate(lviv_mat4_t *m, float x, float y, float z)
{
    store(m, glm::translate(to_glm(*m), glm::vec3(x, y, z)));
}

void lviv_mat4_scale(lviv_mat4_t *m, float x, float y, float z)
{
    store(m, glm::scale(to_glm(*m), glm::vec3(x, y, z)));
}

void lviv_mat4_rotate(lviv_mat4_t *m, float angle, float x, float y, float z)
{
    store(m, glm::rotate(to_glm(*m), angle, glm::vec3(x, y, z)));
}

void lviv_mat4_frustum(lviv_mat4_t *m, double left, double right, double bottom, double top, double z_near,
                       double z_far)
{
    store(m, to_glm(*m) * glm::mat4(glm::frustum(left, right, bottom, top, z_near, z_far)));
}

void lviv_mat4_ortho(lviv_mat4_t *m, double left, double right, double bottom, double top, double z_near, double z_far)
{
    store(m, to_glm(*m) * glm::mat4(glm::ortho(left, right, bottom, top, z_near, z_far)));
}

void lviv_mat4_perspective(lviv_mat4_t *m, float fovy, float aspect, float z_near, float z_far)
{
    store(m, to_glm(*m) * glm::perspective(fovy, aspect, z_near, z_far));
}

void lviv_mat4_look_at(lviv_mat4_t *m, lviv_vec3_t eye, lviv_vec3_t center, lviv_vec3_t up)
{
    store(m, to_glm(*m) * glm::lookAt(to_glm(eye), to_glm(center), to_glm(up)));
}

lviv_vec4_t lviv_mat4_transform(const lviv_mat4_t *m, lviv_vec4_t v)
{
    const glm::vec4 r = to_glm(*m) * to_glm(v);
    return {r.x, r.y, r.z, r.w};
}

//
// The pipeline
//

// The state's matrices, for a triangle's vertices
struct transforms_t
{
    glm::mat4 mvp, modelview;
    glm::mat3 normal;
};

// After the vertex shader
struct clip_vertex_t
{
    glm::vec4 position; // clip space
    glm::vec2 texcoord;
    uint32_t color;
};

// After the viewport
struct screen_vertex_t
{
    glm::vec4 position; // x, y in pixels from the top left, z in [0, 1], w = 1 / clip w
    glm::vec2 texcoord;
    uint32_t color;
};

// A triangle clipped by 6 planes has at most 9 corners.
static const int CLIP_MAX = 9;

int lviv_geom_begin(lviv_geom_t *g, gpu_triangle_t *triangles, uint64_t *visibility, uint32_t capacity, int width,
                    int height)
{
    g->triangles = triangles;
    g->visibility = visibility;
    g->capacity = capacity;
    g->count = 0;
    g->dropped = 0;
    g->width = width;
    g->height = height;
    g->tiles_x = (width + LVIV_TILE_SIZE - 1) / LVIV_TILE_SIZE;
    g->tiles_y = (height + LVIV_TILE_SIZE - 1) / LVIV_TILE_SIZE;
    if (g->tiles_x * g->tiles_y > LVIV_MAX_TILES)
        return -1;
    for (int t = 0; t < LVIV_MAX_TILES; t++)
        g->lrz[t] = 1.0f;
    return 0;
}

void lviv_geom_matrices(lviv_geom_t *g, const lviv_state_t *s)
{
    const glm::mat4 modelview = to_glm(s->modelview);
    store(&g->mvp, to_glm(s->projection) * modelview);
    // The identity if the modelview is singular
    const glm::mat3 upper(modelview);
    store(&g->normal_matrix,
          std::fabs(glm::determinant(upper)) < 1e-6f ? glm::mat4(1.0f) : glm::mat4(glm::inverseTranspose(upper)));
}

// Of length 1, or unchanged when of length 0
static glm::vec3 unit(glm::vec3 v)
{
    const float l = glm::length(v);
    return l > 0 ? v / l : v;
}

static float clamp01(float x)
{
    return std::fmin(1.0f, std::fmax(0.0f, x));
}

// GL 1.x's fixed-function lighting of one vertex, in eye space: the emission and the global ambient,
// then each light that is on adds its ambient, diffuse and specular terms, a positional light's
// scaled by its attenuation and its spotlight
static uint32_t light(const transforms_t &x, const lviv_state_t &s, const lviv_vertex_t &v)
{
    const glm::vec3 eye(x.modelview * glm::vec4(to_glm(v.position), 1.0f));
    const glm::vec3 n = unit(x.normal * to_glm(v.normal));
    const glm::vec3 to_eye = unit(-eye);

    const lviv_material_t &m = s.material;
    glm::vec3 c = to_glm(m.emissive) + to_glm(m.ambient) * to_glm(s.global_ambient);
    for (int i = 0; i < s.light_count; i++)
    {
        const lviv_light_t &l = s.lights[i];
        const glm::vec3 lpos(to_glm(l.position));
        const bool positional = l.position.w != 0.0f;
        const glm::vec3 to_light = unit(positional ? lpos - eye : lpos);
        const glm::vec3 half = unit(to_light + to_eye);

        // By the distance, and outside its spotlight's cone none: (cos of the angle from its
        // direction)^exponent inside
        float scale = 1.0f;
        if (positional)
        {
            const float d = glm::length(lpos - eye);
            scale = 1.0f / (l.constant_attenuation + l.linear_attenuation * d + l.quadratic_attenuation * d * d);
            if (l.spot_cutoff != 180.0f)
            {
                const float spot = glm::dot(-to_light, to_glm(l.spot_direction));
                scale *= spot < l.spot_cos_cutoff ? 0.0f : std::pow(spot, l.spot_exponent);
            }
        }

        const float n_dot_l = std::fmax(0.0f, glm::dot(n, to_light));
        const float n_dot_h = std::fmax(0.0f, glm::dot(n, half));

        glm::vec3 lit = to_glm(m.ambient) * to_glm(l.ambient) + to_glm(m.diffuse) * to_glm(l.diffuse) * n_dot_l;
        if (n_dot_l > 0.0f && m.shininess > 0.0f)
            lit += to_glm(m.specular) * to_glm(l.specular) * std::pow(n_dot_h, m.shininess);
        c += scale * lit;
    }
    const uint32_t r = (uint8_t)(clamp01(c.x) * 255.0f);
    const uint32_t gr = (uint8_t)(clamp01(c.y) * 255.0f);
    const uint32_t b = (uint8_t)(clamp01(c.z) * 255.0f);
    return 0xFF000000u | r << 16 | gr << 8 | b;
}

// The vertex in clip space, with its own color: lit later, if at all
static clip_vertex_t transform_vertex(const transforms_t &x, const lviv_vertex_t &v)
{
    clip_vertex_t o;
    o.position = x.mvp * glm::vec4(to_glm(v.position), 1.0f);
    o.color = v.color;
    o.texcoord = to_glm(v.texcoord);
    return o;
}

// Distance to a clip plane: left, right, bottom, top, near, far
static float plane_distance(const glm::vec4 &p, int plane)
{
    switch (plane)
    {
    case 0:
        return p.w + p.x;
    case 1:
        return p.w - p.x;
    case 2:
        return p.w + p.y;
    case 3:
        return p.w - p.y;
    case 4:
        return p.w + p.z;
    default:
        return p.w - p.z;
    }
}

// a + (b - a) * t, the color channel by channel
static clip_vertex_t lerp(const clip_vertex_t &a, const clip_vertex_t &b, float t)
{
    clip_vertex_t r;
    r.position = a.position + (b.position - a.position) * t;
    r.texcoord = a.texcoord + (b.texcoord - a.texcoord) * t;
    r.color = 0;
    for (int shift = 0; shift < 32; shift += 8)
    {
        const float ca = (float)(a.color >> shift & 0xFF), cb = (float)(b.color >> shift & 0xFF);
        r.color |= (uint32_t)(ca + (cb - ca) * t + 0.5f) << shift;
    }
    return r;
}

// Sutherland-Hodgman against one plane: the corners of out, or 0
static int clip_plane(const clip_vertex_t *in, int n, clip_vertex_t *out, int plane)
{
    int m = 0;
    for (int i = 0; i < n; i++)
    {
        const clip_vertex_t &curr = in[i], &prev = in[i == 0 ? n - 1 : i - 1];
        const float d_curr = plane_distance(curr.position, plane), d_prev = plane_distance(prev.position, plane);
        const bool curr_in = d_curr >= 0.0f, prev_in = d_prev >= 0.0f;
        if (curr_in != prev_in)
            out[m++] = lerp(prev, curr, d_prev / (d_prev - d_curr));
        if (curr_in)
            out[m++] = curr;
    }
    return m;
}

static screen_vertex_t viewport(const lviv_geom_t &g, const lviv_state_t &s, const clip_vertex_t &v)
{
    const float inv_w = 1.0f / v.position.w;
    const float ndc_x = v.position.x * inv_w, ndc_y = v.position.y * inv_w, ndc_z = v.position.z * inv_w;
    // y from the top: the viewport's top edge is height - (y + viewport height) rows down
    const float top = (float)(g.height - s.viewport_y - s.viewport_height);
    screen_vertex_t o;
    o.position.x = (float)s.viewport_x + (ndc_x + 1.0f) * (0.5f * (float)s.viewport_width);
    o.position.y = top + (1.0f - ndc_y) * (0.5f * (float)s.viewport_height);
    o.position.z = (ndc_z + 1.0f) * 0.5f;
    o.position.w = inv_w;
    o.texcoord = v.texcoord;
    o.color = v.color;
    return o;
}

// A screen position in the GPU frontend's fixed point, as fp_to_fx14_10 makes it: 1/1024 of a
// pixel, rounded to nearest, ties to even
static int32_t frontend_fixed(const float p)
{
    return (int32_t)std::nearbyint(p * 1024.0f); // round to a multiple of 1/1024
}

// A screen vertex's x and y in the frontend's fixed point
struct fixed_xy_t
{
    int32_t x, y;
};

// As the GPU computes it, exactly: in its fixed point, the products in 2^-20 px^2. Positive when
// a, b, c run counter-clockwise on the screen. The core draws a pixel whose center is at 0 or more
// from all three edges (thread.sv), so nothing of a clockwise triangle: the three add up to its
// area.
static int64_t edge(fixed_xy_t a, fixed_xy_t b, fixed_xy_t c)
{
    return (int64_t)(c.x - a.x) * (b.y - a.y) - (int64_t)(c.y - a.y) * (b.x - a.x);
}

// !BUG
// TODO: maybe fix on the frontend ? (both ?)
// ?Explanation: 
// The GPU frontend's bounding box, in pixels, of positions from min to max, as fp_to_fx14_10 and
// tri_bb_aligned_boundries make it: in its fixed point (1/1024 of a pixel, rounded to nearest, ties
// to even; a plain cast would truncate), floored, the minimum snapped to even and the maximum to
// odd. Binned by its float positions instead, a triangle starting within 1/2048 of a pixel below a
// tile boundary would go to the tile before, which this box misses: the frontend's box clamped to
// that tile is then empty, its width in the tile wraps to the whole tile, and the triangle is drawn
// there a tile to the side.
static int frontend_min(const int32_t n)
{
    return (n >> 10) & ~1; // floor(n / 1024), clear bit 0
}

static int frontend_max(const int32_t n)
{
    return (n >> 10) | 1; // floor(n / 1024), set bit 0
}

// The tiles the triangle goes to, with the low-resolution z updated; q: its x and y in the
// frontend's fixed point
static uint64_t bin(lviv_geom_t &g, const lviv_state_t &s, const screen_vertex_t *v, const fixed_xy_t *q)
{
    const int min_x = std::max(0, frontend_min(std::min({q[0].x, q[1].x, q[2].x})));
    const int max_x = std::min(g.width - 1, frontend_max(std::max({q[0].x, q[1].x, q[2].x})));
    const int min_y = std::max(0, frontend_min(std::min({q[0].y, q[1].y, q[2].y})));
    const int max_y = std::min(g.height - 1, frontend_max(std::max({q[0].y, q[1].y, q[2].y})));
    if (min_x > max_x || min_y > max_y)
        return 0;

    const float min_z = std::fmin(std::fmin(v[0].position.z, v[1].position.z), v[2].position.z);
    const float max_z = std::fmax(std::fmax(v[0].position.z, v[1].position.z), v[2].position.z);

    uint64_t mask = 0;
    for (int ty = min_y / LVIV_TILE_SIZE; ty <= max_y / LVIV_TILE_SIZE; ty++)
    {
        for (int tx = min_x / LVIV_TILE_SIZE; tx <= max_x / LVIV_TILE_SIZE; tx++)
        {
            const int tile = ty * g.tiles_x + tx;
            if (s.lrz && min_z > g.lrz[tile])
                continue; // behind what covers the tile
            mask |= 1ull << tile;
            if (!s.lrz)
                continue;

            // Covering the tile wholly, the core drawing each of its pixels: its corner pixels'
            // centers inside
            const int32_t left = (tx * LVIV_TILE_SIZE << 10) + 512, right = left + ((LVIV_TILE_SIZE - 1) << 10);
            const int32_t top = (ty * LVIV_TILE_SIZE << 10) + 512, bottom = top + ((LVIV_TILE_SIZE - 1) << 10);
            const fixed_xy_t corners[4] = {{left, top}, {right, top}, {left, bottom}, {right, bottom}};
            bool covers = true;
            for (int c = 0; c < 4 && covers; c++)
                covers = edge(q[1], q[2], corners[c]) >= 0 && edge(q[2], q[0], corners[c]) >= 0 &&
                         edge(q[0], q[1], corners[c]) >= 0;
            if (covers)
                g.lrz[tile] = std::fmin(g.lrz[tile], max_z);
        }
    }
    return mask;
}

// The triangle on the screen as the GPU sees it, its x and y in the frontend's fixed point (q): its
// area there, or 0 if degenerate or culled
static int64_t screen_area(const lviv_state_t &s, const screen_vertex_t *v, fixed_xy_t *q)
{
    for (int k = 0; k < 3; k++)
        q[k] = {frontend_fixed(v[k].position.x), frontend_fixed(v[k].position.y)};
    const int64_t area = edge(q[0], q[1], q[2]);
    if (area == 0)
        return 0; // degenerate
    const bool front = (area > 0) == (s.front_ccw != 0);
    if ((front && (s.cull == LVIV_CULL_FRONT || s.cull == LVIV_CULL_FRONT_AND_BACK)) ||
        (!front && (s.cull == LVIV_CULL_BACK || s.cull == LVIV_CULL_FRONT_AND_BACK)))
        return 0;
    return area;
}

// The tiles the triangle goes to, or none if it is in none or there is no room for it (dropped)
static uint64_t place(lviv_geom_t &g, const lviv_state_t &s, const screen_vertex_t *v, const fixed_xy_t *q)
{
    const uint64_t mask = bin(g, s, v, q);
    if (mask && g.count == g.capacity)
    {
        g.dropped++;
        return 0;
    }
    return mask;
}

static void record(lviv_geom_t &g, const lviv_state_t &s, const screen_vertex_t *v, uint64_t mask)
{
    gpu_triangle_t *t = &g.triangles[g.count];
    std::memset(t, 0, sizeof *t);
    for (int i = 0; i < 3; i++)
        t->v[i] = gpu_vertex_t{v[i].position.x, v[i].position.y, v[i].position.z, v[i].position.w,
                               v[i].color,      v[i].texcoord.x, v[i].texcoord.y};
    t->tex_id = s.tex_id;
    t->texture_mode = s.texture_mode;
    t->texture_function = s.texture_function;
    t->blend = s.blend;
    t->depth_func = s.depth_func;
    g.visibility[g.count++] = mask;
}

void lviv_geom_triangle(lviv_geom_t *g, const lviv_state_t *s, const lviv_vertex_t *v0, const lviv_vertex_t *v1,
                        const lviv_vertex_t *v2)
{
    const transforms_t x = {to_glm(g->mvp), to_glm(s->modelview), glm::mat3(to_glm(g->normal_matrix))};
    const lviv_vertex_t *v[3] = {v0, v1, v2};
    clip_vertex_t poly[2][CLIP_MAX];
    bool inside = true;
    for (int k = 0; k < 3; k++)
    {
        poly[0][k] = transform_vertex(x, *v[k]);
        for (int plane = 0; plane < 6; plane++)
            inside = inside && plane_distance(poly[0][k].position, plane) >= 0.0f;
    }

    // Inside every clip plane, as clipping leaves it: culled and binned first, lit (most of the
    // work) only if kept
    if (inside)
    {
        screen_vertex_t sv[3] = {viewport(*g, *s, poly[0][0]), viewport(*g, *s, poly[0][1]),
                                 viewport(*g, *s, poly[0][2])};
        fixed_xy_t q[3];
        const int64_t area = screen_area(*s, sv, q);
        if (area == 0)
            return;
        if (area < 0 && s->flip_clockwise)
        {
            std::swap(sv[1], sv[2]);
            std::swap(q[1], q[2]);
            std::swap(v[1], v[2]);
        }
        const uint64_t mask = place(*g, *s, sv, q);
        if (!mask)
            return;
        if (s->lighting)
            for (int k = 0; k < 3; k++)
                sv[k].color = light(x, *s, *v[k]);
        record(*g, *s, sv, mask);
        return;
    }

    // Across a plane: lit first, the colors clipped with the rest
    if (s->lighting)
        for (int k = 0; k < 3; k++)
            poly[0][k].color = light(x, *s, *v[k]);
    int n = 3, cur = 0;
    for (int plane = 0; plane < 6; plane++)
    {
        n = clip_plane(poly[cur], n, poly[cur ^ 1], plane);
        cur ^= 1;
        if (n < 3)
            return;
    }

    // A fan from the first corner, each triangle culled and binned as the GPU sees it
    for (int i = 2; i < n; i++)
    {
        screen_vertex_t sv[3] = {viewport(*g, *s, poly[cur][0]), viewport(*g, *s, poly[cur][i - 1]),
                                 viewport(*g, *s, poly[cur][i])};
        fixed_xy_t q[3];
        const int64_t area = screen_area(*s, sv, q);
        if (area == 0)
            continue;
        if (area < 0 && s->flip_clockwise)
        {
            std::swap(sv[1], sv[2]);
            std::swap(q[1], q[2]);
        }
        const uint64_t mask = place(*g, *s, sv, q);
        if (mask)
            record(*g, *s, sv, mask);
    }
}
