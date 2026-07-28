class_name HUD
extends CanvasLayer
## In-run readouts and the three things you can do that are not tapping a piece.
##
## The tap counter is the only pressure the game applies: nothing is timed, and
## nothing is lost, so par is what turns "I solved it" into "I solved it well".

signal reset_pressed
signal hint_pressed
signal quit_pressed

var level: int = 1
var taps: int = 0
var par: int = 1
var hint_ready: bool = false

var _level: Label
var _taps: Label
var _credits: Label
var _hint: Button


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var accent: Color = LM.C_INK

	_level = UI.label("", 44, accent, HORIZONTAL_ALIGNMENT_LEFT, false)
	_level.position = Vector2(LM.PAD, 46)
	root.add_child(_level)

	_taps = UI.label("", 28, Color(accent.r, accent.g, accent.b, 0.62),
		HORIZONTAL_ALIGNMENT_LEFT, false)
	_taps.position = Vector2(LM.PAD, 102)
	root.add_child(_taps)

	_credits = UI.label("", 30, Color(1.0, 0.84, 0.36), HORIZONTAL_ALIGNMENT_RIGHT, false)
	_credits.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_credits.position = Vector2(-LM.PAD - 300, 54)
	_credits.custom_minimum_size = Vector2(300, 0)
	root.add_child(_credits)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = LM.PAD
	bar.offset_right = -LM.PAD
	bar.offset_top = -UI.BUTTON_H - 40.0
	bar.offset_bottom = -40.0
	bar.add_theme_constant_override("separation", 14)
	root.add_child(bar)

	for spec in [["MENU", "quit"], ["RESET", "reset"], ["HINT  %d" % LM.HINT_COST, "hint"]]:
		var b := UI.button(str(spec[0]), accent)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		match spec[1]:
			"quit":
				b.pressed.connect(func() -> void: quit_pressed.emit())
			"reset":
				b.pressed.connect(func() -> void: reset_pressed.emit())
			_:
				b.pressed.connect(func() -> void: hint_pressed.emit())
				_hint = b
		bar.add_child(b)


func refresh() -> void:
	_level.text = "LEVEL %d" % level
	_taps.text = "%d taps   ·   par %d" % [taps, par]
	_credits.text = "✦ %d" % SaveData.credits
	_hint.disabled = not hint_ready or SaveData.credits < LM.HINT_COST
