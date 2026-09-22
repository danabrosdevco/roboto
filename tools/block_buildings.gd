extends SceneTree

# ─────────────────────────────────────────────
# BLOCK BUILDINGS — writes the TrenchBroom building blocks in maps/blocks/
# (building_*.map): solid buildings with walkable roofs and ramps up to them,
# no interiors, in the style of the hand-made blocks beside them — worldspawn
# brushes only, PSX concrete, chamfered plinths, wedge ramps, metal posts.
#
#   godot --headless --path . --script res://tools/block_buildings.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_buildings.gd -- maps/blocks --force
#
# THE .MAP FILES ARE THE SOURCE ONCE WRITTEN. Open them in TrenchBroom and
# change what you like; this tool never overwrites an existing file unless
# --force is given, because that would throw those edits away. It exists to
# make new variants, not to keep the old ones in sync.
#
# Sizes: every building fits a 32 × 24 m sketch-map lot (TerrainData.lots).
# Quake axes: X = depth (the front faces -X), Y = width, Z = up, ground at z 0,
# footprint centred on the origin. FuncGodot turns Quake (x, y, z) into Godot
# (y, z, x), so a building's Y side lies along a lot's local X — its 32 m side —
# and each fits inside X ±12, Y ±16. 32 units = 1 m (the map settings' scale).
#
# Walkability: ramps and roofs are for the squad, so every ramp is 30° or
# less, 2 m or wider, starts on open ground (never on a plinth's bank, which
# would leave a lip at its foot), and meets its landing and the roof flush.
# Plinth banks are 27°, as gentle as the checkpoint block's, so they can be
# walked onto; they are cut steep only where a ramp hugs the wall.
#
# Textures are only ones that already have a material in
# textures/PSX_Textures/, so building these never makes FuncGodot generate new
# material files.
# ─────────────────────────────────────────────

const UPM := 32.0

const FRAME := "PSX_Textures/concrete_tx_2"
const DECK := "PSX_Textures/concrete_tx_4"
const PLINTH := "PSX_Textures/concrete_wall_tx_4_1"
const METAL := "PSX_Textures/metal_floor_1"
const SHUTTER := "PSX_Textures/metal_wall_4"
const PLASTER_A := "PSX_Textures/concrete_wall_tx_1"
const PLASTER_B := "PSX_Textures/concrete_wall_tx_2"
const BRICK := "PSX_Textures/brick_wall_tx_4"
const INFILL := "PSX_Textures/concrete_tx_5"
const SCORCH := "PSX_Textures/concrete_6"
const RUBBLE := "PSX_Textures/concrete_3"

const SLAB := {"top": DECK, "side": FRAME, "bottom": FRAME}   # anything walked on
const STAIR := {"top": DECK, "side": FRAME, "bottom": FRAME}

var _brushes: Array = []
## Where the piece's no-collision brushes start, or -1 for none. See
## no_collision().
var _ghost_from := -1


func _initialize() -> void:
	var out_dir := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif out_dir == "":
			out_dir = a
		else:
			print("ignoring argument '%s'" % a)
	if out_dir == "":
		print("usage: godot --headless --path . --script res://tools/block_buildings.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not out_dir.begins_with("res://") and not out_dir.is_absolute_path():
		out_dir = "res://" + out_dir
	if not DirAccess.dir_exists_absolute(out_dir):
		print("FAIL  no such folder: %s" % out_dir)
		quit(1)
		return
	var made := {
		"building_house_small": _house_small,
		"building_house_terrace": _house_terrace,
		"building_shop_row": _shop_row,
		"building_apartment": _apartment,
		"building_warehouse": _warehouse,
		"building_compound": _compound,
		"building_ruin_shell": _ruin_shell,
		"building_ruin_low": _ruin_low,
	}
	var skipped := 0
	for name: String in made:
		var path := out_dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		_ghost_from = -1
		(made[name] as Callable).call()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		print("      %-24s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK BUILDINGS DONE%s" % ((" (%d skipped)" % skipped) if skipped > 0 else ""))
	quit()


# ── Brushes ──────────────────────────────────────────────────────────────────

## A convex brush from its vertices (metres) and faces (vertex indices, any
## winding): each face is turned to face outward from the brush's centre.
func brush(verts: Array, faces: Array, tex: Variant) -> void:
	# The centre of the snapped corners, not the snapped centre: on a brush one
	# unit thin, rounding the centre can land it on a face, and then which way
	# that face points is a coin toss.
	var c := Vector3.ZERO
	for v: Vector3 in verts:
		c += _snap(v)
	c /= verts.size()
	var out: Array = []
	for f: Array in faces:
		var poly: Array = []
		for i: int in f:
			poly.append(_snap(verts[i]))
		var n: Vector3 = ((poly[1] as Vector3) - (poly[0] as Vector3)).cross((poly[2] as Vector3) - (poly[0] as Vector3))
		var fc := Vector3.ZERO
		for p: Vector3 in poly:
			fc += p
		fc /= poly.size()
		if n.dot(fc - c) < 0.0:
			poly.reverse()
			n = -n
		out.append({"poly": poly, "n": n.normalized(), "tex": _pick(tex, n.normalized())})
	# A brush is the space inside every face's plane. If a vertex lies outside
	# one — a concave outline, or a face whose corners are not on one plane —
	# TrenchBroom and FuncGodot build something smaller than what was drawn,
	# silently. Say so, with where it is.
	for face: Dictionary in out:
		var p0: Vector3 = face.poly[0]
		var fn: Vector3 = face.n
		for v: Vector3 in verts:
			if (_snap(v) - p0).dot(fn) > 0.5:
				push_warning("brush %d near %s is not convex, or a face is not flat: it will build smaller than drawn" % [_brushes.size(), c / UPM])
				_brushes.append(out)
				return
	_brushes.append(out)


func _pick(tex: Variant, n: Vector3) -> String:
	if tex is String:
		return tex
	var d: Dictionary = tex
	if n.z > 0.7:
		return d.get("top", d.get("side", FRAME))
	if n.z < -0.7:
		return d.get("bottom", d.get("side", FRAME))
	return d.get("side", FRAME)


func _snap(v: Vector3) -> Vector3:
	return Vector3(roundf(v.x * UPM), roundf(v.y * UPM), roundf(v.z * UPM))


## Box between two corners.
func box(a: Vector3, b: Vector3, tex: Variant) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	# Thinner than a unit, both faces snap to the same grid line and the brush
	# builds as nothing at all — an empty collision shape and no mesh.
	var size := _snap(hi) - _snap(lo)
	if size.x < 1.0 or size.y < 1.0 or size.z < 1.0:
		push_warning("box at %s is thinner than one unit (1/32 m) and would build as nothing — skipped; make it thicker" % ((lo + hi) * 0.5))
		return
	_hexa([Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)],
			[lo.z, lo.z, lo.z, lo.z], [hi.z, hi.z, hi.z, hi.z], tex)


## Eight-vertex solid over a quad footprint: `bottom` and `top` heights per
## corner. Faces must come out planar — callers keep them so.
func _hexa(q: Array, bottom: Array, top: Array, tex: Variant) -> void:
	var v: Array = []
	for i in 4:
		v.append(Vector3(q[i].x, q[i].y, bottom[i]))
	for i in 4:
		v.append(Vector3(q[i].x, q[i].y, top[i]))
	brush(v, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], tex)


## Footprint corners ordered low-a, low-b, high-b, high-a for a slope that
## climbs toward `run` ("+x", "-x", "+y", "-y").
func _run_quad(x0: float, y0: float, x1: float, y1: float, run: String) -> Array:
	match run:
		"+x":
			return [Vector2(x0, y0), Vector2(x0, y1), Vector2(x1, y1), Vector2(x1, y0)]
		"-x":
			return [Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1), Vector2(x0, y0)]
		"+y":
			return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
		_:
			return [Vector2(x0, y1), Vector2(x1, y1), Vector2(x1, y0), Vector2(x0, y0)]


## Solid ramp: filled from `base` up to a surface climbing from z_low to
## z_high toward `run`. A ramp that starts at its base is a wedge.
func ramp(x0: float, y0: float, x1: float, y1: float, base: float, z_low: float, z_high: float, run: String, tex: Variant = STAIR) -> void:
	var q := _run_quad(x0, y0, x1, y1, run)
	if z_low - base > 0.01:
		_hexa(q, [base, base, base, base], [z_low, z_low, z_high, z_high], tex)
		return
	var v: Array = []
	for i in 4:
		v.append(Vector3(q[i].x, q[i].y, base))
	v.append(Vector3(q[2].x, q[2].y, z_high))
	v.append(Vector3(q[3].x, q[3].y, z_high))
	brush(v, [[0, 1, 2, 3], [2, 3, 5, 4], [0, 1, 4, 5], [1, 2, 4], [0, 3, 5]], tex)


## Sloped slab `thick` deep under a surface climbing from z_low to z_high.
func flight(x0: float, y0: float, x1: float, y1: float, z_low: float, z_high: float, run: String, thick: float, tex: Variant = STAIR) -> void:
	_hexa(_run_quad(x0, y0, x1, y1, run), [z_low - thick, z_low - thick, z_high - thick, z_high - thick], [z_low, z_low, z_high, z_high], tex)


## Chamfered base slab, like the blocks': the sides flare out `flare` metres
## on the way down. At the default 2 m that is a 27° bank, as gentle as the
## checkpoint slab's, so the top can be walked onto from the ground. `sides`
## overrides the flare per side ("-x", "+x", "-y", "+y") where a ramp hugs the
## wall and a wide bank would stand proud of its foot.
func plinth(x0: float, y0: float, x1: float, y1: float, z_bottom: float = -0.5, z_top: float = 0.5, flare: float = 2.0, tex: Variant = PLINTH, sides: Dictionary = {}) -> void:
	var fmx: float = sides.get("-x", flare)
	var fpx: float = sides.get("+x", flare)
	var fmy: float = sides.get("-y", flare)
	var fpy: float = sides.get("+y", flare)
	var v := [
		Vector3(x0 - fmx, y0 - fmy, z_bottom), Vector3(x1 + fpx, y0 - fmy, z_bottom),
		Vector3(x1 + fpx, y1 + fpy, z_bottom), Vector3(x0 - fmx, y1 + fpy, z_bottom),
		Vector3(x0, y0, z_top), Vector3(x1, y0, z_top), Vector3(x1, y1, z_top), Vector3(x0, y1, z_top)]
	brush(v, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], tex)


## Box turned `deg` degrees about its own vertical axis: rubble.
func chunk(centre: Vector3, size: Vector3, deg: float, tex: Variant = RUBBLE) -> void:
	var q: Array = []
	var r := deg_to_rad(deg)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := Vector2(c.x * size.x * 0.5, c.y * size.y * 0.5).rotated(r)
		q.append(Vector2(centre.x + p.x, centre.y + p.y))
	var z0 := centre.z
	var z1 := centre.z + size.z
	_hexa(q, [z0, z0, z0, z0], [z1, z1, z1, z1], tex)


func post(x: float, y: float, z0: float, z1: float, s: float = 0.25, tex: Variant = METAL) -> void:
	box(Vector3(x - s * 0.5, y - s * 0.5, z0), Vector3(x + s * 0.5, y + s * 0.5, z1), tex)


# ── Parts ────────────────────────────────────────────────────────────────────

## A straight wall along one side of a rectangle, cut by `gaps` ([from, to] in
## the along-coordinate). `across` is its thickness range.
func wall_run(axis: String, across: Vector2, a0: float, a1: float, z0: float, z1: float, gaps: Array = [], tex: Variant = FRAME) -> void:
	var cuts: Array = [a0]
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for g: Array in sorted:
		cuts.append(g[0])
		cuts.append(g[1])
	cuts.append(a1)
	for i in range(0, cuts.size(), 2):
		var s: float = cuts[i]
		var e: float = cuts[i + 1]
		if e - s < 0.05:
			continue
		if axis == "x":
			box(Vector3(across.x, s, z0), Vector3(across.y, e, z1), tex)
		else:
			box(Vector3(s, across.x, z0), Vector3(e, across.y, z1), tex)


## Roof upstand round a rectangle, `t` thick and `h` tall above `z`.
func parapet(x0: float, y0: float, x1: float, y1: float, z: float, h: float = 0.75, t: float = 0.25, gaps: Dictionary = {}, tex: Variant = FRAME) -> void:
	wall_run("x", Vector2(x0, x0 + t), y0, y1, z, z + h, gaps.get("-x", []), tex)
	wall_run("x", Vector2(x1 - t, x1), y0, y1, z, z + h, gaps.get("+x", []), tex)
	wall_run("y", Vector2(y0, y0 + t), x0 + t, x1 - t, z, z + h, gaps.get("-y", []), tex)
	wall_run("y", Vector2(y1 - t, y1), x0 + t, x1 - t, z, z + h, gaps.get("+y", []), tex)


## A shuttered window (or door) on a wall face: the shutter stands proud of
## the wall, with a sill under it and a lintel over it.
func window(face: String, wall: float, along: float, z0: float, w: float, h: float, trim: bool = true, tex: Variant = SHUTTER) -> void:
	var out := -1.0 if face.begins_with("-") else 1.0
	var on_x := face.ends_with("x")
	_face_box(on_x, wall, wall + out * 0.125, along - w * 0.5, along + w * 0.5, z0, z0 + h, tex)
	if trim:
		_face_box(on_x, wall, wall + out * 0.25, along - w * 0.5 - 0.125, along + w * 0.5 + 0.125, z0 - 0.125, z0, FRAME)
		_face_box(on_x, wall, wall + out * 0.1875, along - w * 0.5 - 0.125, along + w * 0.5 + 0.125, z0 + h, z0 + h + 0.25, FRAME)


func _face_box(on_x: bool, d0: float, d1: float, a0: float, a1: float, z0: float, z1: float, tex: Variant) -> void:
	if on_x:
		box(Vector3(d0, a0, z0), Vector3(d1, a1, z1), tex)
	else:
		box(Vector3(a0, d0, z0), Vector3(a1, d1, z1), tex)


## Metal railing along a straight run: posts every ~2.5 m and a top bar,
## following a surface that climbs from z_low to z_high toward `run`.
## `line` is the rail's position across the run; a0..a1 its extent along it.
func rail(axis: String, line: float, a0: float, a1: float, z_low: float, z_high: float, run_positive: bool = true) -> void:
	var length := a1 - a0
	var count := maxi(2, int(ceil(length / 2.5)) + 1)
	for i in count:
		var t := float(i) / float(count - 1)
		var a := lerpf(a0 + 0.1, a1 - 0.1, t)
		var surf := lerpf(z_low, z_high, (a - a0) / length if run_positive else (a1 - a) / length)
		if axis == "x":
			post(line, a, surf - 0.25, surf + 1.0, 0.125)
		else:
			post(a, line, surf - 0.25, surf + 1.0, 0.125)
	var run := ("+" if run_positive else "-") + ("y" if axis == "x" else "x")
	if axis == "x":
		flight(line - 0.0625, a0, line + 0.0625, a1, z_low + 1.125, z_high + 1.125, run, 0.125, METAL)
	else:
		flight(a0, line - 0.0625, a1, line + 0.0625, z_low + 1.125, z_high + 1.125, run, 0.125, METAL)


## Solid concrete balustrade along a sloped run: sits on the surface.
func upstand(axis: String, across: Vector2, a0: float, a1: float, z_low: float, z_high: float, run_positive: bool = true, h: float = 1.0) -> void:
	var run := ("+" if run_positive else "-") + ("y" if axis == "x" else "x")
	if axis == "x":
		flight(across.x, a0, across.y, a1, z_low + h, z_high + h, run, h + 0.25, FRAME)
	else:
		flight(a0, across.x, a1, across.y, z_low + h, z_high + h, run, h + 0.25, FRAME)


func water_tank(x: float, y: float, z: float) -> void:
	for c in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)]:
		post(x + c.x, y + c.y, z, z + 1.25, 0.2)
	box(Vector3(x - 0.875, y - 0.875, z + 1.25), Vector3(x + 0.875, y + 0.875, z + 2.5), METAL)


# ── Buildings ────────────────────────────────────────────────────────────────

## One storey, a solid ramp up the back to a roof with a parapet.
func _house_small() -> void:
	plinth(-5.0, -6.5, 5.0, 6.5)
	box(Vector3(-4.5, -6.0, 0.5), Vector3(4.5, 6.0, 4.5), PLASTER_B)
	box(Vector3(-4.75, -6.25, 4.5), Vector3(4.75, 6.25, 4.75), SLAB)
	parapet(-4.75, -6.25, 4.75, 6.25, 4.75, 0.75, 0.25, {"+x": [[1.5, 4.25]]})
	window("-x", -4.5, 0.0, 0.5, 1.5, 2.25, false)
	box(Vector3(-5.5, -1.25, 2.875), Vector3(-4.5, 1.25, 3.125), FRAME)
	window("-x", -4.5, -3.5, 1.5, 1.25, 1.25)
	window("-x", -4.5, 3.5, 1.5, 1.25, 1.25)
	window("-y", -6.0, 0.0, 1.5, 1.25, 1.25)
	window("+y", 6.0, -1.5, 1.5, 1.25, 1.25)
	window("+y", 6.0, 2.0, 1.5, 1.25, 1.25)
	# Up the back: 10.5 m of ramp to the roof at about 24°, then a landing.
	ramp(4.75, -9.0, 6.75, 1.5, 0.0, 0.0, 4.75, "+y")
	box(Vector3(4.5, 1.5, 0.0), Vector3(6.75, 4.25, 4.75), SLAB)
	rail("x", 6.625, -9.0, 1.5, 0.0, 4.75)
	rail("x", 6.625, 1.5, 4.25, 4.75, 4.75)
	rail("y", 4.125, 4.75, 6.75, 4.75, 4.75)


## Two storeys over a one-storey annex: a ramp to the annex terrace, a second
## ramp from the terrace to the main roof.
func _house_terrace() -> void:
	plinth(-5.5, -8.5, 5.5, 8.5, -0.5, 0.5, 2.0, PLINTH, {"-y": 0.5})   # ramp 1 hugs the -y end
	# Annex, and its roof terrace.
	box(Vector3(-5.0, -8.0, 0.5), Vector3(5.0, -1.0, 4.0), PLASTER_A)
	box(Vector3(-5.25, -8.25, 4.0), Vector3(5.25, -1.0, 4.25), SLAB)
	wall_run("x", Vector2(-5.25, -5.0), -8.25, -1.0, 4.25, 5.0)
	wall_run("x", Vector2(5.0, 5.25), -8.25, -1.0, 4.25, 5.0)
	wall_run("y", Vector2(-8.25, -8.0), -5.0, 5.0, 4.25, 5.0, [[-5.0, -3.0]])
	# Main block.
	box(Vector3(-5.0, -1.0, 0.5), Vector3(5.0, 8.0, 7.5), PLASTER_A)
	box(Vector3(-5.2, -1.0, 4.0), Vector3(5.2, 8.2, 4.25), FRAME)
	box(Vector3(-5.25, -1.25, 7.5), Vector3(5.25, 8.25, 7.75), SLAB)
	parapet(-5.25, -1.25, 5.25, 8.25, 7.75, 0.75, 0.25, {"-y": [[3.0, 5.0]]})
	water_tank(2.25, 5.75, 7.75)
	# Openings.
	window("-x", -5.0, -4.5, 0.5, 1.5, 2.25, false)
	box(Vector3(-6.0, -5.5, 2.875), Vector3(-5.0, -3.5, 3.125), FRAME)
	window("-x", -5.0, -2.25, 1.5, 1.25, 1.25)
	for y in [1.5, 5.5]:
		window("-x", -5.0, y, 1.5, 1.25, 1.25)
		window("-x", -5.0, y, 5.0, 1.25, 1.25)
		window("+x", 5.0, y, 1.5, 1.25, 1.25)
		window("+x", 5.0, y, 5.0, 1.25, 1.25)
	for x in [-2.5, 2.5]:
		window("+y", 8.0, x, 1.5, 1.25, 1.25)
		window("+y", 8.0, x, 5.0, 1.25, 1.25)
	window("+x", 5.0, -4.5, 1.5, 1.25, 1.25)
	# Ground to terrace: along the annex's end wall, clear of the plinth so
	# its foot starts on open ground.
	ramp(-3.0, -11.0, 6.0, -9.0, 0.0, 0.0, 4.25, "-x")
	box(Vector3(-5.25, -11.0, 0.0), Vector3(-3.0, -8.25, 4.25), SLAB)
	rail("y", -10.875, -3.0, 6.0, 0.0, 4.25, false)
	rail("y", -10.875, -5.25, -3.0, 4.25, 4.25)
	rail("x", -5.125, -11.0, -8.25, 4.25, 4.25)
	# Terrace to roof: against the main block's end wall.
	ramp(-4.5, -3.0, 3.0, -1.0, 4.25, 4.25, 7.75, "+x")
	box(Vector3(3.0, -3.0, 4.25), Vector3(5.0, -1.25, 7.75), SLAB)
	rail("y", -2.875, -4.5, 3.0, 4.25, 7.75)
	rail("y", -2.875, 3.0, 5.0, 7.75, 7.75)


## A two-storey row of shops: shuttered fronts under an awning, brick above,
## a long ramp up the back to the roof.
func _shop_row() -> void:
	plinth(-5.0, -12.5, 5.0, 12.5)
	box(Vector3(-4.5, -12.0, 0.5), Vector3(4.5, 12.0, 7.5), BRICK)
	for y in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		var y0 := clampf(y - 0.25, -12.0, 11.5)
		box(Vector3(-4.75, y0, 0.5), Vector3(-4.5, y0 + 0.5, 3.75), FRAME)
	for y in [-9.0, -3.0, 3.0, 9.0]:
		window("-x", -4.5, y, 0.5, 5.0, 2.75, false)
		window("+x", 4.5, y, 1.5, 1.25, 1.25)
		for dy in [-1.25, 1.25]:
			window("-x", -4.5, y + dy, 5.0, 1.0, 1.25)
		window("+x", 4.5, y, 5.0, 1.25, 1.25)
	box(Vector3(-4.75, -12.0, 3.25), Vector3(-4.5, 12.0, 3.75), FRAME)
	box(Vector3(-6.0, -12.0, 3.75), Vector3(-4.5, 12.0, 4.0), FRAME)
	box(Vector3(-4.7, -12.2, 4.0), Vector3(4.7, 12.2, 4.25), FRAME)
	window("-y", -12.0, 0.0, 5.0, 1.25, 1.25)
	window("+y", 12.0, 0.0, 5.0, 1.25, 1.25)
	box(Vector3(-4.75, -12.25, 7.5), Vector3(4.75, 12.25, 7.75), SLAB)
	parapet(-4.75, -12.25, 4.75, 12.25, 7.75, 1.0, 0.25, {"+x": [[-2.75, -0.25]]})
	box(Vector3(-2.5, 4.0, 7.75), Vector3(-1.0, 5.5, 8.75), METAL)
	box(Vector3(-2.5, 7.0, 7.75), Vector3(-1.0, 8.5, 8.75), METAL)
	# 14 m of ramp at about 29°, then a landing onto the roof.
	ramp(4.75, -0.25, 6.75, 14.0, 0.0, 0.0, 7.75, "-y")
	box(Vector3(4.5, -2.75, 0.0), Vector3(6.75, -0.25, 7.75), SLAB)
	upstand("x", Vector2(6.5, 6.75), -0.25, 14.0, 7.75, 0.0)
	box(Vector3(6.5, -2.75, 7.75), Vector3(6.75, -0.25, 8.75), FRAME)
	box(Vector3(4.75, -2.75, 7.75), Vector3(6.5, -2.5, 8.75), FRAME)


## Four storeys of concrete frame with shuttered bays, and a switchback ramp
## tower up the end wall to the roof: two solid flights, two on metal posts.
func _apartment() -> void:
	# The plinth stops at the pillar line on the tower side: its chamfer would
	# otherwise stand proud of the first flight's foot.
	plinth(-6.25, -8.25, 6.25, 7.75, -0.5, 0.5, 2.0, PLINTH, {"+y": 0.25})
	box(Vector3(-5.5, -7.5, 0.5), Vector3(5.5, 7.5, 14.75), INFILL)
	for z in [4.0, 7.5, 11.0]:
		box(Vector3(-5.75, -7.75, z), Vector3(5.75, 7.75, z + 0.25), FRAME)
	box(Vector3(-5.75, -7.75, 14.75), Vector3(5.75, 7.75, 15.0), SLAB)
	for y in [-7.5, -3.75, 0.0, 3.75, 7.5]:
		var y0 := clampf(y - 0.25, -7.75, 7.25)
		box(Vector3(-5.75, y0, 0.5), Vector3(-5.25, y0 + 0.5, 14.75), FRAME)
		box(Vector3(5.25, y0, 0.5), Vector3(5.75, y0 + 0.5, 14.75), FRAME)
	for x in [-2.0, 2.0]:
		box(Vector3(x - 0.25, -7.75, 0.5), Vector3(x + 0.25, -7.25, 14.75), FRAME)
		box(Vector3(x - 0.25, 7.25, 0.5), Vector3(x + 0.25, 7.75, 14.75), FRAME)
	for z0 in [0.5, 4.25, 7.75, 11.25]:
		for y in [-5.625, -1.875, 1.875, 5.625]:
			if z0 == 0.5 and y == -1.875:
				window("-x", -5.5, y, 0.5, 2.0, 2.5, false)   # the way in
			else:
				window("-x", -5.5, y, z0 + 1.0, 2.0, 1.5, false)
			window("+x", 5.5, y, z0 + 1.0, 2.0, 1.5, false)
		for x in [-3.75, 0.0, 3.75]:
			window("-y", -7.5, x, z0 + 1.0, 1.5, 1.5, false)
	box(Vector3(-7.0, -3.0, 3.25), Vector3(-5.5, -0.75, 3.5), FRAME)
	# Roof: parapet, stair head, tank.
	parapet(-5.75, -7.75, 5.75, 7.75, 15.0, 1.0, 0.25, {"+y": [[-5.5, -4.0]]})
	box(Vector3(1.0, -6.0, 15.0), Vector3(4.0, -3.0, 17.5), SLAB)
	window("-x", 1.0, -4.5, 15.0, 1.25, 2.0, false)
	water_tank(-2.25, 2.75, 15.0)
	# Ramp tower: strip A (y 8–10) and strip B (y 10.25–12.25), flights along
	# X between x -4 and 4, 3.75 m a flight; landings at both ends.
	ramp(-4.0, 8.0, 4.0, 10.0, 0.0, 0.0, 3.75, "+x")          # 1: A, solid
	ramp(-4.0, 10.25, 4.0, 12.25, 0.0, 3.75, 7.5, "-x")       # 2: B, solid
	flight(-4.0, 8.0, 4.0, 10.0, 7.5, 11.25, "+x", 0.3)       # 3: A, over 1
	flight(-4.0, 10.25, 4.0, 12.25, 11.25, 15.0, "-x", 0.3)   # 4: B, over 2
	box(Vector3(4.0, 8.0, 3.5), Vector3(6.5, 12.25, 3.75), SLAB)
	box(Vector3(-6.5, 8.0, 7.25), Vector3(-4.0, 12.25, 7.5), SLAB)
	box(Vector3(4.0, 8.0, 11.0), Vector3(6.5, 12.25, 11.25), SLAB)
	box(Vector3(-6.5, 7.75, 14.75), Vector3(-4.0, 12.25, 15.0), SLAB)
	for y in [8.25, 12.0]:
		post(6.25, y, 0.0, 3.5)
		post(6.25, y, 3.75, 11.0)
		post(-6.25, y, 0.0, 7.25)
		post(-6.25, y, 7.5, 14.75)
	# Flight 3 stands on flight 1, flight 4 on flight 2.
	for x in [-2.0, 0.0, 2.0]:
		var t: float = (x + 4.0) / 8.0
		for y in [8.125, 9.875]:
			post(x, y, 3.75 * t - 0.1, 7.5 + 3.75 * t - 0.2)
		for y in [10.375, 12.125]:
			post(x, y, 3.75 + 3.75 * (1.0 - t) - 0.1, 11.25 + 3.75 * (1.0 - t) - 0.2)
	# Balustrades wherever a flight or landing drops away.
	upstand("y", Vector2(9.8, 10.0), -4.0, 4.0, 7.5, 11.25, false)
	upstand("y", Vector2(10.25, 10.45), -4.0, 4.0, 11.25, 15.0, true)
	upstand("y", Vector2(12.05, 12.25), -4.0, 4.0, 11.25, 15.0, true)
	upstand("y", Vector2(12.05, 12.25), -4.0, 4.0, 3.75, 7.5, true)
	upstand("y", Vector2(10.25, 10.45), -4.0, 4.0, 3.75, 7.5, true)
	for z in [3.75, 11.25]:
		box(Vector3(6.3, 8.0, z), Vector3(6.5, 12.25, z + 1.0), FRAME)
		box(Vector3(4.0, 12.05, z), Vector3(6.3, 12.25, z + 1.0), FRAME)
	for z in [7.5, 15.0]:
		box(Vector3(-6.5, 8.0, z), Vector3(-6.3, 12.25, z + 1.0), FRAME)
		box(Vector3(-6.3, 12.05, z), Vector3(-4.0, 12.25, z + 1.0), FRAME)


## Corrugated hall on a concrete frame, with a loading dock and a ramp up the
## back to the roof.
func _warehouse() -> void:
	plinth(-7.5, -11.5, 7.5, 11.5, -0.5, 0.5, 2.0, PLINTH, {"-x": 0.5})   # the dock ramp hugs -x
	box(Vector3(-7.0, -11.0, 0.5), Vector3(7.0, 11.0, 7.0), SHUTTER)
	box(Vector3(-7.125, -11.125, 0.5), Vector3(7.125, 11.125, 1.5), FRAME)
	for y in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		var y0 := clampf(y - 0.25, -11.25, 10.75)
		box(Vector3(-7.25, y0, 0.5), Vector3(-6.75, y0 + 0.5, 7.0), FRAME)
		box(Vector3(6.75, y0, 0.5), Vector3(7.25, y0 + 0.5, 7.0), FRAME)
	for side in [-1.0, 1.0]:
		box(Vector3(-0.25, side * 11.25 - 0.25, 0.5), Vector3(0.25, side * 11.25 + 0.25, 7.0), FRAME)
	box(Vector3(-7.25, -11.25, 6.5), Vector3(7.25, 11.25, 7.0), FRAME)
	box(Vector3(-7.25, -11.25, 7.0), Vector3(7.25, 11.25, 7.25), SLAB)
	parapet(-7.25, -11.25, 7.25, 11.25, 7.25, 0.5, 0.25, {"+x": [[2.0, 4.5]]})
	box(Vector3(-2.0, -6.0, 7.25), Vector3(0.0, -4.0, 8.25), METAL)
	box(Vector3(-2.0, 4.0, 7.25), Vector3(0.0, 6.0, 8.25), METAL)
	# Dock doors, the dock, its ramp, and a canopy over it.
	for y in [-2.75, 2.75]:
		window("-x", -7.125, y, 1.25, 4.5, 4.25, false, METAL)
		box(Vector3(-7.375, y - 2.5, 5.5), Vector3(-7.125, y + 2.5, 5.75), FRAME)
	box(Vector3(-10.5, -6.0, 0.0), Vector3(-7.0, 6.0, 1.25), SLAB)
	ramp(-10.5, 6.0, -8.0, 11.0, 0.0, 0.0, 1.25, "-y")   # beside the plinth, not on it
	for y in [-3.0, 3.0]:
		box(Vector3(-10.75, y - 0.4, 0.4), Vector3(-10.5, y + 0.4, 1.1), METAL)
	box(Vector3(-10.5, -6.5, 5.75), Vector3(-7.25, 6.5, 6.0), FRAME)
	# Up the back: 15 m of ramp at about 26°, starting past the plinth.
	ramp(7.25, -13.0, 9.25, 2.0, 0.0, 0.0, 7.25, "+y")
	box(Vector3(7.0, 2.0, 0.0), Vector3(9.25, 4.5, 7.25), SLAB)
	rail("x", 9.125, -13.0, 2.0, 0.0, 7.25)
	rail("x", 9.125, 2.0, 4.5, 7.25, 7.25)
	rail("y", 4.375, 7.25, 9.25, 7.25, 7.25)


## A walled courtyard: a two-storey house in one corner, an outbuilding in
## the other, a ramp to the outbuilding roof and a flight on posts from there
## to the house roof.
func _compound() -> void:
	# Perimeter wall with a coping, gate posts and gate leaves (one open).
	wall_run("x", Vector2(-10.0, -9.5), -14.0, 14.0, 0.0, 3.0, [[-2.0, 2.0]], PLASTER_B)
	wall_run("x", Vector2(9.5, 10.0), -14.0, 14.0, 0.0, 3.0, [], PLASTER_B)
	wall_run("y", Vector2(-14.0, -13.5), -9.5, 9.5, 0.0, 3.0, [], PLASTER_B)
	wall_run("y", Vector2(13.5, 14.0), -9.5, 9.5, 0.0, 3.0, [], PLASTER_B)
	wall_run("x", Vector2(-10.125, -9.375), -14.125, 14.125, 3.0, 3.25, [[-2.75, 2.75]])
	wall_run("x", Vector2(9.375, 10.125), -14.125, 14.125, 3.0, 3.25)
	wall_run("y", Vector2(-14.125, -13.375), -9.375, 9.375, 3.0, 3.25)
	wall_run("y", Vector2(13.375, 14.125), -9.375, 9.375, 3.0, 3.25)
	for y in [-2.75, 2.0]:
		box(Vector3(-10.25, y, 0.0), Vector3(-9.25, y + 0.75, 3.75), FRAME)
	box(Vector3(-9.875, -2.0, 0.125), Vector3(-9.625, 0.0, 2.75), SHUTTER)
	box(Vector3(-9.625, 1.75, 0.125), Vector3(-7.625, 2.0, 2.75), SHUTTER)
	# House.
	plinth(1.0, 3.0, 9.5, 13.5, -0.5, 0.5, 0.25)
	box(Vector3(1.5, 3.5, 0.5), Vector3(9.5, 13.5, 7.5), PLASTER_A)
	box(Vector3(1.3, 3.3, 4.0), Vector3(9.5, 13.5, 4.25), FRAME)
	box(Vector3(1.25, 3.25, 7.5), Vector3(9.75, 13.75, 7.75), SLAB)
	parapet(1.25, 3.25, 9.75, 13.75, 7.75, 0.75, 0.25, {"-y": [[7.0, 9.0]]})
	window("-x", 1.5, 8.0, 0.5, 1.5, 2.25, false)
	box(Vector3(0.5, 7.0, 2.875), Vector3(1.5, 9.0, 3.125), FRAME)
	for y in [5.5, 11.0]:
		window("-x", 1.5, y, 1.5, 1.25, 1.25)
		window("-x", 1.5, y, 5.0, 1.25, 1.25)
	window("-x", 1.5, 8.0, 5.0, 1.25, 1.25)
	window("-y", 3.5, 4.0, 1.5, 1.25, 1.25)
	window("-y", 3.5, 4.0, 5.0, 1.25, 1.25)
	# Outbuilding.
	plinth(3.0, -13.5, 9.5, -7.5, -0.5, 0.5, 0.25)
	box(Vector3(3.0, -13.5, 0.5), Vector3(9.5, -7.5, 4.0), BRICK)
	box(Vector3(2.75, -13.5, 4.0), Vector3(9.5, -7.25, 4.25), SLAB)
	wall_run("x", Vector2(2.75, 3.0), -13.5, -7.25, 4.25, 5.0)
	window("-x", 3.0, -10.5, 0.5, 1.5, 2.25, false)
	# Courtyard to outbuilding roof, then up to the house roof on posts.
	ramp(-3.0, -7.25, 6.0, -5.25, 0.0, 0.0, 4.25, "+x")
	box(Vector3(6.0, -7.25, 0.0), Vector3(9.5, -5.25, 4.25), SLAB)
	rail("y", -5.375, -3.0, 6.0, 0.0, 4.25)
	flight(7.0, -5.25, 9.0, 3.25, 4.25, 7.75, "+y", 0.3)
	for y in [-3.0, -0.5, 2.0]:
		var zb: float = 4.25 + 3.5 * (y + 5.25) / 8.5 - 0.3
		post(7.125, y, 0.0, zb + 0.1)
		post(8.875, y, 0.0, zb + 0.1)
	rail("x", 7.0625, -5.25, 3.25, 4.25, 7.75)
	rail("x", 8.9375, -5.25, 3.25, 4.25, 7.75)
	# A concrete barrier in the yard, clear of the ramp's foot.
	box(Vector3(-7.5, 4.0, 0.0), Vector3(-5.5, 9.0, 1.25), FRAME)


## A bombed two-storey frame: stumps of wall and pillar, a window hole, one
## corner of floor still up, and a fallen slab to climb to it.
func _ruin_shell() -> void:
	plinth(-6.5, -8.5, 6.5, 8.5)
	# Pillars, broken off at different heights.
	for p in [[-6.0, -8.0, 7.5], [6.0, -8.0, 4.5], [6.0, 8.0, 7.0], [-6.0, 8.0, 2.5], [-6.0, 0.0, 5.0], [6.0, 0.0, 4.0], [0.0, 8.0, 4.0]]:
		box(Vector3(p[0] - 0.25, p[1] - 0.25, 0.5), Vector3(p[0] + 0.25, p[1] + 0.25, p[2]), FRAME)
	# Back wall, stepping down.
	for s in [[-8.0, -5.0, 4.0, PLASTER_B], [-5.0, -2.0, 3.0, SCORCH], [-2.0, 0.0, 1.75, PLASTER_B], [0.0, 2.0, 1.0, SCORCH]]:
		box(Vector3(5.75, s[0], 0.5), Vector3(6.25, s[1], s[2]), s[3])
	# Front wall: two stumps and a gap blown through the middle.
	box(Vector3(-6.25, -8.0, 0.5), Vector3(-5.75, -6.0, 3.5), PLASTER_B)
	box(Vector3(-6.25, -6.0, 0.5), Vector3(-5.75, -4.0, 2.0), SCORCH)
	box(Vector3(-6.25, 4.0, 0.5), Vector3(-5.75, 8.0, 3.0), PLASTER_B)
	# End wall, still two storeys at one side, with a window hole.
	box(Vector3(-6.0, -8.25, 0.5), Vector3(-3.5, -7.75, 7.0), PLASTER_B)
	box(Vector3(-3.5, -8.25, 0.5), Vector3(-1.5, -7.75, 1.5), PLASTER_B)
	box(Vector3(-3.5, -8.25, 3.0), Vector3(-1.5, -7.75, 6.0), SCORCH)
	box(Vector3(-1.5, -8.25, 0.5), Vector3(1.0, -7.75, 5.5), PLASTER_B)
	box(Vector3(1.0, -8.25, 0.5), Vector3(3.0, -7.75, 2.5), SCORCH)
	box(Vector3(-2.0, 7.75, 0.5), Vector3(6.0, 8.25, 1.25), RUBBLE)
	# What is left of the first floor, and the slab that fell off it.
	box(Vector3(1.0, 2.0, 4.0), Vector3(6.25, 8.25, 4.3), SLAB)
	box(Vector3(2.5, -1.0, 4.0), Vector3(6.25, 2.0, 4.3), SLAB)
	flight(-5.0, 3.0, 1.0, 7.0, 0.3, 4.3, "+x", 0.3)
	box(Vector3(-6.25, -8.25, 7.25), Vector3(-3.5, -5.5, 7.5), SLAB)
	# Rubble.
	ramp(3.0, -7.5, 5.75, -2.0, 0.5, 0.5, 2.0, "+x", RUBBLE)
	ramp(-8.0, -3.0, -6.25, 1.0, 0.0, 0.0, 1.0, "+x", RUBBLE)
	chunk(Vector3(-2.0, -3.0, 0.5), Vector3(1.5, 1.0, 0.75), 17.0)
	chunk(Vector3(-3.5, 1.5, 0.5), Vector3(1.25, 1.25, 1.0), 38.0, SCORCH)
	chunk(Vector3(2.75, 4.5, 0.5), Vector3(1.0, 1.5, 0.6), 61.0)
	chunk(Vector3(-7.5, 3.0, 0.0), Vector3(1.25, 0.75, 0.6), 24.0)


## One storey of broken walls round a roof slab that came down: it leans on
## the back wall and makes a ramp to look over it.
func _ruin_low() -> void:
	plinth(-5.0, -6.5, 5.0, 6.5)
	for s in [[-6.0, -2.0, 3.5, PLASTER_A], [-2.0, 1.5, 2.0, SCORCH], [1.5, 6.0, 3.0, PLASTER_A]]:
		box(Vector3(3.5, s[0], 0.5), Vector3(4.0, s[1], s[2]), s[3])
	box(Vector3(-4.0, -6.0, 0.5), Vector3(0.0, -5.5, 2.5), PLASTER_A)
	box(Vector3(0.0, -6.0, 0.5), Vector3(3.5, -5.5, 1.5), SCORCH)
	box(Vector3(0.0, 5.5, 0.5), Vector3(3.5, 6.0, 1.5), PLASTER_A)
	# A door frame still standing on the front line.
	for y in [-1.0, 1.0]:
		box(Vector3(-4.25, y - 0.25, 0.5), Vector3(-3.75, y + 0.25, 3.0), FRAME)
	box(Vector3(-4.25, -1.25, 3.0), Vector3(-3.75, 1.25, 3.5), FRAME)
	box(Vector3(-4.25, -6.0, 0.5), Vector3(-3.75, -3.5, 1.25), PLASTER_A)
	# The roof, fallen against the back wall.
	flight(-3.5, -3.0, 3.5, 2.0, 0.55, 3.25, "+x", 0.3)
	ramp(-3.0, 2.5, 1.0, 5.25, 0.5, 0.5, 1.5, "+y", RUBBLE)
	chunk(Vector3(-1.5, -4.0, 0.5), Vector3(1.5, 1.0, 0.8), 28.0)
	chunk(Vector3(-5.75, 3.0, 0.0), Vector3(1.0, 1.25, 0.6), 52.0)
	chunk(Vector3(1.5, 3.75, 1.4), Vector3(1.0, 0.75, 0.5), 11.0, SCORCH)


# ── Output ───────────────────────────────────────────────────────────────────

## Everything built after this call builds with NO collision: the brushes go
## into a func_detail_illusionary entity instead of worldspawn, so FuncGodot
## gives them a mesh and no collision shape.
##
## For ground detail the squad should walk over rather than into. Rail track is
## the case that forced it: 0.35 m of rail and sleeper is higher than the 0.25 m
## an agent climbs, so every track baked as a wall and cut the yard's navmesh
## into strips. Nothing tall belongs in here — a wall with no collision is a
## hole the squad walks through.
func no_collision() -> void:
	_ghost_from = _brushes.size()


func _map_text() -> String:
	var solid := _brushes.size() if _ghost_from < 0 else _ghost_from
	var lines := PackedStringArray(["// Game: Roboto", "// Format: Valve", "// entity 0", "{",
			"\"mapversion\" \"220\"", "\"wad\" \"\"", "\"classname\" \"worldspawn\""])
	for b in range(0, solid):
		lines.append_array(_brush_text(b))
	lines.append("}")
	if solid < _brushes.size():
		lines.append_array(["// entity 1", "{", "\"classname\" \"func_detail_illusionary\""])
		for b in range(solid, _brushes.size()):
			lines.append_array(_brush_text(b))
		lines.append("}")
	return "\n".join(lines) + "\n"


func _brush_text(b: int) -> PackedStringArray:
	var lines := PackedStringArray(["// brush %d" % b, "{"])
	for face: Dictionary in _brushes[b]:
		var p: Array = face.poly
		var n: Vector3 = face.n
		var u: Vector3
		var v: Vector3
		if absf(n.z) > 0.999:
			u = Vector3(signf(n.z), 0, 0)
			v = Vector3(0, -1, 0)
		else:
			u = Vector3(0, 0, 1).cross(n).normalized()
			v = u.cross(n).normalized()
		# Plane points as FuncGodot and TrenchBroom read them: the normal is
		# (p2 - p0) × (p1 - p0), so an outward-wound face goes in as v0 v2 v1.
		# "name@0.3" asks for a texture scale other than 1: fine detail such
		# as solar cells, which at 8 m a repeat would be the size of doors.
		var tex: String = face.tex
		var scale := "1 1"
		var at := tex.find("@")
		if at >= 0:
			scale = "%s %s" % [tex.substr(at + 1), tex.substr(at + 1)]
			tex = tex.substr(0, at)
		lines.append("%s %s %s %s [ %s 0 ] [ %s 0 ] 0 %s" % [_pt(p[0]), _pt(p[2]), _pt(p[1]), tex, _axis(u), _axis(v), scale])
	lines.append("}")
	return lines


func _pt(v: Vector3) -> String:
	return "( %d %d %d )" % [int(v.x), int(v.y), int(v.z)]


func _axis(v: Vector3) -> String:
	return "%s %s %s" % [_num(v.x), _num(v.y), _num(v.z)]


func _num(f: float) -> String:
	if absf(f - roundf(f)) < 1e-9:
		return str(int(roundf(f)))
	return String.num(f, 6)


func _extent_text() -> String:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for b: Array in _brushes:
		for face: Dictionary in b:
			for p: Vector3 in face.poly:
				lo = lo.min(p)
				hi = hi.max(p)
	return "x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f m" % [lo.x / UPM, hi.x / UPM, lo.y / UPM, hi.y / UPM, lo.z / UPM, hi.z / UPM]
