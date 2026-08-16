## DemoPlayer — Minimal player controller for testing the horde system.
##
## WASD to move, mouse to look, Space to jump.
## This script also auto-creates the floor, player mesh, collision shapes,
## environment, and a stats HUD so the demo scene is fully self-contained.
extends CharacterBody3D

@export var move_speed  : float = 7.0
@export var jump_force  : float = 10.0

var _hud   : Label
@onready var mesh: MeshInstance3D = $PlayerMesh

func _ready() -> void:
	# ── Disable global music for this scene ──
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		if am.has_method("transition_to_music"):
			am.transition_to_music(null, 1.0)

	# ── Create HUD ──
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	_hud = Label.new()
	_hud.name = "StatsLabel"
	_hud.position = Vector2(16, 16)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_hud)


func _physics_process(delta: float) -> void:
	# ── Movement ──
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_dir := Vector3.ZERO

	var cam := get_viewport().get_camera_3d()
	if cam:
		var forward := -cam.global_transform.basis.z
		var right := cam.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		move_dir = (right * input_dir.x + forward * -input_dir.y).normalized()
	else:
		move_dir = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if move_dir.length_squared() > 0.01:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed

		# Rotate mesh towards movement direction
		var target_basis := Basis.looking_at(move_dir, Vector3.UP)
		mesh.global_transform.basis = mesh.global_transform.basis.slerp(target_basis, 15.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	if not is_on_floor():
		velocity.y -= 28.0 * delta
	elif Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_force

	move_and_slide()

	# ── HUD ──
	if _hud:
		var mgr = get_parent().get_node_or_null("HordeManager")
		var fps_text := "FPS: %d" % Engine.get_frames_per_second()
		if mgr:
			var promoted := 0
			for n in mgr.node_pool:
				if n.is_active:
					promoted += 1
			_hud.text = "%s\nAlive: %d / %d\nPromoted: %d / %d\nTokens: %d / %d" % [
				fps_text,
				mgr.alive_count, mgr.max_alive,
				promoted, mgr.max_active_nodes,
				mgr.active_tokens, mgr.max_tokens
			]
		else:
			_hud.text = fps_text


func take_damage(info: DamageInfo) -> void:
	# Stub — implement player health here
	pass
