extends Node
class_name BuildingManager

signal building_state_changed(is_enabled: bool)

@export_category("Bindings")
@export var cycle_controller: Node # Node export avoids class-cache indexing race conditions

var is_building_allowed: bool = true

func _ready() -> void:
	if not cycle_controller:
		cycle_controller = _find_node_in_tree("DayNightCycleController")

	if cycle_controller:
		if "day_started" in cycle_controller:
			var day_sig: Signal = cycle_controller.get("day_started")
			if day_sig and not day_sig.is_connected(_on_day_started):
				day_sig.connect(_on_day_started)
		if "night_started" in cycle_controller:
			var night_sig: Signal = cycle_controller.get("night_started")
			if night_sig and not night_sig.is_connected(_on_night_started):
				night_sig.connect(_on_night_started)

	# Initial state check
	if cycle_controller and "current_phase" in cycle_controller and cycle_controller.current_phase == 2: # 2 = NIGHT
		_set_building_allowed(false)
	else:
		_set_building_allowed(true)

func _find_node_in_tree(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var root_node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if root_node:
		return root_node.find_child(node_name, true, false)
	return null

func _on_day_started() -> void:
	print("🔨 [BUILDING MANAGER] Peace time started. Construction & trap placement ENABLED.")
	_set_building_allowed(true)

func _on_night_started() -> void:
	print("🚫 [BUILDING MANAGER] Night siege started. Construction & trap placement DISABLED.")
	_set_building_allowed(false)

func _set_building_allowed(allowed: bool) -> void:
	if is_building_allowed != allowed:
		is_building_allowed = allowed
		building_state_changed.emit(is_building_allowed)
