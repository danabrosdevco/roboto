extends Node3D
class_name EmpBlast

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

# ─────────────────────────────────────────────
# EMP BLAST — the EMP grenade's payload. Attacks the signal, not the frame.
#
# Spawned by AIGrenadeProjectile exactly where a frag's Explosion would be — it
# carries the same source_actor / source_faction pair the projectile hands over,
# which is the whole contract. So an EMP grenade is just a grenade whose
# explosion_scene is this.
#
# WHAT IT DOES. Every robot in range takes signal damage with falloff, and has
# its signal RECOVERY locked for a few seconds. At the centre that means E-KILL
# — frozen in place, no orders, no fire — and the lock is what makes it a real
# stun rather than a flicker: see Enemy.lock_signal. Further out it lands in
# CRITICAL or DEGRADED instead. Either way it climbs back out gradually.
#
# Hits everyone in range, allies included — softer, the same rule the frag
# follows. A stun that politely skips your squad is a stun you never have to
# think about placing. Hardened Uplink halves both the damage and the lock.
#
# No health damage at all. That is the point of it: you use this to stop a
# garrison, not to kill it, and then your squad does the killing.
# ─────────────────────────────────────────────

@export var radius: float = 9.0
## Signal damage at the centre. Above 1.0 so a direct hit E-KILLs through the
## stock resistance of 1.0.
@export var peak_signal_damage: float = 1.15
@export var edge_signal_damage: float = 0.45
## Seconds of locked recovery at the centre, tapering to edge_lock at radius.
@export var peak_lock: float = 3.5
@export var edge_lock: float = 0.6
## Your own side takes this fraction. Enough to punish a careless throw, not
## enough to freeze your squad solid.
@export var friendly_multiplier: float = 0.25

@export_group("Look")
@export var pulse_color: Color = Color(0.55, 0.9, 1.0, 0.55)
@export var pulse_seconds: float = 0.55

# Set by the projectile before this enters the tree. Same names and meaning as
# Explosion's, which is why the projectile needs no change to throw an EMP.
var source_actor: Node = null
var source_faction: Enums.Factions = Enums.Factions.NEUTRAL


func _ready() -> void:
	# DEFERRED. The projectile adds this to the tree and only THEN sets its
	# position, so in _ready it is still sitting at the world origin. A pulse
	# fired here measured every robot's distance from (0,0,0) and hit nothing.
	# The frag never had this problem because its Explosion finds its targets
	# through an Area3D on later physics frames, after the move has happened.
	_detonate.call_deferred()


func _detonate() -> void:
	_pulse()
	_show()


# Direct distance checks rather than an Area3D. An area needs a physics frame to
# populate its overlaps, and a one-shot blast that waited for one would either
# miss the frame or need its own timer to catch it. Every robot is already in
# the "enemies" group — the player's squad too — so this is exact and immediate.
func _pulse() -> void:
	var hits := 0
	# Credited to the EMP, not the thrower's gun: see Enemy._signal_cause.
	_Analytics.set_cause("EMP")
	for n in get_tree().get_nodes_in_group("enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method("receive_signal_damage"):
			continue
		if "alive" in n and not n.alive:
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d > radius:
			continue
		var t: float = clampf(d / maxf(radius, 0.01), 0.0, 1.0)
		var amount: float = lerpf(peak_signal_damage, edge_signal_damage, t)
		var lock: float = lerpf(peak_lock, edge_lock, t)
		if _is_friendly(n):
			amount *= friendly_multiplier
			lock *= friendly_multiplier
		n.receive_signal_damage(amount, source_actor)
		if n.has_method("lock_signal"):
			n.lock_signal(lock)
		hits += 1
	_Analytics.clear_cause()
	# One line per blast, worth having while tuning radius and falloff.
	print("[EMP] pulse hit %d robot(s) within %.0fm" % [hits, radius])


func _is_friendly(n: Node) -> bool:
	if source_faction == Enums.Factions.NEUTRAL:
		return false
	if not n.has_method("get_faction"):
		return false
	return not Enums.are_hostile(source_faction, n.get_faction())


# An expanding shell, built in code so the payload needs no authored art. It
# has to read as DIFFERENT from a frag at a glance — no fire, no debris, just a
# cold ring going out and fading — because the two do completely different
# things and a player needs to know which one just went off.
func _show() -> void:
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	shell.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = pulse_color
	mat.emission_enabled = true
	mat.emission = Color(pulse_color.r, pulse_color.g, pulse_color.b)
	mat.emission_energy_multiplier = 2.5
	shell.material_override = mat
	shell.scale = Vector3.ONE * 0.2
	add_child(shell)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * radius, pulse_seconds) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, pulse_seconds)
	tween.chain().tween_callback(queue_free)
