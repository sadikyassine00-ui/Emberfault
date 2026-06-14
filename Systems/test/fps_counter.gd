extends Label

func _process(_delta):
	# Grabs the engine's internal frame rate and updates the text every single frame
	text = "FPS: " + str(Engine.get_frames_per_second())
