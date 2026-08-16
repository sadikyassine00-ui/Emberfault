extends Node

@export var max_health: float = 100.0
var current_health: float

signal health_changed(new_health: float, old_health: float)
signal died()

func _ready() -> void:
	current_health = max_health

func take_damage(damage_info: DamageInfo) -> void:
	if current_health <= 0:
		return
	
	var old_health := current_health
	current_health -= damage_info.amount
	current_health = max(0.0, current_health)
	
	health_changed.emit(current_health, old_health)
	
	if current_health <= 0:
		died.emit()
