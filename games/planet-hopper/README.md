# Planet Hopper

*(working title)*

You fly a spacecraft that hops from orbit to orbit across an endless run of
star systems. Two meters decide how far you get: **fuel**, which you spend
steering between planets, and **oxygen**, which drains the whole time and only
refills in the orbit of a green, oxygen-rich world. Oxygen is the clock — you
are never allowed to settle anywhere for long.

Built with Godot 4.6. All art is drawn procedurally in `_draw()`, so the project
carries no image assets beyond the launcher icon.

## Controls

One thumb does everything.

| | |
| --- | --- |
| **Tap** while orbiting | Break orbit along your current tangent |
| **Hold** | Burn toward your finger (costs fuel) |
| **Drag** while holding | Steer — the nose swings to follow |
| **Release** | Coast on gravity alone |

Breaking orbit is free. Fuel only pays for steering and braking in flight, so an
empty tank strands you but never softlocks you.

## The loop

- **Launching** flings you along the tangent of your orbit, so *when* you tap
  decides *where* you go. This is the core skill.
- **Capture** happens when you cross a planet's drawn ring slowly enough. The
  ring turns white the moment you are slow enough to be caught — if it stays
  dim, you are coming in too hot and need to turn around and retro-burn.
- **Refuelling** happens passively while in orbit. Green worlds restore oxygen,
  amber ones restore fuel, grey ones give nothing. Each world holds a finite
  reserve, shown as an arc outside its ring, so you cannot camp one forever.

## Hazards

| | |
| --- | --- |
| **Moons** | Circle their planet outside the capture ring, so they threaten your approach and departure rather than the orbit you are parked in. |
| **Black holes** | Pull far harder and further than their size suggests, and kill inside the event horizon. Their reach is drawn. Good for a slingshot if you are confident. |
| **Meteorites** | Drift on straight lines, ignoring gravity. Cheap to dodge if you see them coming. |

Drifting far above or below the lane of planets also ends the run — you get a
warning well before the boundary.

## Credits and the shop

Finishing a run pays out credits based on distance travelled and orbits reached.
Spend them in the shop on **ships** (six hulls, each with its own silhouette and
colours) and **worlds** (five palettes that repaint planets, moons, stars and
the background). Both are purely cosmetic — nothing you buy changes handling or
difficulty. Progress saves to `user://planet_hopper.save`.

## Project layout

```
main.tscn            an empty Node2D; main.gd builds the tree in code
scripts/config.gd    every tuning number, in one place (class PH)
scripts/main.gd      game manager: owns world, ship, camera, screens
scripts/ship.gd      the player — orbit state, free flight, capture
scripts/world.gd     endless chunked procedural generation
scripts/planet.gd    orbitable body; oxygen / fuel / barren
scripts/moon.gd  black_hole.gd  meteor.gd   hazards
scripts/starfield.gd parallax background, tiled procedurally
scripts/hud.gd  menus.gd        in-run readouts / title, game over, shop
scripts/skins.gd  save_data.gd  cosmetics catalogue and persistence
tests/smoke_test.gd  headless autopilot soak test
```

Nothing uses physics bodies or collision shapes. Every object is a circle, so
collision is a distance check and the whole simulation stays in one readable
place.

## Running it

```sh
godot --path games/planet-hopper                    # play on desktop
godot --headless --path games/planet-hopper --import
```

Mouse input drives the game on desktop — Godot synthesises it from touch on
device, so one input path covers both.

### Tests

`tests/smoke_test.gd` flies an autopilot through the real world and ship code,
restarting on each death, and fails the process on any script error. It is a
crash/soak test, not an assertion of fun.

```sh
godot --headless --path games/planet-hopper --script tests/smoke_test.gd
godot --headless --path games/planet-hopper --script tests/smoke_test.gd -- 60000
```

The trailing number is the frame budget at a fixed 60 Hz step (default 12000,
about 200 s of simulated play). A healthy run reports captures well into the
dozens and a spread of death causes. It is excluded from exported builds.

## Tuning

Everything worth adjusting lives in `scripts/config.gd`. The one coupling to
know about: orbital speed is derived from `GRAV` and planet mass, and launch
speed, capture speed and the size of the gravity wells are all expressed
relative to it — so changing `GRAV` moves the whole game's feel at once, while
the individual multipliers can be nudged independently.
