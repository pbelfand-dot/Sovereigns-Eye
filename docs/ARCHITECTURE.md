# Architecture (Phase 2)

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
          ├ VillageLayoutGenerator   │  layout, families, characters, clock
          ├ CharacterGenerator       │
          │  └ TalentRoller          │
          └ CourtSystem.initialize   ▼
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
| Noble society | `scripts/court/court_system.gd`, `house_data.gd`, `data/court.json` | Selects the playable heir, tracks the house treasury and renown, and owns recruitment, offices, training, wages, loyalty, departures and knighthood. Court fields serialize on `WorldState` and `CharacterData`. |
| NPC behaviour | `scripts/ai/npc_brain.gd`, `scripts/characters/npc.gd` | Schedule block (sleep/home/work/leisure/play) → queue of steps (go / enter / stay). Work styles: stationary, fields, patrol, drill, market, forest, estate, assist. Traits bias leisure (gregarious → tavern, devout → chapel). |
| Mood | `scripts/ai/mood_system.gd` | Daily drift toward a target built from labelled factors (shown on the card). Stress changes hourly with activity. |
| Navigation | `scripts/world/road_graph.gd` | A* over road centerlines + square ring + door nodes. `find_path(from, to)` is the only API the brain uses, so a navmesh can replace it later. |
| Camera | `scripts/world/strategy_camera.gd` | Smooth pan/zoom/rotate; mouse, keyboard and macOS trackpad gestures; follow mode. |
| UI | `scripts/ui/*` | Built in code from one theme (`ui_theme.gd`). The card's portrait is a live render of the character's own 3D model. |
| Saving | `scripts/persistence/save_manager.gd` | Versioned JSON, written to a temp file then renamed (crash-safe). Version 1 saves migrate to Phase 2 by deterministically creating their player house and opinions. |

## Time

1 in-game hour = 40 real seconds at 1x (a day is 16 minutes). Speeds are 1x,
2x, 4x and 8x. A year has 4 seasons of 30 days and starts in Spring 1187.

## Extension points for later phases

* **Phase 3 (economy):** buildings are data with ids, workers and residents;
  add production per building type in `data/buildings.json`.
* **Phase 5 (military):** combat/leadership already exist; `train()` grows
  current toward potential.
* **Phase 6 (dynasties):** `TalentRoller.inheritance_affinity()` already
  biases children toward parents' talents; `FamilyData` tracks households.
* **Off-screen simulation:** `NPCBrain` only needs a body for movement; a
  lightweight "abstract" brain can tick CharacterData directly for people in
  other settlements.
