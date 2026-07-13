extends Node
class_name DirectorStateController

# --- SIGNALS PUMP ---
signal defense_stage_changed(new_stage: DefenseStage)
signal wave_completed()

# --- ENUM STRUCTURES ---
enum DefenseStage {
	PREP = 0, # Vanguard Probing (Low intensity setup)
	SQUEEZE = 1, # Max Capacity Stress Test (High Hunter Flanking)
	APEX_BREACH = 2, # Heavy Armor & Boss Deployments
	EXTERMINATION = 3 # Clean up residual swarmers pool
}

enum EnemyType {
	CORE_BREAKER = 0,
	PLAYER_HUNTER = 1,
	EARTH_SHAKER = 2,
	CORE_CRUSHER = 3
}

@export_category("Core Bindings")
@export var horde_manager: Node
@export var base_core_node: Node3D

@export_category("Dynamic Pacing Config")
@export var tension_panic_threshold: float = 85.0
@export var breathing_window_duration: float = 4.5
@export var breathing_spawn_delay_scalar: float = 2.5

@export_category("Wave Stage Durations")
@export var stage_durations: Array[float] = [30.0, 120.0, 60.0, 0.0]

@export_category("Wave Spawner Cadence")
@export var stage_spawn_intervals: Array[float] = [2.0, 0.8, 1.2, -1.0]
@export var stage_spawn_batch_sizes: Array[int] = [6, 12, 8, 0]
@export var stage_hunter_ratios: Array[float] = [0.15, 0.40, 0.30, 0.0]

# --- ARCHITECTURAL TRACKING MATRIX ---
var current_defense_stage: DefenseStage = DefenseStage.PREP

var stage_timer: float = 0.0
var continuous_spawn_accumulator: float = 0.0
var global_tension: float = 0.0

# Rubber-band pacing states
var breathing_window_active: bool = false
var breathing_window_timer: float = 0.0
var active_spawn_scalar: float = 1.0

func _ready() -> void:
	print("🎬 [PACING ENGINE INITIALIZED] Running Standalone Base Defense Matrix.")
	_initialize_defense_wave()

func _physics_process(delta: float) -> void:
	_calculate_dynamic_tension()
	_evaluate_breathing_windows(delta)

	if current_defense_stage != DefenseStage.EXTERMINATION:
		stage_timer -= delta
		_execute_procedural_spawner_pump(delta)

		if stage_timer <= 0.0:
			_advance_defense_stage()
	else:
		# EXTERMINATION PASS: Victory triggers when the live index flushes completely
		if horde_manager and horde_manager.alive_count == 0:
			set_physics_process(false)
			print("🏆 [PACING ENGINE] Wave Cleared Successfully! All entities wiped.")
			wave_completed.emit()

	# Throttled Telemetry Performance Diagnostics Output
	if Engine.get_process_frames() % 60 == 0:
		_log_pacing_telemetry()

# --- TIMELINE CONTROLLERS ---

func _initialize_defense_wave() -> void:
	current_defense_stage = DefenseStage.PREP
	stage_timer = stage_durations[int(DefenseStage.PREP)]
	continuous_spawn_accumulator = 0.0
	global_tension = 0.0
	breathing_window_active = false
	active_spawn_scalar = 1.0

	if horde_manager and base_core_node:
		horde_manager.current_spawn_type = EnemyType.CORE_BREAKER
		horde_manager.target_hunter_ratio = stage_hunter_ratios[int(DefenseStage.PREP)]
		horde_manager.spawn_wave_ring(base_core_node, 35.0, 20)

	defense_stage_changed.emit(current_defense_stage)

func _advance_defense_stage() -> void:
	var next_stage_idx: int = int(current_defense_stage) + 1
	current_defense_stage = next_stage_idx as DefenseStage
	stage_timer = stage_durations[next_stage_idx]
	continuous_spawn_accumulator = 0.0

	match current_defense_stage:
		DefenseStage.SQUEEZE:
			print("🚨 [TIMELINE SHIFT] Entering Stage 2: THE SQUEEZE. Ramping flank vectors.")
		DefenseStage.APEX_BREACH:
			print("💥 [TIMELINE SHIFT] Entering Stage 3: APEX BREACH. Heavy payloads authorized.")
			_trigger_elite_strike_force()
		DefenseStage.EXTERMINATION:
			print("🧹 [TIMELINE SHIFT] Entering Stage 4: EXTERMINATION. Spawners disabled.")

	defense_stage_changed.emit(current_defense_stage)

# --- AAA ENGAGEMENT MATH ---

func _calculate_dynamic_tension() -> void:
	if not horde_manager: return

	# 1. Pool Capacity Saturation Factor
	var saturation: float = float(horde_manager.alive_count) / float(horde_manager.max_concurrent_enemies)

	# 2. Voxel Spatial Proximity Threat Factor (Allocation-Safe Cache Sweep)
	var proximity_stress: float = 0.0
	if base_core_node and horde_manager.alive_count > 0:
		var core_pos: Vector3 = base_core_node.global_position
		var samples: int = min(horde_manager.alive_count, 12)

		for i in range(samples):
			var dist: float = core_pos.distance_to(horde_manager.positions[i])
			if dist < 15.0:
				proximity_stress += (15.0 - dist) / 15.0

		proximity_stress = (proximity_stress / float(samples)) * 30.0

	# Combine parameters into a responsive intensity curve
	global_tension = min((saturation * 70.0) + proximity_stress, 100.0)

func _evaluate_breathing_windows(delta: float) -> void:
	if global_tension >= tension_panic_threshold and not breathing_window_active:
		breathing_window_active = true
		breathing_window_timer = 0.0
		print("🧼 [ENGAGEMENT] Panic state hit (%.1f%%). Opening safety breathing window." % global_tension)

	if breathing_window_active:
		breathing_window_timer += delta
		active_spawn_scalar = breathing_spawn_delay_scalar

		if breathing_window_timer >= breathing_window_duration and global_tension < tension_panic_threshold:
			breathing_window_active = false
			active_spawn_scalar = 1.0
			print("🔥 [ENGAGEMENT] Safety window closed. Re-engaging standard pacing metrics.")
	else:
		active_spawn_scalar = 1.0

func _execute_procedural_spawner_pump(delta: float) -> void:
	var current_idx: int = int(current_defense_stage)
	var base_interval: float = stage_spawn_intervals[current_idx]

	if not horde_manager or base_interval <= 0.0: return
	if horde_manager.alive_count >= horde_manager.max_concurrent_enemies: return

	continuous_spawn_accumulator += delta
	var calibrated_interval: float = base_interval * active_spawn_scalar

	if continuous_spawn_accumulator >= calibrated_interval:
		continuous_spawn_accumulator = 0.0

		var active_type: int = EnemyType.CORE_BREAKER
		if current_defense_stage == DefenseStage.APEX_BREACH:
			active_type = EnemyType.EARTH_SHAKER if randf() > 0.7 else EnemyType.CORE_BREAKER

		# 3-Argument State Injection Pass
		horde_manager.current_spawn_type = active_type
		horde_manager.target_hunter_ratio = stage_hunter_ratios[current_idx]

		var batch_size: int = stage_spawn_batch_sizes[current_idx]
		horde_manager.spawn_wave_ring(base_core_node, randf_range(32.0, 40.0), batch_size)

func _trigger_elite_strike_force() -> void:
	if not horde_manager or not base_core_node: return

	# 1. Deploy Core-Crusher Structural Boss
	horde_manager.current_spawn_type = EnemyType.CORE_CRUSHER
	horde_manager.target_hunter_ratio = 0.0
	horde_manager.spawn_wave_ring(base_core_node, 45.0, 1)

	# 2. Deploy Voxel Deletion Attendants
	horde_manager.current_spawn_type = EnemyType.EARTH_SHAKER
	horde_manager.target_hunter_ratio = 0.20
	horde_manager.spawn_wave_ring(base_core_node, 40.0, 4)

# --- UTILITIES ---

func _log_pacing_telemetry() -> void:
	var stage_name: String = DefenseStage.keys()[current_defense_stage]
	var flag: String = "[BREATHING]" if breathing_window_active else "[NORMAL]"
	var live_count: int = horde_manager.alive_count if horde_manager else 0

	print("📊 [STAGE: %s] | Tension: %.1f%% %s | Clock: %.1fs | Swarmers: %d" % [
		stage_name, global_tension, flag, stage_timer, live_count
	])
