class_name CombatComponent
extends Node3D

signal strike_impact(position: Vector3)

@export_category("References")
@export var horde_manager: HordeManager
@export var camera_manager: CameraManager
@export var visual_model: Node3D
@export var visuals_container: Node3D
@export var hammer_mesh: MeshInstance3D

@export_category("Combat Settings")
@export var hit_stop_duration: float = 11.0
@export var hammer_tip_offset: Vector3 = Vector3(0.0, 0.0, -2.0)

@export_category("Matrix Hitbox Settings")
@export var strike_radius: float = 4.5 # Optimized to sweep elite combat layers
@export var strike_arc_degrees: float = 145.0

@onready var combat_buffer: CombatBuffer = $CombatBuffer
@onready var combat_juice_engine = get_node_or_null("CombatJuiceEngine")

var parent: CharacterBody3D
var state_machine: AnimationNodeStateMachinePlayback

# Safe fallback reference definition if DamagePayload isn't registered globally
class CoreDamagePayload extends RefCounted:
	var base_damage: float = 15.0
	var is_critical: bool = false

var is_attacking: bool:
	get:
		return combat_buffer.is_attacking if combat_buffer else false

func _ready() -> void:
	parent = get_parent() as CharacterBody3D

	if not horde_manager:
		horde_manager = get_tree().current_scene.find_child("HordeManager", true, false) as HordeManager

	var anim_tree = parent.get_node_or_null("Axyl/AnimationTree") as AnimationTree
	if anim_tree:
		state_machine = anim_tree.get("parameters/playback")

	var right_hand = parent.find_child("R_hand", true, false)
	var hammer_pivot = parent.find_child("HammerPivot", true, false)

	if not hammer_pivot:
		hammer_pivot = Node3D.new()
		hammer_pivot.name = "HammerPivot"
		visuals_container.add_child(hammer_pivot)
		if right_hand:
			hammer_pivot.position = right_hand.position
		hammer_pivot.rotation_degrees = Vector3(-35.0, 0.0, 0.0)

	if right_hand and hammer_mesh:
		if hammer_mesh.get_parent() != right_hand:
			var old_parent = hammer_mesh.get_parent()
			if old_parent:
				old_parent.remove_child(hammer_mesh)
			right_hand.add_child(hammer_mesh)
		hammer_mesh.position = Vector3(-0.175556, 0.014508, -2.019118)
		hammer_mesh.rotation = Vector3.ZERO

	if combat_buffer:
		combat_buffer.initialize(parent, visual_model, state_machine)
		combat_buffer.strike_impact_frame.connect(_on_strike_impact_frame)
	else:
		push_error("CombatComponent: Missing CombatBuffer child node.")

func start_attack() -> void:
	if not combat_buffer: return

	if combat_juice_engine and not combat_buffer.is_attacking:
		combat_juice_engine.execute_wind_up(hammer_mesh)

	combat_buffer.start_attack()

func _on_combo_cancel_window_reached() -> void:
	if combat_buffer:
		combat_buffer._on_combo_cancel_window_reached()

func _on_strike_impact_frame(combo_step: int) -> void:
	if not hammer_mesh: return

	var tip_pos: Vector3 = hammer_mesh.to_global(hammer_tip_offset)
	strike_impact.emit(tip_pos)

	if combat_juice_engine:
		combat_juice_engine.execute_strike_juice(hammer_mesh, hit_stop_duration, combo_step)

	if not horde_manager:
		print("❌ [COMBAT FATAL] Aborting strike: horde_manager reference is NULL!")
		return

	# --- 📐 HIGH-PERFORMANCE SWEEP DATA LOOP ---
	var hit_indices := PackedInt32Array()
	var origin: Vector3 = parent.global_position

	# AAA MATRIX CRITICAL FIX: Changed from negative basis.z to positive basis.z
	# This flips the mathematical cone 180 degrees to match the asset's forward swing heading vector!
	var forward := visual_model.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD

	var active_radius: float = strike_radius if combo_step < 2 else (strike_radius * 1.4)
	var rad_sq: float = active_radius * active_radius
	var arc_dot_threshold: float = cos(deg_to_rad(strike_arc_degrees * 0.5))

	for i in range(horde_manager.highest_active_index):
		if horde_manager.states[i] != 0:
			var target_pos: Vector3 = horde_manager.positions[i]
			var to_enemy := Vector3(target_pos.x - origin.x, 0.0, target_pos.z - origin.z)
			var dist_sq: float = to_enemy.length_squared()

			if dist_sq <= rad_sq:
				# Attack 3 skips heading validation entirely to process a full 360 radial ring blast
				if combo_step == 2 or dist_sq < 0.25:
					hit_indices.append(i)
				else:
					var dir := to_enemy.normalized()
					if dir.dot(forward) >= arc_dot_threshold:
						hit_indices.append(i)

	if hit_indices.size() > 0:
		_route_batch_to_horde_manager(hit_indices, combo_step)

func _route_batch_to_horde_manager(indices: PackedInt32Array, combo_step: int) -> void:
	if not horde_manager: return

	var current_payload = CoreDamagePayload.new()
	if combo_step < 2:
		current_payload.base_damage = 15.0
	else:
		current_payload.base_damage = 45.0
		current_payload.is_critical = true

	horde_manager.register_batch_strikes(indices, current_payload, combo_step)
