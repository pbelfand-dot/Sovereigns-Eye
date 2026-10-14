# Character models

Phase 1 characters are assembled from primitives in
`scripts/characters/character_model.gd` from each character's `appearance`
data (skin, hair, outfit colors, height, build). To use real models, replace
`CharacterModel.create()` and keep its `animate(mode, phase, delta)` interface;
both the walking NPCs and the card portraits use it. Models face **-Z**.
