extends "res://tools/block_canal_works.gd"

# ─────────────────────────────────────────────
# BLOCK CANAL PARK — the dilapidated waterfront park on the Georgetown bank,
# and the landmarks the map is read against.
#
#   maps/blocks/canal/park_*.map, maps/blocks/canal/mark_*.map
#
#   godot --headless --path . --script res://tools/block_canal_park.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_canal_park.gd -- maps/blocks --force [names]
#
# WHY A PARK, AND WHY A RUINED ONE. The waterfront bench was an esplanade and
# nothing else: 450 m of paving with a rail along one side and a 3 m drop to
# the water, which is the most exposed ground on the map and had nothing on it
# to make that interesting. A park is the opposite kind of space — paths that
# go round rather than through, hedges and beds that block sight without
# stopping fire, a tennis court that is a fenced room outdoors, a pavilion
# that is a roof in the open. Derelict, because the rest of the map is.
#
# EVERY PIECE IN HERE OBEYS THE THREE RULES THE REACHABILITY PROBE TAUGHT:
#
#   1. nothing between 0.25 and 0.45 m, which is the band the baker will not
#      climb but a body would, and the band that makes a surface look walkable
#      and bake as a wall;
#   2. any surface meant to be stood on is AT LEAST 2 M WIDE, because the
#      baker erodes the walkable area by the agent radius from every side and
#      a 1.5 m path comes back as a 0.5 m thread or as nothing;
#   3. anything raised has a RAMP, not steps. A 0.34 m tread holds nobody —
#      that one cost three debugging passes on this map alone.
# ─────────────────────────────────────────────

const TARMAC := "PSX_Textures/concrete_3"
const CLAY := "PSX_Textures/dirt_hell_1"
const PARK_WALL := "PSX_Textures/concrete_7"
const PAINT_LINE := "PSX_Textures/concrete_1@0.25"

const PARK := {
	"park_path_run": "_path_run",
	"park_pavilion": "_pavilion",
	"park_bench_row": "_bench_row",
	"park_playground": "_playground",
	"park_overgrown_bed": "_overgrown_bed",
	"park_fountain_dry": "_fountain_dry",
	"park_tennis_court": "_tennis_court",
	"park_pergola_ruin": "_pergola_ruin",
	"mark_stack": "_stack",
	"mark_aqueduct_piers": "_aqueduct_piers",
	"mark_statue": "_statue",
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
		print("usage: godot --headless --path . --script res://tools/block_canal_park.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("canal")
	if not DirAccess.dir_exists_absolute(dir):
		print("FAIL  no folder at %s — run block_canal.gd first" % dir)
		quit(1)
		return
	var written := 0
	var skipped := 0
	for name: String in PARK:
		if not only.is_empty() and not only.has(name):
			continue
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		_ghost_from = -1
		_entities = []
		call(PARK[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-26s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK CANAL PARK DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── The park ─────────────────────────────────────────────────────────────────

## 32 M OF PARK PATH, 3 m wide, cracked tarmac with grass breaking through and
## a kerb either side. 3 m so it survives the agent radius with 2 m to spare —
## a 1.5 m path, which is what a real one is, bakes to a thread.
func _path_run() -> void:
	box(Vector3(-16.0, -1.5, -0.4), Vector3(16.0, 1.5, 0.0), {"top": TARMAC, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-16.0, s * 1.5, -0.4), Vector3(16.0, s * 1.65, 0.1), {"top": COPING, "side": COPING, "bottom": CONCRETE})
	# The grass either side, flush, so the path is a surface and not a kerb to
	# climb on and off.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-16.0, s * 1.65, -0.4), Vector3(16.0, s * 5.0, 0.0), {"top": WEED, "side": SPOIL, "bottom": SPOIL})
	no_collision()
	var x := -15.0
	while x < 15.0:
		heap(Vector3(x, (_hash_f(int(x) * 7) - 0.5) * 2.4, 0.0), 0.5, 0.35, 0.18, int(x) + 3, SPOIL)
		x += 2.2


## A BANDSTAND: an octagonal roof on eight posts over a raised floor, with the
## roof half gone. The floor is 0.2 m up and RAMPED on two sides — stepped it
## would bake as an island, which is the whole lesson of this map.
func _pavilion() -> void:
	var r := 5.0
	cylinder(Vector3(0.0, 0.0, -0.4), r, 0.6, 8, {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		ramp(s * r, -1.6, s * (r + 2.4), 1.6, -0.4, 0.2, 0.0, "+x" if s > 0.0 else "-x",
				{"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		post(cos(a) * (r - 0.5), sin(a) * (r - 0.5), 0.2, 3.1, 0.22, WOOD_DARK)
	# The roof, with two of its eight segments fallen in.
	for i in 8:
		if i == 2 or i == 3:
			continue
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		solid([Vector3(cos(a0) * (r + 0.7), sin(a0) * (r + 0.7), 3.1),
				Vector3(cos(a1) * (r + 0.7), sin(a1) * (r + 0.7), 3.1),
				Vector3(cos(a1) * 0.6, sin(a1) * 0.6, 4.6), Vector3(cos(a0) * 0.6, sin(a0) * 0.6, 4.6),
				Vector3(cos(a0) * (r + 0.7), sin(a0) * (r + 0.7), 3.35),
				Vector3(cos(a1) * (r + 0.7), sin(a1) * (r + 0.7), 3.35),
				Vector3(cos(a1) * 0.6, sin(a1) * 0.6, 4.85), Vector3(cos(a0) * 0.6, sin(a0) * 0.6, 4.85)], SHINGLE)
	# The fallen pieces on the floor beside it.
	tipped_box(Vector3(r + 1.4, 2.6, 0.3), Vector3(3.2, 2.6, 0.2), Vector3(12.0, 0.0, 28.0), SHINGLE)
	tipped_box(Vector3(r + 2.6, -1.0, 0.25), Vector3(2.4, 1.8, 0.2), Vector3(-8.0, 6.0, 64.0), SHINGLE)


## A row of park benches, some on their backs. Mesh only: a bench is 0.45 m to
## the seat, right on the line a body steps over, and a line of them with
## collision is a line of maybes.
func _bench_row() -> void:
	no_collision()
	for i in 5:
		var x := -9.0 + i * 4.5
		if i == 3:
			tipped_box(Vector3(x, 0.4, 0.3), Vector3(1.9, 0.7, 0.55), Vector3(86.0, 0.0, 14.0), WOOD_DARK)
			continue
		box(Vector3(x - 0.95, -0.28, 0.0), Vector3(x + 0.95, 0.28, 0.45), {"top": WOOD, "side": WOOD_DARK, "bottom": IRON})
		box(Vector3(x - 0.95, 0.18, 0.45), Vector3(x + 0.95, 0.32, 1.0), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
		for s: float in [-1.0, 1.0]:
			box(Vector3(x + s * 0.88, -0.3, -0.1), Vector3(x + s * 0.95, 0.34, 0.45), IRON)


## A RUSTED PLAY STRUCTURE on a sunken safety surface: a deck 1.2 m up on four
## legs, a slide off one side, a ramp up the other. Head height, which makes it
## the only thing in the park you can shoot from.
func _playground() -> void:
	box(Vector3(-7.0, -5.0, -0.45), Vector3(7.0, 5.0, -0.05), {"top": RUBBER, "side": COPING, "bottom": CONCRETE})
	box(Vector3(-2.0, -1.6, -0.05), Vector3(2.0, 1.6, 1.2), {"top": GRATING, "side": IRON, "bottom": IRON})
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			post(sx * 1.8, sy * 1.4, -0.05, 2.6, 0.14, IRON)
	box(Vector3(-2.2, -1.8, 2.6), Vector3(2.2, 1.8, 2.8), {"top": RUST_PANEL, "side": IRON, "bottom": IRON})
	# The ramp up, 2.2 m wide so it survives the erosion, and the slide down.
	ramp(2.0, -1.1, 5.6, 1.1, -0.45, 0.0, 1.2, "-x", {"top": GRATING, "side": IRON, "bottom": IRON})
	solid([Vector3(-2.0, -1.5, 1.2), Vector3(-2.0, -0.3, 1.2), Vector3(-5.4, -0.3, -0.05), Vector3(-5.4, -1.5, -0.05),
			Vector3(-2.0, -1.5, 1.35), Vector3(-2.0, -0.3, 1.35), Vector3(-5.4, -0.3, 0.1), Vector3(-5.4, -1.5, 0.1)],
			{"top": RUST_PANEL, "side": IRON, "bottom": IRON})
	no_collision()
	for s: float in [-1.0, 1.0]:
		for i in 5:
			box(Vector3(-2.1 + i * 0.95, s * 1.6, 1.2), Vector3(-1.95 + i * 0.95, s * 1.75, 2.0), IRON)


## AN OVERGROWN BED: a low stone wall round soil gone to scrub. The wall is
## 0.95 m — under cover height on purpose, so it breaks a sightline for a
## crouching body and not for a standing one.
func _overgrown_bed() -> void:
	var w := 7.0
	var d := 3.0
	for e: Array in [[-w, -d, w, -d + 0.4], [-w, d - 0.4, w, d], [-w, -d, -w + 0.4, d], [w - 0.4, -d, w, d]]:
		box(Vector3(e[0], e[1], -0.4), Vector3(e[2], e[3], 0.95), {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	box(Vector3(-w + 0.4, -d + 0.4, -0.4), Vector3(w - 0.4, d - 0.4, 0.8), {"top": DIRT, "side": SPOIL, "bottom": SPOIL})
	no_collision()
	for i in 9:
		var x := lerpf(-w + 1.2, w - 1.2, float(i) / 8.0)
		heap(Vector3(x, (_hash_f(i * 13) - 0.5) * 3.4, 0.8), 1.1, 0.9, 1.3, i * 7 + 2, SPOIL)


## A DRY FOUNTAIN: a round basin 0.8 m down with a ramped break in its wall,
## and the pedestal still in the middle. A bowl you can get into and be caught
## in — and the ramp is what stops it being a hole with navmesh in it and no
## way out, which is what the retention basin taught.
func _fountain_dry() -> void:
	var r := 6.0
	cylinder(Vector3(0.0, 0.0, -1.4), r + 0.8, 1.4, 12, {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	# The basin floor, and a ramp out of it on one side.
	cylinder(Vector3(0.0, 0.0, -0.9), r, 0.1, 12, {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	ramp(-1.6, -r - 0.8, 1.6, r * 0.2, -1.4, 0.0, -0.8, "-y", {"top": CONCRETE, "side": PARK_WALL, "bottom": CONCRETE})
	cylinder(Vector3(0.0, 0.0, -0.8), 1.3, 0.9, 8, {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	cylinder(Vector3(0.0, 0.0, 0.1), 0.55, 1.5, 8, PARK_WALL, 0.4)
	no_collision()
	for i in 11:
		var a := TAU * i / 11.0
		heap(Vector3(cos(a) * r * 0.7, sin(a) * r * 0.7, -0.8), 0.7, 0.5, 0.3, i * 11 + 4, SPOIL)


## A TENNIS COURT gone to weeds inside a sagging chain-link cage. The best
## piece of ground in the park: a 36 x 18 room outdoors with exactly two ways
## in, no cover inside it at all, and a fence you can see through and shoot
## through but not walk through.
func _tennis_court() -> void:
	var w := 18.0
	var d := 9.0
	box(Vector3(-w, -d, -0.4), Vector3(w, d, 0.0), {"top": CLAY, "side": CONCRETE, "bottom": CONCRETE})
	# The lines, what is left of them.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-w + 2.0, s * (d - 2.0) - 0.06, 0.0), Vector3(w - 2.0, s * (d - 2.0) + 0.06, 0.0625), PAINT_LINE)
		box(Vector3(s * (w - 2.0) - 0.06, -d + 2.0, 0.0), Vector3(s * (w - 2.0) + 0.06, d - 2.0, 0.0625), PAINT_LINE)
	box(Vector3(-0.06, -d + 2.0, 0.0), Vector3(0.06, d - 2.0, 0.0625), PAINT_LINE)
	# The net posts, and the net down.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-0.12, s * (d - 1.2) - 0.12, 0.0), Vector3(0.12, s * (d - 1.2) + 0.12, 1.1), IRON)
	# The cage. Two gaps, at diagonally opposite corners, so crossing it is a
	# commitment rather than a shortcut.
	# Explicit runs, not wall_run: its axis argument names the axis the run is
	# measured ON, and read the other way round it built a 36 x 36 cage round
	# an 36 x 18 court.
	for s: float in [-1.0, 1.0]:
		var gap0: float = -w if s > 0.0 else w - 5.0
		var gap1: float = -w + 5.0 if s > 0.0 else w
		for run: Array in [[-w, gap0], [gap1, w]]:
			if run[1] - run[0] < 0.5:
				continue
			box(Vector3(run[0], s * d - s * 0.08, -0.4), Vector3(run[1], s * d + s * 0.08, 3.4), HERAS)
		box(Vector3(s * w - s * 0.08, -d, -0.4), Vector3(s * w + s * 0.08, d, 3.4), HERAS)
	no_collision()
	for i in 24:
		var x := -w + 1.0 + i * 1.5
		heap(Vector3(x, (_hash_f(i * 17) - 0.5) * 15.0, 0.0), 0.6, 0.45, 0.3, i * 5 + 7, SPOIL)


## A PERGOLA half fallen: four bays of columns with the beams off two of them,
## and what is left overgrown. A colonnade is a sightline you can see down and
## not shoot down, which is a thing this map has none of.
func _pergola_ruin() -> void:
	var half := 11.0
	box(Vector3(-half - 1.0, -2.2, -0.4), Vector3(half + 1.0, 2.2, 0.0), {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	for i in 5:
		var x := lerpf(-half, half, float(i) / 4.0)
		for s: float in [-1.0, 1.0]:
			if i == 3 and s > 0.0:
				continue                      # this one is down
			cylinder(Vector3(x, s * 1.6, 0.0), 0.3, 2.9, 8, PARK_WALL, 0.26)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half - 0.4, s * 1.6 - 0.2, 2.9), Vector3(half * 0.2, s * 1.6 + 0.2, 3.2), WOOD_DARK)
	for i in 4:
		var x := lerpf(-half, -1.0, float(i) / 3.0)
		box(Vector3(x - 0.12, -2.1, 3.2), Vector3(x + 0.12, 2.1, 3.38), WOOD_DARK)
	# The fallen column and beam.
	log_x(Vector3(half * 0.55, 1.4, 0.3), 0.3, 2.8, 8, PARK_WALL, "x")
	tipped_box(Vector3(half * 0.8, -0.4, 0.28), Vector3(4.4, 0.4, 0.36), Vector3(0.0, 4.0, 22.0), WOOD_DARK)
	no_collision()
	for i in 6:
		var x := lerpf(-half, half, float(i) / 5.0)
		heap(Vector3(x, 1.9, 0.0), 0.9, 0.6, 1.4, i * 9 + 3, SPOIL)


# ── Landmarks ────────────────────────────────────────────────────────────────

## THE INCINERATOR STACK, 44 m of tapering brick on a square base. The thing
## you steer by from anywhere on the map — it clears the mills by 28 m and the
## office block by 16, which is the whole job of a landmark on a site that is
## otherwise all one height.
func _stack() -> void:
	box(Vector3(-5.0, -5.0, -3.0), Vector3(5.0, 5.0, 3.0), {"top": COPING, "side": MILL_BRICK, "bottom": CONCRETE})
	box(Vector3(-4.2, -4.2, 3.0), Vector3(4.2, 4.2, 6.5), MILL_BRICK)
	# The shaft, in six tapering drums rather than one cone: at this distance
	# the steps read as the brick courses they would be.
	for i in 6:
		var z: float = 6.5 + i * 6.0
		var r0: float = 3.3 - i * 0.33
		var r1: float = 3.3 - (i + 1) * 0.33
		cylinder(Vector3(0.0, 0.0, z), r0, 6.0, 8, MILL_BRICK, r1)
	cylinder(Vector3(0.0, 0.0, 42.5), 1.5, 1.5, 8, MILL_BRICK, 1.75)
	no_collision()
	# The bands and the ladder, which is what tells you how big it is.
	for i in 4:
		var z: float = 12.0 + i * 8.0
		cylinder(Vector3(0.0, 0.0, z), 3.1 - i * 0.44, 0.5, 8, COPING, 3.05 - i * 0.44)
	for i in 34:
		box(Vector3(-0.22, 3.4 - i * 0.055, 7.0 + i * 1.05), Vector3(0.22, 3.5 - i * 0.055, 7.1 + i * 1.05), IRON)


## THE AQUEDUCT PIERS: five stone piers standing in the river where a bridge
## used to be, with the stub of its abutment on the bank. Mesh only and out in
## the water — they are a horizon, not ground, and the whole point of them is
## that the crossing they mark is gone.
func _aqueduct_piers() -> void:
	box(Vector3(-9.0, -3.0, -6.0), Vector3(9.0, 8.0, 3.5), {"top": DIRT, "side": RUBBLE_WALL, "bottom": CONCRETE})
	box(Vector3(-7.0, 2.0, 3.5), Vector3(7.0, 8.0, 7.5), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	no_collision()
	for i in 5:
		var y := -22.0 - i * 26.0
		var h: float = 7.0 - i * 0.4
		var sway := (_hash_f(i * 23) - 0.5) * 2.6
		solid([Vector3(-5.0, y - 4.0, -6.0), Vector3(5.0, y - 4.0, -6.0), Vector3(5.0, y + 4.0, -6.0), Vector3(-5.0, y + 4.0, -6.0),
				Vector3(-3.4 + sway, y - 2.6, h), Vector3(3.4 + sway, y - 2.6, h),
				Vector3(3.4 + sway, y + 2.6, h), Vector3(-3.4 + sway, y + 2.6, h)], RUBBLE_WALL)
		# The cutwater on the upstream face.
		solid([Vector3(-5.0, y - 4.0, -6.0), Vector3(5.0, y - 4.0, -6.0), Vector3(0.0, y - 7.5, -6.0),
				Vector3(-3.4 + sway, y - 2.6, h), Vector3(3.4 + sway, y - 2.6, h), Vector3(sway, y - 5.0, h)], RUBBLE_WALL)


## A STATUE ON ITS PLINTH at a path junction: a 4 m plinth with the figure
## gone and only the boots left on it, which is how most of them end up. Reads
## at a hundred metres and tells you where you are in the park.
func _statue() -> void:
	box(Vector3(-3.2, -3.2, -0.5), Vector3(3.2, 3.2, 0.25), {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	box(Vector3(-2.2, -2.2, 0.25), Vector3(2.2, 2.2, 0.75), {"top": COPING, "side": PARK_WALL, "bottom": CONCRETE})
	box(Vector3(-1.5, -1.5, 0.75), Vector3(1.5, 1.5, 3.6), {"top": COPING, "side": PARK_WALL, "bottom": PARK_WALL})
	box(Vector3(-1.7, -1.7, 3.6), Vector3(1.7, 1.7, 4.0), {"top": COPING, "side": COPING, "bottom": COPING})
	no_collision()
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 0.34 - 0.2, -0.45, 4.0), Vector3(s * 0.34 + 0.2, 0.35, 4.55), IRON)
	box(Vector3(-1.1, -1.72, 1.4), Vector3(1.1, -1.66, 2.1), IRON)
