# WeaponTrail.gd (DISABLED)
# Old procedural weapon trail. Disabled in favor of the new SlashVFX system.
extends Node3D

@export_category("References")
@export var base_marker: Marker3D
@export var tip_marker: Marker3D

@export_category("Trail Settings")
@export var is_emitting: bool = false
@export_range(0.01, 1.0, 0.01) var lifetime: float = 0.12
@export var trail_color: Color = Color(1.0, 0.85, 0.4, 1.0)
@export var custom_material: Material

func _ready() -> void:
	hide()
	set_process(false)

func _process(_delta: float) -> void:
	pass
