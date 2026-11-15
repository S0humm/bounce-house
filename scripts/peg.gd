extends StaticBody2D

var tween: Tween

# Called by the ball when it touches this chip: a quick little bump
func hit() -> void:
	var sprite: Sprite2D = $Sprite2D
	if tween:
		tween.kill()
	sprite.scale = Vector2.ONE
	tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.05)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.1)
