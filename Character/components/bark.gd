extends Node3D  # Or just `Node` if it's not in 3D space
class_name Bark
@export var bark_clips: Array[AudioStream] = []
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func bark():
	if bark_clips.is_empty():
		return
	var random_bark = bark_clips.pick_random()
	audio_player.stream = random_bark
	audio_player.play()
