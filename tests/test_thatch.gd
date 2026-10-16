extends TestCase
## Thatch & Repair (3D/buildings/thatch-repair): a Cottage is roofed in
## weathered thatch, its walls patched and its windows hung with plank
## shutters; a Timber House and a farmhouse have neat thatch; a Townhouse
## keeps the kit's tiles.

const DIR := "res://3D/buildings/thatch-repair/models/"
const BUDGETS := {"SE_Thatch_4x6": 3200, "SE_Thatch_6x8": 4000, "SE_Patch_": 300, "SE_Shutters_Plank_": 400}


func _modules(parts: Array) -> Array:
	var out: Array = []
	for p: Array in parts:
		out.append(str(p[0]))
	return out


func _count(parts: Array, needle: String) -> int:
	var n := 0
	for m: String in _modules(parts):
		if m.contains(needle):
			n += 1
	return n


func test_every_thatch_model_loads_within_budget() -> void:
	var seen := 0
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".glb"):
			continue
		seen += 1
		var root := (load(DIR + f) as PackedScene).instantiate()
		var tris := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				check(mat != null and mat.resource_name.begins_with("MI_Thatch"), "%s: a thatch material" % f)
				if mat:
					check(mat.albedo_texture != null, "%s: %s has its texture" % [f, mat.resource_name])
					if mat.resource_name in ["MI_Thatch", "MI_Thatch_Worn"]:
						check(mat.normal_enabled and mat.normal_texture != null, "%s: %s has its relief" % [f, mat.resource_name])
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := 0
		for prefix: String in BUDGETS:
			if f.begins_with(prefix):
				budget = BUDGETS[prefix]
		check(budget > 0 and tris <= budget and tris > 50, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 12, "all twelve thatch & repair models are there")


func test_a_homes_roof_follows_its_level() -> void:
	if not VillageKit.available():
		return
	for v in VillageKit.variants("cottage").size():
		var poor: Array = VillageKit.prefab("cottage", v, 0)["parts"]
		var timber: Array = VillageKit.prefab("cottage", v, 1)["parts"]
		var town: Array = VillageKit.prefab("cottage", v, 2)["parts"]
		check_eq(_count(poor, "SE_Thatch_4x6_Worn"), 1, "cottage %d: a Cottage has weathered thatch" % v)
		check_eq(_count(poor, "Roof_") , 0, "cottage %d: and no tiles or gables" % v)
		check(_modules(timber).has("thatch:SE_Thatch_4x6"), "cottage %d: a Timber House has neat thatch" % v)
		check_eq(_count(timber, "Roof_"), 0, "cottage %d: still no tiles" % v)
		check(_modules(town).has("Roof_RoundTiles_4x6"), "cottage %d: a Townhouse is tiled" % v)
		check_eq(_count(town, "Roof_Front_Brick4"), 2, "cottage %d: with its gable ends" % v)
		check_eq(_count(town, "SE_Thatch"), 0, "cottage %d: and no thatch" % v)
		for parts: Array in [poor, timber, town]:
			check_eq(_count(parts, "Prop_Chimney"), 1, "cottage %d: a chimney at every level" % v)
	for v in VillageKit.variants("farmhouse").size():
		var farm: Array = VillageKit.prefab("farmhouse", v, 0)["parts"]
		check(_modules(farm).has("thatch:SE_Thatch_6x8"), "farmhouse %d: neat thatch" % v)
		check_eq(_count(VillageKit.prefab("farmhouse", v, 0)["detail_parts"], "SE_Patch"), 0, "farmhouse %d: its walls are sound" % v)


func test_the_thatch_sits_on_its_walls() -> void:
	if not VillageKit.available():
		return
	for v in VillageKit.variants("cottage").size():
		var walls := VillageKit.wall_height("cottage", v, 0)
		var thatch: Dictionary = VillageKit.prefab("cottage", v, 0)
		var tiles: Dictionary = VillageKit.prefab("cottage", v, 2)
		var roof_xf := Transform3D()
		var chimney_xf := Transform3D()
		for p: Array in thatch["parts"]:
			if str(p[0]).contains("SE_Thatch"):
				roof_xf = p[1]
			if str(p[0]) == "Prop_Chimney":
				chimney_xf = p[1]
		check(is_equal_approx(roof_xf.origin.y, walls), "cottage %d: the roof sits on the walls (%.2f)" % [v, roof_xf.origin.y])
		var box := roof_xf * VillageKit.module_mesh("thatch:SE_Thatch_4x6_Worn").get_aabb()
		check(box.size.x >= 6.4 and box.size.z >= 4.6, "cottage %d: it overhangs the 6 x 4 m walls (%.1f x %.1f)" % [v, box.size.x, box.size.z])
		check(box.position.y < walls - 0.3, "cottage %d: its eaves come down past the wall tops" % v)
		var rise := float(thatch["height"]) - walls
		var tile_rise := float(tiles["height"]) - VillageKit.wall_height("cottage", v, 2)
		check(rise > 2.8 and absf(rise - tile_rise) < 0.8, "cottage %d: about as tall as the tiled roof (%.2f, %.2f)" % [v, rise, tile_rise])
		var chimney_top := chimney_xf.origin.y + VillageKit.module_mesh("Prop_Chimney").get_aabb().end.y
		check(chimney_top > float(thatch["height"]) + 0.3, "cottage %d: the chimney clears the ridge" % v)
		check(chimney_xf.origin.y < walls + rise - 1.5, "cottage %d: and rises out of the thatch, not off it" % v)


func test_a_poor_home_is_patched_and_shuttered() -> void:
	if not VillageKit.available():
		return
	var cfg := VillageKit.thatch_config()
	var patches := 0
	for v in VillageKit.variants("cottage").size():
		var recipe: Dictionary = VillageKit.variants("cottage")[v]
		var poor: Dictionary = VillageKit.prefab("cottage", v, 0)
		var timber: Dictionary = VillageKit.prefab("cottage", v, 1)
		var ground: String = str(recipe["blocks"][0].get("ground", recipe["blocks"][0]["walls"]))
		var mine := 0
		for p: Array in poor["detail_parts"]:
			var m := str(p[0])
			var xf: Transform3D = p[1]
			if m.contains("SE_Patch"):
				mine += 1
				check((cfg["patches"][ground] as Array).has(m), "cottage %d: %s suits a %s wall" % [v, m, ground])
				check(xf.origin.y > 0.5 and xf.origin.y < 2.4, "cottage %d: patches are on the ground floor" % v)
				var out := Vector2(xf.origin.x, xf.origin.z)
				check(absf(out.x) > 2.9 or absf(out.y) > 1.9, "cottage %d: on the outside of a wall" % v)
			check(not m.begins_with("WindowShutters_"), "cottage %d: no kit shutters at a poor home (%s)" % [v, m])
		check(mine <= int(recipe.get("repairs", 0)), "cottage %d: at most %d patches (%d)" % [v, int(recipe.get("repairs", 0)), mine])
		patches += mine
		check_eq(_count(timber["detail_parts"], "SE_Patch"), 0, "cottage %d: a Timber House is mended" % v)
		check_eq(_count(timber["detail_parts"], "SE_Shutters_Plank"), 0, "cottage %d: with the kit's shutters" % v)
		# Same windows, same shutters open or shut: only the planks change.
		var floors := VillageKit.wall_height("cottage", v, 0)
		var a: Array = []
		var b: Array = []
		for p: Array in poor["detail_parts"]:
			if str(p[0]).contains("Shutters") and (p[1] as Transform3D).origin.y < floors:
				a.append("%s@%s" % [str(p[0]).get_slice("_", str(p[0]).get_slice_count("_") - 1), str((p[1] as Transform3D).origin.snappedf(0.01))])
		for p: Array in timber["detail_parts"]:
			if str(p[0]).contains("Shutters") and (p[1] as Transform3D).origin.y < floors:
				b.append("%s@%s" % [str(p[0]).get_slice("_", str(p[0]).get_slice_count("_") - 1), str((p[1] as Transform3D).origin.snappedf(0.01))])
		a.sort()
		b.sort()
		check_eq(a, b, "cottage %d: the shutters hang where they did, open or shut as they were" % v)
	check(patches > 0, "some poor cottages are patched (%d)" % patches)


func test_a_missing_roof_size_falls_back_to_tiles() -> void:
	if not VillageKit.available():
		return
	var prefabs: Dictionary = VillageKit.config()["prefabs"]
	prefabs["_test_barn"] = {"variants": [{"blocks": [{"cells": [5, 4], "at": [0, 0], "stories": 1, "walls": "plaster", "roof": "thatch", "ridge": "x", "door": true}]}]}
	var p := VillageKit.prefab("_test_barn", 0)
	check(_modules(p["parts"]).has("Roof_RoundTiles_8x10"), "no 8 x 10 thatch: the kit's tiles instead")
	prefabs.erase("_test_barn")
	VillageKit.clear_cache()


func test_the_same_home_comes_out_the_same() -> void:
	if not VillageKit.available():
		return
	var first: Array = (VillageKit.prefab("cottage", 0, 0)["detail_parts"] as Array).duplicate()
	VillageKit.clear_cache()
	var again: Array = VillageKit.prefab("cottage", 0, 0)["detail_parts"]
	check_eq(_modules(again), _modules(first), "patches and shutters are rolled the same every time")
