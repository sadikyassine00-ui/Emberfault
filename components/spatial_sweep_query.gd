extends ShapeCast3D
class_name SpatialSweepQuery

func _ready() -> void:
	# Keep dormant during idle frames to completely clear CPU overhead
	enabled = false

	# Enforce explicit Layer 3 (Enemies) physics mask configurations (bit index 2)
	collision_mask = 1 << 2
	set_collision_mask_value(1, false)

func _physics_process(_delta: float) -> void:
	# VISUAL DEBUG AID: Follows heading smoothly when manually enabled in inspector
	if enabled:
		var combat_comp = get_parent()
		if combat_comp and "visual_model" in combat_comp and combat_comp.visual_model:
			var debug_transform = combat_comp.visual_model.global_transform
			global_transform.basis = debug_transform.basis.orthonormalized()
			global_transform.origin = debug_transform.origin

func execute_sweep_query(query_basis: Basis, query_origin: Vector3) -> Array[ActiveEnemy]:
	# STRIP SCALE CONTAMINATION: Assemble a clean, unscaled matrix footprint
	global_transform.basis = query_basis.orthonormalized()
	global_transform.origin = query_origin

	force_shapecast_update()

	var total_hits = get_collision_count()
	var processed_colliders: Array[ActiveEnemy] = []

	for i in range(total_hits):
		var collider = get_collider(i)

		if collider is ActiveEnemy and not processed_colliders.has(collider):
			processed_colliders.append(collider as ActiveEnemy)

	return processed_colliders
