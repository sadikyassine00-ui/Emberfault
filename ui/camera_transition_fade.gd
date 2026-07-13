extends Control

@export var camera_manager: CameraManager

func _ready() -> void:
	modulate.a = 0
	hide()


func fade_in(duration: float = 1.0) -> Tween:
	var tween = create_tween()
	# 1. Make sure it's not hidden
	show()
	# 2. Ensure we start from exactly 0
	modulate.a = 0
	# 3. Animate
	tween.tween_property(self, "modulate:a", 1.0, duration)
	return tween

func fade_out(duration: float = 1.0):
	var tween = create_tween()
	# Interpolate alpha to 0
	tween.tween_property(self, "modulate:a", 0.0, duration)
	# Optional: Hide the node after the fade finishes so it doesn't block clicks
	tween.tween_callback(hide)
