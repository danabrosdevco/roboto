extends StaticBody3D
class_name BreakablePanel

# ─────────────────────────────────────────────
# BREAKABLE PANEL — a wall or door you shoot through.
#
# Drop it in, set health, done. Nothing needs assigning: the mesh, collider and
# spark effect are all in the scene, and every export has a working default.
#
# TAKES TWO ARGUMENTS. Every damage source in this project calls
# apply_damage(amount, source) — ai_weapon, the player's hud weapon, melee and
# Explosion all pass an attributor. test_target.gd declares apply_damage(damage)
# with ONE parameter, so shooting a crate raises "too many arguments" rather
# than damaging it. The source is optional here so both conventions work.
#
# `destroyed` is the useful bit for a tutorial: wire it to an objective and
# "shoot through the wall" becomes a completion condition with no new code.
# ─────────────────────────────────────────────

signal damaged(remaining: int, amount: int)
signal destroyed(panel: BreakablePanel)

@export var health: int = 60
@export var max_health: int = 60
## NEUTRAL by default so the AI's hostility checks never pick it as a target —
## a squad shooting a door instead of you is not the tutorial anyone wants.
@export var faction: Enums.Factions = Enums.Factions.NEUTRAL
## Reported to anything asking whether this blocks a line — cover scoring and
## the AI's obstacle checks both use it.
@export var obstacle: bool = true
## Seconds between the killing blow and the panel vanishing, so the hit lands
## visually before the hole appears.
@export var destroy_delay: float = 0.15
## Leave true to free the node. False hides it and disables the collider
## instead, which is what you want if something still needs the reference.
@export var free_on_destroy: bool = true
@export var hit_effect: ParticleEffect
@export var death_effect: ParticleEffect
@export var hit_sound: AudioStreamPlayer3D
@export var death_sound: AudioStreamPlayer3D
## Broadcast a sound stimulus when it breaks, so nearby AI investigate the
## noise. Off by default — a tutorial wall should not summon the map.
@export var alert_on_destroy: bool = false
@export var alert_radius: float = 25.0

var alive: bool = true

@onready var _collider: CollisionShape3D = _find_collider()


func _ready() -> void:
	if max_health < health:
		max_health = health


# `source` is unused but must be accepted — see the note at the top.
func apply_damage(damage, _source = null) -> void:
	if not alive:
		return
	health -= int(damage)
	damaged.emit(maxi(health, 0), int(damage))
	if health > 0:
		if hit_effect != null:
			hit_effect.activate()
		if hit_sound != null:
			hit_sound.play()
		return
	alive = false
	_break()


func _break() -> void:
	if death_effect != null:
		death_effect.activate()
	if death_sound != null:
		death_sound.play()
	if alert_on_destroy:
		_emit_stimulus()

	# Collider off FIRST, so the opening is walkable the instant it breaks even
	# while the delay plays out. Deferred because this can run from inside a
	# physics callback, and changing a collider mid-query is a Godot error.
	if _collider != null:
		_collider.set_deferred("disabled", true)

	destroyed.emit(self)

	if destroy_delay > 0.0:
		await get_tree().create_timer(destroy_delay).timeout
	if not is_inside_tree():
		return
	if free_on_destroy:
		queue_free()
	else:
		visible = false


func _emit_stimulus() -> void:
	# StimulusManager is a child of AIManager and is in no group, so there is no
	# lookup to do but a search. One-shot on destruction, so the cost is fine.
	var manager := get_tree().root.find_child("StimulusManager", true, false)
	if manager == null or not manager.has_method("emit_stimulus"):
		push_warning("BreakablePanel '%s': alert_on_destroy is on but no StimulusManager was found, so breaking it alerts nobody." % name)
		return
	manager.emit_stimulus(
		StimulusManager.StimulusType.GUNSHOT_HEARD,
		global_position, faction, null)


func _find_collider() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null


# The contract the rest of the project expects from something shootable.
func get_faction():
	return faction


func get_obstacle() -> bool:
	return obstacle


func health_fraction() -> float:
	return clampf(float(health) / maxf(float(max_health), 1.0), 0.0, 1.0)
