extends "res://tools/block_industrial.gd"

# ─────────────────────────────────────────────
# BLOCK SUBURBAN — American suburban retail, for a map set on the outskirts of
# a mall: the anchor and its glazed entrance, the big box and the strip across
# the ring road, the outlots, and all the furniture of a very large car park.
#
#   maps/blocks/suburban/suburban_*.map
#
#   godot --headless --path . --script res://tools/block_suburban.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_suburban.gd -- maps/blocks --force [piece names]
#
# Built on block_industrial.gd, which this extends: the same brush kit, hull,
# conventions and no-overwrite rule. Build prefabs with block_prefabs.gd.
#
# WHY THIS FAMILY LOOKS THE WAY IT DOES. Retail of this kind is built to be
# read at 50 km/h from a road, so almost all of it is one enormous blank
# surface with a parapet hiding the roof and a sign on a pole doing the
# talking. That is a gift to this project: huge unbroken walls are cheap in
# brushes, they read from across a map, and they make the car park — which is
# where the fighting is — a wide open place ringed by things you cannot see
# over or through. The pieces here are therefore deliberately plain, and the
# detail is spent on the three places a body can actually interact with the
# building: the entrance, the service dock, and the drive-thru.
#
# HOW IT IS MEANT TO BE LAID OUT. An anchor at one end, the entry court beside
# it, the strip facing it across 120 m of asphalt, outlots scattered along the
# road frontage, and light standards on a 30 m grid through the lot. The lot
# itself is terrain or industrial_parking_lot, not a piece in here.
#
# CAR PARK GEOMETRY RULES, learned the hard way elsewhere in this project:
#   - every kerb is 0.15 m. Under the 0.45 m a body steps over, so nothing in
#     a car park is a wall by accident, and well under the 0.5 m the navmesh
#     baker climbs, so no kerb makes a step the bake calls walkable and
#     move_and_slide then refuses.
#   - every screen wall and parapet is 1.2 m or more, because that is what
#     CoverPointSpawner probes at. A 1.0 m wall is decoration; a 1.2 m wall is
#     a firing position. There is nothing in between on purpose.
#   - lanes a rover has to drive stay 7 m clear of anything.
# ─────────────────────────────────────────────

## Exterior insulation and finish — the beige render every one of these is
## wrapped in.
const EIFS := "PSX_Textures/plaster_1"
const RETAIL_BRICK := "PSX_Textures/brick_wall_tx_2"
const STORE_GLASS := "PSX_Textures/glass_window"
const DARK_GLASS := "PSX_Textures/glass_dark"
const BROKEN_GLASS := "PSX_Textures/glass_broken"
const SIGN_BAND := "PSX_Textures/metal_wall_1"
const ROOF_MEMBRANE := "PSX_Textures/roofing_1"
const KERB := "PSX_Textures/concrete_1"
const WALK := "PSX_Textures/concrete_tx_4@0.5"

const STORE := {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE}
const RETAIL_PLINTH := {"top": WALK, "side": RETAIL_BRICK, "bottom": CONCRETE}
const ISLAND := {"top": DIRT, "side": KERB, "bottom": CONCRETE}

## Kerb height. See the header: it is 0.15 everywhere, deliberately.
const KERB_H := 0.15
## Anything meant to be cover is at least this, because that is the height a
## standing cover point is probed at.
const COVER_H := 1.25

const SUBURBAN := {
	"suburban_mall_anchor": "_mall_anchor",
	"suburban_mall_entry": "_mall_entry",
	"suburban_big_box": "_big_box",
	"suburban_retail_strip": "_retail_strip",
	"suburban_service_dock": "_service_dock",
	"suburban_drive_thru": "_drive_thru",
	"suburban_gas_canopy": "_gas_canopy",
	"suburban_pylon_sign": "_pylon_sign",
	"suburban_entry_monument": "_entry_monument",
	"suburban_parking_island": "_parking_island",
	"suburban_lot_light": "_lot_light",
	"suburban_cart_corral": "_cart_corral",
}


func _initialize() -> void:
	var base := ""
	var force := false
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			only.append(a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_suburban.gd -- maps/blocks [--force] [piece names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("suburban")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in SUBURBAN:
		if not only.is_empty() and not only.has(name):
			continue
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		_ghost_from = -1
		_entities = []
		call(SUBURBAN[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-28s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK SUBURBAN DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── Shared parts ─────────────────────────────────────────────────────────────

## A rectangular band of brushes round a rectangle: `out` metres proud of it,
## `inn` metres inside it, from z0 to z1. `gaps` is the same dictionary
## parapet() takes ("-x", "+x", "-y", "+y" -> [[from, to], ...] along that
## side) for the places something else has to pass through.
##
## WHY THIS EXISTS. Every building in here used to wear its brick base course
## and its parapet as ONE BOX bigger than the mass, which is a box that
## contains the mass: two brushes sharing the whole wall's volume, z-fighting
## across all of it. A brush cannot have a hole, so a base course or a parapet
## round a mass is four brushes round it, butted on their ends.
func _ring(x0: float, y0: float, x1: float, y1: float, out: float, inn: float, z0: float, z1: float, tex: Variant, gaps: Dictionary = {}) -> void:
	wall_run("y", Vector2(y0 - out, y0 + inn), x0 - out, x1 + out, z0, z1, gaps.get("-y", []), tex)
	wall_run("y", Vector2(y1 - inn, y1 + out), x0 - out, x1 + out, z0, z1, gaps.get("+y", []), tex)
	wall_run("x", Vector2(x0 - out, x0 + inn), y0 + inn, y1 - inn, z0, z1, gaps.get("-x", []), tex)
	wall_run("x", Vector2(x1 - inn, x1 + out), y0 + inn, y1 - inn, z0, z1, gaps.get("+x", []), tex)


## The cornice that caps a mass: `out` (0.35) m proud of the wall and 0.3 m back onto
## the roof, as a ring. A solid slab here would also swallow the plant that
## stands on the roof, and the plant is the point of the skyline.
func _parapet_ring(x0: float, y0: float, x1: float, y1: float, top: float, h: float, gaps: Dictionary = {}, out: float = 0.35) -> void:
	_ring(x0, y0, x1, y1, out, 0.3, top, top + h, {"top": CONCRETE, "side": EIFS, "bottom": EIFS}, gaps)


## The band of render above a shopfront that the tenant's name goes on, and
## the parapet over it. One call, because every piece in here has one.
## `y` is the wall face: the band stands proud of it, never into it.
func _fascia(x0: float, x1: float, y: float, depth: float, top: float, band: float) -> void:
	box(Vector3(x0, y, top - band), Vector3(x1, y + depth, top), SIGN_BAND)
	box(Vector3(x0, y, top), Vector3(x1, y + depth + 0.15, top + 0.5), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})


## A run of shopfront: glazing between mullions, on a low brick plinth, with
## the doors as a wider dark bay in the middle. `y` is the WALL FACE and the
## whole thing stands proud of it (to +y); drawn into the wall it was a second
## wall inside the first. `z0` is where it stands, for fronts on a kerbed walk.
func _shopfront(x0: float, x1: float, y: float, top: float, door_at: float = 0.5, z0: float = 0.0) -> void:
	var door := lerpf(x0, x1, door_at)
	# The plinth is in two runs and the door is not on it. The door glass and
	# its posts go down to z0 themselves, and a plinth under them would be a
	# second solid in the same space.
	for pair: Array in [[x0, door - 1.7], [door + 1.7, x1]]:
		var a: float = pair[0]
		var b: float = pair[1]
		if b - a < 0.5:
			continue
		box(Vector3(a, y, z0), Vector3(b, y + 0.3, 0.6), {"top": WALK, "side": RETAIL_BRICK, "bottom": CONCRETE})
		# Mullions every 2.5 m. They are 0.12 m, which is nothing to walk
		# round, but at this scale they are what makes a glass wall read as a
		# shopfront rather than as a sheet of blue. The panes are cut BETWEEN
		# them: a mullion drawn across one sheet of glass is two brushes in
		# the same space, and it flickers.
		var cursor := a
		var m := a + 2.5
		while m < b - 0.3:
			box(Vector3(cursor, y + 0.05, 0.6), Vector3(m - 0.06, y + 0.25, top), STORE_GLASS)
			box(Vector3(m - 0.06, y, 0.6), Vector3(m + 0.06, y + 0.32, top), METAL)
			cursor = m + 0.06
			m += 2.5
		box(Vector3(cursor, y + 0.05, 0.6), Vector3(b, y + 0.25, top), STORE_GLASS)
	box(Vector3(door - 1.5, y + 0.05, z0), Vector3(door + 1.5, y + 0.25, top), DARK_GLASS)
	for s: float in [-1.0, 1.0]:
		box(Vector3(door + s * 1.5, y, z0), Vector3(door + s * 1.7, y + 0.32, top), METAL)


## Rooftop plant: the packaged units and the screen round them. Every one of
## these buildings has a field of them and they are the only thing on the
## skyline above the parapet.
func _rooftop_plant(x0: float, y0: float, x1: float, y1: float, top: float, seed: int) -> void:
	var nx := maxi(1, int((x1 - x0) / 9.0))
	var ny := maxi(1, int((y1 - y0) / 9.0))
	for i in nx:
		for j in ny:
			if _hash_f(i * 31 + j * 17 + seed) < 0.35:
				continue
			var cx := lerpf(x0, x1, (i + 0.5) / float(nx))
			var cy := lerpf(y0, y1, (j + 0.5) / float(ny))
			var w := 1.6 + _hash_f(i + j * 7 + seed) * 1.4
			var d := 1.2 + _hash_f(i * 5 + j + seed) * 1.0
			box(Vector3(cx - w, cy - d, top), Vector3(cx + w, cy + d, top + 1.1), {"top": GRATING, "side": SHUTTER, "bottom": METAL})
			box(Vector3(cx - w * 0.5, cy - d * 0.5, top + 1.1), Vector3(cx + w * 0.5, cy + d * 0.5, top + 1.45), METAL)


## A deterministic 0..1 from one integer, for scattering plant and parking
## bays without carrying a RandomNumberGenerator around.
func _hash_f(n: int) -> float:
	var h: int = n * 374761393 + 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Painted bays along a kerb line, as the thin paint boxes used elsewhere.
func _bays(x0: float, x1: float, y0: float, y1: float, pitch: float, z: float) -> void:
	var x := x0
	while x <= x1 + 0.01:
		box(Vector3(x - 0.06, y0, z), Vector3(x + 0.06, y1, z + 0.0625), PAINT)
		x += pitch


# ── The mall ─────────────────────────────────────────────────────────────────

## THE ANCHOR. A department store 64 x 44 m and 11 m to the parapet, blank on
## three sides because that is how they are built, with a brick base course, a
## taller entry tower on the long face, and a roof covered in plant.
##
## The blankness is the point. It gives the car park a 11 m backstop that
## nothing can see over or shoot through, and it costs about thirty brushes.
func _mall_anchor() -> void:
	var w := 32.0
	var d := 22.0
	var top := 11.0
	box(Vector3(-w, -d, -0.5), Vector3(w, d, top), STORE)
	# Brick to 3 m all the way round, which is what they all have, and what
	# stops the wall reading as one flat 11 m sheet of beige. It stops short
	# of the entry tower, which comes down to the ground on its own.
	_ring(-w, -d, w, d, 0.2, 0.0, -0.5, 3.0, RETAIL_BRICK, {"+y": [[-9.0, 9.0]]})
	# Pilasters: shallow piers up the long faces, 8 m apart. None on the tower
	# face between its shoulders, where the tower itself stands.
	for i in range(-3, 4):
		for s: float in [-1.0, 1.0]:
			if s > 0.0 and absi(i) <= 1:
				continue
			box(Vector3(i * 8.0 - 0.9, s * d, 3.0), Vector3(i * 8.0 + 0.9, s * (d + 0.35), top), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# The parapet, standing proud so the roof is hidden from the lot. Open
	# where the tower goes up through it.
	_parapet_ring(-w, -d, w, d, top, 1.4, {"+y": [[-9.0, 9.0]]})
	# The entry tower: the one piece of architecture on the whole building.
	# It starts at the wall face, and carries on up behind the parapet line as
	# a second brush so it is not also a box inside the mass.
	box(Vector3(-9.0, d, -0.5), Vector3(9.0, d + 3.0, 15.0), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-9.0, d - 0.4, top), Vector3(9.0, d, 15.0), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# Glass on the tower face above the canopy, doors under it.
	box(Vector3(-7.4, d + 3.0, 4.2), Vector3(7.4, d + 3.2, 13.4), DARK_GLASS)
	_shopfront(-6.0, 6.0, d + 3.0, 3.6)
	# The canopy over the doors, on two posts. 3.6 m clear underneath, so a
	# rover goes under it rather than round.
	box(Vector3(-11.0, d + 3.0, 3.6), Vector3(11.0, d + 9.0, 4.2), {"top": GRATING, "side": METAL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 10.0 - 0.3, d + 8.2, 0.0), Vector3(s * 10.0 + 0.3, d + 8.8, 3.6), METAL)
	_rooftop_plant(-w + 5.0, -d + 5.0, w - 5.0, d - 5.0, top, 11)


## THE MALL ENTRANCE: a glazed court between two blank wings, 14 m to the
## ridge, with a steel canopy over the doors and a vestibule you can stand in.
## The one place on the whole building a body can see through.
func _mall_entry() -> void:
	var top := 9.0
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 11.0, -9.0, -0.5), Vector3(s * 20.0, 9.0, top), STORE)
		# The brick course on the two long faces. Not the end facing the court:
		# the court glass stands there.
		for e: float in [-1.0, 1.0]:
			box(Vector3(s * 11.0, e * 9.0, -0.5), Vector3(s * 20.0, e * 9.2, 3.0), RETAIL_BRICK)
		# The cornice, a ring so the plant can stand on the roof inside it.
		_parapet_ring(minf(s * 11.0, s * 20.0) + 0.4, -9.0, maxf(s * 11.0, s * 20.0) - 0.4, 9.0, top, 1.3)
	# The court: glass between the wings, carried up to a gable. In two runs,
	# one each side of the vestibule, so the vestibule really is open at both
	# ends — the glass used to run straight across its mouth.
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			box(Vector3(s * 3.6, e * 8.4, -0.5), Vector3(s * 11.0, e * 9.0, 13.0), STORE_GLASS)
	solid([Vector3(-11.0, -9.0, 13.0), Vector3(11.0, -9.0, 13.0), Vector3(11.0, 9.0, 13.0), Vector3(-11.0, 9.0, 13.0),
			Vector3(-11.0, -0.8, 14.6), Vector3(11.0, -0.8, 14.6), Vector3(11.0, 0.8, 14.6), Vector3(-11.0, 0.8, 14.6)], DARK_GLASS)
	# Mullions up the court, which are also the only thing holding the glass
	# up and so want to look like it. On the outside face, in front of the
	# glass, and in two lengths either side of the canopy that is bolted to them.
	for i in range(-4, 5):
		if absi(i) <= 1:
			continue
		for s: float in [-1.0, 1.0]:
			box(Vector3(i * 2.4 - 0.11, s * 9.0, -0.5), Vector3(i * 2.4 + 0.11, s * 9.2, 3.8), METAL)
			box(Vector3(i * 2.4 - 0.11, s * 9.0, 4.4), Vector3(i * 2.4 + 0.11, s * 9.2, 13.0), METAL)
	# Through the middle: the vestibule, open at both ends so the court is a
	# route and not a wall with a picture of a door on it.
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 3.2, -9.2, -0.5), Vector3(s * 3.6, 9.2, 3.2), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-3.6, -9.2, 3.2), Vector3(3.6, 9.2, 3.6), {"top": WALK, "side": METAL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-13.0, s * 9.0, 3.8), Vector3(13.0, s * 14.0, 4.4), {"top": GRATING, "side": METAL, "bottom": METAL})
		for e: float in [-1.0, 1.0]:
			box(Vector3(e * 12.0 - 0.3, s * 13.2, 0.0), Vector3(e * 12.0 + 0.3, s * 13.8, 3.8), METAL)
	_rooftop_plant(-19.0, -7.0, -12.0, 7.0, top, 3)
	_rooftop_plant(12.0, -7.0, 19.0, 7.0, top, 5)


## A FREE-STANDING BIG BOX, 44 x 30 and 8.5 m up: the whole front in glazing
## under a raised entry parapet, a garden centre fenced off one end, and the
## rest blank. Smaller than the anchor and meant to sit across the lot from it.
func _big_box() -> void:
	var w := 22.0
	var d := 15.0
	var top := 8.5
	box(Vector3(-w, -d, -0.5), Vector3(w, d, top), STORE)
	# The brick course, open on the end where the garden centre joins and across the shopfront.
	_ring(-w, -d, w, d, 0.2, 0.0, -0.5, 2.6, RETAIL_BRICK, {"+x": [[-d, -d + 18.0]], "+y": [[-16.0, 16.0]]})
	# The entry element: a tall slab of parapet over the doors, which is the
	# only way anyone tells one of these buildings from another. The parapet
	# is open where it rises.
	_parapet_ring(-w, -d, w, d, top, 1.3, {"+y": [[-8.0, 8.0]]})
	box(Vector3(-8.0, d - 0.4, top), Vector3(8.0, d + 0.8, top + 3.6), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-7.0, d + 0.8, top + 0.6), Vector3(7.0, d + 0.9, top + 2.8), SIGN_BAND)
	# Glazing up to the underside of the canopy, name band above it.
	_shopfront(-16.0, 16.0, d, 3.4)
	_fascia(-16.0, 16.0, d, 0.4, 6.0, 2.0)
	box(Vector3(-17.5, d, 3.4), Vector3(17.5, d + 4.0, 4.0), {"top": GRATING, "side": METAL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 16.0 - 0.3, d + 3.2, 0.0), Vector3(s * 16.0 + 0.3, d + 3.8, 3.4), METAL)
	# The garden centre: a fenced yard off the end, open to the sky. Good
	# ground to fight over — cover inside, one way in. The fence stands on the
	# slab and the three runs butt at their corners.
	box(Vector3(w, -d, -0.5), Vector3(w + 14.0, -d + 18.0, 0.1), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: Array in [[w, -d, w + 14.0, -d + 0.3], [w, -d + 17.7, w + 14.0, -d + 18.0], [w + 13.7, -d + 0.3, w + 14.0, -d + 17.7]]:
		box(Vector3(s[0], s[1], 0.1), Vector3(s[2], s[3], COVER_H + 0.55), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	_rooftop_plant(-w + 4.0, -d + 4.0, w - 4.0, d - 6.0, top, 23)


## THE STRIP across the road: six tenant bays under one continuous canopy,
## 68 m long and 5.5 m to the parapet, with a service door to each at the back.
## The piece that makes the other side of a car park into somewhere.
func _retail_strip() -> void:
	var half := 34.0
	var d := 9.0
	var top := 5.5
	box(Vector3(-half, -d, -0.5), Vector3(half, d, top), STORE)
	# Brick on the back and both ends. The front is the shopfronts and piers.
	_ring(-half, -d, half, d, 0.2, 0.0, -0.5, 2.4, RETAIL_BRICK, {"+y": [[-half - 0.2, half + 0.2]]})
	_parapet_ring(-half, -d, half, d, top, 1.5)
	# Six bays. The dividing piers stand 0.5 m proud of the wall and run up to
	# the parapet, which is what makes one long building read as six
	# tenancies. The fascia is the same depth, so they are flush.
	var bays := 6
	for i in bays:
		var x0 := lerpf(-half, half, float(i) / bays) + 0.6
		var x1 := lerpf(-half, half, float(i + 1) / bays) - 0.6
		_shopfront(x0, x1, d, 3.6, 0.3 + 0.4 * _hash_f(i * 13), KERB_H)
		_fascia(x0, x1, d, 0.5, 4.9, 1.3)
		# The back door and its step. 0.15 m, like every other step here. The
		# door stands proud of the brick course; it used to be set into it.
		box(Vector3(lerpf(x0, x1, 0.5) - 0.9, -d - 0.5, -0.5), Vector3(lerpf(x0, x1, 0.5) + 0.9, -d - 0.2, 2.2), SHUTTER)
		box(Vector3(lerpf(x0, x1, 0.5) - 1.3, -d - 1.6, 0.0), Vector3(lerpf(x0, x1, 0.5) + 1.3, -d - 0.5, KERB_H), RETAIL_PLINTH)
	for i in range(0, bays + 1):
		var x := lerpf(-half, half, float(i) / bays)
		box(Vector3(x - 0.6, d, KERB_H), Vector3(x + 0.6, d + 0.5, top), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# The walk and the canopy over it: 3.4 m clear, so it shelters bodies and
	# not vehicles, and the kerb at its edge is 0.15. The canopy starts at the
	# face of the piers and fascia.
	box(Vector3(-half, d, -0.5), Vector3(half, d + 4.0, KERB_H), RETAIL_PLINTH)
	box(Vector3(-half, d + 0.5, 3.4), Vector3(half, d + 3.6, 3.9), {"top": GRATING, "side": METAL, "bottom": METAL})
	var p := -half + 3.0
	while p < half:
		box(Vector3(p - 0.14, d + 3.0, KERB_H), Vector3(p + 0.14, d + 3.3, 3.4), METAL)
		p += 6.0
	_rooftop_plant(-half + 4.0, -d + 3.0, half - 4.0, d - 3.0, top, 41)


## THE BACK OF HOUSE: a dock wall with four doors, levellers, a compactor and
## a screen wall round the bins. The side of a mall nobody photographs and the
## side a squad actually fights on, because it is the only face with cover.
func _service_dock() -> void:
	var half := 22.0
	var top := 8.0
	box(Vector3(-half, 2.0, -0.5), Vector3(half, 10.0, top), STORE)
	_parapet_ring(-half, 2.0, half, 10.0, top, 1.3)
	# The dock itself is a 1.2 m shelf, which is a lorry bed and also exactly
	# the height a standing cover point wants. Both of those are on purpose.
	box(Vector3(-half, 0.0, -0.5), Vector3(half, 2.0, 1.2), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	for i in 4:
		var x := lerpf(-half + 5.0, half - 5.0, float(i) / 3.0)
		box(Vector3(x - 2.0, 1.8, 1.2), Vector3(x + 2.0, 2.0, 5.4), SHUTTER)
		box(Vector3(x - 2.3, 1.6, 5.4), Vector3(x + 2.3, 2.0, 5.9), METAL)
		# Bumpers, and the leveller plate hanging off the dock edge.
		for s: float in [-1.0, 1.0]:
			box(Vector3(x + s * 2.1, -0.2, 0.5), Vector3(x + s * 2.3, 0.0, 0.9), RUBBER)
		box(Vector3(x - 1.8, -0.4, 1.05), Vector3(x + 1.8, 0.0, 1.2), GRATING)
	# Stairs up to the dock at one end, because a 1.2 m shelf with no way up
	# is a shelf the squad can see and never reach.
	ramp(-half - 3.2, 0.0, -half, 2.0, -0.5, 0.0, 1.2, "+x", {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	# The bin store: three walls at cover height, open to the lot. The end
	# wall runs between the other two, not through them.
	box(Vector3(half + 2.0, 0.0, -0.5), Vector3(half + 12.0, 0.4, COVER_H), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(half + 2.0, 7.6, -0.5), Vector3(half + 12.0, 8.0, COVER_H), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(half + 11.6, 0.4, -0.5), Vector3(half + 12.0, 7.6, COVER_H), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(half + 3.0, 1.4, 0.0), Vector3(half + 7.4, 5.0, 2.1), {"top": METAL, "side": GREEN, "bottom": METAL})
	box(Vector3(half + 8.0, 1.4, 0.0), Vector3(half + 11.0, 4.2, 1.6), {"top": METAL, "side": GREEN, "bottom": METAL})
	_rooftop_plant(-half + 4.0, 3.5, half - 4.0, 8.5, top, 61)


# ── Outlots ──────────────────────────────────────────────────────────────────

## A drive-thru restaurant on its own lot: a small building with glazing on
## two sides, a lane round the back of it behind a kerb, a menu board and a
## window canopy. The lane is 4 m, which a rover will not fit down — that is
## correct, it is a car lane, and the kerb is 0.15 so a body crosses it freely.
func _drive_thru() -> void:
	var w := 9.0
	var d := 7.0
	var top := 4.6
	box(Vector3(-w, -d, -0.5), Vector3(w, d, top), STORE)
	# The brick course, open across the shopfront.
	_ring(-w, -d, w, d, 0.2, 0.0, -0.5, 1.4, RETAIL_BRICK, {"+y": [[-7.0, 7.0]]})
	_parapet_ring(-w, -d, w, d, top, 1.6)
	# A mansard band of a different colour, which is the one flourish this
	# building type is allowed.
	_ring(-w, -d, w, d, 0.5, 0.0, top - 1.0, top, SIGN_BAND)
	_shopfront(-7.0, 7.0, d, 3.2)
	# Glazing down the near end, standing on the brick course.
	box(Vector3(-w - 0.2, -d + 1.0, 1.4), Vector3(-w, d - 3.0, 3.4), STORE_GLASS)
	# The service window and its little canopy, on the lane side.
	box(Vector3(w, -2.0, 1.4), Vector3(w + 0.2, 1.0, 2.6), DARK_GLASS)
	box(Vector3(w + 0.2, -2.6, 2.6), Vector3(w + 2.2, 1.6, 3.0), {"top": GRATING, "side": METAL, "bottom": METAL})
	# The lane: a 4 m strip of asphalt wrapping the back and the window side,
	# kerbed on its outside edge. The back run stops where the side run starts.
	box(Vector3(w + 0.4, -d - 6.0, -0.5), Vector3(w + 4.4, d + 2.0, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-w - 4.4, -d - 6.0, -0.5), Vector3(w + 0.4, -d - 2.0, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(w + 4.4, -d - 6.0, -0.5), Vector3(w + 4.6, d + 2.0, KERB_H), ISLAND)
	box(Vector3(-w - 4.6, -d - 6.2, -0.5), Vector3(w + 4.6, -d - 6.0, KERB_H), ISLAND)
	# The menu board and the speaker post, standing on the lane. The board sits
	# on a stub of post rather than the post running through it.
	box(Vector3(w + 1.2, -d - 4.6, 0.05), Vector3(w + 1.5, -d - 2.6, 1.0), METAL)
	box(Vector3(w + 0.9, -d - 4.8, 1.0), Vector3(w + 1.8, -d - 2.4, 2.8), {"top": METAL, "side": SIGN_BAND, "bottom": METAL})
	box(Vector3(w + 3.4, -d - 1.4, 0.05), Vector3(w + 3.7, -d - 1.1, 1.5), METAL)


## A FUEL CANOPY: four pump islands under a 5.2 m deck on six columns, with
## the kiosk off to one side. 5.2 m clear so anything in the game drives
## under it, and the islands are 0.15 kerbs so nothing walks into one.
func _gas_canopy() -> void:
	var w := 14.0
	var d := 9.0
	var clear := 5.2
	box(Vector3(-w, -d, clear), Vector3(w, d, clear + 1.0), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	# The skirt round the deck, a ring: a slab here would be the deck twice.
	_ring(-w, -d, w, d, 0.3, 0.0, clear + 0.2, clear + 0.8, SIGN_BAND)
	for i in 3:
		for s: float in [-1.0, 1.0]:
			var x := lerpf(-w + 3.0, w - 3.0, float(i) / 2.0)
			box(Vector3(x - 0.45, s * (d - 2.5) - 0.45, 0.0), Vector3(x + 0.45, s * (d - 2.5) + 0.45, clear), {"top": METAL, "side": CONCRETE, "bottom": CONCRETE})
	for i in 2:
		for s: float in [-1.0, 1.0]:
			var x := lerpf(-w + 5.0, w - 5.0, float(i))
			var y := s * 3.2
			box(Vector3(x - 3.0, y - 1.1, -0.5), Vector3(x + 3.0, y + 1.1, KERB_H), ISLAND)
			# The pumps. Two to an island, as a body-sized thing to get behind.
			for e: float in [-1.0, 1.0]:
				box(Vector3(x + e * 1.6 - 0.5, y - 0.45, KERB_H), Vector3(x + e * 1.6 + 0.5, y + 0.45, KERB_H + 1.7), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	# The kiosk, which is where the cover is.
	box(Vector3(w + 4.0, -6.0, -0.5), Vector3(w + 16.0, 2.0, 4.2), STORE)
	_ring(w + 4.0, -6.0, w + 16.0, 2.0, 0.2, 0.0, 4.2, 5.0, {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	_shopfront(w + 5.0, w + 15.0, -6.32, 3.0)


# ── Signs and furniture ──────────────────────────────────────────────────────

## THE PYLON. 16 m of tenant panels on a clad column, at the road. It is the
## piece that tells a player where the mall is from anywhere on the map, and
## at 16 m it clears the anchor's parapet by 5 m, which is the whole job.
func _pylon_sign() -> void:
	box(Vector3(-2.6, -1.6, -0.6), Vector3(2.6, 1.6, 0.3), {"top": WALK, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(-1.5, -0.9, 0.3), Vector3(1.5, 0.9, 4.0), RETAIL_BRICK)
	box(Vector3(-1.1, -0.7, 4.0), Vector3(1.1, 0.7, 15.4), {"top": METAL, "side": EIFS, "bottom": METAL})
	# The cabinet: the tenant panels, set proud of the column on both faces. It
	# is built round the column — two wings and a skin each side — because
	# drawn as one block it contained the column.
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 1.1, -0.95, 6.0), Vector3(s * 2.9, 0.95, 15.4), {"top": METAL, "side": METAL, "bottom": METAL})
		box(Vector3(-1.1, s * 0.7, 6.0), Vector3(1.1, s * 0.95, 15.4), {"top": METAL, "side": METAL, "bottom": METAL})
	for i in 5:
		var z := lerpf(6.4, 14.6, float(i) / 5.0)
		for s: float in [-1.0, 1.0]:
			box(Vector3(-2.7, s * 0.95, z), Vector3(2.7, s * 1.05, z + 1.4), SIGN_BAND)
	# The crown, which is the bit with the mall's own name on.
	box(Vector3(-3.2, -1.1, 15.4), Vector3(3.2, 1.1, 16.6), {"top": METAL, "side": SIGN_BAND, "bottom": METAL})


## The low wall at the entrance off the ring road, with planting behind it.
## 1.3 m, so it is cover, which is unusual for a thing whose job is decorative
## and is the reason to have it on a map at all.
func _entry_monument() -> void:
	box(Vector3(-7.0, -1.8, -0.5), Vector3(7.0, 1.8, KERB_H), ISLAND)
	box(Vector3(-6.0, -0.9, KERB_H), Vector3(6.0, 0.1, COVER_H + 0.05), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(-6.3, -1.05, COVER_H + 0.05), Vector3(6.3, 0.25, COVER_H + 0.35), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-4.4, -1.1, 0.45), Vector3(4.4, -0.9, 1.15), SIGN_BAND)
	# The bed behind it, raised on its own kerb.
	box(Vector3(-6.6, 0.2, KERB_H), Vector3(6.6, 1.7, 0.55), ISLAND)
	for i in 5:
		var x := lerpf(-5.2, 5.2, float(i) / 4.0)
		box(Vector3(x - 0.5, 0.6, 0.55), Vector3(x + 0.5, 1.4, 1.5), {"top": DIRT, "side": SPOIL, "bottom": DIRT})


## A PARKING ISLAND: the kerbed strip between two rows of bays, with the
## bay lines painted off both sides of it. The piece that turns a flat slab of
## asphalt into a car park, and the thing a squad crosses a lot of.
func _parking_island() -> void:
	var half := 18.0
	box(Vector3(-half, -1.4, -0.5), Vector3(half, 1.4, KERB_H), ISLAND)
	# Nose-in bays either side, 2.7 m apart.
	for s: float in [-1.0, 1.0]:
		_bays(-half, half, s * 1.4, s * 6.8, 2.7, 0.0)
		box(Vector3(-half, s * 6.8, 0.0), Vector3(half, s * 6.86, 0.0625), PAINT)
	# Three stumps along it. Mesh only: a 0.3 m stump is above the 0.25 m the
	# baker climbs and the 0.45 m a body steps over is close enough that half
	# the squad catches on one, and a car park wants to be walked across.
	no_collision()
	for i in 3:
		var x := lerpf(-half + 4.0, half - 4.0, float(i) / 2.0)
		cylinder(Vector3(x, 0.0, KERB_H), 0.55, 0.35, 7, SPOIL, 0.42)
		cylinder(Vector3(x, 0.0, KERB_H + 0.35), 0.22, 1.9, 6, {"top": SPOIL, "side": SPOIL, "bottom": SPOIL}, 0.17)


## THE LIGHT STANDARD. 9 m, double head, on a 0.6 m concrete base. On a 30 m
## grid these are the only vertical things in a car park, so they are what a
## squad takes cover behind and what breaks up every sightline across it.
func _lot_light() -> void:
	box(Vector3(-0.55, -0.55, -0.5), Vector3(0.55, 0.55, 0.6), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-0.26, -0.26, 0.6), Vector3(0.26, 0.26, 9.0), METAL)
	# The arms leave the pole's face rather than starting inside it, and the
	# heads hang from the arms rather than interpenetrating them.
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 0.26, -0.22, 8.6), Vector3(s * 2.2, 0.22, 8.9), METAL)
		box(Vector3(s * 1.5, -0.75, 8.25), Vector3(s * 2.6, 0.75, 8.6), {"top": METAL, "side": METAL, "bottom": SIGN_BAND})


## A trolley corral: a roof on four posts over a rail pen. Chest high, two
## metres by four, and the only cover in the middle of a car park.
func _cart_corral() -> void:
	box(Vector3(-2.2, -1.3, -0.5), Vector3(2.2, 1.3, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-2.2, s * 1.3, 0.0), Vector3(2.2, s * 1.3 + s * 0.12, COVER_H), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	# The closed end, outboard of the slab and spanning the two rails' ends.
	box(Vector3(-2.4, -1.42, 0.0), Vector3(-2.2, 1.42, COVER_H), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	# The posts stand outside the rails, not through them.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(sx * 2.1 - 0.09, sy * 1.51 - 0.09, 0.0), Vector3(sx * 2.1 + 0.09, sy * 1.51 + 0.09, 2.6), METAL)
	box(Vector3(-2.5, -1.6, 2.6), Vector3(2.5, 1.6, 2.8), {"top": ROOF_MEMBRANE, "side": METAL, "bottom": METAL})
