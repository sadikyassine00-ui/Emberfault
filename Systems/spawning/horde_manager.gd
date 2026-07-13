extends Node3D
class_name HordeManager

# =============================================================================
# 🏢 CORE ENGINE BINDINGS
# =============================================================================
@export_group("Core Nodes")
@export var player: Node3D
@export var base_core: Node3D
@export var multimesh: MultiMeshInstance3D
@export var active_enemy_scene: PackedScene
@export var simulation_processor: SwarmSimulationProcessor

@export_group("Horde Framework Settings")
@export var pool_size: int = 1000
@export var max_concurrent_enemies: int = 90
@export var base_speed: float = 4.5
@export var max_active_nodes: int = 15

@export_group("Promotion Envelope Thresholds")
@export var promote_dist: float = 14.5
@export var demote_dist: float = 22.0

# =============================================================================
# 📊 EXPOSED BASELINE BALANCING MATRIX (DAY 1, SECTOR 1)
# =============================================================================
@export_group("Base Archetype Baseline Balances")

@export_subgroup("0: Core-Breaker (Gold)")
@export var breaker_base_hp: float = 30.0
@export var breaker_base_dmg: float = 0.5

@export_subgroup("1: Player-Hunter (Red)")
@export var hunter_base_hp: float = 45.0
@export var hunter_base_dmg: float = 8.0

@export_subgroup("2: Earth-Shaker (Purple)")
@export var shaker_base_hp: float = 140.0
@export var shaker_base_dmg: float = 25.0

# =============================================================================
# 📈 HORDE DIFFICULTY SCALING COEFFICIENTS
# =============================================================================
@export_group("Timeline Engine State")
@export_range(1, 3) var current_sector: int = 1
@export_range(1, 4) var current_day: int = 1

@export_group("Horde Attribute Growth Scales")
@export var hp_growth_per_day: float = 0.08
@export var dmg_growth_per_day: float = 0.05
@export var sector_difficulty_multiplier: float = 1.35

@export_group("Wave Composition Ratios (Auto-Clamped to 100% Total)")
@export_range(0.0, 100.0, 1.0) var pct_core_breakers: float = 70.0:
	set(val):
		pct_core_breakers = val
		_clamp_wave_percentages(0)

@export_range(0.0, 100.0, 1.0) var pct_player_hunters: float = 20.0:
	set(val):
		pct_player_hunters = val
		_clamp_wave_percentages(1)

@export_range(0.0, 100.0, 1.0) var pct_earth_shakers: float = 10.0:
	set(val):
		pct_earth_shakers = val
		_clamp_wave_percentages(2)

@export_group("Visual Archetype Assets")
@export var color_core_breaker: Color = Color.GOLD
@export var color_player_hunter: Color = Color.CRIMSON
@export var color_earth_shaker: Color = Color.PURPLE

# =============================================================================
# 💾 FLAT MEMORY DATA ARRAYS (ZERO RUN-TIME HEAP CHURN)
# =============================================================================
var positions: PackedVector3Array
var velocities: PackedVector3Array
var states: PackedInt32Array # 0 = Dead | 1 = Background Swarm | 2 = Promoted Actor
var intents: PackedInt32Array # 0 = Targets Player | 1 = Targets Base Core
var enemy_types: PackedInt32Array # 0 = Core-Breaker | 1 = Player-Hunter | 2 = Earth-Shaker
var speed_variances: PackedFloat32Array
var health_array: PackedFloat32Array
var damage_array: PackedFloat32Array
var preferred_distances_sq: PackedFloat32Array
var orbital_speeds: PackedFloat32Array

var current_spawn_type: int = 0
var target_hunter_ratio: float = 0.25

# Tracking registers
var alive_count: int = 0
var highest_active_index: int = 0

var node_pool: Array[Node3D] = []
var promotion_processor: HordePromotionProcessor

# =============================================================================
# ⚙️ SYSTEM LIFECYCLE ENGINE PROCEDURES
# =============================================================================
func _ready() -> void:
	promotion_processor = HordePromotionProcessor.new()
	add_child(promotion_processor)

	if not simulation_processor:
		simulation_processor = SwarmSimulationProcessor.new()
		add_child(simulation_processor)

	if not multimesh:
		multimesh = get_node_or_null("MultiMeshInstance3D") as MultiMeshInstance3D

	_initialize_matrices()
	_initialize_node_pool()

func _initialize_matrices() -> void:
	positions.resize(pool_size)
	velocities.resize(pool_size)
	states.resize(pool_size)
	intents.resize(pool_size)
	enemy_types.resize(pool_size)
	speed_variances.resize(pool_size)
	health_array.resize(pool_size)
	damage_array.resize(pool_size)
	preferred_distances_sq.resize(pool_size)
	orbital_speeds.resize(pool_size)

	states.fill(0)

	if multimesh and multimesh.multimesh:
		multimesh.custom_aabb = AABB(Vector3(-10000, -10000, -10000), Vector3(20000, 20000, 20000))
		multimesh.multimesh.instance_count = pool_size
		multimesh.multimesh.visible_instance_count = 0

func _initialize_node_pool() -> void:
	if not active_enemy_scene:
		return
	for i in range(max_active_nodes):
		var node = active_enemy_scene.instantiate()
		add_child(node)
		if node.has_method("deactivate"):
			node.deactivate()
		node_pool.append(node)

func _physics_process(delta: float) -> void:
	if alive_count > 0:
		if simulation_processor:
			simulation_processor.process_swarm_physics(self, delta)
		if promotion_processor:
			promotion_processor.process_promotions(self)

# =============================================================================
# 🌊 HORDE LOGIC MANAGEMENT PIPELINES
# =============================================================================
func spawn_wave_ring(target: Node3D, radius: float, count: int) -> void:
	if alive_count >= max_concurrent_enemies or not target:
		return

	var actual_spawn_count: int = min(count, max_concurrent_enemies - alive_count)
	var target_pos: Vector3 = target.global_position
	var angle_step: float = (PI * 2.0) / float(actual_spawn_count)
	var current_angle: float = randf() * PI * 2.0

	# Pre-compute progression scaling multipliers
	var elapsed_days: int = ((current_sector - 1) * 4) + (current_day - 1)
	var day_hp_mod: float = 1.0 + (elapsed_days * hp_growth_per_day)
	var day_dmg_mod: float = 1.0 + (elapsed_days * dmg_growth_per_day)
	var sector_mod: float = pow(sector_difficulty_multiplier, current_sector - 1)

	var final_hp_multiplier: float = day_hp_mod * sector_mod
	var final_dmg_multiplier: float = day_dmg_mod * sector_mod

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

			# =============================================================================
			# ⚡ PACING ENGINE ROUTING
			# =============================================================================
			var type_index: int = current_spawn_type

			# If spawning a standard swarm unit, apply the dynamic hunter ratio split
			if type_index == 0 and randf() < target_hunter_ratio:
				type_index = 1 # Divert vector targeting directly to player transform

			var chosen_color: Color = color_core_breaker
			var unscaled_hp: float = breaker_base_hp
			var unscaled_dmg: float = breaker_base_dmg
			intents[i] = 1 # Default target path: Central Core

			# Resolve specific attributes based on the final determined type
			if type_index == 0:
				type_index = 0
				intents[i] = 1
				chosen_color = color_core_breaker
				unscaled_hp = breaker_base_hp
				unscaled_dmg = breaker_base_dmg
			elif type_index == 1:
				intents[i] = 0 # Divert pathing matrix to player
				chosen_color = color_player_hunter
				unscaled_hp = hunter_base_hp
				unscaled_dmg = hunter_base_dmg
			elif type_index == 2:
				intents[i] = 1
				chosen_color = color_earth_shaker
				unscaled_hp = shaker_base_hp
				unscaled_dmg = shaker_base_dmg

			enemy_types[i] = type_index

			# Apply calculated scaling to the inspector-defined baseline values
			health_array[i] = unscaled_hp * final_hp_multiplier
			damage_array[i] = unscaled_dmg * final_dmg_multiplier

			if multimesh and multimesh.multimesh:
				multimesh.multimesh.set_instance_color(i, chosen_color)

			alive_count += 1
			highest_active_index = max(highest_active_index, i + 1)
			current_angle += angle_step
			spawned += 1

func kill_enemy(idx: int) -> void:
	if states[idx] == 0:
		return

	states[idx] = 0
	alive_count -= 1

	var associated_node = _find_node_for_idx(idx)
	if associated_node and associated_node.has_method("deactivate"):
		associated_node.deactivate()

	if idx == highest_active_index - 1:
		while highest_active_index > 0 and states[highest_active_index - 1] == 0:
			highest_active_index -= 1

	positions[idx] = Vector3(0, -1000, 0)
	if multimesh and multimesh.multimesh:
		multimesh.multimesh.set_instance_transform(idx, Transform3D(Basis(), positions[idx]))

# =============================================================================
# 🗜️ INTERNAL MATH RECTIFICATION UTILITIES
# =============================================================================
func _clamp_wave_percentages(last_modified: int) -> void:
	var total: float = pct_core_breakers + pct_player_hunters + pct_earth_shakers
	if total > 100.0:
		var overflow: float = total - 100.0
		match last_modified:
			0:
				if pct_player_hunters >= overflow: pct_player_hunters -= overflow
				else:
					overflow -= pct_player_hunters
					pct_player_hunters = 0.0
					pct_earth_shakers = max(0.0, pct_earth_shakers - overflow)
			1:
				if pct_core_breakers >= overflow: pct_core_breakers -= overflow
				else:
					overflow -= pct_core_breakers
					pct_core_breakers = 0.0
					pct_earth_shakers = max(0.0, pct_earth_shakers - overflow)
			2:
				if pct_core_breakers >= overflow: pct_core_breakers -= overflow
				else:
					overflow -= pct_core_breakers
					pct_core_breakers = 0.0
					pct_player_hunters = max(0.0, pct_player_hunters - overflow)

func _get_free_node() -> Node3D:
	for n in node_pool:
		if not n.is_active: return n
	return null

func _find_node_for_idx(idx: int) -> Node3D:
	for n in node_pool:
		if n.is_active and n.linked_idx == idx: return n
	return null

## Place this function cleanly inside your HordeManager.gd script

func register_batch_strikes(indices: PackedInt32Array, payload: RefCounted, combo_index: int) -> void:
	if indices.size() == 0 or not player:
		return

	var player_pos: Vector3 = player.global_position
	var base_damage: float = payload.get("base_damage")

	for idx in indices:
		if states[idx] == 0: continue

		health_array[idx] -= base_damage

		# Inject physics displacement
		var enemy_pos: Vector3 = positions[idx]
		var knockback_dir := (enemy_pos - player_pos).normalized()
		knockback_dir.y = 0.0

		# AAA TWEAK: Reduce light attack knockback to keep units within your follow-up strike zone
		var knockback_force: float = 5.5 if combo_index < 2 else 24.0
		velocities[idx] += knockback_dir * knockback_force

		if combo_index == 2:
			intents[idx] = 0 # Attack 3 Aggro Hijack

		# 4. Synchronize data records directly to live promoted wrapper nodes if active
		var active_node = _find_node_for_idx(idx)
		if active_node:
			var health_comp = active_node.get_node_or_null("HealthComponent")
			if health_comp:
				if "current_health" in health_comp:
					health_comp.current_health = health_array[idx]
				elif "health" in health_comp:
					health_comp.health = health_array[idx]

			# Call hit reaction animation updates on the active 3D actor scene
			if active_node.has_method("apply_hit_stagger_anim"):
				active_node.apply_hit_stagger_anim()

		# 5. Immediate structural death evaluation check
		if health_array[idx] <= 0.0:
			kill_enemy(idx)
