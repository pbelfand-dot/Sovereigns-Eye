class_name Recruitment
extends RefCounted
## Motive-based recruitment: why someone would (or wouldn't) join your house.
##
## Everyone weighs their own motives (data/recruitment.json), from who they
## are: fondness for you, money and security, a home for their family,
## advancement, respect and duty, set against the ties and caution that keep
## them where they are, all coloured by your house's standing with common
## folk. In conversation the heir learns these motives and makes a concrete
## offer:
##   {wage: gold a day, home: building id | MANOR_ROOMS | PROMISE_HOME | -1,
##    position: "household" | "training" | "office" | "workplace" | "squire",
##    focus: attribute (training), office: id, workplace: building id,
##    appeal: true to appeal to their duty and honour}
## They accept, make a counteroffer, or refuse, and say why in plain words.
## Accepted terms are enforced: the wage is paid from the treasury every
## day, the family moves into the home, the job needs a real workplace, and
## promises are checked daily; a broken promise costs trust and standing
## and can make them leave.
##
## Static and deterministic: no dice. The same offer to the same person in
## the same situation always gets the same answer.

const MANOR_ROOMS := -2
const PROMISE_HOME := -3
const SPEAKING_MOTIVES := ["bond", "money", "home", "career", "standing", "ties", "risk"]
const GAINS := ["bond", "money", "home", "career", "standing"]


static func cfg() -> Dictionary:
	return GameData.load_file("recruitment")


static func motive_name(id: String) -> String:
	return str(cfg().get("motives", {}).get(id, {}).get("name", id.capitalize()))


static func _fill(text: String, state: WorldState, vars: Dictionary = {}) -> String:
	var p := state.player()
	text = text.replace("{lord}", "my lady" if p and p.gender == "female" else "my lord")
	for k: String in vars:
		text = text.replace("{%s}" % k, str(vars[k]))
	return text


# --- Who decides, and can they be asked ----------------------------------------------------

## Children (10-15) join as pages: a parent decides for them.
static func decider(state: WorldState, c: CharacterData) -> CharacterData:
	if c.age <= int(CourtSystem.section("recruit").get("ward_max_age", 15)):
		var best: CharacterData = null
		for r in c.relationships_of_type(["parent"]):
			var p := state.get_character(int(r["target"]))
			if p and (best == null or p.player_opinion > best.player_opinion):
				best = p
		if best:
			return best
	return c


## Can you make them an offer at all? Almost always: a refusal never closes
## the door (improve the offer and ask again), a full household only costs
## upkeep, and your own retainers hear new terms. Only you, your own family
## (they already serve the house) and young children can't be asked.
static func can_offer(state: WorldState, c: CharacterData) -> Dictionary:
	if state.is_player(c):
		return {"ok": false, "reason": "That's you."}
	if CourtSystem.is_kin(state, c):
		return {"ok": false, "reason": "%s is family: they already serve your house." % c.first_name}
	if c.age < int(CourtSystem.section("recruit").get("min_age", 10)):
		return {"ok": false, "reason": "%s is too young to serve (10+)." % c.first_name}
	return {"ok": true, "reason": ""}


## Can they be recruited (an offer they haven't sworn to yet)?
static func eligible(state: WorldState, c: CharacterData) -> Dictionary:
	var can := can_offer(state, c)
	if can["ok"] and c.retainer:
		return {"ok": false, "reason": "Already sworn to your house."}
	return can


# --- Motives ---------------------------------------------------------------------------------

static func _trait_sum(c: CharacterData, table: Dictionary) -> float:
	var v := 0.0
	for t in c.traits:
		v += float(table.get(t, 0.0))
	return v


static func _children(state: WorldState, c: CharacterData) -> int:
	var n := 0
	for r in c.relationships_of_type(["child"]):
		var k := state.get_character(int(r["target"]))
		if k and k.age < 16 and k.home_building_id == c.home_building_id:
			n += 1
	return n


static func _household_head(state: WorldState, c: CharacterData) -> bool:
	var fam := state.get_family(c.family_id)
	if fam == null:
		return true
	if fam.head_id == c.id:
		return true
	for r in c.relationships_of_type(["spouse"]):
		if int(r["target"]) == fam.head_id:
			return true
	return false


## How much each motive matters to them (0..1). "ties" and "risk" are what
## holds them back.
static func motives(state: WorldState, c: CharacterData) -> Dictionary:
	var w: Dictionary = cfg().get("weights", {})
	var out := {}
	var b: Dictionary = w.get("bond", {})
	out["bond"] = float(b.get("base", 0.55)) + _trait_sum(c, b.get("traits", {}))
	var m: Dictionary = w.get("money", {})
	var dependents := _children(state, c)
	out["money"] = float(m.get("base", 0.25)) + float(m.get("status", {}).get(c.social_status, 0.2)) \
		+ dependents * float(m.get("per_dependent", 0.05)) + _trait_sum(c, m.get("traits", {})) \
		+ (float(m.get("hungry", 0.2)) if TerritorySystem.is_hungry(state) else 0.0)
	var h: Dictionary = w.get("home", {})
	var kids := _children(state, c)
	var home_w := float(h.get("base", 0.0)) + kids * float(h.get("per_child", 0.18)) + (float(h.get("parent", 0.15)) if kids > 0 else 0.0)
	var home := state.get_building(c.home_building_id)
	if home == null:
		home_w += float(h.get("homeless", 0.6))
	else:
		if state.residents_of(home.id).size() >= int(h.get("crowded_from", 5)):
			home_w += float(h.get("crowded", 0.25))
		if not _household_head(state, c) and c.is_adult():
			home_w += float(h.get("not_household_head", 0.2))
	if _household_head(state, c):
		home_w += float(h.get("owner_status", {}).get(c.social_status, 0.0))
	out["home"] = home_w
	var k: Dictionary = w.get("career", {})
	var career := float(k.get("base", 0.15)) + c.get_current("ambition") / float(k.get("ambition_divisor", 140.0)) + _trait_sum(c, k.get("traits", {}))
	if MoodSystem.wasted_talent_penalty(c) < 0.0:
		career += float(k.get("wasted_talent", 0.3))
	if c.age >= 14 and c.age <= 30:
		career += float(k.get("young", 0.1))
	if c.age >= 60:
		career += float(k.get("elder", -0.3))
	out["career"] = career
	var s: Dictionary = w.get("standing", {})
	out["standing"] = float(s.get("base", 0.05)) + float(s.get("status", {}).get(c.social_status, 0.0)) + _trait_sum(c, s.get("traits", {}))
	var t: Dictionary = w.get("ties", {})
	var ties := 0.0
	if (cfg().get("business_heads", []) as Array).has(c.occupation_id) and _household_head(state, c):
		ties += float(t.get("business_head", 0.45))
	ties += mini(c.relationships_of_type(["friend"]).size(), int(t.get("max_friends", 3))) * float(t.get("per_friend", 0.08))
	for r in c.relationships_of_type(["spouse"]):
		var sp := state.get_character(int(r["target"]))
		if sp and sp.work_building_id >= 0:
			ties += float(t.get("spouse_works_here", 0.1))
	out["ties"] = ties
	var r_cfg: Dictionary = w.get("risk", {})
	out["risk"] = _trait_sum(c, r_cfg.get("traits", {})) + (float(r_cfg.get("elder", 0.25)) if c.age >= 60 else 0.0)
	for key: String in out:
		out[key] = clampf(float(out[key]), 0.0, 1.0)
	return out


## Motives strongest first (what they'd tell you about, in order).
static func ranked_motives(state: WorldState, c: CharacterData) -> Array[String]:
	var m := motives(state, c)
	var ids: Array[String] = []
	for id: String in SPEAKING_MOTIVES:
		if float(m[id]) >= 0.12:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return float(m[a]) > float(m[b]) if m[a] != m[b] else a < b)
	return ids


## A word for how much a motive matters (never a number).
static func strength_word(weight: float) -> String:
	if weight >= 0.65:
		return "above all"
	if weight >= 0.4:
		return "a great deal"
	if weight >= 0.2:
		return "somewhat"
	return "a little"


## "Tell me about your life": they reveal the next motive they haven't told
## you about yet. Returns {line, motive ("" when there's nothing more)}.
static func ask(state: WorldState, c: CharacterData) -> Dictionary:
	var who := decider(state, c)
	var lines: Dictionary = cfg().get("ask_lines", {})
	for id in ranked_motives(state, who):
		if c.known_motives.has(id):
			continue
		c.known_motives.append(id)
		# Fondness matters to them, but they may not be fond of you (yet).
		var key := id
		if id == "bond" and who.player_opinion < float(cfg().get("bond_fond_at", 15.0)) and lines.has("bond_wary"):
			key = "bond_wary"
		var options: Array = lines.get(key, ["\"...\""])
		var line := str(options[(c.id + c.known_motives.size()) % options.size()])
		return {"line": _fill(line, state), "motive": id}
	return {"line": _fill(str(cfg().get("nothing_more", "\"That's all.\"")), state), "motive": ""}


# --- Offers --------------------------------------------------------------------------------

## Homes free to offer: empty ones.
static func available_homes(state: WorldState) -> Array[BuildingData]:
	return GrowthSystem.empty_homes(state)


static func manor_rooms_free(state: WorldState) -> bool:
	var manors := state.layout.buildings_of_type("manor")
	if manors.is_empty():
		return false
	var cap := int(cfg().get("home_offer", {}).get("manor_capacity", 10))
	return state.residents_of(manors[0].id).size() < cap


const WORKPLACE_TYPES := ["workshop", "smithy", "quarry", "bakery", "mill"]


## Workplaces with room for one more craftsperson of the house (two each).
static func open_workplaces(state: WorldState) -> Array[BuildingData]:
	var out: Array[BuildingData] = []
	for b in state.layout.buildings:
		if not WORKPLACE_TYPES.has(b.type):
			continue
		var taken := 0
		for r in state.retainers():
			if int(r.terms.get("workplace", -1)) == b.id:
				taken += 1
		if taken < 2:
			out.append(b)
	return out


## A vacant office, the one suiting their greatest gift if it's free.
static func vacant_office_for(state: WorldState, c: CharacterData) -> String:
	var fallback := ""
	for o: Dictionary in CourtSystem.offices():
		var id := str(o["id"])
		if state.house.holder_of(id) >= 0:
			continue
		if str(o.get("primary", "")) == c.best_attribute():
			return id
		if fallback.is_empty():
			fallback = id
	return fallback


static func is_fighter(c: CharacterData) -> bool:
	return (cfg().get("fighter_attrs", []) as Array).has(c.best_attribute())


## A skilled trade they'd give up to join (unless offered a workplace).
static func is_craftsperson(c: CharacterData) -> bool:
	return (cfg().get("trade_jobs", []) as Array).has(c.occupation_id)


## Gold a day they need: by station, more for a gifted hand.
static func wage_need(c: CharacterData) -> int:
	var need := int(cfg().get("wage_need", {}).get(c.social_status, 2))
	var best := 0
	for attr_id: String in GameData.attribute_ids():
		if attr_id != "ambition":
			best = maxi(best, c.get_current(attr_id))
	for step: Variant in cfg().get("skill_wage", []):
		if best >= int(step):
			need += 1
	return need


## They live by their work, so giving it up for no wage is a loss.
static func lives_by_work(c: CharacterData) -> bool:
	return c.is_adult() and (cfg().get("livelihood_statuses", []) as Array).has(c.social_status) \
		and not c.occupation_id in ["child", "elder"]


## How they feel about the heir as a person: opinion plus friendship or rivalry.
static func _bond_satisfaction(state: WorldState, who: CharacterData) -> float:
	var sat := who.player_opinion / 60.0
	var ties: Dictionary = cfg().get("heir_ties", {})
	var r := who.get_relationship(state.player_id)
	if not r.is_empty():
		sat += float(ties.get(str(r["type"]), 0.0))
	return clampf(sat, -0.6, 1.5)


## What's wrong with an offer before it's even made ("" if it can be made).
static func offer_problem(state: WorldState, c: CharacterData, offer: Dictionary) -> String:
	var wage := int(offer.get("wage", 0))
	if wage < 0 or wage > int(cfg().get("max_wage", 8)):
		return "Wages run from 0 to %d gold a day." % int(cfg().get("max_wage", 8))
	var home := int(offer.get("home", -1))
	if home >= 0:
		var b := state.get_building(home)
		if b == null or not available_homes(state).has(b):
			return "That home isn't free."
	elif home == MANOR_ROOMS and not manor_rooms_free(state):
		return "There's no room left at the manor."
	match str(offer.get("position", "household")):
		"office":
			var office := str(offer.get("office", ""))
			if CourtSystem.office_def(office).is_empty():
				return "Choose an office."
			var holder := state.house.holder_of(office)
			if holder >= 0 and holder != c.id:
				return "That office is already held."
			if c.age < 16:
				return "Too young to hold an office (16+)."
		"workplace":
			var wb := state.get_building(int(offer.get("workplace", -1)))
			var theirs := wb != null and int(c.terms.get("workplace", -1)) == wb.id
			if wb == null or not (theirs or open_workplaces(state).has(wb)):
				return "A job needs a workplace with room: build or choose a workshop, smithy, yard, bakery or mill."
		"squire":
			if c.age < 14 or c.age > 30:
				return "Squires are 14 to 30 years old."
			if c.is_knight():
				return "They're already a knight."
		"training":
			if not CourtSystem.TRAINABLE.has(str(offer.get("focus", ""))):
				return "Choose a skill to train."
	return ""


## Weighs an offer. Returns {total, accept, parts: {motive: contribution},
## reasons: [{text, good}], insulted}.
static func evaluate(state: WorldState, c: CharacterData, offer: Dictionary) -> Dictionary:
	var rc := cfg()
	var who := decider(state, c)
	var w := motives(state, who)
	var sat := {}
	# Fondness: their opinion of you.
	sat["bond"] = _bond_satisfaction(state, who)
	# Money against what they need; working people won't give up their
	# living for nothing.
	var need := float(wage_need(who))
	var wage := float(offer.get("wage", 0))
	sat["money"] = clampf(wage / maxf(need, 1.0), 0.0, 1.0)
	if lives_by_work(who):
		sat["money"] = lerpf(float(rc.get("no_wage", -0.5)), 1.0, sat["money"])
	# A home.
	var ho: Dictionary = rc.get("home_offer", {})
	var home := int(offer.get("home", -1))
	sat["home"] = 0.0
	if home >= 0:
		sat["home"] = float(ho.get("value", 1.0))
		var cur := state.get_building(who.home_building_id)
		var b := state.get_building(home)
		if cur == null or (b and b.tier > cur.tier) or state.residents_of(who.home_building_id).size() >= 5:
			sat["home"] += float(ho.get("better_tier", 0.25))
	elif home == MANOR_ROOMS:
		sat["home"] = float(ho.get("manor_rooms", 0.55))
	elif home == PROMISE_HOME:
		sat["home"] = float(ho.get("promise", 0.6)) * clampf((state.house.standing if state.house else 50.0) / 50.0, 0.3, 1.2)
	# Advancement.
	var co: Dictionary = rc.get("career_offers", {})
	var pos := str(offer.get("position", "household"))
	var career := float(co.get(pos, {}).get("value", 0.25))
	match pos:
		"training":
			if str(offer.get("focus", "")) == c.best_attribute():
				career += float(co["training"].get("best_match", 0.25))
		"office":
			if str(CourtSystem.office_def(str(offer.get("office", ""))).get("primary", "")) == c.best_attribute():
				career += float(co["office"].get("best_match", 0.2))
		"workplace":
			if is_craftsperson(c):
				career += float(co["workplace"].get("craft_match", 0.25))
		"squire":
			career += float(co["squire"].get("fighter_match", 0.25)) if is_fighter(c) else float(co["squire"].get("non_fighter", -0.4))
	sat["career"] = maxf(career, 0.0)
	# Respect, duty, prestige.
	var ap: Dictionary = rc.get("appeal", {})
	var standing := 0.0
	if bool(offer.get("appeal", false)):
		var dutiful := false
		for t in who.traits:
			dutiful = dutiful or (ap.get("duty_traits", []) as Array).has(t)
		dutiful = dutiful or who.social_status in ["burgher", "clergy", "knight", "retainer"]
		standing += float(ap.get("value", 0.8)) if dutiful else float(ap.get("other", 0.2))
	if pos == "office" or pos == "squire":
		standing += 0.5
	sat["standing"] = standing
	# Weigh it all.
	var strong: Dictionary = rc.get("strong_motive", {})
	var parts := {}
	var total := 0.0
	for id: String in GAINS:
		# A motive met strongly carries extra weight: one can be enough.
		var v := float(w[id]) * float(sat[id])
		if v >= float(strong.get("weight", 0.65)):
			v *= float(strong.get("bonus", 1.35))
		parts[id] = v
		total += v
	parts["ties"] = -float(w["ties"])
	parts["risk"] = -float(w["risk"])
	parts["trade"] = -trade_cost() if is_craftsperson(c) and pos != "workplace" else 0.0
	total += parts["ties"] + parts["risk"] + parts["trade"]
	var rep := ((state.house.standing if state.house else 50.0) - 50.0) / 50.0 * float(rc.get("reputation", {}).get("weight", 0.5))
	parts["reputation"] = rep
	total += rep
	var accept := total >= float(rc.get("threshold", 1.0))
	return {"total": total, "accept": accept, "parts": parts, "weights": w, "satisfaction": sat,
		"reasons": _reasons(state, c, offer, w, sat, parts, accept), "insulted": total < float(rc.get("insult_below", 0.25))}


static func trade_cost() -> float:
	return float(cfg().get("trade_cost", 0.45))


static func _career_name(offer: Dictionary) -> String:
	var pos := str(offer.get("position", "household"))
	match pos:
		"training":
			return "Training in %s" % CourtSystem.attr_name(str(offer.get("focus", "")))
		"office":
			return "The office of %s" % CourtSystem.office_name(str(offer.get("office", "")))
		"workplace":
			return "A workplace of their own"
		"squire":
			return "A squire's place"
	return "A place in your household"


## Plain-language reasons, most important first.
static func _reasons(state: WorldState, c: CharacterData, offer: Dictionary, w: Dictionary, sat: Dictionary, parts: Dictionary, accept: bool) -> Array[Dictionary]:
	var lines: Dictionary = cfg().get("reason_lines", {})
	var out: Array[Dictionary] = []
	var vars := {"wage": int(offer.get("wage", 0)), "need": wage_need(decider(state, c)),
		"days": int(cfg().get("promises", {}).get("home_days", 6)), "career": _career_name(offer)}
	var add := func(key: String, good: bool, weight: float) -> void:
		out.append({"text": _fill(str(lines.get(key, key)), state, vars), "good": good, "weight": weight})
	if float(w["bond"]) >= 0.2:
		if float(sat["bond"]) >= 0.8:
			add.call("bond_pos", true, float(parts["bond"]))
		elif float(sat["bond"]) < 0.25:
			add.call("bond_neg", false, float(w["bond"]) * 0.6)
	if float(w["money"]) >= 0.2:
		if float(sat["money"]) >= 1.0:
			add.call("money_pos", true, float(parts["money"]))
		elif int(offer.get("wage", 0)) <= 0:
			add.call("money_none", false, float(w["money"]))
		else:
			add.call("money_low", false, float(w["money"]) * (1.0 - float(sat["money"])))
	if float(w["home"]) >= 0.2:
		if int(offer.get("home", -1)) == PROMISE_HOME and float(sat["home"]) > 0.0:
			add.call("home_promise", true, float(parts["home"]))
		elif float(sat["home"]) >= 1.0:
			add.call("home_pos", true, float(parts["home"]))
		elif float(sat["home"]) < 0.5:
			add.call("home_none", false, float(w["home"]))
	if float(w["career"]) >= 0.2:
		var pos := str(offer.get("position", "household"))
		if float(sat["career"]) >= 0.8:
			add.call("career_pos", true, float(parts["career"]))
		elif pos == "household":
			add.call("career_none", false, float(w["career"]))
		else:
			add.call("career_mismatch", false, float(w["career"]) * (1.0 - float(sat["career"])))
	if float(w["standing"]) >= 0.3:
		if float(sat["standing"]) >= 0.8:
			add.call("standing_pos", true, float(parts["standing"]))
		else:
			add.call("standing_none", false, float(w["standing"]))
	if float(parts["trade"]) < 0.0:
		add.call("trade_neg", false, -float(parts["trade"]))
	elif is_craftsperson(c):
		add.call("trade_pos", true, trade_cost())
	if float(w["ties"]) >= 0.25:
		add.call("ties_neg", false, float(w["ties"]))
	if float(w["risk"]) >= 0.2:
		add.call("risk_neg", false, float(w["risk"]))
	if float(parts["reputation"]) >= 0.1:
		add.call("rep_pos", true, float(parts["reputation"]))
	elif float(parts["reputation"]) <= -0.1:
		add.call("rep_neg", false, -float(parts["reputation"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["good"]) != bool(b["good"]):
			return bool(a["good"]) == accept
		return float(a["weight"]) > float(b["weight"]))
	return out


## Their counteroffer: the offer changed to meet the motive that's missing
## most. {} when no reasonable change would win them over.
static func counteroffer(state: WorldState, c: CharacterData, offer: Dictionary) -> Dictionary:
	var who := decider(state, c)
	var w := motives(state, who)
	var tries: Array[Dictionary] = []
	var need := wage_need(who)
	if int(offer.get("wage", 0)) < need and float(w["money"]) >= 0.2:
		var o := offer.duplicate()
		o["wage"] = need
		tries.append(o)
	if int(offer.get("home", -1)) < 0 and float(w["home"]) >= 0.2:
		var homes := available_homes(state)
		var o := offer.duplicate()
		o["home"] = homes[0].id if not homes.is_empty() else PROMISE_HOME
		tries.append(o)
	if float(w["career"]) >= 0.2:
		var o := offer.duplicate()
		if is_fighter(c) and c.age >= 14 and c.age <= 30:
			o["position"] = "squire"
		elif is_craftsperson(c) and not open_workplaces(state).is_empty():
			o["position"] = "workplace"
			o["workplace"] = open_workplaces(state)[0].id
		else:
			o["position"] = "training"
			o["focus"] = c.best_attribute() if CourtSystem.TRAINABLE.has(c.best_attribute()) else "intelligence"
		if o != offer:
			tries.append(o)
	if float(w["standing"]) >= 0.3 and not bool(offer.get("appeal", false)):
		var o := offer.duplicate()
		o["appeal"] = true
		tries.append(o)
	if float(w["standing"]) >= 0.3 and c.age >= 16 and not str(offer.get("position", "")) in ["office", "squire"]:
		var office := vacant_office_for(state, c)
		if not office.is_empty():
			var o := offer.duplicate()
			o["position"] = "office"
			o["office"] = office
			tries.append(o)
	# The smallest single change that wins them; else two changes together.
	for o in tries:
		if offer_problem(state, c, o).is_empty() and evaluate(state, c, o)["accept"]:
			return o
	for i in tries.size():
		for j in range(i + 1, tries.size()):
			var o := tries[i].duplicate()
			for k: String in tries[j]:
				if tries[j][k] != offer.get(k, null):
					o[k] = tries[j][k]
			if offer_problem(state, c, o).is_empty() and evaluate(state, c, o)["accept"]:
				return o
	return {}


## Plain words for an offer: "3 gold a day, Kemp Cottage, training in Combat".
static func describe(state: WorldState, offer: Dictionary) -> String:
	var parts: Array[String] = []
	var wage := int(offer.get("wage", 0))
	parts.append("%d gold a day" % wage if wage > 0 else "no wage")
	var home := int(offer.get("home", -1))
	if home >= 0:
		var b := state.get_building(home)
		parts.append(b.name if b else "a home")
	elif home == MANOR_ROOMS:
		parts.append("rooms at the manor")
	elif home == PROMISE_HOME:
		parts.append("a home within %d days (a promise)" % int(cfg().get("promises", {}).get("home_days", 6)))
	parts.append(_career_name(offer).to_lower())
	if bool(offer.get("appeal", false)):
		parts.append("an appeal to their duty")
	return ", ".join(parts)


## Makes the offer. Returns {result: "accept" | "counter" | "refuse" | "invalid",
## text, reasons, counter}. Accepting applies the terms at once.
static func propose(state: WorldState, c: CharacterData, offer: Dictionary) -> Dictionary:
	var can := can_offer(state, c)
	if not can["ok"]:
		return {"result": "invalid", "text": can["reason"], "reasons": [], "counter": {}}
	var problem := offer_problem(state, c, offer)
	if not problem.is_empty():
		return {"result": "invalid", "text": problem, "reasons": [], "counter": {}}
	if c.retainer:
		return _propose_new_terms(state, c, offer)
	var ev := evaluate(state, c, offer)
	var who := decider(state, c)
	var name := who.first_name if who == c else "%s's %s" % [c.first_name, "father" if who.gender == "male" else "mother"]
	if ev["accept"]:
		accept(state, c, offer)
		return {"result": "accept", "text": "%s accepts: %s." % [name, describe(state, offer)], "reasons": ev["reasons"], "counter": {}}
	var counter := {}
	if float(ev["total"]) >= float(cfg().get("counter_from", 0.7)) or not ev["insulted"]:
		counter = counteroffer(state, c, offer)
	if not counter.is_empty():
		return {"result": "counter", "text": "%s would come for %s." % [name, describe(state, counter)], "reasons": ev["reasons"], "counter": counter}
	# No door closes: improve the offer and ask again. A lowball still stings.
	if ev["insulted"]:
		who.player_opinion = clampf(who.player_opinion - 3.0, -100.0, 100.0)
	return {"result": "refuse", "text": "%s refuses." % name, "reasons": ev["reasons"], "counter": {}}


# --- Keeping the terms -----------------------------------------------------------------------

## They join on these terms: wage, home, position. Everything is real.
static func accept(state: WorldState, c: CharacterData, offer: Dictionary) -> void:
	CourtSystem.join(state, c)
	_apply_terms(state, c, offer)
	state.house.log_event(state.day(), "%s joined the household for %s." % [c.full_name(), describe(state, offer)], "join")


## The terms a retainer serves on now, as an offer (to start new terms from).
static func current_terms(state: WorldState, c: CharacterData) -> Dictionary:
	var t := {"wage": CourtSystem.wage(c), "home": -1, "position": "household", "appeal": false}
	if not c.office.is_empty():
		t["position"] = "office"
		t["office"] = c.office
	elif int(c.terms.get("workplace", -1)) >= 0 and state.get_building(int(c.terms["workplace"])):
		t["position"] = "workplace"
		t["workplace"] = int(c.terms["workplace"])
	elif c.title == "squire":
		t["position"] = "squire"
	elif not c.focus.is_empty():
		t["position"] = "training"
		t["focus"] = c.focus
	return t


## New terms for one of your retainers. Terms they like better (by their
## own motives) are taken gladly and raise their loyalty; worse ones they
## turn down, a little hurt. Returns the same shape as propose().
static func _propose_new_terms(state: WorldState, c: CharacterData, offer: Dictionary) -> Dictionary:
	var rn: Dictionary = cfg().get("renegotiate", {})
	var old := current_terms(state, c)
	var ev := evaluate(state, c, offer)
	var gain := float(ev["total"]) - float(evaluate(state, c, old)["total"])
	if gain >= -float(rn.get("tolerance", 0.05)):
		_apply_terms(state, c, offer)
		var up := clampf(gain * float(rn.get("loyalty_per_gain", 25.0)), 0.0, float(rn.get("max_loyalty", 20.0)))
		c.loyalty = clampf(c.loyalty + up, 0.0, 100.0)
		state.house.log_event(state.day(), "%s now serves for %s." % [c.full_name(), describe(state, offer)], "court")
		var how := "gladly" if up >= 3.0 else "readily"
		return {"result": "accept", "text": "%s %s agrees: %s." % [c.first_name, how, describe(state, offer)], "reasons": ev["reasons"], "counter": {}}
	c.loyalty = clampf(c.loyalty + float(rn.get("refused_loyalty", -3.0)), 0.0, 100.0)
	return {"result": "refuse", "text": "%s won't take worse terms than they have now." % c.first_name, "reasons": ev["reasons"], "counter": {}}


## Puts terms into effect: the wage, the place (an office, training, a
## workplace, a squire's place) and the home. Used when someone joins and
## when a retainer agrees to new terms.
static func _apply_terms(state: WorldState, c: CharacterData, offer: Dictionary) -> void:
	var pos := str(offer.get("position", "household"))
	if not c.office.is_empty() and not (pos == "office" and str(offer.get("office", "")) == c.office):
		CourtSystem.vacate(state, c.office)
	c.terms = offer.duplicate()
	c.agreed_wage = int(offer.get("wage", 0))
	# Leaving a squire's place or training: those duties end.
	if c.title == "squire" and pos != "squire":
		c.title = ""
	if pos == "household":
		c.focus = ""
	match pos:
		"training":
			CourtSystem.set_focus(state, c, str(offer.get("focus", c.best_attribute())))
		"office":
			if c.office != str(offer.get("office", "")):
				CourtSystem.appoint(state, str(offer.get("office", "")), c)
		"workplace":
			c.work_building_id = int(offer.get("workplace", -1))
		"squire":
			c.title = "squire"
			CourtSystem.set_focus(state, c, "combat")
	if pos != "workplace":
		CourtSystem.assign_workplace(state, c)
	var home := int(offer.get("home", -1))
	if home >= 0:
		move_household(state, c, state.get_building(home))
	elif home == MANOR_ROOMS:
		var manor := state.layout.buildings_of_type("manor")
		if not manor.is_empty():
			c.home_building_id = manor[0].id
	elif home == PROMISE_HOME:
		var open := false
		for p in state.house.promises:
			open = open or int(p.get("character", -1)) == c.id
		if not open:
			state.house.promises.append({"character": c.id, "kind": "home",
				"due": state.day() + int(cfg().get("promises", {}).get("home_days", 6)), "made": state.day()})


## Moves someone and the family living with them into a home.
static func move_household(state: WorldState, c: CharacterData, home: BuildingData) -> void:
	if home == null:
		return
	var old := c.home_building_id
	var fam := state.get_family(c.family_id)
	for p in state.characters:
		if p.family_id == c.family_id and p.home_building_id == old:
			p.home_building_id = home.id
	if fam:
		fam.home_building_id = home.id
	if state.territory:
		state.territory.home_since[home.id] = state.day()
	GrowthSystem.rename_home(state, home)


## Daily: promises kept or broken, and the house's standing with common folk.
## Returns events [{text, kind, character?}].
static func daily_update(state: WorldState, wages_paid: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var h := state.house
	if h == null:
		return events
	var pc: Dictionary = cfg().get("promises", {})
	var sc: Dictionary = cfg().get("standing", {})
	# Paying your people on time builds trust; failing to costs more.
	if not wages_paid:
		h.standing += float(sc.get("unpaid", -2.0))
	elif CourtSystem.daily_wages(state) > 0:
		h.standing += float(sc.get("daily_paid", 0.3))
	if TerritorySystem.is_hungry(state):
		h.standing += float(sc.get("hungry", -1.0))
	var still: Array[Dictionary] = []
	for p in h.promises:
		var c := state.get_character(int(p.get("character", -1)))
		if c == null or not c.retainer:
			continue
		if str(p.get("kind", "")) == "home":
			var homes := available_homes(state)
			if not homes.is_empty():
				move_household(state, c, homes[0])
				h.standing += float(pc.get("kept_standing", 2))
				c.loyalty = clampf(c.loyalty + float(pc.get("kept_loyalty", 6)), 0.0, 100.0)
				h.log_event(state.day(), "Kept your word: %s's family moved into %s." % [c.first_name, homes[0].name], "good")
				events.append({"text": "You kept your word: %s's family has moved into %s." % [c.full_name(), homes[0].name], "kind": "good", "character": c.id, "moved": true})
				continue
			if state.day() > int(p.get("due", 0)):
				c.loyalty = clampf(c.loyalty + float(pc.get("broken_loyalty", -25)), 0.0, 100.0)
				c.player_opinion = clampf(c.player_opinion + float(pc.get("broken_opinion", -20)), -100.0, 100.0)
				h.standing += float(pc.get("broken_standing", -8))
				h.log_event(state.day(), "Broke your promise of a home to %s." % c.full_name(), "bad")
				events.append({"text": "You broke your promise of a home to %s. Trust in your word falls." % c.full_name(), "kind": "bad", "character": c.id})
				if c.loyalty < float(CourtSystem.section("loyalty").get("leave_below", 18)):
					CourtSystem.dismiss(state, c, true)
					events.append({"text": "%s has left your service over the broken promise." % c.full_name(), "kind": "bad", "character": c.id})
				continue
		still.append(p)
	h.promises = still
	h.standing = clampf(h.standing, float(sc.get("min", 0.0)), float(sc.get("max", 100.0)))
	return events


static func standing_label(v: float) -> String:
	if v >= 75: return "trusted"
	if v >= 58: return "well regarded"
	if v >= 42: return "fair"
	if v >= 25: return "doubted"
	return "distrusted"
