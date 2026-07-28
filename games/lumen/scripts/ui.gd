class_name UI
extends RefCounted
## The handful of Control builders the HUD and the menus both need.
##
## Everything on screen is built in code rather than as scenes, so this exists
## purely so the two screens cannot drift apart in how a button looks.

const BUTTON_H := 84.0


static func style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(12)
	return s


## `accent` is the palette's ink colour; `primary` picks the filled treatment
## used for the one action a screen most wants you to take, and everything else
## is a quieter outline.
static func button(text: String, accent: Color, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_H)
	b.add_theme_font_size_override("font_size", 28)
	var base := accent if primary else Color(1, 1, 1, 0.09)
	var fg := Color(0.05, 0.05, 0.09) if primary else accent
	b.add_theme_stylebox_override("normal", style(base, 16))
	b.add_theme_stylebox_override("hover", style(base.lightened(0.12), 16))
	b.add_theme_stylebox_override("pressed", style(base.darkened(0.18), 16))
	b.add_theme_stylebox_override("disabled", style(Color(1, 1, 1, 0.045), 16))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.28))
	return b


## `wrap` off for anything positioned by hand rather than sitting in a container.
## A wrapping Label reports a minimum width of nearly nothing, so a free-floating
## one collapses and breaks its text one character per line.
static func label(text: String, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
