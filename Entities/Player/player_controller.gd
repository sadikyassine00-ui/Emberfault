extends CharacterBody3D

@onready var movement = $MovementComponent
@onready var visual_model = $Visuals
@onready var camera_manager: CameraManager = $CameraManager


func _unhandled_input(event) -> void:
	# Only rotate the camera if the COZY camera is the boss
	if camera_manager.cozy_pcam.priority > camera_manager.swarm_pcam.priority:
		handle_cozy_camera_rotation(event)

func handle_cozy_camera_rotation(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var pcam = camera_manager.cozy_pcam
		var rot = pcam.get_third_person_rotation_degrees()
		rot.y -= event.relative.x * 0.1 # Using sensitivity
		rot.x -= event.relative.y * 0.1
		rot.x = clampf(rot.x, -50, 30)
		rot.y = wrapf(rot.y, 0, 360)
		pcam.set_third_person_rotation_degrees(rot)

func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO

	if cam:
		# This logic works for BOTH cameras perfectly!
		# It always calculates "Forward" based on what the lens sees.
		var cam_basis = cam.global_transform.basis
		var forward = Vector3(cam_basis.z.x, 0, cam_basis.z.z).normalized()
		var right = Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
		direction = (right * input_dir.x + forward * input_dir.y).normalized()

	var dash_pressed = Input.is_action_just_pressed("dash") # Make sure to map "dash" to Shift or Space
	movement.handle_physics(direction, Input.is_action_just_pressed("jump"), dash_pressed, delta)

	if direction:
		var target_angle = atan2(direction.x, direction.z)
		visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, 0.2)
