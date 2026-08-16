## ModularSwarmProcessor — AAA Liquid Horde Physics & Staging Rings (Hybrid-LOD Optimized)
extends Node
class_name ModularSwarmProcessor

@export_category("Spatial Tuning")
@export var separation_radius: float = 1.5
@export var separation_force: float = 14.0

@export_category("Liquid Horde Settings")
@export var cohesion_weight: float = 0.5

@export_category("Density Allocation")
@export var density_threshold: int = 3

@export_category("Momentum Bonus")
@export var momentum_charge_bonus: float = 0.03

@export_category("Staging Ring Settings")
@export var staging_radius: float = 4.0

@export_category("Orbit Speed Factor")
@export var orbit_speed_factor: float = 1.0
@export var raycast_frame_stride: int = 12

@export_category("AAA Polish Settings")
@export var steering_inertia: float = 7.5

@export_category("Vertical Alignment")
@export var ground_offset: float = 0.0
@export var auto_ground_offset: bool = true
@export var gravity_acceleration: float = 28.0

@export_category("PBD Rigid Thresholds")
@export var swarmer_body_radius: float = 0.70

@export_category("AAA Proximity Elasticity")
@export var escalation_trigger_distance: float = 7.0

@export_category("Proximity Multipliers")
@export var proximity_spread_multiplier: float = 1.65

@export_category("Collision Stiffness")
@export var collision_stiffness: float = 0.85

var ground_clamp_query: PhysicsRayQueryParameters3D
var bucket_headers: PackedInt32Array = PackedInt32Array()
var bucket_next: PackedInt32Array = PackedInt32Array()

const HASH_SIZE: int = 2048
const HASH_MASK: int = 2047

var promoted_mask: PackedByteArray = PackedByteArray()

# Sub-profiler accumulators
var _sp_samples: Array[Dictionary] = []
var _sp_frame: int = 0

func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false
	bucket_headers.resize(HASH_SIZE)

func process_swarm(manager: Node, delta: float) -> void:
	var player_node: Node3D = manager.player
	if not player_node:
		return

	var computed_ground_offset := ground_offset
	if auto_ground_offset and manager.multimesh and manager.multimesh.multimesh and manager.multimesh.multimesh.mesh:
		var aabb: AABB = manager.multimesh.multimesh.mesh.get_aabb()
		computed_ground_offset += -aabb.position.y * manager.enemy_scale

	if not has_meta("_debug_printed"):
		set_meta("_debug_printed", true)
		print("PROCESS_SWARM DEBUG:")
		print("  pool_size = ", manager.pool_size)
		if manager.multimesh and manager.multimesh.multimesh:
			print("  mm.instance_count = ", manager.multimesh.multimesh.instance_count)
			print("  mm.use_colors = ", manager.multimesh.multimesh.use_colors)
			print("  mm.use_custom_data = ", manager.multimesh.multimesh.use_custom_data)
		print("Swarm processor initialized multimesh parameters.")

	var player_pos: Vector3 = manager.player.global_position
	if ground_clamp_query.exclude.is_empty() and manager.player.has_method("get_rid"):
		ground_clamp_query.exclude = [manager.player.get_rid()]
	var space_state: PhysicsDirectSpaceState3D = manager.get_world_3d().direct_space_state

	var live_count: int = manager.highest_active_index
	if live_count == 0:
		return

	var mm: MultiMesh = manager.multimesh.multimesh if (manager.multimesh and manager.multimesh.multimesh) else null
	var stride: int = 12

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
	var m_velocities: PackedVector3Array = manager.velocities
	var m_states: PackedByteArray = manager.states
	var m_variances: PackedFloat32Array = manager.speed_variances
	var m_hit_timers: PackedFloat32Array = manager.hit_timers
	var m_type_ids: PackedInt32Array = manager.type_ids
	var m_damage: PackedFloat32Array = manager.damage_array
	var m_attack_cooldowns: PackedFloat32Array = manager.attack_cooldowns
	var m_strike_visual_timers: PackedFloat32Array = manager.strike_visual_timers
	var m_token_states: PackedByteArray = manager.token_states
	var m_headings: PackedVector3Array = manager.headings
	var m_floor_heights: PackedFloat32Array = manager.floor_heights
	var m_staging: PackedFloat32Array = manager.preferred_distances_sq

	var stagger_slices: int = 1
	if "stagger_slices" in manager:
		stagger_slices = max(1, manager.stagger_slices)
	var active_slice: int = current_frame % stagger_slices
	var sim_delta: float = delta * stagger_slices

	if "node_pool" in manager:
		for n in manager.node_pool:
			if n.get("is_active") and n.get("linked_idx") != -1:
				promoted_mask[n.linked_idx] = 1

	var mm_inv_xform := Transform3D()
	var use_local_xform: bool = false
	if manager.multimesh:
		mm_inv_xform = manager.multimesh.global_transform.affine_inverse()
		if mm_inv_xform != Transform3D():
			use_local_xform = true

	var global_orbit_sin: float = sin(time_sec * 2.0)
	var global_orbit_cos: float = cos(time_sec * 3.1)

	var inv_cell_size: float = 1.0 / cell_size
	var _t_hash_start: int = Time.get_ticks_usec()
	# PASS 1: Build Spatial Grid Index Map (We need this every frame because positions change every frame)
	for i in range(live_count):
		if m_states[i] == 0: continue
		var cell_x: int = int(floor(m_positions[i].x * inv_cell_size))
		var cell_z: int = int(floor(m_positions[i].z * inv_cell_size))
		var hash_idx: int = abs((cell_x * 73856093) ^ (cell_z * 19349663)) & HASH_MASK
		bucket_next[i] = bucket_headers[hash_idx]
		bucket_headers[hash_idx] = i
	var _t_hash_end: int = Time.get_ticks_usec()

	var use_colors: bool = false
	var use_custom_data: bool = false
	if mm:
		use_colors = mm.use_colors
		use_custom_data = mm.use_custom_data

	var enemy_scale_vec := Vector3(manager.enemy_scale, manager.enemy_scale, manager.enemy_scale)
	var enemy_scale_basis := Basis().scaled(enemy_scale_vec)  # Pre-built for distant LOD

	# Cache reflection lookups ONCE (has_method is extremely expensive per-call)
	var _has_release_token: bool = manager.has_method("release_token")
	var _has_release_combat_token: bool = manager.has_method("release_combat_token")
	var _has_request_token: bool = manager.has_method("request_token")
	var _has_request_combat_token: bool = manager.has_method("request_combat_token")
	var _has_take_damage: bool = manager.player.has_method("take_damage")

	var _raycast_count: int = 0
	var _t_loop_start: int = Time.get_ticks_usec()

	# PASS 2: Fluid Kinematics Processing Loop
	for i in range(live_count):
		if m_states[i] == 0: continue

		if m_positions[i].y < -25.0:
			manager.kill_enemy(i)
			continue

		var hit_val: float = m_hit_timers[i]
		if hit_val > 0.0:
			hit_val = max(0.0, hit_val - delta * 15.0)
			m_hit_timers[i] = hit_val

		var strike_visual: float = m_strike_visual_timers[i]
		if strike_visual > 0.0:
			strike_visual = max(0.0, strike_visual - delta * 5.0)
			m_strike_visual_timers[i] = strike_visual
			if strike_visual == 0.0:
				if _has_release_token:
					manager.release_token(m_token_states[i])
				elif _has_release_combat_token:
					manager.release_combat_token(m_token_states[i])
				m_token_states[i] = 0

		if m_attack_cooldowns[i] > 0.0:
			m_attack_cooldowns[i] -= delta

		if promoted_mask[i] == 1:
			continue

		var current_pos: Vector3 = m_positions[i]
		var velocity_vec: Vector3 = m_velocities[i]
		var to_target := Vector3(player_pos.x - current_pos.x, 0.0, player_pos.z - current_pos.z)
		var dist_sq: float = to_target.length_squared()
		var distance := sqrt(dist_sq)

		# ─── TIME SLICED HEAVY SIMULATION ───
		if (i % stagger_slices) == active_slice:
			var desired_heading := Vector3.ZERO
			var base_move_speed: float = manager.base_speed * m_variances[i]

			if distance > 0.1:
				var dir_to_target := to_target / distance
				var token_state: int = m_token_states[i]

				if distance <= 5.5 and m_attack_cooldowns[i] <= 0.0 and m_strike_visual_timers[i] <= 0.0 and token_state == 0:
					var granted_token: int = 0
					if _has_request_token:
						granted_token = manager.request_token(distance, i)
					elif _has_request_combat_token:
						granted_token = manager.request_combat_token(0, distance, i)

					if granted_token > 0:
						m_token_states[i] = granted_token
						token_state = granted_token

				if token_state > 0 or m_attack_cooldowns[i] > 0.0:
					var type_def: EnemyTypeDefinition = manager._get_type_def(m_type_ids[i])
					var atk_behavior: AttackBehavior = type_def.get_attack_behavior()
					var atk_cooldown: float = atk_behavior.attack_cooldown

					if distance <= atk_behavior.attack_range:
						if m_attack_cooldowns[i] <= 0.0 and m_strike_visual_timers[i] <= 0.0:
							m_attack_cooldowns[i] = atk_cooldown
							strike_visual = 1.0
							m_strike_visual_timers[i] = 1.0

							var dmg_behavior: DamageBehavior = type_def.get_damage_behavior()
							var dmg_info: DamageInfo = dmg_behavior.calculate(m_type_ids[i], -1, false)
							dmg_info.source_position = current_pos

							HordeCombatEvents.enemy_attacked.emit(i, false, manager.player, dmg_info)
							if _has_take_damage:
								manager.player.take_damage(dmg_info)
						else:
							var close_orbit := Vector3.UP.cross(dir_to_target).normalized()
							if i & 1 == 0: close_orbit = - close_orbit
							desired_heading = (-dir_to_target * 0.8 + close_orbit * 0.2) * base_move_speed
					else:
						desired_heading = dir_to_target * base_move_speed
				else:
					var dynamic_staging_radius: float = m_staging[i]
					# Instead of running straight, run towards a flanking tangent if blocked
					var push_back_weight: float = clamp((dynamic_staging_radius - distance) / dynamic_staging_radius, 0.0, 1.0)

					# Determine a consistent flanking direction per entity
					var flank_sign: float = 1.0 if (i % 2 == 0) else -1.0
					var orbit_dir: Vector3 = Vector3.UP.cross(dir_to_target).normalized() * flank_sign
					var hash_val: float = float((i * 2654435761) & 0xFFFF) / 65536.0
					var shuffle_x: float = (hash_val * 2.0 - 1.0) * 1.8
					var shuffle_z: float = ((hash_val * 1.5 + 0.3) - floorf(hash_val * 1.5 + 0.3)) * 3.6 - 1.8
					var shuffle_noise := Vector3(shuffle_x * global_orbit_sin, 0.0, shuffle_z * global_orbit_cos)

					if distance <= dynamic_staging_radius:
						# Hold the line at the staging ring
						var push_back_vec: Vector3 = -dir_to_target * (base_move_speed * push_back_weight * 2.0)
						desired_heading = (orbit_dir * base_move_speed * orbit_speed_factor * 1.5) + shuffle_noise + push_back_vec
					else:
						# Approach the player, but add sideways flow based on how close we are to our staging ring
						var approach_weight: float = clamp((distance - dynamic_staging_radius) / 10.0, 0.0, 1.0)
						var flank_weight: float = 1.0 - approach_weight
						# Fluidly blend from pure approach into orbiting as we hit the ring wall
						var flow_dir: Vector3 = (dir_to_target * approach_weight + orbit_dir * flank_weight * 1.2).normalized()
						desired_heading = flow_dir * base_move_speed + shuffle_noise

			# Spatial Neighbor Scans
			var cell_x: int = int(floor(current_pos.x * inv_cell_size))
			var cell_z: int = int(floor(current_pos.z * inv_cell_size))
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
								push_vector += (to_neighbor_flat / n_dist) * push_weight * separation_force * 1.5

								if n_dist < active_body_radius:
									var overlap: float = active_body_radius - n_dist
									var displacement: Vector3 = (to_neighbor_flat / n_dist) * overlap * collision_stiffness
									current_pos.x += displacement.x
									current_pos.z += displacement.z

						if valid_neighbor_count >= 12:
							break

						neighbor_idx = bucket_next[neighbor_idx]

					if valid_neighbor_count >= 12:
						break
				if valid_neighbor_count >= 12:
					break

			if valid_neighbor_count > density_threshold:
				velocity_vec.x += (neighbor_center_mass.x / valid_neighbor_count - current_pos.x) * cohesion_weight * sim_delta
				velocity_vec.z += (neighbor_center_mass.z / valid_neighbor_count - current_pos.z) * cohesion_weight * sim_delta
				velocity_vec.x += velocity_vec.x * momentum_charge_bonus * sim_delta
				velocity_vec.z += velocity_vec.z * momentum_charge_bonus * sim_delta

			var my_staging: float = m_staging[i]
			if valid_neighbor_count > 6:
				my_staging += 4.5 * sim_delta
			else:
				my_staging -= 2.0 * sim_delta
			my_staging = clamp(my_staging, staging_radius, staging_radius + 8.0)
			m_staging[i] = my_staging

			velocity_vec.x = lerp(velocity_vec.x, desired_heading.x + push_vector.x, steering_inertia * sim_delta)
			velocity_vec.z = lerp(velocity_vec.z, desired_heading.z + push_vector.z, steering_inertia * sim_delta)

		# ─── LIGHTWEIGHT EVERY-FRAME MOVEMENT ───
		velocity_vec.y -= gravity_acceleration * delta
		current_pos.x += velocity_vec.x * delta
		current_pos.z += velocity_vec.z * delta
		current_pos.y += velocity_vec.y * delta

		var dynamic_stride: int = raycast_frame_stride
		if distance > 22.0:
			dynamic_stride = raycast_frame_stride * 4
		elif distance > 14.5:
			dynamic_stride = raycast_frame_stride * 2

		if (i + current_frame) % dynamic_stride == 0:
			_raycast_count += 1
			ground_clamp_query.from = Vector3(current_pos.x, player_pos.y + 30.0, current_pos.z)
			ground_clamp_query.to = Vector3(current_pos.x, player_pos.y - 30.0, current_pos.z)
			var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
			if not clamp_result.is_empty():
				m_floor_heights[i] = clamp_result.position.y
			else:
				m_floor_heights[i] = current_pos.y

		if current_pos.y <= m_floor_heights[i]:
			current_pos.y = m_floor_heights[i]
			velocity_vec.y = 0.0

		m_positions[i] = current_pos
		m_velocities[i] = velocity_vec

		# ─── ROTATION LOD ───
		# Distant enemies: skip expensive heading lerp + Basis.looking_at (invisible at distance)
		if dist_sq > 400.0:  # > 20 units
			var render_pos_far: Vector3 = current_pos
			render_pos_far.y += computed_ground_offset
			var far_xform: Transform3D = Transform3D(enemy_scale_basis, render_pos_far)
			if mm:
				if use_local_xform:
					far_xform = mm_inv_xform * far_xform
				mm.set_instance_transform(i, far_xform)
				if hit_val > 0.0 or strike_visual > 0.0:
					if use_colors:
						mm.set_instance_color(i, Color(hit_val, strike_visual, 0.0, 1.0))
					if use_custom_data:
						mm.set_instance_custom_data(i, Color(hit_val, strike_visual, 0.0, 0.0))
			continue

		var raw_target_facing := m_headings[i]
		if distance > 0.1:
			raw_target_facing = to_target / distance

		var smoothed_facing: Vector3 = m_headings[i].lerp(raw_target_facing, 14.0 * delta).normalized()
		m_headings[i] = smoothed_facing

		var basis := Basis()
		if smoothed_facing.length_squared() > 0.01:
			basis = Basis.looking_at(smoothed_facing, Vector3.UP)

		basis = basis.scaled(enemy_scale_vec)

		# ─── BATCHED RENDER SERVER PUSH ───
		var render_pos: Vector3 = current_pos
		render_pos.y += computed_ground_offset
		var world_xform: Transform3D = Transform3D(basis, render_pos)

		if mm:
			var local_xform: Transform3D = world_xform
			if use_local_xform:
				local_xform = mm_inv_xform * world_xform

			mm.set_instance_transform(i, local_xform)

			if hit_val > 0.0 or strike_visual > 0.0:
				if use_colors:
					mm.set_instance_color(i, Color(hit_val, strike_visual, 0.0, 1.0))
				if use_custom_data:
					mm.set_instance_custom_data(i, Color(hit_val, strike_visual, 0.0, 0.0))

	var _t_loop_end: int = Time.get_ticks_usec()

	# Write back value types to manager
	manager.positions = m_positions
	manager.velocities = m_velocities
	manager.hit_timers = m_hit_timers
	manager.strike_visual_timers = m_strike_visual_timers
	manager.attack_cooldowns = m_attack_cooldowns
	manager.token_states = m_token_states
	manager.headings = m_headings
	manager.floor_heights = m_floor_heights
	manager.preferred_distances_sq = m_staging

	# Sub-profiler report
	_sp_samples.append({
		"hash": _t_hash_end - _t_hash_start,
		"loop": _t_loop_end - _t_loop_start,
		"raycasts": _raycast_count,
	})
	_sp_frame += 1
	if _sp_frame % 120 == 0:
		var n: int = _sp_samples.size()
		var sum_h: int = 0; var sum_l: int = 0; var sum_r: int = 0
		var max_h: int = 0; var max_l: int = 0; var max_r: int = 0
		for s in _sp_samples:
			sum_h += s.hash; sum_l += s.loop; sum_r += s.raycasts
			max_h = max(max_h, s.hash); max_l = max(max_l, s.loop)
			max_r = max(max_r, s.raycasts)
		# Suppress profiling spam
		# print("  [SWARM SUB] hash_rebuild: avg=%.0fus max=%dus | main_loop: avg=%.0fus max=%dus | raycasts/frame: avg=%.1f max=%d" % [
		# 	float(sum_h)/n, max_h, float(sum_l)/n, max_l, float(sum_r)/n, max_r])
		_sp_samples.clear()

# ═══════════════════════════════════════════
#  Public Queries
# ═══════════════════════════════════════════

## Alias for query_radius, providing an easier name for combat scripts.
func get_enemies_in_radius(center: Vector3, radius: float, manager: Node) -> PackedInt64Array:
	return query_radius(center, radius, manager)

## Performs a spatial hash query over the swarm and returns a packed array
## of 64-bit identifiers (generation << 32 | index) for all alive entities within `radius`.
func query_radius(center: Vector3, radius: float, manager: Node) -> PackedInt64Array:
	var hits := PackedInt64Array()
	if not manager or bucket_headers.size() == 0:
		return hits

	var cell_size: float = 1.6 # Matches the spatial hash cell size above
	var min_x: int = int(floor((center.x - radius) / cell_size))
	var max_x: int = int(floor((center.x + radius) / cell_size))
	var min_z: int = int(floor((center.z - radius) / cell_size))
	var max_z: int = int(floor((center.z + radius) / cell_size))

	var r_sq: float = radius * radius
	var m_pos = manager.positions
	var m_states = manager.states
	var m_gen = manager.generations

	for cx in range(min_x, max_x + 1):
		for cz in range(min_z, max_z + 1):
			var hash_idx: int = abs((cx * 73856093) ^ (cz * 19349663)) & HASH_MASK
			var head: int = bucket_headers[hash_idx]

			while head != -1:
				if m_states[head] != 0:
					var p = m_pos[head]
					var d_sq = (p.x - center.x)*(p.x - center.x) + (p.z - center.z)*(p.z - center.z)
					if d_sq <= r_sq:
						var packed_id: int = (m_gen[head] << 32) | (head & 0xFFFFFFFF)
						hits.append(packed_id)
				head = bucket_next[head]

	return hits
