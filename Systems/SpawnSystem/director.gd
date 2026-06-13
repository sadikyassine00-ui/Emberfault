extends Node
class_name GameDirector

@export_category("Core References")
@export var horde_manager: HordeManager
@export var spawn_manager: SpawnManager

@export_category("Tension Tuning")
@export var max_tension: float = 100.0
@export var tension_growth_rate: float = 15.0 # How fast tension climbs to its target
@export var tension_decay_rate: float = 8.0   # How fast it drops when safe
@export var stress_per_active_enemy: float = 6.0 # 15 enemies = 90 Target Tension
@export var relief_per_kill: float = 12.0     # PUSH BACK! Tension removed per kill

@export_category("Pacing (Wait Times)")
@export var build_up_spawn_rate: float = 2.0
@export var peak_spawn_rate: float = 0.3
@export var breather_duration: float = 8.0

enum Phase { BUILD_UP, PEAK, BREATHER }
var current_phase: Phase = Phase.BUILD_UP
var current_tension: float = 0.0
var breather_timer: float = 0.0

# NEW: We need to remember kills to reward the player
var previous_kill_count: int = 0

func _ready():
	if spawn_manager:
		spawn_manager.set_spawn_rate(build_up_spawn_rate)

func _process(delta):
	if not horde_manager or not spawn_manager: return

	_calculate_tension(delta)
	_evaluate_director_phase(delta)

func _calculate_tension(delta):
	# 1. Check for Kills (The Catharsis / Push Back)
	var current_kills = horde_manager.total_spawned_count - horde_manager.alive_count
	var kills_this_frame = current_kills - previous_kill_count

	if kills_this_frame > 0:
		# Player got a kill! Instantly drop tension!
		current_tension -= (kills_this_frame * relief_per_kill)

	previous_kill_count = current_kills

	# 2. Check Threat Level (The Target Tension)
	var threats_in_face = 0
	for state in horde_manager.states:
		if state == 2:
			threats_in_face += 1

	if threats_in_face > 0:
		# Calculate where the tension *wants* to be based on how crowded the player is
		var target_tension = min(threats_in_face * stress_per_active_enemy, max_tension)

		# Move current tension toward the target tension smoothly
		if current_tension < target_tension:
			current_tension += tension_growth_rate * delta
	else:
		# Nobody is near the player, let tension decay to zero
		current_tension -= tension_decay_rate * delta

	# Clamp to keep math clean
	current_tension = clamp(current_tension, 0.0, max_tension)

func _evaluate_director_phase(delta):
	match current_phase:

		Phase.BUILD_UP:
			if current_tension >= 50.0:
				_transition_to(Phase.PEAK)

		Phase.PEAK:
			# Player failed to keep tension down with kills. They are overwhelmed.
			if current_tension >= 95.0:
				_transition_to(Phase.BREATHER)
			# Player cleared the immediate threat efficiently! Back to build up.
			elif current_tension < 20.0:
				_transition_to(Phase.BUILD_UP)

		Phase.BREATHER:
			breather_timer -= delta
			if breather_timer <= 0.0 and current_tension < 10.0:
				_transition_to(Phase.BUILD_UP)

func _transition_to(new_phase: Phase):
	if current_phase == new_phase: return
	current_phase = new_phase

	match current_phase:
		Phase.BUILD_UP:
			spawn_manager.resume_spawning()
			spawn_manager.set_spawn_rate(build_up_spawn_rate)

		Phase.PEAK:
			spawn_manager.resume_spawning()
			spawn_manager.set_spawn_rate(peak_spawn_rate)

		Phase.BREATHER:
			spawn_manager.pause_spawning()
			breather_timer = breather_duration
