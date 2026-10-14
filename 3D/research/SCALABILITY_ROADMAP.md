# Sovereign's Eye asset scalability roadmap

## Bottom line

The selected Quaternius art family can scale coherently from a tiny settlement to
a large kingdom. The new village kit provides a strong modular construction
language, but the repository is **not yet visually complete for a capital or a
ship-based phase**. Those stages require new categories, not simply more copies
of village houses.

## Readiness by settlement stage

| Stage | Readiness | What works now | Important gap |
| --- | --- | --- | --- |
| Tiny town | Ready for prototype | 176 modular village pieces, basic props, two base characters, 86 Standard animation clips | More NPC outfits and nature dressing before final art |
| Large village | Mostly ready | Modular roofs, walls, floors, doors, stairs, balconies, overhangs, fences, wagon, crate, vines | Markets, workshops, furniture, crops, vegetation, roads, and stronger population variation |
| Town/city districts | Partial | Modules can form dense multi-story blocks and varied streets | Civic landmarks, wealth tiers, signage, plazas, districts, and performance-ready prefabs |
| Kingdom/capital | Not complete | Existing kit can build residential and commercial districts | Palace/keep, monumental walls and gates, towers, barracks, temples, throne room, bridges, siege-scale landmarks |
| Harbor and ships | Not complete | Wagon/crate and generic props can support early dock dressing | Docks, piers, cranes, ropes, sails, cargo sets, ship interiors, and multiple ship classes |

## Matching additions to acquire

1. **Stylized Nature MegaKit** — 116 models for forests, roadsides, village edges,
   gardens, and seven leaf looks. It is the highest-priority world-scale addition.
   https://quaternius.com/packs/stylizednaturemegakit.html
2. **Fantasy Props MegaKit** — 211 props for markets, homes, taverns, workshops,
   weapons, books, potions, tools, furniture, and breakables.
   https://quaternius.com/packs/fantasypropsmegakit.html
3. **Pirate Kit** — 71 characters and environment models and the strongest newer
   Quaternius starting point for the harbor/ship phase. Its ship silhouettes and
   textures must be reviewed beside the village kit before treating it as final.
   https://quaternius.com/packs/piratekit.html
4. **Ultimate Fantasy RTS** — 128 evolving buildings and nature assets that may
   help communicate settlement progression and provide kingdom landmarks. It is
   an older pack, so use selected landmarks rather than mixing it everywhere.
   https://quaternius.com/packs/ultimatefantasyrts.html
5. **Ultimate Modular Ruins** — 90 models for ancient keeps, dungeons, ruined
   districts, and exploration spaces.
   https://quaternius.com/packs/ultimatemodularruins.html

The older six-model Ships Pack is useful for prototypes, but it is too small and
stylistically simple to carry a major naval phase alone.

## Population constraint

The current free base-character test contains only two body models, five hair
styles, one beard, and two eyebrow options. That is enough to validate scale,
materials, rigging, and animation compatibility, but not enough to populate a
kingdom without obvious repetition. Before crowd production, add the wider body
set and modular fantasy outfits or establish a custom outfit recolor/accessory
pipeline.

## Technical scaling rules

- Assemble village modules into reusable building prefabs; do not place hundreds
  of loose pieces at runtime.
- Share the supplied texture maps and materials across every building.
- Create low-cost collision proxies rather than mesh-perfect collisions.
- Add distance-based detail reduction for roofs, windows, vines, and interior
  dressing.
- Stream districts and interiors instead of loading the whole kingdom at once.
- Maintain a small palette of foundation dimensions so grid snapping remains
  predictable across settlement tiers.
- Treat ships as moving gameplay spaces with separate exterior, deck, interior,
  collision, and distant silhouette models.

These rules allow the same art direction to grow without making the final capital
look like a repeated starter village or overwhelming the game at runtime.
