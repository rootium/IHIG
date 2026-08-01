extends Node2D
## Game manager: owns the board, the screens and the level you are on, and
## arbitrates between them. Everything else in this project is deliberately
## unaware of game state.

enum Mode { MENU, PLAY, SOLVED }

var mode: Mode = Mode.MENU
var palette: Dictionary = {}

var board: Board
var hud: HUD
var menus: Menus

var taps: int = 0

var _grid: Grid


func _ready() -> void:
	SaveData.load_game()

	board = Board.new()
	board.tile_pressed.connect(_on_tile_pressed)
	add_child(board)

	hud = HUD.new()
	hud.reset_pressed.connect(_restart_level)
	hud.hint_pressed.connect(_hint)
	hud.quit_pressed.connect(to_title)
	add_child(hud)

	menus = Menus.new()
	menus.play_pressed.connect(func() -> void: start_level(SaveData.level))
	menus.next_pressed.connect(func() -> void: start_level(SaveData.level))
	menus.replay_pressed.connect(_restart_level)
	menus.title_pressed.connect(to_title)
	add_child(menus)

	get_viewport().size_changed.connect(_relayout)
	_relayout()  # records the board rect before the first level is loaded into it
	to_title()


func _notification(what: int) -> void:
	# Android back button: step out of the level rather than closing the app.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == Mode.MENU and not menus.any_visible():
			get_tree().quit()
		elif mode == Mode.MENU:
			menus.show_title()
		else:
			to_title()


# --- level lifecycle ---------------------------------------------------------

## The title shows the level you are about to play, already solved. It is the
## most attractive thing the game can put on screen, and it never spoils
## anything you have not asked for — you are about to be handed the same board
## with a few pieces turned.
func to_title() -> void:
	mode = Mode.MENU
	_load(SaveData.level)
	_grid.orient = _grid.solution.duplicate()
	board.interactive = false
	board.refresh()
	hud.visible = false
	# A first-time player meets the pieces before the board, rather than being
	# dropped onto a grid of shapes nothing has named.
	if SaveData.seen_howto:
		menus.show_title()
	else:
		SaveData.seen_howto = true
		SaveData.save_game()
		menus.show_howto()


func start_level(n: int) -> void:
	mode = Mode.PLAY
	_load(n)
	_grid.restart()
	taps = 0
	board.interactive = true
	board.refresh()
	hud.visible = true
	menus.hide_all()
	_sync_hud()


func _restart_level() -> void:
	start_level(_grid.level)


func _load(n: int) -> void:
	_apply_skin()
	if _grid == null or _grid.level != n:
		_grid = Generator.build(n)
	# set_level re-measures against the rect _relayout already recorded, so the
	# board resizes itself for a grid of a different shape without a second pass.
	board.set_level(_grid)


func _apply_skin() -> void:
	palette = Skins.palette(SaveData.palette_id)
	RenderingServer.set_default_clear_color(palette.get("bg", LM.C_BG))
	board.palette = palette
	board.optic = Skins.optic(SaveData.optic_id)
	menus.set_skin(palette, board.optic)


func _relayout() -> void:
	var vp := get_viewport_rect().size
	board.layout(Rect2(LM.PAD, LM.TOP_BAR,
		vp.x - LM.PAD * 2.0, vp.y - LM.TOP_BAR - LM.BOTTOM_BAR))


func _sync_hud() -> void:
	hud.level = _grid.level
	hud.taps = taps
	hud.par = _grid.par
	hud.hint_ready = _grid.wrong_piece() >= 0
	hud.refresh()


# --- play --------------------------------------------------------------------

func _on_tile_pressed(cell: int) -> void:
	if mode != Mode.PLAY or not _grid.is_movable(cell):
		return
	_grid.toggle(cell)
	taps += 1
	board.refresh()
	board.ping(cell)
	if board.solved():
		_on_solved()
	else:
		_sync_hud()


## Buys one correct piece. It costs credits and it costs a tap, so a hint is
## always a real concession rather than a free undo — which is what keeps par
## worth anything.
func _hint() -> void:
	if mode != Mode.PLAY:
		return
	var cell := _grid.wrong_piece()
	if cell < 0 or not SaveData.spend(LM.HINT_COST):
		return
	_grid.toggle(cell)
	taps += 1
	board.refresh()
	board.ping(cell)
	if board.solved():
		_on_solved()
	else:
		_sync_hud()


func _on_solved() -> void:
	mode = Mode.SOLVED
	var level := _grid.level
	var result := SaveData.clear_level(level, taps, _grid.par)
	hud.visible = false
	board.interactive = false
	menus.show_cleared(level, taps, _grid.par, result)
