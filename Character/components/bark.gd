extends Node3D
class_name Bark

# ─────────────────────────────────────────────
# BARK — one robot's voice.
#
# Requests go through BarkDirector, which owns the channel and decides whether
# this robot is the one who speaks. Call bark(line); do NOT call bark_now()
# unless you are the director.
#
# The old shape was one flat bark_clips array picked at random, fired from a
# single trigger (apply_damage). That is why 102 of the 105 droid voices had
# never been heard.
# ─────────────────────────────────────────────

# The voice library. Shared across every robot using this set — see BarkSet.
@export var bark_set: BarkSet

# LEGACY. The original flat array, kept so existing chassis scenes keep making
# noise until they are pointed at a BarkSet. Used only when bark_set is null or
# has nothing for the requested line.
@export var bark_clips: Array[AudioStream] = []

# Set per-chassis to tell voices apart — the same library at 0.8 reads as a
# heavier frame, at 1.2 as a lighter one.
@export var pitch_min: float = 0.96
@export var pitch_max: float = 1.06

# The squad this voice belongs to, used by the director for its per-squad
# budget and to find the NCO. Resolved lazily: a robot's squad is assigned
# after _ready in most spawn paths.
var squad: Node = null

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

# Shuffle bag per line. pick_random() plays the same clip twice in a row often
# enough to make a library feel much smaller than it is; a bag exhausts every
# clip before repeating.
var _bags: Dictionary = {}


func _ready() -> void:
	# Radio chatter has its own VOICE slider in the options.
	audio_player.bus = AudioBuses.VOICE


# Ask to speak. The director may well say no — that is the entire point, and
# callers should not care.
# `context` is whatever the line needs to read as a sentence — the name of the
# thing spotted or killed. It reaches the comms log, not the audio.
func bark(line: int = BarkSet.Line.HURT, context: String = "") -> void:
	BarkDirector.request(self, line, _resolve_squad(), context)


# Called by the director once this robot has won the channel. Plays
# unconditionally; all arbitration already happened.
func bark_now(line: int) -> void:
	var clip := _next_clip(line)
	if clip == null:
		return
	audio_player.stream = clip
	audio_player.pitch_scale = randf_range(pitch_min, pitch_max)
	audio_player.play()


func _resolve_squad() -> Node:
	if squad != null and is_instance_valid(squad):
		return squad
	# Enemy/Soldier own the squad reference; the bark node hangs below them.
	var owner_node := get_parent()
	while owner_node != null:
		if "squad" in owner_node and owner_node.squad != null:
			squad = owner_node.squad
			return squad
		owner_node = owner_node.get_parent()
	return null


func _next_clip(line: int) -> AudioStream:
	var clips: Array[AudioStream] = []
	if bark_set != null:
		clips = bark_set.clips_for(line)
	if clips.is_empty():
		clips = bark_clips
	if clips.is_empty():
		return null

	var bag: Array = _bags.get(line, [])
	if bag.is_empty():
		for i in clips.size():
			bag.append(i)
		bag.shuffle()
		# Avoid the seam: a reshuffle can put the clip we just played back at
		# the front, which is the repeat the bag exists to prevent.
		if bag.size() > 1 and _bags.has(line) and bag[0] == _last_index.get(line, -1):
			bag.append(bag.pop_front())
	var index: int = bag.pop_back()
	_bags[line] = bag
	_last_index[line] = index
	if index < 0 or index >= clips.size():
		return null
	return clips[index]


var _last_index: Dictionary = {}
