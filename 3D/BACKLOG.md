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
| 2 | **Farm & yard:** haystacks (round, stacked, covered), woodpile/lumber, fences and gates, scarecrow, hay cart | Haystacks and lumber are still a squashed sphere and cylinders, and every farmstead shows them | Procedural haystack and lumber; adds fence variety | Poor patched fences → hurdles → paled fences; also used by the manor's home farm | **next** |
| 3 | **Square edge & market cross:** stone kerb and steps for the square, a market cross for Market Towns, a well-house trough | The square's rim is a flat grey band; a Market Town has no civic heart | The procedural square ring | Kerb → paved steps → a town plaza with a raised cross | |
| 4 | **Smithy family:** forge with hood, bellows, quench trough, anvil and stump, tool rack, unfinished blades, coal heap | A smithy shows only an anvil; workplaces must read before the UI explains them | Smithy dressing sets | Village smith → town armourer → castle forge | |
| 5 | **Home yard:** water butt, laundry line, kitchen garden beds, chicken coop, bench by the door, chopping block | Homes are the most repeated buildings; this is how families feel lived-in | Generic crate/barrel dressing at homes | Poor (patched) → ordinary → prosperous (painted, potted) variants | |
| 6 | **People pass:** faces, hair, aged and heavier bodies, status outfits (labourer, craftsperson, merchant, gentry, noble) on the shared skeleton | The Eye is about reading people; clothes should show status first | Extends the Quaternius base and outfits | Same skeleton and animations from hamlet to court | |
| 7 | **Thatch and repair kit:** thatched roofs, patched walls and shutters for poor homes | A hamlet should look poorer than a town, not just smaller | Tier-0 homes use tiled roofs today | Thatch → tile as homes are upgraded | |
| 8 | **Training yard:** practice dummies, weapon racks, archery butts, a sparring ring | Barracks and squires need a place that reads as training | Dummy set | Village muster → town guard → castle lists | |
| 9 | **Chapel grounds:** bell cote, graves and markers, a lychgate, candles and an altar | Chapels have no grounds | — | Village chapel → town church yard | |
| 10 | Castle and keep kit (walls, towers, gatehouse, keep) | Needed for the castle phase | — | Builds on the kerb and stone language of #3 | |
| 11 | Port and ships | Needed for the coast phase | — | Same timber and rope language as the commons | |

Budgets used so far (triangles; see each family's README):

- A one-off centrepiece (a well) can use up to 6k triangles with Godot's automatic LODs.
- Repeated civic props (banners, signposts) stay under 1.5k.
- Scattered small props (barrels, baskets) should stay under 600 and are merged into chunk meshes.
