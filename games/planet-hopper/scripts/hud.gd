class_name HUD
extends CanvasLayer
## In-run readouts: height, the two bars that decide the run, collected stars,
## and the pause button. Laid out for a 720x1280 portrait viewport.

signal pause_pressed

const MARGIN := 28.0
const BAR_H := 26.0
const BAR_GAP := 9.0

var oxygen: float = 1.0
var fuel: float = 1.0
var height: int = 0
var stars: int = 0
var status: String = ""

var _score: Label
var _stars: Label
var _status: Label
var _bars: Control


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_score = Label.new()
	_score.position = Vector2(MARGIN, 52)
	_score.add_theme_font_size_override("font_size", 62)
	_score.add_theme_color_override("font_color", Color(1, 1, 1))
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_score)

	var pause := Button.new()
	pause.text = "II"
	pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-MARGIN - 72, 56)
	pause.custom_minimum_size = Vector2(72, 72)
	pause.size = Vector2(72, 72)
	pause.add_theme_font_size_override("font_size", 30)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	root.add_child(pause)

	_stars = Label.new()
	_stars.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stars.position = Vector2(-MARGIN - 260, 70)
	_stars.custom_minimum_size = Vector2(170, 0)
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stars.add_theme_font_size_override("font_size", 36)
	_stars.add_theme_color_override("font_color", PH.C_STAR)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stars)

	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bars.position = Vector2(0, 138)
	_bars.custom_minimum_size = Vector2(0, BAR_H * 2 + BAR_GAP)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	root.add_child(_bars)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.position = Vector2(0, 214)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)


func refresh() -> void:
	_score.text = "%02d" % height
	_stars.text = "•  %d" % stars
	_status.text = status
	_bars.queue_redraw()


func _draw_bars() -> void:
	var w := _bars.size.x - MARGIN * 2.0
	_bar(MARGIN, 0.0, w, oxygen, Color(0.42, 0.83, 0.55), "OXYGEN")
	_bar(MARGIN, BAR_H + BAR_GAP, w, fuel, PH.C_RING, "FUEL")


func _bar(x: float, y: float, w: float, frac: float, col: Color, label: String) -> void:
	var f := clampf(frac, 0.0, 1.0)
	_capsule(x, y, w, BAR_H, Color(1, 1, 1, 0.10))
	if f > 0.001:
		# Flashes red as it runs down — the oxygen bar is the run's real clock.
		var c := col
		if f < 0.25:
			c = col.lerp(Color(1, 0.3, 0.3), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
		_capsule(x, y, maxf(w * f, BAR_H), BAR_H, c)
	_bars.draw_string(ThemeDB.fallback_font, Vector2(x, y + BAR_H - 6.0),
		"%s  %d%%" % [label, roundi(f * 100.0)], HORIZONTAL_ALIGNMENT_CENTER, w, 18,
		Color(0.06, 0.08, 0.16, 0.85) if f > 0.35 else Color(1, 1, 1, 0.8))


## Rounded bar: a rect between two end caps. draw_rect has no corner radius.
func _capsule(x: float, y: float, w: float, h: float, col: Color) -> void:
	var r := h * 0.5
	_bars.draw_circle(Vector2(x + r, y + r), r, col)
	_bars.draw_circle(Vector2(x + w - r, y + r), r, col)
	_bars.draw_rect(Rect2(x + r, y, maxf(w - h, 0.0), h), col)
