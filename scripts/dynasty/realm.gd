class_name Realm
extends RefCounted
## Phase 5.2, the wider realm. The noble houses' seats lie a few days' ride
## out on a map (RealmData); each holds your house in some regard (their
## "standing", -100..100), which fades a little each season and is raised by
## visits, gifts, a good talk, fostering and clearing the bandit camps near
## them (Military). The heir rides out to a seat (the days pass at home
## meanwhile); there: a gift, a talk with the lord or lady, the house's young
## seen with the Eye, a hand asked for your heir or kin (the wedding when you
## come home), a kin child left to be fostered until 16, learning what the
## house is known for.
##
## Static and deterministic. Numbers: data/realm.json.


static func cfg() -> Dictionary:
	return GameData.load_file("realm")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


static func map_cfg() -> Dictionary:
	return section("map")


## Where the village sits on the map.
static func center() -> Vector2:
	var m := map_cfg()
	return Vector2(float(m.get("width", 1000)) * 0.5, float(m.get("height", 640)) * 0.5)


static func pos_of(place: Dictionary) -> Vector2:
	var p: Array = place.get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


## Days' ride between two points on the map.
static func ride_days(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) / maxf(1.0, float(map_cfg().get("day_ride", 64)))


## "a day's ride", "3 days' ride".
static func days_text(days: int) -> String:
	return "a day's ride" if days == 1 else "%d days' ride" % days


## What a house is known for, in a few words ("known for its knights"), and
## the attribute a fostered child learns there.
static func known_for_text(house: Dictionary) -> String:
	var kinds: Dictionary = section("houses").get("known_for", {})
	return str((kinds.get(str(house.get("known_for", "")), {}) as Dictionary).get("text", "an old house"))


static func known_for_attribute(house: Dictionary) -> String:
	var kinds: Dictionary = section("houses").get("known_for", {})
	return str((kinds.get(str(house.get("known_for", "")), {}) as Dictionary).get("attribute", "combat"))


## Moves a house's regard for yours by `delta` (kept to -100..100). Returns
## the change made.
static func change_regard(state: WorldState, house_id: int, delta: int) -> int:
	var h := state.realm.get_house(house_id) if state.realm else {}
	if h.is_empty():
		return 0
	var before := int(h["standing"])
	h["standing"] = clampi(before + delta, -100, 100)
	return int(h["standing"]) - before


## A camp near their seats is gone: the houses within reach are grateful.
## Returns their titles.
static func camp_cleared(state: WorldState, camp: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if state.realm == null:
		return out
	var r := section("regard")
	for h in state.realm.houses:
		if h.has("pos") and ride_days(pos_of(h), pos_of(camp)) <= float(r.get("camp_reach_days", 3)):
			change_regard(state, int(h["id"]), int(r.get("camp_cleared", 10)))
			out.append(state.realm.house_title(int(h["id"])))
	return out


# --- The days --------------------------------------------------------------------------------

## Once a day (after Military): regard fades a little each season; fostered
## children learn and come home at their age; a ruler who is a fostered
## child comes home to rule. Events: {text, kind, back?}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.realm == null or state.house == null or state.house.ended:
		return events
	var day := state.day()
	var season_start := day % Calendar.days_per_season() == 0
	var r := section("regard")
	if season_start:
		var drift := int(r.get("drift", 2))
		for h in state.realm.houses:
			var s := int(h["standing"])
			h["standing"] = maxi(0, s - drift) if s > 0 else mini(0, s + drift)
	var f := section("fostering")
	for c: CharacterData in state.characters.duplicate():
		var at := c.fostered_at()
		if at < 0:
			continue
		var house := state.realm.get_house(at)
		if season_start and not house.is_empty():
			c.train(known_for_attribute(house), int(f.get("train_per_season", 3)))
			change_regard(state, at, int(r.get("foster_season", 3)))
		if c.age >= int(f.get("return_age", 16)) or state.is_player(c) or house.is_empty():
			events.append(come_back(state, c))
	if not state.realm.trip.is_empty() and (state.player() == null or state.player().away_at != "journey"):
		state.realm.trip = {}  # the one who rode out is gone; whoever rules now is at home
	return events


## A fostered child comes home (grown, or to rule). The news {text, kind, back}.
static func come_back(state: WorldState, c: CharacterData) -> Dictionary:
	var at := c.fostered_at()
	var house := state.realm.get_house(at)
	var attr := known_for_attribute(house) if not house.is_empty() else "combat"
	c.away_at = ""
	c.away_until = -1
	var text := ""
	if house.is_empty():
		text = "%s is home." % c.full_name()
	else:
		change_regard(state, at, int(section("regard").get("foster_return", 8)))
		c.add_history(state.current_year(), state.current_season(), "family", "Came home from fostering at %s" % house["seat"])
		var name := str(GameData.attribute_def(attr).get("name", attr))
		text = "%s is home from %s%s, fostered by %s: %s %d now." % [c.full_name(), house["seat"], " to rule" if state.is_player(c) else "",
			state.realm.house_title(at), name, c.get_current(attr)]
	state.house.log_event(state.day(), text, "family")
	return {"text": text, "kind": "good", "back": [c.id]}


# --- The young of a house ------------------------------------------------------------------------

## Brings a house's young up to date (made on the first visit): a year older
## on each birthday since, grown in their gifts; past their age they marry
## away and a child is born to the house.
static func update_household(state: WorldState, house_id: int) -> Array[CharacterData]:
	var realm := state.realm
	var h := realm.get_house(house_id)
	var conf: Dictionary = section("houses").get("household", {})
	var young: Array = conf.get("young", [2, 4])
	var ages: Array = conf.get("ages", [3, 22])
	var day := state.day()
	if not realm.households.has(house_id):
		var rng := Seeds.rng(state.world_seed, "household_%d" % house_id)
		var list: Array[CharacterData] = []
		for i in rng.randi_range(int(young[0]), int(young[1])):
			list.append(_member(state, h, rng.randi_range(int(ages[0]), int(ages[1]))))
		realm.households[house_id] = list
		realm.household_day[house_id] = day
		return realm.household(house_id)
	var since := int(realm.household_day.get(house_id, day))
	var year := Calendar.days_per_year()
	var kept: Array[CharacterData] = []
	for c in realm.household(house_id):
		var birthdays := floori(float(day - c.birthday) / year) - floori(float(since - c.birthday) / year)
		for i in maxi(0, birthdays):
			c.age += 1
			if c.age == 13 and c.occupation_id == "child":
				c.occupation_id = "noble_scion"
			LifeSystem._grow(c)
		if c.age <= int(conf.get("away_at", 25)):
			kept.append(c)
	var births := Seeds.rng(state.world_seed, "household_%d_%d" % [house_id, day])
	while kept.size() < int(young[0]):
		kept.append(_member(state, h, births.randi_range(0, 2)))
	realm.households[house_id] = kept
	realm.household_day[house_id] = day
	return realm.household(house_id)


static func _member(state: WorldState, house: Dictionary, age: int) -> CharacterData:
	var id := state.realm.next_member_id
	state.realm.next_member_id -= 1
	return CharacterGenerator.house_member(state, house, age, id, "member_%d" % -id)


# --- The journey -------------------------------------------------------------------------------

## Can the heir ride to this seat now? {ok, reason}
static func can_visit(state: WorldState, house_id: int) -> Dictionary:
	var h := state.realm.get_house(house_id) if state.realm else {}
	if h.is_empty() or not h.has("pos"):
		return {"ok": false, "reason": ""}
	return can_travel(state)


## Can the heir leave the village now (a visit, or leading the warband)?
## {ok, reason}
static func can_travel(state: WorldState) -> Dictionary:
	var me := state.player()
	if me == null:
		return {"ok": false, "reason": ""}
	if (state.realm and not state.realm.trip.is_empty()) or me.is_away():
		return {"ok": false, "reason": "You're already away."}
	if me.age < int(section("visits").get("min_age", 14)):
		return {"ok": false, "reason": "You're too young to ride so far (%d)." % int(section("visits").get("min_age", 14))}
	if Military.wounded(state, me):
		return {"ok": false, "reason": "Rest your wounds first."}
	if Military.due(state):
		return {"ok": false, "reason": "A band strikes today: your place is here."}
	return {"ok": true, "reason": ""}


## The heir rides for a seat: the house's days there. {ok, text, days}
static func set_out(state: WorldState, house_id: int) -> Dictionary:
	var can := can_visit(state, house_id)
	if not can["ok"]:
		return {"ok": false, "text": can["reason"], "days": 0}
	var h := state.realm.get_house(house_id)
	var day := state.day()
	var days := int(h["days"])
	var stay := int(section("visits").get("stay_days", 1))
	state.realm.trip = {"kind": "visit", "house": house_id, "depart": day, "arrive": day + days, "back": day + 2 * days + stay,
		"stage": "out", "done": [], "betrothed": []}
	var me := state.player()
	me.away_at = "journey"
	me.away_until = day + 2 * days + stay
	state.house.log_event(day, "You rode for %s, seat of %s." % [h["seat"], state.realm.house_title(house_id)], "family")
	return {"ok": true, "text": "You ride for %s, %s." % [h["seat"], days_text(days)], "days": days}


## You come to the seat: the house welcomes you (regard for the visit) and
## you meet its young. The welcome.
static func arrive(state: WorldState) -> String:
	var trip := state.realm.trip
	var house_id := int(trip["house"])
	var h := state.realm.get_house(house_id)
	trip["stage"] = "there"
	h["visited"] = state.day()
	change_regard(state, house_id, int(section("regard").get("visit", 5)))
	for c in update_household(state, house_id):
		c.player_opinion = clampf(float(h["standing"]) * 0.5, -100.0, 100.0)
	return "%s welcomes you to %s. House %s is %s, and %s toward yours." % [h["head"], h["seat"], h["name"], known_for_text(h),
		MatchSystem.standing_word(int(h["standing"]))]


## The house you're visiting (while at the seat), else {}.
static func at_seat(state: WorldState) -> Dictionary:
	var trip := state.realm.trip if state.realm else {}
	if trip.is_empty() or str(trip.get("stage", "")) != "there":
		return {}
	return state.realm.get_house(int(trip["house"]))


static func did(state: WorldState, deed: String) -> bool:
	return (state.realm.trip.get("done", []) as Array).has(deed)


static func _done(state: WorldState, deed: String) -> void:
	(state.realm.trip["done"] as Array).append(deed)


## Gifts for the house. {ok, text}
static func give_gift(state: WorldState, gold: int) -> Dictionary:
	var h := at_seat(state)
	if h.is_empty() or did(state, "gift"):
		return {"ok": false, "text": "You've given your gifts."}
	if state.house.gold < gold:
		return {"ok": false, "text": "You haven't %d gold to give." % gold}
	var r := section("regard")
	state.house.gold -= gold
	var delta := change_regard(state, int(h["id"]), mini(int(r.get("gift_max", 18)), roundi(gold * float(r.get("gift_per_gold", 0.12)))))
	_done(state, "gift")
	return {"ok": true, "text": "You give %s gifts worth %d gold. They hold your house a little dearer (+%d)." % [h["head"], gold, delta]}


## A talk with the lord or lady: your Politics carries it, or you misspeak.
## {ok, text, delta}
static func speak(state: WorldState) -> Dictionary:
	var h := at_seat(state)
	if h.is_empty() or did(state, "talk"):
		return {"ok": false, "text": "You've had your talk.", "delta": 0}
	var r := section("regard")
	var politics := state.player().get_current("politics")
	var rng := Seeds.rng(state.world_seed, "speak_%d_%d" % [int(h["id"]), state.day()])
	var gaffe := clampf(float(r.get("gaffe_base", 0.3)) + politics * float(r.get("gaffe_per_politics", -0.004)), 0.05, 0.6)
	var delta := 0
	var text := ""
	var who := str(h["head"])
	if rng.randf() < gaffe:
		delta = change_regard(state, int(h["id"]), int(r.get("gaffe", -4)))
		text = "You speak with %s, and say the wrong thing about their neighbours. A cool silence (%d)." % [who, delta]
	else:
		delta = change_regard(state, int(h["id"]), int(r.get("talk_base", 3)) + roundi(politics * float(r.get("talk_per_politics", 0.1))))
		text = "You speak long with %s of the roads, the harvest and the bands in the woods. They like what they hear (+%d)." % [who, delta]
	_done(state, "talk")
	return {"ok": true, "text": text, "delta": delta}


## Looks at one of the house's young with the Eye.
static func look(state: WorldState, member_id: int) -> CharacterData:
	var c := state.realm.get_member(member_id)
	if c:
		c.appraised = true
		c.met = true
	return c


## Yours who may be matched at a seat: you if unmarried, and your unmarried
## kin of an age.
static func hand_partners(state: WorldState) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	var ages := MatchSystem.section("ages")
	for c in state.characters:
		if not (state.is_player(c) or CourtSystem.is_kin(state, c)) or c.is_visitor() or c.fostered_at() >= 0:
			continue
		if c.age < int(ages.get("min", 16)) or c.age > int(ages.get("max", 50)) or LifeSystem.spouse_of(state, c) != null:
			continue
		if _betrothed_to(state, c.id) >= 0:
			continue
		out.append(c)
	return out


static func _betrothed_to(state: WorldState, character_id: int) -> int:
	for b: Dictionary in state.realm.trip.get("betrothed", []):
		if int(b["to"]) == character_id:
			return int(b["member"])
	return -1


## Asks the house for `member_id`'s hand for `partner_id` (once a visit).
## {ok, accept, text, reasons}
static func ask_hand(state: WorldState, member_id: int, partner_id: int) -> Dictionary:
	var h := at_seat(state)
	var member := state.realm.get_member(member_id)
	var partner := state.get_character(partner_id)
	if h.is_empty() or member == null or partner == null:
		return {"ok": false, "accept": false, "text": "", "reasons": []}
	if did(state, "hand"):
		return {"ok": false, "accept": false, "text": "You've asked once this visit; ask again another time.", "reasons": []}
	var k := section("hands")
	if int(h["standing"]) < int(k.get("min_regard", 10)):
		return {"ok": false, "accept": false, "text": "%s doesn't think well enough of your house to give you a son or daughter (they're %s toward yours)." % [h["head"], MatchSystem.standing_word(int(h["standing"]))], "reasons": []}
	var can := MatchSystem.can_wed(state, partner, member)
	if not can["ok"]:
		return {"ok": false, "accept": false, "text": str(can["reason"]), "reasons": []}
	_done(state, "hand")
	var r := MatchSystem.consider(state, member, partner)
	var wish := float(k.get("wish_base", 0.2)) + int(h["standing"]) * float(k.get("wish_per_regard", 0.006)) + state.house.renown * float(k.get("wish_per_renown", 0.003))
	var reasons: Array = (r["reasons"] as Array).duplicate()
	reasons.append({"text": "Their house wants the match." if wish >= 0.3 else "Their house is willing.", "good": true, "weight": wish})
	reasons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
	var accept := float(r["score"]) + wish >= float(MatchSystem.section("consent").get("threshold", 0.5))
	var whom := "you" if state.is_player(partner) else partner.full_name()
	var text := ""
	if accept:
		(state.realm.trip["betrothed"] as Array).append({"member": member.id, "to": partner.id})
		text = "%s will marry %s. %s comes home with you; the wedding is when you're back." % [member.full_name(), whom, "She" if member.gender == "female" else "He"]
	else:
		text = "%s won't have %s. %s" % [member.first_name, whom, MatchSystem._answer(state, "no")]
	return {"ok": true, "accept": accept, "text": text, "reasons": reasons}


## Your kin children who might be fostered: of an age, at home.
static func foster_candidates(state: WorldState) -> Array[CharacterData]:
	var f := section("fostering")
	var out: Array[CharacterData] = []
	for c in state.characters:
		if state.is_player(c) or not CourtSystem.is_kin(state, c) or c.is_away():
			continue
		if c.age >= int(f.get("min_age", 7)) and c.age <= int(f.get("max_age", 13)):
			out.append(c)
	return out


## Leaves a kin child at the seat to be fostered until they're grown (one a
## visit). {ok, text, away}
static func foster(state: WorldState, child_id: int) -> Dictionary:
	var h := at_seat(state)
	var c := state.get_character(child_id)
	var f := section("fostering")
	if h.is_empty() or c == null:
		return {"ok": false, "text": "", "away": -1}
	if did(state, "foster"):
		return {"ok": false, "text": "They'll foster one of yours at a time.", "away": -1}
	if not foster_candidates(state).has(c):
		return {"ok": false, "text": "%s can't be fostered (%d to %d years, kin, at home)." % [c.first_name, int(f.get("min_age", 7)), int(f.get("max_age", 13))], "away": -1}
	if int(h["standing"]) < int(f.get("min_regard", 10)):
		return {"ok": false, "text": "%s won't take a child of a house they think so little of." % h["head"], "away": -1}
	c.away_at = "foster:%d" % int(h["id"])
	c.away_until = -1
	change_regard(state, int(h["id"]), int(section("regard").get("foster_start", 10)))
	_done(state, "foster")
	c.add_history(state.current_year(), state.current_season(), "family", "Sent to be fostered at %s, by %s" % [h["seat"], state.realm.house_title(int(h["id"]))])
	var attr := str(GameData.attribute_def(known_for_attribute(h)).get("name", ""))
	var text := "%s will be fostered at %s until %d. House %s is %s: %s will learn %s there. They send for %s." % [c.full_name(), h["seat"],
		int(f.get("return_age", 16)), h["name"], known_for_text(h), "she" if c.gender == "female" else "he", attr, "her" if c.gender == "female" else "him"]
	state.house.log_event(state.day(), "%s was sent to be fostered at %s." % [c.full_name(), h["seat"]], "family")
	return {"ok": true, "text": text, "away": c.id}


## You take your leave: the days home. Returns them.
static func take_leave(state: WorldState) -> int:
	var trip := state.realm.trip
	var h := state.realm.get_house(int(trip["house"]))
	trip["stage"] = "back"
	trip["back"] = state.day() + int(section("visits").get("stay_days", 1)) + int(h.get("days", 2))
	if state.player():
		state.player().away_until = int(trip["back"])
	return int(trip["back"]) - state.day()


## Home again: whoever you betrothed at the seat comes with you and the
## wedding is held (with their house's dowry). Events: weddings and {back}.
static func come_home(state: WorldState, events: Array[Dictionary]) -> void:
	var trip := state.realm.trip
	if trip.is_empty():
		return
	var house_id := int(trip["house"])
	var h := state.realm.get_house(house_id)
	var me := state.player()
	if me and me.away_at == "journey":
		me.away_at = ""
		me.away_until = -1
	events.append({"text": "You're home from %s." % h.get("seat", "your journey"), "kind": "info", "back": [me.id] if me else []})
	for b: Dictionary in trip.get("betrothed", []):
		var member := state.realm.get_member(int(b["member"]))
		var partner := state.get_character(int(b["to"]))
		if member == null or partner == null or not MatchSystem.can_wed(state, partner, member)["ok"]:
			continue
		var list: Array = state.realm.households.get(house_id, [])
		list.erase(member)
		var c := CharacterGenerator.bring_member(state, h, member)
		var born := c.full_name()
		c.visiting_until = state.day() + 1
		c.suitor_for = partner.id
		c.position = me.position if me else state.layout.square_center
		events.append({"text": "", "visitor": c.id})
		var gold := MatchSystem.dowry(state, house_id)
		state.house.gold += gold
		change_regard(state, house_id, int(section("regard").get("hand_given", 15)))
		MatchSystem.wed(state, partner, c, events)
		events[-1]["text"] = "%s weds %s. %s sends a dowry of %d gold." % [born, "you" if state.is_player(partner) else partner.full_name(), state.realm.house_title(house_id), gold]
	state.realm.trip = {}
