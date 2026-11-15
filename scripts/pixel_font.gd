extends RefCounted
## A 5x7 pixel font drawn entirely in code. Text is baked white with a 1px black outline,
## so it can be tinted with modulate and stays readable on any background.
## Draw it at integer scales only (1x, 2x, 3x...) to keep every pixel square.

const GLYPH_W := 5
const GLYPH_H := 7
const ADVANCE := 6      # glyph width plus one pixel of spacing
const LINE_STEP := 10   # distance between lines of text

# Rows are separated by "|"; "#" is a lit pixel. Uppercase only.
const GLYPHS := {
	"A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
	"B": "####.|#...#|#...#|####.|#...#|#...#|####.",
	"C": ".###.|#...#|#....|#....|#....|#...#|.###.",
	"D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
	"E": "#####|#....|#....|####.|#....|#....|#####",
	"F": "#####|#....|#....|####.|#....|#....|#....",
	"G": ".###.|#...#|#....|#.###|#...#|#...#|.###.",
	"H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
	"I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.",
	"J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
	"K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
	"L": "#....|#....|#....|#....|#....|#....|#####",
	"M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
	"N": "#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
	"O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
	"P": "####.|#...#|#...#|####.|#....|#....|#....",
	"Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
	"R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
	"S": ".####|#....|#....|.###.|....#|....#|####.",
	"T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
	"U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
	"V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
	"W": "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#",
	"X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
	"Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
	"Z": "#####|....#|...#.|..#..|.#...|#....|#####",
	"0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
	"1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
	"2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
	"3": ".###.|#...#|....#|..##.|....#|#...#|.###.",
	"4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
	"5": "#####|#....|####.|....#|....#|#...#|.###.",
	"6": "..##.|.#...|#....|####.|#...#|#...#|.###.",
	"7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
	"8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
	"9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
	"$": "..#..|.####|#.#..|.###.|..#.#|####.|..#..",
	"+": ".....|..#..|..#..|#####|..#..|..#..|.....",
	"-": ".....|.....|.....|#####|.....|.....|.....",
	".": ".....|.....|.....|.....|.....|.##..|.##..",
	",": ".....|.....|.....|.....|.##..|..#..|.#...",
	"!": "..#..|..#..|..#..|..#..|..#..|.....|..#..",
	"?": ".###.|#...#|....#|...#.|..#..|.....|..#..",
	"%": "##..#|##..#|...#.|..#..|.#...|#..##|#..##",
	":": ".....|.##..|.##..|.....|.##..|.##..|.....",
	"/": "....#|....#|...#.|..#..|.#...|#....|#....",
	"(": "...#.|..#..|.#...|.#...|.#...|..#..|...#.",
	")": ".#...|..#..|...#.|...#.|...#.|..#..|.#...",
	"=": ".....|.....|#####|.....|#####|.....|.....",
}

static var _parsed := {}

static func _glyph(ch: String) -> Array:
	if _parsed.is_empty():
		for k in GLYPHS:
			_parsed[k] = GLYPHS[k].split("|")
	return _parsed.get(ch, _parsed["?"])

# Size in pixels (at 1x) that `text` will occupy, outline included.
static func measure(text: String) -> Vector2i:
	var lines := text.split("\n")
	var cols := 0
	for line in lines:
		cols = maxi(cols, line.length())
	return Vector2i(maxi(cols * ADVANCE - 1, 1) + 2, (lines.size() - 1) * LINE_STEP + GLYPH_H + 2)

static func make_image(text: String) -> Image:
	var size := measure(text)
	var w := size.x
	var h := size.y
	var grid := PackedByteArray()
	grid.resize(w * h)
	var lines := text.to_upper().split("\n")
	for li in lines.size():
		var line := lines[li]
		for ci in line.length():
			var ch := line[ci]
			if ch == " ":
				continue
			var rows: Array = _glyph(ch)
			for gy in GLYPH_H:
				var row: String = rows[gy]
				for gx in GLYPH_W:
					if row[gx] == "#":
						grid[(1 + li * LINE_STEP + gy) * w + 1 + ci * ADVANCE + gx] = 1
	# 1px outline around every lit pixel
	var out := grid.duplicate()
	for y in h:
		for x in w:
			if grid[y * w + x] == 1:
				continue
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and grid[ny * w + nx] == 1:
						out[y * w + x] = 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var v := out[y * w + x]
			if v == 1:
				img.set_pixel(x, y, Color.WHITE)
			elif v == 2:
				img.set_pixel(x, y, Color(0, 0, 0, 1))
	return img

static func texture(text: String) -> ImageTexture:
	return ImageTexture.create_from_image(make_image(text))
