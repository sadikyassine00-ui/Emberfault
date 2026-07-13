class_name CombatBuffer
extends Node

signal strike_impact_frame(combo_step: int)

# --- CACHED COMPONENT REFERENCES ---
var parent: CharacterBody3D
var visual_model: Node3D
var state_machine: AnimationNodeStateMachinePlayback

# --- COMBO & BUFFER STATE REGISTERS ---
var is_attacking: bool = false
var can_buffer: bool = false
var can_instant_cancel: bool = false
var combo_step: int = 0
var combo_buffered: bool = false

# Dynamic Frame Budget Metrics
var current_eval_delay: float = 0.233
var current_total_duration: float = 0.400

# Async Protection Counters & Flags
var runtime_sequence_id: int = 0
var was_eval_window_processed: bool = false

func initialize(p_parent: CharacterBody3D, p_visual_model: Node3D, p_state_machine: AnimationNodeStateMachinePlayback) -> void:
	parent = p_parent
	visual_model = p_visual_model
	state_machine = p_state_machine

func get_mouse_world_position() -> Vector3:
	if not parent: return Vector3.ZERO
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return parent.global_position

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)

	var ground_plane = Plane(Vector3.UP, parent.global_position.y)
	var intersection = ground_plane.intersects_ray(ray_origin, ray_normal)
	if intersection != null:
		return intersection
	else:
		return parent.global_position

func start_attack() -> void:
	if not parent or not visual_model or not state_machine:
		return

	if is_attacking:
		if can_buffer:
			if can_instant_cancel:
				print("⚡ [INSTANT CANCEL] Recovery broken early. Advancing combo chain sequence.")
				_execute_combo_chain()
			else:
				combo_buffered = true
				print("   📥 [BUFFERED] Input queued for active step: %d" % combo_step)
		else:
			print("   ❌ [IGNORED] Input rejected. Player in early swing wind-up.")
		return

	runtime_sequence_id += 1
	var current_sequence_generation = runtime_sequence_id
	was_eval_window_processed = false

	is_attacking = true
	can_buffer = false
	can_instant_cancel = false
	combo_buffered = false

	var target_anim: String = ""
	var active_strike_delay: float = 0.150

	match combo_step:
		0:
			target_anim = "attack_1"
			current_eval_delay = 0.233
			current_total_duration = 0.400
		1:
			target_anim = "attack_2"
			current_eval_delay = 0.233
			current_total_duration = 0.400
		2:
			target_anim = "attack_3"
			active_strike_delay = 0.216
			current_eval_delay = 0.283
			current_total_duration = 0.500

	print("⚔️ [TRIGGERED] CombatBuffer.start_attack() -> Executing: %s | Gen: %d | Step: %d" % [target_anim, current_sequence_generation, combo_step])

	var target_pos = get_mouse_world_position()
	var corrected_target = parent.global_position + (parent.global_position - target_pos)
	corrected_target.y = parent.global_position.y

	if visual_model.global_position.distance_squared_to(corrected_target) > 0.001:
		visual_model.look_at(corrected_target, Vector3.UP)

	if state_machine:
		state_machine.travel(target_anim)

		get_tree().create_timer(active_strike_delay, true, false, false).timeout.connect(func():
			if runtime_sequence_id != current_sequence_generation: return
			can_buffer = true
			print("   🔓 [BUFFER WINDOW OPENED] Input registration active for Gen: %d" % current_sequence_generation)
		)

		get_tree().create_timer(active_strike_delay + 0.016, true, false, false).timeout.connect(func():
			if runtime_sequence_id != current_sequence_generation: return
			strike_impact_frame.emit(combo_step)
		)

		var fail_safe_buffer_delay = current_eval_delay + 0.050
		get_tree().create_timer(fail_safe_buffer_delay, true, false, false).timeout.connect(func():
			if runtime_sequence_id != current_sequence_generation: return
			if not was_eval_window_processed:
				print("⚠️ [FAIL-SAFE ENGAGED] Forcing hardware backup evaluation for Gen: %d." % current_sequence_generation)
				_on_combo_cancel_window_reached()
		)

func _on_combo_cancel_window_reached() -> void:
	if not is_attacking or was_eval_window_processed:
		return

	was_eval_window_processed = true
	var evaluation_generation = runtime_sequence_id

	if combo_buffered:
		print("🔄 [TIMELINE EVENT] Pre-buffered input validated at cancel frame. Chaining forward.")
		_execute_combo_chain()
	else:
		can_instant_cancel = true
		print("⏱️ [TIMELINE EVENT] Recovery entered for Gen: %d. Instant manual cancels unblocked." % evaluation_generation)

		var remaining_recovery = current_total_duration - current_eval_delay
		get_tree().create_timer(remaining_recovery, true, false, false).timeout.connect(func():
			if runtime_sequence_id != evaluation_generation:
				return

			is_attacking = false
			can_buffer = false
			can_instant_cancel = false
			combo_step = 0
			print("🛑 [RESET TO IDLE] Full sequence complete for Gen: %d. State registers flushed." % evaluation_generation)
		)

func _execute_combo_chain() -> void:
	is_attacking = false
	can_buffer = false
	can_instant_cancel = false

	combo_step = 0 if combo_step >= 2 else combo_step + 1
	print("🔄 [CHAINING COMBO] Shifting internal state step register to: %d" % combo_step)
	start_attack()