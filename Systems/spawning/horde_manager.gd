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

@export_group("Promotion Envelope Thresholds")
@export var promote_dist: float = 14.5
@export var demote_dist: float = 22.0

@export_group("Spawning Parameters")
@export var default_hp: float = 30.0
@export var default_damage: float = 1.0

@export_group("Zero-Director Auto Spawner")
@export var auto_spawn_enabled: bool = true
@export var auto_spawn_cooldown: float = 1.0
var spawn_timer: float = 0.0

# Direct C++ Voxel data interface reference
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

# Active Promoted Scene Node Wrapper Pool
var node_pool: Array[ActiveEnemy] = []

# ⚡ EXECUTION CACHE: Pre-sorted active node wrapper reference array
var active_execution_pool: Array[ActiveEnemy] = []

# Execution Indices
var highest_active_index: int = 0
var alive_count: int = 0

# =============================================================================
# ⚙️ AAA WARMUP REGISTERS
# =============================================================================
var warmup_stage: int = 0 # 0: Shader Compile, 1: Spaced Pool Instantiation, 2: Active Gameplay
var _prewarm_dummy: Node3D = null
var _prewarm_frames: int = 2
var _init_index: int = 0
const INIT_BATCH_SIZE: int = 2 # Spawns 2 nodes per frame on startup to prevent hitches

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

	if voxel_terrain and voxel_terrain.has_method("get_voxel_tool"):
		voxel_tool = voxel_terrain.get_voxel_tool()

	if multimesh and multimesh.multimesh:
		multimesh.multimesh.instance_count = 0
		multimesh.multimesh.use_custom_data = true
		multimesh.multimesh.instance_count = pool_size
		for i in range(pool_size):
			multimesh.multimesh.set_instance_color(i, Color.WHITE)
			multimesh.multimesh.set_instance_custom_data(i, Color.TRANSPARENT)

	# ⚡ Pool instantiation loop completely removed from _ready() to avoid entrance hitch!

func get_voxel_ground_height(vt: RefCounted, x: float, start_y: float, z: float, active_offset: float) -> float:
	var xi := int(floor(x))
	var zi := int(floor(z))
	var start_yi := int(floor(start_y))

	var max_range := 12
	var channel = vt.get("channel")

	if channel == 1: # Smooth Terrain (SDF-Based)
		var prev_sdf := 1.0
		for dy in range(max_range, -max_range - 1, -1):
			var cy := start_yi + dy
			var sdf: float = vt.get_voxel_f(Vector3i(xi, cy, zi))
			if sdf < 0.0 and prev_sdf >= 0.0:
				var fraction: float = prev_sdf / (prev_sdf - sdf)
				return float(cy + 1.0 - fraction) + active_offset
			prev_sdf = sdf
	else: # Blocky Terrain (Type-Based)
		for dy in range(max_range, -max_range - 1, -1):
			var cy := start_yi + dy
			var block_type: int = vt.get_voxel(Vector3i(xi, cy, zi))
			if block_type != 0:
				return float(cy + 1.0) + active_offset

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

			if randf() < hunter_ratio:
				enemy_types[i] = 1 # Player-Hunter
			else:
				enemy_types[i] = 0 # Core-Breaker

			alive_count += 1
			highest_active_index = max(highest_active_index, i + 1)
			current_angle += angle_step
			spawned += 1

func kill_enemy(idx: int) -> void:
	if idx >= 0 and idx < pool_size:
		if states[idx] > 0:
			states[idx] = 0
			positions[idx] = Vector3(0, -1000, 0)
			velocities[idx] = Vector3.ZERO
			aggro_cooldowns[idx] = 0.0
			hit_timers[idx] = 0.0
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

func _find_node_for_idx(idx: int) -> ActiveEnemy:
	for n in node_pool:
		if n.is_active and n.linked_idx == idx:
			return n
	return null

# =============================================================================
# ⚡ SAFE MEMORY WRITER API (Bypasses Copy-On-Write PackedArray Traps)
# =============================================================================
func set_enemy_pos_vel(idx: int, pos: Vector3, vel: Vector3) -> void:
	positions[idx] = pos
	velocities[idx] = vel

func set_enemy_state(idx: int, state_val: int) -> void:
	states[idx] = state_val

# =============================================================================
# ⚔️ COMBAT ROUTING ENGINE [SYS-MELEE]
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
		if states[i] == 0:
			continue # Already dead

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

		# Sync Damage and Targets
		if states[i] == 2:
			var active_node = _find_node_for_idx(i)
			if active_node:
				active_node.velocity = velocities[i]

				if player:
					active_node.my_target = player

				if active_node.has_method("trigger_hit_flash"):
					active_node.trigger_hit_flash()

				var health_comp = active_node.get_node_or_null("HealthComponent")
				if health_comp:
					if health_comp.has_method("take_damage"):
						health_comp.take_damage(payload)
					elif health_comp.has_method("apply_damage"):
						health_comp.apply_damage(damage)

					if "current_health" in health_comp:
						health_array[i] = health_comp.current_health
					elif "health" in health_comp:
						health_array[i] = health_comp.health
		else:
			if multimesh and multimesh.multimesh:
				multimesh.multimesh.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))

			health_array[i] -= damage
			if health_array[i] <= 0.0:
				kill_enemy(i)

# =============================================================================
# ⚡ PHYSICS PROCESS & WARMUP EXECUTION
# =============================================================================
func _physics_process(delta: float) -> void:
	# ⚡ AAA PIPELINE CHECK: Restrict gameplay processing until the warmup sequence is complete
	if warmup_stage < 2:
		_execute_warmup_tick()
		return

	if simulation_processor and simulation_processor.has_method("process_swarm_physics"):
		simulation_processor.process_swarm_physics(self, delta)

	if promotion_processor and promotion_processor.has_method("process_promotions"):
		promotion_processor.process_promotions(self)

	if auto_spawn_enabled and player:
		spawn_timer += delta
		if spawn_timer >= auto_spawn_cooldown:
			spawn_timer = 0.0
			if alive_count < max_concurrent_enemies:
				var batch: int = min(15, max_concurrent_enemies - alive_count)
				spawn_wave_ring(player, randf_range(18.0, 26.0), batch)

# =============================================================================
# ⚡ DETERMINISTIC STAGED STATE MACHINE
# =============================================================================
func _execute_warmup_tick() -> void:
	match warmup_stage:
		0: # --- STAGE 0: SHADER PRE-WARMING ---
			if _prewarm_frames == 2:
				var cam = get_viewport().get_camera_3d()
				if cam and active_enemy_scene:
					_prewarm_dummy = active_enemy_scene.instantiate()
					cam.add_child(_prewarm_dummy)
					# Offset directly into camera center-view to force renderer compilation
					_prewarm_dummy.position = Vector3(0.0, 0.0, -1.0)
					_prewarm_dummy.scale = Vector3(0.001, 0.001, 0.001) # Invisible, but drawn

			_prewarm_frames -= 1
			if _prewarm_frames <= 0:
				if _prewarm_dummy:
					_prewarm_dummy.queue_free()
					_prewarm_dummy = null
				warmup_stage = 1
				print("⚡ [SHADER PRE-WARMED] Spectral skull shader compiled & cached on GPU.")

		1: # --- STAGE 1: AMORTIZED POOL INSTANTIATION ---
			if active_enemy_scene:
				var limit: int = int(min(_init_index + INIT_BATCH_SIZE, max_active_nodes))
				for i in range(_init_index, limit):
					var enemy_instance = active_enemy_scene.instantiate() as ActiveEnemy
					add_child(enemy_instance)
					node_pool.append(enemy_instance)
				_init_index = limit

				if _init_index >= max_active_nodes:
					warmup_stage = 2
					print("⚡ [POOL WARMED] %d Node wrappers pooled over multiple frames. Zero ready hitch!" % max_active_nodes)
			else:
				warmup_stage = 2 # Fail-safe if scene reference is missing
