extends CharacterBody3D
class_name ActiveEnemy

var is_active: bool = false
var linked_idx: int = -1
var my_target: Node3D
var horde_mgr: Node3D # We need this to look at the other enemies!

# Swarm Traits
var base_speed: float = 4.5
var speed_variance: float = 1.0
var preferred_dist_sq: float = 10.0
var orbital_speed: float = 1.0

func _ready():
	set_physics_process(false)
	hide()

# NEW: We receive all the traits from the HordeManager when promoted
func activate(pos: Vector3, idx: int, target: Node3D, spd_var: float, pref_dist: float, orb_spd: float, mgr: Node3D):
	global_position = pos
	linked_idx = idx
	my_target = target
	speed_variance = spd_var
	preferred_dist_sq = pref_dist
	orbital_speed = orb_spd
	horde_mgr = mgr

	is_active = true
	show()
	set_physics_process(true)

func deactivate():
	is_active = false
	linked_idx = -1
	my_target = null
	horde_mgr = null
	hide()
	set_physics_process(false)
	global_position = Vector3(0, -1000, 0)

func _physics_process(delta):
	if not is_active or not my_target or not horde_mgr: return

	var current_pos = global_position
	var target_pos = my_target.global_position
	var dist_sq = current_pos.distance_squared_to(target_pos)

	var dir_to_target = Vector3.ZERO
	if dist_sq > 0.001:
		dir_to_target = (target_pos - current_pos).normalized()
		dir_to_target.y = 0

	# 1. Forward Speed & Agitation
	var distance_error_sq = dist_sq - preferred_dist_sq
	var agitation = 1.0
	var forward_speed = 0.0

	if distance_error_sq > 2.0:
		forward_speed = base_speed * speed_variance
	elif distance_error_sq > -1.0:
		agitation = 0.05
	else:
		forward_speed = -1.5 # Back up if too close!
		agitation = 0.2

	var forward_vec = dir_to_target * forward_speed

	# 2. Orbital Strafe
	var tangent = Vector3.UP.cross(dir_to_target).normalized()
	var orbit_intensity = clamp(10.0 / max(sqrt(dist_sq), 1.0), 0.5, 3.0)
	var strafe_vec = tangent * (orbital_speed * orbit_intensity * agitation)

	# 3. Shambling Noise
	var time_sec = Time.get_ticks_msec() / 1000.0
	var shambling_vec = Vector3(sin(time_sec * 3.0 + linked_idx) * 1.5, 0, cos(time_sec * 2.5 + linked_idx) * 1.5) * agitation

	# 4. THE SEPARATION WEB (Reading the HordeManager's data!)
	var separation_vec = Vector3.ZERO
	var bubble_size = 6.0

	var neighbors = [linked_idx - 1, (linked_idx + 13) % horde_mgr.highest_active_index]
	if linked_idx == 0: neighbors[0] = horde_mgr.highest_active_index - 1

	for n_idx in neighbors:
		if horde_mgr.states[n_idx] != 0: # Is the neighbor alive?
			var neighbor_pos = horde_mgr.positions[n_idx]
			var push_dir = current_pos - neighbor_pos
			push_dir.y = 0
			var push_dist_sq = push_dir.length_squared()

			if push_dist_sq < bubble_size and push_dist_sq > 0.001:
				var push_strength = bubble_size - push_dist_sq
				var straight_push = push_dir.normalized()
				if straight_push.dot(dir_to_target) < -0.2:
					forward_vec *= 0.1
				var squirm_slide = Vector3.UP.cross(straight_push) * (1.2 if linked_idx % 2 == 0 else -1.2)
				separation_vec += (straight_push + squirm_slide).normalized() * (push_strength * 2.5 * agitation)

	# 5. Combine and Smooth Velocity
	var desired_velocity = forward_vec + strafe_vec + shambling_vec + separation_vec
	if desired_velocity.length_squared() < 0.05 and agitation < 0.1:
		desired_velocity = Vector3.ZERO

	velocity.x = lerp(velocity.x, desired_velocity.x, 5.0 * delta)
	velocity.z = lerp(velocity.z, desired_velocity.z, 5.0 * delta)

	# Apply Gravity for the voxel floor
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	# Look in the direction of movement
	var look_dir = Vector3(velocity.x, 0, velocity.z)
	if look_dir.length_squared() > 0.1:
		look_at(global_position + look_dir, Vector3.UP)

	move_and_slide()
