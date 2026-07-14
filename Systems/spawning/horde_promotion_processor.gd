extends Node
class_name HordePromotionProcessor

@export_category("Straggler Management")
@export var straggler_distance: float = 38.0
@export var wrap_spawn_radius: float = 22.0

@export_category("Core-Breaker Base Tuning")
@export var core_straggler_distance: float = 45.0
@export var core_wrap_spawn_radius: float = 26.0

func process_promotions(manager: Node) -> void:
	var player_node: Node3D = manager.player
	if not player_node:
		return
		
	var player_pos: Vector3 = player_node.global_position
	var p_flat := Vector2(player_pos.x, player_pos.z)
	
	var core_node: Node3D = manager.core_node
	var core_pos := Vector3.ZERO
	var has_core: bool = false
	if core_node:
		core_pos = core_node.global_position
		has_core = true
	
	var promote_sq: float = manager.promote_dist * manager.promote_dist
	var demote_sq: float = manager.demote_dist * manager.demote_dist
	
	var straggler_sq: float = straggler_distance * straggler_distance
	var core_straggler_sq: float = core_straggler_distance * core_straggler_distance

	# Calculate active running direction
	var player_vel: Vector3 = player_node.get("velocity") if "velocity" in player_node else Vector3.ZERO
	var heading_dir := Vector3.ZERO
	
	if player_vel.length_squared() > 0.1:
		heading_dir = player_vel.normalized()
	else:
		heading_dir = - player_node.global_transform.basis.z.normalized()
		
	var heading_flat := Vector2(heading_dir.x, heading_dir.z).normalized()

	var mm_inv_xform := Transform3D()
	if manager.multimesh:
		mm_inv_xform = manager.multimesh.global_transform.affine_inverse()

	var promoted_indices: PackedInt32Array = PackedInt32Array()
	var promoted_distances_sq: PackedFloat32Array = PackedFloat32Array()
	
	var unpromoted_candidates: PackedInt32Array = PackedInt32Array()
	var unpromoted_distances_sq: PackedFloat32Array = PackedFloat32Array()

	# ⚡ PROMOTION THROTTLING REGISTER: Caps Node activations to prevent CPU frame spikes
	var promotions_this_frame: int = 0
	const MAX_PROMOTIONS_PER_FRAME: int = 2

	# PASS 1: Single-pass gather, coordinate sync, and targeted wrap projections
	for i in range(manager.highest_active_index):
		if manager.states[i] == 0:
			continue # Dead

		var current_pos: Vector3 = manager.positions[i]
		var dist_to_player_sq: float = current_pos.distance_squared_to(player_pos)
		var type: int = manager.enemy_types[i]

		if manager.states[i] == 1:
			if type == 1:
				if dist_to_player_sq > straggler_sq:
					var angle_offset: float = randf_range(-PI / 4.0, PI / 4.0)
					var spawn_dir_2d := heading_flat.rotated(angle_offset)
					var new_flat_pos: Vector2 = p_flat + (spawn_dir_2d * wrap_spawn_radius)
					manager.set_enemy_pos_vel(i, Vector3(new_flat_pos.x, player_pos.y, new_flat_pos.y), Vector3.ZERO)
					current_pos = manager.positions[i]
					dist_to_player_sq = current_pos.distance_squared_to(player_pos)
			else:
				if has_core:
					var dist_to_core_sq: float = current_pos.distance_squared_to(core_pos)
					if dist_to_core_sq > core_straggler_sq:
						var random_angle: float = randf_range(-PI, PI)
						var new_pos := core_pos + Vector3(cos(random_angle), 0.0, sin(random_angle)) * core_wrap_spawn_radius
						manager.set_enemy_pos_vel(i, new_pos, Vector3.ZERO)
						current_pos = manager.positions[i]
						dist_to_player_sq = current_pos.distance_squared_to(player_pos)
				else:
					if dist_to_player_sq > straggler_sq:
						var angle_offset: float = randf_range(-PI / 4.0, PI / 4.0)
						var spawn_dir_2d := heading_flat.rotated(angle_offset)
						var new_flat_pos := p_flat + (spawn_dir_2d * wrap_spawn_radius)
						manager.set_enemy_pos_vel(i, Vector3(new_flat_pos.x, player_pos.y, new_flat_pos.y), Vector3.ZERO)
						current_pos = manager.positions[i]
						dist_to_player_sq = current_pos.distance_squared_to(player_pos)

		# Categorization & Sync
		if manager.states[i] == 2:
			var n = manager._find_node_for_idx(i)
			if n:
				manager.set_enemy_pos_vel(i, n.global_position, manager.velocities[i])
				current_pos = n.global_position
				dist_to_player_sq = current_pos.distance_squared_to(player_pos)
				
				promoted_indices.append(i)
				promoted_distances_sq.append(dist_to_player_sq)
			else:
				manager.set_enemy_state(i, 1) # Fallback recovery
				
		elif manager.states[i] == 1:
			if dist_to_player_sq < promote_sq:
				unpromoted_candidates.append(i)
				unpromoted_distances_sq.append(dist_to_player_sq)

	# PASS 2: Demote active wrappers that walked beyond demote_dist
	var write_idx := 0
	for idx in range(promoted_indices.size()):
		var p_i: int = promoted_indices[idx]
		var dist_sq: float = promoted_distances_sq[idx]
		
		if dist_sq > demote_sq:
			manager.set_enemy_state(p_i, 1)
			var n = manager._find_node_for_idx(p_i)
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
			
	promoted_indices.resize(write_idx)
	promoted_distances_sq.resize(write_idx)

	# PASS 3: Fill empty node wrappers (With Throttling)
	var free_node = manager._get_free_node()
	while free_node and unpromoted_candidates.size() > 0:
		# ⚡ APPLY THROTTLE: Stop promoting if we hit our frame quota limit
		if promotions_this_frame >= MAX_PROMOTIONS_PER_FRAME:
			break
			
		var min_idx := 0
		var min_val := unpromoted_distances_sq[0]
		for idx in range(1, unpromoted_distances_sq.size()):
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
			var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))
			manager.multimesh.multimesh.set_instance_transform(target_i, local_zero)
			
		promoted_indices.append(target_i)
		promoted_distances_sq.append(min_val)
		
		unpromoted_candidates.remove_at(min_idx)
		unpromoted_distances_sq.remove_at(min_idx)
		
		# Increment throttle register
		promotions_this_frame += 1
		free_node = manager._get_free_node()

	# PASS 4: Direct Swapping (With Throttling)
	while unpromoted_candidates.size() > 0 and promoted_indices.size() > 0:
		# ⚡ APPLY THROTTLE: Cap frame workload
		if promotions_this_frame >= MAX_PROMOTIONS_PER_FRAME:
			break
			
		var min_un_idx := 0
		var min_un_val := unpromoted_distances_sq[0]
		for idx in range(1, unpromoted_distances_sq.size()):
			if unpromoted_distances_sq[idx] < min_un_val:
				min_un_val = unpromoted_distances_sq[idx]
				min_un_idx = idx
				
		var max_prom_idx := 0
		var max_prom_val := promoted_distances_sq[0]
		for idx in range(1, promoted_distances_sq.size()):
			if promoted_distances_sq[idx] > max_prom_val:
				max_prom_val = promoted_distances_sq[idx]
				max_prom_idx = idx
				
		if min_un_val < (max_prom_val - 4.0):
			var target_to_promote: int = unpromoted_candidates[min_un_idx]
			var target_to_demote: int = promoted_indices[max_prom_idx]
			
			var n = manager._find_node_for_idx(target_to_demote)
			if n:
				# 1. Demote the far-away wrapper
				manager.set_enemy_state(target_to_demote, 1)
				manager.set_enemy_pos_vel(target_to_demote, n.global_position, manager.velocities[target_to_demote])
				
				if manager.multimesh and manager.multimesh.multimesh:
					var local_tf: Transform3D = mm_inv_xform * Transform3D(n.global_transform.basis, n.global_position)
					manager.multimesh.multimesh.set_instance_transform(target_to_demote, local_tf)
				n.deactivate()
				
				# 2. Promote the closer unit
				manager.set_enemy_state(target_to_promote, 2)
				
				var target_node: Node3D = player_node
				if manager.enemy_types[target_to_promote] == 0 and manager.core_node:
					target_node = manager.core_node

				n.activate(manager.positions[target_to_promote], target_to_promote, target_node, manager.speed_variances[target_to_promote], manager.preferred_distances_sq[target_to_promote], manager.orbital_speeds[target_to_promote], manager)
				
				if manager.multimesh and manager.multimesh.multimesh:
					var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))
					manager.multimesh.multimesh.set_instance_transform(target_to_promote, local_zero)
					
			promoted_indices[max_prom_idx] = target_to_promote
			promoted_distances_sq[max_prom_idx] = min_un_val
			
			unpromoted_candidates.remove_at(min_un_idx)
			unpromoted_distances_sq.remove_at(min_un_idx)
			
			# Increment throttle register
			promotions_this_frame += 1
		else:
			break