# Tessera

A puzzle game in four spatial dimensions.

You are standing in a three dimensional *slice* of a four dimensional room. The
walls you can see are only the walls in this slice. Step one cell along the axis
you cannot see and the wall in front of you may simply not be there. Turn that
axis into view and a wall one cell thick becomes a corridor running away from
you.

Forty-three chambers, on the web, on Android and on desktop, from one codebase.

**[▶ Play it in the browser](https://rootium.github.io/IHIG/tessera/)**

---

## The idea

The whole game is one geometric fact.

A four dimensional box, cut by a three dimensional hyperplane, is a three
dimensional box. Not an approximation of one — exactly one. That means the
world can be stored as 4D boxes, sliced afresh every frame, and drawn as
ordinary geometry, on a phone, at rate.

It stays exactly true while the slice is *turning*, too, which is the part that
makes the game work. The player's frame — the three directions they can see and
the one they cannot — is rotated a quarter turn at a time. Halfway through such
a turn the frame is genuinely oblique, and the cross-section of a box is still
a box, because a rotation in one 2-plane only ever mixes two of the four axes
and hands both of them to the same pair of frame vectors. So the walls do not
pop between configurations: they thin out, sweep through, and become other
walls, and every frame of it is exact.

`scripts/hyper.gd` is where that lives, and it is about forty lines.

## Why turning is a move and not a camera

The three horizontal world axes are always all available to you: two to walk
along and one to step along. So on flat ground you never need to turn — the
fourth dimension is just a sideways step, and the game would be a maze with an
extra direction.

Stepping *up* is the asymmetry. It works along the axes you can see and not
along the one you cannot. A corridor that rises along the hidden axis cannot be
climbed until you turn that axis into view. That single rule is what makes the
central move necessary rather than decorative, and the level generator is built
around it.

## Rules

- **Move** one cell along a visible horizontal direction. A single block in the
  way is stepped up onto if there is headroom.
- **Ana / kata** — one cell along the hidden axis. No step-up: the destination
  must be clear.
- **Turn** — a quarter turn taking a visible axis into the hidden one. It pivots
  on you, so your cell never changes and a turn can never strand you inside a
  wall. The room simply becomes a different room around you.
- Gravity runs along Y, which is never rotated. Falling out of a chamber, or
  touching a hazard, rewinds the step that did it rather than the chamber —
  making someone replay twenty correct moves to punish one wrong one teaches
  nothing. Undo is unlimited.

## Controls, and saying so

There are more verbs here than a puzzle game usually has — walk, step along the
hidden axis, turn an axis into view — and on a phone they all have to be
buttons. The on-screen pad used to be the keyboard with the keys filed off: two
of its buttons were labelled `Z↔W` and `X↔W`, which name the *plane a rotation
turns in* and are therefore the one thing a player who has never met a fourth
axis cannot read.

Now the buttons carry a direction and the group carries the verb. A **STEP**
pair is ana and kata; a **TURN** pair is DEPTH and SIDE, naming which visible
axis is about to be swapped out. Undo and restart are chores rather than moves,
so they sit up beside pause instead of taking two of the six thumb slots. On
touch the scope and the axis readout move to the top left, because the bottom
left is where a thumb and the movement pad go — the pad used to be drawn
straight over the scope.

`HOW TO PLAY` describes whichever controls the device actually has. Telling
someone on a phone to press `E` while the button in front of them says `ANA` is
worse than saying nothing.

## Reading four dimensions

Three things do the work of making the invisible axis legible, and the game
would be unplayable without them:

- **The ghosts.** Neighbouring slices are drawn as edge-only outlines, warm for
  ana and cool for kata. You can see the corridor you cannot walk in yet.
- **The scope** — bottom left with a keyboard, top left on touch, where the
  movement pad is not. Your own column, read along the hidden axis: filled is
  solid, hollow is open, a bar underneath means there is floor to land on.
- **The avatar.** You are drawn as a real hypercube — sixteen vertices, thirty
  two edges — projected through the *same frame the game is slicing with*. When
  you turn, it visibly tumbles inside out. Nothing states your orientation more
  directly.

## The chambers

`tools/tessera/build_campaign.py` generates and proves the campaign. No chamber
ships until a breadth-first search over its entire state space — position,
orientation and keys held — has found the shortest solution, which becomes its
par. Chambers whose optimal route does not use the fourth dimension are thrown
away and regenerated.

The corridors are grown backwards from the answer, the trick the second game in
this repo used: walk a route first, then carve exactly that route out of solid
rock. Two details make the difference between a puzzle and a formality — the
walk keeps a cell of rock between its own passes, because corridor cells that
merely end up side by side are connected whether the walk meant them to be or
not; and it climbs, for the reason above.

`tests/solve_test.gd` then replays every recorded solution through the real
game and requires each chamber to open in exactly par moves. That is what keeps
the generator's model of the rules and the game's actual rules from drifting
apart.

## Building

```sh
tools/build.sh games/tessera                    # web, android, linux, windows
tools/build.sh games/tessera web
python3 tools/tessera/build_campaign.py         # regenerate the chambers
python3 tools/tessera/make_music.py             # re-render the two music loops
godot --headless --path games/tessera -s tests/solve_test.gd
```

## Notes on the build

**One renderer.** GL Compatibility is the only backend that covers web, Android
and desktop from a single export, so everything here is untextured procedural
geometry with hand-written shaders. There are no lights: the key light, the
carved panels, the veining and the edges are all recovered in the fragment
shader from a box's own local coordinates and world size.

**No instance colours.** The Compatibility renderer does not deliver a
MultiMesh's per-instance colours to the shader — they arrive as black. Anything
needing its own colour therefore gets its own material and its own MultiMesh
layer. There are about a dozen, which is cheaper than it sounds.

**No sky.** The camera is orthographic, so every ray through the frustum is
parallel and a sky shader has no meaningful eye direction — it smears its stars
into radial streaks. The backdrop is a full-screen quad under the 3D layer with
two parallax star layers panned against the camera's own rotation.

**Roofless.** Chambers are carved out of solid rock, so drawing every solid cell
would show you the outside of a brick. Only cells bordering open space along a
*visible* axis are drawn, the region outside the chamber counts as rock so the
outer shell never appears, and ceilings are dropped. What is left is the
corridor, open to the sky. Walls between the camera and the player are
dithered away on top of that.

**Audio.** Every sound effect is synthesised in GDScript at startup — a few
hundred milliseconds of arithmetic each, which costs less than loading a file of
the same sound. The two music loops are rendered offline by
`tools/tessera/make_music.py` and are seamless twice over: every oscillator
completes a whole number of cycles in the loop, and the tail is folded back over
the head with an equal-power crossfade so the noise layer wraps cleanly too.

## Assets

Two OFL-licensed typefaces, [Space Grotesk](fonts/SpaceGrotesk-OFL.txt) and
[JetBrains Mono](fonts/JetBrainsMono-OFL.txt), with their licences alongside.

Neither is a symbol font, and a character they lack renders as a missing-glyph
box rather than as an error. Space Grotesk has no `⇄`, `⇅`, `⟳` or `◆` — all
four were on screen at some point. Check with `Font.has_char()` before putting a
symbol in a label, or draw it.
Everything else — every mesh, texture, sound and note — is generated by code in
this repository.
