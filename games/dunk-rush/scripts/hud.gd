class_name HUD
extends CanvasLayer
## In-run readouts: points, the shot clock that decides the run, the air meter,
## the combo multiplier and collected gold. Laid out for a 720x1280 portrait
## viewport.
##
## The shot clock gets the biggest treatment after the score because it is the
## thing that actually ends runs, and a player who does not notice it running
## down has been failed by the interface rather than by their thumbs.

signal pause_pressed

const MARGIN := 28.0
const BAR_H := 24.0
const BAR_GAP := 9.0
const TOAST_TIME := 1.1
const TOAST_Y := 330.0
const TOAST_RISE := 46.0

var points: int = 0
var clock: float = BD.SHOT_CLOCK
var air: float = 1.0
var combo: int = 0
var multiplier: int = 1
var gold: int = 0
var status: String = ""

var _points: Label
var _clock: Label
var _combo: Label
var _gold: Label
var _status: Label
var _toast: Label
var _bars: Control
var _toast_left: float = 0.0


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_points = _label(root, 44, 62, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
	_clock = _label(root, 50, 54, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)

	var pause := Button.new()
	pause.text = "II"
	pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-MARGIN - 72, 52)
	pause.custom_minimum_size = Vector2(72, 72)
	pause.size = Vector2(72, 72)
	pause.add_theme_font_size_override("font_size", 30)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	root.add_child(pause)

	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bars.position = Vector2(0, 136)
	_bars.custom_minimum_size = Vector2(0, BAR_H * 2 + BAR_GAP)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	root.add_child(_bars)

	# Combo and gold share a row: one reads left, the other right, so neither
	# needs a fixed width guessed against the other's.
	_combo = _label(root, 204, 34, BD.C_RIM_TARGET, HORIZONTAL_ALIGNMENT_LEFT)
	_gold = _label(root, 204, 32, BD.C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)

	_status = _label(root, 254, 24, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER)

	_toast = _label(root, TOAST_Y, 46, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_toast.visible = false


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left = maxf(0.0, _toast_left - delta)
	var f := _toast_left / TOAST_TIME
	_toast.visible = _toast_left > 0.0
	_toast.modulate = Color(1, 1, 1, clampf(f * 1.6, 0.0, 1.0))
	# Drifts upward as it fades, so two dunks in quick succession do not stack
	# into one unreadable smear. Both offsets move together — nudging `position`
	# instead would drag the anchored width along with it.
	var rise := (1.0 - f) * TOAST_RISE
	_toast.offset_top = TOAST_Y - rise
	_toast.offset_bottom = TOAST_Y + 69.0 - rise


## Big centred call-out for the thing that just happened. Kept to a couple of
## words: it has to be readable in the half-second before the next jump.
func toast(text: String, col: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast_left = TOAST_TIME
	_toast.visible = true


func refresh() -> void:
	_points.text = "%d" % points
	# Whole seconds until it gets tight, then tenths — the same way a real shot
	# clock switches over, and for the same reason.
	_clock.text = ("%0.1f" % clock) if clock < BD.CLOCK_WARN else ("%d" % ceili(clock))
	_clock.add_theme_color_override("font_color",
			Color(1.0, 0.35, 0.32) if clock < BD.CLOCK_WARN else Color(1, 1, 1))
	_combo.text = ("x%d  ·  %d in a row" % [multiplier, combo]) if combo > 0 else ""
	# "•" rather than the "●" a gold ball would rather be. Godot's fallback font
	# is barely more than Latin-1 and has no geometric shapes at all — checked
	# with Font.has_char — so ● renders as a missing-glyph box. U+2022 and the
	# U+00B7 above are both in it.
	_gold.text = "•  %d" % gold
	_status.text = status
	_bars.queue_redraw()


func _draw_bars() -> void:
	var w := _bars.size.x - MARGIN * 2.0
	_bar(MARGIN, 0.0, w, clock / BD.SHOT_CLOCK, Color(0.96, 0.55, 0.25), "SHOT CLOCK")
	_bar(MARGIN, BAR_H + BAR_GAP, w, air, Color(0.42, 0.78, 0.95), "AIR")


func _bar(x: float, y: float, w: float, frac: float, col: Color, label: String) -> void:
	var f := clampf(frac, 0.0, 1.0)
	_capsule(x, y, w, BAR_H, Color(1, 1, 1, 0.10))
	if f > 0.001:
		var c := col
		if f < 0.25:
			c = col.lerp(Color(1, 0.3, 0.3), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
		_capsule(x, y, maxf(w * f, BAR_H), BAR_H, c)
	_bars.draw_string(ThemeDB.fallback_font, Vector2(x, y + BAR_H - 6.0),
			label, HORIZONTAL_ALIGNMENT_CENTER, w, 17,
			Color(0.06, 0.07, 0.12, 0.85) if f > 0.35 else Color(1, 1, 1, 0.8))


## Rounded bar: a rect between two end caps. draw_rect has no corner radius.
func _capsule(x: float, y: float, w: float, h: float, col: Color) -> void:
	var r := h * 0.5
	_bars.draw_circle(Vector2(x + r, y + r), r, col)
	_bars.draw_circle(Vector2(x + w - r, y + r), r, col)
	_bars.draw_rect(Rect2(x + r, y, maxf(w - h, 0.0), h), col)


## Every readout spans the full viewport width and positions itself by text
## alignment rather than by a hand-placed x.
##
## Setting `position` on a wide-anchored Control does not do this: the Label
## keeps its content-sized width, so a centred one centres inside a box only as
## wide as its own text and ends up wherever its offset put it — which is how
## the shot clock ended up sitting on top of the score.
func _label(root: Control, top: float, size: int, col: Color, align: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_left = MARGIN
	l.offset_right = -MARGIN
	l.offset_top = top
	l.offset_bottom = top + size * 1.5
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l
