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
	"railhead_trackbed": "_trackbed",
}

# ── The envelope. The builder reads these too: describe once. ────────────────

const HL := 12.0            ## half the car's outer length (24 m)
const END := 11.75          ## the inside face of an end bulkhead
const HW := 4.5             ## half the internal width (9.0 m)
const OW := 4.75            ## half the outer width
const H := 4.0              ## internal height, floor to roof underside
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
const BAYS: Array = [Vector2(-6.0, 3.0), Vector2(-6.0, -3.0), Vector2(6.0, 3.0), Vector2(6.0, -3.0)]
## The barracks has twelve racks and the squad is four.
const RACK_PITCH := 3.7
const RACK_Y := 3.2
## Fabrication's mounts: the three with machines on them and the three without.
const FAB_X: Array = [-7.0, -0.5, 6.0]

## Lamp positions (map x, map y) per car; the builder puts a light under each.
const LAMPS := {
	"ops": [[-8.5, 0.0], [8.5, 0.0]],
	"repair": [[-6.0, 3.0], [-6.0, -3.0], [6.0, 3.0], [6.0, -3.0], [0.0, 0.0]],
	"armoury": [[-8.0, 0.0], [0.0, 0.0], [8.0, 0.0]],
	"fab": [[-8.0, 0.0], [0.0, 0.0], [8.0, 0.0]],
	"barracks": [[-8.0, 0.0], [0.0, 0.0], [8.0, 0.0]],
	"platform": [[-6.0, 0.0], [6.0, 0.0]],
}

# ── Textures. Every one has a material in textures/PSX_Textures/. ────────────

const HULL := "PSX_Textures/metal_wall_2"
const FRAME_T := "PSX_Textures/metal_wall_1"
const OPS_T := "PSX_Textures/metal_wall_3"
const PLATE := "PSX_Textures/metal_wall_5"
const FLOOR_T := "PSX_Textures/metal_floor_1"
const GRATE := "PSX_Textures/grate_perf"
const RUST := "PSX_Textures/metal_rusty_tsk_2"
const HAZARD := "PSX_Textures/metal_rusty_tsk_1"
const LAMP_T := "PSX_Textures/hl_office_complex_style_drop_ceiling_1_1"
const GLOW := "PSX_Textures/glitch_tx_1"
const SCREEN := "PSX_Textures/glass_dark"
const BED := "PSX_Textures/concrete_tx_4"
const BALLAST := "PSX_Textures/concrete_3"

var _failed := false


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

## Floor, roof, two side walls and two end bulkheads. An open end has a 3.2 m x
## 3.4 m doorway; a sealed end is a wall. The walls butt the floor and the roof
## and never overlap them: the floor and roof run the full outer width, the
## walls stand between them, the bulkheads stand between the walls.
func _shell(open_front: bool, open_rear: bool, wall: Variant = HULL) -> void:
	box(Vector3(-HL, -OW, -0.5), Vector3(HL, OW, 0.0), {"top": FLOOR_T, "side": wall, "bottom": RUST})
	box(Vector3(-HL, -OW, H), Vector3(HL, OW, H + 0.25), {"top": wall, "side": wall, "bottom": PLATE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-HL, s * HW, 0.0), Vector3(HL, s * OW, H), wall)
	_bulkhead(1.0, open_front, wall)
	_bulkhead(-1.0, open_rear, wall)


func _bulkhead(end: float, open: bool, wall: Variant) -> void:
	var x0: float = END if end > 0.0 else -HL
	var x1: float = HL if end > 0.0 else -END
	if not open:
		box(Vector3(x0, -HW, 0.0), Vector3(x1, HW, H), wall)
		return
	box(Vector3(x0, -HW, 0.0), Vector3(x1, -DOOR, H), wall)
	box(Vector3(x0, DOOR, 0.0), Vector3(x1, HW, H), wall)
	box(Vector3(x0, -DOOR, DOOR_H), Vector3(x1, DOOR, H), wall)


# ── Detail every car shares. All of it is mesh-only. ─────────────────────────

func _lamp(x: float, y: float, top: float = H) -> void:
	box(Vector3(x - 0.0625, y - 0.0625, 3.4), Vector3(x + 0.0625, y + 0.0625, top), FRAME_T)
	box(Vector3(x - 0.5, y - 0.25, 3.1), Vector3(x + 0.5, y + 0.25, 3.4), LAMP_T)


func _lamps(car: String, top: float = H) -> void:
	for p: Array in LAMPS[car]:
		_lamp(p[0], p[1], top)


## Roof beams across the car, between the lamps. They hang from the roof
## underside and stop at 3.85, well above a Walker.
func _beams(xs: Array) -> void:
	for x: float in xs:
		box(Vector3(x - 0.15, -HW, 3.75), Vector3(x + 0.15, HW, H), FRAME_T)


## Floor markings: the 3.0 m lane edges. 0.0625 m proud and mesh-only; the
## baker climbs 0.25 m, so a paint line costs the squad nothing.
func _lane_lines() -> void:
	for s: float in [-1.0, 1.0]:
		box(Vector3(-11.5, s * LANE - (0.0625 if s > 0.0 else 0.0) , 0.0), Vector3(11.5, s * LANE + (0.0 if s > 0.0 else 0.0625), 0.0625), HAZARD)


## Two bogies and their wheels under the floor, between the floor's underside
## and the rail head 1.0 m below it. The wheels rest on rail tops that
## railhead_trackbed puts at exactly this depth.
func _bogies() -> void:
	for cx: float in [-7.5, 7.5]:
		box(Vector3(cx - 1.8, -1.05, -0.75), Vector3(cx + 1.8, 1.05, -0.5), PLATE)
		for wx: float in [-1.0, 1.0]:
			for s: float in [-1.0, 1.0]:
				var ym := s * GAUGE * 0.5
				box(Vector3(cx + wx - 0.3, ym - 0.075, -1.0), Vector3(cx + wx + 0.3, ym + 0.075, -0.75), RUST)


## A 7-segment digit standing 1/16 m proud of a wall face, built from boxes
## that touch and never overlap. `face` is the wall's y; `s` is which wall
## (+1 is the +Y wall); `u0` is where the digit starts in the direction a
## reader walking the car in +X would read it.
const SEGS := {0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd", 6: "afgedc", 7: "abc", 8: "abcdefg", 9: "abcdfg"}


func _digit(d: int, u0: float, v0: float, h: float, face: float, s: float, tex: Variant = GLOW) -> void:
	var w := h * 0.5
	var t := h * 0.125
	var rects := {
		"a": [t, w - t, h - t, h], "d": [t, w - t, 0.0, t], "g": [t, w - t, h * 0.5 - t * 0.5, h * 0.5 + t * 0.5],
		"f": [0.0, t, h * 0.5 + t * 0.5, h - t], "b": [w - t, w, h * 0.5 + t * 0.5, h - t],
		"e": [0.0, t, t, h * 0.5 - t * 0.5], "c": [w - t, w, t, h * 0.5 - t * 0.5],
	}
	var y0: float = face - 0.0625 if s > 0.0 else face
	var y1: float = face if s > 0.0 else face + 0.0625
	for seg in String(SEGS[d]):
		var r: Array = rects[seg]
		var xa: float = u0 + r[0] if s > 0.0 else u0 - r[1]
		var xb: float = u0 + r[1] if s > 0.0 else u0 - r[0]
		box(Vector3(xa, y0, v0 + r[2]), Vector3(xb, y1, v0 + r[3]), tex)


## A number of up to two digits, centred on u, on a wall face.
func _number(n: int, uc: float, v0: float, h: float, face: float, s: float, tex: Variant = GLOW, pad: bool = false) -> void:
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
		var u: float = uc + off if s > 0.0 else uc - off
		_digit(digits[i], u, v0, h, face, s, tex)


# ── The cars ─────────────────────────────────────────────────────────────────

## 1. MOTIVE. Not enterable: a hull the length of a car, a cab, and the things
## that sell that the building moves. One solid box for collision; the rest is
## drawn. Its rear (-X) face is flush against Operations' sealed front.
func _hull_motive() -> void:
	box(Vector3(-HL, -OW, -0.5), Vector3(HL, OW, H + 0.25), {"top": HULL, "side": HULL, "bottom": RUST})
	box(Vector3(-HL, -3.5, H + 0.25), Vector3(-4.0, 3.5, 6.0), HULL)
	no_collision()
	# Radiator louvres on both flanks, standing clear of the hull face.
	for s: float in [-1.0, 1.0]:
		for i in 5:
			var x := -10.0 + i * 4.0
			box(Vector3(x, s * OW if s > 0.0 else -OW - 0.0625, 1.0), Vector3(x + 3.0, (OW + 0.0625) if s > 0.0 else -OW, 3.0), GRATE)
	# Exhaust stacks and a roof vent on the long deck forward of the cab.
	for sx: float in [2.0, 6.0, 10.0]:
		box(Vector3(sx - 0.4, -0.4, H + 0.25), Vector3(sx + 0.4, 0.4, 5.2), RUST)
		box(Vector3(sx - 0.6, -0.6, 5.2), Vector3(sx + 0.6, 0.6, 5.4), FRAME_T)
	# Headlamp bank on the front (+X) face.
	for s: float in [-1.0, 1.0]:
		box(Vector3(HL, s * 3.0 - 0.5, 2.6), Vector3(HL + 0.0625, s * 3.0 + 0.5, 3.4), LAMP_T)
	# The cab's windowless slit. Armoured, so no glass, just a dark reveal.
	box(Vector3(-4.0, -2.5, 5.0), Vector3(-3.9375, 2.5, 5.5), SCREEN)
	_bogies()


## 2. OPERATIONS. Low, dark. The brightest thing is the projection. The table
## is at chest height for a Walker's crew, so the player looks DOWN on it.
## The table is 2.5 m wide, leaving 3.25 m each side of it: it is the one thing
## in the base that stands in the lane, and the lane goes round it.
func _car_ops() -> void:
	_shell(false, true, OPS_T)
	# Pedestal, then the slab on it. Tops at 1.1 and 1.3 m: nothing in the
	# 0.25-0.5 m band.
	box(Vector3(-0.7, -0.7, 0.0), Vector3(0.7, 0.7, 1.1), PLATE)
	box(Vector3(-3.0, -1.25, 1.1), Vector3(3.0, 1.25, 1.3), {"top": SCREEN, "side": PLATE, "bottom": PLATE})
	# Equipment cabinets along the walls, clear of the table's length so the
	# side lanes stay 3.25 m wide where they pass it.
	for s: float in [-1.0, 1.0]:
		for x0: float in [-10.5, -6.5, 3.5, 7.5]:
			box(Vector3(x0, s * 3.9, 0.0), Vector3(x0 + 3.0, s * HW, 3.0), PLATE)
	no_collision()
	# The dropped ceiling is what makes it low: 3.5 m clear, 0.5 above a Walker.
	box(Vector3(-END, -HW, 3.5), Vector3(END, HW, H), {"top": PLATE, "side": PLATE, "bottom": OPS_T})
	# The projection: a flat plan 0.15 m above the slab (1.45 m, under the
	# player's 1.7), a relief on it, and the projector ring hanging above.
	box(Vector3(-2.7, -1.05, 1.3), Vector3(2.7, 1.05, 1.34375), GLOW)
	box(Vector3(-2.2, -0.6, 1.34375), Vector3(-1.4, 0.0, 1.5), GLOW)
	box(Vector3(0.2, 0.1, 1.34375), Vector3(0.8, 0.7, 1.45), GLOW)
	box(Vector3(1.6, -0.5, 1.34375), Vector3(2.4, 0.4, 1.4), GLOW)
	box(Vector3(-1.5, -1.5, 3.3), Vector3(1.5, 1.5, 3.5), LAMP_T)
	# Screens on the cabinet fronts, above the dim band.
	for s: float in [-1.0, 1.0]:
		for x0: float in [-10.5, -6.5, 3.5, 7.5]:
			var face: float = s * 3.9
			var y0: float = face - 0.0625 if s > 0.0 else face
			var y1: float = face if s > 0.0 else face + 0.0625
			box(Vector3(x0 + 0.4, y0, 2.0), Vector3(x0 + 2.6, y1, 2.9), SCREEN)
	_lamps("ops", 3.5)
	_lane_lines()
	_bogies()


## 3. REPAIR. Four bays, two a side, each a separate 6 m bay between full-depth
## divider fins, so the count is four at a glance. Each is 3.0 m deep: a Walker
## (1.7 m) stands in it with 0.65 m to spare, and the 3.0 m lane in front is
## untouched. Empty bays read as capacity. Parts racks in between and at the
## ends carry their bins at the top and bottom and nothing across the middle:
## the player's band stays empty.
func _car_repair() -> void:
	_shell(true, true, HULL)
	for s: float in [-1.0, 1.0]:
		for fx: float in [-9.0, -3.0, 3.0, 9.0]:
			box(Vector3(fx - 0.15, s * 1.75, 0.0), Vector3(fx + 0.15, s * HW, 3.6), FRAME_T)
		# Parts racks: the centre run and both ends.
		box(Vector3(-2.85, s * 3.5, 0.0), Vector3(2.85, s * HW, 3.2), PLATE)
		box(Vector3(-END, s * 3.5, 0.0), Vector3(-9.15, s * HW, 3.2), PLATE)
		box(Vector3(9.15, s * 3.5, 0.0), Vector3(END, s * HW, 3.2), PLATE)
	# Cradle clamps against the back wall, one pair per bay.
	for b: Vector2 in BAYS:
		for dx: float in [-1.3, 1.3]:
			var ya: float = 4.1 if b.y > 0.0 else -HW
			var yb: float = HW if b.y > 0.0 else -4.1
			box(Vector3(b.x + dx - 0.15, ya, 0.0), Vector3(b.x + dx + 0.15, yb, 3.4), FRAME_T)
	no_collision()
	var n := 1
	for b: Vector2 in BAYS:
		var s: float = signf(b.y)
		# The cradle: two saddles on foot plates, flat to the floor and shaped
		# for a chassis. Mesh-only, so a Walker steps into it.
		for dx: float in [-1.25, 1.25]:
			box(Vector3(b.x + dx - 0.2, s * 2.0 if s > 0.0 else -4.0, 0.0), Vector3(b.x + dx + 0.2, 4.0 if s > 0.0 else s * 2.0, 0.1875), HAZARD)
			box(Vector3(b.x + dx - 0.2, s * 2.4 if s > 0.0 else -3.6, 0.1875), Vector3(b.x + dx + 0.2, 3.6 if s > 0.0 else s * 2.4, 0.5), RUST)
		# The bay's front edge on the floor, and its number on the back wall.
		box(Vector3(b.x - 2.7, s * LANE if s > 0.0 else -LANE - 0.125, 0.0), Vector3(b.x + 2.7, (LANE + 0.125) if s > 0.0 else s * LANE, 0.0625), HAZARD)
		_number(n, b.x, 2.2, 1.0, s * HW, s)
		# Overhead gantry beam over the bay and two tool arms off it, all at or
		# above 3.2 m: a Walker's head clears them.
		var by0: float = 2.3 if s > 0.0 else -2.5
		var by1: float = 2.5 if s > 0.0 else -2.3
		box(Vector3(b.x - 2.8, by0, 3.55), Vector3(b.x + 2.8, by1, 3.85), FRAME_T)
		for dx: float in [-1.8, 1.8]:
			box(Vector3(b.x + dx - 0.15, by0, 3.2), Vector3(b.x + dx + 0.15, by1, 3.55), RUST)
		n += 1
	# Bins on the racks' faces, bottom and top rows only.
	for s: float in [-1.0, 1.0]:
		for run: Array in [[-2.85, 2.85], [-END, -9.15], [9.15, END]]:
			var x := float(run[0]) + 0.1
			while x + 0.9 <= float(run[1]) - 0.05:
				for row: Array in [[0.3, 0.8], [0.9, 1.3], [2.3, 2.75], [2.85, 3.1]]:
					var ya: float = s * 3.5 - 0.3 if s > 0.0 else s * 3.5
					var yb: float = s * 3.5 if s > 0.0 else s * 3.5 + 0.3
					box(Vector3(x, minf(ya, yb), row[0]), Vector3(x + 0.9, maxf(ya, yb), row[1]), RUST)
				x += 1.0
	_lamps("repair")
	_lane_lines()
	_beams([-10.0, -2.0, 2.0, 10.0])
	_bogies()


## 4. ARMOURY. Wall racks, three sections a side, one per frame type, each with
## its own colour so a Walker's crew can find theirs. Racks not crates: you see
## what you own. The racks are 0.6 m deep and everything on them is drawn.
func _car_armoury() -> void:
	_shell(true, true, HULL)
	for s: float in [-1.0, 1.0]:
		for x0: float in [-11.0, -3.5, 4.0]:
			box(Vector3(x0, s * 3.9, 0.0), Vector3(x0 + 7.0, s * HW, 3.2), PLATE)
	no_collision()
	var tex := [HAZARD, GRATE, RUST]
	for s: float in [-1.0, 1.0]:
		var ya: float = s * 3.9 - 0.25 if s > 0.0 else s * 3.9
		var yb: float = s * 3.9 if s > 0.0 else s * 3.9 + 0.25
		var si := 0
		for x0: float in [-11.0, -3.5, 4.0]:
			# A header bar naming the section, then the weapons hung under it.
			box(Vector3(x0 + 0.2, minf(ya, yb), 3.0), Vector3(x0 + 6.8, maxf(ya, yb), 3.15), tex[si])
			var x := x0 + 0.5
			while x + 0.2 <= x0 + 6.6:
				box(Vector3(x, minf(ya, yb), 0.5), Vector3(x + 0.2, maxf(ya, yb), 2.8), tex[si])
				x += 0.45
			si += 1
	_lamps("armoury")
	_lane_lines()
	_beams([-10.0, -4.0, 4.0, 10.0])
	_bogies()


## 5. FABRICATION. A machine shop, half-finished. Three mounts along the -Y wall
## carry machines; the same three along the +Y wall are bare plates with their
## anchor studs and an unfinished frame beside them. The software branch that
## builds it out is not here yet, and the empty mounts say so.
func _car_fab() -> void:
	_shell(true, true, HULL)
	for x: float in FAB_X:
		# Fitted: a bed and a head, standing 2.2 m, against the -Y wall.
		box(Vector3(x - 1.5, -HW, 0.0), Vector3(x + 1.5, -3.0, 1.0), PLATE)
		box(Vector3(x - 1.5, -HW, 1.0), Vector3(x - 0.3, -3.2, 2.2), FRAME_T)
	no_collision()
	for x: float in FAB_X:
		# Empty: a floor plate (0.1875 m, under the baker's climb and mesh-only
		# anyway) and four studs on it.
		box(Vector3(x - 1.5, 3.0, 0.0), Vector3(x + 1.5, HW, 0.1875), GRATE)
		for dx: float in [-1.2, 1.2]:
			for yy: float in [3.3, 4.2]:
				box(Vector3(x + dx - 0.1, yy - 0.1, 0.1875), Vector3(x + dx + 0.1, yy + 0.1, 0.4), RUST)
		# Overhead rail with an empty hook block, for the tool that is not here.
		box(Vector3(x - 1.5, 3.6, 3.55), Vector3(x + 1.5, 3.8, 3.85), FRAME_T)
	# The unfinished frame: uprights and one cross-member, no panels.
	for dx: float in [-1.2, 1.2]:
		box(Vector3(10.0 + dx - 0.1, 3.4, 0.0), Vector3(10.0 + dx + 0.1, 3.6, 3.0), FRAME_T)
	box(Vector3(8.7, 3.4, 3.0), Vector3(11.3, 3.6, 3.2), FRAME_T)
	# Fitted machines' tool heads, hanging at 3.2 m and above.
	for x: float in FAB_X:
		box(Vector3(x - 1.5, -3.8, 3.55), Vector3(x + 1.5, -3.6, 3.85), FRAME_T)
		box(Vector3(x - 0.5, -3.8, 3.2), Vector3(x + 0.5, -3.6, 3.55), RUST)
	_lamps("fab")
	_lane_lines()
	_beams([-10.0, -4.0, 4.0])
	_bogies()


## 6. BARRACKS. Twelve standing racks, numbered, in a car built for a squad of
## twelve. The player will have four. A rack is a back plate and fins, 3.5 m
## between fins for a 1.7 m body. Robots do not sleep; there is nowhere to
## sleep. The emptiness is the content.
func _car_barracks() -> void:
	_shell(true, true, HULL)
	var half := RACK_PITCH * 3.0 + 0.1
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, s * 4.2, 0.0), Vector3(half, s * HW, 3.4), PLATE)
		for i in 7:
			var fx := -RACK_PITCH * 3.0 + i * RACK_PITCH
			box(Vector3(fx - 0.1, s * 2.4, 0.0), Vector3(fx + 0.1, s * 4.2, 3.4), FRAME_T)
	no_collision()
	var n := 1
	for s: float in [1.0, -1.0]:
		for i in 6:
			var cx := -RACK_PITCH * 2.5 + i * RACK_PITCH
			# Charge pad on the floor (0.125 m) and the rack's number above.
			box(Vector3(cx - 0.9, s * RACK_Y - 0.9, 0.0), Vector3(cx + 0.9, s * RACK_Y + 0.9, 0.125), GRATE)
			_number(n, cx, 2.75, 0.5, s * 4.2, s, GLOW, true)
			# Charge connector on the back plate, at a Walker's chest.
			box(Vector3(cx - 0.2, minf(s * 4.2 - 0.125 * s, s * 4.2), 1.6), Vector3(cx + 0.2, maxf(s * 4.2 - 0.125 * s, s * 4.2), 1.9), LAMP_T)
			n += 1
	_lamps("barracks")
	_lane_lines()
	_beams([-10.0, -4.0, 4.0, 10.0])
	_bogies()


## 7. PLATFORM. The door, and a boarding ramp down to the station. Departure and
## return; the level exit is at the rear door. The ramp is the one change of
## level in the base: 1.2 m over 7.5 m, 4.0 m wide, a wedge that meets the floor
## flush at the door and the ground at its toe with no lip.
func _car_platform() -> void:
	_shell(true, true, HULL)
	ramp(-HL - RAMP_LEN, -RAMP_HALF_W, -HL, RAMP_HALF_W, -DECK_RISE, -DECK_RISE, 0.0, "+x", {"top": GRATE, "side": PLATE, "bottom": PLATE})
	# Lockers, tall and against the walls, in the forward half.
	for s: float in [-1.0, 1.0]:
		for x0: float in [3.0, 7.0]:
			box(Vector3(x0, s * 3.9, 0.0), Vector3(x0 + 3.0, s * HW, 3.0), PLATE)
	no_collision()
	# The rear door's frame, proud of the outer face and clear of the opening.
	for s: float in [-1.0, 1.0]:
		var ya: float = DOOR if s > 0.0 else -DOOR - 0.25
		var yb: float = DOOR + 0.25 if s > 0.0 else -DOOR
		box(Vector3(-HL - 0.125, ya, 0.0), Vector3(-HL, yb, DOOR_H), HAZARD)
	box(Vector3(-HL - 0.125, -DOOR - 0.25, DOOR_H), Vector3(-HL, DOOR + 0.25, DOOR_H + 0.25), HAZARD)
	# Muster squares on the floor, forward of the arrival point.
	for i in 4:
		var cx := 1.0 + i * 2.5
		box(Vector3(cx - 0.9, -0.9, 0.0), Vector3(cx + 0.9, -0.8125, 0.0625), HAZARD)
		box(Vector3(cx - 0.9, 0.8125, 0.0), Vector3(cx + 0.9, 0.9, 0.0625), HAZARD)
	_lamps("platform")
	_lane_lines()
	_beams([-10.0, -2.0, 2.0, 10.0])
	_bogies()


## THE BED. A slab at the ground's height, rails on sleepers down the middle,
## and the station apron where the ramp comes down. Map X runs along the train
## and is longer at the platform (-X) end: the ramp and 13.5 m of apron.
## The ground is ONE brush with its top at 0; the car floors are 1.2 m above.
func _trackbed() -> void:
	var rear := -(HL * 7.0 + RAMP_LEN + 13.5)
	var front := HL * 7.0 + 6.0
	box(Vector3(rear + 0.0, -12.0, -2.0), Vector3(front, 12.0, 0.0), {"top": BED, "side": BALLAST, "bottom": BALLAST})
	no_collision()
	# Ballast, sleepers, rails. Each stands on the one before; none overlaps.
	var x0 := -HL * 7.0
	var x1 := HL * 7.0 + 6.0
	box(Vector3(x0, -1.7, 0.0), Vector3(x1, 1.7, 0.0625), BALLAST)
	var x := x0 + 0.5
	while x + 0.3 < x1:
		box(Vector3(x, -1.3, 0.0625), Vector3(x + 0.3, 1.3, 0.125), RUST)
		x += 1.0
	for s: float in [-1.0, 1.0]:
		var ym := s * GAUGE * 0.5
		box(Vector3(x0, ym - 0.0625, 0.125), Vector3(x1, ym + 0.0625, 0.1875), FRAME_T)


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

	if name == "railhead_trackbed" or name == "railhead_hull_motive":
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
