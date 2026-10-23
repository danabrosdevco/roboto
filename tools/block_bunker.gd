extends "res://tools/block_buildings.gd"

# ─────────────────────────────────────────────
# BLOCK BUNKER — the surface entrance to an underground rail station: huge
# doors that grind apart onto darkness, which the squad walks into.
#
#   maps/blocks/bunker/bunker_*.map
#
#   godot --headless --path . --script res://tools/block_bunker.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_bunker.gd -- maps/blocks --force [names]
#
# WHAT IT IS, and every number below follows from it: the depot is a railhead,
# the squad's home is a train, every campaign site sits on the same network,
# and this is where that network surfaces. Taking a site means opening its door
# to the railway. The doors are the level exit, they are how the squad arrives
# on a defence, and their position IS the 45-second stand-down progress bar —
# read from cover, at a glance, with no HUD.
#
# THE ARITHMETIC THAT DECIDED THE OPENING. 8.0 m wide takes a Rover (3.4 m
# long, 1.7 wide) or a Bulwark (2.26 m wide) abreast rather than a man; 4.2 m
# high clears a 3.00 m Walker with room over its head AND keeps the whole
# module 5.0 m tall, which is what lets the flush interior mounting stand under
# the Causeway's 5.25 m clearance. One leaf size therefore serves all three
# mountings. A 5.0 m opening would not have.
#
# THE LEAVES ARE NOT IN THIS MOUTH. They are maps of their own, instanced by
# build_bunker.gd as LeafLeft and LeafRight, because GAMEPLAY drives them by
# lerping position.x against stand_down_fraction(). No AnimationPlayer, no
# shader parameter, no swapped meshes: a float driving two transforms stalls
# and resumes for free, which stand_down_interrupted requires. Each leaf map's
# origin IS its closed position, so the instance sits at zero when shut and at
# x = ±TRAVEL when open.
#
# AXES. Quake (x, y, z) is Godot (y, z, x). The mouth is built across MAP Y, so
# the opening spans GODOT X and the leaves slide along Godot ±X, which is what
# GAMEPLAY was promised. The tunnel runs into MAP -X, which is Godot -Z, so the
# approach is from Godot +Z.
#
# FLOOR is z = 0 at the mouth and dead flat the whole 10 m of tunnel: the squad
# starts a defence standing in it and walks out toward the camera. The sunken
# court mounting puts GRADE at +2.5 and keeps the mouth's own datum, so mouth
# and mount drop at the same origin.
#
# NOTHING ON A LEAF STANDS PROUD OF IT. The slot that takes a parked leaf is
# exactly LEAF_T deep, so a rib or a bracket on the face would scrape the
# shroud and clip the plate for the whole 4.3 m of travel. Every band on the
# door is a brush OF the door, stacked, not a strip laid on it.
#
# SOLIDS BEFORE no_collision(), DETAIL AFTER. Nothing solid stands between
# 0.25 m and 0.5 m (the baker's climb and the squad's step-over) — _audit()
# checks that, checks every brush against every other brush, and MEASURES the
# clear opening, the tunnel, the pocket, the dock and the total height off the
# brushes before the file is written.
# ─────────────────────────────────────────────

const BUNKER := {
	"bunker_mouth": "_mouth",
	"bunker_leaf_left": "_leaf_left",
	"bunker_leaf_right": "_leaf_right",
	"bunker_signal_strip": "_signal_strip",
	"bunker_mount_open": "_mount_open",
	"bunker_mount_cliff": "_mount_cliff",
	"bunker_mount_wall": "_mount_wall",
}

# ── The mouth's envelope. build_bunker.gd reads these: describe once. ────────

const OPEN_W := 8.0          ## clear opening width — a Rover or a Bulwark abreast
const OPEN_HALF := 4.0
## Clear opening height. THE DESIGN SAID 4.2 AND THE GRID CANNOT SAY IT: 4.2 m
## is 134.4 units and solid() snaps every coordinate to 1/32 m, so the choice
## is 4.1875 or 4.21875. 134/32 it is — 12 mm under the design, 1.19 m over a
## 3.00 m Walker, and it keeps the module at 5.0 m so the flush interior
## mounting still fits the Causeway's 5.25.
const OPEN_H := 4.1875
const LEAF_W := 4.3          ## each leaf overlaps its jamb by 0.3 m when shut
const LEAF_T := 0.5
const TRAVEL := 4.3          ## how far each leaf runs, along Godot ±X
const TUNNEL_D := 10.0       ## sealed at the back, unlit
const DECK_Z := 5.0            ## the lintel deck: the tap drone lands here
const WALL_TOTAL := 5.25     ## the flush interior mounting's hard ceiling

## The surround, in map x. The plate is the 1.0 m of heavy structure round the
## opening; the leaf runs in FRONT of it, which is the whole legibility
## argument — a recessed leaf disappears behind its own jamb the moment you
## look at the doors from an angle, and the player looks at them from cover.
const PLATE_X1 := 1.0        ## outer face of the plate surround, and the leaf's back
const LEAF_X0 := 1.0
const LEAF_X1 := 1.5
const SKIN_X1 := 1.75        ## outer skin of the leaf shroud
const APRON_X1 := 2.75       ## the module's own ground stops here; a mounting's begins
const TUNNEL_BACK := -10.0   ## the sealed back face, 10 m in
const SLAB_X0 := -11.0

## The surround, in map y. The leaf parks in a closed slot: the plate behind
## it, the shroud skin in front, the guide rail over the top and an end cap
## outboard, open only at SLOT_Y0 where the leaf comes out.
const TUNNEL_WALL := 5.0     ## outer face of the tunnel's side wall
const SLOT_Y0 := 4.0
const SLOT_Y1 := 8.75
const JAMB_Y1 := 9.0         ## the module's outer edge across

const RAIL_Z0 := OPEN_H       ## the guide rail sits straight on top of the leaf
const RAIL_Z1 := 4.5
const STRIP_Z0 := 4.5        ## the signal band, above the opening and clear of the rail
const STRIP_Z1 := 4.75
## The lamp panel is let into the soffit of the reveal at exactly RAIL_Z0, so it
## lights the gap without taking a millimetre off the 4.2 m clear height.
const LAMP_Z1 := 4.375
const LAMP_X1 := 0.9375

## The terminal console: a pylon beside the doors, outside the leaf's travel so
## a closing leaf can never sweep through the thing you are standing at.
const CON_X0 := 1.75
const CON_X1 := 2.75
const CON_Y0 := 7.0
const CON_Y1 := 9.0
const CON_H := 2.0
const CON_FACE_Z := 1.3      ## the readout's middle: standing height for a 1.7 m chassis

## The drive housings, high on each shroud: this world shows its mechanism.
const DRIVE_X1 := 2.5
const DRIVE_Y0 := 5.0
const DRIVE_Z0 := 3.0
const DRIVE_Z1 := 4.75

## The dock, on the lintel deck. A tap drone is 3.4 m across the rotors and
## wants it flat and clear from directly above, so it sits over the lintel
## where the deck is continuous rather than out at the shroud.
const DOCK_X := 0.0
const DOCK_Y := 0.0
## The beacon, offset far enough along the deck that it never stands over the
## drone's landing: 7 m out leaves 5.3 m clear of a 3.4 m rotor disc.
const BEACON_X := 0.75
const BEACON_Y := -7.0

## The chassis these numbers were measured against.
const ROVER_L := 3.4
const ROVER_W := 1.7
const BULWARK_W := 2.26
const WALKER_H := 3.0
const DRONE_SPAN := 3.4

# ── The sunken court. 1 in 7 is 2.5 m over 17.5 m. ──────────────────────────

const COURT_X0 := 2.75       ## butts the module's apron; the mount never overlaps it
const COURT_X1 := 21.75
const COURT_HALF := 12.0
const COURT_DEEP := 2.5
const RAMP_Y0 := -12.0
const RAMP_Y1 := -8.0
const RAMP_FOOT := 4.25      ## 17.5 m of run from COURT_X1 back to here

# ── Textures. The head house's set: this is the same building, buried. ──────

const GREEN := "PSX_Textures/stratcom_green"
const GREEN_P := "PSX_Textures/stratcom_green_panel"
const CREAM := "PSX_Textures/stratcom_cream"
const CEIL_T := "PSX_Textures/stratcom_cream_ceiling"
const CONC := "PSX_Textures/stratcom_concrete_board"
const BRASS := "PSX_Textures/stratcom_brass"
const READOUT := "PSX_Textures/stratcom_readout"
const STENCIL := "PSX_Textures/stratcom_stencil"
const DOOR_T := "PSX_Textures/stratcom_door_steel"
const CONDUIT := "PSX_Textures/stratcom_conduit"
const LAMP_T := "PSX_Textures/hl_office_complex_style_drop_ceiling_1_1"
## The machines' glowing circuitry stand-in. Its material has NO emission, and
## the signal strip is a prefab of its own so GAMEPLAY tints the instance with
## a material_override rather than writing into a shared texture material.
const SIGNAL_T := "PSX_Textures/glitch_tx_1"
const BALLAST := "PSX_Textures/concrete_3"

## 54/32: the dado line has to land on the grid or solid() rounds it and the
## green and the cream stop meeting.
const DADO := 1.6875

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
		print("usage: godot --headless --path . --script res://tools/block_bunker.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("bunker")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in BUNKER:
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
		call(BUNKER[name])
		print("      %-24s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
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
	if only.is_empty():
		_assembly()
	print("BLOCK BUNKER DONE: %d written%s%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else "",
			"  — WITH FAILURES" if _failed else ""])
	quit(1 if _failed else 0)


# ── Painting ────────────────────────────────────────────────────────────────

## A box painted the way Home Command paints everything: green to dado height,
## cream above, split at the dado so the line is a real edge on the grid.
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


# ── The mouth: one module, shared by all three mountings ────────────────────

func _mouth() -> void:
	# THE BASE. One slab under the tunnel, the reveal, the threshold, both leaf
	# slots and the console, so the floor is level with the approach and
	# walkable its whole depth. It stops at APRON_X1 — every mounting's own
	# ground begins there, and two slabs sharing a footprint is a placement
	# clash, not a thicker floor.
	box(Vector3(SLAB_X0, -JAMB_Y1, -0.5), Vector3(APRON_X1, JAMB_Y1, 0.0),
			{"top": CONC, "side": CONC, "bottom": BALLAST})

	# THE TUNNEL. 8.0 x 4.2 clear, 10 m deep, sealed at the back and unlit.
	for s: float in [-1.0, 1.0]:
		_painted(Vector3(TUNNEL_BACK, s * OPEN_HALF, 0.0), Vector3(0.0, s * TUNNEL_WALL, OPEN_H))
	# Sealed means sealed: nothing is modelled on the other side of this.
	_painted(Vector3(SLAB_X0, -TUNNEL_WALL, 0.0), Vector3(TUNNEL_BACK, TUNNEL_WALL, DECK_Z))
	# The tunnel roof, which is also the deck the drone lands on.
	box(Vector3(TUNNEL_BACK, -TUNNEL_WALL, OPEN_H), Vector3(0.0, TUNNEL_WALL, DECK_Z),
			{"top": CONC, "side": CONC, "bottom": CEIL_T})

	# THE PLATE SURROUND: two jambs with the opening between them, and the
	# lintel over the top. The lintel is in three pieces because the lamp panel
	# is let into its soffit, and a lamp hanging BELOW RAIL_Z0 would quietly
	# make the clear opening 4.0 m instead of 4.2.
	for s: float in [-1.0, 1.0]:
		_painted(Vector3(0.0, s * OPEN_HALF, 0.0), Vector3(PLATE_X1, s * JAMB_Y1, OPEN_H))
		box(Vector3(0.0, s * OPEN_HALF, OPEN_H), Vector3(PLATE_X1, s * JAMB_Y1, DECK_Z), CONC)
	box(Vector3(LAMP_X1, -OPEN_HALF, OPEN_H), Vector3(PLATE_X1, OPEN_HALF, DECK_Z), CONC)
	box(Vector3(0.0, -OPEN_HALF, LAMP_Z1), Vector3(LAMP_X1, OPEN_HALF, DECK_Z), {"side": CONC, "bottom": CEIL_T, "top": CONC})
	# THE LAMP PANEL. Behind the leaves when they are shut, so light spills out
	# of the gap as they part and out of nowhere else.
	box(Vector3(0.0, -OPEN_HALF, OPEN_H), Vector3(LAMP_X1, OPEN_HALF, LAMP_Z1), LAMP_T)

	# THE LEAF SLOTS. A leaf at full travel is wholly inside one and nowhere
	# near the walkway.
	for s: float in [-1.0, 1.0]:
		# the skin, which is the module's front face either side of the opening
		box(Vector3(LEAF_X1, s * SLOT_Y0, 0.0), Vector3(SKIN_X1, s * JAMB_Y1, RAIL_Z0), DOOR_T)
		# the end cap, behind the skin and outboard of the parked leaf
		box(Vector3(LEAF_X0, s * SLOT_Y1, 0.0), Vector3(LEAF_X1, s * JAMB_Y1, RAIL_Z0), GREEN_P)

	# THE GUIDE RAIL, straight on top of the leaf and running the full travel,
	# with the deck closing over it. Visible mechanism, above every head.
	box(Vector3(LEAF_X0, -JAMB_Y1, RAIL_Z0), Vector3(SKIN_X1, JAMB_Y1, RAIL_Z1), BRASS)
	box(Vector3(LEAF_X0, -JAMB_Y1, RAIL_Z1), Vector3(SKIN_X1, JAMB_Y1, DECK_Z), GREEN_P)

	# THE DRIVE HOUSINGS, one per jamb, high on the shroud where the motor that
	# pulls a 4.3 m leaf would actually be.
	for s: float in [-1.0, 1.0]:
		box(Vector3(SKIN_X1, s * DRIVE_Y0, DRIVE_Z0), Vector3(DRIVE_X1, s * JAMB_Y1, DRIVE_Z1), GREEN_P)
		box(Vector3(SKIN_X1, s * DRIVE_Y0, DRIVE_Z1), Vector3(DRIVE_X1, s * JAMB_Y1, DECK_Z), BRASS)

	# THE TERMINAL CONSOLE. Beside the doors, reachable on foot, clear of the
	# leaf's travel plane: the interact volume is 2.4 x 1.4 x 2.4 and it has to
	# sit on something the squad walks up to without crossing the opening.
	box(Vector3(CON_X0, CON_Y0, 0.0), Vector3(CON_X1, CON_Y1, CON_H), GREEN_P)
	box(Vector3(CON_X1, CON_Y0 + 0.25, CON_FACE_Z - 0.4), Vector3(CON_X1 + 0.0625, CON_Y1 - 0.25, CON_FACE_Z + 0.4), READOUT)

	# ── Detail. Nothing below collides, so nothing below can bake as a wall. ──
	no_collision()
	# The sill, which is the bottom guide: 6 cm proud, under the 0.25 m the
	# baker climbs anyway, and with no collider at all it cannot cut the floor.
	# IN FRONT OF THE LEAF PLANE, not under it: a sill under the door shared
	# 1.5 m³ with the kick plate at every fraction from shut to half open, and
	# _assembly() is the only thing in this project that could have said so.
	box(Vector3(LEAF_X1, -OPEN_HALF, 0.0), Vector3(SKIN_X1, OPEN_HALF, 0.0625), BRASS)
	# A hazard band on the threshold, so the opening reads as a door from the
	# ground as well as from the hillside opposite.
	box(Vector3(SKIN_X1, -OPEN_HALF, 0.0), Vector3(DRIVE_X1, OPEN_HALF, 0.0625), STENCIL)
	# Banding: a brass line at the dado and another under the deck, both on the
	# front skin where nothing moves — never inside the slot, which is 0.5 m of
	# space the leaf needs all of.
	for s: float in [-1.0, 1.0]:
		box(Vector3(SKIN_X1, s * OPEN_HALF, DADO - 0.0625), Vector3(SKIN_X1 + 0.125, s * (DRIVE_Y0 + 2.0), DADO + 0.0625), BRASS)
	box(Vector3(SKIN_X1, -DRIVE_Y0, DECK_Z - 0.1875), Vector3(SKIN_X1 + 0.125, DRIVE_Y0, DECK_Z), BRASS)
	# Conduit up to each drive housing: this is a machine, and it is worked.
	for s: float in [-1.0, 1.0]:
		box(Vector3(DRIVE_X1 - 0.25, s * (DRIVE_Y0 + 1.0) - 0.125, 0.0),
				Vector3(DRIVE_X1, s * (DRIVE_Y0 + 1.0) + 0.125, DRIVE_Z0), CONDUIT)
	# A stencilled plate over the console's readout. Anything finer than this
	# collapses: solid() snaps every coordinate to 1/32 m.
	box(Vector3(CON_X1, CON_Y0 + 0.25, CON_H - 0.25), Vector3(CON_X1 + 0.0625, CON_Y1 - 0.25, CON_H - 0.0625), STENCIL)


# ── The leaves, one map each, origin at the closed position ─────────────────

## A leaf is 4.3 x 4.2 x 0.5 and overlaps its jamb by 0.3 m when shut, so the
## two of them seal an 8.0 m opening on the centreline with nothing to see
## through. `side` is +1 for the leaf that parks on map +Y, which is Godot +X.
##
## THE ORIGIN IS THE CLOSED POSITION. GAMEPLAY lerps position.x from 0 to
## side * TRAVEL against stand_down_fraction() and nothing else moves.
##
## THE LEADING EDGE IS THE READOUT. The whole stand-down is read off where
## these two brass stiles sit relative to the jambs, from across the map with
## no HUD, so the moving edge is the brightest thing on the door and it is
## 4.2 m of it. Everything else on the leaf is a band stacked in z, flush: a
## 0.5 m slot has no room for a rib standing proud of the face.
## `dy` slides the whole leaf along map y. It is zero for the prefab, which is
## written at the closed position; _assembly() uses it to test the pieces
## against each other at every door fraction, which nothing else can do — the
## assembler sees one concave collider per entity and cannot.
func _leaf(side: float, dy: float = 0.0) -> void:
	var stile: float = dy + side * 0.375
	var y0: float = minf(stile, dy + side * LEAF_W)
	var y1: float = maxf(stile, dy + side * LEAF_W)
	box(Vector3(LEAF_X0, minf(dy, stile), 0.0), Vector3(LEAF_X1, maxf(dy, stile), OPEN_H), BRASS)
	# THE LEAF IS THE BRIGHT THING AND THE OPENING IS THE DARK THING. It is NOT
	# painted green-to-the-dado like the walls it came out of, and the first
	# version of it was: at 60 m, through ten luma steps, the leaf's dark green
	# lower half read as exactly the same value as the dark opening beside it,
	# so a half-open door and an open door were the same picture. The surround
	# stays green and concrete; the leaf is cream with brass courses, so what
	# the player reads across the map is bright panel against dark hole and the
	# boundary between them IS the progress bar.
	for band: Array in [
			[0.0, 0.25, DOOR_T],
			[0.25, 0.375, BRASS],
			[0.375, DADO, CREAM],
			[DADO, DADO + 0.125, BRASS],
			[DADO + 0.125, 3.3, CREAM],
			[3.3, 3.4375, BRASS],
			[3.4375, OPEN_H, CREAM]]:
		box(Vector3(LEAF_X0, y0, band[0]), Vector3(LEAF_X1, y1, band[1]), band[2])


## ── THE PIECES AGAINST EACH OTHER ──────────────────────────────────────────
##
## Every piece of this kit is placed at the same origin, so the assembly IS the
## union of their brushes and brush_overlaps() is the right test for it. It has
## to live here rather than in build_bunker.gd for two reasons: this file has
## the brushes, and only this file can slide a leaf, so only this file can ask
## whether a HALF-OPEN or a PARKED door fouls anything. The assembler sees one
## concave collider per entity and cannot tell the leaves from the jambs.
##
## THE PARKED CASE IS THE ONE THAT MATTERS. A leaf that clears the doorway and
## then clips the shroud it parks in looks fine in every screenshot and is
## wrong for the whole 45 seconds of travel.
func _assembly() -> void:
	for case: Array in [
			["leaves SHUT", 0.0, ""],
			["leaves HALF", 0.5, ""],
			["leaves PARKED", 1.0, ""],
			["parked + sunken court", 1.0, "_mount_open"],
			["parked + cliff face", 1.0, "_mount_cliff"],
			["parked + flush interior", 1.0, "_mount_wall"]]:
		_brushes = []
		_ghost_from = -1
		_entities = []
		_mouth()
		_signal_strip()
		_leaf(-1.0, -TRAVEL * float(case[1]))
		_leaf(1.0, TRAVEL * float(case[1]))
		if case[2] != "":
			call(case[2])
		var pairs := brush_overlaps()
		if pairs.is_empty():
			print("      ASSEMBLY %-24s %3d brushes, 0 overlapping pairs" % [case[0], _brushes.size()])
			continue
		_failed = true
		print("      ASSEMBLY %-24s %3d brushes, %d OVERLAPPING PAIR(S):" % [case[0], _brushes.size(), pairs.size()])
		for i in mini(pairs.size(), 6):
			var p: Array = pairs[i]
			print("               b%d (%s) x b%d (%s) share %s" % [p[0], _brush_box(p[0]), p[1], _brush_box(p[1]), p[2]])


func _leaf_left() -> void:
	_leaf(-1.0)


func _leaf_right() -> void:
	_leaf(1.0)


# ── The signal strip: its own map, so it is its own material ────────────────

## A plain band across the lintel and nothing else. It is a prefab of its own
## because GAMEPLAY has to tint it HUDPalette.SIGNAL: one node, one mesh, one
## material_override, and no risk of writing into a texture material that nine
## other maps share. No cyan is baked anywhere — the StratCom set deliberately
## has none and the colour belongs in code.
func _signal_strip() -> void:
	box(Vector3(SKIN_X1, -OPEN_HALF, STRIP_Z0), Vector3(SKIN_X1 + 0.1875, OPEN_HALF, STRIP_Z1), SIGNAL_T)


# ── Mounting 1: the sunken court, for open ground ───────────────────────────

## A 19 x 24 m cut 2.5 m deep with the mouth in its far wall and a 1 in 7 ramp
## down one side. THE DATUM IS THE COURT FLOOR, which is the mouth's own z = 0,
## so mouth and mount drop at the same origin and grade is at +2.5. The module
## therefore stands 2.5 m proud of the surrounding ground, which is what makes
## the doors readable from across the map instead of a hole nobody can see.
func _mount_open() -> void:
	# The court floor, starting where the module's apron stops, and cut round
	# the ramp rather than under it.
	box(Vector3(COURT_X0, RAMP_Y1, -0.5), Vector3(COURT_X1, COURT_HALF, 0.0),
			{"top": CONC, "side": BALLAST, "bottom": BALLAST})
	box(Vector3(COURT_X0, RAMP_Y0, -0.5), Vector3(RAMP_FOOT, RAMP_Y1, 0.0),
			{"top": CONC, "side": BALLAST, "bottom": BALLAST})
	# Side walls, retaining the cut up to grade.
	for s: float in [-1.0, 1.0]:
		_painted(Vector3(COURT_X0, s * COURT_HALF, 0.0), Vector3(COURT_X1 + 1.0, s * (COURT_HALF + 1.0), COURT_DEEP))
	# The far wall, with the ramp's mouth left open in it.
	_painted(Vector3(COURT_X1, RAMP_Y1, 0.0), Vector3(COURT_X1 + 1.0, COURT_HALF, COURT_DEEP))
	# The near wall's shoulders either side of the module: they retain the cut
	# and give the entrance some bulk to be seen against.
	for s: float in [-1.0, 1.0]:
		_painted(Vector3(-6.0, s * JAMB_Y1, 0.0), Vector3(COURT_X0, s * (COURT_HALF + 1.0), COURT_DEEP))
	# THE RAMP. 2.5 m over 17.5 m is 1 in 7, which is 8.1° — inside everything
	# this project's chassis can climb, and 4 m wide so a Rover and a body pass.
	ramp(RAMP_FOOT, RAMP_Y0, COURT_X1, RAMP_Y1, -0.5, 0.0, COURT_DEEP, "+x",
			{"top": CONC, "side": BALLAST, "bottom": BALLAST})

	no_collision()
	# A kerb along the lip of the cut, so the edge reads from down in the court.
	for s: float in [-1.0, 1.0]:
		box(Vector3(COURT_X0, s * COURT_HALF - 0.0625, COURT_DEEP),
				Vector3(COURT_X1, s * COURT_HALF + 0.0625, COURT_DEEP + 0.1875), BRASS)


# ── Mounting 2: the cliff face, for hillsides and revetments ───────────────

## A revetted headwall standing out of a slope, 7 m high, with wing walls
## flanking the approach. The mass goes ROUND the tunnel, never over it: the
## module's own deck is at 5.0 and the hill sits on that, set back far enough
## that the dock pad is still open to the sky.
##
## THE FACE IS 30 m WIDE, NOT THE 14 THE DESIGN ASKED FOR. The leaves park
## outboard of an 8.0 m opening, which makes the module 18 m across before any
## revetment at all; a 14 m face cannot contain its own doors. See the report.
func _mount_cliff() -> void:
	for s: float in [-1.0, 1.0]:
		# the mass flanking the front face
		_painted(Vector3(0.0, s * JAMB_Y1, 0.0), Vector3(APRON_X1, s * (JAMB_Y1 + 6.0), 7.0))
		# and behind it, filling in beside the tunnel right up to its wall
		_painted(Vector3(SLAB_X0 - 0.5, s * TUNNEL_WALL, 0.0), Vector3(0.0, s * (JAMB_Y1 + 6.0), 7.0))
		# a wing wall returning forward, to funnel the approach
		_painted(Vector3(APRON_X1, s * (COURT_HALF), 0.0), Vector3(APRON_X1 + 4.0, s * (JAMB_Y1 + 6.0), 4.0))
	# The hill over the tunnel, sitting on the module's deck and set back so the
	# strip of deck in front of it stays clear for the drone.
	box(Vector3(SLAB_X0 - 0.5, -TUNNEL_WALL, DECK_Z), Vector3(DOCK_X - 2.5, TUNNEL_WALL, 7.0), CONC)

	no_collision()
	# A coping band along the top of the headwall and a drip course at the
	# dado, so 7 m of concrete has a scale on it.
	for s: float in [-1.0, 1.0]:
		box(Vector3(APRON_X1, s * JAMB_Y1, 6.75), Vector3(APRON_X1 + 0.1875, s * (JAMB_Y1 + 6.0), 7.0), BRASS)
		box(Vector3(APRON_X1, s * JAMB_Y1, DADO - 0.0625), Vector3(APRON_X1 + 0.125, s * COURT_HALF, DADO + 0.0625), BRASS)


# ── Mounting 3: the flush interior ─────────────────────────────────────────

## A plain surround for an interior, and the only variant with a hard number on
## it: TOTAL HEIGHT 5.25 m, the Causeway's interior clearance. The module is
## 5.0 m tall, so this adds a 0.25 m band over the lintel to bring it flush to
## the ceiling, and nothing else. It is why the opening is 4.2 and not 5.0.
func _mount_wall() -> void:
	for s: float in [-1.0, 1.0]:
		_painted(Vector3(PLATE_X1 - 0.25, s * JAMB_Y1, 0.0), Vector3(APRON_X1, s * (JAMB_Y1 + 6.0), WALL_TOTAL))
	box(Vector3(PLATE_X1 - 0.25, -JAMB_Y1, DECK_Z), Vector3(APRON_X1, JAMB_Y1, WALL_TOTAL), CREAM)

	no_collision()
	box(Vector3(APRON_X1, -(JAMB_Y1 + 6.0), WALL_TOTAL - 0.1875),
			Vector3(APRON_X1 + 0.125, JAMB_Y1 + 6.0, WALL_TOTAL), BRASS)


# ── The audit. Measured off the brushes, before anything is written. ────────

func _brush_box(b: int) -> AABB:
	var pl: Array[Plane] = []
	for face: Dictionary in _brushes[b]:
		var n: Vector3 = face.n
		pl.append(Plane(n, n.dot(face.poly[0])))
	# IN METRES. The brush's own planes are in Quake units, because _snap()
	# multiplied by UPM on the way in; every number this audit prints and every
	# threshold it compares against is metres, so the conversion belongs here
	# and nowhere else. The first run of this tool reported a 50 m opening.
	var hull := _hull_box(Geometry3D.compute_convex_mesh_points(pl))
	return AABB(hull.position / UPM, hull.size / UPM)


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

	# 2. Nothing solid between 0.25 m and 0.5 m: the baker will not climb it
	# and a body steps over it, so it bakes as a wall the squad walks through.
	for b in solid_end:
		var bb := _brush_box(b)
		if bb.end.z > 0.25 + 1e-4 and bb.end.z <= 0.5 + 1e-4 and bb.position.z < 0.25:
			ok = false
			print("      BAND     solid b%d tops out at %.3f m — inside 0.25..0.5 m: %s" % [b, bb.end.z, bb])

	# 3. Total height, which is the whole argument for a 4.2 m opening.
	var top := -INF
	for b in _brushes.size():
		top = maxf(top, _brush_box(b).end.z)
	print("      height   %.3f m overall" % top)
	if name == "bunker_mount_wall" and top > WALL_TOTAL + 1e-4:
		ok = false
		print("      FAIL     the flush interior mounting is over the %.2f m ceiling" % WALL_TOTAL)

	if name != "bunker_mouth":
		return ok

	# 4. THE CLEAR OPENING, measured rather than asserted. At the mouth plane,
	# the free span containing the centreline for a WALKER_H body, and the
	# lowest solid thing over the middle of it.
	var dx: float = PLATE_X1 * 0.5
	var width := _centre_gap(dx, WALKER_H, solid_end)
	var height := INF
	for b in solid_end:
		var bb := _brush_box(b)
		if bb.position.x < dx and bb.end.x > dx and bb.position.y < 0.0 and bb.end.y > 0.0 and bb.position.z > 0.05:
			height = minf(height, bb.position.z)
	print("      opening  %.3f m wide x %.3f m high  (design %.1f x %.1f)" % [width, height, OPEN_W, OPEN_H])
	if absf(width - OPEN_W) > 1e-3 or absf(height - OPEN_H) > 1e-3:
		ok = false
		print("      FAIL     the built opening is not the designed one")
	if height < WALKER_H + 1e-4:
		ok = false
		print("      FAIL     a %.2f m Walker cannot pass" % WALKER_H)

	# 5. THE TUNNEL, which a Rover has to get into and turn round in. Turning a
	# 3.4 x 1.7 body on the spot needs a clear circle of its own diagonal.
	var turn := sqrt(ROVER_L * ROVER_L + ROVER_W * ROVER_W)
	var narrow := INF
	var at := 0.0
	var x: float = TUNNEL_BACK + 0.0625
	while x < -0.0625:
		var g := _centre_gap(x, WALKER_H, solid_end)
		if g < narrow:
			narrow = g
			at = x
		x += 0.125
	print("      tunnel   %.3f m narrowest clear width at x=%.2f, %.1f m deep; a Rover turns in %.2f m" % [
			narrow, at, TUNNEL_D, turn])
	if narrow < turn + 1e-4:
		ok = false
		print("      FAIL     a Rover cannot turn round in the tunnel")
	print("      abreast  %.2f m takes %d Bulwarks (%.2f m) or %d Rovers (%.2f m) side by side" % [
			narrow, int(narrow / BULWARK_W), BULWARK_W, int(narrow / ROVER_W), ROVER_W])

	# 6. THE LEAF POCKET. A leaf at full travel must be inside the slot and
	# clear of the walkway, or an open door stands in its own doorway.
	var leaf_outer: float = TRAVEL + LEAF_W
	print("      pocket   a leaf at full travel reaches y %.2f .. %.2f; the slot runs %.2f .. %.2f" % [
			TRAVEL, leaf_outer, SLOT_Y0, SLOT_Y1])
	if leaf_outer > SLOT_Y1 + 1e-4:
		ok = false
		print("      FAIL     the pocket is too short for the leaf")
	if TRAVEL < OPEN_HALF + 1e-4:
		ok = false
		print("      FAIL     %.2f m of travel leaves a leaf standing in a %.1f m opening" % [TRAVEL, OPEN_W])
	# What the 0.5 frame actually shows, since that frame is the whole design.
	print("      half     at fraction 0.50 the leaves stand at y ±%.2f: %.2f m of dark in %.1f m of opening (%d%%)" % [
			TRAVEL * 0.5, TRAVEL, OPEN_W, int(round(TRAVEL / OPEN_W * 100.0))])

	# 7. THE DOCK, flat and unobstructed from directly above for a 3.4 m drone.
	var r: float = DRONE_SPAN * 0.5
	var deck_seen := false
	for b in _brushes.size():
		var bb := _brush_box(b)
		if bb.position.x > DOCK_X + r or bb.end.x < DOCK_X - r:
			continue
		if bb.position.y > DOCK_Y + r or bb.end.y < DOCK_Y - r:
			continue
		if bb.position.z >= DECK_Z - 1e-4:
			ok = false
			print("      FAIL     b%d stands on the dock pad: %s" % [b, bb])
		elif absf(bb.end.z - DECK_Z) < 1e-4:
			deck_seen = true
	if not deck_seen:
		ok = false
		print("      FAIL     nothing decks the dock pad at z = %.2f" % DECK_Z)
	print("      dock     pad at (%.2f, %.2f) z %.2f, clear for a %.1f m drone" % [DOCK_X, DOCK_Y, DECK_Z, DRONE_SPAN])
	return ok


## The free span in y containing the centreline at map x, for a body `h` tall
## standing on the floor. The gap CONTAINING y = 0, not the widest one: outside
## the module there is no geometry at all, so the widest gap at any x is the
## open air beside it, which measures beautifully and means nothing.
func _centre_gap(x: float, h: float, solid_end: int) -> float:
	var lo: float = -JAMB_Y1 - 16.0
	var hi: float = JAMB_Y1 + 16.0
	for b in solid_end:
		var bb := _brush_box(b)
		if bb.position.x > x or bb.end.x < x:
			continue
		if bb.end.z <= 0.05 or bb.position.z >= h:
			continue
		if bb.position.y <= 0.0 and bb.end.y >= 0.0:
			return 0.0        # something solid stands on the centreline itself
		if bb.end.y < 0.0:
			lo = maxf(lo, bb.end.y)
		else:
			hi = minf(hi, bb.position.y)
	return hi - lo
