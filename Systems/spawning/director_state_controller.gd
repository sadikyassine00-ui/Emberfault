extends Node
class_name DirectorStateController

# --- DECOUPLED SIGNALS ---
signal phase_changed(new_phase: DefenseStage, phase_duration: float)
signal spawn_requested(enemy_type: EnemyType, batch_size: int, hunter_ratio: float)
signal breathing_state_changed(is_breathing: bool)

# Legacy / Backward-compatibility signals
signal defense_stage_changed(new_stage: DefenseStage)
signal wave_completed()

# --- ENUM STRUCTURES ---
enum DefenseStage {
	PREP = 0, # Early trickle spawns (10% wave quota)
	SQUEEZE = 1, # Gradual swarm/hunter ramp-up with stress breather (60% wave quota)
	APEX_BREACH = 2, # Maximum intensity & heavy units (30% wave quota)
	EXTERMINATION = 3 # Spawns halted, completes when total quota is spawned and all active units die
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

@export_category("Wave Total Quota Management")
@export var total_wave_enemy_quota: int = 200 # Total enemies spawned across the ENTIRE wave (start to finish)
@export var stage_quota_ratios: Array[float] = [0.10, 0.60, 0.30, 0.0] # Stage quota allocation ratios

@export_category("Dynamic Pacing & Stress Tuning")
@export var stress_panic_threshold: float = 0.85 # N_active / N_max (85%)
@export var breathing_window_duration: float = 6.0 # 6 second breather window
@export var tick_interval: float = 0.2 # 5Hz decision tick frequency (0.2s)

@export_category("Wave Stage Durations")
@export var stage_durations: Array[float] = [30.0, 120.0, 60.0, 0.0]

@export_category("PREP Phase Trickle Cadence")
@export var prep_hunter_ratio: float = 0.0 # 0% hunters during PREP

@export_category("Gradual SQUEEZE Ramp-up Cadence")
@export var squeeze_min_interval: float = 2.5 # Start of SQUEEZE: spawn every 2.5s
@export var squeeze_max_interval: float = 0.8 # End of SQUEEZE: spawn every 0.8s
@export var squeeze_min_batch_size: int = 2 # Start of SQUEEZE: 2 units per batch
@export var squeeze_max_batch_size: int = 8 # End of SQUEEZE: 8 units per batch
@export var squeeze_min_hunter_ratio: float = 0.15 # Start of SQUEEZE: 15% hunters
@export var squeeze_max_hunter_ratio: float = 0.40 # End of SQUEEZE: 40% hunters

@export_category("APEX BREACH Cadence")
@export var apex_spawn_interval: float = 1.0
@export var apex_batch_size: int = 8
@export var apex_hunter_ratio: float = 0.30

@export_category("Automation Controls")
@export var auto_start: bool = false # Set to false so WaveHUD pre-start timer controls startup

# --- ARCHITECTURAL TRACKING MATRIX ---
var current_defense_stage: DefenseStage = DefenseStage.PREP

var stage_timer: float = 0.0
var continuous_spawn_accumulator: float = 0.0
var global_tension: float = 0.0
var active_unit_density: float = 0.0
var is_wave_running: bool = false

# Quota tracking registers
var total_spawned_this_wave: int = 0
var stage_spawned_count: int = 0
var stage_target_quota: int = 0

# Rubber-band stress breather states
var breathing_window_active: bool = false
var breathing_window_timer: float = 0.0
var tick_accumulator: float = 0.0
var telemetry_tick_counter: int = 0

func _ready() -> void:
	# Disable standalone HordeManager spawner immediately on ready
	if horde_manager and "auto_spawn_enabled" in horde_manager:
		horde_manager.auto_spawn_enabled = false

	set_physics_process(false)
	if auto_start:
		start_wave()

func pause_director() -> void:
	is_wave_running = false
	set_physics_process(false)

func start_wave() -> void:
	is_wave_running = true
	_initialize_defense_wave()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	tick_accumulator += delta

	# Throttled decision ticks at ~5Hz (0.2s interval)
	if tick_accumulator < tick_interval:
		return

	var elapsed_tick: float = tick_accumulator
	tick_accumulator = 0.0
	telemetry_tick_counter += 1

	_calculate_dynamic_tension()
	_evaluate_breathing_windows(elapsed_tick)

	if current_defense_stage != DefenseStage.EXTERMINATION:
		stage_timer -= elapsed_tick
		_execute_procedural_spawner_pump(elapsed_tick)

		# 1. Total Wave Quota Check: If entire wave quota is met, jump straight to EXTERMINATION
		if total_spawned_this_wave >= total_wave_enemy_quota:
			_set_extermination_stage()
		# 2. Stage Completion Check: Advance stage when stage quota is reached or stage duration expires
		elif stage_spawned_count >= stage_target_quota or stage_timer <= 0.0:
			_advance_defense_stage()
	else:
		# EXTERMINATION PASS: Complete wave when all active spawned units are eliminated
		var live_count: int = horde_manager.alive_count if (horde_manager and "alive_count" in horde_manager) else 0
		if live_count == 0:
			set_physics_process(false)
			print("🏆 [PACING DIRECTOR] Wave Cleared! All %d spawned enemies eliminated." % total_spawned_this_wave)
			wave_completed.emit()

	# Throttled Telemetry Output (~every 2 seconds)
	if telemetry_tick_counter % 10 == 0:
		_log_pacing_telemetry()

# --- TIMELINE CONTROLLERS ---

func _initialize_defense_wave() -> void:
	current_defense_stage = DefenseStage.PREP
	stage_timer = stage_durations[int(DefenseStage.PREP)]
	continuous_spawn_accumulator = 0.0
	global_tension = 0.0
	active_unit_density = 0.0
	breathing_window_active = false
	telemetry_tick_counter = 0

	# Reset Wave & Stage Quota counters
	total_spawned_this_wave = 0
	stage_spawned_count = 0
	stage_target_quota = int(round(float(total_wave_enemy_quota) * stage_quota_ratios[0]))

	# PREP Phase: Disable standalone HordeManager spawner
	if horde_manager:
		if "auto_spawn_enabled" in horde_manager:
			horde_manager.auto_spawn_enabled = false
		if "current_spawn_type" in horde_manager:
			horde_manager.current_spawn_type = EnemyType.CORE_BREAKER
		if "target_hunter_ratio" in horde_manager:
			horde_manager.target_hunter_ratio = prep_hunter_ratio

	print("🎬 [PACING DIRECTOR] Wave Initialized! Total Wave Quota: %d enemies (PREP Stage Quota: %d)" % [total_wave_enemy_quota, stage_target_quota])
	phase_changed.emit(current_defense_stage, stage_timer)
	defense_stage_changed.emit(current_defense_stage)

func _advance_defense_stage() -> void:
	var next_stage_idx: int = int(current_defense_stage) + 1
	if next_stage_idx > int(DefenseStage.EXTERMINATION):
		return

	current_defense_stage = next_stage_idx as DefenseStage
	stage_timer = stage_durations[next_stage_idx]
	continuous_spawn_accumulator = 0.0
	stage_spawned_count = 0

	if next_stage_idx < stage_quota_ratios.size():
		stage_target_quota = int(round(float(total_wave_enemy_quota) * stage_quota_ratios[next_stage_idx]))
	else:
		stage_target_quota = 0

	# Disable breathing windows on APEX BREACH or EXTERMINATION
	if current_defense_stage == DefenseStage.APEX_BREACH or current_defense_stage == DefenseStage.EXTERMINATION:
		if breathing_window_active:
			breathing_window_active = false
			breathing_state_changed.emit(false)

	match current_defense_stage:
		DefenseStage.SQUEEZE:
			print("🚨 [PACING DIRECTOR] Phase Shift ➔ Stage 2: SQUEEZE (Quota: %d enemies, Duration: %.0fs)" % [stage_target_quota, stage_timer])
		DefenseStage.APEX_BREACH:
			print("💥 [PACING DIRECTOR] Phase Shift ➔ Stage 3: APEX BREACH (Quota: %d enemies, Heavy Payloads Authorized)" % stage_target_quota)
			_trigger_elite_strike_force()
		DefenseStage.EXTERMINATION:
			print("🧹 [PACING DIRECTOR] Phase Shift ➔ Stage 4: EXTERMINATION (Spawns Halted. Wave Total Spawned: %d/%d)" % [total_spawned_this_wave, total_wave_enemy_quota])

	phase_changed.emit(current_defense_stage, stage_timer)
	defense_stage_changed.emit(current_defense_stage)

func _set_extermination_stage() -> void:
	if current_defense_stage == DefenseStage.EXTERMINATION:
		return
	current_defense_stage = DefenseStage.EXTERMINATION
	stage_timer = 0.0
	continuous_spawn_accumulator = 0.0
	stage_spawned_count = 0
	stage_target_quota = 0
	if breathing_window_active:
		breathing_window_active = false
		breathing_state_changed.emit(false)
	print("🧹 [PACING DIRECTOR] Wave Quota Hit (%d/%d)! Transitioning to EXTERMINATION." % [total_spawned_this_wave, total_wave_enemy_quota])
	phase_changed.emit(current_defense_stage, 0.0)
	defense_stage_changed.emit(current_defense_stage)

# --- PACING & STRESS EVALUATION ---

func _calculate_dynamic_tension() -> void:
	if not horde_manager:
		active_unit_density = 0.0
		global_tension = 0.0
		return

	var alive: int = horde_manager.alive_count if "alive_count" in horde_manager else 0
	var max_units: int = horde_manager.max_concurrent_enemies if "max_concurrent_enemies" in horde_manager else 1

	active_unit_density = float(alive) / float(max_units) if max_units > 0 else 0.0

	var proximity_stress: float = 0.0
	if base_core_node and alive > 0 and "positions" in horde_manager:
		var core_pos: Vector3 = base_core_node.global_position
		var samples: int = min(alive, 12)

		for i in range(samples):
			var dist: float = core_pos.distance_to(horde_manager.positions[i])
			if dist < 15.0:
				proximity_stress += (15.0 - dist) / 15.0

		proximity_stress = (proximity_stress / float(samples)) * 30.0

	global_tension = min((active_unit_density * 70.0) + proximity_stress, 100.0)

func _evaluate_breathing_windows(elapsed: float) -> void:
	if current_defense_stage == DefenseStage.APEX_BREACH or current_defense_stage == DefenseStage.EXTERMINATION or current_defense_stage == DefenseStage.PREP:
		if breathing_window_active:
			breathing_window_active = false
			breathing_state_changed.emit(false)
		return

	if active_unit_density >= stress_panic_threshold and not breathing_window_active:
		breathing_window_active = true
		breathing_window_timer = 0.0
		print("🧼 [STRESS DIRECTOR] Stress panic threshold hit (%.1f%% active density). Opening %.1fs safety breather window." % [active_unit_density * 100.0, breathing_window_duration])
		breathing_state_changed.emit(true)

	if breathing_window_active:
		breathing_window_timer += elapsed
		if breathing_window_timer >= breathing_window_duration and active_unit_density < stress_panic_threshold:
			breathing_window_active = false
			print("🔥 [STRESS DIRECTOR] Safety breather window ended. Resuming spawn pressure.")
			breathing_state_changed.emit(false)

func _execute_procedural_spawner_pump(elapsed: float) -> void:
	if current_defense_stage == DefenseStage.EXTERMINATION:
		return

	if breathing_window_active:
		return

	if not horde_manager:
		return

	# Calculate remaining wave and stage quotas
	var remaining_wave_quota: int = max(0, total_wave_enemy_quota - total_spawned_this_wave)
	var remaining_stage_quota: int = max(0, stage_target_quota - stage_spawned_count)

	if remaining_wave_quota <= 0 or remaining_stage_quota <= 0:
		return

	var alive: int = horde_manager.alive_count if "alive_count" in horde_manager else 0
	var max_units: int = horde_manager.max_concurrent_enemies if "max_concurrent_enemies" in horde_manager else 0
	if alive >= max_units:
		return

	var current_interval: float = 1.0
	var current_batch_size: int = 1
	var hunter_ratio: float = 0.0
	var active_type: int = EnemyType.CORE_BREAKER

	if current_defense_stage == DefenseStage.PREP:
		var prep_duration: float = stage_durations[int(DefenseStage.PREP)]
		current_interval = prep_duration / maxf(float(stage_target_quota), 1.0)
		current_batch_size = 1
		hunter_ratio = prep_hunter_ratio
		active_type = EnemyType.CORE_BREAKER

	elif current_defense_stage == DefenseStage.SQUEEZE:
		var total_duration: float = stage_durations[int(DefenseStage.SQUEEZE)]
		var progress: float = clampf(1.0 - (stage_timer / total_duration), 0.0, 1.0)

		current_interval = lerpf(squeeze_min_interval, squeeze_max_interval, progress)
		current_batch_size = int(round(lerpf(float(squeeze_min_batch_size), float(squeeze_max_batch_size), progress)))
		hunter_ratio = lerpf(squeeze_min_hunter_ratio, squeeze_max_hunter_ratio, progress)
		active_type = EnemyType.CORE_BREAKER

	elif current_defense_stage == DefenseStage.APEX_BREACH:
		current_interval = apex_spawn_interval
		current_batch_size = apex_batch_size
		hunter_ratio = apex_hunter_ratio
		active_type = EnemyType.EARTH_SHAKER if randf() > 0.7 else EnemyType.CORE_BREAKER

	continuous_spawn_accumulator += elapsed
	if continuous_spawn_accumulator >= current_interval:
		continuous_spawn_accumulator = 0.0

		# Enforce strict quota limits
		var actual_batch: int = min(current_batch_size, remaining_wave_quota, remaining_stage_quota, max_units - alive)
		if actual_batch <= 0:
			return

		spawn_requested.emit(active_type, actual_batch, hunter_ratio)

		if "current_spawn_type" in horde_manager:
			horde_manager.current_spawn_type = active_type
		if "target_hunter_ratio" in horde_manager:
			horde_manager.target_hunter_ratio = hunter_ratio

		if base_core_node and horde_manager.has_method("spawn_wave_ring"):
			horde_manager.spawn_wave_ring(base_core_node, randf_range(32.0, 40.0), actual_batch)

		total_spawned_this_wave += actual_batch
		stage_spawned_count += actual_batch

		var type_name: String = EnemyType.keys()[active_type]
		print("⚡ [SPAWNER PUMP] Spawned %d x %s | Stage Quota: %d/%d | Total Wave Spawned: %d/%d" % [actual_batch, type_name, stage_spawned_count, stage_target_quota, total_spawned_this_wave, total_wave_enemy_quota])

func _trigger_elite_strike_force() -> void:
	if not horde_manager or not base_core_node:
		return

	var remaining: int = max(0, total_wave_enemy_quota - total_spawned_this_wave)
	if remaining <= 0:
		return

	print("👑 [ELITE STRIKE] Deploying Structural Bosses & Attendants!")

	# Core Crusher (1)
	spawn_requested.emit(EnemyType.CORE_CRUSHER, 1, 0.0)
	if "current_spawn_type" in horde_manager:
		horde_manager.current_spawn_type = EnemyType.CORE_CRUSHER
	if "target_hunter_ratio" in horde_manager:
		horde_manager.target_hunter_ratio = 0.0
	if horde_manager.has_method("spawn_wave_ring"):
		horde_manager.spawn_wave_ring(base_core_node, 45.0, 1)

	total_spawned_this_wave += 1
	stage_spawned_count += 1

	# Earth Shakers (up to 4)
	var shaker_count: int = min(4, total_wave_enemy_quota - total_spawned_this_wave)
	if shaker_count > 0:
		spawn_requested.emit(EnemyType.EARTH_SHAKER, shaker_count, 0.20)
		if "current_spawn_type" in horde_manager:
			horde_manager.current_spawn_type = EnemyType.EARTH_SHAKER
		if "target_hunter_ratio" in horde_manager:
			horde_manager.target_hunter_ratio = 0.20
		if horde_manager.has_method("spawn_wave_ring"):
			horde_manager.spawn_wave_ring(base_core_node, 40.0, shaker_count)

		total_spawned_this_wave += shaker_count
		stage_spawned_count += shaker_count

# --- UTILITIES ---

func _log_pacing_telemetry() -> void:
	var stage_name: String = DefenseStage.keys()[current_defense_stage]
	var flag: String = "[BREATHING]" if breathing_window_active else "[NORMAL]"
	var live_count: int = horde_manager.alive_count if (horde_manager and "alive_count" in horde_manager) else 0
	var max_units: int = horde_manager.max_concurrent_enemies if (horde_manager and "max_concurrent_enemies" in horde_manager) else 0

	print("📊 [PACING TELEMETRY] Stage: %s | Stage Quota: %d/%d | Total Wave: %d/%d | Swarm: %d/%d %s" % [
		stage_name, stage_spawned_count, stage_target_quota, total_spawned_this_wave, total_wave_enemy_quota, live_count, max_units, flag
	])
