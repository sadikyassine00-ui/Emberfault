extends PanelContainer
class_name WeaponCoreCardUI

signal card_selected(core_data: WeaponCoreData)

@onready var slot_badge_label: Label = %SlotBadgeLabel if has_node("%SlotBadgeLabel") else null
@onready var slot_badge_panel: PanelContainer = %SlotBadgePanel if has_node("%SlotBadgePanel") else null
@onready var rarity_panel: PanelContainer = %RarityPanel if has_node("%RarityPanel") else null
@onready var rarity_label: Label = %RarityLabel if has_node("%RarityLabel") else null
@onready var icon_frame_rect: TextureRect = %IconFrameRect if has_node("%IconFrameRect") else null
@onready var icon_rect: TextureRect = %IconRect if has_node("%IconRect") else null
@onready var title_label: Label = %TitleLabel if has_node("%TitleLabel") else null
@onready var description_label: Label = %DescriptionLabel if has_node("%DescriptionLabel") else null
@onready var equipped_banner: PanelContainer = %EquippedBanner if has_node("%EquippedBanner") else null
@onready var equipped_label: Label = %EquippedLabel if has_node("%EquippedLabel") else null

var core_data: WeaponCoreData = null
var current_equipped: WeaponCoreData = null

var _hover_tween: Tween
var _flash_tween: Tween
var _base_y: float = 0.0
var _initialized_pos: bool = false
var _flash_material: ShaderMaterial

func _ready() -> void:
	custom_minimum_size = Vector2(340, 480)
	pivot_offset = Vector2(170, 240)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Initialize subtle hover flash shader material
	var shader := preload("res://shaders/card_hover_flash.gdshader")
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = shader
	_flash_material.set_shader_parameter("flash_intensity", 0.0)
	_flash_material.set_shader_parameter("flash_color", Color.WHITE)
	material = _flash_material

func setup(data: WeaponCoreData, currently_equipped_core: WeaponCoreData = null) -> void:
	core_data = data
	current_equipped = currently_equipped_core
	_update_card_display()

func _update_card_display() -> void:
	if not core_data:
		return

	var rarity_color := core_data.get_rarity_color()

	if slot_badge_label:
		slot_badge_label.text = core_data.get_slot_name()

	if rarity_panel and rarity_label:
		rarity_label.text = core_data.get_rarity_name()
		rarity_label.add_theme_color_override("font_color", rarity_color)

	if title_label:
		title_label.text = core_data.title
		title_label.add_theme_color_override("font_color", rarity_color)

	if description_label:
		description_label.text = core_data.description

	if icon_rect:
		if core_data.icon:
			icon_rect.texture = core_data.icon
			icon_rect.visible = true
			icon_rect.modulate = Color.WHITE
		else:
			icon_rect.modulate = rarity_color

	if icon_frame_rect:
		icon_frame_rect.modulate = Color.WHITE

	if equipped_banner and equipped_label:
		if current_equipped:
			equipped_banner.visible = true
			equipped_label.text = "REPLACES: " + current_equipped.title
			equipped_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
		else:
			equipped_banner.visible = true
			equipped_label.text = "UNBOUND SLOT"
			equipped_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55, 1.0))

func _on_mouse_entered() -> void:
	_trigger_hover_flash()
	_animate_hover(true)

func _on_mouse_exited() -> void:
	_animate_hover(false)

func _trigger_hover_flash() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	# Clean subtle white flash decaying in 0.15s
	_flash_material.set_shader_parameter("flash_color", Color.WHITE)
	_flash_material.set_shader_parameter("flash_intensity", 0.5)
	_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_intensity", 0.0, 0.15)

func _animate_hover(is_hovered: bool) -> void:
	if not _initialized_pos:
		_base_y = position.y
		_initialized_pos = true

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if is_hovered:
		# 1. Scale up card smoothly
		_hover_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.2)
		# 2. Lift card up by 12px
		_hover_tween.tween_property(self, "position:y", _base_y - 12.0, 0.2)
		# 3. Pop icon scale
		if icon_rect:
			_hover_tween.tween_property(icon_rect, "scale", Vector2(1.18, 1.18), 0.2)
	else:
		_hover_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.18)
		_hover_tween.tween_property(self, "position:y", _base_y, 0.18)
		if icon_rect:
			_hover_tween.tween_property(icon_rect, "scale", Vector2(1.0, 1.0), 0.18)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if core_data:
			card_selected.emit(core_data)
			get_viewport().set_input_as_handled()
