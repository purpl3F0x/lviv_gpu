// gltf_scene.h's scenes, on fastgltf: the file parsed in memory and its scene's nodes walked once
// (fastgltf::iterateSceneNodes) into what lviv_gl draws, none of fastgltf's asset kept. Textures as
// the GPU's own texels: copied from the file where scripts/gltf_swizzle.py put them there, else the
// image decoded by stb_image (stb_image.c) and swizzled here.

// <cmath>'s M_PI, not ISO C++: MinGW's math.h (the host test's) hides it in -std=c++17 without
// this, before its first include
#define _USE_MATH_DEFINES

#include "gltf_scene.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <new>
#include <numeric>
#include <string_view>
#include <type_traits>
#include <vector>

#include <fastgltf/core.hpp>
#include <fastgltf/math.hpp>
#include <fastgltf/tools.hpp>

#include "lviv_gl.h"
#include "simdjson.h"
#include "stb_image.h"

namespace fm = fastgltf::math;

// fastgltf's vectors and matrices are GL's arrays (packed floats, the matrices column-major): GL
// takes them as they are, with data()
static_assert(sizeof(fm::fvec2) == 2 * sizeof(float) && sizeof(fm::fvec3) == 3 * sizeof(float) &&
              sizeof(fm::fvec4) == 4 * sizeof(float) && sizeof(fm::fmat4x4) == 16 * sizeof(float));

static const std::size_t max_lights = GL_LIGHT7 - GL_LIGHT0 + 1; // GL's GL_MAX_LIGHTS

// A texture's texels across, at most: the GPU's largest (16 MiB, half of lviv_gl's 32)
static const int max_texture = 2048;

struct gltf_scene
{
    struct texture
    {
        // size x size, the GPU's (lviv_gl_tex_image: ARGB words in Morton order), until set up
        std::vector<std::uint32_t> texels;
        int size;
        GLint wrap_s, wrap_t;
        GLuint name; // lviv_gl's, once set up (0 before, and if it did not fit)
    };

    struct primitive
    {
        fm::fmat4x4 world;                         // its node's
        std::vector<fm::fvec3> positions, normals; // without normals, all (0, 0, 1)
        std::vector<fm::fvec2> texcoords;          // with a texture: its coordinates, transformed
        std::vector<uint32_t> indices;
        GLenum mode; // GL_TRIANGLES, GL_TRIANGLE_STRIP or GL_TRIANGLE_FAN
        fm::fvec4 ambient, diffuse, specular, emission;
        float shininess;
        bool double_sided;
        int texture = -1; // its base color's, in textures; -1: none
    };

    struct light
    {
        fm::fvec4 position; // in world space, or in eye space if eye; w 0: the direction to it
        fm::fvec4 ambient, color;
        fm::fvec4 spot_direction = fm::fvec4(0, 0, -1, 0); // where a spot light shines, as position
        float attenuation[3] = {1, 0, 0};                  // GL's: constant, linear, quadratic
        float spot_exponent = 0, spot_cutoff = 180;        // GL's: the cutoff in degrees, 180 none
        bool eye;
    };

    std::vector<primitive> primitives;
    std::vector<texture> textures;
    std::vector<light> lights;
    fm::fvec4 ambient = fm::fvec4(0.2f, 0.2f, 0.2f, 1.0f); // GL_LIGHT_MODEL_AMBIENT: GL's, or the file's
    int triangles = 0;
    bool own_camera = false, orthographic = false;
    fm::fmat4x4 view; // world to eye
    // Perspective: yfov (radians), aspect (0: the viewport's); orthographic: xmag, ymag
    float yfov = 0, aspect = 0, xmag = 0, ymag = 0, znear = 0, zfar = 0;
    float center[3] = {0, 0, 0}; // of the bounding box, in world space
};

namespace
{

// The file in memory, GLTF_SCENE_PADDING readable bytes after it: read in place
class memory_getter : public fastgltf::GltfDataGetter
{
  public:
    memory_getter(const std::byte *data, std::size_t size) : data(data), size(size)
    {
    }

    void read(void *ptr, std::size_t count) override
    {
        std::memcpy(ptr, data + offset, count);
        offset += count;
    }

    fastgltf::span<std::byte> read(std::size_t count, std::size_t padding) override
    {
        (void)padding; // the file's GLTF_SCENE_PADDING
        fastgltf::span<std::byte> chunk(const_cast<std::byte *>(data) + offset, count);
        offset += count;
        return chunk;
    }

    void reset() override
    {
        offset = 0;
    }

    std::size_t bytesRead() override
    {
        return offset;
    }

    std::size_t totalSize() override
    {
        return size;
    }

  private:
    const std::byte *data;
    std::size_t size, offset = 0;
};

// The accessor's elements as T: copied as they are when they are T's already (copyFromAccessor:
// one memcpy, or one an element when they are interleaved), converted when not (normalized
// integers, KHR_mesh_quantization's, smaller indices); none when they are not T's type, a VEC3 or a
// SCALAR (copyFromAccessor only asserts it)
template <typename T> std::vector<T> elements(const fastgltf::Asset &asset, const fastgltf::Accessor &accessor)
{
    static_assert(std::is_trivially_copyable_v<T>); // or copyFromAccessor never memcpys
    std::vector<T> out;
    if (accessor.type == fastgltf::ElementTraits<T>::type)
    {
        out.resize(accessor.count);
        fastgltf::copyFromAccessor<T>(asset, accessor, out.data());
    }
    return out;
}

// GL's fixed-function material for a glTF one (glTF's default, white, metallic and rough, if none):
// the base color diffuse and ambient, the emission; highlights as bright as 1 - roughness, tinted by
// the base color as far as it is metallic, as tight as Blinn-Phong's exponent for alpha =
// roughness^2 (2 / alpha^2 - 2, at most GL's 128)
void set_material(gltf_scene::primitive &p, const fastgltf::Material &m)
{
    const auto &base = m.pbrData.baseColorFactor;
    const float roughness = std::clamp((float)m.pbrData.roughnessFactor, 0.0f, 1.0f);
    const float metallic = std::clamp((float)m.pbrData.metallicFactor, 0.0f, 1.0f);
    const float alpha = std::max(roughness * roughness, 1e-3f);
    for (int k = 0; k < 3; k++)
    {
        p.ambient[k] = p.diffuse[k] = base[k];
        p.specular[k] = (1.0f - roughness) * (1.0f + (base[k] - 1.0f) * metallic);
        p.emission[k] = m.emissiveFactor[k] * m.emissiveStrength;
    }
    p.ambient[3] = p.diffuse[3] = p.specular[3] = p.emission[3] = 1.0f;
    p.shininess = std::min(2.0f / (alpha * alpha) - 2.0f, 128.0f);
    p.double_sided = m.doubleSided;
}

bool gl_mode(fastgltf::PrimitiveType type, GLenum &mode)
{
    switch (type)
    {
    case fastgltf::PrimitiveType::Triangles:
        mode = GL_TRIANGLES;
        return true;
    case fastgltf::PrimitiveType::TriangleStrip:
        mode = GL_TRIANGLE_STRIP;
        return true;
    case fastgltf::PrimitiveType::TriangleFan:
        mode = GL_TRIANGLE_FAN;
        return true;
    default:
        return false; // points and lines: not drawn
    }
}

// m texels of RGBA (out, out_step bytes apart) from n (in, in_step apart): each the mean of in over
// its share of them, a box filter (one smaller than in's texels takes the one or two it covers)
void box(const std::uint8_t *in, std::size_t in_step, int n, std::uint8_t *out, std::size_t out_step, int m)
{
    const double share = (double)n / m;
    for (int i = 0; i < m; i++)
    {
        const double a = i * share, b = a + share;
        double sum[4] = {0, 0, 0, 0};
        for (int j = (int)a; j < n && j < b; j++)
        {
            const double weight = std::min(b, j + 1.0) - std::max(a, (double)j);
            for (int c = 0; c < 4; c++)
                sum[c] += weight * in[j * in_step + c];
        }
        for (int c = 0; c < 4; c++)
            out[i * out_step + c] = (std::uint8_t)(sum[c] / share + 0.5);
    }
}

// The w x h RGBA image as size x size texels: rows, then columns, through box
std::vector<std::uint8_t> resample(const std::uint8_t *image, int w, int h, int size)
{
    const std::size_t row = 4 * (std::size_t)size;
    std::vector<std::uint8_t> across(row * h), out(row * size);
    for (int y = 0; y < h; y++)
        box(image + 4 * (std::size_t)w * y, 4, w, &across[row * y], 4, size);
    for (int x = 0; x < size; x++)
        box(&across[4 * (std::size_t)x], row, h, &out[4 * (std::size_t)x], row, size);
    return out;
}

// size x size RGBA texels, the top row first, as the GPU's: ARGB words in Morton order
std::vector<std::uint32_t> swizzle(const std::vector<std::uint8_t> &rgba, int size)
{
    std::vector<std::uint32_t> texels((std::size_t)size * size);
    for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            const std::uint8_t *c = &rgba[4 * ((std::size_t)size * y + x)];
            texels[gpu_texel_index((std::uint32_t)x, (std::uint32_t)y)] =
                (std::uint32_t)c[3] << 24 | (std::uint32_t)c[0] << 16 | (std::uint32_t)c[1] << 8 | c[2];
        }
    return texels;
}

// Swizzled texels at half the size: in Morton order every four are a 2 x 2 block, its mean the one
std::vector<std::uint32_t> halve(const std::vector<std::uint32_t> &texels)
{
    std::vector<std::uint32_t> out(texels.size() / 4);
    for (std::size_t i = 0; i < out.size(); i++)
        for (int shift = 0; shift < 32; shift += 8)
        {
            std::uint32_t sum = 2; // rounded
            for (int k = 0; k < 4; k++)
                sum += texels[4 * i + k] >> shift & 0xFF;
            out[i] |= sum / 4 << shift;
        }
    return out;
}

// The GPU's texels for an image, in a buffer view, as scripts/gltf_swizzle.py gives them (its
// extras: {"lviv_texels": {"bufferView": view, "size": size}}); size 0: none
struct swizzled
{
    std::uint64_t view = 0, size = 0;
};

// Loading a file, besides the scene: its textures' in the scene's (-1 not made yet, -2 not to be),
// and its images' swizzled texels, by their index
struct loading
{
    std::vector<int> textures;
    std::vector<swizzled> texels;
};

// fastgltf's extras callback (user: the loading): an image's swizzled texels
void read_extras(simdjson::dom::object *extras, std::size_t index, fastgltf::Category category, void *user)
{
    simdjson::dom::object texels;
    swizzled s;
    if (category != fastgltf::Category::Images || (*extras)["lviv_texels"].get_object().get(texels) ||
        texels["bufferView"].get_uint64().get(s.view) || texels["size"].get_uint64().get(s.size))
        return;
    std::vector<swizzled> &images = static_cast<loading *>(user)->texels;
    if (images.size() <= index)
        images.resize(index + 1);
    images[index] = s;
}


struct gl_attenuation
{
    bool given = false;
    float k[3];
};

struct gl_extras
{
    bool has_ambient = false;
    fm::fvec4 ambient;
    std::vector<gl_attenuation> lights; // by the light's index
};

// The numbers of a JSON array of min to max of them, into out: how many; 0 if it is not one
std::size_t read_numbers(simdjson::simdjson_result<simdjson::dom::element> value, float *out, std::size_t min,
                         std::size_t max)
{
    simdjson::dom::array array;
    if (value.get_array().get(array) || array.size() < min || array.size() > max)
        return 0;
    std::size_t n = 0;
    for (simdjson::dom::element e : array)
    {
        double number;
        if (e.get_double().get(number))
            return 0;
        out[n++] = (float)number;
    }
    return n;
}

gl_extras read_gl_extras(const void *data, std::size_t size)
{
    gl_extras out;
    const char *json = static_cast<const char *>(data);
    std::size_t length = size;
    std::uint32_t glb[5]; // magic, version, length; the first chunk's length and type
    if (size >= sizeof glb && std::memcmp(data, "glTF", 4) == 0)
    {
        std::memcpy(glb, data, sizeof glb);
        if (glb[4] != 0x4E4F534Au || glb[3] > size - sizeof glb) // "JSON"
            return out;
        json += sizeof glb;
        length = glb[3];
    }
    simdjson::dom::parser parser;
    simdjson::dom::element root;
    if (std::string_view(json, length).find("\"gl_") == std::string_view::npos ||
        parser.parse(json, length, false).get(root))
        return out;

    std::uint64_t scene = 0, index;
    if (!root["scene"].get_uint64().get(index))
        scene = index; // as fastgltf's defaultScene, else 0
    float ambient[4] = {0, 0, 0, 1};
    if (read_numbers(root["scenes"].at(scene)["extras"]["gl_light_model_ambient"], ambient, 3, 4))
    {
        out.has_ambient = true;
        out.ambient = fm::fvec4(ambient[0], ambient[1], ambient[2], ambient[3]);
    }
    simdjson::dom::array lights;
    if (!root["extensions"]["KHR_lights_punctual"]["lights"].get_array().get(lights))
        for (simdjson::dom::element light : lights)
        {
            gl_attenuation a;
            a.given = read_numbers(light["extras"]["gl_attenuation_constant_linear_quadratic"], a.k, 3, 3) &&
                      a.k[0] >= 0.0f && a.k[1] >= 0.0f && a.k[2] >= 0.0f;
            out.lights.push_back(a);
        }
    return out;
}

GLint gl_wrap(fastgltf::Wrap wrap)
{
    return wrap == fastgltf::Wrap::ClampToEdge ? GL_CLAMP_TO_EDGE : GL_REPEAT; // mirrored: repeated
}

// The glTF texture as lviv_gl takes one, with its sampler's wrap modes: its image's swizzled texels,
// copied, or else the image (PNG or JPEG, in a buffer view or a data URI) decoded, square, a power of
// two across (its longer side, at most max_texture), and swizzled; false without either
bool make_texture(const fastgltf::Asset &asset, const fastgltf::Texture &texture, const loading &l,
                  gltf_scene::texture &out)
{
    if (!texture.imageIndex)
        return false; // in an extension's format only (KTX2, WebP, DDS)
    const std::size_t index = *texture.imageIndex;
    const swizzled s = index < l.texels.size() ? l.texels[index] : swizzled();
    const std::uint64_t bytes = 4 * s.size * s.size;
    if (s.size != 0 && s.size <= 2048 && (s.size & (s.size - 1)) == 0 && s.view < asset.bufferViews.size() &&
        asset.bufferViews[s.view].byteLength >= bytes &&
        asset.bufferViews[s.view].byteOffset + bytes <= asset.buffers[asset.bufferViews[s.view].bufferIndex].byteLength)
    {
        out.size = (int)s.size;
        out.texels.resize(s.size * s.size);
        // Little-endian words, as the A53's
        std::memcpy(out.texels.data(), fastgltf::DefaultBufferDataAdapter()(asset, s.view).data(), bytes);
    }
    else
    {
        fastgltf::span<const std::byte> file;
        std::visit(fastgltf::visitor{
                       [&](const fastgltf::sources::BufferView &view) {
                           file = fastgltf::DefaultBufferDataAdapter()(asset, view.bufferViewIndex);
                       },
                       [&](const fastgltf::sources::Array &array) {
                           file = fastgltf::span<const std::byte>(array.bytes.data(), array.bytes.size());
                       },
                       [](const auto &) {}, // a file of its own (a URI): not read
                   },
                   asset.images[index].data);
        int w, h, channels;
        stbi_uc *image = file.size() == 0 ? nullptr
                                          : stbi_load_from_memory(reinterpret_cast<const stbi_uc *>(file.data()),
                                                                  (int)file.size(), &w, &h, &channels, 4);
        if (!image)
            return false;
        out.size = 1;
        while (out.size * 2 <= std::max(w, h) && out.size < max_texture)
            out.size *= 2;
        out.texels = swizzle(resample(image, w, h, out.size), out.size);
        stbi_image_free(image);
    }
    const fastgltf::Sampler *sampler = texture.samplerIndex ? &asset.samplers[*texture.samplerIndex] : nullptr;
    out.wrap_s = gl_wrap(sampler ? sampler->wrapS : fastgltf::Wrap::Repeat);
    out.wrap_t = gl_wrap(sampler ? sampler->wrapT : fastgltf::Wrap::Repeat);
    out.name = 0;
    return true;
}

// The primitive's base color texture, as the material's info has it: its coordinates, with
// KHR_texture_transform's applied, and the texture, made once for all primitives; none without either
void add_texture(gltf_scene &scene, const fastgltf::Asset &asset, const fastgltf::Primitive &primitive,
                 const fastgltf::TextureInfo &info, loading &l, gltf_scene::primitive &p)
{
    const fastgltf::TextureTransform *transform = info.transform.get();
    char name[32];
    std::snprintf(name, sizeof name, "TEXCOORD_%u",
                  (unsigned)(transform && transform->texCoordIndex ? *transform->texCoordIndex : info.texCoordIndex));
    const auto *uv = primitive.findAttribute(name);
    if (uv == primitive.attributes.end() || info.textureIndex >= l.textures.size())
        return;
    std::vector<fm::fvec2> texcoords = elements<fm::fvec2>(asset, asset.accessors[uv->accessorIndex]);
    if (texcoords.size() != p.positions.size())
        return;
    int &slot = l.textures[info.textureIndex];
    if (slot == -1)
    {
        gltf_scene::texture t;
        slot = make_texture(asset, asset.textures[info.textureIndex], l, t) ? (int)scene.textures.size() : -2;
        if (slot >= 0)
            scene.textures.push_back(std::move(t));
    }
    if (slot < 0)
        return;
    if (transform)
    {
        // Translation x rotation x scale, the rotation as Khronos's glTF-Sample-Renderer has it (the
        // extension's GLSL turns the other way)
        const float c = std::cos(transform->rotation), s = std::sin(transform->rotation);
        for (fm::fvec2 &t : texcoords)
        {
            const float u = t.x() * transform->uvScale.x(), v = t.y() * transform->uvScale.y();
            t = fm::fvec2(c * u + s * v + transform->uvOffset.x(), -s * u + c * v + transform->uvOffset.y());
        }
    }
    p.texcoords = std::move(texcoords);
    p.texture = slot;
}

// A mesh's triangle primitives, its node's world matrix m
void add_mesh(gltf_scene &scene, const fastgltf::Asset &asset, const fastgltf::Mesh &mesh, const fm::fmat4x4 &m,
              loading &l)
{
    static const fastgltf::Material none;
    for (const fastgltf::Primitive &primitive : mesh.primitives)
    {
        gltf_scene::primitive p;
        const auto *position = primitive.findAttribute("POSITION");
        if (!gl_mode(primitive.type, p.mode) || position == primitive.attributes.end())
            continue;
        p.world = m;
        p.positions = elements<fm::fvec3>(asset, asset.accessors[position->accessorIndex]);
        const std::size_t count = p.positions.size();
        const auto *normal = primitive.findAttribute("NORMAL");
        if (normal != primitive.attributes.end() && asset.accessors[normal->accessorIndex].count == count)
            p.normals = elements<fm::fvec3>(asset, asset.accessors[normal->accessorIndex]);
        if (primitive.indicesAccessor)
            p.indices = elements<std::uint32_t>(asset, asset.accessors[*primitive.indicesAccessor]);
        else
        {
            p.indices.resize(count);
            std::iota(p.indices.begin(), p.indices.end(), 0u);
        }
        if (std::any_of(p.indices.begin(), p.indices.end(), [&](std::uint32_t i) { return i >= count; }))
            continue; // an index past the vertices
        const fastgltf::Material &material = primitive.materialIndex ? asset.materials[*primitive.materialIndex] : none;
        set_material(p, material);
        if (material.pbrData.baseColorTexture)
            add_texture(scene, asset, primitive, *material.pbrData.baseColorTexture, l, p);
        const int n = (int)p.indices.size();
        scene.triangles += p.mode == GL_TRIANGLES ? n / 3 : std::max(n - 2, 0);
        scene.primitives.push_back(std::move(p));
    }
}

gltf_scene::light make_light(const fastgltf::Light &l, const fm::fmat4x4 &m, const float *gl_attenuation)
{
    gltf_scene::light out;
    if (l.type == fastgltf::LightType::Directional)
    {
        // It shines along its node's -z: it is along +z
        const float x = m[2][0], y = m[2][1], z = m[2][2], length = std::sqrt(x * x + y * y + z * z);
        out.position = fm::fvec4(x / length, y / length, z / length, 0.0f);
    }
    else
    {
        out.position = fm::fvec4(m[3][0], m[3][1], m[3][2], 1.0f);
        const float inverse_square[3] = {0, 0, 1};
        std::memcpy(out.attenuation, gl_attenuation ? gl_attenuation : inverse_square, sizeof out.attenuation);
    }
    if (l.type == fastgltf::LightType::Spot)
    {
        out.spot_direction = fm::fvec4(-m[2][0], -m[2][1], -m[2][2], 0.0f); // its node's -z
        const float inner = l.innerConeAngle ? (float)*l.innerConeAngle : 0.0f;
        const float outer = l.outerConeAngle ? (float)*l.outerConeAngle : (float)(M_PI / 4);
        out.spot_cutoff = std::min(outer * (float)(180.0 / M_PI), 90.0f);
        // glTF's ((cos a - cos outer) / (cos inner - cos outer))^2 and GL's cos a ^ exponent, equal
        // at the angle halfway; 0 (none but the cutoff) for a cone without a falloff
        const float halfway = std::cos(0.5f * (inner + outer));
        const float t = (halfway - std::cos(outer)) / (std::cos(inner) - std::cos(outer));
        if (t > 0.0f && t < 1.0f && halfway < 1.0f)
            out.spot_exponent = std::clamp(std::log(t * t) / std::log(halfway), 0.0f, 128.0f);
    }
    out.ambient = fm::fvec4(0, 0, 0, 1);
    out.color = fm::fvec4(l.color[0] * l.intensity, l.color[1] * l.intensity, l.color[2] * l.intensity, 1);
    out.eye = false;
    return out;
}

gltf_scene_t *fail(char *error, std::size_t error_size, std::string_view message)
{
    std::snprintf(error, error_size, "%.*s", (int)message.size(), message.data());
    return nullptr;
}

} // namespace

gltf_scene_t *gltf_scene_load(const void *data, size_t size, char *error, size_t error_size)
{
    // Before fastgltf's parse: the two parsers' memory, one after the other
    const gl_extras extras = read_gl_extras(data, size);
    memory_getter file(static_cast<const std::byte *>(data), size);
    fastgltf::Parser parser(fastgltf::Extensions::KHR_lights_punctual | fastgltf::Extensions::KHR_mesh_quantization |
                            fastgltf::Extensions::KHR_materials_emissive_strength |
                            fastgltf::Extensions::KHR_texture_transform | fastgltf::Extensions::KHR_materials_unlit);
    loading l;
    parser.setExtrasParseCallback(read_extras);
    parser.setUserPointer(&l);
    auto asset = parser.loadGltf(file, "", fastgltf::Options::None);
    if (asset.error() != fastgltf::Error::None)
        return fail(error, error_size, fastgltf::getErrorMessage(asset.error()));
    for (const fastgltf::Buffer &buffer : asset->buffers)
        if (!std::holds_alternative<fastgltf::sources::Array>(buffer.data) &&
            !std::holds_alternative<fastgltf::sources::Vector>(buffer.data) &&
            !std::holds_alternative<fastgltf::sources::ByteView>(buffer.data))
            return fail(error, error_size, "a buffer in a file of its own: a .glb, or a .gltf with them embedded");
    if (asset->scenes.empty())
        return fail(error, error_size, "no scene");

    gltf_scene *scene = new (std::nothrow) gltf_scene;
    if (!scene)
        return fail(error, error_size, "out of memory");
    l.textures.assign(asset->textures.size(), -1);
    fastgltf::iterateSceneNodes(
        asset.get(), asset->defaultScene.value_or(0), fm::fmat4x4(), [&](fastgltf::Node &node, const fm::fmat4x4 &m) {
            if (node.meshIndex)
                add_mesh(*scene, asset.get(), asset->meshes[*node.meshIndex], m, l);
            if (node.cameraIndex && !scene->own_camera)
            {
                const fastgltf::Camera &camera = asset->cameras[*node.cameraIndex];
                scene->own_camera = true;
                scene->view = fm::inverse(m);
                if (const auto *p = std::get_if<fastgltf::Camera::Perspective>(&camera.camera))
                {
                    scene->yfov = p->yfov;
                    scene->aspect = p->aspectRatio ? *p->aspectRatio : 0.0f;
                    scene->znear = p->znear;
                    // None: infinite, far enough here
                    scene->zfar = p->zfar ? *p->zfar : p->znear * 1e4f;
                }
                else if (const auto *o = std::get_if<fastgltf::Camera::Orthographic>(&camera.camera))
                {
                    scene->orthographic = true;
                    scene->xmag = o->xmag;
                    scene->ymag = o->ymag;
                    scene->znear = o->znear;
                    scene->zfar = o->zfar;
                }
            }
            if (node.lightIndex && scene->lights.size() < max_lights)
            {
                const std::size_t i = *node.lightIndex;
                const bool given = i < extras.lights.size() && extras.lights[i].given;
                scene->lights.push_back(make_light(asset->lights[i], m, given ? extras.lights[i].k : nullptr));
            }
        });
    if (extras.has_ambient)
        scene->ambient = extras.ambient;
    if (scene->primitives.empty())
    {
        delete scene;
        return fail(error, error_size, "no triangles");
    }

    // The bounding box in world space
    float lo[3] = {INFINITY, INFINITY, INFINITY}, hi[3] = {-INFINITY, -INFINITY, -INFINITY};
    for (const gltf_scene::primitive &p : scene->primitives)
        for (const fm::fvec3 &v : p.positions)
        {
            const fm::fvec4 world = p.world * fm::fvec4(v.x(), v.y(), v.z(), 1.0f);
            for (int k = 0; k < 3; k++)
            {
                lo[k] = std::min(lo[k], world[k]);
                hi[k] = std::max(hi[k], world[k]);
            }
        }
    for (int k = 0; k < 3; k++)
        scene->center[k] = (lo[k] + hi[k]) * 0.5f;

    // Without a camera: dv/raster_sw's, from 1.5 spans along +z, 45 degrees
    if (!scene->own_camera)
    {
        const float span = std::max({hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], 1e-6f});
        const fm::fvec3 eye(scene->center[0], scene->center[1], scene->center[2] + span * 1.5f);
        scene->view = fm::translate(fm::fmat4x4(), -eye);
        scene->yfov = (float)(45.0 * M_PI / 180.0);
        scene->znear = span * 0.01f;
        scene->zfar = span * 100.0f;
    }
    // Without lights: gl_test's, white from (1, 1, 1) in eye space
    if (scene->lights.empty())
    {
        gltf_scene::light l;
        l.position = fm::fvec4(1, 1, 1, 0);
        l.ambient = fm::fvec4(0.1f, 0.1f, 0.1f, 1);
        l.color = fm::fvec4(1, 1, 1, 1);
        l.eye = true;
        scene->lights.push_back(l);
    }
    return scene;
}

void gltf_scene_free(gltf_scene_t *scene)
{
    if (!scene)
        return;
    for (const gltf_scene::texture &t : scene->textures)
        if (t.name)
            glDeleteTextures(1, &t.name);
    delete scene;
}

int gltf_scene_triangles(const gltf_scene_t *scene)
{
    return scene->triangles;
}

int gltf_scene_textures(const gltf_scene_t *scene)
{
    return (int)scene->textures.size();
}

int gltf_scene_lights(const gltf_scene_t *scene)
{
    return (int)scene->lights.size();
}

int gltf_scene_has_camera(const gltf_scene_t *scene)
{
    return scene->own_camera;
}

// The textures not set up yet, in lviv_gl's memory, largest first: each goes at a multiple of its
// own size there, so none leaves a gap. Should they not all fit, all are taken out again and the
// largest halved, until they do (all the same size, rather than the last ones the smallest).
static void setup_textures(gltf_scene_t *scene)
{
    std::vector<gltf_scene::texture *> order;
    for (gltf_scene::texture &t : scene->textures)
        if (!t.name)
            order.push_back(&t);
    std::stable_sort(order.begin(), order.end(),
                     [](const gltf_scene::texture *a, const gltf_scene::texture *b) { return a->size > b->size; });
    glGetError(); // what came before
    while (!order.empty())
    {
        bool fit = true;
        for (gltf_scene::texture *t : order)
        {
            glGenTextures(1, &t->name);
            if (!t->name)
            {
                glGetError(); // all 128 names taken: the rest untextured
                break;
            }
            glBindTexture(GL_TEXTURE_2D, t->name);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, t->wrap_s);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, t->wrap_t);
            lviv_gl_tex_image(t->size, t->texels.data());
            if (glGetError() != GL_NO_ERROR)
            {
                fit = false;
                break;
            }
        }
        if (fit)
            break;
        for (gltf_scene::texture *t : order)
            if (t->name)
            {
                glDeleteTextures(1, &t->name);
                t->name = 0;
            }
        const int largest = order.front()->size; // still the first, halved: the others are its half at most
        if (largest == 1)
            break; // not even 1 x 1: untextured
        for (gltf_scene::texture *t : order)
            if (t->size == largest)
            {
                t->texels = halve(t->texels);
                t->size /= 2;
            }
    }
    for (gltf_scene::texture *t : order)
        if (t->name)
            std::vector<std::uint32_t>().swap(t->texels); // lviv_gl has them now
    glBindTexture(GL_TEXTURE_2D, 0);
}

void gltf_scene_setup(gltf_scene_t *scene, int width, int height)
{
    setup_textures(scene);
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE); // the lit color times the texture
    glViewport(0, 0, width, height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    if (scene->orthographic)
        glOrtho(-scene->xmag, scene->xmag, -scene->ymag, scene->ymag, scene->znear, scene->zfar);
    else
        gluPerspective(scene->yfov * 180.0 / M_PI, scene->aspect > 0 ? scene->aspect : (double)width / height,
                       scene->znear, scene->zfar);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    for (std::size_t i = 0; i < max_lights; i++)
    {
        const GLenum id = GL_LIGHT0 + (GLenum)i;
        if (i >= scene->lights.size())
        {
            glDisable(id);
            continue;
        }
        const gltf_scene::light &l = scene->lights[i];
        glLightfv(id, GL_AMBIENT, l.ambient.data());
        glLightfv(id, GL_DIFFUSE, l.color.data());
        glLightfv(id, GL_SPECULAR, l.color.data());
        glLightf(id, GL_CONSTANT_ATTENUATION, l.attenuation[0]);
        glLightf(id, GL_LINEAR_ATTENUATION, l.attenuation[1]);
        glLightf(id, GL_QUADRATIC_ATTENUATION, l.attenuation[2]);
        glLightf(id, GL_SPOT_EXPONENT, l.spot_exponent);
        glLightf(id, GL_SPOT_CUTOFF, l.spot_cutoff);
        glEnable(id);
    }
    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, scene->ambient.data());
    glEnable(GL_LIGHTING);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    glEnableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
}

void gltf_scene_draw(const gltf_scene_t *scene, float angle)
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glMatrixMode(GL_MODELVIEW);
    // Each light's position and spot direction through the modelview at the call, as GL has them:
    // eye space, then world
    glLoadIdentity();
    for (std::size_t i = 0; i < scene->lights.size(); i++)
        if (scene->lights[i].eye)
        {
            glLightfv(GL_LIGHT0 + (GLenum)i, GL_POSITION, scene->lights[i].position.data());
            glLightfv(GL_LIGHT0 + (GLenum)i, GL_SPOT_DIRECTION, scene->lights[i].spot_direction.data());
        }
    glLoadMatrixf(scene->view.data());
    for (std::size_t i = 0; i < scene->lights.size(); i++)
        if (!scene->lights[i].eye)
        {
            glLightfv(GL_LIGHT0 + (GLenum)i, GL_POSITION, scene->lights[i].position.data());
            glLightfv(GL_LIGHT0 + (GLenum)i, GL_SPOT_DIRECTION, scene->lights[i].spot_direction.data());
        }
    glTranslatef(scene->center[0], scene->center[1], scene->center[2]);
    glRotatef(angle, 0, 1, 0);
    glTranslatef(-scene->center[0], -scene->center[1], -scene->center[2]);

    for (const gltf_scene::primitive &p : scene->primitives)
    {
        glPushMatrix();
        glMultMatrixf(p.world.data());
        glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, p.ambient.data());
        glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, p.diffuse.data());
        glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, p.specular.data());
        glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, p.emission.data());
        glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, p.shininess);
        if (p.double_sided)
            glDisable(GL_CULL_FACE);
        else
            glEnable(GL_CULL_FACE);
        glVertexPointer(3, GL_FLOAT, 0, p.positions.data());
        if (p.normals.empty())
        {
            glDisableClientState(GL_NORMAL_ARRAY);
            glNormal3f(0, 0, 1);
        }
        else
        {
            glEnableClientState(GL_NORMAL_ARRAY);
            glNormalPointer(GL_FLOAT, 0, p.normals.data());
        }
        if (p.texture >= 0 && scene->textures[p.texture].name)
        {
            glEnable(GL_TEXTURE_2D);
            glBindTexture(GL_TEXTURE_2D, scene->textures[p.texture].name);
            glEnableClientState(GL_TEXTURE_COORD_ARRAY);
            glTexCoordPointer(2, GL_FLOAT, 0, p.texcoords.data());
        }
        else
        {
            glDisable(GL_TEXTURE_2D);
            glDisableClientState(GL_TEXTURE_COORD_ARRAY);
        }
        glDrawElements(p.mode, (GLsizei)p.indices.size(), GL_UNSIGNED_INT, p.indices.data());
        glPopMatrix();
    }
}
