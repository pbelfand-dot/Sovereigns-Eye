class_name Seeds
extends RefCounted
## Deterministic seeding helpers.
##
## A world has one master seed. Each generation step (layout, characters,
## relationships...) gets its own RNG derived from that seed plus a stream
## name, so adding randomness to one system never shifts the results of
## another. Never use the global randf()/randi() in generation code.

## Largest seed we hand out. Kept below 2^31 so it survives JSON (which stores
## numbers as doubles) without precision loss.
const MAX_SEED := 0x7FFFFFFF


## Turns whatever the player typed ("1234", "Ashford", "") into a seed.
static func from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return 0
	if t.is_valid_int():
		return absi(t.to_int()) % MAX_SEED
	return t.hash() & MAX_SEED


static func random_seed_text() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return str(rng.randi_range(100000, 999999))


static func derive(world_seed: int, stream: String) -> int:
	return ("%d:%s" % [world_seed, stream]).hash() & MAX_SEED


static func rng(world_seed: int, stream: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = derive(world_seed, stream)
	return r


## For streams named by a running count ("cart_1", "cart_2"...) whose first
## draw decides something: neighbouring seeds start the generator on
## neighbouring states and their first draws run together, so the seed is
## mixed first.
static func counted_rng(world_seed: int, stream: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(derive(world_seed, stream)) & MAX_SEED
	return r


# --- Small deterministic pick helpers (never touch the global RNG) ---------

static func pick(r: RandomNumberGenerator, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[r.randi_range(0, items.size() - 1)]


static func chance(r: RandomNumberGenerator, probability: float) -> bool:
	return r.randf() < probability


## Fisher-Yates shuffle using the given RNG (Array.shuffle() uses the global one).
static func shuffle(r: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


## Picks a key from {key: weight}. Returns "" if all weights are zero.
static func weighted_key(r: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return ""
	var roll := r.randf() * total
	for k: String in weights:
		roll -= maxf(0.0, float(weights[k]))
		if roll <= 0.0:
			return k
	return weights.keys()[-1]
