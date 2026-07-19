extends MeshInstance3D
class_name FogVignette

@export var player_node: Node3D = null

# AAA Cache Architecture: Direct memory register pointer to the shader material
var _cached_shader_material: ShaderMaterial = null

func _ready() -> void:
	# Query the stack once at initialization
	var active_mat: Material = get_active_material(0)

	if active_mat is ShaderMaterial:
		_cached_shader_material = active_mat
	else:
		push_error("FogVignette Error: Active material at slot 0 must be a valid ShaderMaterial.")

func _process(_delta: float) -> void:
	# O(1) Vector Transfer: Bypasses property stack traversal completely
	if _cached_shader_material and is_instance_valid(player_node):
		_cached_shader_material.set_shader_parameter(
			"player_world_pos",
			player_node.global_position
		)
