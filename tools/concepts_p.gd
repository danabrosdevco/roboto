extends RefCounted
class_name ConceptsP

# ─────────────────────────────────────────────
# CONCEPT BUILDER — PICKET, the selected option only.
#
# The Picket was concepted a round earlier than the other nine, in
# tools/mockup_frames.gd, whose builders are INSTANCE methods on a SceneTree
# script and therefore cannot be called from another renderer. This file is the
# winner — C2, launcher-led — ported to the shared static vocabulary so the
# winners sheet can draw it beside the other nine.
#
# It is a PORT, not a redesign. If the two ever disagree, mockup_frames.gd is
# the original and this is the copy.
# ─────────────────────────────────────────────

const K := preload("res://tools/concept_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")


## C2 — launcher-led. Six tubes canted up and unmistakable, the sensor dish
## demoted to a shoulder fitting, Walker legs underneath.
static func picket_c2(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.55, 0.9, 1.5), Vector3(0, 0.45, 0))
	_pods(root_node, Vector3(0.0, 1.22, 0.0), 3, 2, 0.14, 1.25)
	_dish(root_node, Vector3(-0.86, 1.22, 0.42), 0.4)
	for sx in [-1.0, 1.0]:
		K.leg(root_node, Vector3(sx * 0.62, -0.12, 0), 0.66, 0.76, sx * 6.0, 0.0, true)


## The dish. A shallow cone on a short neck, canted up.
static func _dish(to: Node, at: Vector3, r: float) -> void:
	var d := K.node_at(to, at, Vector3(-52.0 * _Parts.DEG, 0, 0))
	_Parts.cyl(d, r, 0.14, Vector3.ZERO, Vector3.ZERO, true, 16)
	_Parts.cyl(d, 0.055, r * 0.75, Vector3(0, r * 0.45, 0))
	_Parts.sphere(d, 0.1, Vector3(0, r * 0.82, 0))
	_Parts.cyl(to, 0.1, 0.5, at + Vector3(0, -0.34, 0))


## The launcher: a block of tubes, canted up.
static func _pods(to: Node, at: Vector3, cols: int, rows: int, r: float,
		len_f: float) -> void:
	# POSITIVE X. A rotation about +X maps -Z to (0, sin, -cos), so a NEGATIVE
	# angle sends the muzzle DOWN and forward — on the one frame whose whole
	# premise is shooting up. Three of the five first-round options had this
	# sign wrong, which is most of why they "looked like guns": their barrels
	# were aimed at the floor.
	#
	# The dish above is NOT the same case and is correctly negative: a cone's
	# axis is +Y, and +X by a negative angle tilts +Y up and forward.
	var b := K.node_at(to, at, Vector3(54.0 * _Parts.DEG, 0, 0))
	_Parts.plate(b, float(cols) * r * 2.4, float(rows) * r * 2.4, 0.16, 0.08,
			Vector3(0, 0, 0.12))
	for c in cols:
		for w in rows:
			var x := (float(c) - float(cols - 1) * 0.5) * r * 2.3
			var y := (float(w) - float(rows - 1) * 0.5) * r * 2.3
			_Parts.cyl(b, r, 1.1 * len_f, Vector3(x, y, -0.5 * len_f),
					Vector3(PI * 0.5, 0, 0))
