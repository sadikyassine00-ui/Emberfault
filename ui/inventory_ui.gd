extends Control
class_name InventoryUI

signal tab_changed(tab_name: String)

const TAB_BG: Texture2D = preload("res://Art/inventory_ui/tab_bg.png")
const TAB_ACTIVE: Texture2D = preload("res://Art/inventory_ui/tab_active.png")

@onready var main_panel: Control = %MainPanel if has_node("%MainPanel") else null
@onready var items_tab: TextureButton = get_node_or_null("TabHeaderBox/ItemsTab")
@onready var gear_tab: TextureButton = get_node_or_null("TabHeaderBox/GearTab")
@onready var misc_tab: TextureButton = get_node_or_null("TabHeaderBox/MiscTab")

var item_grid: GridContainer = null
var active_tab_name: String = "ITEMS"
var font_monogram: Font = preload("res://font/monogram.ttf")

func _ready() -> void:
	_center_main_panel()
	_setup_tabs()
	_setup_slots()
	_connect_resource_manager()
	update_inventory_display()

func _get_item_grid() -> GridContainer:
	if not item_grid or not is_instance_valid(item_grid):
		item_grid = get_node_or_null("ItemsPanelBox/Middle/MiddleBridge/ItemGridMargin/ItemGrid")
		if not item_grid:
			item_grid = find_child("ItemGrid", true, false) as GridContainer
	return item_grid

func _connect_resource_manager() -> void:
	var res_mgr := _get_resource_manager()
	if res_mgr:
		if res_mgr.has_signal("inventory_updated"):
			if not res_mgr.inventory_updated.is_connected(update_inventory_display):
				res_mgr.inventory_updated.connect(update_inventory_display)
		if res_mgr.has_signal("item_changed"):
			if not res_mgr.item_changed.is_connected(_on_item_changed):
				res_mgr.item_changed.connect(_on_item_changed)

func _get_resource_manager() -> Node:
	if is_inside_tree():
		var root_node := get_tree().root
		if root_node.has_node("ResourceManager"):
			return root_node.get_node("ResourceManager")
		var mgr := root_node.find_child("ResourceManager", true, false)
		if mgr:
			return mgr
		var p := get_parent()
		while p:
			if p.has_node("ResourceManager"):
				return p.get_node("ResourceManager")
			p = p.get_parent()
	return null

func _on_item_changed(_item_data: Resource, _amount: int, _total: int) -> void:
	update_inventory_display()

func _setup_tabs() -> void:
	if not items_tab: items_tab = get_node_or_null("TabHeaderBox/ItemsTab")
	if not gear_tab: gear_tab = get_node_or_null("TabHeaderBox/GearTab")
	if not misc_tab: misc_tab = get_node_or_null("TabHeaderBox/MiscTab")

	if items_tab and not items_tab.pressed.is_connected(_on_items_tab_pressed):
		items_tab.pressed.connect(_on_items_tab_pressed)
	if gear_tab and not gear_tab.pressed.is_connected(_on_gear_tab_pressed):
		gear_tab.pressed.connect(_on_gear_tab_pressed)
	if misc_tab and not misc_tab.pressed.is_connected(_on_misc_tab_pressed):
		misc_tab.pressed.connect(_on_misc_tab_pressed)

	set_active_tab("ITEMS")

func _on_items_tab_pressed() -> void:
	set_active_tab("ITEMS")

func _on_gear_tab_pressed() -> void:
	set_active_tab("GEAR")

func _on_misc_tab_pressed() -> void:
	set_active_tab("MISC")

func set_active_tab(tab_name: String) -> void:
	active_tab_name = tab_name

	_update_tab_button(items_tab, tab_name == "ITEMS")
	_update_tab_button(gear_tab, tab_name == "GEAR")
	_update_tab_button(misc_tab, tab_name == "MISC")

	update_inventory_display()
	tab_changed.emit(tab_name)

func _update_tab_button(button: TextureButton, is_active: bool) -> void:
	if not button:
		return

	button.texture_normal = TAB_ACTIVE if is_active else TAB_BG

	var label := button.get_node_or_null("Label") as Label
	if label:
		if is_active:
			label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85, 1.0))
		else:
			label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.46, 0.85))

func _setup_slots() -> void:
	var grid := _get_item_grid()
	if not grid:
		return

	for slot in grid.get_children():
		if slot is Control:
			_ensure_slot_child_nodes(slot)

func _ensure_slot_child_nodes(slot: Control) -> void:
	var icon_rect := slot.get_node_or_null("ItemIcon") as TextureRect
	if not icon_rect:
		icon_rect = TextureRect.new()
		icon_rect.name = "ItemIcon"
		icon_rect.layout_mode = 1
		icon_rect.anchors_preset = 15
		icon_rect.anchor_right = 1.0
		icon_rect.anchor_bottom = 1.0
		icon_rect.offset_left = 3
		icon_rect.offset_top = 3
		icon_rect.offset_right = -3
		icon_rect.offset_bottom = -3
		icon_rect.grow_horizontal = 2
		icon_rect.grow_vertical = 2
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.visible = false
		slot.add_child(icon_rect)

	var stack_label := slot.get_node_or_null("StackLabel") as Label
	if not stack_label:
		stack_label = Label.new()
		stack_label.name = "StackLabel"
		stack_label.layout_mode = 1
		stack_label.anchors_preset = 3
		stack_label.anchor_left = 1.0
		stack_label.anchor_top = 1.0
		stack_label.anchor_right = 1.0
		stack_label.anchor_bottom = 1.0
		stack_label.offset_left = -30
		stack_label.offset_top = -16
		stack_label.offset_right = -2
		stack_label.offset_bottom = -1
		stack_label.grow_horizontal = 0
		stack_label.grow_vertical = 0
		stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		if font_monogram:
			stack_label.add_theme_font_override("font", font_monogram)
		stack_label.add_theme_font_size_override("font_size", 14)
		stack_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.90, 1.0))
		stack_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.06, 0.02, 0.9))
		stack_label.add_theme_constant_override("shadow_offset_y", 1)
		stack_label.visible = false
		slot.add_child(stack_label)

func update_inventory_display() -> void:
	var grid := _get_item_grid()
	if not grid:
		return

	var res_mgr := _get_resource_manager()
	if not res_mgr:
		return

	var category_filter: int = _get_category_filter_for_tab(active_tab_name)
	var items: Array[Dictionary] = []

	if res_mgr.has_method("get_inventory_items"):
		items = res_mgr.get_inventory_items(category_filter)

	var slots := grid.get_children()
	for i in range(slots.size()):
		var slot := slots[i] as Control
		if not slot:
			continue

		_ensure_slot_child_nodes(slot)

		var icon_rect := slot.get_node_or_null("ItemIcon") as TextureRect
		var stack_label := slot.get_node_or_null("StackLabel") as Label

		if i < items.size():
			var item_info: Dictionary = items[i]
			var item_data: Resource = item_info.get("item_data")
			var count: int = item_info.get("count", 0)

			if item_data and count > 0:
				if icon_rect:
					var tex: Texture2D = item_data.get("icon") if ("icon" in item_data) else null
					icon_rect.texture = tex
					icon_rect.visible = (tex != null)

				if stack_label:
					stack_label.text = str(count)
					stack_label.visible = (count > 1)
			else:
				_clear_slot(icon_rect, stack_label)
		else:
			_clear_slot(icon_rect, stack_label)

func _clear_slot(icon_rect: TextureRect, stack_label: Label) -> void:
	if icon_rect:
		icon_rect.texture = null
		icon_rect.visible = false
	if stack_label:
		stack_label.text = ""
		stack_label.visible = false

func _get_category_filter_for_tab(tab_name: String) -> int:
	match tab_name:
		"ITEMS":
			return -1
		"GEAR":
			return ItemData.Category.EQUIPMENT
		"MISC":
			return ItemData.Category.QUEST
		_:
			return -1

func _center_main_panel() -> void:
	if main_panel:
		var vp_size := get_viewport_rect().size
		if vp_size != Vector2.ZERO:
			main_panel.global_position = (vp_size - main_panel.size) * 0.5

func _unhandled_input(event: InputEvent) -> void:
	var is_toggle := false
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_I:
			is_toggle = true
	elif InputMap.has_action("inventory") and Input.is_action_just_pressed("inventory"):
		is_toggle = true

	if is_toggle:
		visible = not visible
		if visible:
			_center_main_panel()
			_connect_resource_manager()
			update_inventory_display()
		get_viewport().set_input_as_handled()
