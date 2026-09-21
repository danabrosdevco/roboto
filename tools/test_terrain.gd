extends SceneTree

# ─────────────────────────────────────────────
# TERRAIN — the generator, the meshes, the collision and the template level.
#
# The rule everything here protects: WHAT YOU SEE IS WHAT YOU STAND ON. The
# render mesh, the collision and TerrainData.height_at_local() must agree
# everywhere, or props snapped in the editor float, and squads walk through
# ridges they can see. The collision checks cast real rays against real
# HeightMapShape3D tiles under whatever physics engine the project runs (Jolt),
# so a triangulation or orientation mismatch shows up as a number, not a hunch.
#
# Also: same recipe → same heights (levels are authored on top of them), stamps
# and paths do exactly what they say, and the template level loads playable.
#
# Scripts are reached by preload, not class_name, so this runs before the editor
# has ever scanned the new classes.
# ─────────────────────────────────────────────

const Recipe := preload("res://Env/terrain/terrain_recipe.gd")
const Data := preload("res://Env/terrain/terrain_data.gd")
const Generator := preload("res://Env/terrain/terrain_generator.gd")
const MeshBuilder := preload("res://Env/terrain/terrain_mesh_builder.gd")
const TerrainScript := preload("res://Env/terrain/generated_terrain.gd")
const StampScript := preload("res://Env/terrain/terrain_stamp.gd")
const PathScript := preload("res://Env/terrain/terrain_path.gd")
const ScatterScript := preload("res://Env/terrain/terrain_scatter.gd")
const LayerScript := preload("res://Env/terrain/terrain_scatter_layer.gd")
const Sketch := preload("res://Env/terrain/terrain_sketch.gd")
const TEMPLATE := "res://maps/terrain_template_level.tscn"
const TMP_DATA := "user://test_terrain_roundtrip.res"
## A script error inside a check ends that coroutine without reaching quit(),
## and a headless SceneTree then idles for ever — test.sh has no timeout of
## its own and would hang. The watchdog turns that into a loud failure.
const WATCHDOG_S := 300

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


## A small, quick recipe: 256 × 128 m at 2 m, everything switched on.
func _small_recipe() -> Recipe:
	var r := Recipe.new()
	r.size_x = 256.0
	r.size_z = 128.0
	r.cell_size = 2.0
	r.random_seed = 5
	r.border_width = 40.0
	r.border_height = 20.0
	r.floor_width = 50.0
	r.floor_shoulder = 20.0
	r.crater_count = 8
	r.crater_radius_max = 6.0
	r.hydraulic_strength = 0.4
	r.terrace_step = 3.0
	r.terrace_strength = 0.4
	return r


## Flat OPEN ground with no mountains, craters or erosion: modifiers land on a
## known surface.
func _flat_recipe() -> Recipe:
	var r := Recipe.new()
	r.size_x = 128.0
	r.size_z = 128.0
	r.cell_size = 1.0
	r.layout = Recipe.Layout.OPEN
	r.border_sides = 0
	r.hills_height = 3.0
	r.ridge_height = 0.0
	r.detail_height = 0.3
	r.crater_count = 0
	r.thermal_passes = 0
	r.hydraulic_strength = 0.0
	r.smooth_passes = 0
	return r


func _stamp(shape: int, centre: Vector2, y: float, radius: float, falloff: float, extra: Dictionary = {}) -> Dictionary:
	var m := {"type": "stamp", "source": "test", "shape": shape, "footprint": Generator.FOOTPRINT_CIRCLE,
			"centre": centre, "y": y, "radius": radius, "half_size": Vector2(radius, radius),
			"axis_x": Vector2(1, 0), "axis_z": Vector2(0, 1), "falloff": falloff, "amount": 4.0,
			"strength": 1.0, "paint": Generator.PAINT_PAD}
	m.merge(extra, true)
	return m


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL  watchdog: the suite did not finish within %d s — a check probably crashed (see SCRIPT ERROR above)" % WATCHDOG_S)
		quit(2))
	await process_frame
	_test_enum_mirrors()
	_test_determinism()
	_test_floor_at_zero()
	_test_stamps()
	_test_paths()
	_test_cache()
	_test_sampling_matches_triangles()
	_test_meshes()
	_test_roundtrip()
	_test_sketch()
	await _test_collision_matches_surface()
	await _test_scatter()
	await _test_sketch_terrain_node()
	await _test_template_level()
	print("")
	print("ALL TERRAIN CHECKS PASS" if _fails == 0 else "%d TERRAIN CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# The node enums are stored as ints in scenes; the generator reads those ints.
func _test_enum_mirrors() -> void:
	_check("stamp shapes mirror the generator",
			StampScript.Shape.FLATTEN == Generator.STAMP_FLATTEN and StampScript.Shape.RAISE == Generator.STAMP_RAISE
			and StampScript.Shape.LOWER == Generator.STAMP_LOWER and StampScript.Shape.CRATER == Generator.STAMP_CRATER)
	_check("stamp footprints mirror the generator",
			StampScript.Footprint.CIRCLE == Generator.FOOTPRINT_CIRCLE and StampScript.Footprint.RECTANGLE == Generator.FOOTPRINT_RECT)
	_check("stamp paints mirror the generator",
			StampScript.Paint.NONE == Generator.PAINT_NONE and StampScript.Paint.PAD == Generator.PAINT_PAD
			and StampScript.Paint.ROAD == Generator.PAINT_ROAD and StampScript.Paint.SCORCH == Generator.PAINT_SCORCH
			and StampScript.Paint.RUBBLE == Generator.PAINT_RUBBLE)
	_check("path modes mirror the generator",
			PathScript.Mode.ROAD == Generator.PATH_ROAD and PathScript.Mode.TRENCH == Generator.PATH_TRENCH
			and PathScript.Mode.RIVERBED == Generator.PATH_RIVERBED and PathScript.Mode.BERM == Generator.PATH_BERM)


func _test_determinism() -> void:
	var a: Data = Generator.generate(_small_recipe())
	var b: Data = Generator.generate(_small_recipe())
	_check("small recipe generates", a != null and a.is_valid("determinism"))
	if a == null:
		return
	_check("grid snaps to whole chunks", a.cells_x == 128 and a.cells_z == 64, "%d × %d" % [a.cells_x, a.cells_z])
	_check("same recipe → identical heights", a.heights == b.heights)
	_check("same recipe → identical paint", a.control == b.control and a.zone == b.zone)
	var finite := true
	for v in a.heights:
		if is_nan(v) or is_inf(v):
			finite = false
			break
	_check("every height is finite", finite)
	_check("min/max bracket the heights", a.min_height < a.max_height)
	var r := _small_recipe()
	r.random_seed = 6
	var c: Data = Generator.generate(r)
	_check("a different seed → different heights", c.heights != a.heights)
	_check("LOD errors: one per chunk per LOD, LOD0 exact",
			a.lod_errors.size() == a.chunks_x() * a.chunks_z() * a.lod_count and a.lod_errors[0] == 0.0)


func _test_floor_at_zero() -> void:
	var d: Data = Generator.generate(_flat_recipe())
	var total := 0.0
	for v in d.heights:
		total += v
	var mean := total / d.heights.size()
	_check("floor_at_zero centres open ground on y = 0", absf(mean) < 0.001, "mean %.5f" % mean)


func _test_stamps() -> void:
	var base: Data = Generator.generate(_flat_recipe())
	var flat: Data = Generator.generate(_flat_recipe(), [_stamp(Generator.STAMP_FLATTEN, Vector2(10, -6), 3.25, 8.0, 6.0)])
	var level := true
	for p in [Vector2(10, -6), Vector2(17, -6), Vector2(10, 1.5), Vector2(4, -10)]:
		if absf(flat.height_at_local(p.x, p.y) - 3.25) > 0.0005:
			level = false
	_check("FLATTEN levels its whole footprint to its own Y", level)
	var untouched := true
	for p in [Vector2(-40, -40), Vector2(40, 30), Vector2(10 + 8 + 6 + 2.5, -6)]:
		if absf(flat.height_at_local(p.x, p.y) - base.height_at_local(p.x, p.y)) > 0.0001:
			untouched = false
	_check("FLATTEN leaves ground beyond radius + falloff alone", untouched)
	_check("FLATTEN paints its pad", flat.control_at_local(10, -6).b > 0.99)

	# A 30°-turned rectangle: flat along its own axes, not the world's.
	var ax := Vector2(cos(deg_to_rad(30.0)), -sin(deg_to_rad(30.0)))
	var az := Vector2(-ax.y, ax.x)
	var rect: Data = Generator.generate(_flat_recipe(), [_stamp(Generator.STAMP_FLATTEN, Vector2.ZERO, -2.0, 1.0, 0.0,
			{"footprint": Generator.FOOTPRINT_RECT, "half_size": Vector2(20, 6), "axis_x": ax, "axis_z": az})])
	var along := ax * 18.0
	var across_out := az * 9.0
	_check("rotated RECTANGLE is flat along its long axis",
			absf(rect.height_at_local(along.x, along.y) - -2.0) < 0.0005)
	_check("rotated RECTANGLE stops at its short side",
			absf(rect.height_at_local(across_out.x, across_out.y) - base.height_at_local(across_out.x, across_out.y)) < 0.0001)

	var dug: Data = Generator.generate(_flat_recipe(), [_stamp(Generator.STAMP_CRATER, Vector2(-20, 20), 0.0, 10.0, 0.0,
			{"amount": 4.0, "paint": Generator.PAINT_SCORCH})])
	var drop := base.height_at_local(-20, 20) - dug.height_at_local(-20, 20)
	_check("CRATER digs its depth at the centre", absf(drop - 4.0) < 0.05, "dropped %.2f m" % drop)
	_check("CRATER raises a rim", dug.height_at_local(-10, 20) > base.height_at_local(-10, 20) + 0.5)
	_check("CRATER scorches its bowl", dug.control_at_local(-20, 20).g > 0.9)

	var both: Data = Generator.generate(_flat_recipe(), [
			_stamp(Generator.STAMP_FLATTEN, Vector2(0, 0), 1.0, 10.0, 0.0),
			_stamp(Generator.STAMP_FLATTEN, Vector2(8, 0), 5.0, 6.0, 0.0)])
	_check("where stamps overlap, the later one wins", absf(both.height_at_local(6, 0) - 5.0) < 0.0005)


func _test_paths() -> void:
	var base: Data = Generator.generate(_flat_recipe())
	var line := PackedVector3Array([Vector3(-50, 5, 0), Vector3(50, 5, 0)])
	var road: Data = Generator.generate(_flat_recipe(), [{"type": "path", "source": "test", "mode": Generator.PATH_ROAD,
			"points": line, "width": 8.0, "falloff": 4.0, "depth": 0.0, "follow_terrain": false, "smoothing": 0.0, "paint": true}])
	var on_line := true
	for x in [-40.0, -3.0, 0.0, 17.0, 45.0]:
		if absf(road.height_at_local(x, 0.0) - 5.0) > 0.0005 or absf(road.height_at_local(x, 3.5) - 5.0) > 0.0005:
			on_line = false
	_check("ROAD with its own heights levels its bed to the curve", on_line)
	_check("ROAD paints gravel on its bed", road.control_at_local(0, 0).r > 0.99)
	_check("ROAD leaves ground beyond its banks alone",
			absf(road.height_at_local(0, 20) - base.height_at_local(0, 20)) < 0.0001)

	# Densely sampled, as TerrainPath hands them over: with follow_terrain the
	# profile is read at each point, so two endpoints alone would just be a line.
	var dense := PackedVector3Array()
	for z in range(-50, 51):
		dense.append(Vector3(0, 0, z))
	var trench: Data = Generator.generate(_flat_recipe(), [{"type": "path", "source": "test", "mode": Generator.PATH_TRENCH,
			"points": dense, "width": 3.0, "falloff": 1.0,
			"depth": 2.0, "follow_terrain": true, "smoothing": 0.0, "paint": true}])
	var never_raised := true
	for k in trench.heights.size():
		if trench.heights[k] > base.heights[k] + 0.0001:
			never_raised = false
			break
	_check("TRENCH only ever digs", never_raised)
	var deep := base.height_at_local(0, 10) - trench.height_at_local(0, 10)
	_check("TRENCH floor sits about its depth down", absf(deep - 2.0) < 0.35, "%.2f m" % deep)


func _test_cache() -> void:
	var cache := {}
	var mods := [_stamp(Generator.STAMP_FLATTEN, Vector2(0, 0), 2.0, 6.0, 4.0)]
	Generator.generate(_small_recipe(), [], cache)
	var cached: Data = Generator.generate(_small_recipe(), mods, cache)
	var fresh: Data = Generator.generate(_small_recipe(), mods)
	_check("a repeat generate reuses the cached base", cached.generated_info.contains("base cached"))
	_check("cached and fresh generates agree exactly", cached.heights == fresh.heights and cached.control == fresh.control)
	var again: Data = Generator.generate(_small_recipe(), [], cache)
	var plain: Data = Generator.generate(_small_recipe())
	_check("modifiers never leak into the cache", again.heights == plain.heights)


# height_at_local must follow the same diagonal split as HeightMapShape3D.
func _test_sampling_matches_triangles() -> void:
	var d: Data = Generator.generate(_small_recipe())
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var sx := d.cells_x + 1
	var worst := 0.0
	for _i in 400:
		var i := rng.randi_range(0, d.cells_x - 1)
		var j := rng.randi_range(0, d.cells_z - 1)
		var u := rng.randf()
		var v := rng.randf()
		var x := (i + u) * d.cell_size - d.width() * 0.5
		var z := (j + v) * d.cell_size - d.depth() * 0.5
		var k := j * sx + i
		var want: float
		if u + v <= 1.0:
			want = d.heights[k] + u * (d.heights[k + 1] - d.heights[k]) + v * (d.heights[k + sx] - d.heights[k])
		else:
			var h11 := d.heights[k + sx + 1]
			want = h11 + (1.0 - u) * (d.heights[k + sx] - h11) + (1.0 - v) * (d.heights[k + 1] - h11)
		worst = maxf(worst, absf(d.height_at_local(x, z) - want))
	_check("height_at_local interpolates the collision's triangles", worst < 0.0001, "worst %.6f" % worst)
	_check("height_at_local hits stored samples exactly",
			absf(d.height_at_local(-d.width() * 0.5 + 6.0, -d.depth() * 0.5 + 4.0) - d.heights[2 * sx + 3]) < 0.00001)


func _test_meshes() -> void:
	var d: Data = Generator.generate(_small_recipe())
	var c := d.chunk_cells
	var normals := MeshBuilder.compute_normals(d)
	var lods := MeshBuilder.build_lod_indices(c, d.lod_count)
	var skirt := MeshBuilder.skirt_depth(d)
	var m00 := MeshBuilder.build_chunk(d, normals, 0, 0, lods, skirt)
	var m10 := MeshBuilder.build_chunk(d, normals, 1, 0, lods, skirt)
	var a00 := m00.surface_get_arrays(0)
	var a10 := m10.surface_get_arrays(0)
	var v00: PackedVector3Array = a00[Mesh.ARRAY_VERTEX]
	var v10: PackedVector3Array = a10[Mesh.ARRAY_VERTEX]
	var n00: PackedVector3Array = a00[Mesh.ARRAY_NORMAL]
	var n10: PackedVector3Array = a10[Mesh.ARRAY_NORMAL]
	_check("chunk = grid + skirt vertices", v00.size() == (c + 1) * (c + 1) + 4 * c, "%d" % v00.size())
	var seam := true
	for z in c + 1:
		var right_edge := z * (c + 1) + c
		var left_edge := z * (c + 1)
		if not v00[right_edge].is_equal_approx(v10[left_edge]) or not n00[right_edge].is_equal_approx(n10[left_edge]):
			seam = false
	_check("neighbouring chunks share edge positions and normals", seam)
	var idx: PackedInt32Array = a00[Mesh.ARRAY_INDEX]
	var faces_down := true
	for t in range(0, c * c * 6, 6 * 97):
		var n := (v00[idx[t + 1]] - v00[idx[t]]).cross(v00[idx[t + 2]] - v00[idx[t]])
		if n.y >= 0.0:
			faces_down = false
	# Godot's front face is clockwise, whose right-hand normal points AWAY from
	# the viewer: a correctly wound top surface has cross products pointing down.
	_check("ground triangles wound to face up", faces_down)
	var skirt_out := true
	var centre := Vector3(c * 0.5 * d.cell_size - d.width() * 0.5, 0.0, c * 0.5 * d.cell_size - d.depth() * 0.5)
	for t in range(c * c * 6, idx.size(), 6):
		var a := v00[idx[t]]
		var n := (v00[idx[t + 1]] - a).cross(v00[idx[t + 2]] - a)
		var outward := Vector3(a.x - centre.x, 0.0, a.z - centre.z)
		if n.dot(outward) >= 0.0:
			skirt_out = false
			break
	_check("skirts face outward", skirt_out)
	var shrinking := true
	for l in range(1, lods.size()):
		if lods[l].size() >= lods[l - 1].size():
			shrinking = false
	_check("every LOD has fewer indices than the one before", shrinking)
	var lowest_edge := INF
	var lowest_skirt := INF
	for i in (c + 1) * (c + 1):
		lowest_edge = minf(lowest_edge, v00[i].y)
	for i in range((c + 1) * (c + 1), v00.size()):
		lowest_skirt = minf(lowest_skirt, v00[i].y)
	_check("skirts hang below the ground", lowest_skirt < lowest_edge)
	var tiles := MeshBuilder.build_collision_tiles(d)
	var square := true
	for t in tiles:
		var s: HeightMapShape3D = t.shape
		if s.map_width != s.map_depth:
			square = false
	_check("collision tiles are square (Jolt's native height field)", square and tiles.size() > 0)


func _test_roundtrip() -> void:
	var d: Data = Generator.generate(_small_recipe())
	var err := ResourceSaver.save(d, TMP_DATA, ResourceSaver.FLAG_COMPRESS)
	_check("TerrainData saves as compressed binary", err == OK, error_string(err))
	var back: Data = ResourceLoader.load(TMP_DATA, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("TerrainData loads back identical", back != null and back.is_valid("roundtrip")
			and back.heights == d.heights and back.control == d.control and back.lod_errors == d.lod_errors)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DATA))


# ── Sketches ─────────────────────────────────────────────────────────────────
# A 64 × 32 px sketch at 4 m a pixel — a 256 × 128 m map — painted in blocks:
#   white x 0–15 · blue x 20–31, y 2–12 · green x 20–31, y 18–29
#   grey x 36–59, y 2–14 · red x 36–59, y 18–29 · yellow x 60–63
const SK_W := 64
const SK_H := 32
const SK_MPP := 4.0
const SK_MOUNTAIN := Rect2(0, 0, 16, 32)
const SK_WATER := Rect2(20, 2, 12, 11)
const SK_FLAT := Rect2(20, 18, 12, 12)
const SK_URBAN := Rect2(36, 2, 24, 13)
const SK_SHELLED := Rect2(36, 18, 24, 12)
const SK_ROUGH := Rect2(60, 0, 4, 32)


func _sketch_image() -> Image:
	var img := Image.create(SK_W, SK_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.fill_rect(Rect2i(SK_MOUNTAIN), Color(1, 1, 1))
	img.fill_rect(Rect2i(SK_WATER), Color(0, 0, 1))
	img.fill_rect(Rect2i(SK_FLAT), Color(0, 1, 0))
	img.fill_rect(Rect2i(SK_URBAN), Color(0.5, 0.5, 0.5))
	img.fill_rect(Rect2i(SK_SHELLED), Color(1, 0, 0))
	img.fill_rect(Rect2i(SK_ROUGH), Color(1, 1, 0))
	return img


func _sketch_recipe(img: Image) -> Recipe:
	var r := Recipe.new()
	r.size_x = SK_W * SK_MPP
	r.size_z = SK_H * SK_MPP
	r.layout = Recipe.Layout.OPEN
	r.border_sides = 0
	r.hills_height = 3.0
	r.ridge_height = 0.0
	r.detail_height = 2.0   # strong local bumps: flat paint must visibly remove them
	r.crater_count = 0
	r.thermal_passes = 0
	r.hydraulic_strength = 0.0
	if img != null:
		r.sketch = ImageTexture.create_from_image(img)
		r.sketch_metres_per_pixel = SK_MPP
	r.sketch_blend = 8.0
	r.sketch_edge_noise = 0.0
	r.sketch_mountain_height = 30.0
	r.water_level = -1.5
	r.water_depth = 4.0
	r.water_bank = 12.0
	r.urban_block = Vector2(20, 16)
	r.urban_street = 6.0
	r.urban_ruin = 0.0
	r.shelling_per_hectare = 60.0
	r.rough_height = 8.0
	return r


## Local-space rectangle of a pixel rectangle, shrunk by `inset` pixels.
func _sk_local(px: Rect2, inset: float) -> Rect2:
	var half := Vector2(SK_W, SK_H) * SK_MPP * 0.5
	var a := (px.position + Vector2(inset, inset)) * SK_MPP - half
	var b := (px.end - Vector2(inset, inset)) * SK_MPP - half
	return Rect2(a, b - a)


## Heights every 2 m over a local rectangle.
func _heights_in(d: Data, area: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := area.position.x
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			out.append(d.height_at_local(x, z))
			z += 2.0
		x += 2.0
	return out


func _mean(v: PackedFloat32Array) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s / maxf(v.size(), 1.0)


func _spread(v: PackedFloat32Array) -> float:
	var m := _mean(v)
	var s := 0.0
	for x in v:
		s += (x - m) * (x - m)
	return sqrt(s / maxf(v.size(), 1.0))


func _test_sketch() -> void:
	_check("sketch palette: pure colours classify", Sketch.classify(Color(1, 1, 1)) == Sketch.MOUNTAIN
			and Sketch.classify(Color(0, 0, 1)) == Sketch.WATER and Sketch.classify(Color(0.5, 0.5, 0.5)) == Sketch.URBAN
			and Sketch.classify(Color(1, 1, 0)) == Sketch.ROUGH and Sketch.classify(Color(0, 0, 0)) == -1
			and Sketch.classify(Color(0, 0, 1, 0)) == -1)
	_check("sketch palette: a blue/green fringe is not taken for urban grey", Sketch.classify(Color(0, 0.5, 0.5)) != Sketch.URBAN)

	var d: Data = Generator.generate(_sketch_recipe(_sketch_image()))
	var plain: Data = Generator.generate(_sketch_recipe(null))
	_check("a sketch sets the map size (4 m a pixel)", d != null and d.width() == 256.0 and d.depth() == 128.0,
			"%s × %s" % [d.width(), d.depth()] if d else "no data")
	if d == null:
		return
	var tall := Image.create(16, 48, false, Image.FORMAT_RGBA8)
	tall.fill(Color(0, 0, 0, 1))
	tall.fill_rect(Rect2i(4, 20, 8, 8), Color(0, 1, 0))
	var nd: Data = Generator.generate(_sketch_recipe(tall))
	_check("a tall sketch makes a north–south map", nd.depth() > nd.width(), "%s × %s" % [nd.width(), nd.depth()])

	var mountains := _mean(_heights_in(d, _sk_local(SK_MOUNTAIN, 3)))
	var flat_core := _heights_in(d, _sk_local(SK_FLAT, 3))
	_check("white paint stands up as mountains", mountains > _mean(flat_core) + 15.0, "%.1f vs %.1f" % [mountains, _mean(flat_core)])
	_check("green paint is flat ground", _spread(flat_core) < 0.2 and _spread(flat_core) < _spread(_heights_in(plain, _sk_local(SK_FLAT, 3))) * 0.4,
			"spread %.3f m" % _spread(flat_core))

	var under := true
	for h in _heights_in(d, _sk_local(SK_WATER, 3)):
		if h > d.water_level - 1.0:
			under = false
	_check("blue paint becomes a bed below the waterline", under)
	var water_mid := _sk_local(SK_WATER, 0).get_center()
	_check("the water surface covers the painted water only",
			d.water_at_local(water_mid.x, water_mid.y) and not d.water_at_local(_sk_local(SK_SHELLED, 0).get_center().x, _sk_local(SK_SHELLED, 0).get_center().y))
	var dry := true
	var bank_z := _sk_local(SK_WATER, 0).end.y + 6.0
	for x in range(int(_sk_local(SK_WATER, 1).position.x), int(_sk_local(SK_WATER, 1).end.x), 2):
		if d.height_at_local(x, bank_z) < d.water_level + 0.2:
			dry = false
	_check("the land beside water keeps a dry bank", dry)

	_check("grey paint yields building lots", d.lots.size() >= 2, "%d lot(s)" % d.lots.size())
	var level := true
	var inside := true
	var town := _sk_local(SK_URBAN, 0)
	for lot in d.lots:
		var c: Vector2 = lot.centre
		var half: Vector2 = lot.size * 0.5 - Vector2(1, 1)
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = c + Vector2(s.x * half.x, s.y * half.y)
			if absf(d.height_at_local(p.x, p.y) - float(lot.height)) > 0.05:
				level = false
		if not town.has_point(c):
			inside = false
	_check("every lot is level at its recorded height", level)
	_check("every lot lies inside the grey paint", inside)
	var street_found := false
	for a in d.lots:
		for b in d.lots:
			var gap: Vector2 = b.centre - a.centre
			if absf(gap.y) < 0.1 and absf(gap.x - 26.0) < 0.1:
				var mid: Vector2 = (a.centre + b.centre) * 0.5
				street_found = street_found or d.control_at_local(mid.x, mid.y).r > 0.8
	_check("streets are painted between neighbouring lots", street_found)

	var shelled := _heights_in(d, _sk_local(SK_SHELLED, 2))
	var lowest := INF
	for h in shelled:
		lowest = minf(lowest, h)
	var scorched := false
	var area := _sk_local(SK_SHELLED, 2)
	for x in range(int(area.position.x), int(area.end.x), 2):
		for z in range(int(area.position.y), int(area.end.y), 2):
			scorched = scorched or d.control_at_local(x, z).g > 0.5
	_check("red paint is shelled: craters and scorch", lowest < _mean(shelled) - 1.0 and scorched)
	_check("yellow paint is rougher ground", _spread(_heights_in(d, _sk_local(SK_ROUGH, 1))) > _spread(_heights_in(plain, _sk_local(SK_ROUGH, 1))) * 1.5)

	var again: Data = Generator.generate(_sketch_recipe(_sketch_image()))
	_check("the same sketch generates the same terrain", again.heights == d.heights and again.lots.size() == d.lots.size())
	var black := Image.create(SK_W, SK_H, false, Image.FORMAT_RGBA8)
	black.fill(Color(0, 0, 0, 1))
	print("      (the next check prints one \"no painted colours\" warning on purpose)")
	var unpainted: Data = Generator.generate(_sketch_recipe(black))
	_check("an all-black sketch leaves the recipe's terrain untouched", unpainted.heights == plain.heights)

	var cache := {}
	var r := _sketch_recipe(_sketch_image())
	Generator.generate(r, [], cache)
	var edited := _sketch_image()
	edited.fill_rect(Rect2i(22, 20, 4, 4), Color(1, 1, 1))
	r.sketch = ImageTexture.create_from_image(edited)
	var redone: Data = Generator.generate(r, [], cache)
	_check("editing the sketch invalidates the cached base", not redone.generated_info.contains("base cached") and redone.heights != d.heights)


func _test_sketch_terrain_node() -> void:
	var d: Data = Generator.generate(_sketch_recipe(_sketch_image()))
	var terrain: Node3D = TerrainScript.new()
	terrain.data = d
	terrain.position = Vector3(300, 20, -150)
	var scatter: Node3D = ScatterScript.new()
	var layer: LayerScript = LayerScript.new()
	var meshes: Array[Mesh] = [BoxMesh.new()]
	layer.meshes = meshes
	layer.per_hectare = 800.0
	layer.max_slope = 80.0
	layer.max_mountain = 1.0
	layer.max_paint = 1.0
	layer.inside_boundary = false
	var layers: Array[LayerScript] = [layer]
	scatter.layers = layers
	terrain.add_child(scatter)
	root.add_child(terrain)
	await process_frame
	_check("painted water is drawn", terrain.get_water_surface_count() > 0, "%d surface(s)" % terrain.get_water_surface_count())
	var drawn := terrain.find_children("*", "MeshInstance3D", true, false).size()
	_check("water is not a node, so the navmesh bake cannot walk on it", drawn == d.chunks_x() * d.chunks_z(),
			"%d MeshInstance3D for %d chunks" % [drawn, d.chunks_x() * d.chunks_z()])
	var lots: Array = terrain.get_lots()
	var grounded := not lots.is_empty()
	for lot in lots:
		var o: Vector3 = (lot.transform as Transform3D).origin
		if absf(terrain.get_height_at(o) - o.y) > 0.05:
			grounded = false
	_check("get_lots() gives world transforms on the levelled ground", grounded)
	var dry := true
	for xf: Transform3D in scatter.get_layer_transforms(0):
		if d.water_at_local(xf.origin.x, xf.origin.z):
			dry = false
	_check("scatter stays out of the water", dry and not scatter.get_layer_transforms(0).is_empty())
	terrain.queue_free()
	await process_frame


func _test_collision_matches_surface() -> void:
	var d: Data = Generator.generate(_small_recipe())
	var terrain: Node3D = TerrainScript.new()
	terrain.data = d
	terrain.position = Vector3(1000, -50, 700)   # off the origin, so placement errors cannot cancel out
	root.add_child(terrain)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var misses := 0
	var api_worst := 0.0
	var rect: Rect2 = terrain.get_playable_rect()
	for _i in 300:
		var local := Vector3(rng.randf_range(-d.width() * 0.49, d.width() * 0.49), 0.0,
				rng.randf_range(-d.depth() * 0.49, d.depth() * 0.49))
		var world := terrain.to_global(local)
		var q := PhysicsRayQueryParameters3D.create(world + Vector3.UP * 500.0, world + Vector3.DOWN * 500.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			misses += 1
			continue
		# The boundary walls stand inside the map; rays outside them hit wall tops.
		if not rect.has_point(Vector2(local.x, local.z)):
			continue
		var want: float = terrain.to_global(Vector3(local.x, d.height_at_local(local.x, local.z), local.z)).y
		worst = maxf(worst, absf(hit.position.y - want))
		api_worst = maxf(api_worst, absf(terrain.get_height_at(world) - want))
	_check("rays hit the collision everywhere on the map", misses == 0, "%d misses" % misses)
	_check("collision surface matches the rendered heights", worst < 0.05, "worst %.3f m" % worst)
	# 1 mm: the terrain sits 1 km off the origin, and to_local/to_global in
	# single precision round at about a tenth of that.
	_check("get_height_at() matches the data", api_worst < 0.001, "worst %.5f m" % api_worst)
	_check("get_height_at() is NAN off the map", is_nan(terrain.get_height_at(terrain.to_global(Vector3(d.width(), 0, 0)))))
	var chunks := terrain.get_node_or_null(^"_Built/Chunks")
	_check("one render chunk per 64-cell block", chunks != null and chunks.get_child_count() == d.chunks_x() * d.chunks_z())
	terrain.queue_free()
	await process_frame


func _test_scatter() -> void:
	var d: Data = Generator.generate(_small_recipe(), [_stamp(Generator.STAMP_FLATTEN, Vector2(0, 0), 0.0, 12.0, 2.0)])
	var terrain: Node3D = TerrainScript.new()
	terrain.data = d
	var scatter: Node3D = ScatterScript.new()
	var layer: LayerScript = LayerScript.new()
	var meshes: Array[Mesh] = [BoxMesh.new()]
	layer.meshes = meshes
	layer.per_hectare = 400.0
	layer.max_slope = 25.0
	layer.max_mountain = 0.3
	layer.sink = 0.2
	layer.collision_radius = 0.4
	var layers: Array[LayerScript] = [layer]
	scatter.layers = layers
	terrain.add_child(scatter)
	root.add_child(terrain)
	await process_frame
	var mmi: MultiMeshInstance3D = null
	var body: StaticBody3D = null
	for n in scatter.find_children("*", "", true, false):
		if n is MultiMeshInstance3D:
			mmi = n
		elif n is StaticBody3D:
			body = n
	_check("scatter builds a MultiMesh", mmi != null and mmi.multimesh.instance_count > 0)
	if mmi == null:
		terrain.queue_free()
		return
	# Placements come from get_layer_transforms(): the dummy renderer used
	# headless does not keep MultiMesh transforms, so they cannot be read back.
	var placed: Array = scatter.get_layer_transforms(0)
	_check("scatter records one placement per instance", placed.size() == mmi.multimesh.instance_count and placed.size() > 0)
	var rect: Rect2 = terrain.get_playable_rect()
	var inside := true
	var grounded := true
	var off_pad := true
	for xf: Transform3D in placed:
		var p := xf.origin
		if not rect.grow(0.01).has_point(Vector2(p.x, p.z)):
			inside = false
		if absf(p.y - (d.height_at_local(p.x, p.z) - 0.2)) > 0.001:
			grounded = false
		if d.control_at_local(p.x, p.z).b > 0.2:
			off_pad = false
	_check("scattered props stay inside the boundary", inside)
	_check("scattered props sit on the ground, sunk as asked", grounded)
	_check("scattered props keep off building pads", off_pad)
	_check("one collider per prop", body != null and body.get_shape_owners().size() == placed.size())
	scatter.rebuild()
	var again: Array = scatter.get_layer_transforms(0)
	_check("scatter is deterministic", again.size() == placed.size() and (again[0] as Transform3D).is_equal_approx(placed[0]))
	terrain.queue_free()
	await process_frame


func _test_template_level() -> void:
	var packed: PackedScene = load(TEMPLATE)
	_check("template level loads", packed != null)
	if packed == null:
		return
	var level := packed.instantiate()
	root.add_child(level)
	await physics_frame
	await physics_frame
	var terrain := level.get_node_or_null(^"NavigationRegion3D/Terrain") as Node3D
	_check("template has its terrain, with baked data", terrain != null and terrain.data != null)
	if terrain == null or terrain.data == null:
		level.queue_free()
		return
	var d: Data = terrain.data
	_check("template terrain is the valley mission's size",
			absf(d.width() - 1408.0) < 0.1 and absf(d.depth() - 512.0) < 0.1, "%s × %s" % [d.width(), d.depth()])
	_check("template relief is valley-mission scale (< 70 m)", d.max_height - d.min_height < 70.0,
			"%.1f m" % (d.max_height - d.min_height))
	var spawn := level.get_node(^"SpawnPoint") as Node3D
	var space: PhysicsDirectSpaceState3D = spawn.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spawn.global_position + Vector3.UP, spawn.global_position + Vector3.DOWN * 50.0))
	_check("there is ground under the spawn point", not hit.is_empty() and hit.position.y < spawn.global_position.y)
	var pad := level.get_node(^"NavigationRegion3D/Terrain/Stamps/OutpostPad") as Node3D
	var pad_ground: float = terrain.get_height_at(pad.global_position)
	_check("the outpost pad is flat at its own height", absf(pad_ground - pad.global_position.y) < 0.01,
			"%.3f vs %.3f" % [pad_ground, pad.global_position.y])
	var exit := level.get_node(^"NavigationRegion3D/LevelExit") as Node3D
	_check("the level exit stands on the ground", absf(terrain.get_height_at(exit.global_position) - exit.global_position.y) < 0.25)
	var nm: NavigationMesh = (level.get_node(^"NavigationRegion3D") as NavigationRegion3D).navigation_mesh
	_check("template navmesh is baked", nm != null and nm.get_polygon_count() > 100, "%d polygons" % (nm.get_polygon_count() if nm else 0))
	var rect: Rect2 = terrain.get_playable_rect()
	_check("spawn and exit are inside the boundary walls",
			rect.has_point(Vector2(spawn.global_position.x, spawn.global_position.z)) and rect.has_point(Vector2(exit.global_position.x, exit.global_position.z)))
	root.remove_child(level)
	level.queue_free()
	await process_frame
