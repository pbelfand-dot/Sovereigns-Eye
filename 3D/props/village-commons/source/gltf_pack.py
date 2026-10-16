"""Turns Blender's glTF (separate) export into a runtime GLB that shares the
Quaternius trim-sheet textures instead of copying them.

    python3 gltf_pack.py in.gltf out.glb

- Materials named like the kit's (MI_WoodTrim, MI_RockTrim, MI_RoundTiles,
  MI_MetalOrnaments) are replaced with the kit's exact definitions, and their
  images point at the kit's PNGs by relative path, so Godot loads each texture
  once for buildings and commons alike.
- The family's own materials (MI_Commons_*) get their definitions here.
- Geometry goes into the GLB's binary chunk; images stay external (relative URIs).
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
LIB3D = os.path.dirname(os.path.dirname(FAMILY))
VILLAGE = os.path.join(LIB3D, "environments", "quaternius-medieval-village-standard", "models")
TEXTURES = os.path.join(FAMILY, "textures")

LINEAR_MIPMAP = {"magFilter": 9729, "minFilter": 9987}

# name -> (material json with texture slots as image paths, image dir)
KIT = {
    "MI_WoodTrim": {"doubleSided": True, "normalTexture": "T_WoodTrim_Normal.png",
                    "pbr": {"baseColorTexture": "T_WoodTrim_BaseColor.png", "metallicFactor": 0, "metallicRoughnessTexture": "T_WoodTrim_Roughness.png"}},
    "MI_RockTrim": {"doubleSided": True, "normalTexture": "T_RockTrim_Normal.png",
                    "pbr": {"baseColorTexture": "T_RockTrim_BaseColor.png", "metallicRoughnessTexture": "T_RockTrim_ORM.png"}},
    "MI_RoundTiles": {"doubleSided": True, "normalTexture": "T_RoundTiles_Normal.png",
                      "pbr": {"baseColorTexture": "T_RoundTiles_BaseColor.png", "metallicFactor": 0, "metallicRoughnessTexture": "T_RoundTiles_Roughness.png"}},
    "MI_MetalOrnaments": {"doubleSided": True,
                          "pbr": {"baseColorTexture": "T_MetalOrnaments_BaseColor.png", "metallicRoughnessTexture": "T_MetalOrnaments_Roughness.png"}},
}
OWN = {
    "MI_Commons_Banner": {"doubleSided": True, "dir": TEXTURES,
                          "pbr": {"baseColorTexture": "T_Commons_Banner_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}},
    "MI_Commons_Water": {"doubleSided": False,
                         "pbr": {"baseColorFactor": [0.09, 0.2, 0.22, 1.0], "metallicFactor": 0, "roughnessFactor": 0.08}},
}


def rel_uri(out_dir, image_path):
    return os.path.relpath(image_path, out_dir).replace(os.sep, "/")


def pack(src, dst, own=None):
    """`own`: extra family materials {name: spec} (same shape as OWN, with
    "dir" giving their texture folder)."""
    with open(src) as f:
        doc = json.load(f)
    out_dir = os.path.dirname(os.path.abspath(dst))
    doc["images"], doc["textures"], doc["samplers"] = [], [], [LINEAR_MIPMAP]
    image_index = {}

    def tex(path):
        if path not in image_index:
            doc["images"].append({"mimeType": "image/png", "name": os.path.splitext(os.path.basename(path))[0], "uri": rel_uri(out_dir, path)})
            doc["textures"].append({"sampler": 0, "source": len(doc["images"]) - 1})
            image_index[path] = len(doc["textures"]) - 1
        return {"index": image_index[path]}

    used = set()
    for i, m in enumerate(doc.get("materials", [])):
        name = m.get("name", "")
        spec = KIT.get(name) or OWN.get(name) or (own or {}).get(name)
        if spec is None:
            raise SystemExit("%s: material %r is not a kit or commons material" % (src, name))
        used.add(name)
        image_dir = spec.get("dir", VILLAGE)
        new = {"name": name, "doubleSided": spec["doubleSided"]}
        if "normalTexture" in spec:
            new["normalTexture"] = tex(os.path.join(image_dir, spec["normalTexture"]))
        pbr = {}
        for k, v in spec["pbr"].items():
            pbr[k] = tex(os.path.join(image_dir, v)) if k.endswith("Texture") else v
        new["pbrMetallicRoughness"] = pbr
        doc["materials"][i] = new
    for k in ("images", "textures"):
        if not doc[k]:
            del doc[k]
    if "textures" not in doc:
        del doc["samplers"]
    # Embed the geometry buffer.
    buf = doc["buffers"][0]
    with open(os.path.join(os.path.dirname(os.path.abspath(src)), buf["uri"]), "rb") as f:
        bin_data = f.read()
    del buf["uri"]
    buf["byteLength"] = len(bin_data)
    doc.setdefault("asset", {})["generator"] = "Sovereign's Eye village-commons (Blender 4.2 + gltf_pack.py)"
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_data += b"\0" * ((4 - len(bin_data) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_data)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)
    return sorted(used)


def read_glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2 and length == len(data), "bad GLB header"
    jlen, jtype = struct.unpack("<II", data[12:20])
    assert jtype == 0x4E4F534A
    return json.loads(data[20:20 + jlen])


if __name__ == "__main__":
    print(pack(sys.argv[1], sys.argv[2]))
