extends RefCounted
## Everything a crate can give you. "ball" items add special balls to your stock,
## "perk" items last for the rest of the run (they stack up to "max").
## Icons: drop a 16x16 PNG at res://art/icons/<icon>.png and the crate shows it.

const RARITIES := {
	"common":    {"color": Color(0.6, 0.75, 0.9), "weight": 0.0},
	"rare":      {"color": Color(0.3, 0.55, 1.0),  "weight": 50.0},
	"epic":      {"color": Color(0.75, 0.35, 1.0), "weight": 36.0},
	"legendary": {"color": Color(1.0, 0.75, 0.2),  "weight": 14.0},
}
# The reel shows commons, but the real odds above never land on one. Rigged in your favor.
const ORDER := ["common", "rare", "epic", "legendary"]

const ITEMS := {
	"heavy2":  {"kind": "ball", "ball": "heavy",  "count": 2, "rarity": "common", "icon": "heavy",  "short": "HEAVY",  "name": "2 HEAVY BALLS",  "desc": "X2 CHIP VALUE.\nFALLS FAST."},
	"bouncy2": {"kind": "ball", "ball": "bouncy", "count": 2, "rarity": "common", "icon": "bouncy", "short": "BOUNCY", "name": "2 BOUNCY BALLS", "desc": "+0.03 BONUS ON\nEVERY HIT."},
	"ghost2":  {"kind": "ball", "ball": "ghost",  "count": 2, "rarity": "rare",   "icon": "ghost",  "short": "GHOST",  "name": "2 GHOST BALLS",  "desc": "PASSES STRAIGHT\nTHROUGH SKULLS."},
	"heavy4":  {"kind": "ball", "ball": "heavy",  "count": 4, "rarity": "rare",   "icon": "heavy",  "short": "HEAVY",  "name": "4 HEAVY BALLS",  "desc": "X2 CHIP VALUE.\nFALLS FAST."},
	"bouncy4": {"kind": "ball", "ball": "bouncy", "count": 4, "rarity": "rare",   "icon": "bouncy", "short": "BOUNCY", "name": "4 BOUNCY BALLS", "desc": "+0.03 BONUS ON\nEVERY HIT."},
	"lucky":   {"kind": "perk", "max": 3, "rarity": "rare",      "icon": "lucky",   "short": "LUCKY",  "name": "LUCKY CHARM",  "desc": "SKULLS TAKE 10%\nLESS EACH."},
	"gold":    {"kind": "perk", "max": 5, "rarity": "rare",      "icon": "gold",    "short": "GOLD",   "name": "GOLD PLATING", "desc": "+0.01 ON EVERY\nGOOD CHIP."},
	"insure":  {"kind": "perk", "max": 1, "rarity": "epic",      "icon": "insure",  "short": "INSURE", "name": "INSURANCE",    "desc": "BALLS NEVER PAY\nBELOW X0.5."},
	"banana2": {"kind": "ball", "ball": "banana", "count": 2, "rarity": "epic", "icon": "banana", "short": "BANANA", "name": "2 GROS MICHELS", "desc": "A BANANA YOU DROP.\n+X0.50 WHEN IT LANDS."},
	"jackpot": {"kind": "perk", "max": 1, "rarity": "legendary", "icon": "jackpot", "short": "JACKPOT","name": "JACKPOT",      "desc": "EVERY WIN\nPAYS DOUBLE."},
}

static func rarity_color(rarity: String) -> Color:
	return RARITIES[rarity]["color"]

static func icon_texture(id: String) -> Texture2D:
	var path := "res://art/icons/%s.png" % ITEMS[id]["icon"]
	return load(path) if ResourceLoader.exists(path) else null

static func available(owned: Dictionary) -> Array:
	var out := []
	for id in ITEMS:
		var it: Dictionary = ITEMS[id]
		if it["kind"] == "perk" and owned.get(id, 0) >= it["max"]:
			continue
		out.append(id)
	return out

static func _pick(pool: Array, weights: Dictionary) -> String:
	var total := 0.0
	for id in pool:
		total += weights[ITEMS[id]["rarity"]]
	if total <= 0.0:
		return pool.pick_random()
	var x := randf() * total
	for id in pool:
		x -= weights[ITEMS[id]["rarity"]]
		if x < 0.0:
			return id
	return pool.back()

# The real roll. pity = crates in a row without epic or better; at 2 the next one is epic+.
static func roll(owned: Dictionary, pity: int) -> String:
	var w := {}
	for r in ORDER:
		w[r] = RARITIES[r]["weight"]
	if pity >= 2:
		w["rare"] = 0.0
	return _pick(available(owned), w)

# Filler for the reel: what the strip *looks* like
static func filler(owned: Dictionary) -> String:
	return _pick(available(owned), {"common": 40.0, "rare": 30.0, "epic": 18.0, "legendary": 12.0})

static func legendary_item(owned: Dictionary) -> String:
	var pool := available(owned).filter(func(id): return ITEMS[id]["rarity"] == "legendary")
	return pool.pick_random() if not pool.is_empty() else ""
