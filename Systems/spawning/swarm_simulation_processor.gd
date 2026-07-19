extends Node
class_name SwarmSimulationProcessor

@export_category("Spatial Tuning")
@export var separation_radius: float = 1.5
@export var separation_force: float = 6.0

@export_category("Liquid Horde Settings")
@export var cohesion_weight: float = 0.5
@export_category("Density Allocation")
@export var density_threshold: int = 3
@export_category("Momentum Bonus")
@export var momentum_charge_bonus: float = 0.03

@export_category("Staging Ring Settings")
@export var staging_radius: float = 13.0
@export_category("Orbit Speed Factor")
@export var orbit_speed_factor: float = 1.0
@export var raycast_frame_stride: int = 12

@export_category("AAA Polish Settings")
@export var steering_inertia: float = 7.5
@export_category("Vertical Alignment")
@export var ground_offset: float = 1.0
@export var gravity_acceleration: float = 28.0

@export_category("PBD Rigid Thresholds")
@export var swarmer_body_radius: float = 0.70
@export_category("AAA Proximity Elasticity")
@export var escalation_trigger_distance: float = 7.0
@export_category("Proximity Multipliers")
@export var proximity_spread_multiplier: float = 1.65
@export_category("Collision Stiffness")
@export var collision_stiffness: float = 0.40

var ground_clamp_query: PhysicsRayQueryParameters3D
var bucket_headers: PackedInt32Array = PackedInt32Array()
var bucket_next: PackedInt32Array = PackedInt32Array()

const HASH_SIZE: int = 2048
const HASH_MASK: int = 2047

var promoted_mask: PackedByteArray = PackedByteArray()

func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false
	bucket_headers.resize(HASH_SIZE)

func process_swarm_physics(manager: Node, delta: float) -> void:
	if not manager or not manager.player:
		return

	var player_pos: Vector3 = manager.player.global_position
	var space_state: PhysicsDirectSpaceState3D = manager.get_world_3d().direct_space_state

	var core_pos := Vector3.ZERO
	var has_core: bool = false
	if manager.core_node:
		core_pos = manager.core_node.global_position
		has_core = true

	var accumulated_core_damage: float = 0.0
	var live_count: int = manager.highest_active_index
	if live_count == 0:
		return

	if bucket_next.size() != manager.pool_size:
		bucket_next.resize(manager.pool_size)
	if promoted_mask.size() != manager.pool_size:
		promoted_mask.resize(manager.pool_size)

	bucket_headers.fill(-1)
	bucket_next.fill(-1)
	promoted_mask.fill(0)

	var cell_size: float = 1.6
	var current_frame: int = Engine.get_process_frames()
	var time_sec: float = Time.get_ticks_msec() / 1000.0

	var m_positions: PackedVector3Array = manager.positions
	manager.positions = PackedVector3Array()
	var m_velocities: PackedVector3Array = manager.velocities
	manager.velocities = PackedVector3Array()
	var m_states: PackedByteArray = manager.states
	manager.states = PackedByteArray()
	var m_types: PackedInt32Array = manager.enemy_types
	manager.enemy_types = PackedInt32Array()
	var m_variances: PackedFloat32Array = manager.speed_variances
	manager.speed_variances = PackedFloat32Array()
	var m_aggro_cooldowns: PackedFloat32Array = manager.aggro_cooldowns
	manager.aggro_cooldowns = PackedFloat32Array()
	var m_hit_timers: PackedFloat32Array = manager.hit_timers
	manager.hit_timers = PackedFloat32Array()
	var m_damage: PackedFloat32Array = manager.damage_array
	manager.damage_array = PackedFloat32Array()
	var m_attack_cooldowns: PackedFloat32Array = manager.attack_cooldowns
	manager.attack_cooldowns = PackedFloat32Array()
	var m_strike_visual_timers: PackedFloat32Array = manager.strike_visual_timers
	manager.strike_visual_timers = PackedFloat32Array()
	var m_token_states: PackedByteArray = manager.token_states
	manager.token_states = PackedByteArray()
	var m_headings: PackedVector3Array = manager.headings
	manager.headings = PackedVector3Array()
	var m_floor_heights: PackedFloat32Array = manager.floor_heights
	manager.floor_heights = PackedFloat32Array()

	if "node_pool" in manager:
		for n in manager.node_pool:
			if n.get("is_active") and n.get("linked_idx") != -1:
				promoted_mask[n.linked_idx] = 1

	var mm_inv_xform := Transform3D()
	if manager.multimesh:
		mm_inv_xform = manager.multimesh.global_transform.affine_inverse()

	var global_orbit_sin: float = sin(time_sec * 2.0)
	var global_orbit_cos: float = cos(time_sec * 3.1)

	# PASS 1: Build Spatial Grid Index Map
	for i in range(live_count):
		if m_states[i] == 0: continue
		var cell_x: int = int(floor(m_positions[i].x / cell_size))
		var cell_z: int = int(floor(m_positions[i].z / cell_size))
		var hash_idx: int = abs((cell_x * 73856093) ^ (cell_z * 19349663)) & HASH_MASK
		bucket_next[i] = bucket_headers[hash_idx]
		bucket_headers[hash_idx] = i

	# PASS 2: Fluid Kinematics Processing Loop
	for i in range(live_count):
		if m_states[i] == 0: continue

		var hit_val: float = m_hit_timers[i]
		if hit_val > 0.0:
			hit_val = max(0.0, hit_val - delta * 15.0)
			m_hit_timers[i] = hit_val

		var strike_visual: float = m_strike_visual_timers[i]
		if strike_visual > 0.0:
			strike_visual = max(0.0, strike_visual - delta * 5.0)
			m_strike_visual_timers[i] = strike_visual
			if strike_visual == 0.0:
				manager.release_combat_token(m_token_states[i])
				m_token_states[i] = 0

		if m_aggro_cooldowns[i] > 0.0:
			m_aggro_cooldowns[i] -= delta
			if m_aggro_cooldowns[i] <= 0.0:
				m_types[i] = 0
				m_aggro_cooldowns[i] = 0.0
				if m_states[i] == 2:
					var active_node = manager._find_node_for_idx(i)
					if active_node and has_core:
						active_node.my_target = manager.core_node

		if m_attack_cooldowns[i] > 0.0:
			m_attack_cooldowns[i] -= delta

		if promoted_mask[i] == 1:
			var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))
			manager.multimesh.multimesh.set_instance_transform(i, local_zero)
			continue

		var current_pos: Vector3 = m_positions[i]
		var velocity_vec: Vector3 = m_velocities[i]

		velocity_vec.y -= gravity_acceleration * delta

		var type: int = m_types[i]
		var target_pos: Vector3 = player_pos
		if type == 0 and has_core:
			target_pos = core_pos

		var to_target := Vector3(target_pos.x - current_pos.x, 0.0, target_pos.z - current_pos.z)
		var dist_sq: float = to_target.length_squared()
		var distance := sqrt(dist_sq)

		var desired_heading := Vector3.ZERO
		var base_move_speed: float = manager.base_speed * m_variances[i]

		if distance > 0.1:
			var dir_to_target := to_target / distance
			var token_state: int = m_token_states[i]

			if distance <= 5.5 and m_attack_cooldowns[i] <= 0.0 and m_strike_visual_timers[i] <= 0.0 and token_state == 0:
				var granted_token: int = manager.request_combat_token(type, distance, i)
				if granted_token > 0:
					m_token_states[i] = granted_token
					token_state = granted_token

			if token_state > 0 or m_attack_cooldowns[i] > 0.0:
				if distance <= 2.2:
					if m_attack_cooldowns[i] <= 0.0 and m_strike_visual_timers[i] <= 0.0:
						m_attack_cooldowns[i] = 1.5
						strike_visual = 1.0
						m_strike_visual_timers[i] = 1.0

						if token_state == 1 and has_core:
							accumulated_core_damage += m_damage[i]
						elif token_state == 2:
							if manager.player.has_method("take_damage"):
								manager.player.take_damage(m_damage[i])
					else:
						var close_orbit := Vector3.UP.cross(dir_to_target).normalized()
						if i & 1 == 0: close_orbit = - close_orbit
						desired_heading = (-dir_to_target * 0.8 + close_orbit * 0.2) * base_move_speed
				else:
					desired_heading = dir_to_target * base_move_speed
			else:
				var dynamic_staging_radius: float = 6.5 if type == 0 else 5.0
				if distance <= dynamic_staging_radius:
					var orbit_dir: Vector3 = Vector3.UP.cross(dir_to_target).normalized()
					if i & 1 == 0: orbit_dir = - orbit_dir
					var shuffle_noise := Vector3(global_orbit_sin * 0.2, 0.0, global_orbit_cos * 0.2)
					var push_back_weight: float = (dynamic_staging_radius - distance) / dynamic_staging_radius
					var push_back_vec: Vector3 = - dir_to_target * (base_move_speed * push_back_weight * 1.6)
					desired_heading = (orbit_dir * base_move_speed * 0.8) + shuffle_noise + push_back_vec
				else:
					desired_heading = dir_to_target * base_move_speed

		# Spatial Neighbor Scans
		var cell_x: int = int(floor(m_positions[i].x / cell_size))
		var cell_z: int = int(floor(m_positions[i].z / cell_size))

		var push_vector := Vector3.ZERO
		var neighbor_center_mass := Vector3.ZERO
		var valid_neighbor_count: int = 0

		var separation_modifier: float = 1.0
		if distance < escalation_trigger_distance:
			var depth_factor: float = (escalation_trigger_distance - distance) / escalation_trigger_distance
			separation_modifier = 1.0 + (depth_factor * (proximity_spread_multiplier - 1.0))

		var active_sep_radius: float = separation_radius * separation_modifier
		var active_body_radius: float = swarmer_body_radius * separation_modifier
		var pairing_variance: float = 1.0 + (float(i & 15) * 0.01) - 0.08
		var active_sep_rad_sq: float = (active_sep_radius * active_sep_radius) * pairing_variance

		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var target_cell_x := cell_x + dx
				var target_cell_z := cell_z + dz
				var hash_idx: int = abs((target_cell_x * 73856093) ^ (target_cell_z * 19349663)) & HASH_MASK

				var neighbor_idx: int = bucket_headers[hash_idx]
				while neighbor_idx != -1:
					if neighbor_idx != i and m_states[neighbor_idx] != 0:
						var neighbor_pos: Vector3 = m_positions[neighbor_idx]
						var to_neighbor_flat := Vector3(current_pos.x - neighbor_pos.x, 0.0, current_pos.z - neighbor_pos.z)
						var neighbor_dist_sq: float = to_neighbor_flat.length_squared()

						neighbor_center_mass += neighbor_pos
						valid_neighbor_count += 1

						if neighbor_dist_sq < active_sep_rad_sq and neighbor_dist_sq > 0.001:
							var n_dist := sqrt(neighbor_dist_sq)
							var push_weight := (active_sep_radius - n_dist) / active_sep_radius
							push_vector += (to_neighbor_flat / n_dist) * push_weight * separation_force

							if n_dist < active_body_radius:
								var overlap: float = active_body_radius - n_dist
								var displacement: Vector3 = (to_neighbor_flat / n_dist) * overlap * collision_stiffness
								current_pos.x += displacement.x
								current_pos.z += displacement.z

					neighbor_idx = bucket_next[neighbor_idx]

		velocity_vec.x = lerp(velocity_vec.x, desired_heading.x + push_vector.x, steering_inertia * delta)
		velocity_vec.z = lerp(velocity_vec.z, desired_heading.z + push_vector.z, steering_inertia * delta)

		current_pos.x += velocity_vec.x * delta
		current_pos.z += velocity_vec.z * delta
		current_pos.y += velocity_vec.y * delta

		var dynamic_stride: int = raycast_frame_stride
		if distance > 22.0:
			dynamic_stride = raycast_frame_stride * 3
		elif distance > 14.5:
			dynamic_stride = raycast_frame_stride * 2

		if (i + current_frame) % dynamic_stride == 0:
			if manager.voxel_tool:
				m_floor_heights[i] = manager.get_voxel_ground_height(manager.voxel_tool, current_pos.x, current_pos.y, current_pos.z, ground_offset)
			else:
				ground_clamp_query.from = Vector3(current_pos.x, player_pos.y + 30.0, current_pos.z)
				ground_clamp_query.to = Vector3(current_pos.x, player_pos.y - 30.0, current_pos.z)
				var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
				if not clamp_result.is_empty():
					m_floor_heights[i] = clamp_result.position.y + ground_offset
				else:
					m_floor_heights[i] = current_pos.y

		if current_pos.y <= m_floor_heights[i]:
			current_pos.y = m_floor_heights[i]
			velocity_vec.y = 0.0

		m_positions[i] = current_pos
		m_velocities[i] = velocity_vec

		var raw_target_facing := m_headings[i]
		if distance > 0.1:
			if distance <= 4.0 or m_token_states[i] > 0 or m_attack_cooldowns[i] > 0.0:
				raw_target_facing = to_target.normalized()
			elif (velocity_vec.x * velocity_vec.x + velocity_vec.z * velocity_vec.z) > 0.01:
				raw_target_facing = Vector3(velocity_vec.x, 0.0, velocity_vec.z).normalized()

		var smoothed_facing: Vector3 = m_headings[i].lerp(raw_target_facing, 14.0 * delta).normalized()
		m_headings[i] = smoothed_facing

		var basis := Basis()
		if smoothed_facing.length_squared() > 0.01:
			var back_dir: Vector3 = - smoothed_facing
			var right: Vector3 = Vector3.UP.cross(back_dir).normalized()
			var up: Vector3 = back_dir.cross(right).normalized()
			basis = Basis(right, up, back_dir)

		var scale_val: float = manager.enemy_scale
		basis = basis.scaled(Vector3(scale_val, scale_val, scale_val))

		var world_xform := Transform3D(basis, current_pos)
		var local_xform: Transform3D = mm_inv_xform * world_xform
		manager.multimesh.multimesh.set_instance_transform(i, local_xform)
		manager.multimesh.multimesh.set_instance_custom_data(i, Color(hit_val, strike_visual, 0.0, 0.0))

	manager.positions = m_positions
	manager.velocities = m_velocities
	manager.states = m_states
	manager.enemy_types = m_types
	manager.speed_variances = m_variances
	manager.aggro_cooldowns = m_aggro_cooldowns
	manager.hit_timers = m_hit_timers
	manager.damage_array = m_damage
	manager.attack_cooldowns = m_attack_cooldowns
	manager.strike_visual_timers = m_strike_visual_timers
	manager.token_states = m_token_states
	manager.headings = m_headings
	manager.floor_heights = m_floor_heights
