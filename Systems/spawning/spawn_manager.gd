extends Node3D
class_name SpawnManager

@export var horde_manager: HordeManager
@export var player: Node3D
@export var base_core: Node3D
@export var spawn_radius: float = 35.0
@export var saboteur_chance: float = 0.2

@onready var spawn_timer: Timer = $SpawnTimer

var is_spawning: bool = true # The Director's Kill Switch

func _ready():
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

# --- NEW: Helper functions for the Director ---
func set_spawn_rate(time_seconds: float):
	spawn_timer.wait_time = time_seconds
	if is_spawning and spawn_timer.is_stopped():
		spawn_timer.start()

func pause_spawning():
	is_spawning = false
	spawn_timer.stop()

func resume_spawning():
	is_spawning = true
	spawn_timer.start()
# --------------------------------------------

func _on_spawn_timer_timeout():
	if not is_spawning or not player or not horde_manager or not base_core: return

	if horde_manager.alive_count >= horde_manager.max_concurrent_enemies:
		return

	if horde_manager.total_enemies_in_wave != -1 and horde_manager.total_spawned_count >= horde_manager.total_enemies_in_wave:
		return

	var is_saboteur = randf() < saboteur_chance
	var spawn_center = base_core.global_position if is_saboteur else player.global_position

	for attempt in range(3):
		var spawn_pos = _get_safe_spawn_pos(spawn_center)
		if spawn_pos != Vector3.INF:
			horde_manager.spawn_enemy(spawn_pos, is_saboteur)
			return

func _get_safe_spawn_pos(center_pos: Vector3) -> Vector3:
	var angle = randf() * TAU
	var offset = Vector3(cos(angle), 0, sin(angle)) * spawn_radius
	var target_x = center_pos.x + offset.x
	var target_z = center_pos.z + offset.z

	var ray_start = Vector3(target_x, 1000.0, target_z)
	var ray_end = Vector3(target_x, -1000.0, target_z)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)

	if result: return result.position + Vector3(0, 2.0, 0)
	return Vector3.INF
