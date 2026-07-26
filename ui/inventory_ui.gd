extends Control
class_name InventoryUI

@onready var grid_container: GridContainer = %GridContainer

# Map resource types to slot UI nodes
var slots: Dictionary = {}
var icon_textures: Dictionary = {}

# Slot configuration data
const RESOURCE_CONFIG = {
	0: {"name": "Wood", "color": Color(0.68, 0.46, 0.24), "border": Color(0.85, 0.60, 0.35)}, # WOOD
	1: {"name": "Stone", "color": Color(0.55, 0.58, 0.65), "border": Color(0.75, 0.78, 0.85)}, # STONE
	2: {"name": "Cores", "color": Color(0.12, 0.78, 0.96), "border": Color(0.40, 0.90, 1.00)}  # ENERGY_CORES
}

func _ready() -> void:
	_generate_placeholder_icons()
	_build_grid_slots()
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
			
			# Circular badge icon with stylized inner emblem
			if d <= 26.0:
				var alpha: float = smoothstep(26.0, 24.0, d)
				var c := fill_color
				
				# Add inner visual pattern based on type
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

## Construct grid slots dynamically
func _build_grid_slots() -> void:
	if not grid_container:
		return

	# Clear existing children if any
	for child in grid_container.get_children():
		child.queue_free()

	slots.clear()

	for type_id in RESOURCE_CONFIG.keys():
		var slot_panel := _create_slot_node(type_id)
		grid_container.add_child(slot_panel)
		slots[type_id] = slot_panel

func _create_slot_node(type_id: int) -> PanelContainer:
	var cfg = RESOURCE_CONFIG[type_id]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(68, 68)

	# Custom StyleBox for individual slot card
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.25, 0.35, 0.55, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	panel.add_theme_stylebox_override("panel", style)

	# Main Margin Container
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	# Icon TextureRect
	var icon_rect := TextureRect.new()
	icon_rect.name = "IconRect"
	icon_rect.texture = icon_textures[type_id]
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(44, 44)
	icon_rect.modulate = Color(1, 1, 1, 0.35) # Dimmed when empty
	margin.add_child(icon_rect)

	# Bottom-Right Amount Label Container
	var label_container := Control.new()
	label_container.layout_mode = 1 # Anchors mode
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
	amount_label.add_theme_font_size_override("font_size", 13)
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
	if not slots.has(type_id):
		return

	var panel: PanelContainer = slots[type_id]
	var icon_rect: TextureRect = panel.find_child("IconRect", true, false) as TextureRect
	var amount_label: Label = panel.find_child("AmountLabel", true, false) as Label

	if total > 0:
		if icon_rect:
			icon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) # Full brightness when owned
		if amount_label:
			amount_label.text = str(total)
	else:
		if icon_rect:
			icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.35) # Dimmed when empty
		if amount_label:
			amount_label.text = ""
