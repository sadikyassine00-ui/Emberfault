extends Resource
class_name EnemyStats

@export var enemy_name: String = "Grunt"
@export var base_speed: float = 6.0 # Increased for faster swarms
@export var health: float = 10.0
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 1.0
@export var damage: float = 5.0
@export var scale_multiplier: float = 1.0 # 1.0 for grunts, 3.0+ for Bosses
