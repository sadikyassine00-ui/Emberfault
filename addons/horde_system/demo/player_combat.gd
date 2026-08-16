extends Node3D

@export var horde_manager: Node
@export var health_component: Node
@export var attack_radius: float = 4.0
@export var attack_damage: float = 15.0

@export var churn_test_active: bool = false
var _churn_timer: float = 0.0

func _ready() -> void:
	if health_component:
		health_component.died.connect(_on_died)
	
	if not horde_manager:
		var root = get_tree().current_scene
		if root.has_node("HordeManager"):
			horde_manager = root.get_node("HordeManager")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"): # Generic attack input
		attack_swarm()
	elif event.is_action_pressed("ui_up"): # Toggle churn test
		churn_test_active = not churn_test_active
		print("Churn test active: ", churn_test_active)

func _process(delta: float) -> void:
	if churn_test_active and horde_manager:
		_churn_timer += delta
		if _churn_timer > 0.1: # Deal massive AoE damage every 0.1s
			_churn_timer = 0.0
			attack_swarm()
			if Time.get_ticks_msec() % 1000 < 100:
				pass # Suppress profiling spam

func attack_swarm() -> void:
	if not horde_manager: return
	
	var swarm_processor = horde_manager.swarm_processor
	if not swarm_processor: return
	
	# Only the demo knows about this specific radius query
	var enemies_in_range: PackedInt64Array = swarm_processor.get_enemies_in_radius(global_position, attack_radius, horde_manager)
	
	if enemies_in_range.size() > 0:
		var dmg_info = DamageInfo.new()
		dmg_info.amount = attack_damage
		dmg_info.source_position = global_position
		
		# Apply damage
		horde_manager.deal_damage(enemies_in_range, -1.0, global_position, 14.0, dmg_info)

func take_damage(damage_info: DamageInfo) -> void:
	if health_component:
		health_component.take_damage(damage_info)

func _on_died() -> void:
	print("Player died!")
