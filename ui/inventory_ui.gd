extends Control
class_name InventoryUI

@onready var wood_label: Label = %WoodLabel
@onready var stone_label: Label = %StoneLabel
@onready var cores_label: Label = %CoresLabel

func _ready() -> void:
	# Initial UI population from ResourceManager
	_refresh_all_totals()

	# Connect reactively to ResourceManager signal (NO _process polling!)
	var res_mgr = get_tree().root.get_node_or_null("ResourceManager")
	if res_mgr and res_mgr.has_signal("resource_changed"):
		res_mgr.resource_changed.connect(_on_resource_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_I:
			visible = not visible
			get_viewport().set_input_as_handled()

func _refresh_all_totals() -> void:
	var res_mgr = get_tree().root.get_node_or_null("ResourceManager")
	if not res_mgr:
		return

	if res_mgr.has_method("get_resource"):
		_update_label(0, res_mgr.get_resource(0))
		_update_label(1, res_mgr.get_resource(1))
		_update_label(2, res_mgr.get_resource(2))

func _on_resource_changed(type: int, _amount_changed: int, current_total: int) -> void:
	_update_label(type, current_total)

func _update_label(type: int, total: int) -> void:
	match type:
		0: # WOOD
			if wood_label:
				wood_label.text = "Wood: " + str(total)
		1: # STONE
			if stone_label:
				stone_label.text = "Stone: " + str(total)
		2: # ENERGY_CORES
			if cores_label:
				cores_label.text = "Cores: " + str(total)
