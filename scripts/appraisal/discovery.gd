class_name Discovery
extends RefCounted
## How the player finds talent (Phase 2.5, "the Sovereign's Eye").
##
## Nobody's gifts are visible at first. The heir walks over and talks to a
## villager; the talk is ordinary conversation that may hint at a gift
## (data/dialogue.json). After that first meeting the heir may use the
## Sovereign's Eye on them, which plays a reveal scaled to their real talent
## (EyeReveal, data/eye.json) and marks them appraised.
##
## Static and deterministic, like the other rule systems.


static func eye_config() -> Dictionary:
	return GameData.load_file("eye")


static func dialogue() -> Dictionary:
	return GameData.load_file("dialogue")


## The reveal tier a person's greatest potential earns (Ordinary ... Legendary).
static func tier_for(c: CharacterData) -> Dictionary:
	var best := c.best_potential()
	var tier: Dictionary = {}
	for t: Dictionary in eye_config().get("tiers", []):
		if best >= int(t.get("min", 0)):
			tier = t
	return tier


static func tier_id(c: CharacterData) -> String:
	return str(tier_for(c).get("id", "ordinary"))


## The tier definition by id ({} if unknown).
static func tier_by_id(id: String) -> Dictionary:
	for t: Dictionary in eye_config().get("tiers", []):
		if str(t["id"]) == id:
			return t
	return {}


## Can the heir look at them with the Eye yet? (Only after speaking with them.)
static func can_use_eye(state: WorldState, c: CharacterData) -> Dictionary:
	if state.is_player(c):
		return {"ok": false, "reason": "You already know yourself."}
	if not c.met:
		return {"ok": false, "reason": "Speak with them first."}
	return {"ok": true, "reason": ""}


## Their three greatest gifts, strongest first: [{id, name, current, potential, rank}].
static func top_abilities(c: CharacterData, count: int = 3) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for attr_id: String in GameData.attribute_ids():
		var p := c.get_potential(attr_id)
		rows.append({"id": attr_id, "name": str(GameData.attribute_def(attr_id).get("name", attr_id.capitalize())),
			"current": c.get_current(attr_id), "potential": p, "rank": Appraisal.rank_id(p)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["potential"]) > int(b["potential"]) if a["potential"] != b["potential"] else str(a["id"]) < str(b["id"]))
	return rows.slice(0, count)


## Overall promise: the mean of their three greatest potentials.
static func overall_potential(c: CharacterData) -> int:
	var total := 0
	var rows := top_abilities(c)
	for r in rows:
		total += int(r["potential"])
	return roundi(float(total) / maxf(rows.size(), 1.0))


# --- Conversation ------------------------------------------------------------------------

static func _address(state: WorldState) -> String:
	var p := state.player()
	return "my lady" if p and p.gender == "female" else "my lord"


static func _fill(text: String, state: WorldState) -> String:
	var lord := _address(state)
	var p := state.player()
	var title := "lady" if p and p.gender == "female" else "lord"
	text = text.replace("{lord}", lord).replace("{title}", title)
	return text.substr(0, 1).to_upper() + text.substr(1) if text.begins_with(lord) else text


## The topic a person steers the talk toward: weighted by their potentials
## (a great gift comes up often, but not always).
static func pick_topic(c: CharacterData, rng: RandomNumberGenerator) -> String:
	var power := float(dialogue().get("topic_weight_power", 3.0))
	var weights := {}
	for attr_id: String in GameData.attribute_ids():
		weights[attr_id] = pow(maxf(c.get_potential(attr_id), 5.0) / 40.0, power)
	return Seeds.weighted_key(rng, weights)


## 0 mild, 1 keen, 2 striking: how impressive their talk on a topic sounds.
static func intensity(c: CharacterData, attr_id: String, rng: RandomNumberGenerator) -> int:
	var cfg: Dictionary = dialogue().get("intensity", {})
	var noise := float(cfg.get("noise", 22))
	var score := c.get_potential(attr_id) + rng.randf_range(-noise, noise)
	var bias: Dictionary = cfg.get("traits", {})
	for t in c.traits:
		score += float(bias.get(t, 0.0))
	if score >= float(cfg.get("striking", 104)):
		return 2
	if score >= float(cfg.get("keen", 68)):
		return 1
	return 0


## What they say when the heir comes to talk: [String] (speech in quotes,
## gestures in brackets). The first meeting gets a greeting, a topic and a
## glimpse of personality; later talks are shorter.
static func conversation(state: WorldState, c: CharacterData) -> Array[String]:
	var d := dialogue()
	var rng := Seeds.rng(state.world_seed, "talk_%d_%d" % [c.id, state.day()])
	var lines: Array[String] = []
	if c.met:
		var again: Array = d.get("again", ["\"Back again?\""])
		lines.append(_fill(str(Seeds.pick(rng, again)), state))
	else:
		var key := c.social_status
		if c.age < 13:
			key = "child"
		elif c.age >= 62 and c.occupation_id == "elder":
			key = "elder"
		var greet: Array = d.get("greetings", {}).get(key, d.get("greetings", {}).get("commoner", ["Good day."]))
		lines.append("\"%s\"" % _fill(str(Seeds.pick(rng, greet)), state))
	var topic := pick_topic(c, rng)
	var level := intensity(c, topic, rng)
	var options: Array = d.get("topics", {}).get(topic, [[""], [""], [""]])[level]
	lines.append("\"%s\"" % _fill(str(Seeds.pick(rng, options)), state))
	var flavors: Array[String] = []
	for t in c.traits:
		if d.get("traits", {}).has(t):
			flavors.append(str(d["traits"][t]))
	if not flavors.is_empty() and (not c.met or rng.randf() < 0.4):
		lines.append(_fill(flavors[rng.randi_range(0, flavors.size() - 1)], state))
	if c.happiness < 35.0:
		lines.append(_fill(str(d.get("moods", {}).get("low", "")), state))
	elif c.happiness > 78.0 and rng.randf() < 0.5:
		lines.append(_fill(str(d.get("moods", {}).get("high", "")), state))
	return lines


## The heir has spoken with them: they're met (the Eye may be used), and the
## talk counts toward their opinion once a day.
static func meet(state: WorldState, c: CharacterData) -> Dictionary:
	var lines := conversation(state, c)
	var first := not c.met
	c.met = true
	var opinion_text := ""
	if state.house and CourtSystem.can_talk(state, c)["ok"]:
		opinion_text = str(CourtSystem.talk(state, c, Seeds.rng(state.world_seed, "court_talk_%d_%d" % [c.id, state.day()])).get("text", ""))
	return {"lines": lines, "first": first, "opinion": opinion_text}
