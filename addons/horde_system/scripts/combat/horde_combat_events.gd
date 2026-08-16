extends Node

signal enemy_attacked(attacker_id: int, attacker_is_promoted: bool, target: Node, damage_info: DamageInfo)
signal enemy_took_damage(enemy_id: int, enemy_is_promoted: bool, damage_info: DamageInfo)
signal enemy_died(enemy_id: int, enemy_is_promoted: bool, death_position: Vector3, type_id: int)
signal player_attacked_enemy(player_node: Node, enemy_id: int, enemy_is_promoted: bool, damage_info: DamageInfo)
