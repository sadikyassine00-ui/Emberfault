extends Node3D
class_name SpawnManager

@export_category("Core References")
@export var horde_manager: HordeManager
@export var player: Node3D
@export var base_core: Node3D
@export var spawn_radius: float = 60.0
@export var saboteur_chance: float = 0.2

@export_category("Wave Tuning")
@export var base_wave_enemy_count: int = 200
@export var base_grace_period: float = 15.0
@export var min_grace_period: float = 5.0
@export var base_min_squad_size: int = 3
@export var base_max_squad_size: int = 5
@export var base_squad_spawn_cooldown: float = 3.0
@export var min_squad_spawn_cooldown: float = 1.0

@onready var spawn_timer: Timer = $SpawnTimer

var is_spawning: bool = true
var current_wave: int = 1
var elapsed_time: float = 0.0
var wave_active: bool = false
var grace_timer: float = 0.0
var enemies_to_spawn_this_wave: int = 0
var enemies_spawned_this_wave: int = 0
var squad_cooldown_timer: float = 0.0

var reusable_ray_query: PhysicsRayQueryParameters3D

func _ready() -> void:
	reusable_ray_query = PhysicsRayQueryParameters3D.new()
	reusable_ray_query.collision_mask = 1
	reusable_ray_query.collide_with_bodies = true
	reusable_ray_query.collide_with_areas = false

func set_spawn_rate(time_seconds: float) -> void:
	spawn_timer.wait_time = time_seconds

func pause_spawning() -> void:
	is_spawning = false

func resume_spawning() -> void:
	is_spawning = true

func _process(delta: float) -> void:
	if not player or not horde_manager or not base_core: return

	if is_spawning:
		elapsed_time += delta

	if not wave_active:
		if grace_timer > 0.0:
			grace_timer -= delta
			if grace_timer <= 0.0:
				_start_next_wave()
		else:
			_start_next_wave()
	else:
		if enemies_spawned_this_wave >= enemies_to_spawn_this_wave and horde_manager.alive_count <= 0:
			_end_current_wave()
			return

		if is_spawning and enemies_spawned_this_wave < enemies_to_spawn_this_wave:
			squad_cooldown_timer -= delta
			if squad_cooldown_timer <= 0.0:
				_spawn_squad()

func _start_next_wave() -> void:
	enemies_to_spawn_this_wave = base_wave_enemy_count
	enemies_spawned_this_wave = 0
	wave_active = true
	squad_cooldown_timer = 0.0

func _end_current_wave() -> void:
	wave_active = false
	var minutes: float = elapsed_time / 60.0
	var grace_duration: float = maxf(min_grace_period, base_grace_period - minutes * 1.5)
	grace_timer = grace_duration
	current_wave += 1

func _spawn_squad() -> void:
	var minutes: float = elapsed_time / 60.0
	var min_s: int = base_min_squad_size + int(minutes)
	var max_s: int = base_max_squad_size + int(minutes)
	var squad_size: int = randi_range(min_s, max_s)

	squad_size = mini(squad_size, enemies_to_spawn_this_wave - enemies_spawned_this_wave)
	if squad_size <= 0: return

	if horde_manager.alive_count + squad_size > horde_manager.max_concurrent_enemies:
		var base_cooldown: float = spawn_timer.wait_time if spawn_timer else 3.0
		squad_cooldown_timer = maxf(min_squad_spawn_cooldown, base_cooldown - minutes * 0.2)
		return

	var is_saboteur: bool = randf() < saboteur_chance
	var spawn_target_node: Node3D = base_core if is_saboteur else player

	horde_manager.spawn_wave_ring(spawn_target_node, spawn_radius, squad_size)
	enemies_spawned_this_wave += squad_size

	var base_cooldown: float = spawn_timer.wait_time if spawn_timer else 3.0
	squad_cooldown_timer = maxf(min_squad_spawn_cooldown, base_cooldown - minutes * 0.2)
