extends Node
class_name EnemyPool

@export var enemy_scene: PackedScene
@export var initial_pool_size: int = 400
@export var swarm_director: SwarmDirector

var _pool: Array[EnemyController] = []

func _ready():
	for i in range(initial_pool_size):
		var enemy = enemy_scene.instantiate() as EnemyController
		add_child(enemy)

		# Connect the leash/death signal to the despawn function safely
		enemy.request_despawn.connect(_deactivate_enemy)

		_deactivate_enemy(enemy)
		_pool.append(enemy)

func request_enemy(pos: Vector3, target: Node3D):
	for enemy in _pool:
		# NOW THE ENUM REFERENCE WORKS PERFECTLY
		if enemy.current_state == EnemyController.State.INACTIVE:
			enemy.spawn(pos, target, swarm_director)
			return enemy
	return null

func _deactivate_enemy(enemy: EnemyController):
	enemy.current_state = EnemyController.State.INACTIVE
	enemy.visible = false
	enemy.process_mode = Node.PROCESS_MODE_DISABLED

	# Free up the slot mathematically so the next enemy moves up in rank
	if swarm_director:
		swarm_director.unregister_enemy(enemy)
