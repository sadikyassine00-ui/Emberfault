class_name DamagePayload
extends Resource

@export var base_damage: float = 10.0
@export var knockback_force: float = 5.0
@export var element_type: String = "Physical" # Scalable to "Fire", "Shatter", etc.
@export var critical_multiplier: float = 1.0
@export var is_critical: bool = false
