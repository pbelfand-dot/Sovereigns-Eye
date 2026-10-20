# Sovereign's Eye — notes for coding assistants

Godot 4.7, GDScript only. Medieval dynasty sim built around an "Appraisal"
skill (current vs. hidden potential). Read `docs/ARCHITECTURE.md` first.

## Commands
- Tests: `tools/run_tests.sh` (or `godot --headless --path . res://tests/test_runner.tscn`).
  On a fresh clone run `godot --headless --path . --import` once so `class_name`s resolve.
- Village census for a seed: `godot --headless --path . --script res://tools/print_village.gd -- <seed>`
- Screenshots (needs a display): `godot --path . res://tools/capture.tscn -- <seed> <out_dir>`
- One test suite: `TEST_FILTER=recruitment tools/run_tests.sh`
- Who'd join for what (tuning `data/recruitment.json`): `godot --headless --path . --script res://tools/recruit_report.gd -- <seed>`
- Gameplay video (needs a display): `godot --path . --resolution 1280x720 --write-movie out.avi --fixed-fps 30 res://tools/gameplay_demo.tscn -- <seed>` (charters: `tools/charter_demo.tscn`)
- Villagers' remarks as the heir walks past (needs a display): `godot --path . --resolution 1600x900 res://tools/capture.tscn -- <seed> <out_dir> barks`; the lines are in `data/barks.json`.
- The Eye's reveal, each tier at its beats (needs a display): `godot --path . --resolution 1280x720 --fixed-fps 30 res://tools/capture.tscn -- <seed> <out_dir> eye` (`EYE_TIERS=legendary`, `EYE_CALM=1`). Its bells and music: `python3 tools/audio/make_stings.py` (then `--import` and `python3 tools/audio/build_audio_manifest.py`).
- Title screen art (key art + emblem, rendered from the game into `assets/ui/menu/`, needs a display): `godot --path . --resolution 2560x1440 res://tools/key_art.tscn` (`-- 9 <dir> preview` for candidate views, `-- 9 res://assets/ui/menu/ emblem` for the emblem only; see `assets/ui/menu/README.md`).
- Charter pacing (steward bot, data only): `godot --headless --path . --script res://tools/charter_sim.gd -- <seed> [days]`
- The years (Phase 4, data only): `godot --headless --path . --script res://tools/life_sim.gd -- <seed> [years] [steward] [matches] [heirs]` (population, births, deaths, weddings, trades, rulers; `matches` accepts suitors of B rank or better, `heirs` names the most gifted child heir); a card and the chronicle after some years (needs a display): `LIFE_YEARS=16 godot --path . --resolution 1600x900 res://tools/capture.tscn -- <seed> <out_dir> life`. Numbers: `data/life.json`.
- The house's matches (needs a display): `godot --path . --resolution 1600x900 res://tools/capture.tscn -- 12345 <out_dir> matches` (a suitor in talk, the Court panel's Marriages, a kin's match list). Numbers and lines: `data/matches.json`.
- Raids (needs a display): `BATTLE_SPEED=2 godot --path . --resolution 1600x900 --fixed-fps 30 res://tools/capture.tscn -- 12345 <out_dir> battle` (the Defence panel, the line, the charge, the melee, the report; `BATTLE_LEVY=1`); live fights against the captains' odds (headless): `godot --headless --path . res://tools/capture.tscn -- 1 <out_dir> battle_stats` (`BATTLE_SEEDS=1,2`; `BATTLE_KEEP=stone` at the house's castle, `BATTLE_HOST=1` against a noble house's host). Numbers: `data/military.json`.
- The wider realm (needs a display): `godot --path . --resolution 1600x900 res://tools/capture.tscn -- 12345 <out_dir> realm` (the realm map, a visit with the young seen with the Eye, a house, a camp, a camp fight's report, the Defence section). Numbers: `data/realm.json`, camps in `data/military.json`.
- The house's castle and the houses at war (needs a display): `godot --path . --resolution 1600x900 res://tools/capture.tscn -- 12345 <out_dir> keep` (the Court panel's Castle section, the motte and bailey rising and standing, the stone castle rising and standing, a host's demand with allies sent, the host on the realm map, the fight before the gate, the report; `KEEP_ONLY=fight` draws only the fight). Numbers: `data/castle.json`, houses in `data/realm.json` (`rivals`, `aid`, `hosts`); pacing with `tools/charter_sim.gd` (its steward raises the castle).
- Succession (needs a display): `godot --path . --resolution 1600x900 res://tools/capture.tscn -- 9 <out_dir> succession` (the family tree after `SUCC_YEARS` (60) years, a year let pass, a child lord's regency). Numbers: `data/succession.json`.
- 3D assets: original families live in `3D/<category>/<family>/` (see `3D/BACKLOG.md`); build with Blender 4.2 as `bpy` (`/root/bpy-venv/bin/python 3D/props/village-commons/source/build_commons.py --export`), check with `godot --headless --path . --script res://tools/asset_check.gd -- res://3D/props/village-commons/models/`, see them in game with `godot --path . res://tools/capture.tscn -- <seed> <out_dir> commons` (or `farm`, `square`, `smithy`, `home`, `thatch`, `training`, `chapel`, `castle`, `harbour`), then `python3 3D/tools/build_asset_manifest.py`. Clothing on villagers: `godot --path . res://tools/prefab_gallery.tscn -- <out_dir> wear` (Status Wear lineup; `WEAR_MODE=walk` for mid-stride; `bodies` for age and build).

## Rules
- Keep data and presentation separate: game state lives in `CharacterData`,
  `FamilyData`, `BuildingData`, `VillageLayout`, `WorldState` (all `RefCounted`
  with `to_dict`/`from_dict`). Nodes read/write them; nodes never own game data.
- Tunable numbers belong in `data/*.json`, read through `GameData`.
- Generation must be deterministic: use `Seeds.rng(world_seed, "<stream>")`,
  `Seeds.pick/shuffle/chance`; never global `randf()`, `randi()`,
  `Array.shuffle()` or `pick_random()` in generation code.
- JSON stores numbers as floats: cast with `int()` in `from_dict`.
- Current ability must never exceed potential: always go through
  `CharacterData.set_attribute()` / `train()`.
- New save fields: bump `WorldState.SAVE_VERSION` and handle old saves in
  `SaveManager.migrate()`.
- Godot front faces are clockwise; procedural meshes here are viewed from above.
- Vertex/instance colors are sRGB: use `Mats.vertex_colored()`.
- Add a test in `tests/` for new systems; keep all tests green.
- Implement only the current phase; don't build future systems early.
