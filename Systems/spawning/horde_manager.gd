extends Node3D
class_name HordeManager

# =============================================================================
# 🏢 CORE ENGINE BINDINGS
# =============================================================================
@export_group("Core Nodes")
@export var player: Node3D
@export var core_node: Node3D
@export var multimesh: MultiMeshInstance3D
@export var active_enemy_scene: PackedScene
@export var simulation_processor: Node
@export var promotion_processor: Node

@export_group("Voxel Terrain Binding")
@export var voxel_terrain: Node3D

@export_group("Horde Framework Settings")
@export var pool_size: int = 1000
@export var max_concurrent_enemies: int = 150
@export var base_speed: float = 4.5
@export var max_active_nodes: int = 20
@export var enemy_scale: float = 1.0

@export_range(0.0, 1.0) var hunter_ratio: float = 0.25
@export var aggro_hijack_duration: float = 5.0

@export_group("Token Director Framework")
@export var max_core_tokens: int = 5
@export var max_player_tokens: int = 5

var active_core_tokens: int = 0
var active_player_tokens: int = 0

@export_group("Promotion Envelope Thresholds")
@export var promote_dist: float = 14.5
@export var demote_dist: float = 22.0

@export_group("Spawning Parameters")
@export var default_hp: float = 30.0
@export var default_damage: float = 2.0

@export_group("Zero-Director Auto Spawner")
@export var auto_spawn_enabled: bool = true
@export var auto_spawn_cooldown: float = 1.0
var spawn_timer: float = 0.0

var voxel_tool: RefCounted = null

# =============================================================================
# 📦 MEMORY-ALIGNED DATABASE STRUCTURES (FLAT DATA TABLES)
# =============================================================================
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var states: PackedByteArray = PackedByteArray()
var speed_variances: PackedFloat32Array = PackedFloat32Array()
var preferred_distances_sq: PackedFloat32Array = PackedFloat32Array()
var orbital_speeds: PackedFloat32Array = PackedFloat32Array()
var health_array: PackedFloat32Array = PackedFloat32Array()
var damage_array: PackedFloat32Array = PackedFloat32Array()
var enemy_types: PackedInt32Array = PackedInt32Array()
var intents: PackedByteArray = PackedByteArray()
var aggro_cooldowns: PackedFloat32Array = PackedFloat32Array()
var hit_timers: PackedFloat32Array = PackedFloat32Array()
var attack_cooldowns: PackedFloat32Array = PackedFloat32Array()
var strike_visual_timers: PackedFloat32Array = PackedFloat32Array()
var token_states: PackedByteArray = PackedByteArray()
var headings: PackedVector3Array = PackedVector3Array()
var floor_heights: PackedFloat32Array = PackedFloat32Array()
var index_to_node_map: Array[ActiveEnemy] = []

var node_pool: Array[ActiveEnemy] = []
var active_execution_pool: Array[ActiveEnemy] = []

var highest_active_index: int = 0
var alive_count: int = 0

var warmup_stage: int = 0
var _prewarm_dummy: Node3D = null
var _prewarm_frames: int = 2
var _init_index: int = 0
const INIT_BATCH_SIZE: int = 2

func _ready() -> void:
	positions.resize(pool_size)
	velocities.resize(pool_size)
	states.resize(pool_size)
	speed_variances.resize(pool_size)
	preferred_distances_sq.resize(pool_size)
	orbital_speeds.resize(pool_size)
	health_array.resize(pool_size)
	damage_array.resize(pool_size)
	enemy_types.resize(pool_size)
	intents.resize(pool_size)
	aggro_cooldowns.resize(pool_size)
	hit_timers.resize(pool_size)
	attack_cooldowns.resize(pool_size)
	strike_visual_timers.resize(pool_size)
	token_states.resize(pool_size)
	headings.resize(pool_size)
	floor_heights.resize(pool_size)

	positions.fill(Vector3.ZERO)
	velocities.fill(Vector3.ZERO)
	states.fill(0)
	speed_variances.fill(1.0)
	preferred_distances_sq.fill(10.0)
	orbital_speeds.fill(1.0)
	health_array.fill(default_hp)
	damage_array.fill(default_damage)
	enemy_types.fill(0)
	intents.fill(0)
	aggro_cooldowns.fill(0.0)
	hit_timers.fill(0.0)
	attack_cooldowns.fill(0.0)
	strike_visual_timers.fill(0.0)
	token_states.fill(0)
	headings.fill(Vector3.FORWARD)
	floor_heights.fill(0.0)

	active_core_tokens = 0
	active_player_tokens = 0

	index_to_node_map.resize(pool_size)
	index_to_node_map.fill(null)

	if voxel_terrain and voxel_terrain.has_method("get_voxel_tool"):
		voxel_tool = voxel_terrain.get_voxel_tool()

	if multimesh and multimesh.multimesh:
		multimesh.multimesh.instance_count = 0
		multimesh.multimesh.use_custom_data = true
		multimesh.multimesh.instance_count = pool_size
		for i in range(pool_size):
			multimesh.multimesh.set_instance_color(i, Color.WHITE)
			multimesh.multimesh.set_instance_custom_data(i, Color.TRANSPARENT)

# =============================================================================
# ⚡ CENTRALIZED PROXIMITY-THEFT TOKEN ALLOCATION
# =============================================================================
func request_combat_token(type: int, requester_dist: float, requester_idx: int) -> int:
	# Armored atomic bounds guard to catch asynchronous array shifts instantly
	var current_size: int = token_states.size()
	if requester_idx < 0 or requester_idx >= current_size:
		return 0

	var target_token_state: int = 1 if type == 0 else 2
	var current_tokens: int = active_core_tokens if type == 0 else active_player_tokens
	var max_tokens: int = max_core_tokens if type == 0 else max_player_tokens

	if current_tokens < max_tokens:
		if type == 0: active_core_tokens += 1
		else: active_player_tokens += 1
		if requester_idx < token_states.size():
			token_states[requester_idx] = target_token_state
		return target_token_state

	var target_node: Node3D = core_node if type == 0 else player
	if not target_node: return 0

	var target_pos: Vector3 = target_node.global_position
	var worst_idx: int = -1
	var worst_dist: float = requester_dist

	# Multi-thread secure execution loop bounds matching runtime conditions
	var search_limit: int = min(highest_active_index, token_states.size())
	for i in range(search_limit):
		if i >= token_states.size() or i >= strike_visual_timers.size():
			break
		if token_states[i] == target_token_state and strike_visual_timers[i] == 0.0:
			var holder_dist: float = positions[i].distance_to(target_pos)
			if holder_dist > worst_dist:
				worst_dist = holder_dist
				worst_idx = i

	if worst_idx != -1:
		if worst_idx < token_states.size():
			token_states[worst_idx] = 0
		if worst_idx < strike_visual_timers.size():
			strike_visual_timers[worst_idx] = 0.0

		var active_node = _find_node_for_idx(worst_idx)
		if active_node and is_instance_valid(active_node) and active_node.mesh_instance:
			active_node.mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", 0.0)

		if requester_idx < token_states.size():
			token_states[requester_idx] = target_token_state
		return target_token_state

	return 0

func release_combat_token(token_type: int) -> void:
	if token_type == 1:
		active_core_tokens = max(0, active_core_tokens - 1)
	elif token_type == 2:
		active_player_tokens = max(0, active_player_tokens - 1)

# =============================================================================
# 🏔️ PREDICIVE HYPER-PERFORMANCE VOXEL GROUND SCANNER (O(1) CACHE MATCH)
# =============================================================================
func get_voxel_ground_height(vt: RefCounted, x: float, start_y: float, z: float, active_offset: float) -> float:
	if not vt:
		return start_y

	# Convert to integer block coordinates for lightning-fast direct memory array indexing
	var ipos := Vector3i(int(floor(x)), int(floor(start_y)), int(floor(z)))
	var lookup_method := "get_voxel" if vt.has_method("get_voxel") else "get_voxel_f"

	# 1. Predictive Fast-Pass: Check if current node is air and block below is solid
	var current_block = vt.call(lookup_method, ipos)
	var below_block = vt.call(lookup_method, ipos + Vector3i.DOWN)

	if current_block == 0 and below_block != 0:
		return float(ipos.y) + active_offset

	# 2. Predictive Escape: If stuck inside solid geometry, trace up quickly
	if current_block != 0:
		for u in range(1, 5):
			if vt.call(lookup_method, ipos + Vector3i(0, u, 0)) == 0:
				return float(ipos.y + u) + active_offset
		return start_y

	# 3. Micro-Stride Fallback: Scan down locally (capped at 6 steps maximum instead of 25)
	for d in range(2, 8):
		if vt.call(lookup_method, ipos + Vector3i(0, -d, 0)) != 0:
			return float(ipos.y - d + 1) + active_offset

	return start_y

func spawn_wave_ring(target: Node3D, radius: float, count: int) -> void:
	if alive_count >= max_concurrent_enemies or not target:
		return

	var actual_spawn_count: int = min(count, max_concurrent_enemies - alive_count)
	var target_pos: Vector3 = target.global_position
	var angle_step: float = (PI * 2.0) / float(actual_spawn_count)
	var current_angle: float = randf() * PI * 2.0

	var spawned: int = 0
	for i in range(pool_size):
		if spawned >= actual_spawn_count:
			break

		if states[i] == 0:
			var offset := Vector3(cos(current_angle), 0, sin(current_angle)) * radius
			positions[i] = target_pos + offset
			positions[i].y = target_pos.y
			velocities[i] = Vector3.ZERO
			states[i] = 1

			speed_variances[i] = randf_range(0.85, 1.15)
			preferred_distances_sq[i] = randf_range(1.0, 9.0)
			orbital_speeds[i] = randf_range(0.8, 1.4)
			health_array[i] = default_hp
			damage_array[i] = default_damage
			intents[i] = 0
			aggro_cooldowns[i] = 0.0
			hit_timers[i] = 0.0
			attack_cooldowns[i] = 0.0
			strike_visual_timers[i] = 0.0
			token_states[i] = 0
			headings[i] = Vector3.FORWARD
			floor_heights[i] = target_pos.y

			if randf() < hunter_ratio:
				enemy_types[i] = 1
			else:
				enemy_types[i] = 0

			alive_count += 1
			highest_active_index = max(highest_active_index, i + 1)
			current_angle += angle_step
			spawned += 1

func kill_enemy(idx: int) -> void:
	if idx >= 0 and idx < pool_size:
		if states[idx] > 0:
			if multimesh and multimesh.multimesh:
				var mm_inv_xform: Transform3D = multimesh.global_transform.affine_inverse()
				var local_zero: Transform3D = mm_inv_xform * Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))
				multimesh.multimesh.set_instance_transform(idx, local_zero)
				multimesh.multimesh.set_instance_custom_data(idx, Color.TRANSPARENT)

			states[idx] = 0
			positions[idx] = Vector3(0, -1000, 0)
			velocities[idx] = Vector3.ZERO
			aggro_cooldowns[idx] = 0.0
			hit_timers[idx] = 0.0
			attack_cooldowns[idx] = 0.0

			if idx < token_states.size() and token_states[idx] > 0:
				release_combat_token(token_states[idx])

			strike_visual_timers[idx] = 0.0
			if idx < token_states.size():
				token_states[idx] = 0
			headings[idx] = Vector3.FORWARD
			floor_heights[idx] = 0.0
			if idx < index_to_node_map.size():
				index_to_node_map[idx] = null
			alive_count = max(0, alive_count - 1)

			if idx + 1 == highest_active_index:
				var new_highest = 0
				for j in range(idx, -1, -1):
					if states[j] > 0:
						new_highest = j + 1
						break
				highest_active_index = new_highest

func _get_free_node() -> ActiveEnemy:
	for n in node_pool:
		if not n.is_active:
			return n
	return null

# =============================================================================
# 🎯 O(1) DIRECT VECTOR LOOKUP REGISTERS
# =============================================================================
func _find_node_for_idx(idx: int) -> ActiveEnemy:
	if idx >= 0 and idx < index_to_node_map.size():
		return index_to_node_map[idx]
	return null

func set_enemy_pos_vel(idx: int, pos: Vector3, vel: Vector3) -> void:
	if idx >= 0 and idx < pool_size:
		positions[idx] = pos
		velocities[idx] = vel

func set_enemy_state(idx: int, state_val: int) -> void:
	if idx >= 0 and idx < pool_size:
		states[idx] = state_val

# =============================================================================
# ⚔️ BATCH STRIKES ENGINE WITH ABSOLUTE LOCKOUT PROTECTION
# =============================================================================
func register_batch_strikes(indices: PackedInt32Array, payload: RefCounted, combo_step: int) -> void:
	if indices.size() == 0:
		return

	var player_pos := Vector3.ZERO
	var player_forward := Vector3.FORWARD
	if player:
		player_pos = player.global_position
		player_forward = - player.global_transform.basis.z.normalized()

	var damage: float = payload.get("base_damage")

	for i in indices:
		if i < 0 or i >= pool_size: continue
		if states[i] == 0: continue
		if hit_timers[i] > 0.0: continue

		var enemy_pos := positions[i]
		var push_dir := (enemy_pos - player_pos).normalized()
		push_dir.y = 0.0

		if push_dir.length_squared() < 0.001:
			push_dir = player_forward

		if combo_step < 2:
			velocities[i] += push_dir * 14.0
		else:
			velocities[i] += push_dir * 26.0 + Vector3.UP * 7.5

		enemy_types[i] = 1
		aggro_cooldowns[i] = aggro_hijack_duration
		hit_timers[i] = 1.0

		if states[i] == 2:
			var active_node := _find_node_for_idx(i)
			if active_node and is_instance_valid(active_node):
				active_node.velocity = velocities[i]
				if player: active_node.my_target = player
				if active_node.has_method("trigger_hit_flash"): active_node.trigger_hit_flash()

				var health_comp = active_node.health_component
				if health_comp and is_instance_valid(health_comp):
					if health_comp.has_method("take_damage"): health_comp.take_damage(payload)
					elif health_comp.has_method("apply_damage"): health_comp.apply_damage(damage)

					if "current_health" in health_comp: health_array[i] = health_comp.current_health
					elif "health" in health_comp: health_array[i] = health_comp.health
		else:
			if multimesh and multimesh.multimesh:
				multimesh.multimesh.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))

			health_array[i] -= damage
			if health_array[i] <= 0.0:
				kill_enemy(i)

# =============================================================================
# ⚡ DETERMINISTIC PROFILED TICK EXECUTOR
# =============================================================================
func _physics_process(delta: float) -> void:
	if warmup_stage < 2:
		_execute_warmup_tick()
		return

	var frame_parity: int = Engine.get_physics_frames() % 2

	# 1. Elites run every frame to maintain responsive combat reactivity
	for elite in active_execution_pool:
		if elite and is_instance_valid(elite) and elite.is_active:
			elite.managed_tick(delta)

	# 2. Run the heavy swarm simulation mechanics
	if simulation_processor and simulation_processor.has_method("process_swarm_physics"):
		simulation_processor.process_swarm_physics(self, delta)

	# 3. Interleave proximity promotions on EVEN physics frames (30Hz)
	if frame_parity == 0:
		if promotion_processor and promotion_processor.has_method("process_promotions"):
			promotion_processor.process_promotions(self)

	# 4. Spawning logic
	if auto_spawn_enabled and player:
		spawn_timer += delta
		if spawn_timer >= auto_spawn_cooldown:
			spawn_timer = 0.0
			if alive_count < max_concurrent_enemies:
				var batch: int = min(15, max_concurrent_enemies - alive_count)
				spawn_wave_ring(player, randf_range(18.0, 26.0), batch)

	if multimesh and multimesh.multimesh:
		multimesh.multimesh.visible_instance_count = highest_active_index

func _execute_warmup_tick() -> void:
	match warmup_stage:
		0:
			if _prewarm_frames == 2:
				var cam = get_viewport().get_camera_3d()
				if cam and active_enemy_scene:
					_prewarm_dummy = active_enemy_scene.instantiate()
					cam.add_child(_prewarm_dummy)
					_prewarm_dummy.position = Vector3(0.0, 0.0, -1.0)
					_prewarm_dummy.scale = Vector3(0.001, 0.001, 0.001)
			_prewarm_frames -= 1
			if _prewarm_frames <= 0:
				if _prewarm_dummy:
					_prewarm_dummy.queue_free()
					_prewarm_dummy = null
				warmup_stage = 1
		1:
			var limit: int = int(min(_init_index + INIT_BATCH_SIZE, max_active_nodes))
			for i in range(_init_index, limit):
				var enemy_instance = active_enemy_scene.instantiate() as ActiveEnemy
				add_child(enemy_instance)
				node_pool.append(enemy_instance)
			_init_index = limit
			if _init_index >= max_active_nodes:
				warmup_stage = 2
