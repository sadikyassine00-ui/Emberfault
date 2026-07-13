extends Node3D
class_name ActiveEnemy

var is_active: bool = false
var linked_idx: int = -1
var my_target: Node3D
var horde_mgr: HordeManager # Stored reference to the central data manager

# Custom velocity vector; Y-lane is decoupled to cache ground step heights
var velocity: Vector3 = Vector3.ZERO

# Reusable local Raycast query object to eliminate runtime heap allocation churn
var ground_clamp_query: PhysicsRayQueryParameters3D

@export_category("Combat Settings")
@export var attack_range: float = 2.2

@export_category("Swarm Traits")
@export var base_speed: float = 4.5
@export var speed_variance: float = 1.0
var preferred_dist_sq: float = 10.0
@export var orbital_speed: float = 1.2

@export_category("Vertical Alignment")
## The absolute foot buffer clearance anchor relative to the terrain mesh
@export var ground_offset: float = 1.0

@export_category("AAA Elite Visual Spacing")
## The minimum physical air gap footprint maintained between elite entities
@export var elite_body_radius: float = 1.6
## The stiffness constant of the PBD push displacement (0.0 to 1.0)
@export var collision_stiffness: float = 0.50

func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1 # Bound strictly to Layer 1 Terrain Geometry
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false

	set_physics_process(false)
	hide()

	# Connect death signals safely via defensive lookup gates
	var health_comp = get_node_or_null("HealthComponent")
	if health_comp:
		if health_comp.has_signal("entity_died"):
			health_comp.entity_died.connect(_on_health_depleted)
	else:
		push_error("⚠️ [ARCH OVERSIGHT] ActiveEnemy scene instance is missing its HealthComponent child node.")

func _on_health_depleted() -> void:
	if horde_mgr and linked_idx != -1:
		print("💀 [PROMOTED REAPER] Node wrapper '%s' confirmed dead. Reclaiming Index: %d" % [name, linked_idx])
		horde_mgr.kill_enemy(linked_idx)
		# AAA LIFECYCLE GUARD: Force immediate local thread shutdown to prevent zombie write-backs
		deactivate()

func activate(pos: Vector3, idx: int, target: Node3D, spd_var: float, pref_dist: float, orb_spd: float, mgr: HordeManager) -> void:
	global_position = pos
	linked_idx = idx
	my_target = target
	speed_variance = spd_var
	preferred_dist_sq = pref_dist
	orbital_speed = orb_spd
	horde_mgr = mgr
	velocity = Vector3.ZERO

	# --- AAA VISUAL POOL MATCH SCALE ---
	# Pre-scale the orientation basis based on archetype definition matrices before drawing
	var type: int = mgr.enemy_types[idx]
	var scale_size: float = 2.2 if type == 2 else 1.0
	global_transform.basis = Basis().scaled(Vector3(scale_size, scale_size, scale_size))

	# Sync health sub-components across data tables
	var health_comp = get_node_or_null("HealthComponent")
	if health_comp:
		if "current_health" in health_comp:
			health_comp.current_health = mgr.health_array[idx]
		elif "health" in health_comp:
			health_comp.health = mgr.health_array[idx]

	# Initialize localized vertical offsets to stop initial frame drops
	var active_offset: float = ground_offset if type != 2 else (ground_offset * 2.0)
	velocity.y = pos.y + active_offset

	is_active = true
	show()
	set_physics_process(true)

func deactivate() -> void:
	is_active = false
	linked_idx = -1
	my_target = null
	horde_mgr = null
	velocity = Vector3.ZERO
	hide()
	set_physics_process(false)
	global_position = Vector3(0, -1000, 0) # Cast completely out of render tree boundaries

func _physics_process(delta: float) -> void:
	if not is_active or not my_target or not horde_mgr:
		return

	var current_pos: Vector3 = global_position
	var target_pos: Vector3 = my_target.global_position
	var dist_sq: float = current_pos.distance_squared_to(target_pos)

	var dir_to_target := Vector3.ZERO
	if dist_sq > 0.001:
		dir_to_target = (target_pos - current_pos).normalized()
		dir_to_target.y = 0

	var distance := sqrt(dist_sq)
	var attack_range_sq: float = attack_range * attack_range
	var is_in_attack_range: bool = (dist_sq <= attack_range_sq)

	# 1. Forward Steering Vector Calculations
	var distance_error_sq: float = dist_sq - preferred_dist_sq
	var agitation: float = 1.0
	var forward_speed: float = 0.0

	if is_in_attack_range:
		forward_speed = 0.0
		if distance < 1.6:
			forward_speed = -3.5 # Micro-step backward to prevent mesh intersection loops
		agitation = 0.1
	else:
		if distance_error_sq > 2.0:
			forward_speed = base_speed * speed_variance
		elif distance_error_sq > -1.0:
			agitation = 0.05
		else:
			forward_speed = -1.5
			agitation = 0.2

	var forward_vec: Vector3 = dir_to_target * forward_speed

	# 2. Orbital Flanking Strafe Vectors
	var tangent: Vector3 = Vector3.UP.cross(dir_to_target).normalized()
	var orbit_intensity: float = clamp(10.0 / max(distance, 1.0), 0.5, 3.0)
	var strafe_vec: Vector3 = tangent * (orbital_speed * orbit_intensity * agitation)

	# 3. Shambling Noise Matrices
	var time_sec: float = Time.get_ticks_msec() / 1000.0
	var shambling_vec := Vector3(sin(time_sec * 2.5 + linked_idx) * 1.2, 0, cos(time_sec * 2.0 + linked_idx) * 1.2) * agitation

	# 4. O(N) Real-Time Elite Spacing & Collision Solver
	var separation_vec := Vector3.ZERO
	var next_pos_modifier := Vector3.ZERO

	if "node_pool" in horde_mgr:
		for other_enemy in horde_mgr.node_pool:
			if other_enemy == self or not other_enemy.is_active:
				continue

			var other_pos: Vector3 = other_enemy.global_position
			var push_dir := current_pos - other_pos
			push_dir.y = 0
			var push_dist: float = push_dir.length()

			var separation_threshold: float = elite_body_radius * 1.8
			if push_dist < separation_threshold and push_dist > 0.001:
				var push_dir_norm := push_dir / push_dist

				# Kinematic Steering Modification Layer
				var weight: float = (separation_threshold - push_dist) / separation_threshold
				separation_vec += push_dir_norm * weight * 9.0 * agitation

				# Position-Based Dynamics (PBD) Rigid Wall Constraints
				if push_dist < elite_body_radius:
					var overlap: float = elite_body_radius - push_dist
					next_pos_modifier += push_dir_norm * overlap * collision_stiffness

	# 5. Integrate Kinematic Vectors & Smooth Linear Blends
	var desired_velocity: Vector3 = forward_vec + strafe_vec + shambling_vec + separation_vec
	if desired_velocity.length_squared() < 0.05 and agitation < 0.1:
		desired_velocity = Vector3.ZERO

	velocity.x = lerp(velocity.x, desired_velocity.x, 6.0 * delta)
	velocity.z = lerp(velocity.z, desired_velocity.z, 6.0 * delta)

	# FIX: Isolate horizontal velocity translation vectors from absolute target height step cache
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var next_pos: Vector3 = current_pos + (flat_velocity * delta) + next_pos_modifier

	# --- 🔄 6. AMORTIZED ELITE STEP-GLIDER ENGINE ---
	var type: int = horde_mgr.enemy_types[linked_idx]
	var active_offset: float = ground_offset if type != 2 else (ground_offset * 2.0)

	var sim_proc = horde_mgr.simulation_processor
	if sim_proc and sim_proc.get("use_flat_plane_optimization") == true:
		velocity.y = horde_mgr.base_core.global_position.y + active_offset
	else:
		# Topographical Raycast Window: Time-sliced to run once every 8 frames per actor
		if (linked_idx + Engine.get_process_frames()) % 8 == 0:
			var space_state: PhysicsDirectSpaceState3D = horde_mgr.get_world_3d().direct_space_state
			ground_clamp_query.from = Vector3(next_pos.x, next_pos.y + 12.0, next_pos.z)
			ground_clamp_query.to = Vector3(next_pos.x, next_pos.y - 12.0, next_pos.z)

			var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
			if not clamp_result.is_empty():
				velocity.y = clamp_result.position.y + active_offset
			else:
				velocity.y = target_pos.y + active_offset

	# Continuous Step Interpolation Plane
	next_pos.y = move_toward(current_pos.y, velocity.y, 22.0 * delta)
	global_position = next_pos

	# Synchronize active calculations back to the global struct registers
	horde_mgr.positions[linked_idx] = global_position
	horde_mgr.velocities[linked_idx] = velocity

	# --- 7. 🌊 SMOOTH SCALE-AWARE ROTATIONAL FACING ENGINE ---
	var look_dir := Vector3(velocity.x, 0, velocity.z)
	var scale_size: float = 2.2 if type == 2 else 1.0

	if is_in_attack_range and look_dir.length_squared() < 0.2:
		if dir_to_target.length_squared() > 0.001:
			var target_transform: Transform3D = global_transform.looking_at(global_position + dir_to_target, Vector3.UP)

			# Extract pure unscaled orthonormal directional frames to pass quaternion checks safely
			var current_rot_basis := global_transform.basis.orthonormalized()
			var target_rot_basis := target_transform.basis.orthonormalized()

			var slerped_basis := current_rot_basis.slerp(target_rot_basis, 12.0 * delta)
			global_transform.basis = slerped_basis.scaled(Vector3(scale_size, scale_size, scale_size))

	elif look_dir.length_squared() > 0.1:
		var target_transform: Transform3D = global_transform.looking_at(global_position + look_dir, Vector3.UP)

		var current_rot_basis := global_transform.basis.orthonormalized()
		var target_rot_basis := target_transform.basis.orthonormalized()

		var slerped_basis := current_rot_basis.slerp(target_rot_basis, 8.0 * delta)
		global_transform.basis = slerped_basis.scaled(Vector3(scale_size, scale_size, scale_size))
