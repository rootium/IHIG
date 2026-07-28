extends Node

## Progress and settings, in one small JSON file. Web builds get the same
## thing through Godot's IndexedDB-backed user:// filesystem.

const PATH := "user://tessera.save"
const VERSION := 1

var data := {
	"version": VERSION,
	"records": {},          ## level id -> {moves, shards, done}
	"seen_intro": false,
	"settings": {
		"sfx": 0.85,
		"music": 0.55,
		"ghosts": Cfg.GHOST_DEPTH,
		"touch": "auto",     ## auto | on | off
		"invert_drag": false,
		"reduce_flash": false,
	},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()
	Audio.sfx_volume = data.settings.sfx
	Audio.music_volume = data.settings.music


func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# Merge rather than replace, so a save written by an older build still
	# picks up settings added since.
	for k in parsed:
		if k == "settings" and typeof(parsed[k]) == TYPE_DICTIONARY:
			for s in parsed[k]:
				data.settings[s] = parsed[k][s]
		else:
			data[k] = parsed[k]


func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


func record(id: String) -> Dictionary:
	if not data.records.has(id):
		data.records[id] = {"moves": 0, "shards": 0, "done": false}
	return data.records[id]


func report(id: String, moves: int, shards: int) -> Dictionary:
	var r := record(id)
	var improved := false
	if not r.done or moves < int(r.moves):
		if r.done:
			improved = moves < int(r.moves)
		r.moves = moves
	r.shards = maxi(int(r.shards), shards)
	var first: bool = not r.done
	r.done = true
	save_game()
	return {"first": first, "improved": improved}


func is_done(id: String) -> bool:
	return data.records.has(id) and data.records[id].done


func total_done() -> int:
	var n := 0
	for k in data.records:
		if data.records[k].done:
			n += 1
	return n


func total_shards() -> int:
	var n := 0
	for k in data.records:
		n += int(data.records[k].shards)
	return n


func setting(key: String, fallback = null):
	return data.settings.get(key, fallback)


func set_setting(key: String, value) -> void:
	data.settings[key] = value
	save_game()
