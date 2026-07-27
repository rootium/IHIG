class_name Trajectory
extends Node2D
## Draws the ship's predicted coast path as a run of fading dots.
##
## This is the game's aiming interface. While you sit in orbit it shows the arc
## you would get by tapping right now, so choosing the moment to launch becomes
## something you can see rather than something you guess.

var points: PackedVector2Array = PackedVector2Array()
var target: Planet = null
var color: Color = PH.C_RING

const SPACING := 3  ## Draw every Nth simulated step.


func _draw() -> void:
	var n := points.size()
	if n < 2:
		return
	var i := SPACING
	while i < n:
		# Fades with distance: the near end is a commitment, the far end a guess.
		var f := 1.0 - float(i) / float(n)
		draw_circle(points[i], 3.4 * (0.45 + 0.55 * f), Color(color.r, color.g, color.b, 0.25 + 0.7 * f))
		i += SPACING
	if target != null and is_instance_valid(target):
		draw_circle(points[n - 1], 5.0, Color(color.r, color.g, color.b, 0.9))
