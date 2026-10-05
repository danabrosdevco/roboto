extends SceneTree

# ─────────────────────────────────────────────
# BUILD GEORGETOWN — assembles maps/georgetown_art.tscn and
# maps/georgetown_level.tscn: the C&O Canal on its terrace, the mills along
# it, the town above, the waterfront below and the Potomac with Arlington
# across it.
#
#   godot --headless --path . --script res://tools/build_georgetown.gd
#   godot --headless --path . --script res://tools/build_georgetown.gd -- --force
#
# THE HILL IS FOUR FLAT BENCHES, NOT A SLOPE. The brief was a map on a hill
# running down to the river, and this project already knows what a painted
# hill does to a squad: bodies cannot use jagged ground, and height is
# supposed to come from built assets. Georgetown happens to be exactly that
# already — a town that steps down to the Potomac in terraces, each held up by
# a stone wall. So the hill here is:
#
#   UPPER TOWN   z = +7.0   the streets above, where a map starts
#   CANAL        z =  0.0   the towpath, the prism cut 3 m into it
#   LOWER YARDS  z = -4.0   the old industrial level between canal and river
#   WATERFRONT   z = -7.0   the esplanade, and the river 2.4 m under that
#
# Fourteen metres of fall across about 150 m, every metre of it in a wall you
# can see, and the only ways between benches are the stairs, the ramped
# streets and the bridges. That is the map: a player can always tell which
# level they are on and what is above them, and a squad can always be ordered
# somewhere without being asked to walk up a slope it cannot use.
#
# THE CANAL IS THE SPINE. It runs the whole width of the map on the middle
# bench, 9 m wide and 3 m deep with vertical stone both sides. A squad in it
# is committed until the next stair or bridge; a squad on the towpath is
# shooting down into a slot. Everything else is arranged around who holds the
# crossings.
#
# WHAT IT DOES NOT DO: bake the navmesh.
#
#   BAKE_ONLY=1 LEVEL=res://maps/georgetown_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

const ART := "res://maps/georgetown_art.tscn"
const LEVEL := "res://maps/georgetown_level.tscn"
const B := "res://maps/blocks/canal/%s.tscn"
const B_STREETS := "res://maps/blocks/streets/%s.tscn"
const B_SUBURBAN := "res://maps/blocks/suburban/%s.tscn"
const B_PROPS := "res://maps/blocks/props/%s.tscn"
const B_POLARIS := "res://maps/blocks/polaris/%s.tscn"

# ── Which way round everything goes ──────────────────────────────────────────
#
# FUNCGODOT MAPS QUAKE (x, y, z) TO GODOT (y, z, x), so a block built along
# its map X runs along GODOT'S Z, and a block whose front is its map +Y faces
# GODOT'S +X. Written here once; the Polaris build learned this the hard way.
#
# On this map the CANAL runs east-west along the site's X, and the hill falls
# toward +Z, which is south, toward the river.
const ALONG_X := 90.0
const ALONG_Z := 0.0
const FACE_EAST := 0.0
const FACE_NORTH := 90.0
const FACE_WEST := 180.0
const FACE_SOUTH := 270.0

## The benches. Every height in this file is one of these.
const Z_TOWN := 7.0
const Z_CANAL := 0.0
const Z_YARDS := -4.0
const Z_WHARF := -7.0

## Where each bench sits across the site, in Godot Z. The canal's own
## cross-section is 9 m of prism plus a towpath and a berm, so the bench it
## sits on is about 26 m deep and the others take what is left.
const S_TOWN := -96.0
const S_CANAL := 0.0
const S_YARDS := 54.0
const S_WHARF := 116.0

## How far the map runs east-west. The prism tiles in 32 m pieces.
const RUN := 14

var _cache := {}


func _initialize() -> void:
	await process_frame
	var force := OS.get_cmdline_user_args().has("--force")
	for p: String in [ART, LEVEL]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(p)) and not force:
			print("SKIP  %s exists — pass --force to rebuild it." % p)
			quit()
			return

	var art := Node3D.new()
	art.name = "GeorgetownArt"
	root.add_child(art)

	_benches(art)
	_canal(art)
	_mills(art)
	_upper_town(art)
	_lower_yards(art)
	_waterfront(art)

	var placed := _own(art, art)
	var packed := PackedScene.new()
	var err := packed.pack(art)
	if err != OK:
		print("FAIL  could not pack the art scene (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, ART)
	if err != OK:
		print("FAIL  could not save %s (%s)" % [ART, error_string(err)])
		quit(1)
		return
	print("      %s  %d pieces" % [ART.get_file(), placed])
	_write_level()
	print("      %s" % LEVEL.get_file())
	print("BUILD GEORGETOWN DONE")
	quit()


## Instance ROOTS are owned by the art root and nothing inside them is: a
## packed scene writes what its root owns, and owning an instance's internals
## writes them out as declared nodes and quietly stops edits to the block
## reaching the level that instances it.
func _own(node: Node, root_node: Node) -> int:
	var n := 0
	for c in node.get_children():
		c.owner = root_node
		if c.scene_file_path != "":
			n += 1
			continue
		n += _own(c, root_node)
	return n


func _put(parent: Node3D, path: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0, name := "") -> Node3D:
	if not _cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("build_georgetown: no prefab at %s — nothing placed" % path)
			_cache[path] = null
			return null
		_cache[path] = packed
	if _cache[path] == null:
		return null
	var inst := (_cache[path] as PackedScene).instantiate() as Node3D
	inst.name = name if name != "" else path.get_file().get_basename()
	parent.add_child(inst)
	inst.position = Vector3(x, y, z)
	inst.rotation_degrees = Vector3(0.0, yaw, 0.0)
	return inst


func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


## The X of the i-th 32 m bay, so every row on the map lines up with the
## canal instead of drifting out of step with it.
func _bay(i: int) -> float:
	return (i - RUN * 0.5 + 0.5) * 32.0


# ── The benches ──────────────────────────────────────────────────────────────

## The four flat levels and the walls between them.
##
## EACH BENCH IS TILED FROM 32 M STRIPS TO THE DEPTH IT ACTUALLY NEEDS, and
## the canal bench has a HOLE IN IT where the prism goes. The first version
## used one 460 x 360 plate per bench; they overlapped by two hundred metres
## and the town's plate lay on top of the canal and buried it completely. A
## slab you cannot see the top of is the easiest thing in the world to get
## wrong, because from inside the editor it looks like nothing at all.
func _benches(art: Node3D) -> void:
	var g := _group(art, "Benches")
	# name, bench height, from Z, to Z. The canal's own prism piece brings its
	# bed, walls, towpath and berm with it, so the bench skips -12 .. +12.
	var strips: Array = [
		["Town", Z_TOWN, -264.0, -48.0],
		["CanalN", Z_CANAL, -48.0, -12.0],
		["CanalS", Z_CANAL, 12.0, 44.0],
		["Yards", Z_YARDS, 44.0, 104.0],
		["Wharf", Z_WHARF, 104.0, 164.0],
	]
	for s: Array in strips:
		var from: float = s[2]
		var to: float = s[3]
		var rows := int(ceil((to - from) / 32.0))
		for i in rows:
			_put(g, B % "canal_bench", 0.0, from + 16.0 + i * 32.0, ALONG_X, s[1], "%s_%d" % [s[0], i])
	# The retaining wall at the front of each bench, looking down at the next.
	var walls: Array = [
		[Z_TOWN, -46.0],
		[Z_CANAL, 46.0],
		[Z_YARDS, 106.0],
	]
	for w: Array in walls:
		for i in RUN:
			_put(g, B % "canal_terrace_wall", _bay(i), w[1], ALONG_X + 180.0, w[0], "Wall_%.0f_%d" % [w[1], i])


# ── The canal ────────────────────────────────────────────────────────────────

## THE PRISM, bay by bay, with the bridges and the one lock. The bridges are
## placed at bays 2, 6 and 11 — three crossings in 450 m, which is enough that
## the canal is a barrier and few enough that holding one matters.
func _canal(art: Node3D) -> void:
	var g := _group(art, "Canal")
	const BRIDGES := {2: "truss", 6: "road", 11: "truss"}
	for i in RUN:
		if i == 8:
			_put(g, B % "canal_lock", _bay(i), S_CANAL, ALONG_X, Z_CANAL, "Lock")
			continue
		var piece := "canal_prism" if i < 10 else "canal_prism_open"
		_put(g, B % piece, _bay(i), S_CANAL, ALONG_X, Z_CANAL, "Prism_%d" % i)
	for i: int in BRIDGES:
		var kind: String = BRIDGES[i]
		_put(g, B % ("canal_truss_bridge" if kind == "truss" else "canal_road_bridge"),
				_bay(i), S_CANAL, ALONG_X, Z_CANAL, "Bridge_%d" % i)
	# The stairs into the bed. Only two, and both well away from a bridge, so
	# getting into the prism and getting out of it are separate decisions.
	for i: int in [4, 12]:
		_put(g, B % "canal_stair_down", _bay(i) + 9.0, S_CANAL, ALONG_X, Z_CANAL, "CanalStair_%d" % i)
	# The dewatering works in the bed: bags, barriers and an outfall.
	for i: int in [3, 9]:
		_put(g, B % "canal_cofferdam", _bay(i) - 6.0, S_CANAL + 1.5, ALONG_X, Z_CANAL, "Cofferdam_%d" % i)
	for i: int in [1, 7, 13]:
		_put(g, B % "canal_outfall", _bay(i) + 4.0, S_CANAL, ALONG_X, Z_CANAL, "Outfall_%d" % i)
	for i in RUN:
		if posmod(i, 3) != 0:
			continue
		_put(g, B_STREETS % "street_light_cobra", _bay(i), S_CANAL + 11.0, FACE_NORTH, Z_CANAL, "TowLight_%d" % i)


## THE MILLS along the canal's north side, standing on the terrace above the
## berm so their ground floors ARE the wall. Mixed heights deliberately: a row
## of one building repeated is a wall, a row of three is a street.
func _mills(art: Node3D) -> void:
	var g := _group(art, "Mills")
	var z := S_CANAL - 22.0
	var kinds: Array = ["mill_brick_long", "mill_warehouse_stone", "mill_brick_tall",
			"mill_brick_long", "mill_warehouse_stone"]
	for i in 5:
		_put(g, B % kinds[i], -200.0 + i * 92.0, z, FACE_SOUTH, Z_CANAL + 3.0, "Mill_%d" % i)
	# The café terraces, cantilevered over the canal wall between the mills.
	for i: int in [0, 1]:
		_put(g, B % "mill_cafe_terrace", -154.0 + i * 184.0, S_CANAL - 14.0, ALONG_X, Z_CANAL + 3.0, "Cafe_%d" % i)
	# The modern block at the east end, on the far side of the towpath — the
	# one that throws its shadow across the canal in the photograph.
	_put(g, B % "mill_office_modern", 188.0, S_CANAL + 30.0, FACE_WEST, Z_CANAL, "OfficeBlock")


## THE TOWN ABOVE: streets, blocks and the stairs down to the canal. This is
## where a mission starts, and it is deliberately the tightest ground on the
## map — the open stuff is all below.
func _upper_town(art: Node3D) -> void:
	var g := _group(art, "UpperTown")
	for i in RUN:
		_put(g, B_STREETS % "street_road_two_lane", _bay(i), S_TOWN, ALONG_X, Z_TOWN, "MStreet_%d" % i)
		if posmod(i, 2) == 0:
			_put(g, B_STREETS % "street_sidewalk_run", _bay(i), S_TOWN - 22.0, ALONG_X, Z_TOWN, "TownWalk_%d" % i)
	var kinds: Array = ["suburb_townhouse_row", "mill_brick_long", "suburb_townhouse_row"]
	for i in 6:
		var kind: String = kinds[i % 3]
		var path: String = (B % kind) if kind.begins_with("mill") else ("res://maps/blocks/suburbs/%s.tscn" % kind)
		_put(g, path, -190.0 + i * 76.0, S_TOWN - 40.0, FACE_SOUTH, Z_TOWN, "TownBlock_%d" % i)
	# Down to the canal: two public stairs and one ramped street, which are
	# the only three ways off this bench.
	for i: int in [3, 10]:
		_put(g, B % "canal_terrace_stair", _bay(i), S_TOWN + 42.0, ALONG_Z, Z_CANAL, "TownStair_%d" % i)
	_put(g, B % "canal_street_ramp", _bay(7) + 4.0, S_TOWN + 46.0, ALONG_Z, Z_CANAL, "TownRamp")


## THE LOWER YARDS between canal and river: the old working level, still
## industrial. Open enough to cross, broken enough to cross badly.
func _lower_yards(art: Node3D) -> void:
	var g := _group(art, "LowerYards")
	for i in RUN:
		if posmod(i, 2) != 0:
			continue
		_put(g, B_STREETS % "street_alley", _bay(i), S_YARDS + 16.0, ALONG_X, Z_YARDS, "YardAlley_%d" % i)
	for i in 4:
		_put(g, B % "mill_warehouse_stone", -170.0 + i * 108.0, S_YARDS + 34.0, FACE_SOUTH, Z_YARDS, "Yard_%d" % i)
	for i in 3:
		_put(g, B_SUBURBAN % "suburban_service_dock", -120.0 + i * 120.0, S_YARDS + 6.0, FACE_NORTH, Z_YARDS, "YardDock_%d" % i)
	for i: int in [2, 9]:
		_put(g, B % "canal_terrace_stair", _bay(i) + 12.0, S_YARDS - 2.0, ALONG_Z, Z_YARDS, "YardStair_%d" % i)
	_put(g, B % "canal_street_ramp", _bay(12), S_YARDS - 2.0, ALONG_Z, Z_YARDS, "YardRamp")
	for i in RUN:
		if posmod(i, 4) != 0:
			continue
		_put(g, B_STREETS % "street_utility_cabinet", _bay(i) + 8.0, S_YARDS + 24.0, FACE_SOUTH, Z_YARDS, "Cab_%d" % i)


## THE WATERFRONT: the esplanade, a pier, the river and Arlington across it.
## The bottom of the map and its one open flank.
func _waterfront(art: Node3D) -> void:
	var g := _group(art, "Waterfront")
	for i in 10:
		_put(g, B % "wharf_esplanade", -216.0 + i * 48.0, S_WHARF, ALONG_X, Z_WHARF, "Esplanade_%d" % i)
	for i: int in [0, 1, 2]:
		_put(g, B % "wharf_pier", -140.0 + i * 140.0, S_WHARF + 14.0, ALONG_X, Z_WHARF, "Pier_%d" % i)
	for i: int in [4, 11]:
		_put(g, B % "canal_terrace_stair", _bay(i) + 6.0, S_WHARF - 4.0, ALONG_Z, Z_WHARF, "WharfStair_%d" % i)
	_put(g, B % "wharf_river", 0.0, S_WHARF + 2.0, ALONG_X, Z_WHARF, "Potomac")
	# Arlington, 320 m across the water. Mesh only and never walked on: it is
	# a horizon, and the moment anything can reach it, it has to be a map.
	_put(g, B % "wharf_far_shore", 0.0, S_WHARF + 330.0, ALONG_X, Z_WHARF + 1.0, "Arlington")
	for i in 8:
		_put(g, B_STREETS % "street_light_cobra", -200.0 + i * 58.0, S_WHARF - 6.0, FACE_SOUTH, Z_WHARF, "WharfLight_%d" % i)


# ── The level ────────────────────────────────────────────────────────────────

## Objective anchors. TERRAIN puts the pins in and names them; what a mission
## does with them is GAMEPLAY's, which is why these are places and not tasks.
## node, tag, label, x, y, z
const OBJECTIVES: Array = [
	["GT_Lock", "obj_gt_lock", "The Lock", 80.0, -3.0, 0.0],
	["GT_TrussWest", "obj_gt_truss_west", "West Footbridge", -112.0, 0.0, 0.0],
	["GT_RoadBridge", "obj_gt_road_bridge", "The Street Bridge", 16.0, 0.0, 0.0],
	["GT_Cofferdam", "obj_gt_cofferdam", "The Cofferdam", -86.0, -3.0, 1.5],
	["GT_Mill", "obj_gt_mill", "The Long Mill", -200.0, 3.0, -22.0],
	["GT_Ramp", "obj_gt_ramp", "The Ramped Street", 116.0, 3.5, -50.0],
	["GT_Yards", "obj_gt_yards", "The Lower Yards", -62.0, -4.0, 88.0],
	["GT_Esplanade", "obj_gt_esplanade", "The Esplanade", 40.0, -7.0, 116.0],
	["GT_Pier", "obj_gt_pier", "The Centre Pier", 0.0, -7.0, 130.0],
]


## The level scene, written as text: a handful of nodes with an ext_resource
## list. The art scene is packed instead, because it is hundreds of instances.
func _write_level() -> void:
	var objs := PackedStringArray()
	for o: Array in OBJECTIVES:
		objs.append(('[node name="%s" type="Node3D" parent="NavigationRegion3D/Objectives"]\n'
				+ 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)') % [o[0], o[3], o[4], o[5]])
	var text := """[gd_scene load_steps=7 format=3]

[ext_resource type="PackedScene" path="%s" id="1_art"]
[ext_resource type="PackedScene" uid="uid://g7fmy28elpah" path="res://Env/world_objects/spawn_point.tscn" id="2_spawn"]

[sub_resource type="ProceduralSkyMaterial" id="Sky_mat"]
sky_top_color = Color(0.52, 0.55, 0.58, 1)
sky_horizon_color = Color(0.68, 0.69, 0.69, 1)
ground_bottom_color = Color(0.45, 0.46, 0.47, 1)
ground_horizon_color = Color(0.68, 0.69, 0.69, 1)

[sub_resource type="Sky" id="Sky_gt"]
sky_material = SubResource("Sky_mat")

[sub_resource type="Environment" id="Env_gt"]
background_mode = 2
sky = SubResource("Sky_gt")
ambient_light_source = 3
ambient_light_color = Color(0.46, 0.47, 0.49, 1)
ambient_light_sky_contribution = 0.7
ambient_light_energy = 0.85
tonemap_mode = 2
fog_enabled = true
fog_light_color = Color(0.68, 0.69, 0.7, 1)
fog_density = 0.0006

[sub_resource type="NavigationMesh" id="NavigationMesh_gt"]
cell_size = 0.25
agent_radius = 0.5
agent_height = 1.8
agent_max_climb = 0.25
region_min_size = 16.0
edge_max_error = 1.3
detail_sample_distance = 6.0
geometry_parsed_geometry_type = 1
filter_baking_aabb = AABB(-260, -16, -140, 520, 48, 300)

[node name="GeorgetownLevel" type="Node3D"]

[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]
navigation_mesh = SubResource("NavigationMesh_gt")

[node name="GeorgetownArt" parent="NavigationRegion3D" instance=ExtResource("1_art")]

[node name="Objectives" type="Node3D" parent="NavigationRegion3D"]

%s

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_gt")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.82, 0.33, -0.46, 0, 0.81, 0.58, 0.57, -0.48, 0.67, 0, 80, 0)
light_energy = 0.9
light_color = Color(1, 0.98, 0.95, 1)
shadow_enabled = true
directional_shadow_max_distance = 260.0

[node name="SpawnPoint" parent="." instance=ExtResource("2_spawn")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -170, 7, -118)
""" % [ART, "\n\n".join(objs)]
	var f := FileAccess.open(LEVEL, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [LEVEL, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(text)
	f.close()
