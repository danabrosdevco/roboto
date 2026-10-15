extends "res://tools/block_industrial.gd"

# ─────────────────────────────────────────────
# THE COMPUTE CORE — ROUND TWO: AN ASYMMETRIC RELAY MACHINE.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/build_core_relay.gd -- maps/blocks [--force]
#
# Writes maps/blocks/compute/compute_core{_small,,_large}.map, REPLACING round
# one's interlaced skeleton (tools/build_core_skeleton.gd, kept beside this for
# the record). Follow it with:
#
#   tools/block_prefabs.gd -- maps/blocks/compute --only=compute_core --force
#   tools/core_skeleton_dress.gd                          (Paint / Lit / pulse)
#
# The dress pass is NOT optional. FuncGodot assigns materials by texture name,
# so a freshly built prefab is navy metal with grey patches on it; the dress
# pass is what turns the tagged entities into the Paint and Lit groups
# core_pulse.gd needs. It is re-appliable, because a block_prefabs rebuild
# throws the dressing away. It reads this file's tags, not the skeleton's
# shapes, so it needed no change.
#
# ─────────────────────────────────────────────
# WHY ROUND ONE WENT IN THE BIN
#
# docs/concepts/CORE_SKELETON.md records what was built and docs/concepts/
# core_skel_row.png is what the human looked at:
#
#   "i don't like the bands. can we do like a more asymmetrical structure
#    that's more imposing / wider, looks like technology and is visually more
#    interesting? it doesn't need a terminal."
#
# So three things of GAMEPLAY's brief are OVERRIDDEN and must not creep back:
#
#   * THE INTERLACED HORIZONTAL BANDS, entirely. Not a different pitch — the
#     1.0 m alternative was photographed too (core_skel_row_ALT_1m_pitch.png)
#     and shown. A rung repeat up a plain stem is a ladder at every pitch.
#   * "THIN, AND MODEL NOTHING VERTICAL." The replacement is wider and the fin
#     bank is as vertical as a thing gets.
#   * THE CONSOLE PEDESTAL. Not modelled. That amber plate was also the
#     brightest thing on round one's model, so its removal fixes a fault.
#
# "DOESN'T NEED A TERMINAL" MEANS NO MODELLED CONSOLE, NOT NO INTERACTION.
# Env/world_objects/compute_core_point*.tscn wires
# interactibles = [NodePath("Terminal/Interactible")] into a DummyTerminal that
# already has show_body = false, so the interact volume is a box centred on the
# core and NOTHING ON THIS MODEL CARRIES IT. Capture breaks if that node goes.
# reach_size stays at footprint minus 0.6 m; see the wrapper's own header for
# the raycast arithmetic, and note the footprint is a RECTANGLE now, so the
# wrapper's reach box is no longer square either.
#
# ─────────────────────────────────────────────
# THE TRAP, WHICH HAS ALREADY KILLED ONE BUILD
#
# GAMEPLAY's section 10: the first rejected build "read as a building because a
# grid has two directions and it had both". GOING WIDER WALKS STRAIGHT BACK
# TOWARD THAT, so every piece of asymmetry here comes from MASSING AND
# COMPONENTS and none of it from a panelled face:
#
#   * the masses are plain boxes with big BLANK faces, crossed by a shelf, a
#     cable or a vent — never subdivided into bays. A blank face is allowed to
#     be blank; that is what makes the fin bank read as a fitting ON something
#     rather than as one more course of a facade.
#   * the fin bank runs in ONE direction (vertical) in ONE row on ONE flank.
#     A second row at another height would be a grid again.
#   * the only repeats on the whole model are the fins and the three cable
#     terminations, both of which are things a real machine has several of.
#
# ─────────────────────────────────────────────
# THE SHAPE, AND WHY EACH PIECE IS THERE
#
# The register is compute_transformer (see docs/concepts/core_l3_kit_vocabulary.png
# and _transformer() in tools/block_ai_infra.gd): a bunded tray, a mass, a fin
# bank, bushings, a cylinder. That piece reads as EQUIPMENT in one glance, at a
# tenth of this thing's size, and nothing in the kit does it better.
#
#   BUND        a broad tray on a sunk plinth, with a rim on the +X and +Y
#               sides ONLY. A rim all the way round is a planter; two sides is
#               a bund you can see into, and the two it is missing are the two
#               the player approaches from.
#   PRIMARY     a two-stage mass offset into the +X/+Y corner, the upper stage
#               inset on -X and -Y ONLY so the step is one-sided, with a CANTED
#               crown. The cant is what stops the tallest thing on the model
#               being a flat-topped box.
#   SECONDARY   a lower mass alongside on -X, carrying the cylinder and the
#               three cable terminations. Different height, different width,
#               different fittings: that is where the asymmetry lives.
#   FIN BANK    heat-exchanger fins on the -Y flank of the primary mass. The
#               strongest technology cue in the kit.
#   TRUNKS      bushing, horizontal run, junction, vertical trunk, gland in the
#               tray floor. GAMEPLAY's section 1: a core is a RELAY, it holds a
#               territory, and taking it is taking the area's wiring.
#   SHELF       a cantilevered landing shelf carrying the drone pad, springing
#               off the primary mass's step and overhanging the fin bank. This
#               is the asymmetry, the overhang and the cap contract in one
#               move, and it is why the small core is no longer a mushroom: the
#               pad sits BESIDE the mass, not on top of it.
#
# ─────────────────────────────────────────────
# THE CONTRACTS, which are not this file's to adjust
#
#   * THE PAD IS 2.625 m ACROSS AT EVERY SIZE AND COMPLETELY CLEAR, WITH
#     NOTHING ABOVE IT. The TICK drone is built and approved and clamps four
#     legs 0.37 m outside its edge; that one clamp has to be correct on a 4.2 m
#     core and a 12.4 m one alike. The upper stage's -X face is the pad's +X
#     edge BY CONSTRUCTION (see _shelf), so no part of the mass can ever
#     overhang it.
#   * HEIGHTS 4.19 / 7.00 / 12.41. Round one found 4.20 and 12.40 are not
#     expressible on a 1/32 m grid at all; these are the nearest and they are
#     what the site tiers were sized against.
#   * A VERTICAL PATH OF LIT ELEMENTS, ADDRESSABLE BY HEIGHT. core_pulse.gd
#     runs a band of light up the object at 6 m/s and buckets by pulse_y. It
#     does NOT need to be symmetric, and this one is not: it climbs from the
#     cable glands in the tray, up the gaps between the fins as a staircase,
#     out along the shelf lip and up to the crown slot.
#   * NOTHING SOLID BETWEEN 0.25 AND 0.5 m, where the mesh says wall and the AI
#     says step. The plinth's 0.34 m top is INSET under a wider tray plate, so
#     it is an undercut rather than a ledge; the tray itself is a 0.53 m sheer
#     step and the bund rim stands 0.63 m above that.
#
# ─────────────────────────────────────────────
# AXES. FuncGodot maps map (x, y, z) to Godot (y, z, x):
#
#   map +X -> Godot +Z          map +Y -> Godot +X          map +Z -> Godot +Y
#
# The player approaches from Godot -Z, which is map -X, and that is the open
# corner of the bund, the cantilever, the glands and the lit shelf lip. Height
# throughout this file is map Z. Re-deriving this by hand is how Polaris came
# out with its ring road at right angles to its own corners.
#
# ─────────────────────────────────────────────
# THE ENTITY STRUCTURE IS THE REAL DELIVERABLE, and it is unchanged from round
# one because nothing was wrong with it:
#
#   * every painted piece is ITS OWN ENTITY, tagged `core:paint`
#   * every lit piece is ITS OWN ENTITY, tagged `core:lit y=<height>` — one
#     each, because core_pulse.gd needs them addressable by height
#   * fittings that should not cost collision are one shared entity, `core:trim`
#   * everything else is worldspawn and carries the collision
#
# The tags ride on the `// entity N` comment lines, which FuncGodot provably
# ignores and core_skeleton_dress.gd is the only thing that reads.
# ─────────────────────────────────────────────

const OUT := {
	"compute_core_small": "small",
	"compute_core": "med",
	"compute_core_large": "large",
}

# ── the metal ───────────────────────────────────────────────────────────────
## Dark navy ribbed sheet. FAC_ADVERSARY is warm amber, so navy is near its
## complement and faction colour reads against it at range — on the brown
## sheets amber sits on amber and the mechanism dies. Its ribs are fine
## VERTICAL lines, so a blank mass face is extruded metal at a glance without
## one modelled member on it, which is exactly what a face that must stay blank
## needs. NO CONCRETE ANYWHERE, and NOT metal_floor_3: that is a rack grille
## and it tiled into a facade of windows on the first rejected build.
const MAST_TEX := "PSX_Textures/metal_wall_3@0.25"
## Riveted plate, a value lighter, so every FITTING separates from the mass
## carrying it: the fins, the shelf, the bushings, the trunks, the rim.
const PLATE_TEX := "PSX_Textures/metal_floor_1@0.25"
## Grating, at one tile per 0.5 m. At the structure's 0.25 a single perforation
## is about 15 cm and a tray floor photographs as a field of polka dots — see
## the deck in docs/concepts/core_l3_trunk_med.png, which is the accepted
## study's own render and has exactly that.
const VENT_TEX := "PSX_Textures/grate_perf@0.0625"
## The painted pieces: the mass's own sheet, recoloured by the dress pass.
const BAND_TEX := "PSX_Textures/metal_wall_3@0.25"
## The lit pieces. glitch_tx_neutral and NOT glitch_tx_1, which is round one's
## measured override of section 5 of GAMEPLAY's brief and still holds: a core
## carries four faction colours and a 0.77-saturation grain cannot carry purple
## and amber both. See tools/core_skeleton_dress.gd for the numbers.
const SCREEN_TEX := "PSX_Textures/glitch_tx_neutral@0.04"

# ── the invariant numbers, in grid units of 1/32 m ──────────────────────────
## HALF-WIDTH OF THE LANDING PAD. THE RULER. Do not scale it: the TICK clamps
## it. 42 units is 1.3125, so the pad is 2.625 m across against the contract's
## 2.60 — 2.60 m is 83.2 units and a pad centred on its own axis needs an even
## count, so 42 and 41 are the candidates and 42 is nearer.
const PAD_U := 42
const PAD_GAP := 2
## DECK PAST THE PAD AT THE SLAB'S FREE END, so the fourth barb has something
## to bite.
##
## The TICK clamps four legs and each one comes down OUTSIDE one pad edge —
## that is what gripping means and build_tick.gd sized the thigh hinge for it.
## Three of the four land on deck here. The fourth is the one at the free end
## of the cantilever, where the pad's edge WAS the slab's edge, so it closed on
## open air at every size: measured, it reaches 0.11 m past that edge. Eight
## units is 0.25 m, which puts deck under it with 0.14 m to spare and is the
## smallest number that does — the lip is a tip detail on the overhang, not a
## second shelf, and the whole point of keeping it tight is that the cantilever
## is the strongest thing on the model.
const LIP_U := 8
## How much of the mass's -X face the inner raking strut is given, clear of the
## return bank. The strut is 8 units thick and sits in the middle of it.
const STRUT_GAP := 14
const DECK_U := 11        # 0.34 m of shelf slab under the pad surface
const KERB_U := 5
const LUG_U := 8
## Tray top, and where every mass starts. Round one's 0.53 m to the centimetre,
## and the centimetre matters: a 0.53 m sheer step is not something
## move_and_slide climbs, so the player is stopped OUTSIDE the bund — the only
## arrangement the 2 m InteractRaycast works in, because it does not register a
## hit that STARTS inside a volume.
const GROUND_U := 17
## How far the plinth is sunk, so a core set on slightly uneven ground does not
## show daylight under its own tray.
const SINK_U := 10

## EVERY NUMBER OF EVERY SIZE, IN UNITS, WRITTEN OUT RATHER THAN SCALED.
##
## A single scale factor is what made the shipped trio "one form scaled three
## ways", which is the thing GAMEPLAY's brief opens by rejecting. These three
## share a vocabulary and not a shape: the large core's upper stage is nearly
## half its height and the small one's is a quarter, the fin count goes 5/6/8,
## and the shelf's reach past the mass grows faster than the mass does.
##
##   bx, by   bund HALF-extent on map X and Y. The footprint is a RECTANGLE,
##            deeper than it is wide, which is the single cheapest thing that
##            stops a silhouette reading as a monument.
##   top      overall height. 134 / 224 / 397 = 4.1875 / 7.00 / 12.40625 m.
##   sh       top of the lower stage, and the shelf's bearing level.
##   p0       the primary mass's -X face.
##   b_in     how far the upper stage is inset from p0 on -X...
##   b_yin    ...and from the lower stage's -Y face. INSET ON TWO SIDES ONLY:
##            the +X and +Y faces run through both stages unbroken, so the step
##            is one-sided and the mass has a front and a back.
##   drop     how far the canted crown falls from the +X face to the -X face.
##   fd       fin projection; ft fin thickness; fins how many; fp their pitch.
##   s_len    the secondary mass's length on -X from p0...
##   s_y0     ...its -Y face, hugging the +Y side so the tray stays open under
##            the cantilever...
##   s_top    ...and its height. Lower than the lower stage at every size.
##   ext      how far the shelf slab runs BACK from the pad toward the mass —
##            and therefore how far the pad stands off the mass, which is the
##            one number the docked drone's clearance depends on. On the large
##            core the pad alone would leave the overhang looking like a step;
##            the slab carries it out and the pad sits on the end of it.
##
##            IT IS SET BY THE DRONE NOW, NOT BY THE DRAWING. The placed TICK
##            is 3.19 x 3.50 m and reaches 1.66 m from the dock point toward
##            the mass, against 1.375 + ext/32 m of room, so the 0 / 12 / 36
##            this shipped with FOULED the small core and missed on the medium
##            by 0.08 m. The rule is now: run the slab back until either the
##            drone has real room or the slab reaches the bund's own -X edge,
##            whichever comes first. On the medium those coincide at 36 — flush
##            with the bund, 0.84 m of clearance, the same margin the large has
##            always had. ON THE SMALL THEY DO NOT MEET AT ALL: the bund edge
##            is at ext 0, so every millimetre of clearance is a millimetre of
##            diving board, and the small core does not take the drone. See
##            section 4a of docs/concepts/CORE_RELAY.md.
const SPEC := {
	"small": {
		"bx": 72, "by": 56, "top": 134, "sh": 82,
		"p0": -8, "b_in": 22, "b_yin": 14, "drop": 12,
		"fd": 18, "ft": 5, "fins": 5, "fp": 12, "ret": 2,
		"s_len": 44, "s_y0": 2, "s_top": 62, "ext": 24,
	},
	"med": {
		"bx": 96, "by": 76, "top": 224, "sh": 136,
		"p0": -10, "b_in": 36, "b_yin": 26, "drop": 20,
		"fd": 24, "ft": 6, "fins": 6, "fp": 15, "ret": 3,
		"s_len": 56, "s_y0": 10, "s_top": 100, "ext": 36,
	},
	"large": {
		"bx": 132, "by": 104, "top": 397, "sh": 240,
		"p0": -14, "b_in": 44, "b_yin": 38, "drop": 36,
		"fd": 34, "ft": 8, "fins": 8, "fp": 16, "ret": 4,
		"s_len": 76, "s_y0": 22, "s_top": 170, "ext": 36,
	},
}

## func_detail_illusionary: its own Node3D and its own MeshInstance3D, drawn,
## not solid, not seen by the navmesh baker. The separate MeshInstance3D is the
## whole point — it is what makes one piece recolourable at all.
const PAINT_CLASS := "func_detail_illusionary"
const LIT_CLASS := "func_detail_illusionary"

var _trim: Array = []
var _paint: Array = []
var _lit: Array = []
var _dock := 0.0
var _dock_at := Vector3.ZERO


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/build_core_relay.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("compute")
	if not DirAccess.dir_exists_absolute(dir):
		print("FAIL  no such folder: %s" % dir)
		quit(1)
		return
	var written := 0
	for nm: String in OUT:
		var path := dir.path_join(nm + ".map")
		if FileAccess.file_exists(path) and not force:
			# The file on disk is the source once a human has touched it, and
			# force-rebuilding an edited map has destroyed work in this project
			# twice. Round one's trio was verified byte-reproducible from
			# build_core_skeleton.gd before this tool first overwrote it, so
			# nothing hand-made was lost; that check is owed again next time.
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			continue
		_brushes = []
		_entities = []
		_ghost_from = -1
		_relay(OUT[nm])
		# EVERY BRUSH AGAINST EVERY OTHER, as solids, BEFORE the file is
		# written. Checking afterwards is whack-a-mole: each piece moved to
		# clear one clash lands on something else.
		var clashes := brush_overlaps()
		if not clashes.is_empty():
			# EVERY PAIR, not just the worst. A relay is an assembly of fittings
			# and one bad constant usually clashes in three places at once; a
			# single worst-pair line costs a rebuild to find each of the others.
			print("FAIL  %s: %d overlapping brush pair(s)" % [nm, clashes.size()])
			for c: Array in clashes:
				print("          brush %d x %d  shares %s" % [c[0], c[1], c[2]])
			quit(1)
			return
		var over := _over_pad(OUT[nm])
		if not over.is_empty():
			# THE PAD CONTRACT, ASSERTED RATHER THAN CLAIMED. The TICK drone
			# lands here and clamps four legs 0.37 m outside the edge, and a
			# comment saying the geometry guarantees it is worth nothing the
			# first time a variant adds a mast. One brush over the pad fails
			# the build.
			print("FAIL  %s: %d brush(es) stand over the drone pad — %s" % [nm, over.size(), str(over)])
			quit(1)
			return
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		_report(nm, OUT[nm])
	print("BLOCK CORE RELAY DONE: %d written" % written)
	quit()


func _report(nm: String, tag: String) -> void:
	var s: Dictionary = SPEC[tag]
	var paint := 0
	var lit := 0
	for e: Dictionary in _entities:
		var t: String = e.get("tag", "")
		if t.begins_with("core:paint"):
			paint += 1
		elif t.begins_with("core:lit"):
			lit += 1
	print("      %-20s %3d brushes  %s" % [nm, _brushes.size(), _extent_text()])
	print("          footprint %.2f x %.2f m (map X by Y = Godot Z by X) · %.2f m tall · pad 2.625 sq · dock %.2f m · paint %d · lit %d entities · %d collision brush(es)"
			% [u(s.bx * 2), u(s.by * 2), u(s.top), _dock, paint, lit,
					_entities[0].at if not _entities.is_empty() else _brushes.size()])


func u(n: int) -> float:
	return float(n) / UPM


## Brush indices standing in the open column above the pad.
##
## The lugs and the two kerbs are the pad's own fittings and are the only
## things allowed in it, so the test starts ABOVE them: anything higher than
## the lug tops, inside the pad's plan, is something a later edit has flown
## over a landing surface. `_brushes` holds face polygons in UNITS.
func _over_pad(tag: String) -> Array:
	var s: Dictionary = SPEC[tag]
	var xb: int = s.p0 + s.b_in
	# THE PAD, not the slab: the slab runs LIP_U further out at the free end and
	# `ext` further back toward the mass, and neither of those is pad.
	var px0: int = xb - PAD_GAP - PAD_U * 2 - s.ext
	var y0: int = -s.by
	var floor_z: int = s.sh + DECK_U + LUG_U
	var out: Array = []
	for b in _brushes.size():
		var hit := false
		for face: Dictionary in _brushes[b]:
			for p: Vector3 in face.poly:
				if p.z > float(floor_z) + 0.5 and p.x > float(px0) + 0.5 and p.x < float(px0 + PAD_U * 2) - 0.5 \
						and p.y > float(y0) + 0.5 and p.y < float(y0 + PAD_U * 2) - 0.5:
					hit = true
					break
			if hit:
				break
		if hit:
			out.append(b)
	return out


# ── the body ────────────────────────────────────────────────────────────────

## THE ORDER OF THE _emit CALLS AT THE BOTTOM IS THE ENTITY ORDER IN THE FILE,
## and the dress pass reads the file. block_buildings.gd's entity() splits on
## brush INDEX, so a group that has started cannot be gone back to — which is
## why every non-worldspawn piece is collected in _trim / _paint / _lit while
## the solids are drawn, and written out afterwards.
func _relay(tag: String) -> void:
	var s: Dictionary = SPEC[tag]
	_trim = []
	_paint = []
	_lit = []

	_bund(s)
	_masses(s)
	_fins(s)
	_return_bank(s)
	_terminations(s)
	_shelf(s)

	_emit("func_detail_illusionary", "core:trim", _trim)
	for p: Dictionary in _paint:
		_emit(PAINT_CLASS, "core:paint", [p])
	for l: Dictionary in _lit:
		_emit(LIT_CLASS, "core:lit" + ("" if is_nan(l["y"] as float) else " y=%.4f" % (l["y"] as float)), [l])


## THE BUND. A sunk plinth, a wider grated tray plate over it, and a rim on two
## sides. The tray plate overhangs the plinth all the way round, so the
## plinth's 0.34 m top is an UNDERCUT rather than a ledge in the 0.25-0.5 m
## band where the navmesh says step and the geometry says wall.
##
## THE RIM IS ON +X AND +Y ONLY. All four sides is a planter and reads as
## architecture; two adjacent sides is a bund with a spill side, the tray floor
## and its glands stay visible from the approach, and the model gains a back.
func _bund(s: Dictionary) -> void:
	var bx: int = s.bx
	var by: int = s.by
	box(Vector3(-u(bx - 8), -u(by - 8), -u(SINK_U)), Vector3(u(bx - 8), u(by - 8), u(11)), PLATE_TEX)
	box(Vector3(-u(bx), -u(by), u(11)), Vector3(u(bx), u(by), u(GROUND_U)), VENT_TEX)
	# 0.63 m of rim above the tray, so its top is 1.16 m off the ground: clear
	# of the step band at both ends, and tall enough to read as a bund wall
	# rather than as a kerb.
	box(Vector3(u(bx - 10), -u(by), u(GROUND_U)), Vector3(u(bx), u(by), u(GROUND_U + 20)), PLATE_TEX)
	box(Vector3(-u(bx), u(by - 10), u(GROUND_U)), Vector3(u(bx - 10), u(by), u(GROUND_U + 20)), PLATE_TEX)


## THE PRIMARY AND SECONDARY MASSES.
##
## TWO STAGES, STEPPED ON TWO SIDES OUT OF FOUR. The upper stage is pulled in
## on -X and -Y and runs flush on +X and +Y, so one corner of the object is a
## single unbroken 12 m face and the opposite corner is a staircase of volumes.
## A box inset on all four sides is a wedding cake and reads as a tower.
##
## AND THE CROWN IS CANTED. _hexa takes a top height per corner, and heights
## linear in x stay planar, so the upper stage's top is a plane falling toward
## -X. It costs one brush, it is the whole difference between the tallest thing
## on the model being a MACHINE and being a flat-topped box, and it points at
## the shelf.
##
## THE FACES ARE BLANK ON PURPOSE. GAMEPLAY's section 10 — the first rejected
## build "read as a building because a grid has two directions and it had both"
## — means a large face must stay blank and let a trunk, a fin bank or a shelf
## cross it. The only thing modelled on one here is a single vent panel, which
## is a fitting and not a course.
func _masses(s: Dictionary) -> void:
	var px1: int = s.bx - 18                      # +X face, inside the rim
	var p0: int = s.p0
	var ylo: int = -s.by + 8 + s.fd               # clear of the bund edge by the fins' depth
	var yhi: int = s.by - 18
	var sh: int = s.sh
	var top: int = s.top

	box(Vector3(u(p0), u(ylo), u(GROUND_U)), Vector3(u(px1), u(yhi), u(sh)), MAST_TEX)

	# The upper stage, canted. _hexa's quad runs low-x/low-y, high-x/low-y,
	# high-x/high-y, low-x/high-y, and the top array matches it corner for
	# corner — so the two -X corners carry top - drop and the two +X corners
	# carry top, which is a plane.
	var bx0: int = p0 + s.b_in
	var by0: int = ylo + s.b_yin
	var hi := u(top)
	var lo := u(top - s.drop)
	_hexa([Vector2(u(bx0), u(by0)), Vector2(u(px1), u(by0)), Vector2(u(px1), u(yhi)), Vector2(u(bx0), u(yhi))],
			[u(sh), u(sh), u(sh), u(sh)], [lo, hi, hi, lo], MAST_TEX)

	# A PAINTED COLLAR UNDER THE CROWN, on the -Y flank where the camera and the
	# player both see it. One piece, 0.44 m deep, standing 2 units proud — a
	# marking on a machine, not a band round a mast. It is the highest faction
	# colour on the object, which is what makes ownership readable across a map.
	var ct: int = top - s.drop - 8
	_paint.append(_later_box(Vector3(u(bx0 + (px1 - bx0) / 3), u(by0 - 2), u(ct - 10)),
			Vector3(u(px1 - 6), u(by0), u(ct)), BAND_TEX))

	# THE SECONDARY MASS. Lower, shorter, narrower, and hard against the primary
	# mass's -X face so the two read as one machine in two volumes rather than
	# as two objects. It hugs +Y, which leaves the -X/-Y quarter of the tray
	# open — that is the ground the cantilever flies over, and an overhang with
	# nothing under it is the whole of the drama.
	var s0: int = p0 - s.s_len
	box(Vector3(u(s0), u(s.s_y0), u(GROUND_U)), Vector3(u(p0), u(yhi), u(s.s_top)), MAST_TEX)
	# A vent panel on its -X face: one fitting on a blank face. Grating, so it
	# reads as the machine breathing, at a grain fine enough to stay a texture.
	var vy0: int = s.s_y0 + 6
	var vy1: int = yhi - 6
	_trim.append(_later_box(Vector3(u(s0 - 2), u(vy0), u(GROUND_U + 10)),
			Vector3(u(s0), u(vy1), u(s.s_top - 14)), VENT_TEX))
	# A CYLINDER LYING ALONG THE SHOULDER. Straight out of compute_transformer,
	# and the one round form on an object of boxes: a silhouette needs one thing
	# in it that is not a corner.
	#
	# AT THE +X END OF THE SHOULDER, which is not a preference — the three cable
	# terminations stand at the -X end and their jumpers run out over that edge
	# at just above shoulder height. A cylinder in the middle of the top had
	# every one of them passing through it, which brush_overlaps duly reported.
	var cr: float = u(s.s_len) * 0.21
	log_x(Vector3(u(s0 + s.s_len * 7 / 10), u((s.s_y0 + yhi) / 2.0), u(s.s_top)),
			cr, u(yhi - s.s_y0) - cr * 0.6, 8, PLATE_TEX, "y")


## THE FIN BANK: heat-exchanger fins in one row on the -Y flank of the lower
## stage, from the tray to just under the shelf.
##
## IT IS A COMPONENT, NOT A FACADE, and the difference is measurable: the fins
## run in ONE direction, at ONE pitch, in ONE row, at a pitch four to six times
## finer than any other feature on the model. A second row at another height,
## or a horizontal member crossing them, would make it a grid and the object a
## building. There is no horizontal member.
##
## TRIM, so none of them is solid. They are thin plates standing in front of a
## solid mass, so a bullet still stops; what they would otherwise cost is eight
## collision brushes on every one of the 42 cores the levels hold.
func _fins(s: Dictionary) -> void:
	var ylo: int = -s.by + 8 + s.fd
	var x: int = s.p0
	var z0: int = GROUND_U + 4
	var z1: int = s.sh - 10
	for i in s.fins:
		_trim.append(_later_box(Vector3(u(x), u(ylo - s.fd), u(z0)),
				Vector3(u(x + s.ft), u(ylo), u(z1)), PLATE_TEX))
		x += s.fp
	# THE LIT STAIRCASE, IN THE GAPS BETWEEN THE FINS, and this is the vertical
	# path core_pulse.gd needs — asymmetric, which the brief asks for, and
	# hidden behind a component, which is what keeps it from being a row of
	# windows. Each panel is a different height and they climb toward +X, so
	# when the pulse passes, light walks UP and ALONG the bank at once.
	#
	# THEY SIT NEAR THE FIN TIPS AND NOT ON THE MASS FACE, which is a correction
	# made from a photograph rather than a decision. On the face, each panel sat
	# at the bottom of a slot 0.19 m wide and up to 1.06 m deep: the arithmetic
	# says it is hidden from anything more than 10 degrees off the normal, and
	# core_skel_large_flank.png — taken square on to the bank — showed not one
	# of the seven. Three units inboard of the tips they are visible through the
	# gap from any horizontal bearing the bank itself does not occlude, and they
	# are STILL between two fins 0.25 m thick, so the glow is light coming out
	# of a machine rather than a lamp stuck on its side.
	#
	# THE STAIRCASE IS FITTED TO THE BANK RATHER THAN STEPPED BY A CONSTANT.
	# A fixed rise per gap puts the top panel 3 m above the fins on the large
	# core, where there are seven gaps and 6.2 m of bank: the run is solved so
	# the last panel ENDS at the top of the bank at every size, which is also
	# what keeps the pulse's travel proportional to the machine's height.
	var gaps: int = s.fins - 1
	var ret_gaps: int = s.ret - 1
	for i in gaps:
		var gx0: int = s.p0 + i * s.fp + s.ft + 1
		var gx1: int = s.p0 + (i + 1) * s.fp - 1
		# THE LATER HALF OF ONE RUN. The return bank on the -X face carries
		# steps 0 .. ret_gaps-1 and this face carries the rest, so the climb
		# that starts at the corner here is the SAME climb that arrived at it.
		var z := _step(s, ret_gaps + i)
		_lit.append(_later_box(Vector3(u(gx0), u(ylo - s.fd + 3), u(z.x)),
				Vector3(u(gx1), u(ylo - s.fd + 8), u(z.y)), SCREEN_TEX, u((z.x + z.y) / 2)))


## THE RETURN: the bank, and the run in it, turning the -X/-Y corner.
##
## The human saw round two lit, liked it, and asked for one thing — "can we
## have the glowing lines bit extend on two sides of it". TWO ADJACENT faces
## and not two opposite ones, so it stays asymmetric (two of four), so it reads
## as ONE run climbing AROUND the machine rather than as two decorations, and
## because a run that turns the corner is visible from the approach bearing AND
## from the flank. That last one matters: the previous round's open question was
## whether the whole composition had to be turned 90 degrees because its richest
## elevation faced away from the approach. It does not, now.
##
## IT IS THE SAME COMPONENT, NOT A SECOND IDEA. Same fins, same depth, same
## 3-units-inboard-of-the-tips rule for the panels. A glowing line on a bare
## face would read as a sticker where the first leg reads as light inside a
## machine, and the two would not be one run.
##
## THE RETURN CARRIES THE LOW STEPS, which is forced and happens to be right.
## The main bank climbs away from the corner toward +X, so its lowest step is
## at the corner; the return therefore has to arrive there, and it does — it
## starts low at the secondary mass and climbs to meet it. Read as a whole, the
## pulse now leaves the glands in the tray, climbs the -X face, turns the
## corner, and carries on up the flank to the shelf lip and the crown.
##
## WHERE IT STOPS IS WHERE THE BRACKET LANDS. The inner raking strut has to
## bear on this same face — it is the only part of the mass's -X elevation that
## is not behind the secondary mass — so the bank stops 14 units short of it and
## the strut passes through the gap, which looks like what it is.
func _return_bank(s: Dictionary) -> void:
	var ylo: int = -s.by + 8 + s.fd
	var z0: int = GROUND_U + 4
	var z1: int = s.sh - 10
	var w2: int = s.s_y0 - STRUT_GAP - ylo
	if w2 < s.ret * s.ft + (s.ret - 1) * 4:
		# Every early return warns. Too narrow a strip and the return would be
		# fins with no gaps in them, i.e. no run at all, and the first leg would
		# quietly become the only one.
		push_warning("build_core_relay: only %.2f m of -X face is clear of the secondary mass, so the return bank has nowhere to run" % u(w2))
		return
	var g2: int = (w2 - s.ret * s.ft) / maxi(1, s.ret - 1)
	var pitch: int = s.ft + g2
	for i in s.ret:
		var y: int = ylo + i * pitch
		_trim.append(_later_box(Vector3(u(s.p0 - s.fd), u(y), u(z0)),
				Vector3(u(s.p0), u(y + s.ft), u(z1)), PLATE_TEX))
	for k in s.ret - 1:
		var gy0: int = ylo + k * pitch + s.ft + 1
		var gy1: int = ylo + (k + 1) * pitch - 1
		# GAP 0 IS AT THE CORNER, so it takes the HIGHEST of the return's steps
		# and hands the run to the main bank at the same height it left off.
		var z := _step(s, s.ret - 2 - k)
		_lit.append(_later_box(Vector3(u(s.p0 - s.fd + 3), u(gy0), u(z.x)),
				Vector3(u(s.p0 - s.fd + 8), u(gy1), u(z.y)), SCREEN_TEX, u((z.x + z.y) / 2)))


## Step `i` of the single run that crosses both faces, as (bottom, top) in
## units. The run is fitted to the machine rather than stepped by a constant:
## the last panel ENDS at the top of the bank at every size, which is what
## keeps the pulse's travel proportional to the height of the thing it is
## climbing.
func _step(s: Dictionary, i: int) -> Vector2i:
	var base: int = GROUND_U + 6
	var span: int = s.sh - 14 - base
	var panel: int = int(round(float(span) * 0.45))
	var n: int = (s.ret - 1) + (s.fins - 1)
	var rise: int = int(float(span - panel) / float(maxi(1, n - 1)))
	var a: int = base + i * rise
	return Vector2i(a, mini(a + panel, s.sh - 14))


## THE CABLE TERMINATIONS: three of them along the secondary mass's shoulder,
## each a bushing, a horizontal run out over the tray, a junction and a vertical
## trunk into a gland in the floor.
##
## THIS IS THE FICTION, and GAMEPLAY's section 1 is unambiguous about it: a core
## is a relay, not a server cupboard. It holds a territory; it does not sit in
## one. Both earlier builds drew STORAGE and both read as architecture. What is
## drawn here is what CONNECTS — and taking the core is taking the area's
## wiring.
##
## EVERY JOINT IS AXIS-ALIGNED, which is not an aesthetic choice. pipe() caps a
## run with a plane perpendicular to its own axis, so a SLOPED cable landing on
## a horizontal gland top dips into it by r·tan(angle) and probe_map_overlap
## reports it. A horizontal run into the side of a junction box and a vertical
## drop out of its bottom share planes with it exactly, and brush_overlaps
## erodes a shared plane to nothing.
func _terminations(s: Dictionary) -> void:
	var yhi: int = s.by - 18
	var face: int = s.p0 - s.s_len            # the secondary mass's -X face
	var top: int = s.s_top
	var r: float = u(maxi(3, s.ft) + 1) * 0.5
	var span: int = yhi - s.s_y0
	var bush_x: int = face + s.s_len / 5
	# HALFWAY BETWEEN THE MASS AND THE BUND EDGE. A gland under the mass's own
	# footprint would be a cable disappearing into the roof of the thing it is
	# feeding; one at the rim would be in the bund wall. The tray between them
	# is the only place it can land, and it is the open ground the cantilever
	# flies over, so the eye reads cable, floor, overhang in one travel.
	var gland_x: int = face - (s.bx + face) / 2
	for i in 3:
		# EVENLY SPACED IN THE MIDDLES OF THREE EQUAL SHARES, not on the quarter
		# lines. A quarter-line spacing puts the three only 0.28 m apart on the
		# small core, where a gland is 0.36 m across: the glands, the junctions
		# and the lit collars all interpenetrated their neighbours, and
		# brush_overlaps reported six of the eight pairs from that one constant.
		var y: int = s.s_y0 + span * (2 * i + 1) / 6
		var yc: float = u(y)
		# The bushing: a stem and a wider cap, straight off compute_transformer.
		var cap_z: float = u(top) + u(s.s_len) * 0.26
		_trim.append(_later_call(func() -> void:
				cylinder(Vector3(u(bush_x), yc, u(top)), r, u(s.s_len) * 0.26, 6, PLATE_TEX), NAN))
		_paint.append(_later_call(func() -> void:
				cylinder(Vector3(u(bush_x), yc, cap_z), r * 1.45, u(s.s_len) * 0.07, 6, BAND_TEX), NAN))
		# Out over the tray edge, into a junction, and straight down. The jumper
		# stops 1.3 r short of the bushing axis and starts 1.6 r out from the
		# junction's, so every piece BUTTS its neighbour instead of entering it:
		# pipe() and cylinder() cap a run with a plane perpendicular to its own
		# axis, and the hull of a hexagon reaches further than its flats do.
		var hz: float = u(top) + u(s.s_len) * 0.12
		var jx: float = u(gland_x)
		var x_end: float = u(bush_x) - r * 1.3
		var x_start: float = jx + r * 1.6
		_trim.append(_later_call(func() -> void:
				log_x(Vector3((x_start + x_end) * 0.5, yc, hz - r), r, x_end - x_start, 6, PLATE_TEX, "x"), NAN))
		_trim.append(_later_call(func() -> void:
				box(Vector3(jx - r * 1.6, yc - r * 1.6, hz - r * 1.9), Vector3(jx + r * 1.6, yc + r * 1.6, hz + r * 1.2), PLATE_TEX), NAN))
		_trim.append(_later_call(func() -> void:
				cylinder(Vector3(jx, yc, u(GROUND_U + 6)), r, hz - r * 1.9 - u(GROUND_U + 6), 6, PLATE_TEX), NAN))
		# THE GLAND, AND IT IS THE BOTTOM OF THE PULSE. A collar in the tray
		# floor with a lit ring on it: the lowest lit element on the object, so
		# the travelling band starts in the WIRING and climbs into the machine
		# rather than appearing halfway up a mast.
		_trim.append(_later_call(func() -> void:
				cylinder(Vector3(jx, yc, u(GROUND_U)), r * 1.7, u(4), 6, PLATE_TEX), NAN))
		_lit.append(_later_call(func() -> void:
				cylinder(Vector3(jx, yc, u(GROUND_U + 4)), r * 1.5, u(2), 6, SCREEN_TEX), u(GROUND_U + 5)))


## THE CANTILEVERED LANDING SHELF, which is the asymmetry, the overhang and the
## pad contract in one move.
##
## THE PAD'S +X EDGE IS THE UPPER STAGE'S -X FACE, BY CONSTRUCTION. That is how
## "nothing above the pad" is guaranteed rather than measured: the only thing on
## this model that rises past the shelf is the upper stage, and the pad stops
## exactly where it starts. Nothing a later variant adds may go on the pad or
## over it, at any size, ever.
##
## THE SLAB RUNS PAST THE PAD ON THE LARGE CORE (`ext`), because a 2.6 m pad on
## a 12.4 m machine is a small patch and an overhang the same length as its
## bearing reads as a step rather than as a cantilever. The pad sits on the far
## end of the slab and the mass is behind it.
##
## AND THIS IS WHY THE SMALL CORE IS NOT A MUSHROOM. Round one put the constant
## 2.6 m cap on top of a 4.2 m stem, so the head was wider than the mast was
## tall and the thing read as a bird table. Here the same constant pad sits
## BESIDE the mass at two thirds height, with the crown going on up past it: the
## cap is no longer the top of the object and no longer on its axis.
func _shelf(s: Dictionary) -> void:
	var sh: int = s.sh
	var xb: int = s.p0 + s.b_in                  # the upper stage's -X face
	# THE PAD STOPS PAD_GAP SHORT OF THE UPPER STAGE'S FACE, and that 0.06 m is
	# not a margin, it is the proudness of the crown slot. _over_pad caught it:
	# a lit plate standing two units off that face is two units OVER the pad,
	# and "nothing above it" is a contract the TICK is built against rather
	# than a figure of speech. Anything else ever hung on that face has to be
	# thinner than this gap or the build fails, which is the point.
	var px0: int = xb - PAD_GAP - PAD_U * 2 - s.ext  # the pad's -X edge
	var x0: int = px0 - LIP_U                    # the slab's free end, LIP_U further out
	var ylo: int = -s.by + 8 + s.fd
	var y0: int = -s.by                          # flush with the bund's -Y edge
	var y1: int = y0 + PAD_U * 2
	var dt: int = sh + DECK_U                    # THE PAD SURFACE
	var px1: int = px0 + PAD_U * 2               # the pad's +X edge

	_dock = u(dt)
	# THE DOCK POINT, IN GODOT COORDINATES, written into the .map as a comment
	# and turned into a `Dock` Marker3D by the dress pass.
	#
	# IT IS NOT DERIVABLE ANY MORE AND THAT IS A BREAKING CHANGE.
	# holdable_core.gd::_dock_y() returns [4.2, 7.0, 12.4] off size_tier — the
	# top of a core whose cap was CENTRED, which this one's is not: the pad is
	# off-axis on a shelf at two thirds height. Its own comment says
	# "placeholder until the real cores carry a dock marker". This is that
	# marker, so there is something true to wire to; the wiring is GAMEPLAY's.
	_dock_at = Vector3(u(y0 + PAD_U), u(dt), u(px0 + PAD_U))
	box(Vector3(u(x0), u(y0), u(sh)), Vector3(u(xb), u(y1), u(dt)), PLATE_TEX)

	# THE PAD IS AT THE SLAB'S FREE END, not against the mass. `ext` is slab
	# BEHIND the pad, so the drone sits out at the tip of the overhang with the
	# machine behind it — which is the picture — rather than tucked into the
	# corner with the slab reaching past it into nothing.
	#
	# KERBS ON THE TWO INBOARD EDGES ONLY. The TICK clamps four legs 0.37 m
	# OUTSIDE the pad edge, so the two edges it comes in over — -X and -Y, which
	# are also the two the player sees — are left clean, and the two toward the
	# machine get the kerb. Trim, so nothing on the pad is solid.
	_trim.append(_later_box(Vector3(u(px1 - 4), u(y0), u(dt)), Vector3(u(px1), u(y1), u(dt + KERB_U)), PLATE_TEX))
	_trim.append(_later_box(Vector3(u(px0), u(y1 - 4), u(dt)), Vector3(u(px1 - 4), u(y1), u(dt + KERB_U)), PLATE_TEX))
	# The four landing lugs, the TICK's designed interface, inboard of the pad
	# corners. Trim: a navmesh island at 8 m is a place the planner will try to
	# send somebody.
	for lx: int in [px0 + 9, px1 - 9]:
		for ly: int in [y0 + 9, y1 - 9]:
			_trim.append(_later_box(Vector3(u(lx - 3), u(ly - 3), u(dt)),
					Vector3(u(lx + 3), u(ly + 3), u(dt + LUG_U)), PLATE_TEX))

	# TWO RAKING STRUTS under the overhang, from low on the mass's -X face out
	# to the slab's underside at its free end. A cantilever with nothing under
	# it reads as a mistake; a bracket is what says the overhang is DESIGNED.
	#
	# BOTH ARE KEPT CLEAR OF THE SECONDARY MASS'S -Y FACE, which is what the
	# open quarter of the tray is for and the whole reason that mass hugs +Y: a
	# strut spaced evenly across the pad put its inboard one straight through
	# the mass at two sizes out of three.
	var drop: int = int(round(float(sh - GROUND_U) * 0.42))
	for sy: int in [y0 + 10, s.s_y0 - STRUT_GAP + 2]:
		var a := sy
		var b := sy + 8
		_trim.append(_later_call(func() -> void:
				_hexa([Vector2(u(x0 + 10), u(a)), Vector2(u(s.p0), u(a)), Vector2(u(s.p0), u(b)), Vector2(u(x0 + 10), u(b))],
						[u(sh - 8), u(sh - drop - 8), u(sh - drop - 8), u(sh - 8)],
						[u(sh), u(sh - drop), u(sh - drop), u(sh)], PLATE_TEX), NAN))

	# THE LIT SHELF LIP, on the outside of the slab's free end, under the pad
	# surface. The travelling band leaves the fin bank and arrives HERE, at the
	# tip of the overhang, which is what makes the pulse read as going somewhere
	# rather than breathing.
	_lit.append(_later_box(Vector3(u(x0 - 2), u(y0 + 6), u(sh + 3)),
			Vector3(u(x0), u(y1 - 6), u(dt - 3)), SCREEN_TEX, u(sh + DECK_U / 2)))
	# A PAINTED EDGE on the slab's -Y face: faction colour at the height the eye
	# meets it from the approach, on a face the clamp never touches. HALF THE
	# SLAB AND 0.16 m OF IT — the first pass ran the full length at 0.25 m and
	# it photographed as a lit sign slung under the shelf, which is area rather
	# than a legible place and is exactly what got the second build rejected.
	_paint.append(_later_box(Vector3(u(x0 + 6), u(y0 - 2), u(sh + 4)),
			Vector3(u(x0 + 6 + PAD_U), u(y0), u(sh + 9)), BAND_TEX))
	# THE CROWN SLOT: one lit element high on the upper stage's stepped -X face,
	# the top of the pulse's run. ONE, not a course of them — a repeat here is
	# the band language the human threw out.
	var by0: int = ylo + s.b_yin
	var ct: int = s.top - s.drop
	#
	# ITS FOOT IS HELD OFF THE SHELF, and that is a measured clearance rather
	# than a margin: the upper stage's -X face is also the back of the shelf, so
	# a slot sized as a fraction of the crown alone ran down THROUGH the slab
	# and its kerb on the small core, where there is only 1.3 m between the pad
	# surface and the crown at all.
	#
	# AND IT IS A SLOT, NOT A PANEL. The first lit pass ran it across the whole
	# face: 2.2 m by 3.4 m of emissive amber on the large core, which
	# photographed as a backlit poster — the same fault round one's console
	# plate was pulled for, arriving in a different place. At 42% of the face
	# and pushed to the -Y edge it is still the thing that carries ownership at
	# forty metres (core_skel_med_far.png is the test) and it is no longer the
	# thing the eye lands on first at six.
	var slot_lo: int = maxi(dt + KERB_U + 6, ct - (s.top - sh) / 2)
	var slot_hi: int = ct - 8
	var slot_y0: int = by0 + 8
	var slot_y1: int = slot_y0 + 10 + s.b_yin / 3
	_lit.append(_later_box(Vector3(u(xb - 2), u(slot_y0), u(slot_lo)),
			Vector3(u(xb), u(slot_y1), u(slot_hi)), SCREEN_TEX, u((slot_lo + slot_hi) / 2)))
	# AND ONE MORE ON THE -Y FLANK, tall where the approach face is short: the
	# upper stage stands clear of the shelf on that side, so the slot runs the
	# whole way from the step to the collar — 2.9 m of it on the large core
	# against 3.3 m of face. It is the TOP OF THE CLIMB: glands, fin bank, shelf
	# lip and then this, all on one flank, so the pulse travels up ONE elevation
	# instead of jumping between faces where no eye can follow it.
	var cs0: int = sh + 6
	var cs1: int = ct - 14
	_lit.append(_later_box(Vector3(u(xb + 4), u(by0 - 2), u(cs0)),
			Vector3(u(xb + 6 + s.b_yin / 3), u(by0), u(cs1)), SCREEN_TEX, u((cs0 + cs1) / 2)))


# ── deferred brushes, so the entity grouping can be written last ────────────

## A box recorded rather than drawn. `y` is the height core_pulse.gd reaches
## the piece at, and NAN means "never pulses".
func _later_box(a: Vector3, b: Vector3, tex: String, y: float = NAN) -> Dictionary:
	return {"call": func() -> void: box(a, b, tex), "y": y}


## The same, for anything that is not a box — a cylinder, a prism, a wedge.
## Round one only ever deferred boxes; a relay has round fittings on it, and a
## Callable is the only way to put a cylinder in an entity group that has not
## started being written yet.
func _later_call(c: Callable, y: float) -> Dictionary:
	return {"call": c, "y": y}


## One entity of `classname` holding `items`, tagged so the dress pass can find
## it. An empty list writes nothing rather than an empty entity.
func _emit(classname: String, tag: String, items: Array) -> void:
	if items.is_empty():
		push_warning("build_core_relay: nothing was built for '%s', so it was left out of the file" % tag)
		return
	_entities.append({"at": _brushes.size(), "classname": classname, "tag": tag})
	if classname == "func_detail_illusionary" and _ghost_from < 0:
		_ghost_from = _brushes.size()
	for it: Dictionary in items:
		(it["call"] as Callable).call()


## block_buildings.gd's _map_text, plus the tag on the `// entity N` comment.
##
## OVERRIDDEN RATHER THAN EXTENDED because block_buildings.gd is a shared file
## that three lanes work in, and the tag is of no use to any other piece in the
## kit.
func _map_text() -> String:
	var lines := PackedStringArray(["// Game: Roboto", "// Format: Valve",
			"// core:dock %.4f %.4f %.4f" % [_dock_at.x, _dock_at.y, _dock_at.z], "// entity 0", "{",
			"\"mapversion\" \"220\"", "\"wad\" \"\"", "\"classname\" \"worldspawn\""])
	var first: int = _brushes.size() if _entities.is_empty() else _entities[0].at
	for b in range(0, first):
		lines.append_array(_brush_text(b))
	lines.append("}")
	for i in _entities.size():
		var e: Dictionary = _entities[i]
		var until: int = _brushes.size() if i == _entities.size() - 1 else _entities[i + 1].at
		if until <= e.at:
			continue
		var tag: String = e.get("tag", "")
		lines.append_array(["// entity %d%s" % [i + 1, ("  " + tag) if tag != "" else ""],
				"{", "\"classname\" \"%s\"" % e.classname])
		for b in range(e.at, until):
			lines.append_array(_brush_text(b))
		lines.append("}")
	return "\n".join(lines) + "\n"
