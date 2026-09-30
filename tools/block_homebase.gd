extends "res://tools/block_fortress.gd"

# ─────────────────────────────────────────────
# BLOCK HOMEBASE — the depot: the home base, written as one TrenchBroom map.
#
#   maps/depot/depot_level.map
#
#   godot --headless --path . --script res://tools/block_homebase.gd -- maps
#   godot --headless --path . --script res://tools/block_homebase.gd -- maps --force
#
# WHAT IT HAS TO DO. Four things, and the room is shaped by them:
#
#   1. Muster the whole squad where you can see it. Thirty-odd machines
#      standing in formation, the biggest of them a rover. That wants a parade
#      deck, not a row of alcoves.
#   2. Show the chassis you can field. Four hangar bays, each big enough for
#      something THREE TIMES a rover — a rover is 1.7 x 3.4 x 2 m, so a bay has
#      to swallow 5 x 10 x 6 m and still let you walk round it.
#   3. Teach without standing in the way. The range is its own room off the
#      hall, through a lit portal you see on the way down the ramp. You can
#      walk past it every time after the first.
#   4. Send you out. The transit car at the far end.
#
# NOTHING ROBOT-SHAPED IS BUILT HERE. The first pass stood a charge post in
# each bay and it read as a robot — a different, wrong robot, next to the real
# ones. Build the bay, leave the volume empty and lit; the chassis that stands
# in it is spawned by the game, at the ChassisStand markers the level scene
# puts on each bay floor.
#
# You arrive on a gallery 4 m up at the east end and walk down the ramp — the
# one thing worth keeping from the base before this one. From the head of it:
# the bays down the right-hand wall, the muster deck in the middle, the range
# portal on the left, the car straight ahead.
# ─────────────────────────────────────────────

# ── The hall ──
const HALL_X := 42.0     # half the length: 84 m
const HALL_Y := 24.0     # half the width: 48 m
const HALL_Z := 15.0     # the ceiling
const WALL := 1.5

# ── Arrival ──
const GALLERY := 4.0
const GALLERY_FROM := 34.0   # the gallery is x 34..42
const RAMP_TO := 14.0        # 20 m of ramp at 1 in 5
const RAMP_HALF := 5.0       # 10 m wide, so the squad comes down with you

# ── Hangar bays, cut into the north wall ──
const BAY_HALF := 6.0        # 12 m wide
const BAY_BACK := 36.0       # the back face: 12 m from the hall wall
const BAY_HEAD := 9.0        # 9 m to the lintel
const BAYS: Array[float] = [-25.5, -8.5, 8.5, 25.5]

# ── The muster deck ──
const DECK_X0 := -22.0
const DECK_X1 := 2.0
const DECK_HALF := 12.0
const DECK_Z := 0.2          # a step the navmesh will climb (the limit is 0.25)

# ── The range annexe, through the south wall ──
const PORTAL_X0 := 8.0
const PORTAL_X1 := 20.0
const PORTAL_Z := 6.0
const ANNEX_X0 := 2.0
const ANNEX_X1 := 26.0
const ANNEX_FACE := -25.5    # where its floor starts: outside the hall's wall
const ANNEX_BACK := -52.0
const ANNEX_Z := 8.0

# ── The dock ──
const CAR_X := -35.5
const CAR_HALF := 3.2
const CAR_END := 11.0
const DOOR_HALF := 2.5

const DADO_Z := 4.0
## The walls are painted below DADO_Z and bare above it. concrete_wall_11 draws
## a vent strip along its bottom edge and an oxide dado above that; @0.909
## makes one tile 7.27 m, which lands the top of the paint at exactly DADO_Z,
## so the band ends where the paint ends. Run a wall texture like that full
## height and the dado repeats halfway up the wall, and a hall painted to seven
## metres reads as mould rather than as paint.
const DADO := "PSX_Textures/concrete_wall_11@0.909"
const WALL_TEX := CONCRETE
## The one lit surface in the project. The drop ceiling ships a *_emission map,
## but FuncGodot looks for PBR maps in a folder named after the texture, so it
## generated an albedo-only material and the fittings came out dark — the
## material is hand-written in textures/PSX_Textures/ instead, and it needs
## emission_operator on multiply or the whole panel lights, not just the tubes.
## CEILING tiles it at 8 m for the roof; LAMP at 2 m for panels and bay backs.
const CEILING := "PSX_Textures/hl_office_complex_style_drop_ceiling_1_1"
const LAMP := "PSX_Textures/hl_office_complex_style_drop_ceiling_1_1@0.25"
## Plain dark steel for the trim lines. They were glitch_tx_1 and at this size
## it reads as magenta confetti rather than as a lit strip.
const TRIM := "PSX_Textures/metal_wall_5"
const FLOOR_TEX := {"top": "PSX_Textures/concrete_tx_4", "side": CONCRETE, "bottom": CONCRETE}
## Plated steel for the muster deck and the bay stands, so a machine standing
## on one is standing on something built for it rather than on more floor.
const DECK_TEX := {"top": "PSX_Textures/metal_floor_1@0.5", "side": TRIM, "bottom": CONCRETE}
## Pale concrete for painted lines. Read against the steel deck and the floor;
## TRIM is too dark and too rusty to be a marking.
const MARK := "PSX_Textures/concrete_tx_4"


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_homebase.gd -- maps [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("depot")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var path := dir.path_join("depot_level.map")
	if FileAccess.file_exists(path) and not force:
		print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
		quit()
		return
	_brushes = []
	_ghost_from = -1
	_entities = []
	_depot()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(_map_text())
	f.close()
	print("      %-24s %3d brushes  %s" % ["depot_level", _brushes.size(), _extent_text()])
	print("BLOCK HOMEBASE DONE")
	quit()


## ORDER MATTERS. Everything before the first entity() call goes into
## worldspawn; every entity() after that starts a block of its own. The bays
## and the annexe are entities of their own because this project renders in
## gl_compatibility, which lights about eight lights per MESH — one mesh for
## the whole depot would mean eight lights for eighty-four metres of hall. A
## bay that is its own entity is its own mesh with a budget of its own.
func _depot() -> void:
	_shell()
	_gallery()
	_muster()
	_plinth()
	_markings()
	_dock()
	for cx: float in BAYS:
		_bay(cx)
	_annexe()
	_fittings()


## A wall in two bands: painted up to DADO_Z, bare concrete above it. One call
## rather than two boxes at every wall, because getting the band height wrong
## in one place out of fifteen is the kind of seam nobody spots until it is in
## a screenshot.
func banded(x0: float, y0: float, x1: float, y1: float, z1: float) -> void:
	box(Vector3(x0, y0, 0.0), Vector3(x1, y1, minf(DADO_Z, z1)), DADO)
	if z1 > DADO_Z:
		box(Vector3(x0, y0, DADO_Z), Vector3(x1, y1, z1), WALL_TEX)


## Floor, four walls with their openings in them, and the roof.
func _shell() -> void:
	var out := HALL_X + WALL
	var side := HALL_Y + WALL
	box(Vector3(-out, -side, -2.0), Vector3(out, side, 0.0), FLOOR_TEX)
	# The north wall, with a bay-sized hole in it four times over: full-height
	# segments between the bays, a lintel over each bay.
	var edges: Array[float] = [-out]
	for cx: float in BAYS:
		edges.append(cx - BAY_HALF)
		edges.append(cx + BAY_HALF)
	edges.append(out)
	for i in range(0, edges.size() - 1, 2):
		banded(edges[i], HALL_Y, edges[i + 1], side, HALL_Z)
	for cx: float in BAYS:
		box(Vector3(cx - BAY_HALF, HALL_Y, BAY_HEAD), Vector3(cx + BAY_HALF, side, HALL_Z), WALL_TEX)
	# The south wall, with the range portal in it.
	banded(-out, -side, PORTAL_X0, -HALL_Y, HALL_Z)
	banded(PORTAL_X1, -side, out, -HALL_Y, HALL_Z)
	box(Vector3(PORTAL_X0, -side, PORTAL_Z), Vector3(PORTAL_X1, -HALL_Y, HALL_Z), WALL_TEX)
	# The two ends.
	for s: float in [-1.0, 1.0]:
		banded(s * HALL_X, -HALL_Y, s * out, HALL_Y, HALL_Z)
	box(Vector3(-out, -side, HALL_Z), Vector3(out, side, HALL_Z + WALL),
			{"top": CONCRETE, "side": CONCRETE, "bottom": CEILING})
	# Pilasters up the south wall, clear of the portal.
	for k in 11:
		var x := -40.0 + k * 8.0
		if x > PORTAL_X0 - 2.0 and x < PORTAL_X1 + 2.0:
			continue
		box(Vector3(x - 1.0, -HALL_Y, 0.0), Vector3(x + 1.0, -HALL_Y + 1.0, HALL_Z), CONCRETE)


## The gallery you arrive on and the ramp down off it: 10 m wide at 1 in 5,
## kerbed either side so nobody walks off it in the dark.
func _gallery() -> void:
	box(Vector3(GALLERY_FROM, -HALL_Y, 0.0), Vector3(HALL_X, HALL_Y, GALLERY), PAD)
	ramp(RAMP_TO, -RAMP_HALF, GALLERY_FROM, RAMP_HALF, -0.5, 0.0, GALLERY, "+x", PAD)
	for s: float in [-1.0, 1.0]:
		var pts: Array = []
		for pair: Array in [[RAMP_TO, 0.0], [GALLERY_FROM, GALLERY]]:
			for y: float in [s * RAMP_HALF, s * (RAMP_HALF + 0.6)]:
				pts.append(Vector3(pair[0], y, pair[1] - 0.6))
				pts.append(Vector3(pair[0], y, pair[1] + 0.5))
		solid(pts, METAL)
		# The gallery's own edge, either side of the ramp head.
		box(Vector3(GALLERY_FROM - 0.5, s * (RAMP_HALF + 0.6), GALLERY),
				Vector3(GALLERY_FROM, s * HALL_Y, GALLERY + 1.1), METAL)
	# A lit band across the back wall: where you are standing when you arrive.
	box(Vector3(HALL_X - 0.5, -9.0, GALLERY + 2.0), Vector3(HALL_X, 9.0, GALLERY + 4.0), LAMP)


## The muster deck: 24 x 24 m of marked floor in the middle of the hall, a step
## up so it reads as a place rather than as more floor. The step is 0.2 m —
## under the navmesh's 0.25 m climb, so the squad walks on and off it.
func _muster() -> void:
	box(Vector3(DECK_X0, -DECK_HALF, 0.0), Vector3(DECK_X1, DECK_HALF, DECK_Z), DECK_TEX)
	# A painted border inset from the edge, closed at both ends.
	for s: float in [-1.0, 1.0]:
		box(Vector3(DECK_X0 + 1.0, s * (DECK_HALF - 1.4), DECK_Z),
				Vector3(DECK_X1 - 1.0, s * (DECK_HALF - 1.0), DECK_Z + 0.08), MARK)
		var x: float = DECK_X0 + 1.0 if s < 0.0 else DECK_X1 - 1.4
		box(Vector3(x, -(DECK_HALF - 1.4), DECK_Z),
				Vector3(x + 0.4, DECK_HALF - 1.4, DECK_Z + 0.08), MARK)
	# Rank lines every 4 m, so the formation has somewhere to stand.
	for k in 5:
		var x: float = DECK_X0 + 4.0 + k * 4.0
		box(Vector3(x - 0.12, -(DECK_HALF - 2.0), DECK_Z),
				Vector3(x + 0.12, DECK_HALF - 2.0, DECK_Z + 0.06), MARK)


## The plinth at the foot of the ramp. The mission terminal stands on it: the
## first thing you walk into coming down, and the only terminal in the hall —
## the dummy one lives in the range, where it belongs.
func _plinth() -> void:
	plinth(5.0, -5.0, 13.0, 5.0, -0.1, 0.9, 1.6, PAD, {})
	# A lit face on the ramp side, so the terminal is the brightest thing at the
	# bottom of the walk down.
	box(Vector3(12.6, -4.2, 0.2), Vector3(13.0, 4.2, 0.8), LAMP)
	for s: float in [-1.0, 1.0]:
		box(Vector3(5.0, s * 4.6, 0.9), Vector3(13.0, s * 5.0, 1.0), MARK)




## Painted aisles down the hall. Eighty-four metres of bare floor has no scale
## to it and no direction; two lines from the foot of the ramp to the dock, and
## a spur to the range portal, tell you where the room goes without putting
## anything in the way of it.
func _markings() -> void:
	for s: float in [-1.0, 1.0]:
		box(Vector3(-28.0, s * 16.0 - 0.18, 0.0), Vector3(13.0, s * 16.0 + 0.18, 0.06), MARK)
	box(Vector3(-28.4, -16.0, 0.0), Vector3(-28.0, 16.0, 0.06), MARK)
	# The spur to the portal, and a threshold across it.
	box(Vector3(12.0, -23.5, 0.0), Vector3(12.36, -16.0, 0.06), MARK)
	box(Vector3(PORTAL_X0 + 0.5, -HALL_Y - 0.4, 0.0), Vector3(PORTAL_X1 - 0.5, -HALL_Y, 0.07), MARK)
	# Hazard line across the mouth of each bay, on the hall side.
	for cx: float in BAYS:
		box(Vector3(cx - BAY_HALF, HALL_Y - 1.2, 0.0), Vector3(cx + BAY_HALF, HALL_Y - 0.8, 0.06), MARK)

## The transit car at the west end, on its rail bed under a gantry. Built from
## brushes like everything else: two body lengths with a 5 m opening between
## them, wide enough that the whole squad walks in behind you.
func _dock() -> void:
	box(Vector3(-40.0, -18.0, 0.0), Vector3(-31.0, 18.0, 0.6),
			{"top": BALLAST, "side": CONCRETE, "bottom": CONCRETE})
	for o: float in [-2.2, 2.2]:
		box(Vector3(CAR_X + o - 0.12, -18.0, 0.6), Vector3(CAR_X + o + 0.12, 18.0, 0.78), METAL)
	# The way up onto the bed. A 0.6 m kerb is a wall to a navmesh that will
	# only climb 0.25 m: without this apron the squad cannot board the car at
	# all, which the level scene's reachability probe caught.
	ramp(-31.0, -6.0, -27.0, 6.0, -0.5, 0.0, 0.6, "-x", PAD)
	# The body. An opening rather than a recess with a panel in it: the squad
	# has to walk through it, and a door you cannot see through is a door
	# nobody believes in.
	for seg: Array in [[-CAR_END, -DOOR_HALF], [DOOR_HALF, CAR_END]]:
		var pts: Array = []
		for y: float in [seg[0], seg[1]]:
			for lvl: Array in [[0.9, 2.6], [1.7, CAR_HALF], [6.2, CAR_HALF], [7.0, 2.3]]:
				pts.append(Vector3(CAR_X - float(lvl[1]), y, float(lvl[0])))
				pts.append(Vector3(CAR_X + float(lvl[1]), y, float(lvl[0])))
		solid(pts, CLAD)
	# The vestibule behind the opening: floor, back, roof and a lit strip.
	box(Vector3(CAR_X - 3.0, -DOOR_HALF, 0.6), Vector3(CAR_X + 2.4, DOOR_HALF, 0.8), GRATING)
	box(Vector3(CAR_X - 3.0, -DOOR_HALF, 0.8), Vector3(CAR_X - 2.0, DOOR_HALF, 6.2), TECH_WALL)
	box(Vector3(CAR_X - 3.0, -DOOR_HALF, 6.2), Vector3(CAR_X + 3.0, DOOR_HALF, 7.0), CLAD)
	box(Vector3(CAR_X - 2.0, -DOOR_HALF, 4.4), Vector3(CAR_X - 1.8, DOOR_HALF, 5.6), LAMP)
	for s: float in [-1.0, 1.0]:
		box(Vector3(CAR_X + 2.6, s * DOOR_HALF, 0.8), Vector3(CAR_X + 3.4, s * (DOOR_HALF + 0.5), 5.4), METAL)
	box(Vector3(CAR_X + 2.6, -(DOOR_HALF + 0.5), 4.8), Vector3(CAR_X + 3.4, DOOR_HALF + 0.5, 5.4), METAL)
	# Ribs down the body, a lit line each side, and the bogies.
	for k in 11:
		var y := -10.0 + k * 2.0
		if absf(y) < DOOR_HALF + 0.6:
			continue
		for s: float in [-1.0, 1.0]:
			box(Vector3(CAR_X + s * (CAR_HALF - 0.3), y - 0.3, 1.7),
					Vector3(CAR_X + s * (CAR_HALF + 0.2), y + 0.3, 6.2), METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(CAR_X + s * (CAR_HALF - 0.2), -CAR_END, 5.6),
				Vector3(CAR_X + s * (CAR_HALF + 0.15), CAR_END, 6.0), LAMP)
	for y: float in [-7.5, 7.5]:
		box(Vector3(CAR_X - 2.6, y - 2.0, 0.6), Vector3(CAR_X + 2.6, y + 2.0, 1.1), METAL)
		for o: float in [-1.9, 1.9]:
			cylinder(Vector3(CAR_X + o, y - 1.3, 0.66), 0.6, 0.38, 10, METAL)
			cylinder(Vector3(CAR_X + o, y + 1.3, 0.66), 0.6, 0.38, 10, METAL)
	# The tunnel it leaves by, plugged for now, and the gantry over the dock.
	box(Vector3(-HALL_X, -13.0, 0.0), Vector3(-HALL_X + 1.6, 13.0, 10.0), TECH_WALL)
	box(Vector3(-HALL_X + 1.6, -13.0, 9.4), Vector3(-HALL_X + 1.9, 13.0, 10.0), LAMP)
	for y: float in [-14.0, 14.0]:
		for o: float in [-5.2, 5.2]:
			box(Vector3(CAR_X + o - 0.5, y - 0.5, 0.0), Vector3(CAR_X + o + 0.5, y + 0.5, 11.0), CLAD)
		box(Vector3(CAR_X - 5.7, y - 0.5, 11.0), Vector3(CAR_X + 5.7, y + 0.5, 12.0), CLAD)


## ONE HANGAR BAY, as its own entity. 12 m wide, 12 m deep from the hall wall,
## 9 m to the lintel — a rover is 1.7 x 3.4 x 2 m, so this swallows one three
## times that size and still leaves 3 m each side to walk round it and look.
##
## The volume is EMPTY on purpose. The chassis that stands here is spawned by
## the game at the ChassisStand marker the level scene puts on the floor plate.
## Nothing robot-shaped is built in brushes, here or anywhere.
func _bay(cx: float) -> void:
	entity("func_detail")
	var face := HALL_Y + WALL          # where the bay's own shell starts
	var w := BAY_HALF
	# Shell. Every piece stops at the wall band rather than running through it:
	# two solids sharing a face is how you get a z-fighting seam.
	box(Vector3(cx - w - WALL, face, -2.0), Vector3(cx + w + WALL, BAY_BACK + WALL, 0.0), FLOOR_TEX)
	box(Vector3(cx - w - WALL, BAY_BACK, 0.0), Vector3(cx + w + WALL, BAY_BACK + WALL, BAY_HEAD + WALL), CONCRETE)
	for s: float in [-1.0, 1.0]:
		box(Vector3(cx + s * w, face, 0.0), Vector3(cx + s * (w + WALL), BAY_BACK, BAY_HEAD + WALL), CONCRETE)
	box(Vector3(cx - w, face, BAY_HEAD), Vector3(cx + w, BAY_BACK, BAY_HEAD + WALL), CONCRETE)
	# The stand: a plate on the floor low enough to drive onto, with a painted
	# edge, so the bay reads as a display even while it is empty.
	box(Vector3(cx - 4.0, 27.0, 0.0), Vector3(cx + 4.0, 35.0, 0.12), DECK_TEX)
	for s: float in [-1.0, 1.0]:
		box(Vector3(cx + s * 4.0 - 0.25, 27.0, 0.12), Vector3(cx + s * 4.0 + 0.05, 35.0, 0.18), TRIM)
	# Lit back wall, ribs up the sides, and service gantries across the top.
	box(Vector3(cx - 5.0, BAY_BACK - 0.25, 2.4), Vector3(cx + 5.0, BAY_BACK, 6.0), LAMP)
	for s: float in [-1.0, 1.0]:
		for d: float in [28.0, 33.0]:
			box(Vector3(cx + s * w - 0.5, d - 0.4, 0.0), Vector3(cx + s * w, d + 0.4, BAY_HEAD), METAL)
	for d: float in [29.5, 33.0]:
		box(Vector3(cx - w, d, BAY_HEAD - 0.9), Vector3(cx + w, d + 0.8, BAY_HEAD), METAL)
	# The frame round the opening, on the hall side of the jambs.
	for s: float in [-1.0, 1.0]:
		box(Vector3(cx + s * w - 0.4, HALL_Y - 0.3, 0.0), Vector3(cx + s * w + 0.4, HALL_Y, BAY_HEAD), TRIM)
	box(Vector3(cx - w, HALL_Y - 0.3, BAY_HEAD - 0.6), Vector3(cx + w, HALL_Y, BAY_HEAD), TRIM)


## THE RANGE, in a room of its own through the south wall. It is off the hall
## so it never stands between you and the car, and the portal into it is 12 m
## wide and lit above, so you see it from the ramp on the first walk down and
## can ignore it on every walk after.
func _annexe() -> void:
	entity("func_detail")
	var x0 := ANNEX_X0 - WALL
	var x1 := ANNEX_X1 + WALL
	var back := ANNEX_BACK - WALL
	box(Vector3(x0, back, -2.0), Vector3(x1, ANNEX_FACE, 0.0), FLOOR_TEX)
	box(Vector3(x0, back, 0.0), Vector3(ANNEX_X0, ANNEX_FACE, ANNEX_Z + WALL), DADO)
	box(Vector3(ANNEX_X1, back, 0.0), Vector3(x1, ANNEX_FACE, ANNEX_Z + WALL), DADO)
	box(Vector3(x0, back, 0.0), Vector3(x1, ANNEX_BACK, ANNEX_Z + WALL), DADO)
	box(Vector3(x0, back, ANNEX_Z), Vector3(x1, ANNEX_FACE, ANNEX_Z + WALL),
			{"top": CONCRETE, "side": CONCRETE, "bottom": CEILING})
	# The lane: scorched floor from the firing line down to the backstop.
	box(Vector3(ANNEX_X0 + 2.0, ANNEX_BACK + 2.6, 0.0), Vector3(ANNEX_X1 - 2.0, -31.0, 0.12),
			{"top": SCORCH, "side": CONCRETE, "bottom": CONCRETE})
	# The backstop the targets hang on, and the baffles standing off it.
	box(Vector3(ANNEX_X0 + 1.0, ANNEX_BACK + 1.0, 0.0), Vector3(ANNEX_X1 - 1.0, ANNEX_BACK + 2.0, 5.0), TECH_WALL)
	for k in 5:
		var x: float = ANNEX_X0 + 3.0 + k * 4.5
		box(Vector3(x - 0.3, ANNEX_BACK + 2.0, 0.0), Vector3(x + 0.3, ANNEX_BACK + 2.6, 4.0), METAL)
	# The firing line: something to shoot over, with a gap to walk through.
	var mid := (ANNEX_X0 + ANNEX_X1) * 0.5
	for s: float in [-1.0, 1.0]:
		box(Vector3(mid + s * 2.5, -31.0, 0.0), Vector3(mid + s * 9.0, -30.0, 1.1), CONCRETE)
		box(Vector3(mid + s * 2.5, -31.0, 1.1), Vector3(mid + s * 9.0, -30.0, 1.2), TRIM)
	# A lit band down each long wall, so the room reads as its own place.
	for x: float in [ANNEX_X0, ANNEX_X1 - 0.25]:
		box(Vector3(x, ANNEX_BACK + 2.0, 5.4), Vector3(x + 0.25, ANNEX_FACE - 1.0, 6.6), LAMP)
	# The sign band over the portal, on the HALL side: this is the thing you
	# see from the head of the ramp on the first walk down.
	box(Vector3(PORTAL_X0, -HALL_Y, PORTAL_Z), Vector3(PORTAL_X1, -HALL_Y + 0.3, PORTAL_Z + 1.6), LAMP)
	for x: float in [PORTAL_X0 - 0.5, PORTAL_X1]:
		box(Vector3(x, -HALL_Y, 0.0), Vector3(x + 0.5, -HALL_Y + 0.3, PORTAL_Z + 1.6), TRIM)


## Pipes, cable runs and light fittings. None of it is solid: this is a room
## the squad walks round, and a pipe at knee height is a pipe they path round.
func _fittings() -> void:
	no_collision()
	# Service runs down both long walls, above head height.
	for s: float in [-1.0, 1.0]:
		for o: float in [11.0, 12.0]:
			box(Vector3(-HALL_X + 2.0, s * (HALL_Y - 0.8), o), Vector3(HALL_X - 2.0, s * HALL_Y, o + 0.55), METAL)
	# Trusses across the ceiling with a lit panel hung under each one.
	for k in 9:
		var x := -32.0 + k * 8.0
		box(Vector3(x - 0.6, -HALL_Y + 1.0, HALL_Z - 0.8), Vector3(x + 0.6, HALL_Y - 1.0, HALL_Z), GRATING)
		box(Vector3(x - 3.0, -2.0, HALL_Z - 0.6), Vector3(x + 3.0, 2.0, HALL_Z - 0.2), LAMP)
	# Cable trays down the back wall behind the gallery.
	for k in 5:
		var y := -12.0 + k * 6.0
		box(Vector3(HALL_X - 0.7, y - 0.5, GALLERY), Vector3(HALL_X, y + 0.5, HALL_Z), METAL)
	# And a run along the annexe's ceiling.
	for k in 4:
		var y: float = ANNEX_BACK + 6.0 + k * 6.0
		box(Vector3(ANNEX_X0 + 1.0, y - 0.5, ANNEX_Z - 0.7), Vector3(ANNEX_X1 - 1.0, y + 0.5, ANNEX_Z), GRATING)
