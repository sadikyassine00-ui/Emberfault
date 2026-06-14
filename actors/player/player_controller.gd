extends CharacterBody3D

@onready var movement = $MovementComponent
@onready var visual_model = $Axyl
@onready var camera_manager: CameraManager = $CameraManager

# Grab the state machine playback from the AnimationTree
@onready var animation_tree: AnimationTree = $Axyl/AnimationTree
@onready var state_machine = animation_tree.get("parameters/playback")

# --- Combat Memory Buffer ---
var attack_buffer_timer: float = 0.0
const ATTACK_BUFFER_TIME: float = 0.2

func _unhandled_input(event) -> void:
	# Camera rotation logic
	if camera_manager.cozy_pcam.priority > camera_manager.swarm_pcam.priority:
		handle_cozy_camera_rotation(event)

	# Catch clicks instantly at the hardware level
	if event.is_action_pressed("attack"):
		attack_buffer_timer = ATTACK_BUFFER_TIME

func handle_cozy_camera_rotation(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var pcam = camera_manager.cozy_pcam
		var rot = pcam.get_third_person_rotation_degrees()
		rot.y -= event.relative.x * 0.1
		rot.x -= event.relative.y * 0.1
		rot.x = clampf(rot.x, -50, 30)
		rot.y = wrapf(rot.y, 0, 360)
		pcam.set_third_person_rotation_degrees(rot)

func _physics_process(delta: float) -> void:
	# 1. GATHER DIRECTIONAL INPUTS
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO

	if cam:
		var cam_basis = cam.global_transform.basis
		var forward = Vector3(cam_basis.z.x, 0, cam_basis.z.z).normalized()
		var right = Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
		direction = (right * input_dir.x + forward * input_dir.y).normalized()

	var dash_pressed = Input.is_action_just_pressed("dash")
	var jump_pressed = Input.is_action_just_pressed("jump")

	# Countdown the memory buffer
	if attack_buffer_timer > 0:
		attack_buffer_timer -= delta

	# 2. COMBAT STATE CHECK
	var current_state = state_machine.get_current_node()
	var is_attacking = (current_state == "attack_1")

	# 3. WEAPON WEIGHT MODIFIER
	if is_attacking:
		movement.max_speed = 2.0
	else:
		movement.max_speed = 8.0

	# 4. TRIGGER ATTACK STATE FROM THE BUFFER
	if attack_buffer_timer > 0 and not is_attacking and not movement.is_dashing:
		print("attacking right now!!!!!!!")
		state_machine.travel("attack_1")
		is_attacking = true
		attack_buffer_timer = 0.0 # Clear the buffer so he doesn't swing twice

		# --- NEW: SNAP AIM TO CAMERA FORWARD ---
		if cam:
			var cam_basis = cam.global_transform.basis
			# Cameras look down -Z. We invert the Z axis to get the true forward direction on the floor plane.
			var cam_forward = Vector3(-cam_basis.z.x, 0, -cam_basis.z.z).normalized()

			# Instantly snap the model's visual rotation to match the camera
			if cam_forward != Vector3.ZERO:
				visual_model.rotation.y = atan2(cam_forward.x, cam_forward.z)

	# 5. PASS TO PHYSICS ENGINE
	var final_direction = direction
	movement.handle_physics(final_direction, jump_pressed, dash_pressed, delta)

	# 6. HANDLE VISUAL MODEL ROTATION (Movement)
	# This only applies when walking normally. It is bypassed during an attack to maintain the locked aim.
	if direction and not movement.is_dashing and not is_attacking:
		var target_angle = atan2(direction.x, direction.z)
		visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, 0.2)

	# 7. ENGINE RUN/IDLE STATE MACHINE UPDATES
	_update_animations(is_attacking)

func _update_animations(is_attacking: bool) -> void:
	# If the state machine is busy handling the attack, bypass movement states entirely
	if is_attacking or movement.is_dashing:
		return

	var horizontal_velocity = Vector2(velocity.x, velocity.z)

	if horizontal_velocity.length() > 0.2 and is_on_floor():
		state_machine.travel("run")
	else:
		state_machine.travel("idle")
