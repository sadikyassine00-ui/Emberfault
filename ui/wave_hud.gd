extends CanvasLayer
class_name WaveHUD

@export_category("Bindings")
@export var director: DirectorStateController
@export var cycle_controller: Node
@export var pre_start_countdown_seconds: int = 10

@onready var margin_container: Control = $MarginContainer
@onready var timer_box: VBoxContainer = $MarginContainer/TopCenter_TimerBox
@onready var phase_name_label: Label = $MarginContainer/TopCenter_TimerBox/PhaseNameLabel
@onready var timer_label: Label = $MarginContainer/TopCenter_TimerBox/TimerLabel

@onready var victory_banner: Control = $MarginContainer/Center_VictoryBanner
@onready var victory_text_label: Label = $MarginContainer/Center_VictoryBanner/VictoryTextLabel

var is_counting_down: bool = false
var countdown_timer: float = 0.0
var current_countdown_second: int = -1
var victory_tween: Tween = null
var pulse_tween: Tween = null
var survive_transition_tween: Tween = null

func _ready() -> void:
	# 1. Disable mouse filtering recursively on all UI controls so clicks pass through to combat attacks!
	_disable_mouse_filtering(self)

	# 2. Initial UI state setup: Keep HUD elements hidden during DAY peace time
	timer_box.visible = false
	victory_banner.visible = false
	victory_banner.pivot_offset = victory_banner.size / 2.0
	is_counting_down = false

	_style_labels()

	if not director:
		director = _find_node_in_tree("HordeDirector") as DirectorStateController
		if not director:
			director = _find_node_in_tree("DirectorStateController") as DirectorStateController

	if director:
		director.pause_director()
		if not director.phase_changed.is_connected(_on_director_phase_changed):
			director.phase_changed.connect(_on_director_phase_changed)
		if not director.wave_completed.is_connected(_on_director_wave_completed):
			director.wave_completed.connect(_on_director_wave_completed)

	if not cycle_controller:
		cycle_controller = _find_node_in_tree("DayNightCycleController")

	if cycle_controller:
		if "night_started" in cycle_controller:
			var night_sig: Signal = cycle_controller.get("night_started")
			if night_sig and not night_sig.is_connected(_on_night_started):
				night_sig.connect(_on_night_started)
		if "day_started" in cycle_controller:
			var day_sig: Signal = cycle_controller.get("day_started")
			if day_sig and not day_sig.is_connected(_on_day_started):
				day_sig.connect(_on_day_started)

func _find_node_in_tree(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var root_node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if root_node:
		return root_node.find_child(node_name, true, false)
	return null

func _disable_mouse_filtering(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_mouse_filtering(child)

func _style_labels() -> void:
	phase_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_name_label.add_theme_color_override("font_color", Color.WHITE)
	phase_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	phase_name_label.add_theme_constant_override("shadow_offset_x", 2)
	phase_name_label.add_theme_constant_override("shadow_offset_y", 2)
	phase_name_label.add_theme_font_size_override("font_size", 24)

	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	timer_label.add_theme_constant_override("shadow_offset_x", 2)
	timer_label.add_theme_constant_override("shadow_offset_y", 2)
	timer_label.add_theme_font_size_override("font_size", 42)

	victory_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_text_label.add_theme_color_override("font_color", Color.WHITE)
	victory_text_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	victory_text_label.add_theme_constant_override("outline_size", 12)
	victory_text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	victory_text_label.add_theme_constant_override("shadow_offset_x", 5)
	victory_text_label.add_theme_constant_override("shadow_offset_y", 5)
	victory_text_label.add_theme_font_size_override("font_size", 60)

func _on_night_started() -> void:
	print("🌙 [WAVE HUD] Night phase initiated! Triggering Get Ready countdown.")
	timer_box.visible = true
	timer_box.modulate.a = 1.0
	victory_banner.visible = false
	_start_pre_start_countdown()

func _on_day_started() -> void:
	is_counting_down = false
	timer_box.visible = false

	if victory_banner.visible:
		var fade_banner = create_tween()
		fade_banner.tween_property(victory_banner, "modulate:a", 0.0, 0.8)
		fade_banner.tween_callback(func(): victory_banner.visible = false)

func _start_pre_start_countdown() -> void:
	is_counting_down = true
	countdown_timer = float(pre_start_countdown_seconds)
	current_countdown_second = pre_start_countdown_seconds

	if director:
		director.pause_director()

	phase_name_label.visible = true
	phase_name_label.text = "GET READY"

	# Initial positioning centered
	margin_container.anchor_top = 0.20
	timer_label.scale = Vector2(1.0, 1.0)
	timer_label.modulate.a = 1.0

	_update_countdown_tick_display(current_countdown_second)

func _process(delta: float) -> void:
	if is_counting_down:
		# Enforce director frozen during pre-start countdown
		if director and director.is_physics_processing():
			director.pause_director()

		countdown_timer -= delta
		var ceil_sec: int = int(ceil(countdown_timer))

		if ceil_sec != current_countdown_second and ceil_sec > 0:
			current_countdown_second = ceil_sec
			_update_countdown_tick_display(current_countdown_second)

		if countdown_timer <= 0.0:
			is_counting_down = false
			_transition_to_survive_header()
		return

func _update_countdown_tick_display(sec: int) -> void:
	timer_label.text = str(sec)
	var max_sec: float = float(pre_start_countdown_seconds)
	var ratio: float = clampf(countdown_timer / max_sec, 0.0, 1.0)

	var target_color: Color = Color.WHITE

	if ratio > 0.6:
		# >60% time remaining: White
		target_color = Color.WHITE
	elif ratio > 0.3:
		# 30%-60% time remaining: Vibrant Orange
		target_color = Color(1.0, 0.55, 0.1)
	else:
		# <30% time remaining (final 3 seconds): Danger Red
		target_color = Color(1.0, 0.2, 0.2)

	timer_label.add_theme_color_override("font_color", target_color)
	phase_name_label.add_theme_color_override("font_color", target_color)

	# Animate countdown tick pulse
	var tween = create_tween()
	timer_label.pivot_offset = timer_label.size / 2.0

	var scale_amount: float = 1.6 if ratio <= 0.3 else 1.35
	timer_label.scale = Vector2(scale_amount, scale_amount)

	tween.set_parallel(true)
	tween.tween_property(timer_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Danger flashing effect on final 3 seconds
	if ratio <= 0.3:
		timer_label.modulate = Color(1.5, 1.5, 1.5, 1.0) # Bright glow flash
		tween.tween_property(timer_label, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _transition_to_survive_header() -> void:
	# Hide phase name label
	phase_name_label.visible = false
	timer_label.text = "SURVIVE"
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.pivot_offset = timer_label.size / 2.0

	if survive_transition_tween:
		survive_transition_tween.kill()

	survive_transition_tween = create_tween()

	# Phase 1: Center Impact Scale Pop
	timer_label.scale = Vector2(1.8, 1.8)
	survive_transition_tween.tween_property(timer_label, "scale", Vector2(1.2, 1.2), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Start wave spawning in director right as SURVIVE appears
	survive_transition_tween.tween_callback(func():
		if director:
			director.start_wave()
	)

	# Hold center for 0.6s
	survive_transition_tween.tween_interval(0.6)

	# Phase 2: Glide to top & shrink to tiny subtle header
	survive_transition_tween.set_parallel(true)
	survive_transition_tween.tween_property(margin_container, "anchor_top", 0.02, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	survive_transition_tween.tween_property(timer_label, "scale", Vector2(0.55, 0.55), 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	survive_transition_tween.tween_property(timer_label, "modulate:a", 0.75, 0.65) # Subtle semi-transparency

func _on_director_phase_changed(_new_phase: int, _duration: float) -> void:
	pass

func _on_director_wave_completed() -> void:
	# Fade out top SURVIVE label
	var fade_top = create_tween()
	fade_top.tween_property(timer_box, "modulate:a", 0.0, 0.4)
	fade_top.tween_callback(func(): timer_box.visible = false)

	# Present animated Center Victory Banner
	victory_banner.visible = true
	victory_banner.modulate.a = 1.0
	victory_text_label.text = "VICTORY!\nWAVE CLEARED"

	_animate_victory_banner()

func _animate_victory_banner() -> void:
	if victory_tween:
		victory_tween.kill()

	victory_banner.pivot_offset = victory_banner.size / 2.0
	victory_banner.scale = Vector2(0.2, 0.2)
	victory_banner.modulate.a = 0.0

	victory_tween = create_tween()
	victory_tween.set_parallel(true)
	victory_tween.tween_property(victory_banner, "scale", Vector2(1.25, 1.25), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	victory_tween.tween_property(victory_banner, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Settle scale smoothly to 1.0
	victory_tween.chain().tween_property(victory_banner, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Hold visible for 3.0 seconds, then smoothly fade out & dismiss!
	victory_tween.chain().tween_interval(3.0)
	victory_tween.chain().set_parallel(true)
	victory_tween.chain().tween_property(victory_banner, "scale", Vector2(0.85, 0.85), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	victory_tween.chain().tween_property(victory_banner, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	victory_tween.chain().tween_callback(func():
		victory_banner.visible = false
	)
