class_name SaveData
extends RefCounted
## Player wallet, unlocks and records, persisted to user:// as JSON.
##
## Static so any script can reach it without an autoload. `load_game()` is
## idempotent, so callers can front-load it without tracking who got there first.

const PATH := "user://planet_hopper.save"

static var credits: int = 0
static var best_distance: int = 0
static var total_runs: int = 0
static var owned_ships: Array[String] = ["scout"]
static var owned_themes: Array[String] = ["deep_field"]
static var ship_id: String = "scout"
static var theme_id: String = "deep_field"

static var _loaded := false


static func load_game() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	credits = int(d.get("credits", 0))
	best_distance = int(d.get("best_distance", 0))
	total_runs = int(d.get("total_runs", 0))
	ship_id = str(d.get("ship_id", "scout"))
	theme_id = str(d.get("theme_id", "deep_field"))
	owned_ships = _to_ids(d.get("owned_ships", []), "scout")
	owned_themes = _to_ids(d.get("owned_themes", []), "deep_field")
	# A save written by an older build may not know about the equipped item.
	if not owned_ships.has(ship_id):
		ship_id = "scout"
	if not owned_themes.has(theme_id):
		theme_id = "deep_field"


static func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Planet Hopper: could not write save file.")
		return
	f.store_string(JSON.stringify({
		"credits": credits,
		"best_distance": best_distance,
		"total_runs": total_runs,
		"ship_id": ship_id,
		"theme_id": theme_id,
		"owned_ships": owned_ships,
		"owned_themes": owned_themes,
	}))
	f.close()


static func owns(kind: String, id: String) -> bool:
	return (owned_ships if kind == "ship" else owned_themes).has(id)


## Spends `cost` and grants the item. Returns false (and changes nothing) if
## the player cannot afford it or already owns it.
static func buy(kind: String, id: String, cost: int) -> bool:
	if owns(kind, id) or credits < cost:
		return false
	credits -= cost
	if kind == "ship":
		owned_ships.append(id)
	else:
		owned_themes.append(id)
	save_game()
	return true


static func equip(kind: String, id: String) -> void:
	if not owns(kind, id):
		return
	if kind == "ship":
		ship_id = id
	else:
		theme_id = id
	save_game()


## Books the results of a finished run. Returns the credits it awarded.
static func record_run(distance: int, planets: int) -> int:
	var earned := int(distance / 60.0) + planets * 12
	credits += earned
	total_runs += 1
	best_distance = maxi(best_distance, distance)
	save_game()
	return earned


static func _to_ids(v: Variant, fallback: String) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		for item in (v as Array):
			out.append(str(item))
	if not out.has(fallback):
		out.append(fallback)
	return out
