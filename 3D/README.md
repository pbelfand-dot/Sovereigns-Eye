# Sovereign's Eye 3D library

This folder is the game's organized library of stylized, low-poly 3D assets. Models
are stored as **GLB (glTF 2.0)** for broad support across Roblox import workflows,
Godot, Unity, Unreal, Blender, Three.js, and other modern tools.

## Library map

| Location | Contents | Models |
| --- | --- | ---: |
| `characters/blocky/` | Rigged cartoon characters, each with 27 animation clips | 18 |
| `environments/castle-kit/architecture/` | Walls, towers, gates, bridges, stairs, and doors | 54 |
| `environments/castle-kit/decor/` | Banners and pennants | 4 |
| `environments/castle-kit/siege/` | Ballista, catapult, ram, tower, trebuchet, and damaged variants | 10 |
| `environments/castle-kit/terrain/` | Ground, rocks, trees, logs, and trunks | 8 |
| `environments/fantasy-town-kit/architecture/` | Modular buildings, roofs, stairs, mills, walls, and structural parts | 120 |
| `environments/fantasy-town-kit/decor/` | Carts, stalls, fences, banners, lanterns, and props | 16 |
| `environments/fantasy-town-kit/terrain/` | Roads, rocks, trees, and hedges | 21 |
| `environments/fantasy-town-kit/water/` | Modular fountain parts | 10 |

Total: **261 models**.

## Finding the right model

- Browse `previews/` to see every asset without opening a 3D editor. Preview names
  match model names.
- Search [`ASSET_MANIFEST.csv`](ASSET_MANIFEST.csv) for category, source pack,
  animation clips, file size, preview, texture dependency, license, or SHA-256 hash.
- The 18 characters include idle, walk, sprint, sitting, interaction, melee, shooting,
  death, pickup, emote, driving, and wheelchair animation clips.

## Importing correctly

Each GLB uses one nearby PNG color texture. Keep its sibling `Textures/` folder with
the model when moving files. The exact texture path for every model is recorded in
`ASSET_MANIFEST.csv`.

Example:

```text
characters/blocky/
├── character-a.glb
└── Textures/
    └── texture-a.png
```

In most engines, import the `.glb` file directly. If an engine copies assets into a
new folder, copy the corresponding `Textures/` folder too.

## Licensing and provenance

All models and previews in this folder come from Kenney and are released under
**Creative Commons Zero (CC0 1.0)**. They may be used, changed, and distributed for
personal, educational, or commercial purposes. Attribution is appreciated by the
creator but is not required.

- Pack-specific license files are in `licenses/`.
- Original pack pages and retrieval details are in [`SOURCES.md`](SOURCES.md).
- Do not remove those records when shipping or reorganizing the library; they make
  the asset provenance easy to audit.

## Validation

[`VALIDATION.json`](VALIDATION.json) records the completed checks. Every model was
confirmed as a readable glTF 2.0 GLB, every referenced texture is present, every model
has a matching preview, and every file has a SHA-256 checksum in the manifest.

To rebuild both records after changing the library:

```sh
python3 3D/tools/build_asset_manifest.py
```
