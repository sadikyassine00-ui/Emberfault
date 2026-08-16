class_name DefaultDamageBehavior
extends DamageBehavior

@export var amount: float = 2.0

func calculate(attacker_type_id: int, target_id: int, target_is_promoted: bool) -> DamageInfo:
	var info = DamageInfo.new()
	info.amount = amount
	return info
