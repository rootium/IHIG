class_name PH
extends RefCounted
## Central tuning table for Planet Hopper.
##
## The world climbs upward (-Y). Everything here is tuned for feel rather than
## physical accuracy, with one coupling worth knowing: orbital speed is derived
## from GRAV and planet mass, and launch speed is a multiple of it, so moving
## GRAV moves the whole game's pace at once.

# --- Gravity -----------------------------------------------------------------
const GRAV := 1200.0            ## Gravitational constant (game units).
const MAX_GRAV_ACCEL := 2200.0  ## Clamp so close passes stay survivable.
const INFLUENCE_MULT := 11.0     ## Gravity reach of a planet, in its own radii.
const HOLE_INFLUENCE_MULT := 13.0
const HOLE_MASS_MULT := 5.0     ## Black holes pull harder than their size implies.

# --- Ship --------------------------------------------------------------------
const THRUST := 380.0           ## px/s^2 while burning.
const TURN_RATE := 8.0          ## rad/s the nose swings toward your finger.
const MAX_SPEED := 1200.0
## Launch speed as a multiple of orbital speed. This is only slightly above
## orbital because the planet you leave stops pulling on you (see Ship.launch),
## which is what makes a hop read as a clean arc instead of a decaying spiral.
const LAUNCH_MULT := 1.15
const SHIP_RADIUS := 13.0
const TRAIL_LENGTH := 26

# --- Orbits ------------------------------------------------------------------
const ORBIT_GAP := 55.0         ## Orbit height above the surface.
## Capture radius scales with the planet: radius * CAPTURE_MULT + CAPTURE_BASE.
const CAPTURE_MULT := 1.55
const CAPTURE_BASE := 65.0
## Deliberately generous. Aiming is the skill this game asks for; arriving at
## exactly the right speed is not, so almost anything that reaches a ring sticks.
const CAPTURE_SPEED := 600.0
const RECAPTURE_LOCKOUT := 0.25

# --- Life support ------------------------------------------------------------
const FUEL_MAX := 100.0
const FUEL_BURN := 20.0         ## Per second of thrust.
const FUEL_REFILL := 42.0       ## Per second in an amber planet's orbit.
const OXY_MAX := 100.0
const OXY_DRAIN := 2.2          ## ~45 s from full. This is the clock.
const OXY_REFILL := 46.0        ## Per second in a green planet's orbit.

# --- World generation (climbs toward -Y) -------------------------------------
const CHUNK_H := 620.0          ## Height of one generated slice of space.
const WORLD_BAND := 400.0       ## Half-width of the playable column.
const CHUNKS_AHEAD := 5
const CHUNKS_BEHIND := 2
const RAMP_CHUNKS := 40.0       ## Chunks until difficulty is maxed out.
const SAFE_CHUNKS := 4          ## Nothing can kill you below this height.
const FALL_LIMIT := 1500.0      ## How far you may drop below your best height.

# --- Trajectory preview ------------------------------------------------------
## Five seconds of look-ahead, integrated coarsely. Cheap enough to redo every
## frame, which matters because it has to track your finger while you steer.
const PREVIEW_STEPS := 150
const PREVIEW_DT := 1.0 / 30.0

# --- Palette -----------------------------------------------------------------
const C_BG := Color(0.051, 0.067, 0.157)
const C_OXY := Color(0.53, 0.80, 0.53)
const C_FUEL := Color(0.96, 0.66, 0.42)
const C_BARREN := Color(0.66, 0.55, 0.96)
const C_MOON := Color(0.80, 0.82, 0.90)
const C_METEOR := Color(0.77, 0.33, 0.24)
const C_HOLE := Color(0.55, 0.33, 0.85)
const C_RING := Color(0.36, 0.77, 0.91)   ## Cyan target ring.
const C_RING_IDLE := Color(0.45, 0.48, 0.58)
const C_STAR := Color(1.0, 0.82, 0.29)
const C_SHIP := Color(0.94, 0.96, 1.0)
const C_FLAME := Color(1.0, 0.62, 0.26)
