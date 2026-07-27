class_name Menus
extends CanvasLayer
## Title, game-over and shop screens.
##
## Built in code rather than as scenes so the whole game stays readable as a
## handful of scripts. Only one panel is visible at a time; when all are hidden
## the play field gets the input.

signal play_pressed
signal title_pressed

const DIM := Color(0.03, 0.035, 0.08, 0.88)

var _root: Control
var _title: Control
var _over: Control
var _shop: Control

var _credits_labels: Array[Label] = []
var _best_label: Label
var _over_lines: Label
var _over_head: Label
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
	_shop = _build_shop()
	show_title()


# --- public ------------------------------------------------------------------

func show_title() -> void:
	_set_panel(_title)
	_refresh_wallet()


func show_game_over(reason: String, distance: int, planets: int, earned: int) -> void:
	_over_head.text = reason
	_over_lines.text = "%d km travelled\n%d orbits reached\n\n+%d credits" % [distance, planets, earned]
	_set_panel(_over)
	_refresh_wallet()


func show_shop() -> void:
	_rebuild_shop()
	_set_panel(_shop)
	_refresh_wallet()


func hide_all() -> void:
	_set_panel(null)


func any_visible() -> bool:
	return _title.visible or _over.visible or _shop.visible


# --- construction ------------------------------------------------------------

func _build_title() -> Control:
	var panel := _panel()
	var box := _column(panel)

	box.add_child(_label("PLANET HOPPER", 62, Color(0.92, 0.95, 1.0)))
	box.add_child(_label("Tap to break orbit. Hold to burn toward your finger.\nGreen worlds hold oxygen, amber ones hold fuel.\nMoons, meteorites and black holes do not forgive.",
		24, Color(0.72, 0.76, 0.9)))
	box.add_child(_spacer(18))

	_best_label = _label("", 28, Color(0.85, 0.88, 1.0))
	box.add_child(_best_label)
	box.add_child(_wallet_label())
	box.add_child(_spacer(24))

	var play := _button("LAUNCH")
	play.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(play)

	var shop := _button("SHOP")
	shop.pressed.connect(show_shop)
	box.add_child(shop)
	return panel


func _build_over() -> Control:
	var panel := _panel()
	var box := _column(panel)

	_over_head = _label("", 46, Color(1.0, 0.55, 0.5))
	box.add_child(_over_head)
	box.add_child(_spacer(10))

	_over_lines = _label("", 30, Color(0.85, 0.88, 1.0))
	box.add_child(_over_lines)
	box.add_child(_wallet_label())
	box.add_child(_spacer(24))

	var retry := _button("FLY AGAIN")
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
	box.offset_left = 30
	box.offset_right = -30
	box.offset_top = 40
	box.offset_bottom = -30
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_label("SHOP", 46, Color(0.92, 0.95, 1.0)))
	box.add_child(_wallet_label())

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	box.add_child(tabs)
	for pair in [["ship", "SHIPS"], ["theme", "WORLDS"]]:
		var b := _button(str(pair[1]))
		b.custom_minimum_size = Vector2(200, 72)
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
		b.modulate = Color(1, 1, 1) if key == _tab else Color(0.6, 0.62, 0.7)

	for child in _shop_list.get_children():
		child.queue_free()
	var items: Array[Dictionary] = Skins.SHIPS if _tab == "ship" else Skins.THEMES
	for item in items:
		_shop_list.add_child(_shop_row(item))


func _shop_row(item: Dictionary) -> Control:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)
	row.add_theme_stylebox_override("panel", style)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	var prev := Control.new()
	prev.custom_minimum_size = Vector2(104, 88)
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tab == "ship":
		prev.draw.connect(_draw_ship_preview.bind(prev, item))
	else:
		prev.draw.connect(_draw_theme_preview.bind(prev, item))
	h.add_child(prev)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(_label(str(item.name), 30, Color(0.94, 0.96, 1.0), HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(_label(str(item.blurb), 20, Color(0.68, 0.72, 0.86), HORIZONTAL_ALIGNMENT_LEFT))
	h.add_child(text)

	h.add_child(_action_button(item))
	return row


func _action_button(item: Dictionary) -> Button:
	var id := str(item.id)
	var cost := int(item.cost)
	var owned := SaveData.owns(_tab, id)
	var equipped := id == (SaveData.ship_id if _tab == "ship" else SaveData.theme_id)

	var b := _button("")
	b.custom_minimum_size = Vector2(190, 76)
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
	c.draw_circle(mid, 38.0, Color(1, 1, 1, 0.05))
	var pts := PackedVector2Array()
	for p in Ship._hull_points(int(item.get("shape", 0))):
		pts.append(mid + p * 2.2)
	c.draw_colored_polygon(pts, item.get("hull", Color.WHITE))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), item.get("trim", Color.GRAY), 2.0, true)


func _draw_theme_preview(c: Control, item: Dictionary) -> void:
	var mid := c.size * 0.5
	c.draw_rect(Rect2(mid - Vector2(46, 38), Vector2(92, 76)), item.get("bg", Color.BLACK))
	c.draw_circle(mid + Vector2(-24, 4), 17.0, item.get("oxygen", Color.GREEN))
	c.draw_circle(mid + Vector2(6, -12), 11.0, item.get("fuel", Color.ORANGE))
	c.draw_circle(mid + Vector2(22, 16), 13.0, item.get("barren", Color.GRAY))
	c.draw_circle(mid + Vector2(28, -22), 4.0, item.get("star", Color.WHITE))


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
	var l := _label("", 30, Color(1.0, 0.86, 0.45))
	_credits_labels.append(l)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)
	b.add_theme_font_size_override("font_size", 30)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _refresh_wallet() -> void:
	for l in _credits_labels:
		l.text = "%d credits" % SaveData.credits
	if _best_label != null:
		_best_label.text = "Best: %d km" % SaveData.best_distance


func _set_panel(which: Control) -> void:
	for p in [_title, _over, _shop]:
		p.visible = p == which
