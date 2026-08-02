class_name BD
extends RefCounted
## Central tuning table for Dunk Rush.
##
## The climb goes upward (-Y) and gravity pulls down (+Y). Unlike an orbit game
## there is only one force here, which makes every jump an honest parabola —
## that is what lets the aim preview be exact rather than approximate.
##
## The one coupling worth knowing: GRAV and CHUNK_H together decide how much of
## a jump a player needs to spend just to reach the next rim. JUMP_MAX is set
## from those two (see the note there), so moving either without re-checking it
## can quietly make the game unwinnable.

# --- Physics -----------------------------------------------------------------
const GRAV := 1200.0            ## Downward acceleration, px/s^2.
const MAX_SPEED := 1700.0
const AIR_DRAG := 0.12          ## Per second, horizontal only. Keeps long jumps readable.

# --- Jumping -----------------------------------------------------------------
## Pull back to aim. Power is the pull length over MAX_PULL, so a short drag is
## a short hop and the gesture never runs off the top of a phone screen.
const MAX_PULL := 300.0
const MIN_PULL := 26.0          ## Below this a drag is treated as a tap, not an aim.
const JUMP_MIN := 640.0
## Reaching the next rim needs sqrt(2 * GRAV * CHUNK_H) ~= 980 of vertical alone,
## so the ceiling has to sit above that. It is not set much higher on purpose:
## at 1300 a full-power jump just covers the longest sideways step generation
## can produce, which keeps the top of the power meter useful instead of an
## overshoot the player learns never to use.
const JUMP_MAX := 1300.0
const AIM_MIN_ELEVATION := 0.18 ## Radians above horizontal. You may not aim into the floor.

# --- Hang time ---------------------------------------------------------------
## Holding in mid-air floats: gravity is scaled down and you drift toward your
## finger. It spends air, which only refills on a score, so floating is a way to
## save a jump you misjudged rather than a way to fly.
const AIR_MAX := 100.0
const AIR_BURN := 34.0          ## Per second of floating.
const FLOAT_GRAV_MULT := 0.34
const FLOAT_STEER := 620.0      ## px/s^2 sideways toward the touch point.

# --- Shot clock --------------------------------------------------------------
## The run's clock, and the reason you can never settle on a rim. Resets on
## every score, exactly like the real thing.
const SHOT_CLOCK := 24.0
const CLOCK_WARN := 6.0         ## Below this the HUD starts shouting.

# --- Hoops -------------------------------------------------------------------
const RIM_HALF := 54.0          ## Half the rim width at the start of a run.
const RIM_HALF_MIN := 38.0      ## ...and once difficulty is maxed out.
const RIM_THICK := 7.0
## A dunk has to drop through the middle of the rim, not clip its edge. The gap
## between SCORE_HALF and RIM_HALF is the band that clangs instead.
const SCORE_HALF_MULT := 0.72
const SWISH_HALF_MULT := 0.30   ## Dead centre. Worth an extra point.
const BOARD_H := 118.0          ## Backboard height above the rim.
const BOARD_T := 13.0           ## Backboard thickness.
const BOARD_BOUNCE := 0.52      ## How much speed a bank keeps.
const CLANG_BOUNCE := 0.42
## A reflection alone damps toward zero, which lets a player settle onto the
## iron and clang against it until the shot clock runs out. The kick guarantees
## every clang throws you clear of the rim's span instead.
const CLANG_KICK := 300.0
const CLANG_LOCKOUT := 0.22     ## Stops one bad approach registering twice.
const NET_H := 46.0

# --- Moving hoops ------------------------------------------------------------
## Rims that slide are what make *when* you launch matter, the same way the
## orbit angle does in the sibling game. You slide with the rim while hanging.
const SLIDE_SPEED_MIN := 40.0
const SLIDE_SPEED_MAX := 115.0

# --- Player ------------------------------------------------------------------
const BALLER_R := 17.0
const HANG_DROP := 12.0         ## How far below the rim you hang.
const TRAIL_LENGTH := 22

# --- Scoring -----------------------------------------------------------------
const DUNK_POINTS := 2
const SWISH_BONUS := 1
const BANK_BONUS := 1
const MULT_STEP := 3            ## Consecutive dunks per extra multiplier.
const MULT_MAX := 5

# --- Court generation (climbs toward -Y) -------------------------------------
const CHUNK_H := 400.0          ## Vertical gap between rims.
const COURT_BAND := 330.0       ## Half-width of the playable column.
## How far sideways consecutive rims step. The top of this range is what
## JUMP_MAX is sized against, so raising it makes long gaps unreachable.
const STEP_MIN := 230.0
const STEP_MAX := 450.0
const CHUNKS_AHEAD := 5
const CHUNKS_BEHIND := 2
const RAMP_CHUNKS := 35.0       ## Chunks until difficulty is maxed out.
const SAFE_CHUNKS := 4          ## Nothing can kill you below this height.
const FALL_LIMIT := 900.0       ## How far you may drop below your best height.
const SIDE_LIMIT := 2.0         ## Multiples of COURT_BAND before you are out of bounds.

# --- Aim preview -------------------------------------------------------------
## Four seconds of look-ahead, stepped at 1/60 rather than something coarser on
## purpose. Semi-implicit Euler carries an error of g*T*dt/2, so previewing at
## 1/30 while flying at 1/60 would put the drawn path ~15px off the flown one by
## the end of a long jump — enough to turn a predicted dunk into a clang, which
## is exactly the kind of lie this preview exists not to tell.
const PREVIEW_STEPS := 240
const PREVIEW_DT := 1.0 / 60.0

# --- Palette -----------------------------------------------------------------
const C_BG := Color(0.055, 0.063, 0.106)
const C_RIM := Color(0.98, 0.45, 0.16)      ## Regulation orange.
const C_RIM_TARGET := Color(1.0, 0.84, 0.32)
const C_BOARD := Color(0.86, 0.89, 0.96)
const C_NET := Color(0.92, 0.94, 1.0)
const C_BALL := Color(0.95, 0.48, 0.20)
const C_GOLD := Color(1.0, 0.82, 0.29)
const C_DEFENDER := Color(0.82, 0.29, 0.34)
const C_LOOSE := Color(0.62, 0.66, 0.78)
const C_JERSEY := Color(0.36, 0.77, 0.91)
const C_SKIN := Color(0.85, 0.66, 0.48)
