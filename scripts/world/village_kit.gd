class_name VillageKit
extends RefCounted
## Builds buildings out of the Quaternius Medieval Village MegaKit.
##
## Recipes live in data/building_kit.json: each building type is made of
## blocks on a 2 m grid (walls, corners, windows, doors, roof, chimney...).
## A recipe is assembled once into a prefab, which is reused by every building
## of that type and variant:
##   - "shell":   walls, roofs and windows merged into ONE mesh with one surface
##                per shared material (a handful of draw calls per building
##                instead of hundreds of loose pieces);
##   - "details": shutters, vines, doors' dressing and props, hidden beyond
##                `detail_range` so far-away buildings stay cheap;
##   - "boxes":   simple box collision proxies.
## Every module that uses e.g. "MI_Plaster" ends up with the same Material
## object, so all buildings share the kit's textures.
##
## If the kit isn't in the project (or a module is missing), callers fall back
## to the primitive placeholder in BuildingFactory.

const DATA_FILE := "building_kit"

static var _available := -1
static var _modules: Dictionary = {}    # module name -> Mesh (null when missing)
static var _materials: Dictionary = {}  # material name -> Material
static var _prefabs: Dictionary = {}    # "type_variant" -> Dictionary
static var _missing_logged: Dictionary = {}


static func config() -> Dictionary:
	return GameData.load_file(DATA_FILE)


static func kit_path() -> String:
	return str(config().get("kit_path", ""))


static func available() -> bool:
	if _available < 0:
		_available = 1 if ResourceLoader.exists(kit_path() + "Wall_Plaster_Straight.gltf") else 0
		if _available == 0:
			push_warning("VillageKit: Quaternius village kit not found at %s; using placeholder buildings." % kit_path())
	return _available == 1


static func has_prefab(type: String) -> bool:
	return available() and config().get("prefabs", {}).has(type)


## A home's recipe at a higher level (data/building_kit.json "home_tiers"):
## the door block gains stories on top of the same ground floor, so an
## upgrade only adds floors. Tier 0 returns the recipe unchanged.
static func tier_recipe(base: Dictionary, tier: int) -> Dictionary:
	var tiers: Array = config().get("home_tiers", [])
	if tier <= 0 or tiers.is_empty():
		return base
	var t: Dictionary = tiers[mini(tier, tiers.size() - 1)]
	var r := base.duplicate(true)
	for block: Dictionary in r.get("blocks", []):
		if not bool(block.get("door", false)):
			continue
		block["ground"] = str(block.get("ground", block.get("walls", "plaster")))
		block["walls"] = str(t.get("upper_walls", block.get("walls", "plaster")))
		block["stories"] = mini(int(block.get("stories", 1)) + int(t.get("add_stories", 1)), int(t.get("max_stories", 3)))
	if t.has("balcony"):
		r["balcony"] = bool(t["balcony"])
	r["vines"] = int(r.get("vines", 0)) + int(t.get("add_vines", 0))
	return r


## Variant recipes for a building type.
static func variants(type: String) -> Array:
	return config().get("prefabs", {}).get(type, {}).get("variants", [])


## Width/depth (meters) covered by a recipe's blocks. The layout uses the
## footprint in buildings.json; tests check the two agree.
static func recipe_bounds(recipe: Dictionary) -> Rect2:
	var cell := float(config().get("cell", 2.0))
	var r := Rect2()
	var first := true
	for block: Dictionary in recipe.get("blocks", []):
		var cells: Array = block["cells"]
		var at: Array = block.get("at", [0, 0])
		var size := Vector2(float(cells[0]), float(cells[1])) * cell
		var br := Rect2(Vector2(float(at[0]), float(at[1])) - size * 0.5, size)
		r = br if first else r.merge(br)
		first = false
	return r


static func missing_note(type: String) -> String:
	return str(config().get("missing", {}).get(type, ""))


## Mesh of one kit module (e.g. "Wall_Plaster_Straight"), cached.
static func module_mesh(module: String) -> Mesh:
	if _modules.has(module):
		return _modules[module]
	var mesh: Mesh = null
	var path := kit_path() + module + ".gltf"
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var inst := scene.instantiate() if scene else null
		if inst:
			var mi := inst.find_children("*", "MeshInstance3D", true, false)
			if not mi.is_empty():
				mesh = (mi[0] as MeshInstance3D).mesh
			inst.free()
	if mesh == null and not _missing_logged.has(module):
		_missing_logged[module] = true
		push_warning("VillageKit: module %s is missing" % module)
	_modules[module] = mesh
	return mesh


## One Material object per kit material name, shared by every building.
static func shared_material(mat: Material) -> Material:
	if mat == null:
		return null
	var key := mat.resource_name
	if key.is_empty():
		return mat
	if not _materials.has(key):
		_materials[key] = mat
	return _materials[key]


## A shared kit material by name (e.g. "MI_WoodTrim"), once any module using it
## has been loaded. Used for the few non-kit shapes (windmill sails).
static func material_named(key: String) -> Material:
	return _materials.get(key, null)


## Height of the walls (stories of the door block) for a type, variant and tier.
static func wall_height(type: String, variant: int, tier: int = 0) -> float:
	var list := variants(type)
	if list.is_empty():
		return 0.0
	var top := 0
	for block: Dictionary in tier_recipe(list[posmod(variant, list.size())], tier).get("blocks", []):
		if bool(block.get("door", false)):
			top = int(block.get("stories", 1))
	return top * float(config().get("story_height", 3.0))


## Assembled prefab for a building type, variant number and home tier.
## Returns {} if the type has no recipe.
static func prefab(type: String, variant: int, tier: int = 0) -> Dictionary:
	var list := variants(type)
	if list.is_empty():
		return {}
	var vi := posmod(variant, list.size())
	var base_key := "%s_%d" % [type, vi]
	var key := base_key if tier <= 0 else "%s_t%d" % [base_key, tier]
	if _prefabs.has(key):
		return _prefabs[key]
	var recipe := tier_recipe(list[vi], tier)
	# Every tier rolls from the base key, so walls, windows and doors of the
	# floors they share come out the same. Vines roll separately because
	# they only grow on the top floor.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base_key)
	var vine_rng := RandomNumberGenerator.new()
	vine_rng.seed = hash(base_key + "/vines")
	var shell := _Assembler.new()
	var details := _Assembler.new()
	var boxes: Array[AABB] = []
	var top := 0.0
	for block: Dictionary in recipe.get("blocks", []):
		top = maxf(top, _build_block(block, recipe, rng, vine_rng, shell, details, boxes))
	_add_props(recipe, rng, details)
	var out := {
		"key": key,
		"shell": shell.commit(),
		"details": details.commit(),
		"boxes": boxes,
		"sails": bool(recipe.get("sails", false)),
		"height": top,
		"pieces": shell.count + details.count,
		"parts": shell.parts,
		"detail_parts": details.parts,
	}
	_prefabs[key] = out
	return out


## Paving for roads and the square from the kit's own stone textures, mapped
## in world space (no UVs needed). Returns null if the kit is missing.
## kind: "square" (brick paving) or "road" (uneven cobbles).
static func ground_material(kind: String) -> Material:
	var key := "_ground_" + kind
	if _materials.has(key):
		return _materials[key]
	if not available():
		return null
	var base := "T_Brick" if kind == "square" else "T_UnevenBrick"
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_texture = load(kit_path() + base + "_BaseColor.png")
	m.normal_enabled = true
	m.normal_texture = load(kit_path() + base + "_Normal.png")
	m.roughness_texture = load(kit_path() + base + "_Roughness.png")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.albedo_color = Color("#d9cbb4") if kind == "square" else Color("#c4b298")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * (0.5 if kind == "square" else 0.4)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = m
	return m


## Warm light in every kit window at night (amount 0..1).
static func set_night_glow(amount: float) -> void:
	var glass := _materials.get("MI_WindowGlass", null) as StandardMaterial3D
	if glass == null:
		return
	glass.emission_enabled = amount > 0.01
	glass.emission = Color("#ffb45a")
	glass.emission_energy_multiplier = amount * 1.8


## Drops cached prefabs (e.g. after editing building_kit.json).
static func clear_cache() -> void:
	_prefabs.clear()


## Merges a list of [module, Transform3D] parts into one mesh (one surface
## per shared material), e.g. the walls raised so far on a building site.
static func assemble(parts: Array) -> ArrayMesh:
	var a := _Assembler.new()
	for p: Array in parts:
		a.add(str(p[0]), p[1])
	return a.commit()


# --- Assembly -------------------------------------------------------------------

class _Assembler:
	var tools: Dictionary = {}  # material key -> SurfaceTool
	var mats: Dictionary = {}
	var count := 0
	## [[module, Transform3D], ...] in the order added (construction sites
	## re-assemble a subset of these to raise a building piece by piece).
	var parts: Array = []

	func add(module: String, xf: Transform3D) -> void:
		var mesh := VillageKit.module_mesh(module)
		if mesh == null:
			return
		count += 1
		parts.append([module, xf])
		for s in mesh.get_surface_count():
			var mat := VillageKit.shared_material(mesh.surface_get_material(s))
			var key := mat.resource_name if mat else "_none"
			if not tools.has(key):
				var st := SurfaceTool.new()
				tools[key] = st
				mats[key] = mat
			(tools[key] as SurfaceTool).append_from(mesh, s, xf)

	func commit() -> ArrayMesh:
		var am := ArrayMesh.new()
		for key: String in tools:
			(tools[key] as SurfaceTool).commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mats[key])
		return am


const WALLS := {
	"plaster": {
		"plain_ground": ["Wall_Plaster_Straight_Base"],
		"plain": ["Wall_Plaster_Straight", "Wall_Plaster_WoodGrid", "Wall_Plaster_Straight"],
		"door": ["Wall_Plaster_Door_Round", "Wall_Plaster_Door_Flat"],
		"window": ["Wall_Plaster_Window_Wide_Round", "Wall_Plaster_Window_Thin_Round", "Wall_Plaster_Window_Wide_Flat"],
		"corner": "Corner_Exterior_Wood",
	},
	"brick": {
		"plain_ground": ["Wall_UnevenBrick_Straight"],
		"plain": ["Wall_UnevenBrick_Straight"],
		"door": ["Wall_UnevenBrick_Door_Round", "Wall_UnevenBrick_Door_Flat"],
		"window": ["Wall_UnevenBrick_Window_Wide_Round", "Wall_UnevenBrick_Window_Thin_Round", "Wall_UnevenBrick_Window_Wide_Flat"],
		"corner": "Corner_Exterior_Brick",
	},
}

## Window frame + shutter modules that fit each window wall.
const WINDOW_FIT := {
	"Wide_Round": ["Window_Wide_Round1", "WindowShutters_Wide_Round_"],
	"Thin_Round": ["Window_Thin_Round1", "WindowShutters_Thin_Round_"],
	"Wide_Flat": ["Window_Wide_Flat1", "WindowShutters_Wide_Flat_"],
}


## Builds one block; returns its top height (meters).
static func _build_block(block: Dictionary, recipe: Dictionary, rng: RandomNumberGenerator, vine_rng: RandomNumberGenerator, shell: _Assembler, details: _Assembler, boxes: Array[AABB]) -> float:
	var cell := float(config().get("cell", 2.0))
	var sh := float(config().get("story_height", 3.0))
	var cells: Array = block["cells"]
	var cx := int(cells[0])
	var cz := int(cells[1])
	var at: Array = block.get("at", [0, 0])
	var origin := Vector3(float(at[0]), 0.0, float(at[1]))
	var w := cx * cell
	var d := cz * cell
	var stories := int(block.get("stories", 1))
	var upper_set := str(block.get("walls", "plaster"))
	var ground_set := str(block.get("ground", upper_set))
	var tall_windows := str(block.get("windows", "")) == "tall"
	var wall_h := stories * sh

	# Ground floor so windows don't look into the void.
	for ix in cx:
		for iz in cz:
			shell.add("Floor_WoodDark", Transform3D(Basis(), origin + Vector3(-w * 0.5 + cell * (ix + 0.5), 0.02, -d * 0.5 + cell * (iz + 0.5))))

	# Edges: outward normal, number of 2 m segments, half-depth to the edge.
	var edges := [
		{"n": Vector3(0, 0, 1), "count": cx, "depth": d * 0.5, "front": true},
		{"n": Vector3(0, 0, -1), "count": cx, "depth": d * 0.5},
		{"n": Vector3(1, 0, 0), "count": cz, "depth": w * 0.5},
		{"n": Vector3(-1, 0, 0), "count": cz, "depth": w * 0.5},
	]
	var vine_budget := int(recipe.get("vines", 0))
	for s in stories:
		var y := s * sh
		var set_def: Dictionary = WALLS.get(ground_set if s == 0 else upper_set, WALLS["plaster"])
		for e: Dictionary in edges:
			var n: Vector3 = e["n"]
			var count := int(e["count"])
			var basis := Basis(Vector3.UP, atan2(n.x, n.z))
			var door_i := -1
			if e.get("front", false) and s == 0 and bool(block.get("door", false)):
				door_i = (count - 1) / 2
			for i in count:
				var along := -count * cell * 0.5 + cell * (i + 0.5)
				var pos := origin + n * float(e["depth"]) + basis * Vector3(along, 0, 0) + Vector3(0, y, 0)
				var xf := Transform3D(basis, pos)
				if i == door_i:
					var door_wall: String = _pick(set_def["door"], rng)
					shell.add(door_wall, xf)
					var round := door_wall.ends_with("Round")
					shell.add("Door_%d_%s" % [[1, 2, 4, 8][rng.randi() % 4], "Round" if round else "Flat"], xf * Transform3D(Basis(), Vector3(-0.53, 0, 0)))
					continue
				var window_chance := 0.75 if (e.get("front", false) or count > 2) else 0.55
				if tall_windows or rng.randf() < window_chance:
					var wall: String = set_def["window"][1] if tall_windows else _pick(set_def["window"], rng)
					shell.add(wall, xf)
					for fit: String in WINDOW_FIT:
						if wall.ends_with(fit):
							var parts: Array = WINDOW_FIT[fit]
							shell.add(parts[0], xf)
							if not tall_windows and rng.randf() < 0.7:
								details.add(str(parts[1]) + ("Open" if rng.randf() < 0.6 else "Closed"), xf)
				else:
					var plain: Array = set_def["plain_ground"] if s == 0 else set_def["plain"]
					shell.add(_pick(plain, rng), xf)
					if vine_budget > 0 and s == stories - 1 and vine_rng.randf() < 0.5:
						vine_budget -= 1
						details.add(["Prop_Vine1", "Prop_Vine2", "Prop_Vine4"][vine_rng.randi() % 3], xf * Transform3D(Basis(), Vector3(0, sh - 0.25, 0.14)))
		# Corner posts / quoins.
		var corner: String = set_def["corner"]
		for k in 4:
			var sx := -1.0 if k == 0 or k == 3 else 1.0
			var sz := 1.0 if k < 2 else -1.0
			shell.add(corner, Transform3D(Basis(Vector3.UP, k * PI * 0.5), origin + Vector3(sx * w * 0.5, y, sz * d * 0.5)))

	# Balcony on the front of the second story.
	if bool(recipe.get("balcony", false)) and bool(block.get("door", false)) and stories >= 2:
		var bx := origin + Vector3(0, sh, d * 0.5)
		shell.add("Floor_WoodDark", Transform3D(Basis(), bx))
		shell.add("Balcony_Cross_Straight", Transform3D(Basis(), bx))

	var top := wall_h
	match str(block.get("roof", "tiles")):
		"tiles":
			top = _add_tiled_roof(origin, w, d, wall_h, str(block.get("ridge", "x")), recipe, shell)
		"tower":
			shell.add("Roof_Tower_RoundTiles", Transform3D(Basis(), origin + Vector3(0, wall_h, 0)))
			top = wall_h + 6.8
	boxes.append(AABB(origin + Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w, wall_h + (top - wall_h) * 0.5, d)))
	return top


## Tiled gable roof with brick/plaster gable ends. Returns the ridge height.
static func _add_tiled_roof(origin: Vector3, w: float, d: float, base: float, ridge: String, recipe: Dictionary, shell: _Assembler) -> float:
	var along_x := ridge == "x"
	var span := int(round(d if along_x else w))   # gable width
	var length := int(round(w if along_x else d))
	var roof_name := "Roof_RoundTiles_%dx%d" % [span, length]
	var basis := Basis(Vector3.UP, PI * 0.5 if along_x else 0.0)
	shell.add(roof_name, Transform3D(basis, origin + Vector3(0, base, 0)))
	var roof_mesh := module_mesh(roof_name)
	var rise := roof_mesh.get_aabb().end.y if roof_mesh else span * 0.6
	# Gable ends: outward along the ridge axis.
	var gable := "Roof_Front_Brick%d" % span
	for sgn: float in [1.0, -1.0]:
		var n := Vector3(sgn, 0, 0) if along_x else Vector3(0, 0, sgn)
		var gb := Basis(Vector3.UP, atan2(n.x, n.z))
		shell.add(gable, Transform3D(gb, origin + n * (length * 0.5) + Vector3(0, base, 0)))
	# Chimney poking out near one gable end.
	var chimney: Variant = recipe.get("chimney", false)
	if chimney is String or bool(chimney):
		var c_name := "Prop_Chimney2" if str(chimney) == "forge" else "Prop_Chimney"
		var off := (length * 0.5 - 1.5)
		var p := origin + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, -off)) + Vector3(0, base + rise - 2.3, 0)
		shell.add(c_name, Transform3D(Basis(), p))
	return base + rise


static func _add_props(recipe: Dictionary, rng: RandomNumberGenerator, details: _Assembler) -> void:
	var props: Array = recipe.get("props", [])
	if props.is_empty():
		return
	var bounds := recipe_bounds(recipe)
	var right := bounds.end.x
	var left := bounds.position.x
	var crates := 0
	for p: String in props:
		match p:
			"wagon":
				details.add("Prop_Wagon", Transform3D(Basis(Vector3.UP, PI), Vector3(left - 1.3, 0, bounds.position.y + 3.2)))
			"crate":
				var x := right + 0.7 + (crates / 2) * 1.15
				var z := bounds.end.y - 1.0 - (crates % 2) * 1.15
				details.add("Prop_Crate", Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(x, 0, z)))
				crates += 1


static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return str(list[rng.randi() % list.size()])
