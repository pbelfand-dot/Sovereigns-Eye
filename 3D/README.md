# Sovereign's Eye 3D library

This folder is the game's organized library of stylized, low-poly 3D assets. Models
are stored as **glTF 2.0** for broad support across Roblox import workflows, Godot,
Unity, Unreal, Blender, Three.js, and other modern tools. Most collections use
self-contained GLB; the Medieval Village MegaKit keeps JSON glTF, paired BIN, and
shared PNG files to avoid duplicating large texture maps into every module.

## Library map

| Location | Contents | Models |
| --- | --- | ---: |
| `characters/blocky/` | Rigged cartoon characters, each with 27 animation clips | 18 |
| `environments/castle-kit/architecture/` | Walls, towers, gates, bridges, stairs, and doors | 53 |
| `environments/castle-kit/decor/` | Flags, banners, and pennants | 5 |
| `environments/castle-kit/siege/` | Ballista, catapult, ram, tower, trebuchet, and damaged variants | 10 |
| `environments/castle-kit/terrain/` | Ground, rocks, trees, logs, and trunks | 8 |
| `environments/fantasy-town-kit/architecture/` | Modular buildings, roofs, stairs, mills, walls, and structural parts | 121 |
| `environments/fantasy-town-kit/decor/` | Carts, stalls, fences, banners, lanterns, and props | 15 |
| `environments/fantasy-town-kit/terrain/` | Roads, rocks, trees, and hedges | 21 |
| `environments/fantasy-town-kit/water/` | Modular fountain parts | 10 |
| `environments/quaternius-medieval-village-standard/` | Textured modular village architecture and props | 176 |
| `environments/quaternius-stylized-nature-standard/` | Trees, plants, grass, flowers, rocks, and stone path pieces | 68 |
| `props/quaternius-fantasy-props-standard/` | Furniture, market goods, workshop equipment, weapons, books, potions, lighting, and small props | 94 |
| `alternatives/option-01-kaykit-adventurers/` | Rounded fantasy heroes | 5 |
| `alternatives/option-02-kaykit-skeletons/` | Stylized undead characters | 4 |
| `alternatives/option-03-kaykit-dungeon/` | Modular dungeon architecture, furnishings, and props | 203 |
| `alternatives/option-04-kaykit-medieval-hexagon/` | Medieval buildings, terrain, nature, and settlement props | 221 |
| `alternatives/option-05-kaykit-halloween/` | Gothic fantasy scenery, trees, graves, lanterns, and pumpkins | 63 |
| `alternatives/option-03-kenney-graveyard/` | Rejected comparison pack retained for reference | 91 |
| `alternatives/option-04-kenney-platformer/` | Rejected comparison pack retained for reference | 153 |
| `alternatives/option-05-kenney-mini-characters/` | Rejected comparison pack retained for reference | 26 |
| `character-tests/quaternius-universal-base-standard/` | Sleek rigged base bodies plus modular hair test pieces | 10 |
| `characters/quaternius-modular-outfits-fantasy-standard/` | Peasant/Ranger complete outfits and separate modular clothing pieces | 24 |
| `animations/quaternius-universal-animation-library-1/` | In-place and root-motion versions of the first Standard animation set | 2 |
| `animations/quaternius-universal-animation-library-2/` | In-place/root-motion Standard set plus a retargeting mannequin | 3 |

Total: **1,404 glTF 2.0 model files** (1,042 GLB + 362 JSON glTF).

The original blocky set and three Kenney alternatives remain available for comparison,
but the five KayKit collections in [`alternatives/`](alternatives/) are the recommended
non-Minecraft-like, non-Kenney direction. Each shortlisted option has its own models,
preview gallery, source, license, and decision notes.

The current sleek-character test is the free Quaternius Standard pack in
[`character-tests/quaternius-universal-base-standard/`](character-tests/quaternius-universal-base-standard/).
Its matching free outfit sampler is in
[`characters/quaternius-modular-outfits-fantasy-standard/`](characters/quaternius-modular-outfits-fantasy-standard/),
with four complete Peasant/Ranger outfits, 20 modular pieces, and alternate colors.
Both matching Universal Animation Library Standard editions are in
[`animations/`](animations/), including in-place and root-motion exports.
The matching environment direction is documented in
[`research/ARCHITECTURE_SHORTLIST.md`](research/ARCHITECTURE_SHORTLIST.md).
The free Stylized Nature Standard collection in
[`environments/quaternius-stylized-nature-standard/`](environments/quaternius-stylized-nature-standard/)
adds 68 matching trees, plants, rocks, and path pieces.
The free Fantasy Props Standard collection in
[`props/quaternius-fantasy-props-standard/`](props/quaternius-fantasy-props-standard/)
adds 94 matching market, workshop, home, tavern, scholar, and utility props.

## Finding the right model

- Browse `previews/` to see every asset without opening a 3D editor. Preview names
  match model names.
- Search [`ASSET_MANIFEST.csv`](ASSET_MANIFEST.csv) for category, source pack,
  animation clips, file size, preview, texture dependency, license, or SHA-256 hash.
- The 18 characters include idle, walk, sprint, sitting, interaction, melee, shooting,
  death, pickup, emote, driving, and wheelchair animation clips.

## Importing correctly

Some GLBs use a nearby PNG color texture and some embed their textures. When a
`Textures/` folder exists, keep it with the model when moving files. The exact external
texture path for every model is recorded in `ASSET_MANIFEST.csv`.

The Quaternius Medieval Village, Stylized Nature, and Fantasy Props Standard
packs use shared PNG maps and one BIN per JSON glTF. Keep each collection
together; moving only an individual `.gltf` file will leave behind its geometry
or shared textures.

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

All models and previews in this folder come from Kenney, KayKit, or Quaternius and are released
under **Creative Commons Zero (CC0 1.0)**. They may be used, changed, and distributed
for personal, educational, or commercial purposes. Attribution is appreciated but is
not required.

- Pack-specific license files are in `licenses/` and each alternative option folder.
- Original pack pages and retrieval details are in [`SOURCES.md`](SOURCES.md).
- Do not remove those records when shipping or reorganizing the library; they make
  the asset provenance easy to audit.

## Validation

[`VALIDATION.json`](VALIDATION.json) records the completed checks. Every model was
confirmed as readable glTF 2.0, every referenced buffer and texture is present, and every
file has a SHA-256 checksum in the manifest. The original and Kenney collections have
one preview per model; the larger KayKit environment packs provide official overview
and scene galleries instead.

To rebuild both records after changing the library:

```sh
python3 3D/tools/build_asset_manifest.py
```
