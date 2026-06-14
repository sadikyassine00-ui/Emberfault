extends CharacterBody3D
class_name EnemyController

# THE MISSING ENUM IS RESTORED HERE
enum State { INACTIVE, CHASE, ATTACK }

@export var speed: float = 4.0
@export var despawn_distance: float = 60.0 # The Leash distance

var current_state: State = State.INACTIVE
var player_target: Node3D
var director: SwarmDirector

signal request_despawn(enemy_node)

func spawn(pos: Vector3, target: Node3D, swarm_director: SwarmDirector):
	velocity = Vector3.ZERO
	global_position = pos
	player_target = target
	director = swarm_director

	director.register_enemy(self)
	current_state = State.CHASE

	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT

func die():
	request_despawn.emit(self)

func _physics_process(delta):
	if current_state == State.INACTIVE or not player_target or not director:
		return

	# 1. THE LEASH: Despawn if they fall behind unloaded voxel chunks
	var dist_sq = global_position.distance_squared_to(player_target.global_position)
	if dist_sq > despawn_distance ** 2:
		request_despawn.emit(self)
		return

	# 2. GRAVITY
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 3. SLOT NAVIGATION
	var my_slot_pos = director.get_target_slot(self, player_target.global_position)
	var distance_to_slot = global_position.distance_to(my_slot_pos)

	if distance_to_slot > 0.5:
		current_state = State.CHASE
		var dir = global_position.direction_to(my_slot_pos)

		# Smoothly glide toward the slot
		velocity.x = lerpf(velocity.x, dir.x * speed, 8.0 * delta)
		velocity.z = lerpf(velocity.z, dir.z * speed, 8.0 * delta)
	else:
		current_state = State.ATTACK
		# Lock into the slot tightly
		velocity.x = lerpf(velocity.x, 0.0, 10.0 * delta)
		velocity.z = lerpf(velocity.z, 0.0, 10.0 * delta)

	move_and_slide()
