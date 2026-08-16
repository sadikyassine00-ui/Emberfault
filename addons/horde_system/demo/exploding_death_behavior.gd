class_name ExplodingDeathBehavior
extends DeathBehavior

@export var explosion_radius: float = 4.0
@export var explosion_damage: float = 25.0
@export var vfx_scene: PackedScene = preload("res://addons/horde_system/demo/death_vfx.tscn")

func on_death(death_position: Vector3, type_id: int) -> void:
	if vfx_scene:
		var vfx: Node3D = vfx_scene.instantiate()
		
		# We must add the VFX to the current scene tree so it renders and processes.
		# A good safe root is the current scene.
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree and tree.current_scene:
			tree.current_scene.add_child(vfx)
			vfx.global_position = death_position
	
	print("[EXPLOSION] Entity detonated at %s! Dealing %.1f AoE damage in a %.1f meter radius!" % [
		death_position, 
		explosion_damage, 
		explosion_radius
	])
