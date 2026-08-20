#include "geometry_engine.h"
#include "rasterizer.h"
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#ifdef RASTERIZER_EXTERNAL_RASTERIZE_TRIANGLE
extern void threadCmpProgramTexture(const std::vector<uint32_t> &pixels, int width, int height);
extern void threadCmpSaveReferenceImage(const char *path);
#endif

std::vector<Vertex_ObjectSpace> loadOBJ(const std::string &filename)
{
    std::vector<Vertex_ObjectSpace> vertices;
    std::vector<Vec3> temp_positions;
    std::vector<Vec3> temp_normals;

    std::ifstream file(filename);
    if (!file.is_open())
        return vertices;

    std::string line;
    while (std::getline(file, line))
    {
        if (line.empty() || line[0] == '#')
            continue;
        std::istringstream iss(line);
        std::string type;
        iss >> type;

        if (type == "v")
        {
            Vec3 v;
            iss >> v.x >> v.y >> v.z;
            temp_positions.push_back(v);
        }
        else if (type == "vn")
        {
            Vec3 vn;
            iss >> vn.x >> vn.y >> vn.z;
            temp_normals.push_back(vn);
        }
        else if (type == "f")
        {
            std::vector<Vertex_ObjectSpace> face_verts;
            std::string vertexData;
            while (iss >> vertexData)
            {
                int pIdx = 0, nIdx = 0;
                size_t firstSlash = vertexData.find('/');
                size_t lastSlash = vertexData.rfind('/');

                if (firstSlash == std::string::npos)
                {
                    pIdx = std::stoi(vertexData);
                }
                else if (firstSlash == lastSlash)
                {
                    pIdx = std::stoi(vertexData.substr(0, firstSlash));
                }
                else
                {
                    pIdx = std::stoi(vertexData.substr(0, firstSlash));
                    if (lastSlash + 1 < vertexData.length())
                    {
                        nIdx = std::stoi(vertexData.substr(lastSlash + 1));
                    }
                }

                Vertex_ObjectSpace vertex;
                vertex.position = temp_positions[pIdx - 1];
                if (nIdx > 0 && nIdx <= (int)temp_normals.size())
                {
                    vertex.normal = temp_normals[nIdx - 1];
                }
                else
                {
                    vertex.normal = Vec3(0, 0, 1);
                }
                // Color based on normal, packed as ARGB
                uint8_t a = 255;
                uint8_t r = static_cast<uint8_t>(std::abs(vertex.normal.x) * 255.0f);
                uint8_t g = static_cast<uint8_t>(std::abs(vertex.normal.y) * 255.0f);
                uint8_t b = static_cast<uint8_t>(std::abs(vertex.normal.z) * 255.0f);
                vertex.color = (a << 24) | (r << 16) | (g << 8) | b;
                // Procedural planar mapping - UV scale > 1 causes tiling with REPEAT wrap mode
                const float uvScale = 4.0f;
                float u = (vertex.position.x * 0.5f + 0.5f) * uvScale;
                float v = (vertex.position.y * 0.5f + 0.5f) * uvScale;
                vertex.texcoord = Vec2(u, v);
                face_verts.push_back(vertex);
            }

            // Triangulate polygon (fan triangulation)
            for (size_t i = 1; i + 1 < face_verts.size(); ++i)
            {
                vertices.push_back(face_verts[0]);
                vertices.push_back(face_verts[i]);
                vertices.push_back(face_verts[i + 1]);
            }
        }
    }
    return vertices;
}

void savePNG(const Framebuffer &fb, const char *filename)
{
    stbi_write_png(filename, fb.width, fb.height, 4, fb.colorBuffer.data(), fb.width * 4);
}

int main()
{
    int width = 1280;
    int height = 720;
    Framebuffer fb(width, height);
    Rasterizer rasterizer(&fb);
    GeometryEngine geom(&rasterizer, width, height);

    // Load OBJ
    std::vector<Vertex_ObjectSpace> modelVerts = loadOBJ("./objs/suzanne.obj");
    if (modelVerts.empty())
    {
        return 1;
    }

    std::cout << "Loaded " << modelVerts.size() / 3 << " triangles." << std::endl;

    // Determine bounding box for camera placement
    Vec3 min_bounds(1e9f, 1e9f, 1e9f);
    Vec3 max_bounds(-1e9f, -1e9f, -1e9f);
    for (const auto &v : modelVerts)
    {
        min_bounds.x = std::min(min_bounds.x, v.position.x);
        min_bounds.y = std::min(min_bounds.y, v.position.y);
        min_bounds.z = std::min(min_bounds.z, v.position.z);
        max_bounds.x = std::max(max_bounds.x, v.position.x);
        max_bounds.y = std::max(max_bounds.y, v.position.y);
        max_bounds.z = std::max(max_bounds.z, v.position.z);
    }
    Vec3 center = (min_bounds + max_bounds) * 0.5f;
    float max_span =
        std::max(max_bounds.x - min_bounds.x, std::max(max_bounds.y - min_bounds.y, max_bounds.z - min_bounds.z));

    // 1. Setup Camera and MVP
    Mat4 model; // Identity

    // Position camera based on bounding box
    Vec3 eye = center + Vec3(0, 0, max_span * 1.5f);
    Mat4 view = lookAt(eye, center, Vec3(0, 1, 0));

    // Perspective projection: 45 degree FOV, aspect ratio, near 0.1, far 1000.0
    Mat4 projection = perspective(45.0f * 3.14159f / 180.0f, (float)width / (float)height, 0.1f, 1000.0f);

    geom.setModelMatrix(model);
    geom.setViewMatrix(view);
    geom.setProjectionMatrix(projection);

    // Setup Lighting
    geom.lightingEnabled = true;
    geom.light0.position = Vec4(1.0f, 1.0f, 1.0f, 0.0f); // Directional light from upper-right angle
    geom.light0.ambient = Vec3(0.1f, 0.1f, 0.1f);
    geom.light0.diffuse = Vec3(1.0f, 1.0f, 1.0f);
    geom.light0.specular = Vec3(1.0f, 1.0f, 1.0f);

    geom.material.ambient = Vec3(0.5f, 0.5f, 0.5f); // Neutral
    geom.material.diffuse = Vec3(1.0f, 1.0f, 1.0f); // White base to show textures
    geom.material.specular = Vec3(1.0f, 1.0f, 1.0f);
    geom.material.shininess = 32.0f;

    // Load Texture
#ifndef THREAD_VERILATOR_NO_TEXTURE
    Texture myTex;
    int tw, th, tcomp;
    const char *texture_path = "texture_3.jpg";
    unsigned char *data = stbi_load(texture_path, &tw, &th, &tcomp, 4);
    if (data)
    {
        myTex.width = tw;
        myTex.height = th;
        myTex.pixels.resize(tw * th);
        for (int i = 0; i < tw * th; ++i)
        {
            uint8_t r = data[i * 4 + 0];
            uint8_t g = data[i * 4 + 1];
            uint8_t b = data[i * 4 + 2];
            uint8_t a = data[i * 4 + 3];
            myTex.pixels[i] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        stbi_image_free(data);
        std::cout << "Loaded " << texture_path << " (" << tw << "x" << th << ")" << std::endl;

        rasterizer.textureUnit.enabled = true;
        rasterizer.textureUnit.boundTexture = &myTex;
        rasterizer.textureUnit.envMode = TexEnvMode::MODULATE;

#ifdef RASTERIZER_EXTERNAL_RASTERIZE_TRIANGLE
        threadCmpProgramTexture(myTex.pixels, tw, th);
#endif
    }
    else
    {
        std::cerr << "Failed to load " << texture_path << std::endl;
        return 1;
    }
#else
    std::cout << "Texture disabled for thread_verilator compare run" << std::endl;
#endif

    // 3. Clear framebuffer
    fb.clear(0xFF636363, 1.0f);
    // 4. Draw!
    auto start_time = std::chrono::high_resolution_clock::now();

    for (size_t i = 0; i + 2 < modelVerts.size(); i += 3)
    {
        geom.drawTriangle(modelVerts[i], modelVerts[i + 1], modelVerts[i + 2]);
    }

    // Execute binning and rasterization (dumping bins to images)
    rasterizer.flush(true);

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> render_ms = end_time - start_time;
    std::cout << "Render time: " << render_ms.count() << " ms" << std::endl;

    // 5. Output image(s)
#ifdef RASTERIZER_EXTERNAL_RASTERIZE_TRIANGLE
    // Verilator compare mode: save the DUT image and the software reference
    // image side by side for visual diffing.
    savePNG(fb, "output_dut.png");
    threadCmpSaveReferenceImage("output_ref.png");
#else
    // Standalone software mode: framebuffer itself is the software reference.
    savePNG(fb, "output_ref.png");
#endif

    std::cout << "Pixel draw count: " << rasterizer.pixel_draw_count << "\n";

    return 0;
}
