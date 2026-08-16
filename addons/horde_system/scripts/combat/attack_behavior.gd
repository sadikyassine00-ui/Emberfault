class_name AttackBehavior
extends Resource

@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.0

## Override to customize attack timing/targeting logic beyond range+cooldown.
## Return true if an attack should fire this check.
func should_attack(distance_to_target: float, cooldown_remaining: float) -> bool:
	return distance_to_target <= attack_range and cooldown_remaining <= 0.0
