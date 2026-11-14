extends StaticBody2D

var tween: Tween

# Called by the ball when it touches this chip
func hit() -> void:
	var sprite: Sprite2D = $Sprite2D
	# Restart cleanly if the chip gets hit again mid-animation
	if tween:
		tween.kill()
	sprite.scale = Vector2.ONE
	tween = create_tween()
	# Pop up to 1.2x fast, then spring back
	tween.tween_property(sprite, "scale", Vector2(1.2, 1.2), 0.05)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
