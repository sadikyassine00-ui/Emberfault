extends Camera3D

func _ready() -> void:
	# This single line links this camera node to your global juice system
	JuiceDirector.register_camera(self)
