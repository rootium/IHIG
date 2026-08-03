class_name Flight
extends RefCounted
## One point in motion through the court: the state that Court.advance() steps.
##
## This exists so that real flight and the on-screen preview can be literally
## the same code path rather than two implementations that agree today. The
## player copies its own position into one of these and reads it back out; the
## preview runs a throwaway one forward a few seconds. Neither has its own idea
## of what a backboard or a rim does.

var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO

## Set once a backboard has been touched, and never cleared by advance() — a
## bank counts for the whole jump, not just the step it happened on.
var banked: bool = false

## Results of the most recent advance(). Both are cleared at the top of it.
var scored_on: Hoop = null
var hit_iron: Hoop = null


func load_from(p: Vector2, v: Vector2, was_banked: bool) -> void:
	pos = p
	vel = v
	banked = was_banked
	scored_on = null
	hit_iron = null
