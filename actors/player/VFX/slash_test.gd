extends MeshInstance3D

@export var anchor_node: Node3D # Primary Anchor (Attack 1 & 3)
@export var alternate_anchor_node: Node3D # Assign your 'anchor2' node here in the Inspector

@export var inner_radius: float = 1.5
@export var outer_radius: float = 2.5
@export var segments: int = 48

@export var speed_profile: Curve

var imm_mesh: ImmediateMesh
var lifetime_timer: float = 0.0
var current_duration: float = 0.06
var active: bool = false

var current_sweep_angle: float = 0.0
var current_is_vertical: bool = false

# Internal pointer to track which node is currently driving the transform
var _active_tracking_node: Node3D = null

func _ready() -> void:
	imm_mesh = ImmediateMesh.new()
	mesh = imm_mesh
	clear_arc()

func _process(delta: float) -> void:
	if not active: return

	lifetime_timer += delta
	if lifetime_timer >= current_duration:
		clear_arc()
		return

	var progress = lifetime_timer / current_duration
	if speed_profile:
		progress = speed_profile.sample(progress)

	if material_override:
		material_override.set_shader_parameter("animation_progress", progress)

	# Snap to whatever node was chosen when fired
	if _active_tracking_node and is_instance_valid(_active_tracking_node):
		global_position = _active_tracking_node.global_position
		global_basis = _active_tracking_node.global_transform.basis.orthonormalized()

func clear_arc() -> void:
	active = false
	_active_tracking_node = null
	imm_mesh.clear_surfaces()

# Added 'use_alt_anchor' parameter at the end, defaulting to false so old tracks won't break
func fire_procedural_arc(sweep_angle_degrees: float, duration: float, is_vertical: bool = false, use_alt_anchor: bool = false) -> void:
	lifetime_timer = 0.0
	current_duration = duration
	current_sweep_angle = sweep_angle_degrees
	current_is_vertical = is_vertical
	active = true

	# Hot-swap the tracking target based on the call track parameter
	_active_tracking_node = alternate_anchor_node if use_alt_anchor else anchor_node

	if _active_tracking_node and is_instance_valid(_active_tracking_node):
		global_position = _active_tracking_node.global_position
		global_basis = _active_tracking_node.global_transform.basis.orthonormalized()

	_build_instant_flash_geometry()

func _build_instant_flash_geometry() -> void:
	imm_mesh.clear_surfaces()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var rad_sweep = deg_to_rad(current_sweep_angle)
	var start_angle = rad_sweep * 0.5

	for i in range(segments):
		var t_curr = float(i) / float(segments)
		var t_next = float(i + 1) / float(segments)

		var angle_curr = start_angle - (rad_sweep * t_curr)
		var angle_next = start_angle - (rad_sweep * t_next)

		var uv_y1 = t_curr
		var uv_y2 = t_next

		var p_top_curr: Vector3
		var p_bot_curr: Vector3
		var p_top_next: Vector3
		var p_bot_next: Vector3

		if not current_is_vertical:
			p_top_curr = Vector3(sin(angle_curr) * outer_radius, 0.0, -cos(angle_curr) * outer_radius)
			p_bot_curr = Vector3(sin(angle_curr) * inner_radius, 0.0, -cos(angle_curr) * inner_radius)
			p_top_next = Vector3(sin(angle_next) * outer_radius, 0.0, -cos(angle_next) * outer_radius)
			p_bot_next = Vector3(sin(angle_next) * inner_radius, 0.0, -cos(angle_next) * inner_radius)
		else:
			p_top_curr = Vector3(0.0, sin(angle_curr) * outer_radius, -cos(angle_curr) * outer_radius)
			p_bot_curr = Vector3(0.0, sin(angle_curr) * inner_radius, -cos(angle_curr) * inner_radius)
			p_top_next = Vector3(0.0, sin(angle_next) * outer_radius, -cos(angle_next) * outer_radius)
			p_bot_next = Vector3(0.0, sin(angle_next) * inner_radius, -cos(angle_next) * inner_radius)

		_add_quad_local(p_top_curr, p_bot_curr, p_bot_next, p_top_next, uv_y1, uv_y2)

	imm_mesh.surface_end()

func _add_quad_local(l0: Vector3, l1: Vector3, l2: Vector3, l3: Vector3, uv_y1: float, uv_y2: float) -> void:
	imm_mesh.surface_set_uv(Vector2(0.0, uv_y1))
	imm_mesh.surface_add_vertex(l0)
	imm_mesh.surface_set_uv(Vector2(1.0, uv_y1))
	imm_mesh.surface_add_vertex(l1)
	imm_mesh.surface_set_uv(Vector2(1.0, uv_y2))
	imm_mesh.surface_add_vertex(l2)

	imm_mesh.surface_set_uv(Vector2(0.0, uv_y1))
	imm_mesh.surface_add_vertex(l0)
	imm_mesh.surface_set_uv(Vector2(1.0, uv_y2))
	imm_mesh.surface_add_vertex(l2)
	imm_mesh.surface_set_uv(Vector2(0.0, uv_y2))
	imm_mesh.surface_add_vertex(l3)
