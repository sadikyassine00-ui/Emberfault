## HordeEntity — Promoted foreground node.
##
## When a swarm member gets close enough to the player it is "promoted" from a
## cheap MultiMesh instance into a real Node3D so it can have collision,
## animations, hit detection etc.  When it moves far away it is "demoted" back
## to a MultiMesh dot.  This script drives the promoted-side logic.
##
## The HordeManager owns a small pool of these (e.g. 20).  They are recycled.
extends Node3D
class_name ModularHordeEntity

# ── Runtime state ──
var is_active : bool  = false
var linked_idx: int   = -1     # which slot in the flat arrays this node represents
var my_target : Node3D = null  # the player (or whatever we are chasing)
var horde_mgr = null           # back-reference to the HordeManager that owns us

var velocity        : Vector3 = Vector3.ZERO
var current_scale   : float   = 1.0
var local_hit_flash : float = 0.0
var _computed_ground_offset: float = 0.0
var mesh_instance   : MeshInstance3D = null

# ── Exported tuning ──
@export_group("Combat")
@export var attack_range           : float = 2.2
@export var attack_cooldown_time   : float = 1.5

@export_group("Movement")
@export var base_speed             : float = 4.5
@export var speed_variance         : float = 1.0
@export var preferred_dist_sq      : float = 10.0
@export var orbital_speed          : float = 1.2

@export_group("Physics")
@export var ground_offset          : float = 0.0
@export var auto_ground_offset     : bool  = true
@export var gravity                : float = 28.0
@export var body_radius            : float = 1.6
@export var collision_stiffness    : float = 0.50

var _ground_query: PhysicsRayQueryParameters3D

# ─────────────────────────────────────────────
#  Lifecycle
# ─────────────────────────────────────────────
func _ready() -> void:
	_ground_query = PhysicsRayQueryParameters3D.new()
	_ground_query.collision_mask        = 1
	_ground_query.collide_with_bodies   = true
	_ground_query.collide_with_areas    = false

	set_physics_process(false)
	hide()

	# Find the first child MeshInstance3D for shader parameter access
	for child in get_children():
		if child is MeshInstance3D:
			mesh_instance = child
			mesh_instance.set_instance_shader_parameter("is_foreground", 1.0)
			break

# ═══════════════════════════════════════════
#  Combat Integration
# ═══════════════════════════════════════════

## Routes damage applied directly to this node (e.g. via Physics collisions)
## back to the HordeManager's centralized damage system using the packed ID.
func take_damage(damage_info: DamageInfo) -> void:
	if linked_idx == -1 or not is_active:
		return

	var gen: int = horde_mgr.generations[linked_idx]
	var packed_id: int = (gen << 32) | linked_idx
	var ids: PackedInt64Array = PackedInt64Array([packed_id])
	horde_mgr.deal_damage(ids, -1.0, global_position, 14.0, damage_info)

# ═══════════════════════════════════════════
#  State Management
# ═══════════════════════════════════════════

func activate(pos: Vector3, idx: int, target: Node3D,
		spd_var: float, pref_dist: float, orb_spd: float, mgr) -> void:
	global_position    = pos
	linked_idx         = idx
	my_target          = target
	speed_variance     = spd_var
	preferred_dist_sq  = pref_dist
	orbital_speed      = orb_spd
	horde_mgr          = mgr

	# Register into the manager's O(1) lookup map
	if idx >= 0 and idx < mgr.index_to_node_map.size():
		mgr.index_to_node_map[idx] = self

	velocity        = mgr.velocities[idx]
	local_hit_flash = mgr.hit_timers[idx]
	current_scale   = mgr.enemy_scale

	_computed_ground_offset = ground_offset
	if auto_ground_offset:
		for child in get_children():
			if child is MeshInstance3D and child.mesh:
				var aabb = child.mesh.get_aabb()
				_computed_ground_offset += -aabb.position.y * current_scale - child.position.y * current_scale
				break

	global_position    = mgr.positions[idx] + Vector3(0, _computed_ground_offset, 0)
	var to_target := (target.global_position - global_position)
	to_target.y = 0.0
	if to_target.length_squared() > 0.001:
		var back := -to_target.normalized()
		var right := Vector3.UP.cross(back).normalized()
		var up    := back.cross(right).normalized()
		global_transform.basis = Basis(right, up, back).scaled(
			Vector3(current_scale, current_scale, current_scale))
	else:
		global_transform.basis = Basis().scaled(
			Vector3(current_scale, current_scale, current_scale))

	show()

	if mesh_instance:
		mesh_instance.set_instance_shader_parameter("hit_flash_intensity", 0.0)
		mesh_instance.set_instance_shader_parameter("attack_lunge_intensity",
			mgr.strike_visual_timers[idx] if mgr and idx >= 0 else 0.0)

	is_active = true

	# Clean up any lingering animation state from the pool
	var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.stop()
	if mesh_instance and mesh_instance.get_surface_override_material(0):
		mesh_instance.get_surface_override_material(0).albedo_color = Color(1, 1, 0.1764706, 1)

	if horde_mgr and not horde_mgr.active_pool.has(self):
		horde_mgr.active_pool.append(self)

func deactivate() -> void:
	if not is_active:
		return

	if horde_mgr and linked_idx != -1:
		var t_id: int = horde_mgr.type_ids[linked_idx]
		var type_def: EnemyTypeDefinition = horde_mgr._get_type_def(t_id)
		var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
		if anim_player and type_def.death_animation_name and anim_player.has_animation(type_def.death_animation_name):
			anim_player.play(type_def.death_animation_name)

		horde_mgr.hit_timers[linked_idx] = local_hit_flash

		if horde_mgr.token_states[linked_idx] > 0:
			horde_mgr.release_token(horde_mgr.token_states[linked_idx])
		horde_mgr.token_states[linked_idx]          = 0
		horde_mgr.strike_visual_timers[linked_idx]   = 0.0

		if linked_idx < horde_mgr.index_to_node_map.size():
			horde_mgr.index_to_node_map[linked_idx] = null

	if horde_mgr:
		horde_mgr.active_pool.erase(self)

	is_active       = false
	linked_idx      = -1
	my_target       = null
	horde_mgr       = null
	velocity        = Vector3.ZERO
	hide()
	global_position = Vector3(0.0, -1000.0, 0.0)

func trigger_hit_flash() -> void:
	if local_hit_flash > 0.0:
		return
	local_hit_flash = 1.0
	if mesh_instance:
		mesh_instance.set_instance_shader_parameter("hit_flash_intensity", 1.0)

# ─────────────────────────────────────────────
#  Tick — called by HordeManager every physics frame
# ─────────────────────────────────────────────
func managed_tick(delta: float) -> void:
	if not is_active or not my_target or not horde_mgr or linked_idx == -1:
		return

	# ── Hit flash decay ──
	if local_hit_flash > 0.0:
		local_hit_flash = max(0.0, local_hit_flash - delta * 15.0)
		horde_mgr.hit_timers[linked_idx] = local_hit_flash
		if mesh_instance:
			mesh_instance.set_instance_shader_parameter("hit_flash_intensity", local_hit_flash)

	# ── Attack lunge visual decay ──
	var lunge: float = horde_mgr.strike_visual_timers[linked_idx]
	if lunge > 0.0:
		lunge -= delta * 5.0
		if lunge < 0.0: lunge = 0.0
		horde_mgr.strike_visual_timers[linked_idx] = lunge

		if lunge == 0.0:
			horde_mgr.release_token(horde_mgr.token_states[linked_idx])
			horde_mgr.token_states[linked_idx] = 0
		if mesh_instance:
			mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", lunge)

	# ── Attack cooldown ──
	if horde_mgr.attack_cooldowns[linked_idx] > 0.0:
		horde_mgr.attack_cooldowns[linked_idx] -= delta

	# ── Targeting ──
	var pos: Vector3 = global_position
	var target_pos: Vector3 = my_target.global_position
	var to_target: Vector3 = target_pos - pos
	to_target.y = 0.0
	var dist_sq: float = to_target.x * to_target.x + to_target.z * to_target.z
	var distance: float = sqrt(dist_sq)

	var dir_to_target: Vector3 = Vector3.ZERO
	if distance > 0.01:
		dir_to_target = to_target / distance

	# ── Token request ──
	var token: int = horde_mgr.token_states[linked_idx]
	var t_id: int = horde_mgr.type_ids[linked_idx]
	var type_def: EnemyTypeDefinition = horde_mgr._get_type_def(t_id)
	var atk_behavior: AttackBehavior = type_def.get_attack_behavior()

	if distance <= 5.5 and horde_mgr.attack_cooldowns[linked_idx] <= 0.0 \
			and lunge <= 0.0 and token == 0:
		var granted: int = horde_mgr.request_token(distance, linked_idx)
		if granted > 0:
			horde_mgr.token_states[linked_idx] = granted
			token = granted

	# ── Execute attack ──
	if token > 0 and atk_behavior.should_attack(distance, horde_mgr.attack_cooldowns[linked_idx]) \
			and lunge <= 0.0:
		horde_mgr.attack_cooldowns[linked_idx]      = atk_behavior.attack_cooldown
		horde_mgr.strike_visual_timers[linked_idx]   = 1.0
		if mesh_instance:
			mesh_instance.set_instance_shader_parameter("attack_lunge_intensity", 1.0)

		# Play attack animation
		var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
		if anim_player and type_def.attack_animation_name and anim_player.has_animation(type_def.attack_animation_name):
			anim_player.play(type_def.attack_animation_name)

		var dmg_behavior: DamageBehavior = type_def.get_damage_behavior()
		var dmg_info: DamageInfo = dmg_behavior.calculate(t_id, -1, true)
		dmg_info.source_position = global_position

		HordeCombatEvents.enemy_attacked.emit(linked_idx, true, my_target, dmg_info)
		if my_target.has_method("take_damage"):
			my_target.take_damage(dmg_info)

	# ── Movement ──
	velocity.y -= gravity * delta

	var fwd_speed := 0.0
	if distance <= atk_behavior.attack_range:
		fwd_speed = base_speed * speed_variance * 0.4 \
			if horde_mgr.attack_cooldowns[linked_idx] > 0.0 else 0.0
		if distance < 1.2:
			fwd_speed = -3.5
	else:
		fwd_speed = base_speed * speed_variance

	var fwd_vec : Vector3 = dir_to_target * fwd_speed
	var tangent : Vector3 = Vector3.UP.cross(dir_to_target)
	if tangent.length_squared() > 0.001:
		tangent = tangent.normalized()
	else:
		tangent = Vector3.RIGHT
	var orbit_str : float = clamp(10.0 / max(distance, 1.0), 0.5, 3.0)
	var strafe : Vector3 = tangent * (orbital_speed * orbit_str)

	var shamble_hash: float = float((linked_idx * 2654435761) & 0xFFFF) / 65536.0
	var t: float = Time.get_ticks_msec() / 1000.0
	var shamble: Vector3 = Vector3(
		(shamble_hash * 2.0 - 1.0) * 1.2 * sin(t * 2.5),
		0.0,
		((shamble_hash * 1.5 + 0.3) - floorf(shamble_hash * 1.5 + 0.3)) * 2.4 - 1.2) * cos(t * 2.0)

	# ── Separation from other promoted nodes ──
	var sep: Vector3 = Vector3.ZERO
	var pbd: Vector3 = Vector3.ZERO
	var threshold: float = body_radius * 1.8
	var threshold_sq: float = threshold * threshold
	for other: Node3D in horde_mgr.active_pool:
		if other == self:
			continue
		var other_pos: Vector3 = other.global_position
		var push_x: float = pos.x - other_pos.x
		var push_z: float = pos.z - other_pos.z
		var d_sq: float = push_x * push_x + push_z * push_z
		if d_sq < threshold_sq and d_sq > 0.001:
			var d: float = sqrt(d_sq)
			var inv_d: float = 1.0 / d
			var nx: float = push_x * inv_d
			var nz: float = push_z * inv_d
			var weight: float = (threshold - d) / threshold * 9.0
			sep.x += nx * weight
			sep.z += nz * weight
			if d < body_radius:
				var overlap: float = (body_radius - d) * collision_stiffness
				pbd.x += nx * overlap
				pbd.z += nz * overlap

	# Add the hard push-back (pbd) directly to desired velocity for fluid sliding
	var desired := fwd_vec + strafe + shamble + sep + (pbd * 15.0)

	velocity.x = lerp(velocity.x, desired.x, 6.0 * delta)
	velocity.z = lerp(velocity.z, desired.z, 6.0 * delta)

	pos += Vector3(velocity.x, velocity.y, velocity.z) * delta

	# ── Ground clamping ──
	var raw_floor: float = horde_mgr.floor_heights[linked_idx]
	if (linked_idx + Engine.get_process_frames()) % 8 == 0:
		if _ground_query.exclude.is_empty() and my_target and my_target.has_method("get_rid"):
			_ground_query.exclude = [my_target.get_rid()]
		var ss: PhysicsDirectSpaceState3D = horde_mgr.get_world_3d().direct_space_state
		_ground_query.from = Vector3(pos.x, target_pos.y + 30.0, pos.z)
		_ground_query.to   = Vector3(pos.x, target_pos.y - 30.0, pos.z)
		var hit: Dictionary = ss.intersect_ray(_ground_query)
		if not hit.is_empty():
			raw_floor = hit.position.y
		horde_mgr.floor_heights[linked_idx] = raw_floor

	var current_floor: float = raw_floor + _computed_ground_offset

	if pos.y <= current_floor:
		# Smoothly interpolate up slopes rather than instantly snapping
		pos.y = lerp(pos.y, current_floor, 18.0 * delta)
		if velocity.y < 0.0:
			velocity.y = 0.0

	global_position = pos
	var db_pos: Vector3 = pos
	db_pos.y -= _computed_ground_offset
	horde_mgr.set_pos_vel(linked_idx, db_pos, velocity)

	# ── Orientation ──
	if dir_to_target.length_squared() > 0.001:
		var target_basis: Basis = Basis.looking_at(dir_to_target, Vector3.UP)
		var cur_basis: Basis = global_transform.basis.orthonormalized()
		var sv: Vector3 = Vector3(current_scale, current_scale, current_scale)
		global_transform.basis = cur_basis.slerp(target_basis, 14.0 * delta).scaled(sv)
