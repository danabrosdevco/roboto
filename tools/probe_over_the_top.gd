extends SceneTree

# ─────────────────────────────────────────────
# OVER THE TOP — how many deliberate ways are there out of our own front line,
# and are they spaced so that crossing is a DECISION?
#
#   LEVEL=res://maps/salient_level.tscn \
#       godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_over_the_top.gd
#
#   FRONT=Salient_Jumpoff   the anchor that names our front line's x
#   BAND=40.0               how far either side of that x still counts as "on
#                           the front line"
#   WANT=60.0               the spacing below which two exits are one exit
#
# Headless is fine: this reads placed nodes and the kit manifest. It casts no
# rays and asks no navmesh.
#
# WHY IT EXISTS. The moment a trench map lives or dies on is the moment you
# leave your own trench. If there is one way out, the map is a corridor with a
# funnel at the end of it; if the parapet is climbable everywhere, there is no
# moment at all and the trench behind you was decoration. What makes it a
# decision is a SMALL NUMBER OF SPACED EXITS, each with a different cost — which
# is exactly what a ramp, a sap head and a gap in the wire are.
#
# So this counts the four kinds of deliberate exit this kit can build and
# reports where each one is across the frontage and how far apart they are:
#
#   ramps          trench_ramp_end and sunken_road_ramp — the floor comes up to
#                  grade, so a body walks out without climbing anything
#   sap heads      trench_sap_head — a trench pushed out past the line, which is
#                  a start line rather than an exit, and the kit has one
#   wire gaps      wire_belt_gap against wire_belt_run: the belts are the fence
#                  and a gap is the gate
#   embrasures     counted from the kit's own dig records at T_EMBR_PITCH. These
#                  are FIRING SLOTS, NOT EXITS, and they are counted here
#                  because a parapet you can shoot through without climbing is
#                  what makes staying in the trench a real alternative to
#                  leaving it. A line with exits and no embrasures gives you
#                  nothing to do but go over.
#
# WHAT IT CANNOT MEASURE and does not pretend to. Whether the terrain-cut fire
# lines can simply be climbed out of anywhere is a question about slope and
# step height, and it belongs to probe_footing.gd and the 0.45 m step rule, not
# here. The cut is 0.8 m deep (tools/mapdeck_data.gd TR_D) with 1.5 m of
# falloff either side, which is a 28-degree bank — so the honest answer is that
# OUR OWN FIRE LINES ARE WALK-OUT-ANYWHERE, and that is printed as a finding
# rather than discovered later.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

## Piece-name substrings, by what kind of exit they are.
const RAMP_PIECES := ["trench_ramp_end", "sunken_road_ramp"]
const SAP_PIECES := ["trench_sap_head"]
const GAP_PIECES := ["wire_belt_gap"]
const WIRE_PIECES := ["wire_belt_run"]

## The fire-line cut, from tools/mapdeck_data.gd's TR_* constants. Named here
## with its source because the deck is a different file and these three numbers
## are the whole reason the fire lines are not an obstacle.
const TR_DEPTH := 0.8
const TR_FALLOFF := 1.5

## The kit's source, for the embrasure pitch and slot width — see _embrasures().
const KIT_SRC := "res://tools/block_trench.gd"
## Piece-name prefix -> how many slots it carries. An int is a fixed count; the
## string "run" means "one every T_EMBR_PITCH along its length".
const SLOTTED := {"trench_run": "run", "trench_firebay": 3, "trench_dugout": 2}


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/salient_level.tscn godot --headless --path . --script res://tools/probe_over_the_top.gd")
		quit(2)
		return
	var packed := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 20:
		await process_frame

	var front_name := OS.get_environment("FRONT") if OS.get_environment("FRONT") != "" else "Salient_Jumpoff"
	var front: Vector3 = LIB.objective(level, front_name)
	if is_nan(front.x):
		print("FAIL  no %s anchor — without our own front line's x there is no" % front_name)
		print("      way to tell an exit INTO no-man's-land from a ramp in the rear.")
		quit(1)
		return
	var band := float(OS.get_environment("BAND")) if OS.get_environment("BAND") != "" else 40.0
	var want := float(OS.get_environment("WANT")) if OS.get_environment("WANT") != "" else 60.0
	print("   our front line at x %.0f, counting exits within %.0f m of it" % [front.x, band])

	var ramps: Array = []
	var saps: Array = []
	var gaps: Array = []
	var wire: Array = []
	var ramps_far: Array = []
	for n in level.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		var at: Vector3 = (n as Node3D).global_position
		var kind := ""
		for p: String in RAMP_PIECES:
			if nm.contains(p):
				kind = "ramp"
		for p: String in SAP_PIECES:
			if nm.contains(p):
				kind = "sap"
		for p: String in GAP_PIECES:
			if nm.contains(p):
				kind = "gap"
		for p: String in WIRE_PIECES:
			if nm.contains(p):
				kind = "wire"
		if kind == "":
			continue
		match kind:
			"ramp":
				if absf(at.x - front.x) <= band:
					ramps.append([nm, at])
				else:
					ramps_far.append([nm, at])
			"sap":
				saps.append([nm, at])
			"gap":
				gaps.append([nm, at])
			"wire":
				wire.append([nm, at])

	print("")
	print("── OUT OF OUR OWN LINE")
	var exits: Array = ramps.duplicate()
	for s: Array in saps:
		if absf((s[1] as Vector3).x - front.x) <= band * 3.0:
			exits.append(s)
	if exits.is_empty():
		print("   NONE. There is no built way out of the friendly front line at all:")
		print("   every crossing starts by climbing the parapet wherever you happen")
		print("   to be standing, which is the version of this map with no moment in it.")
	exits.sort_custom(func(a: Array, b: Array) -> bool:
			return (a[1] as Vector3).z < (b[1] as Vector3).z)
	# WHICH ROUTE EACH EXIT BELONGS TO, and — the finding this turned up — which
	# routes have none. A laid piece is named <route><nn>_<piece>, so the route
	# is the leading letter. A route with no exit of its own is not broken: it
	# means that route begins by walking out of the fire line wherever you like,
	# which is a different experience from going out through a built sap.
	var by_route := {}
	for e: Array in exits:
		var at: Vector3 = e[1]
		var route := str(e[0]).substr(0, 1)
		by_route[route] = true
		print("   %-28s at x %6.0f, z %6.0f   (route %s)" % [e[0], at.x, at.z, route])
	for g in _level_routes(level):
		if not by_route.has(g):
			print("   route %s has NO built exit — it starts by climbing out of the" % g)
			print("          fire line at whatever point you happen to be standing.")
	var spacings: Array = []
	for i in range(1, exits.size()):
		spacings.append(absf((exits[i][1] as Vector3).z - (exits[i - 1][1] as Vector3).z))
	if spacings.size() > 0:
		var lo := INF
		var hi := 0.0
		for s: float in spacings:
			lo = minf(lo, s)
			hi = maxf(hi, s)
		print("   %d exit(s) across the frontage, %.0f to %.0f m apart" % [
				exits.size(), lo, hi])
		if lo < want:
			print("   note: two of them are %.0f m apart, under the %.0f m at which" % [lo, want])
			print("         two exits read as one wide exit rather than a choice.")
	print("   (%d further ramp(s) elsewhere on the map, not on this line)" % ramps_far.size())

	print("")
	print("── THE WIRE")
	print("   %d belt run(s), %d gap(s)" % [wire.size(), gaps.size()])
	for g: Array in gaps:
		print("   gap %-24s at x %6.0f, z %6.0f" % [g[0], (g[1] as Vector3).x, (g[1] as Vector3).z])
	if gaps.is_empty() and not wire.is_empty():
		print("   NO GAPS AT ALL: every belt on this map is uncut, so the wire is")
		print("   a wall and not a gate. That is a design choice if the routes go")
		print("   round it and a mistake if they run at it.")
	if wire.is_empty():
		print("   no wire belts placed — nothing is channelling anybody")

	print("")
	print("── EMBRASURES, derived from the kit's own constants")
	_embrasures(level)

	print("")
	print("── AND THE PART THAT IS NOT A BUILT EXIT")
	# A 0.8 m cut with 1.5 m of falloff is a bank of about 28 degrees. The
	# squad's step height is 0.45 m, so the lip is not a wall anywhere.
	var slope := rad_to_deg(atan(TR_DEPTH / TR_FALLOFF))
	print("   the fire lines are terrain cuts %.1f m deep with %.1f m of falloff:" % [TR_DEPTH, TR_FALLOFF])
	print("   a %.0f-degree bank, which nothing in the squad has to climb. So our" % slope)
	print("   front line can be left ANYWHERE along its %s, and the built exits" % "frontage")
	print("   above are a convenience rather than a constraint.")

	# THE VERDICT IS ABOUT CHOICE, NOT COUNT. One exit is a funnel; ten evenly
	# spaced exits are a field you wander across. Two to five, far enough apart
	# to be different decisions, is the shape being looked for.
	var ok := exits.size() >= 2
	print("OVER THE TOP %s — %d deliberate exit(s), %d wire gap(s)" % [
			"PASS" if ok else "FAIL", exits.size(), gaps.size()])
	quit(0 if ok else 1)


## The route letters this level actually has pieces for, from the laid names.
## Derived rather than listed: a fourth route added later should appear in this
## probe's output without anybody remembering to come back here.
func _level_routes(level: Node3D) -> Array:
	var kit: Dictionary = LIB.pieces()
	var out: Array = []
	for n in level.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		var at := nm.find("_")
		if at < 1 or not kit.has(nm.substr(at + 1)):
			continue
		# ONLY THE LAID ROUTES. The deck's own dressing is named W####_<piece>
		# and some of those pieces (the ruined tower, a crater) are in the kit
		# manifest too, so a name test alone invents a route "W" out of the
		# scenery. A laid route piece is a child of a group under Trenchworks.
		# The Landmarks group is a ditched tank and a ruined tower, laid from the
		# same kit with their own letter: scenery, not a way across.
		var group := n.get_parent()
		if group == null or group.get_parent() == null:
			continue
		if str(group.name) == "Landmarks" or str(group.get_parent().name) != "Trenchworks":
			continue
		var r := nm.substr(0, 1)
		if not out.has(r):
			out.append(r)
	out.sort()
	return out


## HOW AN EMBRASURE IS COUNTED, and why it is not read out of the scene. An
## embrasure is a CUT IN A BRUSH: block_trench.gd's _embrasures() subtracts a
## T_EMBR-wide slot from the parapet, which leaves no node, no collision shape
## and no dig record. Nothing in the built level says "there is a window here".
##
## So it is derived from the kit's own source, in the only way that cannot go
## stale: the pitch and the slot width are READ OFF block_trench.gd's constants
## (loading a GDScript gives you its consts), the piece lengths are read off the
## manifest's ports, and the run loop below is the same loop _tr_run() uses. The
## three pieces that carry slots are named because the kit source names them —
## _tr_run at the pitch, _tr_firebay with three, _tr_dugout with two — and if
## a fourth is ever given them this probe will under-report until it is added.
## That is a worse outcome than a wrong number looking like a measurement.
## KIT_SRC and SLOTTED, at the top of this file, hold those two facts.
func _embrasures(level: Node3D) -> void:
	var kit: Dictionary = LIB.pieces()
	if kit.is_empty():
		print("   no kit manifest — embrasures NOT COUNTED (run tools/block_trench.gd)")
		return
	var src: Variant = load(KIT_SRC)
	if src == null:
		print("   %s will not load — embrasures NOT COUNTED, because the pitch" % KIT_SRC)
		print("   would have to be typed in and a typed-in pitch is not a measurement.")
		return
	var pitch: float = float(src.T_EMBR_PITCH)
	var width: float = float(src.T_EMBR)
	print("   slots are %.1f m wide at a %.1f m pitch (block_trench.gd's own numbers)" % [width, pitch])
	var laid := {}
	for n in level.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		# Laid pieces are named <route><nn>_<piece>; the piece name is whatever
		# follows the first underscore, and the kit is the authority on whether
		# that is a piece at all.
		var at := nm.find("_")
		if at < 0:
			continue
		var piece := nm.substr(at + 1)
		if not kit.has(piece):
			continue
		# Laid routes only, for the same reason _level_routes() says: the deck's
		# dressing shares piece names with the kit.
		var group := n.get_parent()
		if group == null or group.get_parent() == null \
				or str(group.get_parent().name) != "Trenchworks":
			continue
		laid[piece] = int(laid.get(piece, 0)) + 1
	if laid.is_empty():
		print("   no laid kit pieces found in this level — nothing to count")
		return
	var keys: Array = laid.keys()
	keys.sort()
	var total := 0
	for piece: String in keys:
		var each := 0
		for prefix: String in SLOTTED:
			if not piece.begins_with(prefix):
				continue
			if SLOTTED[prefix] is int:
				each = int(SLOTTED[prefix])
				continue
			# _tr_run's loop, with the length taken from the piece's own ports.
			var ports: Dictionary = (kit[piece] as Dictionary).get("ports", {})
			if not (ports.has("in") and ports.has("out")):
				push_warning("probe_over_the_top: %s has no in/out ports — its slots are not counted" % piece)
				continue
			var length := absf(float(ports.out.x) - float(ports["in"].x))
			var h := length * 0.5
			var c := -h + pitch * 0.5
			while c < h - 1.0:
				each += 1
				c += pitch
		if each > 0:
			total += each * int(laid[piece])
			print("   %-24s x%-3d  %d slot(s) each" % [piece, int(laid[piece]), each])
	if total == 0:
		print("   NONE. Not one laid piece on this map has a firing slot in its")
		print("   parapet, so the only way to shoot is to put your head over the")
		print("   top — which makes the trench a corridor rather than a fighting")
		print("   position.")
	else:
		print("   %d firing slot(s) on the laid works in total" % total)
