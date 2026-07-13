class_name HealthComponent
extends Node

signal health_changed(current_health: float, max_health: float)
signal damage_received(payload: DamagePayload)
signal entity_died

@export var max_health: float = 100.0
@onready var current_health: float = max_health

@export var is_invulnerable: bool = false
@export var iframe_duration: float = 0.2


func take_damage(payload: DamagePayload) -> void:
	if is_invulnerable or current_health <= 0.0:
		return

	# Scalable Hook: Apply mitigation matrices here (e.g., armor, resistances)
	var final_damage = payload.base_damage
	
	current_health = max(0.0, current_health - final_damage)
	health_changed.emit(current_health, max_health)
	damage_received.emit(payload)

	print("❤️ [%s] Hit! Damage: %f | Remaining Health: %f" % [get_parent().name, final_damage, current_health])

	if current_health <= 0.0:
		entity_died.emit()
		return

	# Trigger Invulnerability Windows if configured
	if iframe_duration > 0.0:
		is_invulnerable = true
		get_tree().create_timer(iframe_duration, true, false, false).timeout.connect(func():
			is_invulnerable = false
		)
