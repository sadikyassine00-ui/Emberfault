class_name CameraManager
extends Node

@export var cozy_pcam: PhantomCamera3D
@export var swarm_pcam: PhantomCamera3D
@export var main_cam: Camera3D

signal camera_toggled

func _ready() -> void:
	activate_cozy()

func _unhandled_input(event: InputEvent) -> void:
	# Temporary toggle key for testing (e.g., "C" key)
	if event.is_action_pressed("ui_focus_next"): # Usually Tab
		toggle_camera()

func toggle_camera() -> void:
	camera_toggled.emit()
	if cozy_pcam.priority > swarm_pcam.priority:
		await get_tree().create_timer(0.4).timeout
		activate_swarm()
	else:
		await get_tree().create_timer(0.4).timeout
		activate_cozy()

func activate_cozy() -> void:
	main_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	main_cam.fov = 60
	cozy_pcam.priority = 20
	swarm_pcam.priority = 10
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func activate_swarm() -> void:
	# Switch to the flat look
	main_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	main_cam.fov = 17
	# main_cam.size = 20.0 # Adjust this for "Zoom" in Ortho mode

	swarm_pcam.priority = 20
	cozy_pcam.priority = 10
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
