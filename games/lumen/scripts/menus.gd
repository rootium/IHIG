class_name Menus
extends CanvasLayer
## Title, level-cleared and shop screens.
##
## Built in code rather than as scenes so the whole game stays readable as a
## handful of scripts. Only one panel is visible at a time; when all are hidden
## the board gets the input.

signal play_pressed
signal next_pressed
signal replay_pressed
signal title_pressed

## Not fully opaque, so the solved board behind the title stays visible.
const DIM := Color(0.02, 0.022, 0.045, 0.86)

var accent: Color = LM.C_INK
## The equipped skin, so the legend teaches the pieces as they actually look.
var palette: Dictionary = {}
var optic: Dictionary = {}

var _root: Control
var _title: Control
var _cleared: Control
var _shop: Control
var _howto: Control
var _legend_icons: Array[LegendIcon] = []

var _credit_labels: Array[Label] = []
var _progress: Label
var _play: Button
var _cleared_head: Label
var _cleared_stars: StarRow
var _cleared_lines: Label
var _shop_list: VBoxContainer
var _tab: String = "optic"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_title = _build_title()
	_cleared = _build_cleared()
	_shop = _build_shop()
	_howto = _build_howto()
	show_title()


# --- public ------------------------------------------------------------------

func show_title() -> void:
	_progress.text = "%d levels cleared   ·   %d stars" % [SaveData.cleared, SaveData.stars]
	_play.text = "PLAY  ·  LEVEL %d" % SaveData.level
	_set_panel(_title)
	_refresh_wallet()


func show_cleared(level: int, taps: int, par: int, result: Dictionary) -> void:
	var stars := int(result.stars)
	_cleared_head.text = "LEVEL %d" % level
	_cleared_stars.set_rating(stars)
	_cleared_lines.text = "%d %s against a par of %d\n\n+%d credits%s" % [
		taps, "tap" if taps == 1 else "taps", par,
		int(result.earned), "" if bool(result.fresh) else "  (replay)"]
	_set_panel(_cleared)
	_refresh_wallet()


func show_howto() -> void:
	_set_panel(_howto)


## Called when the equipped skin changes, so the legend keeps teaching the
## pieces as they currently look rather than as they looked at startup.
func set_skin(p_palette: Dictionary, p_optic: Dictionary) -> void:
	palette = p_palette
	optic = p_optic
	for ic in _legend_icons:
		ic.palette = palette
		ic.optic = optic
		ic.queue_redraw()


func show_shop() -> void:
	_rebuild_shop()
	_set_panel(_shop)
	_refresh_wallet()


func hide_all() -> void:
	_set_panel(null)


func any_visible() -> bool:
	return _title.visible or _cleared.visible or _shop.visible


# --- construction ------------------------------------------------------------

func _build_title() -> Control:
	var panel := _panel()
	var box := _column(panel)

	box.add_child(UI.label("LUMEN", 78, Color(0.96, 0.97, 1.0)))
	box.add_child(UI.spacer(6))
	box.add_child(UI.label(
		"Tap a mirror to turn it. Light every ring in the colour it is asking for.",
		23, Color(0.64, 0.68, 0.84)))
	box.add_child(UI.spacer(18))

	_progress = UI.label("", 26, Color(0.85, 0.88, 1.0))
	box.add_child(_progress)
	box.add_child(_wallet_label())
	box.add_child(UI.spacer(22))

	_play = UI.button("PLAY", accent, true)
	_play.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(_play)

	var how := UI.button("HOW TO PLAY", accent)
	how.pressed.connect(show_howto)
	box.add_child(how)

	var shop := UI.button("SHOP", accent)
	shop.pressed.connect(show_shop)
	box.add_child(shop)
	return panel


func _build_cleared() -> Control:
	var panel := _panel()
	var box := _column(panel)

	_cleared_head = UI.label("", 46, Color(0.96, 0.97, 1.0))
	box.add_child(_cleared_head)

	_cleared_stars = StarRow.new()
	box.add_child(_cleared_stars)
	box.add_child(UI.spacer(8))

	_cleared_lines = UI.label("", 28, Color(0.85, 0.88, 1.0))
	box.add_child(_cleared_lines)
	box.add_child(_wallet_label())
	box.add_child(UI.spacer(22))

	var next := UI.button("NEXT LEVEL", accent, true)
	next.pressed.connect(func() -> void: next_pressed.emit())
	box.add_child(next)

	var again := UI.button("REPLAY", accent)
	again.pressed.connect(func() -> void: replay_pressed.emit())
	box.add_child(again)

	var shop := UI.button("SHOP", accent)
	shop.pressed.connect(show_shop)
	box.add_child(shop)

	var home := UI.button("TITLE", accent)
	home.pressed.connect(func() -> void: title_pressed.emit())
	box.add_child(home)
	return panel


func _build_shop() -> Control:
	var panel := _panel()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 26
	box.offset_right = -26
	box.offset_top = 44
	box.offset_bottom = -28
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(UI.label("SHOP", 44, Color(0.96, 0.97, 1.0)))
	box.add_child(_wallet_label())

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	box.add_child(tabs)
	for pair in [["optic", "OPTICS"], ["palette", "PALETTES"]]:
		var b := UI.button(str(pair[1]), accent)
		b.custom_minimum_size = Vector2(220, 68)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_select_tab.bind(str(pair[0])))
		tabs.add_child(b)
		_tab_buttons[str(pair[0])] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_shop_list)

	var back := UI.button("BACK", accent)
	back.pressed.connect(func() -> void: title_pressed.emit())
	box.add_child(back)
	return panel


# --- shop contents -----------------------------------------------------------

func _select_tab(tab: String) -> void:
	_tab = tab
	_rebuild_shop()


func _rebuild_shop() -> void:
	for key in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.modulate = Color(1, 1, 1) if key == _tab else Color(0.55, 0.58, 0.68)

	for child in _shop_list.get_children():
		child.queue_free()
	for item in (Skins.OPTICS if _tab == "optic" else Skins.PALETTES):
		_shop_list.add_child(_shop_row(item))


func _shop_row(item: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UI.style(Color(1, 1, 1, 0.055), 14))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	var prev := Control.new()
	prev.custom_minimum_size = Vector2(104, 82)
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tab == "optic":
		prev.draw.connect(_draw_optic_preview.bind(prev, item))
	else:
		prev.draw.connect(_draw_palette_preview.bind(prev, item))
	h.add_child(prev)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UI.label(str(item.name), 28, Color(0.94, 0.96, 1.0), HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(UI.label(str(item.blurb), 18, Color(0.62, 0.66, 0.80), HORIZONTAL_ALIGNMENT_LEFT))
	h.add_child(text)

	h.add_child(_action_button(item))
	return row


func _action_button(item: Dictionary) -> Button:
	var id := str(item.id)
	var cost := int(item.cost)
	var owned := SaveData.owns(_tab, id)
	var equipped := id == (SaveData.optic_id if _tab == "optic" else SaveData.palette_id)

	var b := UI.button("", accent, not owned and SaveData.credits >= cost)
	b.custom_minimum_size = Vector2(172, 70)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	if equipped:
		b.text = "EQUIPPED"
		b.disabled = true
	elif owned:
		b.text = "EQUIP"
		b.pressed.connect(func() -> void:
			SaveData.equip(_tab, id)
			_rebuild_shop())
	else:
		b.text = "%d cr" % cost
		b.disabled = SaveData.credits < cost
		b.pressed.connect(func() -> void:
			if SaveData.buy(_tab, id, cost):
				SaveData.equip(_tab, id)
			_rebuild_shop()
			_refresh_wallet())
	return b


## A beam bouncing off a mirror, drawn with the optic it is selling.
func _draw_optic_preview(c: Control, item: Dictionary) -> void:
	var mid := c.size * 0.5
	var core: float = maxf(3.0 * float(item.get("core", 1.0)), 1.5)
	var pts := PackedVector2Array([
		mid + Vector2(-38, 16), mid + Vector2(6, 16), mid + Vector2(6, 16), mid + Vector2(6, -22)])
	var col := Color(0.45, 0.85, 1.0)
	c.draw_multiline(pts, Color(col.r, col.g, col.b, 0.13), core * float(item.get("glow", 3.4)), true)
	c.draw_multiline(pts, Color(col.r, col.g, col.b, 0.92), core, true)
	var hot: float = item.get("hot", 0.0)
	if hot > 0.0:
		c.draw_multiline(pts, Color(1, 1, 1, hot), core * 0.34, true)
	c.draw_line(mid + Vector2(-8, 30), mid + Vector2(20, 2), item.get("piece", Color.WHITE), 6.0, true)


func _draw_palette_preview(c: Control, item: Dictionary) -> void:
	var mid := c.size * 0.5
	c.draw_rect(Rect2(mid - Vector2(44, 34), Vector2(88, 68)), item.get("board", Color.BLACK))
	var y := mid.y - 20.0
	for key in ["r", "g", "b"]:
		var col: Color = item.get(key, Color.WHITE)
		c.draw_line(Vector2(mid.x - 34, y), Vector2(mid.x + 34, y),
			Color(col.r, col.g, col.b, 0.16), 12.0, true)
		c.draw_line(Vector2(mid.x - 34, y), Vector2(mid.x + 34, y), col, 3.5, true)
		y += 20.0


# --- small builders ----------------------------------------------------------

# --- how to play -------------------------------------------------------------

## The screen the game was missing.
##
## Lumen's rules fit in two sentences, which is exactly why they were only ever
## two sentences on the title screen. But the pieces are a vocabulary, and
## nothing taught it: a player who cannot tell a splitter from a mirror, or read
## the dot inside a ring, is not solving the puzzle — they are guessing which
## diagonal to tap and waiting to see what happens.
func _build_howto() -> Control:
	var panel := _panel()
	# The other screens let the solved board glow through, which is nice to look
	# at. Here it reads as clutter behind the very shapes being explained.
	panel.color = Color(0.02, 0.022, 0.045, 0.97)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 26
	box.offset_right = -26
	box.offset_top = 44
	box.offset_bottom = -28
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(UI.label("HOW TO PLAY", 44, Color(0.96, 0.97, 1.0)))
	box.add_child(UI.label("Light every ring in the colour it is asking for.",
		24, Color(0.85, 0.88, 1.0)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	list.add_child(_legend_row(LegendIcon.What.SOURCE, LM.R, "Source",
		"Fires a beam. The nozzle points the way it fires, and its colour is what it emits."))
	list.add_child(_legend_row(LegendIcon.What.MIRROR, LM.R, "Mirror",
		"Tap it to turn it. This is the only move in the game."))
	list.add_child(_legend_row(LegendIcon.What.SPLITTER, LM.R, "Splitter",
		"Half the light carries straight on, half turns. Tapping turns the half that turns."))
	list.add_child(_legend_row(LegendIcon.What.TARGET, LM.B, "Target",
		"A ring waiting for light, drawn in the colour it is asking for."))
	list.add_child(_legend_row(LegendIcon.What.TARGET_WRONG, LM.R, "Wrong colour",
		"Light is arriving, but not the light it wants. The dot is what is actually turning up — the only clue a mixing puzzle can give you."))
	list.add_child(_legend_row(LegendIcon.What.TARGET_DONE, LM.G, "Lit",
		"Satisfied, and it stays that way."))
	list.add_child(_legend_row(LegendIcon.What.WALL, LM.R, "Wall",
		"Light stops here."))

	list.add_child(UI.spacer(10))
	list.add_child(UI.label("TWO BEAMS THAT MEET, MIX", 26, Color(0.96, 0.97, 1.0)))
	list.add_child(_mix_row())
	list.add_child(UI.label(
		"Red and green make yellow, and a ring asking for yellow will not take anything else. Working out which two beams have to arrive together is most of the game.",
		20, Color(0.64, 0.68, 0.84)))

	list.add_child(UI.spacer(10))
	list.add_child(UI.label(
		"Nothing is timed and nothing can be lost. RESET puts every piece back where it started. HINT sets one piece correctly, for credits and a tap. Par is simply the number of taps a perfect solve takes.",
		20, Color(0.64, 0.68, 0.84)))

	var begin := UI.button("PLAY", accent, true)
	begin.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(begin)

	var back := UI.button("TITLE", accent)
	back.pressed.connect(func() -> void: title_pressed.emit())
	box.add_child(back)
	return panel


func _legend_row(what: int, tint: int, heading: String, desc: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_icon(what, tint))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 2)
	text.add_child(UI.label(heading, 24, Color(0.93, 0.95, 1.0), HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(UI.label(desc, 19, Color(0.64, 0.68, 0.84), HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(text)
	return row


func _icon(what: int, tint: int) -> LegendIcon:
	var ic := LegendIcon.new(what, tint)
	ic.palette = palette
	ic.optic = optic
	_legend_icons.append(ic)
	return ic


## Red and green arriving at one ring. The rule is the hardest thing in the game
## to state in words and the easiest to show, so it gets shown.
func _mix_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(_icon(LegendIcon.What.SOURCE, LM.R))
	row.add_child(UI.label("+", 30, Color(0.64, 0.68, 0.84), HORIZONTAL_ALIGNMENT_CENTER, false))
	row.add_child(_icon(LegendIcon.What.SOURCE, LM.G))
	row.add_child(UI.label("=", 30, Color(0.64, 0.68, 0.84), HORIZONTAL_ALIGNMENT_CENTER, false))
	row.add_child(_icon(LegendIcon.What.TARGET_DONE, LM.R | LM.G))
	return row


func _panel() -> Control:
	var p := ColorRect.new()
	p.color = DIM
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	_root.add_child(p)
	return p


func _column(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 38
	box.offset_right = -38
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box


func _wallet_label() -> Label:
	var l := UI.label("", 28, Color(1.0, 0.84, 0.36))
	_credit_labels.append(l)
	return l


func _refresh_wallet() -> void:
	for l in _credit_labels:
		l.text = "•  %d credits" % SaveData.credits


func _set_panel(which: Control) -> void:
	for p in [_title, _cleared, _shop, _howto]:
		p.visible = p == which
