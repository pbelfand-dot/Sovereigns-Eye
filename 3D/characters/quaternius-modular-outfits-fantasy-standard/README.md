# Quaternius Modular Character Outfits — Fantasy Standard

This folder contains the free Standard edition of Quaternius's Modular
Character Outfits — Fantasy, organized for Sovereign's Eye. It matches the
Universal Base Characters already in `3D/character-tests/` and uses the same
humanoid rig as the Universal Animation Libraries.

## Included in the free Standard edition

- Four complete rigged outfits: female/male Peasant and female/male Ranger
- Twenty separate rigged pieces for mixing and matching those outfits
- Ranger hoods and shoulder armor
- Shared PBR textures for the clothes and visible base-character skin
- One additional base-color variant for Peasant and Ranger

The official product page shows 12 outfits and 62 modular parts, but those are
the contents of the complete paid Source edition. The free Standard archive
explicitly contains only a portion of the collection. This repository does not
claim that the other eight outfits are included.

## Layout

- `models/outfits/` — four ready-made outfit combinations
- `models/parts/` — 20 individual clothing and accessory pieces
- `textures/` — one shared copy of every texture referenced by the models
- `textures/variants/` — optional alternate Peasant and Ranger base colors
- `previews/overview.jpg` — the publisher's collection preview

The original archive duplicated the same textures beside both model sets. The
glTF texture URIs were changed to point at the single shared `textures/`
directory; geometry, rigs, skin weights, materials, and images are otherwise
unchanged. Keep the whole collection together so those relative paths resolve.

## Integration notes

Quaternius's source readme says the outfits should be combined with only the
head from a Universal Base Character. Keeping the full body under the clothing
causes clipping and wastes rendering work. Start with one complete outfit to
verify the skeleton and animation retargeting, then build the population
customizer from the individual pieces.

The two files in `textures/variants/` can replace the matching default
base-color map to produce a second Peasant or Ranger colorway. They are not
referenced by default, so switching them should be done in the material setup.

## Source and license

- Official page: https://quaternius.com/packs/modularcharacteroutfitsfantasy.html
- Download page: https://quaternius.itch.io/modular-character-outfits-fantasy
- Edition: Standard (free sampler)
- Creator: Quaternius
- License: CC0 1.0

The publisher's original notices are preserved in `LICENSE.txt` and
`SOURCE_README.txt`.
