extends Node2D

const PEG_SCENE := preload("res://scenes/peg.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const FxScript := preload("res://scripts/fx.gd")
const CrateScript := preload("res://scripts/crate.gd")
const PixelLabel := preload("res://scripts/pixel_label.gd")
const Chips := preload("res://scripts/chips.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const Fmt := preload("res://scripts/fmt.gd")

const MIN_BET := 5
const BALL_KEYS := ["normal", "heavy", "bouncy", "ghost"]   # keys 1-4
const BALL_NAMES := {"normal": "NORMAL", "heavy": "HEAVY", "bouncy": "BOUNCY", "ghost": "GHOST"}
const BALL_TAGS := {"normal": "", "heavy": "H ", "bouncy": "B ", "ghost": "G "}
const LIVE_ROWS := 5

# Colors
const GOLD := Color(0.85, 0.65, 0.2)
const PANEL_BG := Color(0.07, 0.09, 0.08, 0.92)
const TEXT_DIM := Color(0.7, 0.7, 0.65)
const DIM := Color(0.45, 0.45, 0.42)
const RED := Color(1.0, 0.38, 0.32)
const MONEY_GOLD := Color(1.0, 0.82, 0.3)
const BLUE := Color(0.45, 0.72, 1.0)
const WHITE := Color(0.95, 0.95, 0.92)

@export var rows := 8
@export var first_row_count := 3    # chips in the top row; each row below adds one
@export var spacing := 38.0
@export var top_y := 60
@export var drop_jitter := 2.0      # tiny random nudge so every drop isn't identical
@export var starting_money := 100
@export var balls_per_ante := 5
@export var first_quota := 250
@export var quota_growth := 2.0     # each ante's goal is 2x the last

var pegs: Array[Node2D] = []

# HUD
var goal_value: Control
var money_value: Control
var bet_value: Control
var ante_value: Control
var balls_value: Control
var last_value: Control
var message_label: Control
var live_labels: Array[Control] = []
var live_empty: Control
var ball_labels := {}
var perk_box: VBoxContainer

# Game state
var money := 0
var bet := 10
var ante := 1
var quota := 0
var balls_left := 0
var busted := false
var ante_over := false
var goal_announced := false
var crate_open := false
var inventory := {"heavy": 0, "bouncy": 0, "ghost": 0}   # special balls you own
var perks := {}                                            # upgrade id -> stacks
var pity := 0                                              # crates in a row without epic+
var selected := "normal"
var live_balls: Array[RigidBody2D] = []

# Juice
var fx: Node2D
var shown_money := 0.0   # what the money label displays; counts up toward `money`
var prev_money := 0
var tick_cooldown := 0.0

func _ready() -> void:
	fx = FxScript.new()
	add_child(fx)
	fx.setup(get_viewport_rect().size)
	build_walls_and_tray()
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
	inventory = {"heavy": 1, "bouncy": 1, "ghost": 0}
	perks = {}
	pity = 0
	selected = "normal"
	last_value.text = "-"
	update_ball_panel()
	update_perk_panel()
	start_ante()
	open_crate("STARTER CRATE")

func start_ante() -> void:
	quota = int(round(first_quota * pow(quota_growth, ante - 1)))
	balls_left = balls_per_ante + perks.get("extra", 0)
	ante_over = false
	goal_announced = false
	new_board()
	clamp_bet()
	var warn := ""
	if ante == 2:
		warn = "\nNEW: MINUS CHIPS!"
	elif ante > 2:
		warn = "\nMORE SKULLS AND MINUS."
	message_label.text = "ANTE %d: REACH %s\n%d BALLS%s\nUP/DOWN BET  A ALL IN\nSPACE DROP  1-4 BALL" % [ante, Fmt.money(quota), balls_left, warn]
	update_status()

func check_ante_end() -> void:
	if ante_over or busted or not live_balls.is_empty():
		return
	if money >= quota:
		ante_over = true
		message_label.text = "GOAL REACHED!\nOPEN YOUR CRATE..."
		fx.ante_cleared(ante)
		await get_tree().create_timer(1.8).timeout
		await open_crate("ANTE %d CRATE" % ante)
		ante += 1
		start_ante()
	elif balls_left == 0 or money < MIN_BET:
		ante_over = true
		busted = true
		var reason := "OUT OF BALLS" if balls_left == 0 else "OUT OF MONEY"
		message_label.text = "BUSTED!\n%s AT ANTE %d.\nPRESS R TO PLAY AGAIN." % [reason, ante]
		fx.busted(maxi(quota - money, 0), money >= int(quota * 0.75))

# Crate spin; resolves when the prize is claimed
func open_crate(title: String) -> void:
	crate_open = true
	var crate: CanvasLayer = CrateScript.new()
	crate.fx = fx
	crate.screen = get_viewport_rect().size
	add_child(crate)
	crate.open(title, perks, pity)
	var item: String = await crate.finished
	grant(item)
	crate_open = false

func grant(id: String) -> void:
	var it: Dictionary = Upgrades.ITEMS[id]
	pity = pity + 1 if it["rarity"] == "rare" else 0
	if it["kind"] == "ball":
		inventory[it["ball"]] += it["count"]
		update_ball_panel()
	else:
		perks[id] = perks.get(id, 0) + 1
		update_perk_panel()
		if id == "extra" and not ante_over:
			balls_left += 1
		if id == "midas" and not ante_over:
			add_midas(3)
	update_status()

# Upgrade effects handed to every ball as it drops
func ball_mods() -> Dictionary:
	return {
		"black_cut": maxf(0.75 - 0.15 * perks.get("lucky", 0), 0.0),
		"neg_scale": pow(0.6, perks.get("skin", 0)),
		"gold_add": 0.01 * perks.get("gold", 0),
	}

# ---------- Difficulty ----------

func skull_count() -> int:
	return mini(3 + int((ante - 1) * 0.6), 12)

func minus_count() -> int:
	return 0 if ante < 2 else mini(4 + 3 * (ante - 2), 24)

# ---------- Status ----------

func update_status() -> void:
	goal_value.text = Fmt.money(quota)
	if float(money) < shown_money:
		shown_money = float(money)   # losses leave instantly
		pulse(money_value, Color(1.6, 0.5, 0.5))
	elif money > prev_money:
		pulse(money_value, Color(1.6, 1.6, 1.6))
	prev_money = money
	money_value.text = Fmt.money(shown_money)
	bet_value.text = Fmt.money(bet)
	ante_value.text = str(ante)
	balls_value.text = str(balls_left)

# ---------- Betting (no cap: 5, 10, 25, 50, 100, 250, 500, 1K ... forever) ----------

func bet_step_up(b: int) -> int:
	var step := 5
	var i := 0
	while step <= b:
		i += 1
		step = [5, 10, 25][i % 3] * int(pow(10, i / 3))
	return step

func bet_step_down(b: int) -> int:
	var best := MIN_BET
	var step := 5
	var i := 0
	while step < b:
		best = step
		i += 1
		step = [5, 10, 25][i % 3] * int(pow(10, i / 3))
	return best

func change_bet(direction: int) -> void:
	var old_bet := bet
	if direction > 0:
		var up := bet_step_up(bet)
		bet = up if up <= money else bet
	else:
		bet = bet_step_down(bet)
	clamp_bet()
	if bet != old_bet:
		fx.bet_changed(direction)
		pulse(bet_value, Color(1.5, 1.5, 1.5))
	update_status()

func clamp_bet() -> void:
	# You can never bet more than you have
	if bet > money:
		bet = bet_step_down(money + 1)
	bet = maxi(bet, MIN_BET)

# ---------- Balls ----------

func drop_ball() -> void:
	if busted or ante_over or crate_open or balls_left <= 0 or bet > money:
		return
	var all_in := bet >= 100 and bet * 10 >= money * 9
	money -= bet
	balls_left -= 1
	var type := selected
	if type != "normal":
		inventory[type] -= 1
		if inventory[type] <= 0:
			selected = "normal"
		update_ball_panel()
	var center_x := get_viewport_rect().size.x / 2.0
	var ball := spawn_ball(type, Vector2(center_x + randf_range(-drop_jitter, drop_jitter), 20), bet)
	fx.ball_dropped(ball.position, all_in)
	clamp_bet()
	update_status()

func spawn_ball(type: String, pos: Vector2, ball_bet: int) -> RigidBody2D:
	var ball: RigidBody2D = BALL_SCENE.instantiate()
	ball.setup(type, ball_mods())
	ball.set_meta("bet", ball_bet)
	ball.position = pos
	if type == "ghost":
		# Ghosts don't even touch skulls and minus chips
		for p in pegs:
			if Chips.is_bad(p.get_meta("chip")):
				ball.add_collision_exception_with(p)
	ball.tree_exited.connect(_on_ball_gone.bind(ball))
	ball.chip_hit.connect(_on_chip_hit)
	ball.tier_up.connect(_on_tier_up)
	live_balls.append(ball)
	add_child(ball)
	return ball

# Runs whenever a ball is removed (collected, timed out, or fell off)
func _on_ball_gone(ball: Node) -> void:
	live_balls.erase(ball)
	if is_queued_for_deletion() or not is_inside_tree():
		return
	if not ball.get_meta("settled", false):
		# Timed out or lost before reaching the tray: give the bet back
		var refund: int = ball.get_meta("bet", 0)
		money += refund
		message_label.text = "BALL TIMED OUT.\n%s REFUNDED." % Fmt.money(refund)
		update_status()
	call_deferred("check_ante_end")

# Ball reached the collection tray: pay out bet x multiplier (after perks)
func _on_tray_entered(body: Node2D) -> void:
	if not body.has_method("get_multiplier") or body.get_meta("settled", false):
		return
	body.set_meta("settled", true)
	var ball_bet: int = body.get_meta("bet", 0)
	var mult: float = body.get_multiplier()
	var notes := []
	if mult < 0.0 and perks.has("insure"):
		mult = 0.0
		notes.append("INSURED")
	if mult > 1.0 and perks.has("roller"):
		mult *= pow(1.25, perks["roller"])
		notes.append("HIGH ROLLER")
	if mult > 1.0 and perks.has("jackpot"):
		mult *= 2.0
		notes.append("JACKPOT X2")
	var payout := int(round(ball_bet * mult))
	money = maxi(money + payout, 0)
	var net := payout - ball_bet
	last_value.text = Fmt.mult(mult)
	last_value.self_modulate = RED if mult < 1.0 else WHITE
	var line := "PAID %s" % Fmt.money(payout) if payout >= 0 else "LOST %s MORE" % Fmt.money(-payout)
	message_label.text = "%s BET  %s\n%s  (%s%s)" % [Fmt.money(ball_bet), Fmt.mult(mult), line, "+" if net >= 0 else "-", Fmt.money(absi(net))]
	if not notes.is_empty():
		message_label.text += "\n" + " + ".join(notes)
	update_status()
	fx.landed(body.position, mult, payout, ball_bet, quota)
	if not goal_announced and money >= quota and live_balls.size() > 1:
		goal_announced = true
		fx.goal_reached()
	body.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if crate_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				drop_ball()
			KEY_UP:
				change_bet(1)
			KEY_DOWN:
				change_bet(-1)
			KEY_A:
				if money >= MIN_BET:
					bet = money
					pulse(bet_value, Color(1.6, 0.6, 0.5))
					update_status()
			KEY_1:
				select_ball("normal")
			KEY_2:
				select_ball("heavy")
			KEY_3:
				select_ball("bouncy")
			KEY_4:
				select_ball("ghost")
			KEY_M:
				fx.toggle_mute()
			KEY_C:
				fx.toggle_calm()
			KEY_R:
				if busted:
					start_run()

func select_ball(type: String) -> void:
	if type != "normal" and inventory[type] <= 0:
		fx.sfx.play("lose", 1.4, -6.0)
		pulse(ball_labels[type], Color(1.6, 0.4, 0.4))
		return
	if selected != type:
		selected = type
		fx.sfx.play("pop", 1.0 + 0.15 * BALL_KEYS.find(type))
	update_ball_panel()
	pulse(ball_labels[type], Color(1.5, 1.5, 1.5))

# ---------- Juice ----------

func _process(delta: float) -> void:
	# Money counts up toward its real value, ticking like a slot machine payout
	var target := float(money)
	if absf(shown_money - target) > 0.5:
		var before := int(shown_money)
		shown_money = move_toward(shown_money, target, maxf(absf(target - shown_money) * 4.0, 40.0) * delta)
		money_value.text = Fmt.money(shown_money)
		tick_cooldown -= delta
		if tick_cooldown <= 0.0 and int(shown_money) != before:
			fx.sfx.play("tick", 1.0 + 0.6 * shown_money / maxf(target, 1.0), -8.0)
			tick_cooldown = 0.05
	elif shown_money != target:
		shown_money = target
		money_value.text = Fmt.money(money)
	update_live_panel()

func _on_chip_hit(ball: RigidBody2D, peg: Node, chip: String, gain: float) -> void:
	var smashed: bool = chip == "black" and ball.ball_type == "heavy"
	fx.chip_hit(chip, ball.global_position, gain, ball.hits - 1, smashed)
	if smashed:
		set_chip(peg, Chips.pick_positive())   # heavy balls turn skulls into good chips
	var i := live_balls.find(ball)
	if i >= 0 and i < live_labels.size():
		pulse(live_labels[i], Color(1.6, 0.5, 0.5) if gain < 0.0 else Color(1.5, 1.5, 1.5))

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

# Staggered board, re-rolled every ante. Later antes bring more skulls and minus chips.
func new_board() -> void:
	for peg in pegs:
		peg.queue_free()
	pegs.clear()

	var screen := get_viewport_rect().size
	var center_x := screen.x / 2.0
	var max_count := int((screen.x - 48.0) / spacing) + 1
	for row in rows:
		var count := first_row_count + row
		if count > max_count:
			count = max_count - ((count - max_count) % 2)
		var row_width := (count - 1) * spacing
		for i in count:
			var peg: Node2D = PEG_SCENE.instantiate()
			peg.position = Vector2(center_x - row_width / 2.0 + i * spacing, top_y + row * spacing * 0.866)
			add_child(peg)
			peg.set_meta("row", row)
			set_chip(peg, Chips.pick_positive())
			pegs.append(peg)
			pop_in(peg, row, i)

	for row in rows:
		get_tree().create_timer(row * 0.045).timeout.connect(fx.peg_pop.bind(row))

	# Skulls: one is always on the bottom row, the rest anywhere below the top row
	var bottom := pegs.filter(func(p): return p.get_meta("row") == rows - 1)
	set_chip(bottom.pick_random(), "black")
	var open := pegs.filter(func(p): return p.get_meta("row") > 0 and p.get_meta("chip") != "black")
	open.shuffle()
	for i in mini(skull_count() - 1, open.size()):
		set_chip(open[i], "black")
	# Minus chips
	open = open.filter(func(p): return p.get_meta("chip") != "black")
	open.shuffle()
	for i in mini(minus_count(), open.size()):
		set_chip(open[i], Chips.pick_negative(ante))
	add_midas(3 * perks.get("midas", 0))

func add_midas(n: int) -> void:
	var good := pegs.filter(func(p): return p.get_meta("chip") in ["c1", "c5", "c10"])
	good.shuffle()
	for i in mini(n, good.size()):
		set_chip(good[i], "c100")

func set_chip(peg: Node2D, chip: String) -> void:
	peg.get_node("Sprite2D").texture = Chips.texture(chip)
	peg.set_meta("chip", chip)

# Invisible walls around the screen (the gold frame is drawn on top), with the collection tray along the bottom
func build_walls_and_tray() -> void:
	var screen := get_viewport_rect().size
	var t := 8.0   # wall thickness, same as the frame
	add_wall(Vector2(screen.x / 2.0, t / 2.0), Vector2(screen.x, t))
	add_wall(Vector2(screen.x / 2.0, screen.y - t / 2.0), Vector2(screen.x, t))
	add_wall(Vector2(t / 2.0, screen.y / 2.0), Vector2(t, screen.y))
	add_wall(Vector2(screen.x - t / 2.0, screen.y / 2.0), Vector2(t, screen.y))

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

func add_wall(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

# ---------- HUD ----------
# Left column: messages, live multipliers, ball picker. Right column: stats, perks.
# Both columns stay clear of the chips (the board is at most 342px wide in the middle).

func build_hud() -> void:
	var hud := CanvasLayer.new()   # separate layer so balls never draw over the UI
	add_child(hud)
	var screen := get_viewport_rect().size

	var left := VBoxContainer.new()
	left.position = Vector2(12, 12)
	left.add_theme_constant_override("separation", 6)
	hud.add_child(left)

	var msg := make_panel(left, 176)
	message_label = PixelLabel.new()
	msg.add_child(message_label)

	var live_box := add_box(make_panel(left, 124), "LIVE MULTIPLIER")
	live_empty = PixelLabel.new()
	live_empty.text = "DROP A BALL"
	live_empty.self_modulate = DIM
	live_box.add_child(live_empty)
	for i in LIVE_ROWS:
		var row := PixelLabel.new()
		row.px = 2
		row.visible = false
		live_box.add_child(row)
		live_labels.append(row)

	var ball_box := add_box(make_panel(left, 124), "NEXT BALL")
	for type in BALL_KEYS:
		var row := PixelLabel.new()
		ball_box.add_child(row)
		ball_labels[type] = row

	var right := VBoxContainer.new()
	right.position = Vector2(screen.x - 12 - 120, 12)
	right.add_theme_constant_override("separation", 6)
	hud.add_child(right)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 3)
	make_panel(right, 120).add_child(stats)
	goal_value = add_stat(stats, "GOAL", RED)
	money_value = add_stat(stats, "MONEY", MONEY_GOLD)
	bet_value = add_stat(stats, "BET", BLUE)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 0)
	stats.add_child(pair)
	ante_value = add_stat(pair, "ANTE", WHITE, 54)
	balls_value = add_stat(pair, "BALLS", WHITE, 54)
	last_value = add_stat(stats, "LAST", WHITE)

	perk_box = add_box(make_panel(right, 120), "PERKS")
	update_ball_panel()
	update_perk_panel()

func make_panel(parent: Node, width: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", make_panel_style())
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)
	return panel

func add_box(panel: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var head := PixelLabel.new()
	head.text = title
	head.self_modulate = TEXT_DIM
	box.add_child(head)
	return box

func add_stat(parent: Node, title: String, color: Color, width := 0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	if width > 0:
		box.custom_minimum_size = Vector2(width, 0)
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

func update_ball_panel() -> void:
	if ball_labels.is_empty():
		return
	for i in BALL_KEYS.size():
		var type: String = BALL_KEYS[i]
		var label: Control = ball_labels[type]
		var count := "" if type == "normal" else " X%d" % inventory[type]
		var arrow := ">" if type == selected else " "
		label.text = "%s%d %s%s" % [arrow, i + 1, BALL_NAMES[type], count]
		if type == selected:
			label.self_modulate = Color(1.0, 0.9, 0.45)
		elif type != "normal" and inventory[type] <= 0:
			label.self_modulate = DIM
		else:
			label.self_modulate = WHITE

func update_perk_panel() -> void:
	if perk_box == null:
		return
	for child in perk_box.get_children().slice(1):
		child.queue_free()
	if perks.is_empty():
		var none := PixelLabel.new()
		none.text = "WIN CRATES!"
		none.self_modulate = DIM
		perk_box.add_child(none)
		return
	for id in perks:
		var it: Dictionary = Upgrades.ITEMS[id]
		var row := PixelLabel.new()
		row.text = it["name"] + ("" if perks[id] == 1 else " X%d" % perks[id])
		row.self_modulate = Upgrades.rarity_color(it["rarity"]).lightened(0.25)
		perk_box.add_child(row)

func update_live_panel() -> void:
	for i in live_labels.size():
		var label: Control = live_labels[i]
		if i < live_balls.size() and is_instance_valid(live_balls[i]):
			var b := live_balls[i]
			label.text = BALL_TAGS[b.ball_type] + Fmt.mult(b.get_multiplier())
			label.self_modulate = b.tier_color()
			label.visible = true
		else:
			label.visible = false
	live_empty.visible = live_balls.is_empty()
