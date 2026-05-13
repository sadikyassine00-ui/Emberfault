extends Node3D
class_name HordeManager

@export_category("Core References")
@export var player: Node3D
@export var terrain_collision_mask: int = 1

@export_category("Wave & Pool Settings")
@export var pool_size: int = 1000            # Total RAM allocation (X)
@export var max_concurrent_enemies: int = 5  # Limit chasing you at once (Y)
@export var total_enemies_in_wave: int = 5   # Total limit before stopping

@export_category("Swarm Settings")
@export var base_speed: float = 4.5
@export var respawn_distance: float = 25.0   # Where they spawn
@export var despawn_distance: float = 60.0   # When they teleport back (keep much larger)

@onready var multi_mesh_instance = $MultiMeshInstance3D
@onready var multimesh = multi_mesh_instance.multimesh

# --- POOL TRACKERS ---
var alive_count: int = 0
var total_spawned_count: int = 0
var highest_active_index: int = 0

var positions = PackedVector3Array()
var velocities = PackedVector3Array()
var states = PackedInt32Array() # 0 = Dead, 1 = Alive

var speed_variances = PackedFloat32Array()
var preferred_distances_sq = PackedFloat32Array()
var orbital_speeds = PackedFloat32Array()

var swarm_anchor: Vector3 = Vector3.ZERO

func _ready():
	# Initialize pool memory
	multimesh.instance_count = pool_size
	# We set this to pool_size so we don't have to update it constantly.
	# We hide "dead" enemies by moving them to Y = -1000.
	multimesh.visible_instance_count = pool_size

	positions.resize(pool_size)
	velocities.resize(pool_size)
	states.resize(pool_size)
	speed_variances.resize(pool_size)
	preferred_distances_sq.resize(pool_size)
	orbital_speeds.resize(pool_size)

	for i in range(pool_size):
		states[i] = 0
		var hidden_transform = Transform3D(Basis(), Vector3(0, -1000, 0))
		multimesh.set_instance_transform(i, hidden_transform)
		# Initialize color to white so they aren't black meshes
		multimesh.set_instance_color(i, Color.WHITE)

func _process(_delta):
	# Spawns 1 enemy per frame until we hit the 'max_concurrent' limit
	if player and alive_count < max_concurrent_enemies:
		if total_enemies_in_wave == -1 or total_spawned_count < total_enemies_in_wave:
			spawn_at_random_edge()

func spawn_at_random_edge():
	var random_angle = randf() * TAU
	var spawn_pos = player.global_position + Vector3(cos(random_angle), 0, sin(random_angle)) * respawn_distance
	spawn_enemy(spawn_pos)

func spawn_enemy(spawn_pos: Vector3):
	var target_idx = -1
	for i in range(pool_size):
		if states[i] == 0:
			target_idx = i
			break

	if target_idx == -1: return

	# Reset data
	positions[target_idx] = spawn_pos
	velocities[target_idx] = Vector3.ZERO
	speed_variances[target_idx] = randf_range(0.8, 1.3)
	preferred_distances_sq[target_idx] = pow(randf_range(3.0, 14.0), 2)
	orbital_speeds[target_idx] = randf_range(0.5, 2.0) * (1.0 if randf() > 0.5 else -1.0)

	states[target_idx] = 1
	alive_count += 1
	total_spawned_count += 1

	if target_idx >= highest_active_index:
		highest_active_index = target_idx + 1

func kill_enemy(idx: int):
	if states[idx] == 0: return
	states[idx] = 0
	alive_count -= 1
	# Move them away instantly
	multimesh.set_instance_transform(idx, Transform3D(Basis(), Vector3(0, -1000, 0)))

func _physics_process(delta):
	if not player or alive_count == 0: return

	var player_pos = player.global_position
	var time_sec = Time.get_ticks_msec() / 1000.0
	var frames = Engine.get_frames_drawn()
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	query.collision_mask = terrain_collision_mask

	for i in range(highest_active_index):
		if states[i] == 0: continue

		var current_pos = positions[i]
		var dist_to_player_sq = current_pos.distance_squared_to(player_pos)

		# TETHERING / AUTO-RESPAWN
		if dist_to_player_sq > (despawn_distance * despawn_distance):
			var random_angle = randf() * TAU
			current_pos = player_pos + Vector3(cos(random_angle), 0, sin(random_angle)) * respawn_distance
			positions[i] = current_pos
			velocities[i] = Vector3.ZERO
			continue

		var dir_to_player = (player_pos - current_pos).normalized() if dist_to_player_sq > 0.1 else Vector3.FORWARD
		var desired_velocity = Vector3.ZERO

		# MOVEMENT LOGIC
		if dist_to_player_sq > 400.0:
			desired_velocity = dir_to_player * (base_speed * speed_variances[i])
		else:
			var dist_err = dist_to_player_sq - preferred_distances_sq[i]
			var agitation = 1.0
			var fwd_speed = 0.0

			if dist_err > 2.0: fwd_speed = base_speed * speed_variances[i]
			elif dist_err > -1.0: agitation = 0.05
			else: fwd_speed = -1.5; agitation = 0.2

			var tangent = Vector3.UP.cross(dir_to_player).normalized()
			var orbit = tangent * (orbital_speeds[i] * agitation)
			var noise = Vector3(sin(time_sec * 3.0 + i), 0, cos(time_sec * 2.5 + i)) * agitation

			desired_velocity = (dir_to_player * fwd_speed) + orbit + noise

		velocities[i] = velocities[i].lerp(desired_velocity, 5.0 * delta)
		current_pos += velocities[i] * delta

		# VOXEL GROUND SNAPPING
		if frames % 10 == i % 10:
			query.from = current_pos + Vector3(0, 20, 0)
			query.to = current_pos + Vector3(0, -20, 0)
			var res = space_state.intersect_ray(query)
			if res: current_pos.y = res.position.y + 0.5 # Small offset for visibility

		positions[i] = current_pos

		# UPDATE TRANSFORM
		var t = Transform3D()
		if dir_to_player.length_squared() > 0.01:
			t = t.looking_at(-dir_to_player, Vector3.UP) # Adjust facing direction as needed
		t.origin = current_pos
		multimesh.set_instance_transform(i, t)
