class_name Battle
extends Node3D
## A raid fought in the village (Phase 5.1). The band comes in along its road
## toward the square; the warband runs to meet it; villagers run home. Each
## fighter picks the nearest foe, closes in and swings: Military.strike, the
## same rules as a fight out of sight, with a bar over each head for what's
## left of them. A side breaks when enough of it has fallen (Military.broken):
## raiders who break run for the road they came by; a warband that breaks
## falls back to the manor and the raiders loot. Then Military.finish says
## who died (real risk) and what was won or lost. You can fight too: walk up
## to a raider and strike (the talk key). Movement and blows follow the game
## speed; pausing pauses the fight.

signal finished(report: Dictionary, events: Array)

## Seconds (game-scaled) a blow, a stagger or a block holds before the fighter
## raises their guard again.
const SWING_HOLD := 0.6
const HIT_HOLD := 0.4
## Raiders turn on defenders (or you) this close; farther, they head for the square.
const AGGRO := 14.0
## You're fair game this close to a raider, even if you haven't struck.
const HEIR_DANGER := 4.0
## After a side breaks, seconds before it's over (the beaten run).
const AFTERMATH := 6.0
## The warband holds a line at the rally point until a raider comes this
## close to it (or, if the band hangs back, this many seconds pass).
const MUSTER_ALERT := 12.0
const MUSTER_SECONDS := 60.0
## A fighter is in the fight once a foe is this close (or a blow has been
## struck at them): only those count when a side breaks, not those still
## running in.
const ENGAGE := 6.0

var world: VillageWorld
var state: WorldState
var ours: Array[Dictionary] = []
var theirs: Array[Dictionary] = []
## You, as a fighter (joins the warband's count when you strike or are struck).
var heir_f: Dictionary = {}
var rng: RandomNumberGenerator
var elapsed := 0.0
var over := false
## "house" or "raiders" once that side breaks.
var routed := ""

## NPCs this battle brought (the band, and men other houses sent): ticked
## and freed here, not by the village.
var _own_npcs: Array[NPC] = []
var _sheltered: Array[NPC] = []
var _loot_point := Vector3.ZERO
var _fall_back := Vector3.ZERO
var _way_out := Vector3.ZERO
var _rally := Vector3.ZERO
## The warband is still gathering at the rally point.
var mustering := true
## You called the fall back (an order): no more blows, the band loots.
var fell_back := false
var _after := 0.0
var _k: Dictionary


static func weapons_for(role: String) -> Array:
	return (HumanModel.anim_config().get("weapons", {}).get("by_role", {}) as Dictionary).get(role, ["sword"])


## Brings the band in and calls everyone to their places.
func start(owner_world: VillageWorld) -> void:
	world = owner_world
	state = world.state
	name = "Battle"
	_k = Military.section("combat")
	rng = Seeds.rng(state.world_seed, "battle_live_%d" % state.day())
	var s := Military.sides(state, false)
	var raid := state.military.raid
	var from_a: Array = raid.get("from", [0, 0, 0])
	var from := Vector3(float(from_a[0]), float(from_a[1]), float(from_a[2]))
	_way_out = from
	_loot_point = state.layout.square_center
	_rally = _rally_point(from)
	var manor := state.get_building(CourtSystem._building_of_type(state, "manor"))
	_fall_back = manor.door_position() if manor else state.layout.square_center
	if not CastleSystem.stands(state).is_empty():
		# Behind the gate.
		_fall_back = state.castle.transform() * Vector3(0, 0, CastleLayout.gate_z(CastleSystem.stands(state)) - 8.0)
		# The house's gold is behind its walls: the band comes for the castle,
		# and meets the warband before its gate.
		_loot_point = _rally
	# The band, at the end of its road.
	var i := 0
	for f: Dictionary in s["theirs"]:
		var c := Military.person(state, int(f["id"]))
		var npc := NPC.new()
		add_child(npc)
		npc.setup(c)
		var off := Vector3(float(i % 3) - 1.0, 0.0, float(i / 3)) * 1.4
		npc.teleport(from + off)
		_arm(npc, f)
		_own_npcs.append(npc)
		f["npc"] = npc
		theirs.append(f)
		i += 1
	# The warband, warned days ago, stands in line at the rally point.
	for f: Dictionary in s["ours"]:
		var npc: NPC
		if int(f["id"]) <= Military.ALLY_ID:
			# Men another house sent: they came by the road and stand with yours.
			npc = NPC.new()
			add_child(npc)
			npc.setup(Military.person(state, int(f["id"])))
			_own_npcs.append(npc)
		else:
			npc = world.npc_of(int(f["id"]))
			if npc == null:
				npc = world.spawn_character(int(f["id"]))
		if npc == null:
			continue
		var c := npc.character
		if c.inside_building_id >= 0:
			var b := state.get_building(c.inside_building_id)
			if b:
				npc.teleport(b.door_position())
			c.inside_building_id = -1
			npc.set_inside(false)
		if npc.brain:
			npc.brain.set_errand({})
		npc.stop()
		_arm(npc, f)
		f["npc"] = npc
		ours.append(f)
	for f: Dictionary in ours:
		var npc: NPC = f["npc"]
		npc.teleport(_line_spot(f))
		npc.face_point(_way_out)
	# You.
	var me := world.player_npc()
	if state.player() and me:
		heir_f = Military.fighter(state, state.player(), "house")
		heir_f["combat"] = int(heir_f["combat"]) + int(CastleSystem.defence(state)["combat"])
		heir_f["npc"] = me
		heir_f["joined"] = false
		heir_f["cool"] = 0.0
		heir_f["hold"] = 0.0
		me.model.set_weapons(weapons_for("heir"))
	# Everyone else runs home.
	for npc: NPC in world.npcs.values():
		if npc != me and not npc.fighting:
			npc.brain.set_errand({"type": "shelter"})
			_sheltered.append(npc)
	Audio.play("alarm_bell")


func _arm(npc: NPC, f: Dictionary) -> void:
	npc.driven = true
	npc.fighting = true
	npc.hurry = false
	npc.model.set_weapons(weapons_for(str(f["role"])))
	npc.set_anim("fight_idle")
	f["cool"] = rng.randf_range(0.0, float(_k.get("swing_seconds", 1.2)))
	f["hold"] = 0.0
	f["fled"] = false
	f["target"] = -99999
	_add_bar(npc, f)


# --- The fight, frame by frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if over or world == null:
		return
	var scale := world.time_scale()
	for npc in _own_npcs:
		if is_instance_valid(npc):
			npc.tick(delta, scale)
	if scale <= 0.0:
		return
	var dt := delta * scale
	elapsed += dt
	_tick_heir(dt)
	if mustering:
		_check_muster()
	for f: Dictionary in ours:
		_tick(f, dt, delta)
	for f: Dictionary in theirs:
		_tick(f, dt, delta)
	_update_bars()
	_check_end(dt)


func _tick_heir(dt: float) -> void:
	if heir_f.is_empty():
		return
	heir_f["cool"] = float(heir_f["cool"]) - dt
	heir_f["hold"] = float(heir_f["hold"]) - dt
	var npc: NPC = heir_f["npc"]
	if not is_instance_valid(npc) or heir_f["down"]:
		return
	if float(heir_f["hold"]) <= 0.0 and npc.activity() in ["attack", "hit", "block"]:
		npc.set_anim("idle")


func _tick(f: Dictionary, dt: float, delta: float) -> void:
	var npc: NPC = f.get("npc")
	if f["down"] or f["fled"]:
		return
	if not is_instance_valid(npc):
		f["down"] = true
		return
	f["cool"] = float(f["cool"]) - dt
	f["hold"] = float(f["hold"]) - dt
	if float(f["hold"]) <= 0.0 and npc._anim_mode in ["attack", "hit", "block"]:
		npc.set_anim("fight_idle")
	var speed := float(_k.get("speed", 3.2))
	# The beaten run.
	if routed == f["side"]:
		var away := _way_out if f["side"] == "raiders" else _fall_back
		if _move(npc, away, speed * 1.15, dt, delta) and f["side"] == "raiders":
			f["fled"] = true
			npc.visible = false
		return
	if fell_back and f["side"] == "raiders":
		# The warband fell back in good order: the band goes for the loot.
		_move(npc, _loot_point, speed, dt, delta)
		return
	if mustering and f["side"] == "house":
		# Holding the line, facing the road they'll come by.
		if _move(npc, _line_spot(f), speed, dt, delta):
			npc.face_point(_way_out)
			npc.set_anim("fight_idle")
		return
	var target := _target_for(f)
	if target.is_empty():
		if f["side"] == "raiders" and routed.is_empty():
			_move(npc, _loot_point, speed, dt, delta)
		else:
			npc.drive(Vector3.ZERO, delta)
		return
	var tnpc: NPC = target["npc"]
	var to := tnpc.global_position - npc.global_position
	to.y = 0.0
	if to.length() < ENGAGE:
		f["engaged"] = true
	var reach := float(_k.get("reach", 1.6))
	if to.length() > reach:
		var stop := tnpc.global_position - to.normalized() * reach * 0.8
		_move(npc, stop, speed, dt, delta)
		return
	npc.drive(Vector3.ZERO, delta)
	npc.face_point(tnpc.global_position)
	if float(f["cool"]) <= 0.0:
		_swing(f, target)


## Where the warband makes its stand: on the band's road out from the square,
## the most open ground (farthest from any building) between RALLY_NEAR and
## RALLY_FAR meters along it, so the line has room and the fight can be seen.
const RALLY_NEAR := 12.0
const RALLY_FAR := 50.0


func _rally_point(from: Vector3) -> Vector3:
	# With a castle, the warband holds its gate (Phase 5.3).
	if not CastleSystem.stands(state).is_empty():
		return CastleSystem.rally_point(state)
	var path := world.graph.find_path(_loot_point, from) if world.graph else PackedVector3Array()
	var best := Vector3.INF
	var best_clear := -INF
	var walked := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := a.distance_to(b)
		var steps := maxi(1, ceili(seg / 2.0))
		for k in steps:
			var d := walked + seg * float(k) / steps
			if d < RALLY_NEAR or d > RALLY_FAR:
				continue
			var p := a.lerp(b, float(k) / steps)
			var clear := _clearance(p)
			if clear > best_clear:
				best_clear = clear
				best = p
		walked += seg
	if best != Vector3.INF:
		return best
	var toward := from - _loot_point
	toward.y = 0.0
	return _loot_point + toward.normalized() * minf(14.0, toward.length() * 0.3)


## Meters from `p` to the nearest building's walls.
func _clearance(p: Vector3) -> float:
	var nearest := INF
	for b in state.layout.buildings:
		var local := b.basis().inverse() * (p - b.position)
		var dx := maxf(absf(local.x) - b.footprint.x * 0.5, 0.0)
		var dz := maxf(absf(local.z) - b.footprint.y * 0.5, 0.0)
		nearest = minf(nearest, sqrt(dx * dx + dz * dz))
	return nearest


## Where `f` stands in the warband's line across the rally point, LINE_GAP
## meters from the next.
const LINE_GAP := 1.8


func _line_spot(f: Dictionary) -> Vector3:
	var across := Vector3(-(_way_out - _rally).z, 0.0, (_way_out - _rally).x).normalized()
	var spot := _rally + across * (float(ours.find(f)) - (ours.size() - 1) / 2.0) * LINE_GAP
	return WorldGeometry.resolve(state, spot, 0.4)


## The warband charges when the band comes up to its line (or has waited
## long enough).
func _check_muster() -> void:
	var close := false
	for f: Dictionary in theirs:
		var npc: NPC = f.get("npc")
		if npc and is_instance_valid(npc) and npc.global_position.distance_to(_rally) < MUSTER_ALERT:
			close = true
	if ours.is_empty() or close or elapsed > MUSTER_SECONDS:
		mustering = false


## Who `f` goes for: the foe they're fighting while it stands, else the
## nearest who isn't already beset (each attacker counts as CROWD meters
## farther), so fights pair off and skill tells. Raiders only close in on
## defenders near them, or on you.
const CROWD := 6.0


func _target_for(f: Dictionary) -> Dictionary:
	var current := _fighter(int(f["target"]))
	if not current.is_empty() and not current["down"] and not current.get("fled", false):
		return current
	var npc: NPC = f["npc"]
	var best: Dictionary = {}
	var best_d := INF
	var best_score := INF
	var foes: Array = theirs if f["side"] == "house" else ours
	var mates: Array = ours if f["side"] == "house" else theirs
	for o: Dictionary in foes:
		if o["down"] or o["fled"] or not is_instance_valid(o.get("npc")):
			continue
		var d := npc.global_position.distance_to((o["npc"] as NPC).global_position)
		var beset := mates.filter(func(m: Dictionary) -> bool: return m != f and not m["down"] and int(m["target"]) == int(o["id"])).size()
		var score := d + beset * CROWD
		if score < best_score:
			best_score = score
			best_d = d
			best = o
	if f["side"] == "raiders" and not heir_f.is_empty() and not heir_f["down"]:
		var hd := npc.global_position.distance_to((heir_f["npc"] as NPC).global_position)
		if (heir_f["joined"] or hd < HEIR_DANGER) and hd < best_d:
			best_d = hd
			best = heir_f
	if f["side"] == "raiders" and best_d > AGGRO:
		return {}
	f["target"] = int(best.get("id", -99999))
	return best


func _fighter(id: int) -> Dictionary:
	if not heir_f.is_empty() and int(heir_f["id"]) == id:
		return heir_f
	for f: Dictionary in ours:
		if int(f["id"]) == id:
			return f
	for f: Dictionary in theirs:
		if int(f["id"]) == id:
			return f
	return {}


## A blow from `f` at `t`.
func _swing(f: Dictionary, t: Dictionary) -> void:
	var npc: NPC = f["npc"]
	var tnpc: NPC = t["npc"]
	f["cool"] = float(_k.get("swing_seconds", 1.2)) * rng.randf_range(0.85, 1.15)
	f["hold"] = SWING_HOLD
	f["swings"] = int(f.get("swings", 0)) + 1
	npc.play_once("attack")
	if t == heir_f:
		heir_f["joined"] = true
	var r := Military.strike(f, t, rng)
	f["engaged"] = true
	t["engaged"] = true
	t["hold"] = HIT_HOLD
	if r["down"]:
		_fall(t)
		_sound("battle_hit", tnpc.global_position)
	elif r["hit"]:
		tnpc.play_once("hit")
		_sound("battle_clash" if t["role"] in ["knight", "retainer", "watch", "leader", "heir"] else "battle_hit", tnpc.global_position)
	else:
		tnpc.play_once("block")
		_sound("battle_block", tnpc.global_position)


func _fall(t: Dictionary) -> void:
	var npc: NPC = t["npc"]
	npc.drive(Vector3.ZERO, 0.016)
	npc.play_once("fallen")
	var bar: Node3D = npc.get_node_or_null("HealthBar")
	if bar:
		bar.visible = false
	if t == heir_f:
		Game.notify.emit("You fall, wounded!", Game.COLOR_BAD)


## Steps toward `to` (around buildings by the roads when one is in the way);
## true once there.
func _move(npc: NPC, to: Vector3, speed: float, dt: float, delta: float) -> bool:
	var goal := to
	var flat := to - npc.global_position
	flat.y = 0.0
	if flat.length() < 0.3:
		npc.drive(Vector3.ZERO, delta)
		return true
	if flat.length() > 3.0 and WorldGeometry.line_blocked(state, npc.global_position, to):
		goal = _waypoint(npc, to)
	var dir := goal - npc.global_position
	dir.y = 0.0
	var dist := dir.length()
	if dist < 0.05:
		npc.drive(Vector3.ZERO, delta)
		return false
	var step := dir / dist * minf(speed * dt, dist)
	# Keep a little room between fighters.
	for other: Dictionary in ours + theirs:
		var o: NPC = other.get("npc")
		if o == null or o == npc or not is_instance_valid(o) or other["down"]:
			continue
		var away := npc.global_position - o.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < 0.8:
			step += away / d * (0.8 - d) * 0.5
	var p := WorldGeometry.resolve(state, npc.global_position + step, 0.35)
	p = TerrainHeight.on_ground(p)
	var moved := p - npc.global_position
	npc.global_position = p
	npc.drive(moved, delta)
	return false


## The next road point on the way to `to` (paths kept a second or two per body).
func _waypoint(npc: NPC, to: Vector3) -> Vector3:
	var cache: Dictionary = npc.get_meta("battle_path", {})
	var path: PackedVector3Array = cache.get("path", PackedVector3Array())
	if path.is_empty() or elapsed > float(cache.get("until", 0.0)) or (cache.get("to", Vector3.INF) as Vector3).distance_to(to) > 4.0:
		path = world.graph.find_path(npc.global_position, to)
		cache = {"path": path, "until": elapsed + 2.0, "to": to}
		npc.set_meta("battle_path", cache)
	for p in path:
		var d := p - npc.global_position
		d.y = 0.0
		if d.length() > 1.0 and not WorldGeometry.line_blocked(state, npc.global_position, p):
			return p
	return to


func _sound(event: String, at: Vector3) -> void:
	if world.soundscape:
		world.soundscape.play_at(event, at)


# --- You -------------------------------------------------------------------------------------

## You strike the raider in front of you (the talk key). False when there's
## no one in reach (so the key does what it always does).
func heir_strike() -> bool:
	if over or heir_f.is_empty() or heir_f["down"]:
		return false
	var me: NPC = heir_f["npc"]
	var best: Dictionary = {}
	var best_d := float(_k.get("reach", 1.6)) + 0.6
	for f: Dictionary in theirs:
		if f["down"] or f["fled"]:
			continue
		var d := me.global_position.distance_to((f["npc"] as NPC).global_position)
		if d < best_d:
			best_d = d
			best = f
	if best.is_empty():
		return false
	if float(heir_f["cool"]) > 0.0:
		return true
	heir_f["joined"] = true
	me.face_point((best["npc"] as NPC).global_position)
	_swing(heir_f, best)
	return true


func heir_down() -> bool:
	return not heir_f.is_empty() and heir_f["down"]


# --- Orders (Phase 5.2) ----------------------------------------------------------------------

## The line charges now, without waiting for the band to come up to it.
func order_charge() -> bool:
	if over or not mustering:
		return false
	mustering = false
	Game.notify.emit("Charge!", Game.COLOR_GOOD)
	return true


## The warband falls back to the manor: the band has the village's loot,
## but no more of yours fall.
func order_fall_back() -> bool:
	if over or not routed.is_empty():
		return false
	routed = "house"
	fell_back = true
	Game.notify.emit("You call the fall back. %s take what they came for." % _foe(), Game.COLOR_BAD)
	return true


## Raiders still standing, and yours ({ours, theirs}).
## Who you're fighting, for the news: "The raiders", or a noble house's men.
func _foe() -> String:
	return "Their men" if state.military.raid.has("host") else "The raiders"


func standing() -> Dictionary:
	var o := ours.filter(func(f: Dictionary) -> bool: return not f["down"]).size()
	if not heir_f.is_empty() and heir_f["joined"] and not heir_f["down"]:
		o += 1
	return {"ours": o, "theirs": theirs.filter(func(f: Dictionary) -> bool: return not f["down"] and not f["fled"]).size()}


# --- The end ---------------------------------------------------------------------------------

func _house_side() -> Array:
	var all: Array = ours.duplicate()
	if not heir_f.is_empty() and heir_f["joined"]:
		all.append(heir_f)
	return all


## A side breaks when its fallen reach its breaking point (Military), counted
## against those in the fight (a foe close, a blow struck) rather than those
## still running in, but never fewer than most of the side.
static func breaks(side: Array) -> bool:
	if side.is_empty() or side.all(func(f: Dictionary) -> bool: return f["down"] or f.get("fled", false)):
		return true
	var in_fight := side.filter(func(f: Dictionary) -> bool: return f.get("engaged", false) or f["down"]).size()
	var count := maxi(in_fight, ceili(side.size() * 0.6))
	return float(Military.fallen(side)) / count >= Military.breaking_point(side)


func _check_end(dt: float) -> void:
	if routed.is_empty():
		var mine := _house_side()
		if breaks(mine):
			routed = "house"
			Game.notify.emit("Your warband breaks! %s fall on the village." % _foe() if not mine.is_empty() else "No one stands against %s!" % _foe().to_lower(), Game.COLOR_BAD)
		elif breaks(theirs):
			routed = "raiders"
			Game.notify.emit("%s break and run!" % _foe(), Game.COLOR_GOOD)
		elif elapsed > float(_k.get("max_seconds", 240)):
			var a := float(Military.fallen(mine)) / maxf(1.0, mine.size())
			var b := float(Military.fallen(theirs)) / maxf(1.0, theirs.size())
			routed = "house" if a > b else "raiders"
		return
	_after += dt
	if _after >= AFTERMATH:
		finish()


## Ends the fight: what it cost and won (Military.finish), and everyone back
## to their day.
func finish() -> void:
	if over:
		return
	over = true
	var winner := "raiders" if routed == "house" else "house"
	var events: Array[Dictionary] = []
	var house := _house_side()
	for f: Dictionary in house + theirs:
		f.erase("npc")
	var report := Military.finish(state, winner, house, theirs, events)
	for npc in _own_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_own_npcs.clear()
	for npc: NPC in world.npcs.values():
		if npc.fighting:
			npc.fighting = false
			npc.driven = npc == world.player_npc()
			npc.model.set_weapons([])
			npc.set_anim("idle")
			var bar := npc.get_node_or_null("HealthBar")
			if bar:
				bar.queue_free()
			npc.brain.replan()
	for npc in _sheltered:
		if is_instance_valid(npc):
			npc.brain.set_errand({})
	var me := world.player_npc()
	if me:
		me.model.set_weapons([])
		me.set_anim("idle")
	finished.emit(report, events)
	queue_free()


# --- Bars ------------------------------------------------------------------------------------

## A bar's size at one meter from the camera (fixed on screen).
const BAR_W := 0.05
const BAR_H := 0.0075


## A bar over their head: what's left of them (green yours, red theirs).
func _add_bar(npc: NPC, f: Dictionary) -> void:
	var old := npc.get_node_or_null("HealthBar")
	if old:
		old.free()
	var bar := Node3D.new()
	bar.name = "HealthBar"
	bar.position.y = npc.model.head_height() + 0.42
	npc.add_child(bar)
	var back := MeshInstance3D.new()
	back.name = "Back"
	var bq := QuadMesh.new()
	bq.size = Vector2(BAR_W + 0.004, BAR_H + 0.004)
	back.mesh = bq
	back.material_override = _bar_material(Color(0.08, 0.06, 0.05, 0.85), 1)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(back)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var fq := QuadMesh.new()
	fq.size = Vector2(BAR_W, BAR_H)
	fill.mesh = fq
	fill.material_override = _bar_material(UITheme.GOOD if f["side"] == "house" else UITheme.BAD, 2)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(fill)


static func _bar_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.fixed_size = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = priority
	return m


func _update_bars() -> void:
	for f: Dictionary in ours + theirs:
		var npc: NPC = f.get("npc")
		if npc == null or not is_instance_valid(npc):
			continue
		var bar := npc.get_node_or_null("HealthBar")
		if bar == null:
			continue
		var frac := clampf(float(f["hp"]) / float(f["max_hp"]), 0.0, 1.0)
		var q := (bar.get_node("Fill") as MeshInstance3D).mesh as QuadMesh
		q.size = Vector2(BAR_W * frac, BAR_H)
		q.center_offset = Vector3(-BAR_W * (1.0 - frac) * 0.5, 0.0, 0.0)
		bar.visible = not f["down"] and not f["fled"] and npc.visible
