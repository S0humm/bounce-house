extends Node2D
## Game feel, kept simple: sounds and short text popups. No particles, shake or flashes.
## The board calls the high-level methods (chip_hit, landed, ante_cleared, ...).

const SfxScript := preload("res://scripts/sfx.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Chips := preload("res://scripts/chips.gd")
const Fmt := preload("res://scripts/fmt.gd")

const WALL := Color(0.07, 0.18, 0.1)   # the 8px edge the balls bounce off

var sfx: Node
var screen := Vector2(640, 360)

func setup(size: Vector2) -> void:
	screen = size
	z_index = 10
	sfx = SfxScript.new()
	add_child(sfx)
	queue_redraw()

# Flat felt comes from the project's clear color; this just marks the walls
func _draw() -> void:
	var t := 8.0
	draw_rect(Rect2(0, 0, screen.x, t), WALL)
	draw_rect(Rect2(0, screen.y - t, screen.x, t), WALL)
	draw_rect(Rect2(0, 0, t, screen.y), WALL)
	draw_rect(Rect2(screen.x - t, 0, t, screen.y), WALL)

func chip_hit(chip: String, pos: Vector2, gain: float, combo: int) -> void:
	var info := Chips.info(chip)
	if info["kind"] == "black":
		sfx.play("womp")
		popup(pos + Vector2(0, -16), "-50%", Color(1.0, 0.35, 0.3))
		return
	var add: float = info["add"]
	if add >= 0.25:
		sfx.play("ding_red", sfx.ladder(combo))
		popup(pos + Vector2(0, -14), "+%.2f" % gain, Chips.color(chip))
	elif add >= 0.05:
		sfx.play("ding_blue", sfx.ladder(combo))
	else:
		sfx.play("blip", sfx.ladder(combo), -6.0)

func tier_up(_pos: Vector2, tier: int) -> void:
	sfx.play("tier", 0.9 + 0.12 * tier)

func ball_dropped(_pos: Vector2, all_in: bool) -> void:
	sfx.play("drop")
	if all_in:
		popup(Vector2(screen.x / 2.0, 40.0), "ALL IN!", Color(1.0, 0.3, 0.25), 2)

func bet_changed(direction: int) -> void:
	sfx.play("tick", 1.2 if direction > 0 else 0.9)

func landed(pos: Vector2, _mult: float, payout: int, bet: int, _quota: int) -> void:
	var p := Vector2(clampf(pos.x, 50.0, screen.x - 50.0), 318.0)
	var net := payout - bet
	if net >= 0:
		sfx.play("coin")
		popup(p, "+" + Fmt.money(net), Color(0.55, 1.0, 0.55), 2, 24.0, 0.9)
	else:
		sfx.play("lose")
		popup(p, "-" + Fmt.money(-net), Color(1.0, 0.45, 0.4), 2, 24.0, 0.9)

func goal_reached() -> void:
	sfx.play("goal")
	popup(Vector2(screen.x / 2.0, 100.0), "GOAL!", Color(1.0, 0.85, 0.3), 3, 16.0, 1.1)

func ante_cleared(ante: int) -> void:
	sfx.play("ante")
	popup(Vector2(screen.x / 2.0, 150.0), "ANTE %d CLEARED!" % ante, Color(1.0, 0.85, 0.3), 3, 10.0, 1.6)

func extinct() -> void:
	sfx.play("womp", 0.8)
	popup(Vector2(screen.x / 2.0, 200.0), "GROS MICHEL WENT EXTINCT", Color(1.0, 0.9, 0.35), 1, 8.0, 2.0)

func busted(short_by: int, near_miss: bool) -> void:
	sfx.play("bust")
	popup(Vector2(screen.x / 2.0, 150.0), "BUSTED", Color(1.0, 0.3, 0.25), 4, 6.0, 2.0)
	if near_miss:
		popup(Vector2(screen.x / 2.0, 200.0), "SO CLOSE! %s SHORT" % Fmt.money(short_by), Color(1.0, 0.85, 0.5), 1, 6.0, 2.0)

func toggle_mute() -> void:
	sfx.toggle_mute()

# Text that floats up a little and disappears
func popup(pos: Vector2, text: String, color: Color, px := 1, rise := 18.0, life := 0.7) -> void:
	var s := Sprite2D.new()
	s.texture = PixelFont.texture(text)
	s.centered = false
	s.scale = Vector2(px, px)
	s.z_index = 20
	s.self_modulate = color
	var start := (pos - Vector2(s.texture.get_size()) * px / 2.0).round()
	s.position = start
	add_child(s)
	var tw := s.create_tween()
	tw.tween_method(func(y: float): s.position.y = roundf(y), start.y, start.y - rise, life).set_ease(Tween.EASE_OUT)
	tw.tween_callback(s.queue_free)
