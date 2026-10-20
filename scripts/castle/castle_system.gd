class_name CastleSystem
extends RefCounted
## Phase 5.3, the house's castle. A motte and bailey first (timber), then a
## stone castle in its place, each ordered when the charter allows and paid
## for in gold; the steward chooses the site (CastleLayout: the nearest open
## ground with room for both, its gate toward the village), the ground is
## levelled there and the trees felled. Builders work it at TerritorySystem's
## rates (and the Master of Works'), using wood and stone from the stores as
## they go; the works wait when a store runs dry. A finished castle raises
## the house (renown, room for retainers, the noble houses' regard) and
## defends it in a raid (Military): the warband holds the gate, fights
## harder and breaks later, and the house's gold is kept behind the walls.
##
## Static and deterministic. Numbers: data/castle.json.

const KINDS := ["timber", "stone"]


static func cfg() -> Dictionary:
	return GameData.load_file("castle")


static func kind_def(kind: String) -> Dictionary:
	return (cfg().get("kinds", {}) as Dictionary).get(kind, {})


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


static func name_of(kind: String) -> String:
	return str(kind_def(kind).get("name", kind))


## What stands ("" none, "timber", "stone").
static func stands(state: WorldState) -> String:
	return state.castle.kind if state.castle else ""


# --- Ordering --------------------------------------------------------------------------------

## The next castle the house could build ("timber", "stone" or "" if none).
static func next_kind(state: WorldState) -> String:
	var c := state.castle
	if c == null or not c.works.is_empty():
		return ""
	if c.kind.is_empty():
		return "timber"
	if c.kind == "timber":
		return "stone"
	return ""


## Can the house order this castle now? {ok, reason}
static func can_order(state: WorldState, kind: String) -> Dictionary:
	var c := state.castle
	var d := kind_def(kind)
	if c == null or d.is_empty():
		return {"ok": false, "reason": ""}
	if not c.works.is_empty():
		return {"ok": false, "reason": "The works on your %s are under way." % name_of(c.works)}
	if next_kind(state) != kind:
		return {"ok": false, "reason": "Your house already has its %s." % name_of(c.kind) if not c.kind.is_empty() else "First a motte and bailey."}
	var charter := int(d.get("charter", 0))
	if CharterSystem.current(state) < charter:
		return {"ok": false, "reason": "A %s needs the charter of a %s." % [name_of(kind), CharterSystem.tier_def(charter).get("name", "town")]}
	if state.house.gold < int(d.get("gold", 0)):
		return {"ok": false, "reason": "The masons' and carpenters' hire is %d gold." % int(d.get("gold", 0))}
	if not c.has_site() and choose_site(state) == Transform3D.IDENTITY:
		return {"ok": false, "reason": "There's no open ground round the village with room for a castle."}
	return {"ok": true, "reason": ""}


## Where the castle should stand: the nearest open ground round the village
## with room for the motte and bailey and the stone castle after it, its gate
## toward the village (IDENTITY if there's none).
static func choose_site(state: WorldState) -> Transform3D:
	var taken := []
	if state.territory:
		for s in state.territory.sites:
			var b := s.building
			taken.append([Transform3D(b.basis(), b.position), Rect2(-b.footprint * 0.5, b.footprint)])
	var found := CastleLayout.spots_for(state.layout, CastleLayout.site_rect().grow(3.0), taken, 1, true)
	return found[0] if not found.is_empty() else Transform3D.IDENTITY


## Orders the castle: the hire is paid, the site chosen (the first time),
## the trees on it felled (their wood to the stores). {ok, text, felled}
static func order(state: WorldState, kind: String) -> Dictionary:
	var can := can_order(state, kind)
	if not can["ok"]:
		return {"ok": false, "text": can["reason"], "felled": 0}
	var c := state.castle
	var d := kind_def(kind)
	var felled := 0
	if not c.has_site():
		var xf := choose_site(state)
		c.site = [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.z, 0.01), snappedf(xf.basis.get_euler().y, 0.0001)]
		var way := lane(state)
		state.layout.roads.append({"name": "castle_lane", "points": way, "width": float(TerritorySystem.section("placement").get("lane_width", 3.0))})
		felled = clear_site(state, way)
	state.house.gold -= int(d.get("gold", 0))
	c.works = kind
	c.work_needed = float(d.get("work", 900))
	c.work_done = 0.0
	c.used = {}
	c.builders.clear()
	c.started_day = state.day()
	c.stalled = ""
	refresh_crew(state)
	var text := "The works on your %s begin%s. Your builders will need %s as they go." % [name_of(kind),
		" (the steward chose the ground and %d trees were felled)" % felled if felled > 0 else "", needs_text(kind)]
	state.house.log_event(state.day(), "Work began on the house's %s." % name_of(kind), "office")
	return {"ok": true, "text": text, "felled": felled}


## "240 wood", "640 stone and 120 wood".
static func needs_text(kind: String) -> String:
	var d := kind_def(kind)
	var parts: Array[String] = []
	for r: String in ["stone", "wood"]:
		if int(d.get(r, 0)) > 0:
			parts.append("%d %s" % [int(d.get(r, 0)), r])
	return " and ".join(parts) if not parts.is_empty() else "nothing more"


## Fells the trees on the site, its apron, the approach to its gate and
## along its lane, and breaks up the boulders there (for their stone).
## Returns how many trees.
static func clear_site(state: WorldState, way: PackedVector3Array = PackedVector3Array()) -> int:
	if state.territory == null:
		return 0
	var inv := state.castle.transform().affine_inverse()
	var ground := CastleLayout.site_rect().grow(float(section("site").get("apron", 10.0)))
	var rocks := 0
	for i in range(state.layout.props.size() - 1, -1, -1):
		var p: Dictionary = state.layout.props[i]
		if str(p["type"]) != "rock":
			continue
		var l: Vector3 = inv * (p["pos"] as Vector3)
		if ground.has_point(Vector2(l.x, l.z)) or (not way.is_empty() and TerritorySystem._near_polyline(p["pos"], way, 3.0)):
			state.layout.props.remove_at(i)
			rocks += 1
	TerritorySystem.add(state, "stone", rocks * float(TerritorySystem.section("construction").get("clear_rock_stone", 5)))
	var xf := state.castle.transform()
	var n := 0
	var apron := float(section("site").get("apron", 10.0))
	var fell: Array[int] = []
	for kind: String in KINDS:
		fell.append_array(CastleLayout.trees_in(state.layout, xf, kind, apron))
	for i in state.layout.trees.size():
		var t := state.layout.trees[i]
		if not way.is_empty() and TerritorySystem._near_polyline(Vector3(t.x, 0, t.y), way, 3.0):
			fell.append(i)
	for i in fell:
		if not state.territory.cleared_trees.has(i):
			state.territory.cleared_trees.append(i)
			n += 1
	TerritorySystem.add(state, "wood", n * float(TerritorySystem.section("construction").get("clear_tree_wood", 3)))
	return n


# --- The works -------------------------------------------------------------------------------

static func is_builder(state: WorldState, c: CharacterData) -> bool:
	return state.castle != null and not state.castle.works.is_empty() and state.castle.builders.has(c.id)


## Fills the crew from the village's builders not at work on another site.
static func refresh_crew(state: WorldState) -> void:
	var c := state.castle
	if c == null or c.works.is_empty():
		return
	var kept: Array[int] = []
	for id in c.builders:
		var p := state.get_character(id)
		if p and TerritorySystem.can_build_with(state, p) and not p.is_away():
			kept.append(id)
	c.builders = kept
	var crew := int(kind_def(c.works).get("crew", 6))
	var rates: Dictionary = TerritorySystem.section("construction").get("builders", {})
	var pool: Array[CharacterData] = []
	for p in state.characters:
		if TerritorySystem.can_build_with(state, p) and not p.is_away() and TerritorySystem.builder_site(state, p) == null and not c.builders.has(p.id):
			pool.append(p)
	pool.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		var ra := float(rates.get(a.occupation_id, 0.0))
		var rb := float(rates.get(b.occupation_id, 0.0))
		return ra > rb if ra != rb else a.id < b.id)
	for p in pool:
		if c.builders.size() >= crew:
			break
		c.builders.append(p.id)


## Builder-hours per hour at this hour of the day.
static func rate(state: WorldState, hour: float) -> float:
	var c := state.castle
	if c == null or c.works.is_empty():
		return 0.0
	var r := 0.0
	for id in c.builders:
		var p := state.get_character(id)
		if p and TerritorySystem.on_shift(p, hour):
			r += TerritorySystem.builder_rate(p)
	return r * TerritorySystem.speed_factor(state)


## Builder-hours in a whole day (for the estimate shown).
static func daily_rate(state: WorldState) -> float:
	var total := 0.0
	for h in 24:
		total += rate(state, h + 0.5)
	return total


static func days_left(state: WorldState) -> float:
	var per_day := daily_rate(state)
	var c := state.castle
	return INF if per_day <= 0.0 or c == null else (c.work_needed - c.work_done) / per_day


## Puts in the work for `game_minutes`, using wood and stone as it goes;
## the works wait while a store is dry. True when the castle is finished
## (call complete()).
static func advance(state: WorldState, game_minutes: float) -> bool:
	var c := state.castle
	if c == null or c.works.is_empty() or game_minutes <= 0.0:
		return false
	var hours := rate(state, Calendar.hour_f(state.minutes)) * game_minutes / 60.0
	if hours <= 0.0:
		return false
	hours = minf(hours, c.work_needed - c.work_done)
	var d := kind_def(c.works)
	var need := {}
	for r: String in ["wood", "stone"]:
		var per := float(d.get(r, 0)) / maxf(c.work_needed, 1.0)
		need[r] = per * hours
	var short := ""
	for r: String in need:
		if float(need[r]) > 0.0 and TerritorySystem.amount(state, r) < float(need[r]):
			short = r
	if not short.is_empty():
		c.stalled = short
		return false
	c.stalled = ""
	for r: String in need:
		if float(need[r]) > 0.0:
			TerritorySystem.add(state, r, -float(need[r]))
			c.used[r] = float(c.used.get(r, 0.0)) + float(need[r])
	c.work_done = minf(c.work_done + hours, c.work_needed)
	return c.work_done >= c.work_needed


## The castle stands: the house is raised by it. Events (the news).
static func complete(state: WorldState) -> Array[Dictionary]:
	var c := state.castle
	var kind := c.works
	var d := kind_def(kind)
	c.kind = kind
	c.works = ""
	c.work_done = 0.0
	c.work_needed = 0.0
	c.builders.clear()
	c.stalled = ""
	state.house.renown += int(d.get("renown", 0))
	if state.realm:
		for h in state.realm.houses:
			Realm.change_regard(state, int(h["id"]), int(d.get("regard", 0)), false)
	var text := "Your %s stands! The house is raised by it (renown +%d, room for %d more in the household), and the houses round about take note." % [
		name_of(kind), int(d.get("renown", 0)), int(d.get("retainers", 0))]
	state.house.log_event(state.day(), "The house's %s was finished." % name_of(kind), "office")
	return [{"text": text, "kind": "good", "castle_done": kind}]


## Once a day: the crew kept full; news when the works wait for a store.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var c := state.castle
	if c == null or c.works.is_empty():
		return events
	refresh_crew(state)
	if not c.stalled.is_empty():
		events.append({"text": "The works on your %s wait for %s." % [name_of(c.works), c.stalled], "kind": "bad"})
	return events


# --- What a castle gives ------------------------------------------------------------------------

## More room in the household with a castle.
static func retainer_bonus(state: WorldState) -> int:
	return int(kind_def(stands(state)).get("retainers", 0))


## The castle's defence in a raid: {combat, hold, gold_safe} (zeros without one).
static func defence(state: WorldState) -> Dictionary:
	var d := kind_def(stands(state))
	return {"combat": int(d.get("combat", 0)), "hold": float(d.get("hold", 0.0)), "gold_safe": float(d.get("gold_safe", 0.0))}


## Where the warband forms up before the gate in a raid.
static func rally_point(state: WorldState) -> Vector3:
	var kind := stands(state)
	var xf := state.castle.transform()
	return xf * Vector3(0, 0, CastleLayout.gate_z(kind) + float(section("site").get("rally", 9.0)))


## Where builder `slot` works on the castle, and what they face.
static func work_spot(state: WorldState, slot: int) -> Vector3:
	var xf := state.castle.transform()
	var r := CastleLayout.site_rect()
	var spots := [Vector2(-8, r.end.y - 4), Vector2(8, r.end.y - 4), Vector2(r.position.x + 3, 0), Vector2(r.end.x - 3, 0),
		Vector2(-10, r.position.y + 3), Vector2(10, r.position.y + 3), Vector2(0, 6), Vector2(-6, -8)]
	# Only where the village can walk to (a castle's back may be in the woods).
	var reach := state.layout.extent - 8.0
	var near := spots.filter(func(v: Vector2) -> bool: return (xf * Vector3(v.x, 0, v.y)).length() <= reach)
	if near.is_empty():
		near = spots.slice(0, 2)
	var s: Vector2 = near[posmod(slot, near.size())]
	return xf * Vector3(s.x, 0, s.y)


## The castle's pieces now standing, for drawing: [model, position, yaw]
## in the castle's frame. Works rise piece by piece with the work done (a
## stone castle takes the motte and bailey's place as it goes up).
static func pieces(state: WorldState) -> Array:
	var c := state.castle
	if c == null:
		return []
	var out := []
	var p := c.progress()
	if not c.works.is_empty():
		var rising := CastleLayout.layout(c.works)
		out.append_array(rising.slice(0, floori(rising.size() * p)))
	if not c.kind.is_empty():
		var old := CastleLayout.layout(c.kind)
		var keep := old.size() if c.works.is_empty() else old.size() - floori(old.size() * p)
		# The old castle comes down as the new one rises: its palisade and
		# gate first, the motte last.
		out.append_array(old.slice(0, keep))
	return out


# --- The ground and what's solid ----------------------------------------------------------------

## The castle's ground levelled to the village's (TerrainHeight pads), [] without a site.
static func pads(state: WorldState) -> Array:
	var c := state.castle
	if c == null or not c.has_site():
		return []
	var s := section("site")
	return [{"inv": c.transform().affine_inverse(), "rect": CastleLayout.site_rect().grow(float(s.get("pad_margin", 6.0))),
		"blend": float(s.get("blend", 14.0))}]


## The site as a yard nothing grows in: {center, rot, half}, {} without one.
static func yard(state: WorldState) -> Dictionary:
	var c := state.castle
	if c == null or not c.has_site():
		return {}
	var r := CastleLayout.site_rect().grow(2.0)
	var xf := c.transform()
	return {"center": xf * Vector3(r.get_center().x, 0, r.get_center().y), "rot": float(c.site[2]), "half": r.size * 0.5}


## A lane from the castle's gate to the nearest road (laid when the site is
## chosen), or an empty line if a road runs close by.
static func lane(state: WorldState) -> PackedVector3Array:
	var xf := state.castle.transform()
	var inner := xf * Vector3(0, 0, CastleLayout.gate_z("stone") + 1.0)
	var outer := xf * Vector3(0, 0, CastleLayout.site_rect().end.y + 4.0)
	var hit := TerritorySystem.nearest_way(state.layout, outer)
	if hit.is_empty():
		return PackedVector3Array([inner, outer])
	var road: Vector3 = hit["point"]
	return PackedVector3Array([inner, outer, outer.lerp(road, 0.5), road])


## What stops a body, piece by piece (in its own frame: an offset and half
## extents for a box, or a radius for a round piece). The gates' passages
## are open; the bridge and the motte's tower are on top of the motte.
const SOLID := {
	"SE_Curtain_Wall": [[Vector2(0, 0), Vector2(2.0, 1.35)]],
	"SE_Curtain_Stair": [[Vector2(0, -0.6), Vector2(4.0, 2.0)]],
	"SE_Curtain_Corner": [[Vector2(0, 0), 2.4]],
	"SE_Tower_Square": [[Vector2(0, 0), Vector2(3.35, 3.35)]],
	"SE_Tower_Corner": [[Vector2(0, 0), Vector2(3.35, 3.35)]],
	"SE_Gatehouse": [[Vector2(-2.95, 0), Vector2(1.4, 4.35)], [Vector2(2.95, 0), Vector2(1.4, 4.35)]],
	"SE_Keep": [[Vector2(0, 0), Vector2(7.6, 9.75)]],
	"SE_Palisade": [[Vector2(0, 0), Vector2(2.0, 0.45)]],
	"SE_Palisade_Corner": [[Vector2(0, 0), 1.1]],
	"SE_Palisade_Gate": [[Vector2(-2.25, 0), Vector2(0.4, 2.6)], [Vector2(2.25, 0), Vector2(0.4, 2.6)]],
	"SE_Motte": [[Vector2(0, 0), 13.0]],
}

static var _solid_key := ""
static var _solid: Array = []


## The castle's solid shapes in the world: [{center, basis, half}] boxes and
## [{center, r}] rounds (cached while the castle doesn't change).
static func obstacles(state: WorldState) -> Array:
	var c := state.castle
	if c == null or not c.has_site():
		return []
	var standing := pieces(state)
	var key := "%s|%s|%d|%s" % [c.kind, c.works, standing.size(), str(c.site)]
	if key == _solid_key:
		return _solid
	var xf := c.transform()
	var out := []
	for p: Array in standing:
		var piece := xf * Transform3D(Basis(Vector3.UP, float(p[2])), p[1] as Vector3)
		for shape: Array in SOLID.get(str(p[0]), []):
			var off: Vector2 = shape[0]
			var center := piece * Vector3(off.x, 0, off.y)
			if shape[1] is Vector2:
				out.append({"center": center, "basis": piece.basis, "half": shape[1], "reach": (shape[1] as Vector2).length()})
			else:
				out.append({"center": center, "r": float(shape[1]), "reach": float(shape[1])})
	_solid_key = key
	_solid = out
	return out
