extends "res://tools/block_fortress.gd"

# ─────────────────────────────────────────────
# BLOCK HOMEBASE — the depot: a new home base, written as one TrenchBroom map.
#
#   maps/depot/depot_level.map
#
#   godot --headless --path . --script res://tools/block_homebase.gd -- maps
#   godot --headless --path . --script res://tools/block_homebase.gd -- maps --force
#
# WHY A NEW ONE. The old home base is 107 x 118 m of open floor with the
# tutorial spread across it — the mission terminal at one end, the dummy
# terminal forty metres away at the other, and a label telling you the tutorial
# is on the back wall. A hub is not a level: everything in it should be legible
# from where you spawn, and reaching any of it should be a walk, not a hike.
#
# So this is ONE ROOM, 48 x 34 m, and you arrive on a gallery above it. From
# the head of the ramp the whole base is in front of you: the squad in their
# cradles on the left, the terminals on the plinth in the middle, the range on
# the right, and the transit car at the far end that takes you out. Nothing is
# more than 40 m from the spawn and nothing is behind you.
#
# The ramp is kept because it is the best thing about the old one — you come in
# high, see the place, then walk down into it.
# ─────────────────────────────────────────────

const HALL_X := 24.0     # half the hall's length: 48 m
const HALL_Y := 17.0     # half its width: 34 m
const HALL_Z := 11.0     # the ceiling
const GALLERY := 3.0     # the gallery you arrive on
const GALLERY_FROM := 14.0
const RAMP_TO := -1.0    # 15 m of ramp at 1 in 5
const WALL := 1.0
const DADO_Z := 4.0
## The walls are painted below DADO_Z and bare above it. concrete_wall_11 draws
## a vent strip along its bottom edge and an oxide dado above that; @0.909
## makes one tile 7.27 m, which lands the top of the paint at exactly DADO_Z,
## so the band ends where the paint ends. The first pass ran the green version
## of the same texture full height, and a hall painted green to seven metres
## reads as mould rather than as paint.
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


func _depot() -> void:
	_shell()
	_gallery()
	_cradles()
	_plinth()
	_range()
	_transit()
	_fittings()


## A wall in two bands: painted up to DADO_Z, bare concrete above it. One call
## rather than two boxes at every wall, because getting the band height wrong
## in one place out of nine is the kind of seam nobody spots until it is in a
## screenshot.
func banded(x0: float, y0: float, x1: float, y1: float, z1: float) -> void:
	box(Vector3(x0, y0, 0.0), Vector3(x1, y1, minf(DADO_Z, z1)), DADO)
	if z1 > DADO_Z:
		box(Vector3(x0, y0, DADO_Z), Vector3(x1, y1, z1), WALL_TEX)


## The room: floor, the long wall on the range side, both ends, and the roof.
## The cradle wall is built in _cradles(), because it has holes in it.
func _shell() -> void:
	box(Vector3(-HALL_X - WALL, -HALL_Y - WALL, -2.0), Vector3(HALL_X + WALL, HALL_Y + WALL, 0.0), FLOOR_TEX)
	banded(-HALL_X - WALL, HALL_Y, HALL_X + WALL, HALL_Y + WALL, HALL_Z)
	for s: float in [-1.0, 1.0]:
		banded(s * HALL_X, -HALL_Y, s * (HALL_X + WALL), HALL_Y, HALL_Z)
	# The roof takes the drop-ceiling texture on its underside, which puts a lit
	# fitting every 8 m. It is only a lit-looking surface, not a light: this
	# renderer caps out around eight lights a mesh, so the room is lit by the
	# nine light nodes in the level and the ceiling just has to read.
	box(Vector3(-HALL_X - WALL, -HALL_Y - WALL, HALL_Z), Vector3(HALL_X + WALL, HALL_Y + WALL, HALL_Z + 1.0),
			{"top": CONCRETE, "side": CONCRETE, "bottom": CEILING})
	# Pilasters up the range wall, clear of the cradle bays opposite.
	for k in 7:
		var x := -21.0 + k * 7.0
		box(Vector3(x - 0.75, HALL_Y - 0.5, 0.0), Vector3(x + 0.75, HALL_Y, HALL_Z), CONCRETE)

## The gallery you arrive on, and the ramp down — 8 m wide at 1 in 5, with a
## kerb either side so nobody walks off it in the dark.
func _gallery() -> void:
	box(Vector3(GALLERY_FROM, -HALL_Y, 0.0), Vector3(HALL_X, HALL_Y, GALLERY), PAD)
	ramp(RAMP_TO, -4.0, GALLERY_FROM, 4.0, -0.5, 0.0, GALLERY, "+x", PAD)
	for s: float in [-1.0, 1.0]:
		var pts: Array = []
		for pair: Array in [[RAMP_TO, 0.0], [GALLERY_FROM, GALLERY]]:
			for y: float in [s * 4.0, s * 4.5]:
				pts.append(Vector3(pair[0], y, pair[1] - 0.5))
				pts.append(Vector3(pair[0], y, pair[1] + 0.4))
		solid(pts, METAL)
		# The gallery's own edge, either side of the ramp head.
		box(Vector3(GALLERY_FROM - 0.4, s * 4.5, GALLERY), Vector3(GALLERY_FROM, s * HALL_Y, GALLERY + 1.0), METAL)
	# Where you stand when you arrive: a lit strip across the back wall.
	box(Vector3(HALL_X - 0.5, -6.0, GALLERY + 1.6), Vector3(HALL_X, 6.0, GALLERY + 3.6), LAMP)


## The squad's cradles: four bays cut INTO the left-hand wall, not four frames
## standing in front of it. The wall is built here rather than in _shell() for
## exactly that reason — a bay has to be a hole in the wall, and a hole is the
## segments either side of it plus a lintel over it. The first pass had them as
## furniture against a flat wall and from the head of the ramp they read as
## nothing at all.
func _cradles() -> void:
	var xs: Array[float] = [-14.0, -6.0, 2.0, 10.0]
	var half := 2.8          # the bay is 5.6 m wide
	var head := 4.6          # and 4.6 m to its lintel
	var face := -HALL_Y      # the wall's inner face
	var outer := -HALL_Y - WALL
	var deep := -HALL_Y - 2.4    # the bay's back face
	var shell := deep - WALL
	# The wall itself: a segment between each pair of bays, and a lintel over
	# each bay. edges walks left to right as wall, opening, wall, opening...
	var edges: Array[float] = [-HALL_X - WALL]
	for x: float in xs:
		edges.append(x - half)
		edges.append(x + half)
	edges.append(HALL_X + WALL)
	for i in range(0, edges.size() - 1, 2):
		banded(edges[i], face, edges[i + 1], outer, HALL_Z)
	for x: float in xs:
		box(Vector3(x - half, face, head), Vector3(x + half, outer, HALL_Z), WALL_TEX)
	for x: float in xs:
		# The bay's own shell. Every piece stops at the wall band rather than
		# running through it: two solids sharing a face is how you get the
		# z-fighting seam we already had on the fortress wall.
		box(Vector3(x - half - WALL, shell, -2.0), Vector3(x + half + WALL, outer, 0.0), FLOOR_TEX)
		box(Vector3(x - half - WALL, shell, 0.0), Vector3(x + half + WALL, deep, head + WALL), CONCRETE)
		for s: float in [-1.0, 1.0]:
			box(Vector3(x + s * half, deep, 0.0), Vector3(x + s * (half + WALL), outer, head + WALL), CONCRETE)
		box(Vector3(x - half, deep, head), Vector3(x + half, outer, head + WALL), CONCRETE)
		# What stands in it: a deck low enough to walk onto (0.2 m against the
		# navmesh's 0.25 m climb), a charge post, a lit panel on the back wall
		# and a frame round the opening so the bay reads as a bay at distance.
		box(Vector3(x - half, deep + 0.2, 0.0), Vector3(x + half, face - 0.2, 0.2), METAL)
		cylinder(Vector3(x, deep + 0.9, 0.2), 0.35, 1.9, 8, METAL)
		box(Vector3(x - 2.0, deep + 0.05, 1.2), Vector3(x + 2.0, deep + 0.25, 3.4), LAMP)
		for s: float in [-1.0, 1.0]:
			box(Vector3(x + s * half - 0.3, face - 0.25, 0.2), Vector3(x + s * half, face, head), TRIM)
		box(Vector3(x - half, face - 0.25, head - 0.4), Vector3(x + half, face, head), TRIM)

## The plinth in the middle of the floor: the mission terminal stands on it and
## the dummy terminal beside it, so the two things you press are together.
func _plinth() -> void:
	plinth(-9.0, -3.0, -1.0, 5.0, -0.1, 0.5, 1.2, PAD, {})
	box(Vector3(-8.0, -2.0, 0.5), Vector3(-7.4, 4.0, 0.9), TRIM)


## The range: a short lane along the right-hand wall with a backstop at the end
## of it. Short on purpose — far enough to aim, near enough to walk back.
func _range() -> void:
	box(Vector3(-HALL_X + 1.0, HALL_Y - 6.0, 0.0), Vector3(-6.0, HALL_Y - 0.5, 0.15), {"top": SCORCH, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-HALL_X + 1.0, HALL_Y - 6.5, 0.0), Vector3(-HALL_X + 2.5, HALL_Y - 0.5, 4.5), CONCRETE)
	for k in 4:
		var y := HALL_Y - 5.5 + k * 1.4
		box(Vector3(-HALL_X + 2.5, y - 0.5, 1.0), Vector3(-HALL_X + 2.7, y + 0.5, 1.2), TRIM)
	# A low wall to shoot over, two thirds of the way down the lane.
	box(Vector3(-14.0, HALL_Y - 6.0, 0.0), Vector3(-13.0, HALL_Y - 2.0, 1.0), CONCRETE)


## The transit car at the far end: a machine-built pod on a rail bed, its door
## open toward the ramp. Walking into it is how you leave. It replaces a train
## model that never belonged here — this one is built from the same brushes as
## everything else, and it is sized so the squad walks in with you.
func _transit() -> void:
	var cx := -19.0
	# The rail bed, and the rails on it.
	box(Vector3(cx - 4.0, -11.0, 0.0), Vector3(cx + 3.5, 11.0, 0.5), {"top": BALLAST, "side": CONCRETE, "bottom": CONCRETE})
	for o: float in [-1.4, 1.4]:
		box(Vector3(cx + o - 0.1, -11.0, 0.5), Vector3(cx + o + 0.1, 11.0, 0.65), METAL)
	# The body, in two lengths with a 4 m gap between them: the gap is the way
	# in. Built as an opening rather than a recess with a panel in it, because
	# the squad has to walk through it and a door you cannot see through is a
	# door nobody believes in.
	for seg: Array in [[-7.0, -2.0], [2.0, 7.0]]:
		var pts: Array = []
		for y: float in [seg[0], seg[1]]:
			for lvl: Array in [[0.7, 1.9], [1.4, 2.2], [4.4, 2.2], [5.0, 1.6]]:
				pts.append(Vector3(cx - float(lvl[1]), y, float(lvl[0])))
				pts.append(Vector3(cx + float(lvl[1]), y, float(lvl[0])))
		solid(pts, CLAD)
	# The vestibule behind the gap: its floor, its back, and the roof over it.
	box(Vector3(cx - 2.2, -2.0, 0.5), Vector3(cx + 1.6, 2.0, 0.7), GRATING)
	box(Vector3(cx - 2.2, -2.0, 0.7), Vector3(cx - 1.4, 2.0, 4.4), TECH_WALL)
	box(Vector3(cx - 2.2, -2.0, 4.4), Vector3(cx + 2.2, 2.0, 5.0), CLAD)
	box(Vector3(cx - 1.4, -2.0, 3.2), Vector3(cx - 1.2, 2.0, 3.6), TRIM)
	for s: float in [-1.0, 1.0]:
		box(Vector3(cx + 1.9, s * 2.0, 0.7), Vector3(cx + 2.5, s * 2.4, 3.8), METAL)
	box(Vector3(cx + 1.9, -2.4, 3.4), Vector3(cx + 2.5, 2.4, 3.8), METAL)
	box(Vector3(cx + 2.4, -2.0, 3.2), Vector3(cx + 2.5, 2.0, 3.4), TRIM)
	# Ribs along the body, a lit strip down each side, and the bogies.
	for k in 7:
		var y := -6.0 + k * 2.0
		if absf(y) < 2.6:
			continue
		for s: float in [-1.0, 1.0]:
			box(Vector3(cx + s * 2.2, y - 0.25, 1.4), Vector3(cx + s * 2.5, y + 0.25, 4.4), METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(cx + s * 2.2, -7.0, 4.0), Vector3(cx + s * 2.45, 7.0, 4.3), METAL)
	for y: float in [-5.0, 5.0]:
		box(Vector3(cx - 1.9, y - 1.4, 0.5), Vector3(cx + 1.9, y + 1.4, 0.9), METAL)
		for o: float in [-1.4, 1.4]:
			cylinder(Vector3(cx + o, y - 0.9, 0.55), 0.45, 0.3, 10, METAL)
			cylinder(Vector3(cx + o, y + 0.9, 0.55), 0.45, 0.3, 10, METAL)
	# The tunnel it leaves by, blocked for now, and the gantry over the dock.
	box(Vector3(-HALL_X, -9.0, 0.0), Vector3(-HALL_X + 1.0, 9.0, 7.0), TECH_WALL)
	box(Vector3(-HALL_X + 1.0, -9.0, 6.6), Vector3(-HALL_X + 1.2, 9.0, 7.0), CLAD)
	for y: float in [-9.0, 9.0]:
		box(Vector3(cx - 4.5, y - 0.4, 0.0), Vector3(cx - 3.7, y + 0.4, 8.0), CLAD)
		box(Vector3(cx + 3.7, y - 0.4, 0.0), Vector3(cx + 4.5, y + 0.4, 8.0), CLAD)
		box(Vector3(cx - 4.5, y - 0.4, 8.0), Vector3(cx + 4.5, y + 0.4, 8.8), CLAD)


## Pipes, cable runs and light fittings. None of it is solid: this is a room
## the squad walks round, and a pipe at knee height is a pipe they path round.
func _fittings() -> void:
	no_collision()
	for s: float in [-1.0, 1.0]:
		for o: float in [8.2, 9.0]:
			box(Vector3(-HALL_X + 1.0, s * (HALL_Y - 0.6), o), Vector3(HALL_X - 1.0, s * HALL_Y, o + 0.45), METAL)
	for k in 5:
		var x := -16.0 + k * 8.0
		box(Vector3(x - 0.5, -HALL_Y + 1.0, HALL_Z - 0.6), Vector3(x + 0.5, HALL_Y - 1.0, HALL_Z), GRATING)
		box(Vector3(x - 2.5, -1.0, HALL_Z - 0.5), Vector3(x + 2.5, 1.0, HALL_Z - 0.2), LAMP)
	# Cable trays dropping down the back wall behind the gallery.
	for k in 3:
		var y := -6.0 + k * 6.0
		box(Vector3(HALL_X - 0.6, y - 0.4, GALLERY), Vector3(HALL_X, y + 0.4, HALL_Z), METAL)
