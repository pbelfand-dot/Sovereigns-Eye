extends SceneTree
## Prints what everyone in a village wants and how they'd answer a few
## standard offers. For tuning data/recruitment.json.
##   godot --headless --path . --script res://tools/recruit_report.gd -- <seed>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if not args.is_empty() else "12345"
	var state := WorldGenerator.generate(seed_text)
	TerritorySystem.initialize(state)
	var offers := {
		"wage2": {"wage": 2},
		"wage4": {"wage": 4},
		"w2+home": {"wage": 2, "home": Recruitment.PROMISE_HOME},
		"w2+train": {"wage": 2, "position": "training", "focus": "combat"},
		"appeal": {"wage": 0, "appeal": true},
	}
	var accepted := {}
	var n := 0
	for c in state.characters:
		if not Recruitment.eligible(state, c)["ok"] or c.age < 16:
			continue
		n += 1
		var m := Recruitment.motives(state, c)
		var parts: Array[String] = []
		for id: String in Recruitment.SPEAKING_MOTIVES:
			parts.append("%s %.2f" % [id.left(4), float(m[id])])
		var answers: Array[String] = []
		for key: String in offers:
			var ev := Recruitment.evaluate(state, c, offers[key])
			answers.append("%s %.2f%s" % [key, float(ev["total"]), "*" if ev["accept"] else ""])
			if ev["accept"]:
				accepted[key] = int(accepted.get(key, 0)) + 1
		var best := _cheapest(state, c)
		if not best.is_empty():
			accepted["tailored"] = int(accepted.get("tailored", 0)) + 1
		print("%-22s %-9s %-12s op %+4d %-28s | %s | %s | best: %s" % [c.full_name().left(22), c.social_status, c.occupation_id, roundi(c.player_opinion),
			",".join(c.traits).left(28), "  ".join(parts), "  ".join(answers), Recruitment.describe(state, best) if not best.is_empty() else "-"])
	print("\n%d adults could be asked. Accepting each offer: %s" % [n, accepted])
	quit()


## The cheapest offer they'd accept (wage first, then extras), or {}.
func _cheapest(state: WorldState, c: CharacterData) -> Dictionary:
	var homes: Array = [-1, Recruitment.PROMISE_HOME]
	var empty := Recruitment.available_homes(state)
	if not empty.is_empty():
		homes.append(empty[0].id)
	var positions: Array[Dictionary] = [{"position": "household"}, {"position": "training", "focus": c.best_attribute() if CourtSystem.TRAINABLE.has(c.best_attribute()) else "combat"}]
	var office := Recruitment.vacant_office_for(state, c)
	if not office.is_empty():
		positions.append({"position": "office", "office": office})
	var wp := Recruitment.open_workplaces(state)
	if not wp.is_empty():
		positions.append({"position": "workplace", "workplace": wp[0].id})
	positions.append({"position": "squire"})
	for wage in range(0, 9):
		for appeal: bool in [false, true]:
			for home: int in homes:
				for pos in positions:
					var o := pos.duplicate()
					o["wage"] = wage
					o["home"] = home
					o["appeal"] = appeal
					if Recruitment.offer_problem(state, c, o).is_empty() and Recruitment.evaluate(state, c, o)["accept"]:
						return o
	return {}
