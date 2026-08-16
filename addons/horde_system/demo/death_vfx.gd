extends GPUParticles3D

func _ready() -> void:
	# Ensure the particles emit exactly once as soon as they are added to the tree
	emitting = true
	
	# Connect the finished signal to queue_free to ensure zero memory leaks
	if not finished.is_connected(queue_free):
		finished.connect(queue_free)
