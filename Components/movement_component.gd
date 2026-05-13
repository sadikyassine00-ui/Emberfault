class_name MovementComponent
extends Node

@export var visuals: Node3D

@export_group("Settings")
@export var max_speed: float = 8.0
@export var acceleration: float = 80.0
@export var friction: float = 60.0
@export var jump_force: float = 12.0
@export var gravity_scale: float = 3.0

@export_group("Step Up Logic")
@export var enable_step_up: bool = true
@export var step_height: float = 0.65 # Set to slightly above your 0.6 voxel scale
@export var step_check_distance: float = 0.5 # How far ahead to look for a step

@export_group("Dash Settings")
@export var dash_speed: float = 30.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.4

@export_group("Forgiveness")
@export var coyote_duration: float = 0.15 # Time allowed to jump after falling
@export var jump_buffer_duration: float = 0.15 # Time to remember a "jump" press

# Internal variables
var parent: CharacterBody3D
var is_dashing: bool = false
var is_invincible: bool = false # iFrame check for your Health system later

var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

func _ready() -> void:
	parent = get_parent() as CharacterBody3D

func handle_physics(direction: Vector3, wants_to_jump: bool, wants_to_dash: bool, delta: float) -> void:
	# --- TIMER UPDATES ---
	if dash_timer > 0:
		dash_timer -= delta
		is_invincible = true # Active iFrames
		if dash_timer <= 0:
			is_dashing = false
			is_invincible = false # End iFrames

	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	# Coyote Timer Logic
	if parent.is_on_floor():
		coyote_timer = coyote_duration
	else:
		coyote_timer -= delta

	# Jump Buffer Logic
	if wants_to_jump:
		jump_buffer_timer = jump_buffer_duration
	else:
		jump_buffer_timer -= delta

	# --- ACTIONS ---

	# 1. Dash
	if wants_to_dash and dash_cooldown_timer <= 0:
		start_dash(direction)

	# 2. Gravity
	if not parent.is_on_floor() and not is_dashing:
		var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		parent.velocity.y -= gravity * gravity_scale * delta

	# 3. Forgiving Jump (Coyote + Buffer)
	if coyote_timer > 0 and jump_buffer_timer > 0 and not is_dashing:
		parent.velocity.y = jump_force
		coyote_timer = 0
		jump_buffer_timer = 0

	# 4. Movement
	if not is_dashing:
		if direction:
			parent.velocity.x = move_toward(parent.velocity.x, direction.x * max_speed, acceleration * delta)
			parent.velocity.z = move_toward(parent.velocity.z, direction.z * max_speed, acceleration * delta)
		else:
			parent.velocity.x = move_toward(parent.velocity.x, 0, friction * delta)
			parent.velocity.z = move_toward(parent.velocity.z, 0, friction * delta)

	# 5. Voxel Step-Up Logic (Must happen right before move_and_slide)
	if enable_step_up and direction != Vector3.ZERO:
		_handle_step_up(direction)

	parent.move_and_slide()

func start_dash(direction: Vector3) -> void:
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown

	var dash_dir = direction
	if dash_dir == Vector3.ZERO:
		dash_dir = -parent.get_node("Visuals").global_transform.basis.z.normalized()

	parent.velocity.x = dash_dir.x * dash_speed
	parent.velocity.z = dash_dir.z * dash_speed
	parent.velocity.y = 0

# --- NEW STEP LOGIC ---
func _handle_step_up(direction: Vector3) -> void:
	# Only step up if we are grounded, trying to move, and actively hitting a wall
	if not parent.is_on_floor() or not parent.is_on_wall() or parent.velocity.y > 0.0:
		return

	var space_state = parent.get_world_3d().direct_space_state
	var move_dir = Vector3(direction.x, 0, direction.z).normalized()

	# 1. Cast a ray forward at chest height to make sure there is room to step into
	var chest_pos = parent.global_position + Vector3(0, step_height + 0.1, 0)
	var chest_target = chest_pos + (move_dir * step_check_distance)

	var chest_query = PhysicsRayQueryParameters3D.create(chest_pos, chest_target)
	chest_query.exclude = [parent.get_rid()] # Ignore the player's own body

	# If the chest ray hits nothing, the space above the block is clear
	if not space_state.intersect_ray(chest_query):

		# 2. Cast a second ray DOWN from that clear space to find the exact top of the block
		var down_target = chest_target - Vector3(0, step_height + 0.2, 0)
		var down_query = PhysicsRayQueryParameters3D.create(chest_target, down_target)
		down_query.exclude = [parent.get_rid()]

		var down_hit = space_state.intersect_ray(down_query)

		if down_hit:
			# Calculate the exact vertical height of the block we hit
			var step_y_diff = down_hit.position.y - parent.global_position.y

			# 3. If the block is taller than a tiny bump, but shorter than our max step_height:
			if step_y_diff > 0.05 and step_y_diff <= step_height:
				# Teleport the player exactly to the top of the voxel
				parent.global_position.y = down_hit.position.y + 0.01
