# Quaternius Universal Base Characters — Standard test

This is the free Standard edition of Quaternius's Universal Base Characters,
prepared as a game-integration test for Sovereign's Eye. It is a sleeker,
more human-proportioned alternative to the earlier blocky and chibi options.

## Included

- Two rigged full-body base characters: female and male Superhero bodies
- Five hairstyles
- One beard and two eyebrow options
- Embedded textures and materials

The models are stored as self-contained GLBs so they can be moved or imported
without losing their PNG texture files. The source archive supplied glTF, BIN,
and PNG files; this repository only repackages that data and does not alter the
meshes, skeletons, weights, or materials.

The hair pieces in `models/hair/` are the source pack's **Rigged to Head Bone**
versions. They are intended to be attached to the matching character skeleton,
not used as independent characters.

## Test order

1. Import one full-body model from `models/bodies/` into the game.
2. Confirm scale, material appearance, skeleton, and skin deformation.
3. Import a hairstyle from `models/hair/` and attach it to the head bone.
4. Test one movement animation after retargeting to the game's animation system.

This free pack is a visual and technical test, not the final population system.
The paid Source edition and the separate Fantasy Outfits pack provide the wider
body and clothing variety discussed for a large crowd.

## Source and license

- Official page: https://quaternius.com/packs/universalbasecharacters.html
- Download page: https://quaternius.itch.io/universal-base-characters
- Creator: Quaternius
- License: CC0 1.0

The original Standard-edition license notice is preserved in `LICENSE.txt`.
