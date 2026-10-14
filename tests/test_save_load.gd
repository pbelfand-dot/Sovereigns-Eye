extends TestCase

const SLOT := "test_roundtrip"


func test_save_load_roundtrip() -> void:
	var w := WorldGenerator.generate("roundtrip-seed")
	# Mutate live state the way play would.
	var c := w.characters[3]
	c.happiness = 12.5
	c.loyalty = 88.25
	c.appraised = true
	c.position = Vector3(10.5, 0.0, -4.25)
	c.inside_building_id = -1
	c.activity = "work"
	c.add_history(1187, "Spring", "achievement", "Test event")
	w.minutes = 12345.5
	var before := JSON.stringify(w.to_dict())

	check_eq(SaveManager.save(w, SLOT), OK, "save succeeds")
	var loaded := SaveManager.load_state(SLOT)
	check(loaded != null, "load succeeds")
	if loaded == null:
		return
	var after := JSON.stringify(loaded.to_dict())
	check(before == after, "world survives a save/load round trip unchanged")
	var lc := loaded.get_character(c.id)
	check_eq(lc.full_name(), c.full_name(), "identity kept")
	check_eq(lc.get_potential("leadership"), c.get_potential("leadership"), "potential kept")
	check(lc.appraised, "appraisal flag kept")
	check_eq(lc.position, c.position, "position kept")
	check_eq(loaded.layout.buildings.size(), w.layout.buildings.size(), "buildings kept")
	SaveManager.delete(SLOT)
	check(not SaveManager.exists(SLOT), "slot deleted")


func test_missing_slot_returns_null() -> void:
	check(SaveManager.load_state("does_not_exist") == null, "missing slot loads as null")
