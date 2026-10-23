extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for the three F2 RAFT compute core models.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_core_f2.gd
#
# Writes:
#   res://maps/blocks/compute/compute_core_f2_small.tscn    4.20 m
#   res://maps/blocks/compute/compute_core_f2.tscn          7.00 m
#   res://maps/blocks/compute/compute_core_f2_large.tscn   12.40 m
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. Same contract as
# tools/build_bulwark.gd, and read that file's header for why these generators
# exist at all: a model with ~90 named pieces and hand-numbered sub-resource ids
# is a transcription exercise with nothing to learn from, and writing it by hand
# is how load_steps counts go wrong. It is NOT a build step. Re-running it after
# the scene has been touched in the editor throws that work away, the way
# --force map rebuilds have repeatedly cost this project its gameplay layers.
# If the geometry needs changing after today, change the scene.
#
# ─────────────────────────────────────────────
# WHAT THIS IS
#
# Concept F2 RAFT, chosen AS PRESENTED at the end of three rounds — see
# docs/concepts/CORE_F_VARIANTS.md §2 and §7, and COMPUTE_CORES_2.md §1 for why
# F won at all. The face-mounted-fin fix floated in §7 is deliberately NOT
# applied here: the human picked the corner fins that were drawn.
#
# Every number below is lifted from tools/concepts_core_f.gd — _raft(), _fin(),
# _trunk(), _rim(), _conduit() — and from ConceptsCore2's _console/_bands/
# _risers/_pad/_kerb/_lugs. That file was the authority and this one was the same
# shape rebuilt out of MeshInstance3D so it could ship.
#
# NO LONGER TRUE OF THE MEMBERS, as of the 2026-10-13 review. The sizes that
# fix the proportions and the whole palette are set HERE now and the concept
# file does not have them: the fin section, the corner posts, the inset body,
# the course depth, the rack panels and every texture. What is still lifted
# unchanged is everything the review did not ask about — the raft, the
# conduits, the corbel, the pad, the lugs and all three overall heights.
#
# THE TWO THINGS THAT MAKE THIS CORE WHAT IT IS, and neither may be touched:
#
#   1. THE CAP IS CONSTANT. PAD is a HALF-width of 1.30 — a 2.60 m lugged pad
#      on the 4.2 m core and on the 12.4 m one alike. ConceptsCore2 calls it
#      "THE RULER. Do not scale it." It is also the contract with the TICK hack
#      drone, which clamps that pad with one clamp at one size. SCALING IT
#      BREAKS THE DRONE AS WELL AS THE SILHOUETTE.
#   2. THE PAINTED SURFACES ARE THE FEATURE. See the PAINT note below.
#
# ─────────────────────────────────────────────
# THE PAINTED NODE LIST — the contract with whatever colours these by owner
#
# Every painted surface is its OWN MeshInstance3D with its OWN
# StandardMaterial3D instance, and all of them hang under a single child of the
# root named **"Paint"**. A future owner-colour system walks
# `core.get_node("Paint").get_children()` and sets `albedo_color` on each
# mesh's material_override. Nothing structural is in that node, so it can never
# repaint the plant-grey.
#
# THERE ARE TWO SUCH LISTS NOW — "Paint" and "Lit" — and the LIT NODE block
# further down says why they are not one. Everything below is about Paint.
#
# Paint holds NINETEEN meshes, in three groups:
#
#   RaftLipXNeg / RaftLipXPos / RaftLipZNeg / RaftLipZPos        4   ground ring
#   ConduitPipeL / ConduitGlandL / ConduitPipeR / ConduitGlandR  4   ground runs
#   Fin{E,W,S,N}{Blade,Head} + Fin{E,W,S}Foot                   11   full height
#   (the N fin starts above the console bay and so has no foot)
#
# THE PAINT GLOWS, which widens that contract: each material has
# emission_enabled with `emission` set to the same faction colour as
# `albedo_color`. An owner-colour system that sets albedo_color ALONE will
# repaint the surface and leave it glowing in the previous owner's colour, so it
# must set both. See PAINT_GLOW.
#
# THIS REPLACES THE FAKE. Env/world_objects/core_signal.gd builds a procedural
# "DeckCollar" and "ClimbBand" and tints them from HUDPalette, and its own
# header says it is placeholder presentation that "the real art can replace
# this without touching the state machine". This is that real art. The default
# albedo here is HUDPalette.FAC_ADVERSARY — the same amber core_signal starts
# an unowned core at — so an unwired core already looks right.
#
# A MESH WITH NO MATERIAL IS INVISIBLE AS A BUG until somebody sees it in the
# wrong colour, so every piece in this file goes through _mesh(), which refuses
# to make one without a material.
#
# THIS IS ARCHITECTURE, NOT A ROBOT. check_frame.gd does not apply: no
# FactionLivery, no "enemies" group, no Bark, no nav agent. It is a Node3D with
# meshes, one StaticBody3D and — since 2026-10-14 — core_pulse.gd on its root,
# which animates the Lit materials and does nothing else.
#
# ─────────────────────────────────────────────
# NO CSG, ANYWHERE
#
# The concept cuts the console bay out of the shaft with a CSG subtraction.
# csg_bake.gd exists because a CSGShape3D rebuilds the first time it enters the
# tree — 335 ms for a wave of robots — and that baker only walks AI scenes, so
# a CSG node in a world object would pay the rebuild at every level load with
# nothing to catch it. The bay here is therefore FIVE BRUSHES around a void
# (_shaft_with_bay), which occupies exactly the solid the subtraction left.
# Read every box in this file as a brush; that is what the .map cores are.
#
# ─────────────────────────────────────────────
# HOW IT FITS compute_core_point.tscn
#
# REACH IS THE CORE'S OWN FOOTPRINT, which here is the RAFT, not the shaft. The
# raft plate's top is at 0.52 m with a sheer edge, so the player is stopped by
# the raft's collision and cannot step onto it — which is what puts the camera
# OUTSIDE a reach box sized to the footprint, the only arrangement the 2 m
# InteractRaycast works in (it does not register a hit when it starts inside the
# volume). The footprints are 3.28 / 4.43 / 6.30 m square.
#
# MEASURED, AND IT IS TIGHTER THAN THE WRAPPER'S COMMENT SAYS. The player's
# capsule radius is 0.25, so the camera stops 0.25 m outside the raft edge — not
# half a metre — and test_character hangs the InteractRaycast 0.261 m FORWARD of
# the camera. So a reach box set exactly to the footprint has its ray starting
# 0.011 m INSIDE it, on the wrong side of the rule. The shipped 7 m core is in
# that position today (3.375 m base, reach_size 3.38) and works because nobody
# walks perfectly square into the middle of a face. These are wider cores, so
# the REGISTRATION block below asks for 0.6 m off the reach box rather than
# reproducing an 11 mm margin on purpose.
#
# The console bay faces -Z at y 1.10–2.00 with the lit plate centred at 1.55 —
# the player's eye is at about 1.5 (a 1.7 m capsule with the camera 0.65 above
# its middle), so the interface is at eye level — and a kick rail at 1.02. Its
# distance from where the player is stopped is 1.14 / 1.32 / 1.60 m at the three
# sizes, inside the 2 m ray at every size, which is why the raft is allowed to
# be this wide.
#
# THE CONDUITS AND THEIR GLANDS HAVE NO COLLISION. They run off the BACK of the
# raft to rw + 0.70 and would otherwise make the footprint non-square and give
# a nav bake a 0.17 m pipe to quantise for no gameplay at all.
# ─────────────────────────────────────────────

const OUT_DIR := "res://maps/blocks/compute"

# ── THE PALETTE, and it is the half of the revision that is not geometry ─────
#
# Review, 2026-10-13: "the capture modules are not computery enough. look at the
# old capture model, with its sleek lines, it looks like a piece of technology,
# these don't."
#
# Measured against the shipped compute_core.map and its neighbours, the gap was
# never complexity — the old core is 22 brushes. It was TEXTURE. Face counts:
#
#   compute_core.map        metal_floor_1 63 · glitch_tx_1 30 · rubber_tsk_1 29
#   compute_rack_row.map    metal_floor_3 96 · glitch_tx_1 48 · metal_floor_1 35
#   compute_data_hall.map   metal_floor_3 210 · metal_floor_1 84 · glitch_tx_1 66
#
# A QUARTER of the old core's faces are glitch_tx_1 — a green data-noise sheet
# that is already emissive in its own .tres — and the family's cabinet bodies are
# metal_floor_3, a perforated rack grille. F2 shipped with NEITHER: a concrete
# shaft and metal_floor_1 decking, which is the texture set of a transformer
# yard. That is most of why it read as plant.
#
## Cabinet body. The perforated grille every shipped rack in maps/blocks/compute
## is skinned in, so the core is made of the same stuff as the racks around it.
const MAT_RACK := "res://textures/PSX_Textures/metal_floor_3.tres"
## Frame members — posts, courses, corbel. Ribbed metal, reads as extrusion.
const MAT_FRAME := "res://textures/PSX_Textures/metal_wall_4.tres"
## THE SCREEN. glitch_tx_1's own .tres is a GREEN emissive material — a flat
## Color(0.45, 1, 0.6) at 0.9 energy — and that fixed green is exactly what the
## 2026-10-14 review rejected. It is no longer used as a material here; only its
## PNG is, under fresh per-core materials. Kept as the texture's address and as
## the record of where the green came from.
const MAT_SCREEN := "res://textures/PSX_Textures/glitch_tx_1.tres"
## THE SCREEN TEXTURE, which is what the lit pieces actually wear now.
const SCREEN_TEX := "res://textures/PSX_Textures/glitch_tx_1.png"
## Decking and the raft plate. Shared read-only — never mutated here.
const MAT_METAL := "res://textures/PSX_Textures/metal_floor_1.tres"
## The four footings the raft stands on, and the only poured thing left.
const MAT_CONCRETE := "res://textures/PSX_Textures/concrete_tx_5.tres"
## The painted pieces get a fresh StandardMaterial3D each, built on this.
const PAINT_TEX := "res://textures/PSX_Textures/metal_wall_3.png"

## EMISSION ENERGY ON THE FACTION PAINT. Review: "the faction color needs to be
## bright/glowing not flat."
##
## The pattern is Env/world_objects/core_signal.gd:181-188 — emission_enabled,
## emission set to the faction colour, an energy multiplier. What is NOT copied
## from there is SHADING_MODE_UNSHADED: that file applies it to thin open tubes
## which are pure signal, whereas these are 19 structural-looking blades, lips
## and pipes whose form has to survive. Unshaded flattens a blade into a sticker.
##
## 0.95 WAS PICKED BY PHOTOGRAPHING IT, not reasoned to, and the number is low
## for a reason worth writing down. FAC_ADVERSARY is Color(0.91, 0.63, 0.23) —
## its red channel is ALREADY at 0.91, so emission energy multiplies straight
## into clipping rather than into brightness. 1.3 was the first value tried and
## in tools/mockup_shots.gd it came back pale: red and green both pinned and the
## amber went towards white, which is the colour the glow existed to show. 0.6
## held the texture but still read as paint. At 0.95 the raft lip and the fins
## are unmistakably lit strips against the grey, and a zoom still reads amber.
##
## IT DOES NOT BLOOM, because the mockup level's WorldEnvironment has no glow
## pass — so "glowing" here is self-illumination, not a halo, and the value that
## looks right is therefore much lower than one tuned against a bloom.
const PAINT_GLOW := 0.95

# ─────────────────────────────────────────────
# THE LIT NODE — the second owner-coloured list, and NOT the same thing as Paint
#
# Review, 2026-10-14: "the green glowing elements should be faction colored, and
# it should have some pulsing / interesting effect to it."
#
# The lit strips — the reveal under every shelf course, the strip down each rack
# bay, the line under the corbel, the line under the pad deck and the console
# plate — used to wear glitch_tx_1.tres straight, which is a FIXED GREEN. They
# are faction-coloured now, and they hang under a second child of the root named
# **"Lit"**, parallel to "Paint" and deliberately not merged into it:
#
#   Paint  is painted bodywork that glows. Flat, structural, constant.
#   Lit    is SCREENS. They carry glitch_tx_1's data noise and they MOVE.
#
# An owner-colour pass has to walk both and set `albedo_color` AND `emission` on
# both — but it should expect to treat them differently in future (a damaged
# core might kill the screens and keep the paint), which is the whole reason
# they are two lists.
#
# TWO THINGS THAT WILL BITE AN OWNER-COLOUR PASS, and they are written here
# because they are not guessable from the node names:
#
#   1. MATERIALS ARE SHARED WITHIN A SEGMENT. The eight rack strips at one
#      height share one StandardMaterial3D, because they are one pulse unit.
#      Setting albedo on every child therefore sets some materials eight times,
#      which is harmless — but DO NOT assume child count equals material count.
#   2. DO NOT WRITE emission_energy_multiplier. core_pulse.gd animates exactly
#      that float, reads the generator's value as the rest level, and multiplies
#      it by PEAK_GAIN. A pass that stamps an energy onto the Lit materials is
#      fighting a tween and will lose intermittently.
#
# ─────────────────────────────────────────────
# THE EMISSION, and the trap this file has already paid for once
#
# The previous pass put glitch_tx_1 across whole 5 m bays at 0.9 flat emission
# and the lit shot came back as a green lamp with a machine inside it: the data
# noise invisible, the panels reading as flat paint. Thinning the strips fixed
# the area but not the mechanism — a FLAT emission colour is uniform across the
# face by construction, so past some energy it is a solid rectangle no matter
# how narrow it is.
#
# THE FIX IS emission_texture, NOT A LOWER NUMBER. With the glitch PNG wired to
# emission as well as albedo, the light the surface makes VARIES PER TEXEL, so
# the noise is in the glow itself and survives any energy. It is set to
# EMISSION_OP_ADD, not MULTIPLY, and that choice is the one that keeps the
# faction read:
#
#   EMISSION = (emission_colour + texture.rgb) * energy
#
# ADD puts the faction colour under the noise as a FLOOR. The texture is green
# and magenta; on MULTIPLY it would recolour the glow — an amber core would emit
# yellow-green and magenta speckle, and an Argus core would be unreadable. On
# ADD the faction colour is always present at full strength and the texture only
# adds variation on top of it. Hue is owned by the faction; the texture owns the
# grain.
#
# 0.34 IS LOW AND THAT IS THE POINT. It is a REST level that core_pulse.gd
# multiplies by 2.6 at the crest, so the number that has to survive clipping is
# 0.88, not 0.34. FAC_ADVERSARY is Color(0.91, 0.63, 0.23) — red already at 0.91
# — and because ADD puts the texture on top of that, the brightest texels sit at
# about 1.36 before energy is applied. At 0.88 those just touch the ceiling,
# which is a sparkle on the noisiest texels; at the 1.3 that instinct asks for,
# every texel pins and the strip is a white bar with no grain in it, which is
# the original fault with a different number in it.
const LIT_GLOW := 0.40
## THE CONSOLE PLATE ALONE, which does not pulse and is not at rest either. See
## the note on ConsolePlate in _shaft_with_bay: it is the one lit face big enough
## to be seen texel by texel, and at 0.40 the texture's own green beat the amber
## under it. This is the energy at which the faction colour wins.
const CONSOLE_GLOW := 0.85

const _Palette := preload("res://Character/hud/hud_palette.gd")
## The pulse. Attached to the root of all three scenes; see its own header.
const PULSE_SCRIPT := "res://maps/blocks/compute/core_pulse.gd"

const DEG := PI / 180.0

# ── the numbers, all of them from the concept ───────────────────────────────

## HALF-WIDTH of the landing pad. THE RULER. Do not scale it.
## ConceptsCore2.F_PAD, and the TICK clamps it.
const PAD := 1.3
const LUG_H := 0.26         ## ConceptsCore2.LUG_H
const DECK_T := 0.34        ## ConceptsCore2.DECK_T
const KERB_H := 0.15        ## ConceptsCore2.KERB_H

# SLIMMED, 2026-10-13. The concept's blade was 0.20 x 0.62 and at that section
# it is a buttress, not a mullion. The old core's verticals are slim posts and
# that is the whole of its "sleek lines"; nothing was added to it to get them.
const FIN_T := 0.14         ## ConceptsCoreF.F2_FIN_T, was 0.20
const FIN_W := 0.5          ## ConceptsCoreF.F2_FIN_W, was 0.62

## ── THE RACK FRAME, all three numbers new in the 2026-10-13 revision ────────
## Corner post section. Slim, square, full shaft height: four vertical lines in
## every elevation, which is the thing the old core has and F2 did not.
const POST := 0.18
## How far the cabinet body is set back inside the frame plane. The posts and
## the fins keep the silhouette at `sw`; the body falls away behind them, so
## every face has a shadow line down each edge and a recess to put a screen in.
const INSET := 0.12
## Shelf course depth. Was a 0.14 band standing 0.08 proud; a rack's shelves are
## SHALLOWER AND MORE FREQUENT than that, and reading as plant was the cost.
const COURSE_H := 0.09
## Rack panel thickness. Sits on the inset body, so its face is still 0.08
## behind the frame plane and it reads as something set INTO the cabinet.
const PANEL_T := 0.06

## shaft width, overall height, output filename. ConceptsCoreF.SHAFT and
## ConceptsCore2.H_SMALL / H_MEDIUM / H_LARGE.
const SIZES := [
	[1.5, 4.2, "compute_core_f2_small.tscn"],
	[2.3, 7.0, "compute_core_f2.tscn"],
	[3.6, 12.4, "compute_core_f2_large.tscn"],
]

var _concrete: Material
var _metal: Material
var _rack: Material
var _frame: Material
var _paint_tex: Texture2D
var _screen_tex: Texture2D
var _screen_faces: int      ## how much of the model wears glitch_tx_1
var _pulse_script: Script
var _root: Node3D
var _structure: Node3D
var _paint: Node3D
var _lit_node: Node3D
var _hulls: Array[Node3D]   ## pieces that also get a collision box


func _init() -> void:
	_concrete = load(MAT_CONCRETE)
	_metal = load(MAT_METAL)
	_rack = load(MAT_RACK)
	_frame = load(MAT_FRAME)
	_paint_tex = load(PAINT_TEX)
	_screen_tex = load(SCREEN_TEX)
	_pulse_script = load(PULSE_SCRIPT)
	if (_concrete == null or _metal == null or _rack == null or _frame == null
			or _screen_tex == null or _paint_tex == null or _pulse_script == null):
		printerr("build_core_f2: a material, a texture or the pulse script failed to load, so every piece would be bare")
		quit(1)
		return
	for spec: Array in SIZES:
		var sw: float = spec[0]
		var target: float = spec[1]
		var path: String = "%s/%s" % [OUT_DIR, spec[2]]
		_screen_faces = 0
		var node := _build(sw, target)
		var bb := _bounds(node, node)
		var packed := PackedScene.new()
		var err := packed.pack(node)
		if err != OK:
			printerr("build_core_f2: pack failed for %s (%s)" % [path, error_string(err)])
			quit(1)
			return
		err = ResourceSaver.save(packed, path)
		if err != OK:
			printerr("build_core_f2: save failed for %s (%s)" % [path, error_string(err)])
			quit(1)
			return
		print("build_core_f2: wrote %s" % path)
		print("    measured  W %.2f  H %.2f  L %.2f   (origin at %.2f, %.2f, %.2f)"
				% [bb.size.x, bb.size.y, bb.size.z, bb.position.x, bb.position.y, bb.position.z])
		var meshes: int = _count_meshes(node)
		print("    footprint %.2f square · paint %d · lit %d · meshes %d"
				% [_raft_half(sw) * 2.0, _paint.get_child_count(),
						_lit_node.get_child_count(), meshes])
		# Every piece here is a box or a short cylinder, so "faces" is 6 a piece
		# and the ratio is comparable with a .map brush count. The shipped
		# compute_core.map carries glitch_tx_1 on 30 of its 134 faces: 22%.
		# READ THIS AS A PIECE COUNT, NOT AN AREA, since the 2026-10-14 pass.
		# Cutting each rack strip into one segment per bay tripled the lit piece
		# count without adding a square centimetre of lit surface, so the large
		# core's 42% is the same strips as before with joints in them.
		print("    glitch_tx_1 on %d of %d pieces — %.0f%% of faces (old core 22%%)"
				% [_screen_faces, meshes, 100.0 * float(_screen_faces) / float(meshes)])
		node.free()
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## The only way a mesh gets made in this file, so nothing can ship bare.
## A MeshInstance3D with no material draws in the editor's default white and
## nobody notices until it is seen next to something that IS painted.
func _mesh(parent: Node, nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO, mat: Material = null) -> MeshInstance3D:
	if mat == null:
		mat = _rack
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.position = at
	m.rotation = euler
	m.material_override = mat
	parent.add_child(m)
	m.owner = _root
	return m


## A structural piece. Defaults to the rack body texture; `solid` adds a
## matching collision box.
func _part(nm: String, size: Vector3, at: Vector3, euler: Vector3 = Vector3.ZERO,
		mat: Material = null, solid: bool = false) -> MeshInstance3D:
	var m := _mesh(_structure, nm, _boxm(size), at, euler, mat)
	if solid:
		_hulls.append(m)
	return m


## A PAINTED piece. Its own mesh, its own material instance, and it lands in
## the Paint node — which is the whole list an owner-colour system walks.
func _painted(nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _mesh(_paint, nm, mesh, at, euler, _paint_material())


## FRESH PER PIECE, not shared. Resources are shared in this engine: one
## material handed to twenty meshes is one object, and the first script that
## wanted to pulse a single fin would pulse the whole core. See CLAUDE.md's
## duplicate() rule — this is the same fault, caught before it was written.
func _paint_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _paint_tex
	# The colour core_signal.gd starts an unowned core at, so a core dropped in
	# a level with nothing wired to it already reads as StratCom's.
	m.albedo_color = _Palette.FAC_ADVERSARY
	# AND IT GLOWS. Painted amber on a grey machine in a grey level is amber-grey;
	# the faction has to be findable across a field. core_signal.gd's _emissive()
	# is the project's pattern and this is it, minus the unshaded mode — see
	# PAINT_GLOW for why that part does not come across.
	m.emission_enabled = true
	m.emission = _Palette.FAC_ADVERSARY
	m.emission_energy_multiplier = PAINT_GLOW
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# PER INSTANCE, NOT PER SCENE. A sub-resource in a .tscn is ONE object
	# shared by every instantiation of that scene unless it says otherwise, so
	# two cores in one level would have shared these materials and the second
	# owner to capture a core would have repainted the first one's. Latent since
	# the Paint list was written and never fired because no level holds two F2
	# cores yet; fixed here because the Lit list cannot live with it at all —
	# two cores would also have been fighting over one pulse.
	m.resource_local_to_scene = true
	return m


## A LIT piece — a screen, not paint. See the LIT NODE block at the top for why
## this is a separate list and why emission is textured rather than flat.
##
## `at_y` is the height the pulse reaches it at, written as metadata for
## core_pulse.gd. Passing NAN means "this one does not pulse", which is the
## console plate and only the console plate.
##
## `mat` lets several pieces at one height share a material, because a height is
## one pulse unit; pass null for a piece that owns its own.
func _lit(nm: String, mesh: Mesh, at: Vector3, euler: Vector3 = Vector3.ZERO,
		at_y: float = NAN, mat: StandardMaterial3D = null) -> MeshInstance3D:
	if mat == null:
		mat = _lit_material()
	var m := _mesh(_lit_node, nm, mesh, at, euler, mat)
	_screen_faces += 1
	if not is_nan(at_y):
		m.set_meta(&"pulse_y", at_y)
	return m


## Faction-coloured screen. The texture is on BOTH albedo and emission; the
## emission operator is ADD so the faction colour is a floor the noise sits on
## rather than a tint the noise recolours. The long version is at the top.
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
	# See _paint_material. Doubly required here: core_pulse.gd writes this
	# material's energy every frame, so two cores sharing one would stutter.
	m.resource_local_to_scene = true
	return m


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cylm(radius: float, height: float, sides: int = 12) -> CylinderMesh:
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


# ─────────────────────────────────────────────
# THE MODEL
# ─────────────────────────────────────────────

## Raft half-width. ConceptsCoreF._raft: sw * 0.72 + 0.56.
func _raft_half(sw: float) -> float:
	return sw * 0.72 + 0.56


## Where the shaft starts — the raft plate's top face. ConceptsCoreF._raft.
const GROUND := 0.52


func _build(sw: float, target: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ComputeCoreF2"
	# THE PULSE RIDES ON THE MODEL, not on a wrapper. A core instanced on an
	# empty stage with nothing else wired still animates, which is how it is
	# photographed and how it will first be dropped into a level.
	root.set_script(_pulse_script)
	_root = root
	_hulls = []
	_structure = _node(root, "Structure")
	# THE PAINTED NODE LIST. See the header. Declared before anything is built
	# so no painted piece can end up anywhere else by accident.
	_paint = _node(root, "Paint")
	# THE LIT LIST, which is the other one and is not the same thing. See the
	# LIT NODE block at the top.
	_lit_node = _node(root, "Lit")

	var rw := _raft_half(sw)
	var neck: float = target - 1.26     # ConceptsCoreF._trunk

	_raft(sw, rw)
	_trunk(sw, target, neck)
	_fins(sw, neck)
	_collision(sw, rw, neck)
	return root


## THE BASE: a steel raft plate on four short pads, with a shadow gap under it.
##
## THE SHADOW GAP IS THE WHOLE TELL — the plate's underside is at 0.30 and its
## top at 0.52, so there is 0.30 m of daylight under a 0.22 m plate, which is
## what separates "bolted down" from "poured". It is also the one base in the
## set that survives a slope, because a raft on pads can be shimmed.
func _raft(sw: float, rw: float) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# The four footings, and the only poured thing left in the model: a
			# steel raft shimmed onto concrete pads is the reading, and it is
			# also what keeps one grey material in a model that is otherwise
			# all equipment.
			_part("RaftPad%s" % _corner(sx, sz), Vector3(0.52, 0.3, 0.52),
					Vector3(sx * (rw - 0.42), 0.15, sz * (rw - 0.42)), Vector3.ZERO, _concrete)
	_part("RaftPlate", Vector3(rw * 2.0, 0.22, rw * 2.0), Vector3(0, 0.41, 0),
			Vector3.ZERO, _metal)

	# Bolt rows along the two long edges. ConceptsCoreF uses _Parts.studs, which
	# lays its cylinders on their side with Rx(90) because the kit's studs live
	# on the VERTICAL faces of robots. These are on a deck's top face, so they
	# stand up in +Y instead — the only change in this file to anything the
	# concept drew, and it is an orientation, not a proportion: same count,
	# same spacing, same 0.055 radius.
	var step: float = (rw * 2.0 - 0.8) / 5.0
	for sz: float in [-1.0, 1.0]:
		for i in 6:
			_mesh(_structure, "RaftStud%s%d" % ["S" if sz > 0.0 else "N", i],
					_cylm(0.055, 0.077, 6),
					Vector3(-rw + 0.4 + step * float(i), 0.53, sz * (rw - 0.22)),
					Vector3.ZERO, _metal)

	# ── PAINT: the raft lip. A 0.16 x 0.18 ring on the plate's own edge.
	# Ground level, 360 degrees, never occluded by anything including the Tick,
	# and it is the ring you are standing outside of when you take the core.
	# The bars are INSET by half their thickness so the ring reads as a band ON
	# the plate rather than a box AROUND it — ConceptsCoreF._rim.
	var t := 0.18
	var h := 0.16
	for sx: float in [-1.0, 1.0]:
		_painted("RaftLipX%s" % ("Pos" if sx > 0.0 else "Neg"),
				_boxm(Vector3(t, h, rw * 2.0)),
				Vector3(sx * (rw - t * 0.5), GROUND + h * 0.5, 0))
	for sz: float in [-1.0, 1.0]:
		_painted("RaftLipZ%s" % ("Pos" if sz > 0.0 else "Neg"),
				_boxm(Vector3(rw * 2.0 - t * 2.0, h, t)),
				Vector3(0, GROUND + h * 0.5, sz * (rw - t * 0.5)))

	# ── Two conduit trunks leaving the raft at the back, over the lip and away.
	# This is the fitting that says the core is PLUGGED INTO SOMETHING rather
	# than parked on the ground. The pipe and its gland are painted; the saddles
	# under it are plant, exactly as ConceptsCoreF._conduit returns them.
	for sx: float in [-0.5, 0.5]:
		var tag := "R" if sx > 0.0 else "L"
		var from := Vector3(sx * sw, 0.78, sw * 0.5)
		var to_p := Vector3(sx * sw, 0.78, _raft_half(sw) + 0.7)
		var leng: float = to_p.z - from.z
		if leng < 0.4:
			push_warning("build_core_f2: %.2f m of conduit run at sw %.2f, so the core would not read as plugged in" % [leng, sw])
			continue
		_painted("ConduitPipe%s" % tag, _cylm(0.17, leng, 8),
				(from + to_p) * 0.5, Vector3(PI * 0.5, 0, 0))
		var saddles: int = maxi(2, int(leng / 1.8) + 1)
		for i in saddles:
			var p: Vector3 = from.lerp(to_p, float(i) / float(saddles - 1))
			_part("ConduitSaddle%s%d" % [tag, i], Vector3(0.408, p.y, 0.408),
					Vector3(p.x, p.y * 0.5, p.z), Vector3.ZERO, _metal)
		_painted("ConduitGland%s" % tag, _boxm(Vector3(0.51, 0.51, 0.51)), to_p)


## EVERYTHING ABOVE THE RAFT, and it is round two's F unchanged: shaft, console
## bay, band courses, back risers, corbel, pad.
##
## THE CORBEL IS NOT OPTIONAL. A constant 2.60 m pad on a shaft of three
## different widths needs a transition, or two of the three read as a mistake —
## on the small core the pad overhangs the shaft by half a metre each side, on
## the large the shaft is wider than the pad. COMPUTE_CORES_2.md has the
## argument.
func _trunk(sw: float, target: float, neck: float) -> void:
	if neck - GROUND < 1.2:
		push_warning("build_core_f2: %.2f m of shaft above the raft, so the console has nowhere to go" % (neck - GROUND))

	# THE CABINET IS NOT THE SILHOUETTE ANY MORE. The body is built INSET on
	# every side; the four posts and the four fins hold the outline at `sw`, so
	# the overall box, the collision and the measured bounds are unchanged while
	# every elevation gains four vertical shadow lines and a recess.
	var bw: float = sw - INSET * 2.0
	_shaft_with_bay(bw, neck, minf(bw * 0.74, 1.5))
	_frame_posts(sw, neck)
	_courses(sw, neck)
	_rack_faces(sw, bw, neck)

	# Two cable risers and their tie, up the BACK face. A blank back is the
	# thing that makes a slab read as a placeholder. They run in the CORNER
	# CHANNELS now — in line with the posts, against the inset body — so they
	# are cable trunking inside the frame instead of two pipes crossing the vent
	# panels that the revision put in the middle of that face.
	var r: float = clampf(sw * 0.06, 0.07, 0.14)
	var ry1: float = neck - 0.4
	for sx: float in [-1.0, 1.0]:
		_mesh(_structure, "Riser%s" % ("R" if sx > 0.0 else "L"),
				_cylm(r, ry1 - GROUND, 8),
				Vector3(sx * (sw * 0.5 - POST * 0.5), (GROUND + ry1) * 0.5, bw * 0.5 + r),
				Vector3.ZERO, _metal)
	_part("RiserTie", Vector3(sw - POST, r * 2.2, r * 2.2),
			Vector3(0, ry1, bw * 0.5 + r), Vector3.ZERO, _frame)

	# The corbel: a slab off the shaft head and a neck up to the cap.
	var ctop: float = target - LUG_H - DECK_T - 0.2
	var cw: float = maxf(sw, PAD * 1.5) + 0.1
	_part("CorbelSlab", Vector3(cw, 0.22, cw), Vector3(0, neck + 0.11, 0),
			Vector3.ZERO, _frame, true)
	_part("CorbelNeck", Vector3(PAD * 1.6, ctop - neck - 0.22, PAD * 1.6),
			Vector3(0, (ctop + neck + 0.22) * 0.5, 0), Vector3.ZERO, _frame, true)
	# A lit course under the corbel, right round. The corbel is where the eye
	# stops on a 12 m core and it was a bare grey shelf.
	# ITS TOP IS BURIED IN THE CORBEL ON PURPOSE. Left a centimetre clear it was
	# a 3.5 m square emissive TABLE seen from the camera's height, not a reveal;
	# an emissive box only reads as a line if every face but the edge is covered.
	_lit("CorbelLight", _boxm(Vector3(cw - 0.16, 0.07, cw - 0.16)),
			Vector3(0, neck - 0.025, 0), Vector3.ZERO, neck - 0.025)
	_pad(target)


## FOUR SLIM CORNER POSTS, full shaft height, outer faces flush with `sw`.
##
## This is the single change that does most of the work the review asked for.
## The old core is 22 brushes and gets its "sleek lines" from thin members —
## slim posts, shallow shelves, an inset cabinet — not from detail. F2 had one
## chunky box with a band round it, and a box with a band round it is plant.
func _frame_posts(sw: float, neck: float) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_part("FramePost%s" % _corner(sx, sz),
					Vector3(POST, neck - GROUND, POST),
					Vector3(sx * (sw - POST) * 0.5, (neck + GROUND) * 0.5,
							sz * (sw - POST) * 0.5),
					Vector3.ZERO, _frame)


## SHALLOW SHELF COURSES, and more of them than the band they replace.
##
## 0.09 deep standing 0.03 proud of the frame plane, at roughly 1.7 m — the
## rhythm of a rack, where the old 0.14 band every 2.1 m was the rhythm of a
## concrete lift. They cross in front of the recessed panels, which is what
## stops a tall lit slot reading as a stripe.
##
## 1.7 AND NOT 1.3, WHICH WAS RENDERED FIRST. At 1.3 the 12.4 m core came back
## with seven courses and read as a ladder — the shipped core carries TWO across
## its whole height, and the lesson of this revision is that thin members beat
## many members. 1.7 gives 2 / 2 / 5 at the three sizes.
func _courses(sw: float, neck: float) -> void:
	var h: float = neck - GROUND
	var n: int = _course_count(neck)
	for i in range(1, n):
		var y: float = GROUND + h * float(i) / float(n)
		_part("Course%d" % i, Vector3(sw + 0.06, COURSE_H, sw + 0.06),
				Vector3(0, y, 0), Vector3.ZERO, _frame)
		# A LIT REVEAL UNDER EACH SHELF, right round. This is the shipped core's
		# own move — three of its five glitch_tx_1 brushes are 0.25 m bands at
		# height, not panels — and it is what makes a horizontal read as a
		# running light rather than a ledge. It stops at the posts, which stand
		# proud of it, so the line is broken at the corners the way a real one is.
		var ly: float = y - COURSE_H * 0.5 - 0.035
		_lit("CourseLight%d" % i, _boxm(Vector3(sw - 0.04, 0.07, sw - 0.04)),
				Vector3(0, ly, 0), Vector3.ZERO, ly)


## HOW MANY RACK SEGMENTS THE SHAFT IS DIVIDED INTO, and therefore how many
## shelf courses it carries (one fewer — the top division is the corbel). Shared
## with _rack_faces so the lit strips break EXACTLY where the shelves cross
## them: a strip segmented on any other rhythm leaves a lit joint in mid-panel.
func _course_count(neck: float) -> int:
	return maxi(3, int((neck - GROUND) / 1.7))


## THE RACK FACES — glitch_tx_1 panels in the recess, two to a face.
##
## WHERE THE DATA TEXTURE WENT. The shipped core carries glitch_tx_1 on about a
## quarter of its faces and F2 carried none; this is the bulk of the correction.
## Each face has two bays, between a corner post and the central fin: a recessed
## GRILLE panel filling the bay, with a slim LIT STRIP down its inner edge.
##
## IT IS A STRIP AND NOT THE WHOLE PANEL, AND THAT WAS RENDERED BOTH WAYS. The
## first pass put glitch_tx_1 across the entire bay — eight 5 m emissive sheets —
## and the lit mockup came back as a green lamp with a machine inside it: the
## emission swamped the texture, so the data noise that was the entire point of
## the texture was invisible and the panels read as flat paint. The old core
## never does this. Its glitch brushes are 0.25 m BANDS and one console screen;
## the glow is in thin lines against dark metal, which is also why it reads as
## sleek. So: grille where the area is, glitch where the line is.
##
## Both sit ON the inset body, so their faces are still 0.04-0.08 m behind the
## frame plane. A screen flush with the posts would read as a sticker.
func _rack_faces(sw: float, bw: float, neck: float) -> void:
	var bay_in: float = FIN_W * 0.5 + 0.05
	var bay_out: float = sw * 0.5 - POST - 0.05
	var bay_w: float = bay_out - bay_in
	if bay_w < 0.12:
		push_warning("build_core_f2: %.2f m of bay beside the fin at sw %.2f, so the rack faces are a line and the core keeps no data texture at all" % [bay_w, sw])
		return
	var lit_w: float = minf(0.13, bay_w * 0.38)
	# ── THE STRIPS ARE CUT AT THE SHELVES, which is what lets the pulse CLIMB.
	# A single 10 m lit bar can only brighten as one object — it would breathe,
	# and breathing is the dull version of this effect. Cut into one segment per
	# rack bay, the eight strips become a ladder the travelling band can walk up,
	# and the breaks land under the shelf courses where a rack's own joints are,
	# so the segmentation is invisible when the pulse is not passing.
	#
	# ONE MATERIAL PER SEGMENT, SHARED BY ALL EIGHT STRIPS AT THAT HEIGHT. They
	# are one pulse unit by definition, so eight materials would be eight
	# tweeners doing identical arithmetic. core_pulse.gd de-duplicates what it is
	# handed, and the LIT NODE block at the top warns the owner-colour pass.
	var h: float = neck - GROUND
	var n: int = _course_count(neck)
	var seg_mats: Array[StandardMaterial3D] = []
	for j in n:
		seg_mats.append(_lit_material())
	for face in [[1.0, 0.0, "E"], [-1.0, 0.0, "W"], [0.0, 1.0, "S"], [0.0, -1.0, "N"]]:
		var nx: float = face[0]
		var nz: float = face[1]
		var tag: String = face[2]
		var yaw: float = atan2(nx, nz)
		# -Z is the approach face and its lower 0.9 m is the console bay, so its
		# panels start above the bay head — same rule the north fin follows.
		var y0: float = 2.12 if tag == "N" else GROUND + 0.1
		var y1: float = neck - 0.08
		if y1 - y0 < 0.3:
			push_warning("build_core_f2: %.2f m of panel on face %s, so that face stays bare" % [y1 - y0, tag])
			continue
		var out_n := Vector3(nx, 0, nz) * (bw * 0.5 + PANEL_T * 0.5 - 0.02)
		var lit_n := Vector3(nx, 0, nz) * (bw * 0.5 + PANEL_T - 0.02 + 0.02)
		var tangent := Vector3(nz, 0, -nx)
		var mid := Vector3(0, (y0 + y1) * 0.5, 0)
		for side: float in [-1.0, 1.0]:
			var sfx: String = "A" if side > 0.0 else "B"
			_mesh(_structure, "RackPanel%s%s" % [tag, sfx],
					_boxm(Vector3(bay_w, y1 - y0, PANEL_T)),
					out_n + tangent * (side * (bay_in + bay_w * 0.5)) + mid,
					Vector3(0, yaw, 0), _rack)
			# AGAINST THE POST, NOT AGAINST THE FIN — moved 2026-10-14, and it
			# is a consequence of the recolour rather than a preference. The
			# strip used to run down the bay's INNER edge, 5 cm from a fin
			# blade, which worked while it was green against amber paint. The
			# moment the strips became faction-coloured too, a lit line 5 cm
			# from a lit blade of the same hue stopped being a separate
			# object: the first render of the amber version had eight strips
			# in it that could not be found. At the bay's OUTER edge it is
			# amber against the grey ribbed post, which is the contrast the
			# green used to get for free.
			var lit_at := lit_n + tangent * (side * (bay_out - lit_w * 0.5))
			for j in n:
				var sy0: float = maxf(y0, GROUND + h * float(j) / float(n))
				var sy1: float = minf(y1, GROUND + h * float(j + 1) / float(n))
				# The -Z face starts above the console bay, so its lower
				# segments simply are not there. Silent on purpose and ONLY
				# here: it is the bay, not a failure, and the north fin and the
				# north panels already skip the same band for the same reason.
				if sy1 - sy0 < 0.06:
					continue
				var sy: float = (sy0 + sy1) * 0.5
				_lit("RackLit%s%s%d" % [tag, sfx, j],
						_boxm(Vector3(lit_w, sy1 - sy0, 0.04)),
						lit_at + Vector3(0, sy, 0),
						Vector3(0, yaw, 0), sy, seg_mats[j])


## THE SHAFT, as five brushes around the console void.
##
## The concept cuts a w x 0.90 x 0.50 box out of the shaft's -Z face centred at
## y 1.55 and then sets a lit plate inside the hole. These five pieces are
## exactly the solid that subtraction leaves, so the silhouette and the measured
## bounds are identical and no CSG enters the tree. See the header.
##
## THE PLATE GOES AGAINST THE BACK OF THE RECESS, NOT NEAR IT. The concept's
## CSGPolygon3D extrudes along its own NEGATIVE Z, so its origin is the FRONT
## of the slab; reproduced here as a plain box, the centre has to be moved back
## by half its depth or it floats a hand's width proud of the bay. That hovering
## fault is the one the kit's own note was written about.
## TAKES THE BODY WIDTH, NOT THE OVERALL WIDTH, since the 2026-10-13 revision:
## the cabinet is built INSET and the posts and fins carry the outline. The
## recess depth drops by exactly that inset, so the lit plate, the kick rail and
## therefore the distance the player's 2 m InteractRaycast has to cover all stay
## at the world positions the header's arithmetic was done for.
func _shaft_with_bay(sw: float, neck: float, w: float) -> void:
	var face: float = -sw * 0.5         # the approach face, -Z
	var y0 := 1.1                       # recess floor
	var y1 := 2.0                       # recess head
	var depth: float = 0.49 - INSET     # measured from the INSET body face
	var jamb: float = (sw - w) * 0.5
	if jamb <= 0.05:
		push_warning("build_core_f2: %.2f m of jamb beside the console, so the bay cuts the shaft in two" % jamb)

	for sx: float in [-1.0, 1.0]:
		_part("ShaftJamb%s" % ("R" if sx > 0.0 else "L"),
				Vector3(jamb, neck - GROUND, sw),
				Vector3(sx * (sw - jamb) * 0.5, (neck + GROUND) * 0.5, 0),
				Vector3.ZERO, null, true)
	_part("ShaftBelowBay", Vector3(w, y0 - GROUND, sw),
			Vector3(0, (y0 + GROUND) * 0.5, 0), Vector3.ZERO, null, true)
	_part("ShaftAboveBay", Vector3(w, neck - y1, sw),
			Vector3(0, (neck + y1) * 0.5, 0), Vector3.ZERO, null, true)
	_part("ShaftBayBack", Vector3(w, y1 - y0, sw - depth),
			Vector3(0, (y0 + y1) * 0.5, face + depth + (sw - depth) * 0.5),
			Vector3.ZERO, null, true)

	# THE INTERFACE. A lit plate in the bay at y 1.55 — the one the 2 m
	# InteractRaycast is aimed at — and a kick rail at knee height standing
	# proud of the face, so there is a horizontal saying "stand here" rather
	# than a hole in a wall.
	# The plate is glitch_tx_1 now. It was metal_floor_1 — a grey rectangle in a
	# hole, which is a hatch, not an interface. The texture is emissive in its
	# own .tres, so the thing the player has to walk up and press is the one lit
	# object on the approach face.
	# AND IT IS THE ONE LIT PIECE THAT DOES NOT PULSE. No pulse_y, so core_pulse
	# leaves it at rest forever. The travelling band is decoration; this is the
	# thing the player has to find and press, and an interface that goes dark for
	# part of every cycle is a worse interface however good it looks. It also
	# gives the pulse a second fixed reference, beside the painted fins, to be
	# brighter and dimmer than.
	#
	# IT ALSO SITS BRIGHTER THAN THE REST LEVEL, AND THAT IS A COLOUR FIX AS MUCH
	# AS A GAMEPLAY ONE. It is the biggest single lit face on the model and the
	# only one photographed close enough to show individual texels, so at the
	# 0.40 rest the other pieces use it came back reading OLIVE: glitch_tx_1 is
	# green and magenta, and at a low energy the texture's own hue beats the
	# faction colour underneath it. Driving its energy up pushes the faction
	# floor past the texture and the plate reads amber with green grain in it,
	# which is the right way round. The thin strips never had this problem —
	# they are a few pixels wide and average out — so only this one is raised.
	var console := _lit("ConsolePlate", _boxm(Vector3(w * 0.8, 0.62, 0.1)),
			Vector3(0, 1.55, face + depth - 0.05))
	(console.material_override as StandardMaterial3D).emission_energy_multiplier = CONSOLE_GLOW
	_part("ConsoleKickRail", Vector3(w * 0.95, 0.09, 0.14),
			Vector3(0, 1.02, face - 0.06), Vector3.ZERO, _frame)


## THE CAP, AND IT IS THE SAME CAP AT EVERY SIZE. 2.60 m across, lug tops at
## `top`, level — the shipped core's 30-degree cut is the fault this replaces,
## because anything flat-bottomed rocks on it.
##
## Three silhouette breaks, none of which depends on a bore: a lit slot under
## the deck, a kerb on its edge, and four lugs standing proud at the corners. A
## BORED HOLE DRAWS IDENTICALLY TO A FLAT FACE, which is what killed the Yoke.
func _pad(top: float) -> void:
	var deck_top: float = top - LUG_H
	# THE LIT SLOT, now actually lit: glitch_tx_1 under the deck overhang, so the
	# shadow line under the cap is a green reveal. This is the piece the concept
	# always described as lit and that shipped in grey.
	# THE SLOT STAYS GREY AND GETS A LIT LINE INSIDE IT. Lighting the whole 0.20 m
	# slot was tried and on the small core the cap read as a lamp — the slot is
	# 2.31 m across, so it is the largest single face anywhere near the top.
	# Shortening it instead left it floating clear of the corbel neck it is
	# supposed to sit on. So: full-depth slot in plant metal, with a 0.06 m
	# reveal of glitch_tx_1 tucked under the deck overhang, 1.5 cm proud of the
	# slot so the line is the only part of it that shows.
	_part("PadSlot", Vector3(PAD * 1.78, 0.2, PAD * 1.78),
			Vector3(0, deck_top - DECK_T - 0.1, 0), Vector3.ZERO, _metal)
	# THE LAST RUNG. It is the highest lit piece on the model, so it is where the
	# travelling pulse arrives and dies — the band visibly reaches the pad and
	# stops, which is what makes the effect read as going somewhere.
	_lit("PadLight", _boxm(Vector3(PAD * 1.8, 0.06, PAD * 1.8)),
			Vector3(0, deck_top - DECK_T - 0.03, 0), Vector3.ZERO,
			deck_top - DECK_T - 0.03)
	_part("PadDeck", Vector3(PAD * 2.0, DECK_T, PAD * 2.0),
			Vector3(0, deck_top - DECK_T * 0.5, 0), Vector3.ZERO, _metal, true)
	var t := 0.14
	for sx: float in [-1.0, 1.0]:
		_part("PadKerbX%s" % ("Pos" if sx > 0.0 else "Neg"),
				Vector3(t, KERB_H, PAD * 2.0),
				Vector3(sx * (PAD - t * 0.5), deck_top + KERB_H * 0.5, 0),
				Vector3.ZERO, _metal)
	for sz: float in [-1.0, 1.0]:
		_part("PadKerbZ%s" % ("Pos" if sz > 0.0 else "Neg"),
				Vector3(PAD * 2.0 - t * 2.0, KERB_H, t),
				Vector3(0, deck_top + KERB_H * 0.5, sz * (PAD - t * 0.5)),
				Vector3.ZERO, _metal)
	# FOUR LANDING LUGS, and these are the TICK's interface — the designed one,
	# where the hack sheet had to go looking for "the only square level pair" on
	# the shipped core and found two corner posts by accident.
	#
	# The concept extrudes a chamfered square; an 8-sided cylinder 0.195 across
	# the corners is the same octagon to within a few millimetres at 0.36 m, and
	# it is one primitive instead of a polygon extrusion whose axis has already
	# cost this project a render. Turned 22.5 degrees so its flats face the axes.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_mesh(_structure, "PadLug%s" % _corner(sx, sz), _cylm(0.195, LUG_H, 8),
					Vector3(sx * (PAD - 0.26), deck_top + LUG_H * 0.5, sz * (PAD - 0.26)),
					Vector3(0, 22.5 * DEG, 0), _metal)


## THE COLOUR, and this is the maximalist answer in the set: FOUR BLADE FINS AT
## THE SHAFT'S CORNERS, each running the whole height of the shaft from a flared
## foot on the raft to a flared head under the corbel.
##
## ON THE DIAGONALS, so no two faces are ever hidden at once: from any bearing
## on the ground at least two fins are in profile and one is in plan. The heads
## reach the corbel at target - 1.26, which is the exact height the Tick cannot
## reach down to; the middles pass through 1.55 on both sides of the console
## bay; and nothing in this variant is on the pad, so the drone occludes none
## of it.
##
## ON THE FACES, NOT THE CORNERS — and this is a correction, not a preference.
##
## Built on the diagonals, as the concept drew them, the fins did not read as
## fins at any size. A blade at 45 degrees on a corner shows its NARROW EDGE to
## every orthogonal bearing, so the paint-only render came back as four bare
## posts round an empty frame, and in geometry the small core went further
## still: four chunky table legs with a 1.5 m shaft hidden behind them, reading
## as a stool carrying the pad. CORE_F_VARIANTS.md section 7 named the fix and
## this is it — on a face, the blade's WIDTH lies in the elevation, which is
## the only place a painted zone can be seen from.
##
## YAWED SO LOCAL +Z POINTS OUT. A rotation of t about Y takes +Z to
## (sin t, 0, cos t), so the yaw that points a blade's thickness along the
## outward normal (nx, 0, nz) is atan2(nx, nz) — and that puts its width,
## FIN_W, across the face where it shows. Getting this sign wrong lays every
## blade flat against the shaft instead of standing it off.
##
## THE APPROACH FACE GETS A SHORT ONE. -Z carries the console bay at y 1.1-2.0,
## and the jambs beside it are only (sw - min(sw*0.74, 1.5)) / 2 — 0.195 m on
## the small core, far too narrow to flank a 0.62 m blade. So the north fin
## starts ABOVE the bay and reads as a hood over the door. Four blades either
## way, so the painted silhouette keeps its four-fold symmetry in plan, and the
## front is still legibly the front.
func _fins(sw: float, neck: float) -> void:
	# normal x, normal z, tag
	for face in [[1.0, 0.0, "E"], [-1.0, 0.0, "W"], [0.0, 1.0, "S"], [0.0, -1.0, "N"]]:
		var nx: float = face[0]
		var nz: float = face[1]
		var tag: String = face[2]
		var yaw: float = atan2(nx, nz)
		# SEATED ON THE INSET BODY, NOT ON THE OLD FLUSH FACE. Since the cabinet
		# fell back by INSET, a blade left at sw * 0.5 would float clear of it.
		# Its BACK goes on the body face and its front lands all but flush with
		# the posts, so the fin reads as a mullion in the frame rather than a
		# buttress strapped to a box — which is the whole of the slimming.
		var off: float = sw * 0.5 - INSET + FIN_T * 0.5
		var at := Vector3(nx * off, 0, nz * off)
		var is_front: bool = tag == "N"
		var y0: float = 2.05 if is_front else GROUND
		var h: float = neck - y0
		if h <= 0.4:
			push_warning("build_core_f2: %.2f m of shaft above the console, so the north fin has nowhere to go" % h)
			continue
		_painted("Fin%sBlade" % tag, _boxm(Vector3(FIN_W, h, FIN_T)),
				at + Vector3(0, (y0 + neck) * 0.5, 0), Vector3(0, yaw, 0))
		# THE FOOT. A fin that meets a deck at a right angle reads as a sheet
		# standing in a slot; a flare reads as something welded. The north fin
		# starts in mid-air above a door and has no deck to meet.
		if not is_front:
			_painted("Fin%sFoot" % tag, _boxm(Vector3(FIN_W + 0.24, 0.26, FIN_T + 0.12)),
					at + Vector3(0, GROUND + 0.13, 0), Vector3(0, yaw, 0))
		# THE HEAD, under the corbel, and deliberately the heaviest section: at
		# 12.4 m the shaft's own courses carry the middle and only the head is
		# still a shape.
		_painted("Fin%sHead" % tag, _boxm(Vector3(FIN_W + 0.18, 0.34, FIN_T + 0.08)),
				at + Vector3(0, neck - 0.17, 0), Vector3(0, yaw, 0))

## -Z is the approach face, so -Z is north.
func _corner(sx: float, sz: float) -> String:
	return ("N" if sz < 0.0 else "S") + ("E" if sx > 0.0 else "W")


# ─────────────────────────────────────────────
# COLLISION
#
# ONE StaticBody3D, collision_mask = 0 — it is a thing to be hit and it tests
# nothing itself, which is what FuncGodot writes for worldspawn and what the
# shipped .map cores therefore already are.
#
# THE RAFT IS THE WHOLE FOOTPRINT, AND THAT IS DELIBERATE. A 0.52 m sheer step
# is not something the player's move_and_slide climbs, so the raft block stops
# them outside it — which is the arrangement the wrapper's reach box needs. If
# anybody later gives the player stair-stepping, this becomes a core you can
# stand on top of and the reach box must shrink to the shaft at the same time,
# or the camera ends up inside it and nothing can be pressed.
#
# The fins, the lip, the conduits, the studs, the kerb and the lugs have no
# collision: paint and fittings the player can brush past, and four blades on
# the diagonals would otherwise give a nav bake four 45-degree wedges to
# quantise around a box it already has.
# ─────────────────────────────────────────────
func _collision(sw: float, rw: float, neck: float) -> void:
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_mask = 0
	_root.add_child(body)
	body.owner = _root

	# The raft, as one block from the ground to the plate top. The pads and the
	# shadow gap are not modelled in collision on purpose — a 0.30 m slot the
	# player can get a foot into is worse than a solid kerb.
	_shape(body, "RaftBlock", Vector3(rw * 2.0, GROUND, rw * 2.0),
			Vector3(0, GROUND * 0.5, 0))
	# The shaft, as ONE box: the console recess is 0.49 m deep and giving it a
	# five-box collision would let the player stand inside the bay, which is
	# exactly where the 2 m raycast stops working.
	_shape(body, "ShaftBlock", Vector3(sw, neck - GROUND, sw),
			Vector3(0, (neck + GROUND) * 0.5, 0))
	# Everything above the shaft, as one column out to the corbel. Nothing can
	# reach it, but a core is cover and a round should stop on it.
	var cw: float = maxf(sw, PAD * 1.5) + 0.1
	var cap_top: float = neck + 1.26
	_shape(body, "CapBlock", Vector3(cw, cap_top - neck, cw),
			Vector3(0, (cap_top + neck) * 0.5, 0))


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
# MEASUREMENT — tools/check_frame.gd's _bounds, verbatim apart from the CSG
# clause, which cannot fire because nothing here is CSG. Kept in the same shape
# so a number printed by this file and a number printed by that one mean the
# same thing.
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


# ─────────────────────────────────────────────
# REGISTRATION — what a coordinator changes for a level to USE one of these.
#
# Nothing below has been done. These three scenes sit BESIDE the shipped cores;
# no wrapper, no mission and no .map has been repointed.
#
#   1. A new objective wrapper per size, copied from
#      Env/world_objects/compute_core_point{,_small,_large}.tscn with its
#      ext_resource "2_core" pointed at the F2 scene and its Terminal's
#      reach_size changed. THE FOOTPRINT MINUS 0.6, not the footprint — see the
#      raycast arithmetic in the header; the 0.6 is what puts the ray's origin
#      0.29 m outside the box instead of 0.011 m inside it:
#
#        small    res://maps/blocks/compute/compute_core_f2_small.tscn
#                 footprint 3.28 · reach_size Vector3(2.68, 3, 2.68)   was 1.88
#        medium   res://maps/blocks/compute/compute_core_f2.tscn
#                 footprint 4.43 · reach_size Vector3(3.83, 3, 3.83)   was 3.38
#        large    res://maps/blocks/compute/compute_core_f2_large.tscn
#                 footprint 6.30 · reach_size Vector3(5.70, 3, 5.70)   was 5.19
#
#      channel_range is measured from the INTERACTIBLE and has to clear where
#      the player actually stands — 1.89 / 2.47 / 3.40 m from the axis — plus
#      room to shuffle while the channel runs. Roughly 4.5 / 5.0 / 6.0, against
#      the shipped 4.5 on the medium.
#
#      indicator_height follows the core: 4.1 / 6.9 / 12.3 keeps the marker
#      just under the lug tops, where the shipped medium already puts it.
#
#   2. CoreSignal, if one is attached, should stop building its own
#      presentation. Its DeckCollar and ClimbBand are the placeholder this
#      replaces; the replacement is `get_node("Paint").get_children()`, nineteen
#      MeshInstance3D each with its own StandardMaterial3D to set albedo_color
#      AND `emission` on — both, or the glow keeps the old owner's colour. That
#      is a change to core_signal.gd, which this task did not touch.
#
#   3. Nav. The raft is a 0.52 m sheer step with a 3.28 / 4.43 / 6.30 m square
#      footprint — a bigger obstacle than the shipped cores at every size — so
#      any level that swaps one in needs its navmesh rebaked, and anything
#      placed within about a metre of the old footprint re-checked for overlap.
# ─────────────────────────────────────────────
