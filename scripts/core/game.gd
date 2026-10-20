extends Node
## Autoload "Game": owns the current WorldState and moves between the main
## menu and the world. Also the single entry point for saving and loading.

## Emitted right before saving so live systems (NPC positions) can write
## their state back into the WorldState.
signal before_save
signal game_saved(slot: String)
## UI toast messages from anywhere in the game.
signal notify(text: String, color: Color)
## The player changed their keys (ControlsSettings): prompts and help re-read them.
signal keys_changed

const WORLD_SCENE := "res://scenes/world/world.tscn"
const MENU_SCENE := "res://scenes/main/main.tscn"

const COLOR_INFO := Color(0.93, 0.86, 0.72)
const COLOR_GOOD := Color(0.6, 0.9, 0.55)
const COLOR_BAD := Color(0.95, 0.45, 0.4)
const COLOR_TALENT := Color(1.0, 0.72, 0.25)

var state: WorldState
## Slot the current game was loaded from / last saved to.
var current_slot: String = ""


func _ready() -> void:
	InputSetup.register()


func start_new_game(seed_text: String = "") -> void:
	if seed_text.strip_edges().is_empty():
		seed_text = Seeds.random_seed_text()
	state = WorldGenerator.generate(seed_text.strip_edges())
	current_slot = ""
	get_tree().change_scene_to_file(WORLD_SCENE)


func load_game(slot: String) -> bool:
	var loaded := SaveManager.load_state(slot)
	if loaded == null:
		notify.emit("Could not load %s." % SaveManager.slot_label(slot), COLOR_BAD)
		return false
	state = loaded
	current_slot = slot
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)
	return true


func save_game(slot: String) -> bool:
	if state == null:
		return false
	if state.player() and state.player().is_away():
		notify.emit("You can't save while you're away from the village.", COLOR_BAD)
		return false
	before_save.emit()
	var err := SaveManager.save(state, slot)
	if err != OK:
		notify.emit("Save failed: %s" % error_string(err), COLOR_BAD)
		return false
	current_slot = slot
	Audio.play("saved")
	game_saved.emit(slot)
	notify.emit("Game saved to %s." % SaveManager.slot_label(slot), COLOR_GOOD)
	return true


func quit_to_menu() -> void:
	state = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func quit_game() -> void:
	get_tree().quit()
