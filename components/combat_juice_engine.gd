class_name CombatJuiceEngine
extends Node

var original_hammer_scale: Vector3 = Vector3.ZERO
var active_tween: Tween

func execute_wind_up(hammer_mesh: MeshInstance3D) -> void:
	if not hammer_mesh:
		return
		
	_ensure_scale_cached(hammer_mesh)
	
	if active_tween and active_tween.is_valid():
		active_tween.kill()
		
	active_tween = get_tree().create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	active_tween.set_ignore_time_scale(true)
	
	# Vertical "Wind-Up" stretch tween
	active_tween.tween_property(hammer_mesh, "scale", Vector3(original_hammer_scale.x * 0.7, original_hammer_scale.y * 1.5, original_hammer_scale.z * 0.7), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	active_tween.tween_property(hammer_mesh, "scale", original_hammer_scale, 0.1)

func execute_strike_juice(hammer_mesh: MeshInstance3D, hit_stop_duration: float, combo_step: int) -> void:
	if not hammer_mesh:
		return
		
	_ensure_scale_cached(hammer_mesh)
	
	# Execute baseline frame stall feedback
	var current_frames = 8.0 if combo_step < 2 else hit_stop_duration
	trigger_hit_stop(current_frames)
	
	if active_tween and active_tween.is_valid():
		active_tween.kill()
		
	active_tween = get_tree().create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	active_tween.set_ignore_time_scale(true)
	
	# Instant flat impact squash
	hammer_mesh.scale = Vector3(original_hammer_scale.x * 1.5, original_hammer_scale.y * 0.3, original_hammer_scale.z * 1.5)
	
	# Bounce back to normal
	active_tween.tween_property(hammer_mesh, "scale", Vector3(original_hammer_scale.x * 0.9, original_hammer_scale.y * 1.2, original_hammer_scale.z * 0.9), 0.1)
	active_tween.tween_property(hammer_mesh, "scale", original_hammer_scale, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)

func _ensure_scale_cached(hammer_mesh: MeshInstance3D) -> void:
	if original_hammer_scale == Vector3.ZERO:
		original_hammer_scale = hammer_mesh.scale
		if original_hammer_scale == Vector3.ZERO:
			original_hammer_scale = Vector3.ONE

func trigger_hit_stop(duration_frames: float) -> void:
	var duration_sec = duration_frames / 60.0
	Engine.time_scale = 0.05
	# async safety timers utilizing true ignore_time_scale
	get_tree().create_timer(duration_sec, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
	)
