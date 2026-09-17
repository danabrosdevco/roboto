extends Node3D
class_name Explosion
@export var effects: Array[GPUParticles3D]
@export var audio: AudioStreamPlayer3D
@export var damage_value:=  20
@export var damage_area: Area3D
# Who set it off. Whatever spawns the explosion should set this — the AI grenade
# and the player's grenade both know. Left at NEUTRAL it damages everyone, which
# is the old behaviour.
@export var source_faction: Enums.Factions = Enums.Factions.NEUTRAL
# WHO THREW IT. The blast used to pass itself as the damage source, which meant
# a grenade kill was credited to a particle effect — nobody scored it, nobody
# barked it, and the victim never retaliated, because apply_damage only reacts
# when the source `is CharacterBody3D` and an Explosion is a Node3D. Grenades
# were tactically invisible to the AI.
@export var source_actor: Node = null
# Blast hits everyone, allies included, just softer. A grenade that politely
# ignores your squad is worse than one that makes you think about where you
# throw it.
@export var friendly_fire_multiplier: float = 0.34
var damaged: = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	for i in effects:
		i.emitting = true
	audio.pitch_scale = randf_range(0.9, 1.1)   # ±10% pitch change
	if get_parent() is not World:
		audio.play()
	await get_tree().create_timer(0.3).timeout
	damage_area.monitoring = false
	await get_tree().create_timer(2).timeout
	queue_free()



func _on_area_3d_body_entered(body: Node3D) -> void:
	if damaged.has(body):  # skip repeat
		return

	var attacker: Node = self
	if source_actor != null and is_instance_valid(source_actor):
		attacker = source_actor

	if body.has_method("apply_damage"):
		body.apply_damage(_damage_for(body), attacker)
		damaged[body] = true
	elif body.get_parent() and body.get_parent().has_method("apply_damage"):
		# This branch was calling apply_damage() with one argument against a
		# two-argument signature — a runtime error every time it was reached.
		body.get_parent().apply_damage(_damage_for(body.get_parent()), attacker)
		damaged[body.get_parent()] = true


func _damage_for(body: Node) -> int:
	if source_faction == Enums.Factions.NEUTRAL:
		return damage_value   # nobody set an owner — blast hits everyone fully
	if not body.has_method("get_faction"):
		return damage_value
	if Enums.are_hostile(source_faction, body.get_faction()):
		return damage_value
	return maxi(1, int(round(float(damage_value) * friendly_fire_multiplier)))
