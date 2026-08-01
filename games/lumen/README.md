# Lumen

*(working title)*

A light-routing puzzle. A few sources fire beams across a grid; a few rings are
waiting to be lit, each in a particular colour. Between them sit mirrors you can
turn. Tap one and it flips between `/` and `\`, the light takes a different
route, and you try again.

Two beams arriving at the same ring **mix**. Red and green make yellow, and a
ring asking for yellow will not take anything else — so some rings cannot be
satisfied by one beam at all, and working out which two have to meet there is
most of the game.

Built with Godot 4.6. All art is drawn procedurally in `_draw()`, so the project
carries no image assets beyond the launcher icon.

**[▶ Play it in the browser](https://rootium.github.io/IHIG/lumen/)**

## Teaching the board

The rules fit in two sentences and used to be stated in two sentences on the
title screen. That was not enough, because the rules are not the hard part —
the *pieces* are. A player who cannot tell a splitter from a mirror, or read the
dot inside a ring, is not solving the puzzle; they are guessing which diagonal
to tap and waiting to see what happens.

So there is a **HOW TO PLAY** screen. It names every piece, and shows the mixing
rule as red and green arriving at one yellow ring rather than just asserting it.
It opens by itself the first time the game is launched, and sits on the title
screen after that.

The legend draws its icons through `scripts/pieces.gd`, which is also what the
board draws through. That is deliberate: a legend that redraws the pieces in its
own code goes quietly wrong the first time the board's look changes, and a
legend that is wrong teaches the player to read something that is not there.

## Controls

One thumb, one verb.

| | |
| --- | --- |
| **Tap a mirror** | Turn it. That is the entire input. |
| **RESET** | Put every piece back where the level started. Free. |
| **HINT** | Buy one piece, set correctly. Costs credits *and* a tap. |

Nothing is timed and nothing can be lost. The only pressure is **par**: the
number of pieces the level was built out of true, and therefore the number of
taps a perfect solve takes.

## Reading the board

| | |
| --- | --- |
| **Rounded block with a nozzle** | A source. The nozzle is the direction it fires; its colour is what it emits. |
| **Solid diagonal** | A mirror. Tap to turn it. |
| **See-through diagonal with solid ends** | A splitter. Half the light carries straight on, half turns. Tap to turn the half that turns. |
| **Hollow ring** | A target, in the colour it is asking for. |
| **Ring with a dot in it** | A target being fed the wrong colour — the dot is what is actually arriving. |
| **Filled disc with a halo** | A target that is done. |
| **Square block** | A wall. Light stops here. |

The wrong-colour state is the one that matters. A mixing puzzle can only give
you one useful clue, and that clue is *which* colour turned up.

## Every level is solvable, and that is not a hope

Levels are generated, endlessly, and a generated puzzle that cannot be solved is
the one bug a player can neither work around nor forgive. So the solution is not
searched for — it is what gets built.

The generator picks a target, then walks **backwards** away from it, placing the
mirrors that would have brought a beam there, and plants a source wherever it
runs out of turns. Walking backwards costs nothing, because a mirror that turns
a beam travelling east into one travelling north also turns north into east.
By the time the board exists it is already solved; scrambling a few pieces at
the end is what makes it a puzzle, and how many were scrambled is the par.

Two bookkeeping sets keep independent paths from ruining each other: cells a
beam passes straight through, where nothing may be placed, and cells holding a
piece, which nothing else may touch. A solution beam only ever visits those, so
the decoy mirrors and walls scattered through everything else provably cannot
affect the answer.

It is still checked. Before a level is handed over it is traced with the same
code that renders it and asked whether it is solved, and `tests/smoke_test.gd`
re-asks that question for hundreds of levels at a time.

## Difficulty

Two ramps, because they do different jobs.

The **fast** one is the introduction: over about 26 levels the grid grows from
5x6 to 8x11 and every rule turns up — colour, then splitters, then mixing. The
first few levels are one mirror and one ring on a small board.

The **slow** one is everything after. The board cannot get any bigger, so what
grows instead is how far the light travels and how many pieces are wrong when
you arrive. It settles around par 7 with three targets, most of them involving a
mix or a splitter. Par deliberately stops climbing: a high par makes a level
*long* rather than hard, and length is not difficulty.

The first version of this ramp stopped at level 26 and every level after it was
identical. The soak test's banded report is what caught it, which is why that
report is in the test rather than a single average.

## Credits and the shop

Clearing a level pays credits, scaled by the level and by how close to par you
came. Replays pay a quarter, so going back to level 1 is never a better way to
earn than moving forward.

Spend them on **optics** (six beam treatments — how wide the core is, how far
the glow spreads, whether there is a white-hot centre) and **palettes** (five
board colourways). Palettes repaint the light itself, which is safe because
mixing happens on a three-bit colour mask rather than on pixels: a palette can
call red "coral" and green "jade" and their mix still lands wherever coral plus
jade lands. Nothing you buy changes a puzzle. Progress saves to
`user://lumen.save`.

## Project layout

```
main.tscn             an empty Node2D; main.gd builds the tree in code
scripts/config.gd     every tuning number, in one place (class LM)
scripts/main.gd       game manager: owns board, screens, the level you are on
scripts/grid.gd       one puzzle: cells, pieces, and the two orientation snapshots
scripts/beam.gd       the trace — what the light does, for everyone who asks
scripts/generator.gd  builds levels backwards from their own solution
scripts/board.gd      draws the board, turns taps into cells
scripts/pieces.gd     how each piece looks, from a centre and a size
scripts/legend.gd     one piece on its own, for the how-to screen
scripts/stars.gd      the three-star rating, drawn rather than typed
scripts/glow.gd       the one layer that animates
scripts/hud.gd  menus.gd  ui.gd   in-run readouts / screens / shared builders
scripts/skins.gd  save_data.gd    cosmetics catalogue and persistence
tests/smoke_test.gd   generator soak test
```

`Beam.trace()` is the single source of truth. The renderer draws what it
returns, the win check reads what it returns, and the generator validates its
own work through it — so what you see and what the game thinks cannot drift
apart.

## Performance

A puzzle is still between taps, so the board is rebuilt when the board changes
and never per frame. The rebuild sorts every beam segment into one bucket per
colour mask, so however tangled the light gets the whole beam layer draws in at
most seven `draw_multiline()` calls rather than one per segment.

That leaves the halo on a satisfied target and the ripple under a tap, which do
want to animate. They live on a separate `Glow` node drawing a handful of
circles, and with nothing lit and nothing tapped it does no work at all.

Generation runs about 1 ms per level, so a level loads within a frame and
nothing needs to be generated ahead of time or cached to disk.

## Running it

```sh
godot --path games/lumen                    # play on desktop
godot --headless --path games/lumen --import
tools/build_android.sh games/lumen          # an APK
tools/build_site.sh lumen                   # the web build, into docs/
```

Mouse input drives the game on desktop — Godot synthesises it from touch on
device, so one input path covers both.

### A note on symbols

Godot's fallback font is barely more than Latin-1. It has no `★`, no `✦`, and no
geometric shapes at all — `●`, `○`, `■` and `◆` are all absent. Anything on
screen that is not a letter therefore either has to be drawn (as the rating in
`scripts/stars.gd` is) or has to be one of the few that survive: `•`, `·`, `°`,
`†`. Check with `Font.has_char()` before typing a symbol into a label; it fails
silently as a missing-glyph box, and only on export.

### Tests

`tests/smoke_test.gd` generates levels and asserts, through the real tracer,
that each one generates, that the orientations it calls the solution really do
light every target, that the orientations it hands the player really do not,
that par is exactly the number of taps a canonical solve takes, and that
building the same level twice gives a byte-identical board — level numbers are
supposed to mean the same thing on every device.

```sh
godot --headless --path games/lumen --script tests/smoke_test.gd
godot --headless --path games/lumen --script tests/smoke_test.gd -- 5000
```

The trailing number is how many levels to check (default 500). It also prints
the shape of the ladder in bands, which is not a pass/fail thing but is the only
way to see whether difficulty is still going anywhere — averaged over a whole
run, a ramp that flattens out at level 26 looks identical to one that does not.
It is excluded from exported builds.

## Tuning

Everything worth adjusting lives in `scripts/config.gd`. The two couplings to
know about: every generator dial is a minimum plus a span across one of the two
difficulty ramps, so `RAMP_LEVELS` and `DEEP_LEVELS` move the whole game's pace
at once while the individual dials can be nudged independently. And beam colour
is a three-bit mask, so the mixing rule is a bitwise OR — the palette only
supplies what each bit looks like.

One ordering in the generator is load-bearing and was found by the soak test
rather than by thinking: mixes and splitters are grafted on immediately after
the first path, before the other independent paths are carved. Both need room,
and filling the board first quietly starves the two features that make a level
interesting rather than merely long.
