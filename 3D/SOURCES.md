# Asset sources

Retrieved on 2026-10-13 from the original publishers, Kenney, KayKit, and Quaternius.

| Collection | Source page | Pack version | License | Included |
| --- | --- | --- | --- | ---: |
| Blocky Characters | [kenney.nl/assets/blocky-characters](https://kenney.nl/assets/blocky-characters) | 2.0 | CC0 1.0 | 18 GLB models |
| Castle Kit | [kenney.nl/assets/castle-kit](https://kenney.nl/assets/castle-kit) | 2.0 | CC0 1.0 | 76 GLB models |
| Fantasy Town Kit | [kenney.nl/assets/fantasy-town-kit](https://kenney.nl/assets/fantasy-town-kit) | 2.0 | CC0 1.0 | 167 GLB models |
| KayKit Adventurers | [github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) | 1.0 | CC0 1.0 | 5 GLB models |
| KayKit Skeletons | [github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) | 1.0 | CC0 1.0 | 4 GLB models |
| Graveyard Kit | [kenney.nl/assets/graveyard-kit](https://kenney.nl/assets/graveyard-kit) | 5.0 | CC0 1.0 | 91 GLB models |
| Platformer Kit | [kenney.nl/assets/platformer-kit](https://kenney.nl/assets/platformer-kit) | current download | CC0 1.0 | 153 GLB models |
| Mini Characters | [kenney.nl/assets/mini-characters](https://kenney.nl/assets/mini-characters) | current download | CC0 1.0 | 26 GLB models |
| KayKit Dungeon Remastered | [github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0) | 1.0 | CC0 1.0 | 203 GLB models |
| KayKit Medieval Hexagon | [github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0) | 1.0 | CC0 1.0 | 221 GLB models |
| KayKit Halloween Bits | [github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0](https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0) | 1.0 | CC0 1.0 | 63 GLB models |
| Universal Base Characters | [quaternius.com/packs/universalbasecharacters.html](https://quaternius.com/packs/universalbasecharacters.html) | Standard (free) | CC0 1.0 | 10 GLB models |
| Modular Character Outfits — Fantasy | [quaternius.com/packs/modularcharacteroutfitsfantasy.html](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) | Standard (free sampler) | CC0 1.0 | 4 complete outfits + 20 modular parts |
| Universal Animation Library | [quaternius.com/packs/universalanimationlibrary.html](https://quaternius.com/packs/universalanimationlibrary.html) | Standard (free), 2026-06-16 update | CC0 1.0 | 2 GLB animation containers |
| Universal Animation Library 2 | [quaternius.com/packs/universalanimationlibrary2.html](https://quaternius.com/packs/universalanimationlibrary2.html) | Standard (free), 2026-06-16 update | CC0 1.0 | 2 GLB animation containers + 1 mannequin |
| Medieval Village MegaKit | [quaternius.com/packs/medievalvillagemegakit.html](https://quaternius.com/packs/medievalvillagemegakit.html) | Standard (free) | CC0 1.0 | 176 JSON glTF models + shared textures |
| Stylized Nature MegaKit | [quaternius.com/packs/stylizednaturemegakit.html](https://quaternius.com/packs/stylizednaturemegakit.html) | Standard (free) | CC0 1.0 | 68 JSON glTF models + shared textures |
| Fantasy Props MegaKit | [quaternius.com/packs/fantasypropsmegakit.html](https://quaternius.com/packs/fantasypropsmegakit.html) | Standard (free) | CC0 1.0 | 94 JSON glTF models + shared textures |

The repository includes a single glTF 2.0 version of each model, all required PNG
textures, and available previews. Duplicate FBX and OBJ versions from the source
archives were intentionally omitted to keep the Git repository small and avoid
maintaining multiple copies of the same mesh.

The Medieval Village MegaKit remains in its source JSON glTF + BIN layout so its
22 high-resolution texture maps can be shared by all 176 modules. Converting every
piece to a self-contained GLB would duplicate those maps hundreds of times.

The Medieval Hexagon and Halloween packs were distributed as glTF plus external binary
and texture data. They were losslessly repackaged as self-contained GLB files for a
consistent import workflow; model geometry and materials were not redesigned.

The Quaternius Standard character test was distributed as glTF plus external binary
and texture data. Its two bodies and eight head-bone-rigged hair/eyebrow pieces were
also repackaged as self-contained GLBs. The source archive contained two texture URI
filename mismatches; the correct included PNG files were used while embedding the
textures so the resulting GLBs have no missing external dependencies.

The Quaternius Modular Character Outfits Standard archive was retrieved on
2026-10-14. It is a free sampler containing four complete Peasant/Ranger outfits and
20 separate pieces, not the 12 outfits and 62 parts in the paid Source edition. Its
Godot/Unreal JSON glTF files are retained, with their duplicate texture folders
consolidated into one shared directory and two supplied color variants preserved.

The Quaternius Stylized Nature MegaKit Standard archive was retrieved on
2026-10-14. It contains 68 of the full pack's 116 models. The archive's JSON glTF
and BIN files are retained, duplicate FBX/OBJ geometry was omitted, and the shared
textures were moved into one directory with the image URIs updated accordingly.

The Quaternius Fantasy Props MegaKit Standard archive was retrieved on
2026-10-14. It contains 94 model files from the full 200+ model collection. The
archive's JSON glTF and BIN files are retained, duplicate FBX/OBJ geometry was
omitted, and the shared textures were moved into one directory with the image
URIs updated accordingly. The alternate Unreal normal maps are retained but are
not referenced by the glTF files.

The original license text distributed inside each pack is preserved verbatim in
[`licenses/`](licenses/) or the corresponding `alternatives/` option folder. The
complete file-by-file inventory is in [`ASSET_MANIFEST.csv`](ASSET_MANIFEST.csv).
