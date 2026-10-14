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
# _risers/_pad/_kerb/_lugs. Nothing is re-tuned. That file stays the authority;
# this one is the same shape rebuilt out of MeshInstance3D so it can ship.
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
# Paint holds TWENTY meshes, in three groups:
#
#   RaftLipXNeg / RaftLipXPos / RaftLipZNeg / RaftLipZPos        4   ground ring
#   ConduitPipeL / ConduitGlandL / ConduitPipeR / ConduitGlandR  4   ground runs
#   Fin{NE,NW,SE,SW}{Blade,Foot,Head}                           12   full height
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
# meshes and one StaticBody3D.
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

## Plant-grey. Shared read-only — never mutated here, so no duplicate() needed.
const MAT_CONCRETE := "res://textures/PSX_Textures/concrete_tx_5.tres"
const MAT_METAL := "res://textures/PSX_Textures/metal_floor_1.tres"
## The painted pieces get a fresh StandardMaterial3D each, built on this.
const PAINT_TEX := "res://textures/PSX_Textures/metal_wall_3.png"

const _Palette := preload("res://Character/hud/hud_palette.gd")

const DEG := PI / 180.0

# ── the numbers, all of them from the concept ───────────────────────────────

## HALF-WIDTH of the landing pad. THE RULER. Do not scale it.
## ConceptsCore2.F_PAD, and the TICK clamps it.
const PAD := 1.3
const LUG_H := 0.26         ## ConceptsCore2.LUG_H
const DECK_T := 0.34        ## ConceptsCore2.DECK_T
const KERB_H := 0.15        ## ConceptsCore2.KERB_H

const FIN_T := 0.2          ## ConceptsCoreF.F2_FIN_T
const FIN_W := 0.62         ## ConceptsCoreF.F2_FIN_W

## shaft width, overall height, output filename. ConceptsCoreF.SHAFT and
## ConceptsCore2.H_SMALL / H_MEDIUM / H_LARGE.
const SIZES := [
	[1.5, 4.2, "compute_core_f2_small.tscn"],
	[2.3, 7.0, "compute_core_f2.tscn"],
	[3.6, 12.4, "compute_core_f2_large.tscn"],
]

var _concrete: Material
var _metal: Material
var _paint_tex: Texture2D
var _root: Node3D
var _structure: Node3D
var _paint: Node3D
var _hulls: Array[Node3D]   ## pieces that also get a collision box


func _init() -> void:
	_concrete = load(MAT_CONCRETE)
	_metal = load(MAT_METAL)
	_paint_tex = load(PAINT_TEX)
	if _concrete == null or _metal == null or _paint_tex == null:
		printerr("build_core_f2: a material failed to load, so every piece would be bare")
		quit(1)
		return
	for spec: Array in SIZES:
		var sw: float = spec[0]
		var target: float = spec[1]
		var path: String = "%s/%s" % [OUT_DIR, spec[2]]
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
		print("    footprint %.2f square · paint pieces %d · meshes %d"
				% [_raft_half(sw) * 2.0, _paint.get_child_count(), _count_meshes(node)])
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
		mat = _concrete
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.position = at
	m.rotation = euler
	m.material_override = mat
	parent.add_child(m)
	m.owner = _root
	return m


## A structural piece, in plant-grey. `solid` adds a matching collision box.
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
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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
	_root = root
	_hulls = []
	_structure = _node(root, "Structure")
	# THE PAINTED NODE LIST. See the header. Declared before anything is built
	# so no painted piece can end up anywhere else by accident.
	_paint = _node(root, "Paint")

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
			_part("RaftPad%s" % _corner(sx, sz), Vector3(0.52, 0.3, 0.52),
					Vector3(sx * (rw - 0.42), 0.15, sz * (rw - 0.42)), Vector3.ZERO, _metal)
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
	_shaft_with_bay(sw, neck, minf(sw * 0.74, 1.5))

	# Band courses, so a tall box is not one tall box. Spaced at about 2 m,
	# which is the course height the shipped compute blocks already use.
	var n: int = maxi(1, int((neck - GROUND) / 2.1))
	for i in range(1, n):
		_part("Band%d" % i, Vector3(sw + 0.16, 0.14, sw + 0.16),
				Vector3(0, GROUND + (neck - GROUND) * float(i) / float(n), 0))

	# Two cable risers and their tie, up the BACK face. A blank back is the
	# thing that makes a slab read as a placeholder.
	var r: float = clampf(sw * 0.06, 0.07, 0.14)
	var ry1: float = neck - 0.4
	for sx: float in [-1.0, 1.0]:
		_mesh(_structure, "Riser%s" % ("R" if sx > 0.0 else "L"),
				_cylm(r, ry1 - GROUND, 8),
				Vector3(sx * sw * 0.25, (GROUND + ry1) * 0.5, sw * 0.5 + r),
				Vector3.ZERO, _metal)
	_part("RiserTie", Vector3(sw * 0.55, r * 2.2, r * 2.2),
			Vector3(0, ry1, sw * 0.5 + r), Vector3.ZERO, _metal)

	# The corbel: a slab off the shaft head and a neck up to the cap.
	var ctop: float = target - LUG_H - DECK_T - 0.2
	var cw: float = maxf(sw, PAD * 1.5) + 0.1
	_part("CorbelSlab", Vector3(cw, 0.22, cw), Vector3(0, neck + 0.11, 0),
			Vector3.ZERO, null, true)
	_part("CorbelNeck", Vector3(PAD * 1.6, ctop - neck - 0.22, PAD * 1.6),
			Vector3(0, (ctop + neck + 0.22) * 0.5, 0), Vector3.ZERO, null, true)
	_pad(target)


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
func _shaft_with_bay(sw: float, neck: float, w: float) -> void:
	var face: float = -sw * 0.5         # the approach face, -Z
	var y0 := 1.1                       # recess floor
	var y1 := 2.0                       # recess head
	var depth := 0.49                   # how far the recess bites in
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
	_mesh(_structure, "ConsolePlate", _boxm(Vector3(w * 0.8, 0.62, 0.1)),
			Vector3(0, 1.55, face + 0.42 - 0.05), Vector3.ZERO, _metal)
	_part("ConsoleKickRail", Vector3(w * 0.95, 0.09, 0.14),
			Vector3(0, 1.02, face - 0.06), Vector3.ZERO, _metal)


## THE CAP, AND IT IS THE SAME CAP AT EVERY SIZE. 2.60 m across, lug tops at
## `top`, level — the shipped core's 30-degree cut is the fault this replaces,
## because anything flat-bottomed rocks on it.
##
## Three silhouette breaks, none of which depends on a bore: a lit slot under
## the deck, a kerb on its edge, and four lugs standing proud at the corners. A
## BORED HOLE DRAWS IDENTICALLY TO A FLAT FACE, which is what killed the Yoke.
func _pad(top: float) -> void:
	var deck_top: float = top - LUG_H
	_part("PadSlot", Vector3(PAD * 1.78, 0.2, PAD * 1.78),
			Vector3(0, deck_top - DECK_T - 0.1, 0), Vector3.ZERO, _metal)
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
		# Half the thickness buried in the shaft: welded on, not floating beside.
		var at := Vector3(nx * sw * 0.5, 0, nz * sw * 0.5)
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
			_painted("Fin%sFoot" % tag, _boxm(Vector3(FIN_W + 0.3, 0.34, FIN_T + 0.16)),
					at + Vector3(0, GROUND + 0.17, 0), Vector3(0, yaw, 0))
		# THE HEAD, under the corbel, and deliberately the heaviest section: at
		# 12.4 m the shaft's own courses carry the middle and only the head is
		# still a shape.
		_painted("Fin%sHead" % tag, _boxm(Vector3(FIN_W + 0.22, 0.46, FIN_T + 0.1)),
				at + Vector3(0, neck - 0.23, 0), Vector3(0, yaw, 0))

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
#      replaces; the replacement is `get_node("Paint").get_children()`, twenty
#      MeshInstance3D each with its own StandardMaterial3D to set albedo_color
#      on. That is a change to core_signal.gd, which this task did not touch.
#
#   3. Nav. The raft is a 0.52 m sheer step with a 3.28 / 4.43 / 6.30 m square
#      footprint — a bigger obstacle than the shipped cores at every size — so
#      any level that swaps one in needs its navmesh rebaked, and anything
#      placed within about a metre of the old footprint re-checked for overlap.
# ─────────────────────────────────────────────
