class_name NPCBrain
extends RefCounted
## Lightweight daily-routine AI.
##
## The occupation's schedule (data/schedules.json) says what the person should
## be doing this hour: sleep, home, work, leisure or play. The brain turns that
## into a short queue of steps ("go", "enter", "stay") and refills the queue
## when it runs out, so people keep moving between spots during long blocks.
## Traits bias leisure choices (gregarious -> tavern, devout -> chapel...).
##
## Future political/recruitment AI can sit beside this: it only needs to add
## new activities or override the schedule.

var npc: NPC
var c: CharacterData
var world: VillageWorld
var rng := RandomNumberGenerator.new()

var block_activity := ""
var _steps: Array[Dictionary] = []
var _current: Dictionary = {}
var _stay_left := 0.0
## Personal clock offset (hours) so the village doesn't move in lockstep.
var _offset := 0.0
## An order that overrides the daily routine:
##   {type: "hold", face: Vector3} stand still, e.g. while the heir speaks
##   with them
var errand: Dictionary = {}


func _init(body: NPC, owner_world: VillageWorld) -> void:
	npc = body
	c = body.character
	world = owner_world
	rng.seed = Seeds.derive(world.state.world_seed, "brain_%d" % c.id)
	_offset = rng.randf_range(-0.35, 0.35)
	if c.has_trait("diligent"):
		_offset -= 0.25
	elif c.has_trait("lazy"):
		_offset += 0.4


func schedule_id() -> String:
	var court := CourtSystem.schedule_for(c)
	if not court.is_empty():
		return court
	return str(c.occupation().get("schedule", "worker"))


## Drops the current plan (e.g. after joining the household or changing
## office) so the next step follows the new duties.
func replan() -> void:
	block_activity = ""
	_steps.clear()
	_current = {}


func activity_at(hour: float) -> String:
	var h := fposmod(hour + _offset, 24.0)
	for block: Array in GameData.schedule(schedule_id()):
		if h >= float(block[0]) and h < float(block[1]):
			var activity := str(block[2])
			if activity == "play" and c.age >= 16:
				return "leisure"
			if activity == "leisure" and c.age < 12:
				return "play"
			return activity
	return "home"


## Gives the brain an order (see `errand`); {} returns to the routine.
func set_errand(e: Dictionary) -> void:
	errand = e
	_steps.clear()
	_current = {}
	if e.is_empty():
		block_activity = ""


func _errand_update(_game_minutes: float) -> void:
	match str(errand.get("type", "")):
		"hold":
			if c.inside_building_id >= 0:
				_leave_building()
			npc.stop()
			npc.set_anim("talk")
			if errand.has("face"):
				npc.face_point(errand["face"])
		_:
			set_errand({})


## Called every frame with the in-game minutes that passed.
func update(game_minutes: float) -> void:
	if not errand.is_empty():
		if game_minutes > 0.0 or str(errand.get("type", "")) == "hold":
			_errand_update(game_minutes)
		return
	var activity := activity_at(Calendar.hour_f(world.state.minutes))
	if activity != block_activity:
		block_activity = activity
		c.activity = activity
		_steps.clear()
		_current = {}
	if game_minutes > 0.0:
		MoodSystem.activity_update(c, block_activity, game_minutes / 60.0)
		_advance(game_minutes)


func _advance(game_minutes: float) -> void:
	if _current.is_empty():
		if _steps.is_empty():
			_plan(block_activity)
		if _steps.is_empty():
			return
		_start(_steps.pop_front())
		return
	match str(_current["type"]):
		"go":
			if not npc.is_moving():
				_current = {}
		"stay":
			_stay_left -= game_minutes
			if _stay_left <= 0.0:
				_current = {}
		_:
			_current = {}


func _start(step: Dictionary) -> void:
	_current = step
	match str(step["type"]):
		"go":
			if c.inside_building_id >= 0:
				_leave_building()
			npc.walk_path(world.graph.find_path(npc.global_position, step["pos"]))
			npc.set_anim("idle")
			c.activity_text = str(step.get("text", "Walking"))
		"enter":
			var b := world.state.get_building(int(step["building"]))
			if b:
				npc.teleport(b.door_position())
				c.inside_building_id = b.id
				npc.set_inside(true)
			c.activity_text = str(step.get("text", ""))
			_current = {}
		"stay":
			_stay_left = float(step["minutes"])
			npc.set_anim(str(step.get("anim", "idle")))
			npc.face_point(step.get("face", null))
			c.activity_text = str(step.get("text", ""))


func _leave_building() -> void:
	var b := world.state.get_building(c.inside_building_id)
	if b:
		npc.teleport(b.door_position())
	c.inside_building_id = -1
	npc.set_inside(false)


# --- Step helpers --------------------------------------------------------------------

func _go(pos: Vector3, text: String) -> void:
	_steps.append({"type": "go", "pos": TerrainHeight.on_ground(pos), "text": text})


func _enter(building_id: int, text: String) -> void:
	_steps.append({"type": "enter", "building": building_id, "text": text})


func _stay(minutes: float, anim: String, text: String, face: Variant = null) -> void:
	_steps.append({"type": "stay", "minutes": minutes, "anim": anim, "text": text, "face": face})


func _go_inside(b: BuildingData, minutes: float, text: String) -> void:
	if c.inside_building_id != b.id:
		_go(b.door_position(), "Heading to %s" % b.name)
		_enter(b.id, text)
	_stay(minutes, "idle", text)


func _near(p: Vector3, radius: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := rng.randf_range(radius * 0.3, radius)
	return p + Vector3(cos(a) * d, 0, sin(a) * d)


# --- Planning ------------------------------------------------------------------------

func _plan(activity: String) -> void:
	match activity:
		"sleep":
			_plan_sleep()
		"home":
			_plan_home()
		"work":
			var court_style := CourtSystem.work_style(c)
			_plan_work(court_style if not court_style.is_empty() else str(c.occupation().get("work_style", "stationary")))
		"leisure":
			_plan_leisure()
		"play":
			_plan_play()
		_:
			_plan_home()


func _home() -> BuildingData:
	return world.state.get_building(c.home_building_id)


func _plan_sleep() -> void:
	var home := _home()
	if home:
		_go_inside(home, 600.0, "Asleep at home")


func _plan_home() -> void:
	var home := _home()
	if home == null:
		_plan_play()
		return
	if c.age < 6 or rng.randf() < 0.5:
		_go_inside(home, rng.randf_range(40, 90), "Resting at home")
	else:
		var spot := home.door_position() + home.forward() * rng.randf_range(0.5, 2.5) + home.basis() * Vector3(rng.randf_range(-2.5, 2.5), 0, 0)
		_go(spot, "Heading home")
		_stay(rng.randf_range(25, 60), "work" if c.age >= 12 else "idle", "Doing chores at home", home.door_position())


func _plan_work(style: String) -> void:
	var site := TerritorySystem.builder_site(world.state, c)
	if site:
		_plan_build(site)
		return
	var wp := world.state.get_building(c.work_building_id)
	var occ := c.occupation()
	var text := str(occ.get("activity", "Working"))
	if c.retainer:
		text = CourtSystem.work_text(world.state, c)
	match style:
		"stationary":
			if wp == null:
				_plan_home()
			elif rng.randf() < 0.25:
				_go_inside(wp, rng.randf_range(30, 60), text)
			else:
				_go(wp.work_spot(world.worker_slot(c)), "Walking to work")
				_stay(rng.randf_range(50, 110), "work", text, wp.position)
		"estate":
			if wp == null:
				_plan_home()
			elif c.occupation_id == "lord" and rng.randf() < 0.2:
				var p := world.graph.random_square_point(rng)
				_go(p, "Riding out to the village")
				_stay(rng.randf_range(20, 40), "talk", "Inspecting the village", world.state.layout.square_center)
			elif rng.randf() < 0.5:
				_go_inside(wp, rng.randf_range(40, 90), text)
			else:
				_go(wp.work_spot(rng.randi_range(0, 5)), "Walking the grounds")
				_stay(rng.randf_range(20, 50), "talk", text)
		"fields":
			_plan_fields(wp, text)
		"patrol":
			var p := world.graph.random_road_point(rng)
			for i in 6:
				if p.length() < 80.0:
					break
				p = world.graph.random_road_point(rng)
			_go(p, "Patrolling the roads")
			_stay(rng.randf_range(4, 12), "idle", "Standing watch")
		"drill":
			# At the training yard's pells, dummies, quintain and ring (by charter).
			var charter := world.state.territory.charter if world.state.territory else 0
			var spots := PropKit.drill_spots(world.state.layout, charter)
			var dummies := world.state.layout.props_of_type("dummy")
			if not spots.is_empty() and wp != null:
				var spot: Array = spots[world.worker_slot(c) % spots.size()]
				_go(spot[0], "Heading to the training yard")
				_stay(rng.randf_range(40, 80), "work", text, spot[1])
			elif dummies.is_empty() or wp == null:
				_plan_work("patrol")
			else:
				var d: Dictionary = dummies[world.worker_slot(c) % dummies.size()]
				var dpos: Vector3 = d["pos"]
				var stand := dpos + Basis(Vector3.UP, float(d["rot"])) * Vector3(0, 0, 1.4)
				_go(stand, "Heading to the training yard")
				_stay(rng.randf_range(40, 80), "work", text, dpos)
		"market":
			var spots := world.state.layout.market_spots()
			if wp and wp.type == "market":
				# Trading under the Market Hall's arches.
				_go(wp.work_spot(world.worker_slot(c)), "Opening a stall at the market hall")
				_stay(rng.randf_range(60, 120), "talk", text, wp.position)
			elif spots.is_empty():
				_plan_home()
			else:
				_go(spots[c.id % spots.size()], "Opening the market stall")
				_stay(rng.randf_range(60, 120), "talk", text, world.state.layout.square_center)
		"forest":
			var tree := world.random_forest_spot(rng)
			var stand := tree + (Vector3.ZERO - tree).normalized() * 1.2
			_go(stand, "Heading into the woods")
			_stay(rng.randf_range(40, 80), "work", text, tree)
		"assist":
			if wp and wp.type == "farmhouse":
				_plan_fields(wp, "Helping in the fields")
			elif wp:
				_go(wp.work_spot(world.worker_slot(c)), "Off to learn the trade")
				_stay(rng.randf_range(40, 90), "work", text, wp.position)
			else:
				_plan_play()
		"oversee":
			var sites := world.state.territory.sites if world.state.territory else []
			if sites.is_empty():
				_plan_work("estate")
			else:
				var s: ConstructionSite = sites[rng.randi_range(0, sites.size() - 1)]
				_go(TerritorySystem.work_spot(s, 4 + rng.randi_range(0, 1)), "Off to inspect the works")
				_stay(rng.randf_range(30, 60), "talk", "Overseeing the new %s" % TerritorySystem.display_name(s.building.type), s.building.position)
		"play":
			_plan_play()
		"stroll":
			_plan_stroll()
		_:
			_plan_home()


## On a building crew: work at the site instead of the usual job.
func _plan_build(site: ConstructionSite) -> void:
	var spot := TerritorySystem.work_spot(site, site.builders.find(c.id))
	_go(spot, "Off to the building site")
	_stay(rng.randf_range(40, 90), "work", "Building the new %s" % TerritorySystem.display_name(site.building.type), site.building.position)


func _plan_fields(wp: BuildingData, text: String) -> void:
	var fields: Array[Dictionary] = []
	if wp:
		fields = world.state.layout.fields_of_building(wp.id)
	if fields.is_empty():
		fields = world.state.layout.fields
	if fields.is_empty():
		_plan_home()
		return
	var f: Dictionary = fields[rng.randi_range(0, fields.size() - 1)]
	var size: Vector2 = f["size"]
	var local := Vector3(rng.randf_range(-0.4, 0.4) * size.x, 0, rng.randf_range(-0.4, 0.4) * size.y)
	var p: Vector3 = f["center"] + Basis(Vector3.UP, float(f["rot"])) * local
	_go(p, "Heading to the fields")
	_stay(rng.randf_range(25, 60), "work", text, p + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)))


func _plan_play() -> void:
	var home := _home()
	if c.age < 6 and home:
		_go(home.door_position() + home.forward() * rng.randf_range(1.0, 3.0), "Toddling outside")
		_stay(rng.randf_range(10, 25), "idle", "Playing by the door")
		return
	if home == null or rng.randf() < 0.6:
		_go(world.graph.random_square_point(rng), "Running off to play")
		_stay(rng.randf_range(4, 12), "talk", "Playing with other children")
	else:
		_go(_near(home.door_position(), 7.0), "Running off to play")
		_stay(rng.randf_range(4, 12), "talk", "Playing near home")


func _plan_stroll() -> void:
	var benches := world.state.layout.props_of_type("bench")
	if not benches.is_empty() and rng.randf() < 0.5:
		var b: Dictionary = benches[rng.randi_range(0, benches.size() - 1)]
		var bpos: Vector3 = b["pos"]
		_go(bpos + Basis(Vector3.UP, float(b["rot"])) * Vector3(0, 0, 0.8), "Shuffling to the square")
		_stay(rng.randf_range(30, 60), "talk", str(c.occupation().get("activity", "Resting")), world.state.layout.square_center)
	else:
		_go(world.graph.random_square_point(rng), "Taking a slow walk")
		_stay(rng.randf_range(20, 40), "talk", "Watching the village go by")


func _plan_leisure() -> void:
	if c.age < 12:
		_plan_play()
		return
	var weights := {"square": 2.0, "home": 1.0, "stroll": 0.6, "chapel": 0.6}
	if c.age >= 16:
		weights["tavern"] = 1.2
	var friends := c.relationships_of_type(["friend", "lover"])
	if not friends.is_empty():
		weights["visit"] = 1.2
	for t in c.traits:
		var prefs: Dictionary = GameData.trait_def(t).get("leisure", {})
		for k: String in prefs:
			if weights.has(k):
				weights[k] = float(weights[k]) * float(prefs[k])
	if c.age >= 60:
		weights["stroll"] = float(weights["stroll"]) + 1.5
	match Seeds.weighted_key(rng, weights):
		"tavern":
			var taverns := world.state.layout.buildings_of_type("tavern")
			if taverns.is_empty():
				_plan_play()
			else:
				_go_inside(taverns[0], rng.randf_range(40, 100), "Drinking at %s" % taverns[0].name)
		"chapel":
			var chapels := world.state.layout.buildings_of_type("chapel")
			if chapels.is_empty():
				_plan_home()
			else:
				_go_inside(chapels[0], rng.randf_range(30, 60), "Praying at the %s" % chapels[0].name)
		"visit":
			var r: Dictionary = friends[rng.randi_range(0, friends.size() - 1)]
			var friend := world.state.get_character(int(r["target"]))
			var fhome: BuildingData = world.state.get_building(friend.home_building_id) if friend else null
			if fhome == null or fhome.id == c.home_building_id:
				_plan_square()
			else:
				_go(fhome.door_position() + fhome.forward() * 1.5 + fhome.basis() * Vector3(rng.randf_range(-1.5, 1.5), 0, 0), "Going to see %s" % friend.first_name)
				_stay(rng.randf_range(20, 45), "talk", "Visiting %s" % friend.full_name(), fhome.door_position())
		"stroll":
			if c.age >= 60:
				_plan_stroll()
			else:
				var p := world.graph.random_road_point(rng)
				_go(p, "Out for a stroll")
				_stay(rng.randf_range(5, 12), "idle", "Enjoying the air")
		"home":
			_plan_home()
		_:
			_plan_square()


func _plan_square() -> void:
	_go(world.graph.random_square_point(rng), "Wandering to the square")
	_stay(rng.randf_range(10, 25), "talk", "Chatting in the square", world.state.layout.square_center)
