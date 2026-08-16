class_name EnemyTypeDefinition
extends Resource

@export var damage_behavior: DamageBehavior
@export var attack_behavior: AttackBehavior
@export var death_behavior: DeathBehavior

@export var attack_animation_name: StringName = &"Attack"
@export var death_animation_name: StringName = &"Death"

func get_damage_behavior() -> DamageBehavior:
	if damage_behavior: return damage_behavior
	return DefaultDamageBehavior.new()

func get_attack_behavior() -> AttackBehavior:
	if attack_behavior: return attack_behavior
	return DefaultAttackBehavior.new()

func get_death_behavior() -> DeathBehavior:
	if death_behavior: return death_behavior
	return DefaultDeathBehavior.new()
