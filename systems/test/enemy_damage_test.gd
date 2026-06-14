extends Node3D
class_name PlayerCombat

@export var camera: Camera3D
@export var horde_manager: HordeManager
@export var spawn_manager: SpawnManager # Optional: Only if you want INSTANT respawns

var hit_radius: float = 1.5

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		check_hit(event.position)

func check_hit(mouse_pos: Vector2):
	if not horde_manager or horde_manager.alive_count == 0: return

	var mm = horde_manager.multimesh
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)

	var closest_distance = hit_radius
	var hit_index = -1

	# Loop through ONLY the highest active index, saving huge amounts of CPU
	for i in range(horde_manager.highest_active_index):
		if horde_manager.states[i] == 0: continue # Skip dead enemies

		var enemy_pos = horde_manager.positions[i]
		var v = enemy_pos - ray_origin
		var distance_to_ray = v.cross(ray_normal).length()

		if distance_to_ray < closest_distance:
			var dot_product = v.normalized().dot(ray_normal)
			if dot_product > 0:
				closest_distance = distance_to_ray
				hit_index = i

	# --- THE NEW POOLING LOGIC ---
	if hit_index != -1:
		print("Killed enemy index: ", hit_index)

		# 1. Kill the enemy (Hides them and lowers alive_count)
		horde_manager.kill_enemy(hit_index)

		# 2. (OPTIONAL) Force an instant respawn
		# If you don't do this, the SpawnManager will just spawn them naturally
		# on its next timer tick. If you want them instantly replaced, uncomment this:
		# if spawn_manager:
		#     spawn_manager._on_spawn_timer_timeout()
