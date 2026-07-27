class_name PH
extends RefCounted
## Central tuning table for Planet Hopper.
##
## Everything here is hand-tuned for feel, not physical accuracy. The one rule
## worth keeping: orbital speed is derived from GRAV and planet mass, so if you
## change GRAV the launch speed and capture window move with it.

# --- Gravity -----------------------------------------------------------------
const GRAV := 1200.0            ## Gravitational constant (game units).
const MAX_GRAV_ACCEL := 2600.0  ## Clamp so close passes stay survivable.
## Gravity reach of a planet, in its own radii. Wide enough that neighbouring
## wells overlap, so a roughly-aimed hop gets funnelled in rather than sailing
## off into nothing.
const INFLUENCE_MULT := 13.0
const HOLE_INFLUENCE_MULT := 17.0
const HOLE_MASS_MULT := 7.0     ## Black holes pull far harder for their size.

# --- Ship --------------------------------------------------------------------
const THRUST := 430.0           ## px/s^2 while burning.
const TURN_RATE := 7.0          ## rad/s the nose swings toward your finger.
const MAX_SPEED := 1400.0
const LAUNCH_MULT := 1.45       ## Launch speed as a multiple of orbital speed.
const SHIP_RADIUS := 11.0

# --- Orbits ------------------------------------------------------------------
const ORBIT_GAP := 70.0         ## Nominal orbit height above the surface.
## Capture radius scales with the planet — radius * CAPTURE_MULT + CAPTURE_BASE —
## so big worlds are forgiving targets and small ones are a real test of aim.
const CAPTURE_MULT := 1.8
const CAPTURE_BASE := 90.0
const CAPTURE_SPEED := 400.0    ## Come in faster than this and you sail past.
const RECAPTURE_LOCKOUT := 0.35 ## Grace after launch so you don't re-dock instantly.

# --- Life support ------------------------------------------------------------
const FUEL_MAX := 100.0
const FUEL_BURN := 22.0         ## Per second of thrust.
const FUEL_REFILL := 32.0       ## Per second in a fuel planet's orbit.
const OXY_MAX := 100.0
const OXY_DRAIN := 3.0          ## Per second, always. This is the clock.
const OXY_REFILL := 34.0        ## Per second in an oxygen planet's orbit.

# --- World generation --------------------------------------------------------
const CHUNK_W := 900.0          ## Width of one generated slice of space.
const WORLD_BAND := 1250.0      ## Half-height of the playable band.
const CHUNKS_AHEAD := 4
const CHUNKS_BEHIND := 2
const RAMP_CHUNKS := 26.0       ## Chunks until difficulty is maxed out.

# --- Palette -----------------------------------------------------------------
const C_BG := Color(0.027, 0.031, 0.071)
const C_OXY := Color(0.24, 0.72, 0.47)
const C_FUEL := Color(0.93, 0.66, 0.24)
const C_BARREN := Color(0.44, 0.42, 0.52)
const C_MOON := Color(0.78, 0.79, 0.86)
const C_METEOR := Color(0.71, 0.45, 0.34)
const C_HOLE := Color(0.62, 0.36, 0.9)
const C_SHIP := Color(0.91, 0.94, 1.0)
const C_FLAME := Color(1.0, 0.6, 0.24)
