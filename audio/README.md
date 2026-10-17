# Audio library

This folder is a ship-ready CC0 audio starter library for Sovereign's Eye.
It contains 312 `.ogg` files: 10 music tracks, 6 location ambience beds,
281 short sound effects, and 15 bells and cues for the Sovereign's Eye that
the game makes itself. Attribution is not required, but source and license
records are kept here so every asset remains traceable.

## Folder map

| Folder | Files | Best use |
|---|---:|---|
| `music/randommind-medieval/` | 10 | menus, settlement life, exploration, combat, victory and defeat |
| `ambience/freesound-cc0/` | 6 | market crowds, tavern chatter, village morning, smithy and hearth |
| `sfx/kenney-rpg/` | 51 | doors, books, coins, cloth, knives, pots and other medieval interactions |
| `sfx/kenney-impact/` | 130 | footsteps and wood, metal, glass, mining and general impacts |
| `sfx/kenney-interface/` | 100 | buttons, confirmation, errors, opening, closing, scrolling and selection |
| `stings/` | 15 | the Sovereign's Eye: bells, each tier's music, a note per ability, the stamp ([README](stings/README.md)) |

`AUDIO_MANIFEST.csv` records the codec, duration, channels, sample rate, byte
size, SHA-256 checksum, license and source page for every audio file.

## In the game

The library is wired in through `data/audio.json`:
- `scripts/audio/audio_director.gd` (the `Audio` autoload) handles the buses, volume settings, music crossfades and one-shots.
- `scripts/audio/soundscape.gd` handles the per-district ambience, villager foley and day/night/court music.
- Tune levels, zones and which files play there.

## Suggested in-game soundscape

Use four audio buses: `Music`, `Ambience`, `SFX`, and `UI`. Music should sit
under the simulation rather than dominate it. Ambience should be spatial and
location-aware, with two or three quiet layers at most.

| Place or state | Suggested audio |
|---|---|
| Main menu / inn | `old_tower_inn_loop.ogg` |
| Village daytime | `bards_tale_loop.ogg` or `harvest_season.ogg` |
| Market square | `market_day_loop.ogg` + `market_busy_crowd.ogg` |
| Tavern interior | `tavern_chatter.ogg` + `fireplace_loop.ogg` |
| Residential edge / farms | `village_morning.ogg` |
| Smithy | `blacksmith_work.ogg` plus occasional metal impacts |
| Feast / court | `kings_feast_loop.ogg` |
| Festival | `minstrel_dance_loop.ogg` |
| World exploration | `exploration.ogg` |
| Battle | `battle.ogg` |
| Outcome | `victory.ogg` or `defeat.ogg` |

For repeated footsteps and work sounds, choose randomly from each numbered
family and vary pitch slightly (about 0.95–1.05). Crossfade ambience when the
camera moves between districts. Avoid recognizable spoken lines; the crowd
beds work because speech stays indistinct.

## Licenses and provenance

All included audio is dedicated to the public domain under CC0 1.0 and can be
used, modified and distributed commercially without attribution.

- Music: RandomMind, downloaded from OpenGameArt. See
  [`music/randommind-medieval/README.md`](music/randommind-medieval/README.md).
- Ambience: individual Freesound contributors. The repository uses Freesound's
  public high-quality preview encodes, converted to Ogg Vorbis. See
  [`ambience/freesound-cc0/README.md`](ambience/freesound-cc0/README.md).
- SFX: Kenney. Each SFX folder contains the license file distributed with its
  original pack.
- Stings: made for the game by `tools/audio/make_stings.py` (CC0 1.0). The
  Legendary landing carries the first phrase of RandomMind's victory theme.
  See [`stings/README.md`](stings/README.md).

The CC0 legal code is available at <https://creativecommons.org/publicdomain/zero/1.0/>.

## Rebuild the inventory

Run `python3 tools/audio/build_audio_manifest.py` from the repository root.
The script requires `ffprobe` and rewrites `audio/AUDIO_MANIFEST.csv`.
