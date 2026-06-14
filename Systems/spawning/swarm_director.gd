extends Node
class_name SwarmDirector

var active_enemies: Array[Node3D] = []

func register_enemy(enemy: Node3D):
	if not active_enemies.has(enemy):
		active_enemies.append(enemy)

func unregister_enemy(enemy: Node3D):
	active_enemies.erase(enemy)

func get_target_slot(enemy: Node3D, player_pos: Vector3) -> Vector3:
	var rank = active_enemies.find(enemy)
	if rank == -1:
		return player_pos

	var radius = 0.0
	var angle = 0.0

	# FRONTLINE: Top 8 enemies (2 meters away)
	if rank < 8:
		radius = 2.0
		angle = rank * (TAU / 8.0)

	# MIDLINE: Next 16 enemies (5 meters away)
	elif rank < 24:
		radius = 5.0
		angle = (rank - 8) * (TAU / 16.0)

	# BACKLINE: Infinite expanding rings
	else:
		var backline_index = rank - 24
		var ring_tier = int(backline_index / 20.0)
		radius = 8.0 + (ring_tier * 2.5)
		angle = backline_index * (TAU / 20.0)

	# Make the swarm slowly rotate around the player
	var time_offset = Time.get_ticks_msec() / 3000.0
	angle += time_offset if rank < 8 else -time_offset

	return player_pos + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
