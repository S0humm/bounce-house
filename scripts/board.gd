extends Node2D

const PEG_SCENE := preload("res://scenes/peg.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const FxScript := preload("res://scripts/fx.gd")
const PixelLabel := preload("res://scripts/pixel_label.gd")

const CHIP_TEXTURES := {
	"white": preload("res://art/peg_white.png"),
	"red": preload("res://art/peg_red.png"),
	"blue": preload("res://art/peg_blue.png"),
	"green": preload("res://art/peg_green.png"),
	"black": preload("res://art/peg_black.png"),
}

const BET_STEPS := [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000]

# Colors
const GOLD := Color(0.85, 0.65, 0.2)
const PANEL_BG := Color(0.07, 0.09, 0.08, 0.92)
const TEXT_DIM := Color(0.7, 0.7, 0.65)
const RED := Color(1.0, 0.38, 0.32)
const MONEY_GOLD := Color(1.0, 0.82, 0.3)
const BLUE := Color(0.45, 0.72, 1.0)
const WHITE := Color(0.95, 0.95, 0.92)

@export var rows := 8
@export var first_row_count := 3    # chips in the top row; each row below adds one
@export var spacing := 38.0
@export var top_y := 60
@export var black_chips := 4
@export var drop_jitter := 2.0      # tiny random nudge so every drop isn't identical
@export var starting_money := 100
@export var balls_per_ante := 5
@export var first_quota := 250
@export var quota_growth := 2.0     # each ante's goal is 2x the last

var pegs: Array[Node2D] = []

# HUD labels
var goal_value: Control   # PixelLabel
var money_value: Control   # PixelLabel
var bet_value: Control   # PixelLabel
var ante_value: Control   # PixelLabel
var balls_value: Control   # PixelLabel
var last_value: Control   # PixelLabel
var message_label: Control   # PixelLabel

# Game state
var money := 0
var bet := 10
var ante := 1
var quota := 0
var balls_left := 0
var balls_in_play := 0
var busted := false
var ante_over := false
var goal_announced := false

# Juice
var fx: Node2D
var shown_money := 0.0   # what the money label displays; counts up toward `money`
var prev_money := 0
var tick_cooldown := 0.0

func _ready() -> void:
	fx = FxScript.new()
	add_child(fx)
	fx.setup(get_viewport_rect().size)
	build_border_and_tray()
	build_hud()
	start_run()

# ---------- Run and ante flow ----------

func start_run() -> void:
	money = starting_money
	shown_money = float(money)
	prev_money = money
	bet = 10
	ante = 1
	busted = false
	last_value.text = "-"
	start_ante()

func start_ante() -> void:
	quota = int(round(first_quota * pow(quota_growth, ante - 1)))
	balls_left = balls_per_ante
	ante_over = false
	goal_announced = false
	new_board()
	clamp_bet()
	message_label.text = "ANTE %d\nReach $%d with %d balls.\nUP/DOWN BET   A ALL IN\nSPACE DROP   M MUTE   C CALM" % [ante, quota, balls_per_ante]
	update_status()

func check_ante_end() -> void:
	if ante_over or balls_in_play > 0:
		return
	if money >= quota:
		ante_over = true
		message_label.text = "GOAL REACHED!\nNext ante..."
		fx.ante_cleared(ante)
		ante += 1
		await get_tree().create_timer(2.2).timeout
		start_ante()
	elif balls_left == 0 or money < BET_STEPS[0]:
		ante_over = true
		busted = true
		var reason := "Out of balls" if balls_left == 0 else "Out of money"
		message_label.text = "BUSTED!\n%s at ante %d.\nPress R to play again." % [reason, ante]
		fx.busted(maxi(quota - money, 0), money >= int(quota * 0.75))

func update_status() -> void:
	goal_value.text = "$%d" % quota
	if float(money) < shown_money:
		shown_money = float(money)   # bets leave instantly
		pulse(money_value, Color(1.6, 0.5, 0.5))
	elif money > prev_money:
		pulse(money_value, Color(1.6, 1.6, 1.6))
	prev_money = money
	money_value.text = "$%d" % int(round(shown_money))
	bet_value.text = "$%d" % bet
	ante_value.text = str(ante)
	balls_value.text = str(balls_left)

# ---------- Betting ----------

func change_bet(direction: int) -> void:
	# Move to the next step above/below the current bet, never past what you can afford
	var target: int = bet
	if direction > 0:
		for step in BET_STEPS:
			if step > bet:
				target = step
				break
		if target > money:
			target = bet   # can't afford the next step, stay put
	else:
		target = BET_STEPS[0]
		for step in BET_STEPS:
			if step < bet:
				target = step
	var old_bet := bet
	bet = target
	clamp_bet()
	if bet != old_bet:
		fx.bet_changed(direction)
		pulse(bet_value, Color(1.5, 1.5, 1.5))
	update_status()

func clamp_bet() -> void:
	# You can never bet more than you have
	if bet > money:
		bet = BET_STEPS[0]
		for step in BET_STEPS:
			if step <= money:
				bet = step
	bet = max(bet, BET_STEPS[0])

# ---------- Balls ----------

func drop_ball() -> void:
	if busted or ante_over or balls_left <= 0 or bet > money:
		return
	var all_in := bet >= 100 and bet * 10 >= money * 9
	money -= bet
	balls_left -= 1
	balls_in_play += 1
	var ball: RigidBody2D = BALL_SCENE.instantiate()
	ball.set_meta("bet", bet)
	var center_x := get_viewport_rect().size.x / 2.0
	ball.position = Vector2(center_x + randf_range(-drop_jitter, drop_jitter), 20)
	ball.tree_exited.connect(_on_ball_gone.bind(ball))
	ball.chip_hit.connect(_on_chip_hit)
	ball.tier_up.connect(_on_tier_up)
	add_child(ball)
	fx.ball_dropped(ball.position, all_in)
	clamp_bet()
	update_status()

# Runs whenever a ball is removed (collected, timed out, or fell off)
func _on_ball_gone(ball: Node) -> void:
	balls_in_play -= 1
	if not ball.get_meta("settled", false):
		# Timed out or lost before reaching the tray: give the bet back
		var refund: int = ball.get_meta("bet", 0)
		money += refund
		message_label.text = "Ball timed out.\n$%d refunded." % refund
		update_status()
	call_deferred("check_ante_end")

# Ball reached the collection tray: pay out bet x chip multiplier
func _on_tray_entered(body: Node2D) -> void:
	if body.has_method("get_multiplier") and not body.get_meta("settled", false):
		var ball_bet: int = body.get_meta("bet", 0)
		var mult: float = body.get_multiplier()
		var payout := int(round(ball_bet * mult))
		money += payout
		var net := payout - ball_bet
		var sign := "+" if net >= 0 else ""
		last_value.text = "x%.3f" % mult
		message_label.text = "$%d bet  x%.3f\nPaid $%d  (%s%d)" % [ball_bet, mult, payout, sign, net]
		update_status()
		fx.landed(body.position, mult, payout, ball_bet, quota)
		if not goal_announced and money >= quota and balls_in_play > 1:
			goal_announced = true
			fx.goal_reached()
		body.set_meta("settled", true)
		body.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				drop_ball()
			KEY_UP:
				change_bet(1)
			KEY_DOWN:
				change_bet(-1)
			KEY_A:
				bet = max(money, BET_STEPS[0])
				update_status()
			KEY_M:
				fx.toggle_mute()
			KEY_C:
				fx.toggle_calm()
			KEY_R:
				if busted:
					start_run()

# ---------- Juice ----------

func _process(delta: float) -> void:
	# Money counts up toward its real value, ticking like a slot machine payout
	var target := float(money)
	if absf(shown_money - target) > 0.5:
		var before := int(shown_money)
		shown_money = move_toward(shown_money, target, maxf(absf(target - shown_money) * 4.0, 40.0) * delta)
		money_value.text = "$%d" % int(round(shown_money))
		tick_cooldown -= delta
		if tick_cooldown <= 0.0 and int(shown_money) != before:
			fx.sfx.play("tick", 1.0 + 0.6 * shown_money / maxf(target, 1.0), -8.0)
			tick_cooldown = 0.05
	elif shown_money != target:
		shown_money = target
		money_value.text = "$%d" % money

func _on_chip_hit(ball: RigidBody2D, chip: String, gain: float) -> void:
	fx.chip_hit(chip, ball.global_position, gain, ball.hits - 1)

func _on_tier_up(ball: RigidBody2D, tier: int) -> void:
	fx.tier_up(ball.global_position, tier)

# Quick 1.5x jump plus color flash on a HUD value, in two hard steps (no smooth easing)
func pulse(label: Control, tint: Color) -> void:
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(1.5, 1.5)
	label.modulate = tint
	var tw := label.create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(func(): label.scale = Vector2.ONE)
	tw.tween_interval(0.09)
	tw.tween_callback(func(): label.modulate = Color.WHITE)

# Chips pop in row by row when a new board is built
func pop_in(peg: Node2D, row: int, i: int) -> void:
	var sprite: Sprite2D = peg.get_node("Sprite2D")
	sprite.scale = Vector2.ZERO
	var tw := sprite.create_tween()
	tw.tween_interval(row * 0.045 + i * 0.008)
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------- Board building ----------

# Full staggered board, new colors every ante
func new_board() -> void:
	for peg in pegs:
		peg.queue_free()
	pegs.clear()

	var screen := get_viewport_rect().size
	var center_x := screen.x / 2.0
	# Most chips that fit across the screen with room for the ball at the walls
	var max_count := int((screen.x - 48.0) / spacing) + 1
	for row in rows:
		var count := first_row_count + row
		if count > max_count:
			# Keep the stagger once rows hit full width
			count = max_count - ((count - max_count) % 2)
		var row_width := (count - 1) * spacing
		for i in count:
			var peg: Node2D = PEG_SCENE.instantiate()
			peg.position = Vector2(center_x - row_width / 2.0 + i * spacing, top_y + row * spacing * 0.866)
			add_child(peg)
			set_chip(peg, pick_color())
			pegs.append(peg)
			pop_in(peg, row, i)

	for row in rows:
		get_tree().create_timer(row * 0.045).timeout.connect(fx.peg_pop.bind(row))

	# Make a few random chips black (the rare, highest-value ones)
	var shuffled := pegs.duplicate()
	shuffled.shuffle()
	for i in min(black_chips, shuffled.size()):
		set_chip(shuffled[i], "black")

func pick_color() -> String:
	var r := randf() * 100.0
	if r < 60.0:
		return "white"   # 60%
	elif r < 85.0:
		return "red"     # 25%
	elif r < 95.0:
		return "blue"    # 10%
	return "green"       # 5%

func set_chip(peg: Node2D, color: String) -> void:
	peg.get_node("Sprite2D").texture = CHIP_TEXTURES[color]
	peg.set_meta("chip", color)

# Gold border around the whole screen, with the collection tray along the bottom
func build_border_and_tray() -> void:
	var screen := get_viewport_rect().size
	var t := 8.0   # border thickness

	add_block(Vector2(screen.x / 2.0, t / 2.0), Vector2(screen.x, t), GOLD)                 # top
	add_block(Vector2(screen.x / 2.0, screen.y - t / 2.0), Vector2(screen.x, t), GOLD)      # bottom
	add_block(Vector2(t / 2.0, screen.y / 2.0), Vector2(t, screen.y), GOLD)                 # left
	add_block(Vector2(screen.x - t / 2.0, screen.y / 2.0), Vector2(t, screen.y), GOLD)      # right

	# One sensor along the bottom: any ball that reaches it gets paid out
	var tray := Area2D.new()
	tray.position = Vector2(screen.x / 2.0, screen.y - t - 6.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(screen.x - t * 2.0, 12)
	shape.shape = rect
	tray.add_child(shape)
	tray.body_entered.connect(_on_tray_entered)
	add_child(tray)

func add_block(center: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var vis := ColorRect.new()
	vis.size = size
	vis.position = -size / 2.0
	vis.color = color
	body.add_child(vis)
	add_child(body)

# ---------- HUD ----------

func build_hud() -> void:
	# Separate layer so balls never draw over the UI
	var hud := CanvasLayer.new()
	add_child(hud)
	var screen := get_viewport_rect().size

	# Stats panel, top right
	var stats := PanelContainer.new()
	stats.add_theme_stylebox_override("panel", make_panel_style())
	stats.custom_minimum_size = Vector2(196, 0)
	hud.add_child(stats)
	stats.anchor_left = 1.0
	stats.anchor_right = 1.0
	stats.offset_left = -196 - 12
	stats.offset_right = -12
	stats.offset_top = 12
	stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	stats.add_child(grid)

	goal_value = add_stat(grid, "GOAL", RED)
	money_value = add_stat(grid, "MONEY", MONEY_GOLD)
	bet_value = add_stat(grid, "BET", BLUE)
	ante_value = add_stat(grid, "ANTE", WHITE)
	balls_value = add_stat(grid, "BALLS", WHITE)
	last_value = add_stat(grid, "LAST", WHITE)

	# Message panel, top left
	var msg := PanelContainer.new()
	msg.add_theme_stylebox_override("panel", make_panel_style())
	msg.custom_minimum_size = Vector2(200, 0)
	msg.position = Vector2(12, 12)
	hud.add_child(msg)

	message_label = PixelLabel.new()
	msg.add_child(message_label)

func add_stat(parent: Node, title: String, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(58, 0)
	box.add_theme_constant_override("separation", 1)

	var title_label := PixelLabel.new()
	title_label.text = title
	title_label.self_modulate = TEXT_DIM
	box.add_child(title_label)

	var value_label := PixelLabel.new()
	value_label.px = 2
	value_label.self_modulate = color
	box.add_child(value_label)

	parent.add_child(box)
	return value_label

func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.anti_aliasing = false   # hard pixel edges
	style.set_content_margin_all(6)
	return style
