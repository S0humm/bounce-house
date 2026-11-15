extends Node2D
## Casino-style game feel: screen shake, hit-stop, particles, coin showers, win banners,
## chaser lights. Everything is drawn or synthesized in code - no art or audio files.
## The board calls the high-level methods (chip_hit, landed, ante_cleared, ...).

const SfxScript := preload("res://scripts/sfx.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")

const GOLD := Color(0.85, 0.65, 0.2)
const BULB_ON := Color(1.0, 0.96, 0.65)
const BULB_MID := Color(0.85, 0.58, 0.16)
const BULB_OFF := Color(0.5, 0.34, 0.1)

const CHIP_COLORS := {
	"white": Color(0.95, 0.95, 0.9),
	"red": Color(1.0, 0.35, 0.3),
	"blue": Color(0.4, 0.7, 1.0),
	"green": Color(0.4, 1.0, 0.5),
	"black": Color(0.6, 0.15, 0.2),
}
const TIER_COLORS := [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.92, 0.45),
	Color(1.0, 0.62, 0.2),
	Color(1.0, 0.35, 0.7),
	Color(0.55, 1.0, 1.0),
]

# Win tiers by ball multiplier: loss, win, nice, big, mega, jackpot
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const BANNER_Y := 156   # vertical center of the win banner

const WIN_COINS := [0, 10, 22, 40, 70, 110]
const WIN_SHAKE := [0.0, 0.05, 0.15, 0.35, 0.6, 0.85]
const WIN_PARTY := [0.0, 0.0, 0.8, 1.8, 3.0, 4.5]

var sfx: Node
var screen := Vector2(640, 360)
var calm := false          # less shake, no screen flashes

var cam: Camera2D
var hud_layer: CanvasLayer
var flash_rect: ColorRect
var band: ColorRect
var banner_sprite: Sprite2D
var flash_tween: Tween
var banner_tween: Tween

var trauma := 0.0
var party := 0.0           # seconds of celebration lights left
var rainbow := 0.0         # seconds the banner cycles colors
var chase := 0.0
var stop_end_ms := 0
var win_streak := 0
var bulbs := PackedVector2Array()
var dot3_tex: ImageTexture
var dot2_tex: ImageTexture
var coin_tex: ImageTexture

func setup(size: Vector2) -> void:
	screen = size
	z_index = 10
	sfx = SfxScript.new()
	add_child(sfx)
	dot3_tex = _make_dot(3)
	dot2_tex = _make_dot(2)
	coin_tex = _make_coin()
	_build_bulbs()
	_build_background()

	cam = Camera2D.new()
	cam.position = screen / 2.0
	add_child(cam)
	cam.make_current()

	# Screen-space layer above the HUD: flashes and win banners
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	flash_rect = ColorRect.new()
	flash_rect.size = screen
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(flash_rect)
	band = ColorRect.new()
	band.position = Vector2(0, BANNER_Y - 30)
	band.size = Vector2(screen.x, 60)
	band.color = Color(0, 0, 0, 0.7)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.visible = false
	hud_layer.add_child(band)
	banner_sprite = Sprite2D.new()
	banner_sprite.centered = false
	banner_sprite.visible = false
	hud_layer.add_child(banner_sprite)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _process(delta: float) -> void:
	chase += delta * (2.6 if party > 0.0 else 1.0)
	party = maxf(0.0, party - delta)
	trauma = maxf(0.0, trauma - delta * 1.8)
	var s := trauma * trauma
	var amp := 9.0 * s * (0.35 if calm else 1.0)
	# Whole-pixel offsets and no rotation, so shaking never breaks the pixel grid
	cam.offset = (Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp).round()
	if Engine.time_scale != 1.0 and Time.get_ticks_msec() >= stop_end_ms:
		Engine.time_scale = 1.0
	if rainbow > 0.0:
		rainbow -= delta
		banner_sprite.self_modulate = Color.from_hsv(fmod(chase * 1.4, 1.0), 0.55, 1.0)
	queue_redraw()

# ---------- Frame, chaser lights ----------

func _build_bulbs() -> void:
	bulbs.clear()
	var inset := 4.0
	var step := 10.0
	var x := inset
	while x < screen.x - inset:
		bulbs.append(Vector2(x, inset))
		x += step
	var y := inset
	while y < screen.y - inset:
		bulbs.append(Vector2(screen.x - inset, y))
		y += step
	x = screen.x - inset
	while x > inset:
		bulbs.append(Vector2(x, screen.y - inset))
		x -= step
	y = screen.y - inset
	while y > inset:
		bulbs.append(Vector2(inset, y))
		y -= step

func _build_background() -> void:
	# Spotlit felt drawn as ordered-dither pixel art: a handful of greens, no smooth gradient
	var w := 320
	var h := 180
	var inner := Color(0.17, 0.40, 0.24)
	var outer := Color(0.04, 0.12, 0.07)
	var levels := 6
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var dx := (x + 0.5) / w - 0.5
			var dy := (y + 0.5) / h - 0.5
			var t := clampf(sqrt(dx * dx + dy * dy) / 0.62, 0.0, 1.0)
			var threshold: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			var q := floorf(t * (levels - 1) + threshold) / (levels - 1)
			img.set_pixel(x, y, inner.lerp(outer, clampf(q, 0.0, 1.0)))
	var bg := Sprite2D.new()
	bg.texture = ImageTexture.create_from_image(img)
	bg.centered = false
	bg.scale = screen / Vector2(w, h)
	bg.z_as_relative = false
	bg.z_index = -100
	add_child(bg)

func _draw() -> void:
	# Gold bleed outside the frame so camera shake never exposes the background
	var b := 24.0
	draw_rect(Rect2(-b, -b, screen.x + 2.0 * b, b), GOLD)
	draw_rect(Rect2(-b, screen.y, screen.x + 2.0 * b, b), GOLD)
	draw_rect(Rect2(-b, 0, b, screen.y), GOLD)
	draw_rect(Rect2(screen.x, 0, b, screen.y), GOLD)
	for i in bulbs.size():
		var col := BULB_OFF
		if party > 0.0:
			col = Color.from_hsv(fmod(i * 0.03 + chase * 1.6, 1.0), 0.55, 1.0)
		else:
			var phase := posmod(i - int(chase * 14.0), 5)
			if phase == 0:
				col = BULB_ON
			elif phase == 1:
				col = BULB_MID
		draw_rect(Rect2(bulbs[i] - Vector2(1.5, 1.5), Vector2(3, 3)), col)

# ---------- High-level events (called by the board) ----------

func chip_hit(chip: String, pos: Vector2, gain: float, combo: int) -> void:
	var col: Color = CHIP_COLORS.get(chip, Color.WHITE)
	match chip:
		"black":
			sfx.play("womp")
			burst(pos, col, 14, 110.0, 0.5, 1.4, 200.0)
			popup(pos + Vector2(0, -16), "-50%", Color(1.0, 0.35, 0.3), 2, 18.0, 0.7)
			add_trauma(0.3)
			hit_stop(0.05)
			flash(Color(0.8, 0.05, 0.05), 0.22, 0.25)
		"red":
			sfx.play("ding_red", sfx.ladder(combo))
			burst(pos, col, 8, 75.0, 0.4, 1.2)
			popup(pos + Vector2(0, -14), "+%.2f" % gain, col, 1)
		"blue":
			sfx.play("ding_blue", sfx.ladder(combo))
			burst(pos, col, 6, 65.0, 0.35, 1.0)
			popup(pos + Vector2(0, -14), "+%.2f" % gain, col, 1)
		"green":
			sfx.play("chime", sfx.ladder(combo))
			burst(pos, col, 7, 70.0, 0.4, 1.1)
			popup(pos + Vector2(0, -14), "+%.2f" % gain, col, 1)
		_:
			sfx.play("blip", sfx.ladder(combo), -6.0)
			burst(pos, col, 3, 40.0, 0.28, 0.9, 60.0)

func tier_up(pos: Vector2, tier: int) -> void:
	var col: Color = TIER_COLORS[clampi(tier, 0, TIER_COLORS.size() - 1)]
	sfx.play("tier", 0.9 + 0.12 * tier)
	burst(pos, col, 18, 140.0, 0.55, 1.6, 40.0)
	add_trauma(0.06 + 0.03 * tier)

func ball_dropped(pos: Vector2, all_in: bool) -> void:
	sfx.play("drop")
	burst(pos + Vector2(0, -4), Color(1, 1, 1), 6, 45.0, 0.3, 1.0, 0.0)
	add_trauma(0.05)
	if all_in:
		sfx.play("tier", 0.7)
		popup(Vector2(screen.x / 2.0, 40.0), "ALL IN!", Color(1.0, 0.3, 0.25), 3, 14.0, 1.0)
		add_trauma(0.25)

func bet_changed(direction: int) -> void:
	sfx.play("tick", 1.0 + 0.25 * direction, -4.0)

func peg_pop(row: int) -> void:
	sfx.play("pop", 0.75 + row * 0.08, -8.0)

func landed(pos: Vector2, mult: float, payout: int, bet: int, quota: int) -> void:
	var tier := 0
	if mult >= 10.0:
		tier = 5
	elif mult >= 7.0:
		tier = 4
	elif mult >= 4.0:
		tier = 3
	elif mult >= 2.0:
		tier = 2
	elif mult >= 1.0:
		tier = 1
	# Big money is a big win even at a modest multiplier
	if payout > bet and payout >= quota * 0.5:
		tier = maxi(tier, 3)
	var p := Vector2(clampf(pos.x, 50.0, screen.x - 50.0), 318.0)
	var net := payout - bet

	if tier == 0:
		win_streak = 0
		sfx.play("lose")
		popup(p, "-$%d" % -net, Color(1.0, 0.5, 0.45), 1)
		return

	win_streak += 1
	sfx.play("coin", sfx.ladder(win_streak - 1))
	popup(p, "+$%d" % net, Color(0.55, 1.0, 0.55), 3 if tier >= 4 else 2, 28.0, 0.9)
	if win_streak >= 2:
		popup(p + Vector2(0, -24), "STREAK x%d" % win_streak, Color(1.0, 0.6, 0.2), 1)
	coins(p, WIN_COINS[tier], tier >= 3)
	add_trauma(WIN_SHAKE[tier])
	party = maxf(party, WIN_PARTY[tier])

	match tier:
		2:
			sfx.play("win_small")
			popup(p + Vector2(0, -42), "NICE WIN!", Color(1.0, 0.85, 0.3), 2, 20.0, 1.0)
		3:
			sfx.play("win_big")
			show_banner("BIG WIN!", Color(1.0, 0.85, 0.3), 0.9, 4)
			flash(Color(1.0, 0.85, 0.3), 0.3, 0.35)
			hit_stop(0.05)
		4:
			sfx.play("mega")
			show_banner("MEGA WIN!!", Color(1.0, 0.5, 0.35), 1.3, 4)
			flash(Color(1.0, 0.7, 0.3), 0.4, 0.5)
			hit_stop(0.09)
			confetti(40)
		5:
			sfx.play("mega")
			show_banner("JACKPOT!!!", Color.WHITE, 2.0, 5, true)
			flash(Color(1.0, 1.0, 1.0), 0.55, 0.6)
			hit_stop(0.12)
			confetti(80)

func goal_reached() -> void:
	sfx.play("goal")
	popup(Vector2(screen.x / 2.0, 100.0), "GOAL!", Color(1.0, 0.85, 0.3), 3, 16.0, 1.1)
	flash(Color(1.0, 0.85, 0.3), 0.2, 0.3)
	party = maxf(party, 1.0)
	confetti(25)

func ante_cleared(ante: int) -> void:
	sfx.play("ante")
	show_banner("ANTE %d CLEARED!" % ante, Color(1.0, 0.85, 0.3), 1.4, 4)
	flash(Color(1.0, 0.85, 0.3), 0.4, 0.5)
	confetti(70)
	add_trauma(0.4)
	party = maxf(party, 3.0)
	hit_stop(0.06)

func busted(short_by: int, near_miss: bool) -> void:
	win_streak = 0
	sfx.play("bust")
	show_banner("BUSTED", Color(1.0, 0.3, 0.25), 1.6, 5)
	if near_miss:
		popup(Vector2(screen.x / 2.0, 214.0), "SO CLOSE!  $%d SHORT" % short_by, Color(1.0, 0.85, 0.5), 2, 10.0, 1.8)
	flash(Color(0.8, 0.0, 0.0), 0.4, 0.6)
	add_trauma(0.5)
	hit_stop(0.5, 0.2)

func notice(text: String) -> void:
	popup(Vector2(screen.x / 2.0, 190.0), text, Color(0.9, 0.9, 0.85), 2, 8.0, 1.0)

func toggle_mute() -> void:
	notice("SOUND OFF" if sfx.toggle_mute() else "SOUND ON")

func toggle_calm() -> void:
	calm = not calm
	notice("CALM MODE ON" if calm else "CALM MODE OFF")

# ---------- Building blocks ----------

func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)

# Freeze (or slow) the whole game for a moment, measured in real time.
func hit_stop(duration: float, time_scale := 0.05) -> void:
	if calm:
		return
	Engine.time_scale = time_scale
	stop_end_ms = maxi(stop_end_ms, Time.get_ticks_msec() + int(duration * 1000.0))

func flash(color: Color, alpha := 0.35, duration := 0.25) -> void:
	if calm:
		return
	if flash_tween:
		flash_tween.kill()
	flash_rect.color = Color(color.r, color.g, color.b, alpha)
	flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "color:a", 0.0, duration)

func burst(pos: Vector2, color: Color, amount := 10, speed := 90.0, life := 0.45, size := 1.0, gravity := 120.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = dot3_tex if size >= 1.15 else dot2_tex   # never scaled, so pixels stay square
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, gravity)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.color_ramp = _fade_ramp(color)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# Particle material that plays the 4-frame coin spin (no rotation, so pixels stay crisp)
func _coin_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.particles_animation = true
	m.particles_anim_h_frames = 4
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = true
	return m

# Coins fountain up from the landing spot; on big wins a coin rain falls across the screen too.
func coins(pos: Vector2, count: int, rain := false) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = coin_tex
	p.material = _coin_material()
	p.amount = count
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.direction = Vector2.UP
	p.spread = 38.0
	p.gravity = Vector2(0, 520)
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 290.0
	p.anim_speed_min = 2.0
	p.anim_speed_max = 4.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	if rain:
		var r := CPUParticles2D.new()
		r.position = Vector2(screen.x / 2.0, 12.0)
		r.texture = coin_tex
		r.material = _coin_material()
		r.amount = int(count * 0.8)
		r.lifetime = 2.2
		r.one_shot = true
		r.explosiveness = 0.35
		r.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		r.emission_rect_extents = Vector2(screen.x / 2.0 - 14.0, 2.0)
		r.direction = Vector2.DOWN
		r.spread = 12.0
		r.gravity = Vector2(0, 260)
		r.initial_velocity_min = 20.0
		r.initial_velocity_max = 80.0
		r.anim_speed_min = 2.0
		r.anim_speed_max = 4.0
		r.anim_offset_min = 0.0
		r.anim_offset_max = 1.0
		add_child(r)
		r.emitting = true
		r.finished.connect(r.queue_free)

func confetti(amount := 60) -> void:
	var rainbow_ramp := Gradient.new()
	rainbow_ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	rainbow_ramp.offsets = PackedFloat32Array([0.0, 0.17, 0.34, 0.51, 0.68, 0.85])
	rainbow_ramp.colors = PackedColorArray([
		Color(1.0, 0.3, 0.3), Color(1.0, 0.8, 0.2), Color(0.4, 1.0, 0.4),
		Color(0.3, 0.8, 1.0), Color(0.8, 0.4, 1.0), Color(1.0, 0.5, 0.8)])
	for side in 2:
		var p := CPUParticles2D.new()
		p.position = Vector2(16.0 if side == 0 else screen.x - 16.0, screen.y - 16.0)
		p.texture = dot3_tex if side == 0 else dot2_tex
		p.amount = amount
		p.lifetime = 2.4
		p.one_shot = true
		p.explosiveness = 0.9
		p.direction = Vector2(1.0 if side == 0 else -1.0, -1.1).normalized()
		p.spread = 28.0
		p.gravity = Vector2(0, 240)
		p.initial_velocity_min = 180.0
		p.initial_velocity_max = 420.0
		p.color_initial_ramp = rainbow_ramp
		p.color_ramp = _fade_ramp(Color.WHITE)
		add_child(p)
		p.emitting = true
		p.finished.connect(p.queue_free)

# Floating pixel-font text. `px` is the integer pixel scale (1 = small, 2 = medium, 3 = big).
func popup(pos: Vector2, text: String, color: Color, px := 1, rise := 22.0, life := 0.7) -> void:
	var s := Sprite2D.new()
	s.texture = PixelFont.texture(text)
	s.centered = false
	s.scale = Vector2(px, px)
	s.z_index = 20
	s.self_modulate = Color.WHITE   # first frames flash white, like a pixel-art hit flash
	var start := (pos - Vector2(s.texture.get_size()) * px / 2.0).round()
	s.position = start
	add_child(s)
	var move := s.create_tween()
	move.tween_method(func(y: float): s.position.y = roundf(y), start.y, start.y - rise, life).set_ease(Tween.EASE_OUT)
	var look := s.create_tween()
	look.tween_interval(0.06)
	look.tween_callback(func(): s.self_modulate = color)
	look.tween_interval(maxf(life * 0.7 - 0.06, 0.0))
	# Blink out instead of a smooth fade
	look.tween_method(func(t: float): s.visible = int(t * 12.0) % 2 == 0, 0.0, 1.0, life * 0.3)
	look.tween_callback(s.queue_free)

# Win banner: stepped pop-in, hold, blink out. `px` is the integer pixel scale of the text.
func show_banner(text: String, color: Color, hold := 1.0, px := 4, rainbow_text := false) -> void:
	if banner_tween:
		banner_tween.kill()
	sfx.play("whoosh", 1.0, -6.0)
	banner_sprite.texture = PixelFont.texture(text)
	banner_sprite.self_modulate = color
	banner_sprite.visible = true
	band.visible = true
	rainbow = (hold + 0.6) if rainbow_text else 0.0
	banner_tween = create_tween()
	banner_tween.tween_callback(_banner_step.bind(px + 2, 0.34))
	banner_tween.tween_interval(0.05)
	banner_tween.tween_callback(_banner_step.bind(px + 1, 0.67))
	banner_tween.tween_interval(0.05)
	banner_tween.tween_callback(_banner_step.bind(px, 1.0))
	banner_tween.tween_interval(hold)
	for i in 3:
		banner_tween.tween_callback(banner_sprite.set_visible.bind(false))
		banner_tween.tween_interval(0.06)
		banner_tween.tween_callback(banner_sprite.set_visible.bind(true))
		banner_tween.tween_interval(0.06)
	banner_tween.tween_callback(_hide_banner)

func _banner_step(px: int, band_fraction: float) -> void:
	banner_sprite.scale = Vector2(px, px)
	banner_sprite.position = (Vector2(screen.x / 2.0, BANNER_Y) - Vector2(banner_sprite.texture.get_size()) * px / 2.0).round()
	band.size.y = roundf(60.0 * band_fraction / 4.0) * 4.0
	band.position.y = BANNER_Y - band.size.y / 2.0

func _hide_banner() -> void:
	banner_sprite.visible = false
	band.visible = false
	rainbow = 0.0

# ---------- Generated textures ----------

# Fade-out in hard steps (no smooth alpha), which reads as pixel art
func _fade_ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 0.95])
	g.colors = PackedColorArray([c, Color(c.r, c.g, c.b, 0.65), Color(c.r, c.g, c.b, 0.3), Color(c.r, c.g, c.b, 0.0)])
	return g

# Square spark: size x size pixels with the corners clipped off when it is 3x3
func _make_dot(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	if size == 3:
		for corner in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
			img.set_pixelv(corner, Color(1, 1, 1, 0))
	return ImageTexture.create_from_image(img)

# 4-frame coin spin, 8x8 each: face on, turning, edge on, turning back
func _make_coin() -> ImageTexture:
	var img := Image.create(32, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half_widths := [3.9, 2.9, 0.9, 2.9]
	for f in 4:
		var rx: float = half_widths[f]
		for y in 8:
			for x in 8:
				var nx := (x - 3.5) / rx
				var ny := (y - 3.5) / 3.9
				var d := nx * nx + ny * ny
				if d <= 1.0:
					var inner := (x - 3.5) / maxf(rx - 1.0, 0.5)
					var face := inner * inner + ny * ny * 0.6 <= 0.9 and rx > 1.5
					img.set_pixel(f * 8 + x, y, Color(1.0, 0.82, 0.2) if face else Color(0.62, 0.4, 0.05))
		if f < 2:
			img.set_pixel(f * 8 + 2, 2, Color(1.0, 1.0, 0.85))
			img.set_pixel(f * 8 + 3, 2, Color(1.0, 0.95, 0.6))
	return ImageTexture.create_from_image(img)
