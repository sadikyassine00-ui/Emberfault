class_name HubLevel
extends Node

@export_category("Level Audio")
@export var background_music: AudioStream = preload("res://systems/audio/music/The_Snow_Queen.ogg")
@export var ambient_wind: AudioStream = preload("res://systems/audio/ambient/wind_sound.ogg")
@export var music_fade_duration: float = 2.0
@export var ambient_fade_duration: float = 2.0

func _ready() -> void:
	_setup_level_audio()

func _setup_level_audio() -> void:
	if background_music and AudioManager.has_method("transition_to_music"):
		AudioManager.transition_to_music(background_music, music_fade_duration)

	if ambient_wind and AudioManager.has_method("play_ambience"):
		AudioManager.play_ambience(ambient_wind, ambient_fade_duration)
