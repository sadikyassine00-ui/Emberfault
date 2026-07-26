@tool
extends Node
class_name DayNightCycleController

# --- SIGNALS ---
signal day_started()
signal dusk_warning(seconds_until_night: float)
signal night_started()
signal dawn_started()
signal wave_cleared()
signal cycle_phase_changed(new_phase: CyclePhase, phase_duration: float)
signal progress_updated(current_phase: CyclePhase, phase_progress: float)

# --- MASTER STATE ENUM ---
enum CyclePhase {
	DAY = 0,    # Peace time: building, mining, expeditions (~120s)
	DUSK = 1,   # Warning phase (~20s)
	NIGHT = 2,  # Siege time: horde defense (Wave-driven)
	DAWN = 3    # Transition phase (~15s)
}

@export_category("Bindings")
@export var director_controller: Node # Node export avoids class-cache indexing race conditions

@export_category("Level Initial Starting Phase Setup")
@export_enum("DAY", "DUSK", "NIGHT", "DAWN") var initial_starting_phase: int = 0:
	set(v):
		initial_starting_phase = v
		if Engine.is_editor_hint():
			progress_updated.emit(v as CyclePhase, 0.0)
			var env_mgr = _find_node_in_tree("EnvironmentManager")
			if env_mgr and env_mgr.has_method("update_environment_live"):
				env_mgr.update_environment_live()

@export_category("Phase Duration Tuning (Seconds)")
@export var day_duration: float = 120.0
@export var dusk_duration: float = 20.0
@export var dawn_duration: float = 15.0
@export var dusk_warning_lead_time: float = 10.0 # Warning emitted 10s before NIGHT

# --- ARCHITECTURAL TRACKING MATRIX ---
var current_phase: CyclePhase = CyclePhase.DAY
var phase_timer: float = 0.0
var current_phase_duration: float = 120.0
var dusk_warning_emitted: bool = false
var tick_accumulator: float = 0.0

func _ready() -> void:
	if not director_controller:
		director_controller = _find_node_in_tree("HordeDirector")
		if not director_controller:
			director_controller = _find_node_in_tree("DirectorStateController")

	if director_controller and "wave_completed" in director_controller:
		var wave_sig: Signal = director_controller.get("wave_completed")
		if wave_sig and not wave_sig.is_connected(_on_director_wave_completed):
			wave_sig.connect(_on_director_wave_completed)

	if not Engine.is_editor_hint():
		_start_phase(clamp(initial_starting_phase, 0, 3) as CyclePhase)
	else:
		progress_updated.emit(clamp(initial_starting_phase, 0, 3) as CyclePhase, 0.0)

func _find_node_in_tree(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var root_node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if root_node:
		return root_node.find_child(node_name, true, false)
	return null

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Throttled ~10Hz progress updates (0.1s interval) for zero-allocation performance
	tick_accumulator += delta
	if tick_accumulator >= 0.1:
		var elapsed_tick: float = tick_accumulator
		tick_accumulator = 0.0

		if current_phase == CyclePhase.NIGHT:
			var night_progress: float = 0.5
			if director_controller:
				var total_quota: int = director_controller.get("total_wave_enemy_quota") if "total_wave_enemy_quota" in director_controller else 0
				var spawned: int = director_controller.get("total_spawned_this_wave") if "total_spawned_this_wave" in director_controller else 0
				if total_quota > 0:
					night_progress = clampf(float(spawned) / float(total_quota), 0.0, 1.0)
			progress_updated.emit(CyclePhase.NIGHT, night_progress)
		else:
			phase_timer -= elapsed_tick
			var progress: float = clampf(1.0 - (phase_timer / current_phase_duration), 0.0, 1.0)
			progress_updated.emit(current_phase, progress)

			# Dusk Warning Check
			if current_phase == CyclePhase.DUSK and not dusk_warning_emitted:
				if phase_timer <= dusk_warning_lead_time:
					dusk_warning_emitted = true
					print("⚠️ [DAY/NIGHT CYCLE] Dusk Warning! Night siege begins in %.0fs!" % phase_timer)
					dusk_warning.emit(phase_timer)

			if phase_timer <= 0.0:
				_advance_cycle_phase()

func _start_phase(new_phase: CyclePhase) -> void:
	current_phase = new_phase
	dusk_warning_emitted = false

	match current_phase:
		CyclePhase.DAY:
			current_phase_duration = day_duration
			phase_timer = day_duration
			print("☀️ [DAY/NIGHT CYCLE] Phase Shift ➔ DAY (Duration: %.0fs - Peace & Building Time)" % current_phase_duration)
			if director_controller and director_controller.has_method("pause_director"):
				director_controller.pause_director()
			day_started.emit()

		CyclePhase.DUSK:
			current_phase_duration = dusk_duration
			phase_timer = dusk_duration
			print("🌆 [DAY/NIGHT CYCLE] Phase Shift ➔ DUSK (Duration: %.0fs - Warning: Night Siege Approaching)" % current_phase_duration)

		CyclePhase.NIGHT:
			current_phase_duration = 0.0 # Wave-driven
			phase_timer = 0.0
			print("🌙 [DAY/NIGHT CYCLE] Phase Shift ➔ NIGHT (Horde Siege Engaged!)")
			if director_controller and director_controller.has_method("pause_director"):
				director_controller.pause_director()
			night_started.emit()

		CyclePhase.DAWN:
			current_phase_duration = dawn_duration
			phase_timer = dawn_duration
			print("🌅 [DAY/NIGHT CYCLE] Phase Shift ➔ DAWN (Duration: %.0fs - Wave Cleared & Reset)" % current_phase_duration)
			if director_controller and director_controller.has_method("pause_director"):
				director_controller.pause_director()
			dawn_started.emit()

	cycle_phase_changed.emit(current_phase, current_phase_duration)

func _advance_cycle_phase() -> void:
	match current_phase:
		CyclePhase.DAY:
			_start_phase(CyclePhase.DUSK)
		CyclePhase.DUSK:
			_start_phase(CyclePhase.NIGHT)
		CyclePhase.NIGHT:
			_start_phase(CyclePhase.DAWN)
		CyclePhase.DAWN:
			_start_phase(CyclePhase.DAY)

func _on_director_wave_completed() -> void:
	if current_phase == CyclePhase.NIGHT:
		print("🏆 [DAY/NIGHT CYCLE] Horde Wave Cleared!")
		wave_cleared.emit()
		_start_phase(CyclePhase.DAWN)
