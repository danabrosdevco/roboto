extends "res://tools/block_bridges.gd"

# ─────────────────────────────────────────────
# BLOCK FORTRESS — the pieces a causeway map is made of: a derelict highway
# carried across the water in sections, and the machine-built fort at the end
# of it.
#
#   maps/blocks/causeway/causeway_*.map — highway deck in 48 m sections that
#       butt end to end, an approach ramp, and three states of disrepair. Built
#       from bridge_highway's section, narrowed to 16 m.
#
#   maps/blocks/fortress/fort_*.map — a machine keep on its own podium, with
#       the ramp down to the data halls inside it, and wall and gate sections
#       for outworks.
#
#   godot --headless --path . --script res://tools/block_fortress.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_fortress.gd -- maps/blocks --force [piece names]
#
# fort_tower.map CARRIES HAND EDITS. It was opened in TrenchBroom and had its
# clipping fixed — 136 faces that exist in the file and not in this source. DO
# NOT PASS --force FOR IT. Running it once destroyed all of them, and they only
# came back because they happened to be committed. To change a texture on it,
# use tools/map_retexture.gd on the .map; to change its SHAPE, change it here
# and then merge by hand, knowing what you are throwing away.
#
# TWO RULES RUN THROUGH ALL OF IT, both learnt the hard way:
#
# WALKABLE GROUND IS FLAT GROUND. The navmesh agent climbs 0.25 m and is 0.6 m
# across. Anything the squad is meant to cross is flat and open — no kerbs
# across a deck, no median barriers, no steps. Where the ground has to change
# height it changes on a ramp of 1 in 5 or shallower, and never narrower than
# 8 m, so the rover and anything larger takes it without a thought.
#
# WRECKAGE DOES NOT COLLIDE. The broken spans look shelled and carry nothing:
# every piece of fallen slab, hanging rail and rubble is built after
# no_collision(), so it is mesh only. What the squad walks on is a clean flat
# surface with nothing scattered on it.
# ─────────────────────────────────────────────

const CAUSEWAY := {
	"causeway_span": "_causeway_span",
	"causeway_span_cracked": "_causeway_span_cracked",
	"causeway_span_broken": "_causeway_span_broken",
	"causeway_ramp": "_causeway_ramp",
	"causeway_pier": "_causeway_pier",
}

const FORTRESS := {
	"fort_tower": "_fort_tower",
	"fort_keep": "_fort_keep",
	"fort_wall": "_fort_wall",
	"fort_gate": "_fort_gate",
}

## The citadel's measurements, all of them on the 1/32 m grid.
const TOW_SHAFT := 24.5     # half the shaft: 49 m square
const TOW_VOID := 20.5      # half the hollow inside: 41 m square
const TOW_TIER := 19.0      # half the upper tier: 38 m square
const TOW_CROWN := 14.0     # half the crown: 28 m square
const TOW_BASE := 0.0       # the basement floor, 10 m below the yard
const TOW_PITCH := 6.0      # floor to floor, and what one ramp climbs at 1 in 5
const TOW_LEVELS := 24      # twenty-four data halls, one above the other
## The fort round it.
const FORT_HALF := 100.0    # half the podium: 200 m square
const FORT_YARD := 10.0     # the yard, and the top of the podium
const FORT_WALK := 14.0     # the walk along the inside of the wall
const FORT_PARAPET := 17.0  # the top of the parapet outside the walk
const GATE_HALF := 8.0      # half the gateway: 16 m clear
## The pit down to the tower: 24 m wide, from the yard to the basement at 1 in
## 6, on the far side of the yard from the gate, into the tower's east face.
const PIT_HALF := 12.0
const PIT_FROM := 88.0
const PIT_TO := 28.0

## The causeway's section: 48 m between piers, 16 m of deck 4 m above the
## water. Wide enough for two vehicles to pass, low enough to climb onto from
## a ramp that is not a kilometre long.
const CWAY_SPAN := 48.0
const CWAY_W := 16.0
const CWAY_H := 4.0
## Machine work: the fort is new, and reads new — clean faces, lit seams.
const SEAM := "PSX_Textures/glitch_tx_1@0.25"
## The same band with no light in it, for the curtain walls. A different
## concrete from TECH_WALL so the trim still reads, just unlit.
const TRIM := "PSX_Textures/concrete_tx_5"


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
		print("usage: godot --headless --path . --script res://tools/block_fortress.gd -- maps/blocks [--force] [piece names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var written := 0
	var skipped := 0
	for pair: Array in [["causeway", CAUSEWAY], ["fortress", FORTRESS]]:
		var dir: String = base.path_join(pair[0])
		if not DirAccess.dir_exists_absolute(dir):
			var err := DirAccess.make_dir_recursive_absolute(dir)
			if err != OK:
				print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
				quit(1)
				return
		var table: Dictionary = pair[1]
		for name: String in table:
			if not only.is_empty() and not only.has(name):
				continue
			var path := dir.path_join(name + ".map")
			if FileAccess.file_exists(path) and not force:
				print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
				skipped += 1
				continue
			_brushes = []
			# Without this a piece that called no_collision() would hand the
			# flag to the next one, and the next piece would build as a ghost.
			_ghost_from = -1
			_entities = []
			call(table[name])
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
				quit(1)
				return
			f.store_string(_map_text())
			f.close()
			written += 1
			print("      %-24s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK FORTRESS DONE: %d written%s" % [written, (", %d skipped" % skipped) if skipped > 0 else ""])
	quit()


# ── The causeway ─────────────────────────────────────────────────────────────

## Deck and piers only — no abutment and no embankment, because these butt end
## to end. The deck's ends are square at ±span/2, so sections placed span apart
## meet flush with nothing to step over.
func _cway_deck(span: float, w: float, h: float, piers: int, bottom: float = -7.0) -> void:
	var depth := 1.75
	_deck(span, w, h, depth, 1.0)
	var sub := span / (piers + 1)
	for i in piers:
		_column_pier(-span * 0.5 + sub * (i + 1), w, h, depth, bottom, [-w * 0.28, w * 0.28])


## Lane markings: an edge line each side and a dashed centre. No barrier down
## the middle — a median would cut the deck into two lanes the squad could not
## cross between.
func _cway_paint(x0: float, x1: float, w: float, h: float) -> void:
	for s: float in [-1.0, 1.0]:
		_paint(x0, x1, s * (w * 0.5 - 1.25), h)
	_paint(x0, x1, 0.0, h, 3.0, 5.0)


## A sound section: 48 m of deck on three column piers, 16 m wide, 4 m up.
func _causeway_span() -> void:
	_cway_deck(CWAY_SPAN, CWAY_W, CWAY_H, 3)
	_cway_paint(-CWAY_SPAN * 0.5, CWAY_SPAN * 0.5, CWAY_W, CWAY_H)


## The same span, settled over its middle pier: the deck dips 0.2 m and comes
## back, which the eye reads as subsidence and the navmesh does not notice.
## Cracked slab and spalled concrete on top of it, none of it solid.
func _causeway_span_cracked() -> void:
	_cway_deck(CWAY_SPAN, CWAY_W, CWAY_H, 3)
	_cway_paint(-CWAY_SPAN * 0.5, CWAY_SPAN * 0.5, CWAY_W, CWAY_H)
	# The dip: a shallow pan 16 m long, 0.2 m deep, on 1 in 20 slopes.
	box(Vector3(-8.0, -CWAY_W * 0.5, CWAY_H - 0.25), Vector3(8.0, CWAY_W * 0.5, CWAY_H - 0.2), ROAD)
	for s: float in [-1.0, 1.0]:
		ramp(8.0 * s, -CWAY_W * 0.5, 12.0 * s, CWAY_W * 0.5, CWAY_H - 0.25, 0.0, 0.2, "+x" if s < 0.0 else "-x", ROAD)
	no_collision()
	for k in 7:
		var x := -10.0 + k * 3.25
		chunk(Vector3(x, -4.0 + (k % 3) * 4.0, CWAY_H + 0.1), Vector3(1.6, 1.2, 0.2), 20.0 * k, RUBBLE)
	# A length of parapet gone, lying where it fell.
	box(Vector3(-4.0, CWAY_W * 0.5, CWAY_H), Vector3(6.0, CWAY_W * 0.5 + 1.0, CWAY_H + 1.0), SCORCH)


## A shelled section: the northern half of the deck is gone over 20 m, leaving
## a 7 m lane on the south side. The lane is clear, flat and unobstructed —
## everything hanging into the hole is mesh only.
func _causeway_span_broken() -> void:
	var half := CWAY_SPAN * 0.5
	var w := CWAY_W
	var depth := 1.75
	# Deck in three pieces round the hole: x -24..-10, x 10..24, and the lane.
	for seg: Array in [[-half, -10.0], [10.0, half]]:
		box(Vector3(seg[0], -w * 0.5, CWAY_H - 1.0), Vector3(seg[1], w * 0.5, CWAY_H), ROAD)
	box(Vector3(-10.0, -w * 0.5, CWAY_H - 1.0), Vector3(10.0, -w * 0.5 + 7.0, CWAY_H), ROAD)
	# Side walls: the south one runs the length, the north one is broken away.
	box(Vector3(-half, -w * 0.5 - 1.0, CWAY_H - depth), Vector3(half, -w * 0.5, CWAY_H + 1.0), ROAD)
	for seg: Array in [[-half, -11.0], [11.0, half]]:
		box(Vector3(seg[0], w * 0.5, CWAY_H - depth), Vector3(seg[1], w * 0.5 + 1.0, CWAY_H + 1.0), ROAD)
	var sub := CWAY_SPAN / 4.0
	for i in 3:
		_column_pier(-half + sub * (i + 1), w, CWAY_H, depth, -7.0, [-w * 0.28, w * 0.28])
	_cway_paint(-half, half, w, CWAY_H)
	no_collision()
	# Slabs hanging into the hole, rebar, and the span in the water below.
	for k in 4:
		chunk(Vector3(-6.0 + k * 4.0, 1.0 + (k % 2) * 3.0, CWAY_H - 1.2), Vector3(3.5, 3.0, 1.0), 14.0 + 30.0 * k, RUBBLE)
	chunk(Vector3(0.0, 5.0, -1.2), Vector3(14.0, 7.0, 1.0), 6.0, RUBBLE)
	chunk(Vector3(-7.0, 7.5, -1.4), Vector3(5.0, 4.0, 1.0), 25.0, SCORCH)
	for k in 5:
		beam(Vector3(-8.0 + k * 4.0, 2.0, CWAY_H - 1.0), Vector3(-7.0 + k * 4.0, 5.0, CWAY_H - 2.2), 0.09, METAL)


## The way on: 24 m of embankment climbing 4 m at 1 in 6, 16 m wide, square at
## the top so a span butts it. Gentle enough for anything on wheels.
## HALF THE WIDTH OF THE FLARE AT THE MOUTH, EACH SIDE. The ramp used to be one
## 16 m strip for its whole 24 m, so the only way on to the causeway was a 16 m
## gate at the far end: a body approaching from anywhere else met the ramp's
## flank, which is a 1.6 m step up at mid-ramp, and had to walk back out and
## funnel. Measured on the baked mesh, the walkable surface was 17 m of a 31 m
## footprint and the rest was wall.
##
## The deck still narrows to CWAY_W where it lands, because that is what the
## spans are. It is the approach that opens out.
const CWAY_FLARE := 7.0


func _causeway_ramp() -> void:
	var w := CWAY_W
	var run := 24.0
	ramp(-run, -w * 0.5, 0.0, w * 0.5, -1.0, 0.0, CWAY_H, "+x", ROAD)
	# A wedge each side, wide at the mouth and closing to the deck line at the
	# top, so the whole fan is one continuous walking surface. Built as a hull
	# rather than a ramp() because ramp() is rectangular and this tapers; it
	# meets the main ramp exactly on y = +-w/2, touching and not overlapping.
	#
	# It starts OUTSIDE the side wall, at w/2 + 1, and its apex stops at the
	# abutment face at x = -1. Run to w/2 and to x = 0 instead and it lies
	# inside both of them — 22 overlapping brush pairs on top of the 7 this
	# piece already had. The wall between the two surfaces is no barrier where
	# it matters: it rises from nothing at the mouth and is level with the ramp
	# for the first half, by which point a body is already on the deck line.
	for s: float in [-1.0, 1.0]:
		var inner: float = s * (w * 0.5 + 1.0)
		var outer: float = s * (w * 0.5 + 1.0 + CWAY_FLARE)
		solid([
			Vector3(-run, inner, -1.0), Vector3(-run, outer, -1.0),
			Vector3(-run, inner, 0.0), Vector3(-run, outer, 0.0),
			Vector3(-1.0, inner, -1.0), Vector3(-1.0, inner, CWAY_H),
		], ROAD)
	# Side walls along the climb, and the abutment the deck lands on.
	for s: float in [-1.0, 1.0]:
		var y0: float = s * w * 0.5
		var y1: float = s * (w * 0.5 + 1.0)
		var pts: Array = []
		for pair: Array in [[-run, -1.0], [0.0, CWAY_H + 1.0]]:
			for y: float in [y0, y1]:
				pts.append(Vector3(pair[0], y, -1.0))
				pts.append(Vector3(pair[0], y, pair[1]))
		solid(pts, ROAD)
	# The abutment is the FOOTING under the ramp, stopping at its underside.
	# Taken up to CWAY_H it is buried inside the ramp and both side walls — the
	# last 3 of the 7 overlapping pairs this piece shipped with.
	box(Vector3(-1.0, -w * 0.5 - 1.0, -6.0), Vector3(0.0, w * 0.5 + 1.0, -1.0), CONCRETE)
	# NO _embankment HERE ANY MORE. It banks earth from the deck line outwards
	# over the same ground the flare now occupies, which is 14 more overlapping
	# brush pairs, and its job — getting from the field up to the deck — is what
	# the flare does, walkably, which the embankment never did: its sides fall
	# 1 in SIDE_RUN, deliberately steeper than the baker will walk, so that on a
	# BRIDGE the squad cannot climb the bank and fall in the river. On a causeway
	# abutment that same slope was the wall they kept meeting.


## Where a span is missing: one pier standing in the water with a stub of deck
## on it. Nothing to walk on — it marks the gap.
func _causeway_pier() -> void:
	_column_pier(0.0, CWAY_W, CWAY_H, 1.75, -7.0, [-CWAY_W * 0.28, CWAY_W * 0.28])
	no_collision()
	box(Vector3(-3.0, -CWAY_W * 0.5, CWAY_H - 1.0), Vector3(3.0, CWAY_W * 0.5, CWAY_H), ROAD)
	chunk(Vector3(0.0, 0.0, CWAY_H - 0.6), Vector3(5.0, 9.0, 1.0), 8.0, RUBBLE)
	for k in 4:
		beam(Vector3(-2.0 + k * 1.5, -5.0, CWAY_H - 1.0), Vector3(-2.5 + k * 1.5, -7.0, CWAY_H - 2.5), 0.09, METAL)


# ── The tower ────────────────────────────────────────────────────────────────

## THE CITADEL. The fort and the tower are one piece, because they interlock:
## the fort's yard is the tower's roof line, the fort's pit is the way into the
## tower, and a tower standing on a separate podium would bake a navmesh floor
## sealed inside its own walls.
##
## The way through it, which is the mission:
##   1. up the outside ramp, 60 m of it, to the gate in the west wall;
##   2. across the yard, 200 m square, under the walls and the bastions;
##   3. DOWN the pit, 60 m at 1 in 6, to the portal at the foot of the tower;
##   4. UP through twenty-four data halls, from the basement to 138 m.
##
## 260 m to the tips of the horns, on a 49 m shaft. Ribbed the whole way and
## set back twice, after the courts and jails built like that, and given the
## taper and the four horns of a black tower out of a story.
##
## THE INSIDE AND THE OUTSIDE DO NOT MEET. No gunloops, no windows, no firing
## slots: one portal at the foot of the pit, one door onto the terrace at the
## top, and nothing else. It keeps the fight inside honest and keeps the
## navmesh out of the walls.
func _fort_tower() -> void:
	_citadel_podium()
	_citadel_rim()
	_citadel_pit()
	_tower_shell()
	for n in TOW_LEVELS:
		var h: float = TOW_BASE + TOW_PITCH * n
		# Each floor is its own entity, so FuncGodot gives it its own mesh. The
		# project renders in GL compatibility, which lights at most eight lights
		# per mesh: as one mesh the tower could not have a lamp on every floor.
		entity("func_detail")
		_tower_plate(h, n)
		_tower_kit(h, n)
		if n < TOW_LEVELS - 1:
			var a := _tower_flight(n % 4)
			ramp(a[0], a[1], a[2], a[3], h - 1.0, h, h + TOW_PITCH, a[4], SLAB)
	# Everything solid is built by now, so the rest of the fit-out can be mesh
	# only. no_collision() is a single line in the piece, not a switch: called
	# inside the loop above it would have turned every floor after the first
	# into a ghost.
	no_collision()
	for n in TOW_LEVELS:
		_tower_trays(TOW_BASE + TOW_PITCH * n, n)


## The podium: the yard, in slabs round the two holes in it — the tower's
## footprint and the pit that leads to it. Never a slab UNDER the tower: the
## baker reads surfaces, not solids, and a podium top face under a 260 m tower
## bakes as a floor sealed inside it.
##
## IT STOPS AT THE INSIDE FACE OF THE WALL, not at the outside of the fort.
## When it ran the full width its outer face sat in the same plane as the
## wall's, and the two fought over every pixel of the bottom half of the fort
## — concrete over tech wall, flickering between them as the camera moved.
func _citadel_podium() -> void:
	var i := FORT_HALF - 8.0
	var t := TOW_SHAFT
	var p := PIT_HALF
	for r: Array in [[-i, -i, i, -t], [-i, t, i, i], [-i, -t, -t, t], [PIT_FROM, -t, i, t],
			[t, -t, PIT_FROM, -p], [t, p, PIT_FROM, t]]:
		box(Vector3(r[0], r[1], -1.0), Vector3(r[2], r[3], FORT_YARD), PAD)
	# The floor of the gateway itself, where the wall is not.
	box(Vector3(-FORT_HALF, -GATE_HALF, -1.0), Vector3(-i, GATE_HALF, FORT_YARD), PAD)
	# The way in: 60 m of ramp outside the west wall, 16 m wide, at 1 in 6.
	ramp(-FORT_HALF - 60.0, -GATE_HALF, -FORT_HALF, GATE_HALF, -1.0, 0.0, FORT_YARD, "+x", PAD)
	# A PARAPET DOWN BOTH SIDES OF IT, which it has never had.
	#
	# The ramp is a free-standing wedge with vertical flanks, ten metres high at
	# the top and open to the air down both sides. Walked on the baked mesh, the
	# ground beside it joins the ramp only at the very foot: from about five
	# metres up it is a separate island, so a body halfway along has walkable
	# mesh right next to it in plan and no way onto it. The path solver sends
	# them back to the foot while crowd steering shoves them at the straight
	# line, and they grind along the flank — which is what "the AI get stuck on
	# the edges" is. On the mesh itself there is only the agent radius, 0.6 m,
	# between a body and a ten metre drop.
	#
	# block_bridges already fixed this exact thing for the bridge ramps, and its
	# comment says why: it "left every ramp in this file open down both sides,
	# over the water, at exactly the place a squad is funnelling and shoving".
	# This is the same wall on the same kind of edge.
	#
	# 0.9 m, NOT 0.3: anything from 0.25 to 0.5 is the band where the baker will
	# not climb it but a body steps straight over it, which is how the canal
	# coping put squads in the water. Above the 0.45 m step-over it stops them
	# dead. It sits OUTSIDE the gate line, so the 16 m of roadway is untouched.
	# One convex wedge a side, not upstand(): upstand builds its slope as a
	# stack of brushes that overlap each other, which put 26 new overlapping
	# pairs into a piece that already carries 461. This is one brush — top
	# following the ramp, bottom flat on the ramp's own base — and it meets the
	# ramp's flank at exactly y = +-GATE_HALF, touching and not overlapping.
	var foot := -FORT_HALF - 60.0
	for s: float in [-1.0, 1.0]:
		var inner: float = s * GATE_HALF
		var outer: float = inner + s * 0.5
		solid([
			Vector3(foot, inner, -1.0), Vector3(foot, outer, -1.0),
			Vector3(foot, inner, 0.9), Vector3(foot, outer, 0.9),
			Vector3(-FORT_HALF - 0.3, inner, -1.0), Vector3(-FORT_HALF - 0.3, outer, -1.0),
			Vector3(-FORT_HALF - 0.3, inner, FORT_YARD + 0.75),
			Vector3(-FORT_HALF - 0.3, outer, FORT_YARD + 0.75),
		], TECH_WALL)


## The wall: 8 m thick to a walk 4 m above the yard, with a parapet outside it,
## one brush from the ground up. Eight ramps climb from the yard onto the walk,
## two a side, and the walk itself climbs another 4 m at each corner onto the
## bastions — so the corners look down on the rest of the wall the way a corner
## tower should, and the whole circuit is still walkable.
func _citadel_rim() -> void:
	var f := FORT_HALF
	var inner := f - 8.0
	for s: float in [-1.0, 1.0]:
		# North and south walls run the full width.
		box(Vector3(-f, s * inner, -1.0), Vector3(f, s * f, FORT_WALK), TECH_WALL)
		box(Vector3(-f, s * (f - 3.0), FORT_WALK), Vector3(f, s * f, FORT_PARAPET), TECH_WALL)
		# The east wall, and the west one in two lengths either side of the gate.
		# They stop at the inside face of the north and south walls, so no two
		# of them share an outer plane to fight over.
		box(Vector3(inner, s * GATE_HALF, -1.0), Vector3(f, s * inner, FORT_WALK), TECH_WALL)
		box(Vector3(f - 3.0, s * GATE_HALF, FORT_WALK), Vector3(f, s * inner, FORT_PARAPET), TECH_WALL)
		box(Vector3(-f, s * GATE_HALF, -1.0), Vector3(-inner, s * inner, FORT_WALK), TECH_WALL)
		box(Vector3(-f, s * GATE_HALF, FORT_WALK), Vector3(-f + 3.0, s * inner, FORT_PARAPET), TECH_WALL)
	# The gateway: 16 m wide and 8 m high, with its head carried across.
	box(Vector3(-f, -GATE_HALF, FORT_YARD + 8.0), Vector3(-inner, GATE_HALF, FORT_PARAPET + 2.0), TECH_WALL)
	box(Vector3(-f - 0.5, -GATE_HALF - 2.0, FORT_PARAPET + 2.0), Vector3(-inner, GATE_HALF + 2.0, FORT_PARAPET + 3.0), CLAD)
	# UNLIT. These jambs and the bastion bands below were SEAM, which puts an
	# emissive strip down both sides of the gate and along the top of all four
	# bastion parapets — a glowing outline round the whole curtain wall, and
	# the thing anyone looking at the causeway sees first. The tower keeps its
	# lit seams; the walls it stands behind do not.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-f - 0.25, s * GATE_HALF, FORT_YARD), Vector3(-inner, s * (GATE_HALF + 0.5), FORT_PARAPET + 2.0), TRIM)
	_citadel_ramps()
	_citadel_bastions()


## The eight ramps from the yard up onto the walk, two a side. They climb
## ACROSS the wall rather than along it, so each meets the walk on its whole
## width instead of at a corner.
##
## Every one is given its low and high ends in sorted order with the run
## direction chosen to match. Passing them the other way round — as the south
## and west ones were — builds a ramp that climbs from the wall down to the
## yard, which looks identical from above and is walkable from neither end.
func _citadel_ramps() -> void:
	var inner := FORT_HALF - 8.0
	var foot := inner - 24.0
	for s: float in [-1.0, 1.0]:
		var lo: float = minf(s * foot, s * inner)
		var hi: float = maxf(s * foot, s * inner)
		for o: float in [-40.0, 40.0]:
			ramp(o - 3.5, lo, o + 3.5, hi, FORT_YARD - 1.0, FORT_YARD, FORT_WALK,
					"+y" if s > 0.0 else "-y", PAD)
			ramp(lo, o - 3.5, hi, o + 3.5, FORT_YARD - 1.0, FORT_YARD, FORT_WALK,
					"+x" if s > 0.0 else "-x", PAD)


## The corner towers. Their platform stands 4 m above the walk, and the walk
## climbs to meet it along both adjoining walls — the ramps are IN the walk,
## its full 8 m width, not shelves hung beside it over the yard. That was the
## mistake the first time: a ramp beside the walk meets the bastion at a
## corner, and three of the four corners came out unreachable.
func _citadel_bastions() -> void:
	var f := FORT_HALF
	var inner := f - 8.0
	var top := FORT_WALK + 4.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var cx: float = sx * (f - 11.0)
			var cy: float = sy * (f - 11.0)
			box(Vector3(cx - 12.0, cy - 12.0, -1.0), Vector3(cx + 12.0, cy + 12.0, top), TECH_WALL)
			# Parapet on the two outer sides only; the inner two are the way on.
			box(Vector3(cx + sx * 8.0, cy - 12.0, top), Vector3(cx + sx * 12.0, cy + 12.0, top + 7.0), TECH_WALL)
			box(Vector3(cx - 12.0, cy + sy * 8.0, top), Vector3(cx + 12.0, cy + sy * 12.0, top + 7.0), TECH_WALL)
			# The band along the top of it. TRIM, not SEAM: lit, this put a
			# glowing line round all four bastions and the gate, which read as
			# an outline round the whole fort from down the causeway.
			box(Vector3(cx + sx * 8.0, cy - 12.0, top + 6.6), Vector3(cx + sx * 12.0, cy + 12.0, top + 7.0), TRIM)
			box(Vector3(cx - 12.0, cy + sy * 8.0, top + 6.6), Vector3(cx + 12.0, cy + sy * 12.0, top + 7.0), TRIM)
			# The walk climbs the last 24 m to it along both adjoining walls.
			var wall_lo: float = minf(sy * inner, sy * f)
			var wall_hi: float = maxf(sy * inner, sy * f)
			ramp(minf(sx * 77.0, sx * 53.0), wall_lo, maxf(sx * 77.0, sx * 53.0), wall_hi,
					FORT_WALK - 1.0, FORT_WALK, top, "+x" if sx > 0.0 else "-x", PAD)
			var side_lo: float = minf(sx * inner, sx * f)
			var side_hi: float = maxf(sx * inner, sx * f)
			ramp(side_lo, minf(sy * 77.0, sy * 53.0), side_hi, maxf(sy * 77.0, sy * 53.0),
					FORT_WALK - 1.0, FORT_WALK, top, "+y" if sy > 0.0 else "-y", PAD)

## The pit: down from the yard to the tower's basement, 24 m wide, at 1 in 6.
## It is on the FAR side of the yard from the gate on purpose — the squad has
## to cross the whole fort and go round the tower to reach it, which is what
## the yard is for. Walls either side, one brush each from the ground to the
## yard, so nothing stands on a top face.
func _citadel_pit() -> void:
	var p := PIT_HALF
	ramp(PIT_TO, -p, PIT_FROM, p, -1.0, TOW_BASE, FORT_YARD, "+x", PAD)
	box(Vector3(TOW_SHAFT, -p, -1.0), Vector3(PIT_TO, p, TOW_BASE), PAD)
	for s: float in [-1.0, 1.0]:
		box(Vector3(TOW_SHAFT, s * p, -1.0), Vector3(PIT_FROM, s * (p + 2.0), FORT_YARD), TECH_WALL)
		box(Vector3(TOW_SHAFT, s * (p + 0.4), FORT_YARD - 0.6), Vector3(PIT_FROM, s * (p + 2.0), FORT_YARD - 0.2), SEAM)

## The shaft, its ribs, the two set-backs and the horns.
func _tower_shell() -> void:
	var t := TOW_SHAFT
	var v := TOW_VOID
	var top := TOW_BASE + TOW_PITCH * (TOW_LEVELS - 1) + 8.0
	var door := 10.0
	for s: float in [-1.0, 1.0]:
		box(Vector3(-t, s * v, TOW_BASE - 1.0), Vector3(t, s * t, top), PALE)
	box(Vector3(-t, -v, TOW_BASE - 1.0), Vector3(-v, v, top), PALE)
	# The east wall, with the portal from the pit cut through it. East, because
	# the pit is on the far side of the yard from the gate.
	for s: float in [-1.0, 1.0]:
		box(Vector3(v, s * door, TOW_BASE - 1.0), Vector3(t, s * v, top), PALE)
	box(Vector3(v, -door, TOW_BASE + 8.0), Vector3(t, door, top), PALE)
	# Ribs: 2.5 m of pilaster every 4 m, standing 1.5 m proud, from the yard up.
	# Nothing between them but wall.
	for k in 11:
		var o := -20.0 + k * 4.0
		for s: float in [-1.0, 1.0]:
			box(Vector3(o - 1.25, s * t, FORT_YARD), Vector3(o + 1.25, s * (t + 1.5), top), TECH_WALL)
			var foot := FORT_YARD
			if s > 0.0 and absf(o) < door + 1.5:
				foot = TOW_BASE + 9.0
			box(Vector3(s * t, o - 1.25, foot), Vector3(s * (t + 1.5), o + 1.25, top), TECH_WALL)
	var tier := top + 50.0
	box(Vector3(-TOW_TIER, -TOW_TIER, top), Vector3(TOW_TIER, TOW_TIER, tier), PALE)
	for k in 9:
		var o := -16.0 + k * 4.0
		for s: float in [-1.0, 1.0]:
			box(Vector3(o - 1.25, s * TOW_TIER, top), Vector3(o + 1.25, s * (TOW_TIER + 1.5), tier), TECH_WALL)
			box(Vector3(s * TOW_TIER, o - 1.25, top), Vector3(s * (TOW_TIER + 1.5), o + 1.25, tier), TECH_WALL)
	var crown := tier + 28.0
	box(Vector3(-TOW_CROWN, -TOW_CROWN, tier), Vector3(TOW_CROWN, TOW_CROWN, crown), CLAD)
	box(Vector3(-TOW_CROWN, -TOW_CROWN, crown - 0.5), Vector3(TOW_CROWN, TOW_CROWN, crown), SEAM)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var pts: Array = []
			for lvl: Array in [[crown, 0.0], [crown + 36.0, 4.0]]:
				var z: float = lvl[0]
				var lean: float = lvl[1]
				var cx: float = sx * (TOW_CROWN - 3.0 + lean)
				var cy: float = sy * (TOW_CROWN - 3.0 + lean)
				var r: float = 3.0 - lean * 0.6
				pts.append_array([Vector3(cx - r, cy - r, z), Vector3(cx + r, cy - r, z),
						Vector3(cx + r, cy + r, z), Vector3(cx - r, cy + r, z)])
			solid(pts, CLAD)
	# The one door out, off the top floor onto the terrace the set-back leaves.
	box(Vector3(-t, -door, top - TOW_PITCH), Vector3(-v, door, top - TOW_PITCH + 5.0), SEAM)
	_relay_mast(crown)


## THE UPLINK, on the crown between the horns. This is what the tower is for
## and why the machines hold the island: the island is a data centre, and this
## is how its compute leaves it.
##
## It is built as infrastructure rather than as an aerial — a clad core 16 m
## square carrying bank after bank of heat exchangers, dish arrays on
## outriggers at two levels, and a braced lattice above that to the head. The
## citadel tops out at 400 m, and from the mainland shore the relay is what you
## see before the tower under it resolves at all.
##
## Nothing up here is walkable and nothing is meant to be — the shaft's top
## floor is 262 m below the head. It is silhouette and objective, not ground.
func _relay_mast(z0: float) -> void:
	var deck := z0 + 6.0
	var core_top := deck + 100.0
	_relay_deck(z0, deck)
	_relay_core(deck, core_top)
	_relay_lattice(core_top, core_top + 50.0)
	_relay_head(core_top + 50.0)


## The machine deck it all stands on: the crown's whole footprint, with a lit
## border and four buttresses gathering in to the core.
func _relay_deck(z0: float, deck: float) -> void:
	var c := TOW_CROWN
	box(Vector3(-c, -c, z0), Vector3(c, c, deck), CLAD)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-c, s * (c - 0.5), deck - 0.5), Vector3(c, s * c, deck), SEAM)
		box(Vector3(s * (c - 0.5), -(c - 0.5), deck - 0.5), Vector3(s * c, c - 0.5, deck), SEAM)
	# Buttresses on the diagonals, deck edge up to the core's foot.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var pts: Array = []
			for lvl: Array in [[deck, c - 1.5], [deck + 16.0, 7.0]]:
				var z: float = lvl[0]
				var r: float = lvl[1]
				pts.append_array([Vector3(sx * r, sy * (r - 3.0), z), Vector3(sx * (r - 3.0), sy * r, z),
						Vector3(sx * (r - 5.0), sy * (r - 5.0), z)])
			solid(pts, TECH_WALL)


## The core: a hundred metres of clad machine, stepping in as it climbs, with
## a bank of heat exchanger fins on every face of every stage. The fins are
## what make it read as plant rather than as a mast — a data centre is mostly
## a machine for moving heat.
func _relay_core(foot: float, top: float) -> void:
	var stages := 5
	var tall: float = (top - foot) / stages
	for i in stages:
		var r: float = 8.0 - i * 0.5
		var z: float = foot + tall * i
		box(Vector3(-r, -r, z), Vector3(r, r, z + tall), CLAD)
		# A lit band at each joint, and the ribs that carry the fins.
		box(Vector3(-r - 0.25, -r - 0.25, z + tall - 1.0), Vector3(r + 0.25, r + 0.25, z + tall - 0.4), METAL)
		for s: float in [-1.0, 1.0]:
			box(Vector3(-r, s * r, z), Vector3(r, s * (r + 0.5), z + tall - 1.0), TECH_WALL)
			box(Vector3(s * r, -r, z), Vector3(s * (r + 0.5), r, z + tall - 1.0), TECH_WALL)
		# The fins themselves: six louvres a face, standing 1.5 m proud.
		for k in 6:
			var fz: float = z + 3.0 + k * (tall - 6.0) / 5.0
			for s: float in [-1.0, 1.0]:
				box(Vector3(-r + 1.0, s * (r + 0.5), fz), Vector3(r - 1.0, s * (r + 2.0), fz + 1.0), METAL)
				box(Vector3(s * (r + 0.5), -r + 1.0, fz), Vector3(s * (r + 2.0), r - 1.0, fz + 1.0), METAL)
	# Dish arrays on outriggers, at a third and two thirds of the way up.
	for level: float in [foot + tall * 1.5, foot + tall * 3.5]:
		var r := 7.0
		for k in 4:
			var a := TAU * k / 4.0
			var d := Vector3(cos(a), sin(a), 0.0)
			beam(d * (r - 1.0) + Vector3(0.0, 0.0, level), d * (r + 7.0) + Vector3(0.0, 0.0, level), 0.5, METAL)
			var c := d * (r + 8.0) + Vector3(0.0, 0.0, level)
			cylinder(Vector3(c.x, c.y, c.z - 2.5), 3.0, 1.0, 12, CLAD)
			cylinder(Vector3(c.x, c.y, c.z - 1.6), 2.6, 0.4, 12, METAL)
			beam(Vector3(c.x, c.y, c.z - 1.5), Vector3(c.x, c.y, c.z + 2.0), 0.25, METAL)


## Above the core, a braced lattice: four legs drawing in from 10 m to 4 m,
## with a ring and a diagonal in every bay.
func _relay_lattice(foot: float, head: float) -> void:
	var bays := 6
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			beam(Vector3(sx * 5.0, sy * 5.0, foot), Vector3(sx * 2.0, sy * 2.0, head), 0.5, METAL)
	for i in range(1, bays + 1):
		var t: float = float(i) / bays
		var tp: float = float(i - 1) / bays
		var r: float = lerpf(5.0, 2.0, t)
		var rp: float = lerpf(5.0, 2.0, tp)
		var z: float = lerpf(foot, head, t)
		var zp: float = lerpf(foot, head, tp)
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			var b := TAU * (k + 1) / 4.0 + PI * 0.25
			var s2 := sqrt(2.0)
			beam(Vector3(cos(a) * r * s2, sin(a) * r * s2, z),
					Vector3(cos(b) * r * s2, sin(b) * r * s2, z), 0.3, METAL)
			beam(Vector3(cos(a) * rp * s2, sin(a) * rp * s2, zp),
					Vector3(cos(b) * r * s2, sin(b) * r * s2, z), 0.24, METAL)
	# Panel antennas up the lattice, three to a face.
	for k in 3:
		var a := TAU * k / 3.0
		var z: float = foot + 14.0
		var o := Vector3(cos(a), sin(a), 0.0) * 4.4
		box_yawed(Vector3(o.x - 0.5, o.y - 2.0, z), Vector3(o.x + 0.5, o.y + 2.0, z + 9.0),
				Vector3(o.x, o.y, z), rad_to_deg(a), CLAD)


## The head: the link itself, drum on drum, lit, with a needle above it.
func _relay_head(z: float) -> void:
	cylinder(Vector3(0.0, 0.0, z), 5.0, 5.0, 12, CLAD)
	cylinder(Vector3(0.0, 0.0, z + 1.0), 5.3, 0.5, 12, SEAM)
	cylinder(Vector3(0.0, 0.0, z + 5.0), 3.4, 4.0, 10, CLAD)
	cylinder(Vector3(0.0, 0.0, z + 6.0), 3.7, 0.5, 10, SEAM)
	cylinder(Vector3(0.0, 0.0, z + 9.0), 2.0, 3.0, 8, CLAD)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var d := Vector3(cos(a), sin(a), 0.0)
		beam(d * 3.2 + Vector3(0.0, 0.0, z + 5.5), d * 6.0 + Vector3(0.0, 0.0, z + 3.0), 0.22, METAL)
	beam(Vector3(0.0, 0.0, z + 12.0), Vector3(0.0, 0.0, z + 26.0), 0.35, METAL)
	cylinder(Vector3(0.0, 0.0, z + 26.0), 0.8, 1.5, 6, SEAM)


## The floor slab: the whole shaft, less the well where the ramp from the floor
## below comes up through it. Without that well the ramp would run into the
## underside of this slab with no headroom for the last stretch of it, and the
## climb would stop there with nothing to show why.
func _tower_plate(h: float, n: int) -> void:
	var v := TOW_VOID
	if n == 0:
		box(Vector3(-v, -v, h - 0.75), Vector3(v, v, h), SLAB)
		return
	var well := _tower_well((n - 1) % 4)
	for r: Array in [[-v, -v, v, well[1]], [-v, well[3], v, v],
			[-v, well[1], well[0], well[3]], [well[2], well[1], v, well[3]]]:
		if r[2] - r[0] < 0.5 or r[3] - r[1] < 0.5:
			continue
		box(Vector3(r[0], r[1], h - 0.75), Vector3(r[2], r[3], h), SLAB)


## The ramp up one inside wall: [x0, y0, x1, y1, run], 7 m wide over a 30 m
## run, stopping 10 m short of the far wall. Those last metres are the landing,
## and they are floor rather than ramp: a ramp that runs all the way to the
## corner meets the floor it is trying to reach at a single point, and the
## navmesh does not join a point to anything.
func _tower_flight(w: int) -> Array:
	var v := TOW_VOID
	match w:
		0: return [-20.0, -v, 10.0, -v + 7.0, "+x"]
		1: return [v - 7.0, -20.0, v, 10.0, "+y"]
		2: return [-10.0, v - 7.0, 20.0, v, "-x"]
		_: return [-v, -10.0, -v + 7.0, 20.0, "-y"]


## The hole the top of that ramp comes up through: [x0, y0, x1, y1].
##
## It opens 12 m along the 30 m run, not at the top. The slab above is 5.25 m
## over the foot of the ramp and the ramp climbs at 1 in 5, so headroom runs
## out 21 m along — and a ramp with 1.4 m of headroom is a ramp the navmesh
## stops dead in the middle of.
func _tower_well(w: int) -> Array:
	var v := TOW_VOID
	match w:
		0: return [-8.0, -v, 10.0, -v + 7.0]
		1: return [v - 7.0, -8.0, v, 10.0]
		2: return [-10.0, v - 7.0, 8.0, v]
		_: return [-v, -10.0, -v + 7.0, 8.0]


## What is on the floor: rows of racks down the middle with 5 m aisles, and on
## some floors the plant that cools them. Nothing within 7 m of the wall, so
## there is always a lane round the outside whatever else is in the way.
func _tower_kit(h: float, n: int) -> void:
	if n == 0:
		# The hall you come in to is kept clear — the fight starts here and the
		# squad has to be able to get through the door and spread out.
		return
	var along_x := n % 2 == 0
	var rows := 4 if n % 3 != 0 else 3
	for i in rows:
		var o := -10.5 + i * 7.0
		# A line of indicators down the face of each row, not a strip along the
		# top of it: glitch_tx_1 over a whole surface reads as mould.
		if along_x:
			box(Vector3(-13.5, o - 0.7, h), Vector3(13.5, o + 0.7, h + 2.4), CLAD)
			for s: float in [-1.0, 1.0]:
				box(Vector3(-13.5, o + s * 0.7, h + 1.6), Vector3(13.5, o + s * 0.85, h + 1.8), SEAM)
		else:
			box(Vector3(o - 0.7, -13.5, h), Vector3(o + 0.7, 13.5, h + 2.4), CLAD)
			for s: float in [-1.0, 1.0]:
				box(Vector3(o + s * 0.7, -13.5, h + 1.6), Vector3(o + s * 0.85, 13.5, h + 1.8), SEAM)
	if n % 3 == 0:
		for s: float in [-1.0, 1.0]:
			box(Vector3(s * 14.0, -13.0, h), Vector3(s * 18.0, -4.0, h + 3.2), METAL)
		box(Vector3(-18.0, 5.0, h), Vector3(-14.0, 14.0, h + 3.2), METAL)


## Cable trays over the aisles. Mesh only: a tray the squad can walk into is a
## tray in the way of the fight.
func _tower_trays(h: float, n: int) -> void:
	if n == 0:
		return
	for i in 3:
		var o := -9.0 + i * 9.0
		if n % 2 == 0:
			box(Vector3(-15.0, o - 0.5, h + 4.2), Vector3(15.0, o + 0.5, h + 4.5), GRATING)
		else:
			box(Vector3(o - 0.5, -15.0, h + 4.2), Vector3(o + 0.5, 15.0, h + 4.5), GRATING)

func _fort_keep() -> void:
	var half := 48.0
	var top := 4.0
	var rim := 7.0
	var gate := 7.0        # half the gate opening: 14 m clear
	var pit_y := 10.0      # half the pit width: 20 m clear
	# The podium, in four slabs around the pit, so the pit is a hole in it
	# rather than a box standing in a yard.
	for slab: Array in [[-half, -half, half, -pit_y], [-half, pit_y, half, half],
			[-half, -pit_y, -24.0, pit_y], [40.0, -pit_y, half, pit_y]]:
		box(Vector3(slab[0], slab[1], -1.0), Vector3(slab[2], slab[3], top), PAD)
	# The rim: one brush per side, ground to parapet, with the gate left out of
	# the west face.
	for side: Array in [[-half, -half, half, -half + 2.0], [-half, half - 2.0, half, half],
			[half - 2.0, -half, half, half]]:
		box(Vector3(side[0], side[1], -1.0), Vector3(side[2], side[3], rim), TECH_WALL)
	for s: float in [-1.0, 1.0]:
		var y0: float = gate if s > 0.0 else -half
		var y1: float = half if s > 0.0 else -gate
		box(Vector3(-half, y0, -1.0), Vector3(-half + 2.0, y1, rim), TECH_WALL)
	# The gate: piers either side and a head over it, 6 m clear beneath.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, s * gate, -1.0), Vector3(-half + 2.0, s * (gate + 1.5), rim + 1.5), TECH_WALL)
	box(Vector3(-half, -gate, top + 6.0), Vector3(-half + 2.0, gate, rim + 1.5), TECH_WALL)
	box(Vector3(-half - 0.5, -gate - 1.5, rim + 1.5), Vector3(-half + 2.5, gate + 1.5, rim + 2.5), CLAD)
	box(Vector3(-half - 0.5, -gate - 1.5, rim + 2.5), Vector3(-half - 0.15, gate + 1.5, rim + 2.9), SEAM)
	# Bastions at the corners, standing above the parapet to be seen from the
	# water, each one solid — nothing to get lost inside.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var cx: float = sx * (half - 5.0)
			var cy: float = sy * (half - 5.0)
			box(Vector3(cx - 7.0, cy - 7.0, -1.0), Vector3(cx + 7.0, cy + 7.0, rim + 3.0), TECH_WALL)
			box(Vector3(cx - 7.0, cy - 7.0, rim + 2.4), Vector3(cx + 7.0, cy + 7.0, rim + 2.8), SEAM)
	# The way up from the causeway: outside the west gate, 16 m wide at 1 in 6.
	ramp(-half - 24.0, -8.0, -half, 8.0, -1.0, 0.0, top, "+x", PAD)
	# The back ramp, off the east face, for anything that comes overland.
	ramp(half, -8.0, half + 24.0, 8.0, -1.0, top, 0.0, "+x", PAD)
	# The pit: down from the yard at 1 in 6 to a floor at ground level, 20 m
	# wide the whole way. Walls either side, one brush each, ground to yard.
	ramp(-24.0, -pit_y, 0.0, pit_y, -1.0, top, 0.0, "+x", PAD)
	box(Vector3(0.0, -pit_y, -1.0), Vector3(40.0, pit_y, 0.0), PAD)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-24.0, s * pit_y, -1.0), Vector3(40.0, s * (pit_y + 1.5), top + 1.0), TECH_WALL)
		box(Vector3(-24.0, s * (pit_y + 1.15), top + 0.4), Vector3(40.0, s * (pit_y + 1.5), top + 0.8), SEAM)
	# The head house at the end of the pit, and the portal into it: 20 m wide,
	# 6 m high, which is room enough for anything that has to get down there.
	box(Vector3(40.0, -pit_y - 1.5, 6.0), Vector3(half, pit_y + 1.5, 16.0), CLAD)
	for s: float in [-1.0, 1.0]:
		box(Vector3(40.0, s * pit_y, -1.0), Vector3(half, s * (pit_y + 1.5), 16.0), TECH_WALL)
	box(Vector3(46.0, -pit_y, 0.0), Vector3(half, pit_y, 6.0), TECH_WALL)
	box(Vector3(45.6, -pit_y, 0.0), Vector3(46.0, pit_y, 6.0), SEAM)
	# The mast over the head house: what you see from the mainland.
	cylinder(Vector3(half - 4.0, 0.0, 16.0), 3.0, 14.0, 8, CLAD, 2.0)
	cylinder(Vector3(half - 4.0, 0.0, 30.0), 2.2, 1.0, 8, SEAM)
	beam(Vector3(half - 4.0, 0.0, 31.0), Vector3(half - 4.0, 0.0, 38.0), 0.4, CLAD)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		beam(Vector3(half - 4.0 + cos(a) * 2.6, sin(a) * 2.6, 16.5),
				Vector3(half - 4.0 + cos(a) * 1.9, sin(a) * 1.9, 29.0), 0.22, SEAM)
	# Lit seams up the gate piers and along the rim, so it reads as new work.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half - 0.25, s * gate, 0.0), Vector3(-half + 2.25, s * (gate + 0.4), rim + 1.5), SEAM)
	for side: Array in [[-half, -half + 2.0], [half - 2.0, half]]:
		box(Vector3(side[0] if side[0] < 0.0 else side[1] - 0.35, -half, rim - 0.9), Vector3(side[0] + 0.35 if side[0] < 0.0 else side[1], half, rim - 0.5), SEAM)


## A wall for outworks, 24 m of it, 4.5 m high and machine-built. Butts end to
## end, and its base is buried 1 m so it sits on uneven ground without a gap.
func _fort_wall() -> void:
	box(Vector3(-12.0, -1.0, -1.0), Vector3(12.0, 1.0, 4.5), TECH_WALL)
	# THE SEAM SITS PROUD OF THE FACE, not inside it. At y −1.0 … −0.65 it was
	# 0.35 m deep in the wall's own brush with its front face exactly coplanar
	# with the wall's — two solids in the same place, and the renderer picking
	# between them per pixel, which is the flicker you see on a moving camera.
	box(Vector3(-12.0, -1.06, 4.1), Vector3(12.0, -1.0, 4.5), SEAM)
	# Each buttress in TWO halves, one either side. As a single brush straddling
	# the wall, its middle 2 m was buried inside it for nothing.
	for k in 3:
		var x := -8.0 + k * 8.0
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.3, minf(s * 1.0, s * 1.6), -1.0),
					Vector3(x + 0.3, maxf(s * 1.0, s * 1.6), 4.0), CLAD)


## A gate for outworks: the same wall with a 12 m opening in it, headed at 6 m.
## Wide enough and tall enough that nothing has to think about it.
func _fort_gate() -> void:
	for s: float in [-1.0, 1.0]:
		# The wall run starts where the pier ENDS, at 7.5. It used to start at
		# 6.0 and drive 1.5 m into it.
		box(Vector3(s * 7.5, -1.0, -1.0), Vector3(s * 12.0, 1.0, 4.5), TECH_WALL)
		box(Vector3(s * 7.5, -1.06, 4.1), Vector3(s * 12.0, -1.0, 4.5), SEAM)
		box(Vector3(s * 6.0, -1.8, -1.0), Vector3(s * 7.5, 1.8, 7.5), TECH_WALL)
	# The lintel spans the OPENING and butts the piers either side. At ±7.5 it
	# had both its ends buried in them.
	box(Vector3(-6.0, -1.8, 6.0), Vector3(6.0, 1.8, 7.5), CLAD)
	box(Vector3(-6.0, -1.86, 7.1), Vector3(6.0, -1.8, 7.5), SEAM)
