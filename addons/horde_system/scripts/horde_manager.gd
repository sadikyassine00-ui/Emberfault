## HordeManager — Central hub of the horde system.
##
## This node owns:
##   • A flat PackedArray "database" for every entity attribute (positions, velocities, health…).
##   • A MultiMesh for rendering hundreds of swarm members cheaply.
##   • A small object pool of HordeEntity nodes for close-range "promoted" enemies.
##   • References to the SwarmProcessor (simulation) and PromotionProcessor (LOD switching).
##
## Usage:
##   1. Drop a HordeManager into your scene.
##   2. Assign a player Node3D, a MultiMeshInstance3D, and an active_entity_scene PackedScene.
##   3. Optionally plug in SwarmProcessor / PromotionProcessor children (or let it find them).
##   4. Call spawn_ring() to add enemies — or enable auto_spawn.
##
## Designed to be game-agnostic.  Your player just needs a global_position;
## optionally implement take_damage(amount: float) for combat.
extends Node3D
class_name ModularHordeManager

# ═══════════════════════════════════════════
#  Exports — configure in the Inspector
# ═══════════════════════════════════════════

@export_group("References")
## The player node the horde will chase.
@export var player: Node3D
## The MultiMeshInstance3D used for rendering the swarm layer.
@export var multimesh: MultiMeshInstance3D
## Scene to instantiate for promoted (close-range) entities.
@export var active_entity_scene: PackedScene
## (Optional) Drag-in references; if null, the manager finds children by class.
@export var swarm_processor: Node
@export var promotion_processor: Node

@export_group("Pool Sizes")
## Total number of entity slots pre-allocated (the ceiling for alive enemies).
@export var pool_size: int = 500
## Max number of active enemies you want spawning on the field right now.
@export var max_alive: int = 150
## Max number of full Node3D (promoted) instances to exist concurrently.
@export var max_active_nodes: int = 20
## CPU Optimization: Only update 1/N of the swarm per frame. Higher = better FPS, slightly jittery sim.
@export var stagger_slices: int = 5

@export_group("Movement")
@export var base_speed: float = 4.5
@export var enemy_scale: float = 1.0

@export_group("Combat — Token Director")
## Max simultaneous attack tokens (one token = one enemy allowed to strike).
@export var max_tokens: int = 8

@export_group("Promotion Envelope")
## Distance at which a swarm member may be promoted to a Node3D.
@export var promote_dist: float = 14.5
## Distance at which a promoted Node3D reverts to a MultiMesh dot.
@export var demote_dist: float = 22.0

@export_group("Spawning Defaults")
@export var default_hp: float = 30.0
@export var default_damage: float = 2.0

@export_group("Combat")
@export var enemy_types: Array[EnemyTypeDefinition] = []

@export_group("Auto Spawner")
@export var auto_spawn: bool = true
@export var spawn_cooldown: float = 1.0
@export var spawn_radius_min: float = 18.0
@export var spawn_radius_max: float = 26.0

# ═══════════════════════════════════════════
#  Flat-array "database"
# ═══════════════════════════════════════════
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var states: PackedByteArray = PackedByteArray() # 0=dead, 1=swarm, 2=promoted
var speed_variances: PackedFloat32Array = PackedFloat32Array()
var preferred_distances_sq: PackedFloat32Array = PackedFloat32Array()
var orbital_speeds: PackedFloat32Array = PackedFloat32Array()
var health_array: PackedFloat32Array = PackedFloat32Array()
var damage_array: PackedFloat32Array = PackedFloat32Array()
var hit_timers: PackedFloat32Array = PackedFloat32Array()
var attack_cooldowns: PackedFloat32Array = PackedFloat32Array()
var strike_visual_timers: PackedFloat32Array = PackedFloat32Array()
var token_states: PackedByteArray = PackedByteArray()
var headings: PackedVector3Array = PackedVector3Array()
var floor_heights: PackedFloat32Array = PackedFloat32Array()
var generations: PackedInt32Array = PackedInt32Array()
var free_indices: PackedInt32Array = PackedInt32Array()
var type_ids: PackedInt32Array = PackedInt32Array()

## Maps flat-array index → the HordeEntity node currently representing it (or null).
var index_to_node_map: Array[Node3D] = []

## Object pool of pre-created HordeEntity nodes.
var node_pool: Array[Node3D] = []
## Currently active (promoted) nodes — iterated every physics frame.
var active_pool: Array[Node3D] = []

var highest_active_index: int = 0
var alive_count: int = 0
var active_tokens: int = 0
var _mm_hide_xform: Transform3D  # Cached once, reused every kill

var _spawn_timer: float = 0.0
var _warmup_stage: int = 0
var _prewarm_dummy: Node3D = null
var _prewarm_frames: int = 2
var _init_index: int = 0
const _INIT_BATCH: int = 2

# ═══════════════════════════════════════════
#  Ready
# ═══════════════════════════════════════════
func _ready() -> void:
	# Auto-find processors if not explicitly assigned
	if not swarm_processor:
		for child in get_children():
			if child.has_method("process_swarm"):
				swarm_processor = child
				break
	if not promotion_processor:
		for child in get_children():
			if child.has_method("process_promotions"):
				promotion_processor = child
				break

	# Allocate flat arrays
	positions.resize(pool_size); positions.fill(Vector3.ZERO)
	velocities.resize(pool_size); velocities.fill(Vector3.ZERO)
	states.resize(pool_size); states.fill(0)
	speed_variances.resize(pool_size); speed_variances.fill(1.0)
	preferred_distances_sq.resize(pool_size)
	for i in range(pool_size):
		preferred_distances_sq[i] = 4.0 + float(i % 8) * 1.0 + randf_range(-0.5, 0.5)
	orbital_speeds.resize(pool_size); orbital_speeds.fill(1.0)
	health_array.resize(pool_size); health_array.fill(default_hp)
	damage_array.resize(pool_size); damage_array.fill(default_damage)
	hit_timers.resize(pool_size); hit_timers.fill(0.0)
	attack_cooldowns.resize(pool_size); attack_cooldowns.fill(0.0)
	strike_visual_timers.resize(pool_size); strike_visual_timers.fill(0.0)
	token_states.resize(pool_size); token_states.fill(0)
	headings.resize(pool_size); headings.fill(Vector3.FORWARD)
	floor_heights.resize(pool_size); floor_heights.fill(0.0)
	generations.resize(pool_size); generations.fill(0)
	type_ids.resize(pool_size); type_ids.fill(0)

	free_indices.resize(pool_size)
	for i in range(pool_size):
		free_indices[i] = pool_size - 1 - i

	index_to_node_map.resize(pool_size)
	index_to_node_map.fill(null)

	# Configure MultiMesh
	if multimesh and multimesh.multimesh:
		var mm := multimesh.multimesh
		mm.instance_count = 0
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.instance_count = pool_size
		for i in range(pool_size):
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, Color.TRANSPARENT)

		print("GODOT MULTIMESH BUFFER SIZE: ", mm.buffer.size())
		print("MY POOL_SIZE: ", pool_size)

	# Pre-compute the hide transform for kill_enemy (avoids affine_inverse per kill)
	if multimesh:
		var mm_inv := multimesh.global_transform.affine_inverse()
		_mm_hide_xform = mm_inv * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))

# ═══════════════════════════════════════════
#  Token Director — limits simultaneous attackers
# ═══════════════════════════════════════════

## Request an attack token.  Returns 1 on success, 0 on failure.
## If all tokens are taken, the farthest holder loses theirs (proximity theft).
func request_token(requester_dist: float, requester_idx: int) -> int:
	if requester_idx < 0 or requester_idx >= token_states.size():
		return 0

	if active_tokens < max_tokens:
		active_tokens += 1
		token_states[requester_idx] = 1
		return 1

	# Proximity theft — steal from the farthest token holder
	if not player:
		return 0
	var tp: Vector3 = player.global_position
	var worst: int = -1
	var w_dist: float = requester_dist

	var limit: int = min(highest_active_index, token_states.size())
	for i in range(limit):
		if token_states[i] == 1 and strike_visual_timers[i] == 0.0:
			var d: float = positions[i].distance_to(tp)
			if d > w_dist:
				w_dist = d
				worst = i

	if worst != -1:
		token_states[worst] = 0
		strike_visual_timers[worst] = 0.0
		var node := _find_node(worst)
		if node and is_instance_valid(node) and node.mesh_instance:
			node.mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", 0.0)
		token_states[requester_idx] = 1
		return 1

	return 0

func release_token(_token_value: int) -> void:
	active_tokens = max(0, active_tokens - 1)

# ═══════════════════════════════════════════
#  Spawning
# ═══════════════════════════════════════════

## Spawn `count` enemies in a ring of `radius` around `center`.
func spawn_ring(center: Node3D, radius: float, count: int) -> void:
	if alive_count >= max_alive or not center:
		return
	var actual: int = min(count, max_alive - alive_count)
	var center_p: Vector3 = center.global_position
	var angle_step: float = TAU / float(actual)
	var angle: float = randf() * TAU
	var spawned: int = 0

	while spawned < actual and free_indices.size() > 0:
		var f_idx: int = free_indices.size() - 1
		var i: int = free_indices[f_idx]
		free_indices.resize(f_idx)

		generations[i] += 1

		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		positions[i] = center_p + offset
		positions[i].y = center_p.y
		velocities[i] = Vector3.ZERO
		states[i] = 1 # Swarm by default
		speed_variances[i] = 1.0 + randf_range(-0.15, 0.15)
		preferred_distances_sq[i] = randf_range(1.0, 9.0)
		type_ids[i] = 0
		orbital_speeds[i] = randf_range(0.8, 1.4)
		health_array[i] = default_hp
		damage_array[i] = default_damage
		hit_timers[i] = 0.0
		attack_cooldowns[i] = 0.0
		strike_visual_timers[i] = 0.0
		token_states[i] = 0
		headings[i] = Vector3.FORWARD
		floor_heights[i] = center_p.y

		alive_count += 1
		highest_active_index = max(highest_active_index, i + 1)
		angle += angle_step
		spawned += 1

## Kill a single entity by flat-array index.
func kill_enemy(idx: int) -> void:
	if idx < 0 or idx >= pool_size or states[idx] == 0:
		return

	# Hide from MultiMesh
	if multimesh and multimesh.multimesh:
		multimesh.multimesh.set_instance_transform(idx, _mm_hide_xform)
		multimesh.multimesh.set_instance_custom_data(idx, Color.TRANSPARENT)

	var t_id: int = type_ids[idx]
	var behavior: DeathBehavior = _get_type_def(t_id).get_death_behavior()
	behavior.on_death(positions[idx], t_id)
	HordeCombatEvents.enemy_died.emit(idx, states[idx] == 2, positions[idx], t_id)

	states[idx] = 0
	positions[idx] = Vector3(0, -1000, 0)
	velocities[idx] = Vector3.ZERO

	if token_states[idx] > 0:
		release_token(token_states[idx])
	token_states[idx] = 0
	strike_visual_timers[idx] = 0.0
	hit_timers[idx] = 0.0
	attack_cooldowns[idx] = 0.0
	headings[idx] = Vector3.FORWARD
	floor_heights[idx] = 0.0

	if idx < index_to_node_map.size():
		index_to_node_map[idx] = null

	alive_count = max(0, alive_count - 1)
	free_indices.append(idx)

	if idx + 1 == highest_active_index:
		var new_h := 0
		var scan_floor := max(0, idx - 32)
		for j in range(idx, scan_floor - 1, -1):
			if states[j] > 0:
				new_h = j + 1
				break
		highest_active_index = new_h

# ═══════════════════════════════════════════
#  Batch damage — call from weapon systems
# ═══════════════════════════════════════════

## Deal `amount` damage to every entity packed in `packed_ids` (64-bit: generation << 32 | index).
## `knockback_origin` is the world-space point the knockback radiates from.
## `knockback_force` controls push strength.
func deal_damage(packed_ids: PackedInt64Array, amount: float = -1.0,
		knockback_origin: Vector3 = Vector3.ZERO,
		knockback_force: float = 14.0,
		damage_info: DamageInfo = null) -> void:
	for packed in packed_ids:
		var i: int = packed & 0xFFFFFFFF
		var gen: int = packed >> 32

		if i < 0 or i >= pool_size or states[i] == 0:
			continue
		if generations[i] != gen:
			continue
		if hit_timers[i] > 0.0:
			continue

		hit_timers[i] = 1.0

		var actual_amount: float = amount
		var info: DamageInfo = damage_info
		if not info:
			# Fallback if no DamageInfo provided
			info = DamageInfo.new()
			info.amount = amount if amount >= 0.0 else default_damage
			info.source_position = knockback_origin
			actual_amount = info.amount
		else:
			if actual_amount < 0.0:
				actual_amount = info.amount

		HordeCombatEvents.enemy_took_damage.emit(i, states[i] == 2, info)

		# Knockback
		var push := (positions[i] - knockback_origin).normalized()
		push.y = 0.0
		if push.length_squared() < 0.001:
			push = Vector3.FORWARD
		velocities[i] += push * knockback_force

		# Promoted node path
		if states[i] == 2:
			var node := _find_node(i)
			if node and is_instance_valid(node):
				node.velocity = velocities[i]
				node.trigger_hit_flash()
				health_array[i] -= actual_amount
				if health_array[i] <= 0.0:
					node.deactivate()
					kill_enemy(i)
		else:
			# Swarm path — mark custom data red flash
			if multimesh and multimesh.multimesh:
				multimesh.multimesh.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))

			health_array[i] -= actual_amount
			if health_array[i] <= 0.0:
				kill_enemy(i)

# ═══════════════════════════════════════════
#  Internal helpers
# ═══════════════════════════════════════════
func set_pos_vel(idx: int, pos: Vector3, vel: Vector3) -> void:
	if idx >= 0 and idx < pool_size:
		positions[idx] = pos
		velocities[idx] = vel

func set_state(idx: int, val: int) -> void:
	if idx >= 0 and idx < pool_size:
		states[idx] = val

func _find_node(idx: int) -> Node3D:
	if idx < 0 or idx >= index_to_node_map.size():
		return null
	return index_to_node_map[idx]

var _fallback_type_def: EnemyTypeDefinition = null
func _get_type_def(t_id: int) -> EnemyTypeDefinition:
	if t_id >= 0 and t_id < enemy_types.size() and enemy_types[t_id] != null:
		return enemy_types[t_id]
	if not _fallback_type_def:
		_fallback_type_def = EnemyTypeDefinition.new()
	return _fallback_type_def

func _get_free_node() -> Node3D:
	for n in node_pool:
		if not n.is_active:
			return n
	return null

# ═══════════════════════════════════════════
#  Physics tick — orchestrates everything
# ═══════════════════════════════════════════
var _prof_samples: Array[Dictionary] = []
var _prof_frame: int = 0

func _physics_process(delta: float) -> void:
	# ── Warmup: stagger node pool creation over multiple frames ──
	if _warmup_stage < 2:
		_warmup_tick()
		return

	var t0 := Time.get_ticks_usec()

	# 1. Promoted entities tick every frame (responsive combat)
	for entity: Node3D in active_pool:
		if entity and is_instance_valid(entity) and entity.is_active:
			entity.managed_tick(delta)

	var t1 := Time.get_ticks_usec()

	# 2. Swarm simulation
	if swarm_processor:
		swarm_processor.process_swarm(self, delta)

	var t2 := Time.get_ticks_usec()

	# 3. Promotions at half rate (30 Hz on 60 FPS)
	if Engine.get_physics_frames() % 2 == 0:
		if promotion_processor:
			promotion_processor.process_promotions(self)

	var t3 := Time.get_ticks_usec()

	# 4. Auto-spawn
	if auto_spawn and player:
		_spawn_timer += delta
		if _spawn_timer >= spawn_cooldown:
			_spawn_timer = 0.0
			if alive_count < max_alive:
				var batch: int = min(15, max_alive - alive_count)
				spawn_ring(player, randf_range(spawn_radius_min, spawn_radius_max), batch)

	# 5. Clamp visible instance count for performance
	if multimesh and multimesh.multimesh:
		multimesh.multimesh.visible_instance_count = highest_active_index

	var t4 := Time.get_ticks_usec()

	# ── Profiler accumulator ──
	_prof_samples.append({
		"promoted": t1 - t0,
		"swarm": t2 - t1,
		"promotion": t3 - t2,
		"total": t4 - t0,
		"alive": alive_count,
	})
	_prof_frame += 1
	if _prof_frame % 120 == 0:
		var n: int = _prof_samples.size()
		var sum_p := 0; var sum_s := 0; var sum_pr := 0; var sum_t := 0
		var max_p := 0; var max_s := 0; var max_pr := 0; var max_t := 0
		for s in _prof_samples:
			sum_p += s.promoted; sum_s += s.swarm; sum_pr += s.promotion; sum_t += s.total
			max_p = max(max_p, s.promoted); max_s = max(max_s, s.swarm)
			max_pr = max(max_pr, s.promotion); max_t = max(max_t, s.total)
		# Suppress profiling spam
		# print("═══ HORDE PROFILER (%d frames, %d alive) ═══" % [n, alive_count])
		# print("  Promoted ticks: avg=%.1fus  max=%.1fus" % [float(sum_p)/n, float(max_p)])
		# print("  Swarm sim:      avg=%.1fus  max=%.1fus" % [float(sum_s)/n, float(max_s)])
		# print("  Promotion proc: avg=%.1fus  max=%.1fus" % [float(sum_pr)/n, float(max_pr)])
		# print("  TOTAL frame:    avg=%.1fus  max=%.1fus (%.1f FPS budget)" % [float(sum_t)/n, float(max_t), 1000000.0 / max(1, max_t)])
		_prof_samples.clear()

func _warmup_tick() -> void:
	match _warmup_stage:
		0:
			# Pre-warm GPU by briefly instantiating one entity in front of camera
			if _prewarm_frames == 2:
				var cam := get_viewport().get_camera_3d()
				if cam and active_entity_scene:
					_prewarm_dummy = active_entity_scene.instantiate()
					cam.add_child(_prewarm_dummy)
					_prewarm_dummy.position = Vector3(0.0, 0.0, -1.0)
					_prewarm_dummy.scale = Vector3(0.001, 0.001, 0.001)
			_prewarm_frames -= 1
			if _prewarm_frames <= 0:
				if _prewarm_dummy:
					_prewarm_dummy.queue_free()
					_prewarm_dummy = null
				_warmup_stage = 1
		1:
			# Gradually instantiate the node pool
			var limit: int = int(min(_init_index + _INIT_BATCH, max_active_nodes))
			for i in range(_init_index, limit):
				var inst := active_entity_scene.instantiate() as Node3D
				add_child(inst)
				node_pool.append(inst)
			_init_index = limit
			if _init_index >= max_active_nodes:
				_warmup_stage = 2
