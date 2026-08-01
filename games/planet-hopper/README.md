# Planet Hopper

*(working title)*

You fly a spacecraft that climbs endlessly upward, hopping from orbit to orbit.
Two meters decide how far you get: **fuel**, which you spend steering between
planets, and **oxygen**, which drains the whole time and only refills in the
orbit of a green, oxygen-rich world. Oxygen is the clock — you are never allowed
to settle anywhere for long.

Built with Godot 4.6. All art is drawn procedurally in `_draw()`, so the project
carries no image assets beyond the launcher icon.

**[▶ Play it in the browser](https://rootium.github.io/IHIG/planet-hopper/)**

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

## Reading the screen

The game is built around one idea: **you should never have to guess where a
launch will take you.**

- A **dotted curve** runs from the ship showing exactly where a coast from here
  ends up. While you sit in orbit it previews the hop you would get by tapping
  right now, and it sweeps around as you orbit — so choosing the moment to
  launch is something you can see rather than something you time blind.
- The planet that curve lands on lights up with a **bright cyan ring and four
  tick marks**. Everything else shows a dim grey arc.
- The planet you are **currently orbiting** draws one full ring whose filled
  portion is its remaining oxygen or fuel.

The preview always shows the *coasting* path, so it stays honest about what
happens if you let go.

## The loop

- **Launching** flings you along the tangent of your orbit, so *when* you tap
  decides *where* you go. This is the core skill, and the trajectory curve is
  what makes it fair.
- **Capture** happens when you cross a planet's ring. The speed limit for being
  caught is deliberately generous — aiming is the skill this game asks for,
  arriving at exactly the right speed is not.
- **Refuelling** happens passively while in orbit. Green worlds restore oxygen,
  amber ones restore fuel, purple ones give nothing. Reserves are finite, so you
  cannot camp one forever.
- **Stars** are scattered along the routes between planets and are worth more
  credits than anything else, which is the reason to take the scenic line.

Once you launch, the planet you left stops pulling on you until something else
catches you. Without that, any hop below escape velocity curves straight back to
where it started, which reads as the game fighting you.

## Hazards

Nothing hostile spawns in the first four chunks, so every run opens with room to
learn the controls.

| | |
| --- | --- |
| **Moons** | Circle their planet outside the capture ring, so they threaten your approach and departure rather than the orbit you are parked in. |
| **Black holes** | Pull far harder and further than their size suggests, and kill inside the event horizon. Their reach is drawn. Rare. |
| **Meteorites** | Drift sideways across the climb, ignoring gravity. Cheap to dodge if you see them coming. |

Falling too far back down, or drifting out of the corridor sideways, also ends
the run. Both give you a warning first.

## Credits and the shop

Finishing a run pays credits for height climbed, orbits reached, and stars
collected. Spend them on **ships** (six hulls, each with its own silhouette and
colours) and **worlds** (five palettes that repaint planets, moons, stars,
background and the target ring). Both are purely cosmetic — nothing you buy
changes handling or difficulty. Progress saves to `user://planet_hopper.save`.

## Project layout

```
main.tscn            an empty Node2D; main.gd builds the tree in code
scripts/config.gd    every tuning number, in one place (class PH)
scripts/main.gd      game manager: owns world, ship, camera, screens
scripts/ship.gd      the player — orbit state, free flight, capture, prediction
scripts/trajectory.gd draws the predicted path
scripts/world.gd     endless chunked procedural generation, gravity queries
scripts/planet.gd    orbitable body; oxygen / fuel / barren
scripts/moon.gd  black_hole.gd  meteor.gd   hazards
scripts/star_pickup.gd  collectible credits
scripts/starfield.gd parallax background, tiled procedurally
scripts/hud.gd  menus.gd        in-run readouts / title, pause, game over, shop
scripts/skins.gd  save_data.gd  cosmetics catalogue and persistence
tests/smoke_test.gd  headless autopilot soak test
```

Nothing uses physics bodies or collision shapes. Every object is a circle, so
collision is a distance check and the whole simulation stays in one readable
place.

`World.gravity_at()` is the single source of truth for gravity — both actual
flight and the on-screen preview call it, so the two cannot drift apart.

## Running it

```sh
godot --path games/planet-hopper                    # play on desktop
godot --headless --path games/planet-hopper --import
```

Mouse input drives the game on desktop — Godot synthesises it from touch on
device, so one input path covers both.

### Tests

`tests/smoke_test.gd` flies an autopilot through the real world and ship code,
restarting on each death, and fails the process on any script error.

Its autopilot aims the way a player is meant to: it watches `Ship.predict()` and
launches when the predicted path lands somewhere higher. It never thrusts to
steer, only to arrest a fall — so its capture count is a direct measurement of
whether the trajectory preview alone is enough to play the game.

```sh
godot --headless --fixed-fps 60 --path games/planet-hopper --script tests/smoke_test.gd
godot --headless --fixed-fps 60 --path games/planet-hopper --script tests/smoke_test.gd -- 200000
```

The trailing number is the frame budget at a fixed 60 Hz step (default 12000,
about 200 s of simulated play). It is excluded from exported builds.

Pass `--fixed-fps` or the run takes as long as the play it simulates: without
it Godot paces its main loop to real time, so the loop sleeps most of every
frame. With it the same 3000-frame run drops from 21 s to 1.7 s.

## Tuning

Everything worth adjusting lives in `scripts/config.gd`. The one coupling to
know about: orbital speed is derived from `GRAV` and planet mass, and launch
speed, capture speed and the size of the gravity wells are all expressed
relative to it — so changing `GRAV` moves the whole game's feel at once, while
the individual multipliers can be nudged independently.

Generation is deliberately one planet per chunk: chunk height and the sideways
step are what set the length of a hop, so a fixed count keeps the climb evenly
paced. A chunk that came out empty would leave a gap no hop could cross, so the
placement fallback relaxes spacing rather than skipping a chunk.
