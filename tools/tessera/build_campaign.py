#!/usr/bin/env python3
"""Builds Tessera's campaign.

Four dimensional level design cannot be done by eye. A chamber that looks
obviously solvable often is not, and one that looks impossible is frequently
three moves long. So no chamber ships until this has proved it:

  * a breadth-first search over the entire reachable state space — position,
    frame orientation and keys held — finds the shortest solution, which
    becomes the chamber's par;
  * chambers that do not force the player to use the fourth dimension, or that
    fall below a stratum's difficulty floor, are thrown away and regenerated.

The generator itself works backwards from the answer, the same trick the second
game in this repo used: walk a random route through the 4D volume first, then
carve exactly that route out of solid rock. Everything the walk did not touch
stays solid, so the route is guaranteed to exist. The solver then tells us
whether it is the *interesting* route or whether a shortcut appeared.

Run:  python3 tools/tessera/build_campaign.py
Writes: games/tessera/scripts/campaign.gd
"""

from __future__ import annotations

import random
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "games/tessera/scripts/campaign.gd"

X, Y, Z, W = 0, 1, 2, 3
IDENT = ((X, 1), (Y, 1), (Z, 1), (W, 1))
DOWN = (0, -1, 0, 0)
UP = (0, 1, 0, 0)

SOLID, AIR = "#", "."
GOAL, START, HAZARD, SHARD, FIELD = "G", "S", "^", "*", "~"
DOORS, KEYS = "1234", "abcd"

BLOCKING = {SOLID}


# --------------------------------------------------------------------------
# frames


def rotate(frame, slot, d):
    """Turn frame vector `slot` into the hidden one through a right angle.

    Mirrors Hyper.rotated_frame() at t = 1 exactly; if these two ever disagree
    the solver is proving things about a different game than the one shipping.
    """
    v = list(frame)
    a, b = v[slot], v[3]
    if d > 0:
        v[slot], v[3] = b, (a[0], -a[1])
    else:
        v[slot], v[3] = (b[0], -b[1]), a
    return tuple(v)


def add(cell, av, n=1):
    axis, sign = av
    c = list(cell)
    c[axis] += sign * n
    return tuple(c)


def offset(cell, d):
    return (cell[0] + d[0], cell[1] + d[1], cell[2] + d[2], cell[3] + d[3])


# --------------------------------------------------------------------------
# chambers


class Chamber:
    def __init__(self, size):
        self.size = tuple(size)
        self.cells = {}
        self.start = (1, 1, 1, 0)
        self.name = "Chamber"
        self.hint = ""
        self.stratum = 1
        self.allow_zw = False
        self.allow_xw = False
        self.par = 0
        self.solution = []

    # -- geometry
    def inside(self, c):
        return all(0 <= c[i] < self.size[i] for i in range(4))

    def get(self, c):
        return self.cells.get(c, AIR)

    def put(self, c, ch):
        if self.inside(c):
            self.cells[c] = ch

    def blocked(self, c, keys):
        ch = self.cells.get(c, AIR)
        if ch in DOORS:
            return not (keys >> DOORS.index(ch)) & 1
        return ch in BLOCKING

    def shard_count(self):
        return sum(1 for v in self.cells.values() if v == SHARD)

    # -- rules, mirroring scripts/game.gd
    def settle_keys(self, cell, keys):
        for _ in range(64):
            below = offset(cell, DOWN)
            if self.blocked(below, keys):
                break
            cell = below
            if cell[1] < 0:
                return None
        return cell

    def text(self):
        sx, sy, sz, sw = self.size
        rot = "none"
        if self.allow_zw and self.allow_xw:
            rot = "both"
        elif self.allow_zw:
            rot = "zw"
        elif self.allow_xw:
            rot = "xw"
        head = [
            f"name: {self.name}",
            f"stratum: {self.stratum}",
        ]
        if self.hint:
            head.append(f"hint: {self.hint}")
        head += [f"rot: {rot}", f"par: {self.par}", f"size: {sx} {sy} {sz} {sw}"]

        body = []
        for w in range(sw):
            for y in range(sy):
                rows = []
                used = False
                for z in range(sz):
                    row = []
                    for x in range(sx):
                        c = (x, y, z, w)
                        ch = START if c == self.start else self.cells.get(c, AIR)
                        if ch != AIR:
                            used = True
                        row.append(ch)
                    rows.append("".join(row))
                if used:
                    body.append(f"--- y{y} w{w}")
                    body += rows
        return "\n".join(head + body) + "\n"


def parse(text):
    """The same format scripts/level.gd reads, so the tool and the game agree."""
    ch = Chamber((8, 4, 8, 2))
    cur = None
    rows = []
    grids = {}
    for raw in text.splitlines():
        line = raw.rstrip()
        if line.startswith("---"):
            if cur is not None:
                grids[cur] = rows
            y = w = 0
            for p in line[3:].strip().split():
                if p.startswith("y"):
                    y = int(p[1:])
                elif p.startswith("w"):
                    w = int(p[1:])
            cur, rows = (y, w), []
            continue
        if cur is not None:
            rows.append(line)
            continue
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k, v = k.strip(), v.strip()
        if k == "name":
            ch.name = v
        elif k == "hint":
            ch.hint = v
        elif k == "stratum":
            ch.stratum = int(v)
        elif k == "par":
            ch.par = int(v)
        elif k == "rot":
            ch.allow_zw = v in ("zw", "both")
            ch.allow_xw = v in ("xw", "both")
        elif k == "size":
            ch.size = tuple(int(n) for n in v.split())
    if cur is not None:
        grids[cur] = rows
    for (y, w), rws in grids.items():
        for z, row in enumerate(rws):
            for x, c in enumerate(row):
                if c == AIR or c == " ":
                    continue
                if c == START:
                    ch.start = (x, y, z, w)
                else:
                    ch.cells[(x, y, z, w)] = c
    return ch


# --------------------------------------------------------------------------
# solver


def successors(ch, cell, frame, keys):
    """Every state one player action away, as (cell, frame, keys, kind)."""
    out = []

    for slot in (0, 2):
        for sign in (1, -1):
            d = (frame[slot][0], frame[slot][1] * sign)
            target = add(cell, d)
            if ch.blocked(target, keys):
                up = offset(target, UP)
                head = offset(cell, UP)
                if ch.blocked(up, keys) or ch.blocked(head, keys):
                    continue
                target = up
            landed = ch.settle_keys(target, keys)
            if landed is None:
                continue
            out.append((landed, frame, keys, "w%d%s" % (slot, "+" if sign > 0 else "-")))

    for sign in (1, -1):
        d = (frame[3][0], frame[3][1] * sign)
        target = add(cell, d)
        if ch.blocked(target, keys):
            continue
        landed = ch.settle_keys(target, keys)
        if landed is None:
            continue
        out.append((landed, frame, keys, "s%s" % ("+" if sign > 0 else "-")))

    slots = []
    if ch.allow_zw:
        slots.append(2)
    if ch.allow_xw:
        slots.append(0)
    if ch.get(cell) != FIELD:
        for slot in slots:
            for d in (1, -1):
                nf = rotate(frame, slot, d)
                landed = ch.settle_keys(cell, keys)
                if landed is None:
                    continue
                out.append((landed, nf, keys, "r%d%s" % (slot, "+" if d > 0 else "-")))

    return out


def analyse(ch):
    """One search of the whole chamber, from which everything else follows.

    Returns (depth, arrival, back): the fewest moves that reach each cell, the
    state it was first reached in, and the parent map for reconstructing a
    route. Doing this once rather than once per candidate exit is the
    difference between generating a stratum in seconds and in an hour — the
    search over position, orientation and keys is by far the most expensive
    thing in this file.
    """
    start = ch.settle_keys(ch.start, 0)
    if start is None:
        return {}, {}, {}
    s0 = (start, IDENT, 0)
    back = {s0: None}
    depth = {start: 0}
    arrival = {start: s0}
    q = deque([(s0, 0)])
    while q:
        state, d = q.popleft()
        cell, frame, keys = state
        for ncell, nframe, nkeys, kind in successors(ch, cell, frame, keys):
            here = ch.get(ncell)
            if here == HAZARD:
                continue
            if here in KEYS:
                nkeys = nkeys | (1 << KEYS.index(here))
            st = (ncell, nframe, nkeys)
            if st in back:
                continue
            back[st] = (state, kind)
            if ncell not in depth:
                depth[ncell] = d + 1
                arrival[ncell] = st
            q.append((st, d + 1))
    return depth, arrival, back


def route_to(back, state):
    """The action kinds and the cells along the shortest route to a state."""
    kinds, cells = [], [state[0]]
    cur = state
    while back[cur] is not None:
        prev, kind = back[cur]
        kinds.append(kind)
        cells.append(prev[0])
        cur = prev
    kinds.reverse()
    return kinds, cells


def solve(ch, max_states=1_500_000):
    """Shortest solution as (length, action kinds, cells walked), or None."""
    start = ch.settle_keys(ch.start, 0)
    if start is None or ch.get(start) == HAZARD:
        return None
    s0 = (start, IDENT, 0)
    seen = {s0: None}
    q = deque([s0])
    goal_state = None

    while q:
        cell, frame, keys = q.popleft()
        if ch.get(cell) == GOAL:
            goal_state = (cell, frame, keys)
            break
        for ncell, nframe, nkeys, kind in successors(ch, cell, frame, keys):
            here = ch.get(ncell)
            if here == HAZARD:
                continue
            if here in KEYS:
                nkeys = nkeys | (1 << KEYS.index(here))
            st = (ncell, nframe, nkeys)
            if st in seen:
                continue
            if len(seen) > max_states:
                return None
            seen[st] = ((cell, frame, keys), kind)
            q.append(st)

    if goal_state is None:
        return None

    kinds, cells = [], [goal_state[0]]
    cur = goal_state
    while seen[cur] is not None:
        prev, kind = seen[cur]
        kinds.append(kind)
        cells.append(prev[0])
        cur = prev
    kinds.reverse()
    return len(kinds), kinds, cells


# --------------------------------------------------------------------------
# generation


def carve(rng, size, allow_zw, allow_xw, target, weights):
    """Grow a corridor through the 4D volume, then cut it out of solid rock.

    Three details decide whether the result is a puzzle or a formality.

    The corridor keeps a cell of rock between its own passes. Two corridor
    cells that merely end up side by side are connected whether the walk meant
    them to be or not, and a handful of those shortcuts collapses a forty step
    route into a six move solution.

    It backtracks when it runs out of room, the way any maze generator does, so
    what comes out is a spanning tree rather than a single thread — and the
    branches it abandons become the chamber's dead ends.

    And it climbs. Without height there is no reason to ever turn: the three
    horizontal world axes are always all available, two to walk along and one
    to shift along, so a flat corridor can be followed without ever using the
    fourth dimension as more than a sideways step. Stepping *up* is the
    asymmetry. It works along the axes you can see and not along the one you
    cannot, so a corridor that rises along the hidden axis cannot be climbed
    until you turn that axis into view. That one rule is what makes the game's
    central move necessary rather than decorative.
    """
    sx, sy, sz, sw = size
    start = (rng.randrange(1, sx - 1), 1, rng.randrange(1, sz - 1), rng.randrange(sw))
    visited = {start}
    order = [start]
    stack = [start]

    def free_of_neighbours(target_cell, came_from):
        if target_cell in visited:
            return False
        for axis in range(4):
            for sgn in (-1, 1):
                nb = list(target_cell)
                nb[axis] += sgn
                nb = tuple(nb)
                if nb != came_from and nb in visited:
                    return False
        return True

    # weights bias which axis the corridor prefers; the third entry is how
    # often it tries to rise.
    axis_bag = [0] * weights[0] + [2] * weights[0] + [3] * weights[1]
    climb_chance = weights[2] / 12.0

    while len(order) < target and stack:
        cell = stack[-1]
        cands = []
        for axis in (0, 2, 3):
            for sgn in (-1, 1):
                base = list(cell)
                base[axis] += sgn
                for rise in ((0, 1) if rng.random() < climb_chance else (0,)):
                    t = (base[0], base[1] + rise, base[2], base[3])
                    if not all(0 <= t[i] < size[i] for i in range(4)):
                        continue
                    if not (1 <= t[1] <= sy - 2):
                        continue
                    if rise:
                        ledge = (t[0], t[1] - 1, t[2], t[3])
                        if ledge in visited:
                            continue
                    if free_of_neighbours(t, cell):
                        cands.append((axis, t))
        if not cands:
            stack.pop()
            continue
        want = rng.choice(axis_bag)
        pool = [t for a, t in cands if a == want] or [t for _a, t in cands]
        nxt = rng.choice(pool)
        visited.add(nxt)
        order.append(nxt)
        stack.append(nxt)

    ch = Chamber(size)
    ch.allow_zw, ch.allow_xw = allow_zw, allow_xw

    # Everything is stone until the corridor says otherwise.
    for w in range(sw):
        for y in range(sy):
            for z in range(sz):
                for x in range(sx):
                    ch.cells[(x, y, z, w)] = SOLID

    for c in order:
        ch.cells[c] = AIR
        head = offset(c, UP)
        if ch.inside(head):
            ch.cells[head] = AIR
    # Floors go down only after every cell is carved, so a corridor passing
    # underneath another still gets its ceiling back.
    for c in order:
        floor = offset(c, DOWN)
        if ch.inside(floor) and floor not in visited:
            ch.cells[floor] = SOLID

    ch.start = order[0]
    ch.cells[order[0]] = AIR
    return ch, order, 0, 0


def pick_exit(ch, spec):
    """The furthest exit whose shortest route actually uses the fourth dimension.

    Every reachable cell is a candidate. Taking them furthest-first and keeping
    the first that clears the stratum's floor gives the hardest chamber this
    carving can support, without generating anything twice. Straight-line
    distance is no guide at all: in four dimensions the cell two steps away is
    regularly the last one the search finds.
    """
    depth, arrival, back = analyse(ch)
    if not depth:
        return None
    for cell in sorted(depth, key=lambda c: -depth[c]):
        if depth[cell] < spec["min_par"]:
            return None          # sorted, so nothing further down will do
        kinds, cells = route_to(back, arrival[cell])
        if sum(1 for k in kinds if k[0] == "s") < spec["min_shift"]:
            continue
        if sum(1 for k in kinds if k[0] == "r") < spec["min_rot"]:
            continue
        return cell, depth[cell], kinds, cells
    return None


def sprinkle_shards(ch, rng, solution_cells, n):
    """Shards sit on branches of the corridor the optimal route never takes, so
    collecting them costs moves — which is the whole point of them."""
    spine = set(solution_cells)
    pockets = [
        c for c, v in ch.cells.items()
        if v == AIR and c not in spine and c[1] == 1
        and ch.cells.get(offset(c, DOWN)) == SOLID
        and c != ch.start
    ]
    rng.shuffle(pockets)
    for c in pockets[:n]:
        ch.cells[c] = SHARD


STRATA = [
    dict(
        n=9, stratum=1, size=(9, 7, 9, 3), zw=False, xw=False,
        steps=(16, 26), weights=(6, 4, 1), min_par=10, min_shift=3, min_rot=0,
    ),
    dict(
        n=10, stratum=2, size=(10, 8, 10, 3), zw=True, xw=False,
        steps=(24, 36), weights=(6, 4, 4), min_par=14, min_shift=3, min_rot=1,
    ),
    dict(
        n=10, stratum=3, size=(11, 9, 11, 4), zw=True, xw=True,
        steps=(32, 46), weights=(6, 4, 6), min_par=18, min_shift=4, min_rot=2,
    ),
    dict(
        n=11, stratum=4, size=(12, 9, 12, 5), zw=True, xw=True,
        steps=(46, 64), weights=(6, 5, 7), min_par=26, min_shift=5, min_rot=2,
    ),
]

NAMES = [
    "Threshold", "Ana", "Kata", "Offset", "Sidestep", "The Thin Wall", "Parallax",
    "Interleave", "Quarter Turn", "Edgewise", "Facing", "Unfold", "Cross Section",
    "Hinge", "The Long Way Round", "Reveal", "Orthogonal", "Sleight", "Fold Line",
    "Displacement", "Two Axes", "Chiral", "The Second Hinge", "Recursion",
    "Meridian", "Lattice", "Involute", "Klein", "Hypersill", "Manifold",
    "Deep Cut", "Antechamber", "The Fourth Wall", "Tesseract", "Cell Complex",
    "Null Section", "Boundary", "Coordinate", "The Last Turn", "Closure",
    "Vestibule", "Aperture", "Transept", "Ambulatory", "Reliquary", "Crypt",
    "Oratory", "Narthex", "Clerestory", "Apse",
]


def generate(rng, spec, index):
    """Carve until one survives the search and the stratum's difficulty floor."""
    for _ in range(60):
        target = rng.randint(*spec["steps"])
        ch, route, _, _ = carve(
            rng, spec["size"], spec["zw"], spec["xw"], target, spec["weights"])
        found = pick_exit(ch, spec)
        if found is None:
            continue
        goal, par, _kinds, cells = found
        ch.cells[goal] = GOAL
        ch.stratum = spec["stratum"]
        ch.par = par
        ch.solution = _kinds
        # Shards are walked through, never around, so they cannot change par.
        sprinkle_shards(ch, rng, cells, rng.randint(1, 3))
        ch.name = NAMES[index % len(NAMES)]
        return ch
    return None


# --------------------------------------------------------------------------
# handwritten chambers
#
# Only the opening three are placed by hand, and even those are built with code
# rather than typed as ASCII: a plate here, a wall there. Laying out four
# dimensions character by character is how you end up with an exit standing on
# nothing.


def plate(ch, x0, x1, z0, z1, y, w, glyph=SOLID):
    for x in range(x0, x1 + 1):
        for z in range(z0, z1 + 1):
            ch.put((x, y, z, w), glyph)


def wall(ch, x, z0, z1, y, w, height=2):
    """Walls are two cells tall. A one-cell wall is not a wall — the step-up
    rule lets the player climb straight over it."""
    for z in range(z0, z1 + 1):
        for dy in range(height):
            ch.put((x, y + dy, z, w), SOLID)


def tut_threshold():
    """One wall, and a slice next door where it does not exist."""
    ch = Chamber((7, 4, 5, 2))
    ch.name = "Threshold"
    ch.hint = "The wall is only a wall in the slice you stand in. Step ana to get past it."
    plate(ch, 1, 5, 1, 3, 0, 0)
    wall(ch, 3, 1, 3, 1, 0)
    plate(ch, 2, 4, 2, 2, 0, 1)      # the bypass, one step ana
    ch.start = (1, 1, 2, 0)
    ch.cells[(5, 1, 2, 0)] = GOAL
    return ch


def tut_ana_kata():
    """Two walls, two bypasses, and a return trip."""
    ch = Chamber((9, 4, 5, 3))
    ch.name = "Ana and Kata"
    ch.hint = "Q steps back the other way. Warm outlines are ana of you; cool ones kata."
    plate(ch, 1, 7, 1, 3, 0, 0)
    wall(ch, 3, 1, 3, 1, 0)
    wall(ch, 5, 1, 3, 1, 0)
    plate(ch, 2, 4, 2, 2, 0, 1)
    ch.put((7, 0, 2, 1), SOLID)      # the step back down at the far end
    plate(ch, 4, 7, 2, 2, 0, 2)
    ch.start = (1, 1, 2, 0)
    ch.cells[(7, 1, 2, 0)] = GOAL
    return ch


def tut_offset():
    """A shard off the obvious line, to make the scope worth reading."""
    ch = Chamber((9, 4, 7, 3))
    ch.name = "Offset"
    ch.hint = "The scope, bottom left, is your own column read along the hidden axis."
    plate(ch, 1, 7, 1, 5, 0, 0)
    wall(ch, 4, 1, 5, 1, 0)
    plate(ch, 3, 5, 1, 5, 0, 1)
    ch.put((4, 1, 1, 1), SHARD)
    ch.start = (1, 1, 3, 0)
    ch.cells[(7, 1, 3, 0)] = GOAL
    return ch


TUTORIALS = [tut_threshold, tut_ana_kata, tut_offset]

## Named openings for each stratum, so the generated chambers still arrive with
## something to say the first time a mechanic appears.
STRATUM_INTRO = {
    2: ("Quarter Turn",
        "F turns depth into the hidden axis. Watch what the walls do."),
    3: ("Two Hinges",
        "G turns the other way, across. Both turns are yours now."),
    4: ("The Deep Lattice",
        "Nothing new from here. Only further in."),
}


def main():
    rng = random.Random(20260728)
    chambers = []

    for build in TUTORIALS:
        ch = build()
        res = solve(ch)
        if res is None:
            print(f"  !! tutorial {ch.name!r} is NOT SOLVABLE", file=sys.stderr)
            return 1
        ch.par = res[0]
        ch.solution = res[1]
        chambers.append(ch)
        print(f"  hand  {ch.name:22s} par {ch.par:3d}  "
              f"shift {sum(1 for k in res[1] if k[0] == 's')} "
              f"rot {sum(1 for k in res[1] if k[0] == 'r')}", flush=True)

    index = len(chambers)
    for spec in STRATA:
        made = 0
        tries = 0
        while made < spec["n"] and tries < spec["n"] * 30:
            tries += 1
            ch = generate(rng, spec, index)
            if ch is None:
                continue
            chambers.append(ch)
            print(f"  gen   {ch.name:22s} par {ch.par:3d}  stratum {ch.stratum}"
                  f"  {ch.size}  shards {ch.shard_count()}", flush=True)
            index += 1
            made += 1
        if made < spec["n"]:
            print(f"  !! stratum {spec['stratum']} only produced {made}/{spec['n']}",
                  file=sys.stderr)

    # Order by stratum then by par, so difficulty climbs steadily.
    chambers.sort(key=lambda c: (c.stratum, c.par))

    # Introduce each stratum's mechanic on its first chamber.
    seen = set()
    for c in chambers:
        if c.stratum in STRATUM_INTRO and c.stratum not in seen:
            seen.add(c.stratum)
            c.name, c.hint = STRATUM_INTRO[c.stratum]

    # Every chamber ships as text, so prove the text is what we solved.
    for c in chambers:
        again = solve(parse(c.text()))
        if again is None or again[0] != c.par:
            print(f"  !! {c.name!r} does not survive the round trip through text",
                  file=sys.stderr)
            return 1

    body = ",\n".join('"""\n' + c.text() + '"""' for c in chambers)
    sols = ",\n".join('\t"%s"' % " ".join(c.solution) for c in chambers)
    OUT.write_text(HEADER + body + FOOTER.replace("$SOLUTIONS$", sols))
    print(f"\nwrote {OUT.relative_to(ROOT)} — {len(chambers)} chambers, "
          f"par {min(c.par for c in chambers)}..{max(c.par for c in chambers)}")
    return 0


HEADER = '''class_name Campaign
extends RefCounted

## The chambers, as source text.
##
## GENERATED — do not edit by hand. tools/tessera/build_campaign.py writes this
## file. It parses the same format scripts/level.gd reads, proves every chamber
## solvable with a breadth-first search over the whole state space of position,
## orientation and keys, and records the shortest solution as par. A chamber
## that does not force the player to use the fourth dimension never gets in.

const SOURCES := [
'''

FOOTER = ''',
]


static func count() -> int:
	return SOURCES.size()


static func get_level(i: int) -> Level:
	return Level.parse(SOURCES[clampi(i, 0, SOURCES.size() - 1)])


static func id(i: int) -> String:
	return "ch%03d" % i


## One optimal solution per chamber, as replayable actions:
##   wN+/wN-  walk along frame slot N      sN+/sN-  step ana or kata
##   rN+/rN-  turn frame slot N into the hidden axis
##
## tests/solve_test.gd replays every one of these through the real game code and
## checks it reaches the exit in exactly par moves. That is what keeps the
## solver honest: if the rules in game.gd and the rules in the generator ever
## drift apart, these stop working.
const SOLUTIONS := [
$SOLUTIONS$,
]


static func solution(i: int) -> PackedStringArray:
	return SOLUTIONS[clampi(i, 0, SOLUTIONS.size() - 1)].split(" ", false)


## Chambers are ordered by stratum; this is where each one starts.
static func stratum_of(i: int) -> int:
	var t := SOURCES[clampi(i, 0, SOURCES.size() - 1)] as String
	var at := t.find("stratum:")
	return 1 if at < 0 else int(t.substr(at + 8, 3).strip_edges())
'''


if __name__ == "__main__":
    raise SystemExit(main())
