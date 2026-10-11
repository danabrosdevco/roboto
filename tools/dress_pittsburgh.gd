extends "res://tools/mapdeck.gd"

# ─────────────────────────────────────────────
# DRESS PITTSBURGH — a statics pass on maps/pittsburgh_art.tscn in the WORKS
# theme: the plant nobody shut down. It ADDS; it moves nothing that is there.
#
#   godot --headless --path . --script res://tools/dress_pittsburgh.gd
#   ...and again with --apply.
#
# Safe to run because of the split: this writes the ART scene, and every
# objective, patrol, cover point, spawn and exit lives in the LEVEL, which this
# tool never opens.
#
# THE BRIDGES AND THE AREAS ARE NOT TOUCHED. Nothing is placed on a bridge, in
# a river or on a road, and nothing existing is moved or removed. Everything
# this adds goes under Dressing/Works_* so the whole pass can be lifted back
# out in one go if it is wrong.
#
# LANES ARE KEPT FOR VEHICLES, and they come from the map rather than from me.
# The terrain paints its own road network into the control map, so anywhere
# with road paint on it is left clear with a margin — which keeps every route
# the level already had. On top of that each objective gets a clear circle,
# because a rover that cannot get to the fight is a rover that is not in it,
# and the lanes between neighbouring objectives are kept open the same way.
# ─────────────────────────────────────────────

const ART := "res://maps/pittsburgh_art.tscn"
const DATA := "res://maps/terrain_data/pittsburgh_level_terrain.res"
const Split := preload("res://tools/level_split.gd")
## Slag, clinker and broken ground. The existing layers on this map come to
## about twenty a hectare between them, which is one piece every twenty-two
## metres — nothing at all in the near ground you actually look at, and the
## single biggest reason the land reads as bare however much is standing on it.
const SCATTER := "res://maps/blocks/scatter/scatter_works.tres"

## How much clear ground a road keeps either side of itself.
const ROAD_CLEAR := 7.0
## A rover needs this much room through a fight, measured off the widest thing
## that has to use it.
const LANE_HALF := 9.0
## Clear circle round every objective, so the ground it is fought over on stays
## ground and not a scrapyard.
const OBJECTIVE_CLEAR := 20.0

## Where the squad and its vehicles have to be able to drive, as polylines in
## metres. These are the routes between the places the missions care about;
## the painted roads are kept clear on top of these, not instead of them.
const LANES: Array = [
	# North bank: staging, through the depot, into the Ohio Works, to the dam.
	[Vector2(-491, 351), Vector2(-430, 250), Vector2(-360, 150), Vector2(-330, 20),
		Vector2(-352, -100), Vector2(-320, -150), Vector2(-298, -161)],
	# The works to the shore and on east along the Allegheny.
	[Vector2(-352, -132), Vector2(-260, -90), Vector2(-155, -45), Vector2(-20, -60),
		Vector2(100, -85), Vector2(240, -180), Vector2(352, -265)],
	# South bank: the bridgehead east to the furnace and the coke works.
	[Vector2(85, 78), Vector2(200, 140), Vector2(320, 200), Vector2(395, 237),
		Vector2(480, 250), Vector2(538, 266)],
	# The island crossing.
	[Vector2(-250, -84), Vector2(-200, -20), Vector2(-160, 40)],
]

## District, and what goes in it. Ops are the deck's own: at / row / grid /
## ring, in metres, filtered through everything above before they are placed.
const WORKS: Array = [
	# ── OHIO WORKS ────────────────────────────────────────────────────────────
	# The one that already reads best, built out into a full plant: two
	# furnaces and a stack on the high side, the gas holders and pipe runs
	# behind them, hot metal on rail, and the scrap and coal that feed it.
	["OhioWorks", [
		["at", "industrial/industrial_blast_furnace", -396.0, -176.0, 20.0],
		["at", "industrial/industrial_blast_furnace", -352.0, -196.0, 20.0],
		["at", "industrial/industrial_smokestack", -420.0, -140.0, 0.0],
		["at", "industrial/industrial_smokestack", -300.0, -206.0, 0.0],
		["row", "industrial/industrial_gas_sphere", -440.0, -60.0, -330.0, -30.0, 16.0],
		["row", "industrial/industrial_pipe_rack", -430.0, -100.0, -300.0, -100.0, 2.0],
		["row", "industrial/industrial_pipe_rack", -420.0, -76.0, -310.0, -76.0, 2.0],
		["row", "industrial/industrial_conveyor", -300.0, -190.0, -240.0, -140.0, 3.0],
		["row", "industrial/industrial_rail_track", -460.0, -46.0, -250.0, -46.0, 0.0],
		["row", "industrial/industrial_rail_tank_car", -430.0, -46.0, -330.0, -46.0, 5.0],
		["row", "industrial/industrial_rail_gondola", -310.0, -46.0, -250.0, -46.0, 5.0],
		["at", "industrial/industrial_gantry_crane", -390.0, -10.0, 90.0],
		["at", "industrial/industrial_coal_pile", -466.0, -10.0, 0.0],
		["at", "industrial/industrial_coal_pile", -446.0, 14.0, 0.0],
		["at", "industrial/industrial_scrap_yard", -420.0, 30.0, 30.0],
		["at", "industrial/industrial_substation", -280.0, -60.0, 0.0],
		["at", "industrial/industrial_water_tower", -410.0, -210.0, 0.0],
		["at", "industrial/industrial_plant_office", -270.0, -20.0, 0.0],
		["row", "industrial/industrial_warehouse_long", -470.0, 80.0, -340.0, 80.0, 14.0],
		["row", "machines/machine_steel_coils", -300.0, 20.0, -220.0, 20.0, 10.0],
		["row", "props/prop_barrels", -330.0, -80.0, -260.0, -80.0, 14.0],
		# More of it, because this is the district that already reads best and
		# the one worth over-building rather than under-building.
		["row", "industrial/industrial_pipe_rack", -280.0, -130.0, -180.0, -130.0, 2.0],
		["row", "features/feature_fuel_tanks", -470.0, -60.0, -470.0, 40.0, 18.0],
		["row", "industrial/industrial_silos", -250.0, -160.0, -190.0, -160.0, 10.0],
		["row", "machines/machine_semi_truck", -300.0, 60.0, -200.0, 60.0, 16.0],
		["row", "props/prop_concrete_pipes", -240.0, 60.0, -180.0, 60.0, 12.0],
		["row", "props/prop_crates", -350.0, 40.0, -270.0, 40.0, 12.0],
		["at", "industrial/industrial_gatehouse", -300.0, 100.0, 0.0],
		["at", "industrial/industrial_parking_lot", -230.0, 20.0, 0.0],
		["row", "props/prop_robot_wreck", -400.0, -120.0, -300.0, -120.0, 24.0],
	]],
	# ── THE FURNACE AND THE COKE WORKS ────────────────────────────────────────
	["Furnace", [
		["at", "industrial/industrial_blast_furnace", 360.0, 196.0, 200.0],
		["at", "industrial/industrial_smokestack", 430.0, 200.0, 0.0],
		["row", "industrial/industrial_gas_sphere", 300.0, 290.0, 400.0, 290.0, 16.0],
		["row", "industrial/industrial_pipe_rack", 320.0, 180.0, 430.0, 180.0, 2.0],
		["at", "industrial/industrial_coal_pile", 300.0, 250.0, 0.0],
		["at", "industrial/industrial_gantry_crane", 450.0, 250.0, 0.0],
		["row", "machines/machine_steel_coils", 440.0, 300.0, 520.0, 300.0, 10.0],
	]],
	["CokeWorks", [
		["row", "industrial/industrial_silos", 560.0, 200.0, 620.0, 200.0, 8.0],
		["row", "industrial/industrial_conveyor", 545.0, 210.0, 545.0, 300.0, 3.0],
		["at", "industrial/industrial_smokestack", 600.0, 300.0, 0.0],
		["row", "industrial/industrial_pipe_rack", 500.0, 310.0, 600.0, 310.0, 2.0],
		["at", "industrial/industrial_coal_pile", 580.0, 330.0, 0.0],
		["at", "industrial/industrial_substation", 620.0, 260.0, 0.0],
	]],
	# ── THE PORT ──────────────────────────────────────────────────────────────
	["Port", [
		["row", "industrial/industrial_gantry_crane", 330.0, -330.0, 440.0, -330.0, 40.0],
		["grid", "industrial/industrial_container_yard", 300.0, -380.0, 460.0, -300.0, 0.0, 20.0],
		["row", "industrial/industrial_conveyor", 400.0, -300.0, 400.0, -230.0, 3.0],
		["at", "industrial/industrial_warehouse_long", 470.0, -350.0, 90.0],
		["at", "industrial/industrial_water_tower", 300.0, -230.0, 0.0],
	]],
	# ── THE STRIP ─────────────────────────────────────────────────────────────
	["Strip", [
		["row", "industrial/industrial_rail_track", -20.0, -130.0, 200.0, -130.0, 0.0],
		["row", "industrial/industrial_rail_boxcar", 20.0, -130.0, 140.0, -130.0, 5.0],
		["row", "industrial/industrial_warehouse_long", 0.0, -170.0, 180.0, -170.0, 16.0],
		["at", "industrial/industrial_sawtooth_factory", 220.0, -140.0, 0.0],
		["at", "industrial/industrial_water_tower", -40.0, -160.0, 0.0],
		["row", "features/feature_container_stack", 40.0, -40.0, 160.0, -40.0, 18.0],
	]],
	# ── THE DEPOT AND THE STAGING END ─────────────────────────────────────────
	["DroneDepot", [
		["row", "industrial/industrial_hangar_shed", -380.0, 190.0, -260.0, 190.0, 16.0],
		["at", "industrial/industrial_substation", -250.0, 130.0, 0.0],
		["row", "machines/machine_pallet_rack", -360.0, 110.0, -280.0, 110.0, 8.0],
	]],
	["Staging", [
		["row", "machines/machine_semi_truck", -540.0, 310.0, -440.0, 310.0, 16.0],
		["row", "features/feature_fuel_tanks", -560.0, 380.0, -470.0, 380.0, 22.0],
		["at", "industrial/industrial_gatehouse", -450.0, 330.0, 0.0],
	]],
	# ── THE RAIL UP THE VALLEY ────────────────────────────────────────────────
	["ValleyRail", [
		["row", "industrial/industrial_rail_track", -450.0, 330.0, -420.0, 20.0, 0.0],
		["row", "industrial/industrial_rail_gondola", -440.0, 260.0, -426.0, 140.0, 6.0],
	]],
]

## Micro-terrain and litter. The land itself, not what stands on it — this is
## the half of the pass that answers "more visual texture to the land", and it
## is deliberately spread wide rather than gathered into the districts.
const GROUND: Array = [
	["row", "ground/ground_swell", -480.0, 60.0, -180.0, 60.0, 30.0],
	["row", "ground/ground_swell", -120.0, 200.0, 220.0, 200.0, 30.0],
	["row", "ground/ground_swell", 260.0, -120.0, 560.0, -120.0, 30.0],
	["row", "ground/ground_swell", 200.0, 320.0, 520.0, 320.0, 30.0],
	["row", "ground/ground_berm", -420.0, -230.0, -240.0, -230.0, 26.0],
	["row", "ground/ground_berm", 300.0, 140.0, 500.0, 140.0, 26.0],
	["row", "ground/ground_berm", -60.0, -200.0, 160.0, -200.0, 26.0],
	["row", "ground/ground_spoil", -460.0, -120.0, -260.0, -120.0, 34.0],
	["row", "ground/ground_spoil", 380.0, 170.0, 560.0, 170.0, 34.0],
	["row", "ground/ground_spoil", 40.0, 160.0, 240.0, 160.0, 34.0],
	["row", "ground/ground_washout", -200.0, 120.0, -40.0, 120.0, 30.0],
	["row", "ground/ground_washout", 240.0, -60.0, 400.0, -60.0, 30.0],
	["row", "ground/ground_track", -470.0, 0.0, -200.0, 0.0, 6.0],
	["row", "ground/ground_track", 60.0, 240.0, 340.0, 240.0, 6.0],
	["row", "props/prop_dirt_mound", -440.0, 200.0, -200.0, 200.0, 40.0],
	["row", "props/prop_rubble_pile", 180.0, -300.0, 460.0, -300.0, 44.0],
	["row", "props/prop_boulder_b", -160.0, 300.0, 200.0, 300.0, 50.0],
	["row", "props/prop_rock_slabs", 360.0, 60.0, 620.0, 60.0, 46.0],
	["row", "props/prop_power_pole", -480.0, -260.0, 100.0, -260.0, 60.0],
	["row", "props/prop_power_pole", 120.0, 340.0, 560.0, 340.0, 60.0],
]

var _d: Data = null
var _blockers: Array = []          ## [centre, radius] of everything already there


func _initialize() -> void:
	await process_frame
	var apply := OS.get_cmdline_user_args().has("--apply")
	_d = load(DATA) as Data
	if _d == null:
		print("FAIL  no terrain data at %s" % DATA)
		quit(1)
		return
	var packed := load(ART) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % ART)
		quit(1)
		return
	var art := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var dressing := art.get_node_or_null(^"Dressing")
	if dressing == null:
		print("FAIL  %s has no Dressing group" % ART.get_file())
		quit(1)
		return
	# EVERYTHING THIS PASS ADDS GOES FIRST, so the table can be tuned and the
	# tool re-run. Without this the second run finds its own first run standing
	# in the way and places nothing, which is correct and useless.
	var cleared := 0
	for g in dressing.get_children():
		if str(g.name).begins_with("Works_"):
			cleared += g.get_child_count()
			dressing.remove_child(g)
			g.queue_free()
	if cleared > 0:
		print("   cleared %d piece(s) from a previous run of this pass" % cleared)
	_add_scatter(art)
	_survey(art)
	print("   %d piece(s) already on the map, left where they are" % _blockers.size())

	var made := 0
	var dropped := 0
	for entry: Array in WORKS + [["Ground", GROUND]]:
		var group: Node3D = null
		var n := 0
		for op: Array in entry[1]:
			var packed_piece := load("res://maps/blocks/%s.tscn" % op[1]) as PackedScene
			if packed_piece == null:
				continue
			for row: Array in _placements(_d, op):
				var at: Vector3 = row[0]
				var why := _refuse(at, _size_of(op[1]))
				if why != "":
					dropped += 1
					continue
				if group == null:
					group = Node3D.new()
					group.name = "Works_%s" % entry[0]
					dressing.add_child(group)
					group.owner = art
				var inst := packed_piece.instantiate() as Node3D
				group.add_child(inst)
				inst.owner = art
				inst.position = at
				inst.rotation.y = deg_to_rad(float(row[1]))
				inst.name = "W%03d_%s" % [n, str(op[1]).get_file()]
				_blockers.append([Vector2(at.x, at.z), _reach(_size_of(op[1]))])
				n += 1
				made += 1
		if n > 0:
			print("   %-12s %3d piece(s)" % [entry[0], n])
	print("   %d placed, %d refused (road, river, lane, objective or already taken)" % [
			made, dropped])
	if not apply:
		print("   DRY RUN — pass --apply")
		quit()
		return
	Split.reown(art, art, null, null, {})
	var uid := ResourceLoader.get_resource_uid(ART)
	var out := PackedScene.new()
	if out.pack(art) != OK or ResourceSaver.save(out, ART) != OK:
		print("FAIL  could not write %s" % ART)
		quit(1)
		return
	# The uid goes back on by hand: pack() makes a new resource with no
	# identity, and the level that instances this art points at it by uid.
	# Stripping the written-out script defaults is reinstance.gd's job, which
	# is run straight after — no sense having two tools that both do it.
	if uid != ResourceUID.INVALID_ID:
		var text := FileAccess.get_file_as_string(ART)
		var head := text.get_slice("\n", 0)
		if not head.contains("uid="):
			var f := FileAccess.open(ART, FileAccess.WRITE)
			f.store_string(head.replace("]", " uid=\"%s\"]" % ResourceUID.id_to_text(uid))
					+ text.substr(head.length()))
			f.close()
		ResourceUID.set_id(uid, ART)
	print("      wrote %s. Run reinstance.gd on it, then REBAKE." % ART.get_file())
	print("DRESS PITTSBURGH DONE")
	quit()


## Everything already standing on the map, so this pass puts nothing through
## it. Measured off each piece's own meshes rather than assumed.
func _survey(art: Node3D) -> void:
	for n: Node3D in art.find_children("*", "Node3D", true, false):
		if n.scene_file_path == "" or not n.scene_file_path.begins_with("res://maps/blocks/"):
			continue
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var b := mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		_blockers.append([_world_xz(art, n), _reach(box)])


func _reach(box: AABB) -> float:
	return maxf(box.size.x, box.size.z) * 0.5


## Why this spot cannot have something on it, or "" if it can.
func _refuse(at: Vector3, box: AABB) -> String:
	var p := Vector2(at.x, at.z)
	var r := _reach(box)
	if is_nan(at.y):
		return "off the map"
	if _d.water_at_local(at.x, at.z):
		return "river"
	# THE ROADS ARE THE LANES. The terrain paints its own network into the
	# control map's red channel, so reading it keeps every route the level
	# already had without me having to know where any of them go.
	for a in 8:
		var s := p + Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * (r + ROAD_CLEAR)
		if _d.control_at_local(s.x, s.y).r > 0.18:
			return "road"
	if _d.control_at_local(at.x, at.z).r > 0.18:
		return "road"
	for lane: Array in LANES:
		for i in lane.size() - 1:
			if _to_segment(p, lane[i], lane[i + 1]) < r + LANE_HALF:
				return "lane"
	for o: Array in OBJECTIVES:
		if p.distance_to(Vector2(o[0], o[1])) < r + OBJECTIVE_CLEAR:
			return "objective"
	for b: Array in _blockers:
		if p.distance_to(b[0]) < r + float(b[1]) + 2.0:
			return "taken"
	return ""


## The objectives this level's missions are written against, so the ground they
## are fought over stays clear. Read off maps/pittsburgh_level.tscn.
const OBJECTIVES: Array = [
	[-298.0, -161.0], [-155.0, -45.0], [100.0, -85.0], [395.0, 237.0],
	[352.0, -265.0], [-250.0, -84.0], [85.0, 78.0], [538.0, 266.0],
]


func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Where a node sits in the map, worked up the parent chain. The art scene is
## not in the tree — putting it there to ask would rebuild every mesh on it —
## so global_transform is not available and this is the honest way to get it.
func _world_xz(art: Node3D, n: Node3D) -> Vector2:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != art.get_parent():
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return Vector2(t.origin.x, t.origin.z)


## Adds the works litter layer to the terrain's scatter, once.
func _add_scatter(art: Node3D) -> void:
	var scatter := art.get_node_or_null(^"Terrain/Scatter")
	if scatter == null:
		print("   no Terrain/Scatter to add the litter layer to")
		return
	var layer := load(SCATTER)
	if layer == null:
		return
	var layers: Array = scatter.layers
	for l in layers:
		if l != null and l.resource_path == SCATTER:
			print("   litter layer already on")
			return
	layers.append(layer)
	scatter.layers = layers
	print("   litter layer added — %d layer(s) on the terrain now" % layers.size())
