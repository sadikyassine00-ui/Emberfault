extends Node3D
class_name ActiveEnemy

var is_active: bool = false
var linked_idx: int = -1
var my_target: Node3D

# Fixed: Explicitly type the manager to unlock method return types for the compiler
var horde_mgr: HordeManager = null

var velocity: Vector3 = Vector3.ZERO
var ground_clamp_query: PhysicsRayQueryParameters3D
var current_scale_factor: float = 1.0
var mesh_instance: MeshInstance3D = null
var local_hit_flash: float = 0.0

# AAA Architectural Cache
var health_component: Node = null

@export_category("Combat Settings")
@export var attack_range: float = 2.2
@export var attack_cooldown_duration: float = 1.5

@export_category("Swarm Traits")
@export var base_speed: float = 4.5
@export var speed_variance: float = 1.0
var preferred_dist_sq: float = 10.0
@export var orbital_speed: float = 1.2

@export_category("Vertical Alignment")
@export var ground_offset: float = 1.0
@export_category("Vertical Alignment")
@export var gravity_acceleration: float = 28.0

@export_category("AAA Elite Visual Spacing")
@export var elite_body_radius: float = 1.6
@export var collision_stiffness: float = 0.50

func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false

	set_physics_process(false)
	hide()

	for child in get_children():
		if child is MeshInstance3D:
			mesh_instance = child
			mesh_instance.set_instance_shader_parameter("is_foreground", 1.0)
			break

	health_component = get_node_or_null("HealthComponent")
	if health_component and health_component.has_signal("entity_died"):
		health_component.entity_died.connect(_on_health_depleted)

func _on_health_depleted() -> void:
	if horde_mgr and linked_idx != -1:
		horde_mgr.kill_enemy(linked_idx)
		deactivate()

func activate(pos: Vector3, idx: int, target: Node3D, spd_var: float, pref_dist: float, orb_spd: float, mgr: HordeManager) -> void:
	global_position = pos
	linked_idx = idx
	my_target = target
	speed_variance = spd_var
	preferred_dist_sq = pref_dist
	orbital_speed = orb_spd
	horde_mgr = mgr

	# O(1) Central Index Map Registration
	mgr.index_to_node_map[idx] = self

	# Inherit initial metrics directly via data arrays
	velocity = mgr.velocities[idx]
	local_hit_flash = mgr.hit_timers[idx]
	current_scale_factor = mgr.enemy_scale

	# Explicit type declarations clear inference pipeline warnings
	var flat_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length_squared() > 0.05:
		var back_dir: Vector3 = - flat_vel.normalized()
		var right: Vector3 = Vector3.UP.cross(back_dir).normalized()
		var up: Vector3 = back_dir.cross(right).normalized()
		global_transform.basis = Basis(right, up, back_dir).scaled(Vector3(current_scale_factor, current_scale_factor, current_scale_factor))
	else:
		global_transform.basis = Basis().scaled(Vector3(current_scale_factor, current_scale_factor, current_scale_factor))

	if mesh_instance:
		mesh_instance.set_instance_shader_parameter("hit_flash_intensity", 0.0)
		mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", mgr.strike_visual_timers[idx])

	# Access the pre-cached reference pointer directly
	if health_component:
		if "current_health" in health_component:
			health_component.current_health = mgr.health_array[idx]
		elif "health" in health_component:
			health_component.health = mgr.health_array[idx]

	is_active = true
	show()

	if horde_mgr and not horde_mgr.active_execution_pool.has(self):
		horde_mgr.active_execution_pool.append(self)


func deactivate() -> void:
	if horde_mgr and linked_idx != -1:
		# Write current state markers back to the database fields
		horde_mgr.hit_timers[linked_idx] = local_hit_flash

		if horde_mgr.strike_visual_timers[linked_idx] > 0.0:
			horde_mgr.release_combat_token(horde_mgr.token_states[linked_idx])

		horde_mgr.token_states[linked_idx] = 0
		horde_mgr.strike_visual_timers[linked_idx] = 0.0

		# Clear the O(1) manager reference BEFORE resetting identifiers
		horde_mgr.index_to_node_map[linked_idx] = null

	if horde_mgr:
		horde_mgr.active_execution_pool.erase(self)

	# Clean state resets to completely neutralize the object profile
	is_active = false
	linked_idx = -1
	my_target = null
	horde_mgr = null
	velocity = Vector3.ZERO
	hide()
	global_position = Vector3(0.0, -1000.0, 0.0)

func trigger_hit_flash() -> void:
	if local_hit_flash > 0.0:
		return
	local_hit_flash = 1.0
	if mesh_instance:
		mesh_instance.set_instance_shader_parameter("hit_flash_intensity", 1.0)

func managed_tick(managed_delta: float) -> void:
	if not is_active or not my_target or not horde_mgr or linked_idx == -1:
		return

	if local_hit_flash > 0.0:
		local_hit_flash = max(0.0, local_hit_flash - managed_delta * 15.0)
		horde_mgr.hit_timers[linked_idx] = local_hit_flash
		if mesh_instance:
			mesh_instance.set_instance_shader_parameter("hit_flash_intensity", local_hit_flash)

	var visual_lunge: float = horde_mgr.strike_visual_timers[linked_idx]
	if visual_lunge > 0.0:
		visual_lunge = max(0.0, visual_lunge - managed_delta * 5.0)
		horde_mgr.strike_visual_timers[linked_idx] = visual_lunge

		if visual_lunge == 0.0:
			horde_mgr.release_combat_token(horde_mgr.token_states[linked_idx])
			horde_mgr.token_states[linked_idx] = 0

		if mesh_instance:
			mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", visual_lunge)

	if horde_mgr.attack_cooldowns[linked_idx] > 0.0:
		horde_mgr.attack_cooldowns[linked_idx] -= managed_delta

	var current_pos := global_position
	var target_pos := my_target.global_position
	var dist_sq := current_pos.distance_squared_to(target_pos)

	var dir_to_target := Vector3.ZERO
	if dist_sq > 0.001:
		dir_to_target = (target_pos - current_pos).normalized()
		dir_to_target.y = 0.0

	var distance := sqrt(dist_sq)
	var is_in_attack_range := (distance <= attack_range)
	var current_token_state: int = horde_mgr.token_states[linked_idx]

	if distance <= 5.5 and horde_mgr.attack_cooldowns[linked_idx] <= 0.0 and visual_lunge <= 0.0 and current_token_state == 0:
		var target_type_idx: int = 0 if my_target is BaseCore else 1
		# Fixed: Explicitly type token index to bypass Variant evaluation
		var granted_token: int = horde_mgr.request_combat_token(target_type_idx, distance, linked_idx)
		if granted_token > 0:
			horde_mgr.token_states[linked_idx] = granted_token
			current_token_state = granted_token

	if current_token_state > 0 and is_in_attack_range and horde_mgr.attack_cooldowns[linked_idx] <= 0.0 and visual_lunge <= 0.0:
		horde_mgr.attack_cooldowns[linked_idx] = attack_cooldown_duration
		visual_lunge = 1.0
		horde_mgr.strike_visual_timers[linked_idx] = 1.0

		if mesh_instance:
			mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", 1.0)

		if my_target.has_method("take_damage"):
			my_target.take_damage(horde_mgr.damage_array[linked_idx])
		elif my_target.has_method("apply_damage"):
			my_target.apply_damage(horde_mgr.damage_array[linked_idx])

	velocity.y -= gravity_acceleration * managed_delta

	var forward_speed := 0.0
	if distance <= attack_range:
		if horde_mgr.attack_cooldowns[linked_idx] > 0.0:
			forward_speed = base_speed * speed_variance * 0.4
		else:
			forward_speed = 0.0

		if distance < 1.2:
			forward_speed = -3.5
	else:
		forward_speed = base_speed * speed_variance

	var forward_vec := dir_to_target * forward_speed
	var tangent := Vector3.UP.cross(dir_to_target).normalized()

	# Fixed: Explicitly typed structural variables to clear calculation pipeline errors
	var orbit_intensity: float = clamp(10.0 / max(distance, 1.0), 0.5, 3.0)
	var strafe_vec: Vector3 = tangent * (orbital_speed * orbit_intensity)

	var time_sec := Time.get_ticks_msec() / 1000.0
	var shambling_vec := Vector3(sin(time_sec * 2.5 + linked_idx) * 1.2, 0.0, cos(time_sec * 2.0 + linked_idx) * 1.2)

	var separation_vec := Vector3.ZERO
	var next_pos_modifier := Vector3.ZERO

	for other_enemy: ActiveEnemy in horde_mgr.active_execution_pool:
		if other_enemy == self: continue

		# Fixed: Strict typed vectors inside the high-density separation loop
		var other_pos: Vector3 = other_enemy.global_position
		var push_dir: Vector3 = current_pos - other_pos
		push_dir.y = 0.0
		var push_dist: float = push_dir.length()

		var separation_threshold := elite_body_radius * 1.8
		if push_dist < separation_threshold and push_dist > 0.001:
			var push_dir_norm: Vector3 = push_dir / push_dist
			var weight: float = (separation_threshold - push_dist) / separation_threshold
			separation_vec += push_dir_norm * weight * 9.0

			if push_dist < elite_body_radius:
				var overlap: float = elite_body_radius - push_dist
				next_pos_modifier += push_dir_norm * overlap * collision_stiffness

	# Fixed: Explicit type layout ensures fast processing for the movement engine
	var desired_velocity: Vector3 = forward_vec + strafe_vec + shambling_vec + separation_vec
	velocity.x = lerp(velocity.x, desired_velocity.x, 6.0 * managed_delta)
	velocity.z = lerp(velocity.z, desired_velocity.z, 6.0 * managed_delta)

	var max_pbd_displacement := 0.25
	if next_pos_modifier.length_squared() > max_pbd_displacement * max_pbd_displacement:
		next_pos_modifier = next_pos_modifier.normalized() * max_pbd_displacement

	current_pos.x += velocity.x * managed_delta
	current_pos.z += velocity.z * managed_delta
	current_pos.y += velocity.y * managed_delta

	var solid_floor_height := target_pos.y
	if horde_mgr.voxel_tool:
		solid_floor_height = horde_mgr.get_voxel_ground_height(horde_mgr.voxel_tool, current_pos.x, current_pos.y, current_pos.z, ground_offset)
	else:
		if (linked_idx + Engine.get_process_frames()) % 8 == 0:
			# Fixed: Bypasses dynamic variant lookup across the space state system
			var space_state: PhysicsDirectSpaceState3D = horde_mgr.get_world_3d().direct_space_state
			ground_clamp_query.from = Vector3(current_pos.x, target_pos.y + 30.0, current_pos.z)
			ground_clamp_query.to = Vector3(current_pos.x, target_pos.y - 30.0, current_pos.z)
			var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
			if not clamp_result.is_empty():
				solid_floor_height = clamp_result.position.y + ground_offset

	if current_pos.y <= solid_floor_height:
		current_pos.y = solid_floor_height
		velocity.y = 0.0

	global_position = current_pos
	horde_mgr.set_enemy_pos_vel(linked_idx, global_position, velocity)

	var scale_vec := Vector3(current_scale_factor, current_scale_factor, current_scale_factor)
	var look_dir := Vector3(velocity.x, 0.0, velocity.z)
	if distance <= 4.0 and dir_to_target.length_squared() > 0.001:
		look_dir = dir_to_target

	if look_dir.length_squared() > 0.01:
		var target_transform := global_transform.looking_at(global_position + look_dir, Vector3.UP)
		var current_rot_basis := global_transform.basis.orthonormalized()
		var target_rot_basis := target_transform.basis.orthonormalized()
		var slerped_basis := current_rot_basis.slerp(target_rot_basis, 14.0 * managed_delta)
		global_transform.basis = slerped_basis.scaled(scale_vec)
