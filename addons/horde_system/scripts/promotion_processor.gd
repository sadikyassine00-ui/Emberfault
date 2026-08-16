## PromotionProcessor — Decides which swarm members become real Node3D's.
##
## Every other physics frame (30 Hz) it:
##   1. Gathers distances of all alive entities to the player.
##   2. Demotes any promoted node that walked past demote_dist.
##   3. Promotes the closest unpromoted entities into free node pool slots.
##   4. Swaps far promoted nodes for closer unpromoted ones.
##   5. Wraps stragglers that wandered too far back in front of the player.
##
## Promotions are throttled to MAX_PROMOTIONS_PER_FRAME to avoid stutter.
extends Node
class_name ModularPromotionProcessor

@export_group("Straggler Wrapping")
## Distance beyond which an unpromoted ModularHordeEntity gets teleported back near the player
@export var straggler_distance  : float = 38.0
## Radius at which wrapped entities reappear (in front of player heading)
@export var wrap_spawn_radius   : float = 22.0

# Pre-allocated work arrays (grown once, reused every frame)
var _promoted_ids  : PackedInt32Array   = PackedInt32Array()
var _promoted_dists: PackedFloat32Array = PackedFloat32Array()
var _candidate_ids : PackedInt32Array   = PackedInt32Array()
var _candidate_dists: PackedFloat32Array = PackedFloat32Array()


func process_promotions(mgr) -> void:
	var player_node: Node3D = mgr.player
	if not player_node:
		return

	var player_pos  : Vector3 = player_node.global_position
	var p_flat      : Vector2 = Vector2(player_pos.x, player_pos.z)

	var promote_sq  : float = mgr.promote_dist * mgr.promote_dist
	var demote_sq   : float = mgr.demote_dist  * mgr.demote_dist
	var effective_straggler: float = straggler_distance
	var effective_wrap: float = wrap_spawn_radius
	if "spawn_radius_max" in mgr and mgr.spawn_radius_max > straggler_distance:
		effective_straggler = mgr.spawn_radius_max + 15.0
	if "spawn_radius_min" in mgr and mgr.spawn_radius_min > wrap_spawn_radius:
		effective_wrap = mgr.spawn_radius_min

	var straggler_sq: float = effective_straggler * effective_straggler

	# Determine player heading for straggler wrap direction
	var heading := Vector3.ZERO
	var pv: Vector3 = player_node.get("velocity") if "velocity" in player_node else Vector3.ZERO
	if pv.length_squared() > 0.1:
		heading = pv.normalized()
	else:
		heading = -player_node.global_transform.basis.z.normalized()
	var heading_2d : Vector2 = Vector2(heading.x, heading.z).normalized()

	var mm_inv : Transform3D = Transform3D()
	if mgr.multimesh:
		mm_inv = mgr.multimesh.global_transform.affine_inverse()

	# Grow work arrays if needed
	var cap : int = mgr.pool_size
	if _promoted_ids.size() < cap:
		_promoted_ids.resize(cap)
		_promoted_dists.resize(cap)
		_candidate_ids.resize(cap)
		_candidate_dists.resize(cap)

	var n_promoted  : int = 0
	var n_candidates: int = 0
	var n_promotions: int = 0
	const MAX_PROMOTIONS_PER_FRAME: int = 2

	# ══════════════════════════════════════════
	#  PASS 1 — Gather + straggler wrapping
	# ══════════════════════════════════════════
	for i in range(mgr.highest_active_index):
		var state : int = mgr.states[i]
		if state == 0:
			continue

		var cur_pos : Vector3
		if state == 2:
			var node: Node3D = mgr.index_to_node_map[i]
			if node:
				cur_pos = node.global_position
				mgr.set_pos_vel(i, cur_pos, mgr.velocities[i])
			else:
				# Node lost — recover
				mgr.set_state(i, 1)
				state   = 1
				cur_pos = mgr.positions[i]
		else:
			cur_pos = mgr.positions[i]

		var dist_sq : float = cur_pos.distance_squared_to(player_pos)

		# Wrap stragglers — teleport back in front of the player
		if state == 1 and dist_sq > straggler_sq:
			var angle  : float = randf_range(-PI / 4.0, PI / 4.0)
			var dir_2d : Vector2 = heading_2d.rotated(angle)
			var new_2d : Vector2 = p_flat + dir_2d * effective_wrap
			cur_pos = Vector3(new_2d.x, player_pos.y, new_2d.y)
			mgr.set_pos_vel(i, cur_pos, Vector3.ZERO)
			dist_sq = cur_pos.distance_squared_to(player_pos)

		# Bucket into promoted or promotion-candidate lists
		if state == 2:
			_promoted_ids[n_promoted]   = i
			_promoted_dists[n_promoted] = dist_sq
			n_promoted += 1
		elif state == 1 and dist_sq < promote_sq:
			_candidate_ids[n_candidates]   = i
			_candidate_dists[n_candidates] = dist_sq
			n_candidates += 1

	# ══════════════════════════════════════════
	#  PASS 2 — Demote distant promoted nodes
	# ══════════════════════════════════════════
	var write : int = 0
	for idx in range(n_promoted):
		var p_i  : int   = _promoted_ids[idx]
		var d_sq : float = _promoted_dists[idx]

		if d_sq > demote_sq:
			mgr.set_state(p_i, 1)
			var node: Node3D = mgr.index_to_node_map[p_i]
			if node:
				mgr.set_pos_vel(p_i, node.global_position, mgr.velocities[p_i])
				if mgr.multimesh and mgr.multimesh.multimesh:
					var xf := mm_inv * Transform3D(node.global_transform.basis, node.global_position)
					mgr.multimesh.multimesh.set_instance_transform(p_i, xf)
				node.deactivate()
		else:
			_promoted_ids[write]   = p_i
			_promoted_dists[write] = d_sq
			write += 1
	n_promoted = write

	# ══════════════════════════════════════════
	#  PASS 3 — Promote closest candidates into free nodes
	# ══════════════════════════════════════════
	var free_node: Node3D = mgr._get_free_node()
	while free_node and n_candidates > 0:
		if n_promotions >= MAX_PROMOTIONS_PER_FRAME:
			break

		# Find closest candidate
		var best_idx : int   = 0
		var best_val : float = _candidate_dists[0]
		for j in range(1, n_candidates):
			if _candidate_dists[j] < best_val:
				best_val = _candidate_dists[j]
				best_idx = j

		var target_i : int = _candidate_ids[best_idx]
		mgr.set_state(target_i, 2)

		free_node.activate(mgr.positions[target_i], target_i, player_node,
			mgr.speed_variances[target_i], mgr.preferred_distances_sq[target_i],
			mgr.orbital_speeds[target_i], mgr)

		if mgr.multimesh and mgr.multimesh.multimesh:
			var hide_xf := mm_inv * Transform3D(
				Basis().scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))
			mgr.multimesh.multimesh.set_instance_transform(target_i, hide_xf)

		_promoted_ids[n_promoted]   = target_i
		_promoted_dists[n_promoted] = best_val
		n_promoted += 1

		# O(1) swap-remove candidate
		_candidate_ids[best_idx]   = _candidate_ids[n_candidates - 1]
		_candidate_dists[best_idx] = _candidate_dists[n_candidates - 1]
		n_candidates -= 1

		n_promotions += 1
		free_node = mgr._get_free_node()

	# ══════════════════════════════════════════
	#  PASS 4 — Swap: demote farthest promoted, promote closest candidate
	# ══════════════════════════════════════════
	while n_candidates > 0 and n_promoted > 0:
		if n_promotions >= MAX_PROMOTIONS_PER_FRAME:
			break

		var best_c_idx : int   = 0
		var best_c_val : float = _candidate_dists[0]
		for j in range(1, n_candidates):
			if _candidate_dists[j] < best_c_val:
				best_c_val = _candidate_dists[j]
				best_c_idx = j

		var worst_p_idx : int   = 0
		var worst_p_val : float = _promoted_dists[0]
		for j in range(1, n_promoted):
			if _promoted_dists[j] > worst_p_val:
				worst_p_val = _promoted_dists[j]
				worst_p_idx = j

		if best_c_val < (worst_p_val - 4.0):
			var to_promote : int = _candidate_ids[best_c_idx]
			var to_demote  : int = _promoted_ids[worst_p_idx]

			var node: Node3D = mgr.index_to_node_map[to_demote]
			if node:
				mgr.set_state(to_demote, 1)
				mgr.set_pos_vel(to_demote, node.global_position, mgr.velocities[to_demote])
				if mgr.multimesh and mgr.multimesh.multimesh:
					var xf := mm_inv * Transform3D(node.global_transform.basis, node.global_position)
					mgr.multimesh.multimesh.set_instance_transform(to_demote, xf)
				node.deactivate()

				mgr.set_state(to_promote, 2)
				node.activate(mgr.positions[to_promote], to_promote, player_node,
					mgr.speed_variances[to_promote], mgr.preferred_distances_sq[to_promote],
					mgr.orbital_speeds[to_promote], mgr)

				if mgr.multimesh and mgr.multimesh.multimesh:
					var hide_xf := mm_inv * Transform3D(
						Basis().scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))
					mgr.multimesh.multimesh.set_instance_transform(to_promote, hide_xf)

			_promoted_ids[worst_p_idx]   = to_promote
			_promoted_dists[worst_p_idx] = best_c_val

			_candidate_ids[best_c_idx]   = _candidate_ids[n_candidates - 1]
			_candidate_dists[best_c_idx] = _candidate_dists[n_candidates - 1]
			n_candidates -= 1

			n_promotions += 1
		else:
			break
