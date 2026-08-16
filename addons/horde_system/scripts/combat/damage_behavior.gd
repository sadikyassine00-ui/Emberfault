class_name DamageBehavior
extends Resource

## Override in a derived Resource. Return the DamageInfo to apply.
func calculate(attacker_type_id: int, target_id: int, target_is_promoted: bool) -> DamageInfo:
	push_warning("DamageBehavior.calculate() not overridden — returning zero damage")
	return DamageInfo.new()
