extends SceneTree

func _init():
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = 1

	var b = Basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9))
	var o = Vector3(10, 11, 12)
	var t = Transform3D(b, o)
	
	mm.set_instance_transform(0, t)
	mm.set_instance_color(0, Color(0.1, 0.2, 0.3, 0.4))
	mm.set_instance_custom_data(0, Color(0.5, 0.6, 0.7, 0.8))

	print("BUFFER:")
	print(mm.buffer)
	quit()
