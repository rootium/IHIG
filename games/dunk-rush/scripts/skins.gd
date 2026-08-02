class_name Skins
extends RefCounted
## Catalogue of purchasable cosmetics.
##
## Ballers change the kit you wear and the ball you carry; arenas repaint the
## rim, backboard, net, crowd and background. Neither touches handling, so
## buying is always a cosmetic choice and never a difficulty one.
##
## Hazards deliberately keep their colours across every arena. A defender or a
## loose ball has to read as danger at a glance, and that is worth more than
## palette consistency.

static var BALLERS: Array[Dictionary] = [
	{
		"id": "rookie", "name": "Rookie", "cost": 0,
		"blurb": "Practice kit and a borrowed ball.",
		"jersey": Color(0.36, 0.77, 0.91), "trim": Color(0.95, 0.97, 1.0),
		"ball": Color(0.95, 0.48, 0.20), "skin": Color(0.85, 0.66, 0.48),
	},
	{
		"id": "streetball", "name": "Streetball", "cost": 250,
		"blurb": "No referees where this one learned.",
		"jersey": Color(0.18, 0.19, 0.24), "trim": Color(0.98, 0.76, 0.22),
		"ball": Color(0.88, 0.40, 0.16), "skin": Color(0.55, 0.38, 0.26),
	},
	{
		"id": "allstar", "name": "All-Star", "cost": 450,
		"blurb": "Voted in. Loudly.",
		"jersey": Color(0.92, 0.28, 0.34), "trim": Color(1.0, 0.93, 0.72),
		"ball": Color(0.98, 0.58, 0.25), "skin": Color(0.72, 0.52, 0.36),
	},
	{
		"id": "throwback", "name": "Throwback", "cost": 700,
		"blurb": "Shorts far too short. Unbothered.",
		"jersey": Color(0.36, 0.62, 0.38), "trim": Color(0.98, 0.92, 0.68),
		"ball": Color(0.78, 0.44, 0.22), "skin": Color(0.90, 0.72, 0.55),
	},
	{
		"id": "neon", "name": "Neon", "cost": 1100,
		"blurb": "Visible from the cheap seats.",
		"jersey": Color(0.55, 0.95, 0.35), "trim": Color(0.30, 0.98, 0.90),
		"ball": Color(0.35, 0.98, 0.78), "skin": Color(0.62, 0.45, 0.34),
	},
	{
		"id": "champion", "name": "Champion", "cost": 1600,
		"blurb": "Gold kit. Earned it, apparently.",
		"jersey": Color(0.96, 0.82, 0.36), "trim": Color(0.30, 0.24, 0.10),
		"ball": Color(1.0, 0.76, 0.28), "skin": Color(0.80, 0.60, 0.42),
	},
]

## Arena palettes.
static var ARENAS: Array[Dictionary] = [
	{
		"id": "night_court", "name": "Night Court", "cost": 0,
		"blurb": "One floodlight and a lot of noise.",
		"bg": Color(0.055, 0.063, 0.106),
		"rim": Color(0.98, 0.45, 0.16), "rim_target": Color(1.0, 0.84, 0.32),
		"board": Color(0.86, 0.89, 0.96), "net": Color(0.92, 0.94, 1.0),
		"crowd": Color(0.30, 0.34, 0.52), "flash": Color(1.0, 0.97, 0.85),
		"gold": Color(1.0, 0.82, 0.29),
	},
	{
		"id": "blacktop", "name": "Blacktop", "cost": 400,
		"blurb": "Chain nets and a chalk line.",
		"bg": Color(0.075, 0.078, 0.082),
		"rim": Color(0.92, 0.36, 0.22), "rim_target": Color(0.98, 0.78, 0.30),
		"board": Color(0.72, 0.74, 0.72), "net": Color(0.80, 0.82, 0.86),
		"crowd": Color(0.36, 0.38, 0.36), "flash": Color(0.98, 0.92, 0.72),
		"gold": Color(1.0, 0.80, 0.32),
	},
	{
		"id": "finals", "name": "Finals", "cost": 750,
		"blurb": "Everyone is standing up.",
		"bg": Color(0.10, 0.035, 0.065),
		"rim": Color(1.0, 0.52, 0.20), "rim_target": Color(1.0, 0.90, 0.45),
		"board": Color(0.96, 0.92, 0.94), "net": Color(1.0, 0.96, 0.96),
		"crowd": Color(0.58, 0.26, 0.38), "flash": Color(1.0, 0.98, 0.92),
		"gold": Color(1.0, 0.86, 0.40),
	},
	{
		"id": "sunset_park", "name": "Sunset Park", "cost": 1200,
		"blurb": "Playing until you cannot see the rim.",
		"bg": Color(0.13, 0.072, 0.052),
		"rim": Color(1.0, 0.60, 0.24), "rim_target": Color(1.0, 0.88, 0.52),
		"board": Color(0.94, 0.84, 0.72), "net": Color(1.0, 0.93, 0.84),
		"crowd": Color(0.62, 0.42, 0.30), "flash": Color(1.0, 0.90, 0.66),
		"gold": Color(1.0, 0.84, 0.36),
	},
	{
		"id": "hardwood", "name": "Hardwood", "cost": 1800,
		"blurb": "Polished floor, television lighting.",
		"bg": Color(0.045, 0.075, 0.115),
		"rim": Color(0.98, 0.50, 0.18), "rim_target": Color(0.62, 0.95, 1.0),
		"board": Color(0.90, 0.95, 1.0), "net": Color(0.96, 0.98, 1.0),
		"crowd": Color(0.26, 0.42, 0.60), "flash": Color(0.92, 0.98, 1.0),
		"gold": Color(1.0, 0.85, 0.35),
	},
]


static func baller(id: String) -> Dictionary:
	for b in BALLERS:
		if b.id == id:
			return b
	return BALLERS[0]


static func arena(id: String) -> Dictionary:
	for a in ARENAS:
		if a.id == id:
			return a
	return ARENAS[0]
