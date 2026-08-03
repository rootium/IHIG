# Dunk Rush

You are a dunker climbing an endless stack of baskets. Every rim you throw down
on resets the **shot clock** and refills your **air**; miss, and you fall.
There is no floor to land on, so the only way to stay in the run is to keep
scoring.

Built with Godot 4.6. All art is drawn procedurally in `_draw()`, so the project
carries no image assets beyond the launcher icon.

## Controls

One thumb does everything.

| | |
| --- | --- |
| **Drag back** while hanging | Aim — pull further for a harder jump |
| **Release** | Jump along the line you were shown |
| **Tap** (no drag) | Jump again with the aim you last used |
| **Hold** in mid-air | Hang — softer gravity, drifts toward your finger, spends air |

Jumping is free. Air only pays for hanging, so an empty meter costs you control
in the air but never strands you on a rim.

## Reading the screen

The game is built around one idea: **you should never have to guess where a jump
will take you.**

- A **dotted curve** runs from your hands showing exactly where a jump at the
  current aim and power lands. It tracks your thumb as you drag.
- The curve is **honest about contact**. It bounces off backboards, because
  banking is something you are meant to aim on purpose. It stops dead on a
  **red cross** when the line would hit iron, so a clang is something you see
  before you commit rather than after.
- The rim it lands on lights up with **bright ticks over its scoring band**, so
  you know not just *which* basket but whether you are lined up with the part of
  it that actually goes in.
- The **arrow and ring** at your feet show aim direction and how much of the
  power meter the drag is spending.

## The loop

- **Aiming** is the core skill, and the dotted line is what makes it fair.
- **Dunking** means dropping through the middle of a rim on the way down. Catch
  the rim and you hang there, ready to aim again.
- **The shot clock** is the run's real timer. 24 seconds, reset by every score,
  and nothing else refills it. It is what stops you from parking on a rim and
  lining up the perfect jump forever.
- **Air** refills only on a score too, which keeps mid-air saves rationed.
- **Gold** sits off the straight line between rims, so collecting it is a
  decision rather than something that happens to you on the way past.

### Scoring

| | |
| --- | --- |
| Dunk | 2 points |
| Swish | +1 — through the dead centre of the rim |
| Off the glass | +1 — banked off a backboard on the way in |
| Combo | Every 3 consecutive dunks adds a multiplier, up to 5x |

Clipping the iron **clangs**: you carom off, lose the combo, and keep falling —
but the run continues. Re-dunking a rim you already scored on is a legal way to
save yourself; it just does not pay twice.

## Hazards

Nothing hostile spawns in the first four chunks, so every run opens with room to
learn the jump.

| | |
| --- | --- |
| **Defenders** | Patrol the gap *below* a rim — the space you rise through — rather than level with it, so they threaten the approach instead of parking on the basket. |
| **Loose balls** | Drift sideways across the climb, ignoring gravity. Cheap to dodge if you saw them before you jumped. |
| **Sliding rims** | Not hostile, but they move. You slide with one while hanging and carry its speed into your jump, so *when* you let go matters as much as where you aim. |

Falling too far below your best height, or drifting out of the column sideways,
also ends the run. Both give you a warning first.

## Credits and the shop

Finishing a run pays credits for points scored, dunks landed and gold collected.
Spend them on **ballers** (six kits, each with its own colours and ball) and
**arenas** (five palettes that repaint rims, backboards, nets, crowd and
background). Both are purely cosmetic — nothing you buy changes handling or
difficulty. Progress saves to `user://dunk_rush.save`.

## Project layout

```
main.tscn             an empty Node2D; main.gd builds the tree in code
scripts/config.gd     every tuning number, in one place (class BD)
scripts/main.gd       game manager: owns court, player, camera, screens
scripts/baller.gd     the player — hanging, aiming, flight, prediction
scripts/flight.gd     one point in motion; the state Court.advance() steps
scripts/court.gd      endless chunked generation, and all flight physics
scripts/hoop.gd       rim, backboard, net; owns its own scoring bands
scripts/trajectory.gd draws the predicted path
scripts/defender.gd  loose_ball.gd    hazards
scripts/gold_ball.gd  collectible credits
scripts/ball.gd       seam drawing shared by everything round and orange
scripts/crowd.gd      parallax stands, tiled procedurally
scripts/hud.gd  menus.gd    in-run readouts / title, pause, game over, shop
scripts/skins.gd  save_data.gd  cosmetics catalogue and persistence
tests/smoke_test.gd   headless autopilot soak test
```

Nothing uses physics bodies or collision shapes. The player is a circle, a rim
is a segment and a backboard is a rectangle, so every collision is a couple of
lines of arithmetic and the whole simulation stays in one readable place.

`Court.advance()` is the single source of truth for movement. The player hands
it their position and velocity and takes the result back; the aim preview runs
the identical call on a throwaway `Flight`. The drawn path and the flown path
are not two implementations that agree — they are the same one.

## Running it

```sh
godot --path games/dunk-rush                    # play on desktop
godot --headless --path games/dunk-rush --import
```

Mouse input drives the game on desktop — Godot synthesises it from touch on
device, so one input path covers both.

### Tests

`tests/smoke_test.gd` runs an autopilot up the real court and player code,
restarting on each death, and fails the process on any script error.

Its autopilot plays the way a player is meant to: it sweeps a fan of aims,
watches `Baller.predict()`, and takes the line the preview says lands on a
higher basket — then narrows the search around its best near-miss, the way a
thumb adjusts a drag that came up short. It never hangs to steer, only to arrest
a fall, so its dunk count is a direct measurement of whether the aim preview
alone is enough to play the game.

```sh
godot --headless --fixed-fps 60 --path games/dunk-rush --script tests/smoke_test.gd
godot --headless --fixed-fps 60 --path games/dunk-rush --script tests/smoke_test.gd -- 60000
```

The trailing number is the frame budget at a fixed 60 Hz step (default 12000,
about 200 s of simulated play). It is excluded from exported builds.

Pass `--fixed-fps` or the run takes as long as the play it simulates: without it
Godot paces its main loop to real time, so the loop sleeps most of every frame.

## Tuning

Everything worth adjusting lives in `scripts/config.gd`. Two couplings to know
about:

- **`GRAV`, `CHUNK_H` and `JUMP_MAX` move together.** Reaching the next rim
  costs `sqrt(2 * GRAV * CHUNK_H)` of vertical speed before a jump has covered
  any sideways distance at all. `JUMP_MAX` is sized so that a full-power jump
  just covers the longest sideways step in `STEP_MIN..STEP_MAX` — which is what
  keeps the top of the power meter useful instead of a permanent overshoot.
- **`PREVIEW_DT` must match the frame step.** Semi-implicit Euler carries an
  error of `g*T*dt/2`, so previewing at 1/30 while flying at 1/60 puts the drawn
  path about 15px off the flown one by the end of a long jump — enough to turn a
  promised dunk into a clang. It is 1/60 for that reason, and `PREVIEW_STEPS`
  buys the look-ahead back.

Generation is deliberately one hoop per chunk, zigzagging: chunk height and the
sideways step are what set the length of a jump, so a fixed count keeps the
climb evenly paced. The zigzag turns around at the edge of the column, which
stops a run drifting into one wall and staying there.
