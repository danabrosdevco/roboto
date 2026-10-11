extends SceneTree

# ─────────────────────────────────────────────
# BUILD RAILHEAD — assembles maps/railhead_art.tscn, the armoured-train home
# base: seven cars on a bed, walked end to end.
#
#   godot --headless --path . --script res://tools/build_railhead.gd -- --force
#
# THIS WRITES THE ART SCENE AND NOTHING ELSE. There is no _write_level() in this
# file and there never will be. A level scene is where gameplay nodes live —
# spawns, the mission terminal, the exit, the stands — and a generator that
# writes one deletes them the next time it runs. That happened twice in a month
# on other levels; build_polaris.gd and build_georgetown.gd now both refuse to,
# and this one was never taught how. Gameplay attaches to the MARKERS below by
# name. Do not hand-place anything in the art scene either: it is regenerated.
#
# THE TRAIN runs along Godot Z. Car 1 (Motive) is at +Z, car 7 (Platform) at -Z,
# so walking the rake from the platform is walking toward +Z, past the
# consequences in sequence. Every car is placed with no yaw: map +X is Godot +Z
# (see block_railhead.gd), which is toward the locomotive.
#
# THE FLOOR is DECK_RISE above the ground in every car and flat. The one change
# of level is the boarding ramp in the Platform car.
#
# MARKERS are empty Node3Ds under Markers/, named plainly, recorded in _anchors
# at the moment each car is placed and derived from the car's transform and the
# constants block_railhead.gd owns. NOTHING HERE IS A TYPED COORDINATE: the
# Polaris objective was typed, the road moved by 6 m, and the marker ended up
# inside a wall. A marker that falls inside a collider is reported.
#
# WHAT IT DOES NOT DO: bake the navmesh. See _reach() for the geometric
# stand-in, and say plainly in any report that it is not a bake.
# ─────────────────────────────────────────────

const R := preload("res://tools/block_railhead.gd")

const ART := "res://maps/railhead_art.tscn"
## THE STATION, as one droppable scene: the prefab, its lights and its markers.
const STATION := "res://maps/railhead_station.tscn"
const B := "res://maps/blocks/railhead/%s.tscn"

## Car order, front to back: the thing you do last to the thing you do first.
const CARS: Array = [
	["Motive", "railhead_hull_motive"],
	["Operations", "railhead_car_ops"],
	["Repair", "railhead_car_repair"],
	["Armoury", "railhead_car_armoury"],
	["Fabrication", "railhead_car_fab"],
	["Barracks", "railhead_car_barracks"],
	["Platform", "railhead_car_platform"],
]
const PITCH := 32.0

var _cache := {}
var _placed: Array = []
var _clashes := 0
## Marker name -> world position, recorded as the cars go down.
var _anchors: Dictionary = {}
## Markers that are meant to be inside something solid (the table is the marker).
var _solid_ok: Array = ["HoloTable"]


## A marker that names a FIXTURE, not a place to stand: the table, and the
## machine mounts, fitted or empty. They sit inside or against solid things on
## purpose, so neither the inside-a-collider check nor the reach test applies.
func _fixture(k: String) -> bool:
	return _solid_ok.has(k) or k.begins_with("FabricationMount") or k == "Station_RampFoot" or k.begins_with("Station_TrackCut") or k.begins_with("Station_Mast") or k == "BriefingBoard" or k.begins_with("PlatformDoor_Leaf") or k.begins_with("Backdrop_")
var _cars: Dictionary = {}


func _initialize() -> void:
	await process_frame
	var force := OS.get_cmdline_user_args().has("--force")
	if FileAccess.file_exists(ProjectSettings.globalize_path(ART)) and not force:
		print("SKIP  %s exists — pass --force to rebuild it." % ART)
		quit()
		return

	var art := Node3D.new()
	art.name = "RailheadArt"
	root.add_child(art)

	var ground := _group(art, "Ground")
	_put(ground, B % "railhead_trackbed", 0.0, 0.0, 0.0, "Trackbed")
	if not _write_station():
		quit(1)
		return
	_put(ground, STATION, 0.0, 0.0, 0.0, "Station")

	var rake := _group(art, "Rake")
	rake.position.y = R.DECK_RISE
	for i in CARS.size():
		var z := (3 - i) * PITCH
		var car := _put(rake, B % CARS[i][1], 0.0, z, 0.0, "Car%d_%s" % [i + 1, CARS[i][0]])
		_cars[CARS[i][0]] = car
	_record_markers()

	var markers := _group(art, "Markers")
	for k: String in _anchors:
		var m := Node3D.new()
		m.name = k
		markers.add_child(m)
		m.global_position = _anchors[k]
	_lights(_group(art, "Lights"))

	_own(art, art)
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
	print("      %s  %d cars, %d markers" % [ART.get_file(), CARS.size(), _anchors.size()])
	print("      %s NOT written — this tool never writes a level." % "railhead_level.tscn")
	if _clashes > 0:
		print("      PLACEMENT GUARD: %d clash(es) — see the warnings above" % _clashes)
	else:
		print("      PLACEMENT GUARD: clean")
	var bad := _check_markers()
	_reach(R.WALKER_W, "Walker 1.7 m x 3.0 m")
	_reach(2.0, "Bulwark 1.9 m across the shoulders, 2.0 m allowed for the carried shield")
	print("BUILD RAILHEAD DONE")
	quit(1 if (_clashes > 0 or bad > 0) else 0)


## Instance ROOTS are owned by the art root and nothing inside them is, so an
## edit to a block in maps/blocks/ still reaches the level that instances it.
func _own(node: Node, root_node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c.scene_file_path != "":
			c.owner = root_node
			n += 1
			continue
		c.owner = root_node
		n += _own(c, root_node)
	return n


func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


func _put(parent: Node3D, path: String, x: float, z: float, yaw: float, name: String) -> Node3D:
	if not _cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("build_railhead: no prefab at %s — nothing placed" % path)
			_cache[path] = null
			return null
		_cache[path] = packed
	if _cache[path] == null:
		return null
	var inst := (_cache[path] as PackedScene).instantiate() as Node3D
	inst.name = name
	parent.add_child(inst)
	inst.position = Vector3(x, 0.0, z)
	inst.rotation_degrees = Vector3(0.0, yaw, 0.0)
	_guard(inst)
	return inst


# ── The placement guard: colliders against colliders, at the moment of placing ──

const PLACEMENT_M3 := 0.25


func _shape_boxes(n: Node3D) -> Array:
	var out: Array = []
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var m := cs.shape.get_debug_mesh()
		if m == null:
			continue
		out.append(cs.global_transform * m.get_aabb())
	return out


func _guard(inst: Node3D) -> void:
	var shapes := _shape_boxes(inst)
	if shapes.is_empty():
		return
	var box: AABB = shapes[0]
	for s: AABB in shapes:
		box = box.merge(s)
	for other: Dictionary in _placed:
		if not box.intersects(other.box):
			continue
		var shared := 0.0
		var where := AABB()
		var first := true
		for a: AABB in shapes:
			for b: AABB in other.shapes:
				if not a.intersects(b):
					continue
				var s := a.intersection(b)
				shared += s.size.x * s.size.y * s.size.z
				where = s if first else where.merge(s)
				first = false
		if shared > PLACEMENT_M3:
			_clashes += 1
			var c := where.get_center()
			push_warning("build_railhead: %s overlaps %s by %.1f m3 around (%.0f, %.0f, %.0f) — move one of them" % [
					inst.name, other.name, shared, c.x, c.y, c.z])
	_placed.append({"name": String(inst.name), "box": box, "shapes": shapes})


# ── Markers ──────────────────────────────────────────────────────────────────

## A car-local point (map x along, map y across, map z up) in world space.
## FuncGodot turns Quake (x, y, z) into Godot (y, z, x).
func _at(car: String, mx: float, my: float, mz: float) -> Vector3:
	var c: Node3D = _cars[car]
	return c.global_transform * Vector3(my, mz, mx)


func _record_markers() -> void:
	# Operations: the holo table, and the two places to stand and look down on it.
	_anchors["HoloTable"] = _at("Operations", 0.0, 0.0, 1.3)
	_anchors["HoloTable_ViewA"] = _at("Operations", 0.0, -2.9, 0.0)
	_anchors["HoloTable_ViewB"] = _at("Operations", 0.0, 2.9, 0.0)
	# The raked seating bay and the board it faces, at the front of the map room.
	_anchors["BriefingBoard"] = _at("Operations", R.END - 0.1, 0.0, 2.2)
	_anchors["Seating_Aisle"] = _at("Operations", 12.0, 0.0, 0.0)
	# Repair: one marker per bay, where a chassis stands.
	for i in R.BAYS.size():
		var b: Vector2 = R.BAYS[i]
		_anchors["RepairBay_%d" % (i + 1)] = _at("Repair", b.x, b.y, 0.0)
	# Armoury and Fabrication: the middle of each, in the lane.
	_anchors["Armoury"] = _at("Armoury", 0.0, 0.0, 0.0)
	_anchors["Fabrication"] = _at("Fabrication", 0.0, 0.0, 0.0)
	for i in R.FAB_X.size():
		_anchors["FabricationMount_%d_Fitted" % (i + 1)] = _at("Fabrication", R.FAB_X[i], -3.7, 0.0)
		_anchors["FabricationMount_%d_Empty" % (i + 1)] = _at("Fabrication", R.FAB_X[i], 3.7, 0.0)
	# Barracks: twelve bays down the +Y wall, numbered from the platform end, each
	# marker at the middle of the bay where a chassis is parked nose-in.
	for i in 12:
		var cx: float = -R.END + R.BAR_PITCH * (i + 0.5)
		_anchors["BarracksRack_%02d" % (i + 1)] = _at("Barracks", cx, R.BAR_Y0 + R.BAR_DEPTH * 0.5, 0.0)
	# Platform: where the player arrives, where the squad forms up, the door.
	_anchors["PlayerArrival"] = _at("Platform", -8.0, 0.0, 1.0)
	_anchors["SquadMuster"] = _at("Platform", 4.0, 0.0, 0.0)
	for i in 4:
		_anchors["SquadMuster_Slot%d" % (i + 1)] = _at("Platform", 1.0 + i * 2.5, 0.0, 0.0)
	# The platform door is the side door onto the station, at the car's middle.
	_anchors["PlatformDoor"] = _at("Platform", 0.0, R.HW, 0.0)
	_anchors["PlatformDoor_Outside"] = _at("Platform", 0.0, R.OW + 2.5, 0.0)
	# The leaf slides +X into a pocket of real space beside the opening.
	_anchors["PlatformDoor_LeafClosed"] = _at("Platform", 0.0, R.HW - 0.05, 1.7)
	_anchors["PlatformDoor_LeafOpen"] = _at("Platform", 2.0 * R.DOOR, R.HW - 0.05, 1.7)
	_anchors["PlatformDoor_Zone"] = _at("Platform", 0.0, 2.0, 0.0)
	# Where the view hangs, one plate each side. Left is the platform side: the
	# +Y wall, which is on the left walking toward the locomotive.
	_anchors["Backdrop_Left"] = _at("Armoury", 0.0, R.BACKDROP_Y, 3.5)
	_anchors["Backdrop_Right"] = _at("Armoury", 0.0, -R.BACKDROP_Y, 3.5)


# ── Lights ───────────────────────────────────────────────────────────────────
# One OmniLight3D under every lamp fitting the generator drew, at 3.0 m, with a
# range that stops short of the neighbouring car's mesh: this project renders in
# GL compatibility, which lights at most eight lights per mesh.

## Home Command lights warm and even, the light of a building that expects people to
## read in it: tungsten, every lamp, no flicker, no exceptions. No amber, no cyan.
const TUNGSTEN := Color("F2D9A8")
const KEY := {"Operations": "ops", "Repair": "repair", "Armoury": "armoury", "Fabrication": "fab",
		"Barracks": "barracks", "Platform": "platform"}


func _lights(g: Node3D) -> void:
	for car: String in KEY:
		var i := 0
		for p: Array in R.LAMPS[KEY[car]]:
			var l := OmniLight3D.new()
			l.name = "Lamp_%s_%d" % [car, i]
			g.add_child(l)
			l.global_position = _at(car, p[0], p[1], 3.0)
			l.light_color = TUNGSTEN
			# Operations is dark on purpose; the table is the light.
			# Operations is lower and dimmer than the rest, but not dark to the point of being out.
			l.light_energy = 0.7 if car == "Operations" else 1.0
			l.omni_range = 5.5
			i += 1
	var t := OmniLight3D.new()
	t.name = "Lamp_HoloTable"
	g.add_child(t)
	t.global_position = _at("Operations", 0.0, 0.0, 1.9)
	t.light_color = TUNGSTEN
	t.light_energy = 1.6
	t.omni_range = 5.0


# ── Checks ───────────────────────────────────────────────────────────────────

## Every marker against every collider: a marker inside a wall is the Polaris bug.
func _check_markers() -> int:
	var bad := 0
	var walk_top: float = R.DECK_RISE + 0.3
	for k: String in _all():
		if _fixture(k):
			continue
		var p: Vector3 = _all()[k]
		for o: Dictionary in _placed:
			for a: AABB in o.shapes:
				# A floor or a ramp under the marker is not a collision with it.
				if a.end.y <= walk_top:
					continue
				if a.grow(0.05).has_point(p + Vector3(0.0, 0.5, 0.0)) or a.grow(0.05).has_point(p):
					print("      MARKER   %s is inside a collider of %s" % [k, o.name])
					bad += 1
	if bad == 0:
		print("      MARKERS  %d, none inside a collider" % _all().size())
	return bad


## A GEOMETRIC STAND-IN FOR A BAKE, and not one. Rasterises the colliders that
## stand between the floor and 3.0 m above it onto a 0.25 m grid, grows each by
## a Walker's half-width (0.85 m, a square rather than a circle, so it is
## stricter than the truth at corners), and flood-fills from the foot of the
## boarding ramp. It says whether a 1.7 m x 3.0 m body has a path through the
## geometry to each marker. It says nothing about what the navmesh baker will
## do: the baker erodes 0.5 m, has no per-agent clearance, and only a bake can
## show what it makes of any of this.
const CELL := 0.25
const GX0 := -24.0
const GX1 := 24.0
const GZ0 := -152.0
const GZ1 := 152.0


func _reach(width: float = R.WALKER_W, label: String = "Walker 1.7 m x 3.0 m") -> void:
	var nx := int((GX1 - GX0) / CELL)
	var nz := int((GZ1 - GZ0) / CELL)
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	var r := width * 0.5
	var lo: float = R.DECK_RISE + 0.3
	var hi: float = R.DECK_RISE + R.WALKER_H
	for o: Dictionary in _placed:
		for a: AABB in o.shapes:
			if a.end.y <= lo or a.position.y >= hi:
				continue
			var ix0 := maxi(0, int(ceil((a.position.x - r - GX0) / CELL - 0.5)))
			var ix1 := mini(nx - 1, int(floor((a.end.x + r - GX0) / CELL - 0.5)))
			var iz0 := maxi(0, int(ceil((a.position.z - r - GZ0) / CELL - 0.5)))
			var iz1 := mini(nz - 1, int(floor((a.end.z + r - GZ0) / CELL - 0.5)))
			for ix in range(ix0, ix1 + 1):
				for iz in range(iz0, iz1 + 1):
					blocked[iz * nx + ix] = 1
	# From the middle of the platform: the ramp up to it is a plain 1 in 6.3 wedge 4 m wide, and the bake below is what proves it.
	var start: Vector3 = _st["Station_PlatformCentre"]
	var s := Vector2i(int((start.x - GX0) / CELL), int((start.z - GZ0) / CELL))
	if blocked[s.y * nx + s.x] == 1:
		print("      REACH    the start cell is blocked — the test cannot run")
		return
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var queue: Array = [s]
	seen[s.y * nx + s.x] = 1
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz:
				continue
			var idx := n.y * nx + n.x
			if seen[idx] == 1 or blocked[idx] == 1:
				continue
			seen[idx] = 1
			queue.append(n)
	var unreachable := 0
	for k: String in _all():
		if _fixture(k):
			continue
		var p: Vector3 = _all()[k]
		var cx := int((p.x - GX0) / CELL)
		var cz := int((p.z - GZ0) / CELL)
		if seen[cz * nx + cx] != 1:
			print("      REACH    %s is NOT reachable by the %s" % [k, label])
			unreachable += 1
	print("      REACH    geometric flood-fill, %s, from the platform centre: %d of %d markers reachable (NOT a bake)" % [label, 
			_standing() - unreachable, _standing()])


func _standing() -> int:
	var n := 0
	for k: String in _all():
		if not _fixture(k):
			n += 1
	return n


# ── The station: one scene, so it can be dropped into a mission map ──────────

## Station-local points (map x along the track, map y across, map z up), which
## are world points too: the station is placed at the origin with no yaw.
var _st: Dictionary = {}


func _write_station() -> bool:
	var top: float = R.DECK_RISE
	var cy: float = R.ST_RAMP_Y
	_st["Station_RampFoot"] = Vector3(cy, 0.0, R.ST_X1 + R.RAMP_LEN)
	_st["Station_RampTop"] = Vector3(cy, top, R.ST_X1)
	_st["Station_HeadHouseDoor"] = Vector3(cy, top, R.HH_X1)
	_st["Station_HeadHouse"] = Vector3(cy, top, (R.ST_X0 + R.HH_X1) * 0.5)
	_st["Station_PlatformCentre"] = Vector3((R.ST_Y0 + R.ST_Y1) * 0.5, top, 0.0)
	_st["Station_BerthRear"] = Vector3(R.ST_Y0 + 1.75, top, -7.0 * R.HL)
	_st["Station_BerthFront"] = Vector3(R.ST_Y0 + 1.75, top, 7.0 * R.HL)
	# The aerial mast: a landmark, and the reason you still get briefings.
	_st["Station_Mast"] = Vector3(R.MAST_Y, 0.0, R.MAST_X)
	_st["Station_MastTop"] = Vector3(R.MAST_Y, R.MAST_H, R.MAST_X)
	# The track is cut here. A mission map joins its own track to these.
	_st["Station_TrackCut_Rear"] = Vector3(0.0, 0.0, -R.ST_CUT)
	_st["Station_TrackCut_Front"] = Vector3(0.0, 0.0, R.ST_CUT)

	var st := Node3D.new()
	st.name = "RailheadStation"
	root.add_child(st)
	var packed := load(B % "railhead_station") as PackedScene
	if packed == null:
		print("FAIL  no prefab at %s — run block_prefabs.gd first" % (B % "railhead_station"))
		return false
	var inst := packed.instantiate() as Node3D
	inst.name = "Station"
	st.add_child(inst)
	var mk := _group(st, "Markers")
	for k: String in _st:
		var m := Node3D.new()
		m.name = k
		mk.add_child(m)
		m.position = _st[k]
	# At most eight lights reach the platform mesh in GL compatibility: seven
	# canopy lights and one in the head house.
	var lg := _group(st, "Lights")
	for i in R.POSTS.size():
		var l := OmniLight3D.new()
		l.name = "Canopy_%d" % i
		lg.add_child(l)
		l.position = Vector3(R.ST_LAMP_Y, R.ST_LAMP_Z, R.POSTS[i])
		l.light_color = TUNGSTEN
		l.light_energy = 1.1
		l.omni_range = 8.0
	var hl := OmniLight3D.new()
	hl.name = "HeadHouse"
	lg.add_child(hl)
	hl.position = Vector3(cy, top + 3.0, (R.ST_X0 + R.HH_X1) * 0.5)
	hl.light_color = TUNGSTEN
	hl.light_energy = 1.0
	hl.omni_range = 8.0
	_own(st, st)
	var ps := PackedScene.new()
	var err := ps.pack(st)
	if err == OK:
		err = ResourceSaver.save(ps, STATION)
	root.remove_child(st)
	st.free()
	if err != OK:
		print("FAIL  could not save %s (%s)" % [STATION, error_string(err)])
		return false
	print("      %s  one prefab, %d markers" % [STATION.get_file(), _st.size()])
	return true


## Every marker, the train's and the station's.
func _all() -> Dictionary:
	var d := _anchors.duplicate()
	d.merge(_st)
	return d
