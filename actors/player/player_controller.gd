extends CharacterBody3D

signal strike_impact(position: Vector3)

@export var slash_scene: PackedScene # Drag and drop your WeaponTrail3D.tscn here

@onready var movement: MovementComponent = $MovementComponent
@onready var combat: CombatComponent = $CombatComponent
@onready var health_component: Node = $HealthComponent
@onready var visual_model: Node3D = $Axyl

var active_trail: Node3D = null

# AAA Architectural Cache & Stabilization
var _camera_cache: Camera3D = null
var _initial_y: float = 0.0
var _is_stabilized: bool = false
var _stabilization_timer: float = 1.5

func _ready() -> void:
	_initial_y = global_position.y
	_cache_active_camera()

	if combat:
		combat.strike_impact.connect(func(pos: Vector3) -> void:
			strike_impact.emit(pos)
		)

func _cache_active_camera() -> void:
	var vp := get_viewport()
	if vp:
		_camera_cache = vp.get_camera_3d()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		if movement and combat and not movement.is_dashing:
			combat.start_attack()

	if event.is_action_pressed("ui_home"):
		# Optimized: Uses pre-cached combat component reference instantly
		if combat and combat.horde_manager:
			var forward_dir := -combat.visual_model.global_transform.basis.z.normalized()
			var spawn_point := global_position + (forward_dir * 5.0)
			combat.horde_manager.debug_inject_cluster(10, spawn_point)
			return

		var current_scene := get_tree().current_scene
		if current_scene:
			var fallback_manager := current_scene.find_child("HordeManager", true, false) as HordeManager
			if fallback_manager:
				var spawn_point := global_position + Vector3(0, 0, -5.0)
				fallback_manager.debug_inject_cluster(10, spawn_point)

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# O(1) Pointer Validation: Only queries scene tree if the camera object dies/changes
	if not is_instance_valid(_camera_cache):
		_cache_active_camera()

	var direction := Vector3.ZERO
	if _camera_cache:
		var cam_basis := _camera_cache.global_transform.basis
		var forward := Vector3(cam_basis.z.x, 0.0, cam_basis.z.z).normalized()
		var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
		direction = (right * input_dir.x + forward * input_dir.y).normalized()

	var dash_pressed := Input.is_action_just_pressed("dash")
	var jump_pressed := Input.is_action_just_pressed("jump")
	var is_attacking := combat.is_attacking if combat else false

	# Consolidated Component Operations to reduce branch checking overhead
	if movement:
		movement.max_speed = 2.0 if is_attacking else 8.0
		movement.handle_physics(direction, jump_pressed, dash_pressed, delta)

		if not _is_stabilized:
			_stabilization_timer -= delta
			velocity.y = 0.0
			global_position.y = _initial_y
			if is_on_floor() or _stabilization_timer <= 0.0:
				_is_stabilized = true

		if direction and visual_model and not movement.is_dashing and not is_attacking:
			var target_angle := atan2(direction.x, direction.z)
			visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, 0.2)

	_update_animations(is_attacking)

func _update_animations(is_attacking: bool) -> void:
	var is_dashing := movement.is_dashing if movement else false
	if is_attacking or is_dashing:
		return

	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var state_machine = combat.state_machine if combat else null

	if state_machine:
		if horizontal_velocity.length() > 0.2 and is_on_floor():
			state_machine.travel("run")
		else:
			state_machine.travel("idle")

func take_damage(amount: float) -> void:
	if health_component and health_component.has_method("apply_damage"):
		health_component.apply_damage(amount)
