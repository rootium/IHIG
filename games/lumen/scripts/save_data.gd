class_name SaveData
extends RefCounted
## Player wallet, unlocks and progress, persisted to user:// as JSON.
##
## Static so any script can reach it without an autoload. `load_game()` is
## idempotent, so callers can front-load it without tracking who got there first.

const PATH := "user://lumen.save"

static var credits: int = 0
static var level: int = 1         ## Lowest level not yet cleared.
static var cleared: int = 0
static var stars: int = 0
static var owned_optics: Array[String] = ["standard"]
static var owned_palettes: Array[String] = ["darkroom"]
static var optic_id: String = "standard"
static var palette_id: String = "darkroom"
static var seen_howto: bool = false

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
	level = maxi(1, int(d.get("level", 1)))
	cleared = int(d.get("cleared", 0))
	stars = int(d.get("stars", 0))
	optic_id = str(d.get("optic_id", "standard"))
	palette_id = str(d.get("palette_id", "darkroom"))
	# A save from before the how-to screen existed belongs to someone who has
	# already played, so do not interrupt them with it.
	seen_howto = bool(d.get("seen_howto", true))
	owned_optics = _to_ids(d.get("owned_optics", []), "standard")
	owned_palettes = _to_ids(d.get("owned_palettes", []), "darkroom")
	# A save written by an older build may not know about the equipped item.
	if not owned_optics.has(optic_id):
		optic_id = "standard"
	if not owned_palettes.has(palette_id):
		palette_id = "darkroom"


static func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Lumen: could not write save file.")
		return
	f.store_string(JSON.stringify({
		"credits": credits,
		"level": level,
		"cleared": cleared,
		"stars": stars,
		"optic_id": optic_id,
		"palette_id": palette_id,
		"seen_howto": seen_howto,
		"owned_optics": owned_optics,
		"owned_palettes": owned_palettes,
	}))
	f.close()


static func owns(kind: String, id: String) -> bool:
	return (owned_optics if kind == "optic" else owned_palettes).has(id)


## Spends `cost` and grants the item. Returns false (and changes nothing) if
## the player cannot afford it or already owns it.
static func buy(kind: String, id: String, cost: int) -> bool:
	if owns(kind, id) or credits < cost:
		return false
	credits -= cost
	if kind == "optic":
		owned_optics.append(id)
	else:
		owned_palettes.append(id)
	save_game()
	return true


static func equip(kind: String, id: String) -> void:
	if not owns(kind, id):
		return
	if kind == "optic":
		optic_id = id
	else:
		palette_id = id
	save_game()


static func spend(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	save_game()
	return true


## Books a cleared level and returns {stars, earned, fresh}.
##
## Replays pay a fraction, so going back to level 1 is never a better way to
## earn than moving on. Stars are the tap count measured against the
## generator's own solution: matching it is three, and there is always a way to.
static func clear_level(n: int, taps: int, par: int) -> Dictionary:
	var earned_stars := 3 if taps <= par else (2 if taps <= par * 2 + 2 else 1)
	var fresh := n >= level
	var earned := LM.CR_BASE + n * LM.CR_PER_LEVEL + earned_stars * LM.CR_PER_STAR
	if not fresh:
		earned = int(earned * LM.REPLAY_RATE)
	credits += earned
	if fresh:
		level = n + 1
		cleared += 1
		stars += earned_stars
	save_game()
	return {"stars": earned_stars, "earned": earned, "fresh": fresh}


static func _to_ids(v: Variant, fallback: String) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		for item in (v as Array):
			out.append(str(item))
	if not out.has(fallback):
		out.append(fallback)
	return out
