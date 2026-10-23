extends "res://tools/block_industrial.gd"

# ─────────────────────────────────────────────
# THE COMPUTE CORE — THE SKELETON, AS BRUSH GEOMETRY. ROUND ONE: NO HEAD.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/build_core_skeleton.gd -- maps/blocks [--force]
#
# Writes maps/blocks/compute/compute_core{_small,,_large}.map — REPLACING the
# shipped trio, which was block_industrial.gd's core_column() scaled three ways.
# Follow it with:
#
#   tools/block_prefabs.gd -- maps/blocks/compute --only=compute_core --force
#   tools/core_skeleton_dress.gd                          (Paint / Lit / pulse)
#
# The dress pass is NOT optional and NOT cosmetic. FuncGodot assigns materials
# by texture name, so a freshly built prefab has no faction colour and no
# pulse; the dress pass is what turns the tagged entities into the Paint and
# Lit groups core_signal.gd and core_pulse.gd need. It is re-appliable — run it
# again after any block_prefabs rebuild, which is a rebuild that otherwise
# throws the dressing away.
#
# ─────────────────────────────────────────────
# WHY THERE IS NO HEAD ON THIS
#
# docs/briefs/COMPUTE_CORE_ART.md governs, and docs/concepts/archive/CORE_LOOK3.md is
# the study it came off: five variants (TRUNK / UPLINK / PATCH / ANCHOR /
# RELAY) on ONE SHARED BODY. The human was offered the five and chose "build
# the skeleton, decide after" — because every fault across three rejected
# rounds was found by looking at a lit render and none of them would have shown
# in outline.
#
# So this file builds the shared body and stops: deck, mast, interlacing,
# flare, corbel, cap, console pedestal. No cross-arms, no dish, no tie-rods, no
# cable trunks. DO NOT ADD GEAR HERE TO SHOW WILLING — a fourth rejected build
# is the specific thing this round exists to prevent. When a variant is chosen
# its gear goes in a `_gear_<variant>()` called beside _console() and nothing
# else in this file has to move.
#
# ─────────────────────────────────────────────
# THE CONTRACTS, which are not this file's to adjust
#
#   * HEIGHTS 4.20 / 7.00 / 12.40, FOOTPRINTS 3.28 / 4.43 / 6.30, MASTS
#     0.90 / 1.30 / 1.95 across.
#   * THE CAP IS 2.60 m ACROSS AT EVERY SIZE AND COMPLETELY CLEAR. The TICK
#     drone is built and approved and clamps four legs 0.37 m outside its edge;
#     that one clamp has to be correct on a 4.2 m core and a 12.4 m one alike,
#     which is the constancy the chosen concept won on. NOTHING GOES ON THE
#     CAP, at any size, in any variant, ever.
#   * PAINTED RUN NEAR 17-18% OF THE MAST. _report prints the measured share,
#     because that is the number the second rejected build never took.
#   * CONSOLE ON THE -Z FACE (Godot), a PEDESTAL and not a recess. Screen 1.55,
#     kick rail 1.02, brow 1.92.
#   * THIN, AND NOTHING VERTICAL ON THE MAST. A grid needs two directions; this
#     gets one. The first rejected build read as a building because it had both.
#
# AND THE GRID IS 1/32 m, WHICH IS THE ONE CONTRACT THAT COULD NOT SURVIVE.
# block_buildings.gd's _snap rounds every vertex to a whole unit of 1/32 m, so
# this file is written in UNITS through u() and the numbers above are the
# nearest achievable ones. 4.20 m is 134.4 units and 12.40 m is 396.8, so
# neither height is expressible as brush geometry at all; 3.28 m is 104.96
# units and a cap centred on an axis needs an EVEN unit count, so the
# footprints move too. Every residual is under 3 cm and _report prints what was
# actually built. The study was primitives, which have no grid — this is the
# cost of the deliverable being brushes, and it is not recoverable.
#
# ─────────────────────────────────────────────
# AXES. FuncGodot maps map (x, y, z) to Godot (y, z, x):
#
#   map +X -> Godot +Z          map +Y -> Godot +X          map +Z -> Godot +Y
#
# So the console face, which the brief puts on Godot -Z, is built on map -X
# here, and "height" throughout this file is map Z. Re-deriving this by hand is
# how Polaris came out with its ring road at right angles to its own corners.
#
# ─────────────────────────────────────────────
# THE MAST IS A STACK, AND THAT IS WHY NO TWO BRUSHES OVERLAP
#
# A band around a column is either four plates or a segment of the column, and
# there is no third option: one full-section box standing proud of a
# full-height mast interpenetrates it, which probe_map_overlap reports and
# TrenchBroom hates. Four plates a band would be 116 brushes of ring on the
# large core against a segmented mast's 31. So the mast is built as bare
# segments with the band and reveal heights LEFT OUT, and each band or reveal
# fills its own slot as one brush.
#
# THE COST, STATED RATHER THAN HIDDEN: those slots are
# func_detail_illusionary, so the mast's collision has a 0.22 m gap at each
# painted band and a 0.125 m gap at each reveal — about a quarter of the large
# core's mast height, each gap shielded above and below by a band standing
# proud of it. The study's own collision was a handful of boxes and had the
# same gaps, so this matches what was accepted rather than introducing
# something. If a human decides a core must stop a bullet at every height the
# fix is one word: PAINT_CLASS and LIT_CLASS become "func_detail", at the price
# of one concave collision shape per band.
#
# ─────────────────────────────────────────────
# THE ENTITY STRUCTURE IS THE REAL DELIVERABLE
#
# The shipped core was ALL worldspawn, so FuncGodot baked it to one
# MeshInstance3D and nothing on it could be recoloured — which is why
# Env/world_objects/core_signal.gd still fakes owner colour with a procedural
# collar and band, and why its own header asks for art that replaces it.
#
#   * every painted band is ITS OWN ENTITY, tagged `core:paint`
#   * every lit slot is ITS OWN ENTITY, tagged `core:lit y=<height>` — one per
#     band and NOT one for all of them, because core_pulse.gd runs a band of
#     light up the mast and needs them addressable by height
#   * the fine metal trim is one shared no-collision entity, `core:trim`
#   * everything else is worldspawn and carries the collision
#
# The tags go into the .map as comments on the `// entity N` line. A comment
# rather than an entity property on purpose: the kit already writes those
# comment lines and FuncGodot provably ignores them, where an unregistered key
# on a registered solid class would be a guess. core_skeleton_dress.gd is the
# only thing that reads them.
# ─────────────────────────────────────────────

const OUT := {
	"compute_core_small": "small",
	"compute_core": "med",
	"compute_core_large": "large",
}

# ── the metal ───────────────────────────────────────────────────────────────
# metal_wall_3 is a DARK NAVY RIBBED sheet and all three reasons matter.
# FAC_ADVERSARY is warm amber, so navy is near its complement and the bands
# read at range — on metal_wall_1 or _4, both brown, amber sits on amber and
# the whole mechanism of this look dies. Its ribs are fine VERTICAL lines, so
# the mast is extruded metal at a glance without one modelled vertical member.
# And it is the sheet the paint is on too, so a painted band and a bare band
# are one material in two colours, which is what "interlaced colour /
# non-colour" literally asks for.
#
# NO CONCRETE ANYWHERE, and NOT metal_floor_3: the first rejected build put its
# shaft on concrete_tx_5, a transformer yard, and its cabinet on metal_floor_3,
# a perforated rack grille that tiles into a facade of windows at 12 m.
#
# 0.25 is units-per-texel, so a 256 px sheet tiles every 64 units — one tile
# per 2 m. The study found texel density was a real fault rather than a
# flourish: its first lit shot had the grated deck as four enormous polka dots
# and the cap as smeared planking, and nothing about that is visible in line
# art.
const MAST_TEX := "PSX_Textures/metal_wall_3@0.25"
## Riveted plate, a value lighter than the mast, so gear separates from the stem.
const PLATE_TEX := "PSX_Textures/metal_floor_1@0.25"
## Reads as breathing, at a grain fine enough to stay a texture.
##
## AND IT IS NOT ON THE STRUCTURE'S 0.25, WHICH IS A FAULT CARRIED OVER FROM
## THE STUDY RATHER THAN A PREFERENCE. grate_perf is a sheet of holes, so at
## one tile per 2 m a single perforation is about 15 cm across and the deck
## photographs as a field of enormous polka dots — look at the deck in
## docs/concepts/core_l3_trunk_med.png, which is the accepted study's own
## render and has it. 0.0625 is one tile per 0.5 m, which puts the holes at
## about 4 cm and lets the grating stay a texture, which is the whole reason
## this sheet was chosen over metal_floor_3.
const VENT_TEX := "PSX_Textures/grate_perf@0.0625"
## The painted bands: the mast's own sheet, recoloured by the dress pass.
const BAND_TEX := "PSX_Textures/metal_wall_3@0.25"
## THE LIT SLOTS, AND THIS IS A DELIBERATE OVERRIDE OF SECTION 5 OF GAMEPLAY'S
## BRIEF, made on measurement rather than taste.
##
## Their brief says glitch_tx_1. Measured, glitch_tx_1 is SATURATION 0.771 — a
## strongly hued texture — and the core has to carry FOUR faction colours:
## amber FAC_ADVERSARY for the Swarm, blue SIGNAL for the player, green
## FAC_HOME for Home Command and tyrian FAC_ARGUS for Argus. A 0.77-saturation
## grain cannot carry purple and amber both: adding a heavily hued grain onto a
## faction colour muddies it even under EMISSION_OP_ADD, which is the same
## failure section 7 warns about for MULTIPLY ("an amber core emits yellow-green
## speckle and an Argus core is unreadable") arriving by a different route.
##
## glitch_tx_neutral is that same image with the hue stripped and the exposure
## kept: saturation 0.771 -> 0.109, mean 0.183 -> 0.176, peak 0.561 unchanged.
## Value-only grain, so the faction colour genuinely owns the HUE and the
## texture owns the SPARKLE — which is what section 7 asks for in words.
## Everything else in sections 5 and 7 stands unchanged.
##
## 0.04 units-per-texel tiles a 256 px sheet every 10.24 units, about one tile
## per 32 cm. A 0.125 m reveal still carries several texels of grain across its
## length; at the structure's 0.25 it would be one flat colour and the data
## noise the ADD operator exists to preserve would never appear at all.
const SCREEN_TEX := "PSX_Textures/glitch_tx_neutral@0.04"

# ── the invariant numbers, in grid units of 1/32 m ──────────────────────────
## HALF-WIDTH OF THE LANDING PAD. THE RULER. Do not scale it: the TICK clamps
## it. 42 units is 1.3125, so the cap is 2.625 m across against the contract's
## 2.60 — 2.60 m is 83.2 units and a cap centred on the mast axis needs an even
## count, so 42 (2.625) and 41 (2.5625) are the candidates and 42 is nearer.
## 1.25 cm a side, and the TICK's clamp offset is unaffected to the millimetre
## it can be built at.
const PAD_U := 42
const LUG_U := 8          # 0.25 m, the lugs stand proud of the landing deck
const DECK_U := 11        # 0.34375 m landing deck
const KERB_U := 5         # 0.15625 m kerb round it
## Deck top, and where the mast starts. The study's 0.52 to the centimetre, and
## the centimetre matters: a 0.53 m sheer step is not something move_and_slide
## climbs, so the player is stopped OUTSIDE the deck — the only arrangement the
## 2 m InteractRaycast works in, because it does not register a hit that STARTS
## inside a volume.
const GROUND_U := 17      # 0.53125 m
## THE INTERLACE PITCH, and the one number this whole look turns on. Constant
## across the three sizes, so the band COUNT is the size cue and no variant
## needs a second one. 20 units is 0.625 m against the study's 0.62, and it
## reproduces the study's slot counts exactly: 4 / 8 / 17, hence 2 / 4 / 8
## painted rings.
##
## BAND DENSITY IS THE OPEN QUESTION THIS ROUND EXISTS TO ANSWER — 17 slots on
## the 12.4 m core, machine or ladder — and this constant is the whole dial.
const PITCH_U := 20
## Painted ring height inside that pitch: 7 units, 0.21875 m, about a third of
## the pitch. With the lit reveal in the middle of the bare slot the mast comes
## out about two thirds bare metal, and THAT RATIO IS THE FIX. The second build
## failed because its colour had no quiet to sit in.
const BAND_U := 7
## How far a painted ring stands proud of the mast each side. Small, because it
## has to be a BAND ON the mast and not a flange around it. It is also what the
## console cabinet butts against, so the cabinet and the bands share one face.
const OUT_U := 2          # 0.0625 m
## The lit slot: 4 units of aperture, set 1 unit back from the mast skin, so
## the mast segments above and below are its own lips.
##
## A SINGLE LIP IS ONLY RIGHT FOR ONE VIEWING ELEVATION and there is no one
## elevation — the player looks UP at a 12 m core from its foot and ACROSS at a
## 4 m one from forty metres. Recessed between two, the glow is visible through
## the aperture from anything inside about 65 degrees of horizontal and can
## never read as a lamp, because an emissive surface BEHIND the silhouette is
## light coming out of a machine by construction.
##
## SIX UNITS AND NOT FOUR, AND THE FIRST LIT SHOT IS WHY. At four the slots
## were invisible at rest — not dim, absent: an emissive strip 0.125 m tall on
## a 1.94 m mast is a few pixels at any distance a core is seen from, and in
## the first render the mast read as unbroken navy between the bands. The
## brightness is the study's calibrated 0.40 and is not this file's to raise
## (core_pulse.gd takes it to 0.96 at the crest, and above that the amber goes
## white), so the AREA is the dial that was available. Compare
## docs/concepts/core_l3_trunk_med.png, where the study's own reveals cannot be
## found either.
const SLOT_U := 6
const SLOT_BACK_U := 1
## How far below the top of the lugs the mast stops. 40 units is 1.25 m, and it
## is NOT free to move: it sets the mast run, which sets the slot count, and
## 40 is what reproduces the study's 4 / 8 / 17.
const NECK_DROP_U := 40

## mast half-width, deck half-width, top of the lugs — all in units.
##
## Deck halves 52 / 71 / 101 give footprints 3.25 / 4.4375 / 6.3125 against the
## study's 3.28 / 4.43 / 6.30. Tops 134 / 224 / 397 give 4.1875 / 7.00 /
## 12.40625 against 4.20 / 7.00 / 12.40. Mast halves 14 / 21 / 31 give
## 0.875 / 1.3125 / 1.9375 across against 0.90 / 1.30 / 1.95.
const SPEC := {
	"small": [14, 52, 134],
	"med": [21, 71, 224],
	"large": [31, 101, 397],
}

## func_detail_illusionary: its own Node3D and its own MeshInstance3D, drawn,
## not solid, not seen by the navmesh baker. The separate MeshInstance3D is the
## whole point — it is what makes a band recolourable at all.
const PAINT_CLASS := "func_detail_illusionary"
const LIT_CLASS := "func_detail_illusionary"

var _trim: Array = []
var _paint: Array = []
var _lit: Array = []


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/build_core_skeleton.gd -- maps/blocks [--force]")
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
			# twice. The shipped trio was verified byte-reproducible from
			# block_industrial.gd before this tool first overwrote it, so
			# nothing was lost then; that check is owed again next time.
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			continue
		_brushes = []
		_entities = []
		_ghost_from = -1
		_skeleton(OUT[nm])
		# EVERY BRUSH AGAINST EVERY OTHER, as solids, BEFORE the file is
		# written. Checking afterwards is whack-a-mole: each piece moved to
		# clear one clash lands on something else.
		var clashes := brush_overlaps()
		if not clashes.is_empty():
			print("FAIL  %s: %d overlapping brush pair(s), worst %s" % [nm, clashes.size(), clashes[0][2]])
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
	print("BLOCK CORE SKELETON DONE: %d written" % written)
	quit()


func _report(nm: String, tag: String) -> void:
	var spec: Array = SPEC[tag]
	var run: int = spec[2] - NECK_DROP_U - GROUND_U
	var slots := _slots(run)
	var rings := _rings(slots)
	var paint := 0
	var lit := 0
	for e: Dictionary in _entities:
		var t: String = e.get("tag", "")
		if t.begins_with("core:paint"):
			paint += 1
		elif t.begins_with("core:lit"):
			lit += 1
	print("      %-20s %3d brushes  %s" % [nm, _brushes.size(), _extent_text()])
	# THE QUIET, AS A NUMBER. This is the measurement the second build never
	# took and the one its rejection was about: how much of the mast's own run
	# is faction colour. The brief wants 17-18%.
	print("          mast %.3f sq · cap %.3f sq · %d slots · %d painted rings = %.1f%% of the %.2f m mast run · paint %d · lit %d entities · %d collision brush(es)"
			% [u(spec[0] * 2), u(PAD_U * 2), slots, rings,
					100.0 * float(rings) * u(BAND_U) / u(run), u(run),
					paint, lit, _entities[0].at if not _entities.is_empty() else _brushes.size()])


func u(n: int) -> float:
	return float(n) / UPM


func _slots(run: int) -> int:
	return maxi(3, int(round(float(run) / float(PITCH_U))))


## ODD SLOTS ARE PAINTED, so the mast always starts bare at the deck.
func _rings(slots: int) -> int:
	var n := 0
	for i in slots:
		if i % 2 == 1:
			n += 1
	return n


# ── the body ────────────────────────────────────────────────────────────────

## THE ORDER OF THE _emit CALLS AT THE BOTTOM IS THE ENTITY ORDER IN THE FILE,
## and the dress pass reads the file. block_buildings.gd's entity() splits on
## brush INDEX, so a group that has started cannot be gone back to — which is
## why every non-worldspawn brush is collected in _trim / _paint / _lit while
## the solids are drawn and written out afterwards.
func _skeleton(tag: String) -> void:
	var spec: Array = SPEC[tag]
	var mh: int = spec[0]       # mast HALF-width
	var rh: int = spec[1]       # deck HALF-width
	var top: int = spec[2]      # top of the lugs — the core's overall height
	var neck: int = top - NECK_DROP_U
	var run: int = neck - GROUND_U
	var slots := _slots(run)
	# Integer division, so the pitch is a whole number of units and every band
	# lands ON the grid rather than being rounded onto it by _snap. The
	# remainder goes into the top bare segment, which is the one place a few
	# millimetres cannot be read: it is under the flare.
	var pitch: int = run / slots

	_trim = []
	_paint = []
	_lit = []

	_deck(rh)
	_mast(mh, neck, slots, pitch)
	_head(mh, neck, top)
	_console(mh, rh)

	_emit("func_detail_illusionary", "core:trim", _trim)
	for p: Dictionary in _paint:
		_emit(PAINT_CLASS, "core:paint", [p])
	for l: Dictionary in _lit:
		_emit(LIT_CLASS, "core:lit" + ("" if is_nan(l["y"] as float) else " y=%.4f" % (l["y"] as float)), [l])


## THE DECK. A plinth with a wider grated plate on it, so there is an overhang
## shadow all the way round and it reads as a PLATFORM rather than a poured
## slab. Both courses are solid, so the whole thing is one 0.53 m sheer step —
## over the 0.5 m the navmesh baker will climb, with nothing in the 0.25-0.5 m
## band where the mesh says wall and the AI says step.
##
## AND IT IS NOT PAINTED, which is a deliberate reversal of the second build.
## That one put a 0.16 m amber lip right round its raft — the largest painted
## area on the model and, in the lit shot, a bright orange rectangle drawn on
## the floor that the eye finds before anything else on the core.
##
## A rim and four corner clamps, in plate, because a 6.3 m square of grating
## photographed as an empty black field with a machine standing in the middle
## of it: the deck read as a hole rather than as a surface. An edge and four
## corners is all an eye needs to call a surface a made thing. TRIM, so none of
## it is solid — a 0.1 m rim is in nobody's way but it is another collision
## brush on every one of the 42 cores the levels hold.
func _deck(rh: int) -> void:
	box(Vector3(-u(rh - 8), -u(rh - 8), -u(10)), Vector3(u(rh - 8), u(rh - 8), u(11)), PLATE_TEX)
	box(Vector3(-u(rh), -u(rh), u(11)), Vector3(u(rh), u(rh), u(GROUND_U)), VENT_TEX)
	for s: int in [-1, 1]:
		var e := _edge(rh, 5, s)
		_trim.append(_later(Vector3(e.x, -u(rh), u(GROUND_U)), Vector3(e.y, u(rh), u(GROUND_U + 3)), PLATE_TEX))
		_trim.append(_later(Vector3(-u(rh - 5), e.x, u(GROUND_U)), Vector3(u(rh - 5), e.y, u(GROUND_U + 3)), PLATE_TEX))
	# Inboard of the rim by three units rather than tucked into it: a clamp that
	# shares its edge with the rim interpenetrates it, and a rim-plus-clamp
	# corner reads as one lumpy fitting rather than two.
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var cx: int = sx * (rh - 18)
			var cy: int = sy * (rh - 18)
			_trim.append(_later(Vector3(u(cx - 10), u(cy - 10), u(GROUND_U)),
					Vector3(u(cx + 10), u(cy + 10), u(GROUND_U + 4)), PLATE_TEX))


## A `w`-unit strip hugging the `s` side of a square of half-width `half`,
## returned as (low, high) in metres. Typed out once because writing it inline
## four times is how an edge ends up on the wrong side of its own square.
func _edge(half: int, w: int, s: int) -> Vector2:
	if s > 0:
		return Vector2(u(half - w), u(half))
	return Vector2(-u(half), -u(half - w))


## THE MAST: a stack of plain ribbed boxes with a ladder of interlaced bands
## left out of it.
##
## THERE IS NOTHING VERTICAL ON IT. No corner posts, no fins, no pilasters, no
## recessed bays. The first rejected build had four posts and four fins
## crossing five shelf courses, and that is a grid; a grid is a facade. The
## ribs in metal_wall_3 are the only vertical line here and they are a texture,
## so they never become geometry at range. That is the whole of the anti-grid
## argument and it is the thing to protect if this file is edited.
##
## ODD SLOTS ARE PAINTED, EVEN SLOTS CARRY A LIT REVEAL, and the first and last
## slot are left bare — so the read up the tower is metal, PAINT, metal, GLOW,
## metal, PAINT, and the mast starts and ends on bare metal at every size.
##
## THE REVEAL SITS IN THE MIDDLE OF ITS BARE SLOT, which is a correction and
## not a decision. The study first put it directly under each painted band, for
## a good reason — an emissive box only reads as a line if every face but its
## edge is covered — and in the lit shot it was invisible, because the band
## stands proud, the shooting bearing looks DOWN at the core, and a line tucked
## under an overhang can only be seen from below it. In the middle of the slot
## it is seen from every elevation and the interlacing gets richer rather than
## busier.
func _mast(mh: int, neck: int, slots: int, pitch: int) -> void:
	var run: int = neck - GROUND_U
	if run < 52:
		push_warning("build_core_skeleton: %.2f m of mast, so the interlacing has nowhere to run" % u(run))
	# A plain box has no edge where it meets the deck; one shallow kick course
	# gives it one, in plate. IT IS THE BOTTOM SEGMENT OF THE STACK rather than
	# a collar on it — a collar round a column is four brushes or an overlap,
	# and this file has neither. At the bands' own proud section, so the console
	# cabinet butts one plane up the whole of its height.
	box(Vector3(-u(mh + OUT_U), -u(mh + OUT_U), u(GROUND_U)),
			Vector3(u(mh + OUT_U), u(mh + OUT_U), u(GROUND_U + 4)), PLATE_TEX)

	# Where the stack stops for a feature: [from, to, kind, centre].
	var cuts: Array = []
	for i in slots:
		var c: int = GROUND_U + pitch * i + pitch / 2
		if i % 2 == 1:
			cuts.append([c - BAND_U / 2, c - BAND_U / 2 + BAND_U, "paint", c])
		elif i != 0 and i != slots - 1:
			cuts.append([c - SLOT_U / 2, c - SLOT_U / 2 + SLOT_U, "lit", c])

	var z: int = GROUND_U + 4
	for cut: Array in cuts:
		var a: int = cut[0]
		var b: int = cut[1]
		if a > z:
			box(Vector3(-u(mh), -u(mh), u(z)), Vector3(u(mh), u(mh), u(a)), MAST_TEX)
		elif a < z:
			push_warning("build_core_skeleton: the band at %.2f m overruns the one below it — BAND_U is too tall for a %.2f m pitch" % [u(a), u(pitch)])
		if cut[2] == "paint":
			# PROUD, so the band is a band and not a change of texture. The
			# dress pass recolours exactly this brush and nothing else.
			_paint.append(_later(Vector3(-u(mh + OUT_U), -u(mh + OUT_U), u(a)),
					Vector3(u(mh + OUT_U), u(mh + OUT_U), u(b)), BAND_TEX))
		else:
			# SET BACK, so the segments above and below are the aperture's own
			# lips and the light is genuinely inside the machine.
			var e: int = mh - SLOT_BACK_U
			_lit.append(_later(Vector3(-u(e), -u(e), u(a)), Vector3(u(e), u(e), u(b)),
					SCREEN_TEX, u(cut[3] as int)))
		z = b
	if neck > z:
		box(Vector3(-u(mh), -u(mh), u(z)), Vector3(u(mh), u(mh), u(neck)), MAST_TEX)


## THE HEAD: a flare, a lit course under the corbel, the corbel, and the cap.
## Forty units from the mast top to the top of the lugs, allocated
## 5 / 4 / 10 / 2 / 11 / 8 — flare, lit course, corbel, lit rim, landing deck,
## lugs — so the overall height is exact by construction rather than measured
## afterwards and hoped about.
##
## THE FLARE IS NOT DECORATION. A 2.6 m cap on a 0.9 m mast overhangs by 0.85 m
## a side and without a transition the pad looks dropped on rather than
## carried. It is clamped to the corbel, so on the large core — where the mast
## is already 1.94 — it collapses into a thicker corbel instead of flaring out
## past the cap. It also reads as the PORT: a slim stem widening into a flat
## lugged head is a socket, which is the fiction. The TICK lands there.
##
## AND THE HEAD IS IN THE MAST'S OWN NAVY. The study's first lit render had the
## flare and corbel on plate, and because plate is a value lighter the head
## came away from the stem and photographed as a pale capital on a dark column
## — a stone pier, which is the exact word the rejection used about the second
## build. Only the LANDING DECK is plate, so the one light surface on the
## object is the one the TICK sits on, and the cap reads as a port.
func _head(mh: int, neck: int, top: int) -> void:
	var fh: int = maxi(mh + 2, mini(30, mh + 12))      # flare half-width
	var cw := 33                                       # corbel half-width
	box(Vector3(-u(fh), -u(fh), u(neck)), Vector3(u(fh), u(fh), u(neck + 5)), MAST_TEX)
	# THE TOP RUNG, in a recess between the flare and the corbel — where the
	# travelling band arrives and dies, which is what makes the pulse read as
	# going somewhere rather than breathing. Set back the same single unit the
	# mast reveals are, so it is the same detail and not a second idea.
	_lit.append(_later(Vector3(-u(fh - SLOT_BACK_U), -u(fh - SLOT_BACK_U), u(neck + 5)),
			Vector3(u(fh - SLOT_BACK_U), u(fh - SLOT_BACK_U), u(neck + 9)), SCREEN_TEX, u(neck + 7)))
	box(Vector3(-u(cw), -u(cw), u(neck + 9)), Vector3(u(cw), u(cw), u(neck + 19)), MAST_TEX)
	_pad(neck + 19, top)


## THE CAP, AND IT IS THE SAME CAP AT EVERY SIZE. 2.625 m across, lug tops
## exactly at `top`, level, and CLEAR. Nothing any variant adds later goes on
## it or over it.
func _pad(from: int, top: int) -> void:
	# A lit rim in the shadow of the deck's overhang: wider than the corbel and
	# narrower than the deck, so it is a line of light under the pad rather
	# than a lamp on top of it.
	_lit.append(_later(Vector3(-u(35), -u(35), u(from)), Vector3(u(35), u(35), u(from + 2)),
			SCREEN_TEX, u(from + 1)))
	var dt: int = top - LUG_U
	box(Vector3(-u(PAD_U), -u(PAD_U), u(from + 2)), Vector3(u(PAD_U), u(PAD_U), u(dt)), PLATE_TEX)
	# Kerbs and the four landing lugs — the TICK's designed interface. TRIM, so
	# nothing on the cap is solid: a navmesh island 12 m up is a place the
	# planner will try to send somebody.
	for s: int in [-1, 1]:
		var e := _edge(PAD_U, 4, s)
		_trim.append(_later(Vector3(e.x, -u(PAD_U), u(dt)), Vector3(e.y, u(PAD_U), u(dt + KERB_U)), PLATE_TEX))
		_trim.append(_later(Vector3(-u(PAD_U - 4), e.x, u(dt)), Vector3(u(PAD_U - 4), e.y, u(dt + KERB_U)), PLATE_TEX))
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var lx: int = sx * (PAD_U - 9)
			var ly: int = sy * (PAD_U - 9)
			_trim.append(_later(Vector3(u(lx - 3), u(ly - 3), u(dt)),
					Vector3(u(lx + 3), u(ly + 3), u(dt + LUG_U)), PLATE_TEX))


## Where the console cabinet's front face sits, measured from the axis on map
## -X, which is Godot -Z.
##
## IT IS A PEDESTAL AGAINST THE MAST, NOT A BAY CUT INTO IT, and that follows
## from "thin" rather than from taste. The second build cut a 0.49 m recess
## into a 1.50 m shaft; the same recess in a 0.90 m mast leaves 0.41 m of
## material and cuts the stem in two. A separate terminal cabinet plugged into
## the mast keeps the mast unbroken AND is better for the brief — a patch
## cabinet with a screen on it is a connectivity fitting; a hole in a wall is
## not.
##
## THE FORMULA IS RAYCAST ARITHMETIC. The player's capsule radius is 0.25 so
## the camera stops 0.25 m outside the deck edge, and test_character hangs the
## 2 m InteractRaycast 0.261 m FORWARD of the camera — so the ray starts
## 0.011 m INSIDE the footprint, which is the latent fault in the wrapper's
## header. On the large core a cabinet hugging the mast would be
## 3.16 - 0.97 = 2.19 m away and OUT of a 2 m ray, so it is pushed out to at
## least rh - 50 units. Reach comes out 0.74 / 1.13 / 1.56 m at the three
## sizes, all inside the ray with room to shuffle.
func _console_front(mh: int, rh: int) -> int:
	return maxi(mh + 14, rh - 50)


## THE CONSOLE. Screen centred at 1.55 — the player's eye is about 1.5, a 1.7 m
## capsule with the camera 0.65 above its middle — with a kick rail at 1.02 and
## a brow over it at 1.92. All three are contract heights.
func _console(mh: int, rh: int) -> void:
	var f: int = _console_front(mh, rh)
	var w: int = clampi(mh + 8, 18, 27)         # cabinet HALF-width
	var h := 65                                 # 2.03 m, the top of the body
	# Stopped at the bands' proud face rather than at the mast skin, so the
	# cabinet butts one plane and the bare segments keep a 0.0625 m shadow gap
	# behind it. Butting the skin instead would interpenetrate every painted
	# band below 2 m, which on the small core is one of only two.
	box(Vector3(-u(f), -u(w), u(GROUND_U)), Vector3(-u(mh + OUT_U), u(w), u(h)), PLATE_TEX)
	_trim.append(_later(Vector3(-u(f + 2), -u(w - 4), u(20)), Vector3(-u(f), u(w - 4), u(29)), VENT_TEX))
	# A BROW OVER THE SCREEN. A lit plate flush on a flat panel has no top edge
	# and reads as a sticker; a hood gives it one and says "stand here".
	_trim.append(_later(Vector3(-u(f + 9), -u(w + 2), u(60)), Vector3(-u(f), u(w + 2), u(63)), PLATE_TEX))
	_trim.append(_later(Vector3(-u(f + 5), -u(w * 9 / 10), u(31)), Vector3(-u(f), u(w * 9 / 10), u(34)), PLATE_TEX))
	# THE INTERFACE, AND IT IS THE ONE LIT PIECE THAT NEVER PULSES. No height
	# tag, so core_pulse.gd leaves it at rest forever: an interface that goes
	# dark for part of every cycle is a worse interface however good it looks,
	# and a constant face gives the travelling band a fixed reference to be
	# brighter and dimmer than.
	_lit.append(_later(Vector3(-u(f + 2), -u(w * 7 / 10), u(41)), Vector3(-u(f), u(w * 7 / 10), u(58)), SCREEN_TEX))
	# The cabinet joins the interlacing: one painted course on its head, at the
	# same section as a mast band, so the console is part of the ladder rather
	# than an object standing next to it. THIN — the study's first pass gave it
	# the mast band's full 0.22 and it photographed as a bright orange shelf at
	# the best-lit part of the model, the first thing the eye found on the whole
	# core, which is not what a kick-plate on a terminal should be.
	_paint.append(_later(Vector3(-u(f + 2), -u(w + 2), u(h)), Vector3(-u(mh + OUT_U), u(w + 2), u(h + 4)), BAND_TEX))


# ── deferred brushes, so the entity grouping can be written last ────────────

## A box recorded rather than drawn. `y` is the height core_pulse.gd reaches
## the piece at, and NAN means "never pulses" — the console plate, and only the
## console plate.
func _later(a: Vector3, b: Vector3, tex: String, y: float = NAN) -> Dictionary:
	return {"a": a, "b": b, "tex": tex, "y": y}


## One entity of `classname` holding `items`, tagged so the dress pass can find
## it. An empty list writes nothing rather than an empty entity.
func _emit(classname: String, tag: String, items: Array) -> void:
	if items.is_empty():
		push_warning("build_core_skeleton: nothing was built for '%s', so it was left out of the file" % tag)
		return
	_entities.append({"at": _brushes.size(), "classname": classname, "tag": tag})
	if classname == "func_detail_illusionary" and _ghost_from < 0:
		_ghost_from = _brushes.size()
	for it: Dictionary in items:
		box(it["a"], it["b"], it["tex"])


## block_buildings.gd's _map_text, plus the tag on the `// entity N` comment.
##
## OVERRIDDEN RATHER THAN EXTENDED because block_buildings.gd is a shared file
## that three lanes work in, and the tag is of no use to any other piece in the
## kit.
func _map_text() -> String:
	var lines := PackedStringArray(["// Game: Roboto", "// Format: Valve", "// entity 0", "{",
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
