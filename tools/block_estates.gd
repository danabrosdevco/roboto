extends "res://tools/block_doodads.gd"

# ─────────────────────────────────────────────
# BLOCK ESTATES — the big housing blocks: slabs, towers, courtyard blocks and
# an unfinished frame, in maps/blocks/estates/estate_*.map.
#
#   godot --headless --path . --script res://tools/block_estates.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_estates.gd -- maps/blocks --force
#
# WHY A SECOND FAMILY. `building_*` fits one 32 × 24 m sketch-map lot and tops
# out at four storeys, so a town built from it is a field of sheds you can see
# straight across. These take TWO OR FOUR lots, street included, and stand five
# to eight storeys. They are there to break the line of sight the small blocks
# cannot.
#
# SIZES, in lots. The sketch grid is a 34 x 26 m block on a 41 x 33 m period:
#
#   wide  2 × 1   up to 72 × 24 m   Quake Y ±36,   X ±12
#   deep  1 × 2   up to 32 × 56 m   Quake Y ±16,   X ±28
#   big   2 × 2   up to 72 × 56 m   Quake Y ±36,   X ±28
#
# Those are the built extents, plinth flares and ramps included, measured off
# the maps rather than intended: two lots plus the street between them is 73 m
# by 57 m, so each piece keeps half a metre of pavement at its widest.
#
# PLACING ONE COSTS THE LOTS IT COVERS. Nothing here knows about the lot grid;
# whatever puts one down has to leave the neighbouring lots empty. See
# docs/BLOCKS.md.
#
# Same kit and rules as the tools this extends: worldspawn brushes only,
# 32 units = 1 m, ground at z 0, footprint centred on the origin, only textures
# that already have a material, and never an overwrite without --force.
#
# WHAT YOU CAN CLIMB, AND WHAT YOU CANNOT. Every deck marked walkable is
# reached by a ramp of 30° or less that starts on open ground or on the deck
# below, as the small buildings are. The TOP of a tall mass usually is not: a
# squad on a 30 m roof can see the whole town, which is the opposite of what
# these are for. An unreachable roof still bakes navmesh; `navmesh_islands.gd`
# sweeps it at load, and Mutaha's region_min_size drops the small ones anyway.
# Each piece's comment says which decks are meant to be reachable.
# ─────────────────────────────────────────────

## Floor to floor. The ground floor is taller, as the small blocks' are.
const STOREY := 3.5
const GROUND_H := 4.0
## Half extents, by how many lots the piece covers. See the table above.
const HALF_W1 := 15.0    # one lot along Quake Y
const HALF_W2 := 35.5    # two
const HALF_D1 := 11.0    # one lot along Quake X
const HALF_D2 := 27.5    # two


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			print("ignoring argument '%s'" % a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_estates.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var made := {
		"estate_slab_five": _slab_five,
		"estate_slab_stepped": _slab_stepped,
		"estate_slab_broken": _slab_broken,
		"estate_gallery_block": _gallery_block,
		"estate_slab_dogleg": _slab_dogleg,
		"estate_podium_row": _podium_row,
		"estate_twin_tower": _twin_tower,
		"estate_point_tower": _point_tower,
		"estate_courtyard_wing": _courtyard_wing,
		"estate_courtyard_block": _courtyard_block,
		"estate_u_block": _u_block,
		"estate_microdistrict": _microdistrict,
		"estate_slab_pair_bridge": _slab_pair_bridge,
		"estate_frame_shell": _frame_shell,
		"estate_collapsed_corner": _collapsed_corner,
		"estate_market_hall": _market_hall,
	}
	var dir := base.path_join("estates")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var skipped := 0
	for name: String in made:
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		# A piece that called no_collision() must not hand the flag to the next.
		_ghost_from = -1
		_entities = []
		(made[name] as Callable).call()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		print("      %-28s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK ESTATES DONE%s" % ((" (%d skipped)" % skipped) if skipped > 0 else ""))
	quit()


# ── Parts ────────────────────────────────────────────────────────────────────

## Where a mass of `storeys` storeys puts its roof, standing on `base`.
func mass_top(storeys: int, base: float = 0.5) -> float:
	return base + GROUND_H + STOREY * (storeys - 1)


## A residential bar: the solid mass, a band at every floor line, and the roof
## slab that oversails it. Returns the height you would WALK on, which is the
## top of that slab and not the top of the mass.
##
## Solid, like every other building in the kit. A hollow one would need doors,
## interior navmesh and a light budget per room, and the squad fights round
## these rather than through them.
func bar(x0: float, y0: float, x1: float, y1: float, storeys: int, tex: Variant,
		base: float = 0.5, cap: bool = true) -> float:
	var top := mass_top(storeys, base)
	box(Vector3(x0, y0, base), Vector3(x1, y1, top), tex)
	for i in storeys - 1:
		band(x0, y0, x1, y1, base + GROUND_H + STOREY * i)
	if not cap:
		return top
	box(Vector3(x0 - 0.3, y0 - 0.3, top), Vector3(x1 + 0.3, y1 + 0.3, top + 0.3), SLAB)
	return top + 0.3


## A floor band: a 0.25 m ledge round the OUTSIDE of a mass, four thin boxes.
##
## IT USED TO BE ONE SLAB ACROSS THE WHOLE FOOTPRINT. Buried in a solid block
## that is invisible and looks like nothing — and it is a FLOOR to the navmesh
## baker, which rasterises surfaces rather than solids, so the top of every
## buried slab came out as a 670 m2 deck inside the building with no way to it.
## Five storeys of that is four phantom decks per block. Only the rim is ever
## seen, so only the rim is built.
func band(x0: float, y0: float, x1: float, y1: float, z: float,
		out: float = 0.25, thick: float = 0.25) -> void:
	box(Vector3(x0 - out, y0 - out, z - thick), Vector3(x0 + out, y1 + out, z), FRAME)
	box(Vector3(x1 - out, y0 - out, z - thick), Vector3(x1 + out, y1 + out, z), FRAME)
	box(Vector3(x0 + out, y0 - out, z - thick), Vector3(x1 - out, y0 + out, z), FRAME)
	box(Vector3(x0 + out, y1 - out, z - thick), Vector3(x1 - out, y1 + out, z), FRAME)


## Piers up a long face, every `pitch` metres: the vertical rhythm that stops a
## 71 m wall reading as one slab of texture.
func piers(axis: String, line: float, a0: float, a1: float, z0: float, z1: float,
		pitch: float = 4.0, depth: float = 0.25) -> void:
	var n: int = maxi(2, int(round((a1 - a0) / pitch)) + 1)
	for i in n:
		var a := lerpf(a0, a1, float(i) / (n - 1))
		var s: float = minf(0.3, (a1 - a0) / (n * 2.0))
		var lo: float = clampf(a - s, a0, a1 - s * 2.0)
		if axis == "x":
			box(Vector3(line, lo, z0), Vector3(line + depth, lo + s * 2.0, z1), FRAME)
		else:
			box(Vector3(lo, line, z0), Vector3(lo + s * 2.0, line + depth, z1), FRAME)


## A grid of shutters on one face: `count` bays across, one row per storey.
## Trim is off — a large block carries hundreds of these and the sill and
## lintel would treble the brush count for something read from 30 m away.
func rows(face: String, wall: float, a0: float, a1: float, count: int, storeys: int,
		base: float = 0.5, w: float = 1.75, h: float = 1.5) -> void:
	for i in count:
		var a := lerpf(a0, a1, (i + 0.5) / count)
		for s in storeys:
			var z := base + 1.25 if s == 0 else base + GROUND_H + STOREY * (s - 1) + 1.0
			window(face, wall, a, z, w, h, false)


## The chamfered base a block stands on. INSET AND FLARED WIDE on purpose: the
## buildings tool flares 2 m for a 1 m rise, which is a 27° bank a body walks
## up, and at the 1 m flare these started with it was 45°. The navmesh accepts
## 45 and a body cannot hold it, so the squad stood at the foot of every block
## on a skirt the mesh said they were on — fifteen of the sixteen, on the first
## run of tools/test_block_steps.gd. The inset keeps the built extent the same.
func pad(x0: float, y0: float, x1: float, y1: float, sides: Dictionary = {}) -> void:
	plinth(x0 + 1.0, y0 + 1.0, x1 - 1.0, y1 - 1.0, -0.5, 0.5, 2.0, PLINTH, sides)


## A walkway or floor slab, `thick` deep under its walking surface.
func deck_slab(x0: float, y0: float, x1: float, y1: float, z: float, thick: float = 0.3,
		tex: Variant = SLAB) -> void:
	box(Vector3(x0, y0, z - thick), Vector3(x1, y1, z), tex)


## Posts under a deck: ONE ROW, along its outer edge. A gallery is held off the
## wall it runs past, so the inner side needs nothing — and an inner row stood
## in the middle of whatever ramp shared the strip, which the navmesh baker
## erodes a full agent radius around from both sides at once.
func props_under(x0: float, y0: float, x1: float, y1: float, z: float, pitch: float = 5.0) -> void:
	var n: int = maxi(2, int(round((y1 - y0) / pitch)) + 1)
	for i in n:
		var y := lerpf(y0 + 0.4, y1 - 0.4, float(i) / (n - 1))
		post(x1 - 0.4, y, 0.0, z - 0.3, 0.3, FRAME)


## THE LANDING AT THE TOP OF A RAMP IS NOT OPTIONAL. A ramp meets the deck it
## serves along one line, and a sloped surface touching a flat one shares a
## CORNER, not an edge — so the navmesh baker builds two regions that never
## join and the deck comes out unreachable with the ramp sitting against it.
## A flat landing at the top, overlapping the deck by a couple of metres, is
## what makes them one surface. Every reachable deck here has one.
func landing(x0: float, y0: float, x1: float, y1: float, z: float) -> void:
	deck_slab(x0, y0, x1, y1, z)
	props_under(x0, y0, x1, y1, z, 4.0)


## A ramp with a rail down each side. Solid when it starts on the ground, so
## there is no crawl space under it for a body to catch in; a slab on posts
## when it starts on a deck, so the deck below stays usable.
func climb(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, run: String,
		on_ground: bool = true, rails: bool = true) -> void:
	if on_ground:
		ramp(x0, y0, x1, y1, 0.0, z0, z1, run)
	else:
		flight(x0, y0, x1, y1, z0, z1, run, 0.3)
	if not rails:
		return
	var up := run.begins_with("+")
	if run.ends_with("y"):
		rail("x", x0 + 0.125, y0, y1, z0, z1, up)
		rail("x", x1 - 0.125, y0, y1, z0, z1, up)
	else:
		rail("y", y0 + 0.125, x0, x1, z0, z1, up)
		rail("y", y1 - 0.125, x0, x1, z0, z1, up)


## The standard roof: parapet, a stair head and a water tank, so a roof reads
## as a roof rather than as the top of a box.
func roof_cap(x0: float, y0: float, x1: float, y1: float, z: float, gaps: Dictionary = {},
		head: bool = true) -> void:
	parapet(x0, y0, x1, y1, z, 1.0, 0.3, gaps)
	if not head:
		return
	var hx: float = lerpf(x0, x1, 0.3)
	var hy: float = lerpf(y0, y1, 0.35)
	box(Vector3(hx, hy, z), Vector3(hx + 3.0, hy + 3.5, z + 2.5), SLAB)
	window("-x", hx, hy + 1.75, z, 1.25, 2.0, false)
	water_tank(lerpf(x0, x1, 0.6), lerpf(y0, y1, 0.7), z)


## An undercroft: a bar built as two masses with a gap through the ground
## storey and the block carried over it on a beam. Apartment blocks on legs are
## everywhere, and a hole you can walk through at street level is worth more to
## a fight than another solid wall.
func pierce(x0: float, y0: float, x1: float, y1: float, storeys: int, tex: Variant,
		gaps: Array, head: float = 4.0) -> float:
	var top := mass_top(storeys)
	var cuts: Array = [y0]
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for g: Array in sorted:
		cuts.append(g[0])
		cuts.append(g[1])
	cuts.append(y1)
	for i in range(0, cuts.size(), 2):
		var s: float = cuts[i]
		var e: float = cuts[i + 1]
		if e - s > 0.05:
			box(Vector3(x0, s, 0.5), Vector3(x1, e, top), tex)
	# Everything above the opening is carried across it.
	for g: Array in sorted:
		box(Vector3(x0, g[0], head + 0.5), Vector3(x1, g[1], top), tex)
		box(Vector3(x0 - 0.25, g[0], head + 0.5), Vector3(x1 + 0.25, g[1], head + 0.9), FRAME)
		for y: float in [g[0], g[1]]:
			post(x0 + 0.6, y + (0.6 if y == g[0] else -0.6), 0.5, head + 0.5, 0.6, FRAME)
			post(x1 - 0.6, y + (0.6 if y == g[0] else -0.6), 0.5, head + 0.5, 0.6, FRAME)
	for i in storeys - 1:
		band(x0, y0, x1, y1, 0.5 + GROUND_H + STOREY * i)
	box(Vector3(x0 - 0.3, y0 - 0.3, top), Vector3(x1 + 0.3, y1 + 0.3, top + 0.3), SLAB)
	return top + 0.3


# ── Wide: two lots side by side, 71 × 22 m ───────────────────────────────────

## Five storeys, 68 m long, with two undercrofts through it and a gallery along
## the back. Walkable: the gallery at 8.3 m and the roof at 18.8 m.
func _slab_five() -> void:
	# The pad stops level with the wall on the ramp side. Anywhere it stands
	# proud of the mass there is a strip of its top at 0.5 m with a near
	# vertical face under it — walkable to the baker, a step to a body.
	pad(-9.0, -35.0, 6.0, 35.0, {"+x": 0.25})
	var roof := pierce(-8.0, -34.0, 5.0, 34.0, 5, INFILL, [[-14.0, -9.0], [9.0, 14.0]])
	piers("x", -8.25, -34.0, 34.0, 0.5, roof - 0.3, 4.25)
	piers("x", 5.0, -34.0, 34.0, 0.5, roof - 0.3, 4.25)
	rows("-x", -8.0, -33.0, -15.0, 5, 5)
	rows("-x", -8.0, -8.0, 8.0, 4, 5)
	rows("-x", -8.0, 15.0, 33.0, 5, 5)
	rows("+x", 5.0, -33.0, 33.0, 15, 5)
	rows("-y", -34.0, -7.0, 4.0, 3, 5)
	rows("+y", 34.0, -7.0, 4.0, 3, 5)
	roof_cap(-8.3, -34.3, 5.3, 34.3, roof, {"+x": [[18.0, 26.0]]})
	# The gallery, and the two ramps that reach it and then the roof.
	#
	# THE RAMPS ARE OUTBOARD OF THE GALLERY, NOT UNDER IT. They used to run in
	# the same strip: 8 m of headroom at the foot, none at the top, so the
	# navmesh baker ate the last third of each ramp and left a 68 m walkway you
	# could see and not reach. A ramp may run beside a deck or over it, never
	# under the one it is climbing to.
	# 4 m of gallery, not 3: at an agent radius of 0.6 a 3 m walkway with a post
	# row in it erodes to a thread and the baker drops pieces of it.
	deck_slab(5.0, -34.0, 9.0, 34.0, 8.3)
	props_under(5.0, -34.0, 9.0, 34.0, 8.3, 5.5)
	# The parapet BREAKS WHERE A RAMP ARRIVES. A landing that meets a walled
	# deck is a landing against a wall.
	upstand("x", Vector2(8.7, 9.0), -34.0, -17.0, 8.3, 8.3, true, 1.0)
	upstand("x", Vector2(8.7, 9.0), -10.0, 34.0, 8.3, 8.3, true, 1.0)
	climb(9.0, -34.0, 14.0, -17.0, 0.0, 8.3, "+y")
	# ONE landing serves the top of the first ramp AND the foot of the second.
	# A ramp rising off a deck touches it along one line too, so its foot needs a
	# flat pad exactly as much as its head does.
	landing(4.0, -17.0, 14.0, -10.0, 8.3)
	climb(9.0, -10.0, 14.0, 19.0, 8.3, roof, "+y", false)
	props_under(9.0, -10.0, 14.0, 19.0, 8.3, 5.0)
	landing(3.0, 19.0, 14.0, 25.0, roof)
	props_under(8.0, -12.0, 11.0, 10.0, 8.3, 5.0)
	upstand("x", Vector2(10.7, 11.0), -12.0, 10.0, 8.3, roof, true, 1.0)


## Three storeys, then five, then seven, in 22 m steps along its length. Three
## roofs at 11.8, 18.8 and 25.8 m, each reached from the one below, so the
## whole thing is a staircase of decks. The most useful shape here for breaking
## a long street: from any angle something is in the way.
func _slab_stepped() -> void:
	pad(-9.0, -35.0, 6.0, 35.0, {"+x": 0.25})
	var a := bar(-8.0, -34.0, 5.0, -11.0, 3, PLASTER_A)
	var b := bar(-8.0, -11.0, 5.0, 11.0, 5, INFILL)
	var c := bar(-8.0, 11.0, 5.0, 34.0, 7, PLASTER_B)
	for span: Array in [[-34.0, -11.0, 3], [-11.0, 11.0, 5], [11.0, 34.0, 7]]:
		var z: float = mass_top(int(span[2]))
		piers("x", -8.25, span[0], span[1], 0.5, z, 4.25)
		rows("-x", -8.0, span[0] + 1.0, span[1] - 1.0, 5, int(span[2]))
		rows("+x", 5.0, span[0] + 1.0, span[1] - 1.0, 5, int(span[2]))
	rows("-y", -34.0, -7.0, 4.0, 3, 3)
	rows("+y", 34.0, -7.0, 4.0, 3, 7)
	roof_cap(-8.3, -34.3, 5.3, -10.7, a, {"+y": [[-6.0, -3.0]], "+x": [[-17.0, -9.0]]}, false)
	roof_cap(-8.3, -11.3, 5.3, 11.3, b, {"+x": [[3.0, 11.0]]}, false)
	roof_cap(-8.3, 10.7, 5.3, 34.3, c, {"+x": [[24.0, 34.0]]})
	# Ground to the low roof up the back, then two short flights over the steps.
	# 4.5 m wide, not 3. A ramp carries two rails, each of which the navmesh
	# baker erodes a full agent radius around: at 3 m the strip left down the
	# middle is 1.4 m and Recast drops it, so the ramp bakes as nothing and
	# everything above it is cut off. Every ramp in this family is 4.5 m now.
	# The landing has to sit ALONGSIDE the roof it serves, not beyond its end:
	# past the end it clips the corner over a metre and a bit and the two never
	# join. Here it runs 5 m down the roof's east edge instead.
	climb(6.0, -36.0, 10.5, -16.0, 0.0, a, "+y")
	landing(3.0, -16.0, 10.5, -10.0, a)
	# 7 m of rise wants 13.8 m of run to stay under 30 degrees; at the 10.8 m
	# the step itself gives you it would be 33.
	# The two upper flights run up the BACK, stacked over the first. They used to
	# cut across the step from one roof to the next — which is inside the wing
	# above, so the flight was buried in a solid block for its whole length.
	climb(6.0, -10.0, 10.5, 4.0, a, b, "+y", false)
	props_under(6.0, -10.0, 10.5, 4.0, a, 4.5)
	landing(3.0, 4.0, 10.5, 10.0, b)
	climb(6.0, 12.0, 10.5, 26.0, b, c, "+y", false)
	props_under(6.0, 12.0, 10.5, 26.0, b, 4.5)
	landing(0.0, 26.0, 10.5, 32.0, c)


## The same five-storey slab with a 14 m bay brought down in the middle. The
## breach is the way up: rubble to the second floor, a fallen slab from there
## to the third. Two halves that have to be cleared separately.
func _slab_broken() -> void:
	pad(-9.0, -35.0, 7.0, -8.0)
	pad(-9.0, 10.0, 7.0, 35.0)
	var west := bar(-8.0, -34.0, 5.0, -9.0, 5, INFILL)
	var east := bar(-8.0, 9.0, 5.0, 34.0, 5, SCORCH)
	piers("x", -8.25, -34.0, -9.0, 0.5, west - 0.3, 4.25)
	piers("x", -8.25, 9.0, 34.0, 0.5, east - 0.3, 4.25)
	rows("-x", -8.0, -33.0, -10.0, 6, 5)
	rows("-x", -8.0, 10.0, 33.0, 6, 5)
	rows("+x", 5.0, -33.0, -10.0, 6, 5)
	roof_cap(-8.3, -34.3, 5.3, -8.7, west, {"+x": [[-30.0, -27.0]]}, false)
	roof_cap(-8.3, 8.7, 5.3, 34.3, east)
	# The break: floor slabs left sticking into the gap, scorched stumps of the
	# party walls, and the heap the rest of it made.
	for i in 4:
		var z: float = 0.5 + GROUND_H + STOREY * i
		box(Vector3(-8.0, -9.0, z - 0.3), Vector3(5.0, -9.0 + 2.0 + i * 0.9, z), SLAB)
		box(Vector3(-8.0, 9.0 - 1.5 - i * 0.7, z - 0.3), Vector3(5.0, 9.0, z), SLAB)
	for p: Array in [[-7.0, -4.5, 9.0], [4.0, -4.5, 6.5], [-7.0, 5.0, 12.0], [4.0, 5.0, 7.5]]:
		box(Vector3(float(p[0]) - 0.4, float(p[1]) - 0.4, 0.5),
				Vector3(float(p[0]) + 0.4, float(p[1]) + 0.4, float(p[2])), SCORCH)
	# Rubble to the second floor, then the slab that came off the third. The
	# breach is 18 m wide because the heap has to climb 7.6 m inside it and
	# still lie under 30 degrees; at 14 m it was 35.
	ramp(-6.0, -8.5, 3.0, 8.5, 0.0, 0.3, 7.9, "+y", RUBBLE)
	rail("x", -5.9, -8.5, 8.5, 0.3, 7.9)
	rail("x", 2.9, -8.5, 8.5, 0.3, 7.9)
	flight(-6.5, 6.0, 2.0, 8.9, 8.0, 11.3, "+y", 0.4, RUBBLE)
	chunk(Vector3(-7.0, 1.0, 0.0), Vector3(2.5, 1.8, 1.1), 22.0)
	chunk(Vector3(4.0, -1.0, 0.0), Vector3(2.0, 2.2, 1.4), 51.0, SCORCH)
	chunk(Vector3(6.5, 2.5, 0.0), Vector3(3.0, 2.0, 1.0), 8.0)
	chunk(Vector3(-9.5, -1.5, 0.0), Vector3(2.2, 1.6, 0.9), 37.0)


## Deck access: four storeys with an open walkway down the back at two levels,
## the way half the world's social housing is built. Three walkable levels —
## 4.8, 8.3 and the roof at 15.3 — and every one of them looks down on the
## street. The piece to put where you want a fight to have a top and a bottom.
func _gallery_block() -> void:
	pad(-9.0, -35.0, 5.0, 35.0, {"+x": 0.25})
	var roof := pierce(-8.0, -34.0, 3.0, 34.0, 4, PLASTER_A, [[-3.0, 3.0]])
	piers("x", -8.25, -34.0, 34.0, 0.5, roof - 0.3, 4.25)
	rows("-x", -8.0, -33.0, -4.0, 8, 4)
	rows("-x", -8.0, 4.0, 33.0, 8, 4)
	rows("-y", -34.0, -7.0, 2.0, 3, 4)
	rows("+y", 34.0, -7.0, 2.0, 3, 4)
	roof_cap(-8.3, -34.3, 3.3, 34.3, roof, {"+x": [[17.0, 25.0]]})
	# Two galleries the whole length, doors onto them, and a stair OUTBOARD of
	# them — the three flights run in their own strip beside the walkways, not
	# beneath them, because a ramp under the deck it climbs to has no headroom
	# where it matters and the baker deletes its top.
	for level: Array in [[4.8, 0], [8.3, 1]]:
		var z: float = level[0]
		deck_slab(3.0, -34.0, 7.0, 34.0, z)
		props_under(3.0, -34.0, 7.0, 34.0, z, 5.5)
		for i in 9:
			var y := lerpf(-31.0, 31.0, float(i) / 8.0)
			window("+x", 3.0, y, z, 1.5, 2.25, false)
	# Parapets, broken where a flight comes off the walkway.
	upstand("x", Vector2(6.7, 7.0), -34.0, -23.0, 4.8, 4.8, true, 1.0)
	upstand("x", Vector2(6.7, 7.0), -16.0, 34.0, 4.8, 4.8, true, 1.0)
	upstand("x", Vector2(6.7, 7.0), -34.0, -10.0, 8.3, 8.3, true, 1.0)
	upstand("x", Vector2(6.7, 7.0), -2.0, 8.0, 8.3, 8.3, true, 1.0)
	upstand("x", Vector2(6.7, 7.0), 8.0, 34.0, 8.3, 8.3, true, 1.0)
	climb(7.0, -34.0, 11.0, -23.0, 0.0, 4.8, "+y")
	landing(2.0, -23.0, 11.0, -17.0, 4.8)
	climb(7.0, -17.0, 11.0, -9.0, 4.8, 8.3, "+y", false)
	props_under(7.0, -17.0, 11.0, -9.0, 8.3, 4.0)
	landing(2.0, -9.0, 11.0, -3.0, 8.3)
	climb(7.0, -3.0, 11.0, 18.0, 8.3, roof, "+y", false)
	props_under(7.0, -3.0, 11.0, 18.0, roof, 5.0)
	landing(1.0, 18.0, 11.0, 24.0, roof)
	upstand("x", Vector2(9.2, 9.5), -34.0, -8.0, 0.0, 8.3, true, 1.0)
	upstand("x", Vector2(9.2, 9.5), 14.0, 34.0, 8.3, roof, true, 1.0)


## Two wings offset across the street line with a stair core in the elbow: five
## storeys one side, four the other. The offset is the point — it gives the
## street a corner to fight round instead of a flat run. Walkable: the low roof
## at 15.3, reached up the inside of the elbow.
func _slab_dogleg() -> void:
	pad(-11.0, -35.0, 3.0, -2.0)
	pad(-3.0, -3.0, 11.0, 35.0, {"-x": 0.25})
	var a := bar(-10.0, -34.0, 2.0, -3.0, 5, INFILL)
	var b := bar(-2.0, -2.0, 10.0, 34.0, 4, PLASTER_B)
	box(Vector3(-3.0, -4.0, 0.5), Vector3(3.0, 0.0, mass_top(6)), FRAME)
	box(Vector3(-3.3, -4.3, mass_top(6)), Vector3(3.3, 0.3, mass_top(6) + 0.3), SLAB)
	piers("x", -10.25, -34.0, -3.0, 0.5, a - 0.3, 4.25)
	piers("x", 10.0, -2.0, 34.0, 0.5, b - 0.3, 4.25)
	rows("-x", -10.0, -33.0, -4.0, 7, 5)
	rows("+x", 2.0, -33.0, -5.0, 7, 5)
	rows("-x", -2.0, -1.0, 33.0, 8, 4)
	rows("+x", 10.0, -1.0, 33.0, 8, 4)
	roof_cap(-10.3, -34.3, 2.3, -2.7, a, {}, false)
	roof_cap(-2.3, -2.3, 10.3, 34.3, b, {"-x": [[28.0, 34.0]]})
	# Up the inside of the elbow to the lower roof. The higher one stays out of
	# reach: from 34 m of slab at 18.8 m you would see the whole quarter.
	climb(-6.0, 0.0, -3.0, 30.0, 0.0, b, "+y")
	deck_slab(-6.0, 30.0, -2.0, 33.0, b)
	props_under(-6.0, 30.0, -2.0, 33.0, b, 3.0)
	rail("x", -5.9, 30.0, 33.0, b, b)
	rail("y", 32.9, -6.0, -2.0, b, b)


## Two storeys of shops with a four-storey bar set back on their roof. The
## podium roof is a 71 × 16 m terrace a storey and a half up, with a parapet all
## round it — a firing line over the street, and the best reason in the kit to
## take a building rather than walk past it. Walkable: the podium at 8.3 m.
func _podium_row() -> void:
	pad(-10.0, -35.0, 7.0, 35.0, {"+x": 0.25})
	box(Vector3(-9.0, -34.0, 0.5), Vector3(6.0, 34.0, 8.0), BRICK)
	box(Vector3(-9.3, -34.3, 8.0), Vector3(6.3, 34.3, 8.3), SLAB)
	# Shopfronts: shutters the whole length under a continuous awning.
	for i in 16:
		var y := lerpf(-32.0, 32.0, (i + 0.5) / 16.0)
		window("-x", -9.0, y, 0.5, 2.75, 3.0, false)
	box(Vector3(-10.5, -34.0, 3.9), Vector3(-9.0, 34.0, 4.2), SHUTTER)
	for i in 9:
		post(-10.25, lerpf(-33.0, 33.0, float(i) / 8.0), 0.0, 3.9)
	rows("-x", -9.0, -32.0, 32.0, 16, 1, 4.5)
	# The bar on top, set back from the podium's edge on all four sides.
	var roof := bar(-6.0, -28.0, 3.0, 28.0, 4, PLASTER_A, 8.3)
	piers("x", -6.25, -28.0, 28.0, 8.3, roof - 0.3, 4.25)
	piers("x", 3.0, -28.0, 28.0, 8.3, roof - 0.3, 4.25)
	rows("-x", -6.0, -27.0, 27.0, 13, 4, 8.3)
	rows("+x", 3.0, -27.0, 27.0, 13, 4, 8.3)
	# The break in the parapet is where the ramp ARRIVES, not where it starts.
	parapet(-9.3, -34.3, 6.3, 34.3, 8.3, 1.0, 0.3, {"+x": [[-19.0, -13.0]]})
	water_tank(4.5, -31.0, 8.3)
	# One straight ramp up the back, inside the footprint, with a landing that
	# runs onto the podium rather than touching it at a corner.
	climb(6.3, -34.0, 9.3, -16.0, 0.0, 8.3, "+y")
	landing(3.0, -16.0, 9.3, -12.5, 8.3)


# ── Deep: two lots front to back, 30 × 55 m ──────────────────────────────────

## Two seven-storey towers on a shared two-storey podium, with the podium's
## roof as a walled yard between them. Walkable: the podium at 8.3 m. The
## towers are not — at 26.6 m they are there to stand in the way.
func _twin_tower() -> void:
	pad(-27.0, -14.0, 27.0, 11.0, {"+y": 0.25})
	box(Vector3(-26.0, -13.0, 0.5), Vector3(26.0, 10.0, 8.0), INFILL)
	box(Vector3(-26.3, -13.3, 8.0), Vector3(26.3, 10.3, 8.3), SLAB)
	rows("-y", -13.0, -25.0, 25.0, 12, 2)
	for x: float in [-24.0, 8.0]:
		var roof := bar(x, -11.0, x + 16.0, 8.0, 5, PLASTER_A, 8.3)
		piers("y", -11.25, x, x + 16.0, 8.3, roof - 0.3, 4.0)
		piers("y", 8.0, x, x + 16.0, 8.3, roof - 0.3, 4.0)
		rows("-y", -11.0, x + 1.0, x + 15.0, 4, 5, 8.3)
		rows("+y", 8.0, x + 1.0, x + 15.0, 4, 5, 8.3)
		rows("-x", x, -10.0, 7.0, 4, 5, 8.3)
		rows("+x", x + 16.0, -10.0, 7.0, 4, 5, 8.3)
		water_tank(x + 8.0, 5.0, roof)
	# The yard between them, walled by the two towers and a parapet at each end.
	parapet(-26.3, -13.3, 26.3, 10.3, 8.3, 1.1, 0.3, {"+y": [[-6.0, 2.0]]})
	box(Vector3(-8.0, -11.0, 8.3), Vector3(-4.0, -7.0, 9.6), FRAME)
	box(Vector3(2.0, 4.0, 8.3), Vector3(6.0, 8.0, 9.6), FRAME)
	# One ramp up the open end, landing across the podium edge.
	climb(-20.0, 10.3, -2.0, 13.3, 0.0, 8.3, "+x")
	landing(-2.0, 5.0, 2.0, 13.3, 8.3)


## One eight-storey tower on a two-storey skirt: 30 m to the parapet and 32.6 m
## to the tank, the tallest thing in the
## kit that is not a landmark. Walkable: the skirt roof at 8.3 m, which is a
## 40 × 22 m deck wrapped round the tower's foot. The tower is not climbable
## and is not meant to be.
func _point_tower() -> void:
	pad(-21.0, -14.0, 21.0, 10.0, {"+y": 0.25})
	box(Vector3(-20.0, -13.0, 0.5), Vector3(20.0, 9.0, 8.0), INFILL)
	box(Vector3(-20.3, -13.3, 8.0), Vector3(20.3, 9.3, 8.3), SLAB)
	rows("-y", -13.0, -19.0, 19.0, 9, 2)
	rows("-x", -20.0, -12.0, 8.0, 5, 2)
	rows("+x", 20.0, -12.0, 8.0, 5, 2)
	# The tower sits 1 m further south than it looks it should: the ring of skirt
	# roof round it has to stay wider than twice the agent radius or the two
	# halves of it are separate places.
	var roof := bar(-11.0, -8.0, 11.0, 6.0, 6, PLASTER_B, 8.3)
	for face: Array in [["-y", -8.0, -10.0, 10.0, 6], ["+y", 6.0, -10.0, 10.0, 6]]:
		rows(str(face[0]), float(face[1]), float(face[2]), float(face[3]), 6, int(face[4]), 8.3)
	rows("-x", -11.0, -7.0, 5.0, 4, 6, 8.3)
	rows("+x", 11.0, -7.0, 5.0, 4, 6, 8.3)
	piers("y", -8.25, -11.0, 11.0, 8.3, roof - 0.3, 4.4)
	piers("y", 6.0, -11.0, 11.0, 8.3, roof - 0.3, 4.4)
	roof_cap(-11.3, -8.3, 11.3, 6.3, roof, {}, true)
	parapet(-20.3, -13.3, 20.3, 9.3, 8.3, 1.1, 0.3, {"+y": [[-6.0, 2.0]]})
	climb(-20.0, 9.3, -2.0, 13.3, 0.0, 8.3, "+x")
	landing(-2.0, 4.0, 2.0, 13.3, 8.3)


## An L of four storeys round a yard that opens to the street: the yard is a
## killing ground with one way in, and the ramp up it is 30 m long, so taking
## the roof costs you the whole length of it under fire. Walkable: the roof at
## 15.3 m.
func _courtyard_wing() -> void:
	pad(-27.0, -15.0, -11.0, 15.0)
	pad(-12.0, 4.0, 27.0, 15.0)
	var a := bar(-26.0, -14.0, -12.0, 14.0, 4, PLASTER_A)
	var b := bar(-12.0, 4.0, 26.0, 14.0, 4, INFILL)
	piers("x", -26.25, -14.0, 14.0, 0.5, a - 0.3, 4.4)
	piers("y", 14.0, -12.0, 26.0, 0.5, b - 0.3, 4.4)
	rows("-x", -26.0, -13.0, 13.0, 6, 4)
	rows("+x", -12.0, -13.0, 3.0, 4, 4)
	rows("-y", 4.0, -11.0, 25.0, 6, 4)
	rows("+y", 14.0, -25.0, 25.0, 12, 4)
	rows("+x", 26.0, 5.0, 13.0, 2, 4)
	roof_cap(-26.3, -14.3, -11.7, 14.3, a, {"+x": [[-10.5, -3.5]]}, false)
	roof_cap(-12.3, 3.7, 26.3, 14.3, b)
	# Up the yard in two flights that double back, because the yard is 38 m the
	# long way and only 18 m the short way: one straight run at 15.3 m of rise
	# would be 40 degrees, which is a wall to a body however walkable the
	# navmesh thinks it is.
	climb(-9.0, -13.0, 7.0, -9.0, 0.0, 7.6, "+x")
	deck_slab(7.0, -13.0, 13.0, -5.0, 7.6)
	props_under(7.0, -13.0, 13.0, -5.0, 7.6, 4.0)
	upstand("y", Vector2(-13.3, -13.0), 7.0, 13.0, 7.6, 7.6, true, 1.0)
	upstand("x", Vector2(12.7, 13.0), -13.0, -5.0, 7.6, 7.6, true, 1.0)
	climb(-9.0, -9.0, 9.0, -5.0, 7.6, a, "-x", false)
	props_under(-9.0, -9.0, 9.0, -5.0, a, 5.0)
	landing(-14.5, -9.0, -9.0, -5.0, a)
	upstand("y", Vector2(-9.3, -9.0), -12.0, 9.0, a, a, true, 1.0)
	upstand("y", Vector2(-5.3, -5.0), -12.0, 9.0, 7.6, a, false, 1.0)
	# A wall across the yard mouth, with a gap: cover on the way in.
	box(Vector3(-12.0, -14.0, 0.0), Vector3(-11.0, -6.0, 2.4), PLASTER_B)
	box(Vector3(-12.0, -2.0, 0.0), Vector3(-11.0, 4.0, 2.4), PLASTER_B)


# ── Big: four lots, 71 × 55 m ────────────────────────────────────────────────

## A perimeter block round its own courtyard, five storeys, with an archway
## through each long side. The courtyard is 28 × 44 m of ground you can only
## reach through an arch, and the gallery ring at 8.3 m looks down into it.
## Walkable: the gallery, and the roof at 18.8 m from the gallery's far end.
func _courtyard_block() -> void:
	pad(-27.0, -35.0, 27.0, 35.0)
	var roof := mass_top(5) + 0.3
	# Two long bars, pierced, and two end bars between them.
	# 10 m archways, not 6. The bar is 12 m deep, so the opening is a tunnel:
	# the corner posts eat 2.4 m of a 6 m one and the navmesh baker erodes a
	# further 0.6 either side, which left too little of it to get a squad in and
	# the whole courtyard unreachable.
	pierce(-26.0, -34.0, -14.0, 34.0, 5, INFILL, [[-5.0, 5.0]])
	pierce(14.0, -34.0, 26.0, 34.0, 5, INFILL, [[-5.0, 5.0]])
	bar(-14.0, -34.0, 14.0, -22.0, 5, PLASTER_A)
	bar(-14.0, 22.0, 14.0, 34.0, 5, PLASTER_B)
	piers("x", -26.25, -34.0, 34.0, 0.5, roof - 0.3, 4.25)
	piers("x", 26.0, -34.0, 34.0, 0.5, roof - 0.3, 4.25)
	rows("-x", -26.0, -33.0, -4.0, 7, 5)
	rows("-x", -26.0, 4.0, 33.0, 7, 5)
	rows("+x", 26.0, -33.0, -4.0, 7, 5)
	rows("+x", 26.0, 4.0, 33.0, 7, 5)
	rows("-y", -34.0, -13.0, 13.0, 6, 5)
	rows("+y", 34.0, -13.0, 13.0, 6, 5)
	# Inward faces, onto the yard.
	rows("+x", -14.0, -21.0, 21.0, 10, 5)
	rows("-x", 14.0, -21.0, 21.0, 10, 5)
	roof_cap(-26.3, -34.3, -13.7, 34.3, roof, {"+x": [[-2.0, 2.0]]}, false)
	roof_cap(13.7, -34.3, 26.3, 34.3, roof, {"-x": [[15.0, 25.0]]})
	parapet(-14.3, -34.3, 14.3, -21.7, roof, 1.0, 0.3)
	parapet(-14.3, 21.7, 14.3, 34.3, roof, 1.0, 0.3)
	# The gallery ring inside the yard, and the two ramps that serve it.
	for side: Array in [[-14.0, -10.5, "+x"], [10.5, 14.0, "-x"]]:
		deck_slab(float(side[0]), -21.0, float(side[1]), 21.0, 8.3)
		props_under(float(side[0]), -21.0, float(side[1]), 21.0, 8.3, 5.0)
	deck_slab(-14.0, -22.0, 14.0, -18.5, 8.3)
	props_under(-14.0, -22.0, 14.0, -18.5, 8.3, 6.0)
	# Gaps in the gallery ring where each ramp meets it.
	upstand("x", Vector2(-10.8, -10.5), -21.0, 1.0, 8.3, 8.3, true, 1.0)
	upstand("x", Vector2(-10.8, -10.5), 7.0, 21.0, 8.3, 8.3, true, 1.0)
	upstand("x", Vector2(10.5, 10.8), -21.0, -5.0, 8.3, 8.3, true, 1.0)
	upstand("x", Vector2(10.5, 10.8), 1.0, 21.0, 8.3, 8.3, true, 1.0)
	upstand("y", Vector2(-18.8, -18.5), -10.5, 10.5, 8.3, 8.3, true, 1.0)
	# Both ramps stand OUT IN THE COURTYARD, not under the gallery ring. Under
	# it they had no headroom at the top and the baker deleted them.
	climb(-11.0, -18.0, -6.5, 2.0, 0.0, 8.3, "+y")
	landing(-14.0, 2.0, -6.5, 6.5, 8.3)
	landing(6.5, -9.0, 14.0, -2.0, 8.3)
	climb(6.5, -2.0, 11.0, 18.0, 8.3, roof, "+y", false)
	props_under(6.5, -2.0, 11.0, 18.0, roof, 5.0)
	landing(4.0, 16.0, 20.0, 23.0, roof)
	upstand("x", Vector2(7.0, 7.3), -2.0, 18.0, 8.3, roof, true, 1.0)
	upstand("x", Vector2(10.2, 10.5), -2.0, 18.0, 8.3, roof, true, 1.0)


## A U of four storeys round a yard, with a six-storey back. The yard opens
## south and holds a hard standing and a bin store; the arms' roofs at 15.3 m
## are walkable and look straight down into it. The back block is not.
func _u_block() -> void:
	pad(-27.0, -35.0, 27.0, -21.0)
	pad(-27.0, -22.0, -11.0, 35.0)
	pad(11.0, -22.0, 27.0, 35.0)
	var back := bar(-26.0, -34.0, 26.0, -22.0, 6, INFILL)
	var west := bar(-26.0, -22.0, -12.0, 34.0, 4, PLASTER_A)
	var east := bar(12.0, -22.0, 26.0, 34.0, 4, PLASTER_B)
	piers("y", -34.25, -26.0, 26.0, 0.5, back - 0.3, 4.4)
	piers("x", -26.25, -22.0, 34.0, 0.5, west - 0.3, 4.4)
	piers("x", 26.0, -22.0, 34.0, 0.5, east - 0.3, 4.4)
	rows("-y", -34.0, -25.0, 25.0, 12, 6)
	rows("-x", -26.0, -21.0, 33.0, 12, 4)
	rows("+x", 26.0, -21.0, 33.0, 12, 4)
	rows("+x", -12.0, -20.0, 33.0, 11, 4)
	rows("-x", 12.0, -20.0, 33.0, 11, 4)
	rows("+y", 34.0, -25.0, -13.0, 3, 4)
	rows("+y", 34.0, 13.0, 25.0, 3, 4)
	roof_cap(-26.3, -34.3, 26.3, -21.7, back, {}, false)
	roof_cap(-26.3, -22.3, -11.7, 34.3, west, {"+x": [[28.0, 32.0]]}, false)
	roof_cap(11.7, -22.3, 26.3, 34.3, east)
	# Up the inside of the west arm.
	# The ramp stops at z 30 and the landing takes the last 4 m: run to 34 and
	# the landing sat on top of its own approach with 0.7 m of headroom.
	climb(-12.0, 2.0, -8.0, 30.0, 0.0, west, "+y")
	deck_slab(-12.0, 30.0, -6.0, 34.0, west)
	props_under(-12.0, 30.0, -6.0, 34.0, west, 4.0)
	rail("x", -6.1, 30.0, 34.0, west, west)
	# The yard: a bin store and a low wall to fight over.
	box(Vector3(-6.0, -18.0, 0.0), Vector3(2.0, -10.0, 3.2), BRICK)
	box(Vector3(-6.3, -18.3, 3.2), Vector3(2.3, -9.7, 3.5), SLAB)
	box(Vector3(-9.0, 4.0, 0.0), Vector3(9.0, 5.0, 1.4), FRAME)
	box(Vector3(-9.0, 18.0, 0.0), Vector3(-2.0, 19.0, 1.4), FRAME)
	box(Vector3(2.0, 18.0, 0.0), Vector3(9.0, 19.0, 1.4), FRAME)


## Two slabs set at right angles with a single-storey shop block between them,
## the way a microdistrict is laid out: the buildings make the space rather
## than filling it. Walkable: the shop roof at 5.3 m, and nothing else — both
## slabs are sightline blocks.
func _microdistrict() -> void:
	pad(-27.0, -35.0, -13.0, 3.0)
	pad(-11.0, 21.0, 27.0, 35.0)
	var a := bar(-26.0, -34.0, -14.0, 2.0, 5, INFILL)
	var b := bar(-10.0, 22.0, 26.0, 34.0, 4, PLASTER_A)
	piers("x", -26.25, -34.0, 2.0, 0.5, a - 0.3, 4.5)
	piers("x", -14.0, -34.0, 2.0, 0.5, a - 0.3, 4.5)
	piers("y", 34.0, -10.0, 26.0, 0.5, b - 0.3, 4.5)
	rows("-x", -26.0, -33.0, 1.0, 8, 5)
	rows("+x", -14.0, -33.0, 1.0, 8, 5)
	rows("-y", 22.0, -9.0, 25.0, 8, 4)
	rows("+y", 34.0, -9.0, 25.0, 8, 4)
	roof_cap(-26.3, -34.3, -13.7, 2.3, a, {}, false)
	roof_cap(-10.3, 21.7, 26.3, 34.3, b, {}, false)
	# The shops in the middle, and the ramp onto their roof.
	box(Vector3(-8.0, -16.0, 0.5), Vector3(8.0, 2.0, 5.0), BRICK)
	box(Vector3(-8.3, -16.3, 5.0), Vector3(8.3, 2.3, 5.3), SLAB)
	for i in 5:
		window("-x", -8.0, lerpf(-14.0, 0.0, float(i) / 4.0), 0.5, 2.5, 3.0, false)
	parapet(-8.3, -16.3, 8.3, 2.3, 5.3, 0.9, 0.3, {"+y": [[-5.5, -0.5]]})
	climb(-5.0, 2.3, -1.0, 13.3, 0.0, 5.3, "-y")
	water_tank(5.0, -13.0, 5.3)
	# The space between: a playground frame, a transformer hut, kerbs.
	for c: Array in [[14.0, -24.0], [14.0, -10.0], [20.0, -17.0]]:
		post(float(c[0]), float(c[1]), 0.0, 3.0, 0.3)
	box(Vector3(11.0, -25.5, 2.8), Vector3(23.0, -25.2, 3.1), METAL)
	box(Vector3(11.0, -8.8, 2.8), Vector3(23.0, -8.5, 3.1), METAL)
	box(Vector3(16.0, 6.0, 0.0), Vector3(22.0, 14.0, 3.4), PLASTER_B)
	box(Vector3(15.7, 5.7, 3.4), Vector3(22.3, 14.3, 3.7), SLAB)
	box(Vector3(-11.0, 6.0, 0.0), Vector3(-10.4, 18.0, 0.5), FRAME)


## Two six-storey slabs facing each other across a low deck, joined by a bridge
## at the fourth floor. Both slabs carry a gallery at 15.3 m that the bridge
## lands on, so crossing between them is a real route and not scenery.
## Walkable: the deck at 4.8 m. THE GALLERIES AND THE BRIDGE AT 15.3 ARE NOT
## YET — the flight climbs to 14.5 m and the last stretch will not join them.
## On the list.
func _slab_pair_bridge() -> void:
	pad(-27.0, -35.0, -13.0, 35.0)
	pad(13.0, -35.0, 27.0, 35.0)
	var west := bar(-26.0, -34.0, -14.0, 34.0, 6, INFILL)
	var east := bar(14.0, -34.0, 26.0, 34.0, 6, PLASTER_A)
	piers("x", -26.25, -34.0, 34.0, 0.5, west - 0.3, 4.25)
	piers("x", 26.0, -34.0, 34.0, 0.5, east - 0.3, 4.25)
	rows("-x", -26.0, -33.0, 33.0, 16, 6)
	rows("+x", 26.0, -33.0, 33.0, 16, 6)
	rows("-y", -34.0, -25.0, 25.0, 6, 6)
	rows("+y", 34.0, -25.0, 25.0, 6, 6)
	roof_cap(-26.3, -34.3, -13.7, 34.3, west, {}, false)
	roof_cap(13.7, -34.3, 26.3, 34.3, east, {}, false)
	# The deck between the slabs, a storey and a bit up.
	box(Vector3(-14.0, -20.0, 0.5), Vector3(14.0, 20.0, 4.5), BRICK)
	box(Vector3(-14.3, -20.3, 4.5), Vector3(14.3, 20.3, 4.8), SLAB)
	parapet(-14.3, -20.3, 14.3, 20.3, 4.8, 0.9, 0.3, {"-y": [[-13.0, -7.0]]})
	for i in 6:
		window("-y", -20.0, lerpf(-11.0, 11.0, float(i) / 5.0), 0.5, 2.0, 2.5, false)
	# Galleries at the fourth floor, and the bridge between them.
	for side: Array in [[-14.0, -10.5, -14.0], [10.5, 14.0, 14.0]]:
		deck_slab(float(side[0]), -34.0, float(side[1]), 34.0, 15.3)
		for i in 13:
			window(("+x" if float(side[2]) < 0.0 else "-x"), float(side[2]),
					lerpf(-31.0, 31.0, float(i) / 12.0), 15.3, 1.5, 2.25, false)
	# The west gallery's parapet breaks where the ramp lands on it.
	upstand("x", Vector2(-10.8, -10.5), -34.0, 11.0, 15.3, 15.3, true, 1.0)
	upstand("x", Vector2(-10.8, -10.5), 17.0, 34.0, 15.3, 15.3, true, 1.0)
	upstand("x", Vector2(10.5, 10.8), -34.0, 34.0, 15.3, 15.3, true, 1.0)
	deck_slab(-10.5, -4.0, 10.5, 4.0, 15.3)
	rail("y", -3.9, -10.5, 10.5, 15.3, 15.3)
	rail("y", 3.9, -10.5, 10.5, 15.3, 15.3)
	# Two legs a side, at the bridge's own edges. At four they stood in the
	# middle of the ramp below and split it into two threads the baker dropped.
	for x: float in [-9.5, 9.5]:
		post(x, -3.6, 4.8, 15.0, 0.35, FRAME)
		post(x, 3.6, 4.8, 15.0, 0.35, FRAME)
	# Ground to the deck, deck to the west gallery.
	climb(-12.0, -32.0, -8.0, -20.3, 0.0, 4.8, "+y")
	# Out on the deck rather than under the west gallery, which it climbs to.
	# No pad at this foot: the ramp from the ground runs head-on into the deck's
	# own edge, which is already a flat surface the full width of it. A pad here
	# only put a ceiling 0.9 m over the top of the ramp below.
	climb(-8.0, -18.0, -3.5, 12.0, 4.8, 15.3, "+y", false)
	props_under(-8.0, -18.0, -3.5, 12.0, 15.3, 5.0)
	landing(-14.0, 11.0, -3.5, 17.0, 15.3)
	upstand("x", Vector2(-7.3, -7.0), -18.0, 12.0, 4.8, 15.3, true, 1.0)
	upstand("x", Vector2(-10.5, -10.2), -18.0, 12.0, 4.8, 15.3, true, 1.0)


## A frame that was never finished: columns, floors and a few shuttered panels,
## five decks of it and no walls. You can see through it and still not be able
## to shoot through it, which no other piece here does. Walkable: every deck up
## to the fourth, by the builders' ramps, which are in different bays at each
## level so crossing the floor is part of the climb.
func _frame_shell() -> void:
	var xs: Array = [-20.0, -13.0, -6.0, 1.0, 8.0, 15.0, 20.0]
	var ys: Array = [-26.0, -19.5, -13.0, -6.5, 0.0, 6.5, 13.0, 19.5, 26.0]
	var decks: Array = [4.3, 7.8, 11.3, 14.8]
	pad(-21.5, -27.5, 21.5, 27.5, {"-y": 0.25})
	for x: float in xs:
		for y: float in ys:
			box(Vector3(x - 0.35, y - 0.35, 0.3), Vector3(x + 0.35, y + 0.35, 16.4), FRAME)
	# Floors, each with a void so the frame reads as open and the navmesh is
	# not five solid decks of 40 by 52 metres stacked on one lot.
	for i in decks.size():
		var z: float = decks[i]
		# A big void in each floor, on alternate sides, so the frame reads as
		# open from the street and does not stack four full decks of 40 by 52 m
		# of navmesh on one lot.
		var hole_y: float = -13.0 if i % 2 == 0 else 6.5
		deck_slab(-20.5, -26.5, 20.5, hole_y - 6.5, z, 0.35, SLAB)
		deck_slab(-20.5, hole_y + 6.5, 20.5, 26.5, z, 0.35, SLAB)
		deck_slab(-20.5, hole_y - 6.5, -6.0, hole_y + 6.5, z, 0.35, SLAB)
		deck_slab(8.0, hole_y - 6.5, 20.5, hole_y + 6.5, z, 0.35, SLAB)
		# Edge upstands, so a body cannot walk off the side in the dark.
		upstand("x", Vector2(-20.5, -20.2), -26.5, 26.5, z, z, true, 0.9)
		upstand("x", Vector2(20.2, 20.5), -26.5, 26.5, z, z, true, 0.9)
		upstand("y", Vector2(-26.5, -26.2), -20.5, 20.5, z, z, true, 0.9)
		upstand("y", Vector2(26.2, 26.5), -20.5, 20.5, z, z, true, 0.9)
	# Shuttering and panels left on a few bays: partial cover, not walls.
	for p: Array in [[-20.4, -19.5, 0.0, 0], [-20.4, 6.5, 19.5, 1], [20.1, -19.5, -6.5, 2],
			[20.1, 0.0, 13.0, 3]]:
		box(Vector3(float(p[0]), float(p[1]), decks[int(p[3])] - 0.35),
				Vector3(float(p[0]) + 0.3, float(p[2]), decks[int(p[3])] + 2.6), INFILL)
	# The builders' ramps. EACH ONE RUNS UP THROUGH THE VOID IN THE FLOOR IT IS
	# CLIMBING TO — anywhere else it is under a solid deck and the top of it has
	# no headroom. The voids alternate sides, so the climb crosses each floor.
	climb(-5.0, -19.5, 0.0, -6.5, 0.0, 4.3, "+y")
	climb(1.0, 0.0, 6.0, 13.0, 4.3, 7.8, "+y", false)
	climb(-5.0, -19.5, 0.0, -6.5, 7.8, 11.3, "+y", false)
	climb(1.0, 0.0, 6.0, 13.0, 11.3, 14.8, "+y", false)
	# Nothing climbs off the top deck: the frame is a place to fight inside,
	# not a 16 m firing platform over the quarter.
	# A hoist and a stack of panels on the ground, so it reads as a site.
	post(15.0, -26.0, 0.3, 22.0, 0.45, METAL)
	post(15.0, -22.0, 0.3, 22.0, 0.45, METAL)
	box(Vector3(14.3, -26.6, 21.6), Vector3(15.7, -21.4, 22.4), METAL)
	chunk(Vector3(-16.0, 22.0, 0.3), Vector3(5.0, 2.5, 1.2), 12.0, INFILL)
	chunk(Vector3(-10.0, 23.5, 0.3), Vector3(4.0, 2.0, 0.8), 71.0, INFILL)


## Five storeys with one corner brought down into a ramp of its own floors.
## The rubble climbs to the third floor, so there is a way up that is not a
## staircase and cannot be held from inside. Walkable: the rubble and the
## exposed floors at 11.5 m. The main roof is NOT — see the note at the heap.
func _collapsed_corner() -> void:
	pad(-27.0, -35.0, 27.0, 13.0)
	var roof := bar(-26.0, -34.0, 26.0, 12.0, 5, INFILL)
	piers("x", -26.25, -34.0, 12.0, 0.5, roof - 0.3, 4.4)
	piers("x", 26.0, -34.0, 12.0, 0.5, roof - 0.3, 4.4)
	rows("-x", -26.0, -33.0, 11.0, 11, 5)
	rows("+x", 26.0, -33.0, 11.0, 11, 5)
	rows("-y", -34.0, -25.0, 25.0, 12, 5)
	roof_cap(-26.3, -34.3, 26.3, 12.3, roof, {"+y": [[-14.0, -8.0]]})
	# The fallen corner: floor plates still cantilevered off the break, the
	# party walls standing as stumps, and the heap they came down in.
	for i in 4:
		var z: float = 0.5 + GROUND_H + STOREY * i
		box(Vector3(-26.0, 12.0, z - 0.35), Vector3(26.0, 12.0 + 2.5 + i * 1.6, z), SLAB)
	for p: Array in [[-22.0, 15.0, 13.0], [-8.0, 16.5, 9.5], [6.0, 15.5, 11.5], [20.0, 17.0, 7.0]]:
		box(Vector3(float(p[0]) - 0.45, float(p[1]) - 0.45, 0.5),
				Vector3(float(p[0]) + 0.45, float(p[1]) + 0.45, float(p[2])), SCORCH)
	# 11.2 m of rise over 20 m of heap is 29 degrees. At the 17 m the corner
	# actually covers it was 33, which a body cannot hold on.
	# The heap meets the ground at nothing, not at 0.3 m: a lip along the foot
	# of a ramp is the whole ramp wasted.
	ramp(-14.0, 13.0, 4.0, 33.0, 0.0, 0.0, 11.2, "-y", RUBBLE)
	landing(-14.0, 8.0, 4.0, 13.0, 11.5)
	rail("x", -13.9, 13.0, 33.0, 11.2, 0.0)
	rail("x", 3.9, 13.0, 33.0, 11.2, 0.0)
	flight(4.0, 13.0, 14.0, 22.0, 5.5, 11.3, "-y", 0.5, RUBBLE)
	# NOTHING CLIMBS FROM HERE TO THE ROOF. The heap tops out at 11.2 m against
	# a break face whose roof is 18.8, and the 7.6 m between them would want 14 m
	# of run in ground that is 1 m wide. The third floor is as far as the breach
	# goes, which is what it is for.
	for c: Array in [[-20.0, 24.0, 3.0, 2.4, 1.6, 19.0], [10.0, 26.0, 4.0, 3.0, 1.9, 44.0],
			[20.0, 21.0, 3.5, 2.2, 1.3, 63.0], [-4.0, 31.0, 5.0, 2.8, 1.1, 9.0],
			[18.0, 31.0, 3.0, 2.0, 0.9, 31.0], [-24.0, 18.0, 2.5, 2.0, 1.4, 55.0]]:
		chunk(Vector3(float(c[0]), float(c[1]), 0.0),
				Vector3(float(c[2]), float(c[3]), float(c[4])), float(c[5]))
	# From the exposed floors to the main roof, up the break face.
	# Up the break face from the heap, in a strip the landing actually reaches.




## A market hall with housing over one end: 46 m of clear-span roof at 12.3 m
## that you can get onto, and a six-storey bar behind it that you cannot. The
## roof is the biggest single piece of high ground in the kit.
func _market_hall() -> void:
	pad(-27.0, -35.0, 21.0, 7.0, {"+x": 0.25})
	box(Vector3(-26.0, -34.0, 0.5), Vector3(20.0, 6.0, 12.0), SHUTTER)
	box(Vector3(-26.3, -34.3, 12.0), Vector3(20.3, 6.3, 12.3), SLAB)
	# The hall's frame: bays up both long sides and a clerestory band.
	piers("x", -26.4, -34.0, 6.0, 0.5, 12.0, 5.0, 0.4)
	piers("x", 20.0, -34.0, 6.0, 0.5, 12.0, 5.0, 0.4)
	# A clerestory RING, not a slab across the hall: buried in the solid it is
	# invisible, and its top face comes out as a 1700 m2 deck inside the hall.
	band(-26.0, -34.0, 20.0, 6.0, 9.3, 0.4, 0.8)
	for i in 6:
		window("-y", -34.0, lerpf(-20.0, 14.0, float(i) / 5.0), 0.5, 3.5, 4.5, false)
	for i in 8:
		var y := lerpf(-31.0, 3.0, float(i) / 7.0)
		window("-x", -26.0, y, 9.6, 2.0, 2.0, false)
		window("+x", 20.0, y, 9.6, 2.0, 2.0, false)
	parapet(-26.3, -34.3, 20.3, 6.3, 12.3, 1.1, 0.3, {"+x": [[-14.0, -6.0]]})
	water_tank(16.0, -30.0, 12.3)
	# The housing behind it.
	var roof := bar(-26.0, 8.0, 26.0, 34.0, 6, PLASTER_A)
	piers("y", 34.0, -26.0, 26.0, 0.5, roof - 0.3, 4.4)
	rows("+y", 34.0, -25.0, 25.0, 12, 6)
	rows("-x", -26.0, 9.0, 33.0, 6, 6)
	rows("+x", 26.0, 9.0, 33.0, 6, 6)
	# Only the storeys that stand ABOVE the hall roof have a face to put a
	# window in; asking for six here put four rows of them in mid-air.
	rows("-y", 8.0, -25.0, 25.0, 12, 3, 12.6)
	roof_cap(-26.3, 7.7, 26.3, 34.3, roof, {}, false)
	# One long ramp up the hall's back, inside the footprint.
	climb(20.3, -34.0, 26.3, -12.0, 0.0, 12.3, "+y")
	landing(14.0, -12.0, 26.3, -6.0, 12.3)
	# A loading yard along the hall's other side. The kerbs are 0.4 m, under the
	# 0.45 m a body steps over: at the 1.2 m they started at, each one was a
	# 6 by 14 m island of navmesh on top of a block nothing could climb.
	box(Vector3(-26.0, -34.0, 0.0), Vector3(-20.0, -20.0, 0.4), FRAME)
	box(Vector3(-26.0, -16.0, 0.0), Vector3(-20.0, -4.0, 0.4), FRAME)
