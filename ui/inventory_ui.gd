extends Control
class_name InventoryUI

@onready var grid_container: GridContainer = %GridContainer

const MAX_SLOTS: int = 36 # 6x6 Grid

# Slot UI references (0 to 35)
var slot_panels: Array[PanelContainer] = []
# Mapping of ResourceType ID to assigned slot index (e.g. {0: 0, 1: 1})
var assigned_slots: Dictionary = {}
var icon_textures: Dictionary = {}

# Resource config
const RESOURCE_CONFIG = {
	0: {"name": "Wood", "color": Color(0.68, 0.46, 0.24), "border": Color(0.85, 0.60, 0.35)}, # WOOD
	1: {"name": "Stone", "color": Color(0.55, 0.58, 0.65), "border": Color(0.75, 0.78, 0.85)}, # STONE
	2: {"name": "Cores", "color": Color(0.12, 0.78, 0.96), "border": Color(0.40, 0.90, 1.00)}  # ENERGY_CORES
}

func _ready() -> void:
	_generate_placeholder_icons()
	_build_6x6_grid()
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

## Generate crisp procedural placeholder textures for each resource type
func _generate_placeholder_icons() -> void:
	for type_id in RESOURCE_CONFIG.keys():
		var cfg = RESOURCE_CONFIG[type_id]
		icon_textures[type_id] = _create_icon_texture(cfg["color"], cfg["border"], type_id)

func _create_icon_texture(fill_color: Color, border_color: Color, type_id: int) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # Transparent background

	var center := Vector2i(32, 32)
	for x in range(64):
		for y in range(64):
			var p := Vector2i(x, y)
			var d := (p - center).length()

			if d <= 26.0:
				var alpha: float = smoothstep(26.0, 24.0, d)
				var c := fill_color

				if type_id == 0: # Wood: Ring grain
					if abs(d - 12.0) < 2.0 or abs(d - 19.0) < 1.5:
						c = c.darkened(0.25)
				elif type_id == 1: # Stone: Facet cut
					if (x + y) % 16 < 4 or (x - y) % 16 < 3:
						c = c.lightened(0.15)
				elif type_id == 2: # Energy Core: Glowing inner core
					if d <= 12.0:
						c = Color(0.9, 1.0, 1.0, 1.0)
					elif d <= 18.0:
						c = c.lightened(0.4)

				c.a = alpha
				img.set_pixel(x, y, c)
			elif d <= 28.0:
				var border_alpha: float = smoothstep(28.0, 26.0, d)
				var bc := border_color
				bc.a = border_alpha
				img.set_pixel(x, y, bc)

	return ImageTexture.create_from_image(img)

## Build 36 empty grid slots (6 columns x 6 rows)
func _build_6x6_grid() -> void:
	if not grid_container:
		return

	grid_container.columns = 6

	for child in grid_container.get_children():
		child.queue_free()

	slot_panels.clear()
	assigned_slots.clear()

	for i in range(MAX_SLOTS):
		var panel := _create_empty_slot_node(i)
		grid_container.add_child(panel)
		slot_panels.append(panel)

func _create_empty_slot_node(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Slot_" + str(index)
	panel.custom_minimum_size = Vector2(52, 52)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.80)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.20, 0.30, 0.48, 0.45)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var icon_rect := TextureRect.new()
	icon_rect.name = "IconRect"
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(34, 34)
	icon_rect.visible = false # Hidden when empty
	margin.add_child(icon_rect)

	var label_container := Control.new()
	label_container.layout_mode = 1
	label_container.anchors_preset = PRESET_FULL_RECT
	margin.add_child(label_container)

	var amount_label := Label.new()
	amount_label.name = "AmountLabel"
	amount_label.anchors_preset = PRESET_BOTTOM_RIGHT
	amount_label.grow_horizontal = GROW_DIRECTION_BEGIN
	amount_label.grow_vertical = GROW_DIRECTION_BEGIN
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_label.text = ""
	amount_label.add_theme_font_size_override("font_size", 12)
	amount_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	amount_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	amount_label.add_theme_constant_override("outline_size", 4)
	label_container.add_child(amount_label)

	return panel

func _refresh_all_totals() -> void:
	var res_mgr = get_tree().root.get_node_or_null("ResourceManager")
	if not res_mgr:
		return

	if res_mgr.has_method("get_resource"):
		for type_id in RESOURCE_CONFIG.keys():
			_update_slot(type_id, res_mgr.get_resource(type_id))

func _on_resource_changed(type: int, _amount_changed: int, current_total: int) -> void:
	_update_slot(type, current_total)

func _update_slot(type_id: int, total: int) -> void:
	if total > 0:
		# If item is not yet assigned a slot in the grid, append it to the first free slot
		if not assigned_slots.has(type_id):
			var free_index := _find_first_free_slot()
			if free_index != -1:
				assigned_slots[type_id] = free_index

		if assigned_slots.has(type_id):
			var slot_idx: int = assigned_slots[type_id]
			var panel := slot_panels[slot_idx]
			var icon_rect: TextureRect = panel.find_child("IconRect", true, false) as TextureRect
			var amount_label: Label = panel.find_child("AmountLabel", true, false) as Label

			if icon_rect:
				icon_rect.texture = icon_textures[type_id]
				icon_rect.visible = true
				icon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)

			if amount_label:
				amount_label.text = str(total)
	else:
		# If count drops to 0, clear the slot
		if assigned_slots.has(type_id):
			var slot_idx: int = assigned_slots[type_id]
			var panel := slot_panels[slot_idx]
			var icon_rect: TextureRect = panel.find_child("IconRect", true, false) as TextureRect
			var amount_label: Label = panel.find_child("AmountLabel", true, false) as Label

			if icon_rect:
				icon_rect.texture = null
				icon_rect.visible = false

			if amount_label:
				amount_label.text = ""

			assigned_slots.erase(type_id)

func _find_first_free_slot() -> int:
	var used_indices := assigned_slots.values()
	for i in range(MAX_SLOTS):
		if not (i in used_indices):
			return i
	return -1
