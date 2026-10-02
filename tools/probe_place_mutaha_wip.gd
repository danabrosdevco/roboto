extends SceneTree

# ─────────────────────────────────────────────
# PLACE QAMAREEN — writes the node text for the four changes asked for on the
# temporary copy of Mutaha, against the terrain that is ON DISK.
#
#   godot --headless --path . --script res://tools/probe_place_mutaha_wip.gd
#   → scratch/mutaha_wip_nodes.txt, to append to maps/mutaha_wip_level.tscn
#
# It writes a text file and nothing else. It never touches a scene, because
# packing a scene outside the editor writes `= null` for every unset script
# property and flattens instanced sub-scenes.
#
# WHAT IT PLACES
#   BridgeOutSouth   the island's south span is gone; this is the wreckage that
#                    says so, at both abutments and in the channel between.
#   SouthCrossing    the span moved to the new road over the river at z = 316.
#   WestBridgehead   cover on the west bank where the west bridge lands, so
#                    arriving there is a fight and not a walk.
#   IslandSouthWall  a river wall along the spit, so the machines on the south
#                    tip cannot be shot at from the far bank.
#   SouthQuarter     the buildings and street dressing on the 22 new lots.
#
# EVERY PIECE IS CHECKED FOR OVERLAP before it is written: against the pieces
# already placed, against the building lots the generator recorded, against the
# corridor each bridge prefab needs for its deck and ramps, and against the
# water. A rejected piece is reported with what it hit. Two blocks in the same
# volume is the cheapest way to make a level look broken and the easiest thing
# to miss without a display.
# ─────────────────────────────────────────────

const DATA := "res://maps/terrain_data/mutaha_wip_level_terrain.res"
const OUT := "C:/Users/User/AppData/Local/Temp/claude/D--Godot-Games-roboto/adb53eea-3f20-4c1a-a10d-7b2d1903ab73/scratchpad/mutaha_wip_nodes.txt"

## Footprints in metres, x by z, in the piece's own space. Measured off the
## collision shapes by probe_block_size.gd — the docs round them.
const SIZE := {
	"dress_feature_berm": Vector2(15.0, 5.5),
	"dress_feature_container_stack": Vector2(15.7, 5.1),
	"dress_fort_checkpoint": Vector2(22.3, 13.8),
	"dress_fort_dragon_teeth": Vector2(13.3, 3.0),
	"dress_fort_floodlight_mast": Vector2(3.2, 4.5),
	"dress_fort_hesco_sangar": Vector2(10.3, 5.0),
	"dress_fort_hesco_wall": Vector2(12.1, 4.4),
	"dress_fort_razor_wire": Vector2(10.1, 1.0),
	"dress_fort_t_walls": Vector2(7.5, 1.2),
	"dress_industrial_container_yard": Vector2(32.0, 24.0),
	"dress_industrial_parking_lot": Vector2(30.0, 20.0),
	"dress_prop_barrels": Vector2(1.8, 1.8),
	"dress_prop_boulder_b": Vector2(1.4, 2.8),
	"dress_prop_car_wreck": Vector2(4.4, 1.9),
	"dress_prop_concrete_blocks": Vector2(3.8, 3.2),
	"dress_prop_concrete_pipes": Vector2(2.6, 3.3),
	"dress_prop_crates": Vector2(1.8, 2.0),
	"dress_prop_dirt_mound": Vector2(3.5, 4.4),
	"dress_prop_hesco_row": Vector2(4.4, 1.1),
	"dress_prop_jersey_barrier": Vector2(3.0, 0.6),
	"dress_prop_lamp_post": Vector2(0.5, 2.3),
	"dress_prop_power_pole": Vector2(2.2, 0.3),
	"dress_prop_rubble_pile": Vector2(4.9, 4.1),
	"dress_prop_sandbag_nest": Vector2(4.3, 3.1),
	"dress_prop_sandbag_wall": Vector2(3.9, 0.5),
	"dress_prop_tank_trap": Vector2(1.6, 1.6),
	# The obelisk is the piece whose visual and collision differ most: the ducts
	# that make it 24 x 28 m are mesh only now, and what stands in the way is
	# the plinth. Its mass also sits 3.9 m west of its origin.
	"dress_compute_obelisk": Vector2(15.2, 13.2),
	"dress_compute_data_hall": Vector2(29.0, 18.8),
	"dress_compute_chiller_yard": Vector2(14.0, 20.0),
	"dress_compute_monolith": Vector2(4.4, 2.8),
	"dress_compute_generator": Vector2(12.3, 4.6),
	"dress_compute_transformer": Vector2(3.6, 4.4),
	"dress_compute_cable_run": Vector2(3.3, 12.6),
	"dress_compute_network_cabinet": Vector2(1.4, 2.1),
	"dress_compute_rack_row": Vector2(5.6, 3.0),
	"dress_compute_racks_toppled": Vector2(3.8, 5.7),
	"dress_compute_cooling_unit": Vector2(6.5, 2.4),
	"dress_compute_satellite_dish": Vector2(4.0, 3.3),
	"dress_solar_canopy": Vector2(28.0, 40.0),
	"dress_solar_canopy_broken": Vector2(28.0, 40.0),
	"dress_solar_battery_container": Vector2(13.4, 2.8),
	"dress_solar_inverter_skid": Vector2(2.4, 6.2),
	"dress_solar_drone_dock": Vector2(4.0, 3.4),
	"dress_industrial_substation": Vector2(16.1, 20.1),
	"dress_feature_fuel_tanks": Vector2(14.0, 9.0),
	"br_bridge_gorge": Vector2(17.3, 56.5),
	"bld_apartment": Vector2(22.5, 16.5),
	"bld_compound": Vector2(28.3, 20.4),
	"bld_house_small": Vector2(17.5, 14.0),
	"bld_house_terrace": Vector2(21.5, 15.0),
	"bld_ruin_low": Vector2(17.0, 14.0),
	"bld_ruin_shell": Vector2(21.0, 17.0),
	"bld_shop_row": Vector2(29.0, 14.0),
	"bld_warehouse": Vector2(27.0, 20.3),
}

## The mix on the west bank already, so the new quarter reads as the same town.
const INTACT: Array[String] = ["bld_house_small", "bld_house_small", "bld_house_terrace",
		"bld_compound", "bld_shop_row", "bld_warehouse", "bld_apartment", "bld_house_small",
		"bld_house_terrace", "bld_compound"]
const RUINED: Array[String] = ["bld_ruin_shell", "bld_ruin_shell", "bld_ruin_low"]

## The new quarter, from the grey painted onto mutaha_wip.png.
const QUARTER := Rect2(-376.0, 88.0, 212.0, 156.0)

## The lots the extra grey paint made, named one by one rather than picked out
## of a rectangle: the west bank already has lots inside that rectangle, and
## putting a second building on one of them would be invisible in a diff and
## obvious in the editor. probe_terrain_diff.gd prints this list.
const FRESH_LOTS: Array[Vector2i] = [
		Vector2i(-311, 79), Vector2i(-188, 79),
		Vector2i(-352, 112), Vector2i(-311, 112), Vector2i(-270, 112), Vector2i(-229, 112), Vector2i(-188, 112),
		Vector2i(-352, 145), Vector2i(-311, 145), Vector2i(-270, 145), Vector2i(-229, 145), Vector2i(-188, 145),
		Vector2i(-352, 178), Vector2i(-311, 178), Vector2i(-270, 178), Vector2i(-229, 178), Vector2i(-188, 178),
		Vector2i(-352, 211), Vector2i(-311, 211), Vector2i(-270, 211), Vector2i(-229, 211), Vector2i(-188, 211)]

var data: TerrainData
var n := 0
var half := 0.0
var lines: PackedStringArray = []
## Every footprint written so far: [centre, half extents, angle, label].
var taken: Array = []
var placed := 0
var refused := 0


func _initialize() -> void:
	data = load(DATA)
	if data == null or data.cells_x == 0:
		print("FAIL  no terrain at %s — bake it first" % DATA)
		quit(1)
		return
	n = data.cells_x + 1
	half = data.cells_x * data.cell_size * 0.5
	print("   %s: %d x %d @ %.1f m, %d lots, %d bridges" % [DATA.get_file(), data.cells_x,
			data.cells_z, data.cell_size, data.lots.size(), data.bridges.size()])

	_reserve_lots()
	_reserve_bridges()

	_bridge_out_south()
	_south_crossing()
	_west_bridgehead()
	_island_south_wall()
	_south_quarter()

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s" % OUT)
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("   %d piece(s) placed, %d refused; wrote %s" % [placed, refused, OUT])
	quit()


# ── the ground ──────────────────────────────────────────────

## Height under a point, bilinear off the baked grid.
func ground(x: float, z: float) -> float:
	var fx: float = clampf((x + half) / data.cell_size, 0.0, float(data.cells_x))
	var fz: float = clampf((z + half) / data.cell_size, 0.0, float(data.cells_z))
	var i := int(fx)
	var j := int(fz)
	var i1: int = mini(i + 1, data.cells_x)
	var j1: int = mini(j + 1, data.cells_z)
	var tx := fx - i
	var tz := fz - j
	var h00: float = data.heights[j * n + i]
	var h10: float = data.heights[j * n + i1]
	var h01: float = data.heights[j1 * n + i]
	var h11: float = data.heights[j1 * n + i1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Is the water surface drawn here? The mask covers painted water plus a sliver
## of bank, so this is "in the river", not "near it".
func wet(x: float, z: float) -> bool:
	if data.water.is_empty():
		return false
	var i: int = clampi(roundi((x + half) / data.cell_size), 0, data.cells_x)
	var j: int = clampi(roundi((z + half) / data.cell_size), 0, data.cells_z)
	return data.water[j * n + i] > 0


## How rough the ground is over a square: the spread of 9 samples. A piece on
## ground that is not flat sits with one corner in the air.
func relief(x: float, z: float, r: float) -> float:
	var lo := INF
	var hi := -INF
	for dz: float in [-r, 0.0, r]:
		for dx: float in [-r, 0.0, r]:
			var h := ground(x + dx, z + dz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Walking out from a point until the ground drops away: where the bank starts.
## Used for the island's shoreline, which no file records.
func bank(x: float, z: float, step: float, limit: float, lip: float) -> float:
	var d := 0.0
	while absf(d) < limit:
		d += step
		if ground(x + d, z) < lip or wet(x + d, z):
			return x + d - step
	return x + d


# ── overlap ─────────────────────────────────────────────────

func _reserve_lots() -> void:
	# A building lot is 32 x 24 m of ground that belongs to a building, whether
	# this run puts one there or the level already has one. Nothing else goes on
	# it, so street dressing stays in the streets.
	for l in data.lots:
		taken.append([l.centre, (l.size as Vector2) * 0.5, 0.0, "lot"])


func _reserve_bridges() -> void:
	# A gap is where the road stops; the PREFAB reaches much further, because its
	# ramps climb on dry land. bridge_truss_long is 94 m over a 49 m gap, so it
	# overhangs each bank by 23 m, and anything stood there is inside the deck.
	# The island south gap is skipped on purpose: its span has been deleted, and
	# the wreckage that says so goes exactly where the span used to be.
	for br in data.bridges:
		var a: Vector3 = br.start
		var b: Vector3 = br.end
		var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		if mid.distance_to(Vector2(4.0, 172.0)) < 20.0:
			continue
		var dir := Vector2(b.x - a.x, b.z - a.z)
		# Half the prefab, less half the gap: how far it overhangs each bank.
		var overhang := 8.0
		for long_one: Vector2 in [Vector2(-122.0, -38.0), Vector2(29.0, 17.0)]:
			if mid.distance_to(long_one) < 20.0:
				overhang = 24.0
		taken.append([mid, Vector2(12.0, dir.length() * 0.5 + overhang), atan2(dir.x, dir.y),
				"bridge corridor"])


## Corners of a rotated rectangle, in world x/z.
func _corners(c: Vector2, h: Vector2, ang: float) -> Array[Vector2]:
	var ca := cos(ang)
	var sa := sin(ang)
	# The piece's local +X is (cos, -sin) and local +Z is (sin, cos), matching
	# how Basis(UP, angle) is written into a .tscn.
	var ax := Vector2(ca, -sa) * h.x
	var az := Vector2(sa, ca) * h.y
	return [c - ax - az, c + ax - az, c + ax + az, c - ax + az]


## Separating-axis test between two rotated rectangles.
func _hits(ca: Vector2, ha: Vector2, aa: float, cb: Vector2, hb: Vector2, ab: float) -> bool:
	var pa := _corners(ca, ha, aa)
	var pb := _corners(cb, hb, ab)
	for pair: Array in [[pa, aa], [pb, ab]]:
		var ang: float = pair[1]
		for axis: Vector2 in [Vector2(cos(ang), -sin(ang)), Vector2(sin(ang), cos(ang))]:
			var lo_a := INF
			var hi_a := -INF
			var lo_b := INF
			var hi_b := -INF
			for p: Vector2 in pa:
				var d := p.dot(axis)
				lo_a = minf(lo_a, d)
				hi_a = maxf(hi_a, d)
			for p: Vector2 in pb:
				var d := p.dot(axis)
				lo_b = minf(lo_b, d)
				hi_b = maxf(hi_b, d)
			if hi_a <= lo_b or hi_b <= lo_a:
				return false
	return true


# ── writing ─────────────────────────────────────────────────

func group(path: String, nm: String, at := Vector3.ZERO) -> void:
	lines.append("")
	lines.append("[node name=\"%s\" type=\"Node3D\" parent=\"%s\"]" % [nm, path])
	if at != Vector3.ZERO:
		lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4f, %.4f, %.4f)" % [at.x, at.y, at.z])


## Put a piece down, or say why not. `deg` turns it about Y the way the editor
## does; `y` defaults to the ground under it.
## `loose` is for a piece that is MEANT to stand over other things — a canopy
## on legs, whose whole point is that the yard carries on underneath it. It
## skips the overlap test and claims no ground of its own.
func put(parent: String, nm: String, res: String, x: float, z: float, deg := 0.0,
		y := NAN, shrink := 0.6, loose := false) -> bool:
	var size: Vector2 = SIZE.get(res, Vector2(3.0, 3.0))
	var h := size * 0.5 * shrink
	var c := Vector2(x, z)
	var ang := deg_to_rad(deg)
	if not loose:
		for t: Array in taken:
			if _hits(c, h, ang, t[0], t[1], t[2]):
				print("   REFUSED %-22s at (%7.1f, %7.1f) — overlaps %s" % [nm, x, z, t[3]])
				refused += 1
				return false
		taken.append([c, h, ang, nm])
	var ca := cos(ang)
	var sa := sin(ang)
	var yy: float = ground(x, z) if is_nan(y) else y
	lines.append("")
	lines.append("[node name=\"%s\" parent=\"%s\" instance=ExtResource(\"%s\")]" % [nm, parent, res])
	lines.append("transform = Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.5f, %.4f)"
			% [ca, sa, -sa, ca, x, yy, z])
	placed += 1
	return true


## Put a piece down near where it was wanted. Tries the spot, then rings of
## spots out to `reach`, and takes the first that is free, dry and flat. The
## bridgehead and the streets are laid out by intent — a wall on this flank, a
## lamp on that corner — and intent lands on top of a building lot often enough
## that refusing outright leaves holes in the plan.
func put_near(parent: String, nm: String, res: String, x: float, z: float, deg := 0.0,
		reach := 16.0) -> bool:
	var rings := int(reach / 3.5)
	for ring in rings + 1:
		var r := ring * 3.5
		var steps: int = 1 if ring == 0 else 8 + ring * 4
		for i in steps:
			var a := TAU * i / steps + ring * 0.4
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if wet(px, pz) or relief(px, pz, 2.5) > 0.9:
				continue
			if _free(px, pz, res, deg) and put(parent, nm, res, px, pz, deg):
				if ring > 0:
					print("   moved   %-22s %.0f m to (%7.1f, %7.1f)" % [nm, r, px, pz])
				return true
	return put(parent, nm, res, x, z, deg)   # report the refusal properly


## Would this piece fit here? The same test put() makes, without the writing.
func _free(x: float, z: float, res: String, deg: float) -> bool:
	var h: Vector2 = (SIZE.get(res, Vector2(3.0, 3.0)) as Vector2) * 0.3
	var ang := deg_to_rad(deg)
	for t: Array in taken:
		if _hits(Vector2(x, z), h, ang, t[0], t[1], t[2]):
			return false
	return true


## The turn that points a piece's long side (its local X) along a direction.
func along(dir: Vector2) -> float:
	return rad_to_deg(atan2(-dir.y, dir.x))


## The turn that points a piece's local Z along a direction: bridges, and
## anything else built to run forwards.
func facing(dir: Vector2) -> float:
	return rad_to_deg(atan2(dir.x, dir.y))


# ── 1. the span that is gone ────────────────────────────────

func _bridge_out_south() -> void:
	# The generator still leaves the gap: the road runs down the island's spine
	# to the water at (-1.5, 158) and picks up again on the plain at (10, 187).
	# Taking the bridge node out is what makes it impassable; this is what makes
	# it legible from either bank.
	var br := _gap_near(Vector2(4.0, 172.0))
	if br.is_empty():
		print("   REFUSED BridgeOutSouth — no road gap near the island's south tip")
		return
	var a := Vector2(br.start.x, br.start.z)
	var b := Vector2(br.end.x, br.end.z)
	var dir := (b - a).normalized()
	var side := Vector2(dir.y, -dir.x)
	group("NavigationRegion3D/Dressing", "BridgeOutSouth")
	var p := "NavigationRegion3D/Dressing/BridgeOutSouth"

	# Island abutment: the road stops at a barrier line, with what fell off it.
	for i in 3:
		var at := a - dir * 5.0 + side * (i - 1) * 3.4
		put(p, "IslandBarrier%d" % (i + 1), "dress_prop_jersey_barrier", at.x, at.y, along(side))
	put(p, "IslandRubble1", "dress_prop_rubble_pile", (a - dir * 10.0 + side * 6.0).x,
			(a - dir * 10.0 + side * 6.0).y)
	put(p, "IslandRubble2", "dress_prop_rubble_pile", (a - dir * 13.0 - side * 6.0).x,
			(a - dir * 13.0 - side * 6.0).y)
	put(p, "IslandBlocks", "dress_prop_concrete_blocks", (a - dir * 9.0 - side * 3.0).x,
			(a - dir * 9.0 - side * 3.0).y, 18.0)
	put(p, "IslandCar", "dress_prop_car_wreck", (a - dir * 16.0 + side * 2.0).x,
			(a - dir * 16.0 + side * 2.0).y, along(dir) + 12.0)

	# The deck, in the river. It sits on the bed, so it stands out of the water
	# rather than floating on it.
	for i in 4:
		var t: float = 0.22 + i * 0.19
		var at := a.lerp(b, t) + side * (2.5 if i % 2 == 0 else -3.5)
		var bed := ground(at.x, at.y)
		put(p, "FallenSpan%d" % (i + 1), "dress_prop_rubble_pile" if i % 2 == 0
				else "dress_prop_concrete_blocks", at.x, at.y, 20.0 * i, bed)

	# Plain abutment: somebody made sure of it.
	put(p, "PlainTeeth1", "dress_fort_dragon_teeth", (b + dir * 6.0).x, (b + dir * 6.0).y, along(side))
	put(p, "PlainTeeth2", "dress_fort_dragon_teeth", (b + dir * 10.0 + side * 13.0).x,
			(b + dir * 10.0 + side * 13.0).y, along(side))
	put(p, "PlainWire1", "dress_fort_razor_wire", (b + dir * 12.0).x, (b + dir * 12.0).y, along(side))
	put(p, "PlainNest", "dress_prop_sandbag_nest", (b + dir * 18.0 - side * 9.0).x,
			(b + dir * 18.0 - side * 9.0).y, along(dir))
	put(p, "PlainRubble", "dress_prop_rubble_pile", (b + dir * 8.0 - side * 8.0).x,
			(b + dir * 8.0 - side * 8.0).y)
	put(p, "PlainSign", "dress_prop_lamp_post", (b + dir * 15.0 + side * 7.0).x,
			(b + dir * 15.0 + side * 7.0).y, 40.0)


# ── 2. the span that moved ──────────────────────────────────

func _south_crossing() -> void:
	# The new road over the river at z = 316. Painting the road is what opened
	# the gap; this drops the same kind of span the island's south tip had.
	var br := _gap_near(Vector2(-106.0, 316.0))
	if br.is_empty():
		print("   REFUSED SouthCrossing — the road did not open a gap at z = 316")
		return
	var a := Vector2(br.start.x, br.start.z)
	var b := Vector2(br.end.x, br.end.z)
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var side := Vector2(dir.y, -dir.x)
	print("   crossing gap %.1f m at (%.0f, %.0f) heading %.0f deg" % [a.distance_to(b),
			mid.x, mid.y, facing(dir)])
	lines.append("")
	lines.append("[node name=\"Bridge07\" parent=\"NavigationRegion3D/Bridges\" instance=ExtResource(\"br_bridge_gorge\")]")
	var ang := deg_to_rad(facing(dir))
	# bridge_gorge's origin is the middle of the span at the height of the
	# ground at the ramp feet, and its deck sits 0.75 m above that.
	lines.append("transform = Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.5f, %.4f)"
			% [cos(ang), sin(ang), -sin(ang), cos(ang), mid.x, float(br.start.y) - 0.75, mid.y])
	placed += 1

	group("NavigationRegion3D/Dressing", "SouthCrossing")
	var p := "NavigationRegion3D/Dressing/SouthCrossing"
	# A gate on the town side, because this is the way in now.
	put(p, "Gate", "dress_fort_checkpoint", (a - dir * 42.0).x, (a - dir * 42.0).y, along(dir))
	for i in 2:
		var s: float = 1.0 if i == 0 else -1.0
		put(p, "GateWall%d" % (i + 1), "dress_fort_hesco_wall", (a - dir * 34.0 + side * s * 15.0).x,
				(a - dir * 34.0 + side * s * 15.0).y, along(dir))
		put(p, "GateMast%d" % (i + 1), "dress_fort_floodlight_mast",
				(a - dir * 26.0 + side * s * 12.0).x, (a - dir * 26.0 + side * s * 12.0).y, 0.0)
		put(p, "FarWire%d" % (i + 1), "dress_fort_razor_wire", (b + dir * 16.0 + side * s * 11.0).x,
				(b + dir * 16.0 + side * s * 11.0).y, along(dir))
	put(p, "FarNest", "dress_prop_sandbag_nest", (b + dir * 22.0 - side * 8.0).x,
			(b + dir * 22.0 - side * 8.0).y, along(-dir))
	put(p, "FarBarrier1", "dress_prop_jersey_barrier", (b + dir * 10.0 + side * 3.0).x,
			(b + dir * 10.0 + side * 3.0).y, along(side))
	put(p, "FarBarrier2", "dress_prop_jersey_barrier", (b + dir * 10.0 - side * 3.0).x,
			(b + dir * 10.0 - side * 3.0).y, along(side))


# ── 3. cover where the west bridge lands ────────────────────

func _west_bridgehead() -> void:
	# The west bridge's gap ends on the west bank at (-144, -48). The block
	# behind it is one the generator left without a building, so there is a bare
	# 34 x 26 m plaza to fight over — which is exactly the problem: crossing the
	# bridge put the squad in the open with nothing to get behind.
	var br := _gap_near(Vector2(-122.0, -38.0))
	if br.is_empty():
		print("   REFUSED WestBridgehead — no gap at the west bridge")
		return
	# `start` is the west end: the gap is recorded west to east here.
	var o := Vector2(br.start.x, br.start.z)
	var to_island := (Vector2(br.end.x, br.end.z) - o).normalized()
	var u := -to_island                       # inland, away from the water
	var s := Vector2(-u.y, u.x)               # across the road
	group("NavigationRegion3D/Dressing", "WestBridgehead")
	var p := "NavigationRegion3D/Dressing/WestBridgehead"

	# The chicane on the ramp road itself: staggered T-walls, which is what you
	# put on a bridge you still want to use.
	for i in 4:
		var at := o + u * (28.0 + i * 7.0) + s * (5.0 if i % 2 == 0 else -5.0)
		put(p, "Chicane%d" % (i + 1), "dress_fort_t_walls", at.x, at.y, along(s) + (18.0 if i % 2 == 0 else -18.0))
	# Flanking walls, set back far enough to clear the deck and its ramps.
	for i in 3:
		for side_i in 2:
			var sg: float = 1.0 if side_i == 0 else -1.0
			var at := o + u * (8.0 + i * 13.0) + s * sg * 17.0
			put_near(p, "Wall%s%d" % ["N" if sg > 0.0 else "S", i + 1], "dress_fort_hesco_wall",
					at.x, at.y, along(u), 12.0)
	# Overwatch on each flank, and hard cover in the middle of the plaza.
	for side_i in 2:
		var sg: float = 1.0 if side_i == 0 else -1.0
		var at := o + u * 22.0 + s * sg * 27.0
		put_near(p, "Sangar%s" % ["N" if sg > 0.0 else "S"], "dress_fort_hesco_sangar", at.x, at.y, along(s), 20.0)
		var cs := o + u * 40.0 + s * sg * 22.0
		put_near(p, "Containers%s" % ["N" if sg > 0.0 else "S"], "dress_feature_container_stack",
				cs.x, cs.y, along(u) + sg * 14.0, 20.0)
		var bm := o + u * 13.0 + s * sg * 30.0
		put_near(p, "Berm%s" % ["N" if sg > 0.0 else "S"], "dress_feature_berm", bm.x, bm.y, along(u), 20.0)
	# Loose cover, so the plaza is not a chessboard.
	var loose: Array = [
		["Car1", "dress_prop_car_wreck", 18.0, 11.0, 70.0],
		["Car2", "dress_prop_car_wreck", 33.0, -13.0, 20.0],
		["Rubble1", "dress_prop_rubble_pile", 26.0, 13.0, 0.0],
		["Rubble2", "dress_prop_rubble_pile", 46.0, -6.0, 0.0],
		["Blocks1", "dress_prop_concrete_blocks", 15.0, -12.0, 30.0],
		["Blocks2", "dress_prop_concrete_blocks", 38.0, 14.0, -20.0],
		["Pipes", "dress_prop_concrete_pipes", 44.0, 9.0, 55.0],
		["Crates", "dress_prop_crates", 30.0, 8.0, 15.0],
		["Barrels", "dress_prop_barrels", 24.0, -9.0, 0.0],
		["Mound1", "dress_prop_dirt_mound", 12.0, 22.0, 0.0],
		["Mound2", "dress_prop_dirt_mound", 20.0, -22.0, 40.0],
		["Hesco1", "dress_prop_hesco_row", 35.0, 0.0, 12.0],
		["Hesco2", "dress_prop_hesco_row", 39.0, 4.0, 12.0],
		["Lamp1", "dress_prop_lamp_post", 10.0, 9.0, 0.0],
		["Lamp2", "dress_prop_lamp_post", 34.0, -9.0, 180.0],
		["Mast", "dress_fort_floodlight_mast", 6.0, -14.0, 0.0],
	]
	for row: Array in loose:
		var at := o + u * float(row[2]) + s * float(row[3])
		put_near(p, str(row[0]), str(row[1]), at.x, at.y, float(row[4]), 14.0)
	# Wire on the waterline either side of the abutment: the bridge is the only
	# way over, and it should look like it.
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var at := o + u * 3.0 + s * sg * 21.0
		put_near(p, "Wire%d" % (i + 1), "dress_fort_razor_wire", at.x, at.y, along(s), 10.0)


# ── 4. the wall round the island's south tip ────────────────

func _island_south_wall() -> void:
	# The south tip is a spit between the two channels, and the Factory group
	# stands on it. With the south bridge gone you can no longer walk onto it,
	# but you can still stand on the east plain 40 m away and shoot everything
	# on it. A wall along the waterline is what stops that.
	#
	# The shoreline is not recorded anywhere, so it is measured: walk out from
	# the spit's spine at each step until the ground drops to the bank, then set
	# the wall back from the lip so it stands on flat ground.
	group("NavigationRegion3D/Dressing", "IslandSouthWall")
	var p := "NavigationRegion3D/Dressing/IslandSouthWall"
	var lip := -1.8
	var east: Array[Vector2] = []
	var z := 140.0
	while z <= 224.0:
		var spine: float = -60.0 - (z - 140.0) * 0.22
		var e := bank(spine, z, 2.0, 140.0, lip)
		if e - spine > 4.0:
			east.append(Vector2(e - 6.0, z))
		z += 4.0
	_wall_along(p, "East", east, 12.5, ["dress_fort_hesco_wall", "dress_fort_hesco_wall",
			"dress_fort_t_walls"], Vector2(150.0, 162.0))
	# The west face gets earth, not baskets: nobody fortified this side, they
	# just pushed spoil up against it.
	var west: Array[Vector2] = []
	z = 152.0
	while z <= 220.0:
		var spine: float = -60.0 - (z - 140.0) * 0.22
		var w := bank(spine, z, -2.0, 140.0, lip)
		if spine - w > 4.0:
			west.append(Vector2(w + 6.0, z))
		z += 4.0
	_wall_along(p, "West", west, 15.5, ["dress_feature_berm"], Vector2(0.0, 0.0))
	# Two firing positions behind the east wall, looking over it at the plain.
	for i in 2:
		var zz: float = 172.0 + i * 26.0
		var spine: float = -60.0 - (zz - 140.0) * 0.22
		var e := bank(spine, zz, 2.0, 140.0, lip)
		put(p, "Sangar%d" % (i + 1), "dress_fort_hesco_sangar", e - 15.0, zz, 90.0)
	# Wire outside the wall, on the bank where nothing can shelter.
	for i in 3:
		var zz: float = 150.0 + i * 24.0
		var spine: float = -60.0 - (zz - 140.0) * 0.22
		var e := bank(spine, zz, 2.0, 140.0, lip)
		put_near(p, "Wire%d" % (i + 1), "dress_fort_razor_wire", e - 1.0, zz, 90.0, 10.0)
	# Teeth across the gate, so the gap in the wall is a gate and not a hole.
	put(p, "GateTeeth", "dress_fort_dragon_teeth", -22.0, 156.0, 24.0)
	put_near(p, "GateWallA", "dress_fort_t_walls", -14.0, 150.0, 70.0, 10.0)
	put_near(p, "GateWallB", "dress_fort_t_walls", -18.0, 164.0, 70.0, 10.0)


## A wall built along a measured line: pieces end to end, each turned to the
## local heading, skipping a gap where a road has to get through.
func _wall_along(p: String, tag: String, line: Array[Vector2], pitch: float,
		kit: Array, gap: Vector2) -> void:
	if line.size() < 2:
		print("   REFUSED %s wall — could not find a shoreline to follow" % tag)
		return
	var walked := 0.0
	var next := 0.0
	var i := 0
	var k := 0
	while i < line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var seg := a.distance_to(b)
		if walked + seg < next:
			walked += seg
			i += 1
			continue
		var t: float = (next - walked) / maxf(seg, 0.001)
		var at := a.lerp(b, t)
		next += pitch
		if at.y >= gap.x and at.y <= gap.y:
			continue
		var dir := (b - a).normalized()
		k += 1
		put(p, "%s%d" % [tag, k], str(kit[(k - 1) % kit.size()]), at.x, at.y, along(dir))


# ── 5. the new quarter ──────────────────────────────────────

func _south_quarter() -> void:
	# The 22 lots the grey paint made. Two of them get a yard instead of a
	# building: a quarter of nothing but houses reads as wallpaper.
	var by_centre := {}
	for l in data.lots:
		by_centre[Vector2i(roundi(Vector2(l.centre).x), roundi(Vector2(l.centre).y))] = l
	var fresh: Array = []
	for key: Vector2i in FRESH_LOTS:
		if by_centre.has(key):
			fresh.append(by_centre[key])
		else:
			print("   REFUSED lot (%d, %d) — the bake no longer has a lot there" % [key.x, key.y])
	print("   %d of %d new lot(s) found in the bake" % [fresh.size(), FRESH_LOTS.size()])
	var yards := {"(-229, 211)": "dress_industrial_container_yard",
			"(-270, 145)": "dress_industrial_parking_lot"}
	var k := 0
	for l in fresh:
		var c: Vector2 = l.centre
		var key := "(%d, %d)" % [roundi(c.x), roundi(c.y)]
		var res: String = ""
		if yards.has(key):
			res = yards[key]
		else:
			var seed_v := absi(hash(Vector2i(roundi(c.x), roundi(c.y))))
			var pool: Array[String] = RUINED if bool(l.ruined) else INTACT
			res = pool[seed_v % pool.size()]
		var turn: float = 180.0 if absi(hash(Vector2i(roundi(c.y), roundi(c.x)))) % 2 == 0 else 0.0
		# The lot is reserved ground; drop the reservation that covers exactly
		# this lot so the building itself is allowed to stand on it.
		var drop := -1
		for t_i in taken.size():
			if str(taken[t_i][3]) == "lot" and (taken[t_i][0] as Vector2).distance_to(c) < 0.5:
				drop = t_i
		if drop >= 0:
			taken.remove_at(drop)
		put("NavigationRegion3D/Buildings", "LotS%02d_%s" % [k, res.trim_prefix("dress_").trim_prefix("bld_")],
				res, c.x, c.y, turn, float(l.height))
		k += 1

	# Street dressing. The grid is 34 x 26 m blocks with 7 m streets, so the
	# street centrelines are fixed; everything here goes on one of them.
	group("NavigationRegion3D/Dressing", "SouthQuarter")
	var p := "NavigationRegion3D/Dressing/SouthQuarter"
	var street: Array = []
	for kx in range(-9, -3):
		for kz in range(2, 8):
			street.append(Vector2(kx * 41.0 + 37.5, kz * 33.0 + 29.5))
	var props: Array[String] = ["dress_prop_lamp_post", "dress_prop_car_wreck",
			"dress_prop_rubble_pile", "dress_prop_jersey_barrier", "dress_prop_power_pole",
			"dress_prop_crates", "dress_prop_barrels", "dress_prop_concrete_blocks",
			"dress_prop_hesco_row", "dress_prop_sandbag_wall", "dress_prop_dirt_mound",
			"dress_prop_tank_trap", "dress_prop_concrete_pipes"]
	var j := 0
	for centre: Vector2 in street:
		if not QUARTER.has_point(centre):
			continue
		var seed_v := absi(hash(Vector2i(roundi(centre.x), roundi(centre.y))))
		for i in 4:
			var r := seed_v >> (i * 5)
			var at := centre + Vector2((int(r) % 25) - 12.0, ((int(r) >> 3) % 25) - 12.0)
			if wet(at.x, at.y) or relief(at.x, at.y, 2.0) > 0.7:
				continue
			j += 1
			put_near(p, "Street%02d" % j, props[int(r >> 7) % props.size()], at.x, at.y,
					float(int(r >> 11) % 36) * 10.0, 7.0)
	# The quay: the riverside street looks straight across at the island, so it
	# gets a firing line rather than lamp posts.
	var quay := 0
	var zz := 104.0
	while zz <= 232.0:
		var x := -167.5
		if not wet(x, zz) and relief(x, zz, 3.0) < 0.9:
			quay += 1
			var res: String = "dress_prop_sandbag_wall" if quay % 3 != 0 else "dress_prop_hesco_row"
			put(p, "Quay%02d" % quay, res, x + 4.0, zz, 90.0)
			if quay % 4 == 2:
				put(p, "QuayPole%02d" % quay, "dress_prop_power_pole", x - 3.0, zz + 6.0, 0.0)
		zz += 11.0


func _gap_near(at: Vector2) -> Dictionary:
	var best := {}
	var best_d := 60.0
	for br in data.bridges:
		var mid := Vector2((float(br.start.x) + float(br.end.x)) * 0.5,
				(float(br.start.z) + float(br.end.z)) * 0.5)
		var d := mid.distance_to(at)
		if d < best_d:
			best_d = d
			best = br
	return best
