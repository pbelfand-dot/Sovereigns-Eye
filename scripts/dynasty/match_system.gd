class_name MatchSystem
extends RefCounted
## Phase 4.2, the house's matches. The heir asks for someone's hand face to
## face, or accepts a suitor a neighbouring noble house sends; the house's
## kin and retainers are matched from their card. Nobody is made to marry:
## each weighs the match (what they think of the heir or their partner, the
## station it brings, duty and loyalty, a sweetheart already, temperament)
## and answers yes or no with their reasons, like an offer of service. A
## good match matters because children inherit their parents' gifts
## (TalentRoller): the Eye shows who is truly gifted, a suitor's family
## letter only praises.
##
## Suitors (RealmData houses) visit for a season, staying at the manor, so
## they can be met and looked at with the Eye. Accepting brings a dowry,
## renown and the house's good will; declining or letting the visit lapse
## costs some.
##
## Static and deterministic. Numbers: data/matches.json.


static func cfg() -> Dictionary:
	return GameData.load_file("matches")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


# --- Who may marry ---------------------------------------------------------------------------

## Could `a` and `b` marry? {ok, reason}
static func can_wed(state: WorldState, a: CharacterData, b: CharacterData) -> Dictionary:
	var ages := section("ages")
	if a == null or b == null or a == b:
		return {"ok": false, "reason": ""}
	for p: CharacterData in [a, b]:
		if p.age < int(ages.get("min", 16)):
			return {"ok": false, "reason": "%s is too young to marry (%d+)." % [p.first_name, int(ages.get("min", 16))]}
		if p.age > int(ages.get("max", 50)):
			return {"ok": false, "reason": "%s is past marrying." % p.first_name}
		if LifeSystem.spouse_of(state, p) != null:
			return {"ok": false, "reason": "%s is already married." % p.first_name}
	if a.gender == b.gender:
		return {"ok": false, "reason": "A match here is a husband and a wife."}
	if absi(a.age - b.age) > int(ages.get("gap", 15)):
		return {"ok": false, "reason": "They're too far apart in age."}
	if a.family_id == b.family_id or LifeSystem._related(a, b):
		return {"ok": false, "reason": "They're family."}
	for p: CharacterData in [a, b]:
		var other := b if p == a else a
		if p.is_visitor() and p.suitor_for != other.id:
			return {"ok": false, "reason": "%s came to court someone else." % p.first_name}
	return {"ok": true, "reason": ""}


## Whom `c` could marry, the likeliest first (what they think of each other,
## and gifts already seen with the Eye).
static func candidates(state: WorldState, c: CharacterData, limit: int = 8) -> Array[CharacterData]:
	var scored: Array[Array] = []
	for o in state.characters:
		if state.is_player(o) or not can_wed(state, c, o)["ok"]:
			continue
		var score := float(c.get_relationship(o.id).get("opinion", 0)) + float(o.get_relationship(c.id).get("opinion", 0))
		if o.appraised:
			score += o.best_potential() * 0.5
		scored.append([score, o])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]) if x[0] != y[0] else (x[1] as CharacterData).id < (y[1] as CharacterData).id)
	var out: Array[CharacterData] = []
	for s in scored.slice(0, limit):
		out.append(s[1])
	return out


## Does someone belong to the house's matches (the heir, kin, a retainer)?
static func of_the_house(state: WorldState, c: CharacterData) -> bool:
	return state.is_player(c) or CourtSystem.is_kin(state, c) or c.retainer


# --- Consent ---------------------------------------------------------------------------------

## How `c` weighs marrying `partner`. `arranged` when their own house asks it
## of them. {accept, score, reasons: [{text, good, weight}]}
static func consider(state: WorldState, c: CharacterData, partner: CharacterData, arranged: bool = false) -> Dictionary:
	var k := section("consent")
	var reasons: Array[Dictionary] = []
	# A lambda copies a local float, so the running score lives in an array.
	var total: Array[float] = [float(k.get("base", 0.1))]
	var add := func(v: float, text: String) -> void:
		total[0] += v
		if absf(v) >= 0.04:
			reasons.append({"text": text, "good": v > 0.0, "weight": absf(v)})
	if state.is_player(partner):
		var op := c.player_opinion
		add.call(op * float(k.get("opinion_of_heir", 0.006)), "They're fond of you." if op > 0.0 else "They don't care for you.")
	else:
		var op2 := float(c.get_relationship(partner.id).get("opinion", 0))
		if op2 != 0.0:
			add.call(op2 * float(k.get("opinion_of_partner", 0.005)), "They like %s." % partner.first_name if op2 > 0.0 else "They don't like %s." % partner.first_name)
	if arranged:
		if CourtSystem.is_kin(state, c):
			add.call(float(k.get("duty", 0.35)), "They'll do their duty by the house.")
		elif c.retainer:
			var from := float(k.get("loyalty_from", 40))
			add.call((c.loyalty - from) * float(k.get("loyalty", 0.008)), "Loyal to your house." if c.loyalty >= from else "Their loyalty is thin.")
	if _station(state, partner) > _station(state, c):
		add.call(float(k.get("station", 0.35)), "A step up in the world for them.")
	var sweetheart := LifeSystem.lover_of(state, c)
	if sweetheart and sweetheart != partner:
		add.call(float(k.get("courting_other", -0.6)), "Their heart is set on %s." % sweetheart.first_name)
	if c.get_relationship(partner.id).get("type", "") == "rival":
		add.call(float(k.get("rival", -0.8)), "%s is their rival." % partner.first_name)
	var gap := absi(c.age - partner.age) - int(k.get("gap_from", 8))
	if gap > 0:
		add.call(-gap * float(k.get("gap_cost", 0.04)), "The years between them.")
	var traits: Dictionary = k.get("traits", {})
	for t in c.traits:
		if traits.has(t):
			var v := float(traits[t])
			add.call(v, ("Ambitious: the match would raise them." if t == "ambitious" else "%s." % str(GameData.trait_def(t).get("name", t)).capitalize()))
	reasons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
	var score := total[0]
	return {"accept": score >= float(k.get("threshold", 0.5)), "score": score, "reasons": reasons}


## Where someone stands: the house's own rank as nobles; a retainer's family
## above the villagers.
static func _station(state: WorldState, c: CharacterData) -> int:
	if CourtSystem.is_kin(state, c) or state.is_player(c) or c.is_visitor():
		return int(GameData.status_def("noble").get("tier", 5))
	return c.status_tier()


static func _answer(state: WorldState, key: String, partner: CharacterData = null) -> String:
	var lines: Array = section("answers").get(key, ["..."])
	var text := str(lines[(state.day() + (partner.id if partner else 0)) % lines.size()])
	text = Discovery._fill(text, state).replace("{name}", partner.first_name if partner else "")
	return "\"%s\"" % (text.substr(0, 1).to_upper() + text.substr(1))


# --- Proposals -------------------------------------------------------------------------------

## The heir asks `c` for their hand, face to face. {ok, accept, text, reasons}
static func propose(state: WorldState, c: CharacterData, events: Array[Dictionary] = []) -> Dictionary:
	var heir := state.player()
	var can := can_wed(state, heir, c)
	if not can["ok"]:
		return {"ok": false, "accept": false, "text": str(can["reason"]), "reasons": []}
	var r := consider(state, c, heir)
	if r["accept"]:
		wed(state, heir, c, events)
	return {"ok": true, "accept": r["accept"], "text": _answer(state, "yes" if r["accept"] else "no"), "reasons": r["reasons"]}


## The house matches one of its own (`member`: kin or a retainer) with
## `partner`; both must agree. {ok, accept, text, reasons}
static func arrange(state: WorldState, member: CharacterData, partner: CharacterData, events: Array[Dictionary] = []) -> Dictionary:
	if not of_the_house(state, member) or state.is_player(member):
		return {"ok": false, "accept": false, "text": "Only your kin and retainers are matched by the house.", "reasons": []}
	var can := can_wed(state, member, partner)
	if not can["ok"]:
		return {"ok": false, "accept": false, "text": str(can["reason"]), "reasons": []}
	var mine := consider(state, member, partner, true)
	var theirs := consider(state, partner, member, of_the_house(state, partner))
	var reasons: Array[Dictionary] = []
	for r: Dictionary in mine["reasons"]:
		reasons.append({"text": "%s: %s" % [member.first_name, r["text"]], "good": r["good"], "weight": r["weight"]})
	for r: Dictionary in theirs["reasons"]:
		reasons.append({"text": "%s: %s" % [partner.first_name, r["text"]], "good": r["good"], "weight": r["weight"]})
	reasons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
	var accept := bool(mine["accept"]) and bool(theirs["accept"])
	var text := ""
	if accept:
		wed(state, member, partner, events)
		text = "%s and %s agree to marry." % [member.full_name(), partner.full_name()]
	elif not mine["accept"] and not theirs["accept"]:
		text = "Neither %s nor %s will hear of it." % [member.first_name, partner.first_name]
	elif not mine["accept"]:
		text = "%s: %s" % [member.first_name, _answer(state, "no_partner", partner)]
	else:
		text = "%s: %s" % [partner.first_name, _answer(state, "no")]
	return {"ok": true, "accept": accept, "text": text, "reasons": reasons}


## Marries `member` (the heir, kin or a retainer) to `partner`, who joins
## their family and home: into the house at the manor for the heir and kin,
## into a retainer's home for a retainer.
static func wed(state: WorldState, member: CharacterData, partner: CharacterData, events: Array[Dictionary] = []) -> void:
	var w := section("wedding")
	var was_noble := _station(state, partner) >= int(GameData.status_def("noble").get("tier", 5))
	var local := not partner.is_visitor() and not CourtSystem.is_kin(state, partner)
	LifeSystem.link_spouses(state, member, partner)
	var moved: Array[int] = []
	var into_house := state.is_player(member) or CourtSystem.is_kin(state, member)
	if into_house:
		var fam := state.ruling_family()
		moved = LifeSystem.join(state, partner, fam)
		partner.last_name = fam.name
		var lord := fam.head_id == member.id
		partner.occupation_id = "lady" if lord else "noble_scion"
		partner.social_status = "noble"
		partner.work_building_id = CourtSystem._building_of_type(state, "manor")
		partner.met = true
		var renown := int(w.get("renown_noble", 6)) if was_noble else int(w.get("renown_commoner", -2))
		state.house.renown = maxi(state.house.renown + renown, 0)
		if state.is_player(member) and local:
			for c in state.characters:
				if not CourtSystem.is_kin(state, c):
					c.player_opinion = clampf(c.player_opinion + float(w.get("village_opinion_local", 3)), -100.0, 100.0)
	else:
		moved = LifeSystem.join(state, partner, state.get_family(member.family_id))
	partner.visiting_until = -1
	partner.suitor_for = -1
	partner.player_opinion = clampf(partner.player_opinion + float(w.get("spouse_opinion", 25)), -100.0, 100.0)
	partner.loyalty = clampf(partner.loyalty + float(w.get("spouse_loyalty", 15)), 0.0, 100.0)
	var text := "%s and %s are married." % [member.display_name(), partner.display_name()]
	if state.is_player(member):
		text = "You and %s are married." % partner.display_name()
	state.house.log_event(state.day(), text, "marriage")
	events.append({"text": text, "kind": "good", "character": partner.id, "moved": moved, "job": partner.id})


# --- Suitors ---------------------------------------------------------------------------------

## The suitor visiting now (one at a time), or null.
static func visitor(state: WorldState) -> CharacterData:
	for c in state.characters:
		if c.is_visitor():
			return c
	return null


## How a house feels toward yours, in a word (standing -100..100).
static func standing_word(standing: int) -> String:
	if standing >= 40:
		return "warm"
	if standing >= 10:
		return "friendly"
	if standing > -10:
		return "cordial"
	if standing > -40:
		return "cool"
	return "cold"


## The dowry a house sends with its son or daughter (gold).
static func dowry(state: WorldState, house_id: int) -> int:
	var s := section("suitors")
	var h := state.realm.get_house(house_id) if state.realm else {}
	return roundi(float(s.get("dowry_base", 40)) + float(h.get("renown", 0)) * float(s.get("dowry_per_renown", 1.6)))


## Who the houses may send a suitor for: the heir while unmarried, then the
## house's unmarried kin of an age.
static func seeks(state: WorldState, c: CharacterData) -> bool:
	var ages := section("ages")
	if c.age < int(ages.get("min", 16)) or LifeSystem.spouse_of(state, c) != null or c.is_away():
		return false
	if state.is_player(c):
		return c.age <= int(ages.get("max", 50))
	return CourtSystem.is_kin(state, c) and c.age <= int(section("suitors").get("kin_max_age", 40))


## Once a day: a visit ends when it's due; with no one visiting, the next
## suitor is set to come some days on (around a year / yearly_*, so no long
## droughts and no crowding), for the heir first, else unmarried kin.
## Returns events: {text, kind, visitor?, gone?}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.realm == null or state.realm.houses.is_empty() or state.house == null:
		return events
	var day := state.day()
	for c in state.characters.duplicate():
		if c.is_visitor() and state.get_character(c.suitor_for) == null:
			send_home(state, c, "bereaved", events)
		elif c.is_visitor() and day >= c.visiting_until and not state.get_character(c.suitor_for).is_away():
			send_home(state, c, "lapse", events)  # (they wait while the one they came for is away)
	if visitor(state) != null:
		return events
	var target := _sought(state)
	if target == null:
		state.realm.next_suitor_day = -1
		return events
	var rng := Seeds.rng(state.world_seed, "suitors_%d" % day)
	if state.realm.next_suitor_day < 0:
		state.realm.next_suitor_day = day + suitor_gap(state, target, rng)
	elif day >= state.realm.next_suitor_day:
		state.realm.next_suitor_day = -1
		offer(state, target, rng, events)
	return events


## Whom the next suitor comes for: the heir while unmarried, else the eldest
## unmarried kin of an age.
static func _sought(state: WorldState) -> CharacterData:
	var heir := state.player()
	if heir and seeks(state, heir):
		return heir
	var best: CharacterData = null
	var fam := state.ruling_family()
	for id in (fam.member_ids if fam else []):
		var kin := state.get_character(id)
		if kin and seeks(state, kin) and (best == null or kin.age > best.age):
			best = kin
	return best


## Days until the next suitor for `target`: half to one and a half times
## the average gap (a year / yearly_heir or yearly_kin).
static func suitor_gap(state: WorldState, target: CharacterData, rng: RandomNumberGenerator) -> int:
	var s := section("suitors")
	var yearly := float(s.get("yearly_heir", 1.4)) if state.is_player(target) else float(s.get("yearly_kin", 0.6))
	var mean := float(Calendar.days_per_year()) / maxf(yearly, 0.01)
	return maxi(1, roundi(mean * rng.randf_range(0.5, 1.5)))


## A house sends a suitor for `target`; they arrive today and stay at the
## manor until the visit is over.
static func offer(state: WorldState, target: CharacterData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> CharacterData:
	# Every house sends suitors; the renowned and the friendly a little more.
	var weights := {}
	for h in state.realm.houses:
		weights[str(h["id"])] = maxf(1.0, 25.0 + (float(h["renown"]) + float(h["standing"])) * 0.5)
	var house := state.realm.get_house(int(Seeds.weighted_key(rng, weights)))
	var suitor := CharacterGenerator.suitor(state, house, target, "suitor_%d" % state.day())
	suitor.visiting_until = state.day() + int(section("suitors").get("visit_days", 10))
	suitor.suitor_for = target.id
	var entry := GrowthSystem.entry_point(state, rng)
	suitor.position = TerrainHeight.on_ground(entry) if state.layout else entry
	var praise := letter(state, suitor)
	var leave := Calendar.format_date(suitor.visiting_until * Calendar.MINUTES_PER_DAY)
	var whom := "you" if state.is_player(target) else target.first_name
	var pron := "She" if suitor.gender == "female" else "He"
	var text := "%s offers the hand of %s (%d) for %s, with a dowry of %d gold. %s arrives today and stays at the manor until %s. Their letter says: \"%s\"" % [
		state.realm.house_title(suitor.house_id), suitor.full_name(), suitor.age, whom, dowry(state, suitor.house_id), pron, leave, praise]
	state.house.log_event(state.day(), "%s offered the hand of %s for %s." % [state.realm.house_title(suitor.house_id), suitor.full_name(), "the heir" if state.is_player(target) else target.full_name()], "match")
	events.append({"text": text, "kind": "join", "visitor": suitor.id})
	return suitor


## The letter that came with a suitor (the same each time it's read).
static func letter(state: WorldState, suitor: CharacterData) -> String:
	return praise_for(suitor, Seeds.rng(state.world_seed, "letter_%d" % suitor.id))


## What a suitor's family writes of them: their gift, oversold (only the Eye
## tells the truth). A clue at best.
static func praise_for(c: CharacterData, rng: RandomNumberGenerator) -> String:
	var topic := Discovery.pick_topic(c, rng)
	var level := Discovery.intensity(c, topic, rng)
	if rng.randf() * 100.0 < float(section("suitors").get("boast", 30)):
		level = mini(level + 1, 2)
	var lines: Array = section("praise").get(topic, [["{He} is of good family."]])
	var f := c.gender == "female"
	return str(Seeds.pick(rng, lines[mini(level, lines.size() - 1)])).replace("{He}", "She" if f else "He").replace("{His}", "Her" if f else "His") \
		.replace("{he}", "she" if f else "he").replace("{his}", "her" if f else "his").replace("{him}", "her" if f else "him")


## Accepts a visiting suitor: they marry whom they came for. Brings the
## dowry, renown and the house's good will. {ok, text}
static func accept(state: WorldState, suitor: CharacterData, events: Array[Dictionary] = []) -> Dictionary:
	if not suitor.is_visitor():
		return {"ok": false, "text": "%s isn't here as a suitor." % suitor.first_name}
	var target := state.get_character(suitor.suitor_for)
	var can := can_wed(state, target, suitor)
	if not can["ok"]:
		return {"ok": false, "text": str(can["reason"])}
	var gold := dowry(state, suitor.house_id)
	Realm.change_regard(state, suitor.house_id, int(section("suitors").get("standing_accept", 25)))
	state.house.gold += gold
	var born_name := suitor.full_name()
	wed(state, target, suitor, events)
	var text := "%s weds %s. %s sends a dowry of %d gold." % [born_name, "you" if state.is_player(target) else target.full_name(), state.realm.house_title(suitor.house_id), gold]
	# The wedding's news carries the dowry (one notice, not two).
	events[-1]["text"] = text
	return {"ok": true, "text": text}


## Declines a suitor: they go home, and their house thinks less of yours.
static func decline(state: WorldState, suitor: CharacterData, events: Array[Dictionary] = []) -> Dictionary:
	if not suitor.is_visitor():
		return {"ok": false, "text": ""}
	var text := "You decline the offer of %s. %s goes home to %s." % [state.realm.house_title(suitor.house_id), suitor.full_name(), state.realm.get_house(suitor.house_id).get("seat", "")]
	send_home(state, suitor, "decline", events)
	return {"ok": true, "text": text}


## A suitor leaves for home: declined, the visit ran out with no answer
## ("lapse"), or the one they came for died ("bereaved", no offence).
static func send_home(state: WorldState, suitor: CharacterData, why: String, events: Array[Dictionary]) -> void:
	var house := state.realm.get_house(suitor.house_id)
	var s := section("suitors")
	var cost := int(s.get("standing_lapse", -12)) if why == "lapse" else int(s.get("standing_decline", -8))
	if why == "bereaved":
		cost = 0
	if not house.is_empty():
		house["standing"] = clampi(int(house["standing"]) + cost, -100, 100)
	suitor.add_history(state.current_year(), state.current_season(), "family", "Went home from %s unwed" % state.village_name)
	var text := ""
	if why == "lapse":
		text = "%s has gone home to %s: no answer came. %s is offended." % [suitor.full_name(), house.get("seat", ""), state.realm.house_title(suitor.house_id)]
		state.house.log_event(state.day(), text, "bad")
	elif why == "bereaved":
		text = "%s has gone home to %s: the one they came to marry has died." % [suitor.full_name(), house.get("seat", "")]
	else:
		state.house.log_event(state.day(), "You declined the hand of %s." % suitor.full_name(), "match")
	suitor.visiting_until = -1
	LifeSystem.depart(state, suitor, "left", "going home to House %s" % house.get("name", ""), events)
	events.append({"text": text, "kind": "bad", "gone": suitor.id})
