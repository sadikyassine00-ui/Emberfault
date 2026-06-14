extends CanvasLayer

@export var director: GameDirector
@export var horde_manager: HordeManager

@onready var debug_label: Label = $Label

func _process(_delta):
	# Fail-safe just in case things aren't hooked up yet
	if not director or not horde_manager or not debug_label: return

	# 1. Translate the Director's Phase into readable text
	var phase_name = ""
	match director.current_phase:
		0: phase_name = "Phase A [BUILD UP]"
		1: phase_name = "Phase B [PEAK SWARM]"
		2: phase_name = "Phase C [BREATHER]"

	var tension = director.current_tension

	# 2. Calculate Swarm Stats
	var alive = horde_manager.alive_count
	var spawned = horde_manager.total_spawned_count
	var kills = spawned - alive # Simple math: if they spawned but aren't alive, they are dead!

	# Count how many enemies are currently "Real Nodes" (State 2)
	var promoted_count = 0
	for s in horde_manager.states:
		if s == 2: promoted_count += 1

	var max_swarm = horde_manager.max_concurrent_enemies
	var max_nodes = horde_manager.max_active_nodes
	var wave_total = horde_manager.total_enemies_in_wave

	# 3. Build the UI Text
	var text = "=== AI DIRECTOR BRAIN ===\n"
	text += "Current Phase: %s\n" % phase_name

	# Show tension with one decimal point
	text += "Tension Level: %.1f / 100.0\n" % tension

	# Only show the breather timer if we are actually resting
	if director.current_phase == 2:
		text += "Safe Time Left: %.1f sec\n" % director.breather_timer
	else:
		text += "\n" # Spacer

	text += "=== SWARM METRICS ===\n"
	text += "Enemies Killed: %d\n" % kills
	text += "Alive on Map: %d / %d\n" % [alive, max_swarm]
	text += "Promoted (Close Threat): %d / %d\n" % [promoted_count, max_nodes]
	text += "Wave Progress: %d / %d\n" % [spawned, wave_total]

	# Update the label
	debug_label.text = text
