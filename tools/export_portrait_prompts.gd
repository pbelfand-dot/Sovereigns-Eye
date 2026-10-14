extends SceneTree
## Writes an AI prompt for every villager of a seed to a JSON file, ready for
## batch generation in any image AI (FLUX.2 klein / Draw Things / ComfyUI /
## Higgsfield). Put each finished image at the "output" path it lists and the
## game shows it on that villager's card.
##
##   godot --headless --path . --script res://tools/export_portrait_prompts.gd -- <seed> <out.json>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "12345"
	var out := args[1] if args.size() > 1 else "portrait_prompts.json"
	var w := WorldGenerator.generate(seed_text)
	var list: Array = []
	for c in w.characters:
		list.append(PortraitPrompt.build(c, w.world_seed))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed_text": seed_text, "world_seed": w.world_seed, "village": w.village_name, "portraits": list}, "  "))
	f.close()
	print("Wrote %d portrait prompts for %s to %s" % [list.size(), w.village_name, out])
	quit()
