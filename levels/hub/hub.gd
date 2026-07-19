extends Node

# Cache the pointer to avoid costly frame-by-frame string lookups

func _process(_delta: float) -> void:
	# 1. Safe Verification: If reference is missing or dead, attempt a low-overhead fetch
	pass
