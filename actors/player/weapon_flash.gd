extends MeshInstance3D

var active_tween: Tween

func _ready() -> void:
	hide()
	set_instance_shader_parameter("sweep_progress", 0.0)
	set_instance_shader_parameter("dissolve_progress", 0.0)

func play_weapon_flash() -> void:
	if active_tween:
		active_tween.kill()

	# Clear registers back to zero
	set_instance_shader_parameter("sweep_progress", 0.0)
	set_instance_shader_parameter("dissolve_progress", 0.0)
	show()

	active_tween = create_tween().set_parallel(true)

	# ⚡ FIX: Using explicit lambdas prevents Godot from swapping the parameter order
	active_tween.tween_method(
		func(val: float): set_instance_shader_parameter("sweep_progress", val),
		0.0, 1.0, 0.12
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	active_tween.chain().tween_method(
		func(val: float): set_instance_shader_parameter("dissolve_progress", val),
		0.0, 1.0, 0.16
	).set_trans(Tween.TRANS_LINEAR)

	active_tween.chain().tween_callback(hide)
