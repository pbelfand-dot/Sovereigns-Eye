class_name Military
extends RefCounted
## Phase 5.1, the military. Bandits raid the village now and then: you hear
## of them a few days before (warning), and pay them off or fight. Your
## warband is your retainers and knights, the village watch and, if you call
## it, the levy; you may fight too. Fights play out in the village
## (scripts/world/battle.gd) or, when no one is watching (the years passing,
## the sims), are resolved here with the same rules: each blow lands by the
## fighters' Combat, a side breaks when enough of it has fallen (its captain's
## Leadership holds it longer), and anyone who falls may die: real risk, for
## knights and the heir too.
##
## Phase 5.2: the bands live in camps on the realm map. A camp grows, sends
## its whole band to raid, keeps what it takes, and scatters when beaten
## down; the warband can ride out to clear one (fought out of sight on
## arrival), leaving the village the barer while it's away.
##
## Static and deterministic. Numbers: data/military.json.


## Men-at-arms other houses send you take ids from here down (Phase 5.3);
## the bands and the hosts against you, from -1000 down.
const ALLY_ID := -3000


static func cfg() -> Dictionary:
	return GameData.load_file("military")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


# --- Raids -----------------------------------------------------------------------------------

## Once a day: a band is planned (and you're warned) warning_days before it
## comes; on its day it strikes (the world starts the fight at the raid hour;
## tools call `fight`). A raid whose day has passed unfought is fought now.
## Events: {text, kind, raid_warning? / raid?}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var m := state.military
	if m == null or state.house == null or state.house.ended or state.layout == null:
		return events
	var day := state.day()
	var r := section("raids")
	var rng := Seeds.rng(state.world_seed, "raids_%d" % day)
	_expedition_daily(state, events)
	_camps_daily(state, events)
	if m.raid.is_empty():
		if m.next_raid_day < 0:
			m.next_raid_day = maxi(int(r.get("first_day", 30)), day + _gap(rng))
		if day >= m.next_raid_day - int(r.get("warning_days", 2)) and not _raiding_camps(state).is_empty():
			events.append(plan_raid(state, rng))
	elif not bool(m.raid.get("fought", false)):
		if day == int(m.raid["day"]):
			events.append({"text": "%s are here! They'll strike at %d o'clock." % [_cap(str(m.raid["name"])), strike_hour()], "kind": "bad", "raid": true})
		elif day > int(m.raid["day"]):
			fight(state, events)
	return events


## "the Mire Wolves" -> "The Mire Wolves" (only the first letter).
static func _cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _gap(rng: RandomNumberGenerator) -> int:
	return maxi(1, roundi(float(section("raids").get("gap_days", 50)) * rng.randf_range(0.5, 1.5)))


static func strike_hour() -> int:
	return int(section("raids").get("hour", 10))


## A band is coming: how many, from where, what they'd take and what
## they'd take to go away. Returns the warning.
## The band comes from the strongest camp that isn't under attack (a band
## grown to what the village draws is made if there's none, for tools).
static func plan_raid(state: WorldState, rng: RandomNumberGenerator) -> Dictionary:
	var m := state.military
	var r := section("raids")
	var camps := _raiding_camps(state)
	var camp: Dictionary = camps[0] if not camps.is_empty() else make_camp(state, rng, true)["camp"]
	var size := maxi(2, int(camp["men"]))
	var band := str(camp["band"])
	var f: Array = camp["from"]
	var from := Vector3(float(f[0]), float(f[1]), float(f[2]))
	var day := state.day() + int(r.get("warning_days", 2))
	var gold := state.house.gold
	# The house's gold behind a castle's walls is out of reach (CastleSystem).
	var loot_gold := roundi(gold * float(r.get("loot_share", 0.35)) * (1.0 - float(CastleSystem.defence(state)["gold_safe"])))
	var food := state.territory.amount("food") if state.territory else 0.0
	m.raid = {"name": band, "day": day, "size": size, "from": [from.x, from.y, from.z], "road": compass(state, from),
		"loot_gold": loot_gold, "loot_food": roundi(food * float(r.get("loot_food", 0.25))),
		"tribute": maxi(int(r.get("tribute_min", 40)), roundi(loot_gold * float(r.get("tribute_share", 0.6)))),
		"levy": false, "fought": false, "camp": int(camp["id"])}
	m.raiders.clear()
	for i in size:
		m.raiders.append(CharacterGenerator.raider(state, band, i, "raid_%d" % day))
	camp["known"] = true
	var text := "%s, %d strong, have come down the %s road from their camp. They'll strike in %d days unless you pay them %d gold. Court panel (K): Defence.%s" % [
		_cap(band), size, m.raid["road"], int(r.get("warning_days", 2)), int(m.raid["tribute"]), _send_aid(state)]
	state.house.log_event(state.day(), "%s gathered on the %s road, %d strong." % [_cap(band), m.raid["road"], size], "bad")
	return {"text": text, "kind": "bad", "raid_warning": true}


## The band due today and not yet fought (the world starts the fight).
static func due(state: WorldState) -> bool:
	var m := state.military
	return m != null and not m.raid.is_empty() and not bool(m.raid.get("fought", false)) and state.day() >= int(m.raid["day"])


## "north", "east"... of the square.
static func compass(state: WorldState, p: Vector3) -> String:
	var d := p - state.layout.square_center
	if absf(d.x) > absf(d.z):
		return "east" if d.x > 0.0 else "west"
	return "south" if d.z > 0.0 else "north"


## Pay the band to go. {ok, text}
static func pay_off(state: WorldState) -> Dictionary:
	var m := state.military
	if m == null or m.raid.is_empty() or bool(m.raid.get("fought", false)):
		return {"ok": false, "text": "No one is threatening the village."}
	var cost := int(m.raid["tribute"])
	if state.house.gold < cost:
		return {"ok": false, "text": "You haven't the %d gold they ask." % cost}
	state.house.gold -= cost
	state.house.renown = maxi(0, state.house.renown + int(section("after").get("renown_tribute", -2)))
	var camp := m.get_camp(int(m.raid.get("camp", -1)))
	if not camp.is_empty():
		camp["hoard"] = int(camp["hoard"]) + cost
	var text := "You pay %s %d gold, and they move on." % [m.raid["name"], cost]
	if m.raid.has("host"):
		text = Realm.demand_paid(state, int(m.raid["host"]), cost)
	state.house.log_event(state.day(), text, "bad")
	_clear(state)
	return {"ok": true, "text": text}


## Call the levy: the strongest grown villagers take up arms (it costs them
## some happiness). {ok, text}
static func call_levy(state: WorldState) -> Dictionary:
	var m := state.military
	if m == null or m.raid.is_empty() or bool(m.raid.get("levy", false)):
		return {"ok": false, "text": "The levy is called." if m and not m.raid.is_empty() else "There's no one to fight."}
	m.raid["levy"] = true
	var list := levy(state)
	var hit := float(section("warband").get("levy_happiness", -6))
	for c in list:
		c.happiness = clampf(c.happiness + hit, 0.0, 100.0)
	return {"ok": true, "text": "You call the levy: %d villagers take up arms." % list.size()}


static func _clear(state: WorldState) -> void:
	var m := state.military
	m.raid = {}
	m.raiders.clear()
	m.allies.clear()
	m.next_raid_day = state.day() + _gap(Seeds.rng(state.world_seed, "raid_gap_%d" % state.day()))


# --- Who fights ------------------------------------------------------------------------------

static func wounded(state: WorldState, c: CharacterData) -> bool:
	return c.wounded_until > state.day()


## Your warband: retainers and knights (16+), the watch, and the levy if
## it's called. Not the wounded, not you (you fight if you choose to).
static func warband(state: WorldState) -> Array[CharacterData]:
	var w := section("warband")
	var watch: Array = w.get("watch", ["soldier", "guard_captain"])
	var out: Array[CharacterData] = []
	for c in state.characters:
		if state.is_player(c) or c.is_visitor() or c.is_away() or wounded(state, c) or c.age < 16:
			continue
		if c.retainer or c.is_knight() or watch.has(c.occupation_id):
			out.append(c)
	var m := state.military
	if m and not m.raid.is_empty() and bool(m.raid.get("levy", false)):
		for c in levy(state):
			if not out.has(c):
				out.append(c)
	return out


## The levy: the strongest grown villagers, not of the house.
static func levy(state: WorldState) -> Array[CharacterData]:
	var w := section("warband")
	var watch: Array = w.get("watch", [])
	var pool: Array[CharacterData] = []
	for c in state.characters:
		if state.is_player(c) or c.is_visitor() or c.is_away() or CourtSystem.is_kin(state, c) or c.retainer or c.is_knight() or watch.has(c.occupation_id) or wounded(state, c):
			continue
		if c.age >= int(w.get("levy_min_age", 16)) and c.age <= int(w.get("levy_max_age", 55)):
			pool.append(c)
	pool.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.get_current("combat") > b.get_current("combat") if a.get_current("combat") != b.get_current("combat") else a.id < b.id)
	return pool.slice(0, int(w.get("levy_max", 8)))


## How they fight: knight, retainer, watch, levy, heir, raider, leader.
static func role_of(state: WorldState, c: CharacterData) -> String:
	if c.id < 0:
		if c.house_id >= 0:
			# A noble house's men: sent in your aid, or in its host (Phase 5.3).
			if c.id <= ALLY_ID:
				return "ally"
			return "host_knight" if c.is_knight() else "host"
		return "leader" if c.id == -1000 else "raider"
	if state.is_player(c):
		return "heir"
	if c.is_knight():
		return "knight"
	if c.retainer:
		return "retainer"
	if (section("warband").get("watch", []) as Array).has(c.occupation_id):
		return "watch"
	return "levy"


## A fighter's state in a fight.
static func fighter(state: WorldState, c: CharacterData, side: String) -> Dictionary:
	var k := section("combat")
	var role := role_of(state, c)
	var combat := c.get_current("combat")
	if role == "levy":
		combat = maxi(1, combat + int(section("warband").get("levy_combat", -12)))
	return {"id": c.id, "side": side, "name": c.display_name(), "role": role, "combat": combat,
		"leadership": c.get_current("leadership"), "traits": c.traits.duplicate(), "hp": float(k.get("hp", 100)), "max_hp": float(k.get("hp", 100)),
		"down": false, "felled": 0, "hits": 0}


## Both sides as fighters: {ours, theirs}. `heir` adds you to the warband.
static func sides(state: WorldState, heir: bool = false) -> Dictionary:
	var ours: Array[Dictionary] = []
	for c in warband(state):
		ours.append(fighter(state, c, "house"))
	if heir and state.player():
		ours.append(fighter(state, state.player(), "house"))
	# Men-at-arms sent by the noble houses stand with you (Phase 5.3).
	for a in state.military.allies:
		ours.append(fighter(state, a, "house"))
	# At home, a castle: the warband holds its gate (Phase 5.3).
	var wall := CastleSystem.defence(state)
	for f in ours:
		f["combat"] = int(f["combat"]) + int(wall["combat"])
		f["steady"] = float(wall["hold"])
	var theirs: Array[Dictionary] = []
	for r in state.military.raiders:
		theirs.append(fighter(state, r, "raiders"))
	return {"ours": ours, "theirs": theirs}


static func person(state: WorldState, id: int) -> CharacterData:
	if id >= 0:
		return state.get_character(id)
	for r in state.military.raiders:
		if r.id == id:
			return r
	for a in state.military.allies:
		if a.id == id:
			return a
	return null


# --- The fight -------------------------------------------------------------------------------

## The chance a blow lands.
static func hit_chance(att_combat: float, def_combat: float) -> float:
	var k := section("combat")
	var bounds: Array = k.get("hit_range", [0.15, 0.92])
	return clampf(float(k.get("hit_base", 0.55)) + (att_combat - def_combat) * float(k.get("hit_per_point", 0.006)), float(bounds[0]), float(bounds[1]))


## The harm a landed blow does `def`.
static func damage(att: Dictionary, def: Dictionary) -> float:
	var k := section("combat")
	var armor: Dictionary = k.get("armor", {})
	return (float(k.get("damage_base", 10)) + float(att["combat"]) * float(k.get("damage_per_point", 0.16))) * (1.0 - float(armor.get(str(def["role"]), 0.0)))


## `att` swings at `def`: {hit, damage, down}. Changes `def` (and `att`'s tally).
static func strike(att: Dictionary, def: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if def["down"] or att["down"]:
		return {"hit": false, "damage": 0.0, "down": false}
	var hit := rng.randf() < hit_chance(float(att["combat"]), float(def["combat"]))
	var dmg := damage(att, def) * rng.randf_range(0.8, 1.2) if hit else 0.0
	def["hp"] = maxf(0.0, float(def["hp"]) - dmg)
	var down := hit and float(def["hp"]) <= 0.0
	if hit:
		att["hits"] = int(att["hits"]) + 1
	if down:
		def["down"] = true
		att["felled"] = int(att["felled"]) + 1
	return {"hit": hit, "damage": dmg, "down": down}


## The side's captain: the one who leads best.
static func captain(fighters: Array) -> Dictionary:
	var best: Dictionary = {}
	for f: Dictionary in fighters:
		if best.is_empty() or float(f["leadership"]) > float(best["leadership"]):
			best = f
	return best


## The share of a side that must fall before it breaks (its captain's
## Leadership and the fighters' tempers hold it together).
static func breaking_point(fighters: Array) -> float:
	if fighters.is_empty():
		return 0.0
	var k := section("combat")
	var cap := captain(fighters)
	var point := float(k.get("rout_base", 0.35)) + float(cap.get("leadership", 0)) * float(k.get("rout_per_point", 0.003))
	var mods: Dictionary = k.get("traits", {})
	var sum := 0.0
	for f: Dictionary in fighters:
		for t: String in f["traits"]:
			sum += float(mods.get(t, 0.0))
		sum += float(f.get("steady", 0.0))  # walls at their backs (a castle's gate)
	return clampf(point + sum / fighters.size(), 0.15, 0.95)


static func fallen(fighters: Array) -> int:
	return fighters.filter(func(f: Dictionary) -> bool: return f["down"]).size()


## Broken: everyone down, or enough fallen to break the rest.
static func broken(fighters: Array) -> bool:
	if fighters.is_empty():
		return true
	var down := fallen(fighters)
	return down >= fighters.size() or float(down) / fighters.size() >= breaking_point(fighters)


## Fights it out without the world (the years passing, the sims) the way it
## goes in the village (Battle): rounds in which everyone standing strikes
## the foe they're on until it falls, each taking on whoever is least beset,
## until one side breaks. {winner ("house"/"raiders"), ours, theirs, rounds}
static func resolve(ours: Array[Dictionary], theirs: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var rounds := 0
	var on := {}  # fighter (by instance) -> foe dict
	while rounds < 400 and not broken(ours) and not broken(theirs):
		rounds += 1
		var all: Array = ours + theirs
		Seeds.shuffle(rng, all)
		for f: Dictionary in all:
			if f["down"]:
				continue
			var foe: Dictionary = on.get(str(f["side"]) + str(f["id"]), {})
			if foe.is_empty() or foe["down"]:
				foe = _least_beset(f, theirs if f["side"] == "house" else ours, ours if f["side"] == "house" else theirs, on, rng)
				if foe.is_empty():
					break
				on[str(f["side"]) + str(f["id"])] = foe
			strike(f, foe, rng)
	var winner := "raiders" if broken(ours) else "house"
	return {"winner": winner, "ours": ours, "theirs": theirs, "rounds": rounds}


## Your captains' reckoning of the coming fight: the share of `trials`
## fought-out fights (fixed seeds, so it doesn't change by asking) the house
## would win as things stand (the levy if called, you if `heir`).
static func odds(state: WorldState, heir: bool = false, trials: int = 40) -> float:
	if state.military == null or state.military.raid.is_empty():
		return 1.0
	var wins := 0
	for i in trials:
		var s := sides(state, heir)
		if resolve(s["ours"], s["theirs"], Seeds.rng(state.world_seed, "odds_%d_%d" % [state.day(), i]))["winner"] == "house":
			wins += 1
	return float(wins) / trials


## The odds in a word.
static func odds_word(p: float) -> String:
	if p >= 0.85:
		return "certain"
	if p >= 0.65:
		return "good"
	if p >= 0.4:
		return "even"
	if p >= 0.15:
		return "poor"
	return "hopeless"


## The standing foe the fewest of `mates` are already on (ties at random).
static func _least_beset(f: Dictionary, foes: Array, mates: Array, on: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var best: Array = []
	var fewest := 1 << 30
	for o: Dictionary in foes:
		if o["down"]:
			continue
		var n := 0
		for m: Dictionary in mates:
			if not is_same(m, f) and not m["down"] and is_same(on.get(str(m["side"]) + str(m["id"]), {}), o):
				n += 1
		if n < fewest:
			fewest = n
			best = [o]
		elif n == fewest:
			best.append(o)
	return best[rng.randi_range(0, best.size() - 1)] if not best.is_empty() else {}


## The raid fought out of sight (no world): resolve and finish. Returns the
## report; events gain the deaths and the news.
static func fight(state: WorldState, events: Array[Dictionary], heir: bool = false) -> Dictionary:
	if state.military == null or state.military.raid.is_empty():
		return {}
	var s := sides(state, heir)
	var rng := Seeds.rng(state.world_seed, "battle_%d" % state.day())
	var r := resolve(s["ours"], s["theirs"], rng)
	return finish(state, r["winner"], r["ours"], r["theirs"], events)


## What a fight leaves behind (from `fight` or the battle in the village):
## the fallen die or lie wounded (real risk), the rest grow in Combat, the
## house wins renown and the raiders' purse or loses its loot. Returns the
## report {won, band, ours [{id, name, role, felled, fell, died, wounded}],
## size, raiders_fallen, gold, food, renown, day}.
static func finish(state: WorldState, winner: String, ours: Array, theirs: Array, events: Array[Dictionary]) -> Dictionary:
	var m := state.military
	var a := section("after")
	var band := str(m.raid.get("name", "the raiders"))
	var rng := Seeds.rng(state.world_seed, "battle_after_%d" % state.day())
	var won := winner == "house"
	var report := {"won": won, "band": band, "ours": [], "size": theirs.size(), "raiders_fallen": fallen(theirs),
		"gold": 0, "food": 0, "renown": 0, "day": state.day()}
	var dead := _toll(state, ours, report, rng)
	report["allies"] = _allies_report(state, ours)
	if m.raid.has("host"):
		return _finish_host(state, int(m.raid["host"]), won, theirs, report, dead, events)
	var camp := m.get_camp(int(m.raid.get("camp", -1)))
	var scattered := ""
	if won:
		var renown := int(a.get("renown_win", 4)) + fallen(theirs) * int(a.get("renown_per_raider", 1))
		var purse := theirs.size() * int(a.get("purse_per_raider", 12))
		state.house.renown += renown
		state.house.gold += purse
		report["renown"] = renown
		report["gold"] = purse
		if not camp.is_empty():
			camp["men"] = int(camp["men"]) - fallen(theirs)
			if int(camp["men"]) < int(section("camps").get("min_men", 2)):
				scattered = " What's left of them is scattered: their camp is empty."
				_remove_camp(state, camp)
	else:
		var take := mini(int(m.raid.get("loot_gold", 0)), state.house.gold)
		state.house.gold -= take
		if not camp.is_empty():
			camp["hoard"] = int(camp["hoard"]) + take
		var food := 0
		if state.territory:
			food = mini(int(m.raid.get("loot_food", 0)), roundi(state.territory.amount("food")))
			TerritorySystem.add(state, "food", -food)
		for c in state.characters:
			c.happiness = clampf(c.happiness + float(a.get("happiness_loss", -8)), 0.0, 100.0)
		report["gold"] = -take
		report["food"] = -food
	var lost := (report["ours"] as Array).filter(func(l: Dictionary) -> bool: return l["died"]).size()
	var text := ""
	if won:
		text = "Your warband drove off %s: %d of %d raiders fell. %s%s" % [band, fallen(theirs), theirs.size(), "None of yours died." if lost == 0 else "%d of yours died." % lost, scattered]
	elif ours.is_empty():
		text = "No one stood against %s. They took %d gold and %d food." % [band, -int(report["gold"]), -int(report["food"])]
	else:
		text = "%s broke your warband and took %d gold and %d food. %s" % [_cap(band), -int(report["gold"]), -int(report["food"]), "None of yours died." if lost == 0 else "%d of yours died." % lost]
	state.house.log_event(state.day(), text, "office" if won else "bad")
	m.battles += 1
	if won:
		m.won += 1
	m.last_report = report
	_clear(state)
	events.append({"text": text, "kind": "good" if won else "bad", "battle": report})
	for c in dead:
		LifeSystem.die(state, c, "wounds taken fighting %s" % band, events)
	return report


## The chance a fallen fighter dies of their wounds (Gentle fights: far less).
static func death_chance(state: WorldState) -> float:
	var k := section("combat")
	var gentle := state.military != null and state.military.gentle
	return float(k.get("death_chance_gentle", 0.1)) if gentle else float(k.get("death_chance", 0.35))


## Who of `ours` died, who lies wounded and who grew in Combat; each gets a
## line in `report`. Returns the dead (for LifeSystem.die, after the news).
static func _toll(state: WorldState, ours: Array, report: Dictionary, rng: RandomNumberGenerator) -> Array[CharacterData]:
	var k := section("combat")
	var a := section("after")
	var dead: Array[CharacterData] = []
	for f: Dictionary in ours:
		var c := state.get_character(int(f["id"]))
		if c == null:
			continue
		var line := {"id": c.id, "name": c.display_name(), "gender": c.gender, "role": f["role"], "felled": int(f["felled"]), "fell": bool(f["down"]), "died": false, "wounded": false}
		if f["down"]:
			if rng.randf() < death_chance(state):
				line["died"] = true
				dead.append(c)
			else:
				line["wounded"] = true
				c.wounded_until = state.day() + int(k.get("wounded_days", 10))
		else:
			c.train("combat", int(a.get("train_points", 2)) + int(f["felled"]) * int(a.get("train_points_per_kill", 2)))
		(report["ours"] as Array).append(line)
	return dead


# --- Camps (Phase 5.2) -----------------------------------------------------------------------

## The band a village like yours draws: more people, a higher charter and
## more renown draw bigger bands (up to band_max).
static func band_target(state: WorldState) -> int:
	var r := section("raids")
	var size := int(r.get("band_base", 3)) + roundi(state.characters.size() * float(r.get("band_per_people", 0.04))) + CharterSystem.current(state) * int(r.get("band_per_charter", 1)) \
		+ roundi(state.house.renown * float(r.get("band_per_renown", 0.0)))
	return clampi(size, 2, int(r.get("band_max", 14)))


## How many camps the land round a village of this charter holds.
static func max_camps(state: WorldState) -> int:
	var by: Array = section("camps").get("max_by_charter", [1])
	return int(by[clampi(CharterSystem.current(state), 0, by.size() - 1)])


## Camps that may send their band: not one the warband is riding against,
## the strongest first.
static func _raiding_camps(state: WorldState) -> Array[Dictionary]:
	var m := state.military
	var out: Array[Dictionary] = []
	for c in m.camps:
		if m.expedition.is_empty() or int(m.expedition["camp"]) != int(c["id"]):
			out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["men"]) > int(b["men"]) if int(a["men"]) != int(b["men"]) else int(a["id"]) < int(b["id"]))
	return out


## Once a day: a camp is made when the land has room for one and its time
## has come; camps grow toward the band the village draws.
static func _camps_daily(state: WorldState, events: Array[Dictionary]) -> void:
	var m := state.military
	var c := section("camps")
	var day := state.day()
	if m.next_camp_day < 0:
		m.next_camp_day = maxi(int(c.get("first_day", 45)), day + 1)
	if m.camps.size() < max_camps(state) and day >= m.next_camp_day:
		var made := make_camp(state, Seeds.rng(state.world_seed, "camp_%d" % day))
		events.append(made)
		if m.camps.size() == 1:
			m.next_raid_day = maxi(m.next_raid_day, day + int(c.get("first_raid_days", 15)))
	for camp in m.camps:
		if not bool(camp.get("known", true)) and day >= int(camp.get("found", 0)):
			events.append(reveal_camp(state, camp, "Your woodcutters have found where"))
	var grow := maxi(1, int(c.get("grow_days", 10)))
	var target := band_target(state)
	for camp in m.camps:
		var age := day - int(camp["founded"])
		if age > 0 and age % grow == 0 and int(camp["men"]) < target:
			camp["men"] = int(camp["men"]) + 1


static func _camp_gap(state: WorldState) -> int:
	var rng := Seeds.rng(state.world_seed, "camp_gap_%d" % state.day())
	return maxi(1, roundi(float(section("camps").get("gap_days", 70)) * rng.randf_range(0.5, 1.5)))


## A band makes camp on the realm map, out along one of the village's roads
## (its raids come in by that road). `grown`: already as big as the village
## draws (for tools and tests). Returns the news {text, kind, camp_made, camp}.
static func make_camp(state: WorldState, rng: RandomNumberGenerator, grown: bool = false) -> Dictionary:
	var m := state.military
	var c := section("camps")
	var names: Array = section("raids").get("names", ["a band of outlaws"])
	var used := m.camps.map(func(x: Dictionary) -> String: return str(x["band"]))
	var free := names.filter(func(n: String) -> bool: return not used.has(n))
	var band := str(Seeds.pick(rng, free if not free.is_empty() else names))
	var from := GrowthSystem.entry_point(state, rng)
	var map := Realm.map_cfg()
	var days_range: Array = map.get("camp_days", [1, 2])
	var days := rng.randi_range(int(days_range[0]), int(days_range[1]))
	var dir := Vector2(from.x - state.layout.square_center.x, from.z - state.layout.square_center.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.from_angle(rng.randf() * TAU)
	var pos := Realm.center() + dir * days * float(map.get("day_ride", 64))
	var share: Array = c.get("start_share", [0.6, 0.9])
	var hoard: Array = c.get("hoard_start", [10, 30])
	var found: Array = c.get("found_days", [20, 40])
	var men := band_target(state) if grown else maxi(2, roundi(band_target(state) * rng.randf_range(float(share[0]), float(share[1]))))
	var camp := {"id": m.next_camp_id, "band": band, "pos": [float(roundi(pos.x)), float(roundi(pos.y))], "days": days,
		"from": [from.x, from.y, from.z], "road": compass(state, from), "men": men,
		"hoard": rng.randi_range(int(hoard[0]), int(hoard[1])), "founded": state.day(),
		"known": grown, "found": state.day() + rng.randi_range(int(found[0]), int(found[1]))}
	m.next_camp_id += 1
	m.camps.append(camp)
	m.next_camp_day = state.day() + _camp_gap(state)
	var text := "Word in the village: a band has made camp somewhere in the woods round about." if not grown else \
		"%s are camped out along the %s road, %s. Realm map (J)." % [_cap(band), camp["road"], Realm.days_text(days)]
	state.house.log_event(state.day(), "A band made camp in the woods.", "bad")
	return {"text": text, "kind": "bad", "camp_made": int(camp["id"]), "camp": camp}


## Where a band camps becomes known (its raid, or your woodcutters). The
## news, or {} if it was known.
static func reveal_camp(state: WorldState, camp: Dictionary, how: String) -> Dictionary:
	if bool(camp.get("known", true)):
		return {}
	camp["known"] = true
	var text := "%s %s camped out along the %s road, %s. Realm map (J)." % [how, camp["band"], camp["road"], Realm.days_text(int(camp["days"]))]
	state.house.log_event(state.day(), "%s camp along the %s road was found." % [_cap(str(camp["band"])), camp["road"]], "bad")
	return {"text": text, "kind": "bad", "camp_found": int(camp["id"])}


## Camps whose place you know (on the map, open to attack).
static func known_camps(state: WorldState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in state.military.camps:
		if bool(c.get("known", true)):
			out.append(c)
	return out


static func _remove_camp(state: WorldState, camp: Dictionary) -> void:
	var m := state.military
	m.camps.erase(camp)
	m.next_camp_day = maxi(m.next_camp_day, state.day() + _camp_gap(state))


# --- Riding against a camp (Phase 5.2) -------------------------------------------------------

## Who rides out: retainers, knights and the watch fit to fight (not the
## levy, who won't leave their fields).
static func riders(state: WorldState) -> Array[CharacterData]:
	var w := section("warband")
	var watch: Array = w.get("watch", ["soldier", "guard_captain"])
	var out: Array[CharacterData] = []
	for c in state.characters:
		if state.is_player(c) or c.is_visitor() or c.is_away() or wounded(state, c) or c.age < 16:
			continue
		if c.retainer or c.is_knight() or watch.has(c.occupation_id):
			out.append(c)
	return out


## The camp's band as fighters, on their own ground (home_combat).
static func camp_band(state: WorldState, camp: Dictionary) -> Array[Dictionary]:
	var theirs: Array[Dictionary] = []
	var bonus := int(section("camps").get("home_combat", 6))
	for i in maxi(1, int(camp["men"])):
		var r := CharacterGenerator.raider(state, str(camp["band"]), i, "camp_%d" % int(camp["id"]))
		var f := fighter(state, r, "raiders")
		f["combat"] = int(f["combat"]) + bonus
		theirs.append(f)
	return theirs


## The fight at the camp: the riders (or the party already out) and you if
## you lead them, against the band.
static func camp_sides(state: WorldState, camp: Dictionary, heir: bool, party: Array = []) -> Dictionary:
	var ours: Array[Dictionary] = []
	var people: Array[CharacterData] = riders(state)
	if not party.is_empty():
		people.clear()
		for id: int in party:
			var c := state.get_character(id)
			if c and not state.is_player(c) and not wounded(state, c):
				people.append(c)
	for c in people:
		ours.append(fighter(state, c, "house"))
	if heir and state.player():
		ours.append(fighter(state, state.player(), "house"))
	return {"ours": ours, "theirs": camp_band(state, camp)}


## The captains' reckoning of an attack on the camp (as for a raid).
static func camp_odds(state: WorldState, camp_id: int, heir: bool = false, trials: int = 40) -> float:
	var camp := state.military.get_camp(camp_id)
	if camp.is_empty():
		return 0.0
	var wins := 0
	for i in trials:
		var s := camp_sides(state, camp, heir)
		if s["ours"].is_empty():
			return 0.0
		if resolve(s["ours"], s["theirs"], Seeds.rng(state.world_seed, "camp_odds_%d_%d_%d" % [camp_id, state.day(), i]))["winner"] == "house":
			wins += 1
	return float(wins) / trials


## Can the warband ride against this camp now? {ok, reason}
static func can_ride(state: WorldState, camp_id: int, heir: bool = false) -> Dictionary:
	var m := state.military
	var camp := m.get_camp(camp_id)
	if camp.is_empty():
		return {"ok": false, "reason": "That camp is gone."}
	if not bool(camp.get("known", true)):
		return {"ok": false, "reason": "No one knows where they camp yet."}
	if not m.expedition.is_empty():
		return {"ok": false, "reason": "Your warband is already away."}
	if not m.raid.is_empty() and int(m.raid.get("camp", -1)) == camp_id:
		return {"ok": false, "reason": "Their band is already on the road to you: meet them at home."}
	if due(state):
		return {"ok": false, "reason": "A band strikes today: your warband is needed at home."}
	if riders(state).is_empty() and not heir:
		return {"ok": false, "reason": "You have no one to send: no retainers, knights or watch fit to fight."}
	return {"ok": true, "reason": ""}


## The warband rides against a camp (and you with it if `heir`): a camp's
## days there, the fight on arrival, the same days home. {ok, text, away [ids]}
static func ride_out(state: WorldState, camp_id: int, heir: bool = false) -> Dictionary:
	var can := can_ride(state, camp_id, heir)
	if not can["ok"]:
		return {"ok": false, "text": can["reason"], "away": []}
	var m := state.military
	var camp := m.get_camp(camp_id)
	var day := state.day()
	var days := int(camp["days"])
	var party: Array[int] = []
	for c in riders(state):
		party.append(c.id)
	m.expedition = {"camp": camp_id, "band": str(camp["band"]), "party": party, "heir": heir,
		"depart": day, "fight": day + days, "back": day + 2 * days, "fought": false}
	var away: Array[int] = party.duplicate()
	if heir and state.player():
		away.append(state.player().id)
	for id in away:
		var c := state.get_character(id)
		c.away_at = "camp"
		c.away_until = day + 2 * days
	var text := "%s ride%s out against %s, %s. %s" % ["You and your warband" if heir else "Your warband (%d)" % party.size(), "" if heir or party.size() != 1 else "s",
		camp["band"], Realm.days_text(days), "The village is the barer while they're away." if not party.is_empty() else ""]
	state.house.log_event(day, "The warband rode out against %s." % camp["band"], "office")
	return {"ok": true, "text": text.strip_edges(), "away": away}


## The expedition's days: the fight on arrival, home again after.
static func _expedition_daily(state: WorldState, events: Array[Dictionary]) -> void:
	var m := state.military
	if m.expedition.is_empty():
		return
	var day := state.day()
	if not bool(m.expedition["fought"]) and day >= int(m.expedition["fight"]):
		_fight_camp(state, events)
	if not m.expedition.is_empty() and day >= int(m.expedition["back"]):
		_ride_home(state, events)


static func _fight_camp(state: WorldState, events: Array[Dictionary]) -> void:
	var m := state.military
	var x := m.expedition
	x["fought"] = true
	var camp := m.get_camp(int(x["camp"]))
	if camp.is_empty():
		events.append({"text": "Your warband found the camp of %s empty: the band is scattered." % x["band"], "kind": "info"})
		return
	var heir := bool(x["heir"]) and state.player() != null and state.player().away_at == "camp"
	var s := camp_sides(state, camp, heir, x["party"])
	if s["ours"].is_empty():
		events.append({"text": "No one was left to fight at the camp of %s." % x["band"], "kind": "bad"})
		return
	var r := resolve(s["ours"], s["theirs"], Seeds.rng(state.world_seed, "camp_fight_%d" % state.day()))
	finish_camp(state, camp, r["winner"], r["ours"], r["theirs"], events)


## What the fight at a camp leaves: the toll on yours as in any fight; won,
## the camp is gone (its hoard and the band's purses are yours, renown, and
## the houses near it are grateful); lost, the band holds and grows bolder.
static func finish_camp(state: WorldState, camp: Dictionary, winner: String, ours: Array, theirs: Array, events: Array[Dictionary]) -> Dictionary:
	var m := state.military
	var a := section("after")
	var band := str(camp["band"])
	var rng := Seeds.rng(state.world_seed, "camp_after_%d" % state.day())
	var won := winner == "house"
	var report := {"won": won, "band": band, "ours": [], "size": theirs.size(), "raiders_fallen": fallen(theirs),
		"gold": 0, "food": 0, "renown": 0, "day": state.day(), "camp": true}
	var dead := _toll(state, ours, report, rng)
	var lost := dead.size()
	var text := ""
	if won:
		var gold := int(camp["hoard"]) + theirs.size() * int(a.get("purse_per_raider", 12))
		var renown := int(section("camps").get("renown_clear", 6)) + fallen(theirs) * int(a.get("renown_per_raider", 1))
		state.house.gold += gold
		state.house.renown += renown
		report["gold"] = gold
		report["renown"] = renown
		var grateful := Realm.camp_cleared(state, camp)
		report["grateful"] = grateful
		_remove_camp(state, camp)
		text = "Your warband took the camp of %s: %d of %d fell and the rest fled. Their hoard of %d gold is yours. %s%s" % [band, fallen(theirs), theirs.size(), gold,
			"None of yours died." if lost == 0 else "%d of yours died." % lost, (" %s %s grateful." % [", ".join(grateful), "is" if grateful.size() == 1 else "are"]) if not grateful.is_empty() else ""]
	else:
		camp["men"] = mini(int(camp["men"]) + 1, int(section("raids").get("band_max", 14)))
		text = "%s held their camp against your warband. %s" % [_cap(band), "None of yours died." if lost == 0 else "%d of yours died." % lost]
	state.house.log_event(state.day(), text, "office" if won else "bad")
	m.battles += 1
	if won:
		m.won += 1
	m.last_report = report
	events.append({"text": text, "kind": "good" if won else "bad", "battle": report})
	for c in dead:
		LifeSystem.die(state, c, "wounds taken at the camp of %s" % band, events)
	return report


static func _ride_home(state: WorldState, events: Array[Dictionary]) -> void:
	var m := state.military
	var back: Array[int] = []
	for c in state.characters:
		if c.away_at == "camp":
			c.away_at = ""
			c.away_until = -1
			back.append(c.id)
	var band := str(m.expedition.get("band", "the band"))
	m.expedition = {}
	if not back.is_empty():
		events.append({"text": "Your warband is home from the camp of %s." % band, "kind": "info", "back": back})


# --- The noble houses in your fights (Phase 5.3) -------------------------------------------------

## The houses that send men-at-arms against the coming raid (Realm.aid_offers):
## their men are made and the raid notes whose. The news, or "".
static func _send_aid(state: WorldState) -> String:
	var m := state.military
	m.raid["allies"] = Realm.aid_offers(state)
	make_allies(state)
	var names: Array[String] = []
	for s: Dictionary in m.raid["allies"]:
		names.append("%s sends %d men-at-arms" % [state.realm.house_title(int(s["house"])), int(s["men"])])
	return (" " + "; ".join(names) + " to stand with you.") if not names.is_empty() else ""


## The men-at-arms sent in aid, made from the raid's "allies" (the same men
## for the same raid).
static func make_allies(state: WorldState) -> void:
	var m := state.military
	m.allies.clear()
	var aid := Realm.section("aid")
	var n := 0
	for s: Dictionary in m.raid.get("allies", []):
		var house := state.realm.get_house(int(s["house"]))
		for i in int(s["men"]):
			m.allies.append(CharacterGenerator.house_soldier(state, house, ALLY_ID - n, false, aid.get("combat", [30, 50]), "aid_%d_%d_%d" % [int(m.raid.get("day", 0)), int(s["house"]), i]))
			n += 1


## Who of the houses' men fought, and how many fell: [{house, men, fell}].
static func _allies_report(state: WorldState, ours: Array) -> Array:
	var by := {}
	for f: Dictionary in ours:
		if str(f["role"]) != "ally":
			continue
		var a := person(state, int(f["id"]))
		var key := a.house_id if a else -1
		if not by.has(key):
			by[key] = {"house": state.realm.house_title(key) if state.realm else "", "men": 0, "fell": 0}
		by[key]["men"] += 1
		if f["down"]:
			by[key]["fell"] += 1
	return by.values()


## A noble house comes against you: it demands gold, or its host marches by
## the road from its seat and strikes on the day it gave (fought like a
## raid; paying the demand sends it home). The news.
static func plan_host(state: WorldState, house_id: int, rng: RandomNumberGenerator) -> Dictionary:
	var m := state.military
	var k := Realm.section("hosts")
	var house := state.realm.get_house(house_id)
	var size := clampi(int(k.get("host_base", 5)) + roundi(int(house["renown"]) / float(k.get("host_per_renown", 12))), 3, int(k.get("host_max", 14)))
	var demand := maxi(int(k.get("demand_min", 80)), roundi(state.house.gold * float(k.get("demand_share", 0.3))))
	var toward := Realm.pos_of(house) - Realm.center()
	var from := _entry_toward(state, Vector3(toward.x, 0, toward.y))
	var day := state.day() + int(k.get("days_to_pay", 4))
	var name := "the host of House %s" % house["name"]
	var take := roundi(demand * float(k.get("take_share", 1.5)) * (1.0 - float(CastleSystem.defence(state)["gold_safe"])))
	m.raid = {"name": name, "day": day, "size": size, "from": [from.x, from.y, from.z], "road": compass(state, from),
		"loot_gold": take, "loot_food": 0, "tribute": demand, "levy": false, "fought": false, "host": house_id}
	m.raiders.clear()
	var knights := maxi(1, roundi(size * float(k.get("knights", 0.3))))
	for i in size:
		var knight := i < knights
		m.raiders.append(CharacterGenerator.house_soldier(state, house, -1000 - i, knight, k.get("knight_combat" if knight else "combat", [30, 50]), "host_%d_%d" % [house_id, state.day()] + "/%d" % i))
	var text := "%s demands %d gold of you. Pay by %s, or %s comes against you %d strong by the %s road. Court panel (K): Defence.%s" % [
		state.realm.house_title(house_id), demand, Calendar.format_date(day * Calendar.MINUTES_PER_DAY), house["head"], size, m.raid["road"], _send_aid(state)]
	state.house.log_event(state.day(), "%s demanded %d gold, or war." % [state.realm.house_title(house_id), demand], "bad")
	return {"text": text, "kind": "bad", "raid_warning": true, "host": house_id}


## The road end nearest the way toward `dir` (from the square).
static func _entry_toward(state: WorldState, dir: Vector3) -> Vector3:
	var best := state.layout.square_center
	var best_dot := -INF
	var names: Array = GrowthSystem.growth_cfg().get("entry_roads", [])
	for road in state.layout.roads:
		if not names.has(str(road.get("name", ""))):
			continue
		var pts: PackedVector3Array = road["points"]
		var end := pts[pts.size() - 1].lerp(pts[pts.size() - 2], 0.15)
		var d := (end - state.layout.square_center).normalized().dot(dir.normalized())
		if d > best_dot:
			best_dot = d
			best = end
	return best


## What a host's fight leaves: beaten, the house pays ransom for its fallen
## knights, you win renown and it keeps the peace; winning, it takes its
## demand and more, and your house is thought less of.
static func _finish_host(state: WorldState, house_id: int, won: bool, theirs: Array, report: Dictionary, dead: Array[CharacterData], events: Array[Dictionary]) -> Dictionary:
	var m := state.military
	var k := Realm.section("hosts")
	var band := str(m.raid.get("name", "the host"))
	var house := state.realm.get_house(house_id)
	var lost := dead.size()
	var text := ""
	report["host"] = true
	if won:
		var knights := theirs.filter(func(f: Dictionary) -> bool: return f["down"] and str(f["role"]) == "host_knight").size()
		var ransom := knights * int(k.get("ransom_per_knight", 40))
		state.house.gold += ransom
		state.house.renown += int(k.get("renown_win", 10))
		report["gold"] = ransom
		report["renown"] = int(k.get("renown_win", 10))
		house["standing"] = maxi(int(house["standing"]), int(k.get("after_regard", -10)))
		var knights_text := "none of them knights" if knights == 0 else ("%d of them %s, ransomed for %d gold" % [knights, "a knight" if knights == 1 else "knights", ransom])
		text = "You beat back %s: %d of %d fell, %s. %s %s will keep the peace." % [band, fallen(theirs), theirs.size(), knights_text,
			"None of yours died." if lost == 0 else "%d of yours died." % lost, house["head"]]
	else:
		var take := mini(int(m.raid.get("loot_gold", 0)), state.house.gold)
		state.house.gold -= take
		state.house.renown = maxi(0, state.house.renown + int(k.get("renown_loss", -6)))
		report["gold"] = -take
		report["renown"] = int(k.get("renown_loss", -6))
		text = "%s broke your warband and took %d gold. %s" % [_cap(band), take, "None of yours died." if lost == 0 else "%d of yours died." % lost]
	house["truce"] = state.day() + int(k.get("truce_days", 80))
	state.house.log_event(state.day(), text, "office" if won else "bad")
	m.battles += 1
	if won:
		m.won += 1
	m.last_report = report
	_clear(state)
	events.append({"text": text, "kind": "good" if won else "bad", "battle": report})
	for c in dead:
		LifeSystem.die(state, c, "wounds taken fighting %s" % band, events)
	return report
