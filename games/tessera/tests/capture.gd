extends SceneTree

## Renders the game offscreen and writes PNGs, so the look can be checked from
## a terminal. Run with:
##
##   xvfb-run -a godot --path games/tessera -s tests/capture.gd -- out/ [script]
##
## The optional script is a comma separated list of steps, each either a number
## of frames to wait or an action name to fire, e.g. "60,ui_play,10,right,20".

var _out := "res://.capture"
var _steps: Array = []
var _i := 0
var _wait := 0
var _shot := 0
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var script := "70" if args.size() < 2 else args[1]
	for s in script.split(","):
		_steps.append(s.strip_edges())
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= _steps.size():
		return true

	var s: String = _steps[_i]
	_i += 1
	if s.is_valid_int():
		_wait = int(s)
		return false

	var game = _main.game
	var ui = _main.ui
	match s:
		"shot":
			var img := root.get_texture().get_image()
			img.save_png("%s/shot%02d.png" % [_out, _shot])
			print("wrote %s/shot%02d.png" % [_out, _shot])
			_shot += 1
		"ui_play": ui.go(ui.Screen.PLAY)
		"ui_title": ui.go(ui.Screen.TITLE)
		"ui_select": ui.go(ui.Screen.SELECT)
		"ui_howto": ui.go(ui.Screen.HOWTO)
		"right": game.walk_screen(1, 0)
		"left": game.walk_screen(-1, 0)
		"fwd": game.walk_screen(0, -1)
		"back": game.walk_screen(0, 1)
		"ana": game.try_shift(1)
		"kata": game.try_shift(-1)
		"rotzw": game.try_rotate(2, 1)
		"rotxw": game.try_rotate(0, 1)
		"undo": game.undo()
		_:
			if s.begins_with("level"):
				_main.open(int(s.substr(5)))
	return false
