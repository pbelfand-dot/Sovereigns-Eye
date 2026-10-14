# Quaternius Stylized Nature MegaKit — Standard

This folder contains the free Standard edition of Quaternius's Stylized Nature
MegaKit, organized for Sovereign's Eye. Its rounded, textured forms match the
project's chosen Quaternius village and character direction.

## Included

- 20 trees: common, dead, pine, and twisted variants
- 24 plants and ground details: bushes, clover, fern, flowers, grass,
  mushrooms, petals, and leafy plants
- 24 rocks and path pieces: pebbles, medium rocks, and round/square rock paths
- 20 shared textures, including alternate leaf and desert-rock color maps
- Four publisher preview images

The free Standard edition contains 68 of the complete pack's 116 models. The
Pro and Source editions include the remaining models; the Source edition also
includes engine projects and preconfigured stylized shaders. Those paid files
are not included here.

## Layout

- `models/` — 68 JSON glTF files and their paired BIN geometry files
- `textures/` — one shared copy of the pack's 20 PNG maps
- `previews/` — four official overview images

The source archive also contained duplicate FBX and OBJ versions. This
repository keeps only glTF 2.0 to avoid storing the same geometry three times.
Image URIs were adjusted to point at the shared `textures/` directory; meshes,
materials, geometry, and images are otherwise unchanged. Keep the collection
together so the relative paths continue to resolve.

## Integration notes

- Use trees and large rocks as instanced scenery, with simplified collisions.
- Use grass, flowers, petals, and pebbles through MultiMesh or another batching
  system rather than individual gameplay nodes.
- `Leaf_Pine.png`, the non-`_C` normal/twisted leaf maps,
  `Leaves_GiantPine_C.png`, and `Rocks_Desert_Diffuse.png` are supplied variants
  that are not referenced by the default materials.
- The free Standard archive does not include the preconfigured Godot shader
  project from the paid Source edition, so the game should apply its own shared
  foliage material and wind treatment.

## Source and license

- Official page: https://quaternius.com/packs/stylizednaturemegakit.html
- Download page: https://quaternius.itch.io/stylized-nature-megakit
- Edition: Standard (free, 68/116 models)
- Creator: Quaternius
- License: CC0 1.0

The publisher's original license notice is preserved in `LICENSE.txt`.
