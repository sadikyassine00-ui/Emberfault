extends Node
class_name SwarmSimulationProcessor

@export_category("Core Bindings")
@export var manager: HordeManager

@export_category("Spatial Tuning")
@export var separation_radius: float = 1.5
@export var separation_force: float = 6.0

@export_category("Liquid Horde Settings (Days Gone Style)")
@export var cohesion_weight: float = 0.5
@export var density_threshold: int = 3
@export var momentum_charge_bonus: float = 0.03

@export_category("Staging Ring Settings")
@export var staging_radius: float = 13.0
@export var orbit_speed_factor: float = 1.0
## AAA Time-Slicing Window: 12 frames means only ~8 entities raycast per frame!
@export var raycast_frame_stride: int = 12

@export_category("Core Assault Tuning")
@export var max_core_attackers: int = 5

@export_category("AAA Polish Settings")
@export var steering_inertia: float = 7.5
@export var crowd_belt_thickness: float = 5.0

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

var promoted_mask: PackedByteArray = PackedByteArray()

# Telemetry metrics
var peak_frame_time_usec: float = 0.0

func _ready() -> void:
	ground_clamp_query = PhysicsRayQueryParameters3D.new()
	ground_clamp_query.collision_mask = 1 # Lock exclusively to Layer 1 World Geometry
	ground_clamp_query.collide_with_bodies = true
	ground_clamp_query.collide_with_areas = false
	bucket_headers.resize(HASH_SIZE)

	if manager:
		promoted_mask.resize(manager.pool_size)
	else:
		promoted_mask.resize(1000)

func process_swarm_physics(_incoming_manager: HordeManager, delta: float) -> void:
	if not manager or not manager.player or not manager.base_core:
		return

	var loop_start_usec: float = Time.get_ticks_usec()
	var player_pos: Vector3 = manager.player.global_position
	var core_pos: Vector3 = manager.base_core.global_position
	var space_state: PhysicsDirectSpaceState3D = manager.get_world_3d().direct_space_state

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

	if "node_pool" in manager:
		for n in manager.node_pool:
			if n.get("is_active") and n.get("linked_idx") != -1:
				promoted_mask[n.linked_idx] = 1

	var current_core_attackers: int = 0

	# PASS 1: Build Spatial Grid Index Map
	for i in range(live_count):
		if manager.states[i] == 0: continue
		var cell_x: int = int(floor(manager.positions[i].x / cell_size))
		var cell_z: int = int(floor(manager.positions[i].z / cell_size))
		var hash_idx: int = abs((cell_x * 73856093) ^ (cell_z * 19349663)) % HASH_SIZE
		bucket_next[i] = bucket_headers[hash_idx]
		bucket_headers[hash_idx] = i

	# PASS 2: Fluid Kinematics Processing Loop
	for i in range(live_count):
		if manager.states[i] == 0: continue

		if promoted_mask[i] == 1:
			manager.multimesh.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
			continue

		var current_pos: Vector3 = manager.positions[i]
		var target_height_cache: float = manager.velocities[i].y # Repurposing velocity.y as height cache
		var velocity_vec: Vector3 = manager.velocities[i]
		velocity_vec.y = 0.0 # Strip height cache away from horizontal velocity vector math

		var type: int = manager.enemy_types[i]

		# --- 🛡️ INITIALIZATION GUARD LAYER ---
		# Prevents newly spawned/demoted entities from diving to 0.0 before their raycast frame hits
		if target_height_cache == 0.0:
			var initial_offset: float = ground_offset if type != 2 else (ground_offset * 2.0)
			target_height_cache = current_pos.y + initial_offset
		# -------------------------------------

		var is_hunter: bool = manager.intents[i] == 0
		var target_pos: Vector3 = player_pos if is_hunter else core_pos

		var to_target := Vector3(target_pos.x - current_pos.x, 0.0, target_pos.z - current_pos.z)
		var dist_sq: float = to_target.length_squared()
		var distance := sqrt(dist_sq)

		var desired_heading := Vector3.ZERO
		var base_move_speed: float = manager.base_speed * manager.speed_variances[i]
		if type == 2:
			base_move_speed *= 0.45

		var slow_noise_x: float = sin(time_sec * 0.8 + i * 2.3) * 0.25
		var slow_noise_z: float = cos(time_sec * 0.6 + i * 3.1) * 0.25
		var wander_vec := Vector3(slow_noise_x, 0, slow_noise_z)

		if distance > 0.1:
			var dir_to_target := to_target / distance

			if is_hunter and distance <= staging_radius:
				var orbit_dir := Vector3.UP.cross(dir_to_target).normalized()
				if i % 2 == 0: orbit_dir = - orbit_dir
				var shuffle_noise := Vector3(sin(time_sec * 2.0 + i), 0.0, cos(time_sec * 3.1 + i)).normalized() * 0.4
				var push_out_weight: float = (staging_radius - distance) / staging_radius
				var push_out_vec := -dir_to_target * (base_move_speed * push_out_weight * 1.5)

				desired_heading = (orbit_dir * base_move_speed * orbit_speed_factor) + (shuffle_noise * base_move_speed) + push_out_vec
			else:
				var unique_hash: float = sin(float(i) * 12.9898) * 43758.5453
				var deterministic_noise: float = abs(unique_hash - floor(unique_hash))

				var strike_range: float = 2.0 if type != 2 else 3.5
				var personal_wait_perimeter: float = 4.5 + (deterministic_noise * crowd_belt_thickness)

				if not is_hunter and distance <= personal_wait_perimeter:
					if distance <= strike_range + 1.0 and current_core_attackers < max_core_attackers:
						current_core_attackers += 1
						desired_heading = (wander_vec * base_move_speed * 0.5) + (dir_to_target * base_move_speed * 0.2)

						if current_frame % 60 == 0 and manager.has_method("apply_core_damage"):
							manager.apply_core_damage(0.5 * manager.speed_variances[i])
					else:
						var depth: float = personal_wait_perimeter - distance
						var push_back_factor: float = clamp(depth / 3.0, 0.0, 2.0)

						var orbit_dir := Vector3.UP.cross(dir_to_target).normalized()
						if i % 2 == 0: orbit_dir = - orbit_dir

						var fallback_orbit: Vector3 = orbit_dir * base_move_speed * 0.6
						var gradient_repulsion: Vector3 = - dir_to_target * base_move_speed * push_back_factor * 0.8

						desired_heading = fallback_orbit + gradient_repulsion + (wander_vec * base_move_speed * 0.3)
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
				var hash_idx: int = abs((target_cell_x * 73856093) ^ (target_cell_z * 19349663)) % HASH_SIZE

				var neighbor_idx: int = bucket_headers[hash_idx]
				while neighbor_idx != -1:
					if neighbor_idx != i and manager.states[neighbor_idx] != 0:
						var neighbor_pos: Vector3 = manager.positions[neighbor_idx]
						var to_neighbor_flat := Vector3(current_pos.x - neighbor_pos.x, 0.0, current_pos.z - neighbor_pos.z)
						var neighbor_dist_sq: float = to_neighbor_flat.length_squared()
						var neighbor_type: int = manager.enemy_types[neighbor_idx]

						total_density_count += 1
						neighbor_center_mass += neighbor_pos
						valid_neighbor_count += 1

						var active_sep_radius: float = separation_radius * separation_modifier
						var active_body_radius: float = swarmer_body_radius * separation_modifier

						if type == 2 or neighbor_type == 2:
							active_sep_radius *= 2.2
							active_body_radius *= 1.8

						var pairing_variance: float = 1.0 + (sin(float(i ^ neighbor_idx) * 57.2) * 0.10)
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

		# --- 🌊 SUBSYSTEM 3: AMORTIZED STEP-GLIDER INTERPOLATION ENGINE ---
		var active_offset: float = ground_offset if type != 2 else (ground_offset * 2.0)

		# Time-Sliced Raycast Gate: Only updates height targets for a microscopic pool fraction per frame
		if (i + current_frame) % raycast_frame_stride == 0:
			# Cast explicitly relative to the swarmer's current horizontal position coordinates
			ground_clamp_query.from = Vector3(current_pos.x, current_pos.y + 12.0, current_pos.z)
			ground_clamp_query.to = Vector3(current_pos.x, current_pos.y - 12.0, current_pos.z)

			var clamp_result: Dictionary = space_state.intersect_ray(ground_clamp_query)
			if not clamp_result.is_empty():
				target_height_cache = clamp_result.position.y + active_offset
			else:
				target_height_cache = target_pos.y + active_offset

		# EVERY SINGLE FRAME: Smoothly glide up or down toward the cached height step target
		current_pos.y = move_toward(current_pos.y, target_height_cache, 18.0 * delta)

		# Write-back synchronization
		manager.positions[i] = current_pos

		# Pack the horizontal movement vectors AND the target height cache back into database memory lanes
		velocity_vec.y = target_height_cache
		manager.velocities[i] = velocity_vec

		# GPU Transformation Builder
		var basis := Basis()
		var flat_vel := Vector3(velocity_vec.x, 0.0, velocity_vec.z)
		if flat_vel.length_squared() > 0.05:
			var forward: Vector3 = flat_vel.normalized()
			var right: Vector3 = Vector3.UP.cross(forward).normalized()
			var up: Vector3 = forward.cross(right).normalized()
			basis = Basis(right, up, forward)

		if type == 2:
			basis = basis.scaled(Vector3(2.2, 2.2, 2.2))

		manager.multimesh.multimesh.set_instance_transform(i, Transform3D(basis, current_pos))

	manager.multimesh.multimesh.visible_instance_count = manager.highest_active_index

	var total_duration_usec: float = Time.get_ticks_usec() - loop_start_usec
	peak_frame_time_usec = max(peak_frame_time_usec, total_duration_usec)

	if current_frame % 60 == 0:
		print("⚡ [STEP GLIDER ACTIVE] Entities: %d | Frame Loop: %.3f ms | HISTORICAL PEAK: %.3f ms" % [manager.alive_count, total_duration_usec / 1000.0, peak_frame_time_usec / 1000.0])
