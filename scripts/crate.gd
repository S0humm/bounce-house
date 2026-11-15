extends CanvasLayer
## Crate opening between antes: a strip of prizes spins, slows down and lands.
## The odds are rigged in your favor (you never actually land a common) and it likes
## to stop one tile short of a legendary.

signal finished(item: String)

const Upgrades := preload("res://scripts/upgrades.gd")
const PixelLabel := preload("res://scripts/pixel_label.gd")
const BallIcons := preload("res://scripts/ball_icons.gd")

const TILE := 52          # distance between tiles on the strip
const TILE_W := 48
const TILE_H := 56
const STRIP := 48         # tiles on the strip
const WIN := 40           # index of the tile we land on
const SPIN_TIME := 4.5
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
var claim_ready := false

var root: Control
var strip: Control
var tiles: Array[Control] = []
var title: Control
var name_label: Control
var desc_label: Control
var prompt: Control

func open(title_text: String, owned: Dictionary, pity: int, bag_room := 99) -> void:
	layer = 8
	winner = Upgrades.roll(owned, pity, bag_room)
	var items := []
	for i in STRIP:
		items.append(Upgrades.filler(owned))
	items[WIN] = winner
	# The near miss: a legendary sitting right after the one you get
	var legend := Upgrades.legendary_item(owned)
	if Upgrades.ITEMS[winner]["rarity"] != "legendary" and legend != "" and randf() < 0.7:
		items[WIN + 1] = legend
		near_miss = true
	_build(title_text, items)

func _build(title_text: String, items: Array) -> void:
	root = Control.new()
	root.size = screen
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim := ColorRect.new()
	dim.size = screen
	dim.color = Color(0.02, 0.04, 0.03, 0.85)
	root.add_child(dim)

	title = _label(title_text, 3, Color(1.0, 0.85, 0.3))
	_center(title, 62)

	var window := Control.new()
	window.clip_contents = true
	window.position = Vector2((screen.x - WINDOW_W) / 2.0, 120)
	window.size = Vector2(WINDOW_W, WINDOW_H)
	root.add_child(window)
	var back := ColorRect.new()
	back.size = window.size
	back.color = Color(0, 0, 0, 0.5)
	window.add_child(back)
	strip = Control.new()
	window.add_child(strip)
	for i in items.size():
		var tile := _tile(items[i])
		tile.position = Vector2(i * TILE + 2, 4)
		strip.add_child(tile)
		tiles.append(tile)

	# Pointer: a thin line through the middle of the window
	var line := ColorRect.new()
	line.position = Vector2(floorf(screen.x / 2.0), 114)
	line.size = Vector2(1, WINDOW_H + 12)
	line.color = Color(1.0, 0.85, 0.3)
	root.add_child(line)

	name_label = _label("", 2, Color.WHITE)
	name_label.visible = false
	desc_label = _label("", 1, Color(0.85, 0.85, 0.8))
	desc_label.visible = false
	prompt = _label("PRESS SPACE TO SPIN", 1, Color(1.0, 0.95, 0.75))
	_center(prompt, 300)

# Tile: rarity-colored box with your hand-drawn icon (if it exists) or the prize's short name
func _tile(id: String) -> Control:
	var it: Dictionary = Upgrades.ITEMS[id]
	var col := Upgrades.rarity_color(it["rarity"])
	var tile := ColorRect.new()
	tile.size = Vector2(TILE_W, TILE_H)
	tile.color = col.darkened(0.6)
	var band := ColorRect.new()
	band.position = Vector2(0, TILE_H - 5)
	band.size = Vector2(TILE_W, 5)
	band.color = col
	tile.add_child(band)
	var tex := Upgrades.icon_texture(id)
	if it["kind"] == "ball":
		var pic := BallIcons.rect(it["ball"], 32)   # the actual ball you get
		pic.position = Vector2((TILE_W - 32) / 2.0, 10)
		tile.add_child(pic)
	elif tex:
		var icon := TextureRect.new()
		icon.texture = tex
		# Small pixel icons stay crisp; bigger hand-drawn art is scaled down smoothly
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if tex.get_width() <= 32 else CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(32, 32)
		icon.position = Vector2((TILE_W - 32) / 2.0, 10)
		tile.add_child(icon)
	else:
		var text := PixelLabel.new()
		text.text = it["short"]
		text.self_modulate = col.lightened(0.4)
		tile.add_child(text)
		text.position = Vector2(floorf((TILE_W - text.size.x) / 2.0), 22)
	if it["kind"] == "ball":
		var badge := PixelLabel.new()
		badge.text = "X%d" % it["count"]
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
	var jitter := randf_range(-16.0, 16.0)
	if near_miss:
		jitter = randf_range(14.0, 21.0)   # stops right at the edge, the legendary peeking in
	target = WIN * TILE + 2 + TILE_W / 2.0 + jitter - WINDOW_W / 2.0
	t = 0.0

func _process(delta: float) -> void:
	if state == "idle" or (state == "reveal" and claim_ready):
		prompt.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
	if state != "spinning":
		return
	t = minf(t + delta / SPIN_TIME, 1.0)
	var e := 1.0 - pow(1.0 - t, 4.0)
	reel_pos = target * e
	strip.position.x = -roundf(reel_pos)
	var idx := int((reel_pos + WINDOW_W / 2.0 - 2.0) / TILE)
	if idx != last_tick:
		last_tick = idx
		fx.sfx.play("tick", 0.8 + 0.9 * e, -2.0)
	if t >= 1.0:
		_reveal()

func _reveal() -> void:
	state = "reveal"
	var it: Dictionary = Upgrades.ITEMS[winner]
	var rarity: String = it["rarity"]
	var col := Upgrades.rarity_color(rarity)
	title.text = rarity.to_upper() + "!"
	title.self_modulate = col
	_center(title, 62)
	name_label.text = it["name"]
	name_label.self_modulate = col.lightened(0.3)
	_center(name_label, 202)
	name_label.visible = true
	desc_label.text = it["desc"]
	_center(desc_label, 228)
	desc_label.visible = true
	fx.sfx.play({"rare": "win_small", "epic": "win_big"}.get(rarity, "mega"))
	prompt.text = "PRESS SPACE TO CLAIM"
	_center(prompt, 300)
	await get_tree().create_timer(0.6).timeout
	claim_ready = true
	prompt.visible = true
