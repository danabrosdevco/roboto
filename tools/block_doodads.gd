extends "res://tools/block_buildings.gd"

# ─────────────────────────────────────────────
# BLOCK DOODADS — writes the TrenchBroom terrain features and props:
#
#   maps/blocks/features/feature_*.map — set pieces placed by hand: rock
#       outcrops, a cliff ledge, berms, trench lining, a crater rim, a
#       pillbox, a watchtower, containers, a pylon, fuel tanks.
#   maps/blocks/props/prop_*.map — boulders, rubble, barriers, sandbags,
#       hesco, tank traps, barrels, crates, wrecks, poles: small enough to
#       scatter (drop the prefab into a TerrainScatterLayer's Scenes) or to
#       place by hand.
#
#   godot --headless --path . --script res://tools/block_doodads.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_doodads.gd -- maps/blocks --force
#
# Same brush kit and rules as block_buildings.gd, which this extends:
# worldspawn only, 32 units = 1 m, ground at z 0, footprint centred on the
# origin, only textures that have a material, and never an overwrite without
# --force — once a map has been edited in TrenchBroom, the map is the source.
#
# What this adds is solid(): the convex hull of any points, so rocks can be
# faceted and beams can lean at any angle. The hull is built from the points
# after they are snapped to the grid, in exact whole-unit arithmetic, so every
# face plane passes through real vertices and TrenchBroom reads the brush back
# exactly as written.
#
# Props sit on z 0 with a little of themselves below it: a scatter layer sinks
# each one by its `sink`, and no slope is perfectly flat.
# ─────────────────────────────────────────────

const ROCK := "PSX_Textures/rock_2"
const STRATA := "PSX_Textures/rock_4"
const DIRT := "PSX_Textures/dirt_4"
const SANDBAG := "PSX_Textures/fabric_tx_1"
const RUST := "PSX_Textures/metal_rusty_tsk_1"
const RUST_PANEL := "PSX_Textures/metal_rusty_tsk_2"
const GREEN := "PSX_Textures/metal_wall_2"
const BLUE := "PSX_Textures/metal_wall_3"
const RUBBER := "PSX_Textures/rubber_tsk_1"
const WOOD := "PSX_Textures/wood_2"
const PLANK := "PSX_Textures/wood_3"
const WOOD_DARK := "PSX_Textures/wood_8"
const CRATE := "PSX_Textures/crate_wooden_2"
const CONCRETE := "PSX_Textures/concrete_tx_5"

const EARTH := {"top": DIRT, "side": DIRT, "bottom": DIRT}


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			print("ignoring argument '%s'" % a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_doodads.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var features := {
		"feature_rock_outcrop": _rock_outcrop,
		"feature_rock_spire": _rock_spire,
		"feature_cliff_ledge": _cliff_ledge,
		"feature_boulder_field": _boulder_field,
		"feature_berm": _berm,
		"feature_trench_revetment": _trench_revetment,
		"feature_crater_rim": _crater_rim,
		"feature_pillbox": _pillbox,
		"feature_watchtower": _watchtower,
		"feature_container_stack": _container_stack,
		"feature_power_pylon": _power_pylon,
		"feature_fuel_tanks": _fuel_tanks,
	}
	var props := {
		"prop_boulder_a": _boulder_a,
		"prop_boulder_b": _boulder_b,
		"prop_boulder_c": _boulder_c,
		"prop_rock_slabs": _rock_slabs,
		"prop_dirt_mound": _dirt_mound,
		"prop_rubble_pile": _rubble_pile,
		"prop_jersey_barrier": _jersey_barrier,
		"prop_concrete_blocks": _concrete_blocks,
		"prop_sandbag_wall": _sandbag_wall,
		"prop_sandbag_nest": _sandbag_nest,
		"prop_hesco_row": _hesco_row,
		"prop_tank_trap": _tank_trap,
		"prop_barrels": _barrels,
		"prop_crates": _crates,
		"prop_car_wreck": _car_wreck,
		"prop_robot_wreck": _robot_wreck,
		"prop_lamp_post": _lamp_post,
		"prop_power_pole": _power_pole,
		"prop_concrete_pipes": _concrete_pipes,
	}
	var skipped := 0
	for pair in [[base.path_join("features"), features], [base.path_join("props"), props]]:
		var dir: String = pair[0]
		if not DirAccess.dir_exists_absolute(dir):
			var err := DirAccess.make_dir_recursive_absolute(dir)
			if err != OK:
				print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
				quit(1)
				return
		var made: Dictionary = pair[1]
		for name: String in made:
			var path := dir.path_join(name + ".map")
			if FileAccess.file_exists(path) and not force:
				print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
				skipped += 1
				continue
			_brushes = []
			(made[name] as Callable).call()
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
				quit(1)
				return
			f.store_string(_map_text())
			f.close()
			print("      %-26s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK DOODADS DONE%s" % ((" (%d skipped)" % skipped) if skipped > 0 else ""))
	quit()


# ── Solids ───────────────────────────────────────────────────────────────────

## Convex hull of `points` (metres) as one brush. The points snap to a grid of
## `grid` units first — coarser for rocks, so facets stay a sensible size.
func solid(points: Array, tex: Variant, grid: int = 1) -> void:
	var snapped: Array = []
	var seen := {}
	for q: Vector3 in points:
		var s := Vector3(roundf(q.x * UPM / grid) * grid, roundf(q.y * UPM / grid) * grid, roundf(q.z * UPM / grid) * grid)
		var key := Vector3i(int(s.x), int(s.y), int(s.z))
		if not seen.has(key):
			seen[key] = true
			snapped.append(s)
	var faces := _hull(snapped)
	if faces.is_empty():
		push_warning("block_doodads: %d point(s) enclose no volume — brush skipped" % snapped.size())
		return
	var verts: Array = []
	for v: Vector3 in snapped:
		verts.append(v / UPM)
	brush(verts, faces, tex)


## ((b - a) × (c - a)) · (d - a) in 64-bit floats. The coordinates are whole
## units, so this is exact: a point is on a face's plane or it is not.
func _orient(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	var bx: float = b.x - a.x
	var by: float = b.y - a.y
	var bz: float = b.z - a.z
	var cx: float = c.x - a.x
	var cy: float = c.y - a.y
	var cz: float = c.z - a.z
	var dx: float = d.x - a.x
	var dy: float = d.y - a.y
	var dz: float = d.z - a.z
	return (by * cz - bz * cy) * dx + (bz * cx - bx * cz) * dy + (bx * cy - by * cx) * dz


## Incremental convex hull. Returns one outward triangle per face plane —
## coplanar triangles merged, since two faces on one plane would be a
## duplicate plane to TrenchBroom.
func _hull(p: Array) -> Array:
	var n := p.size()
	if n < 4:
		return []
	var i1 := 0
	var best := -1.0
	for i in n:
		var d := (p[i] as Vector3).distance_squared_to(p[0])
		if d > best:
			best = d
			i1 = i
	var i2 := 0
	best = -1.0
	for i in n:
		var d := ((p[i1] as Vector3) - (p[0] as Vector3)).cross((p[i] as Vector3) - (p[0] as Vector3)).length_squared()
		if d > best:
			best = d
			i2 = i
	var i3 := -1
	best = 0.0
	for i in n:
		var d := absf(_orient(p[0], p[i1], p[i2], p[i]))
		if d > best:
			best = d
			i3 = i
	if i3 < 0:
		return []   # every point on one plane: no volume
	var tet := [0, i1, i2, i3]
	var faces: Array = []
	for f in [[0, 1, 2, 3], [0, 1, 3, 2], [0, 2, 3, 1], [1, 2, 3, 0]]:
		var a: int = tet[f[0]]
		var b: int = tet[f[1]]
		var c: int = tet[f[2]]
		faces.append([a, c, b] if _orient(p[a], p[b], p[c], p[tet[f[3]]]) > 0.0 else [a, b, c])
	for i in n:
		if tet.has(i):
			continue
		var visible: Array = []
		for f in faces.size():
			if _orient(p[faces[f][0]], p[faces[f][1]], p[faces[f][2]], p[i]) > 0.0:
				visible.append(f)
		if visible.is_empty():
			continue
		var edges := {}
		for f: int in visible:
			for e in 3:
				edges[Vector2i(faces[f][e], faces[f][(e + 1) % 3])] = true
		var added: Array = []
		var degenerate := false
		for e: Vector2i in edges:
			if edges.has(Vector2i(e.y, e.x)):
				continue
			var ab: Vector3 = (p[e.y] as Vector3) - (p[e.x] as Vector3)
			var ai: Vector3 = (p[i] as Vector3) - (p[e.x] as Vector3)
			if ab.cross(ai).is_zero_approx():
				degenerate = true   # the point is on a horizon edge's line: leave it out
				break
			added.append([e.x, e.y, i])
		if degenerate:
			continue
		var kept: Array = []
		for f in faces.size():
			if not visible.has(f):
				kept.append(faces[f])
		kept.append_array(added)
		faces = kept
	var planes: Array = []
	for fa: Array in faces:
		var same := false
		for g: Array in planes:
			if _orient(p[g[0]], p[g[1]], p[g[2]], p[fa[0]]) == 0.0 and _orient(p[g[0]], p[g[1]], p[g[2]], p[fa[1]]) == 0.0 \
					and _orient(p[g[0]], p[g[1]], p[g[2]], p[fa[2]]) == 0.0:
				same = true
				break
		if not same:
			planes.append(fa)
	return planes


## A faceted rock: the hull of `n` jittered points on an ellipsoid of radii
## `r` about `c`. `top` flattens it into a ledge you can stand on, and
## `top_ring` (metres) guarantees that ledge is at least that wide.
func rock(c: Vector3, r: Vector3, seed: int, tex: Variant = ROCK, n: int = 14, top: float = INF, top_ring: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts: Array = []
	for i in n:
		var t := (i + 0.5) / n
		var inc := acos(1.0 - 2.0 * t)
		var az := PI * (1.0 + sqrt(5.0)) * i + rng.randf_range(-0.5, 0.5)
		var d := Vector3(sin(inc) * cos(az), sin(inc) * sin(az), cos(inc))
		var k := rng.randf_range(0.72, 1.08)
		var q := c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * k
		q.z = minf(q.z, top)
		pts.append(q)
	if top_ring > 0.0 and top < INF:
		for i in 7:
			var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
			pts.append(Vector3(c.x + cos(a) * top_ring, c.y + sin(a) * top_ring, top))
	solid(pts, tex, 4)


## A square-section bar `w` wide from a to b.
func beam(a: Vector3, b: Vector3, w: float, tex: Variant = METAL) -> void:
	var axis := (b - a).normalized()
	# The kit's up is +Z (Quake axes), not Vector3.UP.
	var side := axis.cross(Vector3(0, 0, 1) if absf(axis.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	var up := side.cross(axis).normalized()
	var pts: Array = []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var o: Vector3 = side * s.x * w * 0.5 + up * s.y * w * 0.5
		pts.append(a + o)
		pts.append(b + o)
	solid(pts, tex)


## Upright n-sided prism: a drum, a pole, a tank. Built face by face, not by
## hull, so its sides stay exact quads.
func cylinder(c: Vector3, radius: float, height: float, sides: int, tex: Variant, top_radius: float = -1.0) -> void:
	var rt := radius if top_radius < 0.0 else top_radius
	var v: Array = []
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		v.append(Vector3(c.x + cos(a) * radius, c.y + sin(a) * radius, c.z))
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		v.append(Vector3(c.x + cos(a) * rt, c.y + sin(a) * rt, c.z + height))
	var faces: Array = [range(sides), range(sides, sides * 2)]
	for i in sides:
		var j := (i + 1) % sides
		faces.append([i, j, sides + j, sides + i])
	brush(v, faces, tex)


## n-sided prism lying along X or Y (`along` "x" or "y"), resting on z_base.
func log_x(c: Vector3, radius: float, length: float, sides: int, tex: Variant, along: String = "x") -> void:
	var v: Array = []
	for end in [-0.5, 0.5]:
		for i in sides:
			var a := TAU * (i + 0.5) / sides
			var q := Vector2(cos(a) * radius, sin(a) * radius)
			if along == "x":
				v.append(Vector3(c.x + end * length, c.y + q.x, c.z + radius + q.y))
			else:
				v.append(Vector3(c.x + q.x, c.y + end * length, c.z + radius + q.y))
	var faces: Array = [range(sides), range(sides, sides * 2)]
	for i in sides:
		var j := (i + 1) % sides
		faces.append([i, j, sides + j, sides + i])
	brush(v, faces, tex)


## Box of size `s` centred on c, turned by `rot` (degrees about X, Y, Z in
## that order) — a block that has tipped over.
func tipped_box(c: Vector3, s: Vector3, rot: Vector3, tex: Variant) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var pts: Array = []
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				pts.append(c + b * Vector3(x * s.x, y * s.y, z * s.z))
	solid(pts, tex)


## A course of sandbags from a to b (on the ground plane), bags about 0.6 m
## long, offset half a bag on odd courses.
func bag_course(a: Vector2, b: Vector2, z: float, course: int, depth: float = 0.45) -> void:
	var dir := (b - a)
	var length := dir.length()
	dir = dir / length
	var across := Vector2(-dir.y, dir.x)
	var count := maxi(1, int(round(length / 0.6)))
	var bag := length / count
	var shift := 0.5 if course % 2 == 1 else 0.0
	var start := -shift
	var i := 0
	while start < count - 0.01:
		var s0 := maxf(start, 0.0)
		var s1 := minf(start + 1.0, float(count))
		if s1 - s0 > 0.2:
			var p0 := a + dir * (s0 * bag + 0.02)
			var p1 := a + dir * (s1 * bag - 0.02)
			var pts: Array = []
			var h := 0.26 + 0.02 * float((i * 7 + course * 3) % 3)
			for p in [p0, p1]:
				for sgn in [-0.5, 0.5]:
					var q: Vector2 = p + across * depth * sgn
					pts.append(Vector3(q.x, q.y, z))
					pts.append(Vector3(q.x, q.y, z + h))
			solid(pts, SANDBAG)
		start += 1.0
		i += 1


# ── Features ─────────────────────────────────────────────────────────────────

## A crag you can climb: a slab of rock leans against a flat-topped shelf,
## an overwatch perch 4 m up, with the main mass rising behind it for cover.
func _rock_outcrop() -> void:
	rock(Vector3(3.0, 1.0, 2.2), Vector3(4.5, 6.0, 5.0), 11, STRATA, 18)
	rock(Vector3(-3.0, -3.0, 2.5), Vector3(3.2, 3.2, 3.5), 12, STRATA, 16, 4.25, 2.0)
	rock(Vector3(5.0, 6.5, 0.8), Vector3(3.0, 3.5, 2.6), 13, ROCK, 14)
	rock(Vector3(-3.5, 5.0, 0.3), Vector3(2.2, 2.0, 1.6), 14, ROCK, 12)
	rock(Vector3(7.0, -4.0, 0.2), Vector3(1.4, 1.6, 1.2), 15, ROCK, 12)
	rock(Vector3(-6.5, 1.5, 0.1), Vector3(1.0, 1.2, 0.9), 16, ROCK, 10)
	# The climb: a slab from the ground onto the shelf's flat top, about 30°.
	flight(-12.5, -4.25, -4.5, -1.75, -0.3, 4.25, "+x", 0.6, {"top": ROCK, "side": ROCK, "bottom": ROCK})


## A leaning spire of layered rock with fallen blocks round its foot.
func _rock_spire() -> void:
	var lean := Vector2(0.18, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var levels := [[-1.0, 2.3], [2.6, 2.0], [5.4, 1.7], [7.6, 1.3], [9.8, 1.0], [11.5, 0.6]]
	# Each segment is its own convex lump, shifted a little off the last one's
	# axis and cut from fewer, rougher points, so the column reads as weathered
	# rock with ledges rather than as stacked drums.
	for s in levels.size() - 1:
		var pts: Array = []
		var shift := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
		var sides := rng.randi_range(5, 7)
		for k in [s, s + 1]:
			var z: float = levels[k][0]
			var r: float = levels[k][1] * (1.0 if k == s else rng.randf_range(0.85, 1.05))
			for i in sides:
				var a := TAU * i / sides + rng.randf_range(-0.45, 0.45)
				var rr := r * rng.randf_range(0.62, 1.12)
				pts.append(Vector3(cos(a) * rr + lean.x * z + shift.x, sin(a) * rr + lean.y * z + shift.y, z + rng.randf_range(-0.25, 0.25)))
		solid(pts, STRATA, 4)
	rock(Vector3(2.6, -1.8, 0.2), Vector3(1.5, 1.3, 1.1), 22, ROCK, 12)
	rock(Vector3(-2.4, 2.2, 0.0), Vector3(1.2, 1.4, 0.9), 23, ROCK, 12)
	rock(Vector3(-1.2, -3.0, 0.0), Vector3(0.8, 0.9, 0.6), 24, ROCK, 10)


## A cliff edge 16 m wide and 5 m tall in layers, overhanging in places,
## flat on top. A talus ramp of broken rock climbs to the top at one end.
## Stand it against a slope, or use it to make a plateau's edge.
func _cliff_ledge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var layers := [[-0.6, 1.2], [1.2, 2.5], [2.5, 3.8], [3.8, 5.0]]
	for L in layers.size():
		var z0: float = layers[L][0]
		var z1: float = layers[L][1]
		for s in 4:
			var y0 := -8.0 + s * 4.0
			var y1 := y0 + 4.0
			var front := -3.0 + rng.randf_range(-0.9, 0.7) + L * 0.25
			var front_top := front + rng.randf_range(-0.4, 0.4)
			var pts := [
				Vector3(front, y0, z0), Vector3(front + rng.randf_range(-0.3, 0.3), y1, z0),
				Vector3(front_top, y0, z1), Vector3(front_top + rng.randf_range(-0.3, 0.3), y1, z1),
				Vector3(6.0, y0, z0), Vector3(6.0, y1, z0), Vector3(6.0, y0, z1), Vector3(6.0, y1, z1)]
			solid(pts, STRATA, 2)
	# Fallen blocks at the foot.
	rock(Vector3(-4.8, -5.0, 0.1), Vector3(1.3, 1.5, 1.0), 32, ROCK, 12)
	rock(Vector3(-4.2, 2.5, 0.0), Vector3(0.9, 1.1, 0.7), 33, ROCK, 10)
	rock(Vector3(-5.5, 5.8, 0.0), Vector3(0.6, 0.7, 0.5), 34, ROCK, 10)
	# Talus ramp up the +Y end, about 29°, onto a landing that laps over the
	# top so there is no seam to catch a foot.
	ramp(-1.0, 8.5, 5.5, 17.5, 0.0, 0.0, 5.0, "-y", {"top": ROCK, "side": ROCK, "bottom": ROCK})
	box(Vector3(-1.0, 7.0, 3.8), Vector3(5.5, 8.5, 5.0), {"top": ROCK, "side": ROCK, "bottom": ROCK})


## A field of boulders, big and small, over about 24 m square.
func _boulder_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var placed: Array = []
	var tries := 0
	while placed.size() < 13 and tries < 400:
		tries += 1
		var size := rng.randf_range(0.5, 2.4) if placed.size() > 2 else rng.randf_range(2.0, 2.6)
		var p := Vector2(rng.randf_range(-11.0, 11.0), rng.randf_range(-11.0, 11.0))
		var clear := true
		for q: Vector3 in placed:
			if p.distance_to(Vector2(q.x, q.y)) < q.z + size + 0.8:
				clear = false
				break
		if not clear:
			continue
		placed.append(Vector3(p.x, p.y, size))
		var r := Vector3(size * rng.randf_range(0.8, 1.2), size * rng.randf_range(0.8, 1.2), size * rng.randf_range(0.55, 0.85))
		rock(Vector3(p.x, p.y, r.z * 0.3), r, 400 + placed.size(), ROCK if size < 1.8 else STRATA, 12 if size < 1.2 else 14)


## An earth berm 14 m long and 2 m high with a firing step behind it.
func _berm() -> void:
	plinth(-0.75, -5.75, 0.75, 5.75, -0.3, 2.0, 1.75, EARTH)
	plinth(1.4, -5.0, 2.5, 5.0, -0.3, 0.8, 0.5, EARTH, {"-x": 0.0})
	# Lumps along the crest so it is not a perfect prism.
	rock(Vector3(0.0, -3.0, 1.9), Vector3(0.9, 1.6, 0.35), 51, DIRT, 10)
	rock(Vector3(0.1, 2.5, 1.85), Vector3(0.8, 1.8, 0.35), 52, DIRT, 10)


## Lining for 8 m of trench: plank walls on posts, a duckboard floor and a
## sandbag parapet on each lip. Made for a TerrainPath TRENCH 4 m wide and
## 2 m deep: place it on the trench's centreline at ground height.
func _trench_revetment() -> void:
	for side in [-1.0, 1.0]:
		var x0: float = side * 1.6
		box(Vector3(x0 - 0.05, -4.0, -2.0), Vector3(x0 + 0.05, 4.0, 0.2), PLANK)
		for y in [-3.9, -2.0, 0.0, 2.0, 3.9]:
			box(Vector3(x0 + side * 0.05, y - 0.08, -2.2), Vector3(x0 + side * 0.2, y + 0.08, 0.45), WOOD_DARK)
		for course in 2:
			bag_course(Vector2(side * 2.05, -4.0), Vector2(side * 2.05, 4.0), 0.0 + course * 0.28, course, 0.5)
	box(Vector3(-1.1, -3.9, -1.95), Vector3(1.1, 3.9, -1.87), WOOD)
	for y in [-3.2, -1.0, 1.2, 3.4]:
		box(Vector3(-1.2, y - 0.1, -2.0), Vector3(1.2, y + 0.1, -1.95), WOOD_DARK)


## A raised crater rim 12 m across: heaved earth and broken slabs, scorched.
func _crater_rim() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.12, 0.12)
		var rad := 5.6 + rng.randf_range(-0.4, 0.4)
		var c := Vector3(cos(a) * rad, sin(a) * rad, -0.2)
		# Long along the rim, narrow across it.
		var along := Vector3(-sin(a), cos(a), 0.0)
		var out := Vector3(cos(a), sin(a), 0.0)
		var pts: Array = []
		var h := rng.randf_range(0.6, 1.2)
		for k in 10:
			var u := rng.randf_range(-1.0, 1.0)
			var v := rng.randf_range(-1.0, 1.0)
			var w := rng.randf_range(0.0, 1.0)
			pts.append(c + along * u * 1.9 + out * v * 1.1 + Vector3(0, 0, w * h * (1.0 - absf(v) * 0.5)))
		pts.append(c + along * 1.9 + Vector3(0, 0, -0.1))
		pts.append(c - along * 1.9 + Vector3(0, 0, -0.1))
		solid(pts, DIRT, 4)
	for i in 6:
		var a := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(2.0, 8.5)
		tipped_box(Vector3(cos(a) * rad, sin(a) * rad, 0.15), Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.5, 1.0), 0.3),
				Vector3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(0, 180)), SCORCH if i % 2 == 0 else RUBBLE)


## A six-sided concrete pillbox, half dug in, with firing slits and a blast
## wall at its door. An earth ramp climbs to its roof.
func _pillbox() -> void:
	cylinder(Vector3(0, 0, -0.6), 3.5, 2.8, 6, CONCRETE)
	cylinder(Vector3(0, 0, 2.2), 3.8, 0.4, 6, {"top": DECK, "side": FRAME, "bottom": FRAME})
	# Slits on the three front faces (the faces between -60° and +60° of -X).
	for k in [-1, 0, 1]:
		var a: float = PI + k * TAU / 6.0
		var n := Vector3(cos(a), sin(a), 0.0)
		var along := Vector3(-sin(a), cos(a), 0.0)
		var face := n * 3.5 * cos(PI / 6.0)
		var pts: Array = []
		for s in [-0.7, 0.7]:
			for z in [1.2, 1.5]:
				pts.append(face + along * s + n * 0.02 + Vector3(0, 0, z))
				pts.append(face + along * s - n * 0.3 + Vector3(0, 0, z))
		solid(pts, SHUTTER)
	# Door and blast wall on the back (+X) face.
	var back := Vector3(3.5 * cos(PI / 6.0), 0, 0)
	box(back + Vector3(-0.2, -0.6, -0.1), back + Vector3(0.02, 0.6, 1.9), SHUTTER)
	box(back + Vector3(1.2, -2.0, -0.1), back + Vector3(1.6, 2.0, 1.8), CONCRETE)
	# Earth ramp to the roof along the -Y side, about 26°, onto a landing
	# under the roof's edge (the hexagon's point would otherwise stand
	# proud of the ramp's top), and earth banked on.
	ramp(-1.0, -9.7, 1.0, -3.9, -0.2, -0.2, 2.6, "+y", EARTH)
	box(Vector3(-1.0, -3.9, -0.2), Vector3(1.0, -2.8, 2.6), EARTH)
	rock(Vector3(-2.6, 2.2, -0.1), Vector3(1.8, 1.6, 1.2), 71, DIRT, 12)
	rock(Vector3(-3.0, -1.2, -0.1), Vector3(1.4, 2.0, 1.1), 72, DIRT, 12)


## A sandbagged lookout 6 m up on splayed metal legs, roofed, with a
## ramp on posts up to it.
func _watchtower() -> void:
	var legs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for l: Vector2 in legs:
		beam(Vector3(l.x * 2.3, l.y * 2.3, -0.3), Vector3(l.x * 1.8, l.y * 1.8, 6.0), 0.3, RUST)
		post(l.x * 1.8, l.y * 1.8, 6.0, 8.2, 0.15, RUST)
	for i in 4:
		var a: Vector2 = legs[i]
		var b: Vector2 = legs[(i + 1) % 4]
		beam(Vector3(a.x * 2.2, a.y * 2.2, 0.6), Vector3(b.x * 1.95, b.y * 1.95, 4.4), 0.12, RUST)
		beam(Vector3(b.x * 2.2, b.y * 2.2, 0.6), Vector3(a.x * 1.95, a.y * 1.95, 4.4), 0.12, RUST)
	box(Vector3(-2.2, -2.2, 5.7), Vector3(2.2, 2.2, 6.0), SLAB)
	box(Vector3(-2.4, -2.4, 8.2), Vector3(2.4, 2.4, 8.4), RUST_PANEL)
	for course in 3:
		var z := 6.0 + course * 0.28
		bag_course(Vector2(-1.95, -1.95), Vector2(1.95, -1.95), z, course, 0.4)
		bag_course(Vector2(1.95, -1.95), Vector2(1.95, 1.95), z, course, 0.4)
		bag_course(Vector2(1.95, 1.95), Vector2(-1.95, 1.95), z, course, 0.4)
		bag_course(Vector2(-1.95, 1.95), Vector2(-1.95, 0.5), z, course, 0.4)
	# The ramp arrives on the -X side through the gap at y -1.95..0.5.
	flight(-12.5, -1.75, -2.2, 0.25, 0.0, 6.0, "+x", 0.3, SLAB)
	for x in [-10.0, -7.0, -4.2]:
		var zb: float = 6.0 * (x + 12.5) / 10.3 - 0.3
		post(x, -1.6, 0.0, zb + 0.05, 0.2, RUST)
		post(x, 0.1, 0.0, zb + 0.05, 0.2, RUST)
	rail("y", -1.7, -12.5, -2.2, 0.0, 6.0)
	rail("y", 0.2, -12.5, -2.2, 0.0, 6.0)


## Three shipping containers, two side by side and one stacked across them.
func _container_stack() -> void:
	_container(Vector3(-1.3, 0, 0), GREEN)
	_container(Vector3(1.3, 0.6, 0), BLUE)
	_container(Vector3(0.0, -2.8, 2.6), RUST_PANEL)


## One 12.2 × 2.44 × 2.6 m container with its doors at +Y.
func _container(c: Vector3, tex: String) -> void:
	box(c + Vector3(-1.22, -6.1, 0.0), c + Vector3(1.22, 6.1, 2.6), tex)
	for x in [-1.22, 1.22]:
		for z in [0.0, 2.45]:
			box(c + Vector3(x - 0.08 * signf(x), -6.1, z), c + Vector3(x + 0.04 * signf(x), 6.1, z + 0.15), RUST)
	box(c + Vector3(-1.15, 6.1, 0.1), c + Vector3(1.15, 6.16, 2.5), RUST_PANEL)
	for x in [-0.5, 0.5]:
		box(c + Vector3(x - 0.03, 6.16, 0.3), c + Vector3(x + 0.03, 6.22, 2.3), METAL)


## A lattice power pylon about 21 m tall: a landmark and a sniper's dream.
func _power_pylon() -> void:
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var tiers := [[-0.4, 3.2], [6.0, 2.3], [12.0, 1.5], [16.5, 1.0], [20.0, 0.6]]
	for t in tiers.size() - 1:
		var z0: float = tiers[t][0]
		var w0: float = tiers[t][1]
		var z1: float = tiers[t + 1][0]
		var w1: float = tiers[t + 1][1]
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			beam(Vector3(a.x * w0, a.y * w0, z0), Vector3(a.x * w1, a.y * w1, z1), 0.28, METAL)
			if t < 3:
				beam(Vector3(a.x * w0, a.y * w0, z0 + 0.3), Vector3(b.x * w1, b.y * w1, z1 - 0.2), 0.12, METAL)
				beam(Vector3(b.x * w0, b.y * w0, z0 + 0.3), Vector3(a.x * w1, a.y * w1, z1 - 0.2), 0.12, METAL)
	for arm in [[16.5, 4.8], [19.2, 3.6]]:
		var z: float = arm[0]
		var half: float = arm[1]
		beam(Vector3(0, -half, z), Vector3(0, half, z), 0.3, METAL)
		beam(Vector3(0, -half, z + 0.1), Vector3(0, -1.0, z + 1.4), 0.12, METAL)
		beam(Vector3(0, half, z + 0.1), Vector3(0, 1.0, z + 1.4), 0.12, METAL)
		for y in [-half + 0.3, half - 0.3]:
			cylinder(Vector3(0, y, z - 1.0), 0.12, 0.95, 6, RUBBER)
	solid([Vector3(-0.6, -0.6, 20.0), Vector3(0.6, -0.6, 20.0), Vector3(0.6, 0.6, 20.0), Vector3(-0.6, 0.6, 20.0), Vector3(0, 0, 21.3)], METAL)
	for c: Vector2 in corners:
		box(Vector3(c.x * 3.2 - 0.5, c.y * 3.2 - 0.5, -0.5), Vector3(c.x * 3.2 + 0.5, c.y * 3.2 + 0.5, 0.3), CONCRETE)


## Two fuel tanks inside a low concrete bund, joined by pipes and a catwalk.
func _fuel_tanks() -> void:
	for y in [-3.4, 3.4]:
		cylinder(Vector3(0, y, 0.0), 2.6, 6.0, 10, RUST_PANEL)
		cylinder(Vector3(0, y, 6.0), 2.6, 0.9, 10, RUST, 0.6)
		box(Vector3(-2.9, y - 0.4, 0.0), Vector3(-2.5, y + 0.4, 1.4), RUST)
	box(Vector3(-0.8, -3.4, 6.3), Vector3(0.8, 3.4, 6.5), SLAB)
	for x in [-0.8, 0.8]:
		rail("x", x, -1.0, 1.0, 6.5, 6.5)
	log_x(Vector3(-3.8, 0.0, 0.5), 0.25, 9.0, 8, RUST, "y")
	log_x(Vector3(-3.8, 0.0, 1.2), 0.18, 9.0, 8, METAL, "y")
	for y in [-3.4, 3.4]:
		box(Vector3(-3.9, y - 0.2, 0.0), Vector3(-2.7, y + 0.2, 1.6), METAL)
	wall_run("x", Vector2(-5.0, -4.6), -7.0, 7.0, -0.3, 1.0, [[-1.0, 1.0]], CONCRETE)
	wall_run("x", Vector2(3.6, 4.0), -7.0, 7.0, -0.3, 1.0, [], CONCRETE)
	wall_run("y", Vector2(-7.0, -6.6), -4.6, 3.6, -0.3, 1.0, [], CONCRETE)
	wall_run("y", Vector2(6.6, 7.0), -4.6, 3.6, -0.3, 1.0, [], CONCRETE)


# ── Props ────────────────────────────────────────────────────────────────────

func _boulder_a() -> void:
	rock(Vector3(0, 0, 0.18), Vector3(0.75, 0.65, 0.55), 101, ROCK, 12)


func _boulder_b() -> void:
	rock(Vector3(0, 0, 0.25), Vector3(1.5, 0.85, 0.75), 102, ROCK, 14)


func _boulder_c() -> void:
	rock(Vector3(0, 0, 0.45), Vector3(1.9, 1.7, 1.55), 103, STRATA, 16)


## Three flat slabs of rock, tilted a little: stepping stones or a rock shelf.
func _rock_slabs() -> void:
	rock(Vector3(-0.9, -0.5, 0.0), Vector3(1.3, 1.0, 0.45), 111, ROCK, 12, 0.3)
	rock(Vector3(1.0, 0.4, -0.05), Vector3(1.1, 0.9, 0.4), 112, ROCK, 12, 0.22)
	rock(Vector3(0.1, 1.6, -0.1), Vector3(0.8, 0.7, 0.35), 113, ROCK, 10, 0.12)


## A low earth hump, knee-high: enough to crouch behind.
func _dirt_mound() -> void:
	mound(Vector3.ZERO, 2.3, 1.7, 0.8, 121, DIRT)


## A low dome of earth: rings of jittered points narrowing to the crest, so it
## comes out rounded rather than as a random flat hull, which can fold into a
## wedge with one steep face.
func mound(c: Vector3, rx: float, ry: float, h: float, seed: int, tex: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts: Array = []
	for ring in [[-0.3, 1.0], [0.45, 0.8], [0.8, 0.5], [1.0, 0.15]]:
		var t: float = ring[0]
		var k: float = ring[1]
		var count := 9 if k > 0.3 else 4
		for i in count:
			var a := TAU * i / count + rng.randf_range(-0.25, 0.25)
			var j := rng.randf_range(0.92, 1.05)
			pts.append(c + Vector3(cos(a) * rx * k * j, sin(a) * ry * k * j, t * h if t > 0.0 else t))
	solid(pts, tex, 4)


## Broken concrete heaped up with rebar sticking out of it.
func _rubble_pile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 131
	rock(Vector3(0, 0, -0.3), Vector3(2.0, 1.8, 1.0), 132, RUBBLE, 12)
	for i in 11:
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.3, 2.4)
		var z := maxf(0.0, 0.7 * (1.0 - d / 2.4))
		tipped_box(Vector3(cos(a) * d, sin(a) * d, z + 0.1), Vector3(rng.randf_range(0.4, 1.2), rng.randf_range(0.3, 0.8), rng.randf_range(0.15, 0.4)),
				Vector3(rng.randf_range(-25, 25), rng.randf_range(-25, 25), rng.randf_range(0, 180)), [FRAME, RUBBLE, SCORCH, CONCRETE][i % 4])
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		var base := Vector3(cos(a) * 0.8, sin(a) * 0.8, 0.4)
		beam(base, base + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8), rng.randf_range(0.9, 1.6)), 0.05, RUST)


## A 3 m jersey barrier.
## The profile is concave where the shallow lower slope meets the steep upper
## face, and a brush must be convex: two brushes, split at that line.
func _jersey_barrier() -> void:
	_extrude_y([Vector2(-0.3, -0.05), Vector2(0.3, -0.05), Vector2(0.3, 0.08), Vector2(0.15, 0.28),
			Vector2(-0.15, 0.28), Vector2(-0.3, 0.08)], -1.5, 1.5, FRAME)
	_extrude_y([Vector2(-0.15, 0.28), Vector2(0.15, 0.28), Vector2(0.08, 0.81), Vector2(-0.08, 0.81)], -1.5, 1.5, FRAME)


## A convex (x, z) outline pushed along Y from y0 to y1.
func _extrude_y(profile: Array, y0: float, y1: float, tex: Variant) -> void:
	var v: Array = []
	for y in [y0, y1]:
		for q: Vector2 in profile:
			v.append(Vector3(q.x, y, q.y))
	var n := profile.size()
	var faces: Array = [range(n), range(n, n * 2)]
	for i in n:
		faces.append([i, (i + 1) % n, n + (i + 1) % n, n + i])
	brush(v, faces, tex)


## Three big concrete blocks, one knocked over.
func _concrete_blocks() -> void:
	box(Vector3(-1.6, -0.75, -0.1), Vector3(-0.1, 0.75, 1.4), CONCRETE)
	box(Vector3(0.1, -0.7, -0.1), Vector3(1.6, 0.8, 1.4), FRAME)
	tipped_box(Vector3(0.2, 1.95, 0.55), Vector3(1.5, 1.5, 1.5), Vector3(28, 0, 12), CONCRETE)


## Four metres of sandbag wall, four courses high.
func _sandbag_wall() -> void:
	for course in 4:
		bag_course(Vector2(0, -2.0), Vector2(0, 2.0), -0.05 + course * 0.27, course, 0.5)


## A U-shaped sandbag fighting position, open at the back (+X).
func _sandbag_nest() -> void:
	for course in 3:
		var z := -0.05 + course * 0.27
		bag_course(Vector2(-1.5, -1.6), Vector2(-1.5, 1.6), z, course, 0.5)
		bag_course(Vector2(-1.1, -1.9), Vector2(1.4, -1.9), z, course, 0.5)
		bag_course(Vector2(-1.1, 1.9), Vector2(1.4, 1.9), z, course, 0.5)


## Four earth-filled hesco baskets in a row.
func _hesco_row() -> void:
	for i in 4:
		var y := -1.65 + i * 1.1
		box(Vector3(-0.53, y - 0.53, -0.1), Vector3(0.53, y + 0.53, 1.3), {"top": DIRT, "side": SANDBAG, "bottom": SANDBAG})
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			post(c.x * 0.53, y + c.y * 0.53, -0.1, 1.33, 0.05, METAL)


## A Czech hedgehog: three steel bars crossed at right angles, standing on
## three of their ends.
func _tank_trap() -> void:
	# The bars run along the axes of a cube whose body diagonal is vertical.
	var b := Basis(Vector3(1, 1, 1).cross(Vector3(0, 0, 1)).normalized(), acos(1.0 / sqrt(3.0)))
	var centre := Vector3(0, 0, 0.9 / sqrt(3.0) + 0.02)
	for axis in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
		var d: Vector3 = b * axis
		beam(centre - d * 0.9, centre + d * 0.9, 0.14, RUST)


## Oil drums: three standing, one on its side.
func _barrels() -> void:
	cylinder(Vector3(-0.35, -0.3, -0.02), 0.3, 0.9, 8, RUST)
	cylinder(Vector3(0.3, -0.35, -0.02), 0.3, 0.9, 8, GREEN)
	cylinder(Vector3(-0.05, 0.3, -0.02), 0.3, 0.9, 8, BLUE)
	log_x(Vector3(0.95, 0.75, -0.02), 0.3, 0.9, 8, RUST, "y")


## Crates stacked on a pallet, and one beside it.
func _crates() -> void:
	box(Vector3(-0.6, -0.5, 0.0), Vector3(0.6, 0.5, 0.14), WOOD)
	box(Vector3(-0.55, -0.45, 0.14), Vector3(0.45, 0.45, 1.14), CRATE)
	tipped_box(Vector3(-0.05, 0.0, 1.54), Vector3(0.8, 0.8, 0.8), Vector3(0, 0, 14), CRATE)
	tipped_box(Vector3(0.95, 0.9, 0.35), Vector3(0.7, 0.7, 0.7), Vector3(0, 0, -21), CRATE)


## A burnt-out car: body and cabin rusted through, sitting on its rims.
func _car_wreck() -> void:
	_hexa([Vector2(-0.9, -2.2), Vector2(0.9, -2.2), Vector2(0.9, 2.2), Vector2(-0.9, 2.2)],
			[0.25, 0.25, 0.25, 0.25], [0.95, 0.95, 0.85, 0.85], RUST)
	solid([Vector3(-0.8, -1.1, 0.9), Vector3(0.8, -1.1, 0.9), Vector3(0.8, 1.2, 0.9), Vector3(-0.8, 1.2, 0.9),
			Vector3(-0.65, -0.6, 1.5), Vector3(0.65, -0.6, 1.5), Vector3(0.65, 0.8, 1.5), Vector3(-0.65, 0.8, 1.5)], {"top": SCORCH, "side": SHUTTER, "bottom": RUST})
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		log_x(Vector3(c.x * 0.82, c.y * 1.4, -0.1), 0.33, 0.24, 8, RUBBER, "x")


## A fallen war robot, broken open: torso on its side, head torn off, one
## arm flung out, legs buckled.
func _robot_wreck() -> void:
	tipped_box(Vector3(0.0, 0.0, 0.45), Vector3(1.3, 0.9, 1.6), Vector3(90, 0, 12), {"top": METAL, "side": SHUTTER, "bottom": RUST})
	tipped_box(Vector3(0.1, 1.2, 0.55), Vector3(0.9, 0.5, 0.35), Vector3(80, 0, 8), RUST)
	tipped_box(Vector3(1.4, 1.7, 0.25), Vector3(0.55, 0.5, 0.45), Vector3(10, 25, 40), METAL)
	beam(Vector3(-0.4, 0.7, 0.6), Vector3(-1.8, 1.6, 0.3), 0.22, RUST)
	beam(Vector3(-1.8, 1.6, 0.3), Vector3(-2.6, 1.2, 0.15), 0.2, METAL)
	tipped_box(Vector3(-2.8, 1.15, 0.15), Vector3(0.45, 0.3, 0.25), Vector3(0, 0, 30), SHUTTER)
	for s in [-0.3, 0.35]:
		beam(Vector3(s, -0.75, 0.45), Vector3(s + 0.4, -1.8, 0.35), 0.3, RUST)
		beam(Vector3(s + 0.4, -1.8, 0.35), Vector3(s - 0.1, -2.7, 0.2), 0.26, METAL)
		box(Vector3(s - 0.35, -3.05, -0.05), Vector3(s + 0.15, -2.55, 0.25), SHUTTER)
	for i in 3:
		beam(Vector3(0.2 + i * 0.12, 0.9, 0.9), Vector3(0.5 + i * 0.25, 1.6, 0.1), 0.05, RUBBER)


## A street lamp, 7 m, its arm reaching over the road on the -X side.
func _lamp_post() -> void:
	box(Vector3(-0.25, -0.25, -0.2), Vector3(0.25, 0.25, 0.4), CONCRETE)
	cylinder(Vector3(0, 0, 0.4), 0.11, 6.6, 8, METAL, 0.08)
	beam(Vector3(0, 0, 6.8), Vector3(-1.6, 0, 7.1), 0.09, METAL)
	box(Vector3(-2.05, -0.16, 6.95), Vector3(-1.45, 0.16, 7.15), SHUTTER)


## A wooden telegraph pole with a cross arm and insulators.
func _power_pole() -> void:
	cylinder(Vector3(0, 0, -0.5), 0.16, 9.5, 8, WOOD_DARK, 0.12)
	box(Vector3(-0.08, -1.1, 8.1), Vector3(0.08, 1.1, 8.25), WOOD_DARK)
	beam(Vector3(0, -0.9, 8.1), Vector3(0, -0.1, 7.5), 0.06, METAL)
	beam(Vector3(0, 0.9, 8.1), Vector3(0, 0.1, 7.5), 0.06, METAL)
	for y in [-0.95, 0.0, 0.95]:
		cylinder(Vector3(0, y, 8.25), 0.05, 0.18, 6, RUBBER)


## Concrete drainage pipes: two lying side by side, one on top.
func _concrete_pipes() -> void:
	for c in [Vector3(-0.85, 0.0, 0.0), Vector3(0.85, 0.2, 0.0), Vector3(0.0, 0.1, 1.45)]:
		_pipe(c, 0.8, 0.62, 2.4)


## A hollow pipe lying along Y: eight wedge segments round the bore.
func _pipe(c: Vector3, outer: float, inner: float, length: float) -> void:
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var pts: Array = []
		for y in [-length * 0.5, length * 0.5]:
			for a in [a0, a1]:
				for r in [inner, outer]:
					pts.append(Vector3(c.x + cos(a) * r, c.y + y, c.z + outer + sin(a) * r))
		solid(pts, FRAME)
