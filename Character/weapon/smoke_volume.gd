extends Node3D
class_name SmokeVolume

# ─────────────────────────────────────────────
# SMOKE — the only thing in the game that blocks sight without blocking fire.
#
# IT CANNOT BE A PHYSICS BODY. Every AI sight test in this project is a
# raycast (Enemy.is_path_clear), and so is every bullet — so a smoke volume
# with a collider would stop rounds as well as eyes, which is not smoke, it is
# a wall you cannot see. Instead the volumes put themselves in a group and the
# sight test asks them directly: one segment-versus-sphere check per live
# volume, and there are rarely more than two.
#
# THE COST IS PAID ONLY WHEN SMOKE EXISTS. is_path_clear runs many times per
# robot per tick, so `_active` counts live volumes statically and blocks_sight()
# returns on a compare when there are none. With no smoke on the map this costs
# an integer test.
#
# Spawned exactly where a frag's Explosion would be — it is the canister's
# `explosion_scene` — which is why it carries source_actor/source_faction it
# never reads. Same trick the Hatchling's payload uses.
# ─────────────────────────────────────────────

## How far the cloud reaches. The sight test is a sphere, so this is the whole
## of it — no cone, no drift.
@export var radius: float = 7.0
## Seconds it blocks for, fade included.
@export var duration: float = 14.0
## The last stretch, over which it thins out. Sight comes back gradually
## rather than the cloud snapping off: `blocks_sight` shrinks with the alpha,
## so what you see is what the AI sees.
@export var fade_seconds: float = 3.0
## The billow, as a fraction of `radius`, at the moment it bursts. It grows to
## full over `grow_seconds` so a canister reads as filling a space.
@export var start_scale: float = 0.35
@export var grow_seconds: float = 1.2
@export var puffs: Array[Node3D] = []

## Live volumes. Static so the sight test can bail without touching the tree.
static var _active: int = 0

# Set by AIGrenadeProjectile when it spawns this in place of an explosion. Not
# read — smoke is not owned by anyone once it is out — but assigned, so the
# properties have to exist or the detonation errors.
var source_actor: Node = null
var source_faction: Enums.Factions = Enums.Factions.NEUTRAL

var _age: float = 0.0


func _ready() -> void:
	_active += 1
	add_to_group(&"smoke")
	_apply(0.0)


func _exit_tree() -> void:
	_active -= 1


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	_apply(_age)


## 1.0 at full opacity, easing to 0 across the last `fade_seconds`. The AI's
## sight and the player's eyes read the same number.
func density() -> float:
	var left := duration - _age
	if left >= fade_seconds or fade_seconds <= 0.0:
		return 1.0
	return clampf(left / fade_seconds, 0.0, 1.0)


func _apply(age: float) -> void:
	var grow: float = 1.0 if grow_seconds <= 0.0 else clampf(age / grow_seconds, 0.0, 1.0)
	var s: float = lerpf(start_scale, 1.0, grow) * radius
	scale = Vector3(s, s, s)
	var a := density()
	for p in puffs:
		if p == null or not is_instance_valid(p):
			continue
		var mi := p as MeshInstance3D
		if mi == null or mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			# duplicate() in the scene, not here: sharing one material across
			# every puff in every cloud would fade them all together.
			mat.albedo_color.a = a * 0.55


# ─────────────────────────────────────────────
# THE SIGHT TEST
# ─────────────────────────────────────────────
## True when the segment from `from` to `to` passes through live smoke.
## Thinning smoke stops blocking before it stops being drawn — a cloud at 20%
## density only blocks a fifth of its radius, so sight returns from the edges.
static func blocks_sight(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	if _active <= 0 or tree == null:
		return false
	for n in tree.get_nodes_in_group(&"smoke"):
		var vol := n as SmokeVolume
		if vol == null or not is_instance_valid(vol):
			continue
		var reach: float = vol.radius * vol.density()
		if reach <= 0.01:
			continue
		if _segment_hits_sphere(from, to, vol.global_position, reach):
			return true
	return false


## Closest approach of the segment to the centre, against the radius. Clamped
## to the segment rather than the infinite line, or a cloud well behind the
## shooter would blind them.
static func _segment_hits_sphere(from: Vector3, to: Vector3, centre: Vector3, r: float) -> bool:
	var seg := to - from
	var len_sq := seg.length_squared()
	if len_sq < 0.000001:
		return from.distance_to(centre) <= r
	var t := clampf((centre - from).dot(seg) / len_sq, 0.0, 1.0)
	return (from + seg * t).distance_to(centre) <= r
