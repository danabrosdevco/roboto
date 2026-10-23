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
# So the magazine is separated AT LOAD, from the geometry: a measured box picks
# the triangles and a plane cuts through the ones the box cannot decide, making
# two meshes out of one.
#
# NOTHING IS EDITED TO DO THIS. The .blend is untouched, the imported mesh is
# only ever READ — resources are shared in this project, and writing to that one
# would corrupt the rifle for the AI's copies too — and the two meshes built here
# are new ArrayMeshes assigned to this instance alone. Setting `split_magazine`
# false restores the original single mesh exactly, which is the whole reason it
# is a flag rather than an asset change.
#
# WHERE THE NUMBERS CAME FROM. tools/probe_m4_magazine.gd prints a vertical
# profile of the mesh: the muzzle is +X, two things hang below the bore, and
# there is a clear gap between them. The first cut assumed the FORWARD lump was
# the magazine and tinted it to check: it came away pink and it was the TRIGGER
# GUARD.
#
# NOTHING HERE WAS EVER RIGHT ON REASONING ALONE — three cuts were shipped and
# three were reported back from play, each one read as correct until it was
# rendered. So: PART_TINT=Magazine paints whatever came away bright pink, and
# tools/probe_m4_split_shot.gd puts the weapon side on and underneath with the
# magazine both seated and dropped. Look at the pictures before believing a cut.
# ─────────────────────────────────────────────

## Off restores the imported mesh exactly as it came, with no magazine node and
## the old whole-weapon reload. Here because this is geometry surgery on somebody
## else's asset and it has to be possible to take back in one step.
@export var split_magazine: bool = true

## The magazine, in the mesh's own local space. Measured, not guessed —
## tools/probe_m4_magazine.gd prints every triangle these boxes do NOT take in
## the magazine's neighbourhood, and tools/probe_m4_split_shot.gd renders the
## weapon side on with the cut tinted pink so "what came away" and "what stayed"
## are in one frame.
##
## THESE ONLY NOMINATE. The cut itself is made by MAG_LIP below, and the two
## want reading together: a box says which triangles are in play, the plane says
## where through them the magazine ends. Loose here is safe; loose there is not.
const MAG_BOXES: Array[AABB] = [
	# The body of the magazine, everything below the bore.
	AABB(Vector3(0.40, -1.05, -0.30), Vector3(0.62, 1.07, 0.60)),
	# The tab at the top front, which the main box misses by four hundredths.
	# Stops at y -0.33 rather than reaching down: the trigger guard's upper arc
	# is at y -0.34 to -0.43 across the same x, and a box deep enough to catch
	# this tab from below takes the guard with it and leaves THAT flapping.
	AABB(Vector3(0.97, -0.33, -0.09), Vector3(0.13, 0.35, 0.18)),
	# The front spine, x 1.04 to 1.21 and y -0.56 to -0.31 — the thin vertical
	# slice that stayed behind. It sits FORWARD of the guard rather than above
	# it, which is the only reason it can be taken without taking the guard
	# too, and it is why this is a third region and not a taller second one.
	AABB(Vector3(1.04, -0.56, -0.09), Vector3(0.17, 0.25, 0.18)),
	# The shroud, the wedge of magazine ABOVE the bore line and below the
	# receiver. See MAG_LIP — the box only nominates it, the plane does the cut.
	AABB(Vector3(0.60, 0.02, -0.09), Vector3(0.50, 0.082, 0.18)),
]

## WHERE THE MAGAZINE ENDS AND THE GUN BEGINS, and the reason this weapon needs
## a clip plane when no other does.
##
## The artist modelled the magazine and the wall of the magwell as ONE SURFACE.
## Each side of it is a single quad running from the floor of the magazine all
## the way up past the receiver, so magazine and gun are not merely adjacent
## triangles — they are the SAME triangles. No box can separate them. Both ways
## of trying were shipped and both were reported from play: stop the box low and
## a wedge of magazine stays bolted under the receiver; raise it until it catches
## those quads and it takes one triangle of each and leaves the other, which
## tears a ragged fringe along the cut.
##
## So the plane cuts THROUGH them, at the receiver's own underside. Below it is
## magazine and leaves; above it is the wall of the well and stays, which is what
## keeps the well from becoming a hole. The receiver's lowest geometry is y
## +0.103 and the shroud's highest vertex is well under that, so +0.098 sits in
## the gap with room on both sides — close enough that the sliver left behind is
## hidden by the receiver's own skin, far enough that a reimport nudging things a
## hair does not start slicing the receiver.
const MAG_LIP := Plane(Vector3.UP, 0.098)

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
	_split_done = split_part(MAG, MAG_BOXES, "", [], MAG_LIP)


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
