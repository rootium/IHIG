class_name LegendIcon
extends Control
## One board piece, drawn on its own so the how-to screen can name it.
##
## It draws through Pieces, exactly as the board does, which is the point: the
## player is being taught to recognise a shape, so the shape they are shown has
## to be the shape they will meet. The palette and optic come from whatever is
## equipped, so a legend viewed after buying a new colourway teaches that
## colourway rather than the factory one.

enum What { SOURCE, MIRROR, SPLITTER, TARGET, TARGET_WRONG, TARGET_DONE, WALL }

const SIZE := 62.0

var what: int = What.MIRROR
var tint: int = LM.R
var palette: Dictionary = {}
var optic: Dictionary = {}


func _init(p_what: int, p_tint: int = LM.R) -> void:
	what = p_what
	tint = p_tint
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var mid := size * 0.5
	var cell := minf(size.x, size.y)
	match what:
		What.WALL:
			Pieces.wall(self, mid, cell, palette)
		What.MIRROR:
			Pieces.mirror(self, mid, cell, 0, false, optic)
		What.SPLITTER:
			Pieces.mirror(self, mid, cell, 0, true, optic)
		What.SOURCE:
			Pieces.source(self, mid, cell, Grid.E, LM.mix(tint, palette))
		What.TARGET:
			Pieces.target(self, mid, cell, tint, 0, palette)
		What.TARGET_WRONG:
			# Asking for yellow, being fed red — the state the game leans on.
			Pieces.target(self, mid, cell, LM.R | LM.G, LM.R, palette)
		What.TARGET_DONE:
			Pieces.target(self, mid, cell, tint, tint, palette)
