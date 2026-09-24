extends "res://tools/block_fortress.gd"

# ─────────────────────────────────────────────
# BLOCK GROUND — micro-terrain: relief you build rather than paint.
#
#   maps/blocks/ground/
#
#   godot --headless --path . --script res://tools/block_ground.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_ground.gd -- maps/blocks --force
#
# WHY THESE EXIST. Flattish ground is what the squad can fight on and painted
# hills are what it cannot, so every level ends up with a floor that is
# correct and dead. The heliostat field is the worst of them: a thousand
# identical mirrors standing on a billiard table.
#
# These are the middle ground. Every piece is low, every slope is gentle, and
# every one of them is something you WALK OVER rather than round — so the
# ground gets a shape without the navmesh losing one.
#
# THE RULES EVERY PIECE HERE KEEPS.
#
#   * Slopes are 20 degrees or less. The baker walks up to 45, but a body
#     that has to steer while climbing wants far less than its limit, and a
#     rover is not a goat.
#   * No step over 0.2 m anywhere. The navmesh climbs 0.25 m and anything
#     near that is a lip the squad catches on.
#   * Nothing over 1.2 m tall. Past that it is cover, and cover belongs in
#     the props kit where it will be built with vertical sides.
#   * Every edge meets the ground flush. A slab dropped on a field with a
#     square edge is a 0.2 m kerb all the way round it.
#
# tools/test_prop_nav.gd checks the first two. A piece here should come out
# with a WALK of about 16.1 m against 16.0 m straight — the squad goes over
# it, not round — and area on top rather than an island.
# ─────────────────────────────────────────────

const DUST := "PSX_Textures/dirt_2"
const GRIT := "PSX_Textures/concrete_3@0.5"
const HEAPED := "PSX_Textures/dirt_6"
const SLABS := {"top": "PSX_Textures/concrete_tx_4", "side": CONCRETE, "bottom": CONCRETE}
const DUSTED := {"top": DUST, "side": DUST, "bottom": DUST}
const GRITTED := {"top": GRIT, "side": CONCRETE, "bottom": CONCRETE}


func _initialize() -> void:
	var base := ""
	var force := false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		elif only == "":
			only = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_ground.gd -- maps/blocks [name] [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var pieces := {
		"ground_swell": _swell,
		"ground_berm": _berm,
		"ground_berm_ring": _berm_ring,
		"ground_apron": _apron,
		"ground_spoil": _spoil,
		"ground_pad": _pad,
		"ground_washout": _washout,
		"ground_track": _track,
	}
	var dir := base.path_join("ground")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	for name: String in pieces:
		if only != "" and not name.contains(only):
			continue
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — pass --force to overwrite it." % path)
			continue
		# Every piece starts clean. A tool that forgets this builds the second
		# piece with the first one's no-collision flag still set, which is how
		# a whole folder of props silently lost its colliders once.
		_brushes = []
		_ghost_from = -1
		_entities = []
		pieces[name].call()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-24s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK GROUND DONE: %d written" % written)
	quit()


## The plain one, and the one to use most: 30 x 22 m of ground that rises
## 0.72 m in the middle, at 3 degrees. From inside it you cannot see the far
## side of a field, which is the whole point of it.
func _swell() -> void:
	slope_slab(-15.0, -11.0, 15.0, 11.0, 0.72, 11.0, DUSTED)
	slope_slab(-9.0, -6.5, 9.0, 6.5, 0.9, 6.5, DUSTED)


## A graded bank 32 m long: 0.72 m up at 12 degrees, a 3 m crest, and back
## down. Walk over it, or fight from behind it — from the low side it hides a
## standing rover's wheels and nothing else, which is exactly the cover a
## field like this wants.
func _berm() -> void:
	slope_slab(-16.0, -5.0, 16.0, 5.0, 0.72, 3.4, {"top": GRIT, "side": DUST, "bottom": DUST})


## A ring of spoil 26 m across with a dished middle: what is left of a tank
## base, or of a scrape nobody filled in. The middle sits at ground level, so
## it is a place to stand that is out of sight from outside.
func _berm_ring() -> void:
	var n := 14
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for ring: Array in [[13.0, 11.6, 0.0, 0.28], [11.6, 10.2, 0.28, 0.56], [10.2, 8.8, 0.56, 0.7],
				[8.8, 7.4, 0.7, 0.56], [7.4, 6.0, 0.56, 0.24], [6.0, 4.6, 0.24, 0.0]]:
			var pts: Array = []
			for a: float in [a0, a1]:
				for r: float in [ring[0], ring[1]]:
					pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
			for a: float in [a0, a1]:
				pts.append(Vector3(cos(a) * float(ring[0]), sin(a) * float(ring[0]), ring[2]))
				pts.append(Vector3(cos(a) * float(ring[1]), sin(a) * float(ring[1]), ring[3]))
			solid(pts, DUSTED, 2)


## A graded apron: 16 m of gentle climb onto a 10 x 11 m pad 0.72 m up.
## Somewhere to stand a machine, or to put a building on ground that is not
## quite level. One solid, so the pad's edge is a slope on all four sides and
## there is no kerb anywhere to catch a wheel.
func _apron() -> void:
	solid([Vector3(-11.0, -6.0, 0.0), Vector3(6.2, -6.0, 0.0), Vector3(6.2, 6.0, 0.0), Vector3(-11.0, 6.0, 0.0),
			Vector3(-5.0, -5.0, 0.72), Vector3(5.0, -5.0, 0.72),
			Vector3(5.0, 5.0, 0.72), Vector3(-5.0, 5.0, 0.72)], GRITTED)


## A heap of dug material, 1.1 m. Unlike everything else here this is NOT
## something you walk over: it is loose spoil, it stands too steep, and its
## collision is a clip_block with vertical sides so the navmesh carves round
## it cleanly instead of climbing a slope nothing can hold.
func _spoil() -> void:
	clip_block(Vector3(0.0, 0.0, 0.0), Vector2(2.6, 2.0), 0.95)
	no_collision()
	mound(Vector3.ZERO, 3.0, 2.3, 1.1, 211, HEAPED)
	for c: Array in [[-2.4, 1.4, 0.2], [2.7, -1.0, 0.15], [1.2, 2.5, 0.18]]:
		mound(Vector3(float(c[0]), float(c[1]), 0.0), 1.2, 0.9, float(c[2]), 212, HEAPED)


## A concrete pad that has settled. Four slabs, all at the SAME height with a
## finger's width of crack between them — a settled pad wants its slabs at
## four different heights and four different heights is three steps, so the
## settling is in the cracks and the grit rather than in the levels.
func _pad() -> void:
	slope_slab(-6.2, -6.2, 6.2, 6.2, 0.1, 0.8, GRITTED)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var x0: float = minf(0.09, sx * 4.9)
			var x1: float = maxf(0.09, sx * 4.9)
			var y0: float = minf(0.09, sy * 4.9)
			var y1: float = maxf(0.09, sy * 4.9)
			solid([Vector3(x0, y0, 0.0), Vector3(x1, y0, 0.0), Vector3(x1, y1, 0.0), Vector3(x0, y1, 0.0),
					Vector3(x0 + sx * 0.0 + (0.5 if sx < 0.0 else 0.0), y0 + (0.5 if sy < 0.0 else 0.0), 0.2),
					Vector3(x1 - (0.5 if sx > 0.0 else 0.0), y0 + (0.5 if sy < 0.0 else 0.0), 0.2),
					Vector3(x1 - (0.5 if sx > 0.0 else 0.0), y1 - (0.5 if sy > 0.0 else 0.0), 0.2),
					Vector3(x0 + (0.5 if sx < 0.0 else 0.0), y1 - (0.5 if sy > 0.0 else 0.0), 0.2)], SLABS)


## Where the runoff went: a bare channel 4 m wide between two low banks, 26 m
## of it. Read from the side it is a line across the ground; walked along, it
## is a shallow lane that hides your feet. Each bank is one sloped solid, so
## you cross it by walking over rather than by climbing a staircase.
func _washout() -> void:
	for s: float in [-1.0, 1.0]:
		solid([Vector3(-13.0, s * 2.0, 0.0), Vector3(13.0, s * 2.0, 0.0),
				Vector3(13.0, s * 7.0, 0.0), Vector3(-13.0, s * 7.0, 0.0),
				Vector3(-11.5, s * 3.4, 0.56), Vector3(11.5, s * 3.4, 0.56),
				Vector3(11.5, s * 5.6, 0.56), Vector3(-11.5, s * 5.6, 0.56)], DUSTED)
	# Stones washed out of the banks, left in the bed.
	for c: Array in [[-8.5, 0.6], [-3.0, -0.8], [2.4, 0.9], [7.8, -0.5], [11.0, 0.3]]:
		# Sunk almost flush: a stone standing 0.18 m proud is a step, and the
		# bed is somewhere the squad walks along.
		rock(Vector3(float(c[0]), float(c[1]), -0.24), Vector3(0.5, 0.4, 0.3), 220 + int(c[0]), ROCK, 8)


## A worn vehicle track: a crown of dust between two grit shoulders, 30 m of
## it and 0.14 m of relief. The smallest piece here, and the one that does the
## most, because a field with a track across it has been USED.
func _track() -> void:
	slope_slab(-15.0, -3.5, 15.0, 3.5, 0.08, 1.1, GRITTED)
	slope_slab(-15.0, -2.2, 15.0, 2.2, 0.14, 1.4, DUSTED)
	# There were ridges of thrown-out dust along the shoulder. They are gone:
	# wherever one crossed the crown's own slope the two made a face, and the
	# step test kept finding it. A track reads from the change of surface, and
	# nothing on a piece this low is worth a riser a body catches on.
