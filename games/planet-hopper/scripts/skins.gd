class_name Skins
extends RefCounted
## Catalogue of purchasable cosmetics.
##
## Ships change the hull silhouette and colours; themes repaint the whole
## starfield — planets, moons, background and stars. Neither affects handling,
## so buying is always a cosmetic choice and never a difficulty one.

## Hull silhouettes. `shape` indexes into Ship._hull_points().
static var SHIPS: Array[Dictionary] = [
	{
		"id": "scout", "name": "Scout", "cost": 0, "shape": 0,
		"blurb": "Standard issue. Reliable, unglamorous.",
		"hull": Color(0.91, 0.94, 1.0), "trim": Color(0.36, 0.55, 0.95),
		"flame": Color(1.0, 0.6, 0.24),
	},
	{
		"id": "ember", "name": "Ember", "cost": 250, "shape": 0,
		"blurb": "Runs hot. Looks better for it.",
		"hull": Color(0.95, 0.45, 0.25), "trim": Color(1.0, 0.83, 0.4),
		"flame": Color(1.0, 0.82, 0.35),
	},
	{
		"id": "hornet", "name": "Hornet", "cost": 450, "shape": 1,
		"blurb": "Short wings, bad attitude.",
		"hull": Color(0.97, 0.79, 0.16), "trim": Color(0.12, 0.12, 0.14),
		"flame": Color(1.0, 0.55, 0.15),
	},
	{
		"id": "glacier", "name": "Glacier", "cost": 700, "shape": 1,
		"blurb": "Cold hull, colder pilot.",
		"hull": Color(0.72, 0.92, 0.98), "trim": Color(0.24, 0.53, 0.72),
		"flame": Color(0.55, 0.86, 1.0),
	},
	{
		"id": "voidrunner", "name": "Void Runner", "cost": 1100, "shape": 2,
		"blurb": "Built for the long dark between suns.",
		"hull": Color(0.21, 0.18, 0.34), "trim": Color(0.35, 0.95, 0.87),
		"flame": Color(0.45, 1.0, 0.9),
	},
	{
		"id": "solaris", "name": "Solaris", "cost": 1600, "shape": 2,
		"blurb": "Gold-leafed. Wildly impractical.",
		"hull": Color(0.98, 0.85, 0.42), "trim": Color(0.7, 0.35, 0.1),
		"flame": Color(1.0, 0.94, 0.6),
	},
]

## World palettes.
static var THEMES: Array[Dictionary] = [
	{
		"id": "deep_field", "name": "Deep Field", "cost": 0,
		"blurb": "Space as you remember it.",
		"bg": Color(0.027, 0.031, 0.071), "star": Color(0.85, 0.88, 1.0),
		"oxygen": Color(0.24, 0.72, 0.47), "fuel": Color(0.93, 0.66, 0.24),
		"barren": Color(0.44, 0.42, 0.52), "moon": Color(0.78, 0.79, 0.86),
	},
	{
		"id": "nebula_rose", "name": "Nebula Rose", "cost": 400,
		"blurb": "A dust cloud with opinions.",
		"bg": Color(0.11, 0.04, 0.1), "star": Color(1.0, 0.86, 0.93),
		"oxygen": Color(0.35, 0.8, 0.66), "fuel": Color(0.99, 0.55, 0.45),
		"barren": Color(0.55, 0.33, 0.47), "moon": Color(0.93, 0.8, 0.87),
	},
	{
		"id": "emerald_drift", "name": "Emerald Drift", "cost": 750,
		"blurb": "Algae bloomed across half a galaxy.",
		"bg": Color(0.02, 0.08, 0.07), "star": Color(0.8, 1.0, 0.9),
		"oxygen": Color(0.4, 0.93, 0.55), "fuel": Color(0.85, 0.9, 0.3),
		"barren": Color(0.3, 0.47, 0.42), "moon": Color(0.75, 0.92, 0.85),
	},
	{
		"id": "rust_belt", "name": "Rust Belt", "cost": 1200,
		"blurb": "Somebody strip-mined the whole arm.",
		"bg": Color(0.1, 0.06, 0.03), "star": Color(1.0, 0.9, 0.75),
		"oxygen": Color(0.5, 0.72, 0.3), "fuel": Color(1.0, 0.72, 0.2),
		"barren": Color(0.57, 0.34, 0.2), "moon": Color(0.88, 0.76, 0.62),
	},
	{
		"id": "blueprint", "name": "Blueprint", "cost": 1800,
		"blurb": "You are flying inside the schematic.",
		"bg": Color(0.03, 0.06, 0.16), "star": Color(0.7, 0.85, 1.0),
		"oxygen": Color(0.35, 0.85, 1.0), "fuel": Color(0.6, 0.75, 1.0),
		"barren": Color(0.28, 0.38, 0.6), "moon": Color(0.7, 0.82, 1.0),
	},
]


static func ship(id: String) -> Dictionary:
	for s in SHIPS:
		if s.id == id:
			return s
	return SHIPS[0]


static func theme(id: String) -> Dictionary:
	for t in THEMES:
		if t.id == id:
			return t
	return THEMES[0]
