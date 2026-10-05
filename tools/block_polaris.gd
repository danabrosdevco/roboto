extends "res://tools/block_suburbs.gd"

# ─────────────────────────────────────────────
# BLOCK POLARIS — the pieces the mall-outskirts map needs that the suburban,
# street and suburbs families do not have, after looking at how Polaris
# Fashion Place in Columbus is actually laid out.
#
#   maps/blocks/polaris/polaris_*.map
#
#   godot --headless --path . --script res://tools/block_polaris.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_polaris.gd -- maps/blocks --force [names]
#
# WHAT THE REAL SITE IS, because it decided every piece in here:
#
#   - The mall is ONE IRREGULAR MASS in the middle with the anchors as lobes
#     pushed out of it. It is not a row of boxes.
#   - A CLOSED RING ROAD loops right round it — Fashion Place Loop — as a
#     rounded rectangle, not a square. That is why there is a corner arc in
#     here: a loop made of straights and right angles is a different thing to
#     move around and to be shot across.
#   - Between mall and loop is a FAN OF ANGLED PARKING AISLES, each with a
#     landscape island running its WHOLE length, not just a nose at the end.
#   - The restaurants are NOT in the mall and not on its lot. They are
#     detached pads in a row OUTSIDE the loop, each on its own small lot off a
#     short cross street. That is the single most map-shaping fact about the
#     place: it puts a line of separate, enterable-looking buildings with open
#     ground between them along one whole edge of a very large flat site.
#   - The cinema and a sports barn sit INSIDE the loop as their own masses,
#     and the power-centre big boxes sit outside it across an arterial.
#   - Two retention basins are wedged into the parking, which is where the
#     only terrain on the site is.
#
# Built on block_suburbs.gd, for its _gable and _hip: same kit, same textures,
# same no-overwrite rule.
# ─────────────────────────────────────────────

const POLARIS := {
	"polaris_ring_corner": "_ring_corner",
	"polaris_aisle_long": "_aisle_long",
	"polaris_lot_field": "_lot_field",
	"polaris_lot_main": "_lot_main",
	"polaris_ground_grass": "_ground_grass",
	"polaris_mall_wing": "_mall_wing",
	"polaris_cinema": "_cinema",
	"polaris_parking_garage": "_parking_garage",
	"polaris_restaurant_casual": "_restaurant_casual",
	"polaris_restaurant_upscale": "_restaurant_upscale",
	"polaris_restaurant_fast": "_restaurant_fast",
	"polaris_patio": "_patio",
	"polaris_bank_outlot": "_bank_outlot",
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
		print("usage: godot --headless --path . --script res://tools/block_polaris.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("polaris")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in POLARIS:
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
		call(POLARIS[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-30s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK POLARIS DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── The ring road ────────────────────────────────────────────────────────────

## A ring of `segs` wedges between two radii, from angle a0 to a1 in degrees.
func _ring_band(r0: float, r1: float, a0: float, a1: float, z0: float, z1: float, segs: int, tex: Variant) -> void:
	for i in segs:
		var t0 := deg_to_rad(lerpf(a0, a1, float(i) / segs))
		var t1 := deg_to_rad(lerpf(a0, a1, float(i + 1) / segs))
		solid([Vector3(cos(t0) * r0, sin(t0) * r0, z0), Vector3(cos(t0) * r1, sin(t0) * r1, z0),
				Vector3(cos(t1) * r1, sin(t1) * r1, z0), Vector3(cos(t1) * r0, sin(t1) * r0, z0),
				Vector3(cos(t0) * r0, sin(t0) * r0, z1), Vector3(cos(t0) * r1, sin(t0) * r1, z1),
				Vector3(cos(t1) * r1, sin(t1) * r1, z1), Vector3(cos(t1) * r0, sin(t1) * r0, z1)], tex)


## A QUARTER OF THE RING ROAD: 90° of two-lane carriageway on a 50 m
## centreline, kerbed and footwayed both sides, in twelve wedges.
##
## ITS ORIGIN IS THE CENTRE OF THE CIRCLE, NOT THE ROAD. That looks wrong in
## the editor and is the only sane way to place it: four of these at the same
## point, yawed 0, 90, 180, 270, close a complete loop with no measuring, and
## pushing them apart on one axis turns the loop into the rounded rectangle
## the real one is. A piece whose origin sat on the carriageway would have to
## be positioned by trigonometry every single time.
func _ring_corner() -> void:
	var mid := 50.0
	var half := LANE_W
	var segs := 12
	# NO CARRIAGEWAY BAND. The ring road runs across the car park, which is
	# already asphalt — a second surface at the same height is what makes
	# ground crawl, and a square hole cut in the lot for a quarter-circle of
	# road would be 56 m on a side. The kerbs and the footways are the road.
	for s: float in [-1.0, 1.0]:
		var a := mid + s * half
		var b := mid + s * (half + 0.3)
		_ring_band(minf(a, b), maxf(a, b), 0.0, 90.0, -0.3, KERB_H, segs, {"top": WALK, "side": KERB, "bottom": CONCRETE})
		var c := mid + s * (half + 0.3)
		var d := mid + s * (half + 0.3 + 2.4)
		_ring_band(minf(c, d), maxf(c, d), 0.0, 90.0, -0.3, KERB_H, segs, {"top": WALK, "side": KERB, "bottom": CONCRETE})
	# The centre line, dashed round the arc.
	for i in range(0, segs, 2):
		var t0 := deg_to_rad(lerpf(0.0, 90.0, float(i) / segs))
		var t1 := deg_to_rad(lerpf(0.0, 90.0, float(i) + 0.7) / segs)
		_ring_band(mid - 0.08, mid + 0.08, rad_to_deg(t0), rad_to_deg(t1), 0.0, 0.0625, 1, PAINT)


## One lane. Named apart from block_streets' LANE so neither shadows the
## other if the families are ever merged.
const LANE_W := 3.6


## A FULL-LENGTH PARKING AISLE, 64 m: bays both sides of a kerbed island that
## runs the whole way, trees down it, and the drive lanes marked out.
##
## The island running the whole length is the thing that was wrong in the
## first parking piece I made. On the real site every aisle has one, and it
## matters for more than looks: it is a continuous 0.15 m kerb and a line of
## trunks down the middle of a 64 m lane, which is the only thing breaking up
## a car park that is otherwise four hundred metres of open asphalt.
func _aisle_long() -> void:
	var half := 32.0
	# NO SLAB OF ITS OWN. The car park already has an asphalt surface under
	# this; a second one at the same height made 244 columns of the Polaris lot
	# flicker. The aisle is its island, its bays and its trees.
	# The island stands on the asphalt, not in it, and the bays stop at the line
	# that closes them.
	box(Vector3(-half, -1.5, 0.0), Vector3(half, 1.5, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		_bays(-half, half, s * 1.5, s * 6.94, 2.7, 0.0)
		box(Vector3(-half, s * 7.0 - 0.06, 0.0), Vector3(half, s * 7.0 + 0.06, 0.0625), PAINT)
	no_collision()
	var x := -half + 5.0
	while x < half - 4.0:
		cylinder(Vector3(x, 0.0, KERB_H), 0.5, 0.35, 7, SPOIL, 0.36)
		# The trunk stops at the underside of the crown. It used to run on up
		# through it.
		cylinder(Vector3(x, 0.0, KERB_H + 0.35), 0.2, 1.95, 6, SPOIL, 0.14)
		heap(Vector3(x, 0.0, KERB_H + 2.6), 1.7, 1.7, 1.7, int(x) * 5 + 9, SPOIL)
		x += 9.0


## ONE BIG SLAB OF ASPHALT, 180 m square, with its edges ramped to the ground.
## A car park is one surface and should be one brush: tiling it out of small
## pieces gives the navmesh baker a seam every few metres and the renderer a
## few hundred draw calls for a flat plane.
func _lot_field() -> void:
	# A plain box, not yard_slab: with its top at z = 0 the ramped skirt has
	# no height to ramp through and collapses to nothing, and this is the
	# ground of the map anyway — its edge is the edge of the world, not a kerb
	# anything has to get up.
	box(Vector3(-90.0, -90.0, -3.0), Vector3(90.0, 90.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})


## THE WHOLE CAR PARK AS ONE SLAB, 460 x 360, which is everything inside the
## ring road and a little beyond it. One brush, because a car park is one
## surface: tiling it gives the navmesh baker a seam every few metres and the
## renderer a few hundred draw calls for a flat plane.
func _lot_main() -> void:
	box(Vector3(-230.0, -180.0, -3.0), Vector3(230.0, 180.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})


## Ground that is NOT a car park, 260 x 200. The housing, the frontage verge
## and everything past the lot stand on this, and it is the same height as the
## asphalt so the join is a texture change and not a step.
func _ground_grass() -> void:
	box(Vector3(-130.0, -100.0, -3.0), Vector3(130.0, 100.0, 0.0), {"top": DIRT, "side": SPOIL, "bottom": SPOIL})


# ── Masses inside the loop ───────────────────────────────────────────────────

## A WING OF THE MALL ITSELF: the concourse between two anchors. 72 x 34 and
## 12 m to the parapet, blank, with a service band at the back and a court
## entrance in the middle of the front. Lay two or three of these end to end
## with the anchors on the ends and the result is the central mass.
func _mall_wing() -> void:
	var half := 36.0
	var d := 17.0
	var top := 12.0
	box(Vector3(-half, -d, -0.5), Vector3(half, d, top), STORE)
	# The brick course on the two long faces. It is cut where the court
	# entrance comes down to the ground and where each dock door stands.
	var doors: Array = []
	for i in 4:
		var x := lerpf(-26.0, 26.0, float(i) / 3.0)
		doors.append([x - 2.0, x + 2.0])
	wall_run("y", Vector2(d, d + 0.25), -half, half, -0.5, 3.2, [[-8.0, 8.0]], RETAIL_BRICK)
	wall_run("y", Vector2(-d - 0.25, -d), -half, half, -0.5, 3.2, doors, RETAIL_BRICK)
	# The cornice is a ring, open where the court entrance goes up through it.
	_parapet_ring(-half, -d, half, d, top, 1.6, {"+y": [[-8.0, 8.0]]}, 0.4)
	# Pilasters on both long faces, 9 m apart, which is what stops 72 m of
	# render reading as one surface. They stop at the cornice, which carries on
	# over them, and the ones beside the entrance are trimmed back to it.
	for i in range(-3, 4):
		for s: float in [-1.0, 1.0]:
			var lo: float = i * 9.0 - 1.1
			var hi: float = i * 9.0 + 1.1
			if s > 0.0 and hi > -8.0 and lo < 8.0:
				if i > 0:
					lo = 8.0
				elif i < 0:
					hi = -8.0
				else:
					continue
			box(Vector3(lo, s * d, 3.2), Vector3(hi, s * (d + 0.4), top),
					{"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# The court entrance: a raised glazed bay in the middle of the front. It
	# stands on the wall face and carries on up behind the cornice line as a
	# second brush, so it is never also a box inside the mass.
	box(Vector3(-8.0, d, -0.5), Vector3(8.0, d + 2.0, 15.5), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-8.0, d - 0.5, top), Vector3(8.0, d, 15.5), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-6.4, d + 2.0, 4.2), Vector3(6.4, d + 2.2, 14.0), STORE_GLASS)
	_shopfront(-5.0, 5.0, d + 2.0, 3.6)
	box(Vector3(-10.0, d + 2.0, 3.6), Vector3(10.0, d + 7.5, 4.2), {"top": GRATING, "side": METAL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		post(s * 9.0, d + 6.8, 0.0, 3.6, 0.32)
	# The back: dock doors, because every mall wing has a service corridor.
	# They fill the gaps in the brick course, standing as proud as it does and
	# no taller: above that the pilasters are on the same wall.
	for g: Array in doors:
		box(Vector3(g[0], -d - 0.25, -0.5), Vector3(g[1], -d, 3.2), SHUTTER)
	_rooftop_plant(-half + 5.0, -d + 5.0, half - 5.0, d - 5.0, top, 131)


## THE MULTIPLEX, 58 x 44. An auditorium block that steps UP toward the back,
## because that is what a stack of raked houses does, and a long glazed lobby
## across the front under a deep canopy. 17 m at the tallest, so inside the
## loop it is second only to the mall itself.
func _cinema() -> void:
	var half := 29.0
	# Three steps of auditorium, tallest at the back.
	box(Vector3(-half, -22.0, -0.5), Vector3(half, -6.0, 17.0), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	box(Vector3(-half, -6.0, -0.5), Vector3(half, 2.0, 13.5), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	box(Vector3(-half, 2.0, -0.5), Vector3(half, 9.0, 9.5), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	for z: Array in [[-22.0, -6.0, 17.0], [-6.0, 2.0, 13.5], [2.0, 9.0, 9.5]]:
		box(Vector3(-half - 0.4, z[0], z[2]), Vector3(half + 0.4, z[1], z[2] + 1.4), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# The fins up the blank side walls, which is the whole architecture of one
	# of these buildings. Each stops at the roof of the step it stands on —
	# the cornice above it is a slab that sticks out past the wall, and a fin
	# running up through it is two brushes in one place. The one that used to
	# stand at y = 16 was beside the lobby, on no wall at all, so it is gone.
	for i in range(-2, 2):
		var fin_top := 16.0 if i < 0 else (13.5 if i == 0 else 9.5)
		for s: float in [-1.0, 1.0]:
			box(Vector3(s * half, i * 8.0 - 0.8, -0.5), Vector3(s * (half + 0.7), i * 8.0 + 0.8, fin_top),
					{"top": CONCRETE, "side": SIGN_BAND, "bottom": EIFS})
	# The lobby: glass the full width under a 6 m canopy on round columns. The
	# mullions stand on the outside of the glass and are cut round the canopy
	# and the shopfront that are bolted to it.
	box(Vector3(-half, 9.0, -0.5), Vector3(half, 10.0, 8.0), STORE_GLASS)
	for i in 13:
		var x := lerpf(-half + 1.0, half - 1.0, float(i) / 12.0)
		if absf(x) < 10.2:
			continue
		box(Vector3(x - 0.12, 10.0, -0.5), Vector3(x + 0.12, 10.2, 6.0), METAL)
		box(Vector3(x - 0.12, 10.0, 6.8), Vector3(x + 0.12, 10.2, 8.0), METAL)
	box(Vector3(-half - 1.5, 10.0, 6.0), Vector3(half + 1.5, 19.0, 6.8), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	for i in 5:
		var x := lerpf(-24.0, 24.0, float(i) / 4.0)
		cylinder(Vector3(x, 17.5, -0.5), 0.6, 6.5, 8, CONCRETE)
	_shopfront(-10.0, 10.0, 10.0, 4.4)
	# The marquee over the doors.
	box(Vector3(-12.0, 10.1, 8.0), Vector3(12.0, 10.9, 11.6), {"top": METAL, "side": SIGN_BAND, "bottom": METAL})


## A THREE-DECK PARKING GARAGE, 62 x 34, with the ramp at one end. Open-sided
## with a spandrel at every level, which is both what they look like and what
## makes the decks a place to shoot FROM rather than a sealed box.
func _parking_garage() -> void:
	var half := 31.0
	var d := 17.0
	for lvl in 3:
		var z: float = lvl * 3.4
		box(Vector3(-half, -d, z - 0.45), Vector3(half, d, z), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
		# The spandrel: a 1.1 m upstand at every deck edge. Over cover height
		# and solid, so a body on a deck is protected rather than merely
		# hidden, which is the difference that makes a garage worth taking.
		# The long ones run the full length; the end ones run BETWEEN them,
		# and the west one is open at the stair core's door.
		for s: float in [-1.0, 1.0]:
			box(Vector3(-half, s * d - s * 0.4, z), Vector3(half, s * d, z + 1.15), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
			wall_run("x", Vector2(s * half - s * 0.4, s * half), -(d - 0.4), d - 0.4, z, z + 1.15,
					[[-3.0, 3.0]] if s < 0.0 else [], {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
		# Columns and the spine wall, one storey at a time. They stand on a
		# deck and stop at the soffit of the next, because a column run through
		# every deck is a column inside three slabs. The top storey's go on up
		# to the roof line. They stand just inside the spandrel, not in it.
		var z_top: float = z + 3.4 - 0.45 if lvl < 2 else 10.2
		for i in 9:
			if i == 4:
				continue
			var x := lerpf(-half + 3.0, half - 3.0, float(i) / 8.0)
			for s: float in [-1.0, 1.0]:
				box(Vector3(x - 0.45, s * (d - 0.4) - s * 0.45, z), Vector3(x + 0.45, s * (d - 0.4), z_top), CONCRETE)
		box(Vector3(-0.5, -(d - 0.4), z), Vector3(0.5, d - 0.4, z_top), CONCRETE)
	# The ramp between decks, at one end, as two straight flights. The second
	# is a slab laid ON the first — as a wedge from the ground it contained it.
	ramp(half, -d + 2.0, half + 15.0, d - 2.0, -0.5, 0.0, 3.4, "+x", {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	flight(half, -d + 2.0, half + 15.0, d - 2.0, 3.4, 6.8, "+x", 3.4, {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(half, -d, -0.5), Vector3(half + 15.2, -d + 1.2, 8.0), CONCRETE)
	box(Vector3(half, d - 1.2, -0.5), Vector3(half + 15.2, d, 8.0), CONCRETE)
	# The stair and lift core, which is the only enclosed thing on it.
	box(Vector3(-half - 7.0, -6.0, -0.5), Vector3(-half, 6.0, 11.4), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# The doors fill the gap in the west spandrel, in front of the core's face.
	for lvl in 3:
		box(Vector3(-half, -3.0, lvl * 3.4), Vector3(-half + 0.4, 3.0, lvl * 3.4 + 2.3), SHUTTER)
	# On the core's -y face, so "-y": drawn the other way they were inside it.
	for lvl in 3:
		window("-y", -6.0, -half - 5.5, lvl * 3.4 + 0.9, 1.4, 1.6, true, DARK_GLASS)


# ── Outside the loop: the restaurant row ─────────────────────────────────────

## CASUAL DINING on its own pad, 26 x 16: a hipped roof, a glazed front under
## a deep eave, a bar wing with a lower roof, and a fenced patio on the corner.
## The kind that sits in a row of four along the outside of the loop.
func _restaurant_casual() -> void:
	box(Vector3(-13.0, -8.0, -0.4), Vector3(13.0, 8.0, 4.4), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	_hip(-13.0, -8.0, 13.0, 8.0, 4.4, 7.0, 1.3)
	# The bar wing: lower, pushed out, so the roofline steps. Its roof starts
	# where the main eave stops (14.3 m), not at the wall: from the wall it
	# was inside the main roof and inside the main mass.
	box(Vector3(13.0, -5.0, -0.4), Vector3(21.0, 5.0, 3.4), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	_hip(15.3, -5.0, 21.0, 5.0, 3.4, 5.4, 1.0)
	for s: float in [-1.0, 1.0]:
		for i in 4:
			var x := lerpf(-10.0, 10.0, float(i) / 3.0)
			# Not beside the porch on the front, where it would be inside it.
			if s > 0.0 and absf(x) < 5.0:
				continue
			window("y" if s > 0.0 else "-y", s * 8.0, x - 1.3, 1.2, 2.6, 2.0, true, DARK_GLASS)
	# The entry: a gabled porch on two posts, which is how every one of these
	# tells you where the door is from the car park. Its roof begins past the
	# main eave, which hangs over the first 1.3 m of it.
	box(Vector3(-3.0, 8.0, -0.4), Vector3(3.0, 12.0, 3.6), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	_gable(-3.0, 10.0, 3.0, 12.0, 3.6, 5.6, 0.7)
	box(Vector3(-1.3, 12.0, KERB_H), Vector3(1.3, 12.3, 2.4), WOOD_DARK)
	box(Vector3(-4.2, 12.0, -0.4), Vector3(4.2, 14.0, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	_patio_rail(-13.0, -8.0, -3.0, -16.0, true)


## Railed patio ground between (x0,y0) and (x1,y1), with its kerb and rail.
## Pulled out of the restaurants because three of them have one. `on_wall` is
## for one whose edge on the +y side is a building wall, which needs no rail.
func _patio_rail(x0: float, y0: float, x1: float, y1: float, on_wall: bool = false) -> void:
	var a := Vector2(minf(x0, x1), minf(y0, y1))
	var b := Vector2(maxf(x0, x1), maxf(y0, y1))
	box(Vector3(a.x, a.y, -0.4), Vector3(b.x, b.y, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	# A 1.1 m rail. Under cover height on purpose — a patio you can shoot over
	# is a place to be caught in, and that is what a patio should be. The two
	# long runs take the corners, and the short one runs between them.
	var rail_tex := {"top": METAL, "side": METAL, "bottom": METAL}
	box(Vector3(a.x - 0.07, a.y - 0.07, KERB_H), Vector3(b.x + 0.07, a.y + 0.07, KERB_H + 1.1), rail_tex)
	var y_end := b.y - 0.07
	if not on_wall:
		box(Vector3(a.x - 0.07, b.y - 0.07, KERB_H), Vector3(b.x + 0.07, b.y + 0.07, KERB_H + 1.1), rail_tex)
	else:
		y_end = b.y
	box(Vector3(a.x - 0.07, a.y + 0.07, KERB_H), Vector3(a.x + 0.07, y_end, KERB_H + 1.1), rail_tex)


## UPSCALE: a steakhouse. Stone to the sill, tall windows, a flat parapet
## instead of a hip, and a porte-cochere over the drop-off — which is the one
## building type on a site like this with a drive-under canopy away from a
## fuel pump.
func _restaurant_upscale() -> void:
	box(Vector3(-15.0, -9.0, -0.4), Vector3(15.0, 9.0, 6.2), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	_ring(-15.0, -9.0, 15.0, 9.0, 0.3, 0.0, -0.4, 2.0, RETAIL_BRICK)
	_parapet_ring(-15.0, -9.0, 15.0, 9.0, 6.2, 1.4, {}, 0.5)
	for i in 5:
		var x := lerpf(-12.0, 12.0, float(i) / 4.0)
		for s: float in [-1.0, 1.0]:
			var h := 3.0
			if s > 0.0:
				# The door is in this one.
				if i == 2:
					continue
				# Under the porte-cochere roof the window is a little shorter, so its
				# lintel stops under the roof and not in it.
				if absf(x - 1.6) - 1.725 < 9.0:
					h = 2.1
			window("y" if s > 0.0 else "-y", s * 9.0, x - 1.6, 2.2, 3.2, h, true, DARK_GLASS)
	# The door stands on the pad, in front of the brick course.
	_shopfront(-4.0, 4.0, 9.3, 4.2, 0.5, KERB_H)
	# The porte-cochere: 4.6 m clear on four columns, with the drive under it.
	box(Vector3(-9.0, 9.0, 4.6), Vector3(9.0, 20.0, 5.6), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": METAL})
	for sx: float in [-1.0, 1.0]:
		for sy: float in [0.0, 1.0]:
			cylinder(Vector3(sx * 7.6, 11.0 + sy * 7.6, -0.1), 0.55, 4.7, 8, {"top": METAL, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(-9.0, 9.3, -0.4), Vector3(9.0, 20.0, -0.1), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-4.0, 9.3, -0.1), Vector3(4.0, 11.0, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})


## FAST CASUAL: the small one, 16 x 11, flat roof, glass on two sides and a
## tall sign parapet. These come in twos and threes sharing a lot.
func _restaurant_fast() -> void:
	box(Vector3(-8.0, -5.5, -0.4), Vector3(8.0, 5.5, 4.0), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	_ring(-8.0, -5.5, 8.0, 5.5, 0.2, 0.0, -0.4, 1.1, RETAIL_BRICK)
	_parapet_ring(-8.0, -5.5, 8.0, 5.5, 4.0, 1.4, {"+y": [[-5.0, 5.0]]}, 0.4)
	box(Vector3(-5.0, 5.4, 4.0), Vector3(5.0, 6.1, 7.0), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-4.2, 6.1, 4.6), Vector3(4.2, 6.2, 6.5), SIGN_BAND)
	# The door stands in front of the brick course, on the walk.
	_shopfront(-6.5, 6.5, 5.7, 3.2, 0.5, KERB_H)
	box(Vector3(-8.2, -4.5, 1.3), Vector3(-8.0, 4.0, 3.4), STORE_GLASS)
	box(Vector3(-9.5, 5.5, 3.2), Vector3(9.5, 9.0, 3.7), {"top": GRATING, "side": METAL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		post(s * 8.4, 8.4, KERB_H, 3.2, 0.2)
	box(Vector3(-9.5, 5.7, -0.4), Vector3(9.5, 9.2, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})


## A patio on its own, for putting beside any of them: railed, with tables
## and umbrellas. The tables are mesh only — a map where a squad has to pick
## its way round forty bistro chairs is not a better map.
func _patio() -> void:
	_patio_rail(-9.0, -6.0, 9.0, 6.0)
	no_collision()
	for i in 3:
		for j in 2:
			var x := lerpf(-6.0, 6.0, float(i) / 2.0)
			var y := lerpf(-3.2, 3.2, float(j))
			cylinder(Vector3(x, y, KERB_H), 0.75, 0.74, 8, {"top": WOOD, "side": METAL, "bottom": METAL})
			cylinder(Vector3(x, y, KERB_H + 0.74), 0.06, 1.5, 6, METAL)
			cylinder(Vector3(x, y, KERB_H + 2.24), 1.9, 0.3, 8, SIGN_BAND, 0.3)


## A BANK OUTLOT with three drive-up lanes under a canopy. The lanes make it
## the one small building on a frontage with a covered drive-through a body
## can fight along, and the canopy is 4 m clear so it is roof and not ceiling.
func _bank_outlot() -> void:
	box(Vector3(-10.0, -7.0, -0.4), Vector3(10.0, 7.0, 4.6), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	_ring(-10.0, -7.0, 10.0, 7.0, 0.2, 0.0, -0.4, 1.3, RETAIL_BRICK)
	# The cornice is open over the sign and over the drive-up canopy's roof,
	# which meets the wall on that side.
	_parapet_ring(-10.0, -7.0, 10.0, 7.0, 4.6, 1.6, {"+y": [[-6.0, 6.0]], "+x": [[-7.5, 5.0]], "-y": [[10.0, 10.5]]}, 0.5)
	box(Vector3(-6.0, 6.9, 4.6), Vector3(6.0, 7.6, 6.0), SIGN_BAND)
	# The door stands in front of the brick course.
	_shopfront(-7.0, 7.0, 7.2, 3.6)
	# The drive-up: canopy over three lanes, with the island teller between.
	box(Vector3(10.0, -8.0, 4.0), Vector3(24.0, 5.0, 4.8), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	for sy: float in [-1.0, 1.0]:
		cylinder(Vector3(21.5, sy * 5.5, -0.1), 0.45, 4.1, 8, {"top": METAL, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(10.2, -8.0, -0.4), Vector3(24.0, 6.0, -0.1), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for i in 2:
		var y := -4.6 + i * 3.4
		box(Vector3(12.0, y - 0.7, -0.1), Vector3(20.0, y + 0.7, KERB_H), ISLAND)
		box(Vector3(14.0, y - 0.5, KERB_H), Vector3(15.6, y + 0.5, 1.9), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	box(Vector3(10.2, 1.0, 1.0), Vector3(10.6, 3.4, 2.4), DARK_GLASS)
