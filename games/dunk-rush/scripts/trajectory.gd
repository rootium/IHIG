class_name Trajectory
extends Node2D
## Draws the jump you are about to take, as a run of fading dots.
##
## This is the game's aiming interface. Gravity is the only force acting on a
## coasting jump, so these dots are not an estimate — they are exactly where you
## will go unless you choose to float. Getting that guarantee is the reason the
## preview and the player step through the same integrator.

const SPACING := 3  ## Draw every Nth simulated step.

## The colour a blocked line turns. A jump that ends on iron has to be legible
## as a mistake before the thumb lifts, not after.
const C_BLOCKED := Color(1.0, 0.42, 0.38)

var points: PackedVector2Array = PackedVector2Array()
var target: Hoop = null
var blocked: Hoop = null
var color: Color = BD.C_RIM_TARGET

## The pull indicator, drawn at the player while a drag is live.
var show_aim: bool = false
var aim_origin: Vector2 = Vector2.ZERO
var aim_dir: Vector2 = Vector2.UP
var aim_power: float = 0.0


func _draw() -> void:
	_draw_path()
	if show_aim:
		_draw_pull()


func _draw_path() -> void:
	var n := points.size()
	if n < 2:
		return
	# is_instance_valid() alone — a freed Node compares equal to null in
	# GDScript, so a `!= null` guard would not catch one.
	var hits_iron := is_instance_valid(blocked)
	var col := C_BLOCKED if hits_iron else color

	var i := SPACING
	while i < n:
		# Fades with distance: the near end is a commitment, the far end a guess
		# about a court that may have slid by the time you get there.
		var f := 1.0 - float(i) / float(n)
		draw_circle(points[i], 3.2 * (0.45 + 0.55 * f), Color(col.r, col.g, col.b, 0.22 + 0.66 * f))
		i += SPACING

	var end := points[n - 1]
	if hits_iron:
		# A cross where the line meets the rim: this aim clangs.
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(end - d * 9.0, end + d * 9.0, Color(col.r, col.g, col.b, 0.95), 3.5, true)
	elif is_instance_valid(target):
		draw_circle(end, 6.0, Color(col.r, col.g, col.b, 0.9))
		draw_arc(end, 13.0, 0.0, TAU, 18, Color(col.r, col.g, col.b, 0.55), 2.5, true)


## A short arrow out of the player showing where and how hard. The dots already
## say where the jump lands; this says how much of the meter you are spending,
## which is the part that is hard to read off a curve.
func _draw_pull() -> void:
	var len := lerpf(34.0, 96.0, clampf(aim_power, 0.0, 1.0))
	var tip := aim_origin + aim_dir * len
	var col := Color(color.r, color.g, color.b, 0.85)
	draw_line(aim_origin, tip, col, 4.0, true)
	var wing := aim_dir.rotated(PI * 0.82) * 15.0
	draw_line(tip, tip + wing, col, 4.0, true)
	draw_line(tip, tip + aim_dir.rotated(-PI * 0.82) * 15.0, col, 4.0, true)
	# Power ring: fills as the pull lengthens.
	draw_arc(aim_origin, 26.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(aim_power, 0.0, 1.0),
			24, Color(color.r, color.g, color.b, 0.5), 3.0, true)
