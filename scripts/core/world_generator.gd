class_name WorldGenerator
extends RefCounted
## Creates a brand-new WorldState from a seed. Same seed in, same world out.


static func generate(seed_text: String) -> WorldState:
	var state := WorldState.new()
	state.seed_text = seed_text
	state.world_seed = Seeds.from_text(seed_text)
	state.village_name = village_name(state.world_seed)
	state.minutes = Calendar.start_minutes()
	state.last_daily_update = Calendar.day_index(int(state.minutes))
	state.layout = VillageLayoutGenerator.new().generate(state.world_seed)
	CharacterGenerator.new().generate(state)
	CourtSystem.initialize(state)
	TerritorySystem.initialize(state)
	return state


static func village_name(world_seed: int) -> String:
	var rng := Seeds.rng(world_seed, "village_name")
	var n := GameData.names()
	return "%s%s" % [Seeds.pick(rng, n.get("village_prefixes", ["Ash"])), Seeds.pick(rng, n.get("village_suffixes", ["ford"]))]
