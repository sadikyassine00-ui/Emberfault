extends Node
class_name EnvironmentManager

@export_category("Core Bindings")
@export var world_environment: WorldEnvironment
@export var directional_light: DirectionalLight3D
@export var cycle_controller: Node # Node export avoids class-cache indexing race conditions
@export var fog_vignette: MeshInstance3D # Binding to existing FogVignette node in scene

@export_category("Performance Guardrails")
@export var min_rotation_delta_degrees: float = 2.0 # Minimum angle shift before updating light rotation to protect shadow map buffer

# --- EXPERT LIGHTING & COLOR PALETTE MATRIX ---
# DAY: Chill, bright, natural warm sunlight with soft ambient fill (no overexposure, clean saturation)
const LIGHT_COLOR_DAY := Color(1.0, 0.96, 0.90)
const ENERGY_DAY := 1.0
const AMBIENT_COLOR_DAY := Color(0.55, 0.68, 0.85)
const AMBIENT_ENERGY_DAY := 0.45
const FOG_COLOR_DAY := Color(0.50, 0.60, 0.72)
const SUN_PITCH_DAY := -52.0

# DUSK: Rich, warm sunset amber
const LIGHT_COLOR_DUSK := Color(0.98, 0.48, 0.18)
const ENERGY_DUSK := 0.70
const AMBIENT_COLOR_DUSK := Color(0.42, 0.25, 0.45)
const AMBIENT_ENERGY_DUSK := 0.38
const FOG_COLOR_DUSK := Color(0.38, 0.20, 0.35)
const SUN_PITCH_DUSK := -15.0

# NIGHT: Stylized moonlight blue fill with high enemy readability & emissive pop
const LIGHT_COLOR_NIGHT := Color(0.40, 0.58, 0.92)
const ENERGY_NIGHT := 0.55
const AMBIENT_COLOR_NIGHT := Color(0.22, 0.30, 0.55) # Indigo blue fill illuminates dark enemy bodies!
const AMBIENT_ENERGY_NIGHT := 0.48
const FOG_COLOR_NIGHT := Color(0.08, 0.12, 0.25)
const SUN_PITCH_NIGHT := -70.0

# NIGHT DEEP: Midnight moonlit climax
const LIGHT_COLOR_NIGHT_DEEP := Color(0.35, 0.50, 0.85)
const ENERGY_NIGHT_DEEP := 0.45
const AMBIENT_COLOR_NIGHT_DEEP := Color(0.18, 0.24, 0.48)
const AMBIENT_ENERGY_NIGHT_DEEP := 0.42
const FOG_COLOR_NIGHT_DEEP := Color(0.06, 0.09, 0.20)
const SUN_PITCH_NIGHT_DEEP := -85.0

var last_applied_sun_pitch: float = -999.0

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

	# Ensure FogVignette is initialised deactivated during Day
	if fog_vignette:
		fog_vignette.visible = false

func _find_node_in_tree(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var root_node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if root_node:
		return root_node.find_child(node_name, true, false)
	return null

func _on_cycle_progress_updated(phase: int, progress: float) -> void:
	var from_color: Color; var to_color: Color
	var from_energy: float; var to_energy: float
	var from_ambient: Color; var to_ambient: Color
	var from_ambient_energy: float; var to_ambient_energy: float
	var from_fog: Color; var to_fog: Color
	var from_pitch: float; var to_pitch: float
	var from_vignette: float; var to_vignette: float

	match phase:
		0: # DAY: FogVignette deactivated (alpha 0.0)
			from_color = LIGHT_COLOR_DAY; to_color = LIGHT_COLOR_DUSK
			from_energy = ENERGY_DAY; to_energy = ENERGY_DUSK
			from_ambient = AMBIENT_COLOR_DAY; to_ambient = AMBIENT_COLOR_DUSK
			from_ambient_energy = AMBIENT_ENERGY_DAY; to_ambient_energy = AMBIENT_ENERGY_DUSK
			from_fog = FOG_COLOR_DAY; to_fog = FOG_COLOR_DUSK
			from_pitch = SUN_PITCH_DAY; to_pitch = SUN_PITCH_DUSK
			from_vignette = 0.0; to_vignette = 0.0
		1: # DUSK: Ease-in FogVignette mist (0.0 -> 0.85)
			from_color = LIGHT_COLOR_DUSK; to_color = LIGHT_COLOR_NIGHT
			from_energy = ENERGY_DUSK; to_energy = ENERGY_NIGHT
			from_ambient = AMBIENT_COLOR_DUSK; to_ambient = AMBIENT_COLOR_NIGHT
			from_ambient_energy = AMBIENT_ENERGY_DUSK; to_ambient_energy = AMBIENT_ENERGY_NIGHT
			from_fog = FOG_COLOR_DUSK; to_fog = FOG_COLOR_NIGHT
			from_pitch = SUN_PITCH_DUSK; to_pitch = SUN_PITCH_NIGHT
			from_vignette = 0.0; to_vignette = 0.85
		2: # NIGHT: Active thick FogVignette (0.85 -> 0.95)
			from_color = LIGHT_COLOR_NIGHT; to_color = LIGHT_COLOR_NIGHT_DEEP
			from_energy = ENERGY_NIGHT; to_energy = ENERGY_NIGHT_DEEP
			from_ambient = AMBIENT_COLOR_NIGHT; to_ambient = AMBIENT_COLOR_NIGHT_DEEP
			from_ambient_energy = AMBIENT_ENERGY_NIGHT; to_ambient_energy = AMBIENT_ENERGY_NIGHT_DEEP
			from_fog = FOG_COLOR_NIGHT; to_fog = FOG_COLOR_NIGHT_DEEP
			from_pitch = SUN_PITCH_NIGHT; to_pitch = SUN_PITCH_NIGHT_DEEP
			from_vignette = 0.85; to_vignette = 0.95
		3: # DAWN: Ease-out FogVignette (0.95 -> 0.0)
			from_color = LIGHT_COLOR_NIGHT_DEEP; to_color = LIGHT_COLOR_DAY
			from_energy = ENERGY_NIGHT_DEEP; to_energy = ENERGY_DAY
			from_ambient = AMBIENT_COLOR_NIGHT_DEEP; to_ambient = AMBIENT_COLOR_DAY
			from_ambient_energy = AMBIENT_ENERGY_NIGHT_DEEP; to_ambient_energy = AMBIENT_ENERGY_DAY
			from_fog = FOG_COLOR_NIGHT_DEEP; to_fog = FOG_COLOR_DAY
			from_pitch = SUN_PITCH_NIGHT_DEEP; to_pitch = SUN_PITCH_DAY
			from_vignette = 0.95; to_vignette = 0.0

	# Smooth S-Curve Ease-In / Ease-Out interpolation
	var eased_progress: float = smoothstep(0.0, 1.0, progress)

	var cur_light_color: Color = from_color.lerp(to_color, eased_progress)
	var cur_energy: float = lerpf(from_energy, to_energy, eased_progress)
	var cur_ambient: Color = from_ambient.lerp(to_ambient, eased_progress)
	var cur_ambient_energy: float = lerpf(from_ambient_energy, to_ambient_energy, eased_progress)
	var cur_fog: Color = from_fog.lerp(to_fog, eased_progress)
	var cur_pitch: float = lerpf(from_pitch, to_pitch, eased_progress)
	var cur_vignette_alpha: float = lerpf(from_vignette, to_vignette, eased_progress)

	if directional_light:
		directional_light.light_color = cur_light_color
		directional_light.light_energy = cur_energy

		# Discretely update light rotation ONLY when pitch delta exceeds threshold (protects 16.6ms shadow map buffer)
		if abs(cur_pitch - last_applied_sun_pitch) >= min_rotation_delta_degrees:
			last_applied_sun_pitch = cur_pitch
			directional_light.rotation_degrees.x = cur_pitch

	if world_environment and world_environment.environment:
		var env: Environment = world_environment.environment
		env.ambient_light_color = cur_ambient
		env.ambient_light_energy = cur_ambient_energy
		env.fog_light_color = cur_fog

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
