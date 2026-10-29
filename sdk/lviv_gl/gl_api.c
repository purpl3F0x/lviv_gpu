#include "lviv_gl.h"

#include <math.h>
#include <string.h>

#include "lviv_geom.h"

// Capacities: the texture memory, the matrix stacks (GL's minimums). The triangles a frame keeps
// (after clipping, culling and binning) are as many as the platform's frame memory holds
// (lviv_gl_init).
#ifndef LVIV_GL_TEXTURE_BYTES
#define LVIV_GL_TEXTURE_BYTES (32u << 20)
#endif
#define MODELVIEW_DEPTH 32
#define PROJECTION_DEPTH 2

// The GPU's texture table (gpu_map.h's GPU_TEXTURES, GPU_TEXTURE_MAX_LOG2); GL names are 1 more
#define TEXTURES 128
#define TEXTURE_MAX_LOG2 11

// The record's encodings (gpu_types_pkg.sv)
#define FRAGMENT_COLOR 5
#define DEPTH_ALWAYS 7

#define PI 3.14159265358979323846

typedef struct
{
    int enabled;
    GLint size;
    GLenum type;
    GLsizei stride; // bytes, 0 packed
    const uint8_t *pointer;
} array_t;

typedef struct
{
    int generated, loaded;
    int tile_s, tile_t; // GL_REPEAT, else clamp
    uint32_t log2_size;
    uint32_t *texels; // Morton order, in the pool
} texture_t;

// Read by the GPU's texture caches
static uint32_t texture_pool[LVIV_GL_TEXTURE_BYTES / 4] __attribute__((aligned(4096)));

static struct
{
    gpu_t *gpu;
    int width, height;
    GLenum error;

    // The frame memory (lviv_gl_init), read by the GPU's masters: capacity triangles' records, then
    // their tile masks
    gpu_triangle_t *triangles;
    uint64_t *visibility;
    uint32_t capacity;
    lviv_geom_t geom;
    lviv_state_t state; // what lviv_geom draws with, kept up to date with the GL state
    int matrices_dirty;
    uint32_t dropped; // geom.dropped when the frame started
    uint32_t last_triangles;

    GLenum matrix_mode;
    lviv_mat4_t modelview[MODELVIEW_DEPTH], projection[PROJECTION_DEPTH];
    int modelview_top, projection_top;

    int depth_test, cull_face, lighting, blend, texture_2d, normalize;
    int light_on[LVIV_MAX_LIGHTS];
    GLenum cull_mode, front_face, depth_func, sfactor, dfactor, tex_env;
    lviv_light_t lights[LVIV_MAX_LIGHTS]; // GL_LIGHT0 + i, positions in eye space
    uint32_t clear_color, frame_clear_color;

    // The current vertex attributes
    lviv_vec3_t normal;
    lviv_vec2_t texcoord;
    uint32_t color;

    // The primitive being assembled
    GLenum prim;
    int in_begin;
    uint32_t n;              // its vertices so far
    lviv_vertex_t first;     // fans and polygons
    lviv_vertex_t recent[4]; // the last vertices, vertex k at k % 4

    array_t vertex_array, normal_array, color_array, texcoord_array;

    texture_t textures[TEXTURES];
    GLuint bound; // a GL name, 0 none
    uint8_t *pool_next;
} gl;

static void set_error(GLenum error)
{
    if (gl.error == GL_NO_ERROR)
        gl.error = error;
}

static uint8_t to_byte(float c)
{
    return (uint8_t)(fminf(1.0f, fmaxf(0.0f, c)) * 255.0f + 0.5f);
}

static uint32_t argb(float r, float g, float b, float a)
{
    return (uint32_t)to_byte(a) << 24 | (uint32_t)to_byte(r) << 16 | (uint32_t)to_byte(g) << 8 | to_byte(b);
}

// The GPU's encodings of GL's blend factors, texture functions and wrap modes
static int blend_op(GLenum factor)
{
    static const struct
    {
        GLenum gl;
        uint8_t gpu;
    } map[] = {{GL_ZERO, 0},      {GL_ONE, 1},
               {GL_SRC_COLOR, 2}, {GL_ONE_MINUS_SRC_COLOR, 3},
               {GL_DST_COLOR, 4}, {GL_ONE_MINUS_DST_COLOR, 5},
               {GL_SRC_ALPHA, 6}, {GL_ONE_MINUS_SRC_ALPHA, 7},
               {GL_DST_ALPHA, 8}, {GL_ONE_MINUS_DST_ALPHA, 9}};
    for (unsigned i = 0; i < sizeof map / sizeof map[0]; i++)
        if (map[i].gl == factor)
            return map[i].gpu;
    return -1;
}

static int texture_function(GLenum mode)
{
    switch (mode)
    {
    case GL_REPLACE:
        return 0;
    case GL_MODULATE:
        return 1;
    case GL_DECAL:
        return 2;
    case GL_BLEND:
        return 3;
    case GL_ADD:
        return 4;
    }
    return -1;
}

// The render state lviv_geom draws with, from the GL state
static void update_state(void)
{
    lviv_state_t *s = &gl.state;
    s->lighting = gl.lighting;
    s->light_count = 0;
    for (int i = 0; i < LVIV_MAX_LIGHTS; i++)
        if (gl.light_on[i])
            s->lights[s->light_count++] = gl.lights[i];
    s->cull = !gl.cull_face                       ? LVIV_CULL_NONE
              : gl.cull_mode == GL_FRONT          ? LVIV_CULL_FRONT
              : gl.cull_mode == GL_FRONT_AND_BACK ? LVIV_CULL_FRONT_AND_BACK
                                                  : LVIV_CULL_BACK;
    s->front_ccw = gl.front_face == GL_CCW;
    s->flip_clockwise = 1; // GL draws both windings of what it does not cull
    s->depth_func = gl.depth_test ? (uint8_t)(gl.depth_func & 7) : DEPTH_ALWAYS;
    s->lrz = gl.depth_test && (gl.depth_func == GL_LESS || gl.depth_func == GL_LEQUAL);
    s->blend = gl.blend ? (uint8_t)(blend_op(gl.sfactor) << GPU_SFACTOR_OP_SHIFT | blend_op(gl.dfactor)
                                                                                       << GPU_DFACTOR_OP_SHIFT)
                        : (uint8_t)(1u << GPU_SFACTOR_OP_SHIFT);

    const texture_t *t = gl.bound ? &gl.textures[gl.bound - 1] : NULL;
    if (gl.texture_2d && t && t->loaded)
    {
        s->tex_id = (uint8_t)(gl.bound - 1);
        s->texture_mode = (uint8_t)(t->tile_s << GPU_TEXTURE_MODE_U_SHIFT | t->tile_t << GPU_TEXTURE_MODE_V_SHIFT);
        s->texture_function = (uint8_t)texture_function(gl.tex_env);
    }
    else
    {
        s->tex_id = GPU_TEX_ID_NONE;
        s->texture_mode = 1u << GPU_TEXTURE_MODE_U_SHIFT | 1u << GPU_TEXTURE_MODE_V_SHIFT;
        s->texture_function = FRAGMENT_COLOR;
    }
}

static void begin_frame(void)
{
    lviv_geom_begin(&gl.geom, gl.triangles, gl.visibility, gl.capacity, gl.width, gl.height);
    gl.dropped = 0;
    gl.matrices_dirty = 1;
}

int lviv_gl_init(gpu_t *gpu, int width, int height, void *frame_memory, size_t frame_bytes)
{
    memset(&gl, 0, sizeof gl);
    if ((uintptr_t)frame_memory % 64 != 0)
        return -1;
    gl.gpu = gpu;
    gl.width = width;
    gl.height = height;
    const size_t n = frame_bytes / LVIV_GL_TRIANGLE_BYTES;
    gl.capacity = n > UINT32_MAX ? UINT32_MAX : (uint32_t)n;
    gl.triangles = frame_memory;
    gl.visibility = (uint64_t *)(gl.triangles + gl.capacity);
    if (gl.capacity == 0 || lviv_geom_begin(&gl.geom, gl.triangles, gl.visibility, gl.capacity, width, height) != 0)
        return -1;

    gl.matrix_mode = GL_MODELVIEW;
    lviv_mat4_identity(&gl.modelview[0]);
    lviv_mat4_identity(&gl.projection[0]);
    gl.state.modelview = gl.modelview[0];
    gl.state.projection = gl.projection[0];
    gl.matrices_dirty = 1;
    gl.state.viewport_width = width;
    gl.state.viewport_height = height;

    // GL's defaults
    gl.cull_mode = GL_BACK;
    gl.front_face = GL_CCW;
    gl.depth_func = GL_LESS;
    gl.sfactor = GL_ONE;
    gl.dfactor = GL_ZERO;
    gl.tex_env = GL_MODULATE;
    // Toward -z, black, no spotlight (cutoff 180, toward -z) and no attenuation; GL_LIGHT0 white
    for (int i = 0; i < LVIV_MAX_LIGHTS; i++)
        gl.lights[i] = (lviv_light_t){.position = {0, 0, 1, 0},
                                      .spot_direction = {0, 0, -1},
                                      .spot_cutoff = 180.0f,
                                      .spot_cos_cutoff = -1.0f,
                                      .constant_attenuation = 1.0f};
    gl.lights[0].diffuse = gl.lights[0].specular = (lviv_vec3_t){1, 1, 1};
    gl.state.material = (lviv_material_t){{0.2f, 0.2f, 0.2f}, {0.8f, 0.8f, 0.8f}, {0, 0, 0}, {0, 0, 0}, 0.0f};
    gl.state.global_ambient = (lviv_vec3_t){0.2f, 0.2f, 0.2f};
    gl.normal = (lviv_vec3_t){0, 0, 1};
    gl.color = 0xFFFFFFFFu;
    gl.pool_next = (uint8_t *)texture_pool;
    update_state();
    return 0;
}

// The first count triangles of the frame memory, into target; then the next frame
static gpu_status_t render(uint32_t count, uint32_t *target, uint32_t stride, uint32_t *failed_tile)
{
    const gpu_frame_t f = {
        .triangles = gl.triangles,
        .visibility = gl.visibility,
        .triangle_count = count,
        .frame = target,
        .stride = stride,
        .width = (uint32_t)gl.width,
        .height = (uint32_t)gl.height,
        .clear_color = gl.frame_clear_color,
    };
    uint32_t tile;
    gl.last_triangles = count;
    const gpu_status_t status = gpu_frame(gl.gpu, &f, &tile);
    if (failed_tile)
        *failed_tile = tile;
    begin_frame();
    return status;
}

gpu_status_t lviv_gl_frame(uint32_t *target, uint32_t stride, uint32_t *failed_tile)
{
    return render(gl.geom.count, target, stride, failed_tile);
}

gpu_status_t lviv_gl_frame_again(uint32_t *target, uint32_t stride, uint32_t *failed_tile)
{
    return render(gl.geom.count ? gl.geom.count : gl.last_triangles, target, stride, failed_tile);
}

uint32_t lviv_gl_triangles(void)
{
    return gl.last_triangles;
}

GLenum glGetError(void)
{
    const GLenum e = gl.error;
    gl.error = GL_NO_ERROR;
    return e;
}

static int *capability(GLenum cap)
{
    if (cap >= GL_LIGHT0 && cap < GL_LIGHT0 + LVIV_MAX_LIGHTS)
        return &gl.light_on[cap - GL_LIGHT0];
    switch (cap)
    {
    case GL_DEPTH_TEST:
        return &gl.depth_test;
    case GL_CULL_FACE:
        return &gl.cull_face;
    case GL_LIGHTING:
        return &gl.lighting;
    case GL_BLEND:
        return &gl.blend;
    case GL_TEXTURE_2D:
        return &gl.texture_2d;
    case GL_NORMALIZE: // normals are always normalized
        return &gl.normalize;
    }
    return NULL;
}

static void set_capability(GLenum cap, int on)
{
    int *flag = capability(cap);
    if (!flag)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    *flag = on;
    update_state();
}

void glEnable(GLenum cap)
{
    set_capability(cap, 1);
}

void glDisable(GLenum cap)
{
    set_capability(cap, 0);
}

GLboolean glIsEnabled(GLenum cap)
{
    int *flag = capability(cap);
    if (!flag)
    {
        set_error(GL_INVALID_ENUM);
        return GL_FALSE;
    }
    return *flag ? GL_TRUE : GL_FALSE;
}

void glViewport(GLint x, GLint y, GLsizei width, GLsizei height)
{
    if (width < 0 || height < 0)
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    gl.state.viewport_x = x;
    gl.state.viewport_y = y;
    gl.state.viewport_width = width;
    gl.state.viewport_height = height;
}

void glClearColor(GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha)
{
    gl.clear_color = argb(red, green, blue, alpha);
}

// Color and depth together: the GPU clears every tile. What was drawn since the frame started goes.
void glClear(GLbitfield mask)
{
    if (mask & ~(GLbitfield)(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    gl.frame_clear_color = gl.clear_color;
    begin_frame();
}

// lviv_gl_frame renders the frame
void glFlush(void)
{
}

void glFinish(void)
{
}

//
// Matrices
//

static lviv_mat4_t *current_matrix(void)
{
    return gl.matrix_mode == GL_PROJECTION ? &gl.projection[gl.projection_top] : &gl.modelview[gl.modelview_top];
}

static void matrix_changed(void)
{
    gl.state.modelview = gl.modelview[gl.modelview_top];
    gl.state.projection = gl.projection[gl.projection_top];
    gl.matrices_dirty = 1;
}

// The current matrix times m
static void multiply(const lviv_mat4_t *m)
{
    lviv_mat4_multiply(current_matrix(), m);
    matrix_changed();
}

void glMatrixMode(GLenum mode)
{
    if (mode != GL_MODELVIEW && mode != GL_PROJECTION)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.matrix_mode = mode;
}

void glLoadIdentity(void)
{
    lviv_mat4_identity(current_matrix());
    matrix_changed();
}

static lviv_mat4_t from_array(const GLfloat *m)
{
    lviv_mat4_t r;
    for (int c = 0; c < 4; c++)
        for (int row = 0; row < 4; row++)
            r.m[c][row] = m[c * 4 + row];
    return r;
}

void glLoadMatrixf(const GLfloat *m)
{
    *current_matrix() = from_array(m);
    matrix_changed();
}

void glMultMatrixf(const GLfloat *m)
{
    const lviv_mat4_t r = from_array(m);
    multiply(&r);
}

void glPushMatrix(void)
{
    if (gl.matrix_mode == GL_PROJECTION)
    {
        if (gl.projection_top + 1 == PROJECTION_DEPTH)
        {
            set_error(GL_STACK_OVERFLOW);
            return;
        }
        gl.projection[gl.projection_top + 1] = gl.projection[gl.projection_top];
        gl.projection_top++;
    }
    else
    {
        if (gl.modelview_top + 1 == MODELVIEW_DEPTH)
        {
            set_error(GL_STACK_OVERFLOW);
            return;
        }
        gl.modelview[gl.modelview_top + 1] = gl.modelview[gl.modelview_top];
        gl.modelview_top++;
    }
}

void glPopMatrix(void)
{
    int *top = gl.matrix_mode == GL_PROJECTION ? &gl.projection_top : &gl.modelview_top;
    if (*top == 0)
    {
        set_error(GL_STACK_UNDERFLOW);
        return;
    }
    (*top)--;
    matrix_changed();
}

void glTranslatef(GLfloat x, GLfloat y, GLfloat z)
{
    lviv_mat4_translate(current_matrix(), x, y, z);
    matrix_changed();
}

void glScalef(GLfloat x, GLfloat y, GLfloat z)
{
    lviv_mat4_scale(current_matrix(), x, y, z);
    matrix_changed();
}

// angle in degrees, about the axis (x, y, z)
void glRotatef(GLfloat angle, GLfloat x, GLfloat y, GLfloat z)
{
    if (x == 0.0f && y == 0.0f && z == 0.0f)
        return;
    lviv_mat4_rotate(current_matrix(), (float)(angle * PI / 180.0), x, y, z);
    matrix_changed();
}

void glFrustum(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble z_near, GLdouble z_far)
{
    if (z_near <= 0 || z_far <= 0 || left == right || bottom == top || z_near == z_far)
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    lviv_mat4_frustum(current_matrix(), left, right, bottom, top, z_near, z_far);
    matrix_changed();
}

void glOrtho(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble z_near, GLdouble z_far)
{
    if (left == right || bottom == top || z_near == z_far)
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    lviv_mat4_ortho(current_matrix(), left, right, bottom, top, z_near, z_far);
    matrix_changed();
}

void gluPerspective(GLdouble fovy, GLdouble aspect, GLdouble z_near, GLdouble z_far)
{
    lviv_mat4_perspective(current_matrix(), (float)(fovy * PI / 180.0), (float)aspect, (float)z_near, (float)z_far);
    matrix_changed();
}

void gluLookAt(GLdouble eye_x, GLdouble eye_y, GLdouble eye_z, GLdouble center_x, GLdouble center_y, GLdouble center_z,
               GLdouble up_x, GLdouble up_y, GLdouble up_z)
{
    lviv_mat4_look_at(current_matrix(), (lviv_vec3_t){(float)eye_x, (float)eye_y, (float)eye_z},
                      (lviv_vec3_t){(float)center_x, (float)center_y, (float)center_z},
                      (lviv_vec3_t){(float)up_x, (float)up_y, (float)up_z});
    matrix_changed();
}

//
// Primitives
//

static int triangle_mode(GLenum mode)
{
    return mode == GL_TRIANGLES || mode == GL_TRIANGLE_STRIP || mode == GL_TRIANGLE_FAN || mode == GL_QUADS ||
           mode == GL_QUAD_STRIP || mode == GL_POLYGON;
}

static void triangle(const lviv_vertex_t *a, const lviv_vertex_t *b, const lviv_vertex_t *c)
{
    if (gl.matrices_dirty)
    {
        lviv_geom_matrices(&gl.geom, &gl.state);
        gl.matrices_dirty = 0;
    }
    lviv_geom_triangle(&gl.geom, &gl.state, a, b, c);
    if (gl.geom.dropped != gl.dropped)
    {
        gl.dropped = gl.geom.dropped;
        set_error(GL_OUT_OF_MEMORY);
    }
}

static void start_primitive(GLenum mode)
{
    gl.prim = mode;
    gl.n = 0;
}

// Vertex n of the primitive into the triangles it completes
static void assemble(const lviv_vertex_t *v)
{
    const uint32_t n = gl.n++;
    gl.recent[n % 4] = *v;
    const lviv_vertex_t *r = gl.recent;
    switch (gl.prim)
    {
    case GL_TRIANGLES:
        if (n % 3 == 2)
        {
            // recent holds n - 2 .. n at their k % 4
            triangle(&r[(n - 2) % 4], &r[(n - 1) % 4], &r[n % 4]);
        }
        break;
    case GL_TRIANGLE_STRIP: // odd triangles reversed, to keep the winding
        if (n >= 2)
        {
            if (n % 2 == 0)
                triangle(&r[(n - 2) % 4], &r[(n - 1) % 4], &r[n % 4]);
            else
                triangle(&r[(n - 1) % 4], &r[(n - 2) % 4], &r[n % 4]);
        }
        break;
    case GL_TRIANGLE_FAN:
    case GL_POLYGON:
        if (n == 0)
            gl.first = *v;
        else if (n >= 2)
            triangle(&gl.first, &r[(n - 1) % 4], &r[n % 4]);
        break;
    case GL_QUADS:
        if (n % 4 == 3)
        {
            triangle(&r[0], &r[1], &r[2]);
            triangle(&r[0], &r[2], &r[3]);
        }
        break;
    case GL_QUAD_STRIP: // quad k: 2k, 2k + 1, 2k + 3, 2k + 2
        if (n >= 3 && n % 2 == 1)
        {
            triangle(&r[(n - 3) % 4], &r[(n - 2) % 4], &r[n % 4]);
            triangle(&r[(n - 3) % 4], &r[n % 4], &r[(n - 1) % 4]);
        }
        break;
    }
}

void glBegin(GLenum mode)
{
    if (gl.in_begin)
    {
        set_error(GL_INVALID_OPERATION);
        return;
    }
    if (!triangle_mode(mode))
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.in_begin = 1;
    start_primitive(mode);
}

void glEnd(void)
{
    if (!gl.in_begin)
    {
        set_error(GL_INVALID_OPERATION);
        return;
    }
    gl.in_begin = 0;
}

static void vertex(float x, float y, float z)
{
    if (!gl.in_begin)
        return; // GL leaves it undefined
    const lviv_vertex_t v = {{x, y, z}, gl.normal, gl.texcoord, gl.color};
    assemble(&v);
}

void glVertex2f(GLfloat x, GLfloat y)
{
    vertex(x, y, 0.0f);
}

void glVertex3f(GLfloat x, GLfloat y, GLfloat z)
{
    vertex(x, y, z);
}

void glVertex3fv(const GLfloat *v)
{
    vertex(v[0], v[1], v[2]);
}

void glNormal3f(GLfloat x, GLfloat y, GLfloat z)
{
    gl.normal = (lviv_vec3_t){x, y, z};
}

void glNormal3fv(const GLfloat *v)
{
    gl.normal = (lviv_vec3_t){v[0], v[1], v[2]};
}

void glColor3f(GLfloat red, GLfloat green, GLfloat blue)
{
    gl.color = argb(red, green, blue, 1.0f);
}

void glColor4f(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha)
{
    gl.color = argb(red, green, blue, alpha);
}

void glColor3ub(GLubyte red, GLubyte green, GLubyte blue)
{
    gl.color = 0xFF000000u | (uint32_t)red << 16 | (uint32_t)green << 8 | blue;
}

void glColor4ub(GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha)
{
    gl.color = (uint32_t)alpha << 24 | (uint32_t)red << 16 | (uint32_t)green << 8 | blue;
}

void glTexCoord2f(GLfloat s, GLfloat t)
{
    gl.texcoord = (lviv_vec2_t){s, t};
}

//
// Vertex arrays
//

static array_t *client_array(GLenum array)
{
    switch (array)
    {
    case GL_VERTEX_ARRAY:
        return &gl.vertex_array;
    case GL_NORMAL_ARRAY:
        return &gl.normal_array;
    case GL_COLOR_ARRAY:
        return &gl.color_array;
    case GL_TEXTURE_COORD_ARRAY:
        return &gl.texcoord_array;
    }
    return NULL;
}

void glEnableClientState(GLenum array)
{
    array_t *a = client_array(array);
    if (!a)
        set_error(GL_INVALID_ENUM);
    else
        a->enabled = 1;
}

void glDisableClientState(GLenum array)
{
    array_t *a = client_array(array);
    if (!a)
        set_error(GL_INVALID_ENUM);
    else
        a->enabled = 0;
}

static void set_pointer(array_t *a, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer)
{
    if (stride < 0)
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    a->size = size;
    a->type = type;
    a->stride = stride;
    a->pointer = pointer;
}

void glVertexPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer)
{
    if (type != GL_FLOAT)
        set_error(GL_INVALID_ENUM);
    else if (size != 2 && size != 3)
        set_error(GL_INVALID_VALUE);
    else
        set_pointer(&gl.vertex_array, size, type, stride, pointer);
}

void glNormalPointer(GLenum type, GLsizei stride, const GLvoid *pointer)
{
    if (type != GL_FLOAT)
        set_error(GL_INVALID_ENUM);
    else
        set_pointer(&gl.normal_array, 3, type, stride, pointer);
}

void glColorPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer)
{
    if (type != GL_FLOAT && type != GL_UNSIGNED_BYTE)
        set_error(GL_INVALID_ENUM);
    else if (size != 3 && size != 4)
        set_error(GL_INVALID_VALUE);
    else
        set_pointer(&gl.color_array, size, type, stride, pointer);
}

void glTexCoordPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer)
{
    if (type != GL_FLOAT)
        set_error(GL_INVALID_ENUM);
    else if (size != 2)
        set_error(GL_INVALID_VALUE);
    else
        set_pointer(&gl.texcoord_array, size, type, stride, pointer);
}

static const void *element(const array_t *a, GLint i)
{
    const GLsizei bytes = a->type == GL_UNSIGNED_BYTE ? 1 : 4;
    return a->pointer + (size_t)i * (size_t)(a->stride ? a->stride : a->size * bytes);
}

// Vertex i of the enabled arrays, the current attributes for the others
static lviv_vertex_t fetch(GLint i)
{
    lviv_vertex_t v = {{0, 0, 0}, gl.normal, gl.texcoord, gl.color};
    const float *p = element(&gl.vertex_array, i);
    v.position = (lviv_vec3_t){p[0], p[1], gl.vertex_array.size == 3 ? p[2] : 0.0f};
    if (gl.normal_array.enabled)
    {
        const float *n = element(&gl.normal_array, i);
        v.normal = (lviv_vec3_t){n[0], n[1], n[2]};
    }
    if (gl.texcoord_array.enabled)
    {
        const float *t = element(&gl.texcoord_array, i);
        v.texcoord = (lviv_vec2_t){t[0], t[1]};
    }
    if (gl.color_array.enabled)
    {
        const int four = gl.color_array.size == 4;
        if (gl.color_array.type == GL_UNSIGNED_BYTE)
        {
            const uint8_t *c = element(&gl.color_array, i);
            v.color = (uint32_t)(four ? c[3] : 255) << 24 | (uint32_t)c[0] << 16 | (uint32_t)c[1] << 8 | c[2];
        }
        else
        {
            const float *c = element(&gl.color_array, i);
            v.color = argb(c[0], c[1], c[2], four ? c[3] : 1.0f);
        }
    }
    return v;
}

static int can_draw(GLenum mode, GLsizei count)
{
    if (!triangle_mode(mode))
    {
        set_error(GL_INVALID_ENUM);
        return 0;
    }
    if (count < 0)
    {
        set_error(GL_INVALID_VALUE);
        return 0;
    }
    if (gl.in_begin)
    {
        set_error(GL_INVALID_OPERATION);
        return 0;
    }
    return gl.vertex_array.enabled && gl.vertex_array.pointer;
}

void glDrawArrays(GLenum mode, GLint first, GLsizei count)
{
    if (!can_draw(mode, count))
        return;
    start_primitive(mode);
    for (GLint i = first; i < first + count; i++)
    {
        const lviv_vertex_t v = fetch(i);
        assemble(&v);
    }
}

void glDrawElements(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices)
{
    if (type != GL_UNSIGNED_BYTE && type != GL_UNSIGNED_SHORT && type != GL_UNSIGNED_INT)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    if (!can_draw(mode, count))
        return;
    start_primitive(mode);
    for (GLsizei k = 0; k < count; k++)
    {
        const GLint i = type == GL_UNSIGNED_BYTE    ? ((const uint8_t *)indices)[k]
                        : type == GL_UNSIGNED_SHORT ? ((const uint16_t *)indices)[k]
                                                    : (GLint)((const uint32_t *)indices)[k];
        const lviv_vertex_t v = fetch(i);
        assemble(&v);
    }
}

//
// Lighting
//

static lviv_vec3_t rgb(const GLfloat *p)
{
    return (lviv_vec3_t){p[0], p[1], p[2]};
}

void glLightfv(GLenum light, GLenum pname, const GLfloat *params)
{
    if (light < GL_LIGHT0 || light >= GL_LIGHT0 + LVIV_MAX_LIGHTS)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    lviv_light_t *l = &gl.lights[light - GL_LIGHT0];
    switch (pname)
    {
    case GL_AMBIENT:
        l->ambient = rgb(params);
        break;
    case GL_DIFFUSE:
        l->diffuse = rgb(params);
        break;
    case GL_SPECULAR:
        l->specular = rgb(params);
        break;
    case GL_POSITION: // into eye space by the modelview of the moment, as GL does; w 1 unless 0
        l->position = lviv_mat4_transform(&gl.modelview[gl.modelview_top],
                                          (lviv_vec4_t){params[0], params[1], params[2], params[3]});
        if (l->position.w != 0.0f)
            l->position = (lviv_vec4_t){l->position.x / l->position.w, l->position.y / l->position.w,
                                        l->position.z / l->position.w, 1.0f};
        break;
    case GL_SPOT_DIRECTION: // by the modelview's upper 3 x 3 of the moment
    {
        const lviv_vec4_t d = lviv_mat4_transform(&gl.modelview[gl.modelview_top],
                                                  (lviv_vec4_t){params[0], params[1], params[2], 0.0f});
        const float length = sqrtf(d.x * d.x + d.y * d.y + d.z * d.z);
        l->spot_direction = length > 0.0f ? (lviv_vec3_t){d.x / length, d.y / length, d.z / length}
                                          : (lviv_vec3_t){d.x, d.y, d.z};
        break;
    }
    case GL_SPOT_EXPONENT:
        if (params[0] < 0.0f || params[0] > 128.0f)
        {
            set_error(GL_INVALID_VALUE);
            return;
        }
        l->spot_exponent = params[0];
        break;
    case GL_SPOT_CUTOFF:
        if ((params[0] < 0.0f || params[0] > 90.0f) && params[0] != 180.0f)
        {
            set_error(GL_INVALID_VALUE);
            return;
        }
        l->spot_cutoff = params[0];
        l->spot_cos_cutoff = cosf(params[0] * (float)(PI / 180.0));
        break;
    case GL_CONSTANT_ATTENUATION:
    case GL_LINEAR_ATTENUATION:
    case GL_QUADRATIC_ATTENUATION:
        if (params[0] < 0.0f)
        {
            set_error(GL_INVALID_VALUE);
            return;
        }
        if (pname == GL_CONSTANT_ATTENUATION)
            l->constant_attenuation = params[0];
        else if (pname == GL_LINEAR_ATTENUATION)
            l->linear_attenuation = params[0];
        else
            l->quadratic_attenuation = params[0];
        break;
    default:
        set_error(GL_INVALID_ENUM);
        return;
    }
    update_state();
}


void glLightf(GLenum light, GLenum pname, GLfloat param)
{
    if (pname != GL_SPOT_EXPONENT && pname != GL_SPOT_CUTOFF && pname != GL_CONSTANT_ATTENUATION &&
        pname != GL_LINEAR_ATTENUATION && pname != GL_QUADRATIC_ATTENUATION)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    glLightfv(light, pname, &param);
}

void glLightModelfv(GLenum pname, const GLfloat *params)
{
    if (pname != GL_LIGHT_MODEL_AMBIENT)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.state.global_ambient = rgb(params);
}

// One material, the front one (no two-sided lighting)
void glMaterialfv(GLenum face, GLenum pname, const GLfloat *params)
{
    if (face != GL_FRONT && face != GL_BACK && face != GL_FRONT_AND_BACK)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    if (face == GL_BACK)
        return;
    lviv_material_t *m = &gl.state.material;
    switch (pname)
    {
    case GL_AMBIENT:
        m->ambient = rgb(params);
        break;
    case GL_DIFFUSE:
        m->diffuse = rgb(params);
        break;
    case GL_AMBIENT_AND_DIFFUSE:
        m->ambient = m->diffuse = rgb(params);
        break;
    case GL_SPECULAR:
        m->specular = rgb(params);
        break;
    case GL_EMISSION:
        m->emissive = rgb(params);
        break;
    case GL_SHININESS:
        if (params[0] < 0 || params[0] > 128)
            set_error(GL_INVALID_VALUE);
        else
            m->shininess = params[0];
        break;
    default:
        set_error(GL_INVALID_ENUM);
    }
}

void glMaterialf(GLenum face, GLenum pname, GLfloat param)
{
    glMaterialfv(face, pname, &param);
}

//
// Faces, depth, blending, texture functions
//

void glCullFace(GLenum mode)
{
    if (mode != GL_FRONT && mode != GL_BACK && mode != GL_FRONT_AND_BACK)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.cull_mode = mode;
    update_state();
}

void glFrontFace(GLenum mode)
{
    if (mode != GL_CW && mode != GL_CCW)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.front_face = mode;
    update_state();
}

void glDepthFunc(GLenum func)
{
    if (func < GL_NEVER || func > GL_ALWAYS)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.depth_func = func;
    update_state();
}

void glBlendFunc(GLenum sfactor, GLenum dfactor)
{
    if (blend_op(sfactor) < 0 || blend_op(dfactor) < 0)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.sfactor = sfactor;
    gl.dfactor = dfactor;
    update_state();
}

void glTexEnvi(GLenum target, GLenum pname, GLint param)
{
    if (target != GL_TEXTURE_ENV || pname != GL_TEXTURE_ENV_MODE || texture_function((GLenum)param) < 0)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    gl.tex_env = (GLenum)param;
    update_state();
}

//
// Textures
//

void glGenTextures(GLsizei n, GLuint *textures)
{
    if (n < 0)
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    for (GLsizei i = 0; i < n; i++)
    {
        GLuint name = 0; // the first not in use (glDeleteTextures gives them back)
        for (GLuint t = 0; t < TEXTURES && !name; t++)
            if (!gl.textures[t].generated)
                name = t + 1;
        textures[i] = name;
        if (!name)
        {
            set_error(GL_OUT_OF_MEMORY);
            continue;
        }
        gl.textures[name - 1].generated = 1;
        gl.textures[name - 1].tile_s = gl.textures[name - 1].tile_t = 1; // GL_REPEAT
    }
}

// The names back for glGenTextures, and the pool from the end of the last texture still in it on:
// the pool fills in order, so a texture's memory comes back once those placed after it are deleted
// too (all of a scene's, deleted together)
void glDeleteTextures(GLsizei n, const GLuint *textures)
{
    if (n < 0)
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    for (GLsizei i = 0; i < n; i++)
    {
        const GLuint name = textures[i];
        if (name == 0 || name > TEXTURES) // as GL, nothing for 0 or a name not in use
            continue;
        if (gl.bound == name)
            gl.bound = 0;
        memset(&gl.textures[name - 1], 0, sizeof gl.textures[name - 1]);
    }
    gl.pool_next = (uint8_t *)texture_pool;
    for (int t = 0; t < TEXTURES; t++)
    {
        const texture_t *texture = &gl.textures[t];
        uint8_t *end = (uint8_t *)texture->texels + (4u << (2 * texture->log2_size));
        if (texture->loaded && end > gl.pool_next)
            gl.pool_next = end;
    }
    update_state();
}

void glBindTexture(GLenum target, GLuint texture)
{
    if (target != GL_TEXTURE_2D)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    if (texture > TEXTURES || (texture && !gl.textures[texture - 1].generated))
    {
        set_error(GL_INVALID_VALUE);
        return;
    }
    gl.bound = texture;
    update_state();
}

void glTexParameteri(GLenum target, GLenum pname, GLint param)
{
    if (target != GL_TEXTURE_2D)
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    if (!gl.bound)
        return;
    texture_t *t = &gl.textures[gl.bound - 1];
    switch (pname)
    {
    case GL_TEXTURE_WRAP_S:
    case GL_TEXTURE_WRAP_T:
        if (param != GL_REPEAT && param != GL_CLAMP && param != GL_CLAMP_TO_EDGE)
        {
            set_error(GL_INVALID_ENUM);
            return;
        }
        *(pname == GL_TEXTURE_WRAP_S ? &t->tile_s : &t->tile_t) = param == GL_REPEAT;
        break;
    case GL_TEXTURE_MIN_FILTER: // the GPU's own
    case GL_TEXTURE_MAG_FILTER:
        return;
    default:
        set_error(GL_INVALID_ENUM);
        return;
    }
    update_state();
}

// The bound texture, with memory for width x height texels (square, a power of two the GPU takes) in
// the pool, at a multiple of its own size (gpu_set_texture); NULL, with GL's error, if it cannot be
static texture_t *texture_memory(GLsizei width, GLsizei height, GLint border, const GLvoid *pixels, uint32_t *log2_size)
{
    *log2_size = 0;
    while ((1 << *log2_size) < width)
        (*log2_size)++;
    if (width != height || width != (1 << *log2_size) || *log2_size > TEXTURE_MAX_LOG2 || border != 0 || !pixels)
    {
        set_error(GL_INVALID_VALUE);
        return NULL;
    }
    if (!gl.bound)
    {
        set_error(GL_INVALID_OPERATION);
        return NULL;
    }
    texture_t *t = &gl.textures[gl.bound - 1];
    const uintptr_t bytes = 4u << (2 * *log2_size);
    if (!t->loaded || t->log2_size != *log2_size)
    {
        const uintptr_t at = ((uintptr_t)gl.pool_next + bytes - 1) & ~(bytes - 1);
        if (at + bytes > (uintptr_t)texture_pool + sizeof texture_pool)
        {
            set_error(GL_OUT_OF_MEMORY);
            return NULL;
        }
        t->texels = (uint32_t *)at;
        gl.pool_next = (uint8_t *)(at + bytes);
    }
    return t;
}

// The texture's texels, written, to the GPU
static void texture_written(texture_t *t, uint32_t log2_size)
{
    if (gpu_set_texture(gl.gpu, gl.bound - 1, t->texels, log2_size) != 0)
    {
        set_error(GL_OUT_OF_MEMORY);
        t->loaded = 0;
        return;
    }
    t->loaded = 1;
    t->log2_size = log2_size;
    update_state();
}

// Level 0 only (the GPU has no mipmaps: other levels are taken and dropped), square, a power of two
void glTexImage2D(GLenum target, GLint level, GLint internal_format, GLsizei width, GLsizei height, GLint border,
                  GLenum format, GLenum type, const GLvoid *pixels)
{
    (void)internal_format;
    if (target != GL_TEXTURE_2D || type != GL_UNSIGNED_BYTE ||
        (format != GL_RGBA && format != GL_RGB && format != GL_BGRA))
    {
        set_error(GL_INVALID_ENUM);
        return;
    }
    if (level != 0)
        return;
    uint32_t log2_size;
    texture_t *t = texture_memory(width, height, border, pixels, &log2_size);
    if (!t)
        return;
    const uint8_t *src = pixels;
    const int channels = format == GL_RGB ? 3 : 4;
    for (GLsizei y = 0; y < height; y++)
    {
        for (GLsizei x = 0; x < width; x++, src += channels)
        {
            const uint32_t a = channels == 4 ? src[3] : 255;
            const uint32_t r = format == GL_BGRA ? src[2] : src[0], b = format == GL_BGRA ? src[0] : src[2];
            t->texels[gpu_texel_index((uint32_t)x, (uint32_t)y)] = a << 24 | r << 16 | (uint32_t)src[1] << 8 | b;
        }
    }
    texture_written(t, log2_size);
}

void lviv_gl_tex_image(GLsizei size, const uint32_t *texels)
{
    uint32_t log2_size;
    texture_t *t = texture_memory(size, size, 0, texels, &log2_size);
    if (!t)
        return;
    memcpy(t->texels, texels, (size_t)4 << (2 * log2_size));
    texture_written(t, log2_size);
}
