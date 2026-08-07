extends Control
class_name WeaponCoreDraftUI

signal draft_opened()
signal draft_closed()
signal core_selected(selected_core: WeaponCoreData)

const CARD_SCENE: PackedScene = preload("res://ui/WeaponCoreCardUI.tscn")

@onready var cards_container: HBoxContainer = %CardsContainer if has_node("%CardsContainer") else null
@onready var close_button: Button = %CloseButton if has_node("%CloseButton") else null
@onready var equipped_summary_label: Label = %EquippedSummaryLabel if has_node("%EquippedSummaryLabel") else null

var font_monogram: Font = preload("res://font/monogram.ttf")

func _ready() -> void:
	# Ensure UI processes while the rest of the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if close_button:
		close_button.pressed.connect(close_draft)

func open_draft(forced_choices: Array[WeaponCoreData] = []) -> void:
	var choices: Array[WeaponCoreData] = []
	if forced_choices.size() > 0:
		choices = forced_choices
	else:
		choices = WeaponCoreDatabase.get_random_draft_choices(3)

	_populate_cards(choices)
	_update_equipped_summary()

	visible = true
	get_tree().paused = true
	draft_opened.emit()

func close_draft() -> void:
	visible = false
	get_tree().paused = false
	draft_closed.emit()

func _populate_cards(choices: Array[WeaponCoreData]) -> void:
	if not cards_container:
		return

	# Clear previous cards
	for child in cards_container.get_children():
		child.queue_free()

	var player_mgr := _find_player_core_manager()

	for core in choices:
		if not core:
			continue
		var card := CARD_SCENE.instantiate() as WeaponCoreCardUI
		cards_container.add_child(card)

		var currently_equipped: WeaponCoreData = null
		if player_mgr:
			currently_equipped = player_mgr.get_equipped_core(core.slot)

		card.setup(core, currently_equipped)
		card.card_selected.connect(_on_card_selected)

func _on_card_selected(core: WeaponCoreData) -> void:
	var player_mgr := _find_player_core_manager()
	if player_mgr:
		player_mgr.equip_core(core)

	core_selected.emit(core)
	close_draft()

func _update_equipped_summary() -> void:
	if not equipped_summary_label:
		return

	var player_mgr := _find_player_core_manager()
	if not player_mgr:
		equipped_summary_label.text = "EQUIPPED: [Slot 1: None]  |  [Slot 2: None]  |  [Slot 3: None]"
		return

	var c1 := player_mgr.get_equipped_core(WeaponCoreData.SlotType.SLOT_1_PRIMARY)
	var c2 := player_mgr.get_equipped_core(WeaponCoreData.SlotType.SLOT_2_FINISHER)
	var c3 := player_mgr.get_equipped_core(WeaponCoreData.SlotType.SLOT_3_DASH)

	var s1 := c1.title if c1 else "Empty"
	var s2 := c2.title if c2 else "Empty"
	var s3 := c3.title if c3 else "Empty"

	equipped_summary_label.text = "EQUIPPED CORES:  [Primary: %s]  •  [Finisher: %s]  •  [Dash: %s]" % [s1, s2, s3]

func _find_player_core_manager() -> WeaponCoreManager:
	if not is_inside_tree():
		return null

	var current_scene := get_tree().current_scene
	if current_scene:
		var mgr := current_scene.find_child("WeaponCoreManager", true, false) as WeaponCoreManager
		if mgr:
			return mgr

	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		var mgr := p.find_child("WeaponCoreManager", true, false) as WeaponCoreManager
		if mgr:
			return mgr

	return null

func _unhandled_input(event: InputEvent) -> void:
	# Key trigger 'U' to open/close draft screen for quick testing
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_U:
			if visible:
				close_draft()
			else:
				open_draft()
			get_viewport().set_input_as_handled()
