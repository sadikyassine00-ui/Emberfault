extends Node3D
class_name HordeManager

# =============================================================================
# 🏢 CORE ENGINE BINDINGS
# =============================================================================
@export_group("Core Nodes")
@export var player: Node3D
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

# Active Promoted Scene Node Wrapper Pool
var node_pool: Array[ActiveEnemy] = []

# ⚡ EXECUTION CACHE: Pre-sorted active node wrapper reference array
var active_execution_pool: Array[ActiveEnemy] = []

# Execution Indices
var highest_active_index: int = 0
var alive_count: int = 0

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

	if voxel_terrain and voxel_terrain.has_method("get_voxel_tool"):
		voxel_tool = voxel_terrain.get_voxel_tool()

	if multimesh and multimesh.multimesh:
		multimesh.multimesh.instance_count = pool_size
		for i in range(pool_size):
			multimesh.multimesh.set_instance_color(i, Color.WHITE)

	if active_enemy_scene:
		for i in range(max_active_nodes):
			var enemy_instance = active_enemy_scene.instantiate() as ActiveEnemy
			add_child(enemy_instance)
			node_pool.append(enemy_instance)
	else:
		push_error("⚠️ [CRITICAL ARCH FAILURE] HordeManager is missing its ActiveEnemy PackedScene reference.")

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
			enemy_types[i] = 0
			intents[i] = 0

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

		# 1. Update Knockback Physics Trajectories
		var enemy_pos := positions[i]
		var push_dir := (enemy_pos - player_pos).normalized()
		push_dir.y = 0.0

		if push_dir.length_squared() < 0.001:
			push_dir = player_forward

		if combo_step < 2:
			velocities[i] += push_dir * 14.0
		else:
			velocities[i] += push_dir * 26.0 + Vector3.UP * 7.5
			if enemy_types[i] == 0:
				enemy_types[i] = 1 # Hijack aggro!

		# 2. Sync Damage
		if states[i] == 2:
			# Promoted Enemy: Let its actual HealthComponent resolve and update states
			var active_node = _find_node_for_idx(i)
			if active_node:
				active_node.velocity = velocities[i]

				var health_comp = active_node.get_node_or_null("HealthComponent")
				if health_comp:
					if health_comp.has_method("take_damage"):
						health_comp.take_damage(payload)
					elif health_comp.has_method("apply_damage"):
						health_comp.apply_damage(damage)

					# Read the health value back immediately to keep our array in sync
					if "current_health" in health_comp:
						health_array[i] = health_comp.current_health
					elif "health" in health_comp:
						health_array[i] = health_comp.health
		else:
			# Background MultiMesh: Subtract damage directly inside the master array
			health_array[i] -= damage
			if health_array[i] <= 0.0:
				kill_enemy(i)

func _physics_process(delta: float) -> void:
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
