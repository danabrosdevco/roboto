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
# THE TRENCH SYSTEM — three routes across no-man's-land, laid from the kit in
# tools/block_trench.gd — is at the bottom of this file. It reads the kit's
# manifest and its prefabs, so run, in this order:
#
#   godot --headless --path . --script res://tools/block_trench.gd -- maps/blocks --force
#   godot --path . --script res://tools/block_prefabs.gd -- maps/blocks/trench --force
#   godot --headless --path . --script res://tools/build_salient.gd -- --force
#
# AFTERWARDS: bake the navmesh, which nothing here does.
#
#   BAKE_ONLY=1 LEVEL=res://maps/salient_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

const ID := "the_salient"
const LEVEL := "res://maps/salient_level.tscn"
const ART := "res://maps/salient_art.tscn"
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
var _placed: Array = []


func _initialize() -> void:
	await process_frame
	for m: Dictionary in _deck:
		if m.id == ID:
			_map = m
	if _map.is_empty():
		print("FAIL  no deck entry called %s" % ID)
		quit(1)
		return
	if not _load_kit() or not _lay_routes():
		quit(1)
		return
	_landmarks()
	var force := OS.get_cmdline_user_args().has("--force")
	if FileAccess.file_exists(ProjectSettings.globalize_path(LEVEL)) and not force \
			and not ResourceLoader.exists(DATA):
		pass                                  # first pass of a fresh build
	_sketch()
	var r := _recipe()
	_data = Generator.generate(r, _paths() + _earth_modifiers())
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

	# THE ART IS REWRITTEN EVERY RUN. THE LEVEL IS WRITTEN ONCE.
	#
	# This is the whole answer to "the regenerator does not preserve nodes it
	# did not place". It does not have to preserve them, because it never opens
	# the file they are in. The art scene holds the terrain and everything
	# standing on it and is TERRAIN's to overwrite; the level scene holds the
	# spawn, the exit, the objective anchors and whatever GAMEPLAY adds, and is
	# never touched again after it is created. The only thing that crosses is
	# the navmesh, and probe_nav_hillfort writes that back by replacing two
	# lines rather than rewriting the scene.
	#
	# A merge would have been the other way to do it, and it is the wrong one:
	# a file boundary cannot be got subtly wrong. Either the art is rewritten
	# and the level is untouched, or nothing happened.
	if not _write(ART, _art_scene(r), 4000):
		return
	var have_level := FileAccess.file_exists(ProjectSettings.globalize_path(LEVEL))
	if have_level and not OS.get_cmdline_user_args().has("--force-level"):
		print("      %s left alone — it is GAMEPLAY's once it exists." % LEVEL.get_file())
	else:
		if have_level:
			print("      --force-level: OVERWRITING %s, and everything anyone" % LEVEL.get_file())
			print("      else put in it — the exit, the objectives, the spawn move.")
		if not _write(LEVEL, _level_scene(), 800):
			return
	print("      %s  %.0f x %.0f m at %.2f m cells, %d piece(s)" % [ART.get_file(),
			_data.width(), _data.depth(), r.cell_size, _placed.size()])
	print("      kit: %d piece(s) on three routes, %d guard clash(es) at placement" % [_laid.size(), _clashes])
	if not ResourceLoader.exists(DATA):
		print("      terrain data written but not yet importable — RUN THIS AGAIN")
	print("BUILD SALIENT DONE")
	quit()


## Writes, or refuses to. A builder that reports success over a truncated file
## is the worst failure this project has had: it looks done and is not.
func _write(path: String, text: String, least: int) -> bool:
	if text.length() < least:
		print("FAIL  %s came out %d characters; something threw" % [path.get_file(), text.length()])
		quit(1)
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return true


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

## THE ART. Terrain, what shapes it and everything standing on it — and
## nothing else. Rewritten every run.
func _art_scene(r: Recipe) -> String:
	var out := PackedStringArray()
	var ext: Array = [
		["Script", "res://Env/terrain/generated_terrain.gd", "5_terrain"],
		["Script", "res://Env/terrain/terrain_recipe.gd", "6_recipe"],
		["Script", "res://Env/terrain/terrain_path.gd", "8_path"],
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
	for op: Array in _map.get("dress", []):
		for row: Array in _placements(_data, op):
			placed.append([op[1], row[0], row[1]])
	# THE DECK'S DRESSING KNOWS NOTHING OF THE ROUTES. Whatever stands where one
	# runs comes out, before the ext_resources are listed: a piece whose every
	# row was dropped must not be declared and then never used.
	placed = _drop_on_routes(placed)
	print("      %d piece(s) of dressing dropped where a route runs" % _dropped)
	var pieces: Array = []
	for row: Array in placed:
		if not pieces.has(row[0]):
			pieces.append(row[0])
			ext.append(["PackedScene", "res://maps/blocks/%s.tscn" % row[0],
					"p_" + str(row[0]).get_file()])
	ext.append(["Script", STAMP_SCRIPT, "17_stamp"])
	var kit_pieces: Array = []
	for p: Dictionary in _laid:
		if not kit_pieces.has(p.piece):
			kit_pieces.append(p.piece)
			ext.append(["PackedScene", KIT_SCENES % p.piece, "t_" + str(p.piece)])
	# Everything the guard is to be checked against, registered before a kit
	# piece goes down. The dressing is not checked against itself.
	_registry = []
	var n_reg := 0
	for row: Array in placed:
		var pos: Vector3 = row[1]
		var xf := Transform3D(Basis(Vector3.UP, -deg_to_rad(float(row[2]))), pos)
		_register("%s@(%.0f,%.0f)" % [str(row[0]).get_file(), pos.x, pos.z], "res://maps/blocks/%s.tscn" % row[0], xf)
		n_reg += 1

	var subs := PackedStringArray()
	subs.append_array(_recipe_sub(r))
	var curves: Array = []
	for i in (_map.get("paths", []) as Array).size():
		curves.append("Curve3D_t%02d" % i)
		subs.append_array(_curve_sub(curves[i], _map.paths[i][4]))
	var ramp_ids: Array = []
	for rec: Dictionary in _flat + _dig:
		if str(rec.k) == "ramp":
			ramp_ids.append("Curve3D_e%03d" % ramp_ids.size())
	subs.append_array(_ramp_curves(ramp_ids))
	out.append("[gd_scene load_steps=%d format=3]" % (ext.size() + _count_subs(subs) + 1))
	out.append("")
	for e: Array in ext:
		out.append("[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]" % [e[0], e[1], e[2]])
	out.append("")
	out.append_array(subs)

	# ── The tree ──
	_placed = placed
	out.append("[node name=\"SalientArt\" type=\"Node3D\"]")
	out.append("")
	out.append("[node name=\"Terrain\" type=\"Node3D\" parent=\".\"]")
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
		out.append("[node name=\"Scatter\" type=\"Node3D\" parent=\"Terrain\"]")
		out.append("script = ExtResource(\"15_scatter\")")
		out.append("layers = Array[ExtResource(\"16_layer\")]([%s])" % ", ".join(ids))
		out.append("")
	out.append("[node name=\"Trenches\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	for i in curves.size():
		var p: Array = _map.paths[i]
		out.append("[node name=\"Cut%02d\" type=\"Path3D\" parent=\"Terrain/Trenches\"]" % i)
		out.append("curve = SubResource(\"%s\")" % curves[i])
		out.append("script = ExtResource(\"8_path\")")
		out.append("mode = %d" % PATH_MODE[p[0]])
		out.append("width = %s" % _n(float(p[1])))
		out.append("depth = %s" % _n(float(p[2])))
		out.append("falloff = %s" % _n(float(p[3])))
		out.append("smoothing = %s" % _n(float(p[5]) if p.size() > 5 else 8.0))
		out.append("")
	# THE GROUND THE ROUTES NEED, as the stamps and ramps that dug it. Applied
	# above, in this order; written here so the editor makes the same ground.
	out.append("[node name=\"Earthworks\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	out.append_array(_earth_nodes(ramp_ids))
	out.append("[node name=\"Works\" type=\"Node3D\" parent=\".\"]")
	out.append("")
	var n := 1
	for row: Array in placed:
		var piece: String = row[0]
		var pos: Vector3 = row[1]
		out.append("[node name=\"W%04d_%s\" parent=\"Works\" instance=ExtResource(\"p_%s\")]" % [
				n, str(piece).get_file(), str(piece).get_file()])
		out.append(_yawed(pos, float(row[2])))
		out.append("")
		n += 1
	# THE KIT. Each piece is checked against everything before it as it goes down.
	out.append("[node name=\"Trenchworks\" type=\"Node3D\" parent=\".\"]")
	out.append("")
	_trench_nodes(out)
	out.append_array(_anchor_nodes())
	return "\n".join(out) + "\n"


## THE LEVEL. The spawn, the exit, the objective anchors, the environment and
## the navigation region — and one instance of the art. WRITTEN ONCE: after
## that it belongs to whoever is putting missions in it, and this tool does not
## open it again without --force-level.
func _level_scene() -> String:
	var out := PackedStringArray()
	var ext: Array = [
		["Script", "res://maps/trench_broom_level.gd", "1_level"],
		["PackedScene", "res://Env/world_objects/spawn_point.tscn", "2_spawn"],
		["Script", "res://Campaign/squad_spawn_point.gd", "3_squad"],
		["PackedScene", ART, "4_art"],
		["PackedScene", "res://Env/world_objects/level_exit.tscn", "10_exit"],
		["PackedScene", "res://Env/world_environment.tscn", "11_env"],
		["PackedScene", "res://Env/world_objects/squad_objective_point.tscn", "14_sqpoint"],
	]
	if ResourceLoader.exists(ENVIRON):
		ext.append(["Environment", ENVIRON, "12_env"])
	var subs := PackedStringArray([
		"[sub_resource type=\"NavigationMesh\" id=\"NavigationMesh_salient\"]",
		# EMPTY, BUT PRESENT. probe_nav_hillfort writes the bake back by finding
		# these two lines and replacing them; without them it bakes fine,
		# reports forty thousand vertices and has nowhere to put them. Two
		# lines is also why a rebake does not count as touching this file.
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
		""])
	out.append("[gd_scene load_steps=%d format=3]" % (ext.size() + 2))
	out.append("")
	for e: Array in ext:
		out.append("[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]" % [e[0], e[1], e[2]])
	out.append("")
	out.append_array(subs)
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
	out.append("max_slots = 999")
	out.append("")
	out.append("[node name=\"NavigationRegion3D\" type=\"NavigationRegion3D\" parent=\".\"]")
	out.append("navigation_mesh = SubResource(\"NavigationMesh_salient\")")
	out.append("")
	# THE ART GOES UNDER THE REGION, so the baker walks it. It is one node here
	# and a whole scene on the other side of the file boundary.
	out.append("[node name=\"SalientArt\" parent=\"NavigationRegion3D\" instance=ExtResource(\"4_art\")]")
	out.append("")
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
	var tilts := PackedStringArray()
	var nums := PackedStringArray()
	for v: Vector2 in pts:
		# in, out, position — three Vector3s a point, which is how Curve3D
		# stores itself.
		nums.append_array(PackedStringArray(["0", "0", "0", "0", "0", "0",
				_n(v.x), "0", _n(v.y)]))
		tilts.append("0")
	return PackedStringArray(["[sub_resource type=\"Curve3D\" id=\"%s\"]" % id,
			"bake_interval = 2.0",
			"_data = {",
			"\"points\": PackedVector3Array(%s)," % ", ".join(nums),
			"\"tilts\": PackedFloat32Array(%s)" % ", ".join(tilts),
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
	# AND INSIDE THE KIT. An objective in a trench wall is as cut off as one in a
	# building, and the routes were laid after the objectives were typed.
	for o: Array in OBJECTIVES:
		var hit := _kit_piece_at(Vector2(float(o[3]), float(o[4])))
		if hit != "":
			print("      %-28s is inside kit piece %s" % [o[0], hit])
			bad += 1
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


# ═════════════════════════════════════════════════════════════════════════════
# THE TRENCH SYSTEM — three ways across no-man's-land.
#
# The middle of this map was bare cracked mud, so crossing it was a walk into
# fire with nothing to use. It now has three routes, each with a different cost,
# built from the kit in tools/block_trench.gd:
#
#   A  THE SUNKEN ROAD    a cut running diagonally across. Fast and covered, but
#                         a blown span leaves you exposed for 40 m in the middle.
#   B  THE CRATER CHAIN   linked shell holes with scrapes between them. Slow and
#                         safe from fire, and it dead-ends at an uncut wire belt
#                         you have to flank.
#   C  THE COMMUNICATION  a proper zigzag. Completely safe, and it funnels into
#      TRENCH             one pillbox's arc at the far end.
#
# DESCRIBE ONCE, DERIVE THE REST. Nothing here says where anything else is.
# The front lines come from the objective table, the communication trenches
# the routes leave from and the pillboxes they run at come from the deck entry
# the rest of the map is built from, and everything a piece needs to know about
# itself (how long it is, where it joins the next, how much ground it takes) is
# read from the manifest block_trench.gd wrote. Move a pillbox and a route
# follows it; change the length of a run and the route refits.
#
# THE GROUND IS DERIVED TOO. A brush cannot dig a heightfield, so each piece's
# dig list becomes terrain stamps, written to the scene as TerrainStamp nodes
# and applied to the terrain here, off one record: the saved terrain and what
# the editor regenerates cannot disagree.
# ═════════════════════════════════════════════════════════════════════════════

const KIT := "res://maps/blocks/trench/trench_kit.json"
const KIT_SCENES := "res://maps/blocks/trench/%s.tscn"
const STAMP_SCRIPT := "res://Env/terrain/terrain_stamp.gd"

## Metres of ground, from a front-line trench, before a route's first ramp: past
## the berm and the revetment, so the route does not start inside either.
const FRONT_CLEAR := 26.0
## The same at the enemy end, from the enemy front trench to a route's last ramp.
const ENEMY_CLEAR := 24.0
## How far the middle route keeps from the mine crater: its rim, and room.
const CRATER_CLEAR := 24.0
## The crater chain's wire belt, and where the chain stops short of it.
const BELT_BEHIND := 44.0
const CHAIN_SHORT := 12.0
## How far past the end of the sunken road its gapped belt stands.
const ROAD_MOUTH := 10.0
## Ground is levelled this far past every piece (and blended over FLAT_FALL
## more), so the squad never meets a piece across a bank. Salient's own ground is
## rough, with craters down to -7 m and hills up to +2, so this is real work.
const FLAT_MARGIN := 5.0
const FLAT_FALL := 7.0
## A deck piece closer to a kit piece than this is dropped. Salient's dressing
## is scattered by rows and does not know the routes exist.
const DROP_MARGIN := 2.5
## The probe's own measure of "inside each other" is 12 m3; this is the point at
## which a deck piece is dropped for tripping it against a kit piece.
const DROP_M3 := 2.0
## Volume two colliders must share before the guard calls it a clash. The
## colliders are shrunk by GUARD_SHRINK first, so faces that merely touch count
## for nothing.
const GUARD_M3 := 0.25
const GUARD_SHRINK := 0.015

var _kit: Dictionary = {}
var _kit_section: Dictionary = {}
## One entry per kit piece put down: {name, piece, origin, a, route, y}. `a` is
## the heading in degrees from east toward south, which is the way the route
## walks, and is NOT the scene's yaw -- see _theta.
var _laid: Array = []
## Terrain edits, as records. Levelling first and digging after, always.
var _flat: Array = []
var _dig: Array = []
var _marks: Dictionary = {}
var _heading: Dictionary = {}
var _clashes := 0
var _dropped := 0
var _shape_cache: Dictionary = {}
var _registry: Array = []


func _load_kit() -> bool:
	if not FileAccess.file_exists(KIT):
		print("FAIL  %s is missing — run tools/block_trench.gd, then block_prefabs.gd, first" % KIT)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("pieces"):
		print("FAIL  %s is not a kit manifest" % KIT)
		return false
	_kit = (parsed as Dictionary).pieces
	_kit_section = (parsed as Dictionary).get("section", {})
	return true


# ── Frames. FuncGodot's axes, written once. ─────────────────────────────────
#
# A piece is built with +X along it and +Y to the left of its run, and FuncGodot
# maps Quake (x, y, z) to Godot (y, z, x): its +X lies along Godot +Z and its +Y
# along Godot +X. A route heading is therefore kept as `a`, degrees from +X
# (east) toward +Z (south), and the scene's yaw falls out of it:
#
#   forward   (cos a, sin a)       in (x, z)
#   left      (sin a, -cos a)      facing east, left is north (-z)
#   yaw       90 - a               so a piece laid facing east is yawed 90

func _dirv(a: float) -> Vector2:
	return Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))


func _leftv(a: float) -> Vector2:
	return Vector2(sin(deg_to_rad(a)), -cos(deg_to_rad(a)))


## A vector in a piece's own frame, turned into the world's.
func _rot(a: float, local: Vector2) -> Vector2:
	return _dirv(a) * local.x + _leftv(a) * local.y


func _rel(origin: Vector2, a: float, local: Vector2) -> Vector2:
	return origin + _rot(a, local)


func _theta(a: float) -> float:
	return deg_to_rad(90.0 - a)


func _pp(piece: String, port: String) -> Vector2:
	var ports: Dictionary = (_kit[piece] as Dictionary).ports
	if not ports.has(port):
		push_warning("build_salient: %s has no port '%s' — using its origin" % [piece, port])
		return Vector2.ZERO
	return Vector2(float(ports[port].x), float(ports[port].y))


func _objective(node: String) -> Vector2:
	for o: Array in OBJECTIVES:
		if str(o[0]) == node:
			return Vector2(float(o[3]), float(o[4]))
	push_warning("build_salient: no objective called %s — routes cannot anchor to it" % node)
	return Vector2.ZERO


## The z of every communication trench that ends at the friendly front line,
## from the deck entry's own trench cuts.
func _comm_trenches(front_x: float) -> Array:
	var out: Array = []
	for p: Array in _map.get("paths", []):
		var pts: Array = p[4]
		if str(p[0]) != "trench" or pts.size() != 2:
			continue
		if absf((pts[0] as Vector2).y - (pts[1] as Vector2).y) > 0.01:
			continue
		if absf(maxf((pts[0] as Vector2).x, (pts[1] as Vector2).x) - front_x) < 0.01:
			out.append((pts[0] as Vector2).y)
	out.sort()
	return out


## The z of every pillbox on the enemy's front line.
func _enemy_pillboxes(front_x: float) -> Array:
	var out: Array = []
	for op: Array in _map.get("dress", []):
		if str(op[0]) == "at" and str(op[1]) == "features/feature_pillbox" and float(op[2]) > front_x:
			out.append(float(op[3]))
	out.sort()
	return out


# ── Laying a route ───────────────────────────────────────────────────────────

func _lay_routes() -> bool:
	_laid = []
	_flat = []
	_dig = []
	_marks = {}
	var jump := _objective("Salient_Jumpoff")
	var enemy := _objective("Salient_FrontLine")
	var crater := _objective("Salient_Crater")
	var comm := _comm_trenches(jump.x)
	var pills := _enemy_pillboxes(enemy.x)
	if comm.size() < 3 or pills.size() < 3:
		print("FAIL  the deck entry has %d friendly communication trench(es) and %d enemy pillbox(es); the routes need three of each" % [comm.size(), pills.size()])
		return false

	# A — the sunken road. It leaves from the northern communication trench and
	# crosses on the diagonal: east, a bend, SOUTH down the middle of the map, a
	# bend, east again to the enemy line. The south leg is where the span is
	# blown, so the enemy, to the east, sees the whole 40 m of it side on.
	#
	# A STAIRCASE, NOT A STRAIGHT DIAGONAL, because every piece in the kit is laid
	# square to the map. A straight diagonal of 32 m pieces is a chain of rotated
	# boxes, and the level probe measures a piece by the axis-aligned box round its
	# collision: two rotated walls that merely touch score as 128 m3 inside each
	# other, six times over. Squared-off, they score nothing.
	var a_start := Vector2(jump.x + FRONT_CLEAR, comm[0])
	var a_goal := Vector2(enemy.x - ENEMY_CLEAR, a_start.y)
	var road_run := [["sunken_road_run", _length("sunken_road_run")]]
	var road := _lay("A", ["sunken_road_ramp:down", {"fill": road_run, "share": 0.5}, "sunken_road_corner_r",
			"sunken_road_blown", "sunken_road_corner", {"fill": road_run, "share": 0.5},
			"sunken_road_ramp:up"], a_start, a_goal)
	# A GAP IN THE WIRE across the road's mouth: the way out is a funnel, and a
	# funnel is a killing ground. The belt stands where the road actually ends, with
	# its gap on the road's own line.
	_belt("A", (road.pos as Vector2) + _dirv(float(road.a)) * ROAD_MOUTH, float(road.a), "wire_belt_gap")

	# B — the crater chain, down the southern communication trench's line, and the
	# belt of wire it dead-ends at.
	var belt_x := enemy.x - BELT_BEHIND
	var b_start := Vector2(jump.x + FRONT_CLEAR, comm[2])
	var b_goal := Vector2(belt_x - CHAIN_SHORT, comm[2])
	var chain := _lay("B", [{"fill": [["crater_linked", _length("crater_linked")]], "share": 1.0}, "crater_single_deep"], b_start, b_goal)
	# The belt goes where the chain ACTUALLY ends, not where it was meant to: the
	# chain is a whole number of pieces and rarely comes out to the metre.
	_belt("B", (chain.pos as Vector2) + _dirv(float(chain.a)) * CHAIN_SHORT, float(chain.a))

	# C — the communication trench, between the mine crater and the middle
	# pillbox, running at it.
	var c_z := crater.y - CRATER_CLEAR
	var c_start := Vector2(jump.x + FRONT_CLEAR, c_z)
	var c_goal := Vector2(enemy.x - ENEMY_CLEAR, c_z)
	var fire := [["trench_run_32", _length("trench_run_32")], ["trench_run_16", _length("trench_run_16")]]
	_lay("C", ["trench_ramp_end:down", "trench_run_32", "trench_traverse", "trench_traverse_r",
			"trench_firebay", {"piece": "trench_junction_t", "branch": ["trench_sap_head"]},
			"trench_run_32", "trench_dugout", "trench_traverse_r", "trench_traverse", "trench_collapsed",
			{"fill": fire, "share": 1.0}, "trench_ramp_end:up"], c_start, c_goal)
	return true


## How far a piece carries a route along its heading.
func _length(piece: String) -> float:
	if not _kit.has(piece):
		push_warning("build_salient: the kit has no piece called %s" % piece)
		return 1.0
	var ports: Dictionary = (_kit[piece] as Dictionary).ports
	return float(ports.out.x) - float(ports["in"].x)


## Lays `steps` from `start` toward `goal`, fitting the fillers to the distance.
## The first walk records nothing and only measures where the fixed pieces leave
## the route; the second lays it, with the filler counts that make up the rest.
func _lay(route: String, steps: Array, start: Vector2, goal: Vector2) -> Dictionary:
	var a := rad_to_deg(atan2(goal.y - start.y, goal.x - start.x))
	_heading[route] = a
	var dry := _walk(route, steps, start, a, [], false)
	var rem: float = (goal - (dry.pos as Vector2)).dot(_dirv(a))
	var counts := _fill_counts(steps, rem)
	var wet := _walk(route, steps, start, a, counts, true)
	# Every route has an entry. The two that begin on a ramp have marked it; the
	# crater chain simply begins, so its entry is where it starts.
	if not _marks.has(route + ".entry"):
		_marks[route + ".entry"] = start
	var mine := 0
	for p: Dictionary in _laid:
		if str(p.route).begins_with(route) and not p.decor:
			mine += 1
	print("      route %s: heading %.1f, %d piece(s), %.1f m short of its goal" % [route, a, mine,
			(goal - (wet.pos as Vector2)).dot(_dirv(a))])
	return wet


## How many of each filler go in each fill step. The biggest unit first. Never
## rounded UP: a route that stops short of its goal is a few metres of open
## ground, and one that runs past it is inside the enemy's trench.
func _fill_counts(steps: Array, rem: float) -> Array:
	var fills: Array = []
	for s: Variant in steps:
		if s is Dictionary and (s as Dictionary).has("fill"):
			fills.append(s)
	var out: Array = []
	if fills.is_empty():
		return out
	var units: Array = (fills[0] as Dictionary).fill
	var big: Array = units[0]
	var n_big := 0
	var n_small := 0
	if units.size() == 1:
		n_big = maxi(floori(rem / float(big[1])), 0)
	else:
		n_big = maxi(floori(rem / float(big[1])), 0)
		var left: float = rem - n_big * float(big[1])
		n_small = maxi(floori(left / float((units[1] as Array)[1])), 0)
	var share_done := 0.0
	var given := 0
	for i in fills.size():
		share_done += float((fills[i] as Dictionary).get("share", 1.0))
		var upto := roundi(share_done * n_big)
		var c := {big[0]: upto - given}
		given = upto
		if i == 0 and units.size() > 1:
			c[(units[1] as Array)[0]] = n_small
		out.append(c)
	return out


func _walk(route: String, steps: Array, pos0: Vector2, a0: float, counts: Array, record: bool) -> Dictionary:
	var pos := pos0
	var a := a0
	var fill_i := 0
	for step: Variant in steps:
		if step is Dictionary and (step as Dictionary).has("fill"):
			var c: Dictionary = counts[fill_i] if fill_i < counts.size() else {}
			fill_i += 1
			for unit: Array in (step as Dictionary).fill:
				for k in int(c.get(unit[0], 0)):
					var r := _step(route, str(unit[0]), pos, a, record)
					pos = r.pos
					a = r.a
			continue
		var piece := ""
		var branch: Array = []
		if step is Dictionary:
			piece = str((step as Dictionary).piece)
			branch = (step as Dictionary).get("branch", [])
		else:
			piece = str(step)
		var res := _step(route, piece, pos, a, record)
		if record and not branch.is_empty():
			var base := piece.split(":")[0]
			var bp := _pp(base, "branch")
			var turn := float(((_kit[base] as Dictionary).ports.branch as Dictionary).turn)
			_walk(route + "s", branch, _rel(res.origin, res.a_piece, bp), float(res.a_piece) - turn, [], true)
		pos = res.pos
		a = res.a
	return {"pos": pos, "a": a}


## One piece, laid so its entry meets `pos` heading `a`. "name:down" is a ramp
## entered from the ground, "name:up" one left onto it.
func _step(route: String, token: String, pos: Vector2, a: float, record: bool) -> Dictionary:
	var parts := token.split(":")
	var piece := parts[0]
	var mode := parts[1] if parts.size() > 1 else ""
	if not _kit.has(piece):
		push_warning("build_salient: the kit has no piece called %s — route %s stops short" % [piece, route])
		return {"pos": pos, "a": a, "origin": pos, "a_piece": a}
	var ports: Dictionary = (_kit[piece] as Dictionary).ports
	var a_piece := a
	var origin: Vector2
	var out_pos: Vector2
	var out_a := a
	if mode == "down":
		a_piece = a + 180.0
		origin = pos - _rot(a_piece, _pp(piece, "ground"))
		out_pos = _rel(origin, a_piece, _pp(piece, "trench"))
	elif mode == "up":
		origin = pos - _rot(a, _pp(piece, "trench"))
		out_pos = _rel(origin, a, _pp(piece, "ground"))
	else:
		origin = pos - _rot(a, _pp(piece, "in"))
		if ports.has("out"):
			out_pos = _rel(origin, a, _pp(piece, "out"))
			out_a = a - float(ports.out.turn)
		else:
			# A dead end (the sap head): the route stops where it began.
			out_pos = pos
	if record:
		_put(route, piece, origin, a_piece)
		# The little things that go on top of the pieces, and the marks other
		# systems derive their objectives from.
		if route == "C" and piece == "trench_run_32":
			_put(route, "duckboard_run", _rel(origin, a_piece, Vector2(-8.0, 0.0)), a_piece, true)
			_put(route, "duckboard_run", _rel(origin, a_piece, Vector2(8.0, 0.0)), a_piece, true)
		elif route == "C" and piece == "trench_run_16":
			_put(route, "duckboard_run", origin, a_piece, true)
		var marked := {"sunken_road_blown": ["A.blown", ""], "trench_sap_head": ["C.listening_post", "post"],
				"trench_dugout": ["C.dugout", "chamber"], "crater_single_deep": ["B.last_crater", "hole_in"]}
		if marked.has(piece):
			var m: Array = marked[piece]
			_marks[m[0]] = origin if m[1] == "" else _rel(origin, a_piece, _pp(piece, m[1]))
		if mode == "down" and not _marks.has(route + ".entry"):
			_marks[route + ".entry"] = pos
		if mode == "up":
			_marks[route + ".exit"] = pos
	return {"pos": out_pos, "a": out_a, "origin": origin, "a_piece": a_piece}


## Records a placed piece and the ground it takes and digs.
func _put(route: String, piece: String, origin: Vector2, a: float, decor: bool = false) -> void:
	var n := _laid.size()
	var name := "%s%02d_%s" % [route, n, piece]
	_laid.append({"name": name, "piece": piece, "origin": origin, "a": a, "route": route, "y": 0.0, "decor": decor})
	if decor:
		return
	var info: Dictionary = _kit[piece]
	var span: Array = info.span
	_flat.append(_rect_record(name, origin, a, float(span[0]) - FLAT_MARGIN, float(span[1]) - FLAT_MARGIN,
			float(span[2]) + FLAT_MARGIN, float(span[3]) + FLAT_MARGIN, 0.0, FLAT_FALL))
	for d: Dictionary in info.get("dig", []):
		match str(d.k):
			"rect":
				_dig.append(_rect_record(name, origin, a, float(d.x0), float(d.y0), float(d.x1), float(d.y1), float(d.y), float(d.f)))
			"disc":
				var c := _rel(origin, a, Vector2(float(d.x), float(d.y0)))
				_dig.append({"k": "disc", "src": name, "c": Vector3(c.x, float(d.y), c.y), "r": float(d.r), "f": float(d.f)})
			"ramp":
				var p0 := _rel(origin, a, Vector2(float(d.x0), 0.0))
				var p1 := _rel(origin, a, Vector2(float(d.x1), 0.0))
				_dig.append({"k": "ramp", "src": name, "pts": [Vector3(p0.x, float(d.ya), p0.y), Vector3(p1.x, float(d.yb), p1.y)],
						"half": float(d.half), "f": float(_kit_section.get("ramp_falloff", 0.6))})


## A rectangle of a piece's plan as a stamp: its centre, the yaw that turns the
## stamp's own axes onto the piece's, and the size along each. A stamp's X is
## the piece's left and its Z the piece's forward.
func _rect_record(src: String, origin: Vector2, a: float, x0: float, y0: float, x1: float, y1: float, y: float, f: float) -> Dictionary:
	var c := _rel(origin, a, Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5))
	return {"k": "rect", "src": src, "c": Vector3(c.x, y, c.y), "theta": _theta(a), "size": Vector2(y1 - y0, x1 - x0), "f": f}


## A belt of wire across a route's line: four runs side by side, long way across
## it, so the route runs into the middle of it and has to go round the ends.
func _belt(route: String, at: Vector2, a: float, piece: String = "wire_belt_run") -> void:
	var across := a + 90.0
	var run := _length(piece)
	# A gapped belt is one piece with its gap in the middle; a solid belt is four
	# runs side by side.
	var count := 1 if piece == "wire_belt_gap" else 4
	for k in count:
		var off := (k - (count - 1) * 0.5) * run
		_put(route, piece, at + _dirv(across) * off, across)
	_marks[route + ".wire"] = at


# ── The ground ───────────────────────────────────────────────────────────────

## The records as the modifiers TerrainGenerator applies. Levelling first, so
## every dig lands on level ground and none of them is levelled away.
func _earth_modifiers() -> Array:
	var out: Array = []
	for rec: Dictionary in _flat:
		out.append(_modifier(rec))
	for rec: Dictionary in _dig:
		out.append(_modifier(rec))
	return out


func _modifier(rec: Dictionary) -> Dictionary:
	var c: Vector3 = rec.c if rec.has("c") else (rec.pts[0] as Vector3)
	match str(rec.k):
		"ramp":
			var pts := PackedVector3Array()
			for p: Vector3 in rec.pts:
				pts.append(p)
			return {"type": "path", "source": str(rec.src), "mode": Generator.PATH_ROAD, "points": pts,
					"width": float(rec.half) * 2.0, "falloff": float(rec.f), "depth": 0.0,
					"follow_terrain": false, "smoothing": 0.0, "paint": false}
		"disc":
			return {"type": "stamp", "source": str(rec.src), "shape": Generator.STAMP_FLATTEN,
					"footprint": Generator.FOOTPRINT_CIRCLE, "centre": Vector2(c.x, c.z), "y": c.y,
					"radius": float(rec.r), "half_size": Vector2(1.0, 1.0), "axis_x": Vector2(1, 0),
					"axis_z": Vector2(0, 1), "falloff": float(rec.f), "amount": 0.0, "strength": 1.0,
					"paint": Generator.PAINT_NONE}
		_:
			var th: float = rec.theta
			var size: Vector2 = rec.size
			return {"type": "stamp", "source": str(rec.src), "shape": Generator.STAMP_FLATTEN,
					"footprint": Generator.FOOTPRINT_RECT, "centre": Vector2(c.x, c.z), "y": c.y,
					"radius": 10.0, "half_size": size * 0.5, "axis_x": Vector2(cos(th), -sin(th)),
					"axis_z": Vector2(sin(th), cos(th)), "falloff": float(rec.f), "amount": 0.0,
					"strength": 1.0, "paint": Generator.PAINT_NONE}


## The same records as scene nodes, so the editor's Generate button makes the
## ground this tool did. Stamps are Node3Ds with the stamp script; ramps are
## Path3Ds with curves of their own heights.
func _earth_nodes(subs_ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var n := 0
	var ramp_i := 0
	for rec: Dictionary in _flat + _dig:
		var nm := "E%04d" % n
		n += 1
		match str(rec.k):
			"ramp":
				out.append("[node name=\"%s\" type=\"Path3D\" parent=\"Terrain/Earthworks\"]" % nm)
				out.append("curve = SubResource(\"%s\")" % subs_ids[ramp_i])
				ramp_i += 1
				out.append("script = ExtResource(\"8_path\")")
				out.append("mode = 0")
				out.append("width = %s" % _n(float(rec.half) * 2.0))
				out.append("falloff = %s" % _n(float(rec.f)))
				out.append("depth = 0.0")
				out.append("follow_terrain = false")
				out.append("smoothing = 0.0")
				out.append("paint = false")
			"disc":
				var c: Vector3 = rec.c
				out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Terrain/Earthworks\"]" % nm)
				out.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % [_n(c.x), _n(c.y), _n(c.z)])
				out.append("script = ExtResource(\"17_stamp\")")
				out.append("radius = %s" % _n(float(rec.r)))
				out.append("falloff = %s" % _n(float(rec.f)))
				out.append("paint = 0")
			_:
				var c: Vector3 = rec.c
				var size: Vector2 = rec.size
				out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Terrain/Earthworks\"]" % nm)
				out.append("transform = %s" % var_to_str(Transform3D(Basis(Vector3.UP, float(rec.theta)), c)))
				out.append("script = ExtResource(\"17_stamp\")")
				out.append("footprint = 1")
				out.append("size = Vector2(%s, %s)" % [_n(size.x), _n(size.y)])
				out.append("falloff = %s" % _n(float(rec.f)))
				out.append("paint = 0")
		out.append("")
	return out


## Curve3D sub-resources for every ramp, in the order _earth_nodes uses them.
func _ramp_curves(ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	for rec: Dictionary in _flat + _dig:
		if str(rec.k) != "ramp":
			continue
		var nums := PackedStringArray()
		var tilts := PackedStringArray()
		for p: Vector3 in rec.pts:
			nums.append_array(PackedStringArray(["0", "0", "0", "0", "0", "0", _n(p.x), _n(p.y), _n(p.z)]))
			tilts.append("0")
		out.append_array(PackedStringArray(["[sub_resource type=\"Curve3D\" id=\"%s\"]" % ids[i],
				"bake_interval = 2.0",
				"_data = {",
				"\"points\": PackedVector3Array(%s)," % ", ".join(nums),
				"\"tilts\": PackedFloat32Array(%s)" % ", ".join(tilts),
				"}",
				"point_count = %d" % (rec.pts as Array).size(),
				""]))
		i += 1
	return out


# ── Keeping the dressing off the routes ─────────────────────────────────────

## Plan rectangles of every kit piece, grown by `margin`, as [origin, a, x0, y0, x1, y1].
func _footprints(margin: float) -> Array:
	var out: Array = []
	for p: Dictionary in _laid:
		var span: Array = (_kit[p.piece] as Dictionary).span
		out.append([p.origin, p.a, float(span[0]) - margin, float(span[1]) - margin,
				float(span[2]) + margin, float(span[3]) + margin])
	return out


## Whether a world point lies inside any of those rectangles.
func _in_footprint(pt: Vector2, rects: Array) -> bool:
	for r: Array in rects:
		var d := pt - (r[0] as Vector2)
		var lx := d.dot(_dirv(float(r[1])))
		var ly := d.dot(_leftv(float(r[1])))
		if lx >= float(r[2]) and lx <= float(r[4]) and ly >= float(r[3]) and ly <= float(r[5]):
			return true
	return false


## The deck's rows with those that stand on a route taken out. The dressing is
## scattered by rows and knows nothing about the routes: a tank trap in a trench
## is not a placement to fix, it is a placement that must not be there.
##
## TWO TESTS, because there are two things wrong with a piece near a route. One
## is standing ON it, which the footprint says (grown by DROP_MARGIN, so nothing
## is left hard against a wall). The other is being counted as inside it, which
## is how the level probe measures: by the axis-aligned box round a piece's
## collision, and 12 m3 is a fault. A piece can clear the footprint and still
## trip that, so the second test is the probe's own measure, taken at 2 m3.
func _drop_on_routes(placed: Array) -> Array:
	var rects := _footprints(DROP_MARGIN)
	var mine: Array = []
	for p: Dictionary in _laid:
		if p.decor:
			continue
		var shapes := _world_shapes(KIT_SCENES % p.piece, _kit_xf(p))
		if shapes.is_empty():
			continue
		var box: AABB = (shapes[0] as Dictionary).box
		for s: Dictionary in shapes:
			box = box.merge(s.box)
		mine.append(box)
	var kept: Array = []
	for row: Array in placed:
		var path := "res://maps/blocks/%s.tscn" % row[0]
		var pos: Vector3 = row[1]
		# Scene yaw of a deck row is the NEGATIVE of its number (see _yawed).
		var xf := Transform3D(Basis(Vector3.UP, -deg_to_rad(float(row[2]))), pos)
		var hit := false
		var box := _size_of(str(row[0]))
		for sx: float in [0.0, 0.5, 1.0]:
			for sz: float in [0.0, 0.5, 1.0]:
				var w := xf * Vector3(box.position.x + box.size.x * sx, 0.0, box.position.z + box.size.z * sz)
				if _in_footprint(Vector2(w.x, w.z), rects):
					hit = true
		if not hit:
			var shapes := _world_shapes(path, xf)
			if not shapes.is_empty():
				var theirs: AABB = (shapes[0] as Dictionary).box
				for s: Dictionary in shapes:
					theirs = theirs.merge(s.box)
				for m: AABB in mine:
					if not m.intersects(theirs):
						continue
					var i := m.intersection(theirs)
					if i.size.x * i.size.y * i.size.z > DROP_M3:
						hit = true
						break
		if hit:
			_dropped += 1
		else:
			kept.append(row)
	return kept


## A kit piece's transform in the world.
func _kit_xf(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _theta(float(p.a))), Vector3(p.origin.x, float(p.y), p.origin.y))


# ── The placement guard ──────────────────────────────────────────────────────
#
# EVERY PLACEMENT IS CHECKED AGAINST EVERY PREVIOUS ONE, AT THE MOMENT IT GOES
# DOWN, and the warning names both and the volume they share. The alternative --
# put pieces down, probe, move one, probe again -- is whack-a-mole: each piece
# moved lands on something else, and Georgetown took four passes to get from 70
# clashes to 50 that way. (Copied from build_polaris.gd's _guard, with one
# change: kit pieces are turned to any heading, and the axis-aligned box round
# a rotated 32 m wall is 28 x 15 m, so two walls that merely touch would report
# a clash. Here a collider is its own convex shape, and two are compared as
# shapes, shrunk by 1.5 cm so a shared face is nothing.)
#
# THE STANDING RULE: pieces may touch, they may not overlap.
#
# Salient's own dressing is registered first and is NOT checked against itself:
# that is the 195 pairs the level probe already counts and this pass was not
# asked to fix. It is only here to be hit.

## The collision shapes of a prefab in its own space: [{pts, box}].
func _shapes_of(path: String) -> Array:
	if _shape_cache.has(path):
		return _shape_cache[path]
	var out: Array = []
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("build_salient: guard cannot load %s — nothing placed from it is checked" % path)
		_shape_cache[path] = out
		return out
	var inst := packed.instantiate() as Node3D
	for cs: CollisionShape3D in inst.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var xf := Transform3D.IDENTITY
		var at: Node = cs
		while at != null and at != inst:
			if at is Node3D:
				xf = (at as Node3D).transform * xf
			at = at.get_parent()
		var pts := PackedVector3Array()
		var box := AABB()
		if cs.shape is ConvexPolygonShape3D:
			for p: Vector3 in (cs.shape as ConvexPolygonShape3D).points:
				pts.append(xf * p)
			if pts.size() > 0:
				box = AABB(pts[0], Vector3.ZERO)
				for p: Vector3 in pts:
					box = box.expand(p)
		if pts.size() == 0:
			var dbg := cs.shape.get_debug_mesh()
			if dbg == null:
				continue
			box = xf * dbg.get_aabb()
		out.append({"pts": pts, "box": box})
	inst.free()
	_shape_cache[path] = out
	return out


## A placed piece's shapes in the world.
func _world_shapes(path: String, xf: Transform3D) -> Array:
	var out: Array = []
	for s: Dictionary in _shapes_of(path):
		var pts := PackedVector3Array()
		for p: Vector3 in s.pts:
			pts.append(xf * p)
		var box: AABB = xf * (s.box as AABB)
		if pts.size() > 0:
			box = AABB(pts[0], Vector3.ZERO)
			for p: Vector3 in pts:
				box = box.expand(p)
		out.append({"pts": pts, "box": box})
	return out


## Registers a piece with no check, for the dressing that is only there to be hit.
func _register(name: String, path: String, xf: Transform3D) -> Dictionary:
	var shapes := _world_shapes(path, xf)
	var entry := {"name": name, "shapes": shapes, "box": AABB()}
	if not shapes.is_empty():
		var box: AABB = (shapes[0] as Dictionary).box
		for s: Dictionary in shapes:
			box = box.merge(s.box)
		entry.box = box
	_registry.append(entry)
	return entry


func _guard(name: String, path: String, xf: Transform3D) -> void:
	var entry := _register(name, path, xf)
	if (entry.shapes as Array).is_empty():
		return
	for oi in _registry.size() - 1:
		var other: Dictionary = _registry[oi]
		if (other.shapes as Array).is_empty():
			continue
		if not (entry.box as AABB).intersects(other.box):
			continue
		var shared := 0.0
		var where := AABB()
		var first := true
		for a: Dictionary in entry.shapes:
			for b: Dictionary in other.shapes:
				if not (a.box as AABB).intersects(b.box):
					continue
				var v := _shared_volume(a, b)
				if v <= 0.0:
					continue
				shared += v
				var s := (a.box as AABB).intersection(b.box)
				where = s if first else where.merge(s)
				first = false
		if shared > GUARD_M3:
			_clashes += 1
			var c := where.get_center()
			push_warning("build_salient: %s overlaps %s by %.1f m3 around (%.0f, %.1f, %.0f) — move one of them" % [
					name, other.name, shared, c.x, c.y, c.z])


## The planes of a convex point set, facing out: every plane through three
## points that has every other point on one side of it.
func _hull_planes(pts: PackedVector3Array) -> Array:
	var planes: Array = []
	var n := pts.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nrm := (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if nrm.length_squared() < 1e-10:
					continue
				nrm = nrm.normalized()
				var d := nrm.dot(pts[i])
				var above := false
				var below := false
				for m in n:
					var s := nrm.dot(pts[m]) - d
					if s > 1e-4:
						above = true
					elif s < -1e-4:
						below = true
					if above and below:
						break
				if above and below:
					continue
				if above:
					nrm = -nrm
					d = -d
				var dup := false
				for p: Plane in planes:
					if p.normal.dot(nrm) > 0.9999 and absf(p.d - d) < 1e-3:
						dup = true
						break
				if not dup:
					planes.append(Plane(nrm, d))
	return planes


func _box_planes(b: AABB) -> Array:
	return [Plane(Vector3.RIGHT, b.end.x), Plane(Vector3.LEFT, -b.position.x),
			Plane(Vector3.UP, b.end.y), Plane(Vector3.DOWN, -b.position.y),
			Plane(Vector3.BACK, b.end.z), Plane(Vector3.FORWARD, -b.position.z)]


func _planes_of(s: Dictionary) -> Array:
	if not s.has("planes"):
		s["planes"] = _hull_planes(s.pts) if (s.pts as PackedVector3Array).size() >= 4 else _box_planes(s.box)
	return s.planes


## The volume two convex shapes share, from the polytope their planes enclose
## once each has been pulled in by GUARD_SHRINK.
func _shared_volume(a: Dictionary, b: Dictionary) -> float:
	var both: Array[Plane] = []
	for p: Plane in _planes_of(a):
		both.append(Plane(p.normal, p.d - GUARD_SHRINK))
	for p: Plane in _planes_of(b):
		both.append(Plane(p.normal, p.d - GUARD_SHRINK))
	var pts := Geometry3D.compute_convex_mesh_points(both)
	if pts.size() < 4:
		return 0.0
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= pts.size()
	var vol := 0.0
	for pl: Plane in both:
		var on: Array = []
		for p: Vector3 in pts:
			if absf(pl.normal.dot(p) - pl.d) < 1e-3:
				on.append(p)
		if on.size() < 3:
			continue
		var fc := Vector3.ZERO
		for p: Vector3 in on:
			fc += p
		fc /= on.size()
		var u := (on[0] as Vector3 - fc).normalized()
		var v := pl.normal.cross(u)
		var ring: Array = on.duplicate()
		ring.sort_custom(func(p: Vector3, q: Vector3) -> bool:
				return atan2((p - fc).dot(v), (p - fc).dot(u)) < atan2((q - fc).dot(v), (q - fc).dot(u)))
		var area := 0.0
		for i in ring.size():
			area += ((ring[i] as Vector3) - fc).cross((ring[(i + 1) % ring.size()] as Vector3 - fc)).dot(pl.normal)
		vol += absf(area) * 0.5 * absf(pl.d - pl.normal.dot(c)) / 3.0
	return vol


## Every kit piece, as nodes, each checked on its way in. Heights are the
## ground's, which routes have levelled to 0.
func _trench_nodes(nodes_out: PackedStringArray) -> void:
	var routes := {"A": "SunkenRoad", "B": "CraterChain", "C": "CommTrench"}
	var made := {}
	for p: Dictionary in _laid:
		var key := str(p.route).substr(0, 1)
		var group: String = routes.get(key, "Landmarks")
		if not made.has(group):
			made[group] = true
			nodes_out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Trenchworks\"]" % group)
			nodes_out.append("")
		var xf := _kit_xf(p)
		nodes_out.append("[node name=\"%s\" parent=\"Trenchworks/%s\" instance=ExtResource(\"t_%s\")]" % [p.name, group, p.piece])
		nodes_out.append("transform = %s" % var_to_str(xf))
		nodes_out.append("")
		_guard(str(p.name), KIT_SCENES % p.piece, xf)


## The two landmarks: a tank nose-down in a shell hole beside the blown span, and
## a ruined observation post north of it. Both are placed from the route's own
## marks, so they follow the road if it moves.
func _landmarks() -> void:
	if not _marks.has("A.blown"):
		push_warning("build_salient: the sunken road has no blown span to hang landmarks on — no tank, no tower")
		return
	var blown: Vector2 = _marks["A.blown"]
	# The road runs south through its blown span, so "beside it" is measured off
	# the span's own heading, not the route's first one.
	var a := 0.0
	for p: Dictionary in _laid:
		if str(p.piece) == "sunken_road_blown":
			a = float(p.a)
	# On the enemy side of the road, nose toward it: something to give directions
	# by. (Not the friendly side: that is the pond, and a tank in a pond is a
	# wreck nobody can reach.)
	var tank := blown + _leftv(a) * 26.0
	_put("L", "tank_ditched", tank, a + 90.0)
	# Further out and up the road, against the skyline.
	var tower := blown + _leftv(a) * 46.0 - _dirv(a) * 20.0
	_put("L", "op_tower_ruin", tower, a)
	_marks["L.tank"] = tank
	_marks["L.tower"] = tower


## WHERE THE ROUTES' FEATURES ARE, as markers a mission can read. An objective
## typed from these numbers would drift the first time a route moved; a marker
## written from the route cannot. Nothing in the level scene is changed: whoever
## puts an objective on the blown span reads it from here (Trenchworks/Anchors).
func _anchor_nodes() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("[node name=\"Anchors\" type=\"Node3D\" parent=\"Trenchworks\"]")
	out.append("")
	var keys: Array = _marks.keys()
	keys.sort()
	for k: String in keys:
		var at: Vector2 = _marks[k]
		out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Trenchworks/Anchors\"]" % k.replace(".", "_"))
		out.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0, %s)" % [_n(at.x), _n(at.y)])
		out.append("")
	return out


## The name of the kit piece a world point lies in, or "".
func _kit_piece_at(pt: Vector2) -> String:
	for p: Dictionary in _laid:
		var span: Array = (_kit[p.piece] as Dictionary).span
		if _in_footprint(pt, [[p.origin, p.a, float(span[0]), float(span[1]), float(span[2]), float(span[3])]]):
			return str(p.name)
	return ""
