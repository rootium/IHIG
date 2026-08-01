extends CanvasLayer

## Everything drawn on top of the chamber: the readouts, the screens, and the
## on-screen controls a phone needs.
##
## The one piece here that is not decoration is the scope. A three dimensional
## view of a four dimensional room cannot show you what is one step along the
## axis you are not looking down, and the ghost outlines in the world only tell
## you roughly. The scope tells you exactly, for the column you are standing
## in: solid, open, or something worth walking into.

enum Screen { TITLE, SELECT, PLAY, HOWTO, SETTINGS, PAUSE, SOLVED, OUTRO }

const SCOPE_RANGE := 4

## Edge of a square thumb target. 72 in a 1280x720 viewport lands around 9mm on
## a phone once the stretch scale is applied, which is the size a thumb wants.
const PAD_SIZE := 72

var main: Node
var game: Game
var screen := Screen.TITLE

var _font: Font
var _mono: Font
var _root: Control
var _panes := {}
var _hud: Control
var _scope: Control
var _toast: Label
var _toast_t := 0.0
var _title_lbl: Label
var _stat_lbl: Label
var _axis_lbl: RichTextLabel
var _shard_lbl: Label
var _keys_box: HBoxContainer
var _undo_btn: Button
var _reset_btn: Button
var _touch: Control
var _select_grid: GridContainer
var _solved_body: RichTextLabel
var _howto_body: RichTextLabel
var _use_touch := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = _load_font("res://fonts/SpaceGrotesk.ttf")
	_mono = _load_font("res://fonts/JetBrainsMono.ttf")

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_hud()
	_build_touch()
	_panes[Screen.TITLE] = _build_title()
	_panes[Screen.SELECT] = _build_select()
	_panes[Screen.HOWTO] = _build_howto()
	_panes[Screen.SETTINGS] = _build_settings()
	_panes[Screen.PAUSE] = _build_pause()
	_panes[Screen.SOLVED] = _build_solved()
	_panes[Screen.OUTRO] = _build_outro()

	_refresh_touch_mode()
	go(Screen.TITLE)


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path)
		if f is Font:
			return f
	return ThemeDB.fallback_font


func bind(m: Node, g: Game) -> void:
	main = m
	game = g
	g.stats_changed.connect(_refresh_stats)
	g.narrated.connect(toast)
	g.died.connect(func(): _flash(Cfg.C_HAZARD_EDGE))


func blocking_input() -> bool:
	return screen != Screen.PLAY


# --- small builders -----------------------------------------------------------

func _lab(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", _font)
	r.add_theme_font_override("bold_font", _font)
	r.add_theme_font_override("mono_font", _mono)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size)
	r.add_theme_color_override("default_color", Cfg.UI_TEXT)
	return r


func _style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _btn(text: String, cb: Callable, accent := Cfg.UI_ACCENT, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Cfg.UI_TEXT)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", Cfg.VOID)
	b.add_theme_stylebox_override("normal", _style(Color(accent.r, accent.g, accent.b, 0.08), Color(accent.r, accent.g, accent.b, 0.45), 2, 6))
	b.add_theme_stylebox_override("hover", _style(Color(accent.r, accent.g, accent.b, 0.18), accent, 2, 6))
	b.add_theme_stylebox_override("pressed", _style(Color(accent.r, accent.g, accent.b, 0.85), accent, 2, 6))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color(accent.r, accent.g, accent.b, 0.8), 2, 6))
	b.pressed.connect(func():
		Audio.ui()
		cb.call())
	return b


func _pane(dim := 0.82) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	var bg := ColorRect.new()
	bg.color = Color(Cfg.VOID.r, Cfg.VOID.g, Cfg.VOID.b, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	_root.add_child(c)
	return c


func _column(parent: Control, sep := 14) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 40)
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 28)
	parent.add_child(m)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", sep)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(v)
	return v


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)

	var top := HBoxContainer.new()
	top.position = Vector2(26, 18)
	top.add_theme_constant_override("separation", 22)
	_hud.add_child(top)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	top.add_child(col)
	_title_lbl = _lab("", 27, Cfg.UI_TEXT)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_title_lbl)
	_stat_lbl = _lab("", 15, Cfg.UI_DIM, _mono)
	_stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_stat_lbl)

	_keys_box = HBoxContainer.new()
	_keys_box.add_theme_constant_override("separation", 7)
	col.add_child(_keys_box)

	_axis_lbl = _rich(15)
	_axis_lbl.custom_minimum_size = Vector2(340, 24)
	_hud.add_child(_axis_lbl)

	_scope = Control.new()
	_scope.custom_minimum_size = Vector2(330, 54)
	_scope.size = Vector2(330, 46)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.draw.connect(_draw_scope)
	_hud.add_child(_scope)

	# Both are positioned by _place_readouts, which depends on touch mode.

	_shard_lbl = _lab("", 17, Cfg.C_SHARD_EDGE, _mono)
	_shard_lbl.anchor_left = 1.0
	_shard_lbl.anchor_right = 1.0
	_shard_lbl.offset_left = -260
	_shard_lbl.offset_top = 66
	_shard_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shard_lbl.offset_right = -22
	_hud.add_child(_shard_lbl)

	# Undo and restart are chores, not moves. On a phone they used to sit in the
	# bottom-right cluster taking two of the six thumb slots away from the moves
	# that actually play the game, so they live up here with pause instead — and
	# only when there is no keyboard to press Z and R on.
	var top_right := HBoxContainer.new()
	top_right.add_theme_constant_override("separation", 8)
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -340
	top_right.offset_right = -22
	top_right.offset_top = 18
	_hud.add_child(top_right)

	_undo_btn = _btn("UNDO", func(): game.undo(), Cfg.UI_DIM, 15)
	_undo_btn.focus_mode = Control.FOCUS_NONE
	top_right.add_child(_undo_btn)
	_reset_btn = _btn("RESET", func(): game.restart(), Cfg.UI_DIM, 15)
	_reset_btn.focus_mode = Control.FOCUS_NONE
	top_right.add_child(_reset_btn)
	top_right.add_child(_btn("| |", func(): go(Screen.PAUSE), Cfg.UI_DIM, 17))

	_toast = _lab("", 19, Cfg.UI_ACCENT)
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -150
	_toast.offset_bottom = -112
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)


## The column readout. Each slot is one step along the hidden axis from where
## the player stands; the middle slot is the slice they are in.
func _draw_scope() -> void:
	if game == null or game.level == null:
		return
	var n := SCOPE_RANGE * 2 + 1
	var w := 30.0
	var gap := 5.0
	var total := n * w + (n - 1) * gap
	var x0 := 0.0
	var h := 26.0
	var y := 16.0

	var d := Vector4i(
		roundi((game.frame[3] as Vector4).x), roundi((game.frame[3] as Vector4).y),
		roundi((game.frame[3] as Vector4).z), roundi((game.frame[3] as Vector4).w))

	_scope.draw_string(_mono, Vector2(0, 11), "KATA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Cfg.KATA)
	_scope.draw_string(_mono, Vector2(total - 34, 11), "ANA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Cfg.ANA)

	for i in n:
		var off := i - SCOPE_RANGE
		var c := game.cell + Vector4i(d.x * off, d.y * off, d.z * off, d.w * off)
		var r := Rect2(x0 + i * (w + gap), y, w, h)
		var inside := game.level.in_bounds(c)
		var kind := game.level.kind_at(c) if inside else Cfg.Kind.SOLID
		var solid := (not inside) or game.level.blocks_movement(c, game.keys)
		var tint := Cfg.ANA if off > 0 else (Cfg.KATA if off < 0 else Cfg.UI_TEXT)
		var fade := 1.0 - absf(float(off)) / float(SCOPE_RANGE + 1) * 0.55

		if solid:
			_scope.draw_rect(r, Color(tint.r, tint.g, tint.b, 0.30 * fade), true)
			_scope.draw_rect(r, Color(tint.r, tint.g, tint.b, 0.75 * fade), false, 1.5)
		else:
			_scope.draw_rect(r, Color(tint.r, tint.g, tint.b, 0.06 * fade), true)
			_scope.draw_rect(r, Color(tint.r, tint.g, tint.b, 0.34 * fade), false, 1.0)
			# a floor tick, so you can see whether a step there would drop you
			var below := c + Vector4i(0, -1, 0, 0)
			if game.level.in_bounds(below) and game.level.blocks_movement(below, game.keys):
				_scope.draw_line(Vector2(r.position.x + 4, r.end.y - 3),
					Vector2(r.end.x - 4, r.end.y - 3), Color(tint.r, tint.g, tint.b, 0.8 * fade), 2.0)

		if inside and kind >= 0 and not solid:
			var mark := Cfg.edge_color(kind, game.level.hue_at(c))
			if kind != Cfg.Kind.SOLID:
				_scope.draw_circle(r.get_center(), 5.0, Color(mark.r, mark.g, mark.b, fade))

		if off == 0:
			_scope.draw_rect(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)),
				Cfg.PLAYER_EDGE, false, 2.0)


func _axis_chip(v: Vector4, label: String, color: Color) -> String:
	var a := Hyper.axis_of(v)
	var sign := "" if a[1] > 0 else "-"
	return "[color=#%s]%s %s%s[/color]" % [color.to_html(false), label, sign, Hyper.AXIS_NAMES[a[0]]]


func _refresh_stats() -> void:
	if game == null or game.level == null:
		return
	var lv := game.level
	_title_lbl.text = lv.name
	var par_txt := "  ·  par %d" % lv.par if lv.par > 0 else ""
	_stat_lbl.text = "moves %d%s   turns %d   shifts %d" % [game.moves, par_txt, game.rotations, game.shifts]
	_shard_lbl.text = ("shards  %d / %d" % [game.shards, lv.shard_total]) if lv.shard_total > 0 else ""

	_axis_lbl.text = "[b]%s[/b]   %s   [color=#%s]hidden[/color] %s" % [
		_axis_chip(game.frame[0], "screen x", Cfg.UI_DIM),
		_axis_chip(game.frame[2], "screen z", Cfg.UI_DIM),
		Cfg.UI_DIM.to_html(false),
		_axis_chip(game.frame[3], "", Cfg.UI_ACCENT).replace(" -", "-").replace("  ", " ")]

	for c in _keys_box.get_children():
		c.queue_free()
	for h in Cfg.HUES.size():
		if (game.keys & (1 << h)) != 0:
			var chip := _lab("◆", 19, Cfg.HUES[h])
			_keys_box.add_child(chip)

	_scope.queue_redraw()


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 4.2


func _flash(c: Color) -> void:
	if Save.setting("reduce_flash", false):
		return
	var r := ColorRect.new()
	r.color = Color(c.r, c.g, c.b, 0.34)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 0.0, 0.4)
	tw.tween_callback(r.queue_free)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0) * clampf((4.2 - _toast_t) * 4.0, 0.0, 1.0)
	elif _toast.modulate.a > 0.0:
		_toast.modulate.a = 0.0
	if screen == Screen.PLAY and game and game.level:
		_scope.queue_redraw()


# --- screens ------------------------------------------------------------------

func go(s: int) -> void:
	screen = s
	for k in _panes:
		_panes[k].visible = (k == s)
	var playing := s == Screen.PLAY
	_hud.visible = playing
	_touch.visible = playing and _use_touch
	get_tree().paused = (s == Screen.PAUSE)
	if s == Screen.SELECT:
		_fill_select()
	if Save.setting("music", 0.55) > 0.001:
		Audio.music("title" if s in [Screen.TITLE, Screen.HOWTO, Screen.SETTINGS] else "bed")


func _build_title() -> Control:
	var p := _pane(0.55)
	var v := _column(p, 10)
	v.add_child(_lab("T E S S E R A", 74, Cfg.UI_TEXT))
	var sub := _lab("a puzzle in four spatial dimensions", 21, Cfg.UI_ACCENT)
	v.add_child(sub)
	v.add_child(_spacer(26))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_btn("  ENTER  ", func():
		if not Save.data.seen_intro:
			Save.data.seen_intro = true
			Save.save_game()
			go(Screen.HOWTO)
		else:
			go(Screen.SELECT), Cfg.C_GOAL_EDGE, 24))
	row.add_child(_btn("CHAMBERS", func(): go(Screen.SELECT)))
	row.add_child(_btn("HOW", func(): go(Screen.HOWTO)))
	row.add_child(_btn("SETTINGS", func(): go(Screen.SETTINGS)))
	v.add_child(_spacer(10))
	var credit := _lab("IHIG · third game", 13, Cfg.UI_DIM)
	v.add_child(credit)
	return p


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _build_select() -> Control:
	var p := _pane()
	var v := _column(p)
	v.add_child(_lab("CHAMBERS", 40, Cfg.UI_TEXT))
	_select_grid = GridContainer.new()
	_select_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_select_grid.columns = 8
	_select_grid.add_theme_constant_override("h_separation", 8)
	_select_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_select_grid)
	v.add_child(_spacer(12))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("TITLE", func(): go(Screen.TITLE), Cfg.UI_DIM))
	v.add_child(row)
	return p


func _fill_select() -> void:
	for c in _select_grid.get_children():
		c.queue_free()
	var unlocked := 0
	for i in Campaign.count():
		if Save.is_done(Campaign.id(i)):
			unlocked = i + 1
	unlocked = mini(unlocked, Campaign.count() - 1)
	for i in Campaign.count():
		var done := Save.is_done(Campaign.id(i))
		var open := i <= unlocked
		var accent := Cfg.C_GOAL_EDGE if done else (Cfg.UI_ACCENT if open else Cfg.UI_DIM)
		var b := _btn("%d" % (i + 1), func():
			if open:
				main.open(i)
				go(Screen.PLAY), accent, 17)
		b.custom_minimum_size = Vector2(56, 46)
		b.disabled = not open
		_select_grid.add_child(b)


func _build_howto() -> Control:
	var p := _pane()
	var v := _column(p, 10)
	v.add_child(_lab("FOUR DIRECTIONS, NOT THREE", 34, Cfg.UI_TEXT))
	_howto_body = _rich(19)
	_howto_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_howto_body.custom_minimum_size = Vector2(760, 380)
	v.add_child(_howto_body)
	_refresh_howto()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("BEGIN", func(): go(Screen.SELECT), Cfg.C_GOAL_EDGE))
	row.add_child(_btn("TITLE", func(): go(Screen.TITLE), Cfg.UI_DIM))
	v.add_child(row)
	return p


## The instructions have to name the controls the player actually has. Telling
## someone on a phone to press E and Q — while the buttons in front of them say
## ANA and KATA — is worse than saying nothing, so each control gets described
## as whatever it is on this device.
func _refresh_howto() -> void:
	if _howto_body == null:
		return
	var accent := Cfg.UI_ACCENT.to_html(false)
	var ana := Cfg.ANA.to_html(false)
	var turn := Cfg.C_GOAL_EDGE.to_html(false)
	var kata := Cfg.KATA.to_html(false)
	var move_txt := "the arrow pad, bottom left. Drag anywhere on the chamber to swing the camera round." \
		if _use_touch else "WASD or the arrow keys. Drag to turn the camera."
	var step_txt := "the [b]STEP[/b] pair, bottom right." if _use_touch else "E and Q."
	var turn_txt := "the [b]TURN[/b] pair, bottom right." if _use_touch else "F, and later G."
	var scope_where := "Top left, under the chamber name." if _use_touch else "Bottom left."
	var undo_txt := "[b]UNDO[/b] at the top right takes back any number of moves, and [b]RESET[/b] starts the chamber over." \
		if _use_touch else "Z undoes, without limit. R restarts."
	_howto_body.text = """
You are standing in a three dimensional slice of a four dimensional room. The walls you can see are only the walls [i]in this slice[/i].

[color=#%s]MOVE[/color]  %s

[color=#%s]ANA / KATA[/color]  %s These are the two directions along the axis you cannot see. Stepping along it puts you in a different slice of the same room — a wall in front of you may simply not be there.

[color=#%s]TURN[/color]  %s This rotates a visible axis into the hidden one through a right angle. Everything that was ahead of you becomes hidden, and everything that was hidden sweeps into view. A wall one cell thick becomes a corridor running away from you. You need it because you can only climb along axes you can see.

[color=#%s]THE SCOPE[/color]  %s It is the column you stand in, read along the hidden axis: filled is solid, hollow is open, a bar underneath means there is a floor to land on.

[color=#%s]THE OUTLINES[/color]  Warm outlines are one step ana. Cool outlines are one step kata.

%s Falling out of a chamber only rewinds the step that did it, so nothing is ever lost — take the room apart.
""" % [accent, move_txt, ana, step_txt, turn, turn_txt, accent, scope_where, kata, undo_txt]


func _slider(label: String, value: float, cb: Callable) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 16)
	var l := _lab(label, 18, Cfg.UI_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(190, 0)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(260, 28)
	s.value_changed.connect(cb)
	box.add_child(s)
	return box


func _build_settings() -> Control:
	var p := _pane()
	var v := _column(p, 12)
	v.add_child(_lab("SETTINGS", 40, Cfg.UI_TEXT))
	v.add_child(_slider("sound", Save.setting("sfx", 0.85), func(x):
		Audio.sfx_volume = x
		Save.set_setting("sfx", x)))
	v.add_child(_slider("music", Save.setting("music", 0.55), func(x):
		Audio.set_music_volume(x)
		Save.set_setting("music", x)
		if x > 0.001:
			Audio.music("bed")))
	v.add_child(_slider("ghost slices", float(Save.setting("ghosts", Cfg.GHOST_DEPTH)) / 4.0, func(x):
		var d := int(round(x * 4.0))
		Save.set_setting("ghosts", d)
		if game:
			game.ghost_depth = d))

	var touch_row := HBoxContainer.new()
	touch_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	touch_row.add_theme_constant_override("separation", 10)
	var tl := _lab("on-screen controls", 18, Cfg.UI_TEXT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl.custom_minimum_size = Vector2(190, 0)
	touch_row.add_child(tl)
	for mode in ["auto", "on", "off"]:
		touch_row.add_child(_btn(mode.to_upper(), func():
			Save.set_setting("touch", mode)
			_refresh_touch_mode(), Cfg.UI_ACCENT, 15))
	v.add_child(touch_row)

	var flash_btn := _btn("reduce flashing: toggle", func():
		Save.set_setting("reduce_flash", not Save.setting("reduce_flash", false))
		toast("flashing %s" % ("reduced" if Save.setting("reduce_flash", false) else "normal")), Cfg.UI_DIM, 16)
	flash_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(flash_btn)

	v.add_child(_spacer(14))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("BACK", func(): go(Screen.TITLE), Cfg.UI_DIM))
	row.add_child(_btn("ERASE PROGRESS", func():
		Save.data.records = {}
		Save.save_game()
		toast("progress erased"), Cfg.C_HAZARD_EDGE, 15))
	v.add_child(row)
	return p


func _build_pause() -> Control:
	var p := _pane()
	var v := _column(p)
	v.add_child(_lab("PAUSED", 44, Cfg.UI_TEXT))
	v.add_child(_btn("RESUME", func(): go(Screen.PLAY), Cfg.C_GOAL_EDGE))
	v.add_child(_btn("RESTART CHAMBER", func():
		game.restart()
		go(Screen.PLAY)))
	v.add_child(_btn("CHAMBERS", func(): go(Screen.SELECT)))
	v.add_child(_btn("HOW TO PLAY", func(): go(Screen.HOWTO), Cfg.UI_DIM))
	v.add_child(_btn("TITLE", func(): go(Screen.TITLE), Cfg.UI_DIM))
	return p


func _build_solved() -> Control:
	var p := _pane(0.7)
	var v := _column(p)
	v.add_child(_lab("SOLVED", 52, Cfg.C_GOAL_EDGE))
	_solved_body = _rich(21)
	_solved_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_solved_body.custom_minimum_size = Vector2(560, 120)
	v.add_child(_solved_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("NEXT", func(): main.next(), Cfg.C_GOAL_EDGE, 24))
	row.add_child(_btn("RETRY", func():
		game.restart()
		go(Screen.PLAY)))
	row.add_child(_btn("CHAMBERS", func(): go(Screen.SELECT), Cfg.UI_DIM))
	v.add_child(row)
	return p


func _build_outro() -> Control:
	var p := _pane()
	var v := _column(p)
	v.add_child(_lab("EVERY CHAMBER OPENED", 44, Cfg.C_GOAL_EDGE))
	var r := _rich(20)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.custom_minimum_size = Vector2(700, 0)
	r.text = "You have walked every slice this place has.\n\nThe fourth direction stops being strange somewhere around the twentieth chamber. That is the whole trick — there was never anything to visualise, only somewhere else to step."
	v.add_child(r)
	v.add_child(_spacer(16))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("CHAMBERS", func(): go(Screen.SELECT), Cfg.C_GOAL_EDGE))
	row.add_child(_btn("TITLE", func(): go(Screen.TITLE), Cfg.UI_DIM))
	v.add_child(row)
	return p


func show_solved(moves: int, shards: int, par: int, res: Dictionary) -> void:
	var lines := ["[b]%d[/b] moves" % moves]
	if par > 0:
		if moves <= par:
			lines.append("[color=#%s]optimal[/color]" % Cfg.C_GOAL_EDGE.to_html(false))
		else:
			lines.append("par is [b]%d[/b] — %d to spare" % [par, moves - par])
	if game.level.shard_total > 0:
		lines.append("shards [b]%d[/b] of %d" % [shards, game.level.shard_total])
	if res.get("first", false):
		lines.append("[color=#%s]first crossing[/color]" % Cfg.UI_ACCENT.to_html(false))
	elif res.get("improved", false):
		lines.append("[color=#%s]a new best[/color]" % Cfg.UI_ACCENT.to_html(false))
	_solved_body.text = "\n".join(lines)
	go(Screen.SOLVED)


func show_outro() -> void:
	go(Screen.OUTRO)


func on_level_opened(_i: int) -> void:
	_refresh_stats()


# --- on-screen controls -------------------------------------------------------

func _refresh_touch_mode() -> void:
	var mode: String = Save.setting("touch", "auto")
	if mode == "on":
		_use_touch = true
	elif mode == "off":
		_use_touch = false
	else:
		_use_touch = DisplayServer.is_touchscreen_available() \
			or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	_touch.visible = _use_touch and screen == Screen.PLAY
	if _undo_btn != null:
		_undo_btn.visible = _use_touch
		_reset_btn.visible = _use_touch
	_place_readouts()
	_refresh_howto()


## The scope and the axis readout sit in the bottom-left on desktop — which is
## exactly where the movement pad and a thumb go on a phone. The pad was drawn
## straight over the scope, hiding the one readout that says what is one step
## along the axis you cannot see. On touch they move up under the title.
func _place_readouts() -> void:
	if _axis_lbl == null or _scope == null:
		return
	for c: Control in [_axis_lbl, _scope]:
		c.offset_left = 26
		c.anchor_top = 0.0 if _use_touch else 1.0
		c.anchor_bottom = c.anchor_top
	_axis_lbl.offset_right = 366
	_scope.offset_right = 356
	if _use_touch:
		_axis_lbl.offset_top = 104
		_axis_lbl.offset_bottom = 128
		_scope.offset_top = 134
		_scope.offset_bottom = 180
	else:
		_axis_lbl.offset_top = -96
		_axis_lbl.offset_bottom = -66
		_scope.offset_top = -64
		_scope.offset_bottom = -18
	_scope.queue_redraw()


## A thumb target. The shared button style pads 18px either side for prose
## buttons, which on a 72px square leaves almost no room for a word — so the
## margins come back off here.
func _pad(text: String, cb: Callable, accent: Color, size := 26) -> Button:
	var b := _btn(text, cb, accent, size)
	b.custom_minimum_size = Vector2(PAD_SIZE, PAD_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	for slot in ["normal", "hover", "pressed", "focus"]:
		var sb := b.get_theme_stylebox(slot) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
	return b


func _build_touch() -> void:
	_touch = Control.new()
	_touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_touch)

	# left: a directional pad, resolved against the camera like the keys are
	var pad := GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", 6)
	pad.add_theme_constant_override("v_separation", 6)
	pad.anchor_top = 1.0
	pad.anchor_bottom = 1.0
	pad.offset_left = 24
	pad.offset_top = -(PAD_SIZE * 3 + 6 * 2 + 26)
	pad.offset_bottom = -26
	_touch.add_child(pad)
	pad.add_child(_spacer(0))
	pad.add_child(_pad("↑", func(): game.walk_screen(0, -1), Cfg.UI_ACCENT))
	pad.add_child(_spacer(0))
	pad.add_child(_pad("←", func(): game.walk_screen(-1, 0), Cfg.UI_ACCENT))
	pad.add_child(_pad("⟳", func(): game.spin_camera(1), Cfg.UI_DIM, 22))
	pad.add_child(_pad("→", func(): game.walk_screen(1, 0), Cfg.UI_ACCENT))
	pad.add_child(_spacer(0))
	pad.add_child(_pad("↓", func(): game.walk_screen(0, 1), Cfg.UI_ACCENT))
	pad.add_child(_spacer(0))

	# right: the moves that only exist in four dimensions.
	#
	# These four used to be labelled ANA / KATA / Z↔W / X↔W — the key bindings
	# with the keys filed off. "Z↔W" names the plane of the rotation, which is
	# the one thing a player who has never met a fourth axis cannot possibly
	# read. So the buttons carry a direction and the *group* carries the verb:
	# two captioned pairs say "these step, those turn" before anybody has been
	# told what ana or kata mean.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -(PAD_SIZE * 2 + 6 + 24)
	right.offset_right = -24
	right.offset_top = -(PAD_SIZE * 2 + 4 * 3 + 17 * 2 + 26)
	right.offset_bottom = -26
	_touch.add_child(right)

	right.add_child(_caption("STEP  ·  hidden axis"))
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	r1.alignment = BoxContainer.ALIGNMENT_END
	r1.add_child(_pad("KATA", func(): game.try_shift(-1), Cfg.KATA, 15))
	r1.add_child(_pad("ANA", func(): game.try_shift(1), Cfg.ANA, 15))
	right.add_child(r1)

	right.add_child(_caption("TURN  ·  swap an axis in"))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	r2.alignment = BoxContainer.ALIGNMENT_END
	r2.add_child(_pad("⇅", func(): game.try_rotate(2, 1), Cfg.C_GOAL_EDGE, 30))
	r2.add_child(_pad("⇄", func(): game.try_rotate(0, 1), Cfg.C_FIELD_EDGE, 30))
	right.add_child(r2)


## A group heading over a pair of thumb buttons.
func _caption(text: String) -> Label:
	var l := _lab(text, 12, Cfg.UI_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		if screen == Screen.PLAY:
			go(Screen.PAUSE)
		elif screen == Screen.PAUSE:
			go(Screen.PLAY)
		elif screen != Screen.TITLE:
			go(Screen.TITLE)
		get_viewport().set_input_as_handled()
