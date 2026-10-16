# Architecture (Phase 3, step 2)

The core rule: **data is separate from presentation.** Every person,
building and road exists as plain data first (`RefCounted` classes that know
how to save themselves). Nodes in the 3D world only *display* that data and
write live state (positions, activities) back into it. That's what lets the
game grow to hundreds of notable characters later: most of them can live as
data off-screen with no body spawned.

```text
           data/*.json  (tunable design data)
                 │  GameData (static, cached)
                 ▼
 seed ──► WorldGenerator ──► WorldState ◄──────── SaveManager (JSON in user://saves)
          ├ VillageLayoutGenerator   │  layout, families, characters, clock,
          ├ CharacterGenerator       │  house, territory (stores + sites)
          │  └ TalentRoller          │
          ├ CourtSystem.initialize   │
          └ TerritorySystem.initialize ▼
                              VillageWorld (scenes/world/world.tscn)
                 ┌───────────────┼────────────────┬───────────────┐
           VillageBuilder     RoadGraph        NPC × N          GameUI
           (terrain, roads,   (A* over roads,  ├ CharacterModel  ├ CharacterCard (+ PortraitStudio)
            buildings, trees) doors, square)   └ NPCBrain        ├ LedgerPanel, menus, toasts
                                                  └ MoodSystem   ├ uses Appraisal.appraise()
                                                                └ CourtPanel / Court tab
```

## Systems

| System | Files | Notes |
|---|---|---|
| Design data | `data/*.json`, `scripts/core/game_data.gd` | Ranks, odds, occupations, traits, names, buildings, schedules. Nothing is hard-coded in scripts. |
| Determinism | `scripts/core/seeds.gd` | One master seed; each step uses its own derived RNG stream (`Seeds.rng(seed, "talent")`). Never use the global `randf()` in generation. Seeds stay below 2^31 so JSON can't corrupt them. |
| World state | `scripts/core/world_state.gd` | The whole save: seed, clock (minutes since day 1), layout, families, characters. |
| Village layout | `scripts/world/village_layout_generator.gd`, `village_layout.gd`, `building_data.gd` | Square, four roads (north to the manor), farms with lanes and fields, roadside buildings facing the road, forest density by distance. Pure data, saved with the game. |
| 3D village | `village_builder.gd`, `building_factory.gd`, `mats.gd`, `terrain_height.gd` | Builds from the layout. Buildings use a `.glb` if `data/buildings.json` points to one; otherwise primitives. Materials/meshes are cached. Trees and crops use MultiMesh. |
| Characters | `scripts/characters/character_data.gd`, `family_data.gd` | Identity, attributes `{current, potential}` (current is always clamped ≤ potential), traits, mood, relationships, history, appearance, live state. |
| Generation | `character_generator.gd` | Households from `data/backgrounds.json` → fill to 50 → jobs → homes/workplaces → traits & looks (children resemble parents) → talents (children after parents) → relationships → histories with "rumor" hints → starting mood. |
| Appraisal | `scripts/appraisal/appraisal.gd`, `talent_roller.gd` | `Appraisal.appraise(character, level)` returns a report; the UI only reads reports, so weaker appraisal, fog of war or concealment magic only touch this one function. |
| Noble society | `scripts/court/court_system.gd`, `house_data.gd`, `data/court.json` | Selects the playable heir, tracks the house treasury and renown, and owns offices, training, wages, loyalty, departures and knighthood. Court fields serialize on `WorldState` and `CharacterData`. |
| Recruitment | `scripts/court/recruitment.gd`, `data/recruitment.json` | Motive-based, no dice. `motives()` weighs fondness, money, home, advancement and standing against ties and caution, from who someone is. `ask()` reveals motives in words. `evaluate()` scores a concrete offer (wage, home or promise, position, appeal) with plain-language reasons; `can_offer()` is true for everyone but you, your kin and children under 10; `propose()` answers accept / counter / refuse (no lockout after a refusal; for retainers it weighs new terms against `current_terms()`). `accept()` applies real terms (`CharacterData.terms`, `agreed_wage`, `title`; families move home; workplaces fill). `daily_update()` keeps or breaks promises and moves `HouseData.standing`. Save v6. |
| Walking as the heir | `scripts/world/heir_controller.gd`, `world_geometry.gd`, `data/controls.json` | `HeirController` moves the heir from WASD, the left stick, the touch stick or click-to-move, in real time and camera-relative. `WorldGeometry` is the solid world: buildings and sites (boxes), trunks and props (circles), the map edge, and sightlines (`line_blocked`). `VillageWorld` has two modes: "walk" (focus on the person you face; Q = `use_eye`, E = `try_talk`) and "overview" (the map table). |
| The Sovereign's Eye | `scripts/appraisal/discovery.gd`, `scripts/ui/eye_reveal.gd`, `reveal_card.gd`, `eye_emblem.gd`, `data/eye.json`, `data/dialogue.json` | `Discovery.scan_check()` (near, outdoors, in sight) gates the Eye; `talk_check()` gates conversation. `EyeReveal` plays a tier's step list. `NegotiationPanel` is the conversation: talk, ask, offer, answer. |
| Territory (Phase 3) | `scripts/territory/territory_system.gd`, `territory_data.gd`, `construction_site.gd`, `data/territory.json` | Stores (food/wood/stone; gold stays `HouseData.gold`), daily production by occupation × mood × season, consumption, storage caps. Building orders: `snap()` beside the nearest road, `check_placement()` (roads, square, buildings, sites, fields, props, door, lane), `place()` pays, lays a lane road, fells trees/rocks, opens a `ConstructionSite` with a reserved building id and a crew. `advance()` adds builder-hours during work shifts × Master of Works; `complete()` adds the `BuildingData` to the layout, lays fields, hires workers. Saved on `WorldState.territory` (save v3). |
| Growth (Phase 3, step 2) | `scripts/territory/growth_system.gd`, `data/territory.json` ("homes", "growth") | Appeal factors fill `TerritoryData.settler_progress`. `settle()` brings a family to an empty home through `CharacterGenerator.settle_family()`, which runs the founding generator's steps (names, looks, traits, talents, family ties, histories) on its own seeded streams. When every home is full, `order_home()` opens a "home" site on the best road-side spot (`best_home_spot`). Homes whose `home_needs()` are all met get an "upgrade" site that raises `BuildingData.tier`. Rent adds to `CourtSystem.daily_income`, and home level adds a mood factor. |
| Charters (Phase 3.3) | `scripts/territory/charter_system.gd`, `data/charters.json` | `TerritoryData.charter` (0 Hamlet .. 3 Town, save v7). `requirements()` / `can_petition()` / `petition()` (pays the fee, raises banners via `raise_banners()`). The charter sets `max_population` (used by `GrowthSystem.at_capacity`), `build_radius` (home and building spot search), dues and Market Hall trade (`CourtSystem.daily_income`), the retainer cap, appeal and mood factors, and building limits (`limit_for()` reads a buildable's `limits` per charter). Townhouses take lodgers by charter (`GrowthSystem.family_capacity` / `homes_with_room`). |
| Village Commons (art) | `3D/props/village-commons/`, `scripts/world/prop_kit.gd`, `shaders/banner_wind.gdshader`, `data/props.json` "by_charter" | The well, charter banners and signposts are the game's own models (built in Blender from `source/build_commons.py`). `PropKit.commons_model(type, charter)` picks the tier; `VillageBuilder._build_props` places the well whole (keeps its LODs) and merges banners and signposts with the props; a banner whose arm would reach into a building is mirrored (`_arm_blocked`). Banner cloth uses the wind shader (sway weight in UV2, translucent). `petition_charter` → `refresh_props()` swaps them. Checked by `tools/asset_check.gd` and `tests/test_commons.gd`. |
| Farm & Field (art) | `3D/props/farm-field/`, `scripts/world/farm_kit.gd`, `data/farm.json`, `data/props.json` "roots"/"variants" | `VillageBuilder.add_field` hands each field to `FarmKit.build_field`: a furrowed soil bed (one SurfaceTool mesh, vertex colours), the crop as one MultiMesh (grain in 2 m row segments, heads on a jittered grid; tinted per plant, no shadows, fades out at `crop_visibility_range`), a fence MultiMesh by charter (`fence_layout`: 2 m segments stretched to fit, facing out) with its gate on the side facing the farmhouse, and sometimes a scarecrow. Placement is seeded from the field's position (`Seeds.rng`), so a redraw never re-rolls it. Haystacks and lumber pick a model by position from `props.json` "variants" (`PropKit.variant_model`) and merge with the props. `VillageLayoutGenerator` gives them reserved yard spots clear of walls, fields and roads (`YARD_HALF`); loading an older save (v7) drops any stack whose footing reaches into a building (`SaveManager.migrate`, `VillageLayout.yard_spot_clear`; save v8), and building dressing keeps off them. Models are named `farm:NAME`, resolved through `props.json` "roots". `petition_charter` → `refresh_fields()` swaps the fences. Without the models the old simple shapes are drawn. Checked by `tests/test_farm.gd`. |
| Market Square (art) | `3D/props/market-square/`, `scripts/world/village_builder.gd` (`_square_edge`, `square_edge_transforms`), `data/props.json` "square_edge", "by_charter", "whole" | The square's rim is a kerb of 1.5 m pieces by charter (rubble edging, dressed kerb, two stone steps), laid as one MultiMesh round the paving; pieces either side of a road are cut short to stop just clear of it. `VillageLayoutGenerator.square_furniture` reserves the market cross's spot and the trough beside the well (`square_spot`: the angle furthest from stalls, benches, banners and the walk in from each road; no randomness, so save v9 migration adds them to older villages the same way). The cross's "by_charter" entry is empty before Market Town: `PropKit.present()` keeps it out of the drawing and out of `WorldGeometry` until then. Centrepieces in "whole" (well, cross) keep their LODs. `petition_charter` → `refresh_square()` and `refresh_props()` swap them. Checked by `tests/test_square.gd`. |
| Smithy (art) | `3D/props/smithy/`, `VillageLayoutGenerator.smithy_yard`, `data/props.json` "by_charter" "forge", "sets" "forge_yard_*" | Each smithy gets a forge yard against its right wall (else left, else back) where it's clear of buildings, the square, roads, fields, props and trees (no randomness; save v10 adds it to older villages and moves barrels out of it). The "forge" layout prop's `by_charter` entry is a `set:` (`PropKit.set_ready`): the yard's models are placed as a set and merged with the props: a village hearth (Hamlet, Village) or a town forge with a grindstone (Market Town, Town). Its embers are emissive (`KHR_materials_emissive_strength`, written by `gltf_pack.py`). One walking obstacle (`controls.json` props "forge"). Checked by `tests/test_smithy.gd`. |
| Home Yard (art) | `3D/props/home-yard/`, `VillageBuilder.dressing_items`, `PropKit.dressing_set`, `VillageLayoutGenerator.dressing_clear`, `data/props.json` "dressing" cottage/farmhouse, "sets" "home_*", "yard_half" | A cottage's dressing entries name sets by level (`home_door@tier` → `home_door_<t>` for the highest t up to the home's tier; an empty set means none). A set with a footprint (`yard_half`) is drawn only where the whole rectangle is clear of other buildings and new sites, the square, roads, fields, trees, farm and forge yards and the yards already placed (separating-axis `rects_overlap`); a set listed twice is a second choice of spot. Chances are rolled per building, nothing is saved, and an upgrade redraws the props. The hen house, water butt and chopping block are walking obstacles for the heir: `dressing_items` notes them in `VillageLayout.dressing_obstacles` (runtime only) and `WorldGeometry.resolve` pushes out of them. |
| Status Wear (art) | `3D/characters/status-wear/`, `scripts/characters/outfit_kit.gd`, `human_model.gd`, `data/outfits.json` "roots", "headwear", "aprons" | Headwear and aprons skinned to the outfit pack's rig, merged into each villager's outfit mesh like the pack's parts (`"wear:NAME"` parts; bones remapped by name if a skin differs). `OutfitKit.look_for` adds the occupation's headwear, fitted to short or long hair (a bun is let down under a hat; helmet, veil and hood hide the hair; a man's veil becomes a cap) and an apron for apron trades (leather or linen). The cap's felt follows the clothing colour (four colorway atlases). The look's `headwear` and `apron` also feed the portrait prompt, so the painting matches the model. |
| Home levels | `VillageKit.tier_recipe()`, `data/building_kit.json` "home_tiers" | A tier adds stories to the door block. Every tier rolls from the base prefab's seed, and vines use their own random stream, so floors a house already has come out piece for piece the same. `ConstructionView` keeps those pieces and rebuilds the rest. |
| Construction look | `scripts/world/construction_view.gd`, `build_ghost.gd` | `ConstructionView` re-assembles the kit prefab's own pieces (`VillageKit.prefab()["parts"]`) bottom-up inside a scaffold, in a few steps. `BuildGhost` is the translucent green/red placement preview with its lane. `VillageBuilder.refresh_ground()` re-bakes wear and re-filters (never re-rolls) cached grass, so the rest of the meadow stays put. |
| NPC behaviour | `scripts/ai/npc_brain.gd`, `scripts/characters/npc.gd` | Schedule block (sleep/home/work/leisure/play) → queue of steps (go / enter / stay). Work styles: stationary, fields, patrol, drill, market, forest, estate, assist. Traits bias leisure (gregarious → tavern, devout → chapel). |
| Mood | `scripts/ai/mood_system.gd` | Daily drift toward a target built from labelled factors (shown on the card). Stress changes hourly with activity. |
| Navigation | `scripts/world/road_graph.gd` | A* over road centerlines + square ring + door nodes. `find_path(from, to)` is the only API the brain uses, so a navmesh can replace it later. |
| Camera | `scripts/world/strategy_camera.gd` | "follow": close and elevated behind the heir, orbit by drag / right stick / arrows, rises over roofs in the way (`obstruction`). "strategy" (map table): smooth pan/zoom/rotate; mouse, keyboard, controller and macOS trackpad gestures. |
| Input | `scripts/core/input_setup.gd`, `scripts/ui/touch_controls.gd`, `touch_stick.gd`, `touch_button.gd` | Keyboard and controller bindings in one table; on-screen stick and buttons for touch (multi-finger). |
| Picking | `VillageWorld.pick_npc()`, `pick_building()` | Villagers by their projected outline. Buildings by a ray against each building's box, so clicking a roof picks its house. `BuildingCard` shows residents, workers, output and a home's checklist for its next level. |
| UI | `scripts/ui/*` | Built in code from one theme (`ui_theme.gd`). The card's portrait is a live render of the character's own 3D model. |
| Saving | `scripts/persistence/save_manager.gd` | Versioned JSON, written to a temp file then renamed (crash-safe). Version 1 saves migrate to Phase 2 by deterministically creating their player house and opinions; version 2 saves get the Phase 3 starting stores. |

## Time

1 in-game hour = 40 real seconds at 1x (a day is 16 minutes). Speeds are 1x,
2x, 4x and 8x. A year has 4 seasons of 30 days and starts in Spring 1187.

## Extension points for later phases

* **Phase 3 step 3 (charters):** Hamlet → Village → Market Town → Town gates
  on population and buildings. `TerritoryData.built` records what the player
  raised.
* **Phase 5 (military):** combat/leadership already exist; `train()` grows
  current toward potential.
* **Phase 6 (dynasties):** `TalentRoller.inheritance_affinity()` already
  biases children toward parents' talents; `FamilyData` tracks households.
* **Off-screen simulation:** `NPCBrain` only needs a body for movement; a
  lightweight "abstract" brain can tick CharacterData directly for people in
  other settlements.
