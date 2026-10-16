# 3D asset backlog

Original asset families for Sovereign's Eye, in priority order: what improves
the visible game most right now, and what is reused from hamlet to kingdom.
Each family goes through design → model → render → in-game check →
validation before it counts as done (see `props/village-commons/README.md`
for the standard).

Status: **done**, **next**, or blank (queued).

| # | Family | Why now | Replaces / adds | Reuse across settlement growth | Status |
| ---: | --- | --- | --- | --- | --- |
| 1 | **Village Commons:** well ×3, charter banner ×3, signpost ×3 | The square is where the heir starts, and its well was a grey cylinder; charter banners are the reward you see for a charter | Procedural well, banner and signpost primitives | Tiers follow the charter (Hamlet → Town); the same parts scale to a city's market cross | **done** |
| 2 | **Farm & Field:** crops ×5 (wheat, barley, flax, cabbage, turnip), field fences and gates ×3 tiers, haystacks ×3 (haycock, hayrick, stooks), log pile, scarecrow | Fields are the biggest surfaces in the village and were boxes and balls; haystacks and lumber were a squashed sphere and cylinders | Procedural crops, field boxes, haystack and lumber; fences now follow the charter | Wattle hurdles (Hamlet) → split rails (Village) → paled fencing (Town); crops and stacks reuse at the manor's home farm. A hay cart moves to a later carts & transport family | **done** |
| 3 | **Market Square:** kerb ×3 (rubble edging, dressed kerb, two stone steps), market cross ×2 (Market Town cross, Town lantern cross), trough ×2 (log, carved stone) | The square's rim was a flat grey band; a Market Town had no civic heart | The procedural square ring | Rubble edging (Hamlet) → dressed kerb (Village) → stone steps and a market cross (Market Town) → a lantern cross (Town) | **done** |
| 4 | **Smithy:** forge ×2 (village hearth under a timber hood; town forge with a stone hood, tall chimney and double bellows), anvil on its stump, slack tub, charcoal heap and bin, tool rack, grindstone; glowing embers | A smithy showed only a kit anvil; workplaces must read before the UI explains them | The kit anvil dressing | Village hearth (Hamlet, Village) → town forge with a grindstone (Market Town, Town); a castle forge later | **done** |
| 5 | **Home yard:** bench ×3 (log, plank, painted), kitchen garden ×2 (dug bed, raised bed with bean canes), chopping block, water butt, laundry line, hen house with hens, flower pots | Homes are the most repeated buildings; this is how families feel lived-in | The kit bucket, stool, barrel and crate at cottages | Cottage (log bench, dug bed) → Timber House (plank bench, raised bed, water butt, hens) → Townhouse (painted bench, flower pots, no hens) | **done** |
| 6 | **People pass:** headwear, aprons and long garments (done: `characters/status-wear/`: circlet, crown, helmet, straw hat, cap, baker's cap, veil, leather and linen aprons; robes, gowns and coats in ten dyes); next: faces, aged and heavier bodies | The Eye is about reading people; clothes should show status first | Extends the Quaternius base and outfits | Same skeleton and animations from hamlet to court | **next** |
| 7 | **Thatch and repair kit:** thatched roofs, patched walls and shutters for poor homes | A hamlet should look poorer than a town, not just smaller | Tier-0 homes use tiled roofs today | Thatch → tile as homes are upgraded | |
| 8 | **Training yard:** practice dummies, weapon racks, archery butts, a sparring ring | Barracks and squires need a place that reads as training | Dummy set | Village muster → town guard → castle lists | |
| 9 | **Chapel grounds:** bell cote, graves and markers, a lychgate, candles and an altar | Chapels have no grounds | — | Village chapel → town church yard | |
| 10 | Castle and keep kit (walls, towers, gatehouse, keep) | Needed for the castle phase | — | Builds on the kerb and stone language of #3 | |
| 11 | Port and ships | Needed for the coast phase | — | Same timber and rope language as the commons | |

Budgets used so far (triangles; see each family's README):

- A one-off centrepiece (a well) can use up to 6k triangles with Godot's automatic LODs.
- Repeated civic props (banners, signposts) stay under 1.5k.
- Scattered small props (barrels, baskets) should stay under 600 and are merged into chunk meshes.
- Instanced crops (MultiMesh, hundreds per field) stay under 450, cast no shadows and fade out beyond 170 m; a 2 m fence segment stays under 450.
- Yard one-offs (haystacks, log pile, scarecrow) stay under 700, except the three-stook group (2k), which stands in for three separate stacks.
- Edging pieces laid by the dozen round the square (kerbs) stay under 300; a square's centrepiece (market cross) under 3k with LODs.
- Home yard pieces, repeated at every home, stay under 2k (a hen house with its hens) and benches under 500; a whole yard is about 5k, merged.
