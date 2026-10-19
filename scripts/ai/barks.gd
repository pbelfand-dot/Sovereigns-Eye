class_name Barks
extends RefCounted
## What villagers say aloud as the heir walks past (data/barks.json): a
## greeting that shows what they think of the heir, a word about their work,
## the hour or the season, a worry that is really theirs (hunger, crowding,
## overwork), or a clue to a gift. Never a rank or a number: like talk, a
## remark is a reason to look closer with the Eye, never proof.
##
## `line_for` is pure (deterministic for a given rng). An instance remembers
## who spoke lately, so no one repeats themselves and the village doesn't
## talk all at once. That memory is presentation only and is never saved.

var cfg: Dictionary
var rng: RandomNumberGenerator
var _near: Dictionary = {}
var _said_at: Dictionary = {}
var _last_at := -1.0e9
var _recent: Array[String] = []


func _init(world_seed: int = 0) -> void:
	cfg = config().duplicate(true)
	rng = Seeds.rng(world_seed, "barks")


static func config() -> Dictionary:
	return GameData.load_file("barks")


## How likely `c` is to speak up as the heir comes near.
static func chance_for(c: CharacterData, conf: Dictionary = config()) -> float:
	var p := float(conf.get("chance", 0.4))
	var bias: Dictionary = conf.get("chance_traits", {})
	for t in c.traits:
		p *= float(bias.get(t, 1.0))
	if c.age < int(conf.get("child_age", 13)):
		p *= float(conf.get("child_chance", 1.0))
	return clampf(p, 0.0, 1.0)


## Seconds a remark stays up: long enough to read.
static func duration(text: String, conf: Dictionary = config()) -> float:
	var d: Dictionary = conf.get("duration", {})
	return clampf(float(d.get("base", 2.2)) + text.length() * float(d.get("per_char", 0.045)),
		float(d.get("min", 2.6)), float(d.get("max", 5.5)))


## The heir is `dist` paces from `c` at `now` (seconds): has the heir just
## come near, and does `c` speak up? Once near, they stay quiet until the
## heir has gone past `leave_range` and comes back.
func passing(c: CharacterData, dist: float, now: float) -> bool:
	if dist > float(cfg.get("leave_range", 9.0)):
		_near.erase(c.id)
		return false
	if dist > float(cfg.get("range", 6.0)) or _near.has(c.id):
		return false
	_near[c.id] = true
	if now - _last_at < float(cfg.get("gap", 5.0)):
		return false
	if now - float(_said_at.get(c.id, -1.0e9)) < float(cfg.get("cooldown", 60.0)):
		return false
	return rng.randf() < chance_for(c, cfg)


## What `c` says now (and remembers it was said). "" for nothing.
func remark(state: WorldState, c: CharacterData, now: float) -> String:
	var text := line_for(state, c, rng, _recent, cfg)
	if text.is_empty():
		return ""
	_said_at[c.id] = now
	_last_at = now
	_recent.append(text)
	while _recent.size() > int(cfg.get("recent", 12)):
		_recent.pop_front()
	return text


## A line for `c` to say, avoiding the `recent` ones where it can.
static func line_for(state: WorldState, c: CharacterData, r: RandomNumberGenerator, recent: Array[String] = [], conf: Dictionary = config()) -> String:
	var pools := pools_for(state, c, r, conf)
	var weights := {}
	for key: String in pools:
		weights[key] = float(conf.get("weights", {}).get(key, 1.0))
	var key := Seeds.weighted_key(r, weights)
	if key.is_empty():
		return ""
	var options: Array = pools[key]
	var fresh := options.filter(func(o: Variant) -> bool: return not recent.has(_fill(str(o), state)))
	if fresh.is_empty():
		# All said lately: anything but the very last one.
		fresh = options.filter(func(o: Variant) -> bool: return recent.is_empty() or _fill(str(o), state) != recent[-1])
	return _fill(str(Seeds.pick(r, fresh if not fresh.is_empty() else options)), state)


## {category: [lines]} that fit `c` right now. Only true things: a worry is
## offered only when it's real, a work line only while they work.
static func pools_for(state: WorldState, c: CharacterData, r: RandomNumberGenerator, conf: Dictionary = config()) -> Dictionary:
	var out := {}
	var child := c.age < int(conf.get("child_age", 13))
	out["greet"] = _greeting(state, c, conf, child)
	var activity := c.activity
	if activity == "work" and not child:
		var work: Dictionary = conf.get("work", {})
		var occ := "builder" if TerritorySystem.builder_site(state, c) != null else c.occupation_id
		out["work"] = work.get(occ, work.get("_any", []))
	elif activity in ["leisure", "play", "home"]:
		out["work"] = conf.get("play" if child else activity, [])
	var hour := Calendar.hour_f(state.minutes)
	for when: String in conf.get("hours", {}):
		var span: Array = conf["hours"][when]
		var a := float(span[0])
		var b := float(span[1])
		if (hour >= a and hour < b) if a < b else (hour >= a or hour < b):
			out["time"] = conf.get("time", {}).get(when, [])
	out["season"] = conf.get("season", {}).get(Calendar.season_name(state.whole_minutes()), [])
	if not child:
		var worries := worries_of(state, c, conf)
		if not worries.is_empty():
			out["worry"] = conf.get("worry", {}).get(worries[0], [])
		elif c.happiness > 78.0:
			out["happy"] = conf.get("happy", [])
	var topic := Discovery.pick_topic(c, r)
	if child:
		out["gift"] = conf.get("child_gift", {}).get(topic, [])
	else:
		var levels: Array = conf.get("gift", {}).get(topic, [])
		if not levels.is_empty():
			out["gift"] = levels[mini(Discovery.intensity(c, topic, r), levels.size() - 1)]
		var news := _news(state, conf)
		if not news.is_empty():
			out["village"] = news
	if c.appraised and not child:
		out["eyed"] = conf.get("eyed", [])
	if not child:
		var family: Dictionary = conf.get("family", {})
		var baby := false
		var young := false
		for tie in state.living_ties(c, ["child"]):
			var kid: CharacterData = state.get_character(int(tie["target"]))
			baby = baby or (kid != null and kid.age <= 1)
			young = young or (kid != null and kid.age < 10)
		if baby:
			out["family"] = family.get("baby", [])
		elif young:
			out["family"] = family.get("children", [])
	for key: String in out.keys():
		if (out[key] as Array).is_empty():
			out.erase(key)
	return out


static func _greeting(state: WorldState, c: CharacterData, conf: Dictionary, child: bool) -> Array:
	var greet: Dictionary = conf.get("greet", {})
	if child:
		return greet.get("child", [])
	if c.is_visitor():
		return greet.get("guest", [])
	if CourtSystem.is_kin(state, c):
		return greet.get("kin", [])
	if c.retainer:
		return greet.get("sworn", [])
	if c.player_opinion >= float(conf.get("fond_at", 30)):
		return greet.get("fond", [])
	if c.player_opinion <= float(conf.get("sour_at", -20)):
		return greet.get("sour", [])
	return greet.get("civil", [])


## What really troubles them, most pressing first (ids in barks.json "worry").
static func worries_of(state: WorldState, c: CharacterData, conf: Dictionary = config()) -> Array[String]:
	var out: Array[String] = []
	if TerritorySystem.is_hungry(state):
		out.append("hungry")
	elif state.territory and state.territory.amount("food") < float(TerritorySystem.consumption(state).get("food", 0.0)) * float(conf.get("lean_days", 3)):
		out.append("lean")
	if not MoodSystem.mourning(c, state).is_empty():
		out.append("mourning")
	if c.stress > 60.0:
		out.append("overworked")
	for f: Dictionary in MoodSystem.happiness_factors(c, state):
		match str(f["label"]):
			"Crowded home":
				out.append("crowded")
			"Lonely":
				out.append("lonely")
			"Restless in their work", "Talents go unused":
				out.append("restless")
	if out.is_empty() and c.happiness < 35.0:
		out.append("unhappy")
	return out


## Talk of the village: a building going up, the charter.
static func _news(state: WorldState, conf: Dictionary) -> Array:
	var village: Dictionary = conf.get("village", {})
	var out := []
	if state.territory == null:
		return out
	for s in state.territory.sites:
		if s.kind == "build" and s.building:
			out.append_array(village.get("building", []))
			break
	if CharterSystem.current(state) > 0:
		out.append_array(village.get("charter", []))
	return out


static func _fill(text: String, state: WorldState) -> String:
	if text.contains("{site}") and state.territory:
		for s in state.territory.sites:
			if s.kind == "build" and s.building:
				text = text.replace("{site}", s.building.type_name())
				break
	if text.contains("{charter}"):
		text = text.replace("{charter}", CharterSystem.title(state))
	var filled := Discovery._fill(text, state)
	return filled.substr(0, 1).to_upper() + filled.substr(1)
