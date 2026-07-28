class_name Cfg
extends RefCounted

## Every tunable number and colour in the game, in one place.

# --- block kinds --------------------------------------------------------------

enum Kind {
	SOLID,    ## wall and floor
	GOAL,     ## the way out
	KEY,      ## picked up on contact, opens doors of the same hue
	DOOR,     ## solid until its key is held
	HAZARD,   ## touching it restarts the chamber
	SHARD,    ## optional collectible
	FIELD,    ## walk through it freely, but you cannot rotate while inside
	MOVER,    ## solid, and drifts along one axis on a loop
}

## Kinds you cannot walk into.
const BLOCKING := [Kind.SOLID, Kind.DOOR, Kind.MOVER]

# --- timing -------------------------------------------------------------------

const MOVE_TIME := 0.115
const FALL_TIME := 0.085
const SHIFT_TIME := 0.30        ## an ana/kata step
const ROT_TIME := 0.78          ## a quarter turn into the fourth dimension
const CAM_LERP := 9.0
const CAM_SPIN_TIME := 0.32

## How many slices either side of the current one are drawn as ghosts.
const GHOST_DEPTH := 2

# --- palette ------------------------------------------------------------------

const VOID := Color("06070f")
const FOG := Color("0b1024")

const C_SOLID := Color("7d8bbe")
const C_SOLID_EDGE := Color("62d8ff")
const C_GOAL := Color("1fc48f")
const C_GOAL_EDGE := Color("3dffc0")
const C_HAZARD := Color("a8324c")
const C_HAZARD_EDGE := Color("ff3b5c")
const C_SHARD := Color("c19a2e")
const C_SHARD_EDGE := Color("ffd166")
const C_FIELD := Color("6a54b0")
const C_FIELD_EDGE := Color("9a7bff")
const C_MOVER := Color("6d8f95")
const C_MOVER_EDGE := Color("7bffd8")

const PLAYER := Color("fff4e0")
const PLAYER_EDGE := Color("ffc978")

## Keys and their doors share a hue. Levels index into this.
const HUES: Array[Color] = [
	Color("ffb347"),
	Color("ff5fa2"),
	Color("8bffb0"),
	Color("7fb8ff"),
]

## Ghost slices are tinted by which way along the hidden axis they lie, so you
## can read at a glance whether the thing you want is ana or kata of you.
const ANA := Color("ff7bac")
const KATA := Color("5fd2ff")

const UI_TEXT := Color("dfe8ff")
const UI_DIM := Color("7286b5")
const UI_ACCENT := Color("62d8ff")
const UI_WARN := Color("ff8a5c")


static func body_color(kind: int, hue: int) -> Color:
	match kind:
		Kind.GOAL: return C_GOAL
		Kind.HAZARD: return C_HAZARD
		Kind.SHARD: return C_SHARD
		Kind.FIELD: return C_FIELD
		Kind.MOVER: return C_MOVER
		Kind.KEY, Kind.DOOR:
			return HUES[hue % HUES.size()].darkened(0.68)
		_: return C_SOLID


static func edge_color(kind: int, hue: int) -> Color:
	match kind:
		Kind.GOAL: return C_GOAL_EDGE
		Kind.HAZARD: return C_HAZARD_EDGE
		Kind.SHARD: return C_SHARD_EDGE
		Kind.FIELD: return C_FIELD_EDGE
		Kind.MOVER: return C_MOVER_EDGE
		Kind.KEY, Kind.DOOR:
			return HUES[hue % HUES.size()]
		_: return C_SOLID_EDGE
