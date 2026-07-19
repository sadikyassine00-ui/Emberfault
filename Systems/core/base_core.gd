extends Node3D
class_name BaseCore

signal core_damaged(current_health: float, max_health: float)
signal core_destroyed

@export_category("Core Infrastructure")
@export var max_health: float = 500.0
@onready var current_health: float = max_health

var is_dead: bool = false
# ⚡ LOGGING THROTTLE TIMER
var log_cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	if log_cooldown > 0.0:
		log_cooldown -= delta

func take_damage(amount: float) -> void:
	if is_dead: return
	
	current_health = max(0.0, current_health - amount)
	core_damaged.emit(current_health, max_health)
	
	# ⚡ CONSUME LOG OVERHEAD: Spams are throttled to a clean 0.35s window
	if log_cooldown <= 0.0:
		log_cooldown = 0.35
		#print("🚨 [CORE UNDER SIEGE] Integrity: %.1f / %.1f (-%.1f)" % [current_health, max_health, amount])
	
	if current_health <= 0.0:
		_execute_permadeath_wipe()

func _execute_permadeath_wipe() -> void:
	is_dead = true
	core_destroyed.emit()
	#print("💀 [CRITICAL CORE BREACH] Base destroyed. Initiating total run wipe...")
	
	var tree := get_tree()
	if tree:
		tree.reload_current_scene()
