# Quaternius animation libraries

These are the free Standard editions of both Universal Animation Libraries,
packaged for direct testing with the Quaternius Universal Base Characters.

Each library contains two GLBs:

- `*_Standard.glb` — in-place motion; use this first when game code controls
  character movement.
- `*_Standard_RM.glb` — root motion baked into movement animations; use this
  when the animation itself should move the character.

Do not play both files at once. They contain alternate exports of the same clip
set. Import the version that matches the game's locomotion system and retarget
its humanoid skeleton to the character.

The Standard editions are the free subsets of the complete libraries. The
full first library is advertised as 120+ animations; the full second library is
advertised as 130+ complementary animations. The downloaded Standard editions
contain **43 clips each**: 86 clip entries across the two in-place files (85
distinct names because both include `A_TPose`). Each root-motion file repeats
its library's same 43 clips with motion baked into the root.

## Suggested first test

1. Import `quaternius-universal-animation-library-1/models/UAL1_Standard.glb`.
2. Retarget `Idle_Loop`, `Walk_Fwd_Loop`, `Jog_Fwd_Loop`, and one attack clip to
   a body in `../character-tests/quaternius-universal-base-standard/`.
3. Confirm hip height, foot placement, hand pose, and shoulder deformation.
4. Only then try the `_RM` file and configure root-motion handling.

The supplied Godot, Unity, and Unreal setup images are preserved in each pack's
`setup-guides/` folder. Original notices are preserved as `SOURCE_README.txt`.

All files are CC0 1.0.
