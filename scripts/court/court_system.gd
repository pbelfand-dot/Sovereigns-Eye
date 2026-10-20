class_name CourtSystem
extends RefCounted
## Phase 2 - Noble Society: the rules of the player's court.
##
## The player is the heir of the ruling house. With Appraisal they can see who
## is gifted; with this system they act on it:
##   talk / gift      -> raise someone's opinion of the player
##   recruit          -> swear them in as a retainer (or a page, if 10-15)
##   appoint          -> give them an office (Steward, Marshal, Chancellor...)
##   focus            -> choose which attribute they train
##   knight           -> raise a proven retainer to knighthood
## Every day retainers train toward their potential, wages are paid, renown
## accrues and loyalty is tested. All numbers live in data/court.json.
##
## Everything here is static and works on WorldState + CharacterData, so it
## runs the same in the game, in headless tests and on saved games.

const TRAINABLE := ["leadership", "combat", "intelligence", "politics", "administration"]


static func config() -> Dictionary:
	return GameData.load_file("court")


static func section(key: String) -> Dictionary:
	return config().get(key, {})


static func offices() -> Array:
	return config().get("offices", [])


static func office_def(office_id: String) -> Dictionary:
	for o: Dictionary in offices():
		if str(o["id"]) == office_id:
			return o
	return {}


static func office_name(office_id: String) -> String:
	return str(office_def(office_id).get("name", office_id.capitalize()))


static func house_name(state: WorldState) -> String:
	var f := state.ruling_family()
	return f.display_name() if f else "your house"


static func attr_name(attr_id: String) -> String:
	return str(GameData.attribute_def(attr_id).get("name", attr_id.capitalize()))


# --- Setup -----------------------------------------------------------------------

## Creates the house, picks the player and rolls everyone's opinion of them.
## Runs for new games and for saves made before Phase 2. Deterministic.
static func initialize(state: WorldState) -> void:
	if state.house != null and (state.get_character(state.player_id) != null or state.house.ended):
		return
	var h := section("house")
	state.house = HouseData.new()
	state.house.gold = int(h.get("start_gold", 200))
	state.house.renown = int(h.get("start_renown", 10))
	state.player_id = pick_player(state)
	var rng := Seeds.rng(state.world_seed, "court")
	for c in state.characters:
		c.player_opinion = roll_opinion(state, c, rng)
	initialize_meetings(state)
	var p := state.player()
	if p:
		p.player_opinion = 100.0
		p.appraised = true  # you know yourself
	var fam := state.ruling_family()
	if fam and fam.head_id >= 0:
		state.house.rulers.append({"id": fam.head_id, "from": state.day(), "to": -1})
	state.house.log_event(state.day(), "%s takes up the running of %s's household." % [p.full_name() if p else "The heir", house_name(state)], "house")


## The heir has always known their own family (they still need the Eye to
## see their gifts). Safe to call again on loaded games.
static func initialize_meetings(state: WorldState) -> void:
	for c in state.characters:
		if c.family_id == state.ruling_family_id or state.is_player(c):
			c.met = true


## Someone's starting opinion of the player (-100..100): a roll, kinship,
## manor service and personality.
static func roll_opinion(state: WorldState, c: CharacterData, rng: RandomNumberGenerator) -> float:
	var op := section("opinion")
	var trait_mods: Dictionary = op.get("traits", {})
	var manor := _building_of_type(state, "manor")
	var v := float(op.get("base", 5)) + rng.randf_range(-1.0, 1.0) * float(op.get("spread", 15))
	if c.family_id == state.ruling_family_id:
		v += float(op.get("ruling_family", 55))
	elif manor >= 0 and c.work_building_id == manor:
		v += float(op.get("manor_staff", 15))
	for t in c.traits:
		v += float(trait_mods.get(t, 0.0))
	return clampf(v, -100.0, 100.0)


## The ruling family's scion closest to the preferred age, else the lord.
static func pick_player(state: WorldState) -> int:
	var fam := state.ruling_family()
	if fam == null:
		return state.characters[0].id if not state.characters.is_empty() else -1
	var preferred := int(section("player").get("preferred_age", 16))
	var best := -1
	var best_score := INF
	for id in fam.member_ids:
		var c := state.get_character(id)
		if c == null or c.age < 12:
			continue
		var score := absf(c.age - preferred) + (0.0 if c.occupation_id == "noble_scion" else 20.0)
		if score < best_score:
			best_score = score
			best = c.id
	return best if best >= 0 else fam.head_id


static func _building_of_type(state: WorldState, type: String) -> int:
	if state.layout == null:
		return -1
	var list := state.layout.buildings_of_type(type)
	return list[0].id if not list.is_empty() else -1


# --- Roles & names -------------------------------------------------------------------

static func is_kin(state: WorldState, c: CharacterData) -> bool:
	return c.family_id == state.ruling_family_id


## What the person is to the player's court: "Heir of House X", "Marshal",
## "Page", "Retainer"... or their ordinary occupation.
static func role_name(state: WorldState, c: CharacterData) -> String:
	if state.is_player(c):
		var fam := state.ruling_family()
		if fam and fam.head_id == c.id:
			return "%s of %s" % [c.occupation_name(), state.village_name]
		return "Heir of %s" % house_name(state)
	if c.is_visitor():
		return "Suitor from House %s" % state.realm.get_house(c.house_id).get("name", "?") if state.realm else "A guest"
	if Succession.regent(state) == c:
		return "Regent of %s" % state.village_name
	if Succession.heir(state) == c:
		return "Your heir"
	if not c.office.is_empty():
		return office_name(c.office)
	if c.retainer:
		if c.age < 16:
			return "Page" if c.gender == "male" else "Lady-in-waiting"
		return "Knight of the house" if c.is_knight() else "Retainer"
	return c.occupation_name()


static func opinion_label(v: float) -> String:
	if v >= 70: return "Devoted to you"
	if v >= 40: return "Fond of you"
	if v >= 15: return "Friendly"
	if v > -15: return "Neutral"
	if v > -40: return "Wary of you"
	return "Dislikes you"


# --- Talk & gifts ------------------------------------------------------------------------

static func can_talk(state: WorldState, c: CharacterData) -> Dictionary:
	if state.is_player(c):
		return {"ok": false, "reason": "That's you."}
	if c.age < 6:
		return {"ok": false, "reason": "Too young for conversation."}
	if c.last_talk_day == state.day():
		return {"ok": false, "reason": "You already spoke with them today."}
	return {"ok": true, "reason": ""}


## A conversation: raises their opinion of the player a little, once a day.
static func talk(state: WorldState, c: CharacterData, rng: RandomNumberGenerator) -> Dictionary:
	var check := can_talk(state, c)
	if not check["ok"]:
		return {"ok": false, "text": check["reason"], "delta": 0.0}
	var cfg := section("talk")
	var player := state.player()
	var politics := float(player.get_current("politics")) if player else 0.0
	var delta := float(cfg.get("base", 3.0)) + politics / float(cfg.get("politics_divisor", 30.0)) \
		+ rng.randf_range(-1.0, 1.0) * float(cfg.get("spread", 2.0))
	var mods: Dictionary = cfg.get("traits", {})
	for t in c.traits:
		delta *= float(mods.get(t, 1.0))
	if c.player_opinion >= float(cfg.get("cap", 60)):
		delta *= 0.25
	delta = maxf(delta, 0.5)
	c.player_opinion = clampf(c.player_opinion + delta, -100.0, 100.0)
	c.last_talk_day = state.day()
	var topic := _talk_topic(c, rng)
	return {"ok": true, "delta": delta, "text": "You talk with %s about %s. (+%d opinion)" % [c.first_name, topic, roundi(delta)]}


static func _talk_topic(c: CharacterData, rng: RandomNumberGenerator) -> String:
	var topics := ["the harvest", "village gossip", "the weather", "their family", "the road to the capital"]
	if c.retainer:
		topics.append_array(["their training", "the affairs of the house"])
	if c.age < 14:
		topics = ["their games", "the stories they've heard", "what they want to be"]
	return str(topics[rng.randi_range(0, topics.size() - 1)])


static func gift_cost(c: CharacterData) -> int:
	var costs: Array = section("gift").get("cost_by_tier", [10, 15, 25, 25, 40, 60, 100])
	return int(costs[clampi(c.status_tier(), 0, costs.size() - 1)])


static func can_gift(state: WorldState, c: CharacterData) -> Dictionary:
	if state.is_player(c):
		return {"ok": false, "reason": "That's you."}
	var cost := gift_cost(c)
	if state.house.gold < cost:
		return {"ok": false, "reason": "Not enough gold (%d needed)." % cost}
	return {"ok": true, "reason": "", "cost": cost}


static func gift(state: WorldState, c: CharacterData) -> Dictionary:
	var check := can_gift(state, c)
	if not check["ok"]:
		return {"ok": false, "text": check["reason"]}
	var cfg := section("gift")
	var cost := gift_cost(c)
	var delta := float(cfg.get("opinion", 10.0))
	var mods: Dictionary = cfg.get("traits", {})
	for t in c.traits:
		delta *= float(mods.get(t, 1.0))
	if c.player_opinion >= 60.0:
		delta *= 0.5
	state.house.gold -= cost
	c.player_opinion = clampf(c.player_opinion + delta, -100.0, 100.0)
	c.happiness = clampf(c.happiness + 4.0, 0.0, 100.0)
	return {"ok": true, "text": "You give %s a gift worth %d gold. (+%d opinion)" % [c.first_name, cost, roundi(delta)]}


# --- Recruitment ------------------------------------------------------------------------

static func retainer_cap(state: WorldState) -> int:
	var h := section("house")
	return int(h.get("retainer_cap_base", 4)) + floori(state.house.renown / float(h.get("renown_per_extra_retainer", 15))) \
		+ (CharterSystem.retainer_bonus(state) if state.territory else 0)


static func retainer_count(state: WorldState) -> int:
	return state.retainers().size()


## Makes someone a retainer (no checks; Recruitment.propose decides).
static func join(state: WorldState, c: CharacterData) -> void:
	c.retainer = true
	c.joined_day = state.day()
	c.former_status = c.social_status
	c.former_work = c.work_building_id
	if c.status_tier() < int(GameData.status_def("retainer").get("tier", 3)):
		c.social_status = "retainer"
	c.loyalty = clampf(c.loyalty + 15.0, 0.0, 100.0)
	c.happiness = clampf(c.happiness + 10.0, 0.0, 100.0)
	c.player_opinion = clampf(c.player_opinion + 10.0, -100.0, 100.0)
	c.focus = ""
	assign_workplace(state, c)
	c.add_history(state.current_year(), state.current_season(), "appointment",
		"Swore service to %s%s" % [house_name(state), " as a page" if c.age < 16 else ""])
	state.house.log_event(state.day(), "%s joined the household." % c.full_name(), "join")


## Releases a retainer. `left` = they quit rather than being dismissed;
## `quiet` = they rise to rule the house (Succession): no penalty, no news.
static func dismiss(state: WorldState, c: CharacterData, left: bool = false, quiet: bool = false) -> void:
	if not c.retainer:
		return
	if not c.office.is_empty():
		vacate(state, c.office)
	c.retainer = false
	if not c.is_knight() and not c.former_status.is_empty():
		c.social_status = c.former_status
	if c.former_work >= 0:
		c.work_building_id = c.former_work
	c.focus = ""
	c.training_progress.clear()
	# The terms they joined on end with their service.
	c.terms = {}
	c.agreed_wage = -1
	c.title = ""
	var open_promises: Array[Dictionary] = []
	for p in state.house.promises:
		if int(p.get("character", -1)) != c.id:
			open_promises.append(p)
	state.house.promises = open_promises
	if quiet:
		return  # they rise above service (they rule now, Succession)
	if left:
		c.player_opinion = clampf(c.player_opinion - 10.0, -100.0, 100.0)
		c.add_history(state.current_year(), state.current_season(), "career", "Left the service of %s" % house_name(state))
		state.house.log_event(state.day(), "%s has left your service." % c.full_name(), "leave")
	else:
		c.player_opinion = clampf(c.player_opinion - 20.0, -100.0, 100.0)
		c.loyalty = clampf(c.loyalty - 15.0, 0.0, 100.0)
		c.add_history(state.current_year(), state.current_season(), "career", "Dismissed from the service of %s" % house_name(state))
		state.house.log_event(state.day(), "You dismissed %s." % c.full_name(), "leave")


# --- Offices & focus ------------------------------------------------------------------------

static func can_appoint(state: WorldState, office_id: String, c: CharacterData) -> Dictionary:
	if office_def(office_id).is_empty():
		return {"ok": false, "reason": "No such office."}
	if not c.retainer:
		return {"ok": false, "reason": "Only retainers can hold an office."}
	if c.age < 16:
		return {"ok": false, "reason": "Too young to hold an office (16+)."}
	if c.office == office_id:
		return {"ok": false, "reason": "Already holds that office."}
	return {"ok": true, "reason": ""}


static func appoint(state: WorldState, office_id: String, c: CharacterData) -> Dictionary:
	var check := can_appoint(state, office_id, c)
	if not check["ok"]:
		return {"ok": false, "text": check["reason"]}
	var previous := state.get_character(state.house.holder_of(office_id))
	if previous and previous != c:
		vacate(state, office_id)
		previous.player_opinion = clampf(previous.player_opinion - 8.0, -100.0, 100.0)
	if not c.office.is_empty():
		vacate(state, c.office)
	c.office = office_id
	state.house.offices[office_id] = c.id
	c.player_opinion = clampf(c.player_opinion + 5.0, -100.0, 100.0)
	c.loyalty = clampf(c.loyalty + 5.0, 0.0, 100.0)
	assign_workplace(state, c)
	var name := office_name(office_id)
	c.add_history(state.current_year(), state.current_season(), "appointment", "Appointed %s of %s" % [name, house_name(state)])
	state.house.log_event(state.day(), "%s was appointed %s." % [c.full_name(), name], "office")
	# Rivals in the household resent being passed over.
	var resentful: Array[String] = []
	for r in c.relationships_of_type(["rival"]):
		var rival := state.get_character(int(r["target"]))
		if rival and rival.retainer:
			rival.loyalty = clampf(rival.loyalty - 5.0, 0.0, 100.0)
			rival.player_opinion = clampf(rival.player_opinion - 5.0, -100.0, 100.0)
			resentful.append(rival.first_name)
	var text := "%s is now your %s." % [c.full_name(), name]
	if not resentful.is_empty():
		text += " Their rival %s resents it." % ", ".join(resentful)
	return {"ok": true, "text": text}


static func vacate(state: WorldState, office_id: String) -> void:
	var holder := state.get_character(state.house.holder_of(office_id))
	state.house.offices.erase(office_id)
	if holder and holder.office == office_id:
		holder.office = ""
		assign_workplace(state, holder)


## Which attribute someone trains: the player's choice, else their greatest
## trainable talent.
static func focus_of(c: CharacterData) -> String:
	if not c.focus.is_empty():
		return c.focus
	var best := ""
	var best_p := -1
	for a: String in TRAINABLE:
		if c.get_potential(a) > best_p:
			best_p = c.get_potential(a)
			best = a
	return best


static func set_focus(state: WorldState, c: CharacterData, attr_id: String) -> void:
	if attr_id in TRAINABLE:
		c.focus = attr_id
		if c.retainer:
			assign_workplace(state, c)


## Puts the retainer's daily work where their duties are: their office's
## building, the training yard for fighters, otherwise the manor.
static func assign_workplace(state: WorldState, c: CharacterData) -> void:
	if not c.retainer:
		return
	var agreed := state.get_building(int(c.terms.get("workplace", -1)))
	if agreed and c.office.is_empty():
		c.work_building_id = agreed.id
		return
	var type := "manor"
	if not c.office.is_empty():
		type = str(office_def(c.office).get("work", "manor"))
	elif focus_of(c) in ["combat", "leadership"]:
		type = "barracks"
	var b := _building_of_type(state, type)
	if b < 0:
		b = _building_of_type(state, "manor")
	if b >= 0:
		c.work_building_id = b


## A craftsperson who joined for a workplace of their own keeps their
## trade's working day there (until they're given an office).
static func has_trade_terms(c: CharacterData) -> bool:
	return c.retainer and c.office.is_empty() and int(c.terms.get("workplace", -1)) >= 0


## Work behaviour for the NPC brain ("" = use the occupation's).
static func work_style(c: CharacterData) -> String:
	if not c.retainer or has_trade_terms(c):
		return ""
	if not c.office.is_empty():
		return str(office_def(c.office).get("work_style", "estate"))
	return "drill" if focus_of(c) in ["combat", "leadership"] else "estate"


static func work_text(state: WorldState, c: CharacterData) -> String:
	if not c.retainer:
		return ""
	if has_trade_terms(c):
		var b := state.get_building(c.work_building_id)
		return "Working at %s for %s" % [b.name if b else "their workshop", house_name(state)]
	if not c.office.is_empty():
		return str(office_def(c.office).get("activity", "Serving the house"))
	return "Training %s for %s" % [attr_name(focus_of(c)), house_name(state)]


## What a scion of the house (or a suitor staying at the manor) is about.
static func scion_text(state: WorldState, c: CharacterData) -> String:
	if c.is_visitor():
		return "A guest at the manor, come as a suitor"
	if is_tutored(state, c):
		return "Studying %s with tutors" % attr_name(focus_of(c))
	return "Helping to run the estate"


## Schedule override: pages keep a scion's day of lessons; adult retainers use
## the noble household routine so even former children or elders attend work.
static func schedule_for(c: CharacterData) -> String:
	if has_trade_terms(c):
		return ""
	if c.retainer:
		return "scion" if c.age < 16 else "noble"
	return ""


# --- Knighthood ----------------------------------------------------------------------------

static func can_knight(state: WorldState, c: CharacterData) -> Dictionary:
	var cfg := section("knighthood")
	if not c.retainer:
		return {"ok": false, "reason": "Only your retainers can be knighted."}
	if c.is_knight():
		return {"ok": false, "reason": "Already a knight."}
	if c.age < int(cfg.get("min_age", 16)):
		return {"ok": false, "reason": "Too young to be knighted (16+)."}
	if c.get_current("combat") < int(cfg.get("min_combat", 50)) and c.get_current("leadership") < int(cfg.get("min_leadership", 50)):
		return {"ok": false, "reason": "Needs Combat or Leadership of %d first." % int(cfg.get("min_combat", 50))}
	if state.house.gold < int(cfg.get("cost", 60)):
		return {"ok": false, "reason": "Knighting costs %d gold." % int(cfg.get("cost", 60))}
	return {"ok": true, "reason": "", "cost": int(cfg.get("cost", 60))}


static func knight(state: WorldState, c: CharacterData) -> Dictionary:
	var check := can_knight(state, c)
	if not check["ok"]:
		return {"ok": false, "text": check["reason"]}
	var cfg := section("knighthood")
	state.house.gold -= int(cfg.get("cost", 60))
	state.house.renown += int(cfg.get("renown", 5))
	c.social_status = "knight"
	c.title = ""
	c.loyalty = clampf(c.loyalty + float(cfg.get("loyalty", 15)), 0.0, 100.0)
	c.player_opinion = clampf(c.player_opinion + float(cfg.get("opinion", 20)), -100.0, 100.0)
	c.happiness = clampf(c.happiness + 10.0, 0.0, 100.0)
	var p := state.player()
	c.add_history(state.current_year(), state.current_season(), "achievement", "Knighted by %s of %s" % [p.full_name() if p else "the heir", house_name(state)])
	state.house.log_event(state.day(), "%s was knighted." % c.display_name(), "knight")
	return {"ok": true, "text": "Arise, %s!" % c.display_name()}


# --- Money --------------------------------------------------------------------------------

static func _base_wage(c: CharacterData, ward: bool) -> int:
	var w := section("wages")
	if ward:
		return int(w.get("ward", 1))
	return int(w.get("knight", 4)) if c.is_knight() else int(w.get("retainer", 2))


## Gold a day: the wage they agreed to when they joined (else the standard
## wage), plus an office's stipend for an office given after joining.
static func wage(c: CharacterData) -> int:
	if not c.retainer:
		return 0
	var total := c.agreed_wage if c.agreed_wage >= 0 else _base_wage(c, c.age < 16)
	if not c.office.is_empty() and str(c.terms.get("office", "")) != c.office:
		total += int(section("wages").get("office", 3))
	return total


## Gold a day for the household: wages, plus upkeep for every retainer
## beyond what your renown supports.
static func daily_wages(state: WorldState) -> int:
	return retainer_wages(state) + tutored(state).size() * int(section("tutors").get("fee", 1)) + household_upkeep(state)


## What the retainers are paid a day (without tutors or upkeep).
static func retainer_wages(state: WorldState) -> int:
	var total := 0
	for c in state.retainers():
		total += wage(c)
	return total


## Upkeep for a household larger than your renown supports (gold a day).
static func household_upkeep(state: WorldState, extra: int = 0) -> int:
	var over := maxi(retainer_count(state) + extra - retainer_cap(state), 0)
	return over * int(section("house").get("over_cap_upkeep", 2))


static func daily_income(state: WorldState) -> int:
	var base := float(section("house").get("base_income", 18)) + GrowthSystem.rent(state) + CharterSystem.dues(state)
	var steward := state.get_character(state.house.holder_of("steward"))
	if steward:
		base *= 1.0 + steward.get_current("administration") / float(office_def("steward").get("effect_divisor", 200.0))
	# A young ruler's regent runs the house well or badly (Succession).
	base *= maxf(0.0, 1.0 + Succession.regent_income_factor(state))
	return roundi(base)


static func daily_renown(state: WorldState) -> float:
	var chancellor := state.get_character(state.house.holder_of("chancellor"))
	if chancellor == null:
		return 0.0
	return chancellor.get_current("politics") / float(office_def("chancellor").get("effect_divisor", 40.0))


# --- Training -----------------------------------------------------------------------------

static func _age_factor(age: int) -> float:
	var f := 1.0
	for pair: Array in section("training").get("age_factors", []):
		if age >= int(pair[0]):
			f = float(pair[1])
	return f


static func learning(c: CharacterData) -> float:
	var cfg := section("training")
	var l := float(cfg.get("learning_base", 0.6)) + c.get_current("intelligence") * float(cfg.get("learning_per_intelligence", 0.005))
	var mods: Dictionary = cfg.get("traits", {})
	for t in c.traits:
		l *= float(mods.get(t, 1.0))
	return l


## The best mentor for an attribute: an office holder whose office mentors it
## and who is better at it than the student. Returns {"mentor", "bonus"}.
static func mentor_for(state: WorldState, c: CharacterData, attr_id: String) -> Dictionary:
	var cfg := section("training")
	var best: CharacterData = null
	var bonus := 1.0
	for o: Dictionary in offices():
		if not (o.get("mentors", []) as Array).has(attr_id):
			continue
		var m := state.get_character(state.house.holder_of(str(o["id"])))
		if m == null or m == c:
			continue
		var b := clampf(1.0 + (m.get_current(attr_id) - c.get_current(attr_id)) / float(cfg.get("mentor_divisor", 150.0)), 1.0, float(cfg.get("mentor_cap", 1.6)))
		if b > bonus:
			bonus = b
			best = m
	return {"mentor": best, "bonus": bonus}


## The house's own children (kin, not the heir) are taught by tutors at the
## manor in their focus, for a fee (court.json "tutors").
static func is_tutored(state: WorldState, c: CharacterData) -> bool:
	var t := section("tutors")
	return is_kin(state, c) and not state.is_player(c) and not c.retainer and not c.is_away() \
		and c.age >= int(t.get("min_age", 6)) and c.age <= int(t.get("max_age", 17))


static func tutored(state: WorldState) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c in state.characters:
		if is_tutored(state, c):
			out.append(c)
	return out


## Points per day each attribute gains, already scaled by how far from their
## potential they are. Retainers, the player and the house's tutored
## children train.
static func training_rates(state: WorldState, c: CharacterData) -> Dictionary:
	var cfg := section("training")
	var raw := {}
	var focus := focus_of(c)
	if state.is_player(c):
		raw[focus] = float(section("player").get("self_training_rate", 0.7))
	elif is_tutored(state, c):
		raw[focus] = float(section("tutors").get("rate", 1.0))
	elif c.retainer:
		raw[focus] = float(cfg.get("focus_rate", 1.2))
		if not c.office.is_empty():
			var o := office_def(c.office)
			var prim := str(o.get("primary", ""))
			var sec := str(o.get("secondary", ""))
			raw[prim] = float(raw.get(prim, 0.0)) + float(cfg.get("office_primary_rate", 1.1))
			raw[sec] = float(raw.get(sec, 0.0)) + float(cfg.get("office_secondary_rate", 0.5))
	else:
		return {}
	var out := {}
	var common := learning(c) * _age_factor(c.age)
	for a: String in raw:
		var pot := c.get_potential(a)
		if pot <= 0:
			continue
		var gap := float(pot - c.get_current(a)) / float(pot)
		out[a] = float(raw[a]) * gap * common * float(mentor_for(state, c, a)["bonus"])
	return out


## One day of training. Returns events like rank-ups for notifications.
static func train_day(state: WorldState, c: CharacterData) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var rates := training_rates(state, c)
	var renown_cfg: Dictionary = section("renown")
	for a: String in rates:
		var progress := float(c.training_progress.get(a, 0.0)) + float(rates[a])
		var whole := floori(progress)
		if whole <= 0:
			c.training_progress[a] = progress
			continue
		var before := c.get_current(a)
		var gained := c.train(a, whole)
		c.training_progress[a] = progress - whole if c.get_current(a) < c.get_potential(a) else 0.0
		if gained <= 0:
			continue
		var after := c.get_current(a)
		var r_before := Appraisal.rank_index(before)
		var r_after := Appraisal.rank_index(after)
		var who := "Your" if state.is_player(c) else "%s's" % c.first_name
		if r_after > r_before:
			var rank := Appraisal.rank_id(after)
			var reward := int(renown_cfg.get("rank_up", {}).get(rank, 0))
			state.house.renown += reward
			var text := "%s %s rose to %s (%d)." % [who, attr_name(a), rank, after]
			if reward > 0:
				text += " +%d renown" % reward
			events.append({"text": text, "kind": "rank", "character": c.id})
			state.house.log_event(state.day(), text, "rank")
			if r_after >= Appraisal.rank_index(65):
				c.add_history(state.current_year(), state.current_season(), "achievement", "%s reached %s rank" % [attr_name(a), rank])
		if after >= c.get_potential(a) and before < c.get_potential(a):
			var reward := int(renown_cfg.get("full_potential", 4))
			state.house.renown += reward
			var text := "%s %s reached full potential (%d)!" % [who, attr_name(a), after]
			events.append({"text": text, "kind": "potential", "character": c.id})
			state.house.log_event(state.day(), text, "rank")
	return events


# --- Loyalty ------------------------------------------------------------------------------

## Extra loyalty reasons for the player's court (MoodSystem adds them).
static func loyalty_factors(state: WorldState, c: CharacterData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or state.house == null or state.is_player(c):
		return out
	var cfg := section("loyalty")
	if not c.retainer:
		var op := c.player_opinion * 0.1
		if absf(op) >= 1.0:
			out.append({"label": "Opinion of the heir", "value": op})
		return out
	out.append({"label": "Sworn to your house", "value": float(cfg.get("sworn", 15))})
	var op2 := c.player_opinion * float(cfg.get("opinion_factor", 0.2))
	if absf(op2) >= 1.0:
		out.append({"label": "Opinion of you", "value": op2})
	if state.house.in_debt:
		out.append({"label": "Wages unpaid", "value": float(cfg.get("unpaid", -15))})
	if not c.office.is_empty():
		out.append({"label": "Holds the office of %s" % office_name(c.office), "value": float(cfg.get("holds_post", 6))})
	elif c.age >= 16 and c.get_current("ambition") >= 50:
		out.append({"label": "Wants a post", "value": float(cfg.get("wants_post", -6))})
	out.append({"label": "Their gifts are nurtured", "value": float(cfg.get("nurtured", 4))})
	if c.office.is_empty():
		for r in c.relationships_of_type(["rival"]):
			var rival := state.get_character(int(r["target"]))
			if rival and not rival.office.is_empty():
				out.append({"label": "Rival %s holds an office" % rival.first_name, "value": float(cfg.get("rival_outranks", -5))})
				break
	if c.is_knight():
		out.append({"label": "Knighted", "value": float(cfg.get("knighted", 10))})
	return out


# --- Daily ------------------------------------------------------------------------------

## Runs once per in-game day after moods update. Returns notification events:
## [{ "text", "kind", "character"? }]
static func daily_update(state: WorldState, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.house == null:
		return events
	var h := state.house
	var day := state.day()
	var income := daily_income(state)
	h.gold += income - Succession.regent_skim(state, income)
	var wages := daily_wages(state)
	var w_cfg := section("wages")
	var paid := not (wages > 0 and h.gold < wages)
	if not paid:
		if not h.in_debt:
			events.append({"text": "Your coffers are empty: your retainers' wages went unpaid!", "kind": "bad"})
			h.log_event(day, "Wages went unpaid.", "bad")
		h.in_debt = true
		for c in state.retainers():
			c.player_opinion = clampf(c.player_opinion + float(w_cfg.get("unpaid_opinion", -2)), -100.0, 100.0)
			c.loyalty = clampf(c.loyalty + float(w_cfg.get("unpaid_loyalty", -4)), 0.0, 100.0)
	else:
		h.gold -= wages
		if h.in_debt:
			events.append({"text": "Wages are paid again.", "kind": "good"})
		h.in_debt = false
	h.renown_progress += daily_renown(state)
	if h.renown_progress >= 1.0:
		var whole := floori(h.renown_progress)
		h.renown += whole
		h.renown_progress -= whole
	events.append_array(Recruitment.daily_update(state, paid))
	var player := state.player()
	if player:
		events.append_array(train_day(state, player))
	for child in tutored(state):
		events.append_array(train_day(state, child))
	var l_cfg := section("loyalty")
	for c in state.retainers():
		events.append_array(train_day(state, c))
		if c.loyalty < float(l_cfg.get("leave_below", 18)) and rng.randf() < float(l_cfg.get("leave_chance", 0.12)):
			dismiss(state, c, true)
			events.append({"text": "%s has left your service (loyalty %d)." % [c.full_name(), roundi(c.loyalty)], "kind": "bad", "character": c.id})
		elif c.loyalty < float(l_cfg.get("warning_below", 30)) and day % 3 == 0:
			events.append({"text": "%s's loyalty is wavering (%d). Talk to them, raise their station or pay them." % [c.first_name, roundi(c.loyalty)], "kind": "bad", "character": c.id})
	return events
