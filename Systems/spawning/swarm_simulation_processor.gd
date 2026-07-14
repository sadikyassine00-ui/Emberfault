extends Node
class_name SwarmSimulationProcessor

@export_category("Spatial Tuning")
@export var separation_radius: float = 1.5
@export var separation_force: float = 6.0

@export_category("Liquid Horde Settings")
@export var cohesion_weight: float = 0.5
@export var density_threshold: int = 3
@export var momentum_charge_bonus: float = 0.03

@export_category("Staging Ring Settings")
@export var staging_radius: float = 13.0
@export var orbit_speed_factor: float = 1.0
@export var raycast_frame_stride: int = 12

@export_category("AAA Polish Settings")
@export var steering_inertia: float = 7.5
@export_category("Vertical Alignment")
@export var ground_offset: float = 1.0

@export_category("PBD Rigid Thresholds")
@export var swarmer_body_radius: float = 0.70
@export_category("AAA Proximity Elasticity")
@export var escalation_trigger_distance: float = 7.0
@export var proximity_spread_multiplier: float = 1.65
@export var collision_stiffness: float = 0.40

var ground_clamp_query: PhysicsRayQueryParameters3D
var bucket_headers: PackedInt32Array = PackedInt32Array()
var bucket_next: PackedInt32Array = PackedInt32Array()

const HASH_SIZE: int = 2048
const HASH_MASK: int = 2047

var promoted_mask: PackedByteArray = PackedByteArray()
var peak_frame_time_usec: float = 0.0

func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false
	bucket_headers.resize(HASH_SIZE)

func process_swarm_physics(manager: Node, delta: float) -> void:
	if not manager or not manager.player:
		return

	var loop_start_usec: float = Time.get_ticks_usec()
	var player_pos: Vector3 = manager.player.global_position
	var space_state: PhysicsDirectSpaceState3D = manager.get_world_3d().direct_space_state

	var core_pos := Vector3.ZERO
	var has_core: bool = false
	if manager.core_node:
		core_pos = manager.core_node.global_position
		has_core = true

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

	# Local references
	var m_positions: PackedVector3Array = manager.positions
	var m_velocities: PackedVector3Array = manager.velocities
	var m_states: PackedByteArray = manager.states
	var m_types: PackedInt32Array = manager.enemy_types
	var m_variances: PackedFloat32Array = manager.speed_variances
	var m_aggro_cooldowns: PackedFloat32Array = manager.aggro_cooldowns
	# ⚡ LOCAL REGISTER BINDING: Flat visual hit timer cache reference
	var m_hit_timers: PackedFloat32Array = manager.hit_timers

	if "node_pool" in manager:
		for n in manager.node_pool:
			if n.get("is_active") and n.get("linked_idx") != -1:
				promoted_mask[n.linked_idx] = 1

	var mm_inv_xform := Transform3D()
	if manager.multimesh:
		mm_inv_xform = manager.multimesh.global_transform.affine_inverse()

	var global_sin: float = sin(time_sec * 0.8)
	var global_cos: float = cos(time_sec * 0.6)
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

		# ⚡ DECAY VISUAL HIT TIMERS (Linear Interpolated Decay on CPU)
		var hit_val: float = m_hit_timers[i]
		if hit_val > 0.0:
			# Decays fully to zero over ~0.25 seconds (at 4.0 decay multiplier)
			hit_val = max(0.0, hit_val - delta * 4.0)
			m_hit_timers[i] = hit_val

		if m_aggro_cooldowns[i] > 0.0:
			m_aggro_cooldowns[i] -= delta
			if m_aggro_cooldowns[i] <= 0.0:
				m_types[i] = 0
				m_aggro_cooldowns[i] = 0.0
				if m_states[i] == 2:
					var active_node = manager._find_node_for_idx(i)
					if active_node and has_core:
						active_node.my_target = manager.core_node

		if promoted_mask[i] == 1:
			var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))
			manager.multimesh.multimesh.set_instance_transform(i, local_zero)
			continue

		var current_pos: Vector3 = m_positions[i]
		var target_height_cache: float = m_velocities[i].y
		var velocity_vec: Vector3 = m_velocities[i]
		velocity_vec.y = 0.0

		var type: int = m_types[i]

		if target_height_cache == 0.0:
			target_height_cache = current_pos.y + ground_offset

		# Target Selection
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

			if distance <= staging_radius:
				var orbit_dir := Vector3.UP.cross(dir_to_target).normalized()
				if i & 1 == 0: orbit_dir = - orbit_dir

				var shuffle_noise := Vector3(global_orbit_sin * (0.3 + 0.1 * (i & 1)), 0.0, global_orbit_cos * (0.3 + 0.1 * (i & 1)))
				var push_out_weight: float = (staging_radius - distance) / staging_radius
				var push_out_vec := -dir_to_target * (base_move_speed * push_out_weight * 1.5)

				desired_heading = (orbit_dir * base_move_speed * orbit_speed_factor) + (shuffle_noise * base_move_speed) + push_out_vec
			else:
				desired_heading = dir_to_target * base_move_speed

		# Spatial Neighbor Scans
		var cell_x: int = int(floor(current_pos.x / cell_size))
		var cell_z: int = int(floor(current_pos.z / cell_size))

		var push_vector := Vector3.ZERO
		var neighbor_center_mass := Vector3.ZERO
		var valid_neighbor_count: int = 0
		var total_density_count: int = 0

		var separation_modifier: float = 1.0
		if distance < escalation_trigger_distance:
			var depth_factor: float = (escalation_trigger_distance - distance) / escalation_trigger_distance
			separation_modifier = 1.0 + (depth_factor * (proximity_spread_multiplier - 1.0))

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

						total_density_count += 1
						neighbor_center_mass += neighbor_pos
						valid_neighbor_count += 1

						var active_sep_radius: float = separation_radius * separation_modifier
						var active_body_radius: float = swarmer_body_radius * separation_modifier

						var pairing_variance: float = 1.0 + (float((i ^ neighbor_idx) & 15) * 0.01) - 0.08
						var active_sep_rad_sq: float = (active_sep_radius * active_sep_radius) * pairing_variance

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

		var final_desired_velocity: Vector3 = desired_heading

		if valid_neighbor_count > 0:
			neighbor_center_mass /= valid_neighbor_count
			var cohesion_vector := Vector3(neighbor_center_mass.x - current_pos.x, 0.0, neighbor_center_mass.z - current_pos.z).normalized()
			final_desired_velocity += cohesion_vector * cohesion_weight

			if total_density_count >= density_threshold:
				final_desired_velocity *= (1.0 + (total_density_count * momentum_charge_bonus))

		final_desired_velocity += push_vector

		var max_speed_mod: float = 1.4
		if distance < escalation_trigger_distance:
			max_speed_mod = lerp(1.4, 0.85, (escalation_trigger_distance - distance) / escalation_trigger_distance)

		var current_max_speed: float = base_move_speed * max_speed_mod
		if final_desired_velocity.length_squared() > current_max_speed * current_max_speed:
			final_desired_velocity = final_desired_velocity.normalized() * current_max_speed

		velocity_vec.x = lerp(velocity_vec.x, final_desired_velocity.x, steering_inertia * delta)
		velocity_vec.z = lerp(velocity_vec.z, final_desired_velocity.z, steering_inertia * delta)

		current_pos.x += velocity_vec.x * delta
		current_pos.z += velocity_vec.z * delta

		# Step Glider
		var active_offset: float = ground_offset
		var dynamic_stride: int = raycast_frame_stride
		if distance > 22.0:
			dynamic_stride = raycast_frame_stride * 3
		elif distance > 14.5:
			dynamic_stride = raycast_frame_stride * 2

		if (i + current_frame) % dynamic_stride == 0:
			if manager.voxel_tool:
				target_height_cache = manager.get_voxel_ground_height(manager.voxel_tool, current_pos.x, current_pos.y, current_pos.z, active_offset)
			else:
				ground_clamp_query.from = Vector3(current_pos.x, player_pos.y + 30.0, current_pos.z)
				ground_clamp_query.to = Vector3(current_pos.x, player_pos.y - 30.0, current_pos.z)

				var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
				if not clamp_result.is_empty():
					target_height_cache = clamp_result.position.y + active_offset
				else:
					target_height_cache = current_pos.y

		current_pos.y = move_toward(current_pos.y, target_height_cache, 24.0 * delta)

		m_positions[i] = current_pos
		velocity_vec.y = target_height_cache
		m_velocities[i] = velocity_vec

		# GPU Transformation Builder
		var basis := Basis()
		var flat_vel := Vector3(velocity_vec.x, 0.0, velocity_vec.z)
		if flat_vel.length_squared() > 0.05:
			var back_dir: Vector3 = - flat_vel.normalized()
			var right: Vector3 = Vector3.UP.cross(back_dir).normalized()
			var up: Vector3 = back_dir.cross(right).normalized()
			basis = Basis(right, up, back_dir)

		var scale_val: float = manager.enemy_scale
		basis = basis.scaled(Vector3(scale_val, scale_val, scale_val))

		var world_xform := Transform3D(basis, current_pos)
		var local_xform: Transform3D = mm_inv_xform * world_xform
		manager.multimesh.multimesh.set_instance_transform(i, local_xform)

		# ⚡ WRITE TO CUSTOM DATA: Map the decaying hit timer straight to the GPU instance register
		manager.multimesh.multimesh.set_instance_custom_data(i, Color(hit_val, 0.0, 0.0, 0.0))

	# Commit memory back
	manager.positions = m_positions
	manager.velocities = m_velocities
	manager.aggro_cooldowns = m_aggro_cooldowns
	manager.hit_timers = m_hit_timers

	manager.multimesh.multimesh.visible_instance_count = manager.highest_active_index

	var total_duration_usec: float = Time.get_ticks_usec() - loop_start_usec
	peak_frame_time_usec = max(peak_frame_time_usec, total_duration_usec)

	if current_frame % 60 == 0:
		print("⚡ [STEP GLIDER OPTIMIZED] Entities: %d | Frame Loop: %.3f ms | HISTORICAL PEAK: %.3f ms" % [manager.alive_count, total_duration_usec / 1000.0, peak_frame_time_usec / 1000.0])
