extends Node3D

## Application shell. Owns the playfield and hands input to it; the menus and
## HUD live in ui.gd on a layer above.

var game: Game
var ui: Node
var index := 0


func _ready() -> void:
	game = Game.new()
	add_child(game)
	game.solved.connect(_on_solved)

	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)
	ui.bind(self, game)

	open(index)


func open(i: int) -> void:
	index = clampi(i, 0, Campaign.count() - 1)
	game.load_level(Campaign.get_level(index))
	ui.on_level_opened(index)


func next() -> void:
	if index + 1 < Campaign.count():
		open(index + 1)
	else:
		ui.show_outro()


func _on_solved(moves: int, shards: int, par: int) -> void:
	var res := Save.report(Campaign.id(index), moves, shards)
	ui.show_solved(moves, shards, par, res)


func _process(delta: float) -> void:
	if game == null or game.level == null:
		return
	if ui.blocking_input():
		# Nobody is playing, but the chamber behind the menus should still be
		# turning — it is most of what the title screen is.
		if ui.screen == ui.Screen.TITLE:
			game.drift_camera(delta)
		return
	if Input.is_action_just_pressed("move_forward"): game.walk_screen(0, -1)
	elif Input.is_action_just_pressed("move_back"): game.walk_screen(0, 1)
	elif Input.is_action_just_pressed("move_left"): game.walk_screen(-1, 0)
	elif Input.is_action_just_pressed("move_right"): game.walk_screen(1, 0)
	if Input.is_action_just_pressed("step_ana"): game.try_shift(1)
	if Input.is_action_just_pressed("step_kata"): game.try_shift(-1)
	if Input.is_action_just_pressed("rot_zw"): game.try_rotate(2, 1)
	if Input.is_action_just_pressed("rot_xw"): game.try_rotate(0, 1)
	if Input.is_action_just_pressed("undo"): game.undo()
	if Input.is_action_just_pressed("restart"): game.restart()
	if Input.is_action_just_pressed("cam_left"): game.spin_camera(1)
	if Input.is_action_just_pressed("cam_right"): game.spin_camera(-1)
