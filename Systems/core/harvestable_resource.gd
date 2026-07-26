extends Node3D
class_name HarvestableResource

signal harvested(resource_type: int, yield_amount: int)

@export var resource_name: String = "Wood Tree"
@export_enum("WOOD", "STONE", "ENERGY_CORES") var resource_type: int = 0
@export var yield_amount: int = 10
@export var max_durability: int = 3

var current_durability: int = 3

func _ready() -> void:
	current_durability = max_durability
	add_to_group("harvestables")

## Call when hitting, mining, or harvesting this resource node
func harvest(damage: int = 1) -> void:
	if current_durability <= 0:
		return

	current_durability -= damage
	var hp_percent: float = maxf(0.0, (float(current_durability) / float(max_durability)) * 100.0)

	print("[HARVEST] Hit \"%s\" | Damage: %d | Durability: %d/%d (%.1f%%)" % [
		resource_name,
		damage,
		maxf(0.0, current_durability),
		max_durability,
		hp_percent
	])

	if current_durability <= 0:
		_grant_and_destroy()

func _grant_and_destroy() -> void:
	var res_type_name: String = "WOOD"
	match resource_type:
		0: res_type_name = "WOOD"
		1: res_type_name = "STONE"
		2: res_type_name = "ENERGY_CORES"

	var total_count: int = 0
	if is_inside_tree():
		var res_mgr = get_tree().root.get_node_or_null("ResourceManager")
		if res_mgr:
			if res_mgr.has_method("add_resource"):
				res_mgr.add_resource(resource_type, yield_amount)
			if res_mgr.has_method("get_resource"):
				total_count = res_mgr.get_resource(resource_type)

	print("[HARVEST COMPLETE] Destroyed \"%s\" | Gained: +%d %s | Total Inventory: %d %s" % [
		resource_name,
		yield_amount,
		res_type_name,
		total_count,
		res_type_name
	])

	harvested.emit(resource_type, yield_amount)

	var parent_node := get_parent()
	if parent_node and parent_node != get_tree().root:
		parent_node.queue_free()
	else:
		queue_free()
