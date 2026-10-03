extends "res://tools/block_bridges.gd"

# ─────────────────────────────────────────────
# BRIDGE PROPOSALS — bridge_truss_long rebuilt three ways, to look at before
# anything that ships gets changed.
#
#   godot --headless --path . --script res://tools/block_bridge_proposals.gd -- maps/blocks/proposals
#
# WRITES ONLY INTO maps/blocks/proposals/. Nothing in any level references
# that folder, and no file under maps/blocks/bridges/ is read or written here.
# These are drawings, not a change.
#
#   prop_truss_now     — bridge_truss_long exactly as it is today, as the
#                        control. Every picture of a proposal is worthless
#                        without the same camera pointed at the current one.
#   prop_truss_edges   — the three changes aimed at bodies ending up in the
#                        river: a barrier you cannot ride up, a barrier that
#                        does not stop where the span stops, and embankment
#                        flanks too steep for the baker to call walkable.
#   prop_truss_full    — those three, plus a longer level run-on before the
#                        ramp breaks away, and a flared approach.
#
# WHY THESE AND NOT THE SHOULDER I FIRST SUGGESTED. I said the deck wanted a
# metre of slab outside the barrier, so that a navmesh edge allowed to deviate
# 1.25 m would still hang over concrete. Building it showed that is the wrong
# worry: a body steered at a point past the barrier walks INTO the barrier and
# move_and_slide grinds it along. It does not fall. The places a body can
# actually leave the bridge are the places with NO barrier — past the ends of
# the span, and down the embankment flanks, which are cut at 1 in 1.5, or
# 33.7°, deliberately under the 45° the baker will walk. That is a path into
# the river that the navmesh believes in.
# ─────────────────────────────────────────────

const PROPOSALS := {
	"prop_truss_now": "_prop_now",
	"prop_truss_edges": "_prop_edges",
	"prop_truss_full": "_prop_full",
}

# bridge_truss_long's own numbers, and the five that the proposals move.
const BASE := {
	"span": 72.0, "w": 9.0, "h": 3.0, "tall": 8.0, "bay": 6.0,
	# How far the bottom chord stands proud of the deck. 0.5 m is the worst
	# number available: over the 0.25 m the baker climbs, so the navmesh stops
	# at it, but only knee high on a 1.5 m body, so what a capsule does there
	# is ride up and grind along. The road bridges all use 1.0.
	"barrier": 0.5,
	# Whether anything stops a body leaving the ramp sideways. Today nothing
	# does: the chord runs -span/2 to +span/2 and stops dead at the abutment,
	# and the ramps beyond it are open on both sides over the water.
	"guard_on_land": false,
	# Embankment and abutment flanks fall 1 in this. 1.5 is 33.7°, under the
	# baker's 45°, so the navmesh covers them and a squad can be ordered down
	# one. They end at EARTH_BASE, which on these three bridges is under the
	# river.
	"side_run": 1.5,
	# Level deck before the ramp breaks away. Half a metre is short enough
	# that the break can land inside one navmesh polygon.
	"flat_run": 0.5,
	# How much wider the ramp is at its foot than at the deck.
	"flare": 1.0,
}


func _initialize() -> void:
	var base := ""
	var force := false
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			only.append(a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_bridge_proposals.gd -- maps/blocks/proposals [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	if base.contains("/bridges"):
		# The whole point of this tool is that it cannot touch the real ones.
		print("FAIL  %s is the shipping bridge folder. This tool writes proposals only." % base)
		quit(1)
		return
	if not DirAccess.dir_exists_absolute(base):
		var err := DirAccess.make_dir_recursive_absolute(base)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [base, error_string(err)])
			quit(1)
			return
	var written := 0
	for name: String in PROPOSALS:
		if not only.is_empty() and not only.has(name):
			continue
		var path := base.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — pass --force to overwrite it." % path)
			continue
		_brushes = []
		_ghost_from = -1
		_entities = []
		call(PROPOSALS[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-20s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BRIDGE PROPOSALS DONE: %d written" % written)
	quit()


## The control: bridge_truss_long as it stands.
func _prop_now() -> void:
	_truss_v(BASE)


## A barrier at 1.1 m instead of 0.5, carried on past the span and down both
## ramps, and flanks at 1 in 0.8 — 51°, over the 45° the baker walks, so the
## navmesh ends at the top of the embankment and there is no route down the
## side of it at all.
func _prop_edges() -> void:
	var o := BASE.duplicate()
	o.barrier = 1.1
	o.guard_on_land = true
	o.side_run = 0.8
	_truss_v(o)


## The above, plus four metres of level deck before the ramp breaks away, and
## an approach half again as wide at the foot as at the deck.
func _prop_full() -> void:
	var o := BASE.duplicate()
	o.barrier = 1.1
	o.guard_on_land = true
	o.side_run = 0.8
	o.flat_run = 4.0
	o.flare = 1.6
	_truss_v(o)


## _truss() from block_bridges.gd with the five numbers above pulled out of it.
## Kept line for line the same where it is not one of them, so a diff of the
## two functions is the proposal.
func _truss_v(o: Dictionary) -> void:
	var span: float = o.span
	var w: float = o.w
	var h: float = o.h
	var bay: float = o.bay
	var bar: float = o.barrier
	var bays := int(roundf(span / bay))
	var zt: float = h + o.tall
	box(Vector3(-span * 0.5, -w * 0.5, h - 1.0), Vector3(span * 0.5, w * 0.5, h), ROAD)
	for s: float in [-1.0, 1.0]:
		var y := s * (w * 0.5 + 0.5)
		box(Vector3(-span * 0.5, minf(s * w * 0.5, s * (w * 0.5 + 1.0)), h - 1.5),
				Vector3(span * 0.5, maxf(s * w * 0.5, s * (w * 0.5 + 1.0)), h + bar), RUST)
		box(Vector3(-span * 0.5 + bay, y - 0.375, zt - 0.375), Vector3(span * 0.5 - bay, y + 0.375, zt + 0.375), RUST)
		for e: float in [-1.0, 1.0]:
			beam(Vector3(e * span * 0.5, y, h + bar), Vector3(e * (span * 0.5 - bay), y, zt), 0.75, RUST)
		for i in range(1, bays):
			var x := -span * 0.5 + bay * i
			box(Vector3(x - 0.1875, y - 0.1875, h + bar), Vector3(x + 0.1875, y + 0.1875, zt - 0.375), RUST)
		for i in range(1, bays - 1):
			var xa := -span * 0.5 + bay * i
			var xb := xa + bay
			if xb <= 0.0:
				beam(Vector3(xa, y, zt - 0.375), Vector3(xb, y, h + bar), 0.375, RUST)
			else:
				beam(Vector3(xb, y, zt - 0.375), Vector3(xa, y, h + bar), 0.375, RUST)
	for i in range(1, bays):
		var x := -span * 0.5 + bay * i
		box(Vector3(x - 0.1875, -(w * 0.5 + 0.5), zt - 0.25), Vector3(x + 0.1875, w * 0.5 + 0.5, zt + 0.125), RUST)
	for dir: float in [-1.0, 1.0]:
		_abutment_v(span * 0.5, dir, w, h, o.side_run)
		_embankment_v(span * 0.5, dir, w, h, o)


## _abutment() with its flank angle pulled out. At side_run 0.8 the flat top
## is narrower and the flank falls at 51°, so neither of them bakes as a place
## to stand a metre below the deck.
func _abutment_v(x0: float, dir: float, w: float, h: float, side_run: float) -> void:
	var pts: Array = []
	for x: float in [x0 - 1.0, x0]:
		for s: float in [-1.0, 1.0]:
			var toe := s * (w * 0.5 + (h - EARTH_BASE) * side_run)
			pts.append_array([Vector3(dir * x, s * (w * 0.5 + side_run), h - 1.0),
					Vector3(dir * x, toe, EARTH_BASE), Vector3(dir * x, toe, -6.0)])
	solid(pts, CONCRETE)


## _embankment() with its flank angle, its level run-on and a flare pulled
## out, and the guard that today does not exist at all.
func _embankment_v(x0: float, dir: float, w: float, h: float, o: Dictionary) -> void:
	var side_run: float = o.side_run
	var flare: float = o.flare
	var land: float = x0 + o.flat_run
	var foot: float = land + (h + TOE) * RAMP_RUN
	var pts: Array = []
	for s: float in [-1.0, 1.0]:
		var edge := s * w * 0.5
		var edge_foot := s * w * 0.5 * flare
		var toe_top := s * (w * 0.5 + (h - EARTH_BASE) * side_run)
		var toe_foot := s * (w * 0.5 * flare + (-TOE - EARTH_BASE) * side_run)
		pts.append_array([Vector3(dir * x0, edge, h), Vector3(dir * land, edge, h), Vector3(dir * foot, edge_foot, -TOE),
				Vector3(dir * x0, toe_top, EARTH_BASE), Vector3(dir * land, toe_top, EARTH_BASE),
				Vector3(dir * foot, toe_foot, EARTH_BASE)])
	solid(pts, SPOIL)
	if not o.guard_on_land:
		return
	# A SOLID upstand, not rail(). rail() is posts every 2.5 m with a bar over
	# them, and a 0.4 m body walks between two of those without touching
	# either. It is a handrail you can see through and through.
	for s: float in [-1.0, 1.0]:
		var y0 := s * w * 0.5
		var y1 := y0 + s * 0.5
		var across := Vector2(minf(y0, y1), maxf(y0, y1))
		upstand("y", across, minf(dir * x0, dir * land), maxf(dir * x0, dir * land), h, h, true, o.barrier)
		upstand("y", across, minf(dir * land, dir * foot), maxf(dir * land, dir * foot), -TOE, h, dir < 0.0, o.barrier)
