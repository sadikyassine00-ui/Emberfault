extends Node
# JuiceDirector: Centralized, zero-allocation micro-impact architecture

# Cached engine targets
var current_camera: Camera3D = null

# Screen Shake State Registers (Pre-allocated math variables)
var shake_amplitude: float = 0.0
var shake_duration: float = 0.0
var shake_frequency: float = 60.0
var shake_timer: float = 0.0
var camera_base_h_offset: float = 0.0
var camera_base_v_offset: float = 0.0

# Hit-Stop / Frame Freeze Registers
var hit_stop_timer: float = 0.0
var is_in_hit_stop: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # Runs even when Engine.time_scale == 0

func register_camera(camera: Camera3D) -> void:
	current_camera = camera
	if current_camera:
		camera_base_h_offset = current_camera.h_offset
		camera_base_v_offset = current_camera.v_offset

func _process(delta: float) -> void:
	# 1. PROCESS FRAME FREEZES (Using real unscaled delta)
	if is_in_hit_stop:
		# Use unscaled delta because Engine.time_scale will be near zero
		var unscaled_delta: float = get_unscaled_delta(delta)
		hit_stop_timer -= unscaled_delta
		if hit_stop_timer <= 0.0:
			Engine.time_scale = 1.0
			is_in_hit_stop = false

	# 2. PROCESS CAMERA SHAKE
	if shake_duration > 0.0 and current_camera:
		shake_timer += delta
		if shake_timer >= shake_duration:
			# Reset camera offset cleanly
			current_camera.h_offset = camera_base_h_offset
			current_camera.v_offset = camera_base_v_offset
			shake_duration = 0.0
			shake_amplitude = 0.0
		else:
			# Direct trigonometric decay curve (Zero memory allocation)
			var current_decay: float = 1.0 - (shake_timer / shake_duration)
			var offset_x: float = sin(shake_timer * shake_frequency) * shake_amplitude * current_decay
			var offset_y: float = cos(shake_timer * shake_frequency * 0.8) * shake_amplitude * current_decay
			
			current_camera.h_offset = camera_base_h_offset + offset_x
			current_camera.v_offset = camera_base_v_offset + offset_y
    

# --- THE JUICE INTERFACE ---

## Triggers an immediate mechanical screen-shake. Overwrites or stacks based on high priority.
func trigger_shake(amplitude: float, duration: float, frequency: float = 60.0) -> void:
	if amplitude >= shake_amplitude:
		shake_amplitude = amplitude
		shake_duration = duration
		shake_frequency = frequency
		shake_timer = 0.0

## Freezes engine frame pacing instantly to deliver impact mass feedback.
func trigger_hit_stop(duration_seconds: float, scale: float = 0.01) -> void:
	# Avoid compounding loops; preserve longest duration spike
	if duration_seconds > hit_stop_timer:
		hit_stop_timer = duration_seconds
		Engine.time_scale = scale
		is_in_hit_stop = true

## Drives custom shader parameters via global vector uniforms (e.g., Chromatic Aberration burst)
func trigger_environmental_shock(origin: Vector3, force_intensity: float) -> void:
	# Modifies Godot 4 Shader Globals directly without touching materials
	RenderingServer.global_shader_parameter_set("global_impact_origin", origin)
	RenderingServer.global_shader_parameter_set("global_chromatic_intensity", force_intensity)

func get_unscaled_delta(delta: float) -> float:
	# Recovers true delta scale if physics processing is clamped
	return delta / Engine.time_scale if Engine.time_scale > 0.001 else delta