extends Area3D

# Expose a direct reference to the parent's linked matrix index
func get_linked_idx() -> int:
	var parent = get_parent()
	if parent and "linked_idx" in parent:
		return parent.linked_idx
	return -1
