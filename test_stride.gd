extends SceneTree

func _init():
	var mm = MultiMesh.new()
	mm.instance_count = 0
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = 10
	
	print("BUFFER SIZE FOR 10 INSTANCES: ", mm.buffer.size())
	print("STRIDE: ", mm.buffer.size() / 10.0)
	
	quit()
