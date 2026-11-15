extends TextureRect
## Drop-in replacement for Label that draws with the pixel font at an integer scale (`px`).
## Tint it with self_modulate; the black outline stays black.

const PixelFont := preload("res://scripts/pixel_font.gd")

var text := "":
	set(value):
		if value == text and texture != null:
			return
		text = value
		_rebuild()

var px := 1:
	set(value):
		px = maxi(value, 1)
		_rebuild()

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Never stretch to fill a container: that would distort the pixels
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _rebuild() -> void:
	texture = PixelFont.texture(text)
	custom_minimum_size = texture.get_size() * px
	size = custom_minimum_size
