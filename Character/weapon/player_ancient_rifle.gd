extends HUDWeapon
class_name PlayerAncientRifle

# ─────────────────────────────────────────────
# ANCIENT RIFLE, with a magazine that actually leaves the gun.
#
# THE PROBLEM THIS SOLVES. Unlike the Mark One and the Squad Automatic, this
# weapon is not a model built for the game: it is AssaultRifle2_1.blend out of a
# gun pack, and it imports as ONE MeshInstance3D. Its three surfaces are split by
# MATERIAL (Main, MainDark, MainLight) and each spans the length of the weapon,
# so there is no node to pose and no surface to pull out — which is why it had a
# reload that moved the whole gun about and nothing else.
#
# So the magazine is separated AT LOAD, from the geometry, by taking the
# triangles that fall inside a measured box and building two meshes out of one.
#
# NOTHING IS EDITED TO DO THIS. The .blend is untouched, the imported mesh is
# only ever READ — resources are shared in this project, and writing to that one
# would corrupt the rifle for the AI's copies too — and the two meshes built here
# are new ArrayMeshes assigned to this instance alone. Setting `split_magazine`
# false restores the original single mesh exactly, which is the whole reason it
# is a flag rather than an asset change.
#
# WHERE THE BOX CAME FROM. tools/_m4_profile.gd prints a vertical profile of the
# mesh: the muzzle is +X, two things hang below the bore, and there is a clear
# gap between them. The first cut assumed the FORWARD lump was the magazine and
# tinted it to check: it came away pink and it was the TRIGGER GUARD. On this
# model the guard sits at x 1.00 to 1.34 and the magazine is the one behind it,
# x 0.63 to 0.83, reaching y -0.72. Hence the box below, and hence the tint:
# MAG_TINT=1 paints whatever came away bright pink, which answers "did it take
# the right thing" in one render and nothing else does.
# ─────────────────────────────────────────────

## Off restores the imported mesh exactly as it came, with no magazine node and
## the old whole-weapon reload. Here because this is geometry surgery on somebody
## else's asset and it has to be possible to take back in one step.
@export var split_magazine: bool = true

## The magazine, in the mesh's own local space. Measured, not guessed — see the
## note above and tools/_m4_profile.gd. Deliberately tight at the back (1.00,
## against a grip that ends at 0.82) and generous at the front and bottom, where
## there is nothing else to catch.
const MAG_BOXES: Array[AABB] = [
	# The magazine, but only the part of it BELOW THE WELL.
	#
	# The top is deliberately short. Artist modelled the magazine and the magwell
	# as one continuous surface, so a cut that takes the whole magazine leaves the
	# well as an open single-sided shell — you see straight through the gun, and
	# it reads as a slice missing rather than a magazine gone. Stopping the cut at
	# the well.s lip leaves the top of the magazine behind as a plug, which fills
	# that hole. The dropped magazine is the visible part only, which is the part
	# anybody was ever going to look at.
	AABB(Vector3(0.40, -1.05, -0.30), Vector3(0.62, 0.93, 0.60)),
	# AND THE TAB AT THE FRONT OF IT, which the main box misses by four
	# hundredths and which stayed hanging under the magwell after the magazine had
	# gone. It cannot simply be swallowed by widening the main box: the trigger
	# guard starts at x 1.00 too, and a box wide enough to catch this tab takes
	# the guard with it and leaves THAT flapping instead. So it is its own region,
	# measured off the six triangles that were left behind (x 0.99 to 1.07,
	# y -0.32 to 0.03) and kept tight enough to reach nothing else.
	AABB(Vector3(0.97, -0.36, -0.055), Vector3(0.12, 0.26, 0.11)),
]

const MAG := "Magazine"
## Where the magazine ends up once it is clear of the well.
const MAG_CLEAR := Vector3(-0.12, -2.6, 0.0)

var _split_done: bool = false


func _on_initialize() -> void:
	super()
	_split_off_magazine()


## ALSO ON _ready, because the split has to have happened before anything can
## look at the weapon — including tools/preview_viewmodel.gd, which renders the
## scene without ever running initialize(). Guarded, so whichever fires first
## does it once.
func _ready() -> void:
	# m4_hud_weapon.tscn sets weapon_model but NOT viewmodel — every other weapon
	# scene sets both. viewmodel is what part() resolves names against, so without
	# this the magazine node exists, renders, and never moves, which looks exactly
	# like the split having failed.
	if viewmodel == null:
		viewmodel = weapon_model
	_split_off_magazine()


# ─────────────────────────────────────────────
# ONE MESH, TWO MESHES.
#
# Triangles are sorted by CENTROID rather than by vertex, so a triangle is never
# half in each mesh and no hole opens along the cut. Both meshes keep the whole
# original vertex array and differ only in their index list, which costs a little
# memory and keeps every normal, UV and attribute exactly as the artist left it —
# rebuilding the vertex data is where this would go wrong and start shading
# differently from the rest of the gun.
# ─────────────────────────────────────────────
func _split_off_magazine() -> void:
	if not split_magazine or _split_done:
		return
	_split_done = split_part(MAG, MAG_BOXES)


# ─────────────────────────────────────────────
# THE RELOAD.
#
# Same shape as the Mark One's, because it is the same job: a box magazine out
# of a magazine well. The difference is only that this one had to be cut out of
# the mesh first.
# ─────────────────────────────────────────────

## Probed, not guessed — see the note in player_bolt_rifle.gd and the POSES
## switch on tools/preview_viewmodel.gd. This holds the rifle where the magwell
## is actually in shot, which reload_position does not.
const WORK_POS := Vector3(0.31, 0.25, -0.015)
const WORK_ROT := Vector3(0.2, 20.5, 58.0)


func _reload_frame(t: float) -> Array:
	if not _split_done:
		return []   # no magazine to drop; the generic motion is the honest answer
	var up := [base_position, base_rotation]
	var open := [WORK_POS, WORK_ROT]
	var seat := [WORK_POS + Vector3(0.0, 0.03, 0.0), WORK_ROT + Vector3(5.0, -3.0, 0.0)]
	if t < 0.14:
		_mag(0.0)
		return ease_pose(up, open, t / 0.14)
	if t < 0.34:
		var k: float = (t - 0.14) / 0.20
		_mag(k * k)                       # out, and falling
		return ease_pose(open, open, 0.0)
	if t < 0.54:
		_mag(1.0)                         # gone, the other hand is busy
		return ease_pose(open, [(open[0] as Vector3) + Vector3(0.0, -0.04, 0.0), open[1]],
			(t - 0.34) / 0.20)
	if t < 0.76:
		var k: float = (t - 0.54) / 0.22
		_mag(1.0 - smoothstep(0.0, 1.0, k))   # in, decelerating; it is pushed
		return ease_pose([(open[0] as Vector3) + Vector3(0.0, -0.04, 0.0), open[1]], open, k)
	_mag(0.0)
	if t < 0.86:
		return ease_pose(open, seat, (t - 0.76) / 0.10)   # struck home
	return ease_pose(seat, up, (t - 0.86) / 0.14)


func _mag(k: float) -> void:
	var e: float = clampf(k, 0.0, 1.0)
	pose_part(MAG, shift(MAG_CLEAR * e)
		* swing(Vector3(0, 0, 1), -12.0 * e, MAG_BOXES[0].get_center()))
