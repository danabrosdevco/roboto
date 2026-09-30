extends SceneTree

# ─────────────────────────────────────────────
# WATER NAVMESH TESTS
#
# Rivers are not navigable. The bake cannot tell a river bed from any other
# dip and paves it, so Env/terrain/water_navmesh.gd takes the bed back out when
# a level loads. This checks that it does, and that it stops there.
#
# Two halves, because two different things can break:
#   - the strip itself, against every terrain that has water: a polygon in the
#     bed must go and a polygon on the bank must stay. Run on a stub terrain
#     holding the real data, so no level is built for it.
#   - the wiring, against a real level: loading it must leave no navmesh under
#     the water. GeneratedTerrain._ready() is the only thing that calls the
#     strip, and nothing else would notice if that call went away.
# ─────────────────────────────────────────────

const DATA_DIR := "res://maps/terrain_data"
const WaterNavmesh := preload("res://Env/terrain/water_navmesh.gd")
## The level the rule came from: sixteen bridges were taken out of it and the
## squad still reached everything, by wading.
const END_TO_END := "res://maps/pittsburgh_level.tscn"
## A script error inside a check ends that coroutine without reaching quit(),
## and a headless SceneTree then idles for ever. The watchdog makes that loud.
const WATCHDOG_S := 300

var _fails := 0


## Stands in for GeneratedTerrain: the strip only asks a terrain for its data
## and its transform, and building a real one would generate a level's worth of
## chunks and collision for nothing.
class StubTerrain extends Node3D:
	var data


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL  watchdog: the suite did not finish within %d s — a check probably crashed (see SCRIPT ERROR above)" % WATCHDOG_S)
		quit(2))
	await process_frame
	var files := Array(DirAccess.get_files_at(DATA_DIR)).filter(
			func(f: String) -> bool: return f.ends_with(".res"))
	files.sort()
	_check("there is terrain data in %s" % DATA_DIR, not files.is_empty())
	var with_water := 0
	for f: String in files:
		if _strips(DATA_DIR.path_join(f)):
			with_water += 1
	_check("at least one terrain has water to strip", with_water > 0,
			"no .res in %s has a water mask" % DATA_DIR)
	await _wired()
	print("")
	print("ALL WATER NAVMESH CHECKS PASS" if _fails == 0 else "%d WATER NAVMESH CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## One terrain's data: a triangle in its river must go, one on its bank stay.
## Returns whether the data had water at all.
func _strips(path: String) -> bool:
	var data = load(path)
	if data == null or not data.has_water():
		return false
	var name := path.get_file().get_basename()
	var bed := _sample(data, true)
	var bank := _sample(data, false)
	if bed == Vector2.INF or bank == Vector2.INF:
		_check("%s: has both wet and dry ground to test with" % name, false,
				"bed %s, bank %s" % [bed, bank])
		return true
	var terrain := StubTerrain.new()
	terrain.data = data
	var region := NavigationRegion3D.new()
	region.add_child(terrain)
	var mesh := NavigationMesh.new()
	# Two triangles: one on the river bed, one on dry land well above the water.
	var under: float = data.water_level - 1.0
	var over: float = data.water_level + 8.0
	mesh.set_vertices(PackedVector3Array([
		Vector3(bed.x, under, bed.y), Vector3(bed.x + 1.0, under, bed.y), Vector3(bed.x, under, bed.y + 1.0),
		Vector3(bank.x, over, bank.y), Vector3(bank.x + 1.0, over, bank.y), Vector3(bank.x, over, bank.y + 1.0),
	]))
	mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	mesh.add_polygon(PackedInt32Array([3, 4, 5]))
	region.navigation_mesh = mesh
	var dropped := WaterNavmesh.strip(region, terrain)
	_check("%s: the polygon in the river bed goes" % name, dropped == 1,
			"%d polygon(s) dropped, expected 1" % dropped)
	_check("%s: the polygon on the bank stays" % name,
			region.navigation_mesh.get_polygon_count() == 1,
			"%d left, expected 1" % region.navigation_mesh.get_polygon_count())
	region.free()
	return true


## A local x/z over a wet sample, or over a dry one well above the waterline.
## Vector2.INF when the terrain has none.
func _sample(data, wet: bool) -> Vector2:
	var sx: int = data.cells_x + 1
	var step := maxi(1, data.cells_x / 64)
	for j in range(0, data.cells_z + 1, step):
		for i in range(0, sx, step):
			var k: int = j * sx + i
			var is_water: bool = data.water[k] > 0
			if is_water != wet:
				continue
			# Dry ground right at the waterline is the shoreline, which the
			# strip is allowed to trim either way; stay clear of it.
			if not wet and data.heights[k] < data.water_level + 4.0:
				continue
			return Vector2(i * data.cell_size - data.width() * 0.5,
					j * data.cell_size - data.depth() * 0.5)
	return Vector2.INF


## A real level, loaded the way the game loads it.
func _wired() -> void:
	var packed := load(END_TO_END) as PackedScene
	if packed == null:
		_check("%s loads" % END_TO_END.get_file(), false, "load() returned null")
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 4:
		await physics_frame
	var region := level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var terrain := region.get_node_or_null("Terrain") if region != null else null
	if region == null or terrain == null or region.navigation_mesh == null:
		_check("%s has a terrain under a baked NavigationRegion3D" % END_TO_END.get_file(), false)
		root.remove_child(level)
		level.free()
		return
	var data = terrain.data
	var mesh := region.navigation_mesh
	var verts := mesh.get_vertices()
	var ceiling: float = data.water_level + WaterNavmesh.FREEBOARD
	var wading := 0
	var worst := Vector3.ZERO
	for p in mesh.get_polygon_count():
		for idx in mesh.get_polygon(p):
			var world: Vector3 = region.global_transform * verts[idx]
			if world.y >= ceiling:
				continue
			var local: Vector3 = terrain.to_local(world)
			if data.water_at_local(local.x, local.z):
				wading += 1
				worst = world
				break
	_check("%s: no navmesh left in the water after loading it" % END_TO_END.get_file(),
			wading == 0, "%d polygon(s) still in the river, e.g. at %v" % [wading, worst])
	root.remove_child(level)
	level.free()
