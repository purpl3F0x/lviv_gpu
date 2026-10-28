"""glTF files for gl_test (sdk/gl_test) with their textures pre-swizzled: each base color texture's
image also as the GPU's own texels, which sdk/gltf's loader copies as they are (lviv_gl_tex_image)
instead of decoding the image and swizzling it on the A53. Writes a .glb, every buffer and image of
the file in its binary chunk (external files and data: URIs read in), the images kept as they are
for other viewers.

The texels: square, a power of two across (the image's longer side, at most --size), resized with
Pillow's box filter (the loader's weighs the texels its own cut through: an image of another size
comes out a little different from the two); little-endian words a << 24 | r << 16 | g << 8 | b
in Morton order (sdk/src/gpu.c's gpu_texel_index: x's bit i is the index's bit 2i, y's its bit
2i + 1), row 0 the image's top (glTF's v = 0). They go in a buffer view of their own, which the
image's extras name:
    "extras": {"lviv_texels": {"bufferView": <its index>, "size": <texels across>}}
An image that has them already keeps them (for another size, run the script on the original file).

Usage: python scripts/gltf_swizzle.py IN.gltf|IN.glb OUT.glb [--size N]   (with Pillow and NumPy)
"""

import argparse
import base64
import io
import json
import os
import struct
import urllib.parse

import numpy as np
from PIL import Image

GPU_TEXTURE_MAX = 2048  # texels across: GPU_TEXTURE_MAX_LOG2 (sdk/include/gpu_map.h)
ALIGN = 16  # of each buffer and buffer view placed in the binary chunk


def read(path):
    """The file's JSON and, for a .glb, its binary chunk (None for a .gltf)"""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        return json.loads(data), None
    _, length = struct.unpack_from("<II", data, 4)
    offset, chunks = 12, []
    while offset < length:
        size, kind = struct.unpack_from("<I4s", data, offset)
        chunks.append((kind, data[offset + 8 : offset + 8 + size]))
        offset += 8 + size
    return json.loads(chunks[0][1]), next((c for k, c in chunks if k == b"BIN\0"), None)


def load_uri(uri, directory):
    """A URI's bytes and the media type it says (None if it does not): a data URI's, or a file's,
    relative to the glTF file"""
    if uri.startswith("data:"):
        header, _, payload = uri.partition(",")
        data = (
            base64.b64decode(payload)
            if header.endswith(";base64")
            else urllib.parse.unquote_to_bytes(payload)
        )
        return data, header[5:].split(";")[0] or None
    with open(os.path.join(directory, urllib.parse.unquote(uri)), "rb") as f:
        types = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
        return f.read(), types.get(os.path.splitext(uri)[1].lower())


def morton(size):
    """gpu_texel_index of each texel of a size x size texture, by [y, x]"""
    y, x = np.mgrid[0:size, 0:size].astype(np.uint32)
    index = np.zeros((size, size), np.uint32)
    for bit in range(GPU_TEXTURE_MAX.bit_length() - 1):
        index |= ((x >> bit) & 1) << (2 * bit) | ((y >> bit) & 1) << (2 * bit + 1)
    return index


def swizzle(image, largest):
    """The image as the GPU's texels (bytes), and their size across"""
    image = image.convert("RGBA")
    size = 1
    while size * 2 <= max(image.size) and size < largest:
        size *= 2
    if image.size != (size, size):
        image = image.resize((size, size), Image.Resampling.BOX)
    # b, g, r, a: a word's bytes, little-endian
    bgra = np.asarray(image, np.uint8)[:, :, [2, 1, 0, 3]]
    texels = np.empty((size * size, 4), np.uint8)
    texels[morton(size).ravel()] = bgra.reshape(-1, 4)
    return texels.tobytes(), size


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("input", help=".gltf or .glb")
    parser.add_argument("output", help=".glb")
    parser.add_argument(
        "--size",
        type=int,
        default=GPU_TEXTURE_MAX,
        help="texels across, at most: a power of two up to 2048 (default 2048, the loader's)",
    )
    args = parser.parse_args()
    if not 1 <= args.size <= GPU_TEXTURE_MAX or args.size & (args.size - 1):
        parser.error(f"--size: a power of two up to {GPU_TEXTURE_MAX}")
    gltf, glb_binary = read(args.input)
    directory = os.path.dirname(os.path.abspath(args.input))
    binary = bytearray()

    def place(data):
        binary.extend(b"\0" * (-len(binary) % ALIGN))
        offset = len(binary)
        binary.extend(data)
        return offset

    # The buffers one after another, in one
    starts = []
    for i, buffer in enumerate(gltf.get("buffers", [])):
        if "uri" in buffer:
            data, _ = load_uri(buffer["uri"], directory)
        elif i == 0 and glb_binary is not None:
            data = glb_binary
        else:
            raise SystemExit(f"{args.input}: buffer {i} has no data")
        starts.append(place(data[: buffer["byteLength"]]))
    views = gltf.setdefault("bufferViews", [])
    for view in views:
        view["byteOffset"] = starts[view["buffer"]] + view.get("byteOffset", 0)
        view["buffer"] = 0

    def add_view(data):
        views.append({"buffer": 0, "byteOffset": place(data), "byteLength": len(data)})
        return len(views) - 1

    # The images in it too
    images = gltf.get("images", [])
    for image in images:
        if "uri" in image:
            data, media = load_uri(image.pop("uri"), directory)
            image["bufferView"] = add_view(data)
            image.setdefault(
                "mimeType", media or Image.open(io.BytesIO(data)).get_format_mimetype()
            )

    # The base color textures' images, swizzled
    used = set()
    for material in gltf.get("materials", []):
        info = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if info is not None and "source" in gltf["textures"][info["index"]]:
            used.add(gltf["textures"][info["index"]]["source"])
    for i in sorted(used):
        image = images[i]
        name = f"image {i}" + (f" ({image['name']})" if image.get("name") else "")
        extras = image.setdefault("extras", {})
        if "lviv_texels" in extras:
            print(f"{name}: swizzled already, {extras['lviv_texels']['size']} across")
            continue
        view = views[image["bufferView"]]
        data = binary[view["byteOffset"] : view["byteOffset"] + view["byteLength"]]
        picture = Image.open(io.BytesIO(bytes(data)))
        texels, size = swizzle(picture, args.size)
        extras["lviv_texels"] = {"bufferView": add_view(texels), "size": size}
        print(
            f"{name}: {picture.size[0]} x {picture.size[1]}, swizzled {size} x {size}"
        )

    # The .glb: the JSON chunk (padded with spaces), the binary chunk (padded with zeros)
    gltf["buffers"] = [{"byteLength": len(binary)}] if binary else []
    chunk = json.dumps(gltf, separators=(",", ":")).encode()
    chunk += b" " * (-len(chunk) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    out = struct.pack("<I4s", len(chunk), b"JSON") + chunk
    if binary:
        out += struct.pack("<I4s", len(binary), b"BIN\0") + bytes(binary)
    out = struct.pack("<4sII", b"glTF", 2, 12 + len(out)) + out
    with open(args.output, "wb") as f:
        f.write(out)
    print(f"{args.output}: {len(out)} bytes")


if __name__ == "__main__":
    main()
