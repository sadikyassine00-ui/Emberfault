class_name CameraManager
extends Node

@export var isometric_pcam: PhantomCamera3D
@export var main_cam: Camera3D

func _ready() -> void:
	activate_isometric()

func activate_isometric() -> void:
	if main_cam and isometric_pcam:
		main_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		main_cam.fov = 17
		isometric_pcam.priority = 20
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func shake(amplitude: float = 5.0, duration: float = 0.2) -> void:
	if not isometric_pcam:
		return

	# Instantiate a new PhantomCameraNoise3D resource
	var noise_res = PhantomCameraNoise3D.new()
	noise_res.amplitude = amplitude
	noise_res.frequency = 0.5
	noise_res.rotational_noise = true
	noise_res.positional_noise = true

	isometric_pcam.set_noise(noise_res)

	# Create a tween to decay the trauma of the noise resource over duration
	var tween = create_tween()
	tween.tween_method(func(trauma: float):
		noise_res.set_trauma(trauma)
	, 1.0, 0.0, duration)

	# Clean up noise resource after shake completes
	tween.tween_callback(func():
		if isometric_pcam.get_noise() == noise_res:
			isometric_pcam.set_noise(null)
	)
