extends RefCounted
## Every chip type in one place: what it does, how often it shows up, and its art.
## Chip art is drawn in code (22x22 pixel art), so there are no image files to import.

# kind: "add" adds to the multiplier, "black" (skull) takes half of it away
const TYPES := {
	"c1":    {"kind": "add", "add": 0.01, "weight": 50.0, "label": "1",   "color": Color(0.92, 0.2, 0.22)},
	"c5":    {"kind": "add", "add": 0.05, "weight": 27.0, "label": "5",   "color": Color(1.0, 0.55, 0.12)},
	"c10":   {"kind": "add", "add": 0.10, "weight": 13.0, "label": "10",  "color": Color(1.0, 0.8, 0.12)},
	"c25":   {"kind": "add", "add": 0.25, "weight": 6.5,  "label": "25",  "color": Color(0.18, 0.5, 1.0)},
	"c50":   {"kind": "add", "add": 0.50, "weight": 2.5,  "label": "50",  "color": Color(0.2, 0.82, 0.35)},
	"c100":  {"kind": "add", "add": 1.00, "weight": 1.0,  "label": "100", "color": Color(0.6, 0.3, 0.95)},
	"black": {"kind": "black", "label": "K", "color": Color(0.13, 0.12, 0.16)},
}
const POSITIVE := ["c1", "c5", "c10", "c25", "c50", "c100"]

# 3x5 glyphs ("1" is 1px wide so "100" fits inside the chip), K is a 5x5 skull
const GLYPHS := {
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"1": ["#", "#", "#", "#", "#"],
	"I": [".#.", "##.", ".#.", ".#.", "###"],   # wide 1, used when "1" is alone
	"2": ["###", "..#", "###", "#..", "###"],
	"5": ["###", "#..", "###", "..#", "###"],
	"K": [".###.", "#.#.#", "#####", ".###.", ".#.#."],
}

static var _cache := {}

static func info(chip: String) -> Dictionary:
	return TYPES.get(chip, TYPES["c1"])

static func color(chip: String) -> Color:
	return info(chip)["color"]

static func is_bad(chip: String) -> bool:
	return info(chip)["kind"] != "add"

# Random positive chip, weighted so small values are common and big ones rare
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

static func texture(chip: String) -> ImageTexture:
	if not _cache.has(chip):
		_cache[chip] = ImageTexture.create_from_image(_draw(chip))
	return _cache[chip]

# Chip seen from above with a little edge showing below it, like a short stack:
# dark outline, colored ring with 6 stripes, light center with the value.
static func _draw(chip: String) -> Image:
	var t := info(chip)
	var base: Color = t["color"]
	var stripe := Color(1, 1, 1)
	var center := Color(1, 1, 1)
	var ink := base.darkened(0.45)
	var outline := base.darkened(0.65)
	match t["kind"]:
		"black":
			stripe = Color(0.95, 0.22, 0.28)
			center = Color(0.27, 0.25, 0.31)
			ink = Color(0.96, 0.93, 0.86)
			outline = Color(0.03, 0.02, 0.04)
	var side := base.darkened(0.35) if t["kind"] == "add" else base.lightened(0.12)

	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := 10.5
	var cy := 9.5
	# Edge of the chip (2px thick) with stripes on it too
	for dy in [2, 1]:
		for y in 22:
			for x in 22:
				var r := Vector2(x + 0.5 - cx, y + 0.5 - cy - dy).length()
				if r <= 10.0:
					var a := rad_to_deg(atan2(y + 0.5 - cy - dy, x + 0.5 - cx))
					var c := side
					if r > 9.2:
						c = outline
					elif posmod(int(a + 15.0), 60) < 22:
						c = stripe.darkened(0.25)
					img.set_pixel(x, y, c)
	# Top face
	for y in 22:
		for x in 22:
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var r := Vector2(dx, dy).length()
			if r > 10.0:
				continue
			var c := base
			if r > 9.2:
				c = outline
			elif r > 6.6:
				var a := rad_to_deg(atan2(dy, dx))
				if posmod(int(a + 15.0), 60) < 22 and r > 7.1:
					c = stripe
				elif r > 8.4 and dx + dy < -6.0:
					c = base.lightened(0.3)   # small shine on the top-left rim
			elif r > 5.9:
				c = base.darkened(0.15)       # thin ring around the center
			else:
				c = center
			img.set_pixel(x, y, c)
	_text(img, t["label"], ink)
	return img

static func _text(img: Image, label: String, ink: Color) -> void:
	if label == "1":
		label = "I"
	var width := 0
	for ch in label:
		width += GLYPHS[ch][0].length() + 1
	width -= 1
	var x0 := 11 - int(ceil(width / 2.0))
	var y0 := 7
	for ch in label:
		var g: Array = GLYPHS[ch]
		for gy in 5:
			var row: String = g[gy]
			for gx in row.length():
				if row[gx] == "#":
					img.set_pixel(x0 + gx, y0 + gy, ink)
		x0 += g[0].length() + 1
