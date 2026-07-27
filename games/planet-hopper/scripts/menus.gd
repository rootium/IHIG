class_name Menus
extends CanvasLayer
## Title, pause, game-over and shop screens.
##
## Built in code rather than as scenes so the whole game stays readable as a
## handful of scripts. Only one panel is visible at a time; when all are hidden
## the play field gets the input.

signal play_pressed
signal title_pressed
signal resume_pressed

## Not fully opaque, so the live system behind the menus stays faintly visible.
const DIM := Color(0.035, 0.047, 0.11, 0.88)

var _root: Control
var _title: Control
var _over: Control
var _shop: Control
var _pause: Control

var _credits_labels: Array[Label] = []
var _best_label: Label
var _over_head: Label
var _over_lines: Label
var _shop_list: VBoxContainer
var _tab: String = "ship"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_title = _build_title()
	_over = _build_over()
	_pause = _build_pause()
	_shop = _build_shop()
	show_title()


# --- public ------------------------------------------------------------------

func show_title() -> void:
	_set_panel(_title)
	_refresh_wallet()


func show_pause() -> void:
	_set_panel(_pause)


func show_game_over(reason: String, height: int, planets: int, stars: int, earned: int) -> void:
	_over_head.text = reason
	_over_lines.text = "%d km climbed\n%d orbits reached\n%d stars collected\n\n+%d credits" % [
		height, planets, stars, earned]
	_set_panel(_over)
	_refresh_wallet()


func show_shop() -> void:
	_rebuild_shop()
	_set_panel(_shop)
	_refresh_wallet()


func hide_all() -> void:
	_set_panel(null)


func any_visible() -> bool:
	return _title.visible or _over.visible or _shop.visible or _pause.visible


# --- construction ------------------------------------------------------------

func _build_title() -> Control:
	var panel := _panel()
	var box := _column(panel)

	box.add_child(_label("PLANET\nHOPPER", 66, Color(0.95, 0.97, 1.0)))
	box.add_child(_spacer(8))
	box.add_child(_label("Tap to break orbit. The dotted line shows where you will go.\nHold to steer toward your finger.\n\nGreen worlds hold oxygen. Amber worlds hold fuel.",
		24, Color(0.66, 0.71, 0.86)))
	box.add_child(_spacer(20))

	_best_label = _label("", 28, Color(0.85, 0.88, 1.0))
	box.add_child(_best_label)
	box.add_child(_wallet_label())
	box.add_child(_spacer(24))

	var play := _button("LAUNCH", true)
	play.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(play)

	var shop := _button("SHOP")
	shop.pressed.connect(show_shop)
	box.add_child(shop)
	return panel


func _build_pause() -> Control:
	var panel := _panel()
	var box := _column(panel)
	box.add_child(_label("PAUSED", 56, Color(0.95, 0.97, 1.0)))
	box.add_child(_spacer(24))

	var resume := _button("RESUME", true)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	box.add_child(resume)

	var restart := _button("RESTART")
	restart.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(restart)

	var home := _button("TITLE")
	home.pressed.connect(func() -> void: title_pressed.emit())
	box.add_child(home)
	return panel


func _build_over() -> Control:
	var panel := _panel()
	var box := _column(panel)

	_over_head = _label("", 44, Color(1.0, 0.55, 0.5))
	box.add_child(_over_head)
	box.add_child(_spacer(10))

	_over_lines = _label("", 30, Color(0.85, 0.88, 1.0))
	box.add_child(_over_lines)
	box.add_child(_wallet_label())
	box.add_child(_spacer(24))

	var retry := _button("FLY AGAIN", true)
	retry.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(retry)

	var shop := _button("SHOP")
	shop.pressed.connect(show_shop)
	box.add_child(shop)

	var home := _button("TITLE")
	home.pressed.connect(func() -> void: title_pressed.emit())
	box.add_child(home)
	return panel


func _build_shop() -> Control:
	var panel := _panel()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 28
	box.offset_right = -28
	box.offset_top = 44
	box.offset_bottom = -28
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_label("SHOP", 46, Color(0.95, 0.97, 1.0)))
	box.add_child(_wallet_label())

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	box.add_child(tabs)
	for pair in [["ship", "SHIPS"], ["theme", "WORLDS"]]:
		var b := _button(str(pair[1]))
		b.custom_minimum_size = Vector2(200, 70)
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

	var back := _button("BACK")
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
	var items: Array[Dictionary] = Skins.SHIPS if _tab == "ship" else Skins.THEMES
	for item in items:
		_shop_list.add_child(_shop_row(item))


func _shop_row(item: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.06), 14))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	var prev := Control.new()
	prev.custom_minimum_size = Vector2(100, 84)
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tab == "ship":
		prev.draw.connect(_draw_ship_preview.bind(prev, item))
	else:
		prev.draw.connect(_draw_theme_preview.bind(prev, item))
	h.add_child(prev)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(_label(str(item.name), 29, Color(0.94, 0.96, 1.0), HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(_label(str(item.blurb), 19, Color(0.64, 0.68, 0.82), HORIZONTAL_ALIGNMENT_LEFT))
	h.add_child(text)

	h.add_child(_action_button(item))
	return row


func _action_button(item: Dictionary) -> Button:
	var id := str(item.id)
	var cost := int(item.cost)
	var owned := SaveData.owns(_tab, id)
	var equipped := id == (SaveData.ship_id if _tab == "ship" else SaveData.theme_id)

	var b := _button("", not owned and SaveData.credits >= cost)
	b.custom_minimum_size = Vector2(180, 72)
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


func _draw_ship_preview(c: Control, item: Dictionary) -> void:
	var mid := c.size * 0.5
	c.draw_circle(mid, 36.0, Color(1, 1, 1, 0.05))
	# Nose up, so the silhouettes read as rockets rather than arrows.
	var pts := PackedVector2Array()
	for p in Ship._hull_points(int(item.get("shape", 0))):
		pts.append(mid + (p * 2.0).rotated(-PI * 0.5))
	c.draw_colored_polygon(pts, item.get("hull", Color.WHITE))
	c.draw_circle(mid + Vector2(0, -10), 5.0, item.get("trim", Color.GRAY))


func _draw_theme_preview(c: Control, item: Dictionary) -> void:
	var mid := c.size * 0.5
	c.draw_rect(Rect2(mid - Vector2(44, 36), Vector2(88, 72)), item.get("bg", Color.BLACK))
	c.draw_circle(mid + Vector2(-22, 4), 16.0, item.get("oxygen", Color.GREEN))
	c.draw_circle(mid + Vector2(6, -12), 10.0, item.get("fuel", Color.ORANGE))
	c.draw_circle(mid + Vector2(21, 15), 12.0, item.get("barren", Color.GRAY))
	c.draw_circle(mid + Vector2(26, -21), 3.5, item.get("star", Color.WHITE))


# --- small builders ----------------------------------------------------------

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
	box.offset_left = 40
	box.offset_right = -40
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box


func _label(text: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wallet_label() -> Label:
	var l := _label("", 30, PH.C_STAR)
	_credits_labels.append(l)
	return l


func _style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	return s


## `primary` picks the filled cyan treatment used for the one action a screen
## most wants you to take; everything else is a quieter outline.
func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_size_override("font_size", 30)
	var base := PH.C_RING if primary else Color(1, 1, 1, 0.10)
	var fg := Color(0.04, 0.07, 0.14) if primary else Color(0.92, 0.95, 1.0)
	b.add_theme_stylebox_override("normal", _style(base, 16))
	b.add_theme_stylebox_override("hover", _style(base.lightened(0.12), 16))
	b.add_theme_stylebox_override("pressed", _style(base.darkened(0.18), 16))
	b.add_theme_stylebox_override("disabled", _style(Color(1, 1, 1, 0.05), 16))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.32))
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _refresh_wallet() -> void:
	for l in _credits_labels:
		l.text = "✦ %d credits" % SaveData.credits
	if _best_label != null:
		_best_label.text = "Best: %d km" % SaveData.best_distance


func _set_panel(which: Control) -> void:
	for p in [_title, _over, _shop, _pause]:
		p.visible = p == which
