@tool
extends MeshInstance3D
class_name MeleeVisualizer3D

@export_category("Debug Controls")
## Toggles the solid projection area overlay on or off
@export var display_debug_mesh: bool = true:
	set(val):
		display_debug_mesh = val
		if not val:
			_clear_mesh()

## Total segments used to generate the smooth outer curve of the sector face
@export_range(8, 48) var arc_resolution_segments: int = 24
## Base emission color of the tactical weapon sweep zone
@export var visual_mesh_color: Color = Color(0.0, 1.0, 0.4)
## Opacity rating of the filled visual area (0.0 to 1.0)
@export_range(0.0, 1.0) var fill_opacity: float = 0.25

var _immediate_mesh: ImmediateMesh
var _debug_material: StandardMaterial3D

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	mesh = _immediate_mesh

	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

	# AAA VISUAL FIX: Enable alpha blending and disable face culling
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	material_override = _debug_material

func _process(_delta: float) -> void:
	if not display_debug_mesh:
		return

	var combat_comp = get_parent() as CombatComponent
	if not combat_comp or not combat_comp.visual_model:
		return

	_draw_melee_cone_projection(combat_comp)

func _draw_melee_cone_projection(combat_comp: CombatComponent) -> void:
	_immediate_mesh.clear_surfaces()

	var radius: float = combat_comp.strike_radius
	var arc_degrees: float = combat_comp.strike_arc_degrees

	# Pack configured opacity levels dynamically into the material layer
	_debug_material.albedo_color = Color(visual_mesh_color.r, visual_mesh_color.g, visual_mesh_color.b, fill_opacity)

	var forward: Vector3 = combat_comp.visual_model.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD

	var half_arc_rad: float = deg_to_rad(arc_degrees / 2.0)
	var angle_increment: float = (half_arc_rad * 2.0) / float(arc_resolution_segments)

	# AAA FIX: Shift to PRIMITIVE_TRIANGLES to build solid, rasterized screen geometry
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	for step in range(arc_resolution_segments):
		# Compute horizontal angle steps for the current polygon slice
		var angle_a: float = - half_arc_rad + (step * angle_increment)
		var angle_b: float = - half_arc_rad + ((step + 1) * angle_increment)

		var point_a: Vector3 = forward.rotated(Vector3.UP, angle_a) * radius
		var point_b: Vector3 = forward.rotated(Vector3.UP, angle_b) * radius

		# Generate triangle face (Origin -> Left Vertex -> Right Vertex)
		_immediate_mesh.surface_add_vertex(Vector3.ZERO)
		_immediate_mesh.surface_add_vertex(point_a)
		_immediate_mesh.surface_add_vertex(point_b)

	_immediate_mesh.surface_end()

func _clear_mesh() -> void:
	if _immediate_mesh:
		_immediate_mesh.clear_surfaces()
