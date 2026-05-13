extends Node3D
class_name HordeManager

@export_category("Core References")
@export var player: Node3D
@export var base_core: Node3D # NEW: The objective to protect
@export var terrain_collision_mask: int = 1

@export_category("Wave & Pool Settings")
@export var pool_size: int = 1000
@export var max_concurrent_enemies: int = 150
@export var total_enemies_in_wave: int = 500

@export_category("Swarm Settings")
@export var base_speed: float = 4.5
@export var despawn_distance: float = 60.0
@export var respawn_distance: float = 35.0

@onready var multi_mesh_instance = $MultiMeshInstance3D
@onready var multimesh = multi_mesh_instance.multimesh

# --- POOL TRACKERS ---
var alive_count: int = 0
var total_spawned_count: int = 0
var highest_active_index: int = 0

var positions = PackedVector3Array()
var velocities = PackedVector3Array()
var states = PackedInt32Array()
var intents = PackedInt32Array() # NEW: 0 = Harasser (Player), 1 = Saboteur (Base)

var speed_variances = PackedFloat32Array()
var preferred_distances_sq = PackedFloat32Array()
var orbital_speeds = PackedFloat32Array()

func _ready():
	multimesh.instance_count = pool_size
	multimesh.visible_instance_count = pool_size

	positions.resize(pool_size)
	velocities.resize(pool_size)
	states.resize(pool_size)
	intents.resize(pool_size)
	speed_variances.resize(pool_size)
	preferred_distances_sq.resize(pool_size)
	orbital_speeds.resize(pool_size)

	for i in range(pool_size):
		states[i] = 0
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))

# NEW: Takes the is_saboteur flag from the SpawnManager
func spawn_enemy(spawn_pos: Vector3, is_saboteur: bool = false):
	var target_idx = -1
	for i in range(pool_size):
		if states[i] == 0:
			target_idx = i
			break

	if target_idx == -1: return

	positions[target_idx] = spawn_pos
	velocities[target_idx] = Vector3.ZERO
	states[target_idx] = 1
	intents[target_idx] = 1 if is_saboteur else 0

	# Visual Distinction: Saboteurs are Purple, Harassers are White
	var start_color = Color(0.6, 0.2, 0.8) if is_saboteur else Color.WHITE
	multimesh.set_instance_color(target_idx, start_color)

	# Saboteurs are a bit slower, Harassers are faster
	speed_variances[target_idx] = randf_range(0.7, 0.9) if is_saboteur else randf_range(0.9, 1.3)
	preferred_distances_sq[target_idx] = pow(randf_range(3.0, 14.0), 2)
	orbital_speeds[target_idx] = randf_range(0.5, 2.0) * (1.0 if randf() > 0.5 else -1.0)

	alive_count += 1
	total_spawned_count += 1

	if target_idx >= highest_active_index:
		highest_active_index = target_idx + 1

# NEW: The Aggro Switch System
func notify_hit(idx: int):
	if states[idx] == 0: return

	if intents[idx] == 1:
		# It was attacking the base. Now it's MAD at the player.
		intents[idx] = 0
		speed_variances[idx] = 1.5 # Gets a speed boost
		multimesh.set_instance_color(idx, Color.RED) # Turns Red
	else:
		# It was already attacking the player, so it dies.
		kill_enemy(idx)

func kill_enemy(idx: int):
	if states[idx] == 0: return
	states[idx] = 0
	alive_count -= 1
	positions[idx] = Vector3(0, -1000, 0)
	multimesh.set_instance_transform(idx, Transform3D(Basis(), Vector3(0, -1000, 0)))

# --- THE RAW MATH ENGINE ---
func _physics_process(delta):
	if alive_count == 0: return

	var player_pos = player.global_position if player else Vector3.ZERO
	var base_pos = base_core.global_position if base_core else Vector3.ZERO

	var time_sec = Time.get_ticks_msec() / 1000.0
	var frames = Engine.get_frames_drawn()
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	query.collision_mask = terrain_collision_mask
	var despawn_sq = despawn_distance * despawn_distance

	for i in range(highest_active_index):
		if states[i] == 0: continue

		var current_pos = positions[i]

		# Decide who this enemy cares about
		var target_pos = player_pos if intents[i] == 0 else base_pos
		var dist_to_target_sq = current_pos.distance_squared_to(target_pos)

		# TETHERING: Tether to their specific target
		if dist_to_target_sq > despawn_sq:
			var random_angle = randf() * TAU
			current_pos = target_pos + Vector3(cos(random_angle), 0, sin(random_angle)) * respawn_distance

			query.from = current_pos + Vector3(0, 50, 0)
			query.to = current_pos + Vector3(0, -50, 0)
			var result = space_state.intersect_ray(query)
			if result: current_pos.y = result.position.y + 1.0

			positions[i] = current_pos
			velocities[i] = Vector3.ZERO
			continue

		var dir_to_target = Vector3.ZERO
		if dist_to_target_sq > 0.001:
			dir_to_target = (target_pos - current_pos) / sqrt(dist_to_target_sq)

		var desired_velocity = Vector3.ZERO
		var agitation = 1.0
		var forward_speed = 0.0

		if dist_to_target_sq > 400.0:
			forward_speed = base_speed * speed_variances[i]
		else:
			var distance_error_sq = dist_to_target_sq - preferred_distances_sq[i]

			if distance_error_sq > 2.0:
				forward_speed = base_speed * speed_variances[i]
			elif distance_error_sq > -1.0:
				agitation = 0.05
			else:
				forward_speed = -1.5
				agitation = 0.2

		var forward_vec = dir_to_target * forward_speed
		var tangent = Vector3.UP.cross(dir_to_target).normalized()
		var orbit_intensity = clamp(10.0 / max(sqrt(dist_to_target_sq), 1.0), 0.5, 3.0)
		var strafe_vec = tangent * (orbital_speeds[i] * orbit_intensity * agitation)
		var shambling_vec = Vector3(sin(time_sec * 3.0 + i) * 1.5, 0, cos(time_sec * 2.5 + i) * 1.5) * agitation

		# --- SEPARATION WEB RESTORED ---
		var separation_vec = Vector3.ZERO
		var neighbors = [i - 1, (i + 13) % highest_active_index]
		if i == 0: neighbors[0] = highest_active_index - 1

		for n_idx in neighbors:
			if states[n_idx] == 1:
				var push_dir = current_pos - positions[n_idx]
				var dist_sq = push_dir.length_squared()
				var bubble_size = 6.0

				if dist_sq < bubble_size and dist_sq > 0.001:
					var push_strength = bubble_size - dist_sq
					var straight_push = push_dir.normalized()
					if straight_push.dot(dir_to_target) < -0.2:
						forward_vec *= 0.1 # Brake if blocked
					var squirm_slide = Vector3.UP.cross(straight_push) * (1.2 if i % 2 == 0 else -1.2)
					separation_vec += (straight_push + squirm_slide).normalized() * (push_strength * 2.5 * agitation)

		desired_velocity = forward_vec + strafe_vec + shambling_vec + separation_vec
		if desired_velocity.length_squared() < 0.05 and agitation < 0.1:
			desired_velocity = Vector3.ZERO

		velocities[i] = velocities[i].lerp(desired_velocity, 5.0 * delta)
		if velocities[i].length_squared() < 0.01: velocities[i] = Vector3.ZERO
		current_pos += velocities[i] * delta

		# VOXEL GROUND SNAPPING
		if frames % 10 == i % 10:
			query.from = current_pos + Vector3(0, 50, 0)
			query.to = current_pos + Vector3(0, -50, 0)
			var result = space_state.intersect_ray(query)
			if result: current_pos.y = result.position.y + 1.0

		positions[i] = current_pos

		var look_dir = dir_to_target
		look_dir.y = 0
		var t = Transform3D()
		if look_dir.length_squared() > 0.001:
			t = t.looking_at(look_dir, Vector3.UP)
		t.origin = current_pos

		multimesh.set_instance_transform(i, t)
