extends Node

# --- LEGACY RESOURCE ENUM ---
enum ResourceType {
	WOOD = 0,
	STONE = 1,
	ENERGY_CORES = 2
}

# --- SIGNALS ---
signal resource_changed(type: ResourceType, amount_changed: int, current_total: int) # Legacy compatibility
signal item_changed(item_data: Resource, amount_changed: int, current_total: int)
signal inventory_updated()

# Mapping legacy enum IDs to item string IDs
const LEGACY_ID_MAP = {
	ResourceType.WOOD: "wood",
	ResourceType.STONE: "stone",
	ResourceType.ENERGY_CORES: "energy_core"
}

# Registered ItemData database: item_id -> ItemData (Resource)
var registered_items: Dictionary = {}

# Inventory counts: item_id -> int
var item_counts: Dictionary = {}

# Legacy inventory compatibility dictionary
var inventory: Dictionary = {
	ResourceType.WOOD: 0,
	ResourceType.STONE: 0,
	ResourceType.ENERGY_CORES: 0
}

func _ready() -> void:
	_load_default_item_resources()

func _load_default_item_resources() -> void:
	var default_paths = {
		"wood": "res://resources/items/wood.tres",
		"stone": "res://resources/items/stone.tres",
		"energy_core": "res://resources/items/energy_core.tres"
	}

	for item_id in default_paths:
		var path: String = default_paths[item_id]
		if ResourceLoader.exists(path):
			var res = load(path) as Resource
			if res:
				register_item(res)
		else:
			# Fallback procedural ItemData if file is missing
			var fallback_script = load("res://systems/core/item_data.gd")
			if fallback_script:
				var fallback = fallback_script.new()
				fallback.id = item_id
				fallback.name = item_id.capitalize()
				fallback.category = 0
				register_item(fallback)

## Register an ItemData definition into the global registry
func register_item(item_data: Resource) -> void:
	if not item_data or not ("id" in item_data) or item_data.id.is_empty():
		return
	registered_items[item_data.id] = item_data
	if not item_counts.has(item_data.id):
		item_counts[item_data.id] = 0

## Add items using an ItemData resource reference
func add_item(item_data: Resource, amount: int) -> void:
	if not item_data or not ("id" in item_data) or amount <= 0:
		return

	if not registered_items.has(item_data.id):
		register_item(item_data)

	var current: int = item_counts.get(item_data.id, 0)
	var new_total: int = current + amount
	item_counts[item_data.id] = new_total

	# Sync legacy enum inventory if applicable
	for legacy_enum in LEGACY_ID_MAP:
		if LEGACY_ID_MAP[legacy_enum] == item_data.id:
			inventory[legacy_enum] = new_total
			resource_changed.emit(legacy_enum, amount, new_total)
			break

	item_changed.emit(item_data, amount, new_total)
	inventory_updated.emit()

## Add items using string ID
func add_item_by_id(item_id: String, amount: int) -> void:
	if registered_items.has(item_id):
		add_item(registered_items[item_id], amount)

## Legacy method compatibility
func add_resource(type: ResourceType, amount: int) -> void:
	var item_id: String = LEGACY_ID_MAP.get(type, "")
	if registered_items.has(item_id):
		add_item(registered_items[item_id], amount)
	else:
		var current: int = inventory.get(type, 0)
		var new_total: int = current + amount
		inventory[type] = new_total
		resource_changed.emit(type, amount, new_total)
		inventory_updated.emit()

func get_item_count(item_data: Resource) -> int:
	if not item_data or not ("id" in item_data):
		return 0
	return item_counts.get(item_data.id, 0)

func get_item_count_by_id(item_id: String) -> int:
	return item_counts.get(item_id, 0)

func get_resource(type: ResourceType) -> int:
	return inventory.get(type, 0)

## Get all items in inventory with quantity > 0 or matching category filter
func get_inventory_items(category_filter: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id in item_counts:
		var count: int = item_counts[item_id]
		if count > 0 and registered_items.has(item_id):
			var item_data: Resource = registered_items[item_id]
			var cat: int = item_data.get("category") if "category" in item_data else 0
			if category_filter == -1 or cat == category_filter:
				result.append({
					"item_data": item_data,
					"count": count
				})
	return result


func can_afford(cost_dict: Dictionary) -> bool:
	for type_key in cost_dict:
		var req_amount: int = cost_dict[type_key]
		var current_amount: int = 0

		if type_key is Resource and "id" in type_key:
			current_amount = get_item_count(type_key as Resource)
		elif type_key is String:
			current_amount = get_item_count_by_id(type_key as String)
		else:
			current_amount = inventory.get(type_key, 0)

		if current_amount < req_amount:
			return false
	return true

func spend_resources(cost_dict: Dictionary) -> bool:
	if not can_afford(cost_dict):
		return false

	for type_key in cost_dict:
		var req_amount: int = cost_dict[type_key]

		if type_key is Resource and "id" in type_key:
			var item: Resource = type_key as Resource
			var item_id: String = item.get("id")
			var new_total: int = get_item_count_by_id(item_id) - req_amount
			item_counts[item_id] = new_total
			item_changed.emit(item, -req_amount, new_total)
		elif type_key is String:
			var item_id: String = type_key as String
			var new_total: int = get_item_count_by_id(item_id) - req_amount
			item_counts[item_id] = new_total
			if registered_items.has(item_id):
				item_changed.emit(registered_items[item_id], -req_amount, new_total)
		else:
			var current_amount: int = inventory.get(type_key, 0)
			var new_total: int = current_amount - req_amount
			inventory[type_key] = new_total

			var item_id: String = LEGACY_ID_MAP.get(type_key, "")
			if registered_items.has(item_id):
				item_counts[item_id] = new_total
				item_changed.emit(registered_items[item_id], -req_amount, new_total)

			resource_changed.emit(type_key, -req_amount, new_total)

	inventory_updated.emit()
	return true

func reset_inventory() -> void:
	for item_id in item_counts:
		item_counts[item_id] = 0
		if registered_items.has(item_id):
			item_changed.emit(registered_items[item_id], 0, 0)

	for type_key in inventory:
		inventory[type_key] = 0
		resource_changed.emit(type_key, 0, 0)

	inventory_updated.emit()
