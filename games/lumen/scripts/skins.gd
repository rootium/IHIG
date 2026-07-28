class_name Skins
extends RefCounted
## Catalogue of purchasable cosmetics.
##
## Palettes repaint the board and, unusually, the light itself — the three
## colour channels are palette-defined. That is safe because mixing happens on
## the colour mask, not on the pixels: a palette can call red "coral" and green
## "jade" and their mix still lands wherever coral plus jade lands, which is
## still visibly neither. Every palette is checked to keep its three channels
## far apart in hue, since telling them apart is the game.
##
## Optics restyle the beams — how wide the core is, how far the glow spreads,
## whether there is a white-hot centre — and the colour of the mirror pieces.
## Neither kind of purchase changes a puzzle, so buying is always taste.

static var OPTICS: Array[Dictionary] = [
	{
		"id": "standard", "name": "Standard", "cost": 0,
		"blurb": "Issue optics. Clean, honest light.",
		"core": 1.0, "glow": 3.4, "hot": 0.0, "piece": Color(0.86, 0.90, 1.0),
	},
	{
		"id": "hairline", "name": "Hairline", "cost": 200,
		"blurb": "Thin and exact. For people who like straight lines.",
		"core": 0.62, "glow": 2.2, "hot": 0.45, "piece": Color(0.72, 0.80, 0.92),
	},
	{
		"id": "flood", "name": "Flood", "cost": 380,
		"blurb": "Overdriven. The whole board catches the spill.",
		"core": 1.5, "glow": 5.6, "hot": 0.0, "piece": Color(0.92, 0.94, 1.0),
	},
	{
		"id": "filament", "name": "Filament", "cost": 620,
		"blurb": "A burning wire down the middle of every beam.",
		"core": 1.25, "glow": 4.2, "hot": 0.7, "piece": Color(1.0, 0.93, 0.78),
	},
	{
		"id": "obsidian", "name": "Obsidian", "cost": 900,
		"blurb": "Black glass. The light is the only thing you see.",
		"core": 1.05, "glow": 3.0, "hot": 0.25, "piece": Color(0.30, 0.32, 0.40),
	},
	{
		"id": "coldfire", "name": "Cold Fire", "cost": 1400,
		"blurb": "Wide, bright and slightly too much.",
		"core": 1.7, "glow": 6.5, "hot": 0.85, "piece": Color(0.80, 0.98, 1.0),
	},
]

static var PALETTES: Array[Dictionary] = [
	{
		"id": "darkroom", "name": "Darkroom", "cost": 0,
		"blurb": "Somewhere quiet, with the lights off.",
		"bg": Color(0.043, 0.047, 0.086), "board": Color(0.078, 0.086, 0.145),
		"grid": Color(1.0, 1.0, 1.0, 0.05), "wall": Color(0.20, 0.22, 0.31),
		"ink": Color(0.88, 0.91, 1.0),
		"r": Color(1.0, 0.30, 0.38), "g": Color(0.36, 0.95, 0.55), "b": Color(0.38, 0.63, 1.0),
	},
	{
		"id": "blueprint", "name": "Blueprint", "cost": 350,
		"blurb": "Drafting paper, and light that behaves.",
		"bg": Color(0.035, 0.078, 0.16), "board": Color(0.06, 0.12, 0.24),
		"grid": Color(0.6, 0.8, 1.0, 0.10), "wall": Color(0.17, 0.30, 0.48),
		"ink": Color(0.82, 0.92, 1.0),
		"r": Color(1.0, 0.52, 0.42), "g": Color(0.42, 1.0, 0.78), "b": Color(0.44, 0.60, 1.0),
	},
	{
		"id": "greenhouse", "name": "Greenhouse", "cost": 650,
		"blurb": "Warm glass, and something growing under it.",
		"bg": Color(0.035, 0.075, 0.055), "board": Color(0.06, 0.125, 0.09),
		"grid": Color(0.7, 1.0, 0.8, 0.08), "wall": Color(0.17, 0.32, 0.22),
		"ink": Color(0.86, 1.0, 0.90),
		"r": Color(1.0, 0.46, 0.30), "g": Color(0.52, 1.0, 0.40), "b": Color(0.35, 0.72, 1.0),
	},
	{
		"id": "amberlab", "name": "Amber Lab", "cost": 1000,
		"blurb": "Somebody left the safelight on.",
		"bg": Color(0.10, 0.056, 0.032), "board": Color(0.16, 0.09, 0.05),
		"grid": Color(1.0, 0.8, 0.5, 0.09), "wall": Color(0.36, 0.22, 0.12),
		"ink": Color(1.0, 0.92, 0.80),
		"r": Color(1.0, 0.36, 0.26), "g": Color(0.72, 1.0, 0.34), "b": Color(0.40, 0.70, 1.0),
	},
	{
		"id": "vacuum", "name": "Vacuum", "cost": 1500,
		"blurb": "No walls, no air, no excuses.",
		"bg": Color(0.015, 0.015, 0.022), "board": Color(0.035, 0.037, 0.05),
		"grid": Color(1.0, 1.0, 1.0, 0.045), "wall": Color(0.13, 0.135, 0.17),
		"ink": Color(0.94, 0.95, 1.0),
		"r": Color(1.0, 0.22, 0.46), "g": Color(0.30, 1.0, 0.62), "b": Color(0.36, 0.56, 1.0),
	},
]


static func optic(id: String) -> Dictionary:
	for o in OPTICS:
		if o.id == id:
			return o
	return OPTICS[0]


static func palette(id: String) -> Dictionary:
	for p in PALETTES:
		if p.id == id:
			return p
	return PALETTES[0]
