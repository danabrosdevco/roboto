extends Node3D
class_name Explosion

## By path, not by class_name — see the note in ai_weapon.gd.
const _WeaponAudio := preload("res://Managers/weapon_audio.gd")

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")
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

# ── SIGNAL ────────────────────────────────────
# A blast rattles electronics further than it shreds plate. signal_radius is
# deliberately WIDER than the damage Area3D (2.5 m on the base scene): being
# near a shell should cost you your link even when it does not cost you armour,
# which is what gives high explosive a job in the suppression economy that
# small arms cannot do — area denial that degrades rather than kills.
#
# NO RECOVERY LOCK. That is what makes an EMP an EMP: see EmpBlast.lock_signal.
# A frag rattles you and you start climbing back immediately; an EMP holds you
# down. Peak here is tuned to land a clean target just under FUZZED rather than
# anywhere near E-KILL, so no amount of ordinary ordnance does the EMP's job.
@export var signal_radius: float = 8.0
@export var peak_signal_damage: float = 0.35
@export var edge_signal_damage: float = 0.05

var damaged: = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Same rule as the projectile that spawned it: see ai_grenade_projectile.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for i in effects:
		i.emitting = true
	audio.pitch_scale = randf_range(0.9, 1.1)   # ±10% pitch change
	# Banded like a gunshot. A mortar landing three streets away is the thing
	# the player most needs to hear, and it was cut off entirely past its
	# authored max_distance.
	#
	# UNCONDITIONAL. This used to be skipped when the blast was parented to the
	# World, which silenced it completely rather than merely unbanding it — and
	# the World was exactly where every explosion from the player's own kit
	# ended up, because thrown ordnance was parented there. An explosion you
	# cannot hear is never the right answer.
	_WeaponAudio.stage(audio)
	audio.play()
	# DEFERRED, for the reason EmpBlast documents at length: whatever spawns a
	# blast adds it to the tree and only THEN sets its position, so in _ready
	# it is still at the world origin. The kinetic damage never noticed because
	# it comes from an Area3D that resolves on a later physics frame, after the
	# move — a distance sweep run here would measure everyone's range from
	# (0,0,0) and reliably hit nothing.
	_pulse_signal.call_deferred()
	await get_tree().create_timer(0.3, false).timeout
	damage_area.monitoring = false
	await get_tree().create_timer(2, false).timeout
	queue_free()



func _on_area_3d_body_entered(body: Node3D) -> void:
	if damaged.has(body):  # skip repeat
		return

	var attacker: Node = self
	if source_actor != null and is_instance_valid(source_actor):
		attacker = source_actor

	_Analytics.set_cause(str(get_meta(&"analytics_cause", "Explosion")))
	if body.has_method("apply_damage"):
		body.apply_damage(_damage_for(body), attacker)
		damaged[body] = true
	elif body.get_parent() and body.get_parent().has_method("apply_damage"):
		# This branch was calling apply_damage() with one argument against a
		# two-argument signature — a runtime error every time it was reached.
		body.get_parent().apply_damage(_damage_for(body.get_parent()), attacker)
		damaged[body.get_parent()] = true
	_Analytics.clear_cause()


## Signal damage to everything in range, falling off to the edge.
##
## BY GROUP, NOT THROUGH THE DAMAGE AREA. The Area3D is a 2.5 m sphere on a
## collision layer; this needs a wider reach and needs to find the player,
## which is in AI.SIGNAL_GROUP along with every robot. Direct distance checks
## for the same reason EmpBlast uses them: an area needs a physics frame to
## populate its overlaps and a one-shot pulse has no frame to wait for.
##
## No line-of-sight test, which is the same simplification EmpBlast makes — a
## blast round a corner still rattles you. If that ever reads wrong, both
## should gain the check together rather than drifting apart.
func _pulse_signal() -> void:
	if peak_signal_damage <= 0.0 or signal_radius <= 0.0:
		return
	var attacker: Node = self
	if source_actor != null and is_instance_valid(source_actor):
		attacker = source_actor
	_Analytics.set_cause(str(get_meta(&"analytics_cause", "Explosion")))
	for n in get_tree().get_nodes_in_group(AI.SIGNAL_GROUP):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method("receive_signal_damage"):
			continue
		if "alive" in n and not n.alive:
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d > signal_radius:
			continue
		var t: float = clampf(d / maxf(signal_radius, 0.01), 0.0, 1.0)
		var amount: float = lerpf(peak_signal_damage, edge_signal_damage, t)
		# Your own ordnance costs your own side less, exactly as its kinetic
		# damage does — one number per blast for "how much this hurts us".
		if source_faction != Enums.Factions.NEUTRAL and n.has_method("get_faction") \
				and not Enums.are_hostile(source_faction, n.get_faction()):
			amount *= friendly_fire_multiplier
		n.receive_signal_damage(amount, attacker)
	_Analytics.clear_cause()


func _damage_for(body: Node) -> int:
	if source_faction == Enums.Factions.NEUTRAL:
		return damage_value   # nobody set an owner — blast hits everyone fully
	if not body.has_method("get_faction"):
		return damage_value
	if Enums.are_hostile(source_faction, body.get_faction()):
		return damage_value
	return maxi(1, int(round(float(damage_value) * friendly_fire_multiplier)))
