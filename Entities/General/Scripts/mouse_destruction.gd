extends Camera3D

@export var terrain: VoxelTerrain
@export var melee_radius: float = 1.5 # Shrunk down so it doesn't hit unloaded underground chunks
@export var melee_reach: float = 10.0 # How far the player can melee


func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_shoot_voxel_raycast(event.position)

func _shoot_voxel_raycast(mouse_position: Vector2):
	if not terrain: return

	var voxel_tool = terrain.get_voxel_tool()
	var origin = project_ray_origin(mouse_position)
	var direction = project_ray_normal(mouse_position)

	# 1. Use the Voxel Engine's perfect mathematical raycast
	var hit = voxel_tool.raycast(origin, direction, melee_reach)

	if hit:
		_destroy_voxels(hit, voxel_tool)

func _destroy_voxels(hit, voxel_tool: VoxelTool):
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	voxel_tool.value = 0
	voxel_tool.mode = VoxelTool.MODE_SET

	# 2. hit.position returns a Vector3i. We cast it to Vector3 for the AABB math.
	var hit_pos = Vector3(hit.position)
	var radius_vec = Vector3(melee_radius, melee_radius, melee_radius)
	var bounds = AABB(hit_pos - radius_vec, radius_vec * 2)

	# 3. Ask the engine if these specific blocks are cached in RAM
	if voxel_tool.is_area_editable(bounds):
		voxel_tool.do_sphere(hit_pos, melee_radius)
	else:
		print("Engine rejected edit. Hit coordinate: ", hit_pos)
