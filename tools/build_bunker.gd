extends SceneTree

# ─────────────────────────────────────────────
# BUILD BUNKER — assembles the bunker entrance kit: the mouth, the two leaves
# as nodes of their own, the signal strip, the lamp, and the named markers
# GAMEPLAY drives it by.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_bunker.gd -- --force
#
#   maps/blocks/bunker/bunker_entrance.tscn        the module — this is the one
#   maps/blocks/bunker/bunker_entrance_open.tscn   + the sunken court
#   maps/blocks/bunker/bunker_entrance_cliff.tscn  + the revetted headwall
#   maps/blocks/bunker/bunker_entrance_wall.tscn   + the flush interior surround
#
# THE DELIVERABLE IS THE NAMED NODES, not the prettiness. This project's FGD
# has no point classes, so nothing but brushes comes out of a .map and every
# named handle has to be written here — which is exactly why build_railhead.gd
# is the model for this file.
#
# THE LEAVES ARE DRIVEN BY ONE FLOAT. LeafLeft and LeafRight are separate
# instanced nodes whose local position is (0, 0, 0) when the doors are shut:
#
#     leaf_left.position.x  = -TRAVEL * f
#     leaf_right.position.x =  TRAVEL * f        # f = stand_down_fraction()
#
# No AnimationPlayer, no shader parameter, no swapped meshes. A float driving
# two transforms stalls where it is and resumes from there for free, and
# stand_down_interrupted needs precisely that: progress is kept, so the doors
# stop partway, sit there, and grind on again when the bunker is retaken.
#
# NOTHING HERE WRITES A LEVEL. A level scene is where gameplay nodes live, and
# a generator that writes one deletes them the next time it runs — that has
# happened twice on other levels in this project. This writes the art, and
# gameplay attaches to the markers by name.
#
# AXES. FuncGodot turns Quake (x, y, z) into Godot (y, z, x), so a point given
# in the block tool's map coordinates reaches Godot as _at() puts it. Every
# marker below is derived from a block_bunker.gd constant. NOTHING IS A TYPED
# COORDINATE: the Polaris objective was typed, the road moved by 6 m, and the
# marker ended up inside a wall.
#
# WHAT CHECKS THE GEOMETRY, AND WHY IT IS NOT THE RAILHEAD'S CHECK. The railhead
# compares the bounding boxes of each car's colliders, which works because its
# cars stand 32 m apart. FuncGodot gives ONE CONCAVE SHAPE PER ENTITY, so the
# bounding box of this module's collider is the whole module — the AABB guard
# copied from there reported the leaves as 9 m³ inside the mouth and every
# tunnel marker as buried in a wall, all of it nonsense. Brush-against-brush
# across the assembled pieces is proven in block_bunker.gd, which has the
# brushes; everything here asks the PHYSICS SERVER instead.
# ─────────────────────────────────────────────

const B := preload("res://tools/block_bunker.gd")

const PIECE := "res://maps/blocks/bunker/%s.tscn"
const ENTRANCE := "res://maps/blocks/bunker/bunker_entrance.tscn"
const MOUNTED := "res://maps/blocks/bunker/bunker_entrance_%s.tscn"

## The mountings, by the names the design gave them.
const MOUNTS := {
	"open": "bunker_mount_open",
	"cliff": "bunker_mount_cliff",
	"wall": "bunker_mount_wall",
}

## Home Command lights warm and even, every lamp, no exceptions. The one cyan in
## this kit is the signal strip and it is tinted in code, never baked.
const TUNGSTEN := Color("F2D9A8")

var _cache := {}
var _faults := 0
## Marker name -> position in the entrance's own space.
var _marks: Dictionary = {}


func _initialize() -> void:
	await process_frame
	var force := OS.get_cmdline_user_args().has("--force")
	var ok: bool = await _write_entrance(force)
	if ok:
		for key: String in MOUNTS:
			ok = (await _write_mounted(key, force)) and ok
	var good: bool = ok and _faults == 0
	print("BUILD BUNKER %s" % ("DONE" if good else "DONE — WITH FAILURES"))
	quit(0 if good else 1)


# ── The entrance module ─────────────────────────────────────────────────────

func _write_entrance(force: bool) -> bool:
	if FileAccess.file_exists(ProjectSettings.globalize_path(ENTRANCE)) and not force:
		print("SKIP  %s exists — pass --force to rebuild it." % ENTRANCE)
		return true

	var art := Node3D.new()
	art.name = "BunkerEntrance"
	root.add_child(art)

	var mouth := _put(art, PIECE % "bunker_mouth", "Mouth")
	if mouth == null:
		print("FAIL  no bunker_mouth prefab — run block_bunker.gd then block_prefabs.gd")
		root.remove_child(art)
		art.free()
		return false
	# THE TWO HANDLES. Their prefabs are built with the origin at the closed
	# position, so both sit at zero and GAMEPLAY moves them in x and nothing
	# else. Left parks toward Godot -X, right toward +X.
	_put(art, PIECE % "bunker_leaf_left", "LeafLeft")
	_put(art, PIECE % "bunker_leaf_right", "LeafRight")
	# A band on the lintel with a material of its own, so GAMEPLAY can tint it
	# HUDPalette.SIGNAL without writing into a texture material that other maps
	# share. Its own prefab for exactly that reason.
	_put(art, PIECE % "bunker_signal_strip", "SignalStrip")

	_record_marks()
	var markers := _group(art, "Markers")
	for k: String in _marks:
		var m := Node3D.new()
		m.name = k
		markers.add_child(m)
		m.position = _marks[k]

	# ONE LAMP, in the soffit of the reveal, and the tunnel behind it dark. The
	# brief is explicit that there is darkness back there and the level ends in
	# it; the only light in this model is the one that spills out of the gap as
	# the leaves part, which is most of why the opening reads as progress rather
	# than as a shut door with a glow on it.
	var lights := _group(art, "Lights")
	var l := OmniLight3D.new()
	l.name = "Lamp_Reveal"
	lights.add_child(l)
	l.position = _at(B.PLATE_X1 * 0.5, 0.0, B.OPEN_H - 0.3)
	l.light_color = TUNGSTEN
	l.light_energy = 2.0
	l.omni_range = 11.0
	l.shadow_enabled = true

	var saved := _save(art, ENTRANCE)
	print("      %s  %d markers" % [ENTRANCE.get_file(), _marks.size()])
	# OUT OF THE TREE BEFORE ANYTHING IS MEASURED. The first version of this
	# left it in and then loaded a second, posed copy for the physics tests —
	# two sets of colliders in one world, so the shut doors of the first copy
	# blocked the open doors of the second and every test came back "sealed".
	root.remove_child(art)
	art.free()
	await process_frame

	_report_numbers()
	await _check_marks()
	await _reach()
	return saved


## The whole mouth plus one surround, so a level can drop a mounting in one
## piece. The mount prefabs share the mouth's datum — the court's floor IS the
## mouth's z = 0 — so both go down at the same origin with no offset.
func _write_mounted(key: String, force: bool) -> bool:
	var out: String = MOUNTED % key
	if FileAccess.file_exists(ProjectSettings.globalize_path(out)) and not force:
		print("SKIP  %s exists — pass --force to rebuild it." % out)
		return true
	var art := Node3D.new()
	art.name = "BunkerEntrance%s" % key.capitalize()
	root.add_child(art)
	var ent := _put(art, ENTRANCE, "Entrance")
	var mount := _put(art, PIECE % MOUNTS[key], "Mount")
	if ent == null or mount == null:
		print("FAIL  %s not written: a piece is missing" % out)
		root.remove_child(art)
		art.free()
		return false
	var saved := _save(art, out)
	print("      %-30s mouth + %s" % [out.get_file(), MOUNTS[key]])
	root.remove_child(art)
	art.free()
	await process_frame
	return saved


# ── Markers ─────────────────────────────────────────────────────────────────

## A point given in the block tool's MAP coordinates, in Godot space.
## FuncGodot turns Quake (x, y, z) into Godot (y, z, x).
func _at(mx: float, my: float, mz: float) -> Vector3:
	return Vector3(my, mz, mx)


func _record_marks() -> void:
	# THE DOCK, on the lintel deck: flat, continuous and open to the sky in both
	# the court and the cliff mounting, for a 3.4 m tap drone.
	_marks["DockPad"] = _at(B.DOCK_X, B.DOCK_Y, B.DECK_Z)
	# THE BEACON, far enough along the deck that it never stands over the
	# drone's landing. Its height is per-map and is not ours.
	_marks["BeaconMount"] = _at(B.BEACON_X, B.BEACON_Y, B.DECK_Z)
	# THE TERMINAL FACE: the middle of the readout on the console beside the
	# doors, outside the leaf's travel so a closing leaf cannot sweep through
	# whatever is standing at it.
	_marks["TerminalFace"] = _at(B.CON_X1 + 0.0625, (B.CON_Y0 + B.CON_Y1) * 0.5, B.CON_FACE_Z)
	# Where the squad stands to work it, on the ground in front of the console.
	_marks["TerminalStand"] = _at(B.CON_X1 + 1.0, (B.CON_Y0 + B.CON_Y1) * 0.5, 0.0)
	# THE EXIT VOLUME: 4 m into the tunnel, past the leaf plane and past the
	# 1 m reveal, so nobody counts as having left while still in the doorway
	# being shot at.
	_marks["ExitVolume"] = _at(B.TUNNEL_BACK * 0.4, 0.0, 0.0)
	# The doorway itself and the sealed back of the tunnel: the two ends of the
	# walk, for whatever wants to aim a camera or a line of movement down it.
	_marks["Threshold"] = _at(B.PLATE_X1 * 0.5, 0.0, 0.0)
	_marks["TunnelBack"] = _at(B.TUNNEL_BACK + 1.0, 0.0, 0.0)
	# WHERE THE SQUAD STANDS ON A DEFENCE. §12.8: you come up out of the ground
	# and turn round. Four slots across the tunnel 2.0 m apart, 7 m in — far
	# enough back that the leaves are still shut over them at mission start.
	for i in 4:
		_marks["ArrivalSlot_%d" % (i + 1)] = _at(B.TUNNEL_BACK * 0.7, -3.0 + i * 2.0, 0.0)


# ── Scene plumbing ──────────────────────────────────────────────────────────

func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


func _put(parent: Node3D, path: String, name: String) -> Node3D:
	if not _cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("build_bunker: no prefab at %s — nothing placed" % path)
			_cache[path] = null
			return null
		_cache[path] = packed
	if _cache[path] == null:
		return null
	var inst := (_cache[path] as PackedScene).instantiate() as Node3D
	inst.name = name
	parent.add_child(inst)
	return inst


## Instance ROOTS are owned by the art root and nothing inside them is, so an
## edit to a block in maps/blocks/ still reaches whatever instances it.
func _own(node: Node, root_node: Node) -> void:
	for c in node.get_children():
		c.owner = root_node
		if c.scene_file_path == "":
			_own(c, root_node)


func _save(art: Node3D, path: String) -> bool:
	_own(art, art)
	var packed := PackedScene.new()
	var err := packed.pack(art)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	if err != OK:
		print("FAIL  could not save %s (%s)" % [path, error_string(err)])
		return false
	return true


# ── The numbers ────────────────────────────────────────────────────────────

## Measured off the constants the geometry was actually built from, never
## retyped: a number in two places drifts the first time one of them moves.
func _report_numbers() -> void:
	var turn: float = sqrt(B.ROVER_L * B.ROVER_L + B.ROVER_W * B.ROVER_W)
	print("      OPENING  %.2f m wide x %.4f m high clear" % [B.OPEN_W, B.OPEN_H])
	print("      LEAVES   2 x %.2f w x %.4f h x %.2f t, travel %.2f m each along Godot ±X" % [
			B.LEAF_W, B.OPEN_H, B.LEAF_T, B.TRAVEL])
	print("      TUNNEL   %.2f x %.4f x %.1f m deep, flat floor, sealed at the back, unlit" % [
			B.OPEN_W, B.OPEN_H, B.TUNNEL_D])
	print("      ROVER    %.1f x %.1f m turns in %.2f m; the tunnel is %.1f m wide, %.1f m deep" % [
			B.ROVER_L, B.ROVER_W, turn, B.OPEN_W, B.TUNNEL_D])
	print("      DOCK     pad at %s — dock_height wants %.2f (site_slice.gd sets 4.9 today)" % [
			_marks["DockPad"], B.DECK_Z])
	print("      TERMINAL face at %s, interact volume 2.4 x 1.4 x 2.4" % _marks["TerminalFace"])
	print("      EXIT     volume at %s, %.1f m inside the tunnel" % [
			_marks["ExitVolume"], absf(B.TUNNEL_BACK * 0.4)])
	print("      HEIGHTS  module %.2f m; flush interior mounting %.2f m against the Causeway's 5.25" % [
			B.DECK_Z, B.WALL_TOTAL])


# ── Checks, against the real colliders ─────────────────────────────────────

const WALK_Y := 0.1          ## the body's feet, just clear of the floor
const STEP := 0.25
const FINE := 0.0625         ## the span probe's resolution


func _hits(space: PhysicsDirectSpaceState3D, size: Vector3, at: Vector3, yaw: float = 0.0) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := BoxShape3D.new()
	s.size = size
	q.shape = s
	q.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not space.intersect_shape(q, 1).is_empty()


## The entrance, alone in the world, with the leaves posed at `f`.
func _pose(f: float) -> Node3D:
	var art := (load(ENTRANCE) as PackedScene).instantiate() as Node3D
	root.add_child(art)
	var ll := art.find_child("LeafLeft", true, false) as Node3D
	var lr := art.find_child("LeafRight", true, false) as Node3D
	if ll == null or lr == null:
		_faults += 1
		push_warning("build_bunker: LeafLeft/LeafRight missing from the entrance — those two names ARE the deliverable")
		return art
	ll.position.x = -B.TRAVEL * f
	lr.position.x = B.TRAVEL * f
	return art


## Every marker against the real geometry. A marker inside a wall is the
## Polaris bug. The probe sits at chest height ABOVE each marker, because a
## marker is a place to stand and a probe centred on one would report the floor
## it stands on. 0.9 m of probe, not 0.3: the collider is a hollow triangle
## mesh, and a probe small enough to sit inside a wall reports clear.
## it stands on.
func _check_marks() -> void:
	var art := _pose(0.0)
	var space := art.get_world_3d().direct_space_state
	for _i in 8:
		await physics_frame
	var bad := 0
	for k: String in _marks:
		# TerminalFace names a FIXTURE, not a place to stand: it is the middle
		# of the readout ON the console, so a probe round it meets the console
		# by design. TerminalStand, 1 m in front of it, is the one that has to
		# be in open air, and it is checked.
		if k == "TerminalFace":
			continue
		var p: Vector3 = _marks[k]
		if _hits(space, Vector3(0.9, 0.9, 0.9), p + Vector3(0.0, 0.9, 0.0)):
			print("      MARKER   %s is inside solid geometry at %s" % [k, p])
			bad += 1
	if bad == 0:
		print("      MARKERS  %d, none inside solid geometry — with the doors SHUT, the hard case" % _marks.size())
	_faults += bad
	root.remove_child(art)
	art.free()
	await process_frame


## The doors, at the three fractions that matter, against the shapes the game
## itself collides with. It says nothing about what the navmesh BAKER will do:
## the baker erodes 0.5 m, has no per-agent clearance, and only a bake answers
## that.
func _reach() -> void:
	for f: float in [0.0, 0.5, 1.0]:
		var art := _pose(f)
		var space := art.get_world_3d().direct_space_state
		for _i in 8:
			await physics_frame
		var span := _span(space)
		print("      SPAN     f=%.2f  %.2f m clear of %.1f m  (leaves at ±%.2f, %d%% open)" % [
				f, span, B.OPEN_W, B.TRAVEL * f, int(round(span / B.OPEN_W * 100.0))])
		for body: Array in [[B.ROVER_W, "Rover, 1.70 m wide"], [B.BULWARK_W, "Bulwark, 2.26 m wide"]]:
			var got := _walk(space, float(body[0]))
			var want: bool = span >= float(body[0])
			var line := "      WALK     f=%.2f  %-22s %s" % [f, body[1],
					"walks to the back of the tunnel" if got else "stopped at the doors"]
			if got == want:
				print("%s  — as designed" % line)
			else:
				print("%s  — WRONG: %.2f m of span says otherwise" % [line, span])
				_faults += 1
		if f >= 1.0:
			_turn(space)
		root.remove_child(art)
		art.free()
		await process_frame


## The clear span across the doorway AT THE LEAF PLANE, measured by sliding a
## thin tall probe across the opening. THIS IS THE NUMBER THE WHOLE DESIGN
## LIVES OR DIES BY: at f = 0.5 it has to look like about half, from cover,
## with no HUD. Measured only between the jambs — outside them is open air,
## which measures beautifully and means nothing.
## THE PROBE IS DEEPER THAN THE DOOR ON PURPOSE. FuncGodot's collider is a
## TRIANGLE MESH, which is hollow: a probe 0.25 m deep sitting in the middle of
## a 0.5 m leaf crosses no triangle and comes back clear. The first run of this
## reported a 0.31 m hole through a shut door, twice, symmetrically — which was
## the brass stile, the one leaf brush with no internal faces for the probe to
## catch on. A probe that spans the whole leaf thickness cannot be fooled.
func _span(space: PhysicsDirectSpaceState3D) -> float:
	var z: float = (B.LEAF_X0 + B.LEAF_X1) * 0.5
	var probe := Vector3(FINE, B.WALKER_H - 0.2, B.LEAF_T * 2.0)
	var best := 0.0
	var run := 0.0
	var x := -B.OPEN_HALF
	while x <= B.OPEN_HALF:
		if _hits(space, probe, Vector3(x, WALK_Y + probe.y * 0.5, z)):
			run = 0.0
		else:
			run += FINE
			best = maxf(best, run)
		x += FINE
	# The sweep's own resolution adds a cell at each open end; the opening is
	# never wider than it was built.
	return minf(best, B.OPEN_W)


## Walks a body of `width` down the centreline from outside the doors to the
## back of the tunnel and says whether it gets there.
func _walk(space: PhysicsDirectSpaceState3D, width: float) -> bool:
	var size := Vector3(width, B.WALKER_H - 0.2, 0.5)
	var z := 12.0
	while z > B.TUNNEL_BACK + 1.0:
		if _hits(space, size, Vector3(0.0, WALK_Y + size.y * 0.5, z)):
			return false
		z -= STEP
	return true


## A Rover is 3.4 m long and 1.7 m wide. Turning one on the spot sweeps a
## circle of its own diagonal, so the test is the body itself at every yaw in
## the middle of the tunnel — not a width comparison, which would happily pass
## a corridor a Rover can drive into and never get out of.
func _turn(space: PhysicsDirectSpaceState3D) -> void:
	var size := Vector3(B.ROVER_W, 2.0, B.ROVER_L)
	var at := Vector3(0.0, WALK_Y + 1.0, B.TUNNEL_BACK * 0.5)
	var fouled := ""
	var yaw := 0.0
	while yaw < 180.0:
		if _hits(space, size, at, yaw):
			fouled = "%.0f°" % yaw
			break
		yaw += 10.0
	var turn: float = sqrt(B.ROVER_L * B.ROVER_L + B.ROVER_W * B.ROVER_W)
	if fouled == "":
		print("      TURN     a Rover (%.1f x %.1f m, %.2f m diagonal) clears every yaw at %s" % [
				B.ROVER_L, B.ROVER_W, turn, at])
	else:
		print("      TURN     WRONG: a Rover fouls the tunnel at %s — it can drive in and not get out" % fouled)
		_faults += 1
