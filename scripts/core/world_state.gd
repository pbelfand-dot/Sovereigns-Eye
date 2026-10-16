class_name WorldState
extends RefCounted
## Everything that defines one playthrough: the seed, the clock, the village
## layout, families and characters. Saving the game = saving this object.

const SAVE_VERSION := 10

var seed_text: String = ""
var world_seed: int = 0
var village_name: String = ""
var ruling_family_id: int = -1
## The character the player plays: the heir of the ruling house (Phase 2).
var player_id: int = -1
## The player's house: gold, renown, offices. Set up by CourtSystem.
var house: HouseData
## The village's stores and building works (Phase 3). Set up by TerritorySystem.
var territory: TerritoryData
## Minutes since 00:00 on day 1 of the calendar.
var minutes: float = 0.0
## Last whole day for which daily updates (mood drift) ran.
var last_daily_update: int = 0

var layout: VillageLayout
var families: Array[FamilyData] = []
var characters: Array[CharacterData] = []

var _characters_by_id: Dictionary = {}
var _families_by_id: Dictionary = {}


# --- Lookup ------------------------------------------------------------------

func add_character(c: CharacterData) -> void:
	characters.append(c)
	_characters_by_id[c.id] = c


func add_family(f: FamilyData) -> void:
	families.append(f)
	_families_by_id[f.id] = f


func get_character(character_id: int) -> CharacterData:
	return _characters_by_id.get(character_id, null)


func get_family(family_id: int) -> FamilyData:
	return _families_by_id.get(family_id, null)


func get_building(building_id: int) -> BuildingData:
	if layout == null:
		return null
	return layout.get_building(building_id)


func ruling_family() -> FamilyData:
	return get_family(ruling_family_id)


func player() -> CharacterData:
	return get_character(player_id)


func is_player(c: CharacterData) -> bool:
	return c != null and c.id == player_id


## Whole days since the calendar began.
func day() -> int:
	return Calendar.day_index(whole_minutes())


func retainers() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c in characters:
		if c.retainer:
			out.append(c)
	return out


func residents_of(building_id: int) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c in characters:
		if c.home_building_id == building_id:
			out.append(c)
	return out


func workers_of(building_id: int) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c in characters:
		if c.work_building_id == building_id:
			out.append(c)
	return out


# --- Time --------------------------------------------------------------------

func whole_minutes() -> int:
	return floori(minutes)


func current_year() -> int:
	return Calendar.year(whole_minutes())


func current_season() -> String:
	return Calendar.season_name(whole_minutes())


# --- Serialization -------------------------------------------------------------

func to_dict() -> Dictionary:
	var family_list: Array = []
	for f in families:
		family_list.append(f.to_dict())
	var character_list: Array = []
	for c in characters:
		character_list.append(c.to_dict())
	return {
		"save_version": SAVE_VERSION,
		"seed_text": seed_text,
		"seed": world_seed,
		"village_name": village_name,
		"ruling_family": ruling_family_id,
		"player": player_id,
		"house": house.to_dict() if house else {},
		"territory": territory.to_dict() if territory else {},
		"minutes": snappedf(minutes, 0.01),
		"last_daily_update": last_daily_update,
		"layout": layout.to_dict() if layout else {},
		"families": family_list,
		"characters": character_list,
	}


static func from_dict(d: Dictionary) -> WorldState:
	var w := WorldState.new()
	w.seed_text = str(d.get("seed_text", ""))
	w.world_seed = int(d.get("seed", 0))
	w.village_name = str(d.get("village_name", ""))
	w.ruling_family_id = int(d.get("ruling_family", -1))
	w.player_id = int(d.get("player", -1))
	var house_d: Dictionary = d.get("house", {})
	w.house = HouseData.from_dict(house_d) if not house_d.is_empty() else null
	var territory_d: Dictionary = d.get("territory", {})
	w.territory = TerritoryData.from_dict(territory_d) if not territory_d.is_empty() else null
	w.minutes = float(d.get("minutes", 0.0))
	w.last_daily_update = int(d.get("last_daily_update", 0))
	w.layout = VillageLayout.from_dict(d.get("layout", {}))
	for f: Dictionary in d.get("families", []):
		w.add_family(FamilyData.from_dict(f))
	for c: Dictionary in d.get("characters", []):
		w.add_character(CharacterData.from_dict(c))
	# An upgrade site works on the home itself, not a copy.
	if w.territory:
		for s in w.territory.sites:
			if s.is_upgrade() and w.layout.get_building(s.id()):
				s.building = w.layout.get_building(s.id())
	return w
