extends RefCounted
## Every chip type in one place: what it does, how often it shows up, and its (hand-drawn) art.

# kind: "add" adds to the multiplier, "black" (skull) takes half of it away
const TYPES := {
	"c1":    {"kind": "add", "add": 0.01, "weight": 50.0, "color": Color(0.95, 0.95, 0.9)},
	"c5":    {"kind": "add", "add": 0.05, "weight": 27.0, "color": Color(0.4, 0.7, 1.0)},
	"c10":   {"kind": "add", "add": 0.10, "weight": 13.0, "color": Color(0.4, 1.0, 0.5)},
	"c25":   {"kind": "add", "add": 0.25, "weight": 7.0,  "color": Color(1.0, 0.35, 0.3)},
	"c50":   {"kind": "add", "add": 0.50, "weight": 3.0,  "color": Color(1.0, 0.82, 0.25)},
	"black": {"kind": "black", "color": Color(0.6, 0.15, 0.2)},
}
const POSITIVE := ["c1", "c5", "c10", "c25", "c50"]

# The original 1.0 chip art
const TEXTURES := {
	"c1": preload("res://art/peg_white.png"),
	"c5": preload("res://art/peg_blue.png"),
	"c10": preload("res://art/peg_green.png"),
	"c25": preload("res://art/peg_red.png"),
	"c50": preload("res://art/peg_gold.png"),
	"black": preload("res://art/peg_black.png"),
}

static func info(chip: String) -> Dictionary:
	return TYPES.get(chip, TYPES["c1"])

static func color(chip: String) -> Color:
	return info(chip)["color"]

static func is_bad(chip: String) -> bool:
	return info(chip)["kind"] != "add"

# Random good chip, weighted so small values are common and big ones rare
static func pick_positive() -> String:
	var total := 0.0
	for k in POSITIVE:
		total += TYPES[k]["weight"]
	var r := randf() * total
	for k in POSITIVE:
		r -= TYPES[k]["weight"]
		if r < 0.0:
			return k
	return "c1"

static func texture(chip: String) -> Texture2D:
	return TEXTURES.get(chip, TEXTURES["c1"])
