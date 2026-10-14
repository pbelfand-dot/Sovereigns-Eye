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

The repository includes the GLB version of each model, all required PNG textures,
and matching PNG previews. Duplicate FBX and OBJ versions from the source archives
were intentionally omitted to keep the Git repository small and avoid maintaining
multiple copies of the same mesh.

The Medieval Hexagon and Halloween packs were distributed as glTF plus external binary
and texture data. They were losslessly repackaged as self-contained GLB files for a
consistent import workflow; model geometry and materials were not redesigned.

The Quaternius Standard character test was distributed as glTF plus external binary
and texture data. Its two bodies and eight head-bone-rigged hair/eyebrow pieces were
also repackaged as self-contained GLBs. The source archive contained two texture URI
filename mismatches; the correct included PNG files were used while embedding the
textures so the resulting GLBs have no missing external dependencies.

The original license text distributed inside each pack is preserved verbatim in
[`licenses/`](licenses/) or the corresponding `alternatives/` option folder. The
complete file-by-file inventory is in [`ASSET_MANIFEST.csv`](ASSET_MANIFEST.csv).
