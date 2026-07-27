class_name HUD
extends CanvasLayer
## In-run readouts: the two bars that decide the run, plus distance and a
## one-line status message.

const BAR_W := 300.0
const BAR_H := 20.0

var oxygen: float = 1.0
var fuel: float = 1.0
var distance: int = 0
var status: String = ""

var _bars: Control
var _dist: Label
var _status: Label


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_bars = Control.new()
	_bars.position = Vector2(28, 30)
	_bars.custom_minimum_size = Vector2(BAR_W, BAR_H * 2 + 14)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	root.add_child(_bars)

	_dist = Label.new()
	_dist.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dist.position = Vector2(-250, 30)
	_dist.custom_minimum_size = Vector2(220, 0)
	_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dist.add_theme_font_size_override("font_size", 34)
	_dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dist)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.position = Vector2(-260, 128)
	_status.custom_minimum_size = Vector2(520, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 26)
	_status.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)


func refresh() -> void:
	_dist.text = "%d km" % distance
	_status.text = status
	_bars.queue_redraw()


func _draw_bars() -> void:
	_bar(0, oxygen, Color(0.35, 0.85, 0.6), "O2")
	_bar(BAR_H + 14, fuel, Color(0.95, 0.7, 0.28), "FUEL")


func _bar(y: float, frac: float, col: Color, label: String) -> void:
	var box := Rect2(0, y, BAR_W, BAR_H)
	_bars.draw_rect(box, Color(1, 1, 1, 0.10))
	var f := clampf(frac, 0.0, 1.0)
	# Bars flash when they are about to run out — the oxygen one especially.
	var c := col
	if f < 0.25:
		c = col.lerp(Color(1, 0.25, 0.25), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	_bars.draw_rect(Rect2(0, y, BAR_W * f, BAR_H), c)
	_bars.draw_rect(box, Color(1, 1, 1, 0.25), false, 2.0)
	_bars.draw_string(ThemeDB.fallback_font, Vector2(BAR_W + 12, y + BAR_H - 3),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75))
