extends Node

# --- SIGNALS ---
signal resource_changed(type: ResourceType, amount_changed: int, current_total: int)

# --- RESOURCE ENUM ---
enum ResourceType {
	WOOD = 0,
	STONE = 1,
	ENERGY_CORES = 2
}

# --- INVENTORY DICTIONARY (O(1) FAST LOOKUP) ---
var inventory: Dictionary = {
	ResourceType.WOOD: 0,
	ResourceType.STONE: 0,
	ResourceType.ENERGY_CORES: 0
}

func _ready() -> void:
	# Ensure default keys exist in inventory
	if not inventory.has(ResourceType.WOOD):
		inventory[ResourceType.WOOD] = 0
	if not inventory.has(ResourceType.STONE):
		inventory[ResourceType.STONE] = 0
	if not inventory.has(ResourceType.ENERGY_CORES):
		inventory[ResourceType.ENERGY_CORES] = 0

## Add resources to inventory and emit reactive signal
func add_resource(type: ResourceType, amount: int) -> void:
	if amount <= 0:
		return
	var current: int = inventory.get(type, 0)
	var new_total: int = current + amount
	inventory[type] = new_total
	resource_changed.emit(type, amount, new_total)

## Get current amount of specific resource type
func get_resource(type: ResourceType) -> int:
	return inventory.get(type, 0)

## Check if player can afford the cost dictionary without modifying inventory
func can_afford(cost_dict: Dictionary) -> bool:
	for type_key in cost_dict:
		var req_amount: int = cost_dict[type_key]
		var current_amount: int = inventory.get(type_key, 0)
		if current_amount < req_amount:
			return false
	return true

## Atomic resource deduction: returns true and deducts resources ONLY if player can afford all costs
func spend_resources(cost_dict: Dictionary) -> bool:
	if not can_afford(cost_dict):
		return false

	# Deduct resources atomically
	for type_key in cost_dict:
		var req_amount: int = cost_dict[type_key]
		var current_amount: int = inventory.get(type_key, 0)
		var new_total: int = current_amount - req_amount
		inventory[type_key] = new_total
		resource_changed.emit(type_key, -req_amount, new_total)

	return true

## Reset inventory (utility for level restarts or testing)
func reset_inventory() -> void:
	for type_key in inventory:
		inventory[type_key] = 0
		resource_changed.emit(type_key, 0, 0)
