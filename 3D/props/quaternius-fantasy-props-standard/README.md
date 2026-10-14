# Quaternius Fantasy Props MegaKit — Standard

This folder contains the free Standard edition of Quaternius's Fantasy Props
MegaKit, organized for Sovereign's Eye. The pack matches the project's chosen
Quaternius village, nature, character, and outfit direction.

## Included

- 94 JSON glTF 2.0 models and their paired BIN geometry files
- 13 shared glTF texture maps across cloth, furniture, metal, and general props
- 4 additional Unreal-oriented normal maps retained for source completeness
- Three official preview images
- The publisher's original CC0 license notice

The models cover furniture, market stalls, workshop equipment, weapons, books,
potions, lighting, storage, food, tableware, banners, coins, keys, and general
interior dressing. Search `3D/ASSET_MANIFEST.csv` by collection
`quaternius-fantasy-props-standard` to browse the categorized inventory.

## Layout

- `models/` — 94 JSON glTF files and 94 paired BIN files
- `textures/` — shared PNG maps used by all models
- `textures/Normals-UnrealEngine/` — alternate normal maps supplied for Unreal
- `previews/` — three official overview images

The archive also contained duplicate FBX and OBJ versions. This repository keeps
only glTF 2.0 to avoid storing the same geometry three times. Model image URIs
were adjusted to point to the shared `textures/` directory; meshes, materials,
geometry, and images are otherwise unchanged. Keep the collection together so
the relative paths continue to resolve.

## Integration priorities

1. **Market square:** `Stall_Empty`, `Stall_Cart_Empty`, farm crates, barrels,
   baskets, coins, bags, and tableware.
2. **Smithy:** anvil, workbench, whetstone, weapon stand, training dummy,
   bronze tools, sword, shield, buckets, and chain.
3. **Tavern and homes:** tables, chairs, benches, stools, beds, cabinets,
   shelves, mugs, plates, cutlery, candles, chandelier, and fireplace-adjacent
   storage.
4. **Scholar and healer spaces:** books, scrolls, bottles, potions, cauldron,
   chalice, book stand, and bookcase.

Use simple collision proxies instead of mesh-perfect collision. Repeated props
such as crates, barrels, chairs, books, and market goods should share materials
and use MultiMesh or reusable packed scenes where practical.

## Standard versus paid editions

The free Standard archive contains 94 model files. The current pack page
advertises more than 200 models across the full pack. The paid Pro and Source
editions add worn variants and custom simple collisions; Source also includes
preconfigured engine projects and the Wizard's Den preview scene. Those paid
files are not included here.

## Source and license

- Official page: https://quaternius.com/packs/fantasypropsmegakit.html
- Download page: https://quaternius.itch.io/fantasy-props-megakit
- Archive: `Fantasy Props MegaKit[Standard].zip`, published 2025-06-02
- Retrieved: 2026-10-14
- Creator: Quaternius
- License: CC0 1.0
- Original archive SHA-256:
  `8b6f7e806d222e585478f0e1bdc6b271bbc7bc6f84dd6af8ca703a7c64f0cb1e`

The publisher's original license notice is preserved in `LICENSE.txt`.
