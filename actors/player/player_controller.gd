extends CharacterBody3D

signal strike_impact(position: Vector3)

@onready var movement: MovementComponent = $MovementComponent
@onready var combat: CombatComponent = $CombatComponent
@onready var visual_model: Node3D = $Axyl

# AAA Initialization Protection Properties
var _initial_y: float = 0.0
var _is_stabilized: bool = false
var _stabilization_timer: float = 1.5 # 1.5 second safety window for async voxel threads

func _ready() -> void:
	# Capture exact editor-placed height coordinate before physics engine cycles run
	_initial_y = global_position.y

	# Forward strike impact signal from CombatComponent for backwards compatibility
	if combat:
		combat.strike_impact.connect(func(pos: Vector3):
			strike_impact.emit(pos)
		)

func _unhandled_input(event: InputEvent) -> void:
	# Catch attack clicks
	if event.is_action_pressed("attack"):
		if movement and combat:
			if not movement.is_dashing:
				combat.start_attack()

	if event.is_action_pressed("ui_home"): # Default "Home" key on your keyboard
		# 1. Attempt to borrow the reference already cached by your CombatComponent
		var combat_comp = get_node_or_null("CombatComponent")
		if combat_comp and combat_comp.horde_manager:
			# Calculate 5 meters forward based on your visual heading vector so they spawn where you look
			var forward_dir = - combat_comp.visual_model.global_transform.basis.z.normalized()
			var spawn_point = global_position + (forward_dir * 5.0)

			combat_comp.horde_manager.debug_inject_cluster(10, spawn_point)
			return

		# 2. Hard Fail-Safe: If the component link isn't ready, locate the manager directly in the world root
		var fallback_manager = get_tree().current_scene.find_child("HordeManager", true, false) as HordeManager
		if fallback_manager:
			var spawn_point = global_position + Vector3(0, 0, -5.0)
			fallback_manager.debug_inject_cluster(10, spawn_point)
		else:
			print("⚠️ [DEBUG ERROR] Cluster injection aborted. HordeManager node cannot be located anywhere in the active scene tree.")

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

	# 2. COMBAT STATE CHECK & WEAPON WEIGHT MODIFIER
	var is_attacking = combat.is_attacking if combat else false

	if movement:
		if is_attacking:
			movement.max_speed = 2.0
		else:
			movement.max_speed = 8.0

	# 3. PASS TO PHYSICS ENGINE
	if movement:
		movement.handle_physics(direction, jump_pressed, dash_pressed, delta)

	# AAA Anchor Intercept: Prevents falling through asynchronous unbaked voxel meshes
	if not _is_stabilized:
		_stabilization_timer -= delta
		velocity.y = 0.0
		global_position.y = _initial_y

		# Release position anchor the exact frame the floor materializes or safety clock expires
		if is_on_floor() or _stabilization_timer <= 0.0:
			_is_stabilized = true

	# 4. HANDLE VISUAL MODEL ROTATION (Movement)
	if direction and visual_model:
		var is_dashing = movement.is_dashing if movement else false
		if not is_dashing and not is_attacking:
			var target_angle = atan2(direction.x, direction.z)
			visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, 0.2)

	# 5. ENGINE RUN/IDLE STATE MACHINE UPDATES
	_update_animations(is_attacking)

func _update_animations(is_attacking: bool) -> void:
	var is_dashing = movement.is_dashing if movement else false
	if is_attacking or is_dashing:
		return

	var horizontal_velocity = Vector2(velocity.x, velocity.z)
	var state_machine = combat.state_machine if combat else null

	if state_machine:
		if horizontal_velocity.length() > 0.2 and is_on_floor():
			state_machine.travel("run")
		else:
			state_machine.travel("idle")
