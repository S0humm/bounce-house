extends RigidBody2D

# How much each chip color adds to the ball's multiplier
const CHIP_ADD := {"white": 0.01, "red": 0.25, "blue": 0.05, "green": 0.1}

@export var max_lifetime := 20.0   # seconds before a ball is removed no matter what (typical fall is ~9s, slowest ~12s)
@export var stuck_speed := 10.0    # slower than this counts as "not moving"
@export var stuck_delay := 1.0     # seconds of not moving before we nudge it

var age := 0.0
var stuck_time := 0.0
var bonus := 0.0      # running multiplier, starts at x0.00
var label: Label

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	lock_rotation = true   # keeps the number above the ball from spinning
	body_entered.connect(_on_body_entered)

	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(48, 12)
	label.position = Vector2(-24, -20)
	label.add_theme_font_size_override("font_size", 10)
	add_child(label)
	update_label()

func _on_body_entered(body: Node) -> void:
	if body.has_method("hit"):
		body.hit()
		var chip: String = body.get_meta("chip", "white")
		if chip == "black":
			# Black chip: halve the ball's multiplier
			bonus *= 0.5
			flash_label(Color(1.0, 0.3, 0.3))
		else:
			bonus += CHIP_ADD.get(chip, 0.0)
		update_label()

func flash_label(color: Color) -> void:
	label.modulate = color
	var tw := create_tween()
	tw.tween_property(label, "modulate", Color.WHITE, 0.4)

func get_multiplier() -> float:
	return bonus

func update_label() -> void:
	label.text = "x%.3f" % get_multiplier()

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
