class_name CombatBuffer
extends Node

signal strike_impact_frame(combo_step: int)

# --- CACHED COMPONENT REFERENCES ---
var parent: CharacterBody3D
var visual_model: Node3D
var state_machine: AnimationNodeStateMachinePlayback

# --- EXPORTED LINKS & TUNING ---
@export var terrain_manager: Node = null
@export var shatter_particle_emitter: GPUParticles3D = null

# --- AUDIO POOLS ---
# Optional swing/whoosh SFX when attacking thin air
@export var swing_sfx_pool: Array[AudioStream] = []

# Enemy Impact SFX Pools (Triggered ONLY when ShapeCast3D / Hitbox connects with an enemy)
@export var hit_sfx_attack_1_pool: Array[AudioStream] = [
	preload("res://systems/audio/SFX/enemy_hit_1.wav")
]
@export var hit_sfx_attack_2_pool: Array[AudioStream] = [
	preload("res://systems/audio/SFX/enemy_hit_2.wav")
]
@export var hit_sfx_attack_3_pool: Array[AudioStream] = [
	preload("res://systems/audio/SFX/enemy_hit_3.wav")
]

@export var bedrock_voxel_id: int = 2
@export var shatter_width: int = 3
@export var shatter_depth: int = 2

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

# Locked Attack Vector Tracking
var current_attack_direction: Vector3 = Vector3.FORWARD

func initialize(p_parent: CharacterBody3D, p_visual_model: Node3D, p_state_machine: AnimationNodeStateMachinePlayback) -> void:
	parent = p_parent
	visual_model = p_visual_model
	state_machine = p_state_machine

	if not terrain_manager and is_inside_tree():
		terrain_manager = get_tree().current_scene.find_child("TerrainManager", true, false)

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
				_execute_combo_chain()
			else:
				combo_buffered = true
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

	var target_pos = get_mouse_world_position()
	var corrected_target = parent.global_position + (parent.global_position - target_pos)
	corrected_target.y = parent.global_position.y

	var look_dir = (corrected_target - parent.global_position)
	look_dir.y = 0.0
	if look_dir.length_squared() > 0.001:
		current_attack_direction = look_dir.normalized()
	else:
		current_attack_direction = Vector3.FORWARD

	if visual_model.global_position.distance_squared_to(corrected_target) > 0.001:
		visual_model.look_at(corrected_target, Vector3.UP)

	if state_machine:
		state_machine.travel(target_anim)

		get_tree().create_timer(active_strike_delay, true, false, false).timeout.connect(func():
			if runtime_sequence_id != current_sequence_generation: return
			can_buffer = true
		)

		get_tree().create_timer(active_strike_delay + 0.016, true, false, false).timeout.connect(func():
			if runtime_sequence_id != current_sequence_generation: return
			strike_impact_frame.emit(combo_step)

			# Play swing whoosh (optional)
			_play_swing_sfx()

			# Terrain destruction on Attack 3 slam
			if combo_step == 2:
				_execute_terrain_shatter()
		)

		var fail_safe_buffer_delay = current_eval_delay + 0.050
		get_tree().create_timer(fail_safe_buffer_delay, true, false, false).timeout.connect(func():
			if runtime_sequence_id != current_sequence_generation: return
			if not was_eval_window_processed:
				_on_combo_cancel_window_reached()
		)

# --- CALL THIS FROM YOUR HITBOX / SHAPECAST WHEN AN ENEMY IS ACTUALLY HIT ---
func trigger_hit_impact(step: int, hit_position: Vector3) -> void:
	match step:
		0:
			_play_impact_sfx(hit_sfx_attack_1_pool, &"enemy_hit_1", hit_position, 0.88, 1.12, &"SFX")
		1:
			_play_impact_sfx(hit_sfx_attack_2_pool, &"enemy_hit_2", hit_position, 0.86, 1.14, &"SFX")
		2:
			_play_impact_sfx(hit_sfx_attack_3_pool, &"enemy_hit_3", hit_position, 0.78, 0.95, &"SFX")

func _play_swing_sfx() -> void:
	if swing_sfx_pool.is_empty() or not parent:
		return
	var stream = swing_sfx_pool.pick_random()
	if stream:
		AudioManager.play_sfx_3d(
			&"weapon_swing",
			stream,
			parent.global_position + (current_attack_direction * 1.0),
			&"SFX",
			0.95, 1.05,
			20
		)

func _play_impact_sfx(sfx_pool: Array[AudioStream], event_id: StringName, impact_pos: Vector3, pitch_min: float, pitch_max: float, bus_name: StringName) -> void:
	if sfx_pool.is_empty():
		return

	var selected_stream: AudioStream = sfx_pool.pick_random()
	if not selected_stream:
		return

	# Zero-allocation pooled 3D audio playback (15ms throttle stops volume clipping on swarms)
	AudioManager.play_sfx_3d(
		event_id,
		selected_stream,
		impact_pos,
		bus_name,
		pitch_min,
		pitch_max,
		15
	)

func _on_combo_cancel_window_reached() -> void:
	if not is_attacking or was_eval_window_processed:
		return

	was_eval_window_processed = true
	var evaluation_generation = runtime_sequence_id

	if combo_buffered:
		_execute_combo_chain()
	else:
		can_instant_cancel = true

		var remaining_recovery = current_total_duration - current_eval_delay
		get_tree().create_timer(remaining_recovery, true, false, false).timeout.connect(func():
			if runtime_sequence_id != evaluation_generation:
				return

			is_attacking = false
			can_buffer = false
			can_instant_cancel = false
			combo_step = 0
		)

func _execute_combo_chain() -> void:
	is_attacking = false
	can_buffer = false
	can_instant_cancel = false

	combo_step = 0 if combo_step >= 2 else combo_step + 1
	start_attack()

func _execute_terrain_shatter() -> void:
	if not terrain_manager:
		terrain_manager = get_tree().current_scene.find_child("TerrainManager", true, false)

	if not terrain_manager or not terrain_manager.has_method("get_voxel_tool"):
		return

	var vt = terrain_manager.get_voxel_tool()
	if not vt:
		return
	vt.channel = 0

	var local_player_pos: Vector3 = terrain_manager.to_local(parent.global_position)
	var p_x := int(floor(local_player_pos.x))
	var p_y := int(floor(local_player_pos.y))
	var p_z := int(floor(local_player_pos.z))

	var targets: Array[Vector2i] = []
	var half_width: int = int(shatter_width * 0.5)

	if abs(current_attack_direction.x) > abs(current_attack_direction.z):
		if current_attack_direction.x > 0:
			for d in range(1, shatter_depth + 1):
				for w in range(-half_width, shatter_width - half_width):
					targets.append(Vector2i(p_x - d, p_z + w))
		else:
			for d in range(1, shatter_depth + 1):
				for w in range(-half_width, shatter_width - half_width):
					targets.append(Vector2i(p_x + d, p_z + w))
	else:
		if current_attack_direction.z > 0:
			for d in range(1, shatter_depth + 1):
				for w in range(-half_width, shatter_width - half_width):
					targets.append(Vector2i(p_x + w, p_z - d))
		else:
			for d in range(1, shatter_depth + 1):
				for w in range(-half_width, shatter_width - half_width):
					targets.append(Vector2i(p_x + w, p_z + d))

	var impact_center_sum := Vector3.ZERO
	var shattered_count := 0

	for cell in targets:
		for offset_y in range(3, -6, -1):
			var current_y = p_y + offset_y
			var voxel_pos = Vector3i(cell.x, current_y, cell.y)
			var voxel_id = vt.get_voxel(voxel_pos)

			if voxel_id != 0:
				vt.value = 0
				vt.set_voxel(voxel_pos, 0)

				impact_center_sum += Vector3(voxel_pos) + Vector3(0.5, 0.5, 0.5)
				shattered_count += 1
				break

	# Teleport Emitter & Child GPUParticlesCollisionBox3D to dynamic impact height
	if shattered_count > 0 and shatter_particle_emitter:
		var average_impact_center = impact_center_sum / float(shattered_count)
		shatter_particle_emitter.global_position = terrain_manager.to_global(average_impact_center)
		shatter_particle_emitter.restart()
