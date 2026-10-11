extends RefCounted

# ─────────────────────────────────────────────
# SITE ICONS — a small 3D line drawing of each map's defining landmark, to
# stand on the operations table where a generic marker used to.
#
# WHY LINE ART AND NOT LITTLE MODELS. Two reasons, and the second is the real
# one. A node on this board is about two centimetres tall and is read through
# the signal filter, so a solid miniature comes out as an unidentifiable blob
# — the same lesson the map board learnt about text. And the game's existing
# iconography IS line art: the frame and weapon pictures in the armoury and
# the factory are all outline drawings, so a holographic readout drawn the
# same way belongs to the same machine.
#
# Everything here is built from STRUTS — thin square-section bars between two
# points — plus rings made of struts. That is the whole vocabulary. It keeps
# every icon in the same hand, it wears the holo shader without special
# cases, and a landmark that cannot be said in a dozen lines is a landmark
# nobody will recognise at two centimetres anyway.
#
# Each builder draws into a 1x1x1 box standing on the origin, so the board can
# scale them all alike and they sit on the plate rather than through it.
# ─────────────────────────────────────────────


enum Kind {
	MARKER,     # the fallback: a plain diamond, a place and nothing claimed
	RELAY,      # Hillfort: a 59 m dish on a yoke
	ANCHOR,     # Valley Basin: the orbital tether anchor
	TOWER,      # The Causeway: the horned black tower, 408 m
	WHEEL,      # Qamareen: the derelict big wheel
	BRIDGE,     # Coast Road: a low concrete girder bridge
	FURNACE,    # Three Rivers: a blast furnace with its downcomer
	STACK,      # Lockside: a banded brick mill chimney
	DERRICK,    # the Sim Arenas: the centre tower and its lattice
	MALL,       # Polaris: a long low mass with a glazed entry court
	CLOCKTOWER, # Over The Top: the village church tower
}

## Line thickness as a fraction of the icon's height.
const WEIGHT := 0.045
## Segments in a full ring. Ten reads as a circle at this size and costs far
## less than sixteen.
const RING_SEGMENTS := 10


## One landmark, as a mesh standing on the origin in a unit box.
static func build(kind: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		Kind.RELAY: _relay(st)
		Kind.ANCHOR: _anchor(st)
		Kind.TOWER: _tower(st)
		Kind.WHEEL: _wheel(st)
		Kind.BRIDGE: _bridge(st)
		Kind.FURNACE: _furnace(st)
		Kind.STACK: _stack(st)
		Kind.DERRICK: _derrick(st)
		Kind.MALL: _mall(st)
		Kind.CLOCKTOWER: _clocktower(st)
		_: _marker(st)
	st.generate_normals()
	return st.commit()


# ── THE LANDMARKS ────────────────────────────
#
# Each is the real structure, drawn from the generator function that built
# it. The .map files are hand-countable sets of boxes and beams, and every
# generator carries a prose doc comment describing its piece in primitives —
# which is exactly what a line drawing needs. Measured heights are in the
# comments for whoever tunes the scale later.


## Hillfort: a 59 m parabolic dish on a two-armed yoke over a pedestal drum,
## tilted back, with a feed quadpod. 63 m. Not a satellite dish — a radio
## telescope, which is why it is the whole icon and not a detail on a mast.
static func _relay(st: SurfaceTool) -> void:
	_ring(st, Vector3(0, 0.08, 0), 0.17, Vector3.UP)
	_strut(st, Vector3(0, 0.08, 0), Vector3(0, 0.34, 0))
	for x in [-0.16, 0.16]:
		_strut(st, Vector3(0, 0.34, 0), Vector3(x, 0.5, 0))
	var hub := Vector3(0, 0.58, 0.04)
	var face := Vector3(0.0, 0.52, -0.86).normalized()
	_ring(st, hub, 0.38, face)
	_ring(st, hub, 0.19, face)
	var u := face.cross(Vector3.UP).normalized()
	var v := face.cross(u).normalized()
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		_strut(st, hub + (u * cos(a) + v * sin(a)) * 0.38, hub)
	_strut(st, hub, hub - face * 0.3)


## Valley Basin: a tapered pylon carrying a flared anchor head, the tether
## climbing out of it, and four guys to deadman blocks. The tether leaves the
## top of the box uncapped on purpose — the far end of it is not on this
## table, and that is the whole idea of the structure.
static func _anchor(st: SurfaceTool) -> void:
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		var c := Vector3(cos(a), 0.0, sin(a))
		_strut(st, c * 0.17, c * 0.07 + Vector3(0, 0.42, 0))
		var head := Vector3(cos(a) * 0.22, 0.56, sin(a) * 0.22)
		_strut(st, c * 0.07 + Vector3(0, 0.42, 0), head)
		_strut(st, head, c * 0.52)
	_ring(st, Vector3(0, 0.42, 0), 0.1, Vector3.UP)
	_ring(st, Vector3(0, 0.56, 0), 0.22, Vector3.UP)
	_strut(st, Vector3(0, 0.56, 0), Vector3(0, 1.0, 0))


## The Causeway: a ribbed shaft stepping in twice, four horns leaning out off
## the crown, a relay lattice above them. 408 m — the biggest structure in
## the game, and the scale pass lets it stand taller than anything else here.
static func _tower(st: SurfaceTool) -> void:
	var w := [0.21, 0.16, 0.11]
	var y := [0.0, 0.36, 0.52, 0.64]
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		var c := Vector3(cos(a), 0.0, sin(a))
		for s in 3:
			_strut(st, c * w[s] + Vector3(0, y[s], 0), c * w[s] + Vector3(0, y[s + 1], 0))
		_strut(st, c * w[2] + Vector3(0, y[3], 0), c * 0.3 + Vector3(0, 0.86, 0))
	for s in 3:
		_ring(st, Vector3(0, y[s + 1], 0), w[s], Vector3.UP)
	_strut(st, Vector3(0, 0.64, 0), Vector3(0, 1.0, 0))
	_ring(st, Vector3(0, 0.95, 0), 0.05, Vector3.UP)


## Qamareen: the derelict big wheel, two rims on an axle between two
## A-frames. 48 m. Nothing else in that city is round, which is why it works.
static func _wheel(st: SurfaceTool) -> void:
	for z in [-0.06, 0.06]:
		var hub := Vector3(0, 0.6, z)
		_ring(st, hub, 0.36, Vector3.FORWARD)
		for i in 5:
			var a: float = float(i) * PI / 2.5
			_strut(st, hub, hub + Vector3(cos(a) * 0.36, sin(a) * 0.36, 0))
	for z in [-0.14, 0.14]:
		_strut(st, Vector3(-0.24, 0, z), Vector3(0, 0.6, z * 0.43))
		_strut(st, Vector3(0.24, 0, z), Vector3(0, 0.6, z * 0.43))
	_strut(st, Vector3(0, 0.6, -0.06), Vector3(0, 0.6, 0.06))


## Coast Road: a low concrete girder bridge with a ramp at each end. The deck
## is only 4 m up — the flattest landmark of the twelve, drawn flat rather
## than given cables it does not have.
static func _bridge(st: SurfaceTool) -> void:
	var deck := 0.3
	_strut(st, Vector3(-0.34, deck, 0), Vector3(0.34, deck, 0))
	_strut(st, Vector3(-0.34, deck - 0.09, 0), Vector3(0.34, deck - 0.09, 0))
	for x in [-0.34, -0.11, 0.11, 0.34]:
		_strut(st, Vector3(x, deck, 0), Vector3(x, deck - 0.09, 0))
	for x in [-0.18, 0.18]:
		_strut(st, Vector3(x, deck - 0.09, 0), Vector3(x, 0.0, 0))
	_strut(st, Vector3(-0.34, deck, 0), Vector3(-0.56, 0.0, 0))
	_strut(st, Vector3(0.34, deck, 0), Vector3(0.56, 0.0, 0))


## Three Rivers: a blast furnace, which the generator calls the works'
## landmark in so many words. Cast house on legs, the vessel, its bustle
## ring, the downcomer dropping to a dust catcher, and the skip incline
## climbing to the throat. 44 m.
static func _furnace(st: SurfaceTool) -> void:
	_ring(st, Vector3(0, 0.14, 0), 0.2, Vector3.UP)
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		_strut(st, Vector3(cos(a) * 0.2, 0, sin(a) * 0.2),
			Vector3(cos(a) * 0.2, 0.14, sin(a) * 0.2))
	_strut(st, Vector3(0, 0.14, 0), Vector3(0, 0.78, 0))
	_ring(st, Vector3(0, 0.4, 0), 0.13, Vector3.UP)
	_ring(st, Vector3(0, 0.74, 0), 0.08, Vector3.UP)
	_strut(st, Vector3(0, 0.78, 0), Vector3(0.22, 0.6, 0))
	_strut(st, Vector3(0.22, 0.6, 0), Vector3(0.22, 0.22, 0))
	_ring(st, Vector3(0.22, 0.22, 0), 0.07, Vector3.UP)
	_strut(st, Vector3(-0.44, 0.0, 0), Vector3(0, 0.74, 0))


## Lockside: the mill chimney. Forty-four metres, four steel bands, and the
## thing the briefing says you can see from every level of the map.
##
## NOT THE LOCK the mission is named after. That chamber is under five metres
## tall and would read as nothing at two centimetres; the name points at the
## place, the silhouette has to point at the thing you can actually see.
static func _stack(st: SurfaceTool) -> void:
	for s in [-1.0, 1.0]:
		_strut(st, Vector3(0.1 * s, 0.1, 0), Vector3(0.05 * s, 0.9, 0))
		_strut(st, Vector3(0.1 * s, 0.0, 0), Vector3(0.1 * s, 0.1, 0))
	_strut(st, Vector3(-0.13, 0.0, 0), Vector3(0.13, 0.0, 0))
	_strut(st, Vector3(-0.13, 0.1, 0), Vector3(0.13, 0.1, 0))
	for i in 4:
		var y: float = 0.26 + float(i) * 0.17
		var w: float = lerpf(0.1, 0.05, (y - 0.1) / 0.8)
		_strut(st, Vector3(-w, y, 0), Vector3(w, y, 0))
	_strut(st, Vector3(-0.08, 0.9, 0), Vector3(0.08, 0.9, 0))
	_strut(st, Vector3(-0.05, 0.86, 0), Vector3(-0.08, 0.9, 0))
	_strut(st, Vector3(0.05, 0.86, 0), Vector3(0.08, 0.9, 0))


## The sim arenas: the centre tower, put there expressly so there is
## something to navigate by. A deck on four legs with a ramp, a tapering
## lattice derrick above it, a mast on top. 16 m.
##
## ALL THREE ARENA MISSIONS SHARE ONE LEVEL, so all three carry this drawing.
## That is not a collision to design around — it is true, and three nodes
## wearing the same landmark is the board saying they are the same place.
static func _derrick(st: SurfaceTool) -> void:
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		var c := Vector3(cos(a), 0, sin(a))
		_strut(st, c * 0.26, c * 0.26 + Vector3(0, 0.28, 0))
		_strut(st, c * 0.2 + Vector3(0, 0.28, 0), c * 0.07 + Vector3(0, 0.8, 0))
	_ring(st, Vector3(0, 0.28, 0), 0.26, Vector3.UP)
	_strut(st, Vector3(-0.44, 0.0, 0), Vector3(-0.2, 0.28, 0))
	for y in [0.46, 0.64]:
		_ring(st, Vector3(0, y, 0), lerpf(0.2, 0.07, (y - 0.28) / 0.52), Vector3.UP)
	_strut(st, Vector3(0, 0.8, 0), Vector3(0, 1.0, 0))


## Polaris: the dead mall. A long low blank mass with a glazed entry court
## pushed out of the middle and the parking aisles fanning away from it.
## Nothing on that level is tall, so the icon is WIDE instead — which is the
## honest silhouette rather than a flattering one.
static func _mall(st: SurfaceTool) -> void:
	var h := 0.26
	_strut(st, Vector3(-0.56, h, -0.1), Vector3(0.56, h, -0.1))
	_strut(st, Vector3(-0.56, 0, -0.1), Vector3(-0.56, h, -0.1))
	_strut(st, Vector3(0.56, 0, -0.1), Vector3(0.56, h, -0.1))
	_strut(st, Vector3(-0.56, 0, -0.1), Vector3(0.56, 0, -0.1))
	_strut(st, Vector3(-0.15, h, 0.08), Vector3(-0.15, 0.0, 0.08))
	_strut(st, Vector3(0.15, h, 0.08), Vector3(0.15, 0.0, 0.08))
	_strut(st, Vector3(-0.15, h, 0.08), Vector3(0.0, 0.42, 0.08))
	_strut(st, Vector3(0.15, h, 0.08), Vector3(0.0, 0.42, 0.08))
	_strut(st, Vector3(-0.15, h, 0.08), Vector3(0.15, h, 0.08))
	for x in [-0.34, 0.0, 0.34]:
		_strut(st, Vector3(x * 0.6, 0.01, 0.14), Vector3(x, 0.01, 0.5))


## Over The Top: the village church tower behind the enemy guns. Square
## shaft, a clock face on each side, a belfry and a copper spire. 51 m.
##
## Qamareen has this same prefab standing in its west square, which is why
## Qamareen gets the wheel: two nodes wearing one drawing would be saying
## they are the same place, and they are not.
static func _clocktower(st: SurfaceTool) -> void:
	var w := 0.12
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		var c := Vector3(cos(a) * w, 0, sin(a) * w)
		_strut(st, c, c + Vector3(0, 0.62, 0))
		_strut(st, Vector3(cos(a) * w * 1.3, 0.62, sin(a) * w * 1.3),
			Vector3(cos(a) * w * 1.3, 0.7, sin(a) * w * 1.3))
		_strut(st, Vector3(cos(a) * w, 0.66, sin(a) * w), Vector3(0, 0.9, 0))
	_ring(st, Vector3(0, 0.0, 0), 0.2, Vector3.UP)
	_ring(st, Vector3(0, 0.46, 0), w * 1.44, Vector3.UP)
	_ring(st, Vector3(0, 0.52, 0), w * 1.1, Vector3.FORWARD)
	_ring(st, Vector3(0, 0.62, 0), w * 1.44, Vector3.UP)
	_strut(st, Vector3(0, 0.9, 0), Vector3(0, 1.0, 0))


## The fallback. A plain diamond — what a site with no landmark assigned
## gets. It says "a place" and claims nothing about it.
static func _marker(st: SurfaceTool) -> void:
	var top := Vector3(0, 0.62, 0)
	var mid := 0.3
	var pts := [Vector3(-mid, 0.3, 0), Vector3(0, 0.3, -mid),
		Vector3(mid, 0.3, 0), Vector3(0, 0.3, mid)]
	for i in 4:
		var j: int = (i + 1) % 4
		_strut(st, pts[i], pts[j])
		_strut(st, pts[i], top)
		_strut(st, pts[i], Vector3(0, 0.0, 0))


# ── PRIMITIVES ───────────────────────────────

## A square-section bar from a to b. Square rather than round because at this
## size the difference is invisible and a tube costs eight times the
## triangles for it.
static func _strut(st: SurfaceTool, a: Vector3, b: Vector3, weight: float = WEIGHT) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.0001:
		return
	var dir := span / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := dir.cross(up).normalized() * (weight * 0.5)
	var y := dir.cross(x).normalized() * (weight * 0.5)
	var c := [a - x - y, a + x - y, a + x + y, a - x + y,
		b - x - y, b + x - y, b + x + y, b - x + y]
	for f in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		st.add_vertex(c[f[0]]); st.add_vertex(c[f[1]]); st.add_vertex(c[f[2]])
		st.add_vertex(c[f[0]]); st.add_vertex(c[f[2]]); st.add_vertex(c[f[3]])


## A ring of struts around `centre`, in the plane whose normal is `axis`.
static func _ring(st: SurfaceTool, centre: Vector3, radius: float, axis: Vector3,
		weight: float = WEIGHT) -> void:
	var n := axis.normalized()
	var u := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var a := n.cross(u).normalized()
	var b := n.cross(a).normalized()
	var prev := centre + a * radius
	for i in range(1, RING_SEGMENTS + 1):
		var t: float = float(i) / float(RING_SEGMENTS) * TAU
		var p: Vector3 = centre + (a * cos(t) + b * sin(t)) * radius
		_strut(st, prev, p, weight)
		prev = p
