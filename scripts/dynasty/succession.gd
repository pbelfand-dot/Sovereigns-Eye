class_name Succession
extends RefCounted
## Phase 4.3, succession. You live and die like everyone else (LifeSystem's
## curve, with a warning when your health fails); when you die you play on
## as your heir: the child you named, else your eldest, else a grandchild,
## else the nearest kin of the house. A ruler not yet of age rules through
## a regent, whose Administration helps or hurts the house's income and
## who may skim from it if their loyalty is thin. Only an empty house ends
## the game. Also: the house's rulers in turn and its family tree.
##
## Static and deterministic. Numbers: data/succession.json.


static func cfg() -> Dictionary:
	return GameData.load_file("succession")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


static func of_age() -> int:
	return int(section("regency").get("of_age", 16))


# --- The heir --------------------------------------------------------------------------------

## `c`'s living children, eldest first.
static func children_of(state: WorldState, c: CharacterData) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	if c == null:
		return out
	for r in c.relationships_of_type(["child"]):
		var k := state.get_character(int(r["target"]))
		if k:
			out.append(k)
	out.sort_custom(_eldest_first)
	return out


static func _eldest_first(a: CharacterData, b: CharacterData) -> bool:
	return a.age > b.age if a.age != b.age else a.id < b.id


## Grown before young, then the eldest.
static func _before(a: CharacterData, b: CharacterData) -> bool:
	if b == null:
		return true
	if a.is_adult() != b.is_adult():
		return a.is_adult()
	return _eldest_first(a, b)


## Your heir: the child you named, else your eldest (null if childless).
static func heir(state: WorldState) -> CharacterData:
	var p := state.player()
	if p == null or state.house == null:
		return null
	var kids := children_of(state, p)
	var named := state.get_character(state.house.heir_id)
	if named and kids.has(named):
		return named
	return kids[0] if not kids.is_empty() else null


## Whether `c` is the heir you named (not just the eldest by default).
static func is_named(state: WorldState, c: CharacterData) -> bool:
	return state.house != null and c != null and state.house.heir_id == c.id and heir(state) == c


## Who would go on after `c` (the player): the heir, else a grandchild,
## else a brother or sister of the house, else a husband or wife, else
## anyone of the house (grown first, eldest first). Null: no one is left.
static func successor(state: WorldState, c: CharacterData) -> CharacterData:
	var h := heir(state)
	if h:
		return h
	var best: CharacterData = null
	for r in c.relationships_of_type(["grandchild"]):
		var g := state.get_character(int(r["target"]))
		if g and _before(g, best):
			best = g
	if best:
		return best
	for r in c.relationships_of_type(["sibling"]):
		var s := state.get_character(int(r["target"]))
		if s and CourtSystem.is_kin(state, s) and _before(s, best):
			best = s
	if best:
		return best
	var spouse := LifeSystem.spouse_of(state, c)
	if spouse and CourtSystem.is_kin(state, spouse):
		return spouse
	var fam := state.ruling_family()
	for id in (fam.member_ids if fam else []):
		var k := state.get_character(id)
		if k and k != c and not k.is_visitor() and _before(k, best):
			best = k
	return best


## Names `child` (one of yours) your heir. Older children passed over take
## it ill, once each. {ok, text}
static func name_heir(state: WorldState, child: CharacterData) -> Dictionary:
	var p := state.player()
	var kids := children_of(state, p)
	if child == null or not kids.has(child):
		return {"ok": false, "text": "Only your own children can be named your heir."}
	if is_named(state, child):
		return {"ok": false, "text": "%s is already your heir." % child.first_name}
	state.house.heir_id = child.id
	var h := section("heir")
	var hurt: Array[String] = []
	for k in kids:
		if k.age > child.age and not state.house.passed_over.has(k.id):
			state.house.passed_over.append(k.id)
			k.player_opinion = clampf(k.player_opinion + float(h.get("passed_over_opinion", -30)), -100.0, 100.0)
			if k.retainer:
				k.loyalty = clampf(k.loyalty + float(h.get("passed_over_loyalty", -15)), 0.0, 100.0)
			hurt.append(k.first_name)
	var text := "You name %s your heir." % child.full_name()
	if not hurt.is_empty():
		text += " %s, passed over, won't soon forget it." % " and ".join(hurt)
	state.house.log_event(state.day(), "%s named %s heir to %s." % [p.display_name(), child.full_name(), CourtSystem.house_name(state)], "house")
	return {"ok": true, "text": text}


# --- Health ----------------------------------------------------------------------------------

## Past the age where death comes often (data "health" warn_yearly).
static func failing(c: CharacterData) -> bool:
	return c != null and LifeSystem.death_yearly(c.age) >= float(section("health").get("warn_yearly", 0.025))


# --- The ruler and the regency ---------------------------------------------------------------

static func ruler(state: WorldState) -> CharacterData:
	var fam := state.ruling_family()
	return state.get_character(fam.head_id) if fam else null


## The player rules but is not yet of age.
static func minority(state: WorldState) -> bool:
	var p := state.player()
	return p != null and ruler(state) == p and p.age < of_age()


## The regent ruling for you now, or null.
static func regent(state: WorldState) -> CharacterData:
	if state.house == null or not minority(state):
		return null
	return state.get_character(state.house.regent_id)


## Could `c` rule for the young player? {ok, reason}
static func can_be_regent(state: WorldState, c: CharacterData) -> Dictionary:
	if c == null or state.is_player(c):
		return {"ok": false, "reason": ""}
	if not c.is_adult():
		return {"ok": false, "reason": "%s is too young to rule for you." % c.first_name}
	if c.is_visitor():
		return {"ok": false, "reason": "%s is a guest." % c.first_name}
	if not (CourtSystem.is_kin(state, c) or c.retainer):
		return {"ok": false, "reason": "Only your kin or a retainer may rule for you."}
	return {"ok": true, "reason": ""}


## Who rules for a young ruler: a living parent of the house, else the
## eldest grown kin, else the most loyal grown retainer.
static func default_regent(state: WorldState) -> CharacterData:
	var p := state.player()
	if p == null:
		return null
	for r in p.relationships_of_type(["parent"]):
		var par := state.get_character(int(r["target"]))
		if par and can_be_regent(state, par)["ok"]:
			return par
	var best: CharacterData = null
	var fam := state.ruling_family()
	for id in (fam.member_ids if fam else []):
		var k := state.get_character(id)
		if k and can_be_regent(state, k)["ok"] and _before(k, best):
			best = k
	if best:
		return best
	for c in state.retainers():
		if can_be_regent(state, c)["ok"] and (best == null or c.loyalty > best.loyalty):
			best = c
	return best


## Choose who rules for you until you come of age. {ok, text}
static func set_regent(state: WorldState, c: CharacterData) -> Dictionary:
	if not minority(state):
		return {"ok": false, "text": "You rule in your own right."}
	var can := can_be_regent(state, c)
	if not can["ok"]:
		return {"ok": false, "text": str(can["reason"])}
	state.house.regent_id = c.id
	state.house.log_event(state.day(), "%s rules as regent for %s." % [c.full_name(), state.player().full_name()], "office")
	return {"ok": true, "text": "%s will rule for you until you are %d." % [c.full_name(), of_age()]}


## How the regent's Administration moves the house's income (a fraction:
## 0.12 is +12%; a poor regent's is below 0).
static func regent_income_factor(state: WorldState) -> float:
	var r := regent(state)
	if r == null:
		return 0.0
	var k := section("regency")
	return (r.get_current("administration") - float(k.get("income_pivot", 40))) * float(k.get("income_per_point", 0.004))


## Gold a disloyal regent pockets from a day's `income`.
static func regent_skim(state: WorldState, income: int) -> int:
	var r := regent(state)
	var k := section("regency")
	if r == null or r.loyalty >= float(k.get("skim_below", 40)):
		return 0
	return roundi(maxi(income, 0) * float(k.get("skim_share", 0.2)))


# --- Passing on ------------------------------------------------------------------------------

## `heir` becomes head of the house on `old`'s death: the old lord's widow is
## the dowager, the heir's spouse the lady, and a young heir has a regent.
## Returns the new title ("Lord of Wilstead").
static func crown(state: WorldState, heir: CharacterData, old: CharacterData, events: Array[Dictionary]) -> String:
	var fam := state.ruling_family()
	fam.head_id = heir.id
	for r in old.relationships_of_type(["spouse", "late_spouse"]):
		var widow := state.get_character(int(r["target"]))
		if widow and widow != heir and widow.occupation_id in ["lady", "lord"]:
			widow.occupation_id = "dowager"
			events.append({"text": "", "job": widow.id})
	var consort := LifeSystem.spouse_of(state, heir)
	if consort:
		consort.occupation_id = "lady"
		events.append({"text": "", "job": consort.id})
	heir.occupation_id = "lord"
	heir.social_status = "noble"
	heir.work_building_id = CourtSystem._building_of_type(state, "manor")
	if heir.retainer:
		CourtSystem.dismiss(state, heir, false, true)
	var title := "%s of %s" % [heir.occupation_name(), state.village_name]
	heir.add_history(state.current_year(), state.current_season(), "appointment", "Became %s on the death of %s" % [title, old.full_name()])
	events.append({"text": "", "job": heir.id})
	if state.house:
		for r in state.house.rulers:
			if int(r["id"]) == old.id and int(r["to"]) < 0:
				r["to"] = state.day()
		state.house.rulers.append({"id": heir.id, "from": state.day(), "to": -1})
		state.house.regent_id = -1
		if heir.age < of_age() and state.is_player(heir):
			var reg := default_regent(state)
			if reg:
				state.house.regent_id = reg.id
	return title


## The player has died (`dead`, already departed) and `next` (chosen before
## they left, see `successor`) plays on; `was_head` if they ruled. Returns
## the news. With no one left, the house is ended.
static func pass_on(state: WorldState, dead: CharacterData, next: CharacterData, was_head: bool, cause: String, events: Array[Dictionary]) -> String:
	var house := CourtSystem.house_name(state)
	if next == null:
		state.player_id = -1
		state.house.ended = true
		var end := "%s has died of %s, aged %d, and no one of %s is left. The house is ended." % [dead.full_name(), cause, dead.age, house]
		state.house.log_event(state.day(), end, "death")
		events.append({"text": end, "kind": "bad", "ended": true})
		return end
	var tie := str(next.get_relationship(dead.id).get("type", ""))
	if next.retainer:
		CourtSystem.dismiss(state, next, false, true)
	state.player_id = next.id
	_adopt(state, next)
	state.house.heir_id = -1
	state.house.passed_over.clear()
	var title := crown(state, next, dead, events) if was_head else "heir of %s" % house
	var who := next.full_name()
	var his := "her" if dead.gender == "female" else "his"
	match tie:
		"parent":
			who = "%s %s %s" % [his, "son" if next.gender == "male" else "daughter", next.full_name()]
		"grandparent":
			who = "%s %s %s" % [his, "grandson" if next.gender == "male" else "granddaughter", next.full_name()]
		"sibling":
			who = "%s %s %s" % [his, "brother" if next.gender == "male" else "sister", next.full_name()]
		"spouse", "late_spouse":
			who = "%s %s %s" % [his, "husband" if next.gender == "male" else "wife", next.full_name()]
	var text := "%s has died of %s, aged %d. You go on as %s (%d), %s." % [dead.full_name(), cause, dead.age, who, next.age, title]
	var reg := regent(state)
	if reg:
		text += " Until %s is %d, %s rules as regent." % [next.first_name, of_age(), reg.full_name()]
	state.house.log_event(state.day(), text, "death")
	return text


## People's opinion of a new ruler: some of what they thought of the old
## one, the rest their own tie to the new one. The new ruler knows themself
## and their family.
static func _adopt(state: WorldState, next: CharacterData) -> void:
	var keep := float(section("new_ruler").get("keep", 0.6))
	for c in state.characters:
		if c == next:
			continue
		var tie := float(c.get_relationship(next.id).get("opinion", 0))
		c.player_opinion = clampf(c.player_opinion * keep + tie * (1.0 - keep), -100.0, 100.0)
	next.player_opinion = 100.0
	next.appraised = true
	next.met = true
	if next.is_visitor():
		next.visiting_until = -1
	CourtSystem.initialize_meetings(state)


# --- The day ---------------------------------------------------------------------------------

## Once a day, after LifeSystem: your health failing (told once), a regent
## who is gone replaced, a regency ending when you come of age.
## Events: {text, kind, health? / regency_end? / regent?}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var h := state.house
	var p := state.player()
	if h == null or p == null or h.ended:
		return events
	if failing(p) and h.warned_id != p.id:
		h.warned_id = p.id
		var next := successor(state, p)
		var text := "Your health is failing (you are %d). " % p.age
		if next and heir(state) == next:
			text += "%s is your heir; you may name another child from their card." % next.full_name()
		elif next:
			text += "You have no child: the house would pass to %s." % next.full_name()
		else:
			text += "No one of your house would follow you."
		events.append({"text": text, "kind": "bad", "health": true, "character": p.id})
	if minority(state):
		var r := state.get_character(h.regent_id)
		if r == null or not can_be_regent(state, r)["ok"]:
			var nr := default_regent(state)
			h.regent_id = nr.id if nr else -1
			if nr:
				h.log_event(state.day(), "%s now rules as regent for %s." % [nr.full_name(), p.full_name()], "office")
				events.append({"text": "%s now rules as your regent." % nr.full_name(), "kind": "info", "regent": nr.id})
	elif h.regent_id >= 0:
		var old := state.get_person(h.regent_id)
		h.regent_id = -1
		var done := "You come of age and rule %s in your own right." % state.village_name
		if old:
			done += " %s's regency is over." % old.full_name()
		h.log_event(state.day(), done, "office")
		events.append({"text": done, "kind": "good", "regency_end": true, "character": p.id})
	return events


# --- Letting the years pass --------------------------------------------------------------------

## What the house looks like before the years pass (for `summary`).
static func snapshot(state: WorldState) -> Dictionary:
	return {"day": state.day(), "people": state.characters.size(), "gold": state.house.gold if state.house else 0,
		"renown": state.house.renown if state.house else 0, "player": state.player_id}


const STOPS := {
	"visitor": "A suitor has come to the manor.",
	"kin_death": "There has been a death in the family.",
	"succession": "You have died; you go on as your heir.",
	"health": "Your health is failing.",
	"regency_end": "You have come of age.",
	"ended": "The house is ended.",
}


## What happened while the years passed: {from_day, to_day, days, stop
## (reason id or ""), stop_text, people/gold/renown [before, after], counts
## {born, died, left, wed, arrived}, lines (the chronicle since, then the
## rest of the news, each once)}.
static func summary(state: WorldState, before: Dictionary, news: Array, counts: Dictionary, stop: String, days: int) -> Dictionary:
	var lines: Array[String] = []
	if state.house:
		for e in state.house.chronicle:
			if int(e["day"]) > int(before["day"]) and not lines.has(str(e["text"])):
				lines.append(str(e["text"]))
	for t in news:
		if not lines.has(str(t)):
			lines.append(str(t))
	return {"from_day": int(before["day"]), "to_day": state.day(), "days": days, "stop": stop, "stop_text": str(STOPS.get(stop, "")),
		"people": [int(before["people"]), state.characters.size()],
		"gold": [int(before["gold"]), state.house.gold if state.house else 0],
		"renown": [int(before["renown"]), state.house.renown if state.house else 0],
		"counts": counts.duplicate(), "lines": lines}


# --- The family tree -------------------------------------------------------------------------

## The house's family tree from its eldest known forebear down, living and
## departed: [{id, depth, name, born, died (-1 living), living, ruled
## ([from_year, to_year] or []), player, heir, regent, spouses [names]}].
static func tree(state: WorldState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var start := state.player() if state.player() else ruler(state)
	if start == null:
		return rows
	var root := start
	var guard := 0
	while guard < 12:
		guard += 1
		var up: CharacterData = null
		for r in root.relationships_of_type(["parent"]):
			var par := state.get_person(int(r["target"]))
			if par and par.family_id == state.ruling_family_id and (up == null or _ruled(state, par)):
				up = par
		if up == null:
			break
		root = up
	_add_branch(state, root, 0, rows, {})
	return rows


static func _add_branch(state: WorldState, c: CharacterData, depth: int, rows: Array[Dictionary], seen: Dictionary) -> void:
	if seen.has(c.id) or depth > 10:
		return
	seen[c.id] = true
	var spouses: Array[String] = []
	var spouse_ids: Array[int] = []
	for r in c.relationships_of_type(["spouse", "late_spouse"]):
		var s := state.get_person(int(r["target"]))
		if s:
			spouses.append(s.full_name())
			spouse_ids.append(s.id)
	rows.append({"id": c.id, "depth": depth, "name": c.full_name(), "born": born_year(state, c), "died": died_year(c),
		"living": state.get_character(c.id) != null, "ruled": _reign(state, c), "player": state.is_player(c),
		"heir": heir(state) == c, "regent": regent(state) == c, "spouses": spouses, "spouse_ids": spouse_ids})
	for id in spouse_ids:
		seen[id] = true
	var kids: Array[CharacterData] = []
	for r in c.relationships_of_type(["child"]):
		var k := state.get_person(int(r["target"]))
		if k:
			kids.append(k)
	kids.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return born_year(state, a) < born_year(state, b) if born_year(state, a) != born_year(state, b) else a.id < b.id)
	for k in kids:
		_add_branch(state, k, depth + 1, rows, seen)


static func born_year(state: WorldState, c: CharacterData) -> int:
	if c.departed_day >= 0:
		return Calendar.year(c.departed_day * Calendar.MINUTES_PER_DAY) - c.age
	return LifeSystem.birth_year(state, c)


static func died_year(c: CharacterData) -> int:
	if c.departed_day < 0 or c.departed_how != "died":
		return -1
	return Calendar.year(c.departed_day * Calendar.MINUTES_PER_DAY)


static func _ruled(state: WorldState, c: CharacterData) -> bool:
	return state.house != null and state.house.rulers.any(func(r: Dictionary) -> bool: return int(r["id"]) == c.id)


## [from year, to year (-1 still ruling)] if they headed the house, else [].
static func _reign(state: WorldState, c: CharacterData) -> Array:
	if state.house == null:
		return []
	for r in state.house.rulers:
		if int(r["id"]) == c.id:
			var to := int(r["to"])
			return [Calendar.year(int(r["from"]) * Calendar.MINUTES_PER_DAY), Calendar.year(to * Calendar.MINUTES_PER_DAY) if to >= 0 else -1]
	return []
