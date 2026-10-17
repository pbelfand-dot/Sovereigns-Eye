# The Sovereign's Eye: bells and music

The game's own sounds for the Sovereign's Eye reveal: bells for the Eye
opening, each tier's music, a note for each ability as it shows, and the
stamp. Made by [`tools/audio/make_stings.py`](../../tools/audio/make_stings.py)
from fixed seeds, so the script always gives the same sounds. Run it from
the repository root after changing it:

```
python3 tools/audio/make_stings.py                  # rewrites audio/stings/*.ogg
python3 tools/audio/make_stings.py --preview DIR    # also WAVs and spectrograms
godot --headless --path . --import
python3 tools/audio/build_audio_manifest.py
```

## How they're made

Everything is synthesized with numpy. Nothing is sampled except the
Legendary landing (below).

- **Bells.** A church bell is built from its partials: the hum, prime,
  tierce, quint and nominal. Each fades at its own rate, beating slightly
  against a twin. A hand bell is its fundamental and twelfth with a little
  shimmer.
- **Strings.**
  - The harp is built from its harmonics, plucked.
  - The lute is plucked nearer the bridge, with its body warming the low
    notes and dulling the high ones.
- **Kettledrums** come from a drumhead's modes, struck once or rolled.
- **The drone** is in open fifths, voiced like a reed organ.
- **The heartbeat** is a lub-dub.
- **The hall.** A made-up hall reverb puts them all in one room.

**Tuning.** Everything is in C, tuned to A = 440 Hz like the victory theme
it meets at the top. The rises keep to open fifths (C, G, D), and the
landings add the bright third (E).

## Where they play (`data/eye.json`, `data/audio.json`)

| Tier | The Eye opens | Under the clues | As the card turns | Then |
|---|---|---|---|---|
| Ordinary | `ordinary.ogg`: a lute's open fifth, then its octave | | | |
| Skilled | `bell_small.ogg` | | `skilled_land.ogg`: a harp strummed up C-E-G-C, a hand bell | |
| Exceptional | `bell_deep.ogg` | `exceptional_rise.ogg`: drone, harp figure, drum roll | `exceptional_land.ogg`: a drum stroke, a harp swept up, bells on C, G and E | `row_1`–`row_3` as each ability shows, `stamp_once.ogg` |
| Legendary | `heartbeat.ogg` twice, `bell_great.ogg` | `legendary_rise.ogg`: the same, bigger, with hand bells climbing | `legendary_land.ogg`: the victory fanfare's first phrase with a great bell and a drum stroke | `row_1`–`row_3`, `stamp_twice.ogg` |

**Pacing.** Each cue starts on its step, so the music stays with the
picture at any speed:

- **The rise.** It is made to peak exactly when its tier's clues end:
  1.95 s after the card appears for Exceptional, 2.55 s for Legendary. It
  is then cut for a held breath.
- **The landing** comes with the flash as the card turns.
- **Skipping.** A skipped reveal still plays its landing.

## Sources and license

The sounds in this folder were made for Sovereign's Eye and are released
under CC0 1.0 (see `LICENSE.txt`).

`legendary_land.ogg` contains the first 6.8 seconds of RandomMind's
"Medieval: Victory Theme" (CC0 1.0, kept in
[`audio/music/randommind-medieval/`](../music/randommind-medieval/README.md)),
faded as its phrase dies away, with the bells and drum mixed in.
