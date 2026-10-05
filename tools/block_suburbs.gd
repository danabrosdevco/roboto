extends "res://tools/block_suburban.gd"

# ─────────────────────────────────────────────
# BLOCK SUBURBS — everything on a suburban map that is not the mall and not
# the road: the houses behind it, the pads and civic buildings along the
# frontage, and the landscape the whole development sits in.
#
#   maps/blocks/suburbs/suburb_*.map
#
#   godot --headless --path . --script res://tools/block_suburbs.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_suburbs.gd -- maps/blocks --force [piece names]
#
# Built on block_suburban.gd: the same brush kit, retail textures and
# no-overwrite rule. Build prefabs with block_prefabs.gd.
#
# WHAT THESE ARE FOR, AS GROUND. The retail pieces give a map one enormous
# open car park ringed by blank walls. On their own that is one fight repeated
# at different ranges. These are the other half: the housing behind the mall
# is a warren of head-high fences and 6 m gaps, the pads along the frontage
# are isolated buildings with open ground between them, and the pond and the
# berms are the only terrain features on an otherwise flat site.
#
# THE HOUSE PIECES ARE SOLID. A body cannot get inside any of them, and that
# is deliberate: a suburban map is won and lost in the gaps between buildings,
# an interior costs five times the brushes of the shell around it, and a house
# the squad can enter needs a door the navmesh agrees is a door. The pieces
# that ARE meant to be fought through — the storage rows, the motel walkway,
# the dealership — are open by design and say so.
#
# Heights follow block_suburban's rules: every kerb 0.15, every wall meant as
# cover at least 1.25, nothing between 0.2 and 0.5.
# ─────────────────────────────────────────────

const SIDING := "PSX_Textures/wood_wall_1"
const SHINGLE := "PSX_Textures/roofing_1"
const STUCCO := "PSX_Textures/plaster_1"
const HOUSE := {"top": SHINGLE, "side": SIDING, "bottom": CONCRETE}
const RENDERED := {"top": SHINGLE, "side": STUCCO, "bottom": CONCRETE}

const SUBURBS := {
	# Housing
	"suburb_house_ranch": "_house_ranch",
	"suburb_house_two_story": "_house_two_story",
	"suburb_house_split": "_house_split",
	"suburb_garage_detached": "_garage_detached",
	"suburb_townhouse_row": "_townhouse_row",
	"suburb_garden_apartment": "_garden_apartment",
	# Along the frontage
	"suburb_motel_strip": "_motel_strip",
	"suburb_office_lowrise": "_office_lowrise",
	"suburb_self_storage": "_self_storage",
	"suburb_car_dealership": "_car_dealership",
	"suburb_pad_single": "_pad_single",
	"suburb_church": "_church",
	"suburb_school_wing": "_school_wing",
	"suburb_fire_station": "_fire_station",
	# Landscape and edges
	"suburb_retention_pond": "_retention_pond",
	"suburb_berm_landscape": "_berm_landscape",
	"suburb_fence_privacy": "_fence_privacy",
	"suburb_hedge_row": "_hedge_row",
	"suburb_billboard": "_billboard",
	"suburb_bus_shelter": "_bus_shelter",
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
		print("usage: godot --headless --path . --script res://tools/block_suburbs.gd -- maps/blocks [--force] [piece names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("suburbs")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in SUBURBS:
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
		call(SUBURBS[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-30s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
		# Brushes may touch but never share volume — it z-fights, ghosts included.
		var shared := brush_overlaps()
		if not shared.is_empty():
			print("      !! %s: %d overlapping brush pair(s)" % [name, shared.size()])
	print("BLOCK SUBURBS DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── Shared parts ─────────────────────────────────────────────────────────────

## Brushes may touch but never share volume: a face sunk into a face z-fights,
## and that goes for the mesh-only ghosts as much as for the solid ones. So
## everything here that "stands proud" starts AT the plane of the mass it is
## on, and anything that would have crossed a mass is cut into pieces round it.

## A plinth round the foot of a building: four strips OUTSIDE the walls, never
## a slab under them. `gaps` cuts a strip where something else stands on that
## side (a door, a drive, a garage), keyed by the strip's side as in parapet().
func _plinth_ring(x0: float, y0: float, x1: float, y1: float, out: float, z0: float, z1: float, tex: Variant, gaps: Dictionary = {}) -> void:
	wall_run("y", Vector2(y0 - out, y0), x0 - out, x1 + out, z0, z1, gaps.get("-y", []), tex)
	wall_run("y", Vector2(y1, y1 + out), x0 - out, x1 + out, z0, z1, gaps.get("+y", []), tex)
	wall_run("x", Vector2(x0 - out, x0), y0, y1, z0, z1, gaps.get("-x", []), tex)
	wall_run("x", Vector2(x1, x1 + out), y0, y1, z0, z1, gaps.get("+x", []), tex)


## fence_run, but with the rails running BETWEEN the posts. block_industrial's
## passes each rail through every post it crosses, which is a shared volume per
## post per rail. Axis-aligned runs only, which is all this file has.
func _fence_clean(a: Vector2, b: Vector2, z0: float = -0.2, h: float = 2.2) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / 2.5)))
	var post_w := 0.08
	var rail_w := 0.05
	var dir := (b - a).normalized()
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		post(p.x, p.y, z0, z0 + h + 0.1, post_w, METAL)
	for z: float in [z0 + 1.0, z0 + h]:
		for i in n:
			var p := a.lerp(b, float(i) / n) + dir * post_w * 0.5
			var q := a.lerp(b, float(i + 1) / n) - dir * post_w * 0.5
			beam(Vector3(p.x, p.y, z), Vector3(q.x, q.y, z), rail_w, METAL)


## A gabled roof over a rectangle, ridge running along x. One solid, so it is
## one collision hull and one mesh — a roof built as two sloped slabs is two
## of each and looks identical from the ground.
func _gable(x0: float, y0: float, x1: float, y1: float, eaves: float, ridge: float, over: float = 0.45) -> void:
	solid([Vector3(x0 - over, y0 - over, eaves), Vector3(x1 + over, y0 - over, eaves),
			Vector3(x1 + over, y1 + over, eaves), Vector3(x0 - over, y1 + over, eaves),
			Vector3(x0 - over, (y0 + y1) * 0.5, ridge), Vector3(x1 + over, (y0 + y1) * 0.5, ridge)], SHINGLE)


## A hipped roof: the same but pulled in at both ends as well, which is what
## most of these actually have and reads differently on a skyline.
func _hip(x0: float, y0: float, x1: float, y1: float, eaves: float, ridge: float, over: float = 0.45) -> void:
	var inset: float = minf((y1 - y0) * 0.5, (x1 - x0) * 0.3)
	solid([Vector3(x0 - over, y0 - over, eaves), Vector3(x1 + over, y0 - over, eaves),
			Vector3(x1 + over, y1 + over, eaves), Vector3(x0 - over, y1 + over, eaves),
			Vector3(x0 + inset, (y0 + y1) * 0.5, ridge), Vector3(x1 - inset, (y0 + y1) * 0.5, ridge)], SHINGLE)


## A driveway apron from a building out to y1.
##
## ITS TOP IS AT 0, AND THE GROUND IS 0.06 M BELOW THAT. An apron flush with
## the ground is two horizontal faces at one height over the same ground —
## the fault that made 15% of Polaris crawl, and one no brush check can see,
## because the apron and the ground are different .map files that barely share
## any volume. The clearance is made by sinking the GROUND TILE, not by
## raising this: lifting the apron pushed it up into the shutters, kerbs and
## walls standing on it, 32 overlapping pairs in the self-storage yard alone.
func _drive(x0: float, x1: float, y0: float, y1: float) -> void:
	box(Vector3(x0, y0, -0.3), Vector3(x1, y1, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})


## A run of head-high close-boarded fence along x. SOLID, not a picket: a
## fence a body can see and shoot through is not an obstacle and not cover,
## and the whole reason the housing behind a mall is good ground is that its
## fences are neither.
func _privacy_run(x0: float, x1: float, y: float, h: float = 1.9) -> void:
	# The boards run between the posts, not through them: a board through a
	# post is a shared volume per post.
	var cursor := x0
	var x := x0
	while x <= x1 + 0.01:
		if x - 0.09 > cursor + 0.01:
			box(Vector3(cursor, y - 0.07, -0.3), Vector3(x - 0.09, y + 0.07, h), {"top": WOOD, "side": WOOD, "bottom": WOOD})
		box(Vector3(x - 0.09, y - 0.12, -0.3), Vector3(x + 0.09, y + 0.12, h + 0.1), WOOD_DARK)
		cursor = maxf(cursor, x + 0.09)
		x += 2.4
	if x1 > cursor + 0.01:
		box(Vector3(cursor, y - 0.07, -0.3), Vector3(x1, y + 0.07, h), {"top": WOOD, "side": WOOD, "bottom": WOOD})


# ── Housing ──────────────────────────────────────────────────────────────────

## THE RANCH: single storey, hipped, 16 x 9, with an attached garage and a
## drive. The default house, and at 4.6 m to the ridge the thing that sets the
## scale of a whole street.
func _house_ranch() -> void:
	box(Vector3(-8.0, -4.5, -0.4), Vector3(8.0, 4.5, 2.7), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	# The plinth is a ring round the walls, cut where the door and the garage
	# stand, and not a slab under the house.
	_plinth_ring(-8.0, -4.5, 8.0, 4.5, 0.2, -0.4, 0.35, {"top": WALK, "side": RETAIL_BRICK, "bottom": CONCRETE},
			{"+y": [[-0.5, 0.5], [4.0, 8.2]]})
	_hip(-8.0, -4.5, 8.0, 4.5, 2.7, 4.6)
	# The garage end, pushed forward, which is the one thing that makes one of
	# these different from the next.
	box(Vector3(4.0, 4.5, -0.4), Vector3(8.0, 9.5, 2.7), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	# Its roof starts where the main roof's eave ends (4.95), so the two hips
	# meet along an edge instead of one running through the other.
	_hip(4.0, 5.4, 8.0, 9.5, 2.7, 4.2)
	box(Vector3(4.6, 9.5, 0.0), Vector3(7.4, 9.7, 2.2), SHUTTER)
	_drive(4.2, 7.8, 9.5, 16.0)
	window("-y", -4.5, -5.0, 1.0, 1.8, 1.2)
	window("-y", -4.5, 0.5, 1.0, 1.8, 1.2)
	window("y", 4.5, -3.0, 1.0, 1.4, 1.2)
	box(Vector3(-0.5, 4.5, -0.3), Vector3(0.5, 4.7, 2.1), WOOD_DARK)
	# The stoop. 0.15, like every other step in this kit.
	box(Vector3(-1.4, 4.7, -0.4), Vector3(1.4, 6.1, KERB_H), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})


## TWO STOREY, gabled, 12 x 9 and 7.4 m to the ridge, with a garage and a
## porch. Taller than the ranch, so a street of both has a skyline.
func _house_two_story() -> void:
	box(Vector3(-6.0, -4.5, -0.4), Vector3(6.0, 4.5, 5.6), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	_plinth_ring(-6.0, -4.5, 6.0, 4.5, 0.2, -0.4, 0.35, {"top": WALK, "side": RETAIL_BRICK, "bottom": CONCRETE},
			{"+x": [[-1.0, 4.5]], "+y": [[-4.2, 0.6]]})
	_gable(-6.0, -4.5, 6.0, 4.5, 5.6, 7.4)
	box(Vector3(6.0, -1.0, -0.4), Vector3(12.0, 4.5, 2.9), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	# Pulled in by the overhang on the side that meets the house, so the garage
	# roof does not eave into the wall above it.
	_hip(6.45, -1.0, 12.0, 4.5, 2.9, 4.4)
	box(Vector3(7.0, 4.5, 0.0), Vector3(11.0, 4.7, 2.3), SHUTTER)
	_drive(6.8, 11.2, 4.5, 12.0)
	for z: float in [1.0, 3.8]:
		window("y", 4.5, -4.4, z, 1.3, 1.3)
		window("y", 4.5, 1.6, z, 1.3, 1.3)
		window("-y", -4.5, -4.0, z, 1.3, 1.3)
		window("-y", -4.5, 2.0, z, 1.3, 1.3)
	# The porch: a roof on two posts over the door, which is a thing to shoot
	# from behind and the only relief on the front wall.
	box(Vector3(-2.6, 4.5, KERB_H), Vector3(-1.6, 4.7, 2.1), WOOD_DARK)
	box(Vector3(-4.0, 4.5, 2.6), Vector3(0.4, 7.2, 2.9), SHINGLE)
	for x: float in [-3.6, 0.0]:
		post(x, 6.9, KERB_H, 2.6, 0.18, WOOD)
	box(Vector3(-4.2, 4.5, -0.4), Vector3(0.6, 7.3, KERB_H), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})


## A SPLIT LEVEL: half the house a storey higher than the other, which is the
## one suburban house shape that gives a map a roof at two heights in one
## footprint.
func _house_split() -> void:
	box(Vector3(-9.0, -4.5, -0.4), Vector3(0.0, 4.5, 5.4), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	_gable(-9.0, -4.5, 0.0, 4.5, 5.4, 7.0)
	box(Vector3(0.0, -4.5, -0.4), Vector3(8.0, 4.5, 3.1), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# Starts at the join, past the gable's overhang, so the low roof does not
	# run into the high wall.
	_hip(0.45, -4.5, 8.0, 4.5, 3.1, 4.7)
	_plinth_ring(-9.0, -4.5, 8.0, 4.5, 0.2, -0.4, 0.35, {"top": WALK, "side": RETAIL_BRICK, "bottom": CONCRETE},
			{"+y": [[-1.4, -0.4], [2.0, 6.4]]})
	window("y", 4.5, -7.5, 3.6, 1.6, 1.2)
	window("y", 4.5, -4.0, 1.0, 1.6, 1.2)
	window("y", 4.5, 2.0, 1.2, 2.2, 1.3)
	box(Vector3(-1.4, 4.5, -0.3), Vector3(-0.4, 4.7, 2.1), WOOD_DARK)
	box(Vector3(-2.2, 4.7, -0.4), Vector3(0.4, 6.4, KERB_H), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})
	_drive(2.0, 6.4, 4.5, 12.0)


## A detached double garage on its slab. Small, blank and square: the piece
## that fills the back of a lot and gives a yard a hard edge.
func _garage_detached() -> void:
	box(Vector3(-3.6, -3.2, -0.4), Vector3(3.6, 3.2, 2.6), {"top": CONCRETE, "side": SIDING, "bottom": CONCRETE})
	_gable(-3.6, -3.2, 3.6, 3.2, 2.6, 3.9)
	box(Vector3(-2.8, 3.2, 0.0), Vector3(2.8, 3.4, 2.1), SHUTTER)
	_drive(-3.0, 3.0, 3.2, 9.0)


## A ROW OF FOUR TOWNHOUSES, 26 m long, three storeys, each with its own stoop
## and a dogleg in the plan so the row is not one flat wall. Behind a mall
## these line a through road and make it a corridor.
func _townhouse_row() -> void:
	var w := 6.5
	for i in 4:
		var x0 := -13.0 + i * w
		var step: float = 0.0 if i % 2 == 0 else 0.9
		# Each house stops 0.2 m short of its party walls; the walls stand in
		# that gap instead of through the houses either side of them.
		var xa := x0 + 0.2
		var xb := x0 + w - 0.2 if i < 3 else x0 + w
		box(Vector3(xa, -5.0 + step, -0.4), Vector3(xb, 5.0 + step, 8.2), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
		box(Vector3(xa, -5.25 + step, 8.2), Vector3(xb, 5.25 + step, 9.0), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
		# The party wall standing proud, which is how you read four houses
		# instead of one building.
		box(Vector3(x0 - 0.2, -5.2 + step, -0.4), Vector3(x0 + 0.2, 5.2 + step, 9.3), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
		for z: float in [1.1, 4.0, 6.5]:
			window("y", 5.0 + step, x0 + 1.2, z, 1.5, 1.4)
			window("y", 5.0 + step, x0 + 4.8, z, 1.5, 1.4)
		box(Vector3(x0 + 2.6, 5.0 + step, -0.3), Vector3(x0 + 3.7, 5.2 + step, 2.2), WOOD_DARK)
		box(Vector3(x0 + 2.2, 5.2 + step, -0.4), Vector3(x0 + 4.1, 6.8 + step, KERB_H), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(13.0, -5.2, -0.4), Vector3(13.2, 4.8, 9.3), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})


## A GARDEN APARTMENT BLOCK: three storeys round an open stair, with the
## access galleries OUTSIDE the building. The galleries are the point — they
## are a walkable ledge at 3 and 6 m that a squad can be on and shot at from,
## which no other housing piece in here has.
func _garden_apartment() -> void:
	var w := 18.0
	var d := 8.0
	box(Vector3(-w, -d, -0.4), Vector3(w, d, 9.0), {"top": CONCRETE, "side": RENDERED["side"], "bottom": CONCRETE})
	box(Vector3(-w - 0.3, -d - 0.3, 9.0), Vector3(w + 0.3, d + 0.3, 9.8), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	for lvl in 2:
		var z: float = 3.0 + lvl * 3.0
		box(Vector3(-w, d, z - 0.3), Vector3(w, d + 2.2, z), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})
		# The gallery's own balustrade, at cover height because a 1.0 m rail
		# on a 3 m ledge is a thing bodies fall over.
		box(Vector3(-w, d + 2.0, z), Vector3(w, d + 2.2, z + COVER_H), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
		for i in 7:
			var x := lerpf(-w + 2.0, w - 2.0, float(i) / 6.0)
			post(x, d + 2.1, z + COVER_H, z + COVER_H + 0.05, 0.2, CONCRETE)
	for i in 3:
		for lvl in 3:
			var x := lerpf(-w + 3.0, w - 3.0, float(i) / 2.0)
			window("y", d, x - 0.9, 0.9 + lvl * 3.0, 1.8, 1.5)
			window("-y", -d, x - 0.9, 0.9 + lvl * 3.0, 1.8, 1.5)
	# The open stair at one end: a flight to each gallery. The only way up,
	# so the galleries are a route with two ends and not a shelf. The upper
	# flight is a sloped slab 3 m thick, which is exactly the rise between the
	# two, so it rests ON the lower one along their shared slope instead of
	# being a second solid ramp built through it.
	ramp(w - 5.0, d + 2.2, w, d + 7.0, -0.4, 0.0, 2.7, "+x", STAIR)
	flight(w - 5.0, d + 2.2, w, d + 7.0, 3.0, 5.7, "+x", 3.0, STAIR)
	box(Vector3(w - 5.2, d + 7.0, -0.4), Vector3(w + 0.2, d + 7.2, 9.0), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})


# ── Along the frontage ───────────────────────────────────────────────────────

## A TWO-STOREY MOTEL, 52 m of rooms with the walkway and stair outside and
## the office on the end. Like the apartment, the value is the 3 m gallery —
## but this one is open at both ends and faces the car park, which makes it
## the best firing position on a frontage.
func _motel_strip() -> void:
	var half := 26.0
	box(Vector3(-half, -6.0, -0.4), Vector3(half, 2.0, 6.2), {"top": CONCRETE, "side": RENDERED["side"], "bottom": CONCRETE})
	box(Vector3(-half - 0.3, -6.3, 6.2), Vector3(half + 0.3, 2.3, 7.0), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(-half, 2.0, 2.8), Vector3(half, 4.4, 3.1), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-half, 4.2, 3.1), Vector3(half, 4.4, 3.1 + COVER_H), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	# The posts under the walkway, which also hold the roof over the ground
	# floor doors. 2.6 m clear beneath.
	var x := -half + 2.0
	while x <= half - 2.0:
		post(x, 4.2, -0.4, 2.8, 0.2)
		x += 4.0
	for i in 13:
		var dx := lerpf(-half + 2.0, half - 2.0, float(i) / 12.0)
		# Doors on the wall plane, standing proud. The upper one starts on the
		# walkway, which is what it opens onto.
		box(Vector3(dx - 0.5, 2.0, -0.3), Vector3(dx + 0.5, 2.2, 2.1), WOOD_DARK)
		box(Vector3(dx - 0.5, 2.0, 3.1), Vector3(dx + 0.5, 2.2, 5.2), WOOD_DARK)
		# Beside the door and not across it: a window at dx + 0.8 was half
		# inside the door it sat next to.
		window("y", 2.0, dx + 1.6, 1.0, 1.1, 1.2)
		window("y", 2.0, dx + 1.6, 4.0, 1.1, 1.2)
	for s: float in [-1.0, 1.0]:
		ramp(s * (half - 4.0), 4.4, s * half, 9.0, -0.4, 0.0, 3.1, "+x" if s > 0.0 else "-x",
				STAIR)
	# The office, pushed out at one end with its own low roof and sign.
	box(Vector3(-half - 9.0, -6.0, -0.4), Vector3(-half, 3.0, 3.6), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# Stops at the motel's wall: carried on to -half + 0.3 it was inside it.
	box(Vector3(-half - 9.3, -6.3, 3.6), Vector3(-half, 3.3, 4.4), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	_shopfront(-half - 8.0, -half - 1.0, 3.0, 2.8)


## A SUBURBAN OFFICE BOX: three storeys of ribbon glazing on a brick base,
## 34 x 20. The only building on a map like this with a glass wall big enough
## to matter, which makes it both a landmark and somewhere a fight looks good.
func _office_lowrise() -> void:
	var w := 17.0
	var d := 10.0
	box(Vector3(-w, -d, -0.4), Vector3(w, d, 10.2), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	# The brick base is a ring round the walls, not a slab under them.
	_plinth_ring(-w, -d, w, d, 0.25, -0.4, 1.4, RETAIL_BRICK, {"+y": [[-6.5, 6.5]]})
	box(Vector3(-w - 0.4, -d - 0.4, 10.2), Vector3(w + 0.4, d + 0.4, 11.4), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# Three ribbons of glass, each standing 0.2 m off the wall so it reads as a
	# band and not as a sticker. Proud, not recessed: a recess is a hole in the
	# wall, and the wall is one solid.
	for lvl in 3:
		var z: float = 1.6 + lvl * 3.0
		for s: float in [-1.0, 1.0]:
			# The ground-floor ribbon on the entrance face stops either side of
			# the shopfront and its canopy, which stand where it would run.
			if s > 0.0 and lvl == 0:
				box(Vector3(-w + 0.8, d, z), Vector3(-6.5, d + 0.2, z + 1.9), DARK_GLASS)
				box(Vector3(6.5, d, z), Vector3(w - 0.8, d + 0.2, z + 1.9), DARK_GLASS)
			else:
				box(Vector3(-w + 0.8, s * d, z), Vector3(w - 0.8, s * d + s * 0.2, z + 1.9), DARK_GLASS)
			box(Vector3(s * w, -d + 0.8, z), Vector3(s * w + s * 0.2, d - 0.8, z + 1.9), DARK_GLASS)
		for i in 11:
			var x := lerpf(-w + 0.8, w - 0.8, float(i) / 10.0)
			# The mullions stand on the glass, not through it.
			for s: float in [-1.0, 1.0]:
				if s > 0.0 and lvl == 0 and absf(x) < 6.6:
					continue
				box(Vector3(x - 0.09, s * d + s * 0.2, z), Vector3(x + 0.09, s * d + s * 0.28, z + 1.9), METAL)
	# The entrance runs to the canopy's soffit: any higher and the shopfront is
	# inside the canopy slab.
	_shopfront(-5.0, 5.0, d, 3.2)
	box(Vector3(-6.5, d, 3.2), Vector3(6.5, d + 3.4, 3.7), {"top": GRATING, "side": METAL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		post(s * 5.6, d + 2.8, -0.4, 3.2, 0.3)
	# On the cornice slab's top, which is the roof the plant actually stands on.
	_rooftop_plant(-w + 4.0, -d + 4.0, w - 4.0, d - 4.0, 11.4, 77)


## SELF STORAGE: two facing rows of roller doors with a drive between them.
## The best infantry ground in this whole kit — a 9 m lane with forty doors
## and no cover but the corners, and both ends open.
func _self_storage() -> void:
	for s: float in [-1.0, 1.0]:
		box(Vector3(-24.0, s * 4.5, -0.4), Vector3(24.0, s * 11.5, 3.3), {"top": METAL, "side": RUST_PANEL, "bottom": CONCRETE})
		box(Vector3(-24.2, s * 4.3, 3.3), Vector3(24.2, s * 11.5, 3.7), {"top": RUST_PANEL, "side": METAL, "bottom": METAL})
		# The kerb on the lane side of the wall: it was inside the wall, and
		# the lane below now stops where it starts.
		box(Vector3(-24.0, s * 4.3, -0.4), Vector3(24.0, s * 4.5, 0.0), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
		for i in 16:
			var x := lerpf(-23.0, 23.0, float(i) / 15.0)
			# Doors stand proud of the wall into the lane, above the kerb.
			box(Vector3(x - 1.2, s * 4.3, 0.0), Vector3(x + 1.2, s * 4.5, 2.5), SHUTTER)
			box(Vector3(x - 1.35, s * 4.25, 2.5), Vector3(x + 1.35, s * 4.5, 2.75), METAL)
	box(Vector3(-24.0, -4.3, -0.3), Vector3(24.0, 4.3, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})


## A CAR DEALERSHIP: a glass showroom, the service bays beside it, and the
## display lot out front on its own raised pad. The pad is the detail that
## matters — it puts the display row 0.15 m up with a kerb, so the frontage
## reads as a dealership and not as more car park.
func _car_dealership() -> void:
	box(Vector3(-11.0, -9.0, -0.4), Vector3(4.0, 9.0, 7.0), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	box(Vector3(-11.3, -9.3, 7.0), Vector3(4.3, 9.3, 8.2), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# The showroom corner: glass up two storeys on both faces, standing on the
	# walls rather than sunk into them.
	box(Vector3(-11.0, 9.0, -0.4), Vector3(2.0, 9.4, 6.6), STORE_GLASS)
	box(Vector3(-11.4, -9.0, -0.4), Vector3(-11.0, 9.0, 6.6), STORE_GLASS)
	for i in 7:
		var x := lerpf(-10.6, 1.6, float(i) / 6.0)
		box(Vector3(x - 0.1, 9.4, -0.4), Vector3(x + 0.1, 9.5, 6.7), METAL)
	# Service: four bays with roller doors round the side, open to a yard.
	box(Vector3(4.0, -9.0, -0.4), Vector3(22.0, 2.0, 5.2), {"top": METAL, "side": RUST_PANEL, "bottom": CONCRETE})
	# From the showroom's wall, not through it.
	box(Vector3(4.0, -9.2, 5.2), Vector3(22.2, 2.2, 5.6), {"top": RUST_PANEL, "side": METAL, "bottom": METAL})
	for i in 4:
		var x := lerpf(6.5, 19.5, float(i) / 3.0)
		box(Vector3(x - 1.9, 2.0, -0.3), Vector3(x + 1.9, 2.2, 4.2), SHUTTER)
	# The display pad out front.
	box(Vector3(-13.0, 10.0, -0.4), Vector3(14.0, 18.0, KERB_H), {"top": ASPHALT, "side": KERB, "bottom": CONCRETE})
	_bays(-11.0, 12.0, 11.0, 17.0, 3.2, KERB_H)
	for i in 3:
		var x := lerpf(-9.0, 11.0, float(i) / 2.0)
		box(Vector3(x - 0.14, 18.0, KERB_H), Vector3(x + 0.14, 18.3, 6.5), METAL)
		# The sign plate on the post's face, not through it.
		box(Vector3(x - 1.4, 18.3, 4.6), Vector3(x + 1.4, 18.8, 6.3), SIGN_BAND)


## A SINGLE-TENANT PAD: the little building on its own island at the front of
## a lot — a bank, a pharmacy, a coffee place. 18 x 12, glazed on two sides,
## with a drive-up lane and its canopy.
func _pad_single() -> void:
	box(Vector3(-9.0, -6.0, -0.4), Vector3(9.0, 6.0, 4.8), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	# A ring on the ground, round the walls and off the drive-up lane.
	_plinth_ring(-9.0, -6.0, 9.0, 6.0, 0.2, 0.0, 1.2, RETAIL_BRICK, {"+y": [[-7.0, 7.0]], "+x": [[-6.0, 5.0]]})
	box(Vector3(-9.5, -6.5, 4.8), Vector3(9.5, 6.5, 6.4), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	# On the cornice's face, not in it.
	box(Vector3(-6.0, 6.5, 4.8), Vector3(6.0, 6.7, 6.2), SIGN_BAND)
	_shopfront(-7.0, 7.0, 6.0, 3.6)
	box(Vector3(-9.2, -5.8, 1.4), Vector3(-9.0, 4.0, 3.8), STORE_GLASS)
	# The drive-up: a canopy on one column over two lanes, 4.2 m clear.
	box(Vector3(9.0, -5.0, 4.2), Vector3(18.0, 3.0, 4.8), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	box(Vector3(16.4, -1.4, 0.0), Vector3(17.4, -0.4, 4.2), {"top": METAL, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(9.4, -3.0, 0.0), Vector3(11.2, 1.4, 1.3), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	_drive(9.0, 18.0, -8.0, 5.0)


## A suburban church: a wide low hall with a gable, a brick porch and a spire
## on the corner. 19 m to the top of the spire — the only thing on a housing
## map that stands above the roofs, so it is the landmark the whole district
## is read against.
func _church() -> void:
	box(Vector3(-11.0, -8.0, -0.4), Vector3(11.0, 8.0, 5.6), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# No overhang on the porch side: the tower and the porch stand against
	# that wall, and an eave there would run through both.
	_gable(-11.0, -8.0, 11.0, 7.4, 5.6, 9.4, 0.6)
	box(Vector3(-4.0, 8.0, -0.4), Vector3(4.0, 11.5, 4.2), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# Starts where the hall's wall does, so its roof meets the hall instead of
	# running into it.
	_gable(-4.0, 8.5, 4.0, 11.5, 4.2, 6.2, 0.5)
	box(Vector3(-1.3, 11.5, 0.0), Vector3(1.3, 11.7, 3.0), WOOD_DARK)
	for s: float in [-1.0, 1.0]:
		for i in 4:
			var x := lerpf(-8.0, 8.0, float(i) / 3.0)
			# The porch and the tower stand on this wall, so the first three
			# windows on the +y side would be inside them.
			if s > 0.0 and i < 3:
				continue
			window("y" if s > 0.0 else "-y", s * 8.0, x - 0.7, 1.6, 1.4, 2.6, true, DARK_GLASS)
	# The tower and spire.
	box(Vector3(-9.5, 8.0, -0.4), Vector3(-5.5, 12.0, 13.0), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(-9.9, 7.6, 13.0), Vector3(-5.1, 12.4, 13.9), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	solid([Vector3(-9.9, 7.6, 13.9), Vector3(-5.1, 7.6, 13.9), Vector3(-5.1, 12.4, 13.9), Vector3(-9.9, 12.4, 13.9),
			Vector3(-7.5, 10.0, 18.4)], SHINGLE)
	box(Vector3(-7.62, 9.88, 18.4), Vector3(-7.38, 10.12, 19.4), METAL)
	# The cross-piece in two arms either side of the finial, not one bar
	# through it.
	box(Vector3(-8.1, 9.94, 18.9), Vector3(-7.62, 10.06, 19.1), METAL)
	box(Vector3(-7.38, 9.94, 18.9), Vector3(-6.9, 10.06, 19.1), METAL)


## A SCHOOL WING: a long two-storey classroom block with a covered walk, and
## the gym on the end. Big flat walls, regular windows, and a canopy a squad
## can move under out of sight from above.
func _school_wing() -> void:
	var half := 30.0
	box(Vector3(-half, -7.0, -0.4), Vector3(half, 7.0, 7.4), {"top": ROOF_MEMBRANE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# Ends at the gym's wall on that side: carried past it, it was in the gym.
	box(Vector3(-half - 0.3, -7.3, 7.4), Vector3(half, 7.3, 8.4), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	for lvl in 2:
		for i in 10:
			var x := lerpf(-half + 3.0, half - 3.0, float(i) / 9.0)
			# The ground-floor windows stop under the covered walk's slab (z 3.0)
			# on the courtyard side, so they are 1.5 m, not 1.7.
			var z0: float = 1.2 if lvl == 0 else 4.8
			var h: float = 1.5 if lvl == 0 else 1.7
			window("y", 7.0, x - 1.2, z0, 2.4, h, true, DARK_GLASS)
			window("-y", -7.0, x - 1.2, z0, 2.4, h, true, DARK_GLASS)
	box(Vector3(-half, 7.0, 3.0), Vector3(half, 10.4, 3.5), {"top": GRATING, "side": METAL, "bottom": METAL})
	var x := -half + 2.0
	while x <= half - 2.0:
		post(x, 10.0, -0.4, 3.0, 0.22)
		x += 5.0
	# The gym: one tall volume, blank, at the end of the wing.
	box(Vector3(half, -11.0, -0.4), Vector3(half + 26.0, 7.0, 10.5), {"top": ROOF_MEMBRANE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(half, -11.3, 10.5), Vector3(half + 26.3, 7.3, 11.6), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(half + 8.0, 7.0, 0.0), Vector3(half + 12.0, 7.2, 2.6), WOOD_DARK)
	# On the cornice slab, which is what the roof of the wing actually is.
	_rooftop_plant(-half + 5.0, -5.0, half - 5.0, 5.0, 8.4, 93)


## A fire station: three bay doors on a tall apron, the hose tower behind.
## The apron is 12 m deep because that is what the appliances need, which
## makes it a wide open approach with nothing on it.
func _fire_station() -> void:
	box(Vector3(-13.0, -9.0, -0.4), Vector3(13.0, 4.0, 6.6), {"top": ROOF_MEMBRANE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# The cornice in two lengths: the hose tower stands on the back wall at
	# x 9..13, and the overhang there would be inside it.
	box(Vector3(-13.3, -9.3, 6.6), Vector3(9.0, 4.3, 7.8), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	box(Vector3(9.0, -9.0, 6.6), Vector3(13.3, 4.3, 7.8), {"top": CONCRETE, "side": EIFS, "bottom": EIFS})
	for i in 3:
		var x := lerpf(-8.5, 8.5, float(i) / 2.0)
		# Doors on the wall plane, above the apron they open onto.
		box(Vector3(x - 3.3, 4.0, 0.0), Vector3(x + 3.3, 4.2, 4.6), SHUTTER)
		box(Vector3(x - 3.6, 4.0, 4.6), Vector3(x + 3.6, 4.3, 4.9), METAL)
	box(Vector3(9.0, -12.0, -0.4), Vector3(13.0, -9.0, 12.0), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(8.7, -12.3, 12.0), Vector3(13.3, -8.7, 12.9), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	_drive(-13.0, 13.0, 4.0, 16.0)
	_bays(-11.0, 11.0, 4.2, 15.8, 5.5, 0.0)


# ── Landscape and edges ──────────────────────────────────────────────────────

## THE DETENTION BASIN. Every one of these developments has one, and on a map
## it is the only hole in otherwise flat ground.
##
## THE SIDES ARE 1 IN 4. That is 14°, well under the 45° the navmesh baker
## walks, so the whole basin bakes and a squad can be ordered into it and out
## of it anywhere on its rim. That is the opposite of the choice made on the
## bridge embankments — and it is deliberate, because a basin a squad cannot
## get out of is a trap that eats a patrol, whereas a bridge flank that walks
## into a river is a route into water. A dry hole you can walk out of is good
## ground; a wet one you cannot is a bug.
##
## BUILT AS GROUND AROUND A HOLE. It used to be a slab with an inverted
## frustum "bowl" sunk in it, which is two solids through each other and, with
## the bowl's top 0.01 above the slab's, a flat surface with no hole in it at
## all. Now it is a floor slab, and four wedges standing on it that run from
## the rim down the 1-in-4 bank to the floor, meeting at the corners on the
## planes the frustum's own edges lie in. Same outer extent, same depth.
func _retention_pond() -> void:
	var rim := 26.0
	var deep := -2.6
	var floor_r := rim - (0.0 - deep) * 4.0
	var rim_y := rim * 0.7
	var floor_y := floor_r * 0.7
	var ground := {"top": DIRT, "side": SPOIL, "bottom": SPOIL}
	box(Vector3(-rim, -rim_y, -4.0), Vector3(rim, rim_y, deep), ground)
	# Each wedge is the rim edge (at z 0 and at the floor's level) and the floor
	# edge it slopes down to. Neighbours share their mitre triangle exactly.
	for s: float in [-1.0, 1.0]:
		solid([Vector3(s * rim, -rim_y, 0.0), Vector3(s * rim, rim_y, 0.0),
				Vector3(s * rim, -rim_y, deep), Vector3(s * rim, rim_y, deep),
				Vector3(s * floor_r, -floor_y, deep), Vector3(s * floor_r, floor_y, deep)], ground)
		solid([Vector3(-rim, s * rim_y, 0.0), Vector3(rim, s * rim_y, 0.0),
				Vector3(-rim, s * rim_y, deep), Vector3(rim, s * rim_y, deep),
				Vector3(-floor_r, s * floor_y, deep), Vector3(floor_r, s * floor_y, deep)], ground)
	# The outfall structure, which is the one hard thing in it and the only
	# cover down there.
	box(Vector3(floor_r - 5.0, -2.0, deep), Vector3(floor_r - 2.0, 2.0, deep + 2.2), CONCRETE)
	box(Vector3(floor_r - 5.3, -2.3, deep + 2.2), Vector3(floor_r - 1.7, 2.3, deep + 2.5), CONCRETE)
	_fence_clean(Vector2(-rim, -rim_y), Vector2(rim, -rim_y), 0.0, 1.4)
	_fence_clean(Vector2(-rim, rim_y), Vector2(rim, rim_y), 0.0, 1.4)


## A LANDSCAPE BERM: the long low mound between a lot and the road, with
## planting on it. 1 in 3 sides — walkable, because it is meant to be fought
## over rather than hidden behind, and 2 m high, so it breaks a sightline
## across a car park without closing it.
func _berm_landscape() -> void:
	var half := 22.0
	var h := 2.0
	solid([Vector3(-half, -7.0, -0.3), Vector3(half, -7.0, -0.3), Vector3(half, 7.0, -0.3), Vector3(-half, 7.0, -0.3),
			Vector3(-half + 3.0, -1.2, h), Vector3(half - 3.0, -1.2, h),
			Vector3(half - 3.0, 1.2, h), Vector3(-half + 3.0, 1.2, h)],
			{"top": DIRT, "side": SPOIL, "bottom": SPOIL})
	no_collision()
	for i in 6:
		var x := lerpf(-half + 4.0, half - 4.0, float(i) / 5.0)
		var y := (_hash_f(i * 19 + 3) - 0.5) * 2.0
		# The trunk runs from the berm's top to the underside of the crown,
		# which is where the heap's lowest ring is (0.3 below its centre).
		cylinder(Vector3(x, y, h), 0.26, 2.25, 6, SPOIL, 0.18)
		heap(Vector3(x, y, h + 2.6), 1.9, 1.9, 2.0, i * 11 + 5, SPOIL)


## 32 m of close-boarded fence, the thing that actually divides a suburb. Head
## high and solid, so it blocks sight and fire and is not cover — a body
## behind one is hidden and not protected, which is a distinction a map made
## of these will teach the player quickly.
func _fence_privacy() -> void:
	_privacy_run(-16.0, 16.0, 0.0)


## A hedge the same height. Mesh only: a run of bushes with collision chops
## the ground beside it into slivers, and the whole point of a hedge on a map
## is that it hides a route rather than closing one.
func _hedge_row() -> void:
	no_collision()
	var x := -15.0
	while x <= 15.0:
		# 0.95 wide, so a bush's base ring (1.04 at the most, snapped) stays
		# inside its 2.2 m pitch and the bushes touch, not interpenetrate.
		heap(Vector3(x, 0.0, -0.2), 0.95, 1.1, 1.8, int(x) * 7 + 11, SPOIL)
		x += 2.2


## A roadside billboard: a hoarding on two columns, 11 m to the top. Lit from
## below, blank on the back, and the one piece of suburban landscape tall
## enough to see over a parked row.
func _billboard() -> void:
	for s: float in [-1.0, 1.0]:
		# The columns stop at the board's underside.
		box(Vector3(s * 3.0 - 0.45, -0.45, -0.6), Vector3(s * 3.0 + 0.45, 0.45, 7.0), {"top": METAL, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-7.5, -0.25, 7.0), Vector3(7.5, 0.25, 11.0), {"top": METAL, "side": SIGN_BAND, "bottom": METAL})
	box(Vector3(-7.8, -0.4, 11.0), Vector3(7.8, 0.4, 11.3), METAL)
	for x: float in [-5.0, 0.0, 5.0]:
		box(Vector3(x - 0.5, 0.25, 6.4), Vector3(x + 0.5, 1.0, 6.8), METAL)
		box(Vector3(x - 0.14, 1.0, 6.4), Vector3(x + 0.14, 1.1, 7.1), METAL)


## A bus shelter on the sidewalk: glass on three sides under a cantilevered
## roof. See-through, so it hides nothing — but it is 2.6 m of hard roof and
## a thing to break a street's length, which is what a shelter is for here.
func _bus_shelter() -> void:
	box(Vector3(-2.2, -0.8, -0.3), Vector3(2.2, 0.8, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	# The back panel runs the full width and the side panels butt it, so the
	# three are one wall of glass and not three that cross at the corners.
	box(Vector3(-2.2, -0.65, KERB_H), Vector3(-2.05, 0.6, 2.3), STORE_GLASS)
	box(Vector3(2.05, -0.65, KERB_H), Vector3(2.2, 0.6, 2.3), STORE_GLASS)
	box(Vector3(-2.2, -0.8, KERB_H), Vector3(2.2, -0.65, 2.3), STORE_GLASS)
	# Front posts only: the back corners are held by the glass.
	for sx: float in [-1.0, 1.0]:
		post(sx * 2.1, 0.7, KERB_H, 2.5, 0.2)
	box(Vector3(-2.5, -1.0, 2.5), Vector3(2.5, 1.4, 2.7), {"top": METAL, "side": METAL, "bottom": SIGN_BAND})
	box(Vector3(-1.9, -0.6, 0.6), Vector3(1.9, -0.25, 0.75), {"top": WOOD, "side": METAL, "bottom": METAL})
	# Outside the roof's edge, and the plate on the pole's face.
	box(Vector3(2.5, 0.6, KERB_H), Vector3(2.66, 0.76, 3.2), METAL)
	box(Vector3(2.5, 0.76, 2.6), Vector3(2.76, 0.96, 3.1), SIGN_BAND)
