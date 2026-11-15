extends CanvasLayer
## Crate opening between antes: a reel of prizes spins, slows down and lands.
## The odds are rigged in your favor (you never actually land a common) and it loves
## to stop one tile short of a legendary, so every spin feels like a big moment.

signal finished(item: String)

const Upgrades := preload("res://scripts/upgrades.gd")
const PixelLabel := preload("res://scripts/pixel_label.gd")
const Icons := preload("res://scripts/icons.gd")

const TILE := 48          # distance between tiles on the strip
const TILE_W := 44
const TILE_H := 56
const STRIP := 48         # tiles on the strip
const WIN := 40           # index of the tile we land on
const SPIN_TIME := 5.0
const WINDOW_W := 400
const WINDOW_H := 64

var fx: Node2D
var screen := Vector2(640, 360)
var state := "idle"       # idle -> spinning -> reveal -> done
var winner := ""
var near_miss := false
var reel_pos := 0.0
var target := 0.0
var t := 0.0
var last_tick := -1
var shake := 0.0
var hue := 0.0
var claim_ready := false

var root: Control
var strip: Control
var tiles: Array[Control] = []
var marker_top: Control
var title: Control
var rarity_label: Control
var name_label: Control
var desc_label: Control
var prompt: Control
var glow: ColorRect
var dot_tex: ImageTexture

func open(title_text: String, owned: Dictionary, pity: int) -> void:
	layer = 8
	winner = Upgrades.roll(owned, pity)
	var items := []
	for i in STRIP:
		items.append(Upgrades.filler(owned))
	items[WIN] = winner
	# The near miss: a legendary sitting right after the one you get
	var legend := Upgrades.legendary_item(owned)
	if Upgrades.ITEMS[winner]["rarity"] != "legendary" and legend != "" and randf() < 0.7:
		items[WIN + 1] = legend
		near_miss = true
	if legend != "" and randf() < 0.5:
		items[WIN - 2] = legend   # and one that flies past just before it stops
	_build(title_text, items)

func _build(title_text: String, items: Array) -> void:
	dot_tex = _make_dot()
	root = Control.new()
	root.size = screen
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim := ColorRect.new()
	dim.size = screen + Vector2(40, 40)
	dim.position = Vector2(-20, -20)
	dim.color = Color(0.02, 0.03, 0.03, 0.82)
	root.add_child(dim)

	title = _label(title_text, 3, Color(1.0, 0.85, 0.3))
	_center(title, 62)

	# Soft colored glow behind the window, flashes the rarity color on reveal
	glow = ColorRect.new()
	glow.position = Vector2((screen.x - WINDOW_W) / 2.0 - 6, 114)
	glow.size = Vector2(WINDOW_W + 12, WINDOW_H + 12)
	glow.color = Color(1.0, 0.85, 0.3, 0.0)
	root.add_child(glow)

	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.07)
	style.border_color = Color(0.85, 0.65, 0.2)
	style.set_border_width_all(2)
	style.anti_aliasing = false
	frame.add_theme_stylebox_override("panel", style)
	frame.position = Vector2((screen.x - WINDOW_W) / 2.0 - 2, 118)
	frame.size = Vector2(WINDOW_W + 4, WINDOW_H + 4)
	root.add_child(frame)

	var window := Control.new()
	window.clip_contents = true
	window.position = Vector2(2, 2)
	window.size = Vector2(WINDOW_W, WINDOW_H)
	frame.add_child(window)
	strip = Control.new()
	window.add_child(strip)
	for i in items.size():
		var tile := _tile(items[i])
		tile.position = Vector2(i * TILE + 2, 4)
		strip.add_child(tile)
		tiles.append(tile)
	# Dark fade at both ends of the window
	for side in [0, 1]:
		for k in 4:
			var shade := ColorRect.new()
			shade.size = Vector2(6, WINDOW_H)
			shade.position = Vector2(k * 6 if side == 0 else WINDOW_W - (k + 1) * 6, 0)
			shade.color = Color(0, 0, 0, 0.55 - k * 0.13)
			window.add_child(shade)

	# Gold pointer above and below the middle of the window
	marker_top = Control.new()
	root.add_child(marker_top)
	var cx := int(screen.x / 2.0)
	for k in 4:
		for y_base in [110 + k, 194 - k]:
			var r := ColorRect.new()
			r.position = Vector2(cx - (3 - k), y_base)
			r.size = Vector2((3 - k) * 2 + 1, 1)
			r.color = Color(1.0, 0.85, 0.3)
			marker_top.add_child(r)
	var line := ColorRect.new()
	line.position = Vector2(cx, 120)
	line.size = Vector2(1, WINDOW_H)
	line.color = Color(1.0, 0.9, 0.5, 0.8)
	marker_top.add_child(line)

	rarity_label = _label("", 3, Color.WHITE)
	rarity_label.visible = false
	name_label = _label("", 2, Color.WHITE)
	name_label.visible = false
	desc_label = _label("", 1, Color(0.85, 0.85, 0.8))
	desc_label.visible = false
	prompt = _label("PRESS SPACE TO SPIN", 1, Color(1.0, 0.95, 0.75))
	_center(prompt, 300)
	fx.sfx.play("whoosh")

func _tile(id: String) -> Control:
	var it: Dictionary = Upgrades.ITEMS[id]
	var col := Upgrades.rarity_color(it["rarity"])
	var tile := Control.new()
	tile.size = Vector2(TILE_W, TILE_H)
	tile.pivot_offset = tile.size / 2.0
	var border := ColorRect.new()
	border.size = tile.size
	border.color = col
	tile.add_child(border)
	var inner := ColorRect.new()
	inner.position = Vector2(2, 2)
	inner.size = tile.size - Vector2(4, 4)
	inner.color = col.darkened(0.72)
	tile.add_child(inner)
	var shine := ColorRect.new()
	shine.position = Vector2(2, 2)
	shine.size = Vector2(TILE_W - 4, 18)
	shine.color = col.darkened(0.6)
	tile.add_child(shine)
	var band := ColorRect.new()
	band.position = Vector2(2, TILE_H - 8)
	band.size = Vector2(TILE_W - 4, 6)
	band.color = col
	tile.add_child(band)
	var icon := TextureRect.new()
	icon.texture = Icons.texture(it["icon"])
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(32, 32)
	icon.position = Vector2(6, 9)
	tile.add_child(icon)
	if it["kind"] == "ball":
		var badge := PixelLabel.new()
		badge.text = "X%d" % it["count"]
		badge.self_modulate = Color.WHITE
		tile.add_child(badge)
		badge.position = Vector2(TILE_W - badge.size.x - 3, 3)
	return tile

func _label(text: String, px: int, color: Color) -> Control:
	var l := PixelLabel.new()
	l.px = px
	l.text = text
	l.self_modulate = color
	root.add_child(l)
	return l

func _center(l: Control, y: float) -> void:
	l.position = Vector2(floorf((screen.x - l.size.x) / 2.0), y)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_SPACE and event.keycode != KEY_ENTER:
		return
	get_viewport().set_input_as_handled()
	if state == "idle":
		_spin()
	elif state == "reveal" and claim_ready:
		state = "done"
		fx.sfx.play("coin", 1.2)
		finished.emit(winner)
		queue_free()

func _spin() -> void:
	state = "spinning"
	prompt.visible = false
	var center := WINDOW_W / 2.0
	var jitter := randf_range(-15.0, 15.0)
	if near_miss:
		jitter = randf_range(13.0, 19.0)   # stops right at the edge, the legendary peeking in
	target = WIN * TILE + 2 + TILE_W / 2.0 + jitter - center
	t = 0.0
	fx.sfx.play("drop", 0.7)

func _process(delta: float) -> void:
	hue = fmod(hue + delta * 0.8, 1.0)
	if state == "idle":
		prompt.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
	elif state == "spinning":
		t = minf(t + delta / SPIN_TIME, 1.0)
		var e := 1.0 - pow(1.0 - t, 4.0)
		reel_pos = target * e
		strip.position.x = -roundf(reel_pos)
		var idx := int((reel_pos + WINDOW_W / 2.0 - 2.0) / TILE)
		if idx != last_tick:
			last_tick = idx
			fx.sfx.play("tick", 0.8 + 0.9 * e, -2.0)
			marker_top.modulate = Color(2.0, 2.0, 2.0)
		marker_top.modulate = marker_top.modulate.lerp(Color.WHITE, minf(1.0, delta * 12.0))
		if t >= 1.0:
			_reveal()
	elif state == "reveal":
		var it: Dictionary = Upgrades.ITEMS[winner]
		if it["rarity"] == "legendary":
			var c := Color.from_hsv(hue, 0.5, 1.0)
			rarity_label.self_modulate = c
			glow.color = Color(c.r, c.g, c.b, glow.color.a)
		glow.color.a = maxf(0.18, glow.color.a - delta * 1.2)
		if claim_ready:
			prompt.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
	# Shake the whole overlay on big reveals (whole pixels only)
	shake = maxf(0.0, shake - delta * 2.0)
	var amp := 8.0 * shake * shake
	root.position = (Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amp).round()

func _reveal() -> void:
	state = "reveal"
	var it: Dictionary = Upgrades.ITEMS[winner]
	var rarity: String = it["rarity"]
	var col := Upgrades.rarity_color(rarity)
	var tile := tiles[WIN]
	tile.z_index = 2
	var tw := tile.create_tween()
	tw.tween_property(tile, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(tile, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	glow.color = Color(col.r, col.g, col.b, 0.9)

	rarity_label.text = rarity.to_upper() + "!"
	rarity_label.self_modulate = col
	_center(rarity_label, 20 + 6)
	title.visible = false
	rarity_label.visible = true
	name_label.text = it["name"]
	name_label.self_modulate = col.lightened(0.3)
	_center(name_label, 202)
	name_label.visible = true
	desc_label.text = it["desc"]
	_center(desc_label, 228)
	desc_label.visible = true

	var center := Vector2(screen.x / 2.0, 152)
	match rarity:
		"rare":
			fx.sfx.play("win_small")
			_burst(center, col, 24, 140.0)
			shake = 0.35
		"epic":
			fx.sfx.play("win_big")
			_burst(center, col, 40, 190.0)
			_burst(center, Color(1.0, 0.85, 0.3), 20, 120.0)
			_confetti(50)
			shake = 0.6
		_:
			fx.sfx.play("mega")
			fx.sfx.play("goal", 1.0, -2.0)
			_burst(center, col, 60, 230.0)
			_burst(center, Color.WHITE, 30, 160.0)
			_confetti(110)
			shake = 0.9
	if near_miss:
		var so_close := _label("SO CLOSE...", 1, Upgrades.rarity_color("legendary"))
		so_close.position = Vector2(screen.x / 2.0 + 40, 104)
	prompt.text = "PRESS SPACE TO CLAIM"
	_center(prompt, 300)
	await get_tree().create_timer(0.7).timeout
	claim_ready = true
	prompt.visible = true

func _burst(pos: Vector2, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles2D.new()
	p.texture = dot_tex
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.8
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 260)
	p.color = color
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

func _confetti(amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = dot_tex
	p.position = Vector2(screen.x / 2.0, -8)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(screen.x / 2.0, 4)
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.8
	p.lifetime = 2.4
	p.direction = Vector2.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, 60)
	p.hue_variation_min = -1.0
	p.hue_variation_max = 1.0
	p.color = Color(1.0, 0.5, 0.5)
	root.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)

func _make_dot() -> ImageTexture:
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)
