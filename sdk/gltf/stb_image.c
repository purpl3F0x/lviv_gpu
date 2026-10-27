// stb_image (sdk/third_party/stb) for gltf_scene's textures: PNG and JPEG, from memory. On the A53
// with its NEON code, which it takes only when told (STBI_NEON); its last error in a plain static,
// not a thread-local one (the standalone BSP sets up no thread pointer).
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_THREAD_LOCALS
#ifdef __aarch64__
#define STBI_NEON
#endif
#include "stb_image.h"
