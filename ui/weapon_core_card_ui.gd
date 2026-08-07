extends PanelContainer
class_name WeaponCoreCardUI

signal card_selected(core_data: WeaponCoreData)

@onready var slot_badge_label: Label = %SlotBadgeLabel if has_node("%SlotBadgeLabel") else null
@onready var slot_badge_panel: PanelContainer = %SlotBadgePanel if has_node("%SlotBadgePanel") else null
@onready var rarity_label: Label = %RarityLabel if has_node("%RarityLabel") else null
@onready var icon_rect: TextureRect = %IconRect if has_node("%IconRect") else null
@onready var title_label: Label = %TitleLabel if has_node("%TitleLabel") else null
@onready var description_label: Label = %DescriptionLabel if has_node("%DescriptionLabel") else null
@onready var equipped_banner: PanelContainer = %EquippedBanner if has_node("%EquippedBanner") else null
@onready var equipped_label: Label = %EquippedLabel if has_node("%EquippedLabel") else null
@onready var border_glow: ReferenceRect = %BorderGlow if has_node("%BorderGlow") else null

var core_data: WeaponCoreData = null
var current_equipped: WeaponCoreData = null
var _scale_tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(330, 440)
	pivot_offset = Vector2(165, 220)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func setup(data: WeaponCoreData, currently_equipped_core: WeaponCoreData = null) -> void:
	core_data = data
	current_equipped = currently_equipped_core
	_update_card_display()

func _update_card_display() -> void:
	if not core_data:
		return

	if slot_badge_label:
		slot_badge_label.text = core_data.get_slot_name()

	if rarity_label:
		rarity_label.text = core_data.get_rarity_name()
		rarity_label.add_theme_color_override("font_color", core_data.get_rarity_color())

	if title_label:
		title_label.text = core_data.title

	if description_label:
		description_label.text = core_data.description

	if icon_rect:
		if core_data.icon:
			icon_rect.texture = core_data.icon
			icon_rect.visible = true
			icon_rect.modulate = Color.WHITE
		else:
			icon_rect.modulate = core_data.accent_color

	if equipped_banner and equipped_label:
		if current_equipped:
			equipped_banner.visible = true
			equipped_label.text = "REPLACES: " + current_equipped.title
			equipped_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
		else:
			equipped_banner.visible = true
			equipped_label.text = "NEW SLOT CORE"
			equipped_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5, 1.0))

	if border_glow:
		border_glow.modulate = core_data.accent_color

func _on_mouse_entered() -> void:
	_animate_scale(1.05, 0.15)
	if border_glow:
		border_glow.visible = true

func _on_mouse_exited() -> void:
	_animate_scale(1.0, 0.15)
	if border_glow:
		border_glow.visible = false

func _animate_scale(target_scale: float, duration: float) -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), duration)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if core_data:
			card_selected.emit(core_data)
			get_viewport().set_input_as_handled()
