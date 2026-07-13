extends Node3D

@export var anim_player: AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	anim_player.play("Armature|Walk")
	anim_player.speed_scale = 2.5
