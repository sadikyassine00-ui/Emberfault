extends Node3D
class_name ActiveEnemy

# =============================================================================
# 📦 CLASS STATE & REGISTERS
# =============================================================================
var is_active: bool = false
var linked_idx: int = -1
var my_target: Node3D
var horde_mgr: Node

# Custom velocity vector; Y-lane is decoupled to cache ground step heights
var velocity: Vector3 = Vector3.ZERO

# Reusable local Raycast query object to eliminate runtime heap allocation churn
var ground_clamp_query: PhysicsRayQueryParameters3D

var current_scale_factor: float = 1.0

@export_category("Combat Settings")
@export var attack_range: float = 2.2

@export_category("Swarm Traits")
@export var base_speed: float = 4.5
@export var speed_variance: float = 1.0
var preferred_dist_sq: float = 10.0
@export var orbital_speed: float = 1.2

@export_category("Vertical Alignment")
@export var ground_offset: float = 1.0

@export_category("AAA Elite Visual Spacing")
@export var elite_body_radius: float = 1.6
@export var collision_stiffness: float = 0.50

# =============================================================================
# ⚙️ LIFECYCLE PIPELINE
# =============================================================================
func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false

	set_physics_process(false)
	hide()

	var health_comp = get_node_or_null("HealthComponent")
	if health_comp:
		if health_comp.has_signal("entity_died"):
			health_comp.entity_died.connect(_on_health_depleted)
	else:
		push_error("⚠️ [ARCH OVERSIGHT] ActiveEnemy scene instance is missing its HealthComponent child node.")

func _on_health_depleted() -> void:
	if horde_mgr and linked_idx != -1:
		horde_mgr.kill_enemy(linked_idx)
		deactivate()

# =============================================================================
# 🟢 ACTIVATION / DEMOTION HANDOFF SYSTEM
# =============================================================================
func activate(pos: Vector3, idx: int, target: Node3D, spd_var: float, pref_dist: float, orb_spd: float, mgr: Node) -> void:
	global_position = pos
	linked_idx = idx
	my_target = target
	speed_variance = spd_var
	preferred_dist_sq = pref_dist
	orbital_speed = orb_spd
	horde_mgr = mgr
	velocity = Vector3.ZERO

	current_scale_factor = mgr.enemy_scale

	# --- ⚡ PERFECT FACING & SCALE HANDOFF ---
	var vel = mgr.velocities[idx]
	var flat_vel := Vector3(vel.x, 0.0, vel.z)
	if flat_vel.length_squared() > 0.05:
		var back_dir: Vector3 = - flat_vel.normalized()
		var right: Vector3 = Vector3.UP.cross(back_dir).normalized()
		var up: Vector3 = back_dir.cross(right).normalized()
		global_transform.basis = Basis(right, up, back_dir).scaled(Vector3(current_scale_factor, current_scale_factor, current_scale_factor))
	else:
		global_transform.basis = Basis().scaled(Vector3(current_scale_factor, current_scale_factor, current_scale_factor))

	var health_comp = get_node_or_null("HealthComponent")
	if health_comp:
		if "current_health" in health_comp:
			health_comp.current_health = mgr.health_array[idx]
		elif "health" in health_comp:
			health_comp.health = mgr.health_array[idx]

	velocity.y = pos.y

	is_active = true
	show()
	set_physics_process(true)

	if horde_mgr and not horde_mgr.active_execution_pool.has(self):
		horde_mgr.active_execution_pool.append(self)

func deactivate() -> void:
	if horde_mgr:
		horde_mgr.active_execution_pool.erase(self)

	is_active = false
	linked_idx = -1
	my_target = null
	horde_mgr = null
	velocity = Vector3.ZERO
	hide()
	set_physics_process(false)
	global_position = Vector3(0, -1000, 0)

# =============================================================================
# ⚔️ KINEMATIC SWARM PHYSICS LOOP
# =============================================================================
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

	# 1. Forward Steering
	var distance_error_sq: float = dist_sq - preferred_dist_sq
	var agitation: float = 1.0
	var forward_speed: float = 0.0

	if is_in_attack_range:
		forward_speed = 0.0
		if distance < 1.6:
			forward_speed = -3.5
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

	# 2. Strafe Steering
	var tangent: Vector3 = Vector3.UP.cross(dir_to_target).normalized()
	var orbit_intensity: float = clamp(10.0 / max(distance, 1.0), 0.5, 3.0)
	var strafe_vec: Vector3 = tangent * (orbital_speed * orbit_intensity * agitation)

	# 3. Noise Shambling
	var time_sec: float = Time.get_ticks_msec() / 1000.0
	var shambling_vec := Vector3(sin(time_sec * 2.5 + linked_idx) * 1.2, 0, cos(time_sec * 2.0 + linked_idx) * 1.2) * agitation

	var separation_vec := Vector3.ZERO
	var next_pos_modifier := Vector3.ZERO

	for other_enemy in horde_mgr.active_execution_pool:
		if other_enemy == self:
			continue

		var other_pos: Vector3 = other_enemy.global_position
		var push_dir := current_pos - other_pos
		push_dir.y = 0
		var push_dist: float = push_dir.length()

		var separation_threshold: float = elite_body_radius * 1.8
		if push_dist < separation_threshold and push_dist > 0.001:
			var push_dir_norm := push_dir / push_dist
			var weight: float = (separation_threshold - push_dist) / separation_threshold
			separation_vec += push_dir_norm * weight * 9.0 * agitation

			if push_dist < elite_body_radius:
				var overlap: float = elite_body_radius - push_dist
				next_pos_modifier += push_dir_norm * overlap * collision_stiffness

	var desired_velocity: Vector3 = forward_vec + strafe_vec + shambling_vec + separation_vec
	if desired_velocity.length_squared() < 0.05 and agitation < 0.1:
		desired_velocity = Vector3.ZERO

	velocity.x = lerp(velocity.x, desired_velocity.x, 6.0 * delta)
	velocity.z = lerp(velocity.z, desired_velocity.z, 6.0 * delta)

	var max_pbd_displacement: float = 0.25
	if next_pos_modifier.length_squared() > max_pbd_displacement * max_pbd_displacement:
		next_pos_modifier = next_pos_modifier.normalized() * max_pbd_displacement

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var next_pos: Vector3 = current_pos + (flat_velocity * delta) + next_pos_modifier

	# Step Glide Topographical Updates
	var active_offset: float = ground_offset

	if (linked_idx + Engine.get_process_frames()) % 8 == 0:
		if horde_mgr.voxel_tool:
			velocity.y = horde_mgr.get_voxel_ground_height(horde_mgr.voxel_tool, next_pos.x, next_pos.y, next_pos.z, active_offset)
		else:
			var space_state: PhysicsDirectSpaceState3D = horde_mgr.get_world_3d().direct_space_state
			ground_clamp_query.from = Vector3(next_pos.x, target_pos.y + 30.0, next_pos.z)
			ground_clamp_query.to = Vector3(next_pos.x, target_pos.y - 30.0, next_pos.z)

			var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
			if not clamp_result.is_empty():
				velocity.y = clamp_result.position.y + active_offset
			else:
				velocity.y = current_pos.y

	next_pos.y = move_toward(current_pos.y, velocity.y, 22.0 * delta)
	global_position = next_pos

	# ⚡ SAFE API UPGRADE: Bypasses copy-on-write property array modification traps!
	horde_mgr.set_enemy_pos_vel(linked_idx, global_position, velocity)

	# 4. Smooth Rotational Facing (With Scale Preservation)
	var look_dir := Vector3(velocity.x, 0, velocity.z)
	var scale_vec := Vector3(current_scale_factor, current_scale_factor, current_scale_factor)

	if is_in_attack_range and look_dir.length_squared() < 0.2:
		if dir_to_target.length_squared() > 0.001:
			var target_transform: Transform3D = global_transform.looking_at(global_position + dir_to_target, Vector3.UP)
			var current_rot_basis := global_transform.basis.orthonormalized()
			var target_rot_basis := target_transform.basis.orthonormalized()

			var slerped_basis := current_rot_basis.slerp(target_rot_basis, 12.0 * delta)
			global_transform.basis = slerped_basis.scaled(scale_vec)

	elif look_dir.length_squared() > 0.1:
		var target_transform: Transform3D = global_transform.looking_at(global_position + look_dir, Vector3.UP)
		var current_rot_basis := global_transform.basis.orthonormalized()
		var target_rot_basis := target_transform.basis.orthonormalized()

		var slerped_basis := current_rot_basis.slerp(target_rot_basis, 8.0 * delta)
		global_transform.basis = slerped_basis.scaled(scale_vec)
