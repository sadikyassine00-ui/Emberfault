extends Node3D
class_name SpawnManager

@export var horde_manager: HordeManager
@export var player: Node3D
@export var spawn_radius: float = 35.0

@onready var spawn_timer: Timer = $SpawnTimer

func _ready():
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

func _on_spawn_timer_timeout():
	if not player or not horde_manager: return

	# THE GHOST KILLER: Check the HordeManager's limits before doing anything!
	if horde_manager.alive_count >= horde_manager.max_concurrent_enemies:
		return # Swarm is full, stop spawning

	if horde_manager.total_enemies_in_wave != -1 and horde_manager.total_spawned_count >= horde_manager.total_enemies_in_wave:
		return # The wave is completely finished, stop spawning

	# Try to find a safe floor voxel
	for attempt in range(3):
		var spawn_pos = _get_safe_spawn_pos()

		if spawn_pos != Vector3.INF:
			horde_manager.spawn_enemy(spawn_pos)
			return

func _get_safe_spawn_pos() -> Vector3:
	var angle = randf() * TAU
	var offset = Vector3(cos(angle), 0, sin(angle)) * spawn_radius

	var target_x = player.global_position.x + offset.x
	var target_z = player.global_position.z + offset.z

	var ray_start = Vector3(target_x, 1000.0, target_z)
	var ray_end = Vector3(target_x, -1000.0, target_z)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1 # Terrain

	var result = space_state.intersect_ray(query)

	if result:
		return result.position + Vector3(0, 2.0, 0)

	return Vector3.INF
