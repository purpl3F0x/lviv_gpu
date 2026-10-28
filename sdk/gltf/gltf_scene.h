// glTF 2.0 scenes drawn with lviv_gl (sdk/lviv_gl), read with fastgltf (sdk/third_party/fastgltf,
// on sdk/third_party/simdjson): the triangle meshes of a .glb, or of a .gltf with its buffers
// embedded (data: URIs); their metallic-roughness materials as GL's fixed-function ones, with their
// base color textures (the GPU's own texels where scripts/gltf_swizzle.py added them to the file,
// copied as they are; else the PNG or JPEG in the file, decoded by sdk/third_party/stb's stb_image
// and swizzled; with KHR_texture_transform: GL_MODULATE, the lit color times the texture); the
// scene's first camera;
// its KHR_lights_punctual lights, up to GL's eight, as GL's: point and spot lights falling off with
// the square of the distance as glTF has them (not a light's range), or by the GL attenuation the
// file's extras give (gl_attenuation_constant_linear_quadratic), spot lights' cones as GL's
// spotlights; GL's global ambient, or the file's (its scene's extras: gl_light_model_ambient). No
// other textures, nor images in files of their own, skins or morph targets. C++ behind a C
// interface. On the standalone BSP, the two libraries as sdk/third_party/fastgltf.patch and
// simdjson.patch have them, without a file system: files come from the SD card (sd.h), whole, and
// are parsed in memory.
#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

// The readable bytes a file's data needs after its end: simdjson's SIMDJSON_PADDING
#define GLTF_SCENE_PADDING 64

typedef struct gltf_scene gltf_scene_t;

// The scene of the file at data, size bytes (and GLTF_SCENE_PADDING more, which it reads but does
// not use), its default scene or else its first; NULL, with a message in error (error_size bytes),
// if there is none to draw. The data is copied: it can go once this returns.
gltf_scene_t *gltf_scene_load(const void *data, size_t size, char *error, size_t error_size);
// Also deletes its textures from lviv_gl (glDeleteTextures)
void gltf_scene_free(gltf_scene_t *scene);

// Its triangles, its textures, its lights (those it has, or the one it gets without), and whether
// its camera is its own (else one looks at it as dv/raster_sw does: from 1.5 spans along +z)
int gltf_scene_triangles(const gltf_scene_t *scene);
int gltf_scene_textures(const gltf_scene_t *scene);
int gltf_scene_lights(const gltf_scene_t *scene);
int gltf_scene_has_camera(const gltf_scene_t *scene);

// GL's state for it, before drawing it: the camera's projection for a width x height viewport,
// the lights, lighting, the depth test (less), vertex and normal arrays; and, the first time, its
// textures in lviv_gl's memory, the largest halved until they all fit (none, if not at 1 x 1)
void gltf_scene_setup(gltf_scene_t *scene, int width, int height);

// A frame of it: glClear, the camera's view, the lights' positions, then each primitive with its
// material (back faces culled but where double sided), the model turned by angle degrees about the
// vertical axis through its bounding box's center
void gltf_scene_draw(const gltf_scene_t *scene, float angle);

#ifdef __cplusplus
}
#endif
