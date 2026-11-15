extends RefCounted
## Everything a crate can give you. "ball" items add special balls to your stock,
## "perk" items are permanent for the rest of the run (they stack up to "max").

const RARITIES := {
	"common":    {"color": Color(0.55, 0.75, 0.95), "weight": 0.0},
	"rare":      {"color": Color(0.3, 0.55, 1.0),   "weight": 44.0},
	"epic":      {"color": Color(0.75, 0.35, 1.0),  "weight": 38.0},
	"legendary": {"color": Color(1.0, 0.75, 0.2),   "weight": 18.0},
}
# The reel shows plenty of commons, but the real odds above never land on one. Rigged, as promised.
const ORDER := ["common", "rare", "epic", "legendary"]

const ITEMS := {
	"heavy2":  {"kind": "ball", "ball": "heavy",  "count": 2, "rarity": "common", "icon": "HB", "name": "2 HEAVY BALLS",
		"desc": "X2 CHIP VALUE.\nSMASHES SKULLS."},
	"bouncy2": {"kind": "ball", "ball": "bouncy", "count": 2, "rarity": "common", "icon": "BB", "name": "2 BOUNCY BALLS",
		"desc": "+0.03 BONUS ON\nEVERY HIT."},
	"ghost2":  {"kind": "ball", "ball": "ghost",  "count": 2, "rarity": "rare",   "icon": "GB", "name": "2 GHOST BALLS",
		"desc": "PASSES THROUGH\nSKULLS AND -CHIPS."},
	"heavy4":  {"kind": "ball", "ball": "heavy",  "count": 4, "rarity": "rare",   "icon": "HB", "name": "4 HEAVY BALLS",
		"desc": "X2 CHIP VALUE.\nSMASHES SKULLS."},
	"bouncy4": {"kind": "ball", "ball": "bouncy", "count": 4, "rarity": "rare",   "icon": "BB", "name": "4 BOUNCY BALLS",
		"desc": "+0.03 BONUS ON\nEVERY HIT."},
	"lucky":   {"kind": "perk", "max": 3, "rarity": "rare", "icon": "LC", "name": "LUCKY CHARM",
		"desc": "SKULLS TAKE 15%\nLESS EACH."},
	"gold":    {"kind": "perk", "max": 5, "rarity": "rare", "icon": "GP", "name": "GOLD PLATING",
		"desc": "+0.01 ON EVERY\nGOOD CHIP."},
	"skin":    {"kind": "perk", "max": 2, "rarity": "rare", "icon": "TS", "name": "THICK SKIN",
		"desc": "-CHIPS ARE 40%\nWEAKER EACH."},
	"extra":   {"kind": "perk", "max": 3, "rarity": "epic", "icon": "+1", "name": "EXTRA BALL",
		"desc": "+1 BALL EVERY\nANTE."},
	"insure":  {"kind": "perk", "max": 1, "rarity": "epic", "icon": "IN", "name": "INSURANCE",
		"desc": "BALLS NEVER PAY\nBELOW X0."},
	"roller":  {"kind": "perk", "max": 3, "rarity": "epic", "icon": "HR", "name": "HIGH ROLLER",
		"desc": "WINS OVER X1\nPAY 25% MORE."},
	"midas":   {"kind": "perk", "max": 2, "rarity": "legendary", "icon": "MT", "name": "MIDAS TOUCH",
		"desc": "+3 PURPLE 100\nCHIPS PER BOARD."},
	"jackpot": {"kind": "perk", "max": 1, "rarity": "legendary", "icon": "JP", "name": "JACKPOT",
		"desc": "EVERY WIN\nPAYS DOUBLE."},
}

static func rarity_color(rarity: String) -> Color:
	return RARITIES[rarity]["color"]

static func available(owned: Dictionary) -> Array:
	var out := []
	for id in ITEMS:
		var it: Dictionary = ITEMS[id]
		if it["kind"] == "perk" and owned.get(id, 0) >= it["max"]:
			continue
		out.append(id)
	return out

# The real roll. pity = crates in a row without epic or better; at 2 the next one is guaranteed epic+.
static func roll(owned: Dictionary, pity: int) -> String:
	var pool := available(owned)
	var weights := {}
	for r in ORDER:
		weights[r] = RARITIES[r]["weight"]
	if pity >= 2:
		weights["rare"] = 0.0
	var total := 0.0
	for id in pool:
		total += weights[ITEMS[id]["rarity"]]
	var x := randf() * total
	for id in pool:
		x -= weights[ITEMS[id]["rarity"]]
		if x < 0.0:
			return id
	return pool.back()

# Filler for the reel: what the strip *looks* like (lots of commons, a few shiny ones)
static func filler(owned: Dictionary) -> String:
	var pool := available(owned)
	var w := {"common": 40.0, "rare": 30.0, "epic": 18.0, "legendary": 12.0}
	var total := 0.0
	for id in pool:
		total += w[ITEMS[id]["rarity"]]
	var x := randf() * total
	for id in pool:
		x -= w[ITEMS[id]["rarity"]]
		if x < 0.0:
			return id
	return pool.back()

static func legendary_item(owned: Dictionary) -> String:
	var pool := available(owned).filter(func(id): return ITEMS[id]["rarity"] == "legendary")
	return pool.pick_random() if not pool.is_empty() else ""
