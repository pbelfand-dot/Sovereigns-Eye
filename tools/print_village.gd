extends SceneTree
## Prints a census of a generated village. Handy for tuning data/*.json.
##
##   godot --headless --path . --script res://tools/print_village.gd -- 12345


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "12345"
	var w := WorldGenerator.generate(seed_text)
	print("Village of %s (seed %s) - %d people, %d buildings, %d trees, %d fields" % [
		w.village_name, seed_text, w.characters.size(), w.layout.buildings.size(), w.layout.trees.size(), w.layout.fields.size()])
	for b in w.layout.buildings:
		print("  [%2d] %-28s %-10s at (%.0f, %.0f)  residents %d" % [b.id, b.name, b.type, b.position.x, b.position.z, w.residents_of(b.id).size()])
	print("")
	var rank_counts := {}
	for c in w.characters:
		var best := c.best_attribute()
		var line := "%-22s %3d %-6s %-20s %-9s best %-14s %3d/%3d %-3s  H%2d L%2d  %s" % [
			c.full_name(), c.age, c.gender, c.occupation_name(), c.status_name(), best,
			c.get_current(best), c.get_potential(best), Appraisal.rank_id(c.get_potential(best)),
			int(c.happiness), int(c.loyalty), ", ".join(c.traits)]
		print(("* " if Appraisal.is_exceptional(c) else "  ") + line)
		for attr_id in GameData.attribute_ids():
			var r := Appraisal.rank_id(c.get_potential(attr_id))
			rank_counts[r] = int(rank_counts.get(r, 0)) + 1
	print("")
	print("Potential ranks across all attributes: %s" % str(rank_counts))
	quit()
