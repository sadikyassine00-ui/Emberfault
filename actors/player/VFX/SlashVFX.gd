extends Node3D

@export var duration: float = 0.22

@export_category("Manual Flip Overrides")
@export var flip_horizontal: bool = false
@export var flip_vertical: bool = false

@onready var mesh_instance: MeshInstance3D = $SlashMesh

var material: ShaderMaterial = null
var active_tween: Tween = null
var is_standalone: bool = false

func _ready() -> void:
	if not mesh_instance:
		queue_free()
		return

	mesh_instance.rotation_degrees = Vector3.ZERO
	mesh_instance.scale = Vector3.ONE

	material = mesh_instance.material_override as ShaderMaterial

	is_standalone = (get_parent() == get_tree().root)

	if material:
		material.set_shader_parameter("flip_h", flip_horizontal)
		material.set_shader_parameter("flip_v", flip_vertical)

	_play_slash(not is_standalone)

func _play_slash(should_queue_free: bool) -> void:
	if not material:
		if should_queue_free: queue_free()
		return

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	material.set_shader_parameter("progress", 0.0)

	active_tween = create_tween()
	active_tween.tween_property(material, "shader_parameter/progress", 1.0, duration)\
		.set_trans(Tween.TRANS_LINEAR)

	if should_queue_free:
		active_tween.finished.connect(queue_free)
