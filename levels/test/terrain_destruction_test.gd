extends Node3D

@export var terrain: VoxelTerrain
@export var camera: Camera3D

var _voxel_tool: VoxelTool

func _ready() -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
	if terrain:
		_voxel_tool = terrain.get_voxel_tool()

func _unhandled_input(event: InputEvent) -> void:
	if not _voxel_tool or not camera or not terrain:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_excavate_slice(event.position)

func _excavate_slice(mouse_pos: Vector2) -> void:
	# 1. Project rays into Global/World Space
	var global_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var global_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	# 2. Transform global vectors cleanly into Terrain-Local Space
	var local_origin: Vector3 = terrain.to_local(global_origin)
	var local_dir: Vector3 = terrain.global_transform.basis.inverse() * global_dir

	# 3. FIXED SIGNATURE: Pass origin, direction, and explicit max distance
	var hit: VoxelRaycastResult = _voxel_tool.raycast(local_origin, local_dir, 500.0)

	if hit:
		# Extract integer coordinates from the raycast match
		var hit_pos: Vector3i = hit.position
		var half_width: int = 4

		var min_bound := Vector3i(hit_pos.x - half_width, hit_pos.y, hit_pos.z - half_width)
		var max_bound := Vector3i(hit_pos.x + half_width - 1, hit_pos.y, hit_pos.z + half_width - 1)

		_voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)

		# High-performance local clearing loop
		for x in range(min_bound.x, max_bound.x + 1):
			for z in range(min_bound.z, max_bound.z + 1):
				for y in range(min_bound.y, max_bound.y + 1):
					var current_pos := Vector3i(x, y, z)
					var current_id: int = _voxel_tool.get_voxel(current_pos)

					# Enforce hard bedrock rule (ID 4)
					if current_id != 4:
						_voxel_tool.set_voxel(current_pos, 0) # Clear to air
