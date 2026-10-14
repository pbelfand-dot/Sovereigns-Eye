# Building models

Drop `.glb` / `.gltf` (or `.tscn`) building models here, then point the
matching type at them in `data/buildings.json`:

```json
"cottage": { ..., "model": "res://assets/buildings/cottage.glb", "model_scale": 1.0, "model_offset": [0, 0, 0] }
```

Conventions: the door faces **+Z**, the origin is at ground level in the
middle of the footprint, 1 unit = 1 meter. Free CC0 sources that fit the style:
Kenney (kenney.nl), KayKit and Quaternius (itch.io).
