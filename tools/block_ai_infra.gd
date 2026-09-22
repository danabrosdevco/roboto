extends "res://tools/block_doodads.gd"

# ─────────────────────────────────────────────
# BLOCK AI INFRA — what the machines built for themselves, as TrenchBroom
# blocks:
#
#   maps/blocks/solar/solar_*.map — fixed and tracking panel rows, a field
#       the size of a building lot, heliostats round a solar tower, battery
#       containers, inverter skids, drone docks.
#   maps/blocks/compute/compute_*.map — server racks (single, in a row,
#       knocked over), chillers and a chiller yard, a generator, a
#       transformer, a data hall with a walkable roof, a compute obelisk,
#       cable runs, network cabinets, a satellite dish.
#   maps/blocks/landmarks/landmark_*.map — set pieces a map is built round:
#       the ground anchor of an orbital tether.
#
#   godot --headless --path . --script res://tools/block_ai_infra.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_ai_infra.gd -- maps/blocks --force
#
# Built on block_doodads.gd, which this extends: the same brush kit, hull,
# conventions and no-overwrite rule. Build prefabs with block_prefabs.gd.
#
# The look is the machines': repeated, exact, grey clad and black glass, with
# glitch_tx_1 standing in for glowing circuitry. Give that material some
# emission to make it glow in the dark.
# ─────────────────────────────────────────────

const PV := "PSX_Textures/tile_floor_tx_3@0.3"
const GLASS := "PSX_Textures/rubber_tsk_1"
const GLOW := "PSX_Textures/glitch_tx_1@0.5"
const GRATING := "PSX_Textures/metal_floor_3@0.25"
const CLAD := "PSX_Textures/metal_wall_tx_1"
const TECH_WALL := "PSX_Textures/concrete_wall_12_1"
const PALE := "PSX_Textures/concrete_1"

const PANEL := {"top": PV, "side": METAL, "bottom": METAL}
const MIRROR := {"top": GLASS, "side": METAL, "bottom": METAL}
const PAD := {"top": DECK, "side": CONCRETE, "bottom": CONCRETE}


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
		print("usage: godot --headless --path . --script res://tools/block_ai_infra.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var solar := {
		"solar_panel_row": _solar_panel_row,
		"solar_tracker_row": _solar_tracker_row,
		"solar_field_lot": _solar_field_lot,
		"solar_heliostat": _solar_heliostat,
		"solar_tower_field": _solar_tower_field,
		"solar_battery_container": _battery_container,
		"solar_inverter_skid": _inverter_skid,
		"solar_drone_dock": _drone_dock,
	}
	var compute := {
		"compute_server_rack": _server_rack,
		"compute_rack_row": _rack_row,
		"compute_racks_toppled": _racks_toppled,
		"compute_cooling_unit": _cooling_unit,
		"compute_chiller_yard": _chiller_yard,
		"compute_generator": _generator,
		"compute_transformer": _transformer,
		"compute_data_hall": _data_hall,
		"compute_obelisk": _obelisk,
		"compute_cable_run": _cable_run,
		"compute_network_cabinet": _network_cabinet,
		"compute_satellite_dish": _satellite_dish,
	}
	var landmarks := {
		"landmark_tether_anchor": _tether_anchor,
	}
	var skipped := 0
	for pair in [[base.path_join("solar"), solar], [base.path_join("compute"), compute], [base.path_join("landmarks"), landmarks]]:
		var dir: String = pair[0]
		if not DirAccess.dir_exists_absolute(dir):
			var err := DirAccess.make_dir_recursive_absolute(dir)
			if err != OK:
				print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
				quit(1)
				return
		var made: Dictionary = pair[1]
		for name: String in made:
			var path := dir.path_join(name + ".map")
			if FileAccess.file_exists(path) and not force:
				print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
				skipped += 1
				continue
			_brushes = []
			(made[name] as Callable).call()
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
				quit(1)
				return
			f.store_string(_map_text())
			f.close()
			print("      %-26s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK AI INFRA DONE%s" % ((" (%d skipped)" % skipped) if skipped > 0 else ""))
	quit()


# ── Parts ────────────────────────────────────────────────────────────────────

## A round bar between two points in any direction: the hull of two rings.
## Keep r at 0.06 m or more, or the rings round away to nothing on the grid.
func pipe(a: Vector3, b: Vector3, r: float, tex: Variant, sides: int = 8) -> void:
	var axis := (b - a).normalized()
	var s := axis.cross(Vector3(0, 0, 1) if absf(axis.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	var t := axis.cross(s).normalized()
	var pts: Array = []
	for i in sides:
		var ang := TAU * (i + 0.5) / sides
		var o := (s * cos(ang) + t * sin(ang)) * r
		pts.append(a + o)
		pts.append(b + o)
	solid(pts, tex)


## Points turned `yaw` degrees about the vertical line through `about`.
func _yaw(points: Array, about: Vector3, yaw: float) -> Array:
	var r := deg_to_rad(yaw)
	var out: Array = []
	for p: Vector3 in points:
		var d := p - about
		out.append(about + Vector3(d.x * cos(r) - d.y * sin(r), d.x * sin(r) + d.y * cos(r), d.z))
	return out


## A box between two corners, turned `yaw` degrees about `about`.
func box_yawed(a: Vector3, b: Vector3, about: Vector3, yaw: float, tex: Variant) -> void:
	var pts: Array = []
	for x in [a.x, b.x]:
		for y in [a.y, b.y]:
			for z in [a.z, b.z]:
				pts.append(Vector3(x, y, z))
	solid(_yaw(pts, about, yaw), tex)


## A row of fixed solar modules along Y at depth `cx`, tilted `tilt` degrees
## to face -X: `modules` panels over y0..y1, the table `depth` deep across the
## slope with its low edge `low` metres up, on purlins and legs.
func panel_row(cx: float, y0: float, y1: float, depth: float, tilt: float, low: float, modules: int) -> void:
	var run := depth * cos(deg_to_rad(tilt))
	var rise := depth * sin(deg_to_rad(tilt))
	var x0 := cx - run * 0.5
	var x1 := cx + run * 0.5
	var w := (y1 - y0) / modules
	for i in modules:
		flight(x0, y0 + i * w + 0.03, x1, y0 + (i + 1) * w - 0.03, low, low + rise, "+x", 0.05, PANEL)
	for t in [0.2, 0.8]:
		var z: float = low + rise * t - 0.1
		beam(Vector3(lerpf(x0, x1, t), y0, z), Vector3(lerpf(x0, x1, t), y1, z), 0.08, METAL)
	var legs := maxi(2, int(ceil((y1 - y0) / 4.0)) + 1)
	for i in legs:
		var y := lerpf(y0 + 0.3, y1 - 0.3, float(i) / (legs - 1))
		for t in [0.2, 0.8]:
			post(lerpf(x0, x1, t), y, -0.3, low + rise * t - 0.14, 0.1, METAL)


## A heliostat at `c`: a 3 m mirror on a pedestal, tipped 40° to face its
## local -X, the whole thing turned by `yaw` degrees.
func heliostat_at(c: Vector3, yaw: float) -> void:
	cylinder(c + Vector3(0, 0, -0.3), 0.4, 0.5, 8, CONCRETE)
	cylinder(c + Vector3(0, 0, 0.2), 0.14, 2.1, 8, METAL)
	box_yawed(c + Vector3(-0.25, -0.25, 2.2), c + Vector3(0.25, 0.25, 2.6), c, yaw, RUST)
	var half := 1.5 * cos(deg_to_rad(40.0))
	var rise := 1.5 * sin(deg_to_rad(40.0))
	var pts: Array = []
	for x in [-half, half]:
		for y in [-1.5, 1.5]:
			var z: float = 2.75 + (rise if x > 0.0 else -rise)
			pts.append(c + Vector3(x, y, z))
			pts.append(c + Vector3(x, y, z - 0.08))
	solid(_yaw(pts, c, yaw), MIRROR)


## One 42U rack at `c`: 0.6 m wide (Y), 1.2 m deep (X), perforated doors
## front (-X) and back, a status strip down the front; turned by `yaw`.
func rack_at(c: Vector3, yaw: float) -> void:
	box_yawed(c + Vector3(-0.6, -0.3, 0.0), c + Vector3(0.6, 0.3, 2.1), c, yaw, {"top": METAL, "side": SHUTTER, "bottom": METAL})
	box_yawed(c + Vector3(-0.63, -0.28, 0.05), c + Vector3(-0.6, 0.28, 2.02), c, yaw, GRATING)
	box_yawed(c + Vector3(0.6, -0.28, 0.05), c + Vector3(0.63, 0.28, 2.02), c, yaw, GRATING)
	box_yawed(c + Vector3(-0.66, 0.15, 0.3), c + Vector3(-0.63, 0.22, 1.9), c, yaw, GLOW)


## A packaged chiller 5.6 m long (Y) with three fans on top, at `c`.
func cooler_at(c: Vector3) -> void:
	for y in [-2.3, 2.3]:
		box(c + Vector3(-1.0, y - 0.15, -0.1), c + Vector3(1.0, y + 0.15, 0.3), METAL)
	box(c + Vector3(-1.15, -2.8, 0.3), c + Vector3(1.15, 2.8, 2.3), CLAD)
	for s in [-1.0, 1.0]:
		box(c + Vector3(s * 1.15, -2.6, 0.5), c + Vector3(s * 1.21, 2.6, 1.9), GRATING)
	for y in [-1.8, 0.0, 1.8]:
		cylinder(c + Vector3(0, y, 2.3), 0.82, 0.35, 10, METAL)
		cylinder(c + Vector3(0, y, 2.65), 0.74, 0.05, 10, GRATING)
	for z in [0.7, 1.2]:
		pipe(c + Vector3(0.3, -2.8, z), c + Vector3(0.3, -3.6, z), 0.12, RUST, 6)
		pipe(c + Vector3(0.3, -3.6, z), c + Vector3(0.3, -3.6, 0.0), 0.12, RUST, 6)


## An inverter skid at `c`: two inverter cabinets and a small transformer on
## a steel base, a cable tray over them.
func inverter_at(c: Vector3) -> void:
	box(c + Vector3(-3.0, -1.2, -0.1), c + Vector3(3.2, 1.2, 0.2), METAL)
	for x in [-2.0, -0.2]:
		box(c + Vector3(x - 0.8, -0.5, 0.2), c + Vector3(x + 0.8, 0.5, 2.4), CLAD)
		box(c + Vector3(x - 0.7, -0.56, 0.5), c + Vector3(x + 0.7, -0.5, 1.9), GRATING)
		box(c + Vector3(x - 0.3, -0.57, 2.0), c + Vector3(x + 0.3, -0.5, 2.15), GLOW)
	box(c + Vector3(1.4, -0.7, 0.2), c + Vector3(2.8, 0.7, 1.9), GREEN)
	for i in 5:
		var y := -0.6 + i * 0.3
		box(c + Vector3(2.8, y - 0.03, 0.4), c + Vector3(3.15, y + 0.03, 1.7), METAL)
	for y in [-0.4, 0.0, 0.4]:
		cylinder(c + Vector3(2.1, y, 1.9), 0.09, 0.6, 6, RUBBER)
	beam(c + Vector3(-2.8, 0.0, 2.5), c + Vector3(1.8, 0.0, 2.5), 0.2, METAL)


# ── Solar ────────────────────────────────────────────────────────────────────

## Sixteen metres of fixed panels, tilted 25° to face -X.
func _solar_panel_row() -> void:
	panel_row(0.0, -8.0, 8.0, 2.6, 25.0, 0.8, 8)
	pipe(Vector3(1.35, -8.0, 0.45), Vector3(1.35, 8.0, 0.45), 0.08, RUBBER, 6)


## Twenty metres of single-axis tracker: panels on a torque tube, turned 30°.
func _solar_tracker_row() -> void:
	pipe(Vector3(0, -10.0, 1.7), Vector3(0, 10.0, 1.7), 0.09, METAL, 8)
	for y in [-9.6, -5.0, 0.0, 5.0, 9.6]:
		post(0.0, y, -0.4, 1.65, 0.16, METAL)
	box(Vector3(-0.25, -0.3, 1.45), Vector3(0.25, 0.3, 1.95), RUST)
	var half := 1.1 * cos(deg_to_rad(30.0))
	var rise := 1.1 * sin(deg_to_rad(30.0))
	for i in 10:
		var y0 := -10.0 + i * 2.0
		flight(-half, y0 + 0.03, half, y0 + 1.97, 1.8 - rise, 1.8 + rise, "+x", 0.05, PANEL)


## A solar field the size of a building lot (fits 24 × 32 m): five rows of
## panels, a cable tray along their ends and an inverter skid.
func _solar_field_lot() -> void:
	for x in [-8.4, -4.2, 0.0, 4.2, 8.4]:
		panel_row(x, -12.5, 12.5, 2.6, 25.0, 0.8, 12)
	box(Vector3(-9.2, 12.8, 0.3), Vector3(9.2, 13.2, 0.45), METAL)
	for x in [-8.4, -4.2, 0.0, 4.2, 8.4]:
		post(x, 13.0, -0.3, 0.3, 0.1, METAL)
	inverter_at(Vector3(0.0, 14.4, 0.0))


func _solar_heliostat() -> void:
	heliostat_at(Vector3.ZERO, 0.0)


## A solar tower 38 m tall ringed by 21 heliostats, each tipped at it, with a
## gap on the -X side for the way to the plant building: a landmark about 44 m
## across. The band round the receiver is its hot zone.
func _solar_tower_field() -> void:
	cylinder(Vector3(0, 0, -0.5), 3.0, 28.5, 8, CONCRETE, 2.0)
	cylinder(Vector3(0, 0, 28.0), 2.6, 5.0, 8, RUST_PANEL)
	cylinder(Vector3(0, 0, 29.8), 2.66, 1.4, 8, GLOW)
	cylinder(Vector3(0, 0, 33.0), 2.0, 1.6, 8, METAL, 1.4)
	pipe(Vector3(0, 0, 34.6), Vector3(0, 0, 38.5), 0.12, METAL, 6)
	# Service platform at 26 m in eight segments: a ring is not convex.
	for i in 8:
		var pts: Array = []
		for a in [TAU * i / 8.0, TAU * (i + 1) / 8.0]:
			for r in [2.05, 3.4]:
				pts.append(Vector3(cos(a) * r, sin(a) * r, 26.0))
				pts.append(Vector3(cos(a) * r, sin(a) * r, 26.25))
		solid(pts, SLAB)
	box(Vector3(-8.0, -2.5, 0.0), Vector3(-3.2, 2.5, 3.5), CLAD)
	box(Vector3(-8.2, -2.7, 3.5), Vector3(-3.0, 2.7, 3.8), SLAB)
	window("-x", -8.0, 0.0, 0.0, 1.6, 2.4, false)
	for ring in [[14.0, 10, 0.0], [21.0, 14, 0.2]]:
		var r: float = ring[0]
		var n: int = ring[1]
		var turn: float = ring[2]
		for i in n:
			var a := TAU * i / n + turn
			if cos(a) < -0.85:
				continue   # keep the way to the plant building's door clear
			heliostat_at(Vector3(cos(a) * r, sin(a) * r, 0.0), rad_to_deg(a))


## A battery storage container: clad box with louvres, doors at +Y, and air
## handlers on the roof.
func _battery_container() -> void:
	for y in [-4.5, 0.0, 4.5]:
		box(Vector3(-1.4, y - 0.2, -0.2), Vector3(1.4, y + 0.2, 0.15), CONCRETE)
	box(Vector3(-1.22, -6.1, 0.15), Vector3(1.22, 6.1, 3.05), CLAD)
	for y in [-4.5, -1.5, 1.5, 4.5]:
		box(Vector3(-1.3, y - 0.9, 0.6), Vector3(-1.22, y + 0.9, 2.4), GRATING)
		box(Vector3(1.22, y - 0.9, 0.6), Vector3(1.3, y + 0.9, 2.4), GRATING)
	box(Vector3(-1.1, 6.1, 0.3), Vector3(1.1, 6.16, 2.9), SHUTTER)
	for y in [-3.0, 3.0]:
		box(Vector3(-0.6, y - 0.7, 3.05), Vector3(0.6, y + 0.7, 3.8), CLAD)
		cylinder(Vector3(0, y, 3.8), 0.45, 0.12, 8, GRATING)
	box(Vector3(-1.31, -6.0, 1.0), Vector3(-1.22, -5.5, 1.3), GLOW)
	pipe(Vector3(0.6, -6.1, 0.6), Vector3(0.6, -7.2, 0.0), 0.1, RUBBER, 6)


func _inverter_skid() -> void:
	inverter_at(Vector3.ZERO)


## A charging mast for the maintenance drones, one of them parked on the pad.
func _drone_dock() -> void:
	cylinder(Vector3(0, 0, -0.2), 2.0, 0.5, 6, PAD)
	cylinder(Vector3(0, 0, 0.3), 0.15, 3.0, 8, METAL)
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		var tip := Vector3(cos(a) * 1.3, sin(a) * 1.3, 2.5)
		beam(Vector3(0, 0, 3.1), tip, 0.08, METAL)
		box(tip - Vector3(0.12, 0.12, 0.25), tip + Vector3(0.12, 0.12, 0.0), GLOW)
	var d := Vector3(0.9, 0.0, 0.0)
	box(d + Vector3(-0.3, -0.3, 0.6), d + Vector3(0.3, 0.3, 0.85), SHUTTER)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var hub := d + Vector3(cos(a) * 0.75, sin(a) * 0.75, 0.8)
		beam(d + Vector3(0, 0, 0.72), hub, 0.07, METAL)
		# Built as a hull: a disc this thin and small, cut face by face, rounds to
		# the grid slightly out of true.
		pipe(hub + Vector3(0, 0, 0.03), hub + Vector3(0, 0, 0.08), 0.32, RUBBER, 8)
	for y in [-0.25, 0.25]:
		beam(d + Vector3(-0.35, y, 0.33), d + Vector3(0.35, y, 0.33), 0.06, METAL)
		beam(d + Vector3(0.0, y * 0.8, 0.62), d + Vector3(0.0, y, 0.33), 0.05, METAL)


# ── Compute ──────────────────────────────────────────────────────────────────

func _server_rack() -> void:
	rack_at(Vector3.ZERO, 0.0)


## Eight racks on a raised floor under a cable tray.
func _rack_row() -> void:
	box(Vector3(-1.5, -2.8, -0.1), Vector3(1.5, 2.8, 0.3), {"top": METAL, "side": CONCRETE, "bottom": CONCRETE})
	for i in 8:
		rack_at(Vector3(0.0, -2.1 + i * 0.6, 0.3), 0.0)
	for y in [-2.46, 2.4]:
		box(Vector3(-0.62, y, 0.3), Vector3(0.62, y + 0.06, 2.45), CLAD)
	for y in [-2.65, 2.65]:
		post(0.0, y, 0.3, 2.75, 0.1, METAL)
	box(Vector3(-0.25, -2.75, 2.6), Vector3(0.25, 2.75, 2.7), METAL)
	pipe(Vector3(0.0, -2.75, 2.8), Vector3(0.0, 2.75, 2.8), 0.09, RUBBER, 6)


## Racks thrown down: one on its back, one on its face, one leaning, a door
## torn off, cables spilled.
func _racks_toppled() -> void:
	tipped_box(Vector3(0.0, 0.0, 0.3), Vector3(2.1, 0.6, 1.2), Vector3(0, 0, 18), {"top": GRATING, "side": SHUTTER, "bottom": METAL})
	tipped_box(Vector3(0.4, 1.4, 0.3), Vector3(2.1, 0.6, 1.2), Vector3(0, 0, -12), {"top": SHUTTER, "side": SHUTTER, "bottom": GRATING})
	tipped_box(Vector3(-1.2, -1.2, 0.95), Vector3(1.2, 0.6, 2.1), Vector3(0, -38, 30), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	tipped_box(Vector3(1.5, -1.0, 0.03), Vector3(2.0, 0.55, 0.04), Vector3(0, 0, 50), GRATING)
	tipped_box(Vector3(-0.2, 0.05, 0.62), Vector3(1.6, 0.08, 0.04), Vector3(0, 0, 18), GLOW)
	var spill := [Vector3(0.8, 0.6, 0.35), Vector3(1.6, 1.0, 0.08), Vector3(2.6, 0.7, 0.08), Vector3(3.3, 1.3, 0.08)]
	for k in 2:
		var off := Vector3(0.0, k * 0.2, 0.0)
		for i in spill.size() - 1:
			pipe(spill[i] + off, spill[i + 1] + off, 0.06, RUBBER, 6)


func _cooling_unit() -> void:
	cooler_at(Vector3.ZERO)


## A fenced concrete pad of four chillers, with a pipe manifold and pumps.
func _chiller_yard() -> void:
	box(Vector3(-10.0, -7.0, -0.3), Vector3(10.0, 7.0, 0.2), PAD)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		cooler_at(Vector3(x, 1.4, 0.2))
	pipe(Vector3(-8.5, -3.2, 0.9), Vector3(8.5, -3.2, 0.9), 0.18, RUST, 8)
	pipe(Vector3(-8.5, -3.8, 0.9), Vector3(8.5, -3.8, 0.9), 0.18, METAL, 8)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		for y in [-3.2, -3.8]:
			box(Vector3(x - 0.2, y - 0.2, 0.2), Vector3(x + 0.2, y + 0.2, 0.75), METAL)
	box(Vector3(-9.2, -6.2, 0.2), Vector3(-6.8, -4.6, 0.4), METAL)
	for x in [-8.6, -7.4]:
		cylinder(Vector3(x, -5.4, 0.4), 0.35, 0.6, 8, BLUE)
	# Fence on three sides; -Y is the way in.
	var runs := [[Vector2(-9.8, 6.8), Vector2(9.8, 6.8)], [Vector2(-9.8, -6.8), Vector2(-9.8, 6.8)], [Vector2(9.8, -6.8), Vector2(9.8, 6.8)]]
	for r: Array in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var n := int(ceil(a.distance_to(b) / 2.5))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			post(p.x, p.y, -0.3, 2.2, 0.08, METAL)
		for z in [1.0, 2.1]:
			beam(Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), 0.05, METAL)


## A generator in a container, exhaust stacks on the roof, day tank beside.
func _generator() -> void:
	for y in [-4.5, 0.0, 4.5]:
		box(Vector3(-1.4, y - 0.2, -0.2), Vector3(1.4, y + 0.2, 0.15), CONCRETE)
	box(Vector3(-1.22, -6.1, 0.15), Vector3(1.22, 6.1, 3.05), RUST_PANEL)
	box(Vector3(-1.1, -6.16, 0.4), Vector3(1.1, -6.1, 2.8), GRATING)
	box(Vector3(-1.3, 2.0, 0.4), Vector3(-1.22, 4.0, 2.6), SHUTTER)
	for y in [2.5, 4.0]:
		cylinder(Vector3(0.4, y, 3.05), 0.22, 2.2, 8, METAL)
		cylinder(Vector3(0.4, y, 5.25), 0.28, 0.2, 8, RUST)
	log_x(Vector3(2.6, 0.0, 0.3), 0.6, 4.5, 8, GREEN, "y")
	for y in [-1.6, 1.6]:
		box(Vector3(2.1, y - 0.2, -0.1), Vector3(3.1, y + 0.2, 0.5), CONCRETE)


## A substation transformer on a bunded pad: tank, fins, bushings,
## conservator.
func _transformer() -> void:
	box(Vector3(-2.2, -1.8, -0.2), Vector3(2.2, 1.8, 0.2), PAD)
	wall_run("x", Vector2(-2.2, -2.0), -1.8, 1.8, 0.2, 0.6, [], CONCRETE)
	wall_run("x", Vector2(2.0, 2.2), -1.8, 1.8, 0.2, 0.6, [], CONCRETE)
	wall_run("y", Vector2(-1.8, -1.6), -2.0, 2.0, 0.2, 0.6, [], CONCRETE)
	wall_run("y", Vector2(1.6, 1.8), -2.0, 2.0, 0.2, 0.6, [], CONCRETE)
	box(Vector3(-0.9, -0.7, 0.2), Vector3(0.9, 0.7, 2.2), GREEN)
	for s in [-1.0, 1.0]:
		for i in 5:
			var y := -0.6 + i * 0.3
			box(Vector3(s * 0.9, y - 0.03, 0.4), Vector3(s * 1.4, y + 0.03, 2.0), METAL)
	for y in [-0.45, 0.0, 0.45]:
		cylinder(Vector3(0.25, y, 2.2), 0.1, 0.9, 6, RUBBER)
		cylinder(Vector3(0.25, y, 3.1), 0.14, 0.1, 6, METAL)
	log_x(Vector3(-0.55, 0.0, 2.2), 0.25, 1.4, 8, GREEN, "y")


## A data hall for a building lot (fits 24 × 32 m): windowless clad box,
## louvre bands with status strips, cooling plant and a parapet on the roof,
## a roller door, and a ramp up the +X side to the roof.
func _data_hall() -> void:
	plinth(-7.5, -13.5, 7.5, 13.5, -0.5, 0.5, 2.0, PLINTH, {"+x": 0.5, "-y": 1.0, "+y": 1.0})
	box(Vector3(-7.0, -13.0, 0.5), Vector3(7.0, 13.0, 8.0), CLAD)
	box(Vector3(-7.1, -13.1, 0.5), Vector3(7.1, 13.1, 1.4), TECH_WALL)
	for y in [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]:
		for s in [-1.0, 1.0]:
			if s > 0.0 and y > -1.0 and y < 3.0:
				continue   # the ramp's landing is on this stretch of wall
			box(Vector3(s * 7.0, y - 0.6, 1.6), Vector3(s * 7.08, y + 0.6, 7.0), GRATING)
			box(Vector3(s * 7.0, y - 0.6, 7.1), Vector3(s * 7.09, y + 0.6, 7.25), GLOW)
	window("-y", -13.0, 0.0, 0.5, 4.0, 4.5, false)
	box(Vector3(-2.6, -14.3, 5.2), Vector3(2.6, -13.0, 5.45), FRAME)
	window("-x", -7.0, -9.0, 0.5, 1.2, 2.3, false)
	for y in [8.0, 9.0, 10.0]:
		pipe(Vector3(-7.25, y, 0.0), Vector3(-7.25, y, 8.4), 0.12, RUBBER, 6)
	box(Vector3(-7.25, -13.25, 8.0), Vector3(7.25, 13.25, 8.25), SLAB)
	parapet(-7.25, -13.25, 7.25, 13.25, 8.25, 0.9, 0.25, {"+x": [[0.0, 2.5]]})
	for x in [-3.5, 1.5]:
		for y in [-8.0, -2.0, 4.0]:
			box(Vector3(x - 0.9, y - 1.5, 8.25), Vector3(x + 0.9, y + 1.5, 9.65), CLAD)
			for dy in [-0.7, 0.7]:
				cylinder(Vector3(x, y + dy, 9.65), 0.6, 0.12, 10, GRATING)
	# Up the +X side: 14.5 m of ramp at about 30°, landing onto the roof.
	ramp(7.25, -14.5, 9.25, 0.0, 0.0, 0.0, 8.25, "+y")
	box(Vector3(7.0, 0.0, 0.0), Vector3(9.25, 2.5, 8.25), SLAB)
	rail("x", 9.125, -14.5, 0.0, 0.0, 8.25)
	rail("x", 9.125, 0.0, 2.5, 8.25, 8.25)
	rail("y", 2.375, 7.25, 9.25, 8.25, 8.25)


## An AI compute node: a black six-sided obelisk 16 m tall with glowing
## seams, cooling fins round its foot, on four low steps, and three conduits
## running out across the ground.
func _obelisk() -> void:
	for i in 4:
		cylinder(Vector3(0, 0, -0.3 if i == 0 else i * 0.25), 6.8 - i * 1.0, 0.55 if i == 0 else 0.25, 6, PAD)
	cylinder(Vector3(0, 0, 1.0), 1.8, 14.0, 6, GLASS, 0.9)
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		# Set just outside the edge so the seam stands proud of the black faces
		# instead of sinking half into them.
		beam(Vector3(cos(a) * 1.9, sin(a) * 1.9, 1.0), Vector3(cos(a) * 1.0, sin(a) * 1.0, 15.0), 0.22, GLOW)
	var cap: Array = [Vector3(0, 0, 16.6)]
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		cap.append(Vector3(cos(a) * 0.9, sin(a) * 0.9, 15.0))
	solid(cap, GLOW)
	for k in 12:
		var yaw := 360.0 * (k + 0.5) / 12.0
		box_yawed(Vector3(2.1, -0.05, 1.0), Vector3(3.3, 0.05, 3.6), Vector3.ZERO, yaw, METAL)
	for k in 3:
		var yaw := 360.0 * k / 3.0 + 30.0
		box_yawed(Vector3(6.3, -0.3, -0.1), Vector3(16.0, 0.3, 0.4), Vector3.ZERO, yaw, CONCRETE)
		box_yawed(Vector3(6.3, -0.08, 0.4), Vector3(16.0, 0.08, 0.45), Vector3.ZERO, yaw, GLOW)


## Three thick cables snaking across the ground, into a junction box.
func _cable_run() -> void:
	var path := [Vector3(-6.0, -1.0, 0.08), Vector3(-2.5, -0.2, 0.08), Vector3(0.5, 0.8, 0.08), Vector3(4.0, 0.3, 0.08), Vector3(6.5, 1.2, 0.08)]
	for k in 3:
		var off := Vector3(0.0, (k - 1) * 0.24, 0.0)
		for i in path.size() - 1:
			pipe(path[i] + off, path[i + 1] + off, 0.09, RUBBER if k != 1 else GREEN, 6)
	box(Vector3(-0.1, 1.2, -0.1), Vector3(1.1, 2.0, 0.9), CLAD)
	box(Vector3(0.2, 1.17, 0.6), Vector3(0.8, 1.2, 0.7), GLOW)


## A roadside network cabinet with its conduits and a whip antenna.
func _network_cabinet() -> void:
	box(Vector3(-0.45, -0.7, -0.1), Vector3(0.45, 0.7, 0.15), CONCRETE)
	box(Vector3(-0.35, -0.6, 0.15), Vector3(0.35, 0.6, 1.6), CLAD)
	box(Vector3(-0.38, -0.55, 0.3), Vector3(-0.35, -0.02, 1.5), SHUTTER)
	box(Vector3(-0.38, 0.02, 0.3), Vector3(-0.35, 0.55, 1.5), SHUTTER)
	box(Vector3(-0.41, -0.12, 1.52), Vector3(-0.35, 0.12, 1.57), GLOW)
	box(Vector3(-0.4, -0.65, 1.6), Vector3(0.4, 0.65, 1.68), METAL)
	beam(Vector3(0.1, 0.35, 1.68), Vector3(0.1, 0.35, 3.3), 0.05, METAL)
	for y in [-0.3, 0.3]:
		pipe(Vector3(0.4, y, 0.12), Vector3(1.6, y, -0.25), 0.08, RUBBER, 6)


## A 4 m dish on a pedestal, eight panels on a shallow bowl, tilted to face -X.
func _satellite_dish() -> void:
	cylinder(Vector3(0, 0, -0.2), 0.6, 0.4, 8, CONCRETE)
	cylinder(Vector3(0, 0, 0.2), 0.3, 1.8, 8, METAL)
	box(Vector3(-0.4, -0.4, 2.0), Vector3(0.4, 0.4, 2.5), METAL)
	var tilt := Basis(Vector3(0, 1, 0), deg_to_rad(-35.0))
	var centre := Vector3(-0.3, 0.0, 3.0)
	for i in 8:
		var pts: Array = []
		for a in [TAU * i / 8.0, TAU * (i + 1) / 8.0]:
			for r in [0.35, 2.0]:
				for t in [0.0, -0.07]:
					pts.append(centre + tilt * Vector3(cos(a) * r, sin(a) * r, 0.12 * r * r + t))
		solid(pts, PALE)
	solid([centre + tilt * Vector3(0, 0, -0.35), centre + tilt * Vector3(0.45, 0, 0.0), centre + tilt * Vector3(-0.45, 0, 0.0),
			centre + tilt * Vector3(0, 0.45, 0.0), centre + tilt * Vector3(0, -0.45, 0.0), centre + tilt * Vector3(0, 0, 0.05)], METAL)
	var focus := centre + tilt * Vector3(0, 0, 1.4)
	for k in 3:
		var a := TAU * k / 3.0
		beam(centre + tilt * Vector3(cos(a) * 1.8, sin(a) * 1.8, 0.39), focus, 0.05, METAL)
	box(focus - Vector3(0.15, 0.15, 0.15), focus + Vector3(0.15, 0.15, 0.15), METAL)
	beam(Vector3(0, 0, 2.3), centre + tilt * Vector3(0, 0, -0.3), 0.25, METAL)


# ── Landmarks ────────────────────────────────────────────────────────────────

## The reason a fortress stands here: the ground anchor of an orbital tether.
## A battered pylon carries the anchor head 26–48 m up, and the tether climbs
## out of it to 240 m, into the haze, with a climber car on the way. Four guy
## cables fan out from the head, over the compounds, to deadman blocks just
## outside the fortress's corners: the fortress is tied to the thing it
## guards. Round the pylon, 9.5 m up, a gallery on four buttresses looks out
## over the compounds. Two ramps reach it from opposite ends of the pad, as the
## old tower's did, so the court still loops over itself.
##
## Sized for the valley fortress: the 34 × 48 m pad is the old tower's central
## court, and its short ends butt against the compound slabs, so only its long
## sides are banked. The deadmen stand 100 m out along the diagonals, clear of
## every compound. Flatten the ground under them to the pad's height.
func _tether_anchor() -> void:
	plinth(-24.0, -17.0, 24.0, 17.0, -0.5, 0.5, 1.5, PLINTH, {"-x": 0.25, "+x": 0.25})
	# The pylon: battered up to the gallery, then straight, with lit seams.
	cylinder(Vector3(0, 0, 0.0), 7.0, 9.0, 8, TECH_WALL, 5.4)
	cylinder(Vector3(0, 0, 9.0), 5.4, 17.0, 8, TECH_WALL)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 8.0
		var d := Vector3(cos(a), sin(a), 0.0)
		beam(d * 6.91 + Vector3(0, 0, 0.8), d * 5.52 + Vector3(0, 0, 8.6), 0.3, GLOW)
		beam(d * 5.45 + Vector3(0, 0, 10.5), d * 5.45 + Vector3(0, 0, 23.5), 0.3, GLOW)
	cylinder(Vector3(0, 0, 24.5), 5.65, 1.0, 8, GLOW)
	# Buttresses on the diagonals, clear of the ramps, carrying the gallery and
	# pointing the way the cables go.
	for k in 4:
		var a := PI / 4.0 + PI / 2.0 * k
		var d := Vector2(cos(a), sin(a))
		var s := Vector2(-d.y, d.x) * 0.7
		var pts: Array = []
		for rh: Array in [[4.6, 9.0], [11.0, 1.2]]:
			for side: float in [-1.0, 1.0]:
				var p: Vector2 = d * float(rh[0]) + s * side
				pts.append(Vector3(p.x, p.y, 0.3))
				pts.append(Vector3(p.x, p.y, float(rh[1])))
		solid(pts, TECH_WALL)
	# The gallery: an eight-sided ring round the pylon, 4 m wide.
	var ri := 4.8 / cos(PI / 8.0)
	var ro := 9.0 / cos(PI / 8.0)
	var rp := 8.7 / cos(PI / 8.0)
	for k in 8:
		var a0 := TAU * (k - 0.5) / 8.0
		var a1 := TAU * (k + 0.5) / 8.0
		var deck: Array = []
		for a: float in [a0, a1]:
			for r: float in [ri, ro]:
				deck.append(Vector3(cos(a) * r, sin(a) * r, 9.0))
				deck.append(Vector3(cos(a) * r, sin(a) * r, 9.5))
		solid(deck, SLAB)
		# A parapet round the outside, open east and west where the landings join.
		if k == 2 or k == 6:
			continue
		var wall: Array = []
		for a: float in [a0, a1]:
			for r: float in [rp, ro]:
				wall.append(Vector3(cos(a) * r, sin(a) * r, 9.5))
				wall.append(Vector3(cos(a) * r, sin(a) * r, 10.5))
		solid(wall, FRAME)
	# Landings east and west, and the ramps up to them: the west one climbs
	# south from the north end of the pad, the east one north from the south.
	box(Vector3(-2.5, -16.0, 9.0), Vector3(2.5, -8.8, 9.5), SLAB)
	box(Vector3(-2.5, 8.8, 9.0), Vector3(2.5, 16.0, 9.5), SLAB)
	ramp(-21.5, -16.0, -2.5, -12.0, 0.5, 0.5, 9.5, "+x")
	ramp(2.5, 12.0, 21.5, 16.0, 0.5, 0.5, 9.5, "-x")
	rail("y", -15.875, -21.5, -2.5, 0.5, 9.5, true)
	rail("y", -12.125, -21.5, -2.5, 0.5, 9.5, true)
	rail("y", 15.875, 2.5, 21.5, 0.5, 9.5, false)
	rail("y", 12.125, 2.5, 21.5, 0.5, 9.5, false)
	box(Vector3(-2.5, -12.0, 9.5), Vector3(-2.25, -8.8, 10.5), FRAME)
	box(Vector3(2.25, -16.0, 9.5), Vector3(2.5, -8.8, 10.5), FRAME)
	box(Vector3(-2.5, -16.0, 9.5), Vector3(2.5, -15.75, 10.5), FRAME)
	box(Vector3(2.25, 8.8, 9.5), Vector3(2.5, 12.0, 10.5), FRAME)
	box(Vector3(-2.5, 8.8, 9.5), Vector3(-2.25, 16.0, 10.5), FRAME)
	box(Vector3(-2.5, 15.75, 9.5), Vector3(2.5, 16.0, 10.5), FRAME)
	# The anchor head: it flares off the pylon, black, seamed with light.
	cylinder(Vector3(0, 0, 26.0), 5.4, 4.0, 8, GLASS, 10.8)
	cylinder(Vector3(0, 0, 30.0), 10.8, 10.0, 8, GLASS)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		beam(Vector3(cos(a) * 10.9, sin(a) * 10.9, 30.5), Vector3(cos(a) * 10.9, sin(a) * 10.9, 39.5), 0.4, GLOW)
	cylinder(Vector3(0, 0, 40.0), 10.8, 6.0, 8, GLASS, 5.4)
	cylinder(Vector3(0, 0, 46.0), 5.9, 2.0, 8, METAL)
	cylinder(Vector3(0, 0, 46.6), 6.1, 0.8, 8, GLOW)
	# The tether, 4 m across and lit every 16 m, and a climber car partway up.
	cylinder(Vector3(0, 0, 48.0), 2.16, 192.0, 8, GLASS)
	for z in range(56, 236, 16):
		cylinder(Vector3(0, 0, float(z)), 2.45, 0.6, 8, GLOW)
	box(Vector3(-3.4, -3.4, 128.0), Vector3(3.4, 3.4, 135.0), CLAD)
	for o: float in [-3.4, 3.4]:
		var sgn := signf(o)
		box(Vector3(o, -2.2, 132.0), Vector3(o + sgn * 0.06, 2.2, 132.6), GLOW)
		box(Vector3(-2.2, o, 132.0), Vector3(2.2, o + sgn * 0.06, 132.6), GLOW)
	cylinder(Vector3(0, 0, 126.8), 2.6, 1.2, 8, METAL, 3.4)
	cylinder(Vector3(0, 0, 135.0), 3.4, 1.2, 8, METAL, 2.6)
	# Guy cables on the diagonals: a socket arm out of the head, the cable down
	# over the compounds, and the deadman it is tied to.
	for k in 4:
		var a := PI / 4.0 + PI / 2.0 * k
		var d := Vector3(cos(a), sin(a), 0.0)
		var arm := d * 13.0 + Vector3(0, 0, 33.0)
		pipe(d * 9.0 + Vector3(0, 0, 34.0), arm, 0.9, METAL, 8)
		pipe(arm, d * 100.0 + Vector3(0, 0, 3.0), 0.35, METAL, 8)
		deadman_at(d * 100.0)


## A deadman: the battered concrete block a guy cable is tied to, with a
## steel socket and a lit collar where the cable goes in. Cover as well.
func deadman_at(c: Vector3) -> void:
	var pts: Array = []
	for hz: Array in [[4.0, -0.4], [3.0, 3.5]]:
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				pts.append(c + Vector3(sx * float(hz[0]), sy * float(hz[0]), float(hz[1])))
	solid(pts, CONCRETE)
	cylinder(c + Vector3(0, 0, 3.5), 1.4, 1.2, 8, METAL)
	cylinder(c + Vector3(0, 0, 3.9), 1.55, 0.4, 8, GLOW)
