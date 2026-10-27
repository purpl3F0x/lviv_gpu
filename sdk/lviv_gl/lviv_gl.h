// lviv_gl: a subset of OpenGL 1.x for the GPU of gpu_top, in three layers: this API (gl_api.c), the
// transform and data building (lviv_geom.cpp, C++ on GLM behind the C interface of lviv_geom.h:
// vertices to the GPU's triangle records and tile masks) and the GPU driver (sdk/src/gpu.c). The API
// is C, for C and C++ applications.
//
// The names, types and enum values are OpenGL's, so OpenGL 1.x code ports as it is, within these
// limits:
//   - triangles only: GL_TRIANGLES, _STRIP, _FAN, GL_QUADS, GL_QUAD_STRIP, GL_POLYGON (no points,
//     lines or polygon modes)
//   - eight lights (GL_LIGHT0 to GL_LIGHT7), fixed-function lighting per vertex: their colors and
//     positions, no attenuation or spotlights; no GL_COLOR_MATERIAL
//   - textures square, a power of two up to 2048, GL_RGBA, GL_RGB or GL_BGRA of GL_UNSIGNED_BYTE;
//     the filters are the GPU's (glTexParameter takes the wrap modes only); 128 of them, one after
//     another in 4 MiB (LVIV_GL_TEXTURE_BYTES), which glDeleteTextures gives back from the end
//   - no depth mask, stencil, scissor, alpha test or fog; one frame size, at most 64 tiles of 128
//     x 128 pixels (1280 x 720: 60)
// A frame is everything drawn since the last glClear (which clears color and depth together, as
// the GPU clears every tile) and is rendered by lviv_gl_frame, the platform's swap: the
// application keeps the display (double buffering, the DisplayPort output). Its triangles go to
// the frame memory the platform gives (lviv_gl_init); past what it holds, GL_OUT_OF_MEMORY, and
// the rest are dropped. Unsupported names set GL_INVALID_ENUM, as GL does, for glGetError.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "gpu.h"

#ifdef __cplusplus
extern "C"
{
#endif

typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef float GLclampf;
typedef double GLdouble;
typedef double GLclampd;
typedef void GLvoid;

#define GL_FALSE 0
#define GL_TRUE 1

// Errors
#define GL_NO_ERROR 0
#define GL_INVALID_ENUM 0x0500
#define GL_INVALID_VALUE 0x0501
#define GL_INVALID_OPERATION 0x0502
#define GL_STACK_OVERFLOW 0x0503
#define GL_STACK_UNDERFLOW 0x0504
#define GL_OUT_OF_MEMORY 0x0505

// Primitives
#define GL_POINTS 0x0000
#define GL_LINES 0x0001
#define GL_LINE_LOOP 0x0002
#define GL_LINE_STRIP 0x0003
#define GL_TRIANGLES 0x0004
#define GL_TRIANGLE_STRIP 0x0005
#define GL_TRIANGLE_FAN 0x0006
#define GL_QUADS 0x0007
#define GL_QUAD_STRIP 0x0008
#define GL_POLYGON 0x0009

// Matrices
#define GL_MODELVIEW 0x1700
#define GL_PROJECTION 0x1701

// Capabilities
#define GL_CULL_FACE 0x0B44
#define GL_LIGHTING 0x0B50
#define GL_DEPTH_TEST 0x0B71
#define GL_NORMALIZE 0x0BA1
#define GL_BLEND 0x0BE2
#define GL_TEXTURE_2D 0x0DE1
#define GL_LIGHT0 0x4000
#define GL_LIGHT1 0x4001
#define GL_LIGHT2 0x4002
#define GL_LIGHT3 0x4003
#define GL_LIGHT4 0x4004
#define GL_LIGHT5 0x4005
#define GL_LIGHT6 0x4006
#define GL_LIGHT7 0x4007

// Faces
#define GL_FRONT 0x0404
#define GL_BACK 0x0405
#define GL_FRONT_AND_BACK 0x0408
#define GL_CW 0x0900
#define GL_CCW 0x0901

// Depth functions
#define GL_NEVER 0x0200
#define GL_LESS 0x0201
#define GL_EQUAL 0x0202
#define GL_LEQUAL 0x0203
#define GL_GREATER 0x0204
#define GL_NOTEQUAL 0x0205
#define GL_GEQUAL 0x0206
#define GL_ALWAYS 0x0207

// Blend factors
#define GL_ZERO 0
#define GL_ONE 1
#define GL_SRC_COLOR 0x0300
#define GL_ONE_MINUS_SRC_COLOR 0x0301
#define GL_SRC_ALPHA 0x0302
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_DST_ALPHA 0x0304
#define GL_ONE_MINUS_DST_ALPHA 0x0305
#define GL_DST_COLOR 0x0306
#define GL_ONE_MINUS_DST_COLOR 0x0307

// Lighting
#define GL_AMBIENT 0x1200
#define GL_DIFFUSE 0x1201
#define GL_SPECULAR 0x1202
#define GL_POSITION 0x1203
#define GL_EMISSION 0x1600
#define GL_SHININESS 0x1601
#define GL_AMBIENT_AND_DIFFUSE 0x1602
#define GL_LIGHT_MODEL_AMBIENT 0x0B53

// Clearing
#define GL_DEPTH_BUFFER_BIT 0x00000100
#define GL_COLOR_BUFFER_BIT 0x00004000

// Vertex arrays and data types
#define GL_VERTEX_ARRAY 0x8074
#define GL_NORMAL_ARRAY 0x8075
#define GL_COLOR_ARRAY 0x8076
#define GL_TEXTURE_COORD_ARRAY 0x8078
#define GL_BYTE 0x1400
#define GL_UNSIGNED_BYTE 0x1401
#define GL_SHORT 0x1402
#define GL_UNSIGNED_SHORT 0x1403
#define GL_INT 0x1404
#define GL_UNSIGNED_INT 0x1405
#define GL_FLOAT 0x1406

// Textures
#define GL_TEXTURE_ENV 0x2300
#define GL_TEXTURE_ENV_MODE 0x2200
#define GL_ADD 0x0104
#define GL_REPLACE 0x1E01
#define GL_MODULATE 0x2100
#define GL_DECAL 0x2101
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_NEAREST 0x2600
#define GL_LINEAR 0x2601
#define GL_CLAMP 0x2900
#define GL_REPEAT 0x2901
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_RGB 0x1907
#define GL_RGBA 0x1908
#define GL_BGRA 0x80E1

// The frame memory a triangle takes: its record (gpu_triangle_t) and its tile mask
#define LVIV_GL_TRIANGLE_BYTES (GPU_TRIANGLE_BYTES + 8)

// The platform: a context for gpu, frames of width x height pixels, their triangles in frame_memory:
// frame_bytes 64-byte aligned, in memory the GPU's masters reach (PS DDR below 4 GiB, for one),
// frame_bytes / LVIV_GL_TRIANGLE_BYTES triangles a frame. Returns 0, or -1 if the frame has more
// than 64 tiles or frame_memory is not 64-byte aligned or holds no triangle.
int lviv_gl_init(gpu_t *gpu, int width, int height, void *frame_memory, size_t frame_bytes);
// Renders everything drawn since the last glClear into target (stride bytes per row, rows to the
// end of the last row of tiles, in memory the CPU does not cache: gpu_frame_t), and starts the next
// frame. If it fails, the tile it stopped at goes to failed_tile (unless NULL).
gpu_status_t lviv_gl_frame(uint32_t *target, uint32_t stride, uint32_t *failed_tile);
// The triangles the last frame sent to the GPU (after clipping, culling and binning).
uint32_t lviv_gl_triangles(void);
// glTexImage2D for the bound texture with the GPU's own texels, copied as they are: size x size
// words a << 24 | r << 16 | g << 8 | b, in Morton order (gpu_texel_index), row 0 at t = 0; size a
// power of two up to 2048. The errors are glTexImage2D's.
void lviv_gl_tex_image(GLsizei size, const uint32_t *texels);

GLenum glGetError(void);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
GLboolean glIsEnabled(GLenum cap);

void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glClearColor(GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha);
void glClear(GLbitfield mask);
void glFlush(void);
void glFinish(void);

void glMatrixMode(GLenum mode);
void glLoadIdentity(void);
void glLoadMatrixf(const GLfloat *m);
void glMultMatrixf(const GLfloat *m);
void glPushMatrix(void);
void glPopMatrix(void);
void glTranslatef(GLfloat x, GLfloat y, GLfloat z);
void glRotatef(GLfloat angle, GLfloat x, GLfloat y, GLfloat z);
void glScalef(GLfloat x, GLfloat y, GLfloat z);
void glFrustum(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble z_near, GLdouble z_far);
void glOrtho(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble z_near, GLdouble z_far);
void gluPerspective(GLdouble fovy, GLdouble aspect, GLdouble z_near, GLdouble z_far);
void gluLookAt(GLdouble eye_x, GLdouble eye_y, GLdouble eye_z, GLdouble center_x, GLdouble center_y, GLdouble center_z,
               GLdouble up_x, GLdouble up_y, GLdouble up_z);

void glBegin(GLenum mode);
void glEnd(void);
void glVertex2f(GLfloat x, GLfloat y);
void glVertex3f(GLfloat x, GLfloat y, GLfloat z);
void glVertex3fv(const GLfloat *v);
void glNormal3f(GLfloat x, GLfloat y, GLfloat z);
void glNormal3fv(const GLfloat *v);
void glColor3f(GLfloat red, GLfloat green, GLfloat blue);
void glColor4f(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
void glColor3ub(GLubyte red, GLubyte green, GLubyte blue);
void glColor4ub(GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha);
void glTexCoord2f(GLfloat s, GLfloat t);

void glEnableClientState(GLenum array);
void glDisableClientState(GLenum array);
void glVertexPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer);
void glNormalPointer(GLenum type, GLsizei stride, const GLvoid *pointer);
void glColorPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer);
void glTexCoordPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices);

void glLightfv(GLenum light, GLenum pname, const GLfloat *params);
void glLightModelfv(GLenum pname, const GLfloat *params);
void glMaterialfv(GLenum face, GLenum pname, const GLfloat *params);
void glMaterialf(GLenum face, GLenum pname, GLfloat param);

void glCullFace(GLenum mode);
void glFrontFace(GLenum mode);
void glDepthFunc(GLenum func);
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glTexEnvi(GLenum target, GLenum pname, GLint param);

void glGenTextures(GLsizei n, GLuint *textures);
void glDeleteTextures(GLsizei n, const GLuint *textures);
void glBindTexture(GLenum target, GLuint texture);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
void glTexImage2D(GLenum target, GLint level, GLint internal_format, GLsizei width, GLsizei height, GLint border,
                  GLenum format, GLenum type, const GLvoid *pixels);

#ifdef __cplusplus
}
#endif
