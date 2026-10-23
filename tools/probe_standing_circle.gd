extends SceneTree

# ─────────────────────────────────────────────
# CAN YOU ACTUALLY STAND IN THE CAPTURE CIRCLE?
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_standing_circle.gd [-- <site> ...]
#
# Capture is "hit F and stand in the circle", so the circle is not decoration —
# it is the instruction. Two ways it can lie, and this measures both.
#
# IT CAN FLOAT. CoreSignal draws the ring at +0.06 on its OWN origin, with the
# comment "ON the deck, not in it". That is only true while the Signal node
# sits at deck level, and for a BUNKER it does not: site_slice._dress() moves
# the whole Signal node to BeaconMount.global_position so the beacon column
# clears the doorway roof, and the ring is a CHILD of that node, so it goes up
# with it. The human spotted this in a render — "the circle is well above the
# ground" — which is exactly the class of fault a structural probe cannot see:
# the ring EXISTS, it is the right radius, it reads off channel_range like it
# should, and it is five metres in the air.
#
# IT CAN BE ROUND THE WRONG SPOT. holdable_core measures the channel from
# `interactible.global_position`, falling back to the core's own origin. The
# ring is drawn at the Signal node. On a surface core those are the same point;
# once anything moves either of them they are not, and a ring you can stand in
# is no use if standing in it leaves you out of range.
#
# IT BUILDS THE SITE FIRST. The slice raises all of this at runtime, so loading
# the .tscn and reading it is not enough — see CLAUDE.md, "a render is evidence
# only if the thing is in it". Same reason this waits 70 physics frames.
# ─────────────────────────────────────────────

const LEVELS := {
	"hillfort":     ["res://maps/hillfort_level.tscn",      "HillfortSlice"],
	"hillfort_wip": ["res://maps/hillfort_wip_level.tscn",  "HillfortWipSlice"],
	"coast":        ["res://maps/coastal-road_level.tscn",  "CoastSlice"],
	"rivers":       ["res://maps/pittsburgh_level.tscn",    "RiversSlice"],
	"qamareen":     ["res://maps/mutaha_wip_level.tscn",    "QamareenSlice"],
	"lockside":     ["res://maps/georgetown_level.tscn",    "LocksideSlice"],
	"polaris":      ["res://maps/polaris_level.tscn",       "PolarisSlice"],
	"causeway":     ["res://maps/causeway_level.tscn",      "CausewaySlice"],
	"trenchline":   ["res://maps/salient_level.tscn",       "TrenchlineSlice"],
	"basin":        ["res://maps/valley_basin_level.tscn",  "BasinSlice"],
}

## A step up is fine; a chest-high ledge is not. 0.60 m is the tallest thing
## the chassis table says a Walker steps onto without pathing round it.
const HIGH := 0.60
## The collar sits deliberately higher than the ring — it is the thicker tube
## and would bury half its section at 0.06. Allowed for, not flagged.
const COLLAR_LIFT := 0.11
## HOW FAR THE RING MAY SIT FROM THE REAL CAPTURE CENTRE. Not zero, because a
## terminal on the face of a core is legitimately a metre or so off its axis —
## but anything approaching channel_range means the ring is round a different
## place entirely.
const OFF := 2.0
## FROM JUST ABOVE THE RING, not from the sky. Casting from 40 m up measures
## the CEILING on any ring that is indoors or under a span — Causeway's tower
## rings came back at -35.94 m, which is the floor above them, not their own.
## 1.5 m clears the ring's own torus and nothing else.
const UP := 1.5
const DOWN := 50.0

var _fails: int = 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame

	var want: Array = []
	for a in OS.get_cmdline_user_args():
		want.append(String(a))

	print("site         circle                      ring y   ground    gap  off-centre  verdict")
	for name in LEVELS:
		if not want.is_empty() and not want.has(String(name)):
			continue
		await _one(String(name), LEVELS[name][0], LEVELS[name][1])
	print("")
	print("%d circle(s) that lie about where to stand" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, level_path: String, node_name: String) -> void:
	var packed := load(level_path) as PackedScene
	if packed == null:
		print("%-12s FAIL — %s will not load" % [label, level_path])
		_fails += 1
		return
	var level = packed.instantiate()
	root.add_child(level)
	for _i in 70:
		await physics_frame

	var slice = level.get_node_or_null(NodePath(node_name))
	if slice == null:
		print("%-12s FAIL — no %s in the level, so nothing was built" % [label, node_name])
		_fails += 1
		level.queue_free()
		await process_frame
		return

	var rings: Array[Node] = []
	_collect(slice, rings)
	# The slice dresses cores that are AUTHORED IN THE LEVEL on some maps
	# (hillfort_wip instances its own compute_core_point prefabs), so those
	# Signal nodes hang off the level rather than off the slice. Sweep both and
	# de-duplicate, or half the rings on those maps are never looked at.
	_collect(level, rings)
	if rings.is_empty():
		print("%-12s FAIL — no StandingCircle anywhere, so there is nothing to stand in" % label)
		_fails += 1
		level.queue_free()
		await process_frame
		return

	var space := root.world_3d.direct_space_state
	for r in rings:
		var ring := r as Node3D
		var at: Vector3 = ring.global_position
		# EXCLUDE THE RING'S OWN MACHINE. A core is a solid box and a cast
		# started above it lands on its lid, which would read as "ground" at
		# exactly the height that hides the fault.
		var skip: Array[RID] = []
		var sig: Node = ring.get_parent()
		if sig != null and sig.get_parent() != null:
			for b in _bodies(sig.get_parent()):
				skip.append(b.get_rid())
		var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, UP, 0.0), at - Vector3(0.0, DOWN, 0.0))
		q.exclude = skip
		var hit := space.intersect_ray(q)
		var who: String = "%s/%s" % [_who(ring), String(ring.name).replace("Standing", "").replace("Deck", "")]
		var off: float = _off_centre(ring)
		if hit.is_empty():
			print("%-12s %-26s %7.2f   (none)      -  %9.2f   FAIL no ground under it at all"
				% [label, who, at.y, off])
			_fails += 1
			continue
		var gy: float = hit.position.y
		# The collar is seated deliberately higher than the ring, so take that
		# off before judging it — otherwise every collar reads as floating by
		# the one amount that is correct.
		var gap: float = at.y - gy
		if ring.name == &"DeckCollar":
			gap -= COLLAR_LIFT
		var why: String = "ok"
		if gap > HIGH and off > OFF:
			why = "FAIL floats AND round the wrong spot"
		elif gap > HIGH:
			why = "FAIL floats"
		elif off > OFF:
			why = "FAIL round the wrong spot"
		if why != "ok":
			_fails += 1
		print("%-12s %-26s %7.2f %8.2f %6.2f %9.2f   %s"
			% [label, who, at.y, gy, gap, off, why])

	level.queue_free()
	await process_frame


## Named lookup rather than a type check: the ring is a plain MeshInstance3D and
## so is half the art in these levels.
func _collect(n: Node, out: Array[Node]) -> void:
	# BOTH PIECES OF DECK FURNITURE. Measuring only the ring is how the collar
	# kept floating after the ring was fixed — the human found it in a render,
	# which this probe is meant to make unnecessary.
	var deck: bool = n.name == &"StandingCircle" or n.name == &"DeckCollar"
	if deck and n is Node3D and not out.has(n):
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## Which core the ring belongs to, for a report somebody has to act on. The
## ring's parent is the Signal node; its parent is the host that was dressed.
func _who(ring: Node3D) -> String:
	var p := ring.get_parent()
	if p == null:
		return "?"
	var g := p.get_parent()
	return String(g.name) if g != null else String(p.name)


## HOW FAR THE RING IS FROM THE POINT THE CAPTURE IS ACTUALLY MEASURED FROM.
##
## holdable_core._physics_process uses `interactible.global_position` and falls
## back to the core's own origin, so that point — not the Signal node, not the
## beacon mount, not the host — is the centre the player has to be within
## channel_range of. Reported HORIZONTALLY — see below.
func _off_centre(ring: Node3D) -> float:
	var sig := ring.get_parent()
	if sig == null:
		return 0.0
	var core = sig.get("core")
	if core == null or not is_instance_valid(core):
		return 0.0
	var it = core.get("interactible")
	var at: Vector3 = (it as Node3D).global_position if it != null \
		and is_instance_valid(it) else (core as Node3D).global_position
	# HORIZONTAL ONLY. The ring is a marking on the floor and the terminal is
	# up the face of the machine — a bunker's TerminalFace stands 1.24 m above
	# the deck, which is correct and not an error. Measuring in 3D would report
	# that as off-centre and hide a real sideways miss underneath it.
	var a := Vector2(ring.global_position.x, ring.global_position.z)
	var b := Vector2(at.x, at.z)
	return a.distance_to(b)


func _bodies(n: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if n is CollisionObject3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_bodies(c))
	return out
