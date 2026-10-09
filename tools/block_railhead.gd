extends "res://tools/block_buildings.gd"

# ─────────────────────────────────────────────
# BLOCK RAILHEAD — the pieces of the armoured-train home base: seven cars and
# the bed they stand on.
#
#   maps/blocks/railhead/railhead_*.map
#
#   godot --headless --path . --script res://tools/block_railhead.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_railhead.gd -- maps/blocks --force [names]
#
# THE FICTION decided the plan. A machine intelligence copied a doctrine manual
# and built a headquarters that moves. Everything is the right shape and the
# wrong size for the only person who will ever be in it: nothing here is built
# for a 1.7 m drone, so nothing is at 1.7 m. No console, no seat, no handrail.
# Lamps hang at 3.1 m (a Walker's working height), so the player's altitude is
# the dim band in every car.
#
# THE ARITHMETIC THAT DECIDED EVERY DIMENSION, because the navmesh will not
# protect a Walker:
#
#   - The baker erodes every walkable edge by agent_radius = 0.5 m. A passage
#     under 1.0 m clear bakes NOTHING. A passage at 2.0 m bakes a 1.0 m ribbon.
#   - A Walker is 1.7 m wide and 3.0 m tall (walker.tscn: capsule r 0.85, h 3.0)
#     and Godot has no per-agent path clearance, so the baker will route one
#     down anything that shows a ribbon. THE GEOMETRY must refuse it.
#   - So: a corridor is >= 3.0 m clear (a Walker with 0.65 m each side, or two
#     1.0 m soldiers passing). A doorway is >= 2.2 m clear and >= 3.0 m high.
#     Nothing walkable is built between 1.0 m and 2.2 m. _audit() measures all
#     of it from the brushes and refuses to write a piece that fails.
#
# WHY THE CAR IS 9.0 m WIDE INSIDE, not the 6.0 m the brief proposed: at 6.0 a
# 3.0 m lane leaves 1.5 m each side, and a repair bay 1.5 m deep cannot hold a
# 1.7 m Walker at all. 9.0 gives a 3.0 m lane and a 3.0 m zone each side: bay
# depth for a Walker with 0.65 m to spare, rack depth with room to pass. It is
# wider than any real train, which is correct.
#
# AXES. Quake (x, y, z) is Godot (y, z, x). A car is built ALONG MAP X, so it
# runs along Godot Z. Map +X is the FRONT, toward the locomotive; map -X is the
# REAR, toward the platform. Every car is the same way round.
#
# FLOOR is z = 0, dead flat, one height in every car. The only change of level
# in the whole base is the boarding ramp, 1.2 m over 7.5 m (1 in 6.25).
#
# SOLIDS BEFORE no_collision(), DETAIL AFTER. Nothing solid stands between
# 0.25 m and 0.5 m (the baker's climb and the squad's step-over): _audit()
# checks that too.
# ─────────────────────────────────────────────

const RAILHEAD := {
	"railhead_hull_motive": "_hull_motive",
	"railhead_car_ops": "_car_ops",
	"railhead_car_repair": "_car_repair",
	"railhead_car_armoury": "_car_armoury",
	"railhead_car_fab": "_car_fab",
	"railhead_car_barracks": "_car_barracks",
	"railhead_car_platform": "_car_platform",
	"railhead_car_platform_ramp": "_car_platform_ramp",
	"railhead_station": "_station",
	"railhead_trackbed": "_trackbed",
}

# ── The envelope. The builder reads these too: describe once. ────────────────

const HL := 16.0            ## half the car's outer length (32 m)
const END := 15.75          ## the inside face of an end bulkhead
const HW := 4.5             ## half the internal width (9.0 m)
const OW := 4.75            ## half the outer width
const H := 5.0              ## internal height, floor to roof underside
const LANE := 1.5           ## half the central lane, which is never built on
const DOOR := 1.625          ## half a car-to-car doorway (3.25 m clear)
const DOOR_H := 3.40625      ## doorway clear height
const WALKER_W := 1.7
const WALKER_H := 3.0
const MIN_LANE := 3.0
const MIN_DOOR := 2.2

## Where the train stands, in the prefab's own space.
const DECK_RISE := 1.1875   # car floor above the ground: the rail head is 0.1875, a wheel is 1.0 under the floor
const RAMP_LEN := 7.5       ## 1.1875 over 7.5 is 1 in 6.3: under the 1 in 6 limit
const RAMP_HALF_W := 2.0
const GAUGE := 1.435

## Repair bays, car-local (map x, map y). Numbered in walking order from the
## platform, so Bay 1 is the first one you reach.
const BAYS: Array = [Vector2(-8.0, 3.0), Vector2(-8.0, -3.0), Vector2(8.0, 3.0), Vector2(8.0, -3.0)]
## The barracks has twelve racks and the squad is four.
## The barracks: ONE wall of twelve bays, 2.625 m pitch (12 x 2.625 = 31.5 m, exactly
## the car's interior), each 3.6 m deep, so a Bulwark, Walker, Rover or Reclaimer
## stands in one and the lane in front is 5.4 m. Bays are on the +Y side.
const BAR_PITCH := 2.625
const BAR_Y0 := 0.9          ## the front of the bays, and the edge of the lane
const BAR_DEPTH := 3.6
const BAR_FIN := 0.125
const BAR_STUB := 1.5
const BAR_CLEAR_H := 3.6
## The platform door's leaf slides +X into a pocket that ends here.
const DOOR_POCKET_END := 4.875
## Fabrication's mounts: the three with machines on them and the three without.
const FAB_X: Array = [-8.0, 0.0, 8.0]

## Lamp positions (map x, map y) per car; the builder puts a light under each.
## Evenly spaced, one every 8 m down the lane, and FEW: this is a dark vehicle in
## a dark tunnel, and each warm pool is an island, not general illumination.
const LAMPS := {
	"ops": [[-8.0, 0.0], [8.0, 0.0]],
	"repair": [[-12.0, 0.0], [-4.0, 0.0], [4.0, 0.0], [12.0, 0.0]],
	"armoury": [[-12.0, 0.0], [-4.0, 0.0], [4.0, 0.0], [12.0, 0.0]],
	"fab": [[-12.0, 0.0], [-4.0, 0.0], [4.0, 0.0], [12.0, 0.0]],
	"barracks": [[-12.0, -1.8], [-4.0, -1.8], [4.0, -1.8], [12.0, -1.8]],
	"platform": [[-12.0, 0.0], [-4.0, 0.0], [4.0, 0.0], [12.0, 0.0]],
}

# ── Textures. Every one has a material in textures/PSX_Textures/. ────────────

const GREEN := "PSX_Textures/stratcom_green"            # institutional green, to dado height: the signature surface
const GREEN_P := "PSX_Textures/stratcom_green_panel"      # equipment housings, fins, gantries, door furniture
const CREAM := "PSX_Textures/stratcom_cream"              # bone cream, upper wall
const CEIL_T := "PSX_Textures/stratcom_cream_ceiling"      # ceiling panel, visible grid
const CONC := "PSX_Textures/stratcom_concrete_board"       # structure, floors, exterior
const TILE := "PSX_Textures/stratcom_floor_tile"
const ARROW := "PSX_Textures/stratcom_floor_arrow"
const BRASS := "PSX_Textures/stratcom_brass"               # the one warm metal: fittings, rails, plaques, bands
const READOUT := "PSX_Textures/stratcom_readout"           # warm white on dark green glass: every readout
const PLACARD := "PSX_Textures/stratcom_placard"
const STENCIL := "PSX_Textures/stratcom_stencil"
const DOOR_T := "PSX_Textures/stratcom_door_steel"
const CONDUIT := "PSX_Textures/stratcom_conduit"
# Older names, pointed at the StratCom set so nothing is left in rust or amber.
const HULL := GREEN
const FRAME_T := GREEN_P
const OPS_T := GREEN
const PLATE := GREEN_P
const FLOOR_T := CONC
const GRATE := "PSX_Textures/grate_perf"
const RUST := CONDUIT
const HAZARD := STENCIL
const GLOW := READOUT
const SCREEN := READOUT
const GLASS := "PSX_Textures/glass_dark"
const BED := CONC
## The one exception to the StratCom set: the pack's own emissive ceiling light, whose
## material is shared and not ours to edit. Its colour is cream-white, not amber or cyan.
const LAMP_T := "PSX_Textures/hl_office_complex_style_drop_ceiling_1_1"
const BALLAST := "PSX_Textures/concrete_3"
const DADO := 1.125

var _failed := false
## Which side wall has no windows (+1 or -1), or 0 for none: the barracks bays stand against a blank wall.
var _no_win_side := 0.0


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
		print("usage: godot --headless --path . --script res://tools/block_railhead.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("railhead")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in RAILHEAD:
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
		_no_win_side = 0.0
		call(RAILHEAD[name])
		print("      %-26s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
		# Checked BEFORE it is written: a piece that fails is not left on disk
		# looking like a good one.
		if not _audit(name):
			_failed = true
			print("FAIL  %s was NOT written — see above" % name)
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
	print("BLOCK RAILHEAD DONE: %d written%s%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else "",
			"  — WITH FAILURES" if _failed else ""])
	quit(1 if _failed else 0)


# ── The shell every car shares ───────────────────────────────────────────────

## WINDOWS. Eight apertures a side, 2.0 m wide on a 4.0 m pitch, between 1.25 m
## and 3.0 m above the floor. They exist to show MOVEMENT during a transition,
## so they are regular: a passing backdrop reads as motion across eight
## openings and as a porthole across one. There is NO sill, ledge or rail at the
## player's height, only the wall's own thickness.
##
## RULE THAT FOLLOWS FROM THEM: anything standing against a side wall is either
## on a PIER (the 2.0 m of wall between two apertures, at x = -12 ... +12 every
## 4 m) or no taller than 1.1 m. A tall rack across an aperture would make the
## window a painting of a rack. The 4 m pitch is THE MODULE: lamps, bays, racks,
## fins, duct bands and arrows are all laid on it.
const WIN_Z0 := 1.25
const WIN_Z1 := 3.0
const WIN_PITCH := 4.0
const WIN_HALF := 1.0
const WIN_COUNT := 8
## How far outside the car's skin the backdrop plate stands, each side.
const BACKDROP_Y := 20.0
const PIERS: Array = [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]
## The solid wall is 0.1875 m thick (y 4.5 .. 4.6875). Outside it, mesh-only
## board-marked cladding brings the skin to 4.75 m: concrete outside, paint
## inside, from one wall that collides as one thin brush.
const WALL_IN := 4.6875


func _window_xs(s: float, side_door: bool) -> Array:
	var out: Array = []
	if s == _no_win_side:
		return out
	for i in WIN_COUNT:
		var wx := -14.0 + WIN_PITCH * i
		# The door takes the two apertures either side of the middle.
		if side_door and s > 0.0 and absf(wx) < 3.0:
			continue
		out.append(wx)
	return out


## A box painted the way StratCom paints everything: green to dado height,
## cream above. Split at the dado so the line is a real edge, on the grid.
func _painted(a: Vector3, b: Vector3) -> void:
	var lo := minf(a.z, b.z)
	var hi := maxf(a.z, b.z)
	if lo < DADO - 1e-4 and hi > DADO + 1e-4:
		box(Vector3(a.x, a.y, lo), Vector3(b.x, b.y, DADO), GREEN)
		box(Vector3(a.x, a.y, DADO), Vector3(b.x, b.y, hi), CREAM)
	elif hi <= DADO + 1e-4:
		box(a, b, GREEN)
	else:
		box(a, b, CREAM)


## Floor, roof, two side walls and two end bulkheads. An open end has a doorway
## 3.25 m wide x 3.4 m high; a sealed end is a wall. `side_door` cuts a doorway
## in the +Y wall at x = 0, onto a station platform that stands against the car.
func _shell(open_front: bool, open_rear: bool, _wall_tex: Variant = HULL, side_door: bool = false, floor_t: Variant = CONC) -> void:
	box(Vector3(-HL, -OW, -0.5), Vector3(HL, OW, 0.0), {"top": floor_t, "side": CONC, "bottom": CONC})
	box(Vector3(-HL, -OW, H), Vector3(HL, OW, H + 0.25), {"top": CONC, "side": CONC, "bottom": CEIL_T})
	for s: float in [-1.0, 1.0]:
		for r: Array in _wall_rects(s, side_door):
			_painted(Vector3(r[0], s * HW, r[2]), Vector3(r[1], s * WALL_IN, r[3]))
	_bulkhead(1.0, open_front)
	_bulkhead(-1.0, open_rear)


## A side wall as rectangles [x0, x1, z0, z1] around its openings: cut in
## columns between every opening edge, each solid wherever no opening covers it.
func _wall_rects(s: float, side_door: bool) -> Array:
	var ops: Array = []
	for wx: float in _window_xs(s, side_door):
		ops.append([wx - WIN_HALF, wx + WIN_HALF, WIN_Z0, WIN_Z1])
	if side_door and s > 0.0:
		ops.append([-DOOR, DOOR, 0.0, DOOR_H])
	var xs: Array = [-HL, HL]
	for o: Array in ops:
		xs.append(o[0])
		xs.append(o[1])
	xs.sort()
	var out: Array = []
	for i in xs.size() - 1:
		var a: float = xs[i]
		var b: float = xs[i + 1]
		if b - a < 1e-4:
			continue
		var cover: Array = ops.filter(func(o: Array) -> bool: return o[0] <= a + 1e-4 and o[1] >= b - 1e-4)
		cover.sort_custom(func(p: Array, q: Array) -> bool: return p[2] < q[2])
		var z := 0.0
		for o: Array in cover:
			if o[2] > z + 1e-4:
				out.append([a, b, z, o[2]])
			z = o[3]
		if z < H - 1e-4:
			out.append([a, b, z, H])
	return out


func _bulkhead(end: float, open: bool) -> void:
	var x0: float = END if end > 0.0 else -HL
	var x1: float = HL if end > 0.0 else -END
	if not open:
		_painted(Vector3(x0, -HW, 0.0), Vector3(x1, HW, H))
		return
	_painted(Vector3(x0, -HW, 0.0), Vector3(x1, -DOOR, H))
	_painted(Vector3(x0, DOOR, 0.0), Vector3(x1, HW, H))
	_painted(Vector3(x0, -DOOR, DOOR_H), Vector3(x1, DOOR, H))


## Glass and mullions for every aperture, the outer cladding, and the backdrop
## plate. MESH-ONLY, and called after no_collision(). The pane sits inside the
## wall's own thickness in two halves either side of a heavy mullion: standing
## clear of every brush, never laid on a face.
func _glaze(side_door: bool) -> void:
	for s: float in [-1.0, 1.0]:
		for r: Array in _wall_rects(s, side_door):
			box(Vector3(r[0], minf(s * WALL_IN, s * OW), r[2]), Vector3(r[1], maxf(s * WALL_IN, s * OW), r[3]), CONC)
		for wx: float in _window_xs(s, side_door):
			box(Vector3(wx - 0.125, minf(s * HW, s * OW), WIN_Z0), Vector3(wx + 0.125, maxf(s * HW, s * OW), WIN_Z1), BRASS)
			for h: float in [-1.0, 1.0]:
				var xa := wx + (0.125 if h > 0.0 else -WIN_HALF)
				var xb := wx + (WIN_HALF if h > 0.0 else -0.125)
				box(Vector3(xa, minf(s * 4.5625, s * 4.625), WIN_Z0), Vector3(xb, maxf(s * 4.5625, s * 4.625), WIN_Z1), GLASS)
	_backdrop()


## THE TUNNEL WALL: one plate each side, BACKDROP_Y out from the centreline, as
## long as the car, standing on the ground. The line is underground, so what
## passes the windows is tunnel: board-marked concrete, a rib every 8 m, cable
## runs between the ribs, lamp bars between those. Where the view hangs;
## gameplay scrolls or strobes whatever it likes on it, and hides the plates
## in a station, where the station's own wall stands 0 m behind them. Adjacent
## cars' plates touch end to end, and every run stops short of a rib.
const TUNNEL_TOP := 8.0


func _backdrop() -> void:
	for s: float in [-1.0, 1.0]:
		var pa: float = s * BACKDROP_Y - (0.0625 if s > 0.0 else 0.0)
		var pb: float = s * BACKDROP_Y + (0.0 if s > 0.0 else 0.0625)
		box(Vector3(-HL, pa, -DECK_RISE), Vector3(HL, pb, TUNNEL_TOP), CONC)
		# Inner face of the plate: y = s * (BACKDROP_Y - 0.0625); everything
		# stands proud of it toward the train.
		var fy: float = s * (BACKDROP_Y - 0.0625)
		var yo: float = s * (BACKDROP_Y - 0.1875)
		var ribs: Array = [-12.0, -4.0, 4.0, 12.0]
		for rx: float in ribs:
			box(Vector3(rx - 0.25, minf(fy, yo), -DECK_RISE), Vector3(rx + 0.25, maxf(fy, yo), TUNNEL_TOP), GREEN_P)
		var edges: Array = [-HL]
		for rx: float in ribs:
			edges.append(rx - 0.25)
			edges.append(rx + 0.25)
		edges.append(HL)
		for i in range(0, edges.size(), 2):
			var a: float = edges[i]
			var b: float = edges[i + 1]
			for z: float in [1.0, 1.3, 6.0]:
				box(Vector3(a, minf(fy, yo), z), Vector3(b, maxf(fy, yo), z + 0.125), CONDUIT)
			# A lamp bar mid-bay, above the windows' band.
			var cx := (a + b) * 0.5
			box(Vector3(cx - 0.75, minf(fy, yo), 6.5), Vector3(cx + 0.75, maxf(fy, yo), 6.75), LAMP_T)


# ── Detail every car shares. All of it is mesh-only. ─────────────────────────

## Lamps stay in their working band, 3.1 m, however tall the car is: the extra
## height is for plant and gantries ABOVE them, and the stem is just longer.
func _lamp(x: float, y: float, top: float = H) -> void:
	box(Vector3(x - 0.0625, y - 0.0625, 3.4), Vector3(x + 0.0625, y + 0.0625, top), BRASS)
	box(Vector3(x - 0.5, y - 0.25, 3.1), Vector3(x + 0.5, y + 0.25, 3.4), LAMP_T)


func _lamps(car: String, top: float = H) -> void:
	for p: Array in LAMPS[car]:
		_lamp(p[0], p[1], top)


## Roof beams across the car, hung from the roof underside, in the top 0.4 m.
func _beams(xs: Array) -> void:
	for x: float in xs:
		box(Vector3(x - 0.15, -HW, 4.6), Vector3(x + 0.15, HW, H), GREEN_P)


## Overhead plant: a duct run each side at 4.0-4.6 m, under the beams, in
## segments with a brass band on every pier and a stencilled number on each
## segment, because everything is labelled and nobody reads it.
func _ducts() -> void:
	for s: float in [-1.0, 1.0]:
		var ylo := minf(s * 4.0, s * 4.4)
		var yhi := maxf(s * 4.0, s * 4.4)
		var x := -14.0
		var n := 1
		var bands: Array = [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]
		for i in bands.size() + 1:
			var x1: float = bands[i] - 0.125 if i < bands.size() else 14.0
			box(Vector3(x, ylo, 4.0), Vector3(x1, yhi, 4.6), CONDUIT)
			_number(n, (x + x1) * 0.5, 4.15, 0.3, s * 4.0, s, STENCIL, true)
			n += 1
			if i < bands.size():
				box(Vector3(x1, ylo, 4.0), Vector3(bands[i] + 0.125, yhi, 4.6), BRASS)
				x = bands[i] + 0.125


## Floor markings: the lane's edges as stencilled lines, 0.0625 m proud and
## mesh-only, and an arrow on the lane at every 8 m: the baker climbs 0.25 m,
## so paint costs the squad nothing. `edges` are the lane's two sides (y) and
## `yc` its centre; `skip` are x values to leave bare.
func _lane_lines(skip: Array = [], edges: Array = [-LANE, LANE], yc: float = 0.0) -> void:
	for e: float in edges:
		box(Vector3(-15.5, e - (0.0625 if e > yc else 0.0), 0.0), Vector3(15.5, e + (0.0 if e > yc else 0.0625), 0.0625), STENCIL)
	for ax: float in [-12.0, -4.0, 4.0, 12.0]:
		if not skip.has(ax):
			box(Vector3(ax - 0.75, yc - 0.75, 0.0), Vector3(ax + 0.75, yc + 0.75, 0.0625), ARROW)


## The deck track: two flush steel rails down the lane, 2.2 m apart, where a
## chassis is moved. Mesh-only and 0.0625 m proud, so a body walks across them
## and the baker never sees them.
func _deck_track(yc: float = 0.0) -> void:
	for s: float in [-1.0, 1.0]:
		var y := yc + s * 1.1
		box(Vector3(-15.5, y - 0.0625, 0.0), Vector3(15.5, y + 0.0625, 0.0625), DOOR_T)


## Handrails at 1.0 m, along the side walls wherever the wall is free. They are
## a human fitting in a base with no human in it: mesh-only, brass, with a
## bracket at each end. `blocked` is the x ranges something stands in, per side.
func _handrails(blocked_pos: Array, blocked_neg: Array) -> void:
	for s: float in [-1.0, 1.0]:
		var blk: Array = blocked_pos if s > 0.0 else blocked_neg
		var spans: Array = [[-15.5, 15.5]]
		for b: Array in blk:
			var nxt: Array = []
			for sp: Array in spans:
				if b[1] <= sp[0] or b[0] >= sp[1]:
					nxt.append(sp)
					continue
				if b[0] > sp[0]:
					nxt.append([sp[0], b[0]])
				if b[1] < sp[1]:
					nxt.append([b[1], sp[1]])
			spans = nxt
		for sp: Array in spans:
			var x0: float = sp[0] + 0.125
			var x1: float = sp[1] - 0.125
			if x1 - x0 < 0.75:
				continue
			box(Vector3(x0, minf(s * 4.34375, s * 4.40625), 0.96875), Vector3(x1, maxf(s * 4.34375, s * 4.40625), 1.03125), BRASS)
			for bx: float in [x0, x1 - 0.0625]:
				box(Vector3(bx, minf(s * 4.40625, s * HW), 0.96875), Vector3(bx + 0.0625, maxf(s * 4.40625, s * HW), 1.03125), BRASS)


## Two bogies and their wheels under the floor, between the floor's underside
## and the rail head 1.0 m below it.
func _bogies() -> void:
	for cx: float in [-10.0, 10.0]:
		box(Vector3(cx - 1.8, -1.05, -0.75), Vector3(cx + 1.8, 1.05, -0.5), GREEN_P)
		for wx: float in [-1.0, 1.0]:
			for s: float in [-1.0, 1.0]:
				var ym := s * GAUGE * 0.5
				box(Vector3(cx + wx - 0.3, ym - 0.075, -1.0), Vector3(cx + wx + 0.3, ym + 0.075, -0.75), CONDUIT)


## The furniture of a doorway, on the inside face of one bulkhead: steel jambs
## and lintel, a pair of grab rails (for hands that are not there), the door's
## number, and a placard either side at reading height. `n` is the door number;
## -1 is a sealed end, which gets the placards and a brass plaque instead.
func _door_furniture(end: float, n: int) -> void:
	var xa: float = END - 0.0625 if end > 0.0 else -END
	var xb: float = END if end > 0.0 else -END + 0.0625
	if n >= 0:
		for s: float in [-1.0, 1.0]:
			box(Vector3(xa, minf(s * DOOR, s * (DOOR + 0.125)), 0.0), Vector3(xb, maxf(s * DOOR, s * (DOOR + 0.125)), DOOR_H), DOOR_T)
			box(Vector3(xa, minf(s * 1.8125, s * 1.875), 0.8), Vector3(xb, maxf(s * 1.8125, s * 1.875), 1.9), BRASS)
		box(Vector3(xa, -DOOR - 0.125, DOOR_H), Vector3(xb, DOOR + 0.125, DOOR_H + 0.125), DOOR_T)
		_number(n, 0.0, 3.65, 0.5, end * END, end, STENCIL, true, true)
	else:
		box(Vector3(xa, -0.5, 1.6), Vector3(xb, 0.5, 2.0), BRASS)
	for s: float in [-1.0, 1.0]:
		box(Vector3(xa, minf(s * 2.3, s * 3.3), 1.5), Vector3(xb, maxf(s * 2.3, s * 3.3), 2.1), PLACARD)


# ── Digits ───────────────────────────────────────────────────────────────────

## A 7-segment digit standing 1/16 m proud of a wall face, built from boxes
## that touch and never overlap. `face` is the wall's coordinate; `s` is which
## way the viewer is facing (+1 is +Y, or +X when `ax`); `u0` is where the digit
## starts in the direction that viewer reads.
const SEGS := {0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd", 6: "afgedc", 7: "abc", 8: "abcdefg", 9: "abcdfg"}


func _digit(d: int, u0: float, v0: float, h: float, face: float, s: float, tex: Variant = READOUT, ax: bool = false) -> void:
	var w := h * 0.5
	var t := h * 0.125
	var rects := {
		"a": [t, w - t, h - t, h], "d": [t, w - t, 0.0, t], "g": [t, w - t, h * 0.5 - t * 0.5, h * 0.5 + t * 0.5],
		"f": [0.0, t, h * 0.5 + t * 0.5, h - t], "b": [w - t, w, h * 0.5 + t * 0.5, h - t],
		"e": [0.0, t, t, h * 0.5 - t * 0.5], "c": [w - t, w, t, h * 0.5 - t * 0.5],
	}
	var c0: float = face - 0.0625 if s > 0.0 else face
	var c1: float = face if s > 0.0 else face + 0.0625
	for seg in String(SEGS[d]):
		var r: Array = rects[seg]
		if ax:
			var ya: float = u0 - r[1] if s > 0.0 else u0 + r[0]
			var yb: float = u0 - r[0] if s > 0.0 else u0 + r[1]
			box(Vector3(c0, ya, v0 + r[2]), Vector3(c1, yb, v0 + r[3]), tex)
		else:
			var xa: float = u0 + r[0] if s > 0.0 else u0 - r[1]
			var xb: float = u0 + r[1] if s > 0.0 else u0 - r[0]
			box(Vector3(xa, c0, v0 + r[2]), Vector3(xb, c1, v0 + r[3]), tex)


## A number of up to two digits, centred on uc, on a wall face.
func _number(n: int, uc: float, v0: float, h: float, face: float, s: float, tex: Variant = READOUT, pad: bool = false, ax: bool = false) -> void:
	var w := h * 0.5
	var gap := h * 0.25
	var digits: Array = []
	if n >= 10 or pad:
		digits = [n / 10, n % 10]
	else:
		digits = [n]
	var total := w * digits.size() + gap * (digits.size() - 1)
	for i in digits.size():
		var off := -total * 0.5 + i * (w + gap)
		var u: float = uc + off if (s > 0.0) != ax else uc - off
		_digit(digits[i], u, v0, h, face, s, tex, ax)


# ── The cars ─────────────────────────────────────────────────────────────────

## 1. MOTIVE. Not enterable: a hull the length of a car, a cab, and the things
## that sell that the building moves. One solid box for collision; the rest is
## drawn. Its rear (-X) face is flush against Operations' sealed front. Painted
## and swept like the rest: nothing about it is worn.
func _hull_motive() -> void:
	box(Vector3(-HL, -OW, -0.5), Vector3(HL, OW, H + 0.25), {"top": CONC, "side": GREEN, "bottom": CONC})
	box(Vector3(-HL, -3.5, H + 0.25), Vector3(-6.0, 3.5, 7.0), {"top": CONC, "side": GREEN, "bottom": CONC})
	no_collision()
	# Radiator louvres on both flanks, standing clear of the hull face.
	for s: float in [-1.0, 1.0]:
		for i in 5:
			var x := -13.0 + i * 5.0
			box(Vector3(x, s * OW if s > 0.0 else -OW - 0.0625, 1.0), Vector3(x + 3.0, (OW + 0.0625) if s > 0.0 else -OW, 3.0), GREEN_P)
	# Exhaust stacks forward of the cab, banded in brass.
	for sx: float in [2.0, 8.0, 14.0]:
		box(Vector3(sx - 0.4, -0.4, H + 0.25), Vector3(sx + 0.4, 0.4, 6.2), CONDUIT)
		box(Vector3(sx - 0.6, -0.6, 6.2), Vector3(sx + 0.6, 0.6, 6.4), BRASS)
	# Headlamp bank on the front (+X) face.
	for s: float in [-1.0, 1.0]:
		box(Vector3(HL, s * 3.0 - 0.5, 2.6), Vector3(HL + 0.0625, s * 3.0 + 0.5, 3.4), LAMP_T)
	# The cab's windowless slit. Armoured, so no glass, just a dark reveal.
	box(Vector3(-6.0, -2.5, 6.0), Vector3(-5.9375, 2.5, 6.5), READOUT)
	# Its stencilled designation on both flanks: the same number as the station.
	for s: float in [-1.0, 1.0]:
		_number(1, 0.0, 3.4, 1.0, s * OW, -s, STENCIL, true, false)
	_bogies()
	_backdrop()


## 2. OPERATIONS: THE MAP ROOM. Low, dark, and empty. The brightest thing is the
## projection. The table is at chest height for a Walker's crew, so the player
## looks DOWN on it, and it stands in a tiered well of standing positions. The
## floor stays flat: the tiers are drawn, not built, because a real step
## anywhere near the lane would close it. Behind the table, in the front half of
## the car, is a RAKED, FIXED SEATING BAY facing a wall board, two blocks either
## side of a 3.5 m aisle. The chairs were never for anyone.
## The ceiling is dropped to 3.6 m, though the car is 5.0 m.
func _car_ops() -> void:
	_shell(false, true, HULL, false, TILE)
	# Pedestal, then the slab on it. Tops at 1.1 and 1.3 m.
	box(Vector3(-0.8, -0.8, 0.0), Vector3(0.8, 0.8, 1.1), GREEN_P)
	box(Vector3(-4.0, -1.25, 1.1), Vector3(4.0, 1.25, 1.3), {"top": READOUT, "side": GREEN_P, "bottom": GREEN_P})
	# Cabinets on the rear piers, paired. The front half is the seating.
	for s: float in [-1.0, 1.0]:
		for p: float in [-12.0, -8.0]:
			box(Vector3(p - 1.0, minf(s * 3.9, s * HW), 0.0), Vector3(p + 1.0, maxf(s * 3.9, s * HW), 3.0), GREEN_P)
		# The raked blocks: three tiers, front row lowest, each a solid mass from
		# the floor with its top at 0.625 / 1.25 / 1.875 m. Tops well over 0.5 m.
		var tops: Array = [0.625, 1.25, 1.875]
		for i in 3:
			var x1 := END - i * 2.5
			box(Vector3(x1 - 2.5, minf(s * 1.75, s * HW), 0.0), Vector3(x1, maxf(s * 1.75, s * HW), tops[i]), {"top": TILE, "side": GREEN_P, "bottom": GREEN_P})
	no_collision()
	box(Vector3(-END + 0.0625, -HW, 3.6), Vector3(END - 0.0625, HW, H), {"top": CONC, "side": CONC, "bottom": CEIL_T})
	# The tiered well round the table: three rings 0.5 m wide, rising outward.
	# Mesh-only, 0.125 / 0.25 / 0.375 m, so nothing here is a step to the baker.
	for k in range(1, 4):
		var a := 0.5 * (k - 1)
		var b := 0.5 * k
		var top := 0.125 * k
		box(Vector3(-4.0 - b, 1.25 + a, 0.0), Vector3(4.0 + b, 1.25 + b, top), TILE)
		box(Vector3(-4.0 - b, -1.25 - b, 0.0), Vector3(4.0 + b, -1.25 - a, top), TILE)
		for e: float in [-1.0, 1.0]:
			box(Vector3(minf(e * (4.0 + a), e * (4.0 + b)), -1.25 - a, 0.0), Vector3(maxf(e * (4.0 + a), e * (4.0 + b)), 1.25 + a, top), TILE)
	# The projection: a flat plan 0.15 m above the slab (1.45 m, under the
	# player's 1.7), a relief on it, and the projector ring hanging above.
	box(Vector3(-3.7, -1.05, 1.3), Vector3(3.7, 1.05, 1.34375), READOUT)
	box(Vector3(-3.0, -0.6, 1.34375), Vector3(-2.0, 0.0, 1.5), READOUT)
	box(Vector3(0.2, 0.1, 1.34375), Vector3(0.8, 0.7, 1.45), READOUT)
	box(Vector3(2.0, -0.5, 1.34375), Vector3(3.0, 0.4, 1.4), READOUT)
	box(Vector3(-2.0, -1.5, 3.4), Vector3(2.0, 1.5, 3.6), LAMP_T)
	for s: float in [-1.0, 1.0]:
		var face: float = s * 3.9
		var y0: float = face - 0.0625 if s > 0.0 else face
		var y1: float = face if s > 0.0 else face + 0.0625
		for p: float in [-12.0, -8.0]:
			# A board on each cabinet front above the dim band, and its number below it.
			box(Vector3(p - 0.8, y0, 2.0), Vector3(p + 0.8, y1, 2.9), READOUT)
			_number(int((p + 12.0) / 4.0) + 1 + (0 if s > 0.0 else 2), p, 0.5, 0.5, face, s, STENCIL, true)
		# The seats: a cushion and a back, three to a row, on every tier. Bolted
		# to a floor they are meant to be sat on.
		var tops: Array = [0.625, 1.25, 1.875]
		for i in 3:
			var xr: float = END - i * 2.5 - 2.5
			for yc: float in [2.3, 3.0, 3.7]:
				var ys := minf(s * (yc - 0.3), s * (yc + 0.3))
				var ye := maxf(s * (yc - 0.3), s * (yc + 0.3))
				box(Vector3(xr + 0.9, ys, tops[i]), Vector3(xr + 1.6, ye, tops[i] + 0.45), GREEN_P)
				box(Vector3(xr + 0.75, ys, tops[i]), Vector3(xr + 0.9, ye, tops[i] + 0.95), GREEN_P)
	# The board the seats face: the whole front wall's worth of dark green
	# glass, a brass plaque under it.
	box(Vector3(END - 0.0625, -3.5, 1.2), Vector3(END, 3.5, 3.2), READOUT)
	box(Vector3(END - 0.0625, -0.75, 0.9), Vector3(END, 0.75, 1.1), BRASS)
	_door_furniture(-1.0, 1)
	_lamps("ops", 3.6)
	_glaze(false)
	_handrails([[-13.0, -11.0], [-9.0, -7.0], [7.5, 15.75]], [[-13.0, -11.0], [-9.0, -7.0], [7.5, 15.75]])
	_bogies()


## 3. REPAIR. Four bays, two a side, each 7.7 m between full-depth divider fins
## standing on piers, so the count is four at a glance. Each is 3.0 m deep: a
## Walker (1.7 m) stands in it with 0.65 m to spare, and the lane in front is
## untouched. Parts racks sit on piers or stay under 1.1 m so no aperture is
## blocked. Gantries and tool arms use the extra height above 3.2 m.
func _car_repair() -> void:
	_shell(true, true, HULL)
	for s: float in [-1.0, 1.0]:
		for fx: float in [-12.0, -4.0, 4.0, 12.0]:
			box(Vector3(fx - 0.15, minf(s * 1.75, s * HW), 0.0), Vector3(fx + 0.15, maxf(s * 1.75, s * HW), 3.9), GREEN_P)
		box(Vector3(-1.0, minf(s * 3.5, s * HW), 0.0), Vector3(1.0, maxf(s * 3.5, s * HW), 3.2), GREEN_P)
		for run: Array in [[-15.5, -12.5], [-3.7, -1.2], [1.2, 3.7], [12.5, 15.5]]:
			box(Vector3(run[0], minf(s * 3.5, s * HW), 0.0), Vector3(run[1], maxf(s * 3.5, s * HW), 1.1), GREEN_P)
	# Cradle clamps against the back wall, one pair per bay, on the pier.
	for b: Vector2 in BAYS:
		for dx: float in [-0.65, 0.65]:
			var ya: float = 4.1 if b.y > 0.0 else -HW
			var yb: float = HW if b.y > 0.0 else -4.1
			box(Vector3(b.x + dx - 0.15, ya, 0.0), Vector3(b.x + dx + 0.15, yb, 3.4), GREEN_P)
	no_collision()
	var n := 1
	for b: Vector2 in BAYS:
		var s: float = signf(b.y)
		# The cradle: two saddles on foot plates, flat to the floor.
		for dx: float in [-1.5, 1.5]:
			box(Vector3(b.x + dx - 0.2, s * 2.0 if s > 0.0 else -4.0, 0.0), Vector3(b.x + dx + 0.2, 4.0 if s > 0.0 else s * 2.0, 0.1875), STENCIL)
			box(Vector3(b.x + dx - 0.2, s * 2.4 if s > 0.0 else -3.6, 0.1875), Vector3(b.x + dx + 0.2, 3.6 if s > 0.0 else s * 2.4, 0.5), BRASS)
		# The bay's front edge on the floor, and its number above the aperture band.
		box(Vector3(b.x - 3.6, s * LANE if s > 0.0 else -LANE - 0.125, 0.0), Vector3(b.x + 3.6, (LANE + 0.125) if s > 0.0 else s * LANE, 0.0625), STENCIL)
		_number(n, b.x, 3.4, 1.0, s * HW, s)
		# Gantry beam over the bay and two tool arms hanging off it.
		var by0: float = 2.3 if s > 0.0 else -2.5
		var by1: float = 2.5 if s > 0.0 else -2.3
		box(Vector3(b.x - 3.6, by0, 4.0), Vector3(b.x + 3.6, by1, 4.4), GREEN_P)
		for dx: float in [-2.5, 2.5]:
			box(Vector3(b.x + dx - 0.15, by0, 3.2), Vector3(b.x + dx + 0.15, by1, 4.0), BRASS)
		n += 1
	# Bins on the racks' faces. The tall rack: bottom and top rows only. The low
	# racks: two rows, all under 1.1 m.
	for s: float in [-1.0, 1.0]:
		var runs := [[-1.0, 1.0, 0], [-15.5, -12.5, 1], [-3.7, -1.2, 1], [1.2, 3.7, 1], [12.5, 15.5, 1]]
		for run: Array in runs:
			var rows: Array = [[0.3, 0.8], [0.9, 1.3], [2.3, 2.75], [2.85, 3.1]] if run[2] == 0 else [[0.15, 0.55], [0.6, 1.0]]
			var x := float(run[0]) + 0.1
			while x + 0.9 <= float(run[1]) - 0.05:
				for row: Array in rows:
					var ya: float = s * 3.5 - 0.3 if s > 0.0 else s * 3.5
					var yb: float = s * 3.5 if s > 0.0 else s * 3.5 + 0.3
					box(Vector3(x, minf(ya, yb), row[0]), Vector3(x + 0.9, maxf(ya, yb), row[1]), CONDUIT)
				x += 1.0
	_door_furniture(1.0, 1)
	_door_furniture(-1.0, 2)
	_lamps("repair")
	_glaze(false)
	_ducts()
	_lane_lines()
	_deck_track()
	var rblk: Array = [[-15.5, -12.5], [-12.25, -11.75], [-8.8, -7.2], [-4.25, -3.7], [-3.7, -1.2], [-1.2, 1.2], [1.2, 3.7], [3.7, 4.25], [7.2, 8.8], [11.75, 12.25], [12.5, 15.5]]
	_handrails(rblk, rblk)
	_beams([-10.0, -6.0, -2.0, 2.0, 6.0, 10.0])
	_bogies()


## 4. ARMOURY. Wall racks on the piers, one per pier, in three sections by frame
## type. Racks not crates: you see what you own. Racks are 0.6 m deep;
## everything on them is drawn, and every rack is numbered.
func _car_armoury() -> void:
	_shell(true, true, HULL)
	for s: float in [-1.0, 1.0]:
		for p: float in PIERS:
			box(Vector3(p - 1.0, minf(s * 3.9, s * HW), 0.0), Vector3(p + 1.0, maxf(s * 3.9, s * HW), 3.4), GREEN_P)
	no_collision()
	var tex := [BRASS, GREEN_P, CONDUIT]
	var rn := 1
	for s: float in [1.0, -1.0]:
		var ya: float = s * 3.9 - 0.25 if s > 0.0 else s * 3.9
		var yb: float = s * 3.9 if s > 0.0 else s * 3.9 + 0.25
		for p: float in PIERS:
			var si := 0 if p <= -8.0 else (1 if p <= 4.0 else 2)
			box(Vector3(p - 0.9, minf(ya, yb), 3.0), Vector3(p + 0.9, maxf(ya, yb), 3.15), tex[si])
			var x := p - 0.8
			while x + 0.2 <= p + 0.8:
				box(Vector3(x, minf(ya, yb), 0.5), Vector3(x + 0.2, maxf(ya, yb), 2.8), tex[si])
				x += 0.4
			_number(rn, p, 0.1, 0.35, s * 3.9, s, STENCIL, true)
			rn += 1
	_door_furniture(1.0, 2)
	_door_furniture(-1.0, 3)
	_lamps("armoury")
	_glaze(false)
	_ducts()
	_lane_lines()
	_deck_track()
	var blk: Array = []
	for p: float in PIERS:
		blk.append([p - 1.0, p + 1.0])
	_handrails(blk, blk)
	_beams([-14.0, -10.0, -6.0, -2.0, 2.0, 6.0, 10.0, 14.0])
	_bogies()


## 5. FABRICATION. A machine shop, half-finished. Three mounts along the -Y wall
## carry machines: a low bed under the sill line and a head on the pier. The
## same three along the +Y wall are bare plates with their anchor studs, and
## an unfinished frame stands beside them. The software branch that builds it
## out is not here yet, and the empty mounts say so.
func _car_fab() -> void:
	_shell(true, true, HULL)
	for x: float in FAB_X:
		box(Vector3(x - 1.5, -HW, 0.0), Vector3(x + 1.5, -3.0, 1.0), GREEN_P)
		box(Vector3(x - 1.0, -HW, 1.0), Vector3(x + 1.0, -3.2, 2.8), GREEN_P)
	no_collision()
	var mn := 1
	for x: float in FAB_X:
		box(Vector3(x - 1.5, 3.0, 0.0), Vector3(x + 1.5, HW, 0.1875), GRATE)
		for dx: float in [-1.2, 1.2]:
			for yy: float in [3.3, 4.1]:
				box(Vector3(x + dx - 0.1, yy - 0.1, 0.1875), Vector3(x + dx + 0.1, yy + 0.1, 0.4), BRASS)
		# Overhead rail with an empty hook block, for the tool that is not here.
		box(Vector3(x - 1.5, 3.6, 4.0), Vector3(x + 1.5, 3.8, 4.4), GREEN_P)
		# And the fitted machine's rail, with its tool head hanging below.
		box(Vector3(x - 1.5, -3.8, 4.0), Vector3(x + 1.5, -3.6, 4.4), GREEN_P)
		box(Vector3(x - 0.5, -3.8, 3.2), Vector3(x + 0.5, -3.6, 4.0), BRASS)
		# Each mount is stencilled with its number, fitted or not.
		_number(mn, x, 0.3, 0.5, -3.0, -1.0, STENCIL, true)
		_number(mn + 3, x, 0.35, 0.5, 4.5, 1.0, STENCIL, true)
		mn += 1
	# The unfinished frame: uprights and one cross-member, no panels.
	for fx: float in [11.1, 12.9]:
		box(Vector3(fx - 0.1, 3.4, 0.0), Vector3(fx + 0.1, 3.6, 3.0), GREEN_P)
	box(Vector3(11.0, 3.4, 3.0), Vector3(13.0, 3.6, 3.2), GREEN_P)
	_door_furniture(1.0, 3)
	_door_furniture(-1.0, 4)
	_lamps("fab")
	_glaze(false)
	_ducts()
	_lane_lines()
	_deck_track()
	var neg: Array = []
	for x: float in FAB_X:
		neg.append([x - 1.5, x + 1.5])
	_handrails([[10.9, 13.1]], neg)
	_beams([-14.0, -10.0, -6.0, -2.0, 2.0, 6.0, 10.0, 14.0])
	_bogies()


## 6. BARRACKS. THE BIG CHASSIS LIVE HERE. Twelve bays down ONE wall, the +Y one,
## on a 2.625 m pitch (12 x 2.625 = 31.5 m, the car's whole interior), each
## 3.6 m deep and 3.6 m clear. Measured against the four chassis: a Walker
## (1.7 x 3.0 tall), a Bulwark (1.9 across the shoulders and a 1.55 m shield on
## the forearm), a Rover (1.5 x 3.2 LONG, 3.4 tall) and a Reclaimer (1.5 x 3.1
## long) each stand nose-in with room to spare: 2.5 m clear between fins, 3.6 m
## deep, a 3.6 m ceiling under the hoist. The lane in front is 5.4 m. The wall
## behind the bays has no windows; the other side keeps its eight.
## Each bay has a floor outline, two feed rails from the lane, four tie-down
## cleats, wall clamps and a trolley on the overhead hoist, because underneath
## the institutional paint this is a freight system. The player will have
## four; the emptiness is the content.
func _car_barracks() -> void:
	_no_win_side = 1.0
	_shell(true, true, HULL, false, TILE)
	for i in range(1, 12):
		var fx := -END + BAR_PITCH * i
		# SOLID ONLY AT THE BACK. A full-depth solid fin would leave 2.5 m between
		# colliders, which the baker erodes by 1.0 m each side to a 0.5 m ribbon and
		# drops: the bay would bake as a wall. So the partition is a 1.5 m solid
		# stub at the back wall and the rest of it is drawn.
		box(Vector3(fx - BAR_FIN * 0.5, HW - BAR_STUB, 0.0), Vector3(fx + BAR_FIN * 0.5, HW, 3.9), GREEN_P)
	no_collision()
	# The rest of each partition, drawn: it joins the solid stub at y = HW - BAR_STUB.
	for i in range(1, 12):
		var gx := -END + BAR_PITCH * i
		box(Vector3(gx - BAR_FIN * 0.5, BAR_Y0, 0.0), Vector3(gx + BAR_FIN * 0.5, HW - BAR_STUB, 3.9), GREEN_P)
	var n := 1
	for i in 12:
		var cx := -END + BAR_PITCH * (i + 0.5)
		var y1 := BAR_Y0 + BAR_DEPTH
		# The bay's outline on the floor, in stencil: sides and ends.
		for sx: float in [-1.0, 1.0]:
			box(Vector3(minf(cx + sx * 1.0, cx + sx * 1.1), BAR_Y0 + 0.1, 0.0), Vector3(maxf(cx + sx * 1.0, cx + sx * 1.1), y1 - 0.1, 0.0625), STENCIL)
		box(Vector3(cx - 1.0, BAR_Y0 + 0.1, 0.0), Vector3(cx + 1.0, BAR_Y0 + 0.2, 0.0625), STENCIL)
		box(Vector3(cx - 1.0, y1 - 0.2, 0.0), Vector3(cx + 1.0, y1 - 0.1, 0.0625), STENCIL)
		# Two feed rails from the lane into the bay, flush.
		for sx: float in [-1.0, 1.0]:
			box(Vector3(cx + sx * 0.6 - 0.05, BAR_Y0 + 0.2, 0.0), Vector3(cx + sx * 0.6 + 0.05, y1 - 0.2, 0.0625), DOOR_T)
			# Tie-down cleats at the four corners, brass, 0.15 m, between the outline and the rails.
			for yy: float in [BAR_Y0 + 0.5, y1 - 0.5]:
				box(Vector3(cx + sx * 0.8 - 0.1, yy - 0.1, 0.0), Vector3(cx + sx * 0.8 + 0.1, yy + 0.1, 0.15), BRASS)
			# Wall clamps on the back wall at chest height, one each side.
			box(Vector3(cx + sx * 0.8 - 0.15, y1 - 0.2, 0.6), Vector3(cx + sx * 0.8 + 0.15, y1, 0.9), BRASS)
		# The hoist trolley hanging from the overhead rail, over the bay's middle.
		box(Vector3(cx - 0.3, 2.55, 3.7), Vector3(cx + 0.3, 2.85, 4.0), GREEN_P)
		# The bay's number, on the back wall above the clearance line: warm white
		# on dark green glass.
		_number(n, cx, 3.7, 0.5, HW, 1.0, READOUT, true)
		n += 1
	# The overhead hoist rail runs the length of the bays, above everything.
	box(Vector3(-15.5, 2.6, 4.0), Vector3(15.5, 2.8, 4.4), GREEN_P)
	# The lane's edge in stencil; the lane is the empty side, 5.4 m wide.
	box(Vector3(-15.5, BAR_Y0 - 0.0625, 0.0), Vector3(15.5, BAR_Y0, 0.0625), STENCIL)
	_door_furniture(1.0, 4)
	_door_furniture(-1.0, 5)
	_lamps("barracks")
	_glaze(false)
	_ducts()
	_lane_lines([], [-HW + 0.0625], -1.8)
	_deck_track(-1.8)
	_handrails([[-16.0, 16.0]], [])
	_beams([-14.0, -10.0, -6.0, -2.0, 2.0, 6.0, 10.0, 14.0])
	_bogies()


## 7. PLATFORM. The door. A side door at x = 0 in the +Y wall opens onto a
## station platform whose top is at the car's floor height, so the squad walks
## straight off with no step. The rear (-X) end is sealed.
## railhead_car_platform_ramp is the same car with the rear open onto a
## boarding ramp: the way off at a stop with no station.
func _car_platform(ramp_end: bool = false) -> void:
	_shell(true, ramp_end, HULL, true)
	if ramp_end:
		ramp(-HL - RAMP_LEN, -RAMP_HALF_W, -HL, RAMP_HALF_W, -DECK_RISE, -DECK_RISE, 0.0, "+x", {"top": GRATE, "side": GREEN_P, "bottom": GREEN_P})
	for s: float in [-1.0, 1.0]:
		for p: float in [-12.0, -8.0, 8.0, 12.0]:
			box(Vector3(p - 1.0, minf(s * 3.9, s * HW), 0.0), Vector3(p + 1.0, maxf(s * 3.9, s * HW), 3.0), GREEN_P)
	no_collision()
	if ramp_end:
		for s: float in [-1.0, 1.0]:
			var ya: float = DOOR if s > 0.0 else -DOOR - 0.25
			var yb: float = DOOR + 0.25 if s > 0.0 else -DOOR
			box(Vector3(-HL - 0.125, ya, 0.0), Vector3(-HL, yb, DOOR_H), DOOR_T)
		box(Vector3(-HL - 0.125, -DOOR - 0.25, DOOR_H), Vector3(-HL, DOOR + 0.25, DOOR_H + 0.25), DOOR_T)
	# The platform door's frame, proud of the outer face and clear of the opening.
	for s: float in [-1.0, 1.0]:
		var xa: float = DOOR if s > 0.0 else -DOOR - 0.25
		var xb: float = DOOR + 0.25 if s > 0.0 else -DOOR
		box(Vector3(xa, OW, 0.0), Vector3(xb, OW + 0.125, DOOR_H), DOOR_T)
	box(Vector3(-DOOR - 0.25, OW, DOOR_H), Vector3(DOOR + 0.25, OW + 0.125, DOOR_H + 0.25), DOOR_T)
	# Its inside: the number above it on the wall's face, one grab rail on the
	# side the leaf does NOT go. THE LEAF SLIDES +X into a pocket of real space:
	# the 3.25 m of wall face from x 1.625 to 4.875, kept clear of every fitting
	# (no rail, locker or placard stands there), with a header rail and a floor
	# guide drawn for it. The floor guide is 0.03 m high and mesh-only; there is
	# no threshold, no sill, nothing between 0.25 m and 0.5 m.
	_number(6, 0.0, 3.5, 0.5, HW, 1.0, STENCIL, true)
	box(Vector3(-1.8125 - 0.03125, 4.4375, 0.8), Vector3(-1.8125 + 0.03125, HW, 1.9), BRASS)
	box(Vector3(-1.7, 4.3125, 3.4375), Vector3(DOOR_POCKET_END + 0.025, 4.4375, 3.5), GREEN_P)
	for bx: float in [-1.7, 1.9, DOOR_POCKET_END - 0.1]:
		box(Vector3(bx, 4.4375, 3.4375), Vector3(bx + 0.1, HW, 3.5), BRASS)
	box(Vector3(-1.7, 4.375, 0.0), Vector3(DOOR_POCKET_END + 0.025, 4.4375, 0.03125), DOOR_T)
	# Lockers are numbered.
	var ln := 1
	for s: float in [1.0, -1.0]:
		for p: float in [-12.0, -8.0, 8.0, 12.0]:
			_number(ln, p, 2.2, 0.5, s * 3.9, s, STENCIL, true)
			ln += 1
	# Muster squares on the floor, forward of the arrival point.
	for i in 4:
		var cx := 1.0 + i * 2.5
		box(Vector3(cx - 0.9, -0.9, 0.0), Vector3(cx + 0.9, -0.8125, 0.0625), STENCIL)
		box(Vector3(cx - 0.9, 0.8125, 0.0), Vector3(cx + 0.9, 0.9, 0.0625), STENCIL)
	_door_furniture(1.0, 5)
	_door_furniture(-1.0, 6 if ramp_end else -1)
	_lamps("platform")
	_glaze(true)
	_ducts()
	_lane_lines()
	_deck_track()
	var blk: Array = [[-13.0, -7.0], [7.0, 13.0]]
	_handrails([[-13.0, -7.0], [-1.9, 5.1], [7.0, 13.0]], blk)
	_beams([-14.0, -5.0, 5.0, 14.0])
	_bogies()


func _car_platform_ramp() -> void:
	_car_platform(true)


## THE GROUND under the whole scene: one slab, top at 0, 48 m across, cut flat
## at the boundary. It brings no rails: railhead_station owns the track.
func _trackbed() -> void:
	box(Vector3(-ST_CUT, -24.0, -2.0), Vector3(ST_CUT, 24.0, 0.0), {"top": CONC, "side": BALLAST, "bottom": BALLAST})


# ── The station ──────────────────────────────────────────────────────────────
#
# AN UNDERGROUND STATION, A CUT-AND-COVER BOX. The line runs in tunnel; the
# station is a concrete box 40 m wide inside, 10 m high, 300 m long, with a
# roof slab over the lot. The platform, the head house and the cargo gear are
# under it. The track leaves through a portal in each end wall: the prefab is
# CUT there, and a mission map joins its own tunnel to the two mouths.
#
# THE MAST goes UP A SHAFT. It stands on the ground at the rear of the box,
# passes through a square hole in the roof slab, and carries on to 40 m above
# the station floor: the one StratCom object with a reason to exist, because it
# is why you still get briefings. On a surface map it is the landmark.
#
# THE HELD STATE ONLY: lit, working, StratCom's. Unheld (dark, derelict) and
# contested (damaged, fought over) are later work and are not built here.
#
# THE SAME STATION EVERY TIME, because the manual has one station in it: board-
# marked concrete, a stencilled designation, tungsten pendants on a 16 m
# module, a steel door on the head house. Underneath the trappings it is a
# freight stop: deck rails across the platform, a gantry over them, cleats at
# the edge and loading marks on the floor.
#
# THE SIDE WALLS STAND EXACTLY AT THE CARS' BACKDROP PLATES (y = +-20): in
# transit the plates are the view; in a station gameplay hides them and the
# wall is right behind.
#
# THE ARITHMETIC. The car floor is DECK_RISE (1.1875 m) above the ground and
# the car's outer wall face is at OW (4.75 m). The platform top is therefore
# DECK_RISE, and the platform's near edge is OW, so it butts the car skin: the
# floor slab runs to y = OW and the platform starts there, one surface at one
# height. The side door (3.25 x 3.41 m) is cut in that wall. The end ramp is
# 1.1875 m over 7.5 m, 1 in 6.3, as the boarding ramp is.
#
# Track runs along map X, centred on y = 0.

const ST_CUT := 150.0
const ST_X0 := -141.0       ## platform's rear end: the head house stands on it
const ST_X1 := 125.0        ## platform's front end, 13 m past the rake's nose
const ST_Y0 := OW
const ST_Y1 := 20.0         ## the back wall: a 15.25 m platform, clear of cover
const ST_ROOF := 10.0       ## the roof slab's underside, above the ground
const ST_WALL := 1.0
const PORTAL_HALF := 3.5
const PORTAL_H := 6.0
const HH_X1 := -127.0
const HH_Y0 := 6.75
const HH_H := 4.0
## The pendant lamps over the platform, on a 32 m module (every second car).
const POSTS: Array = [-96.0, -64.0, -32.0, 0.0, 32.0, 64.0, 96.0]
const ST_LAMP_Y := 12.0
const ST_LAMP_Z := 6.8      ## where the light stands; the fitting hangs just above it
const ST_RAMP_Y := 10.75    ## the end ramp's and the head house door's centreline
const HH_LAMPS: Array = [-137.0, -131.0]
## The aerial mast: footing and column solid, arms and beacon drawn.
const MAST_X := -146.0
const MAST_Y := 9.75
const MAST_H := 40.0


func _station() -> void:
	var top := DECK_RISE
	box(Vector3(ST_X0, ST_Y0, 0.0), Vector3(ST_X1, ST_Y1, top), {"top": CONC, "side": CONC, "bottom": CONC})
	# The end ramp down to the ground, 4.0 m wide, a wedge with no lip.
	ramp(ST_X1, ST_RAMP_Y - 2.0, ST_X1 + RAMP_LEN, ST_RAMP_Y + 2.0, 0.0, 0.0, top, "-x", {"top": CONC, "side": CONC, "bottom": CONC})
	# THE BOX. Two side walls, two end walls with a portal each, and a roof with
	# a shaft hole in it for the mast.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-ST_CUT, minf(s * 20.0, s * (20.0 + ST_WALL)), 0.0), Vector3(ST_CUT, maxf(s * 20.0, s * (20.0 + ST_WALL)), ST_ROOF), {"top": CONC, "side": CONC, "bottom": CONC})
	for e: float in [-1.0, 1.0]:
		var xa := minf(e * (ST_CUT - ST_WALL), e * ST_CUT)
		var xb := maxf(e * (ST_CUT - ST_WALL), e * ST_CUT)
		box(Vector3(xa, -20.0, 0.0), Vector3(xb, -PORTAL_HALF, ST_ROOF), CONC)
		box(Vector3(xa, PORTAL_HALF, 0.0), Vector3(xb, 20.0, ST_ROOF), CONC)
		box(Vector3(xa, -PORTAL_HALF, PORTAL_H), Vector3(xb, PORTAL_HALF, ST_ROOF), CONC)
	var rz := {"top": CONC, "side": CONC, "bottom": CEIL_T}
	var sx0 := MAST_X - 1.5
	var sx1 := MAST_X + 1.5
	var sy0 := MAST_Y - 1.5
	var sy1 := MAST_Y + 1.5
	box(Vector3(-ST_CUT, -20.0 - ST_WALL, ST_ROOF), Vector3(sx0, 20.0 + ST_WALL, ST_ROOF + 1.0), rz)
	box(Vector3(sx1, -20.0 - ST_WALL, ST_ROOF), Vector3(ST_CUT, 20.0 + ST_WALL, ST_ROOF + 1.0), rz)
	box(Vector3(sx0, -20.0 - ST_WALL, ST_ROOF), Vector3(sx1, sy0, ST_ROOF + 1.0), rz)
	box(Vector3(sx0, sy1, ST_ROOF), Vector3(sx1, 20.0 + ST_WALL, ST_ROOF + 1.0), rz)
	# The head house: a room on the platform's rear end with its door toward
	# the train's side of the platform. Concrete outside, painted inside.
	var hx0 := ST_X0
	var hy1 := ST_Y1
	var cy := ST_RAMP_Y
	box(Vector3(hx0, HH_Y0, top), Vector3(hx0 + 0.25, hy1, top + HH_H), CONC)
	box(Vector3(hx0 + 0.25, HH_Y0, top), Vector3(HH_X1 - 0.25, HH_Y0 + 0.25, top + HH_H), CONC)
	box(Vector3(hx0 + 0.25, hy1 - 0.25, top), Vector3(HH_X1 - 0.25, hy1, top + HH_H), CONC)
	box(Vector3(HH_X1 - 0.25, HH_Y0, top), Vector3(HH_X1, cy - DOOR, top + HH_H), CONC)
	box(Vector3(HH_X1 - 0.25, cy + DOOR, top), Vector3(HH_X1, hy1, top + HH_H), CONC)
	box(Vector3(HH_X1 - 0.25, cy - DOOR, top + DOOR_H), Vector3(HH_X1, cy + DOOR, top + HH_H), CONC)
	box(Vector3(hx0, HH_Y0, top + HH_H), Vector3(HH_X1, hy1, top + HH_H + 0.25), {"top": CONC, "side": CONC, "bottom": CEIL_T})
	# The mast: a footing and a column, solid, the column passing through the shaft.
	box(Vector3(MAST_X - 1.5, MAST_Y - 1.5, 0.0), Vector3(MAST_X + 1.5, MAST_Y + 1.5, 0.75), CONC)
	box(Vector3(MAST_X - 0.3, MAST_Y - 0.3, 0.75), Vector3(MAST_X + 0.3, MAST_Y + 0.3, MAST_H), CONDUIT)
	no_collision()
	# The head house inside, painted: green to the dado, cream above, as
	# mesh-only linings standing against the concrete (touching, never laid in it).
	var ix0 := hx0 + 0.25
	var ix1 := HH_X1 - 0.25
	var iy0 := HH_Y0 + 0.25
	var iy1 := hy1 - 0.25
	var dado := top + DADO
	for lining: Array in [
			[Vector3(ix0, iy0, top), Vector3(ix1, iy0 + 0.0625, dado), GREEN], [Vector3(ix0, iy0, dado), Vector3(ix1, iy0 + 0.0625, top + HH_H), CREAM],
			[Vector3(ix0, iy1 - 0.0625, top), Vector3(ix1, iy1, dado), GREEN], [Vector3(ix0, iy1 - 0.0625, dado), Vector3(ix1, iy1, top + HH_H), CREAM]]:
		box(lining[0], lining[1], lining[2])
	# Platform edge line and a mark at each car's end, so the berth reads.
	box(Vector3(ST_X0, ST_Y0, top), Vector3(ST_X1, ST_Y0 + 0.25, top + 0.0625), STENCIL)
	for i in 8:
		var bx := -112.0 + i * 32.0
		box(Vector3(bx - 0.125, ST_Y0 + 0.25, top), Vector3(bx + 0.125, ST_Y0 + 1.25, top + 0.0625), STENCIL)
	# THE FREIGHT LAYER. Two deck rails along the platform at y = 9 where a load
	# is moved, cleats in pairs along the edge on the 8 m module, a loading arrow
	# on the floor every 48 m, and a gantry rail overhead. All flush or high and
	# all mesh-only: nothing here stands between 0.25 m and 0.5 m.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-120.0, 9.0 + s * 0.6 - 0.05, top), Vector3(120.0, 9.0 + s * 0.6 + 0.05, top + 0.0625), DOOR_T)
	for k in 29:
		var cx := -112.0 + k * 8.0
		if k % 4 == 0:
			continue
		box(Vector3(cx - 0.1, ST_Y0 + 1.9, top), Vector3(cx + 0.1, ST_Y0 + 2.1, top + 0.15), BRASS)
	for ax: float in [-96.0, -48.0, 0.0, 48.0, 96.0]:
		box(Vector3(ax - 0.75, 13.5, top), Vector3(ax + 0.75, 15.0, top + 0.0625), ARROW)
	box(Vector3(-120.0, 17.0, 8.0), Vector3(120.0, 17.3, 8.4), GREEN_P)
	for k in 8:
		var hx := -112.0 + k * 32.0
		box(Vector3(hx - 0.1, 17.0, 8.4), Vector3(hx + 0.1, 17.3, ST_ROOF), GREEN_P)
	# Wall pilasters on the back wall under every pendant, numbered: drawn, not
	# built, so the platform stays clear of cover. And a cable run above where
	# the cars' backdrop plates stop, on both walls.
	for i in POSTS.size():
		var x: float = POSTS[i]
		box(Vector3(x - 0.4, ST_Y1 - 0.5, top), Vector3(x + 0.4, ST_Y1, 9.2), GREEN_P)
		_number(i + 1, x, top + 2.0, 0.4, ST_Y1 - 0.5, 1.0, STENCIL, true)
		# The pendant: a stem from the roof and a lamp head at the working band.
		box(Vector3(x - 0.0625, ST_LAMP_Y - 0.0625, ST_LAMP_Z + 0.5), Vector3(x + 0.0625, ST_LAMP_Y + 0.0625, ST_ROOF), BRASS)
		box(Vector3(x - 0.5, ST_LAMP_Y - 0.25, ST_LAMP_Z + 0.2), Vector3(x + 0.5, ST_LAMP_Y + 0.25, ST_LAMP_Z + 0.5), LAMP_T)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-ST_CUT + ST_WALL, minf(s * 20.0, s * 19.9375), 9.3), Vector3(ST_CUT - ST_WALL, maxf(s * 20.0, s * 19.9375), 9.5), CONDUIT)
	# The portals: a steel frame round each mouth, and the tunnel's number.
	for e: float in [-1.0, 1.0]:
		var fx0 := minf(e * (ST_CUT - ST_WALL - 0.0625), e * (ST_CUT - ST_WALL))
		var fx1 := maxf(e * (ST_CUT - ST_WALL - 0.0625), e * (ST_CUT - ST_WALL))
		for s: float in [-1.0, 1.0]:
			box(Vector3(fx0, minf(s * PORTAL_HALF, s * (PORTAL_HALF + 0.25)), 0.0), Vector3(fx1, maxf(s * PORTAL_HALF, s * (PORTAL_HALF + 0.25)), PORTAL_H), DOOR_T)
		box(Vector3(fx0, -PORTAL_HALF - 0.25, PORTAL_H), Vector3(fx1, PORTAL_HALF + 0.25, PORTAL_H + 0.25), DOOR_T)
		_number(1 if e < 0.0 else 2, 0.0, PORTAL_H + 0.6, 0.6, e * (ST_CUT - ST_WALL), e, STENCIL, true, true)
	# The head house door: steel jambs and a lintel, standing on the outer face.
	for s: float in [-1.0, 1.0]:
		box(Vector3(HH_X1, minf(cy + s * DOOR, cy + s * (DOOR + 0.125)), top), Vector3(HH_X1 + 0.0625, maxf(cy + s * DOOR, cy + s * (DOOR + 0.125)), top + DOOR_H), DOOR_T)
	box(Vector3(HH_X1, cy - DOOR - 0.125, top + DOOR_H), Vector3(HH_X1 + 0.0625, cy + DOOR + 0.125, top + DOOR_H + 0.125), DOOR_T)
	# The designation: the number over the door, a big one on the wall that
	# faces the platform, and placards either side. Accurate; nobody reads them.
	_number(1, cy, top + 3.55, 0.4, HH_X1, -1.0, STENCIL, true, true)
	_number(1, -134.0, top + 1.8, 1.2, HH_Y0, 1.0, STENCIL, true)
	box(Vector3(HH_X1, cy + 2.0, top + 1.5), Vector3(HH_X1 + 0.0625, cy + 3.4, top + 2.5), PLACARD)
	box(Vector3(HH_X1, cy - 3.4, top + 1.5), Vector3(HH_X1 + 0.0625, cy - 2.0, top + 2.5), PLACARD)
	# Head house furniture-free dressing: a board on the far wall above the
	# 1.7 m band, lamps at the working height.
	box(Vector3(ix0, 8.0, top + 2.0), Vector3(ix0 + 0.0625, 13.5, top + 3.0), READOUT)
	for lx: float in HH_LAMPS:
		box(Vector3(lx - 0.0625, cy - 0.0625, top + 3.4), Vector3(lx + 0.0625, cy + 0.0625, top + HH_H), BRASS)
		box(Vector3(lx - 0.5, cy - 0.25, top + 3.1), Vector3(lx + 0.5, cy + 0.25, top + 3.4), LAMP_T)
	# The mast's arms, at 14, 22, 30 and 38 m, either side of the column, and a
	# beacon on top. Right angles only: no guys, no diagonals. All above the roof.
	for h: float in [14.0, 22.0, 30.0, 38.0]:
		box(Vector3(MAST_X - 0.1, MAST_Y - 3.0, h), Vector3(MAST_X + 0.1, MAST_Y - 0.3, h + 0.15), BRASS)
		box(Vector3(MAST_X - 0.1, MAST_Y + 0.3, h), Vector3(MAST_X + 0.1, MAST_Y + 3.0, h + 0.15), BRASS)
	box(Vector3(MAST_X - 0.3, MAST_Y - 0.3, MAST_H), Vector3(MAST_X + 0.3, MAST_Y + 0.3, MAST_H + 0.5), LAMP_T)
	# Track: ballast, sleepers, rails, running out through both portals to the
	# boundary and stopping there flat. Each stands on the one before.
	box(Vector3(-ST_CUT, -1.7, 0.0), Vector3(ST_CUT, 1.7, 0.0625), BALLAST)
	var tx := -ST_CUT + 0.5
	while tx + 0.3 <= ST_CUT:
		box(Vector3(tx, -1.3, 0.0625), Vector3(tx + 0.3, 1.3, 0.125), CONC)
		tx += 1.0
	for s: float in [-1.0, 1.0]:
		var ym := s * GAUGE * 0.5
		box(Vector3(-ST_CUT, ym - 0.0625, 0.125), Vector3(ST_CUT, ym + 0.0625, 0.1875), DOOR_T)


# ── The audit ────────────────────────────────────────────────────────────────

func _brush_box(b: int) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for face: Dictionary in _brushes[b]:
		for p: Vector3 in face.poly:
			lo = lo.min(p)
			hi = hi.max(p)
	return AABB(lo / UPM, (hi - lo) / UPM)


## Free y-intervals across the car at map x, between the side walls, for a
## body standing on the floor: solid brushes that reach above 0.05 m and start
## below `zhi`. Returns [[y0, y1], ...].
func _free_at(x: float, zhi: float, solid_end: int) -> Array:
	var blocks: Array = []
	for b in solid_end:
		var bb := _brush_box(b)
		if bb.position.x >= x or bb.end.x <= x:
			continue
		if bb.end.z <= 0.05 or bb.position.z >= zhi:
			continue
		if bb.end.y <= -HW or bb.position.y >= HW:
			continue
		blocks.append([maxf(bb.position.y, -HW), minf(bb.end.y, HW)])
	blocks.sort_custom(func(a, c): return a[0] < c[0])
	var free: Array = []
	var cursor := -HW
	for blk: Array in blocks:
		if blk[0] > cursor + 1e-4:
			free.append([cursor, blk[0]])
		cursor = maxf(cursor, blk[1])
	if cursor < HW - 1e-4:
		free.append([cursor, HW])
	return free


func _audit(name: String) -> bool:
	var ok := true
	var solid_end: int = _ghost_from if _ghost_from >= 0 else _brushes.size()

	# 1. No brush overlaps another, mesh-only ones included: they are drawn.
	var pairs := brush_overlaps()
	if not pairs.is_empty():
		ok = false
		print("      OVERLAP  %d brush pair(s):" % pairs.size())
		for i in mini(pairs.size(), 8):
			var p: Array = pairs[i]
			print("               b%d (%s) x b%d (%s) share %s" % [p[0], _brush_box(p[0]), p[1], _brush_box(p[1]), p[2]])
	else:
		print("      overlaps 0")

	# 2. Nothing solid between 0.25 m and 0.5 m.
	for b in solid_end:
		var bb := _brush_box(b)
		if bb.end.z > 0.25 + 1e-4 and bb.end.z <= 0.5 + 1e-4 and bb.position.z < 0.25:
			ok = false
			print("      BAND     solid b%d tops out at %.3f m — inside 0.25..0.5 m: %s" % [b, bb.end.z, bb])

	if name in ["railhead_trackbed", "railhead_hull_motive", "railhead_station"]:
		return ok

	# 3. The lane. At every x, the widest free gap for a 3.0 m tall body.
	var worst := INF
	var at := 0.0
	var x := -END + 0.0625
	while x < END:
		var best := 0.0
		for g: Array in _free_at(x, WALKER_H, solid_end):
			best = maxf(best, g[1] - g[0])
		if best < worst:
			worst = best
			at = x
		x += 0.125
	print("      lane     narrowest clear width %.3f m at x=%.2f  (needs >= %.1f)" % [worst, at, MIN_LANE])
	if worst < MIN_LANE - 1e-4:
		ok = false
		print("      FAIL     the lane is under %.1f m" % MIN_LANE)

	# 4. The doorways. Width is the free gap containing y=0 at the bulkhead,
	# height is the lowest solid over it.
	for end: float in [1.0, -1.0]:
		var dx: float = end * (END + 0.125)
		var gap := 0.0
		for g: Array in _free_at(dx, WALKER_H, solid_end):
			if g[0] <= 1e-4 and g[1] >= -1e-4:
				gap = g[1] - g[0]
		var height := INF
		for b in solid_end:
			var bb := _brush_box(b)
			if bb.position.x < dx and bb.end.x > dx and bb.position.y < 0.0 and bb.end.y > 0.0 and bb.position.z > 0.05:
				height = minf(height, bb.position.z)
		var label := "front" if end > 0.0 else "rear "
		if gap == 0.0:
			print("      door     %s sealed" % label)
		else:
			print("      door     %s %.3f m wide x %.3f m high  (needs >= %.1f x %.1f)" % [label, gap, height, MIN_DOOR, WALKER_H])
			if gap < MIN_DOOR - 1e-4 or height < WALKER_H - 1e-4:
				ok = false
				print("      FAIL     a doorway a Walker cannot pass")
	return ok
