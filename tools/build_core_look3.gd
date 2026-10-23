extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for the LOOK 3 compute core variants.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_core_look3.gd
#
# Writes fifteen scenes, five variants x three sizes:
#   res://maps/blocks/compute/core_l3_<variant>_{small,med,large}.tscn
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH — same contract as
# tools/build_core_f2.gd and tools/build_bulwark.gd. It is NOT a build step.
# Re-running it after a scene has been touched in the editor throws that work
# away, which is the --force map rebuild fault with a different file extension.
#
# NEW FILE ON PURPOSE. build_core_f2.gd is not edited and the F2 scenes are not
# touched: this is a third look, not a fourth round of notes on the second.
#
# ─────────────────────────────────────────────
# WHY A THIRD LOOK AT ALL
#
# Two builds were rejected. The approved concept (CORE_F_VARIANTS.md §2) was a
# slim shaft with a raft and four blades; four rounds of notes later — more
# places for faction colour, more computery, glowing not flat, pulsing — the
# shipped F2 photographs as a grid tower covered in orange. Every note was
# answered in isolation and the object was lost:
#
#   * there is no QUIET left for the colour to read against. Four full-height
#     amber fins plus an amber ground ring plus amber-lit rack strips means the
#     grey is the minority surface, and a faction colour that is most of the
#     object stops being a signal.
#   * the detail went from thin lines to a FULL GRID — four corner posts and
#     four fins (verticals) crossing five shelf courses (horizontals), skinned
#     in metal_floor_3, which is a perforated rack grille. At 12.4 m that is a
#     facade of windows.
#   * so it reads as a BUILDING rather than as a device.
#
# The direction for this look, verbatim:
#
#   "i think having interlaced color / non-color is good. i also think thin is
#    better. it should look metal, not concrete. it's a connectivity feature
#    that allows the player to take control of an area and its resources/compute
#    so it should feel like that"
#
# ─────────────────────────────────────────────
# THE FOUR THINGS, AND HOW EVERY VARIANT HERE ANSWERS THEM
#
# 1. INTERLACED COLOUR / NON-COLOUR. Every variant bands the mast: a painted
#    ring, then bare metal, then a painted ring. _band_slots divides the mast's
#    own run by a CONSTANT PITCH, so the band count is 4 / 8 / 17 slots and the
#    painted ones are 2 / 4 / 8 — more bands is visibly a bigger machine, for
#    free, and no variant needs a second size cue. The painted band is 0.22 of
#    a 0.60-0.65 pitch, so roughly TWO THIRDS OF THE MAST IS BARE METAL by
#    construction. That is the quiet F2 did not have, and it is a number rather
#    than an intention: _report prints the painted share of the mast run.
#
# 2. THIN. The masts are 0.90 / 1.30 / 1.95 against F2's 1.50 / 2.30 / 3.60 —
#    a little over half the girth at every size. NOTHING VERTICAL IS DRAWN ON
#    THE MAST AT ALL: no corner posts, no fins, no pilasters. The interlacing
#    is horizontal and the mast's own ribbed texture is the only vertical line
#    in it. That is the single biggest difference from F2 and it is what stops
#    the large core becoming a grid again: a grid needs two directions.
#
# 3. METAL, NOT CONCRETE. There is no concrete in this file. See THE METAL.
#
# 4. CONNECTIVITY. This is the brief and it drives the shapes. The last two
#    rounds built a server cupboard; a relay is not storage. The footprint of
#    every variant is a DECK carrying gear that visibly plugs the object into
#    the ground around it — cable trunks diving into the earth, an uplink dish,
#    a patch frame with jumpers, tie-arms pinned to anchors, a pylon's
#    cross-arms with lines slung off them. The mast is the same slim banded
#    stem in all five; WHAT IT IS PLUGGED INTO is the variant.
#
#    And the pulse is part of that answer rather than decoration. core_pulse.gd
#    climbs by height, and every variant puts its LOWEST lit piece in the ground
#    gear — a gland, a cabinet, an anchor — so the travelling band starts where
#    the object meets the territory, climbs the mast and dies at the pad. The
#    core is visibly drawing something up out of the ground it is standing on.
#
# ─────────────────────────────────────────────
# THE HARD CONSTRAINTS, which are contracts and not preferences
#
#   * THE CAP IS CONSTANT AND CLEAR. PAD is a HALF-width of 1.30 — a 2.60 m
#     lugged pad on the 4.2 m core and on the 12.4 m one alike, because the TICK
#     drone is built and approved and clamps exactly that at one size. Nothing
#     any variant adds sits on the cap or overhangs it.
#   * HEIGHTS ARE EXACTLY 4.20 / 7.00 / 12.40 and the generator prints its
#     measured box so that is checkable rather than claimed.
#   * A CONSOLE BAY ON THE -Z FACE at y 1.10-2.00. See _console.
#   * NO CSG ANYWHERE. csg_bake.gd only walks AI scenes, so a CSGShape3D in a
#     world object pays its 300 ms rebuild at every level load with nothing to
#     catch it. Every piece in this file is a box or a short cylinder; read each
#     one as a brush, which is what the .map cores are.
#   * FOOTPRINTS ARE F2'S, UNCHANGED: 3.28 / 4.43 / 6.30 m square. A nav rebake
#     is already owed and this look does not add a second one. Everything each
#     variant hangs off the mast — dish, arms, ties, trunks — is MEASURED TO
#     STAY INSIDE that square, which is why the dish radius and the cross-arm
#     reach are computed from `rw` rather than typed.
#
# ─────────────────────────────────────────────
# THE METAL, chosen rather than inherited
#
# F2's shaft was on concrete_tx_5, which is a transformer yard, and its cabinet
# body was metal_floor_3, a perforated rack grille — a dark square lattice that
# tiles into a facade of windows at 12 m. Both are gone.
#
#   MAST SKIN: metal_wall_3, a dark NAVY ribbed sheet. Three reasons, in order
#   of how much they matter:
#     a) it is COOL and dark, and FAC_ADVERSARY is Color(0.91, 0.63, 0.23) —
#        warm amber. Amber on navy is near-complementary and reads at range;
#        amber on metal_wall_1 or _4 (both brown) is amber on amber and the
#        bands disappear, which is the whole mechanism of this look dying.
#        It is also far from FAC_ARGUS tyrian, so an Argus core still reads.
#     b) its ribs are fine vertical lines, so the mast is EXTRUDED METAL at a
#        glance without a single modelled vertical member. That is how the
#        shipped compute_core gets its sleek lines on 22 brushes.
#     c) IT IS THE SAME SHEET THE PAINT IS ON. PAINT_TEX is metal_wall_3's PNG
#        too, so a painted band and a bare band are visibly the same material in
#        two colours — which is what "interlaced colour / non-colour" literally
#        asks for, rather than two different objects stacked alternately.
#
#   DECKS, PLATES, FITTINGS, PIPEWORK: metal_floor_1, a dark riveted plate.
#   Neutral grey, reads walkable and bolted, and it is lighter than the mast so
#   the ground gear separates from the stem instead of merging into one mass.
#
#   VENTED AND RECESSED FACES: grate_perf, a fine neutral perforated sheet.
#   It is the texture metal_floor_3 was reached for and should not have been:
#   same "this thing breathes" read, at a grain fine enough to stay a TEXTURE
#   instead of becoming geometry at range.
#
# NO metal_floor_3 and NO concrete anywhere in this file, deliberately.
#
# ─────────────────────────────────────────────
# WHAT IS CARRIED FORWARD FROM F2, BECAUSE IT WAS EARNED
#
#   * PAINT AND LIT AS TWO SEPARATE NAMED GROUPS under the root, each material
#     `resource_local_to_scene = true`. Without that, two cores in one level
#     share materials and the second owner to capture one repaints the other —
#     and two cores would be fighting over one pulse. An owner-colour pass must
#     walk BOTH lists and set `albedo_color` AND `emission` on both, or the
#     surface repaints and keeps glowing in the previous owner's colour.
#   * glitch_tx_1 ON EMISSION WITH EMISSION_OP_ADD. EMISSION = (emission_colour
#     + texture.rgb) * energy, so the faction colour is a FLOOR the data grain
#     sits on. On MULTIPLY the green-and-magenta texture recolours the glow and
#     an Argus core is unreadable.
#   * EMISSION ENERGY MULTIPLIES INTO CLIPPING, NOT BRIGHTNESS. FAC_ADVERSARY's
#     red is already 0.91, so 1.3 photographed pale. The rest levels here are
#     F2's measured ones.
#   * core_pulse.gd ON THE ROOT, unmodified. One looping tween per height
#     bucket, built in _ready, nothing per frame. Its pulse_y contract is the
#     only thing this file has to honour, and the banding suits it better than
#     F2's rack strips did: a ladder of discrete rings IS a travelling band.
#   * DO NOT WRITE emission_energy_multiplier on a Lit material from anywhere
#     else. core_pulse.gd animates exactly that float and reads the generator's
#     value as the rest level.
# ─────────────────────────────────────────────

const OUT_DIR := "res://maps/blocks/compute"

# ── textures ────────────────────────────────────────────────────────────────
const MAST_TEX := "res://textures/PSX_Textures/metal_wall_3.png"
const PLATE_TEX := "res://textures/PSX_Textures/metal_floor_1.png"
const VENT_TEX := "res://textures/PSX_Textures/grate_perf.png"
const PAINT_TEX := "res://textures/PSX_Textures/metal_wall_3.png"
const SCREEN_TEX := "res://textures/PSX_Textures/glitch_tx_1.png"

## PAINT IS PAINTED METAL. LIT IS THE GLOW. F2 ran the paint at 0.95 and the
## bands here came back at that value as flat plastic tape: emission at 0.95 with
## no emission texture is a near-constant amber across the face, so metal_wall_3's
## ribs — the whole reason this look is on a ribbed sheet — were swamped and the
## bands stopped looking like metal at all.
##
## 0.45 is the value where the ribs survive and the band is still unmistakably lit
## against the navy. It is a deliberate split of the two earlier notes rather than
## a reversal of either: "bright/glowing not flat" is now carried by the Lit
## reveals, which are the pieces that actually have a texture in their emission
## and therefore stay interesting at any energy, and "it should look metal" is
## carried by the paint. One constant moves it back if the human disagrees.
const PAINT_GLOW := 0.45
## REST level for the screens. core_pulse multiplies it by PEAK_GAIN at the crest.
const LIT_GLOW := 0.40
## The console plate alone sits brighter: it is the one lit face big enough to be
## read texel by texel, and at 0.40 glitch_tx_1's own green beat the amber under it.
const CONSOLE_GLOW := 0.85

const _Palette := preload("res://Character/hud/hud_palette.gd")
const PULSE_SCRIPT := "res://maps/blocks/compute/core_pulse.gd"

const DEG := PI / 180.0

# ── the invariant numbers ───────────────────────────────────────────────────
## HALF-WIDTH of the landing pad. THE RULER. Do not scale it; the TICK clamps it.
const PAD := 1.3
const LUG_H := 0.26
const DECK_T := 0.34
const KERB_H := 0.15
## Deck top — where the mast starts. F2's 0.52, kept to the centimetre so the
## interact arithmetic in build_core_f2.gd's header carries over unchanged: a
## 0.52 m sheer step is not something move_and_slide climbs, so the player is
## stopped OUTSIDE the deck, which is the only arrangement the 2 m
## InteractRaycast works in (it does not register a hit starting inside a volume).
const GROUND := 0.52

## THE INTERLACE PITCH, and it is the one number this whole look turns on.
## Constant across the three sizes, so the band COUNT is the size cue and no
## variant needs a second one. 0.62 gives 4 / 8 / 17 slots on mast runs of
## 2.42 / 5.22 / 10.62 m, hence 2 / 4 / 8 painted rings.
const BAND_PITCH := 0.62
## Painted ring height within that pitch. 0.22 of ~0.62 is roughly a third, and
## with the lit reveal tucked under it the mast is about two thirds bare metal.
## THAT RATIO IS THE FIX. F2 failed because the colour had no quiet to sit in.
const BAND_H := 0.22
## How far a painted ring stands proud of the mast on each side. Small, because
## the ring has to be a BAND ON the mast, not a flange around it.
const BAND_OUT := 0.05

## mast width, deck half-width, overall height, file tag.
## Deck half-widths give footprints 3.28 / 4.43 / 6.30 — F2's, to the centimetre.
const SIZES := [
	[0.90, 1.64, 4.2, "small"],
	[1.30, 2.215, 7.0, "med"],
	[1.95, 3.15, 12.4, "large"],
]

const VARIANTS := ["trunk", "uplink", "patch", "anchor", "relay"]

var _mast_mat: Material
var _plate_mat: Material
var _vent_mat: Material
var _paint_tex: Texture2D
var _screen_tex: Texture2D
var _pulse_script: Script

var _root: Node3D
var _structure: Node3D
var _paint: Node3D
var _lit_node: Node3D
var _hulls: Array


func _init() -> void:
	_paint_tex = load(PAINT_TEX)
	_screen_tex = load(SCREEN_TEX)
	_pulse_script = load(PULSE_SCRIPT)
	if _paint_tex == null or _screen_tex == null or _pulse_script == null:
		printerr("build_core_look3: a texture or the pulse script failed to load, so every piece would be bare")
		quit(1)
		return
	_mast_mat = _tex_material(MAST_TEX)
	_plate_mat = _tex_material(PLATE_TEX)
	_vent_mat = _tex_material(VENT_TEX)
	if _mast_mat == null or _plate_mat == null or _vent_mat == null:
		printerr("build_core_look3: a structure texture failed to load")
		quit(1)
		return

	for variant: String in VARIANTS:
		print("── %s ──" % variant.to_upper())
		for spec: Array in SIZES:
			var mw: float = spec[0]
			var rw: float = spec[1]
			var target: float = spec[2]
			var path: String = "%s/core_l3_%s_%s.tscn" % [OUT_DIR, variant, spec[3]]
			var node := _build(variant, mw, rw, target)
			var bb := _bounds(node, node)
			var packed := PackedScene.new()
			var err := packed.pack(node)
			if err != OK:
				printerr("build_core_look3: pack failed for %s (%s)" % [path, error_string(err)])
				quit(1)
				return
			err = ResourceSaver.save(packed, path)
			if err != OK:
				printerr("build_core_look3: save failed for %s (%s)" % [path, error_string(err)])
				quit(1)
				return
			_report(path, bb, mw, rw, target)
			node.free()
	quit(0)


func _report(path: String, bb: AABB, mw: float, rw: float, target: float) -> void:
	var neck: float = target - 1.26
	var slots := _band_slots(neck)
	var painted: int = 0
	for i in slots:
		if i % 2 == 1:
			painted += 1
	var run: float = neck - GROUND
	print("  %s" % path.get_file())
	print("      measured  W %.2f  H %.2f  L %.2f   (origin %.2f, %.2f, %.2f)"
			% [bb.size.x, bb.size.y, bb.size.z, bb.position.x, bb.position.y, bb.position.z])
	# THE QUIET, AS A NUMBER. This is the measurement F2 never took and the one
	# the rejection is about: how much of the mast's own run is faction colour.
	print("      mast %.2f sq · footprint %.2f sq · %d slots, %d painted rings — %.0f%% of the mast run is colour · paint %d · lit %d · meshes %d"
			% [mw, rw * 2.0, slots, painted,
					100.0 * float(painted) * BAND_H / run,
					_paint.get_child_count(), _lit_node.get_child_count(),
					_count_meshes(_root)])


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## THE ONLY WAY A MESH GETS MADE HERE, so nothing can ship bare. A
## MeshInstance3D with no material draws in the editor's default white and
## nobody notices until it is seen next to something that IS painted.
func _mesh(parent: Node, nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO, mat: Material = null,
		basis: Variant = null) -> MeshInstance3D:
	if mat == null:
		mat = _mast_mat
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	if basis != null:
		m.basis = basis
	else:
		m.rotation = euler
	m.position = at
	m.material_override = mat
	parent.add_child(m)
	m.owner = _root
	return m


func _part(nm: String, size: Vector3, at: Vector3, euler: Vector3 = Vector3.ZERO,
		mat: Material = null, solid: bool = false) -> MeshInstance3D:
	var m := _mesh(_structure, nm, _boxm(size), at, euler, mat)
	if solid:
		_hulls.append(m)
	return m


## A PAINTED piece: its own mesh, its own material INSTANCE, in the Paint node.
func _painted(nm: String, mesh: Mesh, at: Vector3, euler: Vector3 = Vector3.ZERO,
		basis: Variant = null) -> MeshInstance3D:
	return _mesh(_paint, nm, mesh, at, euler, _paint_material(), basis)


## FRESH PER PIECE, not shared. Resources are shared in this engine: one material
## handed to twenty meshes is one object, and a per-core owner colour would then
## repaint every core in the level. See CLAUDE.md's duplicate() rule.
func _paint_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _paint_tex
	m.albedo_color = _Palette.FAC_ADVERSARY
	# AND IT GLOWS. core_signal.gd's _emissive() is the project's pattern, minus
	# its SHADING_MODE_UNSHADED: that file applies unshaded to thin open tubes
	# which are pure signal, and unshaded flattens a band into a sticker.
	m.emission_enabled = true
	m.emission = _Palette.FAC_ADVERSARY
	m.emission_energy_multiplier = PAINT_GLOW
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_triplanar(m, 0.5)
	# PER INSTANCE, NOT PER SCENE. A sub-resource in a .tscn is ONE object shared
	# by every instantiation of that scene unless it says otherwise.
	m.resource_local_to_scene = true
	return m


## TRIPLANAR UVs, AND IT IS NOT A FLOURISH — it is the fix for a fault the first
## lit render of this look had in every piece.
##
## A BoxMesh maps 0..1 across EVERY face whatever its size, so a 256 px sheet is
## stretched over 2.6 m on the cap and tiled into a 0.2 m band on a ring, and the
## model comes back looking like it is built from several different materials at
## several different scales. The first shot of the TRUNK medium is the proof: the
## grated deck photographed as four enormous polka dots and the cap as smeared
## planking, while the mast — tall and narrow, so stretched the other way — looked
## correct. Nothing about that is visible in line art, which is why three rounds
## did not find it.
##
## Triplanar projects in the mesh's own LOCAL space instead, so texel density is a
## constant metres-per-tile across every piece regardless of its size, and it is
## rotation-safe — which matters here because the raking ties and the slung lines
## are placed by a Basis rather than by an axis. 0.5 is one tile per 2 m for
## structure; the screens want a much finer grain and set their own.
func _triplanar(m: StandardMaterial3D, scale: float) -> void:
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)


## A LIT piece — a screen, not paint. `at_y` is the height the pulse reaches it
## at; NAN means "this one never pulses", which is the console plate and only the
## console plate. `mat` lets several pieces at one height share one pulse unit.
func _lit(nm: String, mesh: Mesh, at: Vector3, euler: Vector3 = Vector3.ZERO,
		at_y: float = NAN, mat: StandardMaterial3D = null,
		basis: Variant = null) -> MeshInstance3D:
	if mat == null:
		mat = _lit_material()
	var m := _mesh(_lit_node, nm, mesh, at, euler, mat, basis)
	if not is_nan(at_y):
		m.set_meta(&"pulse_y", at_y)
	return m


## Faction-coloured screen. The glitch texture is on BOTH albedo and emission and
## the operator is ADD, so the faction colour is a floor the noise sits on rather
## than a tint the noise recolours. See the carried-forward note at the top.
func _lit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _screen_tex
	m.albedo_color = _Palette.FAC_ADVERSARY
	m.emission_enabled = true
	m.emission = _Palette.FAC_ADVERSARY
	m.emission_texture = _screen_tex
	m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	m.emission_energy_multiplier = LIT_GLOW
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# A FINER TILE THAN THE STRUCTURE: 3.0 is one tile per 33 cm, so a 0.06 m
	# reveal still carries several texels of data noise across its length. At the
	# structure's 0.5 a reveal that thin is one flat colour and the grain the ADD
	# operator exists to preserve never appears.
	_triplanar(m, 3.0)
	# Doubly required here: core_pulse.gd writes this material's energy, so two
	# cores sharing one would stutter.
	m.resource_local_to_scene = true
	return m


func _tex_material(path: String) -> StandardMaterial3D:
	var t := load(path) as Texture2D
	if t == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_triplanar(m, 0.5)
	return m


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cylm(radius: float, height: float, sides: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	return c


func _node(parent: Node, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	parent.add_child(n)
	n.owner = _root
	return n


## A basis whose local +Y runs along `dir`. Used for the raking ties and the
## slung lines: a box's own height axis is +Y, so this is the only rotation that
## lets a straight member be placed by its two ENDS rather than by an angle
## somebody worked out on paper and got wrong.
func _along(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if absf(d.dot(Vector3.UP)) > 0.999:
		return Basis.IDENTITY if d.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))


## A straight member between two points, of square section `t`.
func _strut(parent_painted: bool, nm: String, a: Vector3, b: Vector3, t: float,
		mat: Material = null) -> MeshInstance3D:
	var d: Vector3 = b - a
	var mesh := _boxm(Vector3(t, d.length(), t))
	var at: Vector3 = (a + b) * 0.5
	if parent_painted:
		return _painted(nm, mesh, at, Vector3.ZERO, _along(d))
	return _mesh(_structure, nm, mesh, at, Vector3.ZERO,
			mat if mat != null else _plate_mat, _along(d))


# ─────────────────────────────────────────────
# THE MODEL
# ─────────────────────────────────────────────

func _build(variant: String, mw: float, rw: float, target: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ComputeCoreL3"
	# THE PULSE RIDES ON THE MODEL, not on a wrapper, so a core instanced on an
	# empty stage with nothing wired to it still animates — which is how it is
	# photographed and how it will first be dropped into a level.
	root.set_script(_pulse_script)
	_root = root
	_hulls = []
	_structure = _node(root, "Structure")
	# Declared before anything is built so no painted or lit piece can end up
	# anywhere else by accident. See the carried-forward note.
	_paint = _node(root, "Paint")
	_lit_node = _node(root, "Lit")

	var neck: float = target - 1.26

	_deck(rw)
	_mast(variant, mw, neck)
	_head(mw, target, neck)
	_console(mw, rw)

	match variant:
		"trunk": _gear_trunk(mw, rw)
		"uplink": _gear_uplink(mw, rw, neck)
		"patch": _gear_patch(mw, rw, neck)
		"anchor": _gear_anchor(mw, rw, neck)
		"relay": _gear_relay(mw, rw, neck)
		_:
			push_warning("build_core_look3: no gear for variant '%s', so it is a bare mast" % variant)

	_collision(mw, rw, neck, target)
	return root


## THE DECK. A plinth with a wider grated plate on it, so there is an overhang
## shadow all the way round and it reads as a PLATFORM rather than a poured slab.
##
## AND IT IS NOT PAINTED, which is a deliberate reversal of F2. F2 put a 0.16 m
## amber lip right round its raft — the biggest single painted zone in the model
## and, in the lit shot, a bright orange rectangle drawn on the floor that the
## eye reads before anything else. The ground stays quiet here; the only colour
## at deck level in any variant is a COLLAR ON A FITTING, which is punctual.
func _deck(rw: float) -> void:
	_part("DeckPlinth", Vector3(rw * 2.0 - 0.5, 0.34, rw * 2.0 - 0.5),
			Vector3(0, 0.17, 0), Vector3.ZERO, _plate_mat)
	_part("DeckPlate", Vector3(rw * 2.0, 0.18, rw * 2.0),
			Vector3(0, 0.43, 0), Vector3.ZERO, _vent_mat)
	# A RIM AND FOUR CLAMPS, in plate. Grating is a dark fine texture and a 6.3 m
	# square of it photographed as an empty black field with the machine standing
	# in the middle of it — the deck read as a hole rather than as a platform. The
	# rim gives it an edge and the clamps give it four corners, which is all an
	# eye needs to read a surface as a made thing. Neither is painted: the ground
	# stays quiet, and F2's amber floor ring is the fault this is avoiding.
	var t := 0.16
	for sx: float in [-1.0, 1.0]:
		_part("DeckRimX%s" % ("P" if sx > 0.0 else "M"),
				Vector3(t, 0.1, rw * 2.0), Vector3(sx * (rw - t * 0.5), 0.57, 0),
				Vector3.ZERO, _plate_mat)
	for sz: float in [-1.0, 1.0]:
		_part("DeckRimZ%s" % ("P" if sz > 0.0 else "M"),
				Vector3(rw * 2.0 - t * 2.0, 0.1, t), Vector3(0, 0.57, sz * (rw - t * 0.5)),
				Vector3.ZERO, _plate_mat)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_part("DeckClamp%s%s" % ["N" if sz < 0.0 else "S", "E" if sx > 0.0 else "W"],
					Vector3(0.62, 0.12, 0.62),
					Vector3(sx * (rw - 0.38), 0.58, sz * (rw - 0.38)),
					Vector3.ZERO, _plate_mat)


## HOW MANY INTERLACE SLOTS THE MAST CARRIES. A constant pitch, so the count is
## the size cue — and the ODD slots are the painted ones, which means the mast
## always starts bare at the deck and always ends bare under the flare.
func _band_slots(neck: float) -> int:
	return maxi(3, int(round((neck - GROUND) / BAND_PITCH)))


## THE MAST: one plain ribbed box and a ladder of interlaced rings.
##
## THERE IS NOTHING VERTICAL ON IT. No corner posts, no fins, no pilasters, no
## recessed bays. F2 had four posts and four fins crossing five courses and that
## is a grid; a grid is a facade. The ribs in metal_wall_3 are the only vertical
## line here and they are a texture, so they never become geometry at range.
##
## EACH PAINTED RING CARRIES A LIT REVEAL TUCKED UNDER ITS OWN OVERHANG. The
## reveal is narrower than the ring, so only its 0.04 m edge shows and the ring
## shades it: an emissive box only reads as a LINE if every face but the edge is
## covered, which F2's corbel light had to learn the expensive way.
##
## AND THE REVEAL IS WHAT THE PULSE WALKS UP. core_pulse.gd buckets by height, so
## a ladder of discrete rings is exactly the shape that effect wants — better
## than F2's continuous rack strips, which had to be cut artificially to give the
## band something to step on.
func _mast(variant: String, mw: float, neck: float) -> void:
	var run: float = neck - GROUND
	if run < 1.6:
		push_warning("build_core_look3: %.2f m of mast, so the interlacing has nowhere to run" % run)
	_part("MastSkin", Vector3(mw, run, mw), Vector3(0, (GROUND + neck) * 0.5, 0),
			Vector3.ZERO, _mast_mat)
	# A plain box has no top edge where it meets the flare and no bottom edge
	# where it meets the deck; two shallow kick courses give it both, in metal.
	_part("MastFoot", Vector3(mw + 0.12, 0.14, mw + 0.12),
			Vector3(0, GROUND + 0.07, 0), Vector3.ZERO, _plate_mat)

	var n := _band_slots(neck)
	var pitch: float = run / float(n)
	for i in n:
		var y: float = GROUND + pitch * (float(i) + 0.5)
		if i % 2 == 1:
			# PATCH replaces the plain ring with a shelf at exactly these heights,
			# so it builds its own; every other variant takes the plain band.
			if variant != "patch":
				_painted("Band%d" % i,
						_boxm(Vector3(mw + BAND_OUT * 2.0, BAND_H, mw + BAND_OUT * 2.0)),
						Vector3(0, y, 0))
			continue
		if i == 0 or i == n - 1:
			continue        # the mast starts and ends on bare metal.
		_reveal(mw, y)


## A LIT REVEAL, HALFWAY BETWEEN TWO PAINTED BANDS — and the position is a
## correction, not a decision.
##
## The first build put the reveal directly UNDER each painted band, which is
## F2's move and F2's reason (an emissive box only reads as a line if every face
## but its edge is covered). In the lit shot it was invisible: the band stands
## 0.05 proud, the shooting bearing looks DOWN at the core, and a line tucked
## under an overhang is a line you can only see from below it. Three rounds of
## line art would never have shown that either.
##
## Moved to the middle of the bare slot it is seen from every elevation, and the
## interlacing gets richer rather than busier — metal, PAINT, metal, GLOW, metal,
## PAINT — which is a better answer to "interlaced colour / non-colour" than a
## band with a hidden light under it. The painted bands and the lit lines are now
## at different heights, which also fixes F2's other finding: a lit line 5 cm from
## a painted surface of the same hue stops being a separate object.
##
## IT IS A SLOT, NOT A COLLAR, AND THAT TOOK TWO RENDERS. The first version put
## one metal lip ABOVE the light and the light vanished under it; what photographed
## was the lip, as a pale grey line, and the core gained a detail and lost its
## glow. A single lip can only be right for one viewing elevation and there is no
## one elevation — the player looks UP at a 12 m core from its foot and ACROSS at
## a 4 m one from forty metres.
##
## So: two metal flanges standing 0.05 proud with the lit ring set BACK between
## them, flush-plus-a-hair with the mast. The light is then in a genuine recess —
## visible through a 0.12 m aperture from anything inside about 65 degrees of
## horizontal, which is every bearing a player ever has — and it can never read as
## a lamp, because an emissive surface that is BEHIND the silhouette is light
## coming out of the machine by construction. The hair of clearance is there
## because a face coplanar with the mast skin z-fights.
func _reveal(mw: float, y: float) -> void:
	var tag: int = int(round(y * 100.0))
	_part("RevealFlangeT%d" % tag, Vector3(mw + 0.1, 0.06, mw + 0.1),
			Vector3(0, y + 0.09, 0), Vector3.ZERO, _plate_mat)
	_part("RevealFlangeB%d" % tag, Vector3(mw + 0.1, 0.06, mw + 0.1),
			Vector3(0, y - 0.09, 0), Vector3.ZERO, _plate_mat)
	_lit("Reveal%d" % tag, _boxm(Vector3(mw + 0.02, 0.12, mw + 0.02)),
			Vector3(0, y, 0), Vector3.ZERO, y)


## THE HEAD: a two-step flare up to the corbel, then the constant cap.
##
## THE FLARE IS NOT OPTIONAL AND IT IS NOT DECORATION. A 2.60 m cap on a 0.90 m
## mast overhangs by 0.85 m a side; without a transition the pad looks dropped on
## rather than carried. The flare is clamped to the corbel width, so on the large
## core — where the mast is already 1.95 — it quietly collapses into a thicker
## corbel instead of flaring outwards past the cap.
##
## IT ALSO READS AS THE PORT. A slim stem widening into a flat lugged head is a
## socket, which is the fiction: the TICK lands there and takes the core.
func _head(mw: float, target: float, neck: float) -> void:
	var cw: float = PAD * 1.5 + 0.1
	# ONE FLARE, AND IT IS IN THE MAST'S OWN METAL. The first lit render had two
	# flares and a corbel all on metal_floor_1, and because that plate is a value
	# lighter than metal_wall_3 the head came away from the stem and photographed
	# as a pale capital on a dark column — a stone pier, which is the exact word
	# the rejection used about F2. The head is navy now and only the LANDING DECK
	# is plate, so the one light surface on the object is the one the TICK sits on.
	# That also makes the pad read as a port rather than as a roof.
	_part("Flare", Vector3(minf(cw - 0.2, mw + 0.74), 0.22, minf(cw - 0.2, mw + 0.74)),
			Vector3(0, neck - 0.13, 0), Vector3.ZERO, _mast_mat)
	_part("CorbelSlab", Vector3(cw, 0.2, cw), Vector3(0, neck + 0.1, 0),
			Vector3.ZERO, _mast_mat)
	var ctop: float = target - LUG_H - DECK_T - 0.2
	_part("CorbelNeck", Vector3(PAD * 1.42, ctop - neck - 0.2, PAD * 1.42),
			Vector3(0, (ctop + neck + 0.2) * 0.5, 0), Vector3.ZERO, _mast_mat)
	# THE TOP RUNG. Its top is buried in the corbel on purpose — left a centimetre
	# clear it is a 2 m square emissive TABLE seen from the camera's height, not a
	# reveal. This is where the travelling band arrives and dies, which is what
	# makes the pulse read as going somewhere rather than breathing.
	_lit("CorbelLight", _boxm(Vector3(cw - 0.12, 0.07, cw - 0.12)),
			Vector3(0, neck - 0.015, 0), Vector3.ZERO, neck - 0.015)
	_pad(target)


## THE CAP, AND IT IS THE SAME CAP AT EVERY SIZE. 2.60 m across, lug tops exactly
## at `top`, level. NOTHING ANY VARIANT ADDS IS ON IT OR OVER IT: the TICK drone
## is built and approved and clamps this pad at one size.
func _pad(top: float) -> void:
	var deck_top: float = top - LUG_H
	_part("PadSlot", Vector3(PAD * 1.6, 0.2, PAD * 1.6),
			Vector3(0, deck_top - DECK_T - 0.1, 0), Vector3.ZERO, _mast_mat)
	_lit("PadLight", _boxm(Vector3(PAD * 1.7, 0.06, PAD * 1.7)),
			Vector3(0, deck_top - DECK_T - 0.03, 0), Vector3.ZERO,
			deck_top - DECK_T - 0.03)
	_part("PadDeck", Vector3(PAD * 2.0, DECK_T, PAD * 2.0),
			Vector3(0, deck_top - DECK_T * 0.5, 0), Vector3.ZERO, _plate_mat, true)
	var t := 0.14
	for sx: float in [-1.0, 1.0]:
		_part("PadKerbX%s" % ("Pos" if sx > 0.0 else "Neg"),
				Vector3(t, KERB_H, PAD * 2.0),
				Vector3(sx * (PAD - t * 0.5), deck_top + KERB_H * 0.5, 0),
				Vector3.ZERO, _plate_mat)
	for sz: float in [-1.0, 1.0]:
		_part("PadKerbZ%s" % ("Pos" if sz > 0.0 else "Neg"),
				Vector3(PAD * 2.0 - t * 2.0, KERB_H, t),
				Vector3(0, deck_top + KERB_H * 0.5, sz * (PAD - t * 0.5)),
				Vector3.ZERO, _plate_mat)
	# FOUR LANDING LUGS — the TICK's designed interface. An 8-sided cylinder
	# 0.195 across is the concept's chamfered square to within a few millimetres,
	# and it is one primitive instead of a polygon extrusion whose axis has
	# already cost this project a render. Turned 22.5 so its flats face the axes.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_mesh(_structure, "PadLug%s%s" % ["N" if sz < 0.0 else "S", "E" if sx > 0.0 else "W"],
					_cylm(0.195, LUG_H, 8),
					Vector3(sx * (PAD - 0.26), deck_top + LUG_H * 0.5, sz * (PAD - 0.26)),
					Vector3(0, 22.5 * DEG, 0), _plate_mat)


## Where the console cabinet's front face sits, measured from the axis on -Z.
##
## IT IS A PEDESTAL AGAINST THE MAST, NOT A BAY CUT INTO IT, and that is a
## consequence of "thin" rather than a preference. F2 cut a 0.49 m recess into a
## 1.50 m shaft; the same recess in a 0.90 m mast leaves 0.41 m of material and
## cuts the stem in two. A separate terminal cabinet plugged into the mast keeps
## the mast unbroken AND is better for the brief — a patch cabinet with the
## screen on it is a connectivity fitting, which a hole in a wall is not.
##
## THE FORMULA IS RAYCAST ARITHMETIC, NOT TASTE. The player's capsule radius is
## 0.25 so the camera stops 0.25 m outside the deck edge, and test_character
## hangs the 2 m InteractRaycast 0.261 m FORWARD of the camera — so the ray
## starts at rw - 0.011 from the axis. On the large core a cabinet hugging the
## mast would be 3.15 - 0.975 = 2.17 m away and OUT OF REACH, so the cabinet is
## pushed out to at least rw - 1.55. Reach distances come out 0.73 / 1.10 / 1.49 m
## at the three sizes, all inside the 2 m ray with room to spare — better than
## F2's 1.14 / 1.32 / 1.60.
func _console_front(mw: float, rw: float) -> float:
	return maxf(mw * 0.5 + 0.45, rw - 1.55)


## THE CONSOLE. On the -Z approach face, screen centred at y 1.55 — the player's
## eye is at about 1.5 (a 1.7 m capsule with the camera 0.65 above its middle),
## so the interface is at eye level — with a kick rail at 1.02 and a brow over it.
func _console(mw: float, rw: float) -> void:
	var f: float = _console_front(mw, rw)
	var w: float = clampf(mw + 0.5, 1.1, 1.7)
	var depth: float = f - mw * 0.5
	var zc: float = -(mw * 0.5 + depth * 0.5)
	var h: float = 2.05 - GROUND
	_part("ConsoleBody", Vector3(w, h, depth), Vector3(0, GROUND + h * 0.5, zc),
			Vector3.ZERO, _plate_mat, true)
	_part("ConsoleVent", Vector3(w - 0.22, 0.46, depth + 0.04),
			Vector3(0, GROUND + 0.34, zc), Vector3.ZERO, _vent_mat)
	# A BROW OVER THE SCREEN. A lit plate flush on a flat panel has no top edge
	# and reads as a sticker; a hood gives it one and says "stand here".
	_part("ConsoleHood", Vector3(w + 0.08, 0.1, 0.26), Vector3(0, 1.92, -f - 0.08),
			Vector3.ZERO, _plate_mat)
	_part("ConsoleKickRail", Vector3(w * 0.9, 0.09, 0.14), Vector3(0, 1.02, -f - 0.05),
			Vector3.ZERO, _plate_mat)
	# THE INTERFACE, AND IT IS THE ONE LIT PIECE THAT NEVER PULSES. No pulse_y, so
	# core_pulse leaves it at rest forever: an interface that goes dark for part of
	# every cycle is a worse interface however good it looks. It also gives the
	# travelling band a fixed reference to be brighter and dimmer than.
	# Brighter than the rest level because it is the biggest lit face on the model
	# and the only one photographed close enough to show individual texels — at
	# 0.40 glitch_tx_1's own green beats the amber underneath and it reads olive.
	var plate := _lit("ConsolePlate", _boxm(Vector3(w * 0.72, 0.56, 0.06)),
			Vector3(0, 1.55, -f - 0.015))
	(plate.material_override as StandardMaterial3D).emission_energy_multiplier = CONSOLE_GLOW
	# The cabinet joins the interlacing: one painted course on its head, at the
	# same section as a mast band, so the console is part of the ladder.
	# THIN, AND THINNER THAN IT WAS. The first pass gave it the mast band's 0.22
	# section on a cabinet only 1.5 m wide, and in the lit shot it was a bright
	# orange shelf at the brightest-lit part of the model — the first thing the eye
	# found on the whole core, which is not what a kick-plate on a terminal should
	# be. 0.11 makes it a course in the ladder instead of an event.
	_painted("ConsoleCourse", _boxm(Vector3(w + 0.05, 0.11, depth + 0.05)),
			Vector3(0, 1.99, zc))


# ─────────────────────────────────────────────
# THE GEAR — the variant, and the answer to "connectivity"
#
# One rule across all five: the bearings used are +X, -X, +Z and the two REAR
# diagonals. NOTHING RUNS TOWARDS -Z at deck level, because that is where the
# console cabinet stands and where the player walks in. Four-fold symmetry is
# worth less than a front door that works.
# ─────────────────────────────────────────────

## The ground bearings every variant's gear is laid out on. Rear-weighted on
## purpose; see the rule above.
const BEARINGS := [
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0.7071, 0, 0.7071), Vector3(-0.7071, 0, 0.7071),
]
const BEARING_TAGS := ["E", "W", "SE", "SW"]


## ── TRUNK ────────────────────────────────────────────────────────────────────
## IT IS WIRED INTO THE GROUND. Four cable trunks leave the mast foot, run out
## across the deck as three-pipe bundles, and dive into the earth through gland
## boxes at the deck edge.
##
## WHY THIS ANSWERS CONNECTIVITY: it is the most literal answer in the set and
## the hardest to misread. A machine with four fat bundles disappearing into the
## ground is DRAWING SOMETHING FROM somewhere else; a machine on a plinth is
## storage. The glands are the lowest lit pieces on the model, so the pulse
## starts in the cables and climbs the mast — the object is visibly pulling the
## area's compute up out of the ground it stands on.
func _gear_trunk(mw: float, rw: float) -> void:
	# 0.11 AND NOT 0.085. At the first radius the bundles were three hairlines on a
	# 4 m deck and the variant's entire argument was invisible in the lit shot from
	# the shooting bearing. A cable trunk is a FAT object; thin is the mast's job.
	var y: float = GROUND + 0.19
	for i in BEARINGS.size():
		var d: Vector3 = BEARINGS[i]
		var tag: String = BEARING_TAGS[i]
		var a: Vector3 = d * (mw * 0.5 - 0.05) + Vector3(0, y, 0)
		var b: Vector3 = d * (rw - 0.46) + Vector3(0, y, 0)
		var run: float = (b - a).length()
		if run < 0.5:
			push_warning("build_core_look3: %.2f m of trunk on bearing %s, so it would not read as plugged in" % [run, tag])
			continue
		var yaw: float = atan2(d.x, d.z)
		var across := Vector3(d.z, 0, -d.x)
		# THREE PIPES, NOT ONE. A single pipe is a handrail; a bundle is cable.
		# Same reading the kit's own compute_cable_run is built on.
		for k in 3:
			var off: float = (float(k) - 1.0) * 0.25
			_mesh(_structure, "Trunk%sPipe%d" % [tag, k], _cylm(0.11, run, 8),
					(a + b) * 0.5 + across * off, Vector3.ZERO, _plate_mat,
					_along(b - a))
		# A painted banding collar halfway along each bundle. SMALL AND PUNCTUAL:
		# this is the only colour below 1 m on the model, and F2's amber ground
		# ring is exactly what it is not.
		_painted("Trunk%sCollar" % tag, _boxm(Vector3(0.74, 0.16, 0.2)),
				(a + b) * 0.5, Vector3(0, yaw, 0))
		# The gland, and the downpipe through the deck into the earth. The pipe is
		# modelled from y 0 so it reads as going THROUGH rather than stopping on.
		var g: Vector3 = b
		_part("Trunk%sGland" % tag, Vector3(0.62, 0.62, 0.52), g + Vector3(0, 0.08, 0),
				Vector3(0, yaw, 0), _plate_mat)
		_mesh(_structure, "Trunk%sDown" % tag, _cylm(0.16, GROUND + 0.26, 8),
				Vector3(g.x, (GROUND + 0.26) * 0.5, g.z), Vector3.ZERO, _plate_mat)
		_painted("Trunk%sGlandCap" % tag, _boxm(Vector3(0.68, 0.12, 0.58)),
				g + Vector3(0, 0.45, 0), Vector3(0, yaw, 0))
		# THE LOWEST LIT PIECE ON THE MODEL, and that placement is the whole point:
		# core_pulse buckets by height, so the band is born here.
		var ly: float = g.y + 0.08
		_lit("Trunk%sPort" % tag, _boxm(Vector3(0.4, 0.14, 0.04)),
				g + Vector3(0, 0.08, 0) + d * 0.27, Vector3(0, yaw, 0), ly)


## ── UPLINK ───────────────────────────────────────────────────────────────────
## IT TALKS TO SOMETHING. A dish cantilevered off the mast high up, braced by two
## stays down to the deck, with a lit feed horn at its focus and a small ground
## gland at the back.
##
## WHY THIS ANSWERS CONNECTIVITY: the other four variants connect the core to the
## GROUND; this one connects it to the chain of command. Taking a core hands the
## area's compute to Argus, and this is the only variant that draws the route it
## leaves by. It is also the strongest silhouette in the set at distance — a dish
## is recognisable from a bearing where bands are not.
##
## THE DISH IS SIZED OFF `rw`, NOT TYPED. Its outermost point has to stay inside
## the deck square or the footprint changes and a second nav rebake is owed.
func _gear_uplink(mw: float, rw: float, neck: float) -> void:
	var arm: float = clampf(rw * 0.26, 0.42, 0.72)
	var rad: float = clampf(rw * 0.38, 0.6, 1.2)
	var reach: float = mw * 0.5 + arm + rad
	if reach > rw - 0.08:
		# Every early return warns, and a silent clamp here would quietly change
		# the measured footprint — the one number this look is not allowed to move.
		push_warning("build_core_look3: dish reaches %.2f m against a %.2f m deck half-width; shrinking it" % [reach, rw])
		rad = maxf(0.4, rw - 0.12 - mw * 0.5 - arm)
	var y: float = neck - 1.15
	var hub := Vector3(-(mw * 0.5 + arm), y, 0)
	_part("DishArm", Vector3(arm + 0.12, 0.18, 0.22),
			Vector3(-(mw * 0.5 + arm * 0.5), y, 0), Vector3.ZERO, _plate_mat)
	_part("DishYoke", Vector3(0.24, 0.5, 0.24), hub, Vector3.ZERO, _plate_mat)
	# The dish itself: an octagonal plate, tilted up and out. Eight sides because
	# that is what the kit's own compute_satellite_dish is.
	var tilt := Vector3(0, 0, 58.0 * DEG)
	_mesh(_structure, "DishFace", _cylm(rad, 0.12, 8), hub + Vector3(-0.18, 0.26, 0),
			tilt, _vent_mat)
	# THE RIM IS THE INTERLACE, CARRIED ONTO THE DISH. A slightly larger, slightly
	# thinner plate behind the face shows only as a painted edge all the way round,
	# which is the same move as a mast band on a different surface.
	_painted("DishRim", _cylm(rad + 0.09, 0.06, 8), hub + Vector3(-0.15, 0.24, 0), tilt)
	# Two back ribs, in metal, so the dish is not a coin.
	for sx: float in [-1.0, 1.0]:
		_mesh(_structure, "DishRib%s" % ("A" if sx > 0.0 else "B"),
				_boxm(Vector3(0.1, 0.1, rad * 1.6)),
				hub + Vector3(-0.1, 0.26 + sx * rad * 0.42, 0), tilt, _plate_mat)
	# THE FEED HORN, lit, at the focus — the one place on the model where the
	# faction colour is a POINT rather than a band. It is also the highest lit
	# piece below the corbel, so the pulse arrives at the dish last and leaves.
	var feed: Vector3 = hub + Vector3(-0.62, 0.86, 0)
	_lit("DishFeed", _boxm(Vector3(0.18, 0.18, 0.18)), feed, Vector3.ZERO, y + 0.86)
	# THE BOOM, and the first build did not have one: the feed horn floated clear
	# of the dish with nothing holding it, which in the lit shot read as a bug
	# rather than as a fitting. A feed on no boom is a mistake at any distance.
	_strut(false, "DishBoom", hub + Vector3(-0.1, 0.22, 0), feed, 0.07)
	# TWO STAYS DOWN TO THE DECK. Without them a 1.2 m dish on a 0.1 m arm is a
	# lollipop — and a stay is also the cheapest way to say the thing is tensioned
	# into its own foundation rather than bolted on.
	for sz: float in [-1.0, 1.0]:
		var foot := Vector3(-(mw * 0.5 + 0.35), GROUND, sz * (mw * 0.5 + 0.55))
		_strut(false, "DishStay%s" % ("N" if sz < 0.0 else "S"),
				hub + Vector3(0, -0.2, 0), foot, 0.09)
		_part("DishStayPad%s" % ("N" if sz < 0.0 else "S"),
				Vector3(0.34, 0.16, 0.34), foot + Vector3(0, 0.08, 0),
				Vector3.ZERO, _plate_mat)
	# A ground gland at the back, so the uplink is still fed from somewhere.
	var g := Vector3(0, GROUND + 0.1, rw - 0.5)
	_part("FeedGland", Vector3(0.66, 0.6, 0.5), g, Vector3.ZERO, _plate_mat)
	_painted("FeedGlandCap", _boxm(Vector3(0.72, 0.12, 0.56)), g + Vector3(0, 0.36, 0))
	_mesh(_structure, "FeedPipe", _cylm(0.13, rw - 0.5 - mw * 0.5, 8),
			Vector3(0, GROUND + 0.18, (mw * 0.5 + rw - 0.5) * 0.5),
			Vector3(PI * 0.5, 0, 0), _plate_mat)
	_lit("FeedPort", _boxm(Vector3(0.36, 0.13, 0.04)), g + Vector3(0, 0, -0.27),
			Vector3.ZERO, g.y)


## ── PATCH ────────────────────────────────────────────────────────────────────
## IT IS A PATCH FRAME. Every interlace slot is a shelf rather than a ring: a thin
## metal tray with a painted front rail on it, and JUMPER LOOPS running on the
## flanks from one shelf to the next.
##
## WHY THIS ANSWERS CONNECTIVITY: a patch panel is the object whose entire purpose
## is joining lines together, and the jumpers are the only moving-looking thing in
## the set — they say the connections are made HERE and can be remade. It is the
## variant that most looks like something you operate rather than something you
## own.
##
## THE INTERLACING IS THE SAME LADDER with a different section: shelf, bare bay,
## shelf. The painted rail is 0.14 of a 0.62 pitch, so this is the QUIETEST
## variant of the five by colour share and the busiest by piece count.
func _gear_patch(mw: float, rw: float, neck: float) -> void:
	var run: float = neck - GROUND
	var n := _band_slots(neck)
	var pitch: float = run / float(n)
	var out: float = 0.17
	var shelf_ys: Array[float] = []
	for i in n:
		if i % 2 == 0:
			continue
		var y: float = GROUND + pitch * (float(i) + 0.5)
		shelf_ys.append(y)
		_part("Shelf%d" % i, Vector3(mw + out * 2.0, 0.08, mw + out * 2.0),
				Vector3(0, y, 0), Vector3.ZERO, _plate_mat)
		_painted("ShelfRail%d" % i,
				_boxm(Vector3(mw + out * 2.0 + 0.04, 0.14, mw + out * 2.0 + 0.04)),
				Vector3(0, y + 0.11, 0))
		# No lit line on the shelf itself: _mast's reveals are between the shelves
		# and this variant's shelves would shade one into invisibility, which is the
		# fault _reveal's header is about.
	# JUMPERS. Two loops per flank per gap, standing off the mast face, running
	# from one shelf to the next. On +X and -X only: +Z carries the feeder and -Z
	# is the approach face.
	# TWO PER FLANK AT ONE STAND-OFF, not a staggered pair at two. The first build
	# varied the stand-off as well as the position and the large core came back with
	# a lattice of verticals crossing the shelves — which is exactly the grid that
	# got the last look rejected. One stand-off means the jumpers read as cables in
	# front of the mast rather than as members of a frame.
	for j in range(shelf_ys.size() - 1):
		var y0: float = shelf_ys[j] + 0.1
		var y1: float = shelf_ys[j + 1] - 0.02
		for sx: float in [-1.0, 1.0]:
			for k in 2:
				var zoff: float = (float(k) - 0.5) * 0.4
				_mesh(_structure, "Jumper%s%d%d" % ["E" if sx > 0.0 else "W", j, k],
						_cylm(0.06, y1 - y0, 6),
						Vector3(sx * (mw * 0.5 + 0.16), (y0 + y1) * 0.5, zoff),
						Vector3.ZERO, _plate_mat)
	# THE JUNCTION CABINET at the back, with a fan of five lines into the ground.
	# The frame patches; this is where the patched lines leave for the territory.
	var g := Vector3(0, GROUND + 0.45, rw - 0.55)
	_part("Junction", Vector3(1.1, 0.9, 0.6), g, Vector3.ZERO, _plate_mat)
	_part("JunctionVent", Vector3(0.86, 0.5, 0.64), g + Vector3(0, 0.08, 0),
			Vector3.ZERO, _vent_mat)
	_painted("JunctionCourse", _boxm(Vector3(1.16, 0.14, 0.66)), g + Vector3(0, 0.52, 0))
	_lit("JunctionPort", _boxm(Vector3(0.6, 0.12, 0.04)), g + Vector3(0, -0.12, -0.32),
			Vector3.ZERO, g.y - 0.12)
	for k in 5:
		var x: float = (float(k) - 2.0) * 0.22
		_mesh(_structure, "JunctionLine%d" % k, _cylm(0.055, rw - 0.55 - mw * 0.5, 6),
				Vector3(x, GROUND + 0.12, (mw * 0.5 + rw - 0.55) * 0.5),
				Vector3(PI * 0.5, 0, 0), _plate_mat)


## ── ANCHOR ───────────────────────────────────────────────────────────────────
## IT IS PINNED TO ITS GROUND. Four tie-arms rake down from a collar on the mast
## to anchor blocks at the deck edge, each anchor with a painted collar and a pipe
## going into the earth.
##
## WHY THIS ANSWERS CONNECTIVITY: it is the only variant whose shape REACHES OUT.
## The brief's line is that a core should look like it is HOLDING a territory
## rather than sitting in one, and four raking ties going down and outwards is the
## posture of something gripping. The kit's own compute_obelisk is built on this
## grammar and nothing in three rounds has used it.
##
## THE TIE IS TWO SEGMENTS ON ONE RAKE: a metal arm from the collar and a painted
## foot at the anchor end. So the interlacing is on the DIAGONALS as well as the
## horizontals, which is the bearing every variant here is otherwise weakest on.
func _gear_anchor(mw: float, rw: float, neck: float) -> void:
	var run: float = neck - GROUND
	var n := _band_slots(neck)
	var pitch: float = run / float(n)
	# SNAPPED TO AN INTERLACE BAND, not placed independently. The first build put
	# its own painted collar at run * 0.46 and on the medium core that landed 0.12 m
	# from the band at i = 3 — two amber rings almost but not quite coincident,
	# which photographed as a smear. The ties spring from a band that is already
	# there, which is also the better idea: the interlacing is the structure.
	# THE LOWEST PAINTED BAND, AND THAT IS A CORRECTION WORTH THE WORDS. The first
	# build raked from a band at 46% of the mast down to the deck edge, which on a
	# deck only ~1.1 m wider than the mast is a 60-degree member: steep ties read as
	# BRACES — props holding something up — and the lit shot came back as a stick of
	# clutter leaning on a tower. Taken from the LOWEST band instead, the rake is
	# about 33 degrees at every size, and a shallow rake going down and outwards is
	# the posture of something GRIPPING. That is the brief's own word: holding a
	# territory rather than sitting in one.
	#
	# It also puts every piece of this variant's gear below 1.6 m, so the mast above
	# is clean interlacing — the same composition at all three sizes.
	var top: float = GROUND + pitch * 1.5
	for i in BEARINGS.size():
		var d: Vector3 = BEARINGS[i]
		var tag: String = BEARING_TAGS[i]
		var a: Vector3 = d * (mw * 0.5 + 0.02) + Vector3(0, top - 0.04, 0)
		var b: Vector3 = d * (rw - 0.42) + Vector3(0, GROUND + 0.5, 0)
		# ONE CLEAN MEMBER WITH A PAINTED SLEEVE ON IT, not two segments of
		# different sections meeting at a kink. The first build painted the outer
		# 38% of each tie and the joint was visible from every bearing as a bend
		# that is not there — a sleeve is what a tie-rod actually has anyway.
		_strut(false, "Tie%s" % tag, a, b, 0.11)
		_painted("Tie%sSleeve" % tag, _boxm(Vector3(0.17, 0.3, 0.17)),
				a.lerp(b, 0.72), Vector3.ZERO, _along(b - a))
		var yaw: float = atan2(d.x, d.z)
		var g: Vector3 = d * (rw - 0.42)
		# AN UPRIGHT BOLLARD, NOT A SLAB. The first anchor was a low wide block with
		# a painted plate lying on its top face, and a horizontal painted face seen
		# from a three-quarter elevation is an orange smear on the floor — the same
		# fault CORE_F_VARIANTS.md §1 rejected inside F1. A bollard with a collar
		# ROUND it puts the colour in a vertical surface, where it is seen.
		_part("Anchor%s" % tag, Vector3(0.34, 0.8, 0.34),
				g + Vector3(0, GROUND + 0.3, 0), Vector3(0, yaw, 0), _plate_mat)
		_painted("Anchor%sCollar" % tag, _boxm(Vector3(0.44, 0.16, 0.44)),
				g + Vector3(0, GROUND + 0.42, 0), Vector3(0, yaw, 0))
		_mesh(_structure, "Anchor%sDown" % tag, _cylm(0.15, GROUND + 0.1, 8),
				Vector3(g.x, (GROUND + 0.1) * 0.5, g.z), Vector3.ZERO, _plate_mat)
		# The lowest lit piece, in the anchor. Same reason as TRUNK's gland port.
		# KEPT ABOVE y 0.16 ON PURPOSE: at GROUND - 0.1 it hung 0.16 m below the
		# ground plane and the measured box came back 4.36 m tall on a 4.20 m core,
		# which is a HEIGHT CONTRACT broken by a decoration. Heights are checked, so
		# it was caught — but nothing below ground may be drawn.
		var ly: float = GROUND + 0.16
		_lit("Anchor%sPort" % tag, _boxm(Vector3(0.22, 0.14, 0.04)),
				Vector3(g.x, ly, g.z) + d * 0.18, Vector3(0, yaw, 0), ly)


## ── RELAY ────────────────────────────────────────────────────────────────────
## IT IS A PYLON. Cross-arms at the painted interlace levels, alternating bearing
## level by level, each tipped with an insulator and a painted cap, and lines
## slung from the lowest arm down to gland posts on the deck.
##
## WHY THIS ANSWERS CONNECTIVITY: a transmission pylon is the single most legible
## "this holds the grid for an area" object there is, and it is the only variant
## whose connectivity is visible in SILHOUETTE from any bearing at any range — the
## others need you close enough to read a fitting. It also scales hardest: the
## large core gets four arm levels where the small gets one, so "a bigger machine"
## is carried by the arms as well as by the band count.
##
## ARMS START ABOVE y 2.20 ON THE -Z BEARING, because the console cabinet's head
## is at 2.05 and an arm through the terminal is not a detail, it is a bug. Low
## painted levels keep a plain collar instead, which is why the small core has one
## arm level and two collars.
func _gear_relay(mw: float, rw: float, neck: float) -> void:
	var run: float = neck - GROUND
	var n := _band_slots(neck)
	var pitch: float = run / float(n)
	# ARMS REACH rw * 0.55, NOT rw * 0.3. At the first length the large core's
	# cross-arms photographed as seven pairs of 0.95 m pegs on a 10.6 m mast —
	# nubs, not arms, and a pylon whose arms do not read is just a banded mast.
	# The length is still measured against the deck so the footprint cannot move.
	var armlen: float = clampf(rw * 0.55, 0.6, 1.9)
	var k := 0
	var lowest_y := INF
	var lowest_dir := Vector3.ZERO
	for i in n:
		if i % 2 == 0:
			continue
		var y: float = GROUND + pitch * (float(i) + 0.5)
		# ARMS ON EVERY OTHER PAINTED BAND, not on all of them. The first build put
		# a pair on all eight of the large core's bands and it came out a Christmas
		# tree — a pylon has a few big arm levels, and the bands in between are what
		# makes those levels read as levels. 1 / 2 / 4 across the three sizes.
		var armed: bool = k % 2 == 0
		var along_x: bool = (k / 2) % 2 == 0
		k += 1
		if not armed:
			continue
		# A Z-bearing arm below the cabinet head would pass through the console.
		if not along_x and y < 2.3:
			continue
		var d: Vector3 = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var yaw: float = 0.0 if along_x else PI * 0.5
		var tag := "%d" % i
		var reach: float = mw * 0.5 + armlen
		if reach > rw - 0.1:
			push_warning("build_core_look3: a %.2f m cross-arm would leave the %.2f m deck" % [reach, rw])
			continue
		for s: float in [-1.0, 1.0]:
			var tip: Vector3 = d * (s * reach) + Vector3(0, y, 0)
			var rootp: Vector3 = d * (s * mw * 0.45) + Vector3(0, y, 0)
			_strut(false, "Arm%s%s" % [tag, "P" if s > 0.0 else "M"], rootp, tip, 0.14)
			# A STAY UNDER EACH ARM. An unbraced 0.95 m cantilever on a 0.14 m
			# section reads as a stick taped on; the brace makes it a structure.
			_strut(false, "ArmStay%s%s" % [tag, "P" if s > 0.0 else "M"],
					d * (s * mw * 0.5) + Vector3(0, y - 0.46, 0),
					tip - d * (s * 0.16), 0.08)
			_painted("ArmCap%s%s" % [tag, "P" if s > 0.0 else "M"],
					_boxm(Vector3(0.26, 0.2, 0.26)), tip + Vector3(0, 0.1, 0))
			_mesh(_structure, "Insulator%s%s" % [tag, "P" if s > 0.0 else "M"],
					_cylm(0.07, 0.3, 6), tip + Vector3(0, -0.18, 0),
					Vector3.ZERO, _plate_mat)
			_lit("ArmLight%s%s" % [tag, "P" if s > 0.0 else "M"],
					_boxm(Vector3(0.3, 0.05, 0.12)), tip + Vector3(0, -0.02, 0),
					Vector3(0, yaw, 0), y)
			if y < lowest_y:
				lowest_dir = d
		# NO COLLAR HERE. _mast already paints a band at exactly this height for
		# every variant, and the first build added a second ring of the same
		# section on top of it — two coplanar faces, which is z-fighting rather
		# than detail. The arms spring FROM the interlace band; they do not bring
		# their own.
		if y < lowest_y:
			lowest_y = y
	if is_inf(lowest_y):
		push_warning("build_core_look3: no cross-arm cleared the console on a %.2f m mast, so this core is a bare pylon" % mw)
		return
	# THE DOWNLINES. Straight members from the lowest arm's tips to gland posts on
	# the deck — the lines actually leaving the pylon for the territory. Without
	# them the arms are an abstraction; with them the object is connected to its
	# own ground, which is the brief in one piece of geometry.
	var reach2: float = mw * 0.5 + armlen
	for s: float in [-1.0, 1.0]:
		var tip: Vector3 = lowest_dir * (s * reach2) + Vector3(0, lowest_y - 0.3, 0)
		var postp: Vector3 = lowest_dir * (s * (rw - 0.4)) + Vector3(0, GROUND + 0.62, 0)
		_strut(false, "Downline%s" % ("P" if s > 0.0 else "M"), tip, postp, 0.06)
		_part("DownPost%s" % ("P" if s > 0.0 else "M"), Vector3(0.3, 0.62, 0.3),
				postp - Vector3(0, 0.31, 0), Vector3.ZERO, _plate_mat)
		_painted("DownPostCap%s" % ("P" if s > 0.0 else "M"),
				_boxm(Vector3(0.36, 0.12, 0.36)), postp)
		_mesh(_structure, "DownPostPipe%s" % ("P" if s > 0.0 else "M"),
				_cylm(0.12, GROUND + 0.1, 8),
				Vector3(postp.x, (GROUND + 0.1) * 0.5, postp.z), Vector3.ZERO, _plate_mat)
		_lit("DownPostPort%s" % ("P" if s > 0.0 else "M"),
				_boxm(Vector3(0.22, 0.1, 0.04)),
				postp - Vector3(0, 0.3, 0) + lowest_dir * (s * 0.16),
				Vector3(0, atan2(lowest_dir.x * s, lowest_dir.z * s), 0),
				GROUND + 0.32)


# ─────────────────────────────────────────────
# COLLISION
#
# ONE StaticBody3D, collision_mask = 0 — a thing to be hit that tests nothing
# itself, which is what FuncGodot writes for worldspawn and therefore what the
# shipped .map cores already are.
#
# THE DECK IS THE WHOLE FOOTPRINT, as F2's raft was. A 0.52 m sheer step is not
# something move_and_slide climbs, so the player is stopped outside it — the only
# arrangement the 2 m InteractRaycast works in. If anybody later gives the player
# stair-stepping, this becomes a core you can stand on and the reach box must
# shrink to the mast at the same time.
#
# THE GEAR HAS NO COLLISION AT ALL — trunks, ties, arms, dish, jumpers, lines. It
# is fittings the player brushes past, and four raking ties would otherwise give a
# nav bake a set of 45-degree wedges to quantise around a box it already has.
# Godot has no per-agent path clearance; the bake is the only clearance enforced,
# so every extra silhouette in collision is a real cost.
# ─────────────────────────────────────────────
func _collision(mw: float, rw: float, neck: float, target: float) -> void:
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_mask = 0
	_root.add_child(body)
	body.owner = _root

	_shape(body, "DeckBlock", Vector3(rw * 2.0, GROUND, rw * 2.0),
			Vector3(0, GROUND * 0.5, 0))
	_shape(body, "MastBlock", Vector3(mw, neck - GROUND, mw),
			Vector3(0, (neck + GROUND) * 0.5, 0))
	# The console cabinet, so rounds stop on the thing the player shelters behind.
	var f: float = _console_front(mw, rw)
	var depth: float = f - mw * 0.5
	_shape(body, "ConsoleBlock",
			Vector3(clampf(mw + 0.5, 1.1, 1.7), 2.05 - GROUND, depth),
			Vector3(0, (GROUND + 2.05) * 0.5, -(mw * 0.5 + depth * 0.5)))
	# Everything above the mast as one column. Nothing can reach it, but a core is
	# cover and a round should stop on it.
	var cw: float = PAD * 1.5 + 0.1
	_shape(body, "HeadBlock", Vector3(cw, target - neck, cw),
			Vector3(0, (target + neck) * 0.5, 0))


func _shape(body: StaticBody3D, nm: String, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	body.add_child(cs)
	cs.owner = _root


# ─────────────────────────────────────────────
# MEASUREMENT — tools/check_frame.gd's _bounds, so a number printed by this file
# and a number printed by that one mean the same thing.
# ─────────────────────────────────────────────
func _bounds(n: Node, body: Node3D) -> AABB:
	var out := AABB()
	var started := false
	for c in n.get_children():
		var sub := _bounds(c, body)
		if sub.size != Vector3.ZERO:
			out = sub if not started else out.merge(sub)
			started = true
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var local := _relative(vi, body)
		var a := local * vi.get_aabb()
		out = a if not started else out.merge(a)
	return out


## Transform relative to `body` without needing the node in a tree.
func _relative(n: Node3D, body: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != body:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _count_meshes(n: Node) -> int:
	var c: int = 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c
