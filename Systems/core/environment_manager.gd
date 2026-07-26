@tool
extends Node
class_name EnvironmentManager

@export_category("Core Bindings")
@export var world_environment: WorldEnvironment:
	set(v):
		world_environment = v
		update_environment_live()
@export var directional_light: DirectionalLight3D:
	set(v):
		directional_light = v
		update_environment_live()
@export var cycle_controller: Node: # Node export avoids class-cache indexing race conditions
	set(v):
		cycle_controller = v
		update_environment_live()
@export var fog_vignette: MeshInstance3D: # Binding to existing FogVignette node in scene
	set(v):
		fog_vignette = v
		update_environment_live()

@export_category("Performance Guardrails")
@export var min_rotation_delta_degrees: float = 0.5 # Minimum angle shift before updating light rotation to protect shadow map buffer

@export_category("Editor / Debug Live Viewport Override")
@export_enum("Auto (Cycle Driven)", "DAY", "DUSK", "NIGHT", "DAWN") var debug_force_phase: int = 0:
	set(v):
		debug_force_phase = v
		update_environment_live()

# --- INSPECTOR TWEAKABLE ENVIRONMENT MATRIX ---
@export_group("DAY Phase Settings")
@export var day_bg_color: Color = Color(0.35, 0.55, 0.82):
	set(v): day_bg_color = v; update_environment_live()
@export var day_light_color: Color = Color(1.0, 0.96, 0.90):
	set(v): day_light_color = v; update_environment_live()
@export var day_light_energy: float = 1.2:
	set(v): day_light_energy = v; update_environment_live()
@export var day_ambient_color: Color = Color(0.55, 0.68, 0.85):
	set(v): day_ambient_color = v; update_environment_live()
@export var day_ambient_energy: float = 0.50:
	set(v): day_ambient_energy = v; update_environment_live()
@export var day_fog_color: Color = Color(0.50, 0.60, 0.72):
	set(v): day_fog_color = v; update_environment_live()

@export_subgroup("DAY Shadows & Post Processing")
@export var day_shadow_enabled: bool = true:
	set(v): day_shadow_enabled = v; update_environment_live()
@export var day_shadow_opacity: float = 0.85:
	set(v): day_shadow_opacity = v; update_environment_live()
@export var day_shadow_blur: float = 1.0:
	set(v): day_shadow_blur = v; update_environment_live()
@export var day_vignette_alpha: float = 0.0:
	set(v): day_vignette_alpha = v; update_environment_live()
@export var day_glow_intensity: float = 0.6:
	set(v): day_glow_intensity = v; update_environment_live()
@export var day_glow_bloom: float = 0.15:
	set(v): day_glow_bloom = v; update_environment_live()
@export var day_brightness: float = 1.0:
	set(v): day_brightness = v; update_environment_live()
@export var day_contrast: float = 1.0:
	set(v): day_contrast = v; update_environment_live()
@export var day_saturation: float = 1.05:
	set(v): day_saturation = v; update_environment_live()

@export_group("DUSK Phase Settings")
@export var dusk_bg_color: Color = Color(0.48, 0.20, 0.28):
	set(v): dusk_bg_color = v; update_environment_live()
@export var dusk_light_color: Color = Color(0.98, 0.48, 0.18):
	set(v): dusk_light_color = v; update_environment_live()
@export var dusk_light_energy: float = 0.80:
	set(v): dusk_light_energy = v; update_environment_live()
@export var dusk_ambient_color: Color = Color(0.42, 0.25, 0.45):
	set(v): dusk_ambient_color = v; update_environment_live()
@export var dusk_ambient_energy: float = 0.40:
	set(v): dusk_ambient_energy = v; update_environment_live()
@export var dusk_fog_color: Color = Color(0.38, 0.20, 0.35):
	set(v): dusk_fog_color = v; update_environment_live()

@export_subgroup("DUSK Shadows & Post Processing")
@export var dusk_shadow_enabled: bool = true:
	set(v): dusk_shadow_enabled = v; update_environment_live()
@export var dusk_shadow_opacity: float = 0.90:
	set(v): dusk_shadow_opacity = v; update_environment_live()
@export var dusk_shadow_blur: float = 1.5:
	set(v): dusk_shadow_blur = v; update_environment_live()
@export var dusk_vignette_alpha: float = 0.25:
	set(v): dusk_vignette_alpha = v; update_environment_live()
@export var dusk_glow_intensity: float = 0.7:
	set(v): dusk_glow_intensity = v; update_environment_live()
@export var dusk_glow_bloom: float = 0.20:
	set(v): dusk_glow_bloom = v; update_environment_live()
@export var dusk_brightness: float = 0.98:
	set(v): dusk_brightness = v; update_environment_live()
@export var dusk_contrast: float = 1.05:
	set(v): dusk_contrast = v; update_environment_live()
@export var dusk_saturation: float = 1.15:
	set(v): dusk_saturation = v; update_environment_live()

@export_group("NIGHT Phase Settings")
@export var night_bg_color: Color = Color(0.04, 0.06, 0.16):
	set(v): night_bg_color = v; update_environment_live()
@export var night_ambient_color: Color = Color(0.22, 0.30, 0.55):
	set(v): night_ambient_color = v; update_environment_live()
@export var night_ambient_energy: float = 0.48:
	set(v): night_ambient_energy = v; update_environment_live()
@export var night_fog_color: Color = Color(0.08, 0.12, 0.25):
	set(v): night_fog_color = v; update_environment_live()

@export_subgroup("NIGHT Shadows & Post Processing")
@export var night_vignette_alpha: float = 0.85:
	set(v): night_vignette_alpha = v; update_environment_live()
@export var night_glow_intensity: float = 0.85:
	set(v): night_glow_intensity = v; update_environment_live()
@export var night_glow_bloom: float = 0.25:
	set(v): night_glow_bloom = v; update_environment_live()
@export var night_brightness: float = 1.0:
	set(v): night_brightness = v; update_environment_live()
@export var night_contrast: float = 1.02:
	set(v): night_contrast = v; update_environment_live()
@export var night_saturation: float = 1.10:
	set(v): night_saturation = v; update_environment_live()

@export_group("NIGHT DEEP Phase Settings")
@export var night_deep_bg_color: Color = Color(0.01, 0.02, 0.08):
	set(v): night_deep_bg_color = v; update_environment_live()
@export var night_deep_ambient_color: Color = Color(0.18, 0.24, 0.48):
	set(v): night_deep_ambient_color = v; update_environment_live()
@export var night_deep_ambient_energy: float = 0.42:
	set(v): night_deep_ambient_energy = v; update_environment_live()
@export var night_deep_fog_color: Color = Color(0.06, 0.09, 0.20):
	set(v): night_deep_fog_color = v; update_environment_live()

@export_subgroup("NIGHT DEEP Shadows & Post Processing")
@export var night_deep_vignette_alpha: float = 0.95:
	set(v): night_deep_vignette_alpha = v; update_environment_live()
@export var night_deep_glow_intensity: float = 0.95:
	set(v): night_deep_glow_intensity = v; update_environment_live()
@export var night_deep_glow_bloom: float = 0.30:
	set(v): night_deep_glow_bloom = v; update_environment_live()
@export var night_deep_brightness: float = 1.0:
	set(v): night_deep_brightness = v; update_environment_live()
@export var night_deep_contrast: float = 1.05:
	set(v): night_deep_contrast = v; update_environment_live()
@export var night_deep_saturation: float = 1.15:
	set(v): night_deep_saturation = v; update_environment_live()

var last_applied_sun_pitch: float = -999.0
var last_applied_sun_yaw: float = -999.0

func _ready() -> void:
	if not world_environment:
		world_environment = _find_node_in_tree("WorldEnvironment") as WorldEnvironment
	if not directional_light:
		directional_light = _find_node_in_tree("DirectionalLight3D") as DirectionalLight3D
	if not fog_vignette:
		fog_vignette = _find_node_in_tree("FogVignette") as MeshInstance3D
	if not cycle_controller:
		cycle_controller = _find_node_in_tree("DayNightCycleController")

	if cycle_controller and "progress_updated" in cycle_controller:
		var sig: Signal = cycle_controller.get("progress_updated")
		if sig and not sig.is_connected(_on_cycle_progress_updated):
			sig.connect(_on_cycle_progress_updated)

	update_environment_live()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		update_environment_live()

func update_environment_live() -> void:
	if not is_inside_tree():
		return
	if not world_environment:
		world_environment = _find_node_in_tree("WorldEnvironment") as WorldEnvironment
	if not directional_light:
		directional_light = _find_node_in_tree("DirectionalLight3D") as DirectionalLight3D
	if not fog_vignette:
		fog_vignette = _find_node_in_tree("FogVignette") as MeshInstance3D
	if not cycle_controller:
		cycle_controller = _find_node_in_tree("DayNightCycleController")

	var eval_phase: int = 0
	if debug_force_phase > 0:
		eval_phase = debug_force_phase - 1
	elif cycle_controller and "initial_starting_phase" in cycle_controller:
		eval_phase = cycle_controller.get("initial_starting_phase")

	_on_cycle_progress_updated(eval_phase, 0.0)

func _find_node_in_tree(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var root_node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if root_node:
		return root_node.find_child(node_name, true, false)
	return null

func _on_cycle_progress_updated(phase: int, progress: float) -> void:
	var eval_phase: int = phase
	var eval_progress: float = progress

	if debug_force_phase > 0:
		eval_phase = debug_force_phase - 1
		eval_progress = 0.0
	elif Engine.is_editor_hint() and cycle_controller and "initial_starting_phase" in cycle_controller:
		eval_phase = cycle_controller.get("initial_starting_phase")
		eval_progress = 0.0

	var from_bg: Color = day_bg_color; var to_bg: Color = dusk_bg_color
	var from_color: Color = day_light_color; var to_color: Color = dusk_light_color
	var from_energy: float = day_light_energy; var to_energy: float = dusk_light_energy
	var from_ambient: Color = day_ambient_color; var to_ambient: Color = dusk_ambient_color
	var from_ambient_energy: float = day_ambient_energy; var to_ambient_energy: float = dusk_ambient_energy
	var from_fog: Color = day_fog_color; var to_fog: Color = dusk_fog_color

	var from_shadow_enabled: bool = true; var to_shadow_enabled: bool = true
	var from_shadow_opacity: float = 0.85; var to_shadow_opacity: float = 0.85
	var from_shadow_blur: float = 1.0; var to_shadow_blur: float = 1.0

	var from_vignette: float = 0.0; var to_vignette: float = 0.0

	var from_glow_intensity: float = 0.6; var to_glow_intensity: float = 0.6
	var from_glow_bloom: float = 0.15; var to_glow_bloom: float = 0.15
	var from_brightness: float = 1.0; var to_brightness: float = 1.0
	var from_contrast: float = 1.0; var to_contrast: float = 1.0
	var from_saturation: float = 1.0; var to_saturation: float = 1.0

	# Physical Solar Arc Trajectory (Dawn East -> Day Overhead Noon Zenith -> Dusk West -> Night Horizon Sink)
	var cur_pitch: float = -90.0
	var cur_yaw: float = 0.0
	var cur_energy: float = day_light_energy
	var cur_shadow_enabled: bool = true

	match eval_phase:
		0: # DAY: Morning Sunrise (East -90° yaw, -160° pitch) -> Noon Zenith (-90° pitch directly overhead at 0.5 progress!) -> Afternoon (West +90° yaw, -140° pitch)
			from_bg = day_bg_color; to_bg = dusk_bg_color
			from_color = day_light_color; to_color = dusk_light_color
			from_ambient = day_ambient_color; to_ambient = dusk_ambient_color
			from_ambient_energy = day_ambient_energy; to_ambient_energy = dusk_ambient_energy
			from_fog = day_fog_color; to_fog = dusk_fog_color
			from_shadow_enabled = day_shadow_enabled; to_shadow_enabled = dusk_shadow_enabled
			from_shadow_opacity = day_shadow_opacity; to_shadow_opacity = dusk_shadow_opacity
			from_shadow_blur = day_shadow_blur; to_shadow_blur = dusk_shadow_blur
			from_vignette = day_vignette_alpha; to_vignette = dusk_vignette_alpha
			from_glow_intensity = day_glow_intensity; to_glow_intensity = dusk_glow_intensity
			from_glow_bloom = day_glow_bloom; to_glow_bloom = dusk_glow_bloom
			from_brightness = day_brightness; to_brightness = dusk_brightness
			from_contrast = day_contrast; to_contrast = dusk_contrast
			from_saturation = day_saturation; to_saturation = dusk_saturation

			cur_energy = day_light_energy
			if eval_progress <= 0.5:
				var t: float = eval_progress * 2.0
				cur_pitch = lerpf(-160.0, -90.0, t) # Morning: Low East pitch -> High Noon Zenith directly overhead!
				cur_yaw = lerpf(-90.0, 0.0, t)      # East -> South
			else:
				var t: float = (eval_progress - 0.5) * 2.0
				cur_pitch = lerpf(-90.0, -140.0, t)  # High Noon Zenith -> Afternoon West pitch
				cur_yaw = lerpf(0.0, 90.0, t)        # South -> West

		1: # DUSK: Afternoon West -> Sinking into Western Sunset below horizon
			from_bg = dusk_bg_color; to_bg = night_bg_color
			from_color = dusk_light_color; to_color = Color(0.9, 0.35, 0.1)
			from_ambient = dusk_ambient_color; to_ambient = night_ambient_color
			from_ambient_energy = dusk_ambient_energy; to_ambient_energy = night_ambient_energy
			from_fog = dusk_fog_color; to_fog = night_fog_color
			from_shadow_enabled = dusk_shadow_enabled; to_shadow_enabled = false
			from_shadow_opacity = dusk_shadow_opacity; to_shadow_opacity = 0.0
			from_shadow_blur = dusk_shadow_blur; to_shadow_blur = 2.0
			from_vignette = dusk_vignette_alpha; to_vignette = night_vignette_alpha
			from_glow_intensity = dusk_glow_intensity; to_glow_intensity = night_glow_intensity
			from_glow_bloom = dusk_glow_bloom; to_glow_bloom = night_glow_bloom
			from_brightness = dusk_brightness; to_brightness = night_brightness
			from_contrast = dusk_contrast; to_contrast = night_contrast
			from_saturation = dusk_saturation; to_saturation = night_saturation

			cur_pitch = lerpf(-140.0, -178.0, eval_progress) # Sinks into Western horizon
			cur_yaw = 90.0                                     # West
			cur_energy = lerpf(dusk_light_energy, 0.0, eval_progress) # Sun light dims to 0 as it sets!

		2: # NIGHT: Sun is down below horizon and DOES NOT SHOW (energy = 0.0). Night lit by indigo ambient fill!
			from_bg = night_bg_color; to_bg = night_deep_bg_color
			from_color = Color(0.2, 0.3, 0.5); to_color = Color(0.15, 0.2, 0.4)
			from_ambient = night_ambient_color; to_ambient = night_deep_ambient_color
			from_ambient_energy = night_ambient_energy; to_ambient_energy = night_deep_ambient_energy
			from_fog = night_fog_color; to_fog = night_deep_fog_color
			from_shadow_enabled = false; to_shadow_enabled = false
			from_shadow_opacity = 0.0; to_shadow_opacity = 0.0
			from_shadow_blur = 2.0; to_shadow_blur = 2.0
			from_vignette = night_vignette_alpha; to_vignette = night_deep_vignette_alpha
			from_glow_intensity = night_glow_intensity; to_glow_intensity = night_deep_glow_intensity
			from_glow_bloom = night_glow_bloom; to_glow_bloom = night_deep_glow_bloom
			from_brightness = night_brightness; to_brightness = night_deep_brightness
			from_contrast = night_contrast; to_contrast = night_deep_contrast
			from_saturation = night_saturation; to_saturation = night_deep_saturation

			cur_pitch = -180.0
			cur_yaw = 90.0
			cur_energy = 0.0 # Sun is down below horizon and DOES NOT SHOW!
			cur_shadow_enabled = false

		3: # DAWN: Sun emerges over Eastern horizon (-90° yaw, pitch -178° -> -160°), energy fades in 0.0 -> day_light_energy
			from_bg = night_deep_bg_color; to_bg = day_bg_color
			from_color = Color(0.95, 0.6, 0.4); to_color = day_light_color
			from_ambient = night_deep_ambient_color; to_ambient = day_ambient_color
			from_ambient_energy = night_deep_ambient_energy; to_ambient_energy = day_ambient_energy
			from_fog = night_deep_fog_color; to_fog = day_fog_color
			from_shadow_enabled = false; to_shadow_enabled = day_shadow_enabled
			from_shadow_opacity = 0.0; to_shadow_opacity = day_shadow_opacity
			from_shadow_blur = 2.0; to_shadow_blur = day_shadow_blur
			from_vignette = night_deep_vignette_alpha; to_vignette = day_vignette_alpha
			from_glow_intensity = night_deep_glow_intensity; to_glow_intensity = day_glow_intensity
			from_glow_bloom = night_deep_glow_bloom; to_glow_bloom = day_glow_bloom
			from_brightness = night_deep_brightness; to_brightness = day_brightness
			from_contrast = night_deep_contrast; to_contrast = day_contrast
			from_saturation = night_deep_saturation; to_saturation = day_saturation

			cur_pitch = lerpf(-178.0, -160.0, eval_progress) # Rises from Eastern horizon
			cur_yaw = -90.0                                    # East
			cur_energy = lerpf(0.0, day_light_energy, eval_progress) # Fade in sun energy as dawn breaks!

	# Smooth S-Curve Ease-In / Ease-Out interpolation
	var eased_progress: float = smoothstep(0.0, 1.0, eval_progress)

	var cur_bg_color: Color = from_bg.lerp(to_bg, eased_progress)
	var cur_light_color: Color = from_color.lerp(to_color, eased_progress)
	var cur_ambient: Color = from_ambient.lerp(to_ambient, eased_progress)
	var cur_ambient_energy: float = lerpf(from_ambient_energy, to_ambient_energy, eased_progress)
	var cur_fog: Color = from_fog.lerp(to_fog, eased_progress)

	var cur_shadow_opacity: float = lerpf(from_shadow_opacity, to_shadow_opacity, eased_progress)
	var cur_shadow_blur: float = lerpf(from_shadow_blur, to_shadow_blur, eased_progress)

	var cur_vignette_alpha: float = lerpf(from_vignette, to_vignette, eased_progress)

	var cur_glow_intensity: float = lerpf(from_glow_intensity, to_glow_intensity, eased_progress)
	var cur_glow_bloom: float = lerpf(from_glow_bloom, to_glow_bloom, eased_progress)
	var cur_brightness: float = lerpf(from_brightness, to_brightness, eased_progress)
	var cur_contrast: float = lerpf(from_contrast, to_contrast, eased_progress)
	var cur_saturation: float = lerpf(from_saturation, to_saturation, eased_progress)

	if directional_light:
		directional_light.light_color = cur_light_color
		directional_light.light_energy = cur_energy
		directional_light.shadow_enabled = cur_shadow_enabled
		directional_light.shadow_opacity = cur_shadow_opacity
		directional_light.shadow_blur = cur_shadow_blur

		# Continuous smooth sun movement across sky (throttled by min_rotation_delta_degrees)
		var rot_delta: float = abs(cur_pitch - last_applied_sun_pitch) + abs(cur_yaw - last_applied_sun_yaw)
		if rot_delta >= min_rotation_delta_degrees or Engine.is_editor_hint():
			last_applied_sun_pitch = cur_pitch
			last_applied_sun_yaw = cur_yaw
			directional_light.rotation_degrees = Vector3(cur_pitch, cur_yaw, 0.0)

	if world_environment and world_environment.environment:
		var env: Environment = world_environment.environment
		env.background_color = cur_bg_color
		env.ambient_light_color = cur_ambient
		env.ambient_light_energy = cur_ambient_energy
		env.fog_light_color = cur_fog
		env.glow_intensity = cur_glow_intensity
		env.glow_bloom = cur_glow_bloom
		env.adjustment_enabled = true
		env.adjustment_brightness = cur_brightness
		env.adjustment_contrast = cur_contrast
		env.adjustment_saturation = cur_saturation

	# Seamlessly control existing FogVignette node activation & alpha
	if fog_vignette:
		if cur_vignette_alpha <= 0.005:
			fog_vignette.visible = false
		else:
			fog_vignette.visible = true
			var mat: Material = fog_vignette.material_override
			if mat is ShaderMaterial:
				var sh_mat := mat as ShaderMaterial
				var col = sh_mat.get_shader_parameter("fog_color")
				if col is Color:
					col.a = cur_vignette_alpha
					sh_mat.set_shader_parameter("fog_color", col)
