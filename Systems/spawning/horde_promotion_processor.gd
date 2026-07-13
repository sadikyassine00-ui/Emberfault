extends Node
class_name HordePromotionProcessor

@export_category("Straggler Management")
@export var straggler_distance: float = 38.0
@export var wrap_spawn_radius: float = 22.0

func process_promotions(manager: Node) -> void:
	var player_node: Node3D = manager.player
	if not player_node:
		return
		
	var player_pos: Vector3 = player_node.global_position
	var p_flat := Vector2(player_pos.x, player_pos.z)
	
	var promote_sq: float = manager.promote_dist * manager.promote_dist
	var demote_sq: float = manager.demote_dist * manager.demote_dist
	var straggler_sq: float = straggler_distance * straggler_distance

	var player_forward: Vector3 = - player_node.global_transform.basis.z.normalized()
	var player_forward_flat := Vector2(player_forward.x, player_forward.z).normalized()

	for i in range(manager.highest_active_index):
		if manager.states[i] == 0:
			continue # Dead

		var current_pos: Vector3 = manager.positions[i]
		var dist_to_player_sq: float = current_pos.distance_squared_to(player_pos)

		# --- 🔄 INTENT-ISOLATED STRAGGLER CULLING GATE ---
		# Core-Breakers (1) are completely ignored by this block and stay locked on the base core!
		if manager.states[i] == 1 and manager.intents[i] == 0 and dist_to_player_sq > straggler_sq:
			var random_angle: float = randf_range(-PI, PI)
			var check_dir := Vector2(cos(random_angle), sin(random_angle))
			
			if check_dir.dot(player_forward_flat) > 0.4:
				check_dir = - check_dir

			var new_flat_pos: Vector2 = p_flat + (check_dir * wrap_spawn_radius)
			manager.positions[i] = Vector3(new_flat_pos.x, player_pos.y, new_flat_pos.y)
			manager.velocities[i] = Vector3.ZERO
			
			current_pos = manager.positions[i]
			dist_to_player_sq = current_pos.distance_squared_to(player_pos)

		# --- PROMOTION CHECK (State 1 -> State 2) ---
		if manager.states[i] == 1 and dist_to_player_sq < promote_sq:
			var free_node = manager._get_free_node()

			if free_node:
				manager.states[i] = 2
				var target_node: Node3D = manager.player if manager.intents[i] == 0 else manager.base_core
				free_node.activate(current_pos, i, target_node, manager.speed_variances[i], manager.preferred_distances_sq[i], manager.orbital_speeds[i], manager)
				
				if manager.multimesh and manager.multimesh.multimesh:
					manager.multimesh.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
				continue
			else:
				var furthest_node = null
				var max_dist_sq: float = -1.0

				for n in manager.node_pool:
					if n.is_active:
						var n_flat := Vector2(n.global_position.x, n.global_position.z)
						var n_dist_sq: float = p_flat.distance_squared_to(n_flat)
						if n_dist_sq > max_dist_sq:
							max_dist_sq = n_dist_sq
							furthest_node = n

				if furthest_node and dist_to_player_sq < (max_dist_sq - 4.0):
					var stolen_idx: int = furthest_node.linked_idx

					manager.states[stolen_idx] = 1
					manager.positions[stolen_idx] = furthest_node.global_position
					furthest_node.deactivate()

					manager.states[i] = 2
					var target_node: Node3D = manager.player if manager.intents[i] == 0 else manager.base_core
					furthest_node.activate(current_pos, i, target_node, manager.speed_variances[i], manager.preferred_distances_sq[i], manager.orbital_speeds[i], manager)
					
					if manager.multimesh and manager.multimesh.multimesh:
						manager.multimesh.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
					continue

		# --- DEMOTION CHECK (State 2 -> State 1) ---
		if manager.states[i] == 2:
			var n = manager._find_node_for_idx(i)
			if n:
				if dist_to_player_sq > demote_sq:
					manager.states[i] = 1
					manager.positions[i] = n.global_position
					n.deactivate()
				else:
					manager.positions[i] = n.global_position
					continue