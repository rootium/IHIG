class_name LM
extends RefCounted
## Central tuning table for Lumen.
##
## Two couplings are worth knowing. Difficulty is a single ramp `t` in 0..1
## derived from the level number, and every generator dial below is expressed as
## a minimum plus a span across that ramp — so RAMP_LEVELS alone decides how
## fast the whole game opens up. And beam colour is a three-bit mask, so the
## additive mixing rule is just a bitwise OR; the palette supplies what each bit
## looks like.

# --- Colour channels ---------------------------------------------------------
## Beams carry a mask of these. Two beams meeting a target hand it the OR of
## what they carry, which is the entire colour-mixing rule.
const R := 1
const G := 2
const B := 4
const WHITE := 7

# --- Difficulty ramp ---------------------------------------------------------
## Two ramps, because they do different jobs. The fast one introduces the game:
## the board grows to full size and every rule shows up by level 26. The slow
## one is the rest of your life with it — the board cannot get any bigger, so
## what grows instead is how far the light travels and how much of it is wrong
## when you arrive. Without the second ramp every level past the first two dozen
## is the same difficulty, which is exactly what the soak test reported.
const RAMP_LEVELS := 26.0
const DEEP_LEVELS := 110.0
const COLOR_AT := 0.10      ## Fast-ramp point where beams stop all being white.
const MIX_AT := 0.34        ## ...where one target may demand two colours.
const SPLIT_AT := 0.20      ## ...where splitters appear.
const MIX_CHANCE := 0.55    ## Both of these rise toward 1 along the slow ramp.
const SPLIT_CHANCE := 0.6

const GRID_W_MIN := 5
const GRID_W_MAX := 8
const GRID_H_MIN := 6
const GRID_H_MAX := 11

const TURNS_MIN := 1        ## Mirrors on one path.
const TURNS_SPAN := 3       ## ...added across the fast ramp.
const TURNS_DEEP := 2       ## ...and across the slow one.
const PATHS_MIN := 1        ## Independent source/target pairs.
const PATHS_SPAN := 2
const PATHS_DEEP := 1
const SPLITS_DEEP := 1      ## Extra splitters late on, beyond the first.
const RUN_MIN := 1          ## Cells a beam travels between two turns.
const RUN_MAX := 3

const DECOY_MIN := 1        ## Mirrors that no solution beam ever touches.
const DECOY_SPAN := 5
const WALL_MIN := 0
const WALL_SPAN := 5
## Extra pieces knocked out of true, beyond the first. Kept deliberately modest:
## a high par makes a level long rather than hard, and what should grow late on
## is how much the pieces interact — targets, mixes, splitters — not how many
## taps it takes to walk through an obvious answer.
const SCRAMBLE_SPAN := 4
const SCRAMBLE_DEEP := 2

const GEN_ATTEMPTS := 24    ## Whole-level retries before falling back.
const PATH_ATTEMPTS := 14   ## Placements tried for one path before giving up.

# --- Economy -----------------------------------------------------------------
const HINT_COST := 25       ## Credits to have one piece set correctly for you.
const CR_BASE := 12
const CR_PER_LEVEL := 2
const CR_PER_STAR := 9
## Replaying a level you have already cleared pays a fraction of the above, so
## grinding level 1 is never better than pushing forward.
const REPLAY_RATE := 0.25

# --- Layout (720x1280 portrait) ----------------------------------------------
const PAD := 26.0
const TOP_BAR := 156.0
const BOTTOM_BAR := 196.0

# --- Fallback palette --------------------------------------------------------
## Used before a theme is applied and as the default for anything a palette
## forgets to define.
const C_BG := Color(0.043, 0.047, 0.086)
const C_BOARD := Color(0.078, 0.086, 0.145)
const C_GRID := Color(1.0, 1.0, 1.0, 0.05)
const C_WALL := Color(0.20, 0.22, 0.31)
const C_INK := Color(0.88, 0.91, 1.0)
const C_R := Color(1.0, 0.30, 0.38)
const C_G := Color(0.36, 0.95, 0.55)
const C_B := Color(0.38, 0.63, 1.0)


## What a beam carrying `mask` looks like under `pal`.
##
## The channels add, so red plus green really is drawn as the sum of the
## palette's red and green. That can overshoot 1.0, so the result is scaled back
## by its brightest component — a mix reads as a hue rather than a white-out,
## and a palette can restyle every beam without breaking the mixing rule.
static func mix(mask: int, pal: Dictionary) -> Color:
	var c := Color(0.0, 0.0, 0.0, 1.0)
	if mask & R:
		c += pal.get("r", C_R)
	if mask & G:
		c += pal.get("g", C_G)
	if mask & B:
		c += pal.get("b", C_B)
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak > 1.0:
		c = Color(c.r / peak, c.g / peak, c.b / peak)
	c.a = 1.0
	return c
