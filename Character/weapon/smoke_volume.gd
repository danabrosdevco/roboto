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
##
## FORTY-FIVE, not fourteen. Fourteen is about how long it takes to decide to
## cross a street, which meant the cloud was thinning before anyone had moved
## through it — you threw it, watched it, and went anyway. Smoke is for buying
## a crossing or a recovery, and both of those are measured in tens of seconds.
##
## SCENE VALUE, NOT THIS ONE, is what the game uses: smoke_volume.tscn sets it
## and an @export default changes nothing for a node already in a .tscn. Kept in
## step so the two never tell different stories.
@export var duration: float = 45.0
## The last stretch, over which it thins out. Sight comes back gradually
## rather than the cloud snapping off: `blocks_sight` shrinks with the alpha,
## so what you see is what the AI sees. Longer with a longer cloud, or a
## forty-five second screen would stand solid and then drop in three.
@export var fade_seconds: float = 6.0
## The billow, as a fraction of `radius`, at the moment it bursts. It grows to
## full over `grow_seconds` so a canister reads as filling a space.
@export var start_scale: float = 0.35
@export var grow_seconds: float = 1.2
@export var puffs: Array[Node3D] = []

# ── BILLOW ────────────────────────────────────
#
# WHY THE FIRST VERSION DID NOT LOOK LIKE SMOKE. Five puffs, welded in a fixed
# arrangement, scaled in lockstep by their parent. Nothing ever moved relative
# to anything else, so it read as one object inflating rather than as a cloud
# churning — and all five shared ONE material, so where they overlapped you got
# "more opaque" instead of depth.
#
# Three things fix it, none of them expensive:
#   * MORE PUFFS, placed on a spiral rather than by hand, so the silhouette is
#     lumpy instead of showing five ball outlines.
#   * EACH ONE ON ITS OWN CLOCK. Its own phase, its own slow tumble, its own
#     breathing, and its own moment of blooming — outer puffs arrive late, which
#     is what makes a cloud look like it is boiling outward rather than
#     expanding as a unit.
#   * ITS OWN MATERIAL, so alpha can vary puff to puff and an overlap reads as
#     something in front of something else.
#
# The puffs are BUILT IN CODE, not added to smoke_volume.tscn. The scene's five
# stay as the template this copies mesh and material from, and the count becomes
# a number you can turn. It also means none of this needs the editor to reload a
# scene.
#
# Cost is a dozen unshaded spheres on a handful of clouds a mission. The sight
# test is unchanged and still reads density(), so what the player sees and what
# the AI sees have not come apart.

## Total puffs in the cloud, the scene's own included.
@export var puff_count: int = 14
## Turns per second of the slow tumble, and the rate the puffs breathe at.
@export var churn_speed: float = 0.18
## How far a puff wanders from its resting place, as a fraction of its distance
## out. Small on purpose: a cloud seethes, it does not swap its parts around.
@export var churn_amount: float = 0.16
## How far the cloud lifts over its life, as a fraction of radius. Smoke rises.
@export var rise: float = 0.22
## Seed for the puff layout. Fixed, so a cloud looks the same every time it is
## thrown and a screenshot can be compared with the one before it.
@export var layout_seed: int = 20109
## Alpha of ONE puff at full density. Low on purpose: fourteen of these overlap,
## and depth should come from how many you are looking through rather than from
## any one being opaque. The sight test does not read this — blocks_sight() uses
## density(), so turning the look up or down never changes what the AI can see.
@export_range(0.05, 0.6) var puff_alpha: float = 0.28

## Per-puff constants, worked out once: resting direction, distance out, base
## scale, tumble axis, phase, bloom delay, alpha multiplier.
var _rest: Array[Vector3] = []
var _dist: Array[float] = []
var _base_scale: Array[float] = []
var _axis: Array[Vector3] = []
var _phase: Array[float] = []
var _bloom: Array[float] = []
var _alpha_mul: Array[float] = []

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
	_build_puffs()
	_apply(0.0)


## Brings the cloud up to `puff_count` by copying the scene's first puff, then
## works out the constants each one lives by.
##
## EVERY PUFF GETS ITS OWN MATERIAL. The scene shares one between its five —
## which was right when they all faded together and is wrong now that they are
## meant to differ. Duplicated per puff, so a dozen materials per cloud and a
## handful of clouds a mission.
func _build_puffs() -> void:
	var template: MeshInstance3D = null
	for p in puffs:
		if p is MeshInstance3D:
			template = p as MeshInstance3D
			break
	if template == null:
		# EVERY EARLY RETURN SAYS WHY. No template means no mesh to copy, which
		# means a cloud that blocks sight and draws nothing — invisible to the
		# player and solid to the AI, which is the worst way round.
		push_warning("SmokeVolume: no MeshInstance3D in `puffs`, so the cloud has nothing to draw. It will still block sight.")
		return
	while puffs.size() < puff_count:
		var copy := MeshInstance3D.new()
		copy.mesh = template.mesh
		# AND ITS MATERIAL. Without this a generated puff falls back to the
		# default — opaque, lit, white — so the cloud came out as a solid rock
		# with a couple of translucent puffs stuck to it, and from inside it was
		# a white wall. The duplicate() below then gives each one its own copy.
		copy.material_override = template.material_override
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(copy)
		puffs.append(copy)

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var n := puffs.size()
	for i in n:
		var mi := puffs[i] as MeshInstance3D
		if mi != null and mi.material_override != null:
			mi.material_override = mi.material_override.duplicate()
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				# CULLING OFF, and this is the difference between smoke and a wall.
				# A sphere with back faces culled is INVISIBLE from inside it, so a
				# player standing in his own screen saw straight through the puffs
				# around him to the far side of the cloud — a flat slab with a hard
				# polygon edge and daylight through the gaps. With it off you are
				# inside something.
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# A spiral over the sphere rather than random points: random clumps and
		# leaves holes, and a hole in a smoke cloud is a hole you get shot
		# through. This spreads them and the jitter stops it looking woven.
		var t: float = (float(i) + 0.5) / float(n)
		var y: float = 1.0 - 2.0 * t
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var theta: float = float(i) * 2.399963   # the golden angle
		var dir := Vector3(cos(theta) * r, y * 0.55, sin(theta) * r).normalized()
		dir = (dir + Vector3(rng.randfn(0.0, 0.12), rng.randfn(0.0, 0.08),
			rng.randfn(0.0, 0.12))).normalized()
		_rest.append(dir)
		_dist.append(rng.randf_range(0.14, 0.46))
		_base_scale.append(rng.randf_range(0.62, 1.0))
		_axis.append(Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0),
			rng.randfn(0.0, 1.0)).normalized())
		_phase.append(rng.randf_range(0.0, TAU))
		# The ones further out arrive later, which is what boiling outward looks
		# like. The centre is up immediately so the canister reads as having gone
		# off rather than as having been placed.
		_bloom.append(_dist[i] * 0.9)
		_alpha_mul.append(rng.randf_range(0.72, 1.0))


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
	# Rises over its whole life, not just while it grows — in local units,
	# because the parent scale carries it out to world size.
	var lift: float = rise * clampf(age / maxf(duration, 0.001), 0.0, 1.0)

	for i in puffs.size():
		var p: Node3D = puffs[i]
		if p == null or not is_instance_valid(p):
			continue
		var mi := p as MeshInstance3D
		if mi == null:
			continue
		# A puff the constants were never worked out for — a scene edited while
		# this was running. Left where it is rather than thrown to the origin.
		if i >= _rest.size():
			continue

		# Its own clock: a slow sine, offset per puff, so no two are ever at the
		# same point of the same breath.
		var churn: float = sin(age * churn_speed * TAU + _phase[i])
		var bloom: float = 1.0
		if grow_seconds > 0.0:
			bloom = clampf((age - _bloom[i]) / grow_seconds, 0.0, 1.0)
			bloom = bloom * bloom * (3.0 - 2.0 * bloom)   # smoothstep, so it swells in

		var out: float = _dist[i] * (1.0 + churn_amount * churn) * bloom
		p.position = _rest[i] * out + Vector3(0.0, lift, 0.0)
		var puff_scale: float = _base_scale[i] * (1.0 + 0.12 * churn) * lerpf(0.45, 1.0, bloom)
		# Tumbling, slowly. It is a sphere, so this does nothing on its own —
		# but the puffs are not perfect spheres at ten segments, and the
		# faceting catching the light differently per puff is most of what
		# stops them reading as identical balls.
		# Basis carries rotation AND scale, so it is set once, from both — assigning
		# scale after a basis would be thrown away by the next basis write.
		p.basis = Basis(_axis[i], age * churn_speed * 0.6 + _phase[i]).scaled(
			Vector3(puff_scale, puff_scale, puff_scale))

		if mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			# Per puff now, each on its own duplicated material, so an overlap
			# reads as one thing in front of another instead of simply darker.
			mat.albedo_color.a = a * puff_alpha * _alpha_mul[i] * bloom


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
