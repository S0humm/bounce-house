extends RigidBody2D

const Chips := preload("res://scripts/chips.gd")

# The board listens to these to play sound and effects
signal chip_hit(ball: RigidBody2D, peg: Node, chip: String, gain: float)
signal tier_up(ball: RigidBody2D, tier: int)

# Ball types:
#   normal: the standard ball
#   heavy:  falls fast, every chip counts double, smashes skulls into good chips
#   bouncy: springs around and gets +0.03 extra on every hit
#   ghost:  floats straight through skulls
const TYPES := {
	"normal": {"gravity": 0.7,  "bounce": 0.8,  "friction": 0.01, "mass": 1.0, "gain": 1.0, "max_speed": 420.0, "ring": Color(0, 0, 0, 0)},
	"heavy":  {"gravity": 1.1,  "bounce": 0.3,  "friction": 0.3, "mass": 4.0, "gain": 2.0, "max_speed": 480.0, "ring": Color(0.6, 0.66, 0.8)},
	"bouncy": {"gravity": 0.55, "bounce": 0.9,  "friction": 0.0, "mass": 0.8, "gain": 1.0, "max_speed": 230.0, "ring": Color(0.62, 0.95, 0.2)},
	"ghost":  {"gravity": 0.7,  "bounce": 0.8,  "friction": 0.01, "mass": 1.0, "gain": 1.0, "max_speed": 420.0, "ring": Color(0.55, 0.95, 1.0)},
}
const BOUNCY_BONUS := 0.03
const MIN_MULT := -3.0   # floor, so one cursed ball can't wipe out your whole bankroll

# Multiplier needed to reach each glow tier (the ball changes color)
const TIER_STEPS := [1.0, 2.0, 4.0, 7.0]
const TIER_COLORS := [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.92, 0.45),
	Color(1.0, 0.62, 0.2),
	Color(1.0, 0.35, 0.7),
	Color(0.55, 1.0, 1.0),
]
const NEGATIVE_COLOR := Color(1.0, 0.3, 0.3)

@export var max_lifetime := 20.0   # seconds before a ball is removed no matter what
@export var stuck_speed := 10.0    # slower than this counts as "not moving"
@export var stuck_delay := 1.0     # seconds of not moving before we nudge it

var ball_type := "normal"
# Upgrade effects, filled in by the board before the ball drops
var black_cut := 0.5      # share of the multiplier a skull takes away
var gold_add := 0.0       # extra on every good chip
var age := 0.0
var stuck_time := 0.0
var bonus := 0.0      # running multiplier, starts at x0.00
var hits := 0         # chips touched so far (drives the rising pitch)
var tier := 0
var ring: Sprite2D

# Call before adding the ball to the scene
func setup(type_name: String, mods: Dictionary) -> void:
	ball_type = type_name if TYPES.has(type_name) else "normal"
	black_cut = mods.get("black_cut", 0.5)
	gold_add = mods.get("gold_add", 0.0)

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	lock_rotation = true
	can_sleep = false   # a sleeping ball would never get pushed free
	body_entered.connect(_on_body_entered)
	var t: Dictionary = TYPES[ball_type]
	gravity_scale = t["gravity"]
	mass = t["mass"]
	var mat := PhysicsMaterial.new()   # own material, so one ball's type never changes another's
	mat.bounce = t["bounce"]
	mat.friction = t["friction"]
	physics_material_override = mat
	if ball_type != "normal":
		ring = Sprite2D.new()
		ring.texture = _ring_texture()
		ring.self_modulate = t["ring"]
		add_child(ring)
	if ball_type == "ghost":
		$Sprite2D.self_modulate = Color(1, 1, 1, 0.55)
	update_look()

# 1px ring drawn around special balls so you can tell them apart
func _ring_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var r := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if r > 6.6 and r <= 7.8:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

func _on_body_entered(body: Node) -> void:
	if not body.has_method("hit"):
		return
	var chip: String = body.get_meta("chip", "c1")
	var info := Chips.info(chip)
	if ball_type == "ghost" and info["kind"] != "add":
		return   # (ghosts also skip the collision itself, see the board)
	body.hit()
	var gain_mult: float = TYPES[ball_type]["gain"]
	var before := bonus
	match info["kind"]:
		"black":
			if ball_type != "heavy":
				# A skull takes half the multiplier away (and pushes a negative one further down)
				bonus -= absf(bonus) * black_cut
		"add":
			bonus += (info["add"] + gold_add) * gain_mult
	if ball_type == "bouncy":
		bonus += BOUNCY_BONUS
	bonus = maxf(bonus, MIN_MULT)
	var gain := bonus - before
	hits += 1
	var new_tier := 0
	for step in TIER_STEPS:
		if bonus >= step:
			new_tier += 1
	var climbed := new_tier > tier
	tier = new_tier
	update_look()
	chip_hit.emit(self, body, chip, gain)
	if climbed:
		tier_up.emit(self, tier)

func get_multiplier() -> float:
	return bonus

func tier_color() -> Color:
	return NEGATIVE_COLOR if bonus < 0.0 else TIER_COLORS[tier]

func update_look() -> void:
	var col := tier_color()
	$Sprite2D.modulate = col

# Keep every ball under its top speed so nothing rockets off the board
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var cap: float = TYPES[ball_type]["max_speed"]
	if state.linear_velocity.length() > cap:
		state.linear_velocity = state.linear_velocity.limit_length(cap)

func _physics_process(delta: float) -> void:
	age += delta
	# Hard limit: no ball lives forever
	if age > max_lifetime or position.y > 400.0 or position.y < -100.0:
		queue_free()
		return
	# If the ball is resting somewhere, push it free. Heavy balls barely bounce and settle on
	# chips easily, so they get checked sooner and pushed harder (never stuck for 0.5s).
	var heavy := ball_type == "heavy"
	var slow := stuck_speed * (3.0 if heavy else 1.0)
	var wait := 0.2 if heavy else stuck_delay
	if linear_velocity.length() < slow:
		stuck_time += delta
		if stuck_time > wait:
			var side := 1.0 if randf() < 0.5 else -1.0
			var push := randf_range(90.0, 130.0) if heavy else randf_range(20.0, 40.0)
			linear_velocity = Vector2(side * push, -40.0 if heavy else -20.0)
			stuck_time = 0.0
	else:
		stuck_time = 0.0
