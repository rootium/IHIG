class_name SaveData
extends RefCounted
## Player wallet, unlocks and records, persisted to user:// as JSON.
##
## Static so any script can reach it without an autoload. `load_game()` is
## idempotent, so callers can front-load it without tracking who got there first.

const PATH := "user://dunk_rush.save"

static var credits: int = 0
static var best_score: int = 0
static var best_combo: int = 0
static var total_runs: int = 0
static var owned_ballers: Array[String] = ["rookie"]
static var owned_arenas: Array[String] = ["night_court"]
static var baller_id: String = "rookie"
static var arena_id: String = "night_court"

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
	best_score = int(d.get("best_score", 0))
	best_combo = int(d.get("best_combo", 0))
	total_runs = int(d.get("total_runs", 0))
	baller_id = str(d.get("baller_id", "rookie"))
	arena_id = str(d.get("arena_id", "night_court"))
	owned_ballers = _to_ids(d.get("owned_ballers", []), "rookie")
	owned_arenas = _to_ids(d.get("owned_arenas", []), "night_court")
	# A save written by an older build may not know about the equipped item.
	if not owned_ballers.has(baller_id):
		baller_id = "rookie"
	if not owned_arenas.has(arena_id):
		arena_id = "night_court"


static func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Dunk Rush: could not write save file.")
		return
	f.store_string(JSON.stringify({
		"credits": credits,
		"best_score": best_score,
		"best_combo": best_combo,
		"total_runs": total_runs,
		"baller_id": baller_id,
		"arena_id": arena_id,
		"owned_ballers": owned_ballers,
		"owned_arenas": owned_arenas,
	}))
	f.close()


static func owns(kind: String, id: String) -> bool:
	return (owned_ballers if kind == "baller" else owned_arenas).has(id)


## Spends `cost` and grants the item. Returns false (and changes nothing) if
## the player cannot afford it or already owns it.
static func buy(kind: String, id: String, cost: int) -> bool:
	if owns(kind, id) or credits < cost:
		return false
	credits -= cost
	if kind == "baller":
		owned_ballers.append(id)
	else:
		owned_arenas.append(id)
	save_game()
	return true


static func equip(kind: String, id: String) -> void:
	if not owns(kind, id):
		return
	if kind == "baller":
		baller_id = id
	else:
		arena_id = id
	save_game()


## Books the results of a finished run. Returns the credits it awarded.
##
## Points pay the most, because points already fold in the multiplier and are
## the thing the game is actually asking you to chase. Gold pays a flat rate, so
## detouring for it is worth it early and never worth blowing a combo over.
static func record_run(points: int, dunks: int, gold: int, best_run_combo: int) -> int:
	var earned := points * 4 + dunks * 3 + gold * 10
	credits += earned
	total_runs += 1
	best_score = maxi(best_score, points)
	best_combo = maxi(best_combo, best_run_combo)
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
