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
			box(Vector3(s * 11.9, e * (ch + 0.1), 0.35), Vector3(s * 7.4, e * (ch + 0.45), 0.72), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
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
			box(Vector3(-0.3, s * ch - s * 0.14, z), Vector3(0.6, s * ch, z + 0.07), IRON)


## WHAT IS ACTUALLY IN A DRAINED CANAL: silt banks, fallen coping stones, a
## trolley on its side, a tyre, and a run of pipe somebody left. Scattered
## across 30 m of bed and the only cover down there apart from the cofferdam.
##
## The coping blocks and the pipe COLLIDE and everything else does not. A
## 0.4 m stone is something to crouch behind; a 0.1 m scatter of rubbish with
## collision is forty things for a squad to catch on.
func _bed_debris() -> void:
	for i in 5:
		var x := -12.0 + i * 6.0 + _hash_f(i * 13) * 3.0
		var y := (_hash_f(i * 7) - 0.5) * 6.0
		box(Vector3(x - 0.75, y - 0.35, 0.0), Vector3(x + 0.75, y + 0.35, 0.42), {"top": COPING_STONE, "side": COPING_STONE, "bottom": COPING_STONE})
	for i in 3:
		var x := -9.0 + i * 9.0
		mound(Vector3(x, (_hash_f(i * 29) - 0.5) * 5.0, -0.05), 3.4, 2.2, 0.75, i * 17 + 5, SPOIL)
	_pipe_run(Vector3(6.0, -2.2, 0.0), 11.0)
	no_collision()
	# The trolley, on its side in the silt.
	tipped_box(Vector3(-4.0, 2.6, 0.35), Vector3(1.0, 0.6, 0.9), Vector3(74.0, 0.0, 18.0), GRATING)
	for i in 14:
		var x := -14.0 + i * 2.1 + _hash_f(i * 31) * 1.4
		var y := (_hash_f(i * 11) - 0.5) * 7.0
		heap(Vector3(x, y, 0.0), 0.5 + _hash_f(i) * 0.5, 0.4, 0.3, i * 7 + 3, RUBBLE)
	for i in 4:
		var x := -10.0 + i * 7.0
		log_x(Vector3(x, (_hash_f(i * 19) - 0.5) * 6.0, 0.3), 0.32, 0.22, 8, RUBBER, "y")


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
	for lift in lifts:
		var z: float = 1.9 + lift * 2.1
		box(Vector3(-half, -1.3, z - 0.1), Vector3(half, 0.0, z), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
		# The guard rail on each deck, at cover height, so a body on a lift is
		# protected rather than merely standing somewhere high.
		box(Vector3(-half, -1.4, z), Vector3(half, -1.28, z + COVER_H), METAL)
	for i in 7:
		var x := lerpf(-half + 0.4, half - 0.4, float(i) / 6.0)
		for y: float in [-1.25, -0.15]:
			box(Vector3(x - 0.07, y - 0.07, -0.4), Vector3(x + 0.07, y + 0.07, 1.9 + lifts * 2.1), METAL)
	for lift in lifts:
		var z: float = 1.9 + lift * 2.1
		for y: float in [-1.25, -0.15]:
			box(Vector3(-half, y - 0.05, z - 0.95), Vector3(half, y + 0.05, z - 0.85), METAL)
	no_collision()
	box(Vector3(-half - 0.3, -1.6, 1.9 + lifts * 2.1), Vector3(half + 0.3, 0.2, 1.9 + lifts * 2.1 + 0.12), TARP)
	# The ladder between lifts, at one end.
	for lift in lifts:
		var z: float = 1.9 + lift * 2.1
		for x: float in [half - 1.4, half - 0.7]:
			box(Vector3(x - 0.05, -1.1, z - 2.1), Vector3(x + 0.05, -1.0, z), METAL)
		for i in 6:
			box(Vector3(half - 1.45, -1.12, z - 2.0 + i * 0.33), Vector3(half - 0.65, -0.98, z - 1.94 + i * 0.33), METAL)


## A WORKS COMPOUND in the bed or on the towpath: heras fence round a cabin,
## a materials stack, a generator and a stack of pipe. Walled, roofed in one
## corner, and the only thing on the map that is temporary — which makes it
## the obvious objective for a mission about what the work is for.
func _site_compound() -> void:
	var w := 11.0
	var d := 7.0
	box(Vector3(-w, -d, -0.25), Vector3(w, d, 0.05), {"top": BALLAST, "side": CONCRETE, "bottom": CONCRETE})
	# Heras panels: 2 m, on feet, with a gap at one end for the gate.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-w, s * d - s * 0.06, 0.0), Vector3(w, s * d + s * 0.06, 2.0), HERAS)
		box(Vector3(s * w - s * 0.06, -d, 0.0), Vector3(s * w + s * 0.06, d - (4.0 if s > 0.0 else 0.0), 2.0), HERAS)
	for i in 9:
		var x := lerpf(-w + 1.0, w - 1.0, float(i) / 8.0)
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.35, s * d - 0.16, 0.0), Vector3(x + 0.35, s * d + 0.16, 0.14), CONCRETE)
	# The cabin, on blocks.
	box(Vector3(-w + 1.2, -d + 1.0, 0.45), Vector3(-w + 7.6, -d + 3.9, 3.0), {"top": ROOF_MEMBRANE, "side": SHUTTER, "bottom": METAL})
	for sx: float in [0.0, 1.0]:
		for sy: float in [0.0, 1.0]:
			box(Vector3(-w + 1.4 + sx * 5.8, -d + 1.2 + sy * 2.3, 0.05), Vector3(-w + 1.9 + sx * 5.8, -d + 1.7 + sy * 2.3, 0.45), CONCRETE)
	box(Vector3(-w + 2.2, -d + 3.8, 1.1), Vector3(-w + 3.6, -d + 4.0, 2.2), DARK_GLASS)
	box(Vector3(-w + 5.4, -d + 3.8, 0.45), Vector3(-w + 6.6, -d + 4.0, 2.4), SHUTTER)
	# Materials: bagged aggregate, a generator, a stack of pipe.
	for i in 6:
		var x := 1.0 + (i % 3) * 1.1
		var y := 1.2 + int(i / 3) * 1.1
		box(Vector3(x - 0.48, y - 0.48, 0.05), Vector3(x + 0.48, y + 0.48, 0.95), {"top": TARP, "side": TARP, "bottom": TARP})
	box(Vector3(5.6, -4.4, 0.05), Vector3(8.4, -2.4, 1.5), {"top": METAL, "side": GREEN, "bottom": METAL})
	_pipe_run(Vector3(2.0, -4.6, 0.05), 6.0)


## 16 m of the yellow barriers from the photographs, in a line with a gap.
## Waist high and see-through: it marks a hole, it does not stop anybody, and
## knowing the difference is the point of having it.
func _barrier_run() -> void:
	for i in 8:
		if i == 4:
			continue
		var x := -8.0 + i * 2.1
		box(Vector3(x, -0.05, 0.0), Vector3(x + 1.95, 0.05, 1.1), HAZARD)
		for e: float in [0.0, 1.95]:
			box(Vector3(x + e - 0.05, -0.07, 0.0), Vector3(x + e + 0.05, 0.07, 1.18), HAZARD)
			box(Vector3(x + e - 0.3, -0.3, 0.0), Vector3(x + e + 0.3, 0.3, 0.1), HAZARD)


## MARKET STALLS along the towpath: six pitched canopies on frames with
## counters under them. A run of waist-high cover and head-high roof in a
## straight line beside a 3 m drop, which is a nasty place to be caught.
func _market_stalls() -> void:
	for i in 6:
		var x := -15.0 + i * 6.0
		box(Vector3(x - 2.4, -1.6, 0.0), Vector3(x + 2.4, -0.9, 0.95), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				post(x + sx * 2.3, sy * 1.5, 0.0, 2.3, 0.1)
		solid([Vector3(x - 2.7, -1.9, 2.3), Vector3(x + 2.7, -1.9, 2.3), Vector3(x + 2.7, 1.9, 2.3), Vector3(x - 2.7, 1.9, 2.3),
				Vector3(x - 2.7, 0.0, 2.9), Vector3(x + 2.7, 0.0, 2.9)],
				{"top": TARP, "side": TARP, "bottom": TARP})
		no_collision()
		for k in 4:
			heap(Vector3(x - 1.8 + k * 1.2, -1.25, 0.95), 0.45, 0.3, 0.35, i * 13 + k, CRATE)
		entity("worldspawn")


## A PLANK FOOTBRIDGE over the prism: scaffold boards on two beams with a rope
## handrail. The third kind of crossing and the worst one — 1.2 m wide, no
## cover, and it tells a player it is temporary.
func _plank_bridge() -> void:
	var half := BED_HALF + WALL_T + 0.9
	box(Vector3(-0.6, -half, -0.22), Vector3(0.6, half, 0.0), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 0.5 - 0.1, -half, -0.45), Vector3(s * 0.5 + 0.1, half, -0.22), METAL)
	no_collision()
	for s: float in [-1.0, 1.0]:
		for i in 6:
			var y := lerpf(-half + 0.4, half - 0.4, float(i) / 5.0)
			box(Vector3(s * 0.62 - 0.05, y - 0.05, 0.0), Vector3(s * 0.62 + 0.05, y + 0.05, 1.05), METAL)
		box(Vector3(s * 0.62 - 0.035, -half + 0.4, 0.98), Vector3(s * 0.62 + 0.035, half - 0.4, 1.05), RUBBER)


## A MASONRY ARCH VIADUCT carrying a street over the lower yards: three
## segmental arches on piers, 26 m long and 7 m to the deck. A roofed route
## under it and a street over it, which is two levels for the price of one.
func _arch_viaduct() -> void:
	var span := 8.0
	var deck := 7.0
	var w := 4.5
	for i in 4:
		var x := -13.0 + i * span + (0.0 if i < 3 else 1.0)
		box(Vector3(x - 1.3, -w, -2.0), Vector3(x + 1.3, w, deck - 1.2), {"top": CONCRETE, "side": RUBBLE_WALL, "bottom": CONCRETE})
	# The arch rings, each built as five chords so the soffit is a curve.
	for i in 3:
		var cx := -13.0 + i * span + span * 0.5
		for k in 5:
			var a0 := PI * k / 5.0
			var a1 := PI * (k + 1) / 5.0
			var r := span * 0.5 - 1.3
			solid([Vector3(cx + cos(a0) * r, -w, deck - 1.2 + sin(a0) * r),
					Vector3(cx + cos(a1) * r, -w, deck - 1.2 + sin(a1) * r),
					Vector3(cx + cos(a1) * (r + 0.9), -w, deck - 1.2 + sin(a1) * (r + 0.9)),
					Vector3(cx + cos(a0) * (r + 0.9), -w, deck - 1.2 + sin(a0) * (r + 0.9)),
					Vector3(cx + cos(a0) * r, w, deck - 1.2 + sin(a0) * r),
					Vector3(cx + cos(a1) * r, w, deck - 1.2 + sin(a1) * r),
					Vector3(cx + cos(a1) * (r + 0.9), w, deck - 1.2 + sin(a1) * (r + 0.9)),
					Vector3(cx + cos(a0) * (r + 0.9), w, deck - 1.2 + sin(a0) * (r + 0.9))], RUBBLE_WALL)
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
	for i in 5:
		var x0 := -19.0 + i * w
		var top: float = 8.4 + float(i % 3) * 0.7
		var brick: String = MILL_BRICK if i % 2 == 0 else "PSX_Textures/brick_wall_tx_4"
		box(Vector3(x0, -d, -4.0), Vector3(x0 + w, d, top), {"top": CONCRETE, "side": brick, "bottom": CONCRETE})
		# The party wall standing proud above the roof, which is what makes a
		# terrace read as five houses and not one building.
		box(Vector3(x0 - 0.2, -d - 0.1, -4.0), Vector3(x0 + 0.2, d + 0.1, top + 0.8), {"top": COPING, "side": brick, "bottom": brick})
		_gable(x0 + 0.2, -d, x0 + w - 0.2, d, top, top + 2.3, 0.35)
		no_collision()
		for lvl in 3:
			var z: float = 1.0 + lvl * 2.7
			for b in 3:
				var bx := x0 + 1.5 + b * 2.3
				if lvl == 0 and b == 1:
					continue
				window("y", d, bx - 0.52, z, 1.05, 1.7, true, DARK_GLASS)
				box(Vector3(bx - 0.66, d - 0.1, z + 1.7), Vector3(bx + 0.62, d + 0.14, z + 1.86), COPING)
		# The door and its stoop, which is the whole front of one of these.
		box(Vector3(x0 + 3.5, d - 0.1, 0.0), Vector3(x0 + 4.7, d + 0.12, 2.3), WOOD_DARK)
		box(Vector3(x0 + 3.3, d, 2.3), Vector3(x0 + 4.9, d + 0.9, 2.75), COPING)
		entity("worldspawn")
		for k in 4:
			# 0.22 a tread, not 0.3: at 0.3 the fourth step started exactly where
			# the stoop ended and built as a brush of no thickness at all.
			box(Vector3(x0 + 3.3, d + 0.1 + k * 0.22, -0.1), Vector3(x0 + 4.9, d + 1.0, 0.08 + k * 0.17), {"top": COPING, "side": COPING, "bottom": CONCRETE})
		# A dormer, so the roofline is not five identical triangles.
		if i % 2 == 0:
			box(Vector3(x0 + 2.4, d - 2.4, top), Vector3(x0 + 4.4, d - 0.6, top + 1.6), {"top": SHINGLE, "side": brick, "bottom": brick})
			no_collision()
			window("y", d - 0.6, x0 + 2.9, top + 0.4, 0.9, 1.0, true, DARK_GLASS)
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
		box(Vector3(-half - 0.16, -d - 0.16, z), Vector3(half + 0.16, d + 0.16, z + 0.3), MILL_BRICK)
	box(Vector3(-half - 0.22, -d - 0.22, top), Vector3(half + 0.22, d + 0.22, top + 0.85), {"top": COPING, "side": MILL_BRICK, "bottom": MILL_BRICK})
	no_collision()
	for lvl in 3:
		var z: float = 1.1 + lvl * 3.0
		for i in 6:
			var x := lerpf(-half + 2.0, half - 2.0, float(i) / 5.0)
			for s: float in [-1.0, 1.0]:
				window("y", s * d, x - 0.55, z, 1.1, 1.9, true, DARK_GLASS)
				box(Vector3(x - 0.62, s * d - s * 0.12, z + 1.9), Vector3(x + 0.62, s * (d + 0.08), z + 2.05), MILL_BRICK)


## A BOATHOUSE on the waterfront: a long shed open at the river end with racks
## of shells inside and a slipway out of it. Roofed, dark and a dead end,
## which makes it a room on a map that has very few.
func _boathouse() -> void:
	var half := 14.0
	var d := 7.0
	var eave := 4.2
	box(Vector3(-half, -d, -0.4), Vector3(-half + 0.4, d, eave), {"top": CONCRETE, "side": WOOD_DARK, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, s * d - s * 0.4, -0.4), Vector3(half, s * d, eave), {"top": CONCRETE, "side": WOOD_DARK, "bottom": CONCRETE})
	_gable(-half, -d, half, d, eave, eave + 2.4, 0.6)
	box(Vector3(-half + 0.4, -d + 0.4, -0.4), Vector3(half, d - 0.4, 0.0), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		for lvl in 3:
			box(Vector3(-half + 1.0, s * (d - 1.2), 0.6 + lvl * 1.2), Vector3(half - 2.0, s * (d - 0.5), 0.75 + lvl * 1.2), WOOD_DARK)
	no_collision()
	for s: float in [-1.0, 1.0]:
		for lvl in 3:
			log_x(Vector3(-half + 5.0, s * (d - 0.85), 0.95 + lvl * 1.2), 0.3, 13.0, 7, WOOD, "x")
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
		box(Vector3(-half + 1.2, s * (w - 0.95), 1.6), Vector3(-half + 4.8, s * (w - 0.85), 2.5), DARK_GLASS)
	for i in 3:
		var x := -1.0 + i * 3.4
		box(Vector3(x - 1.5, -w + 1.4, 0.3), Vector3(x + 1.5, w - 1.4, 0.72), {"top": IRON, "side": IRON, "bottom": IRON})
	no_collision()
	for i in 4:
		var x := -half + 2.0 + i * 6.0
		for s: float in [-1.0, 1.0]:
			log_x(Vector3(x, s * (w + 0.35), -0.5), 0.42, 0.3, 7, RUBBER, "y")
