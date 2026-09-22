extends "res://tools/block_ai_infra.gd"

# ─────────────────────────────────────────────
# BLOCK INDUSTRIAL — the city's industry, the machines that worked it, and the
# fortifications the robots dug into it, as TrenchBroom blocks:
#
#   maps/blocks/industrial/industrial_*.map — warehouses, a sawtooth factory,
#       hangars, a plant office and a works gate, a car park and a parking
#       deck, container and scrap yards, a coal pile, a smokestack, a blast
#       furnace, silos, a water tower, a gantry crane, a gas sphere, a
#       conveyor, a pipe rack, a substation, rail track and wagons, a coal
#       barge, and a lock and dam you can walk across.
#   maps/blocks/machines/machine_*.map — machine tools (lathe, milling
#       machine, press, machining centre), a robot arm and an assembly line,
#       forklift, excavator, bulldozer, pallet racking, steel coils, a
#       workbench and a semi-truck.
#   maps/blocks/fortifications/fort_*.map — hardpoints: a command bunker, a
#       gun emplacement, a mortar pit, hesco and T-walls, a hesco sangar, a
#       checkpoint, dragon's teeth, razor wire, a sentry turret's mount, an
#       ammo dump and a floodlight mast. The mortar pit and the sentry mount
#       hold no weapon: the weapons are not part of the blocks.
#   maps/blocks/landmarks/landmark_*.map — a clock tower and a big wheel, a
#       landmark for each side of a town.
#   maps/blocks/compute/compute_monolith.map — the machines' monolith, beside
#       the AI-infra tool's compute pieces.
#
#   godot --headless --path . --script res://tools/block_industrial.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_industrial.gd -- maps/blocks --force [piece names]
#
# Built on block_ai_infra.gd, which this extends: the same brush kit, hull,
# conventions and no-overwrite rule. Name pieces after the folder to write only
# those. Build prefabs with block_prefabs.gd.
#
# Brush budget: big pieces stay near 150 brushes, props under 40. Every brush
# is a collision shape and a level holds hundreds of these pieces, so repeated
# detail (sandbags, rail ties, bay lines) is kept coarse on purpose.
# ─────────────────────────────────────────────

const ASPHALT := "PSX_Textures/concrete_3"
const PAINT := "PSX_Textures/concrete_1@0.25"
const COAL := "PSX_Textures/rock_4@0.5"
const ORE := "PSX_Textures/dirt_hell_1"
const SPOIL := "PSX_Textures/dirt_5"
const BALLAST := "PSX_Textures/concrete_3@0.5"
const CLOCK_FACE := "PSX_Textures/snow_1"

const LOT := {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE}
const HESCO := {"top": DIRT, "side": SANDBAG, "bottom": SANDBAG}
const MACHINE := {"top": METAL, "side": GREEN, "bottom": METAL}
const ROOFED := {"top": RUST_PANEL, "side": METAL, "bottom": METAL}

# Each piece's map name and the function that draws it.
const INDUSTRIAL := {
	"industrial_warehouse_long": "_warehouse_long",
	"industrial_sawtooth_factory": "_sawtooth_factory",
	"industrial_hangar_arch": "_hangar_arch",
	"industrial_hangar_shed": "_hangar_shed",
	"industrial_plant_office": "_plant_office",
	"industrial_gatehouse": "_gatehouse",
	"industrial_parking_lot": "_parking_lot",
	"industrial_parking_deck": "_parking_deck",
	"industrial_container_yard": "_container_yard",
	"industrial_scrap_yard": "_scrap_yard",
	"industrial_coal_pile": "_coal_pile",
	"industrial_smokestack": "_smokestack",
	"industrial_blast_furnace": "_blast_furnace",
	"industrial_silos": "_silos",
	"industrial_water_tower": "_water_tower",
	"industrial_gantry_crane": "_gantry_crane",
	"industrial_gas_sphere": "_gas_sphere",
	"industrial_conveyor": "_conveyor",
	"industrial_pipe_rack": "_pipe_rack",
	"industrial_substation": "_substation",
	"industrial_rail_track": "_rail_track",
	"industrial_rail_boxcar": "_rail_boxcar",
	"industrial_rail_tank_car": "_rail_tank_car",
	"industrial_rail_gondola": "_rail_gondola",
	"industrial_coal_barge": "_coal_barge",
	"industrial_lock_dam": "_lock_dam",
}
const MACHINES := {
	"machine_lathe": "_lathe",
	"machine_milling": "_milling",
	"machine_press": "_press",
	"machine_cnc": "_cnc",
	"machine_robot_arm": "_robot_arm",
	"machine_assembly_line": "_assembly_line",
	"machine_forklift": "_forklift",
	"machine_excavator": "_excavator",
	"machine_bulldozer": "_bulldozer",
	"machine_pallet_rack": "_pallet_rack",
	"machine_steel_coils": "_steel_coils",
	"machine_workbench": "_workbench",
	"machine_semi_truck": "_semi_truck",
}
const FORTIFICATIONS := {
	"fort_command_bunker": "_command_bunker",
	"fort_gun_emplacement": "_gun_emplacement",
	"fort_mortar_pit": "_mortar_pit",
	"fort_hesco_wall": "_hesco_wall",
	"fort_t_walls": "_t_walls",
	"fort_hesco_sangar": "_hesco_sangar",
	"fort_checkpoint": "_checkpoint",
	"fort_dragon_teeth": "_dragon_teeth",
	"fort_razor_wire": "_razor_wire",
	"fort_sentry_turret": "_sentry_turret",
	"fort_ammo_dump": "_ammo_dump",
	"fort_floodlight_mast": "_floodlight_mast",
}
# Landmarks for the city's districts, and the machines' monolith: written into
# the landmarks/ and compute/ folders beside the AI-infra tool's pieces.
const LANDMARKS := {
	"landmark_clock_tower": "_clock_tower",
	"landmark_ferris_wheel": "_ferris_wheel",
}
const COMPUTE := {
	"compute_monolith": "_monolith",
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
		print("usage: godot --headless --path . --script res://tools/block_industrial.gd -- maps/blocks [--force] [piece names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var skipped := 0
	var written := 0
	for pair in [[base.path_join("industrial"), INDUSTRIAL], [base.path_join("machines"), MACHINES], [base.path_join("fortifications"), FORTIFICATIONS],
			[base.path_join("landmarks"), LANDMARKS], [base.path_join("compute"), COMPUTE]]:
		var dir: String = pair[0]
		var made: Dictionary = pair[1]
		if not DirAccess.dir_exists_absolute(dir):
			var err := DirAccess.make_dir_recursive_absolute(dir)
			if err != OK:
				print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
				quit(1)
				return
		for name: String in made:
			if not only.is_empty() and not only.has(name):
				continue
			var path := dir.path_join(name + ".map")
			if FileAccess.file_exists(path) and not force:
				print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
				skipped += 1
				continue
			var method: String = made[name]
			if not has_method(method):
				print("FAIL  %s: no function %s in this tool" % [name, method])
				quit(1)
				return
			_brushes = []
			call(method)
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
				quit(1)
				return
			f.store_string(_map_text())
			f.close()
			written += 1
			var heavy := "   WARNING over the brush budget" if _brushes.size() > 200 else ""
			print("      %-30s %3d brushes  %s%s" % [name, _brushes.size(), _extent_text(), heavy])
	for n: String in only:
		if not INDUSTRIAL.has(n) and not MACHINES.has(n) and not FORTIFICATIONS.has(n) and not LANDMARKS.has(n) and not COMPUTE.has(n):
			print("WARNING  no piece called '%s' — nothing written for it" % n)
	print("BLOCK INDUSTRIAL DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


## Upright prism, as the kit draws it — except a tapered one, which goes
## through the hull. Snapped to the grid, the four corners of a sloping side
## stop lying on one plane, and TrenchBroom then builds the brush smaller than
## drawn: every tapered pole and cone here tripped the kit's convexity warning.
func cylinder(c: Vector3, radius: float, height: float, sides: int, tex: Variant, top_radius: float = -1.0) -> void:
	if top_radius < 0.0 or is_equal_approx(top_radius, radius):
		super(c, radius, height, sides, tex, top_radius)
		return
	var pts: Array = []
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		pts.append(Vector3(c.x + cos(a) * radius, c.y + sin(a) * radius, c.z))
		pts.append(Vector3(c.x + cos(a) * top_radius, c.y + sin(a) * top_radius, c.z + height))
	solid(pts, tex)


# ── Placed parts ─────────────────────────────────────────────────────────────
# Vehicles, machines and fences are drawn round their own origin and then
# placed: moved to `c` and turned `yaw` degrees about it.

func _place(pts: Array, c: Vector3, yaw: float) -> Array:
	var moved: Array = []
	for p: Vector3 in pts:
		moved.append(p + c)
	return _yaw(moved, c, yaw)


func _at(c: Vector3, yaw: float, p: Vector3) -> Vector3:
	return _place([p], c, yaw)[0]


## A box by its corners in part space, placed. Exact when not turned.
func pbox(c: Vector3, yaw: float, a: Vector3, b: Vector3, tex: Variant) -> void:
	if is_zero_approx(fmod(yaw, 360.0)):
		box(c + a, c + b, tex)
		return
	var pts: Array = []
	for x: float in [a.x, b.x]:
		for y: float in [a.y, b.y]:
			for z: float in [a.z, b.z]:
				pts.append(Vector3(x, y, z))
	solid(_place(pts, c, yaw), tex)


func psolid(c: Vector3, yaw: float, pts: Array, tex: Variant, grid: int = 1) -> void:
	solid(_place(pts, c, yaw), tex, grid)


func ppipe(c: Vector3, yaw: float, a: Vector3, b: Vector3, r: float, tex: Variant, sides: int = 8) -> void:
	pipe(_at(c, yaw, a), _at(c, yaw, b), r, tex, sides)


func pbeam(c: Vector3, yaw: float, a: Vector3, b: Vector3, w: float, tex: Variant) -> void:
	beam(_at(c, yaw, a), _at(c, yaw, b), w, tex)


## An upright prism whose centre is given in part space.
func pcylinder(c: Vector3, yaw: float, p: Vector3, radius: float, height: float, sides: int, tex: Variant, top_radius: float = -1.0) -> void:
	cylinder(_at(c, yaw, p), radius, height, sides, tex, top_radius)


## A convex (y, z) outline pushed along X from x0 to x1: track frames, blades.
func _extrude_x(profile: Array, x0: float, x1: float, tex: Variant) -> void:
	var v: Array = []
	for x: float in [x0, x1]:
		for q: Vector2 in profile:
			v.append(Vector3(x, q.x, q.y))
	var n := profile.size()
	var faces: Array = [range(n), range(n, n * 2)]
	for i in n:
		faces.append([i, (i + 1) % n, n + (i + 1) % n, n + i])
	brush(v, faces, tex)


## A saloon car 4.4 m long along its local X and 1.8 m wide. Each axle is one
## prism whose ends read as the tyres: two brushes where four would do.
func car_at(c: Vector3, yaw: float, tex: String) -> void:
	psolid(c, yaw, [Vector3(-2.2, -0.9, 0.3), Vector3(2.2, -0.9, 0.3), Vector3(2.2, 0.9, 0.3), Vector3(-2.2, 0.9, 0.3),
			Vector3(-2.15, -0.88, 0.95), Vector3(2.1, -0.88, 0.88), Vector3(2.1, 0.88, 0.88), Vector3(-2.15, 0.88, 0.95)], {"top": tex, "side": tex, "bottom": RUST})
	psolid(c, yaw, [Vector3(-1.4, -0.82, 0.93), Vector3(1.0, -0.82, 0.9), Vector3(1.0, 0.82, 0.9), Vector3(-1.4, 0.82, 0.93),
			Vector3(-1.0, -0.72, 1.45), Vector3(0.45, -0.72, 1.45), Vector3(0.45, 0.72, 1.45), Vector3(-1.0, 0.72, 1.45)], {"top": tex, "side": GLASS, "bottom": tex})
	for x: float in [-1.35, 1.35]:
		ppipe(c, yaw, Vector3(x, -0.93, 0.33), Vector3(x, 0.93, 0.33), 0.33, RUBBER, 8)


## A 7 m lamp standard, its arm and head reaching toward local +X.
func lamp_at(c: Vector3, yaw: float) -> void:
	box(c + Vector3(-0.25, -0.25, -0.2), c + Vector3(0.25, 0.25, 0.4), CONCRETE)
	cylinder(c + Vector3(0, 0, 0.4), 0.11, 6.6, 8, METAL, 0.08)
	pbeam(c, yaw, Vector3(0, 0, 6.85), Vector3(1.4, 0, 7.05), 0.09, METAL)
	pbox(c, yaw, Vector3(1.2, -0.18, 6.9), Vector3(1.9, 0.18, 7.12), SHUTTER)


## Fence from a to b on the ground plane: posts every 2.5 m and two rails.
## No mesh: a panel would stop the squad seeing through it, which a real
## chain-link fence does not.
func fence_run(a: Vector2, b: Vector2, z0: float = -0.2, h: float = 2.2) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / 2.5)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		post(p.x, p.y, z0, z0 + h + 0.1, 0.08, METAL)
	for z: float in [z0 + 1.0, z0 + h]:
		beam(Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), 0.05, METAL)


## A standing panel from a to b on the ground plane, `t` thick. Keep a
## diagonal one 0.1 m or thicker: thinner, its corners snap together.
func panel(a: Vector2, b: Vector2, z0: float, z1: float, t: float, tex: Variant) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * t * 0.5
	var q: Array = [a + n, b + n, b - n, a - n]
	if absf(d.x) < 1e-6 or absf(d.y) < 1e-6:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p: Vector2 in q:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		box(Vector3(lo.x, lo.y, z0), Vector3(hi.x, hi.y, z1), tex)
		return
	var pts: Array = []
	for p: Vector2 in q:
		pts.append(Vector3(p.x, p.y, z0))
		pts.append(Vector3(p.x, p.y, z1))
	solid(pts, tex)


# ── Industrial: buildings ────────────────────────────────────────────────────

## A distribution warehouse, 20 × 48 m and 9 m to the roof: clad walls on a
## block base, six dock doors along the -X side behind a loading dock 1.25 m
## up under a canopy, skylights on the roof, and a ramp up the +X side to it.
func _warehouse_long() -> void:
	# No bank on +X: the roof ramp stands there and must start on open ground.
	plinth(-10.5, -24.5, 10.5, 24.5, -0.5, 0.5, 2.0, PLINTH, {"-x": 0.25, "+x": 0.0})
	box(Vector3(-10, -24, 0.5), Vector3(10, 24, 9.0), CLAD)
	box(Vector3(-10.1, -24.1, 0.5), Vector3(10.1, 24.1, 2.0), TECH_WALL)
	for y: float in [-24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0]:
		var y0 := clampf(y - 0.3, -24.3, 23.7)
		for s: float in [-1.0, 1.0]:
			box(Vector3(s * 10.0 - 0.3, y0, 0.5), Vector3(s * 10.0 + 0.3, y0 + 0.6, 9.0), FRAME)
	box(Vector3(-10.25, -24.25, 9.0), Vector3(10.25, 24.25, 9.25), SLAB)
	parapet(-10.25, -24.25, 10.25, 24.25, 9.25, 0.6, 0.25, {"+x": [[5.5, 8.5]]})
	for x: float in [-4.0, 4.0]:
		box(Vector3(x - 0.9, -20.0, 9.25), Vector3(x + 0.9, 20.0, 9.6), {"top": GLASS, "side": METAL, "bottom": METAL})
	for y: float in [-18.0, -6.0, 6.0, 18.0]:
		cylinder(Vector3(0.0, y, 9.25), 0.5, 1.0, 8, METAL)
	# The dock: doors, bumpers on its face, a ramp up its +Y end, a canopy on rods.
	for y: float in [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]:
		window("-x", -10.0, y, 1.25, 3.5, 3.75, false, METAL)
		for s: float in [-1.0, 1.0]:
			box(Vector3(-14.3, y + s * 1.5 - 0.2, 0.4), Vector3(-14.0, y + s * 1.5 + 0.2, 1.15), RUBBER)
	box(Vector3(-14.0, -22.0, 0.0), Vector3(-10.0, 22.0, 1.25), SLAB)
	ramp(-14.0, 22.0, -11.5, 28.0, 0.0, 0.0, 1.25, "-y")
	box(Vector3(-14.5, -23.0, 5.75), Vector3(-10.0, 23.0, 6.0), FRAME)
	for y: float in [-21.0, -7.0, 7.0, 21.0]:
		beam(Vector3(-10.0, y, 8.0), Vector3(-14.3, y, 6.0), 0.1, METAL)
	window("-y", -24.0, 0.0, 0.5, 5.0, 5.0, false, SHUTTER)
	window("+y", 24.0, -6.0, 0.5, 1.2, 2.3, false, METAL)
	# Up the +X side: 17.5 m of ramp at about 28°, onto a landing at roof height.
	ramp(10.5, -12.0, 12.5, 5.5, 0.0, 0.0, 9.25, "+y")
	box(Vector3(10.25, 5.5, 0.0), Vector3(12.5, 8.5, 9.25), SLAB)
	rail("x", 12.375, -12.0, 5.5, 0.0, 9.25)
	rail("x", 12.375, 5.5, 8.5, 9.25, 9.25)
	rail("y", 8.375, 10.25, 12.5, 9.25, 9.25)


## A brick factory under a sawtooth roof, 24 × 30 m: five north lights glazed
## toward +X, brick gables stepping over each end, tall windows, a loading door
## and two personnel doors on the -X front, and a chimney at one corner.
func _sawtooth_factory() -> void:
	plinth(-12.5, -15.5, 12.5, 15.5, -0.5, 0.5, 2.0)
	box(Vector3(-12, -15, 0.5), Vector3(12, 15, 6.5), BRICK)
	box(Vector3(-12.1, -15.1, 0.5), Vector3(12.1, 15.1, 1.25), FRAME)
	box(Vector3(-12.15, -15.15, 6.25), Vector3(12.15, 15.15, 6.5), FRAME)
	for k in 5:
		var x0 := -12.0 + k * 4.8
		var x1 := x0 + 4.8
		# The tooth: roof sheeting rising toward +X, glass on its steep face.
		brush([Vector3(x0, -15, 6.5), Vector3(x1, -15, 6.5), Vector3(x1, -15, 9.0),
				Vector3(x0, 15, 6.5), Vector3(x1, 15, 6.5), Vector3(x1, 15, 9.0)],
				[[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [0, 2, 5, 3]], {"top": RUST_PANEL, "side": GLASS, "bottom": METAL})
		# Its gables: a brush picks textures by facing, not by side, so the
		# glass would show on the tooth's triangular ends without these.
		for s: float in [-1.0, 1.0]:
			var y0 := s * 15.0
			var y1 := s * 15.25
			brush([Vector3(x0, y0, 6.5), Vector3(x1, y0, 6.5), Vector3(x1, y0, 9.0),
					Vector3(x0, y1, 6.5), Vector3(x1, y1, 6.5), Vector3(x1, y1, 9.0)],
					[[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [0, 2, 5, 3]], BRICK)
		for s: float in [-1.0, 1.0]:
			window("-y" if s < 0.0 else "+y", s * 15.0, x0 + 2.4, 1.75, 1.6, 3.2, false, GLASS)
	window("-x", -12.0, 0.0, 0.5, 5.0, 4.5, false, SHUTTER)
	box(Vector3(-13.5, -3.2, 5.0), Vector3(-12.0, 3.2, 5.25), FRAME)
	for y: float in [-8.0, 8.0]:
		window("-x", -12.0, y, 0.5, 1.2, 2.3, false, METAL)
	for y: float in [-12.0, -4.75, 4.75, 12.0]:
		window("-x", -12.0, y, 2.5, 2.2, 2.4, false, GLASS)
	for y: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		window("+x", 12.0, y, 2.0, 2.2, 3.0, false, GLASS)
	cylinder(Vector3(10.2, 13.2, 0.5), 0.9, 15.0, 10, BRICK, 0.7)
	cylinder(Vector3(10.2, 13.2, 15.2), 0.8, 0.3, 10, FRAME)


## An arched hangar 26 m across and 36 m deep, 11 m to the crown: a shell of
## twelve curved segments on a floor slab, a closed back wall with a door, and
## the front open under a framed arch with its two door leaves slid aside.
func _hangar_arch() -> void:
	plinth(-18.0, -13.0, 18.0, 13.0, -0.4, 0.15, 1.0, PAD)
	var segs := 12
	for k in segs:
		var a0 := PI * k / segs
		var a1 := PI * (k + 1) / segs
		var shell: Array = []
		var ring: Array = []
		var wall: Array = [Vector3(17.6, 0.0, 0.15), Vector3(18.0, 0.0, 0.15)]
		for a: float in [a0, a1]:
			for r: Vector2 in [Vector2(13.0, 11.0), Vector2(13.45, 11.45)]:
				var p := Vector2(cos(a) * r.x, 0.15 + sin(a) * r.y)
				shell.append(Vector3(-18.0, p.x, p.y))
				shell.append(Vector3(18.0, p.x, p.y))
			for r: Vector2 in [Vector2(12.7, 10.7), Vector2(13.9, 11.9)]:
				var p := Vector2(cos(a) * r.x, 0.15 + sin(a) * r.y)
				ring.append(Vector3(-18.6, p.x, p.y))
				ring.append(Vector3(-17.6, p.x, p.y))
			# The back wall in slices from the floor's middle out to the shell's
			# outer face: each slice is convex and together they leave no gap
			# under the curve, which strips with straight tops would.
			var o := Vector2(cos(a) * 13.45, 0.15 + sin(a) * 11.45)
			wall.append(Vector3(17.6, o.x, o.y))
			wall.append(Vector3(18.0, o.x, o.y))
		solid(shell, {"top": RUST_PANEL, "side": SHUTTER, "bottom": METAL})
		solid(ring, FRAME)
		solid(wall, SHUTTER)
	window("+x", 18.0, 0.0, 0.15, 4.0, 4.5, false, METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-19.2, minf(s * 6.5, s * 13.5), 0.15), Vector3(-18.8, maxf(s * 6.5, s * 13.5), 8.5), SHUTTER)


## An open-sided steel shed, 20 × 30 m: portal frames every 6 m under a
## pitched roof, corrugated cladding to 3 m with a gap in each side to walk
## through, open ends, and an overhead crane on runway beams, hook let down.
func _hangar_shed() -> void:
	plinth(-15.0, -10.0, 15.0, 10.0, -0.4, 0.15, 1.0, PAD)
	for x: float in [-15.0, -9.0, -3.0, 3.0, 9.0, 15.0]:
		var xx := clampf(x, -14.75, 14.75)
		for s: float in [-1.0, 1.0]:
			post(xx, s * 9.8, 0.15, 8.8, 0.45, RUST)
			beam(Vector3(xx, s * 9.8, 8.6), Vector3(xx, 0.0, 10.7), 0.4, RUST)
	for s: float in [-1.0, 1.0]:
		_hexa([Vector2(-15.5, s * 10.6), Vector2(15.5, s * 10.6), Vector2(15.5, 0.0), Vector2(-15.5, 0.0)],
				[8.75, 8.75, 10.9, 10.9], [8.95, 8.95, 11.1, 11.1], ROOFED)
		box(Vector3(-15.0, s * 9.2 - 0.25, 6.8), Vector3(15.0, s * 9.2 + 0.25, 7.2), METAL)
	wall_run("y", Vector2(-10.1, -9.95), -15.0, 15.0, 0.15, 3.0, [[-7.5, -1.5]], SHUTTER)
	wall_run("y", Vector2(9.95, 10.1), -15.0, 15.0, 0.15, 3.0, [[4.5, 10.5]], SHUTTER)
	# The crane: bridge girder across the runways, end trucks, trolley, hook.
	box(Vector3(2.4, -9.4, 7.2), Vector3(3.6, 9.4, 7.9), {"top": METAL, "side": RUST_PANEL, "bottom": METAL})
	for s: float in [-1.0, 1.0]:
		box(Vector3(1.6, s * 9.2 - 0.35, 7.2), Vector3(4.4, s * 9.2 + 0.35, 7.6), METAL)
	box(Vector3(2.2, -1.9, 7.9), Vector3(3.8, -0.3, 8.6), SHUTTER)
	for y: float in [-1.35, -0.85]:
		post(3.0, y, 3.1, 7.9, 0.05, METAL)
	box(Vector3(2.7, -1.4, 2.5), Vector3(3.3, -0.8, 3.1), RUST_PANEL)
	box(Vector3(2.9, -1.2, 1.9), Vector3(3.1, -1.0, 2.5), METAL)


## A two-storey plant office, 12 × 18 m: ribbon windows on both floors, an
## entrance canopy on the -X front, a sign frame and plant on the roof, and a
## ramp up the +X side to it.
func _plant_office() -> void:
	plinth(-6.5, -9.5, 6.5, 9.5, -0.5, 0.5, 2.0, PLINTH, {"+x": 0.0})
	box(Vector3(-6, -9, 0.5), Vector3(6, 9, 7.5), PLASTER_B)
	box(Vector3(-6.15, -9.15, 3.9), Vector3(6.15, 9.15, 4.15), FRAME)
	# Ribbon windows: the -X front (split round the door below), both ends.
	for z: float in [1.5, 5.0]:
		if z < 3.0:
			box(Vector3(-6.1, -8.0, z), Vector3(-6.0, -1.6, z + 1.4), GLASS)
			box(Vector3(-6.1, 1.6, z), Vector3(-6.0, 8.0, z + 1.4), GLASS)
		else:
			box(Vector3(-6.1, -8.0, z), Vector3(-6.0, 8.0, z + 1.4), GLASS)
		for s: float in [-1.0, 1.0]:
			box(Vector3(-5.0, minf(s * 9.0, s * 9.1), z), Vector3(4.5, maxf(s * 9.0, s * 9.1), z + 1.4), GLASS)
	window("-x", -6.0, 0.0, 0.5, 2.0, 2.5, false, METAL)
	box(Vector3(-8.0, -2.5, 3.0), Vector3(-6.0, 2.5, 3.25), FRAME)
	for y: float in [-2.3, 2.3]:
		post(-7.8, y, 0.0, 3.0, 0.15, METAL)
	box(Vector3(-6.25, -9.25, 7.5), Vector3(6.25, 9.25, 7.75), SLAB)
	parapet(-6.25, -9.25, 6.25, 9.25, 7.75, 0.8, 0.25, {"+x": [[4.5, 7.0]]})
	# The works' name board, and plant.
	for y: float in [-3.5, 3.5]:
		post(-1.0, y, 7.75, 10.0, 0.2, METAL)
	box(Vector3(-1.1, -4.5, 8.6), Vector3(-0.9, 4.5, 10.0), RUST_PANEL)
	for y: float in [-5.5, 5.0]:
		box(Vector3(1.5, y - 1.0, 7.75), Vector3(3.0, y + 1.0, 8.95), CLAD)
		cylinder(Vector3(2.25, y, 8.95), 0.55, 0.1, 10, GRATING)
	# Up the +X side: 14 m at about 29°, clear of the plinth, onto a landing.
	ramp(6.5, -9.5, 8.5, 4.5, 0.0, 0.0, 7.75, "+y")
	box(Vector3(6.0, 4.5, 0.0), Vector3(8.5, 7.0, 7.75), SLAB)
	rail("x", 8.375, -9.5, 4.5, 0.0, 7.75)
	rail("x", 8.375, 4.5, 7.0, 7.75, 7.75)
	rail("y", 6.875, 6.25, 8.5, 7.75, 7.75)


## A works gate on a road running along X: a guard booth, brick piers either
## side of an 8 m way, a boom across the way in, a sliding gate run half open
## along its track, and fence off both sides.
func _gatehouse() -> void:
	plinth(-2.0, 5.2, 2.0, 8.2, -0.3, 0.3, 0.5)
	box(Vector3(-1.6, 5.5, 0.3), Vector3(1.6, 7.9, 2.9), PLASTER_A)
	box(Vector3(-1.7, 5.4, 1.2), Vector3(1.7, 8.0, 2.3), GLASS)
	window("+x", 1.7, 6.7, 0.3, 1.0, 2.2, false, METAL)
	box(Vector3(-2.2, 5.0, 2.9), Vector3(2.2, 8.4, 3.15), FRAME)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-0.6, s * 4.6 - 0.6, -0.2), Vector3(0.6, s * 4.6 + 0.6, 3.2), BRICK)
		box(Vector3(-0.7, s * 4.6 - 0.7, 3.2), Vector3(0.7, s * 4.6 + 0.7, 3.45), FRAME)
	# The boom: a post, the arm down across the way in, a rest on the far side.
	box(Vector3(-3.4, -5.6, -0.2), Vector3(-2.8, -5.0, 1.2), RUST_PANEL)
	beam(Vector3(-3.1, -5.0, 1.0), Vector3(-3.1, 3.8, 1.0), 0.12, RUST_PANEL)
	post(-3.1, 4.0, -0.2, 0.95, 0.12, METAL)
	# The sliding gate, run back along its fence line on the -Y side.
	var gx := 0.9
	for z: float in [0.15, 2.0]:
		beam(Vector3(gx, -3.8, z), Vector3(gx, -11.8, z), 0.1, METAL)
	for y: float in [-3.8, -7.8, -11.8]:
		post(gx, y, 0.1, 2.05, 0.1, METAL)
	beam(Vector3(gx, -3.8, 0.2), Vector3(gx, -7.8, 1.95), 0.06, METAL)
	beam(Vector3(gx, -7.8, 0.2), Vector3(gx, -11.8, 1.95), 0.06, METAL)
	fence_run(Vector2(0.0, -5.2), Vector2(0.0, -14.0))
	fence_run(Vector2(0.0, 8.4), Vector2(0.0, 14.0))


## An asphalt car park for a building lot, 24 × 32 m: a double row of 24
## marked bays down the middle with wheel stops, aisles either side, kerbs
## round the edge with a way in at each end of each aisle, three lamps, a pay
## station, and five cars left where they were parked.
func _parking_lot() -> void:
	# 3/32 m: the lot's top on the grid, so each line stands one unit proud.
	var top := 0.09375
	box(Vector3(-12.0, -16.0, -0.35), Vector3(12.0, 16.0, top), LOT)
	wall_run("x", Vector2(-12.0, -11.7), -16.0, 16.0, top, 0.25, [], CONCRETE)
	wall_run("x", Vector2(11.7, 12.0), -16.0, 16.0, top, 0.25, [], CONCRETE)
	for s: float in [-1.0, 1.0]:
		var y0 := minf(s * 16.0, s * 15.7)
		wall_run("y", Vector2(y0, y0 + 0.3), -11.7, 11.7, top, 0.25, [[-11.7, -5.5], [5.5, 11.7]], CONCRETE)
	for k in 13:
		var y := -15.0 + k * 2.5
		box(Vector3(-5.0, y - 0.06, top), Vector3(-0.1, y + 0.06, 0.125), PAINT)
		box(Vector3(0.1, y - 0.06, top), Vector3(5.0, y + 0.06, 0.125), PAINT)
	box(Vector3(-0.06, -15.0, top), Vector3(0.06, 15.0, 0.125), PAINT)
	for k in 12:
		var y := -13.75 + k * 2.5
		box(Vector3(-1.0, y - 0.8, top), Vector3(-0.8, y + 0.8, 0.22), CONCRETE)
	for y: float in [-15.6, 0.0, 15.6]:
		lamp_at(Vector3(0.0, y, top), 0.0 if y < 0.0 else 180.0)
	box(Vector3(-8.2, 15.1, top), Vector3(-7.6, 15.6, 1.5), CLAD)
	box(Vector3(-8.25, 15.05, 1.2), Vector3(-7.55, 15.1, 1.4), GLOW)
	# Five cars, nose in to the middle, on the grid of bays.
	var cars := [[-2.6, -11.25, RUST_PANEL], [-2.6, -3.75, BLUE], [2.6, -8.75, GREEN], [2.6, 3.75, SHUTTER], [-2.6, 11.25, METAL]]
	for c: Array in cars:
		var x: float = c[0]
		car_at(Vector3(x, float(c[1]), top), 0.0 if x < 0.0 else 180.0, str(c[2]))


## A two-level parking deck, 25 × 37 m: asphalt at the ground, a deck at 3.5 m
## and a roof deck at 7 m on a grid of columns, joined by two ramps at about
## 11° that run up opposite sides. Parapets round each deck and rails where a
## ramp drops away. Six cars on the three levels, and lamps on the roof.
func _parking_deck() -> void:
	var top := 0.09375
	box(Vector3(-12.5, -18.5, -0.35), Vector3(12.5, 18.5, top), LOT)
	for x: float in [-12.0, -5.0, 5.0, 12.0]:
		for y: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
			post(x, y, top, 6.6, 0.6, FRAME)
	var deck := {"top": ASPHALT, "side": FRAME, "bottom": FRAME}
	# Ramp 1, ground to deck: under a hole in the deck along -X.
	ramp(-11.5, -16.0, -5.5, 2.0, top, top, 3.5, "-y")
	box(Vector3(-5.5, -18.5, 3.1), Vector3(12.5, 18.5, 3.5), deck)
	box(Vector3(-12.5, -18.5, 3.1), Vector3(-5.5, -16.0, 3.5), deck)
	box(Vector3(-12.5, 2.0, 3.1), Vector3(-5.5, 18.5, 3.5), deck)
	# Ramp 2, deck to roof: on the deck, under a hole in the roof along +X.
	ramp(5.5, -2.0, 11.5, 16.0, 3.5, 3.5, 7.0, "+y")
	box(Vector3(-12.5, -18.5, 6.6), Vector3(5.5, 18.5, 7.0), deck)
	box(Vector3(5.5, -18.5, 6.6), Vector3(12.5, -2.0, 7.0), deck)
	box(Vector3(5.5, 16.0, 6.6), Vector3(12.5, 18.5, 7.0), deck)
	# Parapets, open only where a ramp arrives.
	for z: float in [3.5, 7.0]:
		wall_run("y", Vector2(-18.5, -18.25), -12.5, 12.5, z, z + 1.0)
		wall_run("y", Vector2(18.25, 18.5), -12.5, 12.5, z, z + 1.0)
	wall_run("x", Vector2(12.25, 12.5), -18.25, 18.25, 3.5, 4.5)
	wall_run("x", Vector2(-12.5, -12.25), -18.25, 18.25, 3.5, 4.5, [[-16.0, 2.0]])
	wall_run("x", Vector2(-5.5, -5.25), -16.0, 2.0, 3.5, 4.5)
	wall_run("y", Vector2(2.0, 2.25), -12.25, -5.5, 3.5, 4.5)
	wall_run("x", Vector2(-12.5, -12.25), -18.25, 18.25, 7.0, 8.0)
	wall_run("x", Vector2(12.25, 12.5), -18.25, 18.25, 7.0, 8.0, [[-2.0, 16.0]])
	wall_run("x", Vector2(5.25, 5.5), -2.0, 16.0, 7.0, 8.0)
	wall_run("y", Vector2(-2.25, -2.0), 5.5, 12.25, 7.0, 8.0)
	# A ramp's outer side gets a wall, its inner side a rail.
	upstand("x", Vector2(-11.5, -11.25), -16.0, 2.0, top, 3.5, false)
	rail("x", -5.625, -16.0, 2.0, 3.5, top, true)
	upstand("x", Vector2(11.25, 11.5), -2.0, 16.0, 3.5, 7.0, true)
	rail("x", 5.625, -2.0, 16.0, 3.5, 7.0, true)
	for c: Array in [[0.0, -12.0, top, 90.0, BLUE], [0.0, 6.5, top, 90.0, RUST_PANEL], [-9.0, 12.0, 3.5, 0.0, GREEN],
			[1.0, -10.0, 3.5, 90.0, SHUTTER], [-8.5, -12.0, 7.0, 0.0, METAL], [0.0, 8.0, 7.0, 90.0, BLUE]]:
		car_at(Vector3(float(c[0]), float(c[1]), float(c[2])), float(c[3]), str(c[4]))
	for y: float in [-9.0, 9.0]:
		lamp_at(Vector3(-11.6, y, 7.0), 0.0)


# ── Industrial: yards ────────────────────────────────────────────────────────

## A shipping container stacked in a yard: the body and its doors only, since
## a yard holds dozens and the rails and bars of feature_container_stack's
## would triple its brushes. Doors at +Y when along Y, +X otherwise.
func yard_container(c: Vector3, along_y: bool, tex: String) -> void:
	if along_y:
		box(c + Vector3(-1.22, -6.1, 0.0), c + Vector3(1.22, 6.1, 2.6), tex)
		box(c + Vector3(-1.12, 6.1, 0.1), c + Vector3(1.12, 6.16, 2.5), RUST_PANEL)
	else:
		box(c + Vector3(-6.1, -1.22, 0.0), c + Vector3(6.1, 1.22, 2.6), tex)
		box(c + Vector3(6.1, -1.12, 0.1), c + Vector3(6.16, 1.12, 2.5), RUST_PANEL)


## A container yard for a building lot, 24 × 32 m: two blocks of containers
## stacked one to three high with a lane between them, a steel ramp onto the
## top of a single one for a lookout, and a floodlight.
func _container_yard() -> void:
	var top := 0.09375
	box(Vector3(-12.0, -16.0, -0.3), Vector3(12.0, 16.0, top), PAD)
	var colours := [GREEN, BLUE, RUST_PANEL, SHUTTER, GREEN, RUST_PANEL, BLUE, SHUTTER]
	var stacks := [[-9.3, -6.4, 3], [-6.8, -6.4, 2], [-9.3, 6.4, 2], [-6.8, 6.4, 1],
			[3.2, -6.4, 1], [5.7, -6.4, 2], [3.2, 6.4, 3], [5.7, 6.4, 2]]
	var n := 0
	for s: Array in stacks:
		for tier in int(s[2]):
			yard_container(Vector3(float(s[0]), float(s[1]), top + tier * 2.6), true, colours[n % colours.size()])
			n += 1
	# The lookout ramp: from the lane onto the single container at (-6.8, 6.4).
	var z1 := top + 2.6
	flight(-5.58, 4.4, -0.6, 6.4, top, z1, "-x", 0.2, METAL)
	for x: float in [-4.3, -2.3]:
		var zz := lerpf(z1, top, (x + 5.58) / 4.98) - 0.2
		for y: float in [4.55, 6.25]:
			post(x, y, -0.2, zz, 0.12, METAL)
	rail("y", 6.3, -5.58, -0.6, z1, top, true)
	lamp_at(Vector3(11.0, 0.0, top), 180.0)


## A scrap yard, about 26 m square: three heaps of rusted scrap with plates
## and girders sticking out of them, a pyramid of crushed cars, a material
## handler with its grab over the biggest heap, and sheet fencing on two sides.
func _scrap_yard() -> void:
	box(Vector3(-13.0, -13.0, -0.3), Vector3(13.0, 13.0, 0.05), {"top": DIRT, "side": DIRT, "bottom": DIRT})
	mound(Vector3(-5.0, -4.0, 0.0), 5.5, 4.5, 3.2, 901, RUST)
	mound(Vector3(5.0, 6.0, 0.0), 4.0, 5.0, 2.6, 902, RUST_PANEL)
	mound(Vector3(6.5, -7.0, 0.0), 3.0, 3.5, 2.0, 903, RUST)
	var rng := RandomNumberGenerator.new()
	rng.seed = 904
	var heaps := [[Vector2(-5.0, -4.0), 4.0, 2.4], [Vector2(5.0, 6.0), 3.2, 1.9], [Vector2(6.5, -7.0), 2.2, 1.4]]
	var junk := [RUST_PANEL, METAL, GREEN, BLUE, RUST, SHUTTER]
	for i in 11:
		var hp: Array = heaps[i % 3]
		var at: Vector2 = hp[0]
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.3, float(hp[1]))
		var z: float = float(hp[2]) * (1.0 - d / (float(hp[1]) + 1.0)) - 0.2
		if i % 3 == 1:
			var p := Vector3(at.x + cos(a) * d, at.y + sin(a) * d, z)
			beam(p, p + Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5), rng.randf_range(0.8, 1.8)), 0.2, RUST)
		else:
			tipped_box(Vector3(at.x + cos(a) * d, at.y + sin(a) * d, z + 0.3), Vector3(rng.randf_range(1.0, 2.2), rng.randf_range(0.8, 1.6), 0.12),
					Vector3(rng.randf_range(-35, 35), rng.randf_range(-35, 35), rng.randf_range(0, 180)), junk[i % junk.size()])
	# Crushed cars, three, two and one.
	var cube := Vector3(1.6, 3.2, 0.8)
	var row := 0
	for count: int in [3, 2, 1]:
		for k in count:
			var y := -8.0 + (k - (count - 1) * 0.5) * 1.75
			box(Vector3(-9.8, y - cube.x * 0.5, 0.05 + row * cube.z), Vector3(-9.8 + cube.y, y + cube.x * 0.5, 0.05 + (row + 1) * cube.z), junk[(row * 3 + k) % junk.size()])
		row += 1
	_excavator_at(Vector3(-2.0, 7.5, 0.05), -120.0, "grab")
	wall_run("x", Vector2(12.8, 13.0), -13.0, 13.0, -0.2, 2.4, [], RUST_PANEL)
	wall_run("y", Vector2(-13.0, -12.8), -13.0, 12.8, -0.2, 2.4, [], RUST_PANEL)


## A stockpile of loose stuff — coal, ore, spoil: a flank, a shoulder and a
## flat top, eight facets round. At 12 m across and 3.5 m high the flank is
## about 28° and the shoulder 16°, so it can be walked up — unlike mound(),
## whose base is steep.
## The slopes break sharply on purpose. FuncGodot drops any corner where the
## three faces meeting there are within a few degrees of one plane (its triple
## product test, CMP_EPSILON 0.008), so a smooth dome or a true cone comes out
## of it in shards with faces missing.
func heap(c: Vector3, rx: float, ry: float, h: float, seed: int, tex: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts: Array = []
	for ring: Vector3 in [Vector3(-0.3, 1.0, 8), Vector3(0.65, 0.6, 8), Vector3(1.0, 0.25, 6)]:
		var count := int(ring.z)
		var turn := rng.randf_range(0.0, TAU)
		for i in count:
			var a := turn + TAU * (i + rng.randf_range(-0.15, 0.15)) / count
			var j := rng.randf_range(0.94, 1.04)
			var z := ring.x if ring.x < 0.0 else h * ring.x
			pts.append(c + Vector3(cos(a) * rx * ring.y * j, sin(a) * ry * ring.y * j, z))
	solid(pts, tex, 4)


## A coal pile 24 m across and 3.5 m high, walkable all round at under 30°,
## fed by a radial stacker whose boom reaches over its crest from a pivot
## tower, with the feed belt running off from the pivot, and two spill piles.
func _coal_pile() -> void:
	heap(Vector3.ZERO, 12.0, 11.0, 3.5, 911, COAL)
	heap(Vector3(-5.0, 12.8, 0.0), 3.2, 2.6, 1.4, 912, COAL)
	heap(Vector3(8.5, -11.0, 0.0), 2.4, 2.8, 1.1, 913, COAL)
	box(Vector3(-16.1, -0.9, -0.3), Vector3(-14.3, 0.9, 3.4), CONCRETE)
	cylinder(Vector3(-15.2, 0.0, 3.4), 1.1, 0.5, 10, METAL)
	var foot := Vector3(-15.2, 0.0, 4.2)
	var head := Vector3(-1.0, 0.0, 7.4)
	for s: float in [-0.55, 0.55]:
		beam(foot + Vector3(0, s, 0), head + Vector3(0, s, 0), 0.22, RUST_PANEL)
	var up := Vector3(0, 0, 0.12)
	var belt: Array = []
	for p: Vector3 in [foot, head]:
		for s: float in [-0.45, 0.45]:
			belt.append(p + Vector3(0, s, 0.1))
			belt.append(p + Vector3(0, s, 0.1) + up)
	solid(belt, RUBBER)
	beam(Vector3(-15.2, 0.0, 3.9), Vector3(-15.2, 0.0, 9.0), 0.2, METAL)
	beam(Vector3(-15.2, 0.0, 9.0), head + Vector3(0, 0, 0.3), 0.08, METAL)
	box(Vector3(-19.0, -1.0, 3.6), Vector3(-16.1, 1.0, 5.0), CONCRETE)
	# The feed belt, on trestles, from the pivot out along -X.
	box(Vector3(-30.0, -0.6, 1.1), Vector3(-16.1, 0.6, 1.5), {"top": RUBBER, "side": METAL, "bottom": METAL})
	for x: float in [-28.5, -23.0, -18.0]:
		for y: float in [-0.5, 0.5]:
			post(x, y, -0.3, 1.1, 0.14, METAL)


# ── Industrial: structures ───────────────────────────────────────────────────

## A 45 m brick chimney on a square base, tapering, banded in steel, with the
## flue coming in low from the side and a light at the top.
func _smokestack() -> void:
	box(Vector3(-3.5, -3.5, -0.5), Vector3(3.5, 3.5, 2.5), BRICK)
	box(Vector3(-3.7, -3.7, 2.5), Vector3(3.7, 3.7, 2.8), FRAME)
	cylinder(Vector3(0, 0, 2.8), 2.6, 42.2, 12, BRICK, 1.6)
	for z: float in [15.0, 30.0, 42.0]:
		var r := lerpf(2.6, 1.6, (z - 2.8) / 42.2) + 0.1
		cylinder(Vector3(0, 0, z), r, 0.4, 12, RUST)
	cylinder(Vector3(0, 0, 45.0), 1.75, 0.5, 12, FRAME, 1.7)
	cylinder(Vector3(0, 0, 45.5), 0.25, 0.4, 6, GLOW)
	box(Vector3(3.5, -1.2, 0.0), Vector3(9.0, 1.2, 2.8), RUST_PANEL)
	box(Vector3(9.0, -1.5, -0.3), Vector3(10.0, 1.5, 3.2), CONCRETE)


## A blast furnace, the works' landmark, about 53 × 41 m and 44 m tall:
##   the cast house floor, a platform 6 m up that a ramp on its -Y side climbs;
##   the furnace on it — hearth, bosh, stack and throat — banded and ringed
##   by its bustle pipe;
##   four uptakes off the top gathering into a downcomer that drops to the
##   dust catcher on the +Y side;
##   three hot-blast stoves in a row along +X, their main feeding the bustle;
##   the skip incline climbing from -X to the top, with its skip halfway.
func _blast_furnace() -> void:
	box(Vector3(-10, -8, -0.5), Vector3(10, 8, 6.0), {"top": DECK, "side": CONCRETE, "bottom": CONCRETE})
	parapet(-10, -8, 10, 8, 6.0, 1.0, 0.25, {"-y": [[-8.0, -4.0]]})
	ramp(-8.0, -20.0, -4.0, -8.0, 0.0, 0.0, 6.0, "+y")
	rail("x", -7.875, -20.0, -8.0, 0.0, 6.0)
	rail("x", -4.125, -20.0, -8.0, 0.0, 6.0)
	cylinder(Vector3(0, 0, 6.0), 5.0, 6.0, 12, RUST_PANEL)
	cylinder(Vector3(0, 0, 12.0), 5.0, 4.0, 12, RUST, 6.2)
	cylinder(Vector3(0, 0, 16.0), 6.2, 16.0, 12, RUST_PANEL, 4.2)
	cylinder(Vector3(0, 0, 32.0), 4.2, 3.0, 12, METAL, 2.8)
	for z: float in [20.0, 26.0]:
		cylinder(Vector3(0, 0, z), lerpf(6.2, 4.2, (z - 16.0) / 16.0) + 0.15, 0.5, 12, METAL)
	for k in 12:
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		pipe(Vector3(cos(a0) * 7.5, sin(a0) * 7.5, 13.0), Vector3(cos(a1) * 7.5, sin(a1) * 7.5, 13.0), 0.6, RUST, 8)
	# Uptakes, the collector, the downcomer and the dust catcher.
	var collect := Vector3(0.0, 4.5, 43.0)
	for q: Vector2 in [Vector2(-1.8, -1.8), Vector2(1.8, -1.8), Vector2(1.8, 1.8), Vector2(-1.8, 1.8)]:
		pipe(Vector3(q.x, q.y, 34.5), Vector3(q.x * 1.2, q.y * 1.2, 41.5), 0.55, RUST, 8)
		pipe(Vector3(q.x * 1.2, q.y * 1.2, 41.5), collect, 0.55, RUST, 8)
	cylinder(collect - Vector3(0, 0, 1.0), 1.1, 2.0, 8, METAL)
	pipe(collect, Vector3(0.0, 18.0, 23.5), 1.0, RUST_PANEL, 8)
	cylinder(Vector3(0, 18.0, 4.0), 1.0, 4.0, 10, RUST, 3.2)
	cylinder(Vector3(0, 18.0, 8.0), 3.2, 14.0, 10, RUST_PANEL)
	cylinder(Vector3(0, 18.0, 22.0), 3.2, 2.0, 10, RUST, 1.2)
	for q: Vector2 in [Vector2(-2.4, 15.6), Vector2(2.4, 15.6), Vector2(2.4, 20.4), Vector2(-2.4, 20.4)]:
		post(q.x, q.y, -0.3, 8.2, 0.5, METAL)
	# The stoves and the hot-blast main.
	for y: float in [-9.0, 0.0, 9.0]:
		cylinder(Vector3(17.0, y, -0.3), 4.2, 1.0, 12, CONCRETE)
		cylinder(Vector3(17.0, y, 0.7), 3.8, 29.3, 12, RUST_PANEL)
		cylinder(Vector3(17.0, y, 30.0), 3.8, 3.0, 12, METAL, 1.5)
	pipe(Vector3(17.0, -9.0, 12.0), Vector3(17.0, 9.0, 12.0), 0.9, RUST, 8)
	pipe(Vector3(13.0, 0.0, 12.0), Vector3(7.6, 0.0, 12.8), 0.9, RUST, 8)
	# The skip incline, on three bents, and its skip.
	var bottom := Vector3(-32.0, 0.0, 0.5)
	var topp := Vector3(-3.5, 0.0, 36.0)
	for s: float in [-1.5, 1.5]:
		beam(bottom + Vector3(0, s, 0), topp + Vector3(0, s, 0), 0.45, RUST)
	var deck: Array = []
	for p: Vector3 in [bottom, topp]:
		for s: float in [-1.3, 1.3]:
			deck.append(p + Vector3(0, s, 0))
			deck.append(p + Vector3(0, s, 0.3))
	solid(deck, GRATING)
	for x: float in [-24.0, -16.0, -8.0]:
		var z := lerpf(bottom.z, topp.z, (x - bottom.x) / (topp.x - bottom.x)) - 0.3
		for s: float in [-1.0, 1.0]:
			beam(Vector3(x, s * 3.0, -0.3), Vector3(x, s * 1.5, z), 0.4, RUST)
	var mid := bottom.lerp(topp, 0.55)
	box(mid + Vector3(-1.2, -1.1, 0.3), mid + Vector3(1.2, 1.1, 2.0), METAL)


## Four concrete silos 25 m tall on a slab, a head house across their tops,
## the elevator leg standing beside them with its bridge to the head house,
## and a truck shed at the leg's foot.
func _silos() -> void:
	box(Vector3(-7.5, -7.5, -0.5), Vector3(7.5, 7.5, 1.5), CONCRETE)
	for q: Vector2 in [Vector2(-3.4, -3.4), Vector2(3.4, -3.4), Vector2(3.4, 3.4), Vector2(-3.4, 3.4)]:
		cylinder(Vector3(q.x, q.y, 1.5), 3.3, 23.5, 12, PALE)
		cylinder(Vector3(q.x, q.y, 12.0), 3.4, 0.4, 12, FRAME)
	box(Vector3(-7.2, -7.2, 25.0), Vector3(7.2, 7.2, 29.0), CLAD)
	box(Vector3(-7.4, -7.4, 29.0), Vector3(7.4, 7.4, 29.3), FRAME)
	for y: float in [-4.0, 0.0, 4.0]:
		window("-x", -7.2, y, 26.2, 1.4, 1.2, false, GLASS)
	box(Vector3(8.5, -1.5, -0.3), Vector3(11.5, 1.5, 32.0), CLAD)
	box(Vector3(8.2, -1.9, 32.0), Vector3(11.8, 1.9, 34.5), CLAD)
	box(Vector3(7.2, -1.0, 27.0), Vector3(8.5, 1.0, 29.0), CLAD)
	box(Vector3(11.5, -4.0, -0.3), Vector3(17.0, 4.0, 5.0), RUST_PANEL)
	box(Vector3(11.5, -4.3, 5.0), Vector3(17.3, 4.3, 5.25), FRAME)
	window("+x", 17.0, 0.0, 0.0, 3.6, 4.2, false, METAL)


## A water tower 26 m tall: a banded steel tank with a cone roof and a cone
## bottom on six raking legs braced at two levels, its riser pipe down the
## middle, each leg on a footing.
func _water_tower() -> void:
	cylinder(Vector3(0, 0, 15.5), 1.2, 2.5, 12, RUST_PANEL, 5.0)
	cylinder(Vector3(0, 0, 18.0), 5.0, 6.0, 12, RUST_PANEL)
	cylinder(Vector3(0, 0, 20.8), 5.08, 0.4, 12, METAL)
	cylinder(Vector3(0, 0, 24.0), 5.0, 2.5, 12, METAL, 0.5)
	cylinder(Vector3(0, 0, -0.3), 0.6, 16.0, 8, METAL)
	var legs := 6
	for k in legs:
		var a := TAU * (k + 0.5) / legs
		var foot := Vector3(cos(a) * 6.0, sin(a) * 6.0, -0.3)
		var head := Vector3(cos(a) * 4.6, sin(a) * 4.6, 17.2)
		box(foot + Vector3(-0.6, -0.6, -0.2), foot + Vector3(0.6, 0.6, 0.6), CONCRETE)
		beam(foot, head, 0.45, METAL)
		var a1 := TAU * (k + 1.5) / legs
		for t: float in [0.35, 0.7]:
			var p := foot.lerp(head, t)
			var q := Vector3(cos(a1) * 6.0, sin(a1) * 6.0, -0.3).lerp(Vector3(cos(a1) * 4.6, sin(a1) * 4.6, 17.2), t)
			beam(p, q, 0.2, METAL)


## A goliath gantry crane spanning 29 m on rails along X: an A-frame of legs on
## bogies at each side, the box girder 16.5 m up, its trolley, the operator's
## cab hung under one end, and the hook let down on four ropes.
func _gantry_crane() -> void:
	for s: float in [-1.0, 1.0]:
		var y := s * 12.0
		box(Vector3(-15.0, y - 0.4, -0.3), Vector3(15.0, y + 0.4, 0.05), CONCRETE)
		box(Vector3(-15.0, y - 0.1, 0.05), Vector3(15.0, y + 0.1, 0.2), METAL)
		box(Vector3(-5.4, y - 0.7, 0.2), Vector3(5.4, y + 0.7, 1.4), RUST_PANEL)
		for x: float in [-4.0, 4.0]:
			beam(Vector3(x, y, 1.3), Vector3(x * 0.2, y, 16.6), 0.7, RUST_PANEL)
	box(Vector3(-1.2, -14.5, 16.5), Vector3(1.2, 14.5, 18.5), RUST_PANEL)
	box(Vector3(-1.6, -3.0, 18.5), Vector3(1.6, 1.0, 19.6), METAL)
	box(Vector3(-1.2, 8.0, 14.3), Vector3(1.2, 10.2, 16.5), {"top": METAL, "side": GLASS, "bottom": METAL})
	for q: Vector2 in [Vector2(-1.35, -1.6), Vector2(1.35, -1.6), Vector2(-1.35, -0.4), Vector2(1.35, -0.4)]:
		post(q.x, q.y, 8.0, 18.5, 0.05, METAL)
	box(Vector3(-1.5, -1.6, 7.2), Vector3(1.5, -0.4, 8.0), RUST_PANEL)
	box(Vector3(-0.15, -1.15, 6.5), Vector3(0.15, -0.85, 7.2), METAL)


## A spherical gas holder 14 m across, its equator 10 m up, on eight legs
## braced round, with a valve platform on top and its main at the foot.
func _gas_sphere() -> void:
	var r := 7.0
	var c := Vector3(0, 0, 10.0)
	var pts: Array = [c + Vector3(0, 0, r), c - Vector3(0, 0, r)]
	for lat: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var e := deg_to_rad(lat)
		for i in 12:
			var a := TAU * (i + (0.5 if int(lat) % 60 == 0 else 0.0)) / 12.0
			pts.append(c + Vector3(cos(e) * cos(a) * r, cos(e) * sin(a) * r, sin(e) * r))
	solid(pts, PALE)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var d := Vector2(cos(a), sin(a)) * (r + 0.1)
		post(d.x, d.y, -0.3, 10.0, 0.4, METAL)
		var a1 := TAU * (k + 1.5) / 8.0
		var d1 := Vector2(cos(a1), sin(a1)) * (r + 0.1)
		beam(Vector3(d.x, d.y, 0.5), Vector3(d1.x, d1.y, 6.5), 0.15, METAL)
	cylinder(Vector3(0, 0, 16.9), 1.3, 0.4, 8, GRATING)
	pipe(Vector3(0, 0, 3.2), Vector3(0, 0, 0.5), 0.35, METAL, 8)
	pipe(Vector3(0, 0, 0.5), Vector3(11.0, 0, 0.5), 0.35, METAL, 8)
	box(Vector3(10.5, -0.5, -0.3), Vector3(11.5, 0.5, 1.2), CONCRETE)


## An inclined conveyor gallery 30 m long, climbing about 18° from a hopper at
## -X to a transfer tower at +X, on three trestles.
func _conveyor() -> void:
	var a := Vector3(-15.0, 0.0, 1.5)
	var b := Vector3(15.0, 0.0, 11.0)
	var hull: Array = []
	for p: Vector3 in [a, b]:
		for s: float in [-1.2, 1.2]:
			hull.append(p + Vector3(0, s, 0))
			hull.append(p + Vector3(0, s, 2.4))
	solid(hull, {"top": RUST_PANEL, "side": CLAD, "bottom": METAL})
	for x: float in [-7.0, 1.0, 9.0]:
		var z := lerpf(a.z, b.z, (x - a.x) / (b.x - a.x))
		for s: float in [-1.0, 1.0]:
			post(x, s * 1.0, -0.3, z, 0.3, METAL)
		box(Vector3(x - 0.2, -1.3, z - 0.4), Vector3(x + 0.2, 1.3, z), METAL)
	solid([Vector3(-19.0, -2.0, 3.2), Vector3(-15.0, -2.0, 3.2), Vector3(-15.0, 2.0, 3.2), Vector3(-19.0, 2.0, 3.2),
			Vector3(-17.8, -0.8, 1.2), Vector3(-16.2, -0.8, 1.2), Vector3(-16.2, 0.8, 1.2), Vector3(-17.8, 0.8, 1.2)], RUST_PANEL)
	for q: Vector2 in [Vector2(-18.5, -1.5), Vector2(-15.5, -1.5), Vector2(-15.5, 1.5), Vector2(-18.5, 1.5)]:
		post(q.x, q.y, -0.3, 3.2, 0.25, METAL)
	box(Vector3(15.0, -3.0, -0.3), Vector3(21.0, 3.0, 14.0), CLAD)
	box(Vector3(14.8, -3.2, 14.0), Vector3(21.2, 3.2, 14.3), FRAME)
	window("+x", 21.0, 0.0, 0.0, 3.0, 3.5, false, METAL)


## A pipe rack 25 m long on five bents: four pipes on the lower tier, three
## and a cable tray on the top, and one main turning down to a valve at +Y.
func _pipe_rack() -> void:
	for y: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		for x: float in [-2.2, 2.2]:
			post(x, y, -0.3, 7.2, 0.35, METAL)
		for z: float in [4.05, 6.85]:
			box(Vector3(-2.4, y - 0.15, z), Vector3(2.4, y + 0.15, z + 0.3), RUST_PANEL)
	var low := [[-1.6, 0.35, RUST], [-0.6, 0.25, GREEN], [0.4, 0.3, METAL], [1.4, 0.2, BLUE]]
	for p: Array in low:
		var r: float = p[1]
		pipe(Vector3(float(p[0]), -12.5, 4.35 + r), Vector3(float(p[0]), 12.5, 4.35 + r), r, p[2], 8)
	var high := [[-1.4, 0.4, METAL], [-0.4, 0.3, RUST], [0.5, 0.2, GREEN]]
	for p: Array in high:
		var r: float = p[1]
		pipe(Vector3(float(p[0]), -12.5, 7.15 + r), Vector3(float(p[0]), 12.5, 7.15 + r), r, p[2], 8)
	box(Vector3(1.1, -12.5, 7.15), Vector3(2.1, 12.5, 7.3), GRATING)
	pipe(Vector3(-1.6, 12.5, 4.7), Vector3(-1.6, 13.6, 4.7), 0.35, RUST, 8)
	pipe(Vector3(-1.6, 13.6, 4.7), Vector3(-1.6, 13.6, 0.9), 0.35, RUST, 8)
	box(Vector3(-2.2, 13.0, -0.3), Vector3(-1.0, 14.2, 0.9), RUST_PANEL)


## A substation, 20 × 16 m of gravel inside a fence with a gate at -X: two
## transformers, two gantries with insulators carrying three busbars out over
## +X, breakers on stands, and the control hut.
func _substation() -> void:
	box(Vector3(-10.0, -8.0, -0.3), Vector3(10.0, 8.0, 0.1), {"top": BALLAST, "side": CONCRETE, "bottom": CONCRETE})
	fence_run(Vector2(-10.0, -8.0), Vector2(10.0, -8.0), 0.1)
	fence_run(Vector2(10.0, -8.0), Vector2(10.0, 8.0), 0.1)
	fence_run(Vector2(10.0, 8.0), Vector2(-10.0, 8.0), 0.1)
	fence_run(Vector2(-10.0, 8.0), Vector2(-10.0, 2.0), 0.1)
	fence_run(Vector2(-10.0, -2.0), Vector2(-10.0, -8.0), 0.1)
	for y: float in [-4.0, 4.0]:
		transformer_at(Vector3(-4.5, y, 0.1))
	for x: float in [1.5, 6.0]:
		for s: float in [-1.0, 1.0]:
			post(x, s * 3.0, 0.1, 9.0, 0.3, METAL)
		box(Vector3(x - 0.2, -3.3, 8.7), Vector3(x + 0.2, 3.3, 9.1), METAL)
		box(Vector3(x - 0.15, -3.2, 6.0), Vector3(x + 0.15, 3.2, 6.3), METAL)
		for y: float in [-1.5, 0.0, 1.5]:
			cylinder(Vector3(x, y, 7.9), 0.12, 0.8, 6, RUBBER)
	for y: float in [-1.5, 0.0, 1.5]:
		pipe(Vector3(-4.5, y, 7.8), Vector3(9.8, y, 7.8), 0.08, METAL, 6)
		post(-1.5, y, 0.1, 1.4, 0.15, METAL)
		box(Vector3(-2.0, y - 0.4, 1.4), Vector3(-1.0, y + 0.4, 2.6), GREEN)
		cylinder(Vector3(-1.5, y, 2.6), 0.1, 0.7, 6, RUBBER)
	box(Vector3(5.5, -7.5, 0.1), Vector3(9.5, -4.0, 3.0), BRICK)
	box(Vector3(5.3, -7.7, 3.0), Vector3(9.7, -3.8, 3.25), FRAME)
	window("-x", 5.5, -5.75, 0.1, 1.0, 2.2, false, METAL)


## A substation transformer on its bunded pad: tank, two radiator banks,
## three bushings and the conservator.
func transformer_at(c: Vector3) -> void:
	box(c + Vector3(-1.9, -1.5, -0.2), c + Vector3(1.9, 1.5, 0.3), PAD)
	box(c + Vector3(-0.9, -0.7, 0.3), c + Vector3(0.9, 0.7, 2.3), GREEN)
	for s: float in [-1.0, 1.0]:
		box(c + Vector3(-0.8, minf(s * 0.7, s * 1.2), 0.5), c + Vector3(0.8, maxf(s * 0.7, s * 1.2), 2.0), GRATING)
	for x: float in [-0.45, 0.0, 0.45]:
		cylinder(c + Vector3(x, 0.25, 2.3), 0.1, 0.9, 6, RUBBER)
	log_x(c + Vector3(-0.5, -0.3, 2.35), 0.25, 1.4, 8, GREEN, "x")


# ── Industrial: rail and river ───────────────────────────────────────────────

## Twenty-four metres of standard-gauge track along Y: a ballast shoulder,
## sixteen sleepers and two rails. The ends are square, so lengths butt
## together. A wagon's wheels sit on its rails at 0.35 m.
func _rail_track() -> void:
	# No collision on any of it. The rails stand 0.35 m above the ballast and an
	# agent climbs 0.25, so with collision every track baked as a wall and cut
	# the navmesh of the yard it runs through into strips. The squad walks over
	# track, it does not walk into it.
	no_collision()
	plinth(-1.5, -12.0, 1.5, 12.0, -0.3, 0.05, 0.6, {"top": BALLAST, "side": BALLAST, "bottom": BALLAST}, {"-y": 0.0, "+y": 0.0})
	for k in 16:
		var y := -11.25 + k * 1.5
		box(Vector3(-1.3, y - 0.12, 0.05), Vector3(1.3, y + 0.12, 0.2), WOOD_DARK)
	for x: float in [-0.75, 0.75]:
		box(Vector3(x - 0.04, -12.0, 0.2), Vector3(x + 0.04, 12.0, 0.35), METAL)


## A two-axle bogie at `c`, standing on rails whose heads are 0.35 m up: side
## frames, two wheelsets drawn as axle prisms, and the bolster.
func bogie_at(c: Vector3) -> void:
	for x: float in [-0.95, 0.95]:
		box(c + Vector3(x - 0.08, -1.3, 0.45), c + Vector3(x + 0.08, 1.3, 0.95), METAL)
	for y: float in [-0.9, 0.9]:
		pipe(c + Vector3(-0.85, y, 0.8), c + Vector3(0.85, y, 0.8), 0.45, RUST, 8)
	box(c + Vector3(-1.0, -0.3, 0.95), c + Vector3(1.0, 0.3, 1.1), METAL)


func _couplers(half: float) -> void:
	for s: float in [-1.0, 1.0]:
		box(Vector3(-0.2, minf(s * half, s * (half + 0.45)), 0.85), Vector3(0.2, maxf(s * half, s * (half + 0.45)), 1.1), METAL)


## A boxcar 15 m long along Y, for the rail track: sliding doors each side.
func _rail_boxcar() -> void:
	box(Vector3(-1.35, -7.6, 1.0), Vector3(1.35, 7.6, 1.15), METAL)
	box(Vector3(-1.45, -7.5, 1.15), Vector3(1.45, 7.5, 4.3), RUST_PANEL)
	box(Vector3(-1.5, -7.55, 4.3), Vector3(1.5, 7.55, 4.45), METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(minf(s * 1.45, s * 1.53), -1.6, 1.25), Vector3(maxf(s * 1.45, s * 1.53), 1.6, 4.15), SHUTTER)
	for y: float in [-5.3, 5.3]:
		bogie_at(Vector3(0, y, 0))
	_couplers(7.6)


## A tank car 14 m long along Y: a black tank on the underframe, a dome on top.
func _rail_tank_car() -> void:
	box(Vector3(-1.2, -6.9, 1.0), Vector3(1.2, 6.9, 1.15), METAL)
	log_x(Vector3(0, 0, 1.15), 1.35, 12.2, 12, RUBBER, "y")
	cylinder(Vector3(0, 0, 3.7), 0.5, 0.5, 8, METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-1.2, minf(s * 6.1, s * 6.9), 1.15), Vector3(1.2, maxf(s * 6.1, s * 6.9), 1.25), GRATING)
	for y: float in [-5.0, 5.0]:
		bogie_at(Vector3(0, y, 0))
	_couplers(6.9)


## An open gondola 14 m long along Y, ribbed, heaped with coal.
func _rail_gondola() -> void:
	box(Vector3(-1.4, -7.0, 1.0), Vector3(1.4, 7.0, 1.2), METAL)
	wall_run("x", Vector2(-1.4, -1.3), -7.0, 7.0, 1.2, 2.6, [], RUST_PANEL)
	wall_run("x", Vector2(1.3, 1.4), -7.0, 7.0, 1.2, 2.6, [], RUST_PANEL)
	wall_run("y", Vector2(-7.0, -6.9), -1.3, 1.3, 1.2, 2.6, [], RUST_PANEL)
	wall_run("y", Vector2(6.9, 7.0), -1.3, 1.3, 1.2, 2.6, [], RUST_PANEL)
	for y: float in [-4.0, 0.0, 4.0]:
		for s: float in [-1.0, 1.0]:
			box(Vector3(minf(s * 1.4, s * 1.48), y - 0.1, 1.1), Vector3(maxf(s * 1.4, s * 1.48), y + 0.1, 2.6), METAL)
	heap(Vector3(0, 0, 1.2), 1.2, 6.4, 1.6, 921, COAL)
	for y: float in [-5.0, 5.0]:
		bogie_at(Vector3(0, y, 0))
	_couplers(7.0)


## A river coal barge, 37 × 10.5 m, for mooring along a bank: set its z 0 at
## the water line. The hull goes 4.5 m down, to the river bed, so nothing can
## walk under it. Raked ends, a coaming round the hold, two heaps of coal,
## timber fenders, bollards and a winch.
func _coal_barge() -> void:
	box(Vector3(-5.25, -16.0, -4.5), Vector3(5.25, 16.0, 1.0), RUST_PANEL)
	for s: float in [-1.0, 1.0]:
		var y0 := s * 16.0
		var y1 := s * 18.5
		_hexa([Vector2(-5.25, y0), Vector2(5.25, y0), Vector2(5.25, y1), Vector2(-5.25, y1)],
				[-4.5, -4.5, -0.5, -0.5], [1.0, 1.0, 1.0, 1.0], {"top": RUST, "side": RUST_PANEL, "bottom": RUST_PANEL})
		box(Vector3(minf(s * 5.25, s * 5.5), -15.0, 0.0), Vector3(maxf(s * 5.25, s * 5.5), 15.0, 0.6), WOOD)
		box(Vector3(-0.8, minf(s * 16.2, s * 17.4), 1.0), Vector3(0.8, maxf(s * 16.2, s * 17.4), 1.9), METAL)
		for x: float in [-4.6, 4.6]:
			cylinder(Vector3(x, s * 15.4, 1.0), 0.25, 0.6, 8, METAL)
	wall_run("x", Vector2(-4.4, -4.15), -14.0, 14.0, 1.0, 2.2, [], RUST)
	wall_run("x", Vector2(4.15, 4.4), -14.0, 14.0, 1.0, 2.2, [], RUST)
	wall_run("y", Vector2(-14.0, -13.75), -4.15, 4.15, 1.0, 2.2, [], RUST)
	wall_run("y", Vector2(13.75, 14.0), -4.15, 4.15, 1.0, 2.2, [], RUST)
	for y: float in [-7.0, 7.0]:
		heap(Vector3(0, y, 1.0), 3.6, 6.3, 2.4, 931 + int(y), COAL)


## A river lock gate and dam, walkable: a deck 6 m wide and 44 m long across a
## channel, on four piers with noses upstream (-X) and steel gates between
## them, abutments at each end, a solid parapet on the upstream edge to take
## cover behind, a rail and the gate hoist houses on the downstream edge, and
## a control tower on the +Y abutment. Set its z 0 at the height of the banks;
## flatten the ground under each abutment to that height.
func _lock_dam() -> void:
	box(Vector3(-3.0, -22.0, -0.6), Vector3(3.0, 22.0, 0.0), SLAB)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-4.5, minf(s * 16.0, s * 24.0), -7.0), Vector3(4.5, maxf(s * 16.0, s * 24.0), 0.0), {"top": DECK, "side": CONCRETE, "bottom": CONCRETE})
	for y: float in [-12.0, -4.0, 4.0, 12.0]:
		box(Vector3(-4.0, y - 1.2, -9.0), Vector3(4.0, y + 1.2, -0.6), CONCRETE)
		solid([Vector3(-4.0, y - 1.2, -9.0), Vector3(-4.0, y + 1.2, -9.0), Vector3(-5.6, y, -9.0),
				Vector3(-4.0, y - 1.2, -0.6), Vector3(-4.0, y + 1.2, -0.6), Vector3(-5.6, y, -0.6)], CONCRETE)
		box(Vector3(3.0, y - 1.1, 0.0), Vector3(5.2, y + 1.1, 3.0), CLAD)
		box(Vector3(2.9, y - 1.2, 3.0), Vector3(5.3, y + 1.2, 3.2), FRAME)
	var bays := [[-16.0, -13.2], [-10.8, -5.2], [-2.8, 2.8], [5.2, 10.8], [13.2, 16.0]]
	for b: Array in bays:
		box(Vector3(-0.3, float(b[0]), -9.0), Vector3(0.3, float(b[1]), -3.3), RUST)
		box(Vector3(-0.45, float(b[0]), -3.5), Vector3(0.45, float(b[1]), -3.1), METAL)
	# Cover on the upstream edge; a rail on the downstream edge between houses.
	box(Vector3(-3.0, -22.0, 0.0), Vector3(-2.7, 22.0, 1.1), FRAME)
	rail("y", 2.875, -22.0, 22.0, 0.0, 0.0)
	# The control tower, beside the deck on the +Y abutment.
	box(Vector3(-4.5, 16.5, -7.0), Vector3(-9.0, 23.5, 0.0), {"top": DECK, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-8.7, 17.0, 0.0), Vector3(-4.8, 22.0, 6.5), CLAD)
	box(Vector3(-8.8, 16.9, 4.2), Vector3(-4.7, 22.1, 5.6), GLASS)
	box(Vector3(-9.0, 16.7, 6.5), Vector3(-4.5, 22.3, 6.8), FRAME)
	window("+x", -4.8, 19.5, 0.0, 1.2, 2.3, false, METAL)


# ── Machines: tools ──────────────────────────────────────────────────────────
# Shop-floor machines in machine green, fronts toward -X. Small enough to
# place by hand inside a shed or hangar, and solid enough to take cover at.

## An engine lathe 4.4 m long along Y: two cabinet legs, the chip pan, the
## bed, the headstock and chuck, carriage and apron, tool post, tailstock and
## quill, and the lead screw along the front.
func _lathe() -> void:
	for y: float in [-1.6, 1.4]:
		box(Vector3(-0.4, y - 0.4, -0.05), Vector3(0.4, y + 0.4, 0.9), MACHINE)
	box(Vector3(-0.55, -2.2, 0.9), Vector3(0.55, 2.2, 1.0), METAL)
	box(Vector3(-0.3, -2.0, 1.0), Vector3(0.3, 2.0, 1.3), METAL)
	box(Vector3(-0.45, -2.2, 1.0), Vector3(0.45, -1.3, 1.85), MACHINE)
	log_x(Vector3(0, -1.175, 1.36), 0.24, 0.25, 8, METAL, "y")
	box(Vector3(-0.35, 1.3, 1.3), Vector3(0.35, 1.8, 1.75), MACHINE)
	log_x(Vector3(0, 1.1, 1.52), 0.08, 0.4, 6, METAL, "y")
	box(Vector3(-0.4, -0.2, 1.3), Vector3(0.45, 0.4, 1.5), METAL)
	box(Vector3(-0.15, 0.0, 1.5), Vector3(0.15, 0.25, 1.75), RUST)
	box(Vector3(-0.55, -0.25, 1.05), Vector3(-0.4, 0.45, 1.45), MACHINE)
	box(Vector3(-0.53, -2.0, 1.12), Vector3(-0.47, 2.0, 1.18), METAL)


## A knee-type milling machine 2.6 m tall: base, column, knee, saddle and
## table, the ram over them carrying the head, the spindle, the motor on top,
## and the table's handwheels.
func _milling() -> void:
	box(Vector3(-0.6, -0.5, -0.05), Vector3(0.6, 0.5, 0.2), MACHINE)
	box(Vector3(0.0, -0.35, 0.2), Vector3(0.6, 0.35, 1.9), MACHINE)
	box(Vector3(-0.55, -0.35, 0.8), Vector3(0.0, 0.35, 1.2), MACHINE)
	box(Vector3(-0.5, -0.3, 1.2), Vector3(-0.05, 0.3, 1.3), METAL)
	box(Vector3(-0.45, -0.85, 1.3), Vector3(-0.1, 0.85, 1.42), METAL)
	box(Vector3(-0.8, -0.2, 1.9), Vector3(0.6, 0.2, 2.25), MACHINE)
	box(Vector3(-0.8, -0.18, 1.6), Vector3(-0.45, 0.18, 1.95), MACHINE)
	cylinder(Vector3(-0.625, 0, 1.47), 0.06, 0.13, 6, METAL)
	cylinder(Vector3(-0.625, 0, 2.25), 0.16, 0.35, 8, GREEN)
	for y: float in [-0.9, 0.9]:
		log_x(Vector3(-0.28, y, 1.28), 0.08, 0.06, 8, METAL, "y")


## A straight-side press 6.5 m tall: the bed and bolster, two uprights, the
## dies, the slide on its connecting rods, the crown with its drive motor, the
## flywheel on its side, and a control stand.
func _press() -> void:
	box(Vector3(-1.4, -1.8, -0.1), Vector3(1.4, 1.8, 1.2), MACHINE)
	box(Vector3(-1.1, -1.4, 1.2), Vector3(1.1, 1.4, 1.35), METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-1.1, minf(s * 1.4, s * 2.0), 1.2), Vector3(1.1, maxf(s * 1.4, s * 2.0), 5.2), MACHINE)
		post(0.0, s * 0.8, 4.0, 5.2, 0.22, METAL)
	box(Vector3(-0.9, -1.2, 1.35), Vector3(0.9, 1.2, 1.7), RUST)
	box(Vector3(-0.9, -1.2, 2.8), Vector3(0.9, 1.2, 3.2), RUST)
	box(Vector3(-1.0, -1.35, 3.2), Vector3(1.0, 1.35, 4.0), METAL)
	box(Vector3(-1.3, -2.1, 5.2), Vector3(1.3, 2.1, 6.2), MACHINE)
	log_x(Vector3(0.6, 0.0, 6.2), 0.35, 1.2, 8, GREEN, "y")
	log_x(Vector3(0.3, 2.25, 5.3), 0.8, 0.3, 12, METAL, "y")
	post(-2.2, 1.0, -0.1, 1.2, 0.1, METAL)
	box(Vector3(-2.35, 0.8, 1.2), Vector3(-2.05, 1.2, 1.55), SHUTTER)


## A machining centre 3.4 × 2.2 m: its enclosure with a window in the door,
## the control pendant on its arm, the chip conveyor out of the +Y end into
## a bin, and the stack light.
func _cnc() -> void:
	box(Vector3(-1.1, -1.7, -0.05), Vector3(1.1, 1.7, 2.5), {"top": METAL, "side": PALE, "bottom": METAL})
	box(Vector3(-1.16, -0.9, 0.9), Vector3(-1.1, 0.6, 2.1), GLASS)
	box(Vector3(-1.18, -1.0, 0.25), Vector3(-1.1, -0.9, 2.2), METAL)
	beam(Vector3(-1.1, 1.5, 2.2), Vector3(-1.6, 1.9, 2.05), 0.08, METAL)
	box(Vector3(-1.8, 1.75, 1.3), Vector3(-1.55, 2.25, 2.1), SHUTTER)
	box(Vector3(-1.84, 1.85, 1.7), Vector3(-1.8, 2.15, 2.0), GLASS)
	solid([Vector3(-0.3, 1.7, 0.2), Vector3(0.3, 1.7, 0.2), Vector3(-0.3, 3.1, 1.2), Vector3(0.3, 3.1, 1.2),
			Vector3(-0.3, 1.7, 0.45), Vector3(0.3, 1.7, 0.45), Vector3(-0.3, 3.1, 1.45), Vector3(0.3, 3.1, 1.45)], METAL)
	box(Vector3(-0.5, 3.0, -0.05), Vector3(0.5, 3.8, 0.9), BLUE)
	cylinder(Vector3(0.8, -1.4, 2.5), 0.06, 0.35, 6, METAL)
	cylinder(Vector3(0.8, -1.4, 2.85), 0.09, 0.18, 6, GLOW)


# ── Machines: the robot line ─────────────────────────────────────────────────

## A six-axis industrial robot at `c`, facing its local -X: pedestal, turret,
## shoulder, two arm links, the wrist and gripper, the cable down the arm and
## a status light. `reach` bends it: 0 raised, 1 reaching down in front.
func robot_arm_at(c: Vector3, yaw: float, reach: float) -> void:
	pbox(c, yaw, Vector3(-0.45, -0.45, -0.05), Vector3(0.45, 0.45, 0.5), METAL)
	pcylinder(c, yaw, Vector3(0, 0, 0.5), 0.42, 0.45, 10, RUST_PANEL)
	pbox(c, yaw, Vector3(-0.3, -0.35, 0.95), Vector3(0.3, 0.35, 1.45), RUST_PANEL)
	var shoulder := Vector3(0, 0, 1.25)
	var elbow := Vector3(lerpf(0.1, 0.35, reach), 0, lerpf(2.6, 2.4, reach))
	var wrist := Vector3(lerpf(-0.9, -1.4, reach), 0, lerpf(2.8, 1.5, reach))
	pbeam(c, yaw, shoulder, elbow, 0.34, RUST_PANEL)
	pbeam(c, yaw, elbow, wrist, 0.26, RUST_PANEL)
	pbox(c, yaw, elbow + Vector3(-0.2, -0.22, -0.2), elbow + Vector3(0.2, 0.22, 0.2), METAL)
	var tool := wrist + Vector3(-0.05, 0, -0.35)
	pbeam(c, yaw, wrist, tool, 0.16, METAL)
	for s: float in [-0.09, 0.09]:
		pbeam(c, yaw, tool + Vector3(0, s, 0), tool + Vector3(-0.02, s * 1.3, -0.2), 0.07, METAL)
	ppipe(c, yaw, shoulder + Vector3(0.2, 0.22, 0), elbow + Vector3(0.15, 0.22, 0), 0.07, RUBBER, 6)
	pbox(c, yaw, Vector3(0.44, -0.1, 0.22), Vector3(0.5, 0.1, 0.36), GLOW)


## One robot at its cell: the arm reaching over a parts table, and a guard
## rail round the back of the cell.
func _robot_arm() -> void:
	robot_arm_at(Vector3.ZERO, 0.0, 0.7)
	box(Vector3(-2.2, -0.7, -0.05), Vector3(-1.0, 0.7, 0.85), METAL)
	box(Vector3(-1.9, -0.3, 0.85), Vector3(-1.3, 0.3, 1.1), RUST)
	fence_run(Vector2(1.2, -1.8), Vector2(1.2, 1.8), -0.05, 1.3)
	fence_run(Vector2(1.2, 1.8), Vector2(-2.4, 1.8), -0.05, 1.3)


## A war robot being built on the line, on its jig: `stage` 0 is legs and a
## frame, 1 adds the torso, 2 the head and arms.
func chassis_at(c: Vector3, stage: int) -> void:
	box(c + Vector3(-0.5, -0.6, 0.0), c + Vector3(0.5, 0.6, 0.15), METAL)
	for s: float in [-0.25, 0.25]:
		beam(c + Vector3(0.0, s, 0.15), c + Vector3(0.05, s, 1.05), 0.14, METAL)
	box(c + Vector3(-0.3, -0.35, 1.0), c + Vector3(0.3, 0.35, 1.15), RUST)
	if stage >= 1:
		box(c + Vector3(-0.35, -0.4, 1.15), c + Vector3(0.35, 0.4, 2.0), {"top": METAL, "side": SHUTTER, "bottom": RUST})
	if stage >= 2:
		box(c + Vector3(-0.18, -0.18, 2.0), c + Vector3(0.18, 0.18, 2.35), METAL)
		box(c + Vector3(-0.24, -0.1, 2.12), c + Vector3(-0.17, 0.1, 2.2), GLOW)
		for s: float in [-1.0, 1.0]:
			beam(c + Vector3(0.0, s * 0.45, 1.85), c + Vector3(-0.15, s * 0.55, 1.2), 0.14, RUST)


## A robot assembly line 16 m long along Y: the conveyor, four robot arms
## working either side of it, three war robots at three stages of being
## built, the line's control desk and parts bins.
func _assembly_line() -> void:
	box(Vector3(-0.8, -8.0, -0.05), Vector3(0.8, 8.0, 0.85), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	box(Vector3(-0.6, -8.0, 0.85), Vector3(0.6, 8.0, 0.9), RUBBER)
	for s: float in [-1.0, 1.0]:
		box(Vector3(minf(s * 0.72, s * 0.8), -8.0, 0.85), Vector3(maxf(s * 0.72, s * 0.8), 8.0, 1.05), METAL)
	robot_arm_at(Vector3(-1.8, -5.5, 0.0), 180.0, 0.8)
	robot_arm_at(Vector3(1.8, -1.5, 0.0), 0.0, 0.6)
	robot_arm_at(Vector3(-1.8, 2.5, 0.0), 180.0, 0.9)
	robot_arm_at(Vector3(1.8, 6.0, 0.0), 0.0, 0.4)
	chassis_at(Vector3(0.0, -3.5, 0.9), 0)
	chassis_at(Vector3(0.0, 0.5, 0.9), 1)
	chassis_at(Vector3(0.0, 4.5, 0.9), 2)
	box(Vector3(-1.2, -10.0, -0.05), Vector3(1.2, -9.2, 0.95), CLAD)
	box(Vector3(-0.9, -9.6, 0.95), Vector3(0.9, -9.5, 1.6), GLASS)
	cylinder(Vector3(1.0, -9.6, 0.95), 0.05, 0.9, 6, METAL)
	cylinder(Vector3(1.0, -9.6, 1.85), 0.08, 0.2, 6, GLOW)
	for y: float in [-6.8, 3.8]:
		box(Vector3(2.8, y - 0.5, -0.05), Vector3(3.8, y + 0.5, 0.8), CRATE)


# ── Machines: plant and vehicles ─────────────────────────────────────────────

## A forklift at `c` facing its local -X, forks raised under a loaded pallet:
## chassis and counterweight, wheels on two axle prisms, the overhead guard on
## four posts, the seat, the mast and its carriage.
func forklift_at(c: Vector3, yaw: float) -> void:
	pbox(c, yaw, Vector3(-0.6, -0.6, 0.25), Vector3(1.4, 0.6, 1.0), RUST_PANEL)
	pbox(c, yaw, Vector3(1.2, -0.62, 0.25), Vector3(1.9, 0.62, 1.25), SHUTTER)
	ppipe(c, yaw, Vector3(-0.35, -0.65, 0.3), Vector3(-0.35, 0.65, 0.3), 0.3, RUBBER, 8)
	ppipe(c, yaw, Vector3(1.4, -0.6, 0.25), Vector3(1.4, 0.6, 0.25), 0.25, RUBBER, 8)
	for q: Vector2 in [Vector2(-0.3, -0.55), Vector2(-0.3, 0.55), Vector2(1.2, -0.55), Vector2(1.2, 0.55)]:
		pbeam(c, yaw, Vector3(q.x, q.y, 1.0), Vector3(q.x + (0.1 if q.x < 0.0 else 0.0), q.y, 2.15), 0.08, METAL)
	pbox(c, yaw, Vector3(-0.25, -0.6, 2.1), Vector3(1.25, 0.6, 2.2), METAL)
	pbox(c, yaw, Vector3(0.5, -0.3, 1.0), Vector3(1.0, 0.3, 1.45), RUBBER)
	for s: float in [-0.35, 0.35]:
		pbox(c, yaw, Vector3(-0.8, s - 0.06, 0.1), Vector3(-0.65, s + 0.06, 2.6), METAL)
	pbox(c, yaw, Vector3(-0.9, -0.5, 0.55), Vector3(-0.8, 0.5, 1.25), METAL)
	for s: float in [-0.3, 0.3]:
		pbox(c, yaw, Vector3(-2.0, s - 0.06, 0.55), Vector3(-0.8, s + 0.06, 0.62), METAL)
	pbox(c, yaw, Vector3(-2.05, -0.55, 0.62), Vector3(-0.85, 0.55, 0.76), WOOD)
	pbox(c, yaw, Vector3(-1.95, -0.45, 0.76), Vector3(-0.95, 0.45, 1.6), CRATE)


func _forklift() -> void:
	forklift_at(Vector3.ZERO, 0.0)


## A tracked excavator at `c` facing its local -X: tracks, turntable, the
## house and counterweight, the cab on the left, the boom and its ram, and the
## stick down to a bucket — or, with `tool` "grab", an orange-peel grab
## hanging from it, for a scrap yard.
func _excavator_at(c: Vector3, yaw: float, tool: String) -> void:
	var track := [Vector2(-2.1, 0.0), Vector2(2.1, 0.0), Vector2(2.55, 0.35), Vector2(2.55, 0.55),
			Vector2(2.1, 0.9), Vector2(-2.1, 0.9), Vector2(-2.55, 0.55), Vector2(-2.55, 0.35)]
	for s: float in [-1.0, 1.0]:
		var pts: Array = []
		for y: float in [s * 1.1, s * 1.75]:
			for q: Vector2 in track:
				pts.append(Vector3(q.x, y, q.y - 0.05))
		psolid(c, yaw, pts, RUBBER)
	pbox(c, yaw, Vector3(-1.2, -1.1, 0.3), Vector3(1.2, 1.1, 0.8), METAL)
	pcylinder(c, yaw, Vector3(0, 0, 0.8), 1.0, 0.25, 12, METAL)
	pbox(c, yaw, Vector3(-0.8, -1.3, 1.05), Vector3(2.4, 1.3, 2.3), RUST_PANEL)
	pbox(c, yaw, Vector3(2.4, -1.25, 1.05), Vector3(2.9, 1.25, 2.1), SHUTTER)
	pbox(c, yaw, Vector3(-1.4, 0.3, 1.05), Vector3(0.2, 1.3, 3.2), {"top": RUST_PANEL, "side": GLASS, "bottom": METAL})
	pcylinder(c, yaw, Vector3(1.8, -0.8, 2.3), 0.08, 0.6, 6, METAL)
	var foot := Vector3(-0.9, -0.3, 1.8)
	var knee := Vector3(-4.0, -0.3, 4.6)
	var tip := Vector3(-5.6, -0.3, 1.4) if tool != "grab" else Vector3(-5.0, -0.3, 2.6)
	pbeam(c, yaw, foot, knee, 0.5, RUST_PANEL)
	pbeam(c, yaw, knee, tip, 0.36, RUST_PANEL)
	pbeam(c, yaw, Vector3(-1.0, -0.3, 1.3), Vector3(-2.6, -0.3, 3.3), 0.16, METAL)
	if tool == "grab":
		pcylinder(c, yaw, tip - Vector3(0, 0, 0.5), 0.35, 0.5, 8, METAL)
		for q: Vector2 in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)]:
			pbeam(c, yaw, tip - Vector3(0, 0, 0.45), tip + Vector3(q.x, q.y, -1.4), 0.14, RUST)
	else:
		psolid(c, yaw, [tip + Vector3(-0.2, -0.55, 0.2), tip + Vector3(0.5, -0.55, 0.4), tip + Vector3(0.6, -0.55, -0.4), tip + Vector3(0.0, -0.55, -0.6),
				tip + Vector3(-0.2, 0.55, 0.2), tip + Vector3(0.5, 0.55, 0.4), tip + Vector3(0.6, 0.55, -0.4), tip + Vector3(0.0, 0.55, -0.6)], RUST)


func _excavator() -> void:
	_excavator_at(Vector3.ZERO, 0.0, "bucket")


## A crawler bulldozer facing -X: tracks, the engine and hood, the cab under
## its roll-over roof, push arms and the blade leaning back, and a ripper.
func _bulldozer() -> void:
	var track := [Vector2(-1.8, 0.0), Vector2(1.8, 0.0), Vector2(2.2, 0.4), Vector2(1.8, 1.0), Vector2(-1.8, 1.0), Vector2(-2.2, 0.4)]
	for s: float in [-1.0, 1.0]:
		var pts: Array = []
		for y: float in [s * 0.9, s * 1.5]:
			for q: Vector2 in track:
				pts.append(Vector3(q.x, y, q.y - 0.05))
		solid(pts, RUBBER)
	box(Vector3(-1.2, -0.9, 0.4), Vector3(1.6, 0.9, 1.6), RUST_PANEL)
	box(Vector3(-1.2, -0.7, 1.6), Vector3(0.2, 0.7, 2.0), RUST_PANEL)
	box(Vector3(0.2, -0.85, 1.6), Vector3(1.6, 0.85, 3.0), {"top": RUST_PANEL, "side": GLASS, "bottom": METAL})
	box(Vector3(0.1, -0.95, 3.0), Vector3(1.7, 0.95, 3.12), METAL)
	cylinder(Vector3(-0.8, -0.4, 2.0), 0.08, 0.7, 6, METAL)
	for s: float in [-1.0, 1.0]:
		beam(Vector3(0.0, s * 1.6, 0.6), Vector3(-2.2, s * 1.6, 0.7), 0.2, METAL)
	solid([Vector3(-2.55, -1.95, 0.0), Vector3(-2.3, -1.95, 0.0), Vector3(-2.3, -1.95, 1.4), Vector3(-2.05, -1.95, 1.4),
			Vector3(-2.55, 1.95, 0.0), Vector3(-2.3, 1.95, 0.0), Vector3(-2.3, 1.95, 1.4), Vector3(-2.05, 1.95, 1.4)], RUST)
	box(Vector3(1.6, -0.6, 0.7), Vector3(2.0, 0.6, 1.1), METAL)
	beam(Vector3(2.0, 0.0, 0.9), Vector3(2.4, 0.0, -0.1), 0.18, RUST)


## Warehouse pallet racking, three bays 9 m long and 4.6 m tall: blue
## uprights, orange beams at three levels, pallets of crates on most places.
func _pallet_rack() -> void:
	for y: float in [-4.5, -1.5, 1.5, 4.5]:
		for x: float in [-0.5, 0.5]:
			post(x, y, -0.05, 4.6, 0.1, BLUE)
	for z: float in [1.5, 3.0, 4.4]:
		for x: float in [-0.5, 0.5]:
			box(Vector3(x - 0.05, -4.5, z - 0.12), Vector3(x + 0.05, 4.5, z), RUST_PANEL)
	var filled := [[0.0, -3.0, 1.2, CRATE], [0.0, 0.0, 1.0, SHUTTER], [1.5, -3.0, 1.1, CRATE], [1.5, 3.0, 0.9, CRATE],
			[3.0, 0.0, 1.0, SHUTTER], [3.0, 3.0, 1.2, CRATE], [0.0, 3.0, 0.8, BLUE]]
	for p: Array in filled:
		var z0: float = p[0]
		var y: float = p[1]
		box(Vector3(-0.55, y - 1.2, z0), Vector3(0.55, y + 1.2, z0 + 0.14), WOOD)
		box(Vector3(-0.5, y - 1.1, z0 + 0.14), Vector3(0.5, y + 1.1, z0 + 0.14 + float(p[2])), p[3])


## Steel coils from the mill in two rows of three on timber cradles, lying
## along X, beside a stack of plate and a stack of beams.
func _steel_coils() -> void:
	for row: float in [-1.2, 1.2]:
		for k in 3:
			var x := -3.0 + k * 3.0
			box(Vector3(x - 0.6, row - 0.9, -0.1), Vector3(x + 0.6, row + 0.9, 0.25), WOOD_DARK)
			log_x(Vector3(x, row, 0.1), 0.95, 1.4, 12, METAL, "x")
	box(Vector3(5.2, -2.5, -0.05), Vector3(7.7, 2.5, 0.35), METAL)
	box(Vector3(5.3, -2.3, 0.35), Vector3(7.6, 2.2, 0.5), RUST)
	box(Vector3(5.4, -2.4, 0.5), Vector3(7.5, 2.4, 0.62), METAL)
	for y: float in [-1.5, 1.5]:
		box(Vector3(-8.0, y - 0.15, -0.05), Vector3(-5.0, y + 0.15, 0.1), WOOD_DARK)
	for layer in 2:
		for k in 3 - layer:
			var x := -7.4 + k * 0.9 + layer * 0.45
			box(Vector3(x - 0.15, -3.0, 0.1 + layer * 0.3), Vector3(x + 0.15, 3.0, 0.4 + layer * 0.3), RUST)


## A steel workbench with a vice and a toolbox, a shelf under it, a bench
## grinder on its pedestal, and a welding set with its gas cylinders.
func _workbench() -> void:
	box(Vector3(-0.4, -1.0, 0.85), Vector3(0.4, 1.0, 0.95), METAL)
	for q: Vector2 in [Vector2(-0.35, -0.95), Vector2(0.35, -0.95), Vector2(0.35, 0.95), Vector2(-0.35, 0.95)]:
		post(q.x, q.y, -0.05, 0.85, 0.08, METAL)
	box(Vector3(-0.35, -0.95, 0.2), Vector3(0.35, 0.95, 0.25), METAL)
	box(Vector3(-0.4, -0.9, 0.95), Vector3(-0.15, -0.6, 1.15), SHUTTER)
	box(Vector3(-0.1, 0.3, 0.95), Vector3(0.3, 0.9, 1.25), RUST_PANEL)
	post(0.0, 1.6, -0.05, 0.9, 0.12, METAL)
	log_x(Vector3(0.0, 1.6, 0.9), 0.12, 0.45, 8, GREEN, "y")
	box(Vector3(-0.3, -2.1, -0.05), Vector3(0.3, -1.5, 0.7), BLUE)
	box(Vector3(-0.22, -3.25, -0.05), Vector3(0.22, -2.35, 0.1), METAL)
	for p: Array in [[-2.55, GREEN], [-3.0, RUST_PANEL]]:
		cylinder(Vector3(0.0, float(p[0]), 0.1), 0.12, 1.25, 8, p[1], 0.1)
		cylinder(Vector3(0.0, float(p[0]), 1.35), 0.05, 0.1, 6, METAL)


## A cab-over tractor unit and its 13.6 m box trailer, 18 m long, at `c`
## facing its local -X: chassis, cab and roof fairing, tanks, stacks, the fifth
## wheel, axles drawn as prisms, the trailer's landing legs and guard.
func semi_at(c: Vector3, yaw: float, tex: String) -> void:
	pbox(c, yaw, Vector3(-3.4, -0.5, 0.6), Vector3(2.2, 0.5, 0.95), METAL)
	pbox(c, yaw, Vector3(-3.5, -1.25, 0.95), Vector3(-1.4, 1.25, 3.3), tex)
	pbox(c, yaw, Vector3(-3.56, -1.1, 2.1), Vector3(-3.5, 1.1, 3.0), GLASS)
	psolid(c, yaw, [Vector3(-3.3, -1.2, 3.3), Vector3(-1.4, -1.2, 3.3), Vector3(-1.4, 1.2, 3.3), Vector3(-3.3, 1.2, 3.3),
			Vector3(-2.2, -1.1, 4.0), Vector3(-1.4, -1.1, 4.0), Vector3(-1.4, 1.1, 4.0), Vector3(-2.2, 1.1, 4.0)], tex)
	for s: float in [-1.0, 1.0]:
		ppipe(c, yaw, Vector3(-1.2, s * 1.0, 0.95), Vector3(0.2, s * 1.0, 0.95), 0.3, METAL, 8)
		pcylinder(c, yaw, Vector3(-1.3, s * 1.2, 1.0), 0.08, 3.2, 6, METAL)
	pbox(c, yaw, Vector3(0.6, -0.6, 0.95), Vector3(1.8, 0.6, 1.1), METAL)
	for x: float in [-2.6, 0.7, 1.9, 11.2, 12.5]:
		ppipe(c, yaw, Vector3(x, -1.25, 0.5), Vector3(x, 1.25, 0.5), 0.5, RUBBER, 8)
	pbox(c, yaw, Vector3(0.2, -1.25, 1.2), Vector3(13.8, 1.25, 4.0), CLAD)
	for s: float in [-0.9, 0.9]:
		pbox(c, yaw, Vector3(2.4, s - 0.08, -0.05), Vector3(2.56, s + 0.08, 1.2), METAL)
	pbox(c, yaw, Vector3(13.6, -1.1, 0.45), Vector3(13.8, 1.1, 0.65), METAL)


func _semi_truck() -> void:
	semi_at(Vector3(-5.0, 0.0, 0.0), 0.0, BLUE)


# ── Fortifications ───────────────────────────────────────────────────────────
# What the robots dug into the industry to hold it. Fronts face -X, the way
# an attack comes; entrances and ramps are at the back.

## One earth-filled hesco basket, 1.06 m square and 1.4 m tall, at `c`.
func basket_at(c: Vector3) -> void:
	box(c + Vector3(-0.53, -0.53, 0.0), c + Vector3(0.53, 0.53, 1.4), HESCO)


## A command bunker, 12 × 16 m, the heart of a hardpoint: a concrete block
## half-buried behind earth banked against its front and sides, firing slits
## over the banks, a blast door at the back behind a blast wall, and a roof
## with a parapet, an observation cupola and a radio mast, reached by a ramp
## up the back.
func _command_bunker() -> void:
	box(Vector3(-6.0, -8.0, -0.5), Vector3(6.0, 8.0, 2.7), CONCRETE)
	for y: float in [-5.0, -1.7, 1.7, 5.0]:
		box(Vector3(-6.05, y - 0.8, 1.5), Vector3(-5.7, y + 0.8, 1.8), SHUTTER)
	for x: float in [-2.5, 2.5]:
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.8, minf(s * 8.05, s * 7.7), 1.5), Vector3(x + 0.8, maxf(s * 8.05, s * 7.7), 1.8), SHUTTER)
	# Banked earth: 20° up to 1.2 m, below the slits.
	ramp(-10.0, -8.0, -6.0, 8.0, -0.3, -0.3, 1.2, "+x", EARTH)
	ramp(-6.0, -12.0, 4.0, -8.0, -0.3, -0.3, 1.2, "+y", EARTH)
	ramp(-6.0, 8.0, 4.0, 12.0, -0.3, -0.3, 1.2, "-y", EARTH)
	box(Vector3(-6.25, -8.25, 2.7), Vector3(6.25, 8.25, 3.0), SLAB)
	parapet(-6.25, -8.25, 6.25, 8.25, 3.0, 1.0, 0.4, {"+x": [[-5.5, -2.5]]})
	# Up the back: 5.75 m of ramp at about 28°, arriving through the gap.
	ramp(6.25, -5.5, 12.0, -2.5, 0.0, 0.0, 3.0, "-x")
	rail("y", -5.375, 6.25, 12.0, 3.0, 0.0, true)
	rail("y", -2.625, 6.25, 12.0, 3.0, 0.0, true)
	window("+x", 6.0, 4.0, -0.2, 1.6, 2.3, false, METAL)
	box(Vector3(7.6, 1.8, -0.3), Vector3(8.2, 6.2, 2.2), CONCRETE)
	box(Vector3(-2.0, -1.5, 3.0), Vector3(1.0, 1.5, 4.8), CONCRETE)
	box(Vector3(-2.05, -1.0, 4.0), Vector3(-1.8, 1.0, 4.3), SHUTTER)
	box(Vector3(-2.2, -1.7, 4.8), Vector3(1.2, 1.7, 5.0), SLAB)
	post(3.5, 5.5, 3.0, 11.0, 0.14, METAL)
	box(Vector3(3.2, 5.2, 3.0), Vector3(3.8, 5.8, 3.5), METAL)


## A gun emplacement 9 m across: a sandbagged ring open at the back behind a
## blast wall, a twin autocannon on its pedestal behind a shield, facing -X,
## and ammunition stacked against the wall.
func _gun_emplacement() -> void:
	for k in 12:
		if k == 0 or k == 11:
			continue   # the way in, at +X
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		var seg: Array = []
		for a: float in [a0, a1]:
			for r: float in [3.6, 4.4]:
				seg.append(Vector3(cos(a) * r, sin(a) * r, -0.3))
				seg.append(Vector3(cos(a) * r, sin(a) * r, 1.3))
		solid(seg, {"top": DIRT, "side": SANDBAG, "bottom": SANDBAG})
	box(Vector3(5.2, -2.2, -0.3), Vector3(5.7, 2.2, 1.6), HESCO)
	cylinder(Vector3(0, 0, -0.1), 0.35, 1.0, 8, METAL)
	cylinder(Vector3(0, 0, 0.9), 0.6, 0.2, 10, METAL)
	box(Vector3(-0.5, -0.35, 1.1), Vector3(0.6, 0.35, 1.6), GREEN)
	for s: float in [-0.15, 0.15]:
		pipe(Vector3(-0.4, s, 1.45), Vector3(-3.6, s, 1.6), 0.07, METAL, 6)
	solid([Vector3(-0.85, -0.9, 1.0), Vector3(-0.7, -0.9, 1.0), Vector3(-0.85, 0.9, 1.0), Vector3(-0.7, 0.9, 1.0),
			Vector3(-0.7, -0.8, 2.0), Vector3(-0.55, -0.8, 2.0), Vector3(-0.7, 0.8, 2.0), Vector3(-0.55, 0.8, 2.0)], RUST_PANEL)
	box(Vector3(0.2, 0.4, 1.1), Vector3(0.6, 0.8, 1.5), GREEN)
	for p: Array in [[2.4, -2.2, 0.0], [2.4, -1.4, 0.0], [2.4, -1.8, 0.5]]:
		box(Vector3(float(p[0]) - 0.5, float(p[1]) - 0.3, float(p[2]) - 0.05), Vector3(float(p[0]) + 0.5, float(p[1]) + 0.3, float(p[2]) + 0.45), GREEN)


## A mortar pit: a ring of earth and sandbags 6.4 m across, open at the back,
## with rounds in their boxes. The middle is left empty: the mortar itself is
## not part of the block.
func _mortar_pit() -> void:
	for k in 10:
		if k == 0:
			continue
		var a0 := TAU * (k - 0.5) / 10.0
		var a1 := TAU * (k + 0.5) / 10.0
		var seg: Array = []
		for a: float in [a0, a1]:
			for r: float in [2.4, 3.2]:
				seg.append(Vector3(cos(a) * r, sin(a) * r, -0.3))
				seg.append(Vector3(cos(a) * r * 0.97, sin(a) * r * 0.97, 0.9))
		solid(seg, {"top": SANDBAG, "side": DIRT, "bottom": DIRT})
	for p: Array in [[1.2, -1.2], [1.2, -0.5], [1.4, 1.0]]:
		box(Vector3(float(p[0]) - 0.3, float(p[1]) - 0.25, -0.05), Vector3(float(p[0]) + 0.3, float(p[1]) + 0.25, 0.35), GREEN)


## Twelve metres of hesco wall along Y, two baskets high (2.8 m) with the top
## tier offset half a basket, and a return of three baskets at +Y.
func _hesco_wall() -> void:
	for k in 11:
		basket_at(Vector3(0.0, -5.5 + k * 1.1, -0.1))
	for k in 10:
		basket_at(Vector3(0.0, -4.95 + k * 1.1, 1.3))
	for k in 3:
		basket_at(Vector3(1.1 + k * 1.1, 5.5, -0.1))


## Five T-walls in a row along Y, 3.7 m tall, the last one slumped askew.
func _t_walls() -> void:
	for k in 5:
		var y := -3.0 + k * 1.5
		var yaw := 7.0 if k == 4 else 0.0
		var c := Vector3(0.1 if k == 4 else 0.0, y, 0.0)
		pbox(c, yaw, Vector3(-0.5, -0.73, -0.1), Vector3(0.5, 0.73, 0.55), CONCRETE)
		var lean := 0.25 if k == 4 else 0.0
		psolid(c, yaw, [Vector3(-0.2, -0.73, 0.55), Vector3(0.2, -0.73, 0.55), Vector3(-0.2, 0.73, 0.55), Vector3(0.2, 0.73, 0.55),
				Vector3(-0.13 + lean, -0.73, 3.6), Vector3(0.13 + lean, -0.73, 3.6), Vector3(-0.13 + lean, 0.73, 3.6), Vector3(0.13 + lean, 0.73, 3.6)], CONCRETE)


## A hesco sangar: a ring of baskets two high round a room with a door at the
## back (+X), a timber deck on top behind a sandbag parapet 1.1 m high, a
## tin roof on four posts, and a ramp up its -Y side.
func _hesco_sangar() -> void:
	for x: float in [-1.65, -0.55, 0.55, 1.65]:
		for y: float in [-1.65, -0.55, 0.55, 1.65]:
			var edge := absf(x) > 1.0 or absf(y) > 1.0
			if not edge:
				continue
			# The door: no basket below, a lintel at 2 m, and a short one above it.
			if x > 1.0 and absf(y - 0.55) < 0.1:
				box(Vector3(x - 0.53, y - 0.53, 2.2), Vector3(x + 0.53, y + 0.53, 2.7), HESCO)
				continue
			basket_at(Vector3(x, y, -0.1))
			basket_at(Vector3(x, y, 1.3))
	box(Vector3(1.1, 0.0, 2.0), Vector3(2.2, 1.1, 2.2), WOOD_DARK)
	box(Vector3(-2.25, -2.25, 2.7), Vector3(2.25, 2.25, 2.9), {"top": PLANK, "side": WOOD_DARK, "bottom": WOOD_DARK})
	var bag := {"top": SANDBAG, "side": SANDBAG, "bottom": SANDBAG}
	wall_run("x", Vector2(-2.25, -1.85), -2.25, 2.25, 2.9, 4.0, [], bag)
	wall_run("x", Vector2(1.85, 2.25), -2.25, 2.25, 2.9, 4.0, [], bag)
	wall_run("y", Vector2(-2.25, -1.85), -1.85, 1.85, 2.9, 4.0, [[-1.3, 1.3]], bag)
	wall_run("y", Vector2(1.85, 2.25), -1.85, 1.85, 2.9, 4.0, [], bag)
	for q: Vector2 in [Vector2(-2.05, -2.05), Vector2(2.05, -2.05), Vector2(2.05, 2.05), Vector2(-2.05, 2.05)]:
		post(q.x, q.y, 4.0, 5.2, 0.12, WOOD_DARK)
	box(Vector3(-2.5, -2.5, 5.2), Vector3(2.5, 2.5, 5.3), RUST_PANEL)
	# Up the -Y side: 5.5 m at about 28°, onto the deck's edge. 2.6 m wide:
	# between two rails a 2 m ramp left the navmesh too narrow a strip, and the
	# deck came out as an island nobody could reach.
	ramp(-1.3, -7.75, 1.3, -2.25, 0.0, 0.0, 2.9, "+y")
	rail("x", -1.175, -7.75, -2.25, 0.0, 2.9)
	rail("x", 1.175, -7.75, -2.25, 0.0, 2.9)


## A jersey barrier 3 m long, placed: `c`, turned `yaw` (0 lies along Y).
func jersey_at(c: Vector3, yaw: float) -> void:
	for prof: Array in [[Vector2(-0.3, -0.05), Vector2(0.3, -0.05), Vector2(0.3, 0.08), Vector2(0.15, 0.28), Vector2(-0.15, 0.28), Vector2(-0.3, 0.08)],
			[Vector2(-0.15, 0.28), Vector2(0.15, 0.28), Vector2(0.08, 0.81), Vector2(-0.08, 0.81)]]:
		var pts: Array = []
		for y: float in [-1.5, 1.5]:
			for q: Vector2 in prof:
				pts.append(Vector3(q.x, y, q.y))
		psolid(c, yaw, pts, FRAME)


## A vehicle checkpoint on a road running along Y, 24 m long: a chicane of
## jersey barriers, a spike strip, a boom, a hesco guard post with a roof
## beside the way, T-walls lining the far end, a floodlight and a sign.
func _checkpoint() -> void:
	for p: Array in [[-2.5, -9.0], [2.5, -5.0], [-2.5, -1.0]]:
		jersey_at(Vector3(float(p[0]), float(p[1]), 0.0), 90.0)
	box(Vector3(-3.5, 2.4, -0.02), Vector3(3.5, 2.6, 0.06), METAL)
	box(Vector3(4.0, 4.2, -0.2), Vector3(4.6, 4.8, 1.2), RUST_PANEL)
	beam(Vector3(4.3, 4.5, 1.0), Vector3(-3.6, 4.5, 1.0), 0.12, RUST_PANEL)
	post(-3.8, 4.5, -0.2, 0.95, 0.12, METAL)
	for q: Vector2 in [Vector2(6.2, 3.4), Vector2(7.3, 3.4), Vector2(7.3, 4.5), Vector2(7.3, 5.6), Vector2(6.2, 5.6)]:
		basket_at(Vector3(q.x, q.y, -0.1))
	for q: Vector2 in [Vector2(5.5, 3.0), Vector2(5.5, 6.0)]:
		post(q.x, q.y, -0.1, 2.5, 0.12, WOOD_DARK)
	box(Vector3(5.2, 2.6, 2.5), Vector3(8.0, 6.4, 2.6), RUST_PANEL)
	for y: float in [8.0, 10.0]:
		for s: float in [-1.0, 1.0]:
			var c := Vector3(s * 4.6, y, 0.0)
			box(c + Vector3(-0.5, -0.73, -0.1), c + Vector3(0.5, 0.73, 0.55), CONCRETE)
			solid([c + Vector3(-0.2, -0.73, 0.55), c + Vector3(0.2, -0.73, 0.55), c + Vector3(-0.2, 0.73, 0.55), c + Vector3(0.2, 0.73, 0.55),
					c + Vector3(-0.13, -0.73, 3.6), c + Vector3(0.13, -0.73, 3.6), c + Vector3(-0.13, 0.73, 3.6), c + Vector3(0.13, 0.73, 3.6)], CONCRETE)
	lamp_at(Vector3(-5.5, 6.5, 0.0), 0.0)
	post(-4.8, -11.0, -0.2, 2.4, 0.1, METAL)
	box(Vector3(-4.85, -11.6, 1.6), Vector3(-4.75, -10.4, 2.4), RUST_PANEL)


## Dragon's teeth: two staggered rows of concrete pyramids, 13 in all, a
## line vehicles cannot cross and men can crouch behind.
func _dragon_teeth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 951
	for row in 2:
		var x := -0.8 if row == 0 else 0.8
		var count := 7 if row == 0 else 6
		for k in count:
			var y := -6.0 + k * 2.0 + (1.0 if row == 1 else 0.0)
			var b := rng.randf_range(0.55, 0.65)
			var t := rng.randf_range(0.18, 0.24)
			var h := rng.randf_range(0.95, 1.1)
			psolid(Vector3(x, y, 0.0), rng.randf_range(-12.0, 12.0), [Vector3(-b, -b, -0.2), Vector3(b, -b, -0.2), Vector3(b, b, -0.2), Vector3(-b, b, -0.2),
					Vector3(-t, -t, h), Vector3(t, -t, h), Vector3(t, t, h), Vector3(-t, t, h)], CONCRETE)


## Ten metres of concertina wire along Y on five pickets: eight loops drawn as
## diamonds of bar, with a strand along the top and one along the ground.
## Chunky for wire (8 cm), since a thinner bar snaps flat on the grid.
func _razor_wire() -> void:
	for y: float in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		post(0.0, y, -0.2, 1.1, 0.07, RUST)
	for k in 8:
		var y := -4.8 + k * 1.25
		# Each loop leans along the run, alternately each way, so they cross.
		var lo := y if k % 2 == 0 else y + 1.0
		var hi := y + 1.0 if k % 2 == 0 else y
		var p := [Vector3(0.0, lo, 0.05), Vector3(0.45, y + 0.5, 0.5), Vector3(0.0, hi, 0.95), Vector3(-0.45, y + 0.5, 0.5)]
		for i in 4:
			beam(p[i], p[(i + 1) % 4], 0.08, METAL)
	beam(Vector3(0.0, -5.0, 0.95), Vector3(0.0, 5.0, 0.95), 0.08, METAL)
	beam(Vector3(0.0, -5.0, 0.05), Vector3(0.0, 5.0, 0.05), 0.08, METAL)


## The mount for a machine sentry: a concrete base, the pylon with its
## mounting plate 2.4 m up, and the power cable run to a box beside it. The
## gun itself is not part of the block.
func _sentry_turret() -> void:
	box(Vector3(-0.8, -0.8, -0.2), Vector3(0.8, 0.8, 0.5), CONCRETE)
	cylinder(Vector3(0, 0, 0.5), 0.3, 1.7, 6, METAL)
	box(Vector3(-0.35, -0.55, 2.2), Vector3(0.35, 0.55, 2.4), METAL)
	pipe(Vector3(0.8, 0.0, 0.1), Vector3(2.5, 0.5, 0.05), 0.07, RUBBER, 6)
	box(Vector3(2.4, 0.2, -0.1), Vector3(3.0, 0.8, 0.8), CLAD)
	box(Vector3(2.35, 0.3, 0.5), Vector3(2.4, 0.7, 0.6), GLOW)


## An ammunition dump: crates stacked in a bay walled with sandbags on three
## sides, under a camouflage net on four poles, fuel drums outside.
func _ammo_dump() -> void:
	var bag := {"top": SANDBAG, "side": SANDBAG, "bottom": SANDBAG}
	box(Vector3(3.0, -3.6, -0.2), Vector3(3.6, 3.6, 1.3), bag)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-2.5, minf(s * 3.0, s * 3.6), -0.2), Vector3(3.0, maxf(s * 3.0, s * 3.6), 1.3), bag)
	var rng := RandomNumberGenerator.new()
	rng.seed = 961
	for k in 6:
		var x := -1.4 + (k % 3) * 1.3
		var y := -1.2 if k < 3 else 1.0
		box(Vector3(x - 0.5, y - 0.3, -0.05), Vector3(x + 0.5, y + 0.3, 0.45), GREEN)
		if k != 2 and k != 3:
			tipped_box(Vector3(x, y, 0.45), Vector3(0.9, 0.55, 0.4), Vector3(0, 0, rng.randf_range(-12, 12)), GREEN)
	box(Vector3(1.8, -2.4, -0.05), Vector3(2.7, 2.4, 0.5), CRATE)
	for q: Vector2 in [Vector2(-3.0, -3.8), Vector2(3.8, -3.8), Vector2(3.8, 3.8), Vector2(-3.0, 3.8)]:
		post(q.x, q.y, -0.2, 2.6, 0.1, WOOD_DARK)
	for s: float in [-1.0, 1.0]:
		solid([Vector3(-3.1, s * 4.0, 2.2), Vector3(0.4, s * 4.0, 2.8), Vector3(-3.1, 0.0, 2.2), Vector3(0.4, 0.0, 2.8),
				Vector3(-3.1, s * 4.0, 2.3), Vector3(0.4, s * 4.0, 2.9), Vector3(-3.1, 0.0, 2.3), Vector3(0.4, 0.0, 2.9)], SANDBAG)
		solid([Vector3(0.4, s * 4.0, 2.8), Vector3(3.9, s * 4.0, 2.2), Vector3(0.4, 0.0, 2.8), Vector3(3.9, 0.0, 2.2),
				Vector3(0.4, s * 4.0, 2.9), Vector3(3.9, s * 4.0, 2.3), Vector3(0.4, 0.0, 2.9), Vector3(3.9, 0.0, 2.3)], SANDBAG)
	for p: Array in [[-4.0, -2.0, RUST], [-4.1, -1.3, GREEN], [-4.6, -1.7, RUST]]:
		cylinder(Vector3(float(p[0]), float(p[1]), -0.02), 0.3, 0.9, 8, p[2])


## A floodlight mast on its trailer: the mast 8.5 m up to a bar of four lamps
## facing -X, the generator on the deck, outriggers down to pads, and the
## tow bar.
func _floodlight_mast() -> void:
	box(Vector3(-1.2, -0.7, 0.35), Vector3(1.2, 0.7, 0.9), RUST_PANEL)
	pipe(Vector3(0.3, -0.85, 0.3), Vector3(0.3, 0.85, 0.3), 0.3, RUBBER, 8)
	beam(Vector3(1.2, 0.0, 0.6), Vector3(2.6, 0.0, 0.4), 0.1, METAL)
	for q: Vector2 in [Vector2(-1.0, -0.6), Vector2(1.0, -0.6), Vector2(1.0, 0.6), Vector2(-1.0, 0.6)]:
		beam(Vector3(q.x, q.y, 0.6), Vector3(q.x * 1.7, q.y * 2.3, 0.05), 0.1, METAL)
		box(Vector3(q.x * 1.7 - 0.2, q.y * 2.3 - 0.2, -0.1), Vector3(q.x * 1.7 + 0.2, q.y * 2.3 + 0.2, 0.05), METAL)
	box(Vector3(0.1, -0.6, 0.9), Vector3(1.1, 0.6, 1.7), SHUTTER)
	cylinder(Vector3(-0.6, 0, 0.9), 0.14, 8.5, 8, METAL, 0.09)
	box(Vector3(-0.7, -1.3, 9.2), Vector3(-0.5, 1.3, 9.35), METAL)
	for y: float in [-1.0, -0.35, 0.35, 1.0]:
		box(Vector3(-0.85, y - 0.25, 9.35), Vector3(-0.45, y + 0.25, 9.8), METAL)
		box(Vector3(-0.9, y - 0.2, 9.4), Vector3(-0.85, y + 0.2, 9.75), PALE)


# ── Landmarks and the monolith ───────────────────────────────────────────────

## A district's clock tower, 51 m to the beacon on its spire: a brick shaft
## with stone quoins, bands and slit windows on a stepped plaza 18 m square
## (steps of 0.25 m, walkable from every side), a stone clock stage with a face
## on each side at 29 m, an open belfry with its bell, and a green copper spire.
## Tall and square where the wheel is round: from anywhere on a map, the two
## tell the player which side they are on.
func _clock_tower() -> void:
	box(Vector3(-9, -9, -0.5), Vector3(9, 9, 0.25), PAD)
	box(Vector3(-8, -8, 0.25), Vector3(8, 8, 0.5), PAD)
	box(Vector3(-7, -7, 0.5), Vector3(7, 7, 0.75), PAD)
	box(Vector3(-4, -4, 0.75), Vector3(4, 4, 26.0), BRICK)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(minf(sx * 4.2, sx * 3.0), minf(sy * 4.2, sy * 3.0), 0.75), Vector3(maxf(sx * 4.2, sx * 3.0), maxf(sy * 4.2, sy * 3.0), 26.0), FRAME)
	for z: float in [9.0, 18.0]:
		box(Vector3(-4.3, -4.3, z), Vector3(4.3, 4.3, z + 0.5), FRAME)
	window("-x", -4.0, 0.0, 0.75, 2.0, 3.2, false, METAL)
	box(Vector3(-4.35, -1.4, 3.95), Vector3(-4.0, 1.4, 4.45), FRAME)
	for z: float in [5.0, 13.0, 21.0]:
		for f: String in ["-x", "+x", "-y", "+y"]:
			if f == "-x" and z < 6.0:
				continue   # the door is there
			window(f, 4.0 if f.begins_with("+") else -4.0, 0.0, z, 0.8, 2.2, false, GLASS)
	# The clock stage and its four faces. The faces take the lightest texture
	# in the set on a dark ring, with broad hands: at the stage's own shade
	# they vanished from any distance, and a clock that can't be read from the
	# street is just a box.
	box(Vector3(-4.6, -4.6, 26.0), Vector3(4.6, 4.6, 32.0), {"top": DECK, "side": PALE, "bottom": FRAME})
	box(Vector3(-5.0, -5.0, 32.0), Vector3(5.0, 5.0, 32.5), FRAME)
	for s: float in [-1.0, 1.0]:
		log_x(Vector3(s * 4.65, 0.0, 29.0 - 2.7), 2.7, 0.1, 12, METAL, "x")
		log_x(Vector3(0.0, s * 4.65, 29.0 - 2.7), 2.7, 0.1, 12, METAL, "y")
		log_x(Vector3(s * 4.75, 0.0, 29.0 - 2.3), 2.3, 0.1, 12, CLOCK_FACE, "x")
		log_x(Vector3(0.0, s * 4.75, 29.0 - 2.3), 2.3, 0.1, 12, CLOCK_FACE, "y")
		for t: Vector2 in [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]:
			var m := Vector2(t.x * 1.85, 29.0 + t.y * 1.85)
			box(Vector3(minf(s * 4.8, s * 4.86), m.x - 0.12, m.y - 0.12), Vector3(maxf(s * 4.8, s * 4.86), m.x + 0.12, m.y + 0.12), METAL)
			box(Vector3(m.x - 0.12, minf(s * 4.8, s * 4.86), m.y - 0.12), Vector3(m.x + 0.12, maxf(s * 4.8, s * 4.86), m.y + 0.12), METAL)
		beam(Vector3(s * 4.92, 0.0, 29.0), Vector3(s * 4.92, 0.0, 30.8), 0.22, METAL)
		beam(Vector3(s * 4.92, 0.0, 29.0), Vector3(s * 4.92, 1.1, 28.4), 0.3, METAL)
		beam(Vector3(0.0, s * 4.92, 29.0), Vector3(0.0, s * 4.92, 30.8), 0.22, METAL)
		beam(Vector3(0.0, s * 4.92, 29.0), Vector3(-1.1, s * 4.92, 28.4), 0.3, METAL)
	# The belfry: four piers, lintels over the open arches, the bell on its yoke.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(minf(sx * 4.5, sx * 2.9), minf(sy * 4.5, sy * 2.9), 32.5), Vector3(maxf(sx * 4.5, sx * 2.9), maxf(sy * 4.5, sy * 2.9), 38.5), FRAME)
	for s: float in [-1.0, 1.0]:
		box(Vector3(minf(s * 4.5, s * 3.9), -2.9, 37.0), Vector3(maxf(s * 4.5, s * 3.9), 2.9, 38.5), FRAME)
		box(Vector3(-2.9, minf(s * 4.5, s * 3.9), 37.0), Vector3(2.9, maxf(s * 4.5, s * 3.9), 38.5), FRAME)
	box(Vector3(-4.8, -4.8, 38.5), Vector3(4.8, 4.8, 39.0), FRAME)
	cylinder(Vector3(0, 0, 33.8), 1.3, 2.0, 12, RUST, 0.6)
	cylinder(Vector3(0, 0, 35.8), 0.45, 0.4, 8, RUST)
	box(Vector3(-0.2, -3.9, 36.2), Vector3(0.2, 3.9, 36.6), METAL)
	# The spire, its corner pinnacles, and the beacon on its finial.
	solid([Vector3(-4.5, -4.5, 39.0), Vector3(4.5, -4.5, 39.0), Vector3(4.5, 4.5, 39.0), Vector3(-4.5, 4.5, 39.0), Vector3(0, 0, 49.0)], GREEN)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var c := Vector3(sx * 4.2, sy * 4.2, 39.0)
			solid([c + Vector3(-0.5, -0.5, 0), c + Vector3(0.5, -0.5, 0), c + Vector3(0.5, 0.5, 0), c + Vector3(-0.5, 0.5, 0), c + Vector3(0, 0, 2.5)], FRAME)
	post(0.0, 0.0, 48.5, 51.0, 0.16, METAL)
	box(Vector3(-0.25, -0.25, 51.0), Vector3(0.25, 0.25, 51.5), GLOW)


## A derelict funfair's big wheel, 48 m to the top of its rim, turning on a
## hub 26 m up between two A-frames: two rims of twenty segments on ten
## spokes each, a tie at every joint, eighteen cabins still hanging, two
## fallen. Under it, the boarding platform with rails and the ticket booth.
## Nothing else in the city is round, so it reads from anywhere; at 36 m only
## its top cleared the rooftops across the river. The wheel faces the
## prefab's ±Z and its feet stand 27 m apart along its X.
func _ferris_wheel() -> void:
	var r := 22.0
	var hub := 26.0
	var n := 20
	for s: float in [-1.8, 1.8]:
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			beam(Vector3(s, cos(a0) * r, hub + sin(a0) * r), Vector3(s, cos(a1) * r, hub + sin(a1) * r), 0.4, RUST_PANEL)
		for k in 10:
			var a := TAU * (k + 0.5) / 10.0
			beam(Vector3(s, 0.0, hub), Vector3(s, cos(a) * (r - 0.2), hub + sin(a) * (r - 0.2)), 0.2, METAL)
	log_x(Vector3(0.0, 0.0, hub - 1.4), 1.4, 5.0, 12, METAL, "x")
	var colours := [GREEN, BLUE, RUST_PANEL]
	for k in n:
		var a := TAU * k / n
		var p := Vector3(0.0, cos(a) * r, hub + sin(a) * r)
		beam(p + Vector3(-1.8, 0, 0), p + Vector3(1.8, 0, 0), 0.22, METAL)
		if k == 4 or k == 12:
			continue   # these two are on the ground
		box(p + Vector3(-1.2, -0.8, -2.4), p + Vector3(1.2, 0.8, -0.4), {"top": METAL, "side": colours[k % 3], "bottom": METAL})
	# The A-frames, their footings, and two braces up each.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			beam(Vector3(sx * 3.2, sy * 13.5, -0.3), Vector3(sx * 2.6, 0.0, hub), 0.8, RUST)
			box(Vector3(sx * 3.2 - 0.9, sy * 13.5 - 0.9, -0.5), Vector3(sx * 3.2 + 0.9, sy * 13.5 + 0.9, 0.4), CONCRETE)
		for z: float in [9.0, 17.0]:
			var t := (z + 0.3) / (hub + 0.3)
			beam(Vector3(sx * (3.2 - 0.6 * t), -13.5 * (1.0 - t), z), Vector3(sx * (3.2 - 0.6 * t), 13.5 * (1.0 - t), z), 0.45, RUST)
	# The boarding platform. The bottom cabin hangs over its middle, so each
	# half has its own ramp, and both come up the sides, square to the wheel:
	# a ramp along it had the next cabin up hanging over it, with too little
	# headroom to walk up.
	box(Vector3(-2.4, -4.5, -0.3), Vector3(2.4, 4.5, 1.5), PAD)
	ramp(-8.4, -4.1, -2.4, -1.7, 0.0, 0.0, 1.5, "+x")
	ramp(2.4, 1.7, 8.4, 4.1, 0.0, 0.0, 1.5, "-x")
	rail("x", -2.275, -1.7, 4.5, 1.5, 1.5)
	rail("x", 2.275, -4.5, 1.7, 1.5, 1.5)
	for s: float in [-1.0, 1.0]:
		rail("y", s * 4.375, -2.3, 2.3, 1.5, 1.5)
	# The ticket booth by the foot of the first ramp, its window toward it.
	box(Vector3(-11.6, -7.6, -0.2), Vector3(-9.6, -5.6, 2.6), PLASTER_A)
	box(Vector3(-11.8, -7.8, 2.6), Vector3(-9.4, -5.4, 2.8), RUST_PANEL)
	box(Vector3(-9.6, -7.1, 1.1), Vector3(-9.55, -6.1, 1.9), GLASS)
	tipped_box(Vector3(-6.5, 7.5, 0.8), Vector3(2.4, 1.6, 2.0), Vector3(25, 10, 60), {"top": METAL, "side": GREEN, "bottom": METAL})
	tipped_box(Vector3(6.8, -8.0, 0.7), Vector3(2.4, 1.6, 2.0), Vector3(-15, 70, 20), {"top": METAL, "side": BLUE, "bottom": METAL})


## A machine monolith: a tapering black slab 7 m tall on its footing, a line
## of light down each broad face and a crown of light. Set out in two rows
## they make an avenue.
func _monolith() -> void:
	box(Vector3(-1.4, -2.2, -0.3), Vector3(1.4, 2.2, 0.25), PAD)
	solid([Vector3(-0.5, -1.5, 0.25), Vector3(0.5, -1.5, 0.25), Vector3(0.5, 1.5, 0.25), Vector3(-0.5, 1.5, 0.25),
			Vector3(-0.4, -1.3, 7.0), Vector3(0.4, -1.3, 7.0), Vector3(0.4, 1.3, 7.0), Vector3(-0.4, 1.3, 7.0)], GLASS)
	for s: float in [-1.0, 1.0]:
		beam(Vector3(s * 0.52, 0.0, 0.6), Vector3(s * 0.43, 0.0, 6.6), 0.14, GLOW)
	box(Vector3(-0.4, -1.3, 7.0), Vector3(0.4, 1.3, 7.15), GLOW)
