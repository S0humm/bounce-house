extends RefCounted
## Picture of each ball type, shared by the NEXT BALL picker, the drop preview and the crate.

const RING := {"heavy": Color(0.6, 0.66, 0.8), "bouncy": Color(0.62, 0.95, 0.2), "ghost": Color(0.55, 0.95, 1.0)}
const ART := {"banana": "res://art/icons/banana.png", "fire": "res://art/icons/fire.png"}

static var _cache := {}

static func icon(type: String) -> Texture2D:
	if _cache.has(type):
		return _cache[type]
	var tex: Texture2D
	if ART.has(type):
		tex = load(ART[type])   # hand-drawn art
	else:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var core: Image = (load("res://art/ball.png") as Texture2D).get_image()
		core.convert(Image.FORMAT_RGBA8)
		if type == "ghost":
			for y in core.get_height():
				for x in core.get_width():
					var c := core.get_pixel(x, y)
					c.a *= 0.55
					core.set_pixel(x, y, c)
		img.blend_rect(core, Rect2i(Vector2i.ZERO, core.get_size()), Vector2i(2, 2))
		var ring: Color = RING.get(type, Color(0, 0, 0, 0))
		if ring.a > 0.0:
			for y in 16:
				for x in 16:
					var r := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
					if r > 6.6 and r <= 7.8:
						img.set_pixel(x, y, ring)
		tex = ImageTexture.create_from_image(img)
	_cache[type] = tex
	return tex

# A TextureRect that shows the icon fitted into a box: crisp when it's small pixel art
static func rect(type: String, box: int) -> TextureRect:
	var tex := icon(type)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size = Vector2(box, box)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fits_whole := box % maxi(tex.get_width(), tex.get_height()) == 0
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if fits_whole else CanvasItem.TEXTURE_FILTER_LINEAR
	return r
