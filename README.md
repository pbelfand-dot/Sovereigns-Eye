# Sovereign's Eye

A stylized 3D medieval dynasty simulator built around one power: **Appraisal**.
You can see what no one else can — every person's current ability *and* their
hidden maximum potential. Somewhere in your village is a 14-year-old farmhand
with S+ Leadership. Find them.

> **Status: Phase 2 first playable** (internal codename "Project Appraisal").
> Godot 4.7 · GDScript · Quaternius village kit and characters (see [docs/ART_PLAN.md](docs/ART_PLAN.md)).

![The village](docs/screenshots/village.jpg)
![Town square](docs/screenshots/town_square.jpg)
![Appraising a villager](docs/screenshots/character_card.jpg)

---

## ⬇️ Download & play

Every update is built automatically for every platform. Pick yours:

| Device | Download |
|---|---|
| **Windows** (most PCs) | [SovereignsEye-Windows.zip](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/download/latest/SovereignsEye-Windows.zip) |
| **Windows on ARM** (Snapdragon laptops) | [SovereignsEye-Windows-ARM64.zip](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/download/latest/SovereignsEye-Windows-ARM64.zip) |
| **Mac** (Apple Silicon and Intel) | [SovereignsEye-Mac.zip](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/download/latest/SovereignsEye-Mac.zip) |
| **Linux / Chromebook Linux mode** (Intel/AMD) | [SovereignsEye-Linux.zip](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/download/latest/SovereignsEye-Linux.zip) |
| **Linux / Chromebook Linux mode** (ARM) | [SovereignsEye-Linux-ARM64.zip](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/download/latest/SovereignsEye-Linux-ARM64.zip) |
| **Android** (phones, tablets, Chromebooks with Play Store) | [SovereignsEye-Android.apk](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/download/latest/SovereignsEye-Android.apk) |

These links always point to the newest build of `main`. Work that hasn't been
merged yet is on the [preview release](https://github.com/pbelfand-dot/Sovereigns-Eye/releases/tag/preview).

**First launch:** the apps aren't code-signed yet, so your system will warn you once.
- **Mac:** unzip, double-click *Sovereign's Eye*; when macOS blocks it, open
  *System Settings → Privacy & Security* and click **Open Anyway**.
- **Windows:** unzip, run `SovereignsEye.exe`; on the blue SmartScreen box click
  **More info → Run anyway**.
- **Linux:** unzip, then run `./SovereignsEye.x86_64` (or double-click it).
- **Chromebook:** turn on *Settings → Advanced → Developers → Linux development
  environment*, move the Linux zip into *Linux files*, unzip it, and run it from the
  Terminal (`./SovereignsEye.x86_64`, or `.arm64` on ARM Chromebooks).
- **Android:** open the `.apk` and allow installing from your browser/files app.

Your saves stay on your device.

## 1. Run it from source in Godot (for development)

1. **Install Godot 4.7** (free) from <https://godotengine.org/download/macos/>
   and drag `Godot.app` into Applications. Use the standard build (not .NET).
2. **Get the code**: in GitHub Desktop choose *File → Clone repository →
   Sovereigns-Eye*, or in Terminal:
   `git clone https://github.com/pbelfand-dot/Sovereigns-Eye.git`
3. **Open Godot → Import** → pick the `project.godot` file in the folder →
   *Import & Edit*. The first import takes a few seconds.
4. Press the **▶ Play** button (top-right of the editor) or **Cmd+B**.

Apple Silicon Macs run it natively; Godot 4.7 uses Metal by default.

## 2. What to try

| # | Goal | How |
|---|---|---|
| 1-2 | Launch & start a new game | Main menu → **New Game** → leave the seed blank (random) or type one → **Begin** |
| 3 | Explore the village | Drag with the mouse, WASD, pinch/scroll to zoom, Q/E to rotate |
| 4 | NPCs walking around | Speed up time with **2**, **3**, **4**: people go to work, the tavern, the chapel and home to bed |
| 5-7 | Click an NPC → character card | Left-click anyone. That **appraises** them and opens their card |
| 8 | Find exceptional talent | Press **L** for the Village Ledger, sort by *Greatest talent*. Read *History* tabs for "Rumor has it…" clues |
| 9 | Happiness, loyalty, personality | Card → **Personality** tab, including *why* they feel that way |
| 10 | Build your household | Card → **Court**: talk, give gifts, and recruit willing villagers. Children aged 10–15 can join as pages with a parent's approval |
| 11 | Develop retainers | Choose a training focus, appoint a Steward, Marshal, Chancellor, or Court Scholar, and knight proven servants |
| 12 | Run your court | Press **K** to see gold, daily income and wages, renown, offices, retainers, loyalty, and the house chronicle |
| 13 | Save / load | **F5** quicksave, **F9** quickload, or **Esc → Save Game / Load Game**. Quit, relaunch, **Continue** |

The same seed always creates the same village and the same people.

### Controls

| Action | Mouse / trackpad | Keys |
|---|---|---|
| Select & appraise | Left-click a villager | — |
| Pan | Left-drag or right-drag · two-finger scroll | WASD / arrows (Shift = fast) |
| Zoom | Scroll wheel · pinch | R / F, + / − |
| Rotate | Middle-drag · Option + left-drag | Q / E |
| Follow selected | — | C |
| Pause / speed | Top bar buttons | Space · 1 2 3 4 |
| Village ledger | Top bar | L |
| Your court | Top bar | K |
| Quicksave / quickload | — | F5 / F9 |
| Close / menu | — | Esc |
| Help overlay | — | H |
| Debug: appraise everyone | — | F2 |

## 3. How the talent system works

Each of the six attributes — Leadership, Combat, Intelligence, Politics,
Administration, Ambition — has two numbers: **current / potential**.

| Rank | F | D | C | B | A | S | S+ | SS |
|---|---|---|---|---|---|---|---|---|
| Potential | 0–19 | 20–49 | 50–64 | 65–79 | 80–99 | 100–119 | 120–149 | 150+ |
| Base odds | 14% | 48.9% | 20.5% | 11% | 4.5% | 0.9% | 0.25% | 0.05% |

* **D is the most common rank.** Measured over 100 seeds, a village of 50 has
  about 4 people (usually 2–6) with an S-rank or better talent; roughly two in
  three villages hide an S+, and about one in six an SS.
* **Background shifts the odds, never guarantees.** Military families roll
  Combat/Leadership with better odds, merchant families Politics/Administration.
  Children of gifted parents get a modest boost too.
* **Current ability reflects opportunity.** Age, social station and job decide
  how much of their potential someone has developed. That is why a peasant
  child can read *Leadership: 12 / 126 (S+)*.
* **Wasted talent makes people restless.** Gifted, ambitious commoners lose
  happiness ("Talents go unused"), the hook for recruiting them in Phase 2.

All of these numbers live in `data/*.json`, so you can rebalance without code.

## 4. Project layout

```text
project.godot          Godot project (main scene = scenes/main/main.tscn)
data/                  Design data (JSON): ranks, occupations, traits, names,
                       families, buildings, building_kit recipes, animations,
                       schedules, appearance palettes, art style
scenes/main, world/    Main menu and the playable world (built from code)
scripts/core/          Game autoload, world state, seeds, calendar, data loader
scripts/characters/    CharacterData, generator, Quaternius HumanModel (+ primitive
                       fallback), NPC body, AI portrait prompts
scripts/appraisal/     Appraisal skill + talent roller (potential/current)
scripts/court/         Noble-house rules: recruitment, offices, training, wages,
                       loyalty, knighthood, treasury and renown
scripts/ai/            NPC daily-routine brain + mood (happiness/loyalty/stress)
scripts/world/         Layout generator, village builder, VillageKit prefabs, roads,
                       camera, sky
scripts/persistence/   Save/load (JSON in user://saves)
scripts/ui/            Theme, HUD, character card, ledger, menus
3D/                    Asset library (Quaternius used; reference packs .gdignore'd)
shaders/               Villager skin/clothing/hair, experimental toon unifier
assets/                Fonts and extra models (see assets/*/README.md)
ai-art/                Local AI portrait painter (ComfyUI + FLUX.2 klein); not shipped
tests/                 Headless test suite
tools/                 run_tests.sh, village census, screenshot capture, prefab gallery
docs/ARCHITECTURE.md   How the systems fit together
docs/ART_PLAN.md       Art direction, assets used, missing models, scaling plan
```

## 5. The 3D asset library (`3D/`)

The [`3D/`](3D/) folder holds the game's model library: 1,218 cataloged glTF 2.0
files with previews, licenses, checksums and validation records (all CC0).

**Chosen direction: Quaternius.** A sleek, textured, stylized fantasy look:
- [`3D/environments/quaternius-medieval-village-standard/`](3D/environments/quaternius-medieval-village-standard/):
  176 modular village pieces sharing 22 textures (keep the `models/` folder together)
- [`3D/character-tests/quaternius-universal-base-standard/`](3D/character-tests/quaternius-universal-base-standard/):
  rigged base characters, hairstyles, beard and eyebrows (a technical test set)
- [`3D/animations/`](3D/animations/): both Quaternius Universal Animation Libraries,
  86 clips, in-place and root-motion versions
- [`3D/research/SCALABILITY_ROADMAP.md`](3D/research/SCALABILITY_ROADMAP.md): what is
  ready from hamlet to kingdom scale, and what is still missing

The Kenney and blocky packs are kept for reference only and are not the art direction.
See [`3D/README.md`](3D/README.md) for the full catalog and
[`docs/ART_PLAN.md`](docs/ART_PLAN.md) for how the game uses these assets.

![Quaternius sleek base-character test](3D/character-tests/quaternius-universal-base-standard/previews/overview.png)

![Quaternius Medieval Village MegaKit](3D/environments/quaternius-medieval-village-standard/previews/overview.jpg)

## 6. How the art works

* **Buildings** are prefabs assembled from the Quaternius village kit by recipe
  ([`data/building_kit.json`](data/building_kit.json)), merged into one mesh per
  shared material, with distance-culled details and box collisions.
  `godot --path . res://tools/prefab_gallery.tscn -- out_dir` renders every prefab.
* **Villagers** are Quaternius base characters: body, hair, beard, skin and
  outfit colors come from each character's data, and in-place animation clips
  follow their activity and job ([`data/animations.json`](data/animations.json)).
  Clothing is painted on until the free Quaternius outfit pack is added.
* **Card portraits** show an AI painting when one exists for that villager, and
  a live 3D portrait otherwise. Paint them locally with ComfyUI +
  FLUX.2 [klein]: see [`ai-art/README.md`](ai-art/README.md).
* Missing art (trees, props, outfits, windmill, kingdom and harbor pieces) is
  listed with sources and prices in [`docs/ART_PLAN.md`](docs/ART_PLAN.md).

![Villagers](docs/screenshots/villagers.jpg)
![Night](docs/screenshots/night.jpg)

### One consistent look from any source (experimental)

`StyleUnifier` (`scripts/world/style_unifier.gd` + `shaders/unified_toon.gdshader`)
repaints any model, whether from asset packs, AI generators like Higgsfield,
or the built-in placeholders, toward one master palette in
`data/art_style.json`, with shared toon lighting. Call `StyleUnifier.apply(node)`
on an imported model. Edit the palette to restyle everything at once. It is not
switched on in the game yet.

![Style unifier: as imported vs. unified](docs/screenshots/style_unifier_demo.jpg)

To re-render that comparison: `godot --path . res://tools/style_demo.tscn -- out.png`
(needs the reference packs, which are hidden from Godot with `.gdignore`).

## 7. Tests & tools

```bash
tools/run_tests.sh                       # Headless tests (generation, determinism, rank odds,
                                         # court, save/load, art pipeline, live world)
godot --headless --path . --script res://tools/print_village.gd -- 12345   # census of a seed
```

Saves live in `~/Library/Application Support/Godot/app_userdata/Sovereign's Eye/saves/`
as readable JSON.

## 8. Known limitations (Phase 2 first playable)

* Art gaps: clothing is painted on (outfit pack pending); trees, crops, market
  stalls, the well and benches are still simple shapes; hats and hand tools
  aren't shown in 3D yet. See [docs/ART_PLAN.md](docs/ART_PLAN.md).
* NPCs walk along roads and can clip through each other or props; there is
  no navmesh yet.
* Retainers train every day, but people do not age, marry or have children yet.
* You can appraise everyone. Appraisal levels and hidden information are
  supported in code (`Appraisal.appraise(c, level)`) but not used yet.
* You play the ruling house's heir, marked by a gold crest, but there is no
  character creator or succession system yet.
