extends "res://tools/mapdeck.gd"

# ─────────────────────────────────────────────
# BUILD SALIENT — promotes the `the_salient` deck entry into a real level:
# maps/salient_level.tscn, its sketch, its terrain data and its objectives.
#
#   godot --headless --path . --script res://tools/build_salient.gd
#   godot --headless --path . --script res://tools/build_salient.gd -- --force
#
# THE DECK ENTRY IS THE DESIGN AND THIS IS ONLY THE PROMOTION. Paint, recipe,
# trench cuts, dressing and scatter all come out of tools/mapdeck_data.gd
# through the same _placements() the deck renders with, so the concept and the
# level cannot drift apart. Everything this adds is what a level needs and a
# concept does not: a spawn, an exit, objective anchors, a navigation region
# and a saved terrain resource.
#
# RUN IT TWICE THE FIRST TIME. The terrain data file does not exist until this
# writes it, and an ext_resource pointing at a missing file is the silent-null
# check.sh hunts for — so pass one writes the scene without it, saves the data,
# and pass two picks it up. Nothing else changes between them.
#
# AFTERWARDS: bake the navmesh, which nothing here does.
#
#   BAKE_ONLY=1 LEVEL=res://maps/salient_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

const ID := "the_salient"
const LEVEL := "res://maps/salient_level.tscn"
const SKETCH := "res://Env/terrain/sketches/salient.png"
const DATA := "res://maps/terrain_data/salient_level_terrain.res"
const ENVIRON := "res://maps/terrain_data/salient_environment.tres"
const GROUND := "res://maps/terrain_data/salient_terrain_material.tres"

## Objective anchors. TERRAIN puts the pins in and names them; the missions
## that use them are GAMEPLAY's, which is why these are places and not tasks.
## node, tag, label, x, z
const OBJECTIVES: Array = [
	["Salient_Jumpoff", "obj_salient_jumpoff", "Jump-off Trench", -170.0, 0.0],
	["Salient_SapNorth", "obj_salient_sap_north", "North Sap", -100.0, -70.0],
	["Salient_SapSouth", "obj_salient_sap_south", "South Sap", -100.0, 70.0],
	["Salient_Crater", "obj_salient_crater", "The Mine Crater", -60.0, 10.0],
	["Salient_FrontLine", "obj_salient_front", "Their Front Line", 60.0, 34.0],
	["Salient_Redoubt", "obj_salient_redoubt", "The Redoubt", 58.0, -142.0],
	["Salient_Support", "obj_salient_support", "Support Line", 190.0, 0.0],
	["Salient_GunLine", "obj_salient_guns", "The Gun Line", 330.0, 0.0],
	["Salient_Railhead", "obj_salient_railhead", "The Railhead", 350.0, -195.0],
	["Salient_Village", "obj_salient_village", "The Village", 430.0, 95.0],
	# IN THE STREET, NOT IN A BUILDING. The village is four bands of blocks
	# centred on z -142, -47, +47 and +142, so an anchor on one of those
	# numbers is inside a house: the church reported CUT OFF after a 967 m walk
	# twice before these moved into the gaps between the bands.
	["Salient_Church", "obj_salient_church", "The Church Tower", 412.0, -95.0],
]

## Where each anchor's patrol walks, as offsets from it.
const PATROLS: Array = [
	["Salient_FrontLine", Vector2(0, -60), Vector2(0, 60), Vector2(-20, 0)],
	["Salient_Redoubt", Vector2(0, -40), Vector2(30, 0)],
	["Salient_Support", Vector2(0, -70), Vector2(0, 70)],
	["Salient_GunLine", Vector2(-30, -60), Vector2(-30, 60), Vector2(30, 0)],
	["Salient_Village", Vector2(-60, 0), Vector2(40, -95), Vector2(0, -80)],
	["Salient_Railhead", Vector2(-80, 0), Vector2(80, 0)],
]

## Pieces an objective is allowed to sit in: you stand in these, not on them.
const STAND_IN := ["feature_crater_rim", "feature_berm", "feature_trench_revetment",
		"industrial_rail_track", "fort_mortar_pit", "fort_gun_emplacement",
		"fort_hesco_sangar", "fort_razor_wire", "fort_dragon_teeth"]

var _map: Dictionary = {}
var _data: Data = null


func _initialize() -> void:
	await process_frame
	for m: Dictionary in _deck:
		if m.id == ID:
			_map = m
	if _map.is_empty():
		print("FAIL  no deck entry called %s" % ID)
		quit(1)
		return
	var force := OS.get_cmdline_user_args().has("--force")
	if FileAccess.file_exists(ProjectSettings.globalize_path(LEVEL)) and not force \
			and not ResourceLoader.exists(DATA):
		pass                                  # first pass of a fresh build
	_sketch()
	var r := _recipe()
	_data = Generator.generate(r, _paths())
	if _data == null:
		print("FAIL  the terrain would not generate")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://maps/terrain_data")
	var err := ResourceSaver.save(_data, DATA)
	if err != OK:
		print("FAIL  could not save %s (%s)" % [DATA, error_string(err)])
		quit(1)
		return
	_environment()
	_ground_material()
	_check_anchors()
	var text := _scene(r)
	if text.length() < 4000:
		# A builder that reports success over a truncated file is the worst
		# failure this project has had: it looks done and is not.
		print("FAIL  the scene came out %d characters; something threw" % text.length())
		quit(1)
		return
	var f := FileAccess.open(LEVEL, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("      %s  %.0f x %.0f m at %.2f m cells" % [LEVEL.get_file(),
			_data.width(), _data.depth(), r.cell_size])
	if not ResourceLoader.exists(DATA):
		print("      terrain data written but not yet importable — RUN THIS AGAIN")
	print("BUILD SALIENT DONE")
	quit()


# ── The pieces of it ────────────────────────────────────────────────────────

func _sketch() -> void:
	var img := Image.create(_map.px.x, _map.px.y, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	for op: Array in _map.get("paint", []):
		_paint(img, op)
	DirAccess.make_dir_recursive_absolute("res://Env/terrain/sketches")
	img.save_png(SKETCH)


func _recipe() -> Recipe:
	var r := Recipe.new()
	r.layout = Recipe.Layout.OPEN
	r.border_sides = 0
	r.floor_at_zero = true
	r.cell_size = CELL
	r.random_seed = 7
	r.sketch_metres_per_pixel = MPP
	r.floor_depth = 3.0
	r.hills_height = 2.5
	r.hills_scale = 320.0
	r.ridge_height = 0.0
	r.detail_height = 0.5
	r.terrace_strength = 0.0
	r.crater_count = 0
	r.thermal_passes = 2
	r.hydraulic_strength = 0.0
	r.smooth_passes = 2
	r.sketch_mountain_height = 34.0
	r.sketch_blend = 18.0
	r.sketch_edge_noise = 14.0
	r.rough_height = 5.0
	r.road_width = 6.0
	r.water_depth = 6.0
	r.water_bank = 22.0
	r.shelling_per_hectare = 22.0
	r.crater_radius_min = 3.0
	r.crater_radius_max = 11.0
	r.crater_depth = 0.22
	for k: String in _map.get("recipe", {}):
		r.set(k, _map.recipe[k])
	# The sketch goes on as an image the generator can read now; the SCENE
	# points at the .png on disk, which needs one editor import before it
	# resolves. The saved terrain data is what the game actually loads, so a
	# missing import costs regeneration in the editor and nothing else.
	var img := Image.load_from_file(SKETCH)
	if img != null:
		r.sketch = ImageTexture.create_from_image(img)
	return r


func _paths() -> Array:
	var out: Array = []
	for p: Array in _map.get("paths", []):
		var pts := PackedVector3Array()
		for v: Vector2 in p[4]:
			pts.append(Vector3(v.x, 0.0, v.y))
		out.append({"type": "path", "source": "salient", "mode": PATH_MODE[p[0]],
				"points": pts, "width": float(p[1]), "depth": float(p[2]),
				"falloff": float(p[3]), "follow_terrain": true,
				"smoothing": float(p[5]) if p.size() > 5 else 8.0, "paint": true})
	return out


## A copy of the shared environment with more haze in it. Distance fog is what
## gives a flat map depth — without it the far side of the valley reads at the
## same remove as the parapet in front of you.
func _environment() -> void:
	var base := load("res://Env/world_environment.tres") as Environment
	if base == null:
		return
	var env: Environment = base.duplicate()
	env.fog_enabled = true
	env.fog_light_color = Color(0.53, 0.54, 0.55)
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.35
	env.fog_height = -40.0
	env.fog_height_density = 0.006
	ResourceSaver.save(env, ENVIRON)


# ── Writing the scene ───────────────────────────────────────────────────────

func _scene(r: Recipe) -> String:
	var out := PackedStringArray()
	var ext: Array = [
		["Script", "res://maps/trench_broom_level.gd", "1_level"],
		["PackedScene", "res://Env/world_objects/spawn_point.tscn", "2_spawn"],
		["Script", "res://Campaign/squad_spawn_point.gd", "3_squad"],
		["Script", "res://Env/terrain/generated_terrain.gd", "5_terrain"],
		["Script", "res://Env/terrain/terrain_recipe.gd", "6_recipe"],
		["Script", "res://Env/terrain/terrain_path.gd", "8_path"],
		["PackedScene", "res://Env/world_objects/level_exit.tscn", "10_exit"],
		["PackedScene", "res://Env/world_environment.tscn", "11_env"],
		["PackedScene", "res://Env/world_objects/squad_objective_point.tscn", "14_sqpoint"],
		["Script", "res://Env/terrain/terrain_scatter.gd", "15_scatter"],
		["Script", "res://Env/terrain/terrain_scatter_layer.gd", "16_layer"],
	]
	if ResourceLoader.exists(SKETCH):
		ext.append(["Texture2D", SKETCH, "9_sketch"])
	if ResourceLoader.exists(DATA):
		ext.append(["Resource", DATA, "13_data"])
	if ResourceLoader.exists(ENVIRON):
		ext.append(["Environment", ENVIRON, "12_env"])
	if ResourceLoader.exists(GROUND):
		ext.append(["Material", GROUND, "18_ground"])
	for i in (_map.get("scatter", []) as Array).size():
		ext.append(["Resource", "res://maps/blocks/scatter/%s.tres" % _map.scatter[i],
				"sc%d" % i])
	# One ext_resource per DISTINCT piece however often it is placed, and never
	# one that nothing uses: check.sh fails a scene that declares an id it does
	# not reference.
	var placed: Array = []
	var pieces: Array = []
	for op: Array in _map.get("dress", []):
		var rows := _placements(_data, op)
		if rows.is_empty():
			continue
		if not pieces.has(op[1]):
			pieces.append(op[1])
			ext.append(["PackedScene", "res://maps/blocks/%s.tscn" % op[1],
					"p_" + str(op[1]).get_file()])
		for row: Array in rows:
			placed.append([op[1], row[0], row[1]])

	var subs := PackedStringArray()
	subs.append_array(_recipe_sub(r))
	var curves: Array = []
	for i in (_map.get("paths", []) as Array).size():
		curves.append("Curve3D_t%02d" % i)
		subs.append_array(_curve_sub(curves[i], _map.paths[i][4]))
	subs.append_array(PackedStringArray([
		"[sub_resource type=\"NavigationMesh\" id=\"NavigationMesh_salient\"]",
		# EMPTY, BUT PRESENT. probe_nav_hillfort writes the bake back by finding
		# these two lines and replacing them; without them it bakes fine, reports
		# forty thousand vertices and has nowhere to put them.
		"vertices = PackedVector3Array()",
		"polygons = []",
		"geometry_parsed_geometry_type = 1",
		"agent_height = 1.8",
		"agent_max_climb = 0.5",
		"region_min_size = 6.0",
		"edge_max_error = 2.0",
		"detail_sample_distance = 16.0",
		"filter_baking_aabb = AABB(%s, -60, %s, %s, 300, %s)" % [
				_n(-_data.width() * 0.5 - 8.0), _n(-_data.depth() * 0.5 - 8.0),
				_n(_data.width() + 16.0), _n(_data.depth() + 16.0)],
		""]))

	out.append("[gd_scene load_steps=%d format=3]" % (ext.size() + _count_subs(subs) + 1))
	out.append("")
	for e: Array in ext:
		out.append("[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]" % [e[0], e[1], e[2]])
	out.append("")
	out.append_array(subs)

	# ── The tree ──
	out.append("[node name=\"SalientLevel\" type=\"Node3D\" node_paths=PackedStringArray(\"spawn_point\", \"nav_region\", \"level_exits\")]")
	out.append("script = ExtResource(\"1_level\")")
	out.append("spawn_point = NodePath(\"SpawnPoint\")")
	out.append("nav_region = NodePath(\"NavigationRegion3D\")")
	out.append("level_exits = [NodePath(\"NavigationRegion3D/LevelExit\")]")
	out.append("")
	# Behind the reserve trench, on the ground rather than in the cut: a spawn
	# in a trench is a spawn on a scrap of navmesh that joins nothing.
	out.append("[node name=\"SpawnPoint\" parent=\".\" instance=ExtResource(\"2_spawn\")]")
	out.append(_at(-468.0, 20.0, 1.15))
	out.append("")
	out.append("[node name=\"SquadSpawnPoint\" type=\"Node3D\" parent=\".\"]")
	out.append(_at(-476.0, 4.0, 0.0))
	out.append("script = ExtResource(\"3_squad\")")
	out.append("")
	out.append("[node name=\"NavigationRegion3D\" type=\"NavigationRegion3D\" parent=\".\"]")
	out.append("navigation_mesh = SubResource(\"NavigationMesh_salient\")")
	out.append("")
	out.append("[node name=\"Terrain\" type=\"Node3D\" parent=\"NavigationRegion3D\"]")
	out.append("script = ExtResource(\"5_terrain\")")
	out.append("recipe = SubResource(\"Resource_recipe\")")
	if ResourceLoader.exists(DATA):
		out.append("data = ExtResource(\"13_data\")")
	# The default 60 m inset would put the reserve line, the dumps and the
	# railhead outside the playable rect, where scatter is not placed at all.
	if ResourceLoader.exists(GROUND):
		out.append("material = ExtResource(\"18_ground\")")
	out.append("boundary_inset = 16.0")
	out.append("")
	if not (_map.get("scatter", []) as Array).is_empty():
		var ids: Array = []
		for i in (_map.scatter as Array).size():
			ids.append("ExtResource(\"sc%d\")" % i)
		out.append("[node name=\"Scatter\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
		out.append("script = ExtResource(\"15_scatter\")")
		out.append("layers = Array[ExtResource(\"16_layer\")]([%s])" % ", ".join(ids))
		out.append("")
	out.append("[node name=\"Trenches\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
	out.append("")
	for i in curves.size():
		var p: Array = _map.paths[i]
		out.append("[node name=\"Cut%02d\" type=\"Path3D\" parent=\"NavigationRegion3D/Terrain/Trenches\"]" % i)
		out.append("curve = SubResource(\"%s\")" % curves[i])
		out.append("script = ExtResource(\"8_path\")")
		out.append("mode = %d" % PATH_MODE[p[0]])
		out.append("width = %s" % _n(float(p[1])))
		out.append("depth = %s" % _n(float(p[2])))
		out.append("falloff = %s" % _n(float(p[3])))
		out.append("smoothing = %s" % _n(float(p[5]) if p.size() > 5 else 8.0))
		out.append("")
	out.append("[node name=\"Works\" type=\"Node3D\" parent=\"NavigationRegion3D\"]")
	out.append("")
	var n := 1
	for row: Array in placed:
		var piece: String = row[0]
		var pos: Vector3 = row[1]
		out.append("[node name=\"W%04d_%s\" parent=\"NavigationRegion3D/Works\" instance=ExtResource(\"p_%s\")]" % [
				n, str(piece).get_file(), str(piece).get_file()])
		out.append(_yawed(pos, float(row[2])))
		out.append("")
		n += 1
	out.append("[node name=\"LevelExit\" parent=\"NavigationRegion3D\" instance=ExtResource(\"10_exit\")]")
	out.append(_at(470.0, 150.0, 0.6))
	out.append("")
	out.append("[node name=\"WorldEnvironment\" parent=\".\" instance=ExtResource(\"11_env\")]")
	if ResourceLoader.exists(ENVIRON):
		out.append("environment = ExtResource(\"12_env\")")
	out.append("")
	out.append("[node name=\"Sun\" parent=\"WorldEnvironment\" index=\"0\"]")
	# Low and along the line, so the parapets throw shadows across the ground
	# instead of lighting it flat.
	out.append("transform = Transform3D(0.94, 0.28, -0.2, 0, 0.58, 0.81, 0.34, -0.76, 0.55, 0, 0, 0)")
	out.append("shadow_opacity = 0.9")
	out.append("directional_shadow_max_distance = 420.0")
	out.append("")
	out.append("[node name=\"EnemySquadObjs\" type=\"Node\" parent=\".\"]")
	out.append("")
	for o: Array in OBJECTIVES:
		out.append("[node name=\"%s\" parent=\"EnemySquadObjs\" instance=ExtResource(\"14_sqpoint\")]" % o[0])
		out.append(_at(float(o[3]), float(o[4]), 0.0))
		out.append("objective_name = \"%s\"" % o[2])
		out.append("tag = &\"%s\"" % o[1])
		out.append("show_debug_label = false")
		out.append("")
	for p: Array in PATROLS:
		# A patrol point is a CHILD of its anchor, so its transform is relative
		# to it. These are written as offsets for that reason — emitted as
		# world coordinates they land at twice their distance, which has
		# happened on this project before.
		var pi := 1
		for i in range(1, p.size()):
			var off: Vector2 = p[i]
			out.append("[node name=\"Patrol%d\" type=\"Node3D\" parent=\"EnemySquadObjs/%s\"]" % [pi, p[0]])
			out.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0, %s)" % [
					_n(off.x), _n(off.y)])
			out.append("")
			pi += 1
	return "\n".join(out) + "\n"


## Every exported property the recipe script owns, written out by name. Listing
## them by hand goes stale the first time a knob is added.
func _recipe_sub(r: Recipe) -> PackedStringArray:
	var out := PackedStringArray(["[sub_resource type=\"Resource\" id=\"Resource_recipe\"]",
			"script = ExtResource(\"6_recipe\")"])
	for p: Dictionary in r.get_script().get_script_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		if p.name == "sketch":
			if ResourceLoader.exists(SKETCH):
				out.append("sketch = ExtResource(\"9_sketch\")")
			continue
		out.append("%s = %s" % [p.name, var_to_str(r.get(p.name))])
	out.append("")
	return out


func _curve_sub(id: String, pts: Array) -> PackedStringArray:
	var nums := PackedStringArray()
	for v: Vector2 in pts:
		# in, out, position — three Vector3s a point, which is how Curve3D
		# stores itself.
		nums.append_array(PackedStringArray(["0", "0", "0", "0", "0", "0",
				_n(v.x), "0", _n(v.y)]))
	return PackedStringArray(["[sub_resource type=\"Curve3D\" id=\"%s\"]" % id,
			"bake_interval = 2.0",
			"_data = {",
			"\"points\": PackedVector3Array(%s)," % ", ".join(nums),
			"}",
			"point_count = %d" % pts.size(),
			""])


func _count_subs(subs: PackedStringArray) -> int:
	var n := 0
	for l in subs:
		if l.begins_with("[sub_resource"):
			n += 1
	return n


func _at(x: float, z: float, lift: float) -> String:
	var y := _data.height_at_local(x, z)
	if is_nan(y):
		y = 0.0
	return "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % [
			_n(x), _n(y + lift), _n(z)]


func _yawed(pos: Vector3, yaw_deg: float) -> String:
	var a := deg_to_rad(yaw_deg)
	return "transform = Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, %s, %s)" % [
			_n(cos(a)), _n(-sin(a)), _n(sin(a)), _n(cos(a)),
			_n(pos.x), _n(pos.y), _n(pos.z)]


func _n(v: float) -> String:
	return "%.4f" % v if absf(v - roundf(v)) > 0.0001 else str(int(roundf(v)))


## ANCHORS THAT ARE INSIDE A BUILDING. An objective point on a piece's own
## footprint snaps to a hole in the navmesh and the reach probe calls it CUT
## OFF after a thousand-metre walk — which is a true report of a placement
## mistake, and a slow way to find one. Three rebuild-and-rebake cycles went
## on exactly this before the check existed, so it says so up front instead.
func _check_anchors() -> void:
	# WHAT COUNTS AS BLOCKING. Micro-terrain is meant to be stood on, and so
	# is a gun pit, a berm, a crater rim, a length of rail or a trench you are
	# lining — an anchor "inside" one of those is where it belongs. Only solid
	# built volume over two metres carves a hole in the navmesh, so only that
	# is worth a word.
	var boxes: Array = []
	for op: Array in _map.get("dress", []):
		var box := _size_of(op[1])
		if box.size == Vector3.ZERO or box.size.y < 2.0:
			continue
		var fam: String = str(op[1]).get_base_dir()
		if fam == "ground" or STAND_IN.has(str(op[1]).get_file()):
			continue
		for row: Array in _placements(_data, op):
			var at: Vector3 = row[0]
			# Half extents in plan, taken round so a yaw does not matter.
			var reach := maxf(box.size.x, box.size.z) * 0.5
			boxes.append([Vector2(at.x, at.z), reach, str(op[1]).get_file()])
	var bad := 0
	for o: Array in OBJECTIVES:
		bad += _clear(Vector2(float(o[3]), float(o[4])), str(o[0]), boxes)
	for p: Array in PATROLS:
		var anchor := Vector2.ZERO
		for o: Array in OBJECTIVES:
			if str(o[0]) == str(p[0]):
				anchor = Vector2(float(o[3]), float(o[4]))
		for i in range(1, p.size()):
			bad += _clear(anchor + (p[i] as Vector2), "%s/Patrol%d" % [p[0], i], boxes)
	if bad > 0:
		print("      %d anchor(s) stand inside a placed piece — move them" % bad)


func _clear(at: Vector2, who: String, boxes: Array) -> int:
	for b: Array in boxes:
		if at.distance_to(b[0]) < float(b[1]) * 0.8:
			print("      %-28s is inside %s at (%.0f, %.0f)" % [who, b[2], b[0].x, b[0].y])
			return 1
	return 0


## THE GROUND IS DEAD AND THE MATERIAL HAS TO SAY SO. growth_amount is the
## patchy scrub the terrain shader lays on any gentle ground; on a field that
## has been shelled for two years it is zero. The deck entry carries these
## overrides and the level was built without them the first time, so the grass
## came straight back — a concept and the level promoted from it have to be lit
## and surfaced the same or neither tells you anything about the other.
func _ground_material() -> void:
	var base := load("res://Env/terrain/terrain_material.tres") as ShaderMaterial
	if base == null or not _map.has("material"):
		return
	var mat: ShaderMaterial = base.duplicate()
	for k: String in _map.material:
		mat.set_shader_parameter(k, _map.material[k])
	ResourceSaver.save(mat, GROUND)
