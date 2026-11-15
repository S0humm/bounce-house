extends RefCounted
## 16x16 pixel-art icons for crate prizes, drawn in code. Every shape gets an automatic
## dark outline, so they all match.

const OUTLINE := Color(0.07, 0.05, 0.06)
const GHOST := [
	"................",
	"......oooo......",
	"....oowwwwoo....",
	"...owwwwwwwwo...",
	"..owwwwwwwwwwo..",
	"..owwkkwwkkwwo..",
	"..owwkkwwkkwwo..",
	"..owwwwwwwwwwo..",
	"..owwwwwwwwwwo..",
	"..owwwwwwwwwwo..",
	"..owwwwwwwwwwo..",
	"..owwwwwwwwwwo..",
	"..owwwowwowwwo..",
	"..owwo.oo.owwo..",
	"..ooo......ooo..",
	"................",
]

static var _cache := {}

static func texture(id: String) -> ImageTexture:
	if not _cache.has(id):
		_cache[id] = ImageTexture.create_from_image(_draw(id))
	return _cache[id]

static func _draw(id: String) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match id:
		"heavy":
			_ball(img, Vector2(7.5, 8.0), 6.2, Color(0.5, 0.55, 0.66))
			_rect(img, 5, 2, 6, 2, Color(0.35, 0.38, 0.46))   # little handle on top, like a weight
		"bouncy":
			for r in [[0, 4, 4], [0, 7, 5], [1, 10, 3]]:
				_rect(img, r[0], r[1], r[2], 1, Color(0.75, 1.0, 0.45))
			_ball(img, Vector2(10.0, 7.0), 5.0, Color(0.62, 0.95, 0.2))
			_rect(img, 7, 14, 6, 1, Color(0.15, 0.3, 0.1))   # shadow on the ground
		"ghost":
			for y in 16:
				for x in 16:
					match GHOST[y][x]:
						"w": img.set_pixel(x, y, Color(0.8, 0.97, 1.0))
						"k": img.set_pixel(x, y, Color(0.1, 0.2, 0.35))
						"o": img.set_pixel(x, y, OUTLINE)
			return img
		"extra":
			_ball(img, Vector2(7.0, 7.0), 6.0, Color(0.96, 0.96, 0.92))
			_rect(img, 9, 11, 7, 2, Color(0.3, 0.9, 0.4))
			_rect(img, 11, 9, 2, 7, Color(0.3, 0.9, 0.4))
		"lucky":
			var green := Color(0.25, 0.75, 0.3)
			for c in [Vector2(5, 5), Vector2(10.5, 5), Vector2(5, 10.5), Vector2(10.5, 10.5)]:
				_circle(img, c, 3.3, green)
				img.set_pixel(int(c.x) - 1, int(c.y) - 1, green.lightened(0.45))
			_rect(img, 7, 2, 1, 12, green.darkened(0.45))   # veins between the four leaves
			_rect(img, 2, 7, 12, 1, green.darkened(0.45))
			for i in 4:
				_rect(img, 11 + i, 12 + i, 1, 1, Color(0.18, 0.45, 0.15))
		"gold":
			_rect(img, 4, 5, 8, 3, Color(1.0, 0.88, 0.45))    # top face
			_rect(img, 2, 8, 12, 5, Color(0.92, 0.68, 0.18))  # front face
			_rect(img, 11, 8, 3, 5, Color(0.72, 0.5, 0.12))   # shaded side
			_rect(img, 3, 9, 6, 1, Color(1.0, 0.85, 0.4))     # shine
			img.set_pixel(13, 2, Color.WHITE)
			img.set_pixel(14, 3, Color.WHITE)
			img.set_pixel(12, 3, Color.WHITE)
			img.set_pixel(13, 4, Color.WHITE)
		"insure":
			var red := Color(0.92, 0.25, 0.28)
			for y in 16:
				for x in 16:
					var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.5)
					if d.y <= 0.0 and d.length() <= 6.8:
						var band := int(floor((atan2(d.y, d.x) + PI) / (PI / 4.0))) % 2
						img.set_pixel(x, y, red if band == 0 else Color(0.97, 0.95, 0.9))
			_rect(img, 7, 8, 2, 6, Color(0.55, 0.4, 0.25))
			_rect(img, 9, 13, 2, 2, Color(0.55, 0.4, 0.25))
		"roller":
			_rect(img, 3, 3, 10, 10, Color(0.97, 0.96, 0.92))
			_rect(img, 3, 12, 10, 1, Color(0.75, 0.72, 0.7))
			_rect(img, 12, 3, 1, 10, Color(0.75, 0.72, 0.7))
			for p in [Vector2i(4, 4), Vector2i(10, 4), Vector2i(7, 7), Vector2i(4, 10), Vector2i(10, 10)]:
				_rect(img, p.x, p.y, 2, 2, Color(0.85, 0.15, 0.2))
		"midas":
			var gold := Color(1.0, 0.8, 0.25)
			_rect(img, 2, 10, 12, 3, gold.darkened(0.15))
			for spike in [[2, 4], [6, 3], [10, 4]]:
				var x0: int = spike[0]
				for y in range(spike[1], 10):
					var w := 1 + int((y - spike[1]) * 0.5)
					_rect(img, x0 + 2 - w, y, w * 2, 1, gold)
			img.set_pixel(5, 11, Color(0.9, 0.15, 0.25))
			img.set_pixel(8, 11, Color(0.3, 0.6, 1.0))
			img.set_pixel(11, 11, Color(0.9, 0.15, 0.25))
		"jackpot":
			var green := Color(0.35, 0.65, 0.3)
			_circle(img, Vector2(8, 10.5), 5.0, green)
			_rect(img, 6, 4, 4, 3, green)
			_rect(img, 5, 6, 6, 1, Color(0.8, 0.6, 0.2))   # tie
			_rect(img, 4, 2, 3, 2, green)
			_rect(img, 9, 2, 3, 2, green)
			var g := Color(1.0, 0.85, 0.3)
			for p in [[7, 8], [8, 8], [9, 8], [7, 9], [7, 10], [8, 10], [9, 10], [9, 11], [7, 12], [8, 12], [9, 12], [8, 7], [8, 13]]:
				img.set_pixel(p[0], p[1], g)
	_outline(img)
	return img

static func _ball(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5) - c
			if d.length() <= r:
				var shade := col
				if d.x + d.y > r * 0.6:
					shade = col.darkened(0.3)
				img.set_pixel(x, y, shade)
	var hx := int(c.x - r * 0.45)
	var hy := int(c.y - r * 0.45)
	_rect(img, hx, hy, 2, 2, col.lightened(0.6))

static func _circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in 16:
		for x in 16:
			if (Vector2(x + 0.5, y + 0.5) - c).length() <= r:
				img.set_pixel(x, y, col)

static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and yy >= 0 and xx < 16 and yy < 16:
				img.set_pixel(xx, yy, col)

# Dark 1px outline around everything drawn
static func _outline(img: Image) -> void:
	var src := img.duplicate()
	for y in 16:
		for x in 16:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < 16 and ny < 16 and src.get_pixel(nx, ny).a > 0.0 and src.get_pixel(nx, ny) != OUTLINE:
					img.set_pixel(x, y, OUTLINE)
					break
