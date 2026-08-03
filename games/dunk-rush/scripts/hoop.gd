class_name Hoop
extends Node2D
## One basket: a rim you can dunk through, a backboard you can bank off, and a
## net that is purely decorative.
##
## `position` is the centre of the rim, so everything else — the scoring band,
## the backboard rect, the hang point — is derived from it. Sliding hoops move
## that point, and the player hanging on one moves with it.
##
## The rim is divided into three bands, widest to narrowest:
##   |dx| <= swish_half()  dead centre, worth an extra point
##   |dx| <= score_half()  a clean dunk
##   |dx| <= rim_half      the iron — clangs you off and breaks your combo
## Keeping them nested like this means there is no gap a player can fall through
## that is neither a score nor a clang.

var rim_half: float = BD.RIM_HALF
var side: float = 1.0            ## Which side the backboard and pole are on.
var theme: Dictionary = {}

var slide_speed: float = 0.0     ## 0 for a fixed hoop.
var slide_span: float = 0.0      ## Half the travel, in px, around home_x.
var home_x: float = 0.0

var is_target: bool = false      ## The preview says this is where we land.
var is_host: bool = false        ## We are hanging on it right now.
var scored: bool = false         ## Already dunked on this run — no repeat points.

var _phase: float = 0.0
var _flash: float = 0.0          ## Fades after a score, for the net pop.


func setup(p_rim_half: float, p_side: float, p_slide: float, p_span: float,
		rng: RandomNumberGenerator) -> void:
	rim_half = p_rim_half
	side = p_side
	slide_speed = p_slide
	slide_span = p_span
	home_x = position.x
	_phase = rng.randf() * TAU


func step(delta: float) -> void:
	if slide_speed > 0.0 and slide_span > 0.0:
		_phase += (slide_speed / maxf(slide_span, 1.0)) * delta
		position.x = home_x + sin(_phase) * slide_span
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.6)
	queue_redraw()


func celebrate() -> void:
	_flash = 1.0
	scored = true


## Half-width of the band that counts as a dunk rather than iron.
func score_half() -> float:
	return rim_half * BD.SCORE_HALF_MULT


func swish_half() -> float:
	return rim_half * BD.SWISH_HALF_MULT


## Where the player hangs after dunking.
func hang_point() -> Vector2:
	return position + Vector2(0.0, BD.HANG_DROP)


## Current sideways speed of the rim. A player hanging on it carries this into
## their next jump, which is what makes the timing of a launch matter.
func slide_velocity() -> float:
	if slide_speed <= 0.0 or slide_span <= 0.0:
		return 0.0
	return cos(_phase) * slide_speed


## Nearest point on the iron to `p`. The rim is a segment, so this is a clamp
## on x and nothing else.
func rim_closest_point(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, position.x - rim_half, position.x + rim_half), position.y)


## The backboard, in world coordinates. Its inner face is flush with the end of
## the rim, so a ball banked off it drops onto the scoring band rather than
## outside it.
func board_rect() -> Rect2:
	var inner := position.x + side * rim_half
	var outer := inner + side * BD.BOARD_T
	return Rect2(Vector2(minf(inner, outer), position.y - BD.BOARD_H),
			Vector2(BD.BOARD_T, BD.BOARD_H + 8.0))


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	var rim_col: Color = theme.get("rim", BD.C_RIM)
	var board_col: Color = theme.get("board", BD.C_BOARD)
	var net_col: Color = theme.get("net", BD.C_NET)

	_draw_pole(board_col)
	_draw_board(board_col)
	_draw_net(net_col)
	_draw_rim(rim_col)
	_draw_marker(rim_col)


func _draw_pole(col: Color) -> void:
	# Runs from the back of the board out past the edge of the column, so the
	# basket reads as mounted on something rather than floating.
	var back := side * (rim_half + BD.BOARD_T)
	var out := side * (rim_half + 190.0)
	var y := -BD.BOARD_H * 0.55
	draw_line(Vector2(back, y), Vector2(out, y), Color(col.r, col.g, col.b, 0.22), 9.0)


func _draw_board(col: Color) -> void:
	var r := board_rect()
	r.position -= position  # board_rect() is world space; _draw is node-local.
	draw_rect(r, Color(col.r, col.g, col.b, 0.20))
	draw_rect(r, Color(col.r, col.g, col.b, 0.75), false, 3.0)

	# The shooter's square, the one marking every backboard has.
	var inner := side * rim_half
	var w := BD.BOARD_T
	var sq := Rect2(Vector2(minf(inner, inner + side * w), -BD.BOARD_H * 0.62),
			Vector2(w, BD.BOARD_H * 0.42))
	draw_rect(sq, Color(col.r, col.g, col.b, 0.55), false, 2.5)


func _draw_net(col: Color) -> void:
	var strands := 7
	for i in strands + 1:
		var f := float(i) / float(strands)
		var top := Vector2(lerpf(-rim_half, rim_half, f), 0.0)
		# The net tapers inward, and snaps taut for a moment after a dunk.
		var pinch := lerpf(0.42, 0.16, _flash)
		var bottom := Vector2(top.x * pinch, BD.NET_H * (1.0 + 0.25 * _flash))
		draw_line(top, bottom, Color(col.r, col.g, col.b, 0.30 + 0.35 * _flash), 1.8, true)
	# Two hoops of cord around the net.
	for band: float in [0.45, 0.8]:
		var y := BD.NET_H * band * (1.0 + 0.25 * _flash)
		var half := lerpf(rim_half, rim_half * lerpf(0.42, 0.16, _flash), band)
		draw_line(Vector2(-half, y), Vector2(half, y), Color(col.r, col.g, col.b, 0.22), 1.5, true)


func _draw_rim(col: Color) -> void:
	var c := col
	if is_target:
		c = theme.get("rim_target", BD.C_RIM_TARGET)
	if _flash > 0.0:
		c = c.lerp(Color(1, 1, 1), 0.6 * _flash)

	draw_line(Vector2(-rim_half, 0), Vector2(rim_half, 0), c, BD.RIM_THICK, true)
	# End caps, so the iron reads as round bar rather than a flat bar.
	draw_circle(Vector2(-rim_half, 0), BD.RIM_THICK * 0.5, c)
	draw_circle(Vector2(rim_half, 0), BD.RIM_THICK * 0.5, c)


## The aim preview highlights the rim it predicts you will reach. A bright pair
## of ticks over the scoring band tells you not just *which* hoop but whether
## you are lined up with the part of it that scores.
func _draw_marker(col: Color) -> void:
	if is_host:
		return
	if not is_target:
		draw_line(Vector2(-score_half(), -9), Vector2(score_half(), -9),
				Color(0.45, 0.48, 0.58, 0.35), 2.0, true)
		return

	var t: Color = theme.get("rim_target", BD.C_RIM_TARGET)
	var sh := score_half()
	draw_line(Vector2(-sh, -9), Vector2(sh, -9), Color(t.r, t.g, t.b, 0.9), 3.0, true)
	for x: float in [-sh, sh]:
		draw_line(Vector2(x, -16), Vector2(x, -2), Color(t.r, t.g, t.b, 0.9), 3.0)
	if scored:
		return
	# A soft halo, pulsing, on a rim that is still worth points.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	draw_arc(Vector2.ZERO, rim_half + 26.0, PI, TAU, 22,
			Color(t.r, t.g, t.b, 0.16 + 0.16 * pulse), 3.0, true)
