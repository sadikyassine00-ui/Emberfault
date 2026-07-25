extends Node

# --- BUS NAMES ---
const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_SFX_HIGH: StringName = &"Combat_HighPriority"
const BUS_SFX_SWARM: StringName = &"Combat_Swarm"
const BUS_UI: StringName = &"UI"

# --- DEFAULT BACKGROUND AUDIO ---
@export_group("Default Background Audio")
@export var default_music: AudioStream = preload("res://systems/audio/music/The_Snow_Queen.ogg")
@export var default_ambience: AudioStream = preload("res://systems/audio/ambient/wind_sound.ogg")
@export var default_fade_duration: float = 2.0

# --- POOL SIZES ---
@export_group("Pool Allocation")
@export var sfx_3d_pool_size: int = 24
@export var sfx_2d_pool_size: int = 8

# --- THROTTLING CONFIG (in milliseconds) ---
@export_group("Throttling")
@export var default_throttle_ms: int = 25

# Internal Pools & Trackers
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_3d_index: int = 0

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_2d_index: int = 0

# Music Crossfade System (Dual-Player System)
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _music_tween: Tween

# Ambient System
var _ambient_player: AudioStreamPlayer

# Sound Throttling Lookup: HashMap[StringName, int]
var _last_played_timestamps: Dictionary = {}

func _ready() -> void:
	_setup_sfx_pools()
	_setup_music_system()
	_setup_ambient_system()

	# Seamlessly play background music & wind ambient on boot
	if default_music:
		transition_to_music(default_music, default_fade_duration)
	if default_ambience:
		play_ambience(default_ambience, default_fade_duration)

# ------------------------------------------------------------------------------
# POOL INITIALIZATION (Runs strictly at boot / zero runtime heap allocations)
# ------------------------------------------------------------------------------
func _setup_sfx_pools() -> void:
	for i in range(sfx_3d_pool_size):
		var player := AudioStreamPlayer3D.new()
		player.bus = BUS_SFX_SWARM
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		
		# --- TOP-DOWN AUDIO FIXES ---
		player.unit_size = 25.0 # Boosted so isometric camera distance retains full volume
		player.max_db = 6.0 # Extra headroom for swarm hits
		player.attenuation_filter_cutoff_hz = 20500 # Kills low-pass muffling; keeps crisp high-end!
		
		add_child(player)
		_pool_3d.append(player)

func _setup_music_system() -> void:
	_music_player_a = AudioStreamPlayer.new()
	_music_player_b = AudioStreamPlayer.new()
	_music_player_a.bus = BUS_MUSIC
	_music_player_b.bus = BUS_MUSIC
	add_child(_music_player_a)
	add_child(_music_player_b)
	_active_music_player = _music_player_a

func _setup_ambient_system() -> void:
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = BUS_AMBIENCE
	add_child(_ambient_player)

# ------------------------------------------------------------------------------
# SFX PIPELINE (3D Spatial & 2D Global)
# ------------------------------------------------------------------------------
func play_sfx_3d(
	event_id: StringName,
	stream_or_array: Variant, # Accepts AudioStream OR Array[AudioStream]
	global_pos: Vector3,
	bus_override: StringName = BUS_SFX_SWARM,
	pitch_min: float = 0.88,
	pitch_max: float = 1.12,
	custom_throttle_ms: int = -1
) -> void:
	var selected_stream: AudioStream = null

	if stream_or_array is AudioStream:
		selected_stream = stream_or_array
	elif stream_or_array is Array and not stream_or_array.is_empty():
		selected_stream = stream_or_array.pick_random()

	if selected_stream == null:
		return

	# Throttling Check
	var current_time := Time.get_ticks_msec()
	var throttle_limit := custom_throttle_ms if custom_throttle_ms >= 0 else default_throttle_ms
	
	if _last_played_timestamps.has(event_id):
		if current_time - _last_played_timestamps[event_id] < throttle_limit:
			return
	
	_last_played_timestamps[event_id] = current_time

	# Grab player from pool
	var player := _pool_3d[_pool_3d_index]
	_pool_3d_index = (_pool_3d_index + 1) % sfx_3d_pool_size

	player.bus = bus_override
	player.global_position = global_pos
	player.stream = selected_stream
	# Wider pitch range + subtle volume variation for dynamic hit feel
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.volume_db = randf_range(-1.5, 1.5)
	player.play()

func play_sfx_2d(stream: AudioStream, bus_override: StringName = BUS_UI, pitch: float = 1.0) -> void:
	if stream == null:
		return

	var player := _pool_2d[_pool_2d_index]
	_pool_2d_index = (_pool_2d_index + 1) % sfx_2d_pool_size

	player.bus = bus_override
	player.stream = stream
	player.pitch_scale = pitch
	player.play()

# ------------------------------------------------------------------------------
# MUSIC SYSTEM (Crossfading between tracks)
# ------------------------------------------------------------------------------
func transition_to_music(new_stream: AudioStream, fade_duration: float = 1.5) -> void:
	if new_stream == null:
		return

	if new_stream is AudioStreamOggVorbis:
		new_stream.loop = true

	if _active_music_player.stream == new_stream and _active_music_player.playing:
		return

	var incoming_player := _music_player_b if _active_music_player == _music_player_a else _music_player_a
	
	incoming_player.stream = new_stream
	incoming_player.volume_db = -80.0
	incoming_player.play()

	if _music_tween and _music_tween.is_running():
		_music_tween.kill()

	_music_tween = create_tween().set_parallel(true)
	
	if _active_music_player.playing:
		_music_tween.tween_property(_active_music_player, "volume_db", -80.0, fade_duration)
		_music_tween.chain().tween_callback(Callable(_active_music_player, "stop"))

	_music_tween.tween_property(incoming_player, "volume_db", 0.0, fade_duration)
	
	_active_music_player = incoming_player

# ------------------------------------------------------------------------------
# AMBIENCE PIPELINE
# ------------------------------------------------------------------------------
func play_ambience(stream: AudioStream, fade_duration: float = 2.0) -> void:
	if stream == null:
		return

	if stream is AudioStreamOggVorbis:
		stream.loop = true

	if _ambient_player.stream == stream and _ambient_player.playing:
		return

	if fade_duration <= 0.0 or not _ambient_player.playing:
		_ambient_player.stream = stream
		_ambient_player.volume_db = -80.0 if fade_duration > 0.0 else 0.0
		_ambient_player.play()
		if fade_duration > 0.0:
			var fade_in := create_tween()
			fade_in.tween_property(_ambient_player, "volume_db", 0.0, fade_duration)
		return

	var old_player := _ambient_player
	var tween := create_tween()
	tween.tween_property(old_player, "volume_db", -80.0, fade_duration)
	tween.tween_callback(func():
		old_player.stream = stream
		old_player.play()
	)
	tween.tween_property(old_player, "volume_db", 0.0, fade_duration)

# ------------------------------------------------------------------------------
# GLOBAL BUS VOLUME CONTROL (Option menus)
# ------------------------------------------------------------------------------
func set_bus_volume_linear(bus_name: StringName, value_0_to_1: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		var db_val := linear_to_db(clampf(value_0_to_1, 0.0001, 1.0))
		AudioServer.set_bus_volume_db(bus_index, db_val)