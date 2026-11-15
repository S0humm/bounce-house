extends RigidBody2D

const PixelFont := preload("res://scripts/pixel_font.gd")

# The board listens to these to play sound and effects
signal chip_hit(ball: RigidBody2D, chip: String, gain: float)
signal tier_up(ball: RigidBody2D, tier: int)

# How much each chip color adds to the ball's multiplier
const CHIP_ADD := {"white": 0.01, "red": 0.25, "blue": 0.05, "green": 0.1}

# Multiplier needed to reach each glow tier (the ball and its trail change color)
const TIER_STEPS := [1.0, 2.0, 4.0, 7.0]
const TIER_COLORS := [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.92, 0.45),
	Color(1.0, 0.62, 0.2),
	Color(1.0, 0.35, 0.7),
	Color(0.55, 1.0, 1.0),
]

@export var max_lifetime := 20.0   # seconds before a ball is removed no matter what (typical fall is ~9s, slowest ~12s)
@export var stuck_speed := 10.0    # slower than this counts as "not moving"
@export var stuck_delay := 1.0     # seconds of not moving before we nudge it

var age := 0.0
var stuck_time := 0.0
var bonus := 0.0      # running multiplier, starts at x0.00
var hits := 0         # chips touched so far (drives the rising pitch)
var tier := 0
var label: Sprite2D      # the multiplier number, drawn with the pixel font
var label_px := 1
var trail: CPUParticles2D
var label_tween: Tween

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	lock_rotation = true   # keeps the number above the ball from spinning
	body_entered.connect(_on_body_entered)

	label = Sprite2D.new()
	label.centered = false
	add_child(label)
	build_trail()
	update_label()

# Glowing tail made from the ball's own sprite, so it needs no extra art
func build_trail() -> void:
	trail = CPUParticles2D.new()
	trail.show_behind_parent = true
	trail.local_coords = false
	trail.texture = $Sprite2D.texture
	trail.amount = 16
	trail.lifetime = 0.3
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.0
	trail.scale_amount_min = 0.5   # exactly half size: clean 6x6 pixels
	trail.scale_amount_max = 0.5
	var fade := Gradient.new()
	fade.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	fade.offsets = PackedFloat32Array([0.0, 0.35, 0.65, 0.9])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0)])
	trail.color_ramp = fade
	add_child(trail)

func _on_body_entered(body: Node) -> void:
	if body.has_method("hit"):
		body.hit()
		var chip: String = body.get_meta("chip", "white")
		var gain := 0.0
		if chip == "black":
			# Black chip: halve the ball's multiplier
			gain = -bonus * 0.5
			bonus *= 0.5
			flash_label(Color(1.0, 0.3, 0.3))
		else:
			gain = CHIP_ADD.get(chip, 0.0)
			bonus += gain
		hits += 1
		var new_tier := 0
		for step in TIER_STEPS:
			if bonus >= step:
				new_tier += 1
		var climbed := new_tier > tier
		tier = new_tier
		update_label()
		pop_label()
		chip_hit.emit(self, chip, gain)
		if climbed:
			tier_up.emit(self, tier)

func flash_label(color: Color) -> void:
	label.modulate = color
	var tw := create_tween()
	tw.tween_property(label, "modulate", Color.WHITE, 0.4)

# Number jumps to 2x for a moment on every hit (whole-pixel scales only)
func pop_label() -> void:
	if label_tween:
		label_tween.kill()
	place_label(2)
	label_tween = create_tween()
	label_tween.tween_interval(0.08)
	label_tween.tween_callback(place_label.bind(1))

# Center the number above the ball at an integer pixel scale
func place_label(px: int) -> void:
	label_px = px
	label.scale = Vector2(px, px)
	var width: int = label.texture.get_width() * px
	label.position = Vector2(-floorf(width / 2.0), -20 - 4 * px)

func get_multiplier() -> float:
	return bonus

func update_label() -> void:
	label.texture = PixelFont.texture("x%.3f" % get_multiplier())
	var col: Color = TIER_COLORS[tier]
	label.self_modulate = col
	$Sprite2D.modulate = col
	trail.color = col
	place_label(label_px)

func _physics_process(delta: float) -> void:
	age += delta
	# Hard limit: no ball lives forever
	if age > max_lifetime or position.y > 400.0:
		queue_free()
		return
	# If the ball is resting somewhere, give it a small push
	if linear_velocity.length() < stuck_speed:
		stuck_time += delta
		if stuck_time > stuck_delay:
			apply_central_impulse(Vector2(randf_range(-40.0, 40.0), -20.0))
			stuck_time = 0.0
	else:
		stuck_time = 0.0
