# Sovereign's Eye — 3D art plan (Quaternius direction)

**Target look:** sleek, textured, stylized fantasy (Quaternius). Not voxel, not blocky, not chibi.
Kenney, the blocky set and the KayKit alternatives stay in `3D/` as **reference only**. They are hidden from Godot with `.gdignore` and are never shipped.

This plan was written after inspecting:
- `3D/ASSET_MANIFEST.csv`: 1,242 models; 215 of them Quaternius.
- `3D/VALIDATION.json`: 1,242 / 1,242 valid, no missing dependencies.
- The Quaternius folder READMEs.
- `3D/research/SCALABILITY_ROADMAP.md`.

![Manor prefab](screenshots/prefab_manor.jpg) ![Town square](screenshots/town_square.jpg)

---

## 1. What the game uses now

| Library folder | What we use | Where in code |
|---|---|---|
| `environments/quaternius-medieval-village-standard/models/` (176 modules, 22 shared PNGs; folder kept whole) | Walls (plaster, uneven brick), corners, window walls with frames and shutters, doors, floors, tiled roofs, gable ends, tower roofs, chimneys, vines, balconies, crates, wagon. The brick and cobble textures also pave the roads and square. | `scripts/world/village_kit.gd`, recipes in `data/building_kit.json` |
| `character-tests/quaternius-universal-base-standard/models/` | Male and female bodies; Hair_SimpleParted, Long, Buns, Buzzed, BuzzedFemale; Hair_Beard; the eyebrows built into the bodies | `scripts/characters/human_model.gd`, `shaders/human_*.gdshader` |
| `animations/.../UAL1_Standard.glb` and `UAL2_Standard.glb` (**in-place**) | 84 clips mapped to villager activities | `data/animations.json` |
| `animations/.../*_RM.glb` (root motion) | **Not imported yet** (marked "skip"). Game code moves villagers, so the in-place clips are correct (rule 7). Root motion is reserved for cutscenes and scripted moves (rule 8). | — |

### Buildings: reusable prefabs

**Recipes.** Each building type is a data recipe made of blocks on the kit's 2 m grid:

- cells, stories (3 m each), wall set;
- roof type (tiles with a ridge direction, or a tower roof);
- door position, chimney, balcony, props.

There are 11 types with 1–3 variants each. Footprints in `data/buildings.json` match the recipes, and a test enforces that.

**Assembly.**
- A recipe is assembled **once** into a prefab, and every building of that type and variant reuses the same meshes.
- **Shell:** all walls, roof and window pieces are merged into one mesh with one surface per shared material. That is 5–9 draw calls per building instead of 60–150 loose pieces (rule 3).
- **Details:** shutters, vines and props sit in a second mesh. It has no shadows and is hidden beyond 90 m (rule 6).
- **Shared materials:** every module that uses `MI_Plaster`, `MI_RoundTiles` and so on ends up with the *same* Material object (rule 4).
- **Collision:** one box per block on collision layer 2 (rule 5).
- **Ground fit:** each building sits on the lowest corner of its footprint so no wall floats on a slope.
- **Fallback:** if the kit folder is missing, the old primitive buildings are used automatically, so the game never breaks.

### Villagers

**Body.**
- The body is chosen by gender and scaled by the villager's height and build. Children get proportionally larger heads.
- Hair and beard meshes are bound to the body skeleton by bone name.
- Hair, beard and eyebrows are recolored per villager from their data (auburn, blond, grey and so on).
- Skin tone is recolored the same way.

**Clothing (stopgap).** The free bodies ship in underwear, so clothing is painted on in each villager's outfit colors: tunic, robe, gown, mail with tabard, apron, or fine doublet. A shader reads smooth body coordinates baked once per body. **This is a stopgap**; see §3. It reads as tight-fitting clothes on athletic bodies.

**Animation.**
- Walk, idle, talk and job-specific work clips: farmers harvest, plant and water; woodcutters chop; priests use the spell idle; knights drill with sword combos.
- Each villager picks from a list by id, so the crowd doesn't move in lockstep.
- The pelvis motion is rescaled per body so feet stay on the ground.

**Performance.**
- Each villager costs one material and per-instance colors; no material copies.
- The animation library is shared.
- Body LODs are generated at load.

**Fallback.** If the files are missing, the old primitive bodies are used.

### Ground: meadow shader (no assets needed)
- `shaders/terrain_meadow.gdshader` turns the flat green terrain into a meadow. It adds:
  - sunlit and lush patches
  - grass clumps that catch the light
  - fine grain
  - occasional bare earth
  - drifts of wild flowers
- `scripts/world/ground_wear.gd` bakes a 512 px mask from the layout. The grass wears down along roads, around the square, at doorsteps and along field fences.
- All numbers are in `data/art_style.json` → `terrain`.
- Before/after: `docs/screenshots/ground_before_after.jpg`.
- Works on the Forward+, Mobile and Compatibility renderers.
- Real 3D grass tufts, flowers and rocks still come from the Nature MegaKit (section 3).

### Import settings (committed `.import` files)
- Village and body textures: VRAM compressed with mipmaps, capped at **1024 px**; eyes 256, vines 512. That's plenty for a strategy camera and keeps downloads around 50 MB.
- Hair GLBs discard their duplicated embedded textures. All hair shares the two hair texture sheets extracted from the bodies.
- The root-motion files, `Mannequin_F.glb` and `ASSET_MANIFEST.csv` are set to `importer="skip"`: not imported and not exported.

---

## 2. How the assets fit the game's progression

| Stage | Readiness | What carries it | What it still needs |
|---|---|---|---|
| **Tiny town** (Phase 1, now) | **Playable** | Village kit prefabs, 2 bodies + hair, 84 clips; Peasant/Ranger outfit sampler acquired | Integrate real clothing; trees and props |
| **Large village** | Mostly | Larger recipes (2–3 stories, overhangs, balconies); more variants per type | Markets, workshops, furniture, crops, vegetation, population variety |
| **Town / city districts** | Partial | Dense multi-story blocks from the same modules. Prefabs + MultiMesh instancing for repeated houses | Civic landmarks, wealth tiers, signage, plazas; district streaming (§4) |
| **Kingdom / capital** | Missing | Residential/commercial districts only | Palace/keep, monumental walls and gates, towers, barracks, temples, throne room, bridges |
| **Harbor and ships** | Missing | Crates and wagon for early dock dressing only | Docks, piers, cranes, ropes, sails, cargo, ship interiors, several ship classes |

The order to acquire is: clothing → nature → props → bodies and hair variety → town landmarks → kingdom → harbor/ships. Each step has a matching Quaternius pack, so the art never drifts out of one family.

---

## 3. Missing models: flagged, not silently replaced (rule 10)

Prices were checked on Quaternius's itch.io pages on 2026-10-14. All of these packs are CC0.

| Gap (what you see in game today) | Fix | Edition / price | Priority |
|---|---|---|---|
| **Clothing.** Painted-on clothes over athletic underwear bodies | **Modular Character Outfits – Fantasy**: free sampler now acquired (4 Peasant/Ranger outfits + 20 modular pieces); full Source has 12 outfits and 62 parts | **Standard: acquired**; Source $20 | **1 — integrate sampler; Source only if its extra variety is needed** |
| **Body variety.** Only "Superhero" proportions, so children look like small adults | **Universal Base Characters Source**: 6 bodies (Superhero, Regular, Teen × male/female), 20 hairstyles, eye and skin color shaders | $19.99 (we have the free Standard) | 2 |
| **Trees, bushes, rocks, grass, crops.** Still primitive placeholders | **Stylized Nature MegaKit**: 116 models, 7 leaf types | **Standard: free** (68 models); Pro $9.99; Source $14.99 | 3 — free Standard first |
| **Market stalls, well, benches, barrels, forge, anvil, bread oven, tavern sign, hand tools.** Primitives or missing | **Fantasy Props MegaKit**: 211 props | **Standard: free** (94 models); Pro $9.99; Source $14.99 | 4 — free Standard first |
| More village modules (304 vs 176) and ready-made collisions | Medieval Village MegaKit Source | Pro $9.99 / Source $14.99 | 5 |
| **Windmill.** Kit tower plus simple boards in the kit's wood material | Ultimate Fantasy RTS (selected landmarks) or a custom model | free / custom | 6 |
| **Chapel / temple.** Built from village walls and a tower roof | Church/temple pieces: custom, or a future Quaternius kit | — | 6 |
| **Barracks / military.** Plain stone hall, no crenellations or racks | Castle/military pieces in this style | — | 7 |
| **Hats, helmets, crowns.** Not shown in 3D (portraits still describe them) | Outfit pack accessories | (in the outfits pack) | with 1 |
| **Palace, keep, walls, gates, throne room** | Ultimate Modular Ruins (damaged areas), plus a custom or new kit for intact royal architecture | — | kingdom phase |
| **Docks, ships** | Pirate Kit (71 models) as the starting point; review against the village kit first | — | harbor phase |

**Budget.**
- All the free Standard editions: **$0**.
- Every Source edition above: about **$85** one-time.
- Alternatively, Quaternius's Patreon is $10/month for one Source key per month.

**Remaining free downloads.** The outfit sampler is now in `3D/characters/`. The other free Standard packs still to acquire are:

1. Nature.
2. Props.
3. Optionally, the Source bodies.

Next, wire in the acquired outfit sampler to replace painted clothes; nature will
replace the primitive trees, and props will fill the square and workshops after those
packs are acquired.

---

## 4. Scaling plan

**LOD and detail.**
- Building details already cull at 90 m, and body LODs are generated at load.
- Next: a distant **silhouette mesh** per prefab (walls + roof only, merged, roughly 5% of the triangles), swapped in through visibility ranges past about 150 m.
- Villager animation already only runs while the villager is visible. At city scale, far crowds update every Nth frame.

**District streaming (town and capital).**
- The map is split into district chunks, each a scene: road mesh, prefab instances (MultiMesh for repeated houses) and collision boxes.
- Chunks within the camera radius are loaded on a background thread (`ResourceLoader.load_threaded_request`).
- Far chunks show one merged "HLOD" silhouette mesh per district.
- Interiors are separate scenes, loaded only when the camera enters a building.
- Characters always exist as data (already true). Only those near the camera get bodies.

**Ships (rule 9).** Each ship class is five separate scenes:
1. exterior hull;
2. walkable deck with its own navigation;
3. interior (streamed in on boarding);
4. collision proxies;
5. distant silhouette.

A ship is a moving parent node, so crew stay parented to the deck while it sails.

**Grid discipline.** All recipes use the kit's 2 m grid and 3 m stories. New packs must snap to the same grid so buildings from different packs line up.

---

## 5. Where things live

```
3D/                                   asset library (unchanged layout)
  environments/quaternius-medieval-village-standard/   used: village kit
  character-tests/quaternius-universal-base-standard/  used: bodies + hair
  animations/quaternius-universal-animation-library-*  used: in-place clips
  alternatives/, characters/, castle-kit/, fantasy-town-kit/, previews/, tools/, research/, licenses/
                                       .gdignore'd (reference only, never shipped)
data/building_kit.json                building recipes + list of missing pieces
data/animations.json                  activity -> clip mapping
scripts/world/village_kit.gd          prefab assembly, shared materials, paving, night glow
scripts/characters/human_model.gd     Quaternius villagers
shaders/human_body.gdshader           skin tone + painted clothing (stopgap)
shaders/human_hair.gdshader           hair/beard/eyebrow color
tools/prefab_gallery.tscn             renders every prefab and a villager lineup to PNG
tests/test_art_pipeline.gd            footprints, prefab merging, shared materials, bodies, in-place clips
```
