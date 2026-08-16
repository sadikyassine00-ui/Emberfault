class_name DeathBehavior
extends Resource

## Override to spawn VFX, drop loot, etc. Called AFTER the entity/slot is
## already cleaned up in HordeManager — do not assume the array slot is
## still valid, use the passed-in death_position and type_id only.
func on_death(death_position: Vector3, type_id: int) -> void:
	pass
