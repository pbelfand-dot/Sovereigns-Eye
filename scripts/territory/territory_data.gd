class_name TerritoryData
extends RefCounted
## The village's stores and building works (Phase 3). Pure data; the rules
## live in TerritorySystem. Gold is not here: it stays the house treasury
## (HouseData.gold), so the court and the village share one purse.

## "food" / "wood" / "stone" -> amount (fractional: production is per day).
var stock: Dictionary = {}
var sites: Array[ConstructionSite] = []
## Ids of buildings the player has raised.
var built: Array[int] = []
## Indices into VillageLayout.trees felled to make room.
var cleared_trees: Array[int] = []
## Next free building id (shared with the layout's own ids).
var next_building_id: int = 1
## Net change of each resource on the last day, for the HUD and ledger.
var last_change: Dictionary = {}


func amount(resource: String) -> float:
	return float(stock.get(resource, 0.0))


func get_site(building_id: int) -> ConstructionSite:
	for s in sites:
		if s.id() == building_id:
			return s
	return null


func to_dict() -> Dictionary:
	var stock_out := {}
	for k: String in stock:
		stock_out[k] = snappedf(float(stock[k]), 0.01)
	var change_out := {}
	for k: String in last_change:
		change_out[k] = snappedf(float(last_change[k]), 0.01)
	var site_list: Array = []
	for s in sites:
		site_list.append(s.to_dict())
	return {
		"stock": stock_out,
		"sites": site_list,
		"built": built.duplicate(),
		"cleared_trees": cleared_trees.duplicate(),
		"next_building_id": next_building_id,
		"last_change": change_out,
	}


static func from_dict(d: Dictionary) -> TerritoryData:
	var t := TerritoryData.new()
	var stock_in: Dictionary = d.get("stock", {})
	for k: String in stock_in:
		t.stock[k] = float(stock_in[k])
	for s: Dictionary in d.get("sites", []):
		t.sites.append(ConstructionSite.from_dict(s))
	for id: Variant in d.get("built", []):
		t.built.append(int(id))
	for i: Variant in d.get("cleared_trees", []):
		t.cleared_trees.append(int(i))
	t.next_building_id = int(d.get("next_building_id", 1))
	var change_in: Dictionary = d.get("last_change", {})
	for k: String in change_in:
		t.last_change[k] = float(change_in[k])
	return t
