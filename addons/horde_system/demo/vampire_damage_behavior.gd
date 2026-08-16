class_name VampireDamageBehavior
extends DamageBehavior

@export var base_damage: float = 12.0
@export var lifesteal_amount: float = 5.0

func calculate(attacker_id: int, target_id: int, is_melee: bool) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = base_damage
	
	if is_melee:
		info.amount += 3.0
		info.is_critical = true
	
	# Demonstrate custom side-effects without touching core
	print("[VAMPIRE] Entity %d dealt %.1f damage to %d and lifestealed %.1f HP!" % [attacker_id, info.amount, target_id, lifesteal_amount])
	
	return info
