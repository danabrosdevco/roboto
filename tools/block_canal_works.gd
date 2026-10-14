extends "res://tools/block_canal.gd"

# ─────────────────────────────────────────────
# BLOCK CANAL WORKS — the second pass on Georgetown: the gear on the lock, the
# state of the bed, the works going on in it, and the buildings the first pass
# had to borrow from other families.
#
#   maps/blocks/canal/works_*.map, maps/blocks/canal/mill_*.map
#
#   godot --headless --path . --script res://tools/block_canal_works.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_canal_works.gd -- maps/blocks --force [names]
#
# TWO THINGS THE FIRST PASS GOT THIN.
#
# The upper town was built out of suburban townhouses, which are the wrong
# country — Georgetown above the canal is federal rowhouses, flat fronted,
# three bays, straight onto the pavement with a stoop. That is one piece here
# and it changes the whole top bench.
#
# And the prism was clean. A drained canal is not clean: it is silt, fallen
# coping, a shopping trolley, barriers round the holes and a compound at the
# end where the work is actually happening. All of that is cover in a trench
# that otherwise has none, which makes it the difference between a corridor
# and somewhere to fight.
# ─────────────────────────────────────────────

const HERAS := "PSX_Textures/metal_floor_3@0.25"
const TARP := "PSX_Textures/fabric_tx_1"

const WORKS := {
	"works_lock_gear": "_lock_gear",
	"works_bed_debris": "_bed_debris",
	"works_scaffold": "_scaffold",
	"works_site_compound": "_site_compound",
	"works_barrier_run": "_barrier_run",
	"works_market_stalls": "_market_stalls",
	"works_plank_bridge": "_plank_bridge",
	"works_arch_viaduct": "_arch_viaduct",
	"mill_rowhouse_run": "_rowhouse_run",
	"mill_brick_short": "_mill_brick_short",
	"wharf_boathouse": "_boathouse",
	"wharf_barge": "_barge",
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
		print("usage: godot --headless --path . --script res://tools/block_canal_works.gd -- maps/blocks [--force] [names]")
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
	for name: String in WORKS:
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
		call(WORKS[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-26s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK CANAL WORKS DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── On and in the canal ──────────────────────────────────────────────────────

## THE GEAR ON A LOCK: the balance beams over the coping, the paddle winches,
## mooring bollards and the ladder down the chamber wall. Drops onto
## canal_lock and gives the one wide spot in the prism something in it.
func _lock_gear() -> void:
	var ch := 2.5
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			# The balance beam, swung back along the coping.
			# The beam ends AT the post (11.7), not 0.2 m inside it.
			box(Vector3(s * 11.7, e * (ch + 0.1), 0.35), Vector3(s * 7.4, e * (ch + 0.45), 0.72), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
			box(Vector3(s * 12.1, e * (ch + 0.05), 0.35), Vector3(s * 11.7, e * (ch + 0.5), 1.05), WOOD_DARK)
			# The paddle winch on its stand.
			box(Vector3(s * 11.2 - 0.26, e * (ch + 0.9) - 0.26, 0.35), Vector3(s * 11.2 + 0.26, e * (ch + 0.9) + 0.26, 1.15), IRON)
			cylinder(Vector3(s * 11.2, e * (ch + 0.9), 1.15), 0.34, 0.2, 8, IRON)
			box(Vector3(s * 11.2 - 0.07, e * (ch + 0.9) - 0.07, 1.35), Vector3(s * 11.2 + 0.07, e * (ch + 0.9) + 0.07, 1.55), IRON)
	for s: float in [-1.0, 1.0]:
		for i in 3:
			var x := lerpf(-8.0, 8.0, float(i) / 2.0)
			cylinder(Vector3(x, s * (ch + 1.2), 0.35), 0.19, 0.62, 8, IRON)
			cylinder(Vector3(x, s * (ch + 1.2), 0.97), 0.25, 0.12, 8, IRON)
	# The ladder down the chamber wall. Mesh only: rungs with collision are a
	# column of 0.05 m ledges the baker will try to stand on.
	no_collision()
	for s: float in [-1.0, 1.0]:
		box(Vector3(-0.3, s * ch - s * 0.1, -3.4), Vector3(-0.2, s * ch, 0.3), IRON)
		box(Vector3(0.5, s * ch - s * 0.1, -3.4), Vector3(0.6, s * ch, 0.3), IRON)
		for i in 9:
			var z := -3.2 + i * 0.4
			# Between the uprights, not through them.
			box(Vector3(-0.2, s * ch - s * 0.14, z), Vector3(0.5, s * ch, z + 0.07), IRON)


## WHAT IS ACTUALLY IN A DRAINED CANAL: silt banks, fallen coping stones, a
## trolley on its side, a tyre, and a run of pipe somebody left. Scattered
## across 30 m of bed and the only cover down there apart from the cofferdam.
##
## The coping blocks and the pipe COLLIDE and everything else does not. A
## 0.4 m stone is something to crouch behind; a 0.1 m scatter of rubbish with
## collision is forty things for a squad to catch on.
func _bed_debris() -> void:
	_claim_reset()
	# Placed by hand into lanes and then claimed, so nothing in the scatter
	# below can land on them. The pipes take the -Y middle of the bed from
	# x = 0.5 to 11.5, the mounds the +Y side, and the stones the -Y edge.
	# They used to be thrown from a hash and sat on each other.
	_reserve(Vector2(6.0, -1.44), 5.6, 1.15, "the pipe run")
	for i in 3:
		var x := -9.0 + i * 9.0
		_reserve(Vector2(x, 2.2), 3.7, 2.35, "a mound")
		_mound_on(Vector3(x, 2.2, 0.0), 3.4, 2.2, 0.75, i * 17 + 5, SPOIL)
	for i in 5:
		var x := -12.0 + i * 6.0 + _hash_f(i * 13) * 3.0
		var y := -3.6 + (_hash_f(i * 7) - 0.5) * 1.0
		_reserve(Vector2(x, y), 0.75, 0.35, "a coping stone")
		box(Vector3(x - 0.75, y - 0.35, 0.0), Vector3(x + 0.75, y + 0.35, 0.42), {"top": COPING_STONE, "side": COPING_STONE, "bottom": COPING_STONE})
	_pipe_run(Vector3(6.0, -2.2, 0.0), 11.0)
	no_collision()
	# The trolley, on its side in the silt.
	_reserve(Vector2(-4.2, -1.2), 0.95, 0.95, "the trolley")
	tipped_box(Vector3(-4.2, -1.2, 0.35), Vector3(1.0, 0.6, 0.9), Vector3(74.0, 0.0, 18.0), GRATING)
	# The scatter takes the first free spot of three tries and gives up after
	# that: a thinner scatter is fine, an overlapping one is not.
	for i in 14:
		for attempt in 3:
			var x := -14.0 + i * 2.1 + _hash_f(i * 31 + attempt * 97) * 1.4
			var y := (_hash_f(i * 11 + attempt * 57) - 0.5) * 7.0
			if _scatter_heap(Vector3(x, y, 0.0), 0.5 + _hash_f(i) * 0.5, 0.4, 0.3, i * 7 + 3, RUBBLE):
				break
	for i in 4:
		var x := -10.0 + i * 7.0
		var y := (_hash_f(i * 19) - 0.5) * 6.0
		if _claim(Vector2(x, y), 0.34, 0.13):
			log_x(Vector3(x, y, 0.3), 0.32, 0.22, 8, RUBBER, "y")



const COPING_STONE := "PSX_Textures/concrete_1"


## Three lengths of concrete pipe lying where they were dropped.
func _pipe_run(c: Vector3, length: float) -> void:
	for i in 3:
		log_x(c + Vector3(0.0, i * 0.76, i * 0.0), 0.37, length, 8, CONCRETE, "x")


## SCAFFOLD up a mill face, 18 m long and four lifts, with a boarded deck on
## each and a tarp over the top one. A ladder route up the side of a building
## that has no other way up, and a thing to be shot off.
func _scaffold() -> void:
	var half := 9.0
	var lifts := 4
	var top: float = 1.9 + lifts * 2.1
	# STANDARDS FIRST, because everything else is cut round them. They used to
	# run straight through every deck board, ledger and guard rail, which is
	# 199 overlaps in a piece of 90 brushes; now each horizontal member either
	# stops at a standard or runs beside it, on its outer face.
	var xs: Array = []
	for i in 7:
		xs.append(lerpf(-half + 0.4, half - 0.4, float(i) / 6.0))
	for x: float in xs:
		for y: float in [-1.25, -0.15]:
			box(Vector3(x - 0.07, y - 0.07, -0.4), Vector3(x + 0.07, y + 0.07, top), METAL)
	for lift in lifts:
		var z: float = 1.9 + lift * 2.1
		# The boards, in the bays between the standards.
		var x0 := -half
		for i in xs.size() + 1:
			var x1: float = (xs[i] as float) - 0.07 if i < xs.size() else half
			box(Vector3(x0, -1.3, z - 0.1), Vector3(x1, 0.0, z), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
			if i < xs.size():
				x0 = (xs[i] as float) + 0.07
		# The guard rail on each deck, at cover height, so a body on a lift is
		# protected rather than merely standing somewhere high. On the OUTER
		# face of the outer standards (-1.32), not across them.
		box(Vector3(-half, -1.4, z), Vector3(half, -1.32, z + COVER_H), METAL)
		# The ledgers under the deck: one on the outer face of the outer row of
		# standards and one on the inner face of the inner row, against the wall.
		# They sit at z - 0.85, the top of the lift below's guard rail, so the two
		# run into each other at one plane and not through it.
		box(Vector3(-half, -1.4, z - 0.85), Vector3(half, -1.32, z - 0.75), METAL)
		box(Vector3(-half, -0.08, z - 0.85), Vector3(half, 0.0, z - 0.75), METAL)
	no_collision()
	box(Vector3(-half - 0.3, -1.6, top), Vector3(half + 0.3, 0.2, top + 0.12), TARP)
	# The ladder between lifts, hung on the outside at one end. It used to run
	# up through the boards of every deck it passed; outside the rail it passes
	# nothing, and each length stops where the next one starts.
	for lift in lifts:
		var z: float = 1.9 + lift * 2.1
		for x: float in [half - 1.4, half - 0.7]:
			box(Vector3(x - 0.05, -1.5, z - 2.1), Vector3(x + 0.05, -1.4, z), METAL)
		for i in 6:
			box(Vector3(half - 1.35, -1.5, z - 2.0 + i * 0.33), Vector3(half - 0.75, -1.4, z - 1.94 + i * 0.33), METAL)

## A WORKS COMPOUND in the bed or on the towpath: heras fence round a cabin,
## a materials stack, a generator and a stack of pipe. Walled, roofed in one
## corner, and the only thing on the map that is temporary — which makes it
## the obvious objective for a mission about what the work is for.
func _site_compound() -> void:
	var w := 11.0
	var d := 7.0
	# The slab tops out at z = 0 and everything stands on that plane. It used
	# to top out at 0.05, with the fence, the feet and the cabin all starting
	# at 0 or 0.05 — inside it.
	box(Vector3(-w, -d, -0.25), Vector3(w, d, 0.0), {"top": BALLAST, "side": CONCRETE, "bottom": CONCRETE})
	# Heras panels: 2 m, on feet, with a gap at one end for the gate. The long
	# panels run the full length and stand on their feet (0.14 up); the end
	# panels butt between them at the corners and not through them.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-w, s * d - s * 0.06, 0.14), Vector3(w, s * d + s * 0.06, 2.0), HERAS)
		box(Vector3(s * w - s * 0.06, -d + 0.06, 0.0), Vector3(s * w + s * 0.06, d - (4.0 if s > 0.0 else 0.06), 2.0), HERAS)
	for i in 9:
		var x := lerpf(-w + 1.0, w - 1.0, float(i) / 8.0)
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.35, s * d - 0.16, 0.0), Vector3(x + 0.35, s * d + 0.16, 0.14), CONCRETE)
	# The cabin, on blocks.
	box(Vector3(-w + 1.2, -d + 1.0, 0.45), Vector3(-w + 7.6, -d + 3.9, 3.0), {"top": ROOF_MEMBRANE, "side": SHUTTER, "bottom": METAL})
	for sx: float in [0.0, 1.0]:
		for sy: float in [0.0, 1.0]:
			box(Vector3(-w + 1.4 + sx * 5.8, -d + 1.2 + sy * 2.3, 0.0), Vector3(-w + 1.9 + sx * 5.8, -d + 1.7 + sy * 2.3, 0.45), CONCRETE)
	# The window and the door stand on the cabin's face (y = -d + 3.9), not
	# astride it.
	box(Vector3(-w + 2.2, -d + 3.9, 1.1), Vector3(-w + 3.6, -d + 4.1, 2.2), DARK_GLASS)
	box(Vector3(-w + 5.4, -d + 3.9, 0.45), Vector3(-w + 6.6, -d + 4.1, 2.4), SHUTTER)
	# Materials: bagged aggregate, a generator, a stack of pipe.
	for i in 6:
		var x := 1.0 + (i % 3) * 1.1
		var y := 1.2 + int(i / 3) * 1.1
		box(Vector3(x - 0.48, y - 0.48, 0.0), Vector3(x + 0.48, y + 0.48, 0.95), {"top": TARP, "side": TARP, "bottom": TARP})
	box(Vector3(5.6, -4.4, 0.0), Vector3(8.4, -2.4, 1.5), {"top": METAL, "side": GREEN, "bottom": METAL})
	_pipe_run(Vector3(2.0, -4.6, 0.0), 6.0)

## 16 m of the yellow barriers from the photographs, in a line with a gap.
## Waist high and see-through: it marks a hole, it does not stop anybody, and
## knowing the difference is the point of having it.
func _barrier_run() -> void:
	# Body, posts and feet are three layers that touch and do not overlap: the
	# feet are 0.1 high, the posts and the body stand on them, and the body
	# runs BETWEEN its two posts. The feet are 0.15 along the run so that this
	# barrier's far foot and the next one's near foot (0.15 apart) meet and
	# do not cross.
	for i in 8:
		if i == 4:
			continue
		var x := -8.0 + i * 2.1
		box(Vector3(x + 0.05, -0.05, 0.1), Vector3(x + 1.9, 0.05, 1.1), HAZARD)
		for e: float in [0.0, 1.95]:
			box(Vector3(x + e - 0.05, -0.07, 0.1), Vector3(x + e + 0.05, 0.07, 1.18), HAZARD)
			box(Vector3(x + e - 0.075, -0.3, 0.0), Vector3(x + e + 0.075, 0.3, 0.1), HAZARD)

## MARKET STALLS along the towpath: six pitched canopies on frames with
## counters under them. A run of waist-high cover and head-high roof in a
## straight line beside a 3 m drop, which is a nasty place to be caught.
func _market_stalls() -> void:
	for i in 6:
		var x := -15.0 + i * 6.0
		# Between the corner posts (they stand at x +- 2.3, 0.05 either side), not
		# through the ends of it.
		box(Vector3(x - 2.25, -1.6, 0.0), Vector3(x + 2.25, -0.9, 0.95), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				post(x + sx * 2.3, sy * 1.5, 0.0, 2.3, 0.1)
		solid([Vector3(x - 2.7, -1.9, 2.3), Vector3(x + 2.7, -1.9, 2.3), Vector3(x + 2.7, 1.9, 2.3), Vector3(x - 2.7, 1.9, 2.3),
				Vector3(x - 2.7, 0.0, 2.9), Vector3(x + 2.7, 0.0, 2.9)],
				{"top": TARP, "side": TARP, "bottom": TARP})
		no_collision()
		for k in 4:
			_heap_on(Vector3(x - 1.8 + k * 1.2, -1.25, 0.95), 0.45, 0.3, 0.35, i * 13 + k, CRATE)
		entity("worldspawn")


## A PLANK FOOTBRIDGE over the prism: scaffold boards on two beams with a rope
## handrail. The third kind of crossing and the worst one — 1.2 m wide, no
## cover, and it tells a player it is temporary.
func _plank_bridge() -> void:
	# The deck top is DECK_TOP, not 0: it runs on over the towpath and a deck at
	# exactly 0 there is two floors at one height. See block_canal.gd.
	var half := BED_HALF + WALL_T + 0.9
	box(Vector3(-0.6, -half, -0.22), Vector3(0.6, half, DECK_TOP), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 0.5 - 0.1, -half, -0.45), Vector3(s * 0.5 + 0.1, half, -0.22), METAL)
	no_collision()
	for s: float in [-1.0, 1.0]:
		for i in 6:
			var y := lerpf(-half + 0.4, half - 0.4, float(i) / 5.0)
			box(Vector3(s * 0.62 - 0.05, y - 0.05, DECK_TOP), Vector3(s * 0.62 + 0.05, y + 0.05, 0.98), METAL)
		# The rope runs along the tops of the posts, which stop where it begins.
		box(Vector3(s * 0.62 - 0.035, -half + 0.4, 0.98), Vector3(s * 0.62 + 0.035, half - 0.4, 1.05), RUBBER)


## A MASONRY ARCH VIADUCT carrying a street over the lower yards: three
## segmental arches on piers, 26 m long and 7 m to the deck. A roofed route
## under it and a street over it, which is two levels for the price of one.
func _arch_viaduct() -> void:
	var span := 8.0
	var deck := 7.0
	var w := 4.5
	# The piers carry right up to the underside of the deck (deck - 0.7), so the
	# arches are infilled between them and not hung beside them.
	var under: float = deck - 0.7
	var pier_x: Array = []
	for i in 4:
		var x := -13.0 + i * span + (0.0 if i < 3 else 1.0)
		pier_x.append(x)
		box(Vector3(x - 1.3, -w, -2.0), Vector3(x + 1.3, w, under), {"top": CONCRETE, "side": RUBBLE_WALL, "bottom": CONCRETE})
	# THE ARCHES ARE SEGMENTAL AND FILLED TO THE DECK. Each used to be a ring
	# of five chords round a semicircle of radius 2.7 centred 1.2 below the
	# deck, whose crown stood 2.4 m ABOVE the road, and whose ends ran 0.9 m
	# into the piers. Now each bay is a row of vertical slices between the
	# piers: flat on top against the deck, the underside following a circular
	# arc, neighbours sharing the plane they meet on. The springing is 4.2 m
	# and the crown 6.0, which is a 1.8 m rise on a 5.4 m opening.
	var spring := 4.2
	var rise := 1.8
	var slices := 8
	for i in 3:
		var xl: float = (pier_x[i] as float) + 1.3
		var xr: float = (pier_x[i + 1] as float) - 1.3
		var half_open := (xr - xl) * 0.5
		var cx := (xl + xr) * 0.5
		var radius := (half_open * half_open + rise * rise) / (2.0 * rise)
		var zc := spring + rise - radius
		for k in slices:
			var xa := lerpf(xl, xr, float(k) / slices)
			var xb := lerpf(xl, xr, float(k + 1) / slices)
			var za := zc + sqrt(maxf(radius * radius - (xa - cx) * (xa - cx), 0.0))
			var zb := zc + sqrt(maxf(radius * radius - (xb - cx) * (xb - cx), 0.0))
			solid([Vector3(xa, -w, za), Vector3(xb, -w, zb), Vector3(xb, -w, under), Vector3(xa, -w, under),
					Vector3(xa, w, za), Vector3(xb, w, zb), Vector3(xb, w, under), Vector3(xa, w, under)], RUBBLE_WALL)
	box(Vector3(-14.0, -w, deck - 0.7), Vector3(14.0, w, deck), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-14.2, s * w, deck), Vector3(14.2, s * (w + 0.5), deck + 1.05), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})

# ── Buildings ────────────────────────────────────────────────────────────────

## FEDERAL ROWHOUSES, five of them in 38 m: flat brick fronts, three bays, a
## stoop straight onto the pavement, dormers in the roof. The upper town was
## built out of suburban townhouses in the first pass, which is the wrong
## country entirely — these are what stands above a canal in Georgetown.
func _rowhouse_run() -> void:
	var w := 7.6
	var d := 9.0
	var tops: Array = []
	for i in 5:
		tops.append(8.4 + float(i % 3) * 0.7)
	for i in 5:
		var x0 := -19.0 + i * w
		var top: float = tops[i]
		var brick: String = MILL_BRICK if i % 2 == 0 else "PSX_Textures/brick_wall_tx_4"
		box(Vector3(x0, -d, -4.0), Vector3(x0 + w, d, top), {"top": CONCRETE, "side": brick, "bottom": CONCRETE})
		# The party wall standing proud above the roof, which is what makes a
		# terrace read as five houses and not one building. It is two halves,
		# each rising from the roof of the house it stands over and meeting on
		# the dividing line: as one 0.4 m slab straddling that line it sat half
		# inside each neighbour's mass, and those two overlaps were repeated at
		# every wall. The outer wall of the end house is the one place it
		# rises from the ground.
		var prev_top: float = tops[i - 1] if i > 0 else top
		var wall_top: float = maxf(prev_top, top) + 0.8
		var tex_wall := {"top": COPING, "side": brick, "bottom": brick}
		box(Vector3(x0 - 0.2, -d - 0.1, -4.0 if i == 0 else prev_top), Vector3(x0, d + 0.1, wall_top), tex_wall)
		box(Vector3(x0, -d - 0.1, top), Vector3(x0 + 0.2, d + 0.1, wall_top), tex_wall)
		# The roof stops at the party walls (x0 + 0.2) and overhangs only the
		# eaves.
		_gable_run(x0 + 0.2, x0 + w - 0.2, -d, d, top, top + 2.3, 0.35)
		no_collision()
		for lvl in 3:
			var z: float = 1.0 + lvl * 2.7
			for b in 3:
				var bx := x0 + 1.5 + b * 2.3
				if lvl == 0 and b == 1:
					continue
				# Centred on the bay: window()'s "along" is the middle, and
				# passing the left edge put every window half a width to the
				# left of its own lintel. The lintel is window()'s own trim, so
				# the extra COPING hood that sat on the same spot is gone.
				window("y", d, bx, z, 1.05, 1.7, true, DARK_GLASS)
		# The door and its stoop, which is the whole front of one of these. The
		# door stands on the face (y = d), not 0.1 inside it.
		box(Vector3(x0 + 3.5, d, 0.0), Vector3(x0 + 4.7, d + 0.12, 2.3), WOOD_DARK)
		box(Vector3(x0 + 3.3, d, 2.3), Vector3(x0 + 4.9, d + 0.9, 2.75), COPING)
		entity("worldspawn")
		# Four treads, rising TOWARD the door. They used to start at the wall
		# and all run out to the same edge, each over the last, with the
		# highest one at the kerb end. 0.22 a tread, not 0.3: at 0.3 the
		# fourth step started exactly where the stoop ended and built as a
		# brush of no thickness at all.
		for k in 4:
			var ya: float = d + 0.12 + k * 0.22
			box(Vector3(x0 + 3.3, ya, -0.1), Vector3(x0 + 4.9, ya + 0.22, 0.08 + (3 - k) * 0.17), {"top": COPING, "side": COPING, "bottom": CONCRETE})
		# A dormer, so the roofline is not five identical triangles. Its floor
		# lies along the roof slope, 0.04 above it, because a flat-bottomed box
		# on a pitch sinks into the pitch.
		if i % 2 == 0:
			var ya: float = d - 2.4
			var yb: float = d - 0.6
			var za: float = top + 2.3 * (1.0 - ya / (d + 0.35)) + 0.04
			var zb: float = top + 2.3 * (1.0 - yb / (d + 0.35)) + 0.04
			var hull: Array = []
			for x: float in [x0 + 2.4, x0 + 4.4]:
				hull.append(Vector3(x, ya, za))
				hull.append(Vector3(x, yb, zb))
				hull.append(Vector3(x, ya, top + 2.0))
				hull.append(Vector3(x, yb, top + 2.0))
			solid(hull, {"top": SHINGLE, "side": brick, "bottom": brick})
			no_collision()
			window("y", yb, x0 + 3.4, zb + 0.35, 0.9, 1.0, true, DARK_GLASS)
			entity("worldspawn")
	box(Vector3(19.0, -d - 0.1, -4.0), Vector3(19.4, d + 0.1, 9.9), {"top": COPING, "side": MILL_BRICK, "bottom": MILL_BRICK})

## A SHORTER MILL, 26 x 12 and three storeys, for the gaps between the long
## ones. A row of one building repeated is a wall; a row of three sizes is a
## street.
func _mill_brick_short() -> void:
	var half := 13.0
	var d := 6.0
	var top := 10.5
	box(Vector3(-half, -d, -4.0), Vector3(half, d, top), {"top": ROOF_MEMBRANE, "side": MILL_BRICK, "bottom": CONCRETE})
	for z: float in [top - 0.8, top - 0.4]:
		_rim(-half, -d, half, d, 0.16, 0.0, z, z + 0.3, MILL_BRICK)
	# A collar round the roof edge, as in the long mill, not a slab over it.
	_rim(-half, -d, half, d, 0.22, 0.3, top, top + 0.85, {"top": COPING, "side": MILL_BRICK, "bottom": MILL_BRICK})
	no_collision()
	for lvl in 3:
		var z: float = 1.1 + lvl * 3.0
		for i in 6:
			var x := lerpf(-half + 2.0, half - 2.0, float(i) / 5.0)
			for s: float in [-1.0, 1.0]:
				# Named for the side it is on and centred on the bay, as in the long
				# mill: "y" builds toward +Y whichever wall it is given, and the
				# along argument is the CENTRE, not the left edge.
				window("y" if s > 0.0 else "-y", s * d, x, z, 1.1, 1.9, true, DARK_GLASS)
				box(Vector3(x - 0.62, s * d, z + 2.15), Vector3(x + 0.62, s * (d + 0.2), z + 2.3), MILL_BRICK)


## A BOATHOUSE on the waterfront: a long shed open at the river end with racks
## of shells inside and a slipway out of it. Roofed, dark and a dead end,
## which makes it a room on a map that has very few.
func _boathouse() -> void:
	var half := 14.0
	var d := 7.0
	var eave := 4.2
	box(Vector3(-half, -d, -0.4), Vector3(-half + 0.4, d, eave), {"top": CONCRETE, "side": WOOD_DARK, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		# The side walls start where the end wall stops, so the two meet at the
		# corner and do not both occupy it.
		box(Vector3(-half + 0.4, s * d - s * 0.4, -0.4), Vector3(half, s * d, eave), {"top": CONCRETE, "side": WOOD_DARK, "bottom": CONCRETE})
	_gable(-half, -d, half, d, eave, eave + 2.4, 0.6)
	box(Vector3(-half + 0.4, -d + 0.4, -0.4), Vector3(half, d - 0.4, 0.0), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		for lvl in 3:
			box(Vector3(-half + 1.0, s * (d - 1.2), 0.6 + lvl * 1.2), Vector3(half - 2.0, s * (d - 0.5), 0.75 + lvl * 1.2), WOOD_DARK)
	no_collision()
	for s: float in [-1.0, 1.0]:
		for lvl in 3:
			# Resting on the rack bar (0.75 up) and starting at the end wall's inner
			# face: at 13 m centred on -9 each shell ran 1.5 m out through the wall.
			log_x(Vector3(-half + 0.4 + 5.3, s * (d - 0.85), 0.75 + lvl * 1.2), 0.3, 10.6, 7, WOOD, "x")
	entity("worldspawn")
	# The slipway, running out under the water line.
	ramp(half, -3.0, half + 9.0, 3.0, -2.8, 0.0, -2.4, "-x", {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})


## A BARGE at the wharf: a flat steel hull with a deckhouse aft and hatches
## forward, 24 m. Deck 0.9 m above the water, so from the esplanade it is a
## step down onto a platform with a drop on three sides.
func _barge() -> void:
	var half := 12.0
	var w := 4.2
	solid([Vector3(-half, -w, -1.6), Vector3(half - 2.0, -w, -1.6), Vector3(half, -w + 1.2, -1.6), Vector3(half, w - 1.2, -1.6), Vector3(half - 2.0, w, -1.6), Vector3(-half, w, -1.6),
			Vector3(-half, -w, 0.3), Vector3(half - 2.0, -w, 0.3), Vector3(half, -w + 1.2, 0.3), Vector3(half, w - 1.2, 0.3), Vector3(half - 2.0, w, 0.3), Vector3(-half, w, 0.3)],
			{"top": GRATING, "side": IRON, "bottom": IRON})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, s * w - s * 0.25, 0.3), Vector3(half - 2.0, s * w, 0.85), IRON)
	box(Vector3(-half + 0.6, -w + 0.9, 0.3), Vector3(-half + 5.4, w - 0.9, 3.2), {"top": ROOF_MEMBRANE, "side": SHUTTER, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		# On the deckhouse side (|y| = w - 0.9), not straddling it.
		box(Vector3(-half + 1.2, s * (w - 0.9), 1.6), Vector3(-half + 4.8, s * (w - 0.8), 2.5), DARK_GLASS)
	for i in 3:
		var x := -1.0 + i * 3.4
		box(Vector3(x - 1.5, -w + 1.4, 0.3), Vector3(x + 1.5, w - 1.4, 0.72), {"top": IRON, "side": IRON, "bottom": IRON})
	no_collision()
	for i in 4:
		var x := -half + 2.0 + i * 6.0
		for s: float in [-1.0, 1.0]:
			log_x(Vector3(x, s * (w + 0.35), -0.5), 0.42, 0.3, 7, RUBBER, "y")
