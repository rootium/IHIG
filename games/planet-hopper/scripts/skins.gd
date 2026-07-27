class_name Skins
extends RefCounted
## Catalogue of purchasable cosmetics.
##
## Ships change the hull silhouette and colours; themes repaint the starfield —
## planets, moons, stars, background and the target ring. Neither affects
## handling, so buying is always a cosmetic choice and never a difficulty one.
##
## Hazards deliberately keep the same colours across every theme. A moon or a
## black hole has to read as danger at a glance, and that is worth more than
## palette consistency.

## Hull silhouettes. `shape` indexes into Ship._hull_points().
static var SHIPS: Array[Dictionary] = [
	{
		"id": "scout", "name": "Scout", "cost": 0, "shape": 0,
		"blurb": "Standard issue. Reliable, unglamorous.",
		"hull": Color(0.94, 0.96, 1.0), "trim": Color(0.36, 0.77, 0.91),
		"flame": Color(1.0, 0.62, 0.26),
	},
	{
		"id": "ember", "name": "Ember", "cost": 250, "shape": 0,
		"blurb": "Runs hot. Looks better for it.",
		"hull": Color(0.96, 0.55, 0.38), "trim": Color(1.0, 0.86, 0.5),
		"flame": Color(1.0, 0.84, 0.4),
	},
	{
		"id": "hornet", "name": "Hornet", "cost": 450, "shape": 1,
		"blurb": "Short wings, bad attitude.",
		"hull": Color(0.97, 0.81, 0.29), "trim": Color(0.16, 0.16, 0.2),
		"flame": Color(1.0, 0.58, 0.2),
	},
	{
		"id": "glacier", "name": "Glacier", "cost": 700, "shape": 1,
		"blurb": "Cold hull, colder pilot.",
		"hull": Color(0.76, 0.93, 0.98), "trim": Color(0.3, 0.58, 0.76),
		"flame": Color(0.6, 0.88, 1.0),
	},
	{
		"id": "voidrunner", "name": "Void Runner", "cost": 1100, "shape": 2,
		"blurb": "Built for the long dark between suns.",
		"hull": Color(0.29, 0.25, 0.42), "trim": Color(0.4, 0.96, 0.88),
		"flame": Color(0.5, 1.0, 0.92),
	},
	{
		"id": "solaris", "name": "Solaris", "cost": 1600, "shape": 2,
		"blurb": "Gold-leafed. Wildly impractical.",
		"hull": Color(0.98, 0.87, 0.5), "trim": Color(0.74, 0.4, 0.14),
		"flame": Color(1.0, 0.95, 0.66),
	},
]

## World palettes.
static var THEMES: Array[Dictionary] = [
	{
		"id": "deep_field", "name": "Deep Field", "cost": 0,
		"blurb": "Space as you remember it.",
		"bg": Color(0.051, 0.067, 0.157), "star": Color(0.85, 0.88, 1.0),
		"oxygen": Color(0.53, 0.80, 0.53), "fuel": Color(0.96, 0.66, 0.42),
		"barren": Color(0.66, 0.55, 0.96), "moon": Color(0.80, 0.82, 0.90),
		"ring": Color(0.36, 0.77, 0.91), "ring_idle": Color(0.45, 0.48, 0.58),
		"star_pickup": Color(1.0, 0.82, 0.29),
	},
	{
		"id": "nebula_rose", "name": "Nebula Rose", "cost": 400,
		"blurb": "A dust cloud with opinions.",
		"bg": Color(0.12, 0.045, 0.11), "star": Color(1.0, 0.87, 0.94),
		"oxygen": Color(0.45, 0.85, 0.72), "fuel": Color(0.99, 0.6, 0.5),
		"barren": Color(0.72, 0.45, 0.68), "moon": Color(0.94, 0.83, 0.89),
		"ring": Color(0.98, 0.62, 0.78), "ring_idle": Color(0.55, 0.42, 0.52),
		"star_pickup": Color(1.0, 0.86, 0.42),
	},
	{
		"id": "emerald_drift", "name": "Emerald Drift", "cost": 750,
		"blurb": "Algae bloomed across half a galaxy.",
		"bg": Color(0.028, 0.085, 0.075), "star": Color(0.82, 1.0, 0.91),
		"oxygen": Color(0.48, 0.93, 0.6), "fuel": Color(0.88, 0.92, 0.42),
		"barren": Color(0.38, 0.6, 0.55), "moon": Color(0.78, 0.93, 0.86),
		"ring": Color(0.45, 0.95, 0.75), "ring_idle": Color(0.4, 0.55, 0.5),
		"star_pickup": Color(1.0, 0.9, 0.4),
	},
	{
		"id": "rust_belt", "name": "Rust Belt", "cost": 1200,
		"blurb": "Somebody strip-mined the whole arm.",
		"bg": Color(0.11, 0.068, 0.04), "star": Color(1.0, 0.91, 0.78),
		"oxygen": Color(0.6, 0.78, 0.38), "fuel": Color(1.0, 0.75, 0.3),
		"barren": Color(0.68, 0.44, 0.28), "moon": Color(0.9, 0.79, 0.66),
		"ring": Color(1.0, 0.72, 0.35), "ring_idle": Color(0.55, 0.44, 0.35),
		"star_pickup": Color(1.0, 0.88, 0.45),
	},
	{
		"id": "blueprint", "name": "Blueprint", "cost": 1800,
		"blurb": "You are flying inside the schematic.",
		"bg": Color(0.035, 0.07, 0.18), "star": Color(0.72, 0.87, 1.0),
		"oxygen": Color(0.42, 0.88, 1.0), "fuel": Color(0.64, 0.78, 1.0),
		"barren": Color(0.34, 0.45, 0.7), "moon": Color(0.74, 0.85, 1.0),
		"ring": Color(0.6, 0.92, 1.0), "ring_idle": Color(0.4, 0.5, 0.7),
		"star_pickup": Color(1.0, 0.85, 0.35),
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
