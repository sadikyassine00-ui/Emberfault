extends Node
class_name HordePromotionProcessor

@export_category("Straggler Management")
@export var straggler_distance: float = 38.0
@export var wrap_spawn_radius: float = 22.0

@export_category("Core-Breaker Base Tuning")
@export var core_straggler_distance: float = 45.0
@export var core_wrap_spawn_radius: float = 26.0

# AAA Memory Architecture: Permanent pre-allocated registers
var promoted_indices: PackedInt32Array = PackedInt32Array()
var promoted_distances_sq: PackedFloat32Array = PackedFloat32Array()

var unpromoted_candidates: PackedInt32Array = PackedInt32Array()
var unpromoted_distances_sq: PackedFloat32Array = PackedFloat32Array()

func process_promotions(manager: HordeManager) -> void:
	var player_node: Node3D = manager.player
	if not player_node:
		return
		
	var player_pos: Vector3 = player_node.global_position
	var p_flat: Vector2 = Vector2(player_pos.x, player_pos.z)
	
	var core_node: Node3D = manager.core_node
	var core_pos: Vector3 = Vector3.ZERO
	var has_core: bool = false
	if core_node:
		core_pos = core_node.global_position
		has_core = true
	
	var promote_sq: float = manager.promote_dist * manager.promote_dist
	var demote_sq: float = manager.demote_dist * manager.demote_dist
	
	var straggler_sq: float = straggler_distance * straggler_distance
	var core_straggler_sq: float = core_straggler_distance * core_straggler_distance

	var player_vel: Vector3 = player_node.get("velocity") if "velocity" in player_node else Vector3.ZERO
	var heading_dir: Vector3 = Vector3.ZERO
	
	if player_vel.length_squared() > 0.1:
		heading_dir = player_vel.normalized()
	else:
		heading_dir = - player_node.global_transform.basis.z.normalized()
		
	var heading_flat: Vector2 = Vector2(heading_dir.x, heading_dir.z).normalized()

	var mm_inv_xform: Transform3D = Transform3D()
	if manager.multimesh:
		mm_inv_xform = manager.multimesh.global_transform.affine_inverse()

	# Sized Once: Grow capacity up to target index boundary to prevent mid-run resizing
	var current_pool_capacity: int = manager.highest_active_index
	if promoted_indices.size() < current_pool_capacity:
		promoted_indices.resize(current_pool_capacity)
		promoted_distances_sq.resize(current_pool_capacity)
		unpromoted_candidates.resize(current_pool_capacity)
		unpromoted_distances_sq.resize(current_pool_capacity)

	# Virtual Clear: Reset counting registers to reuse allocated memory blocks safely
	var promoted_count: int = 0
	var unpromoted_count: int = 0

	var promotions_this_frame: int = 0
	const MAX_PROMOTIONS_PER_FRAME: int = 2

	# PASS 1: Single-pass gather, coordinate sync, and targeted wrap projections
	for i in range(manager.highest_active_index):
		var state: int = manager.states[i]
		if state == 0:
			continue # Dead

		var current_pos: Vector3
		var dist_to_player_sq: float

		if state == 2:
			var n: ActiveEnemy = manager.index_to_node_map[i]
			if n:
				current_pos = n.global_position
				manager.set_enemy_pos_vel(i, current_pos, manager.velocities[i])
			else:
				manager.set_enemy_state(i, 1) # Fallback recovery
				state = 1
				current_pos = manager.positions[i]
		else:
			current_pos = manager.positions[i]

		dist_to_player_sq = current_pos.distance_squared_to(player_pos)
		
		var type: int = manager.enemy_types[i]

		if state == 1:
			if type == 1:
				if dist_to_player_sq > straggler_sq:
					var angle_offset: float = randf_range(-PI / 4.0, PI / 4.0)
					var spawn_dir_2d: Vector2 = heading_flat.rotated(angle_offset)
					var new_flat_pos: Vector2 = p_flat + (spawn_dir_2d * wrap_spawn_radius)
					current_pos = Vector3(new_flat_pos.x, player_pos.y, new_flat_pos.y)
					manager.set_enemy_pos_vel(i, current_pos, Vector3.ZERO)
					dist_to_player_sq = current_pos.distance_squared_to(player_pos)
			else:
				if has_core:
					var dist_to_core_sq: float = current_pos.distance_squared_to(core_pos)
					if dist_to_core_sq > core_straggler_sq:
						var random_angle: float = randf_range(-PI, PI)
						current_pos = core_pos + Vector3(cos(random_angle), 0.0, sin(random_angle)) * core_wrap_spawn_radius
						manager.set_enemy_pos_vel(i, current_pos, Vector3.ZERO)
						dist_to_player_sq = current_pos.distance_squared_to(player_pos)
				else:
					if dist_to_player_sq > straggler_sq:
						var angle_offset: float = randf_range(-PI / 4.0, PI / 4.0)
						var spawn_dir_2d: Vector2 = heading_flat.rotated(angle_offset)
						var new_flat_pos: Vector2 = p_flat + (spawn_dir_2d * wrap_spawn_radius)
						current_pos = Vector3(new_flat_pos.x, player_pos.y, new_flat_pos.y)
						manager.set_enemy_pos_vel(i, current_pos, Vector3.ZERO)
						dist_to_player_sq = current_pos.distance_squared_to(player_pos)

		if state == 2:
			promoted_indices[promoted_count] = i
			promoted_distances_sq[promoted_count] = dist_to_player_sq
			promoted_count += 1
		elif state == 1:
			if dist_to_player_sq < promote_sq:
				unpromoted_candidates[unpromoted_count] = i
				unpromoted_distances_sq[unpromoted_count] = dist_to_player_sq
				unpromoted_count += 1

	# PASS 2: Demote active wrappers that walked beyond demote_dist
	var write_idx: int = 0
	for idx in range(promoted_count):
		var p_i: int = promoted_indices[idx]
		var dist_sq: float = promoted_distances_sq[idx]
		
		if dist_sq > demote_sq:
			manager.set_enemy_state(p_i, 1)
			var n: ActiveEnemy = manager.index_to_node_map[p_i]
			if n:
				manager.set_enemy_pos_vel(p_i, n.global_position, manager.velocities[p_i])
				if manager.multimesh and manager.multimesh.multimesh:
					var local_tf: Transform3D = mm_inv_xform * Transform3D(n.global_transform.basis, n.global_position)
					manager.multimesh.multimesh.set_instance_transform(p_i, local_tf)
				n.deactivate()
		else:
			promoted_indices[write_idx] = p_i
			promoted_distances_sq[write_idx] = dist_sq
			write_idx += 1
			
	promoted_count = write_idx

	# PASS 3: Fill empty node wrappers (With Throttling)
	var free_node: ActiveEnemy = manager._get_free_node()
	while free_node and unpromoted_count > 0:
		if promotions_this_frame >= MAX_PROMOTIONS_PER_FRAME:
			break
			
		var min_idx: int = 0
		var min_val: float = unpromoted_distances_sq[0]
		for idx in range(1, unpromoted_count):
			if unpromoted_distances_sq[idx] < min_val:
				min_val = unpromoted_distances_sq[idx]
				min_idx = idx
				
		var target_i: int = unpromoted_candidates[min_idx]
		manager.set_enemy_state(target_i, 2)
		
		var target_node: Node3D = player_node
		if manager.enemy_types[target_i] == 0 and manager.core_node:
			target_node = manager.core_node

		free_node.activate(manager.positions[target_i], target_i, target_node, manager.speed_variances[target_i], manager.preferred_distances_sq[target_i], manager.orbital_speeds[target_i], manager)
		
		if manager.multimesh and manager.multimesh.multimesh:
			var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))
			manager.multimesh.multimesh.set_instance_transform(target_i, local_zero)
			
		promoted_indices[promoted_count] = target_i
		promoted_distances_sq[promoted_count] = min_val
		promoted_count += 1
		
		# O(1) Fast Swap: Replaces expensive remove_at() memory shifting mechanics
		unpromoted_candidates[min_idx] = unpromoted_candidates[unpromoted_count - 1]
		unpromoted_distances_sq[min_idx] = unpromoted_distances_sq[unpromoted_count - 1]
		unpromoted_count -= 1
		
		promotions_this_frame += 1
		free_node = manager._get_free_node()

	# PASS 4: Direct Swapping (With Throttling)
	while unpromoted_count > 0 and promoted_count > 0:
		if promotions_this_frame >= MAX_PROMOTIONS_PER_FRAME:
			break
			
		var min_un_idx: int = 0
		var min_un_val: float = unpromoted_distances_sq[0]
		for idx in range(1, unpromoted_count):
			if unpromoted_distances_sq[idx] < min_un_val:
				min_un_val = unpromoted_distances_sq[idx]
				min_un_idx = idx
				
		var max_prom_idx: int = 0
		var max_prom_val: float = promoted_distances_sq[0]
		for idx in range(1, promoted_count):
			if promoted_distances_sq[idx] > max_prom_val:
				max_prom_val = promoted_distances_sq[idx]
				max_prom_idx = idx
				
		if min_un_val < (max_prom_val - 4.0):
			var target_to_promote: int = unpromoted_candidates[min_un_idx]
			var target_to_demote: int = promoted_indices[max_prom_idx]
			
			var n: ActiveEnemy = manager.index_to_node_map[target_to_demote]
			if n:
				manager.set_enemy_state(target_to_demote, 1)
				manager.set_enemy_pos_vel(target_to_demote, n.global_position, manager.velocities[target_to_demote])
				
				if manager.multimesh and manager.multimesh.multimesh:
					var local_tf: Transform3D = mm_inv_xform * Transform3D(n.global_transform.basis, n.global_position)
					manager.multimesh.multimesh.set_instance_transform(target_to_demote, local_tf)
				n.deactivate()
				
				manager.set_enemy_state(target_to_promote, 2)
				
				var target_node: Node3D = player_node
				if manager.enemy_types[target_to_promote] == 0 and manager.core_node:
					target_node = manager.core_node

				n.activate(manager.positions[target_to_promote], target_to_promote, target_node, manager.speed_variances[target_to_promote], manager.preferred_distances_sq[target_to_promote], manager.orbital_speeds[target_to_promote], manager)
				
				if manager.multimesh and manager.multimesh.multimesh:
					var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))
					manager.multimesh.multimesh.set_instance_transform(target_to_promote, local_zero)
					
			promoted_indices[max_prom_idx] = target_to_promote
			promoted_distances_sq[max_prom_idx] = min_un_val
			
			# O(1) Fast Swap out the processed candidate
			unpromoted_candidates[min_un_idx] = unpromoted_candidates[unpromoted_count - 1]
			unpromoted_distances_sq[min_un_idx] = unpromoted_distances_sq[unpromoted_count - 1]
			unpromoted_count -= 1
			
			promotions_this_frame += 1
		else:
			break