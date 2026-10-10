extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/bastion.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_bastion.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. A robot scene is thirty
# sub-resources with hand-numbered ids and an exact load_steps count, and
# writing that by hand is transcription with nothing to learn from. It is NOT a
# build step: re-running it after the scene has been touched in the editor
# throws that work away, which is how --force rebuilds have repeatedly cost this
# project its gameplay layers. If the geometry needs changing after today,
# change the scene.
#
# ── WHAT THIS IS ─────────────────────────────
#
# BASTION — StratCom, supply 3, ground, deployable hardpoint, enemy only. It
# walks, then plants: immobile, heavily armoured, and projecting a field that
# hardens nearby StratCom units against suppression. Concept B, THE PYLON
# (planted), out of ConceptsC.bastion_b() — legs locked straight, four long
# outriggers hammered down, the field held overhead as a canopy hoop on a mast.
#
# THIS FRAME IS SUPPOSED TO LOOK RIGHT, and that is the faction statement.
# StratCom is the player's own parent organisation, so the Bastion is built out
# of the PLAYER's vocabulary on purpose — the Walker's chamfered hull with its
# sloped glacis and cut tail, the turret ring, the box turret with its cheek and
# brow sliced off, ONE eye offset to port, the whip antenna, boxy limbs — with
# more plate on it and better finished. Every other enemy frame in this batch is
# built to look wrong. This one is the army the player's own side belongs to.
#
# ── SCOPE: THE MODEL, AND NOTHING ELSE ───────
#
# No ChassisDefinition, no catalogue entry, no weapon item, no bastion.gd, no
# faction. The root script is walker.gd, which is the right existing script: a
# legged frame with a real turret and the Walker's gait, traverse and facing are
# all generic.
#
# NO FACTION IS SET, DELIBERATELY. docs/frames/ENEMY_FACTIONS.md is why:
# Enums.are_hostile() matches four values and falls out to `return false`, so a
# robot carrying a fifth is simultaneously invisible and near-invulnerable
# across thirty-five call sites, not one of which errors. This frame therefore
# ships as ENEMY (enemy.gd's default) until are_hostile is a table. That work is
# gated and is not this pass's.
#
# ── THE GEOMETRY IS THE CONCEPT, REBUILT ─────
#
# ConceptsC.bastion_b() is the authority on silhouette and position. Two
# systematic changes, both for the same reason the Lance's generator needed
# them:
#
#   1. THE VERTICAL ORIGIN. The concept builders put ground at y = 0; a robot
#      scene has to put the body origin where the collision capsule's bottom
#      touches the ground. GROUND below is that offset and every y is written as
#      GROUND + <the concept's own y>, so the two files read side by side.
#   2. THE PARTS GO THROUGH _mesh / _hull / _cut. ConceptKit's shapes are raw
#      CSG with no material and no scene ownership, which is fine for a concept
#      render and wrong for a shipping scene. The concept's chamfered
#      CSGPolygon3D plates and wedges are rebuilt as CSGMesh3D boxes with bevel
#      cuts taken off them, which is the idiom walker.tscn, rover.tscn,
#      bulwark.tscn and lance.tscn already use.
#
# And five judged departures, each with a reason:
#
#   THE TWO SIDE OUTRIGGERS LEAN OUTWARD. In the concept they lean INWARD, under
#   the hull — `_spade(… -1.1 …, -90.0, …)` yaws so the ram's own -Z lands on
#   +X. That is exactly the error concepts_c.gd's own docstring warns about two
#   lines above the call ("leaning them in the root's frame instead is this
#   project's commonest error: all four then lean the same way and two of them
#   drive into the hull"). Port takes yaw +90 and starboard -90 here, so all
#   four lean along their own radius, which is what the helper says it is for.
#   The roots moved inboard to x ±0.54 to keep the measured width at the
#   concept's 3.44 once they do.
#
#   THE TURRET IS CENTRED AND THE MAST MOVED AFT. The concept hangs the head at
#   x -0.5 so the mast can own the middle. That works for a still and not for a
#   frame whose turret TRAVERSES: the head sweeps a 0.70 m circle about its ring
#   and the mast is 0.54 across, so an off-centre head on a centred mast grinds
#   through it at every bearing. The ring is on the centreline at z -0.55 where
#   the player's own frames put it, the mast stands on the aft deck at z +0.70,
#   and the mast is raked 20 degrees forward so the canopy still lands over the
#   middle of the frame. Measured: 1.25 m between the two axes against the
#   0.98 m the sweep needs.
#
#   THE TURRET RING IS WIDER THAN THE TURRET. ConceptKit.head() has a known
#   fault — the brief flags it — where the ring sits at `at` and the turret body
#   at `at + 0.19 * scale` with the body taller than the gap, so the ring is
#   INSIDE the body at every scale and has never been visible. Fixed by moving
#   it rather than dropping it: r 0.62 against a turret 0.47 across the half
#   width and 0.52 across the half length, seated on the deck with the body's
#   underside 0.02 above its top face. It is the single cheapest piece of family
#   resemblance on the frame and it had to actually be on screen.
#
#   FOUR STAYS AND FOUR EMITTER HEADS UNDER THE HOOP, not three. The doc is
#   emphatic that the planted state has to be legible from any angle, and
#   three-fold symmetry on a frame approached from any bearing gives a different
#   silhouette front-on and side-on. Four reads the same from all four
#   quadrants, which also suits "more of it and better finished".
#
#   SKIRTS. BASTION.md section 5 lists "Spades / skirts: deployed when planted"
#   and says in terms "spades down, skirts out, projector lit"; concept B has no
#   skirts, because the skirts belong to option A, where they exist to occlude
#   the legs entirely. B wins on the opposite read — locked legs as columns —
#   so these are HIP APRONS: they hang from the hull's lower flank to y 0.92 and
#   cover the hip joints, leaving the whole lower half of each leg, both knee
#   collars and all four feet visible below them. Outboard of the thighs by
#   0.10 m, on a bracket, so they stand off the hull and break the outline.
#
# ── WHAT AN UNPLANT WOULD HAVE TO MOVE ───────
#
# The scene is the PLANTED state. There is no bastion.gd yet, so nothing stows
# anything; the nodes a future one needs are named and nested for it:
#
#   Rig/Outriggers/Outrigger{F,A,L,R}/Ram
#       Each Ram carries the whole beam-jack-blade assembly and nothing else.
#       Stowing is: Ram.rotation.x from PLANT_LEAN (28 deg) back toward 0 —
#       which folds it flat under the belly — or, for the concept-C read,
#       up the flank blade-first. The Jack mesh should retract into the Beam's
#       Gland at the same time; it is a separate node for exactly that.
#   Rig/Mast  (rake) and Rig/Mast/Canopy  (level)
#       Mast.rotation.x from -MAST_RAKE to about -90 deg lays the column down
#       fore-and-aft on the back deck. Canopy counter-rotates the hoop level, so
#       a stow has to drive both or the hoop ends up on edge. Rig/MastCollar
#       stays put: it is hull.
#   Rig/Skirts/Skirt{L,R}
#       Hinge nodes. rotation.z from ±SKIRT_CANT to about ∓80 deg swings each
#       apron up against the flank. Rig/Skirts/Bracket{L,R} are hull and must
#       not move with them, which is why they are on the container and not on
#       the hinges.
#   Rig/Mast/Canopy/Lenses/*
#       The projector's lit faces. Their material is the only non-metal,
#       non-eye material on the frame; unplanting kills the emission.
#
# The legs need nothing: walker.gd's gait already drives HipL/HipR and their
# knees, and the planted pose is their rest pose.
#
# ── WHY THE HIPS CARRY NO ROTATION ───────────
#
# walker.gd's _pose_leg writes hip.rotation.x, hip.rotation.z, knee.rotation.x,
# foot.rotation.x and foot.rotation.z ABSOLUTELY, every physics frame, including
# at a dead stop where it writes zeroes. Any splay baked onto a hip node is
# therefore erased on the first tick and the frame's legs snap vertical. The
# concept's splay and fore-aft reach live on a Splay child instead — which is
# what walker.tscn itself does, with the 15-degree thigh tilt on the ThighL mesh
# and HipL left at identity.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/bastion.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
## walker.gd, not a new bastion.gd. Legged, with a real turret and a real
## traverse; the gait, the facing split and the pitch clamp are all generic.
const BODY_SCRIPT := "res://Character/characters/ai/walker.gd"
## The Walker's own two clips. Same factory, same voice — deliberately, this
## being the one enemy frame that is supposed to sound issued.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__23.wav"

const DEG := PI / 180.0
## The Walker's eye is a plain StandardMaterial3D with this as its albedo — not
## the shared faction metal. Carried over verbatim so the two frames' eyes are
## the same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

# ── THE VERTICAL ORIGIN ──
#
# The capsule is sized to the BODY — hull, belly deck and legs — and not to the
# mast, the same way the Bulwark's capsule stops below its shield: 3.9 m of a
# 4.47 m frame, which puts the canopy hoop above it as unshot structure. Its
# bottom is ground, so GROUND converts every concept y (ground = 0) into scene
# space, and the feet sink 3.5 cm below it the way the Walker's sink 17.
const CAP_R := 1.05
const CAP_H := 3.90
const GROUND := -CAP_H * 0.5

# ── THE PLANTED STATE, AS NUMBERS ──
const PLANT_LEAN := 28.0        # outrigger ram, degrees off vertical
const PLANT_REACH := 1.82       # ram axis length to the blade's centre
const MAST_RAKE := 20.0         # forward rake, so the canopy lands over the middle
## 1.54, which is measured against check_frame's box and not chosen: the first
## pass at 1.62 put the hoop's crown 0.08 m above BASTION.md's quoted 4.48, and
## the mast is the one piece on the frame whose length nothing else depends on.
const MAST_LEN := 1.54
const SKIRT_CANT := 8.0         # hip apron, splayed out at the bottom

var _metal: Material
var _root: CharacterBody3D


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_bastion: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_bastion: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_bastion: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
#
# Everything visible goes through _mesh or _hull, both of which assign the
# shared robot_metal material and the scene owner PackedScene.pack() needs, so
# no piece can be left unpainted or unowned. A single unpainted mesh is
# invisible as a bug until someone renders the frame in a faction colour.
#
# The two exceptions are the EYE and the projector LENSES, and both are
# precedented: walker.tscn's Eye carries its own StandardMaterial3D and so do
# its LampL/LampR, and none of the three is in that scene's livery list.
# ─────────────────────────────────────────────

func _mesh(parent: Node, nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.position = at
	m.rotation = euler
	m.material_override = _metal
	parent.add_child(m)
	m.owner = _root
	return m


func _node(parent: Node, nm: String, at: Vector3, euler: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = at
	n.rotation = euler
	parent.add_child(n)
	n.owner = _root
	return n


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A CSG box used as a CUT. Subtractions are how this family gets its sloped
## glacis, its cut tail and its chamfered flanks, and reusing them is most of
## why a new frame reads as coming out of the same factory.
func _cut(parent: Node, nm: String, size: Vector3, at: Vector3,
		euler: Vector3 = Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = nm
	b.size = size
	b.position = at
	b.rotation = euler
	b.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(b)
	b.owner = _root
	return b


## A CSG hull: a box with cuts taken out of it. Baked at boot by csg_bake.gd,
## which is the only reason these may exist at all — see that file for the
## 335 ms spike that made baking compulsory.
func _hull(parent: Node, nm: String, size: Vector3, at: Vector3,
		euler: Vector3 = Vector3.ZERO) -> CSGMesh3D:
	var h := CSGMesh3D.new()
	h.name = nm
	h.mesh = _boxm(size)
	h.position = at
	h.rotation = euler
	h.material = _metal
	parent.add_child(h)
	h.owner = _root
	return h


## ONE TOP-FLANK CHAMFER, in the family's own proportions rather than in numbers
## chosen by eye: a cut 70% of the width and 80% of the height, seated at 68% of
## the half-width and 66% of the half-height, turned 30 degrees. Lifted off
## ConceptKit.hull, which lifted it off walker.tscn. `up` flips it to the BOTTOM
## corners, which is what the belly deck wants.
func _bevel(hull: CSGMesh3D, size: Vector3, s: float, nm: String,
		up: bool = true) -> void:
	var sign_y := 1.0 if up else -1.0
	_cut(hull, nm, Vector3(size.x * 0.7, size.y * 0.8, size.z * 1.4),
			Vector3(s * size.x * 0.68, sign_y * size.y * 0.66, 0),
			Vector3(0, 0, s * sign_y * 30.0 * DEG))


func _sphere_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _cyl_mesh(r: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 0
	return c


## A truncated cone. `top` and `bottom` are the two radii, so a dish aimed at
## the ground is written with the WIDE radius at the bottom — the sign the
## concept file flags twice, in the other direction, for muzzle brakes.
func _cone_mesh(top: float, bottom: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	c.rings = 0
	return c


func _torus_mesh(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 20
	t.ring_segments = 6
	return t


## Bolt heads in a row, which is what makes a plate look BOLTED ON rather than
## floating a centimetre off the hull. `axis` is the euler that lays the stud's
## cylinder into the face it sits on.
func _studs(parent: Node, nm: String, count: int, from: Vector3, step: Vector3,
		axis: Vector3, r: float = 0.034) -> void:
	for i in count:
		_mesh(parent, "%s%d" % [nm, i], _cyl_mesh(r, r * 1.4, 6),
				from + step * float(i), axis)


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object and this project has already
## paid for that once — see the duplicate() rule in CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m


## THE PROJECTOR'S LIT FACES. The same trick walker.tscn's LampL/LampR use — an
## emissive StandardMaterial3D, outside the livery — because the planted state
## has to be readable and "projector lit" is a third of that read. Institutional
## green rather than the lamps' warm white: this is StratCom's own field, and the
## colour is the one already written and waiting at hud_palette.gd:63.
func _projector_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.95, 0.80)
	m.emission_enabled = true
	m.emission = Color(0.42, 0.90, 0.52)
	m.emission_energy_multiplier = 2.6
	return m


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Bastion"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's second
	# argument defaults to false, meaning "for this run only" — a frame built
	# without it packs with no groups line, and a robot outside "enemies" is
	# invisible to AIManager, to EMP and to every hostile sweep in the game while
	# still standing there looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision and senses ──
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_R
	cap.height = CAP_H
	col.shape = cap
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, or the assignment is silently dropped. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three default clips instead. That line was untyped in the
	# worked example for the Bulwark's whole life and bulwark.tscn shipped with
	# the wrong voice because of it — nobody noticed, because it still barks.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# Lower and narrower than the Walker's 0.72-0.80. Three and a half metres of
	# plate standing still.
	bark.set("pitch_min", 0.58)
	bark.set("pitch_max", 0.66)
	root_body.add_child(bark)
	bark.owner = root_body

	var nav := NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	root_body.add_child(nav)
	nav.owner = root_body

	var det := Area3D.new()
	det.name = "Detection"
	root_body.add_child(det)
	det.owner = root_body
	var dcol := CollisionShape3D.new()
	dcol.name = "CollisionShape3D"
	var dsphere := SphereShape3D.new()
	dsphere.radius = 25.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body

	# ── the rig ──
	var rig := _node(root_body, "Rig", Vector3.ZERO)

	# THE HULL, in the player's own chamfered vocabulary at supply-3 size:
	# 2.5 x 1.3 x 2.3, sloped glacis off the nose, cut-back tail, bevels down
	# both top flanks. Proportions are ConceptKit.hull's, which are walker.tscn's.
	var hull_size := Vector3(2.5, 1.3, 2.3)
	var hull := _hull(rig, "Hull", hull_size, Vector3(0, GROUND + 2.25, 0))
	_cut(hull, "Glacis", Vector3(hull_size.x * 1.4, hull_size.y * 1.2, hull_size.z * 0.8),
			Vector3(0, -hull_size.y * 0.72, -hull_size.z * 0.62), Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(hull_size.x * 1.4, hull_size.y * 1.2, hull_size.z * 0.6),
			Vector3(0, -hull_size.y * 0.68, hull_size.z * 0.64), Vector3(20.0 * DEG, 0, 0))
	_bevel(hull, hull_size, -1.0, "BevelL")
	_bevel(hull, hull_size, 1.0, "BevelR")

	# THE BELLY DECK. The glacis and tail cuts take the hull's lower nose and
	# lower stern away, which leaves the four outriggers' roots hanging in open
	# air underneath it — the fore one measurably so. This is the deployment deck
	# they come out of, and it also sockets the four hip balls. Chamfered on its
	# BOTTOM corners, because it is a belly.
	var deck_size := Vector3(1.9, 0.4, 1.9)
	var deck := _hull(rig, "BellyDeck", deck_size, Vector3(0, GROUND + 1.6, 0))
	_bevel(deck, deck_size, -1.0, "ChamferL", false)
	_bevel(deck, deck_size, 1.0, "ChamferR", false)

	_applique(rig)
	_antenna(rig)
	var turret := _turret(rig)
	var mast := _mast(rig)
	_outriggers(rig)
	_skirts(rig)
	var legs := _legs(rig)

	# ── effects, livery ──
	var spark := (load(SPARK) as PackedScene).instantiate()
	spark.name = "SparkBurst"
	root_body.add_child(spark)
	spark.owner = root_body
	var oil := (load(OIL) as PackedScene).instantiate()
	oil.name = "OilSpray"
	root_body.add_child(oil)
	oil.owner = root_body

	var livery := Node.new()
	livery.name = "FactionLivery"
	livery.set_script(load(LIVERY))
	root_body.add_child(livery)
	livery.owner = root_body
	livery.set("base_material", _metal)
	livery.set("paint_blend", 1.0)
	livery.set("marker_energy", 2.2)
	# EVERY PAINTED PIECE, in a TYPED array.
	#
	# `pieces` is Array[Node3D]; an untyped one lands as [] and FactionLivery
	# then falls back to walking its WHOLE PARENT — which paints every mesh on
	# the frame, the EYE INCLUDED. That is how the Bulwark's eye ended up
	# faction-coloured despite being carefully left off this list: the list
	# itself was never there.
	#
	# FactionLivery._gather recurses, so a container node paints everything under
	# it. That is why the entries below are containers wherever a subtree is
	# entirely metal, and individual meshes wherever a subtree is not:
	#
	#   Turret is NOT listed      — the Eye hangs off it.
	#   Mast is NOT listed        — the projector Lenses hang off its Canopy.
	#
	# THE EYE AND THE LENSES ARE DELIBERATELY ABSENT. The eye keeps the Walker's
	# own StandardMaterial3D, because the one feature that identifies a robot in
	# this game must not change colour per faction. The lenses keep an emissive
	# material for the same reason walker.tscn's lamps do.
	var paint: Array[Node3D] = []
	paint.append(hull)
	paint.append(deck)
	paint.append(rig.get_node("AppliqueL"))
	paint.append(rig.get_node("AppliqueR"))
	paint.append(rig.get_node("Antenna"))
	paint.append(rig.get_node("TurretRing"))
	paint.append(turret.get_node("TurretBody"))
	paint.append(turret.get_node("GunPivot"))
	paint.append(rig.get_node("MastCollar"))
	paint.append(mast.get_node("Column"))
	paint.append(mast.get_node("Gland"))
	paint.append(mast.get_node("Canopy/Hub"))
	paint.append(mast.get_node("Canopy/Hoop"))
	paint.append(mast.get_node("Canopy/Stays"))
	paint.append(mast.get_node("Canopy/Emitters"))
	paint.append(rig.get_node("Outriggers"))
	paint.append(rig.get_node("Skirts"))
	for hip in legs:
		paint.append(hip)
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D,
	# NavigationAgent3D, Bark, Area3D or Array[Node3D] — not NodePath — so
	# assigning a NodePath silently does nothing and the frame comes out with a
	# null turret and legs the gait cannot find. Nothing errors.
	# PackedScene.pack() turns these references back into the
	# `node_paths=PackedStringArray(...)` form the editor writes, so the saved
	# scene looks hand-authored either way.
	root_body.set("rig", rig)
	# THE GAIT DRIVES THE FORE PAIR. walker.gd has two hips and this frame has
	# four; the fore pair is what a viewer watches, and on a planted frame none
	# of it moves anyway. The aft pair is built identically so the day bastion.gd
	# wants a four-legged gait, the nodes are already there and symmetrical.
	root_body.set("hip_left", rig.get_node("HipL"))
	root_body.set("knee_left", rig.get_node("HipL/SplayL/KneeL"))
	root_body.set("hip_right", rig.get_node("HipR"))
	root_body.set("knee_right", rig.get_node("HipR/SplayR/KneeR"))
	root_body.set("foot_left", rig.get_node("HipL/SplayL/KneeL/FootL"))
	root_body.set("foot_right", rig.get_node("HipR/SplayR/KneeR/FootR"))
	# A REAL TURRET AND A REAL TRAVERSE, not the stub the Lance and the Picket
	# need. It also satisfies the rule BASTION.md section 5 flags:
	# `hull_spoils_aim` in enemy.gd:2894 is excused by a property literally named
	# `turret` being non-null, so a frame with a null turret never settles its
	# aim and never leaves WeaponState.AIM while moving.
	root_body.set("turret", turret)
	root_body.set("gun_pivot", turret.get_node("GunPivot"))
	root_body.set("weapon_mount", turret.get_node("GunPivot/WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY. particle_effects_die and
	# particle_effects_hit are Array[ParticleEffect] and visible_pieces is
	# Array[Node3D]; a plain untyped Array assigned to any of them fails SILENTLY
	# and the packed scene comes out with []. The Bulwark's first build shipped
	# all three empty — no death effects, no hit sparks.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	var vis: Array[Node3D] = []
	vis.append(hull)
	vis.append(turret.get_node("TurretBody"))
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	root_body.set("activation_distance", 200)
	# BASTION.md section 3. 300, under the Bulwark's 400: it is not a duel.
	root_body.set("health", 300)
	root_body.set("max_health", 300)
	# ZERO, BECAUSE THE SCENE IS THE PLANTED STATE. Section 3 gives 0.6 walking
	# and 0.0 planted, and there is no bastion.gd to tell the two apart — a
	# Bastion that crawled with its outriggers hammered into the soil and its
	# mast up would read as broken. enemy.gd handles it: `base_dir * move_speed`
	# is simply zero, and the one place that would divide guards itself with
	# maxf(move_speed, 1.0) at enemy.gd:1736. Whoever writes the plant/unplant
	# state raises this to 0.6 for the walking half.
	root_body.set("move_speed", 0.0)
	root_body.set("soldier_name", "Bastion")
	root_body.set("flatten_collider_when_downed", false)
	# Section 3's base_sensor_range. It is a plain export on Enemy, so it is in
	# scope here; the ChassisDefinition that will carry the same number is not.
	root_body.set("sensor_range", 60.0)
	# THE HARDENING FRAME IS ITSELF HARDENED. A plain export on AI
	# (ai.gd:67) — ChassisDefinition has no signal field — and it divides both
	# incoming suppression and the length of an EMP lock (ai.gd:117, 138).
	root_body.set("signal_resistance", 2.0)
	# Slower than the Walker's 55 and slower than the Bulwark's 42. Flanking a
	# hardpoint is the counter and it should be a real one.
	root_body.set("turret_traverse_degrees", 34.0)
	return root_body


# ─────────────────────────────────────────────
# THE STRATCOM TELL
# ─────────────────────────────────────────────
## APPLIQUÉ ON THE HULL FLANKS, BOLTED. More plate than the player's own frames
## carry and better finished — that is the entire faction statement, and it is
## the same idiom rover_veteran() uses for the player's veteran kit, which is the
## point: this is where that kit comes from.
##
## Seated at x ±1.29 against a hull flank at ±1.25, so it stands 0.04 proud and
## reads as a separate course rather than as a thicker hull. Above the skirt
## hinge at y 1.62 and below the top-flank bevel at 3.11, which is the one band
## of this hull that is flat on both sides.
func _applique(rig: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		var grp := _node(rig, "Applique%s" % tag, Vector3.ZERO)
		var size := Vector3(0.12, 0.6, 1.9)
		var plate := _hull(grp, "Plate", size, Vector3(s * 1.29, GROUND + 2.2, 0))
		# Lower corners raked off both ends, so the course is a pressed plate and
		# not a slab taped to the side. A BOX ROTATED 45 DEGREES IS A DIAMOND and
		# it is symmetric about both axes, so one rotation serves both corners —
		# what matters is that the cut is centred ON the corner, not near it.
		_cut(plate, "EndF", Vector3(0.4, 0.4, 0.4), Vector3(0, -0.3, -0.95),
				Vector3(45.0 * DEG, 0, 0))
		_cut(plate, "EndA", Vector3(0.4, 0.4, 0.4), Vector3(0, -0.3, 0.95),
				Vector3(45.0 * DEG, 0, 0))
		# Bolt heads on the plate's outer face, axis along X so the heads face
		# outboard where a three-quarter view sees them.
		_studs(grp, "Stud", 4, Vector3(s * 1.37, GROUND + 2.42, -0.6),
				Vector3(0, 0, 0.4), Vector3(0, 0, PI * 0.5), 0.032)


## THE WHIP, AND IT IS ON THE HULL RATHER THAN ON THE TURRET.
##
## On the Walker — and on the Bulwark, and in ConceptKit.head — the whip rides
## the head, and that is where it was built here first. Rendered beside the
## Walker it had vanished: capped at 0.56 m it is a third of the Walker's whip
## on a frame half again as tall, and it was capped because of what is over it.
## Measured, on the turret:
##
##   the antenna sweeps a circle of radius 0.52 about the ring, and the ring is
##   0.70 from the canopy's axis, so its distance from that axis runs 0.18 to
##   1.22 as the turret traverses — straight under the hub at one end of that
##   range and straight under the hoop's own tube (1.12 to 1.32) at the other.
##   The four stays dip to 3.92 across the middle of it. There is no length
##   that is safe at every bearing, and a whip that is only correct while the
##   turret faces forward is a clash waiting for the first fight.
##
## On the hull it is fixed, so it is measurable once: at (-0.80, -0.85) it
## stands 0.85 from the turret's 0.70 sweep and 1.30 from the canopy axis, which
## is just inside the hoop's tube — hence 1.06 m, topping out at 3.98 against
## the hoop's underside at 4.13.
##
## Seated at x -0.80 and not further out: the hull's top-flank bevel has eaten
## everything outboard of about 0.82 at this height, and an antenna bolted to a
## chamfer floats in mid-air.
func _antenna(rig: Node3D) -> void:
	var grp := _node(rig, "Antenna", Vector3(-0.8, GROUND + 2.86, -0.85))
	_mesh(grp, "Base", _boxm(Vector3(0.16, 0.18, 0.16)), Vector3.ZERO)
	_mesh(grp, "Whip", _boxm(Vector3(0.03, 1.06, 0.03)), Vector3(0, 0.59, 0))


# ─────────────────────────────────────────────
# THE TURRET
# ─────────────────────────────────────────────
## The Walker's head, at 0.8 scale, on a ring that is actually visible.
##
## FORWARD OF CENTRE AT z -0.55, which is what buys the mast the aft deck: the
## head's sweep radius about this axis is sqrt(0.472² + 0.52²) = 0.70 and the
## mast's widest radius is 0.27, so the two axes need 0.97 m between them and
## they have 1.25.
##
## IT IS A TRAVERSE, NOT A STUB. walker.gd slews turret.rotation.y toward the
## target at turret_traverse_degrees per second and pitches GunPivot between
## gun_min_pitch_degrees and gun_max_pitch_degrees, so the pivot starts at zero
## where the aiming code expects to find it. heavy_mg fits on WeaponMount.
func _turret(rig: Node3D) -> Node3D:
	# THE RING IS WIDER THAN THE TURRET AND SITS ON THE DECK. See the header:
	# ConceptKit.head() puts it inside the turret body at every scale, where it
	# has never been visible on any concept sheet. r 0.62 against a body 0.47
	# across the half width and 0.52 across the half length leaves it proud on
	# every bearing.
	_mesh(rig, "TurretRing", _cyl_mesh(0.62, 0.14, 14), Vector3(0, GROUND + 2.92, -0.55))
	var turret := _node(rig, "Turret", Vector3(0, GROUND + 2.99, -0.55))

	# A box with its cheek sliced off below and its brow sliced off above, which
	# with one offset eye is how a frame in this game is recognised at forty
	# pixels. Cut proportions are ConceptKit.head's, which are walker.tscn's.
	var body_size := Vector3(0.944, 0.48, 1.04)
	var body := _hull(turret, "TurretBody", body_size, Vector3(0, 0.26, 0))
	_cut(body, "Cheek", Vector3(1.2272, 0.56, 0.56), Vector3(0, -0.352, -0.688),
			Vector3(-35.0 * DEG, 0, 0))
	_cut(body, "Brow", Vector3(1.2272, 0.56, 0.56), Vector3(0, 0.4, -0.624),
			Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, OFFSET TO PORT, and the Walker's own material rather than the
	# shared metal — a StandardMaterial3D with the eye texture as albedo.
	# Painting it with faction livery like everything else would make the one
	# feature that identifies a robot in this game change colour per faction, so
	# it is deliberately left out of the livery list in _build.
	#
	# A CHILD OF Turret AND NOT OF TurretBody, which matters: FactionLivery's
	# _gather recurses, so an eye under a listed piece is painted anyway.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.136
	eye_mesh.height = 0.224
	eye_mesh.radial_segments = 16
	eye_mesh.rings = 8
	var eye := _mesh(turret, "Eye", eye_mesh, Vector3(-0.272, 0.372, -0.528))
	eye.material_override = _eye_material()

	# GunPivot elevates and nothing else, and the mantlet and the mount ride it,
	# at the Walker's own offsets scaled by 0.8.
	var pivot := _node(turret, "GunPivot", Vector3(0, 0.228, -0.4))
	_mesh(pivot, "Mantlet", _boxm(Vector3(0.4, 0.29, 0.21)), Vector3(-0.16, 0.05, -0.09))
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the mount
	# has to turn that onto the body's -Z. Read off a matrix the two look like
	# the same quarter turn; they are not, and the Bulwark's first build had it
	# backwards — the gun fitted, elevated, tracked targets and fired directly
	# behind the frame, with nothing complaining, because a mount pointing the
	# wrong way is a perfectly valid transform. All four shipping frames agree.
	_node(pivot, "WeaponMount", Vector3(-0.16, 0.05, -0.2), Vector3(0, PI * 0.5, 0))
	return turret


# ─────────────────────────────────────────────
# THE MAST AND THE CANOPY — the field, held overhead
# ─────────────────────────────────────────────
## THE OVERHEAD HOOP IS THE CLEAREST STATEMENT OF "PROJECTING SOMETHING OVER AN
## AREA", which is the entire unit, and it is the reason concept B won. A parasol
## over a position.
##
## Raked MAST_RAKE forward off the aft deck, so the column clears the turret's
## sweep while the hoop still lands over the middle of the frame: base at
## z +0.70, top at z +0.15, which is 0.15 m off the hull's own centre.
##
## Canopy counter-rotates by the same angle, so the hoop lies FLAT — the field it
## stands for lies over the ground, and a hoop on edge reads as a wheel. That
## pairing is what a future stow has to drive together.
func _mast(rig: Node3D) -> Node3D:
	# The collar is HULL and stays put when the mast lays down, so it lives on
	# the rig rather than on the mast node.
	_mesh(rig, "MastCollar", _cyl_mesh(0.36, 0.24, 12), Vector3(0, GROUND + 2.84, 0.7))
	var mast := _node(rig, "Mast", Vector3(0, GROUND + 2.78, 0.7),
			Vector3(-MAST_RAKE * DEG, 0, 0))
	# Tapered, and with a visible gland two-thirds of the way down: a column that
	# has obviously TELESCOPED is the cheapest "this deployed" signal on the
	# frame, and it is the piece the Jack repeats four times underneath.
	_mesh(mast, "Column", _cone_mesh(0.17, 0.27, MAST_LEN, 10),
			Vector3(0, MAST_LEN * 0.5, 0))
	_mesh(mast, "Gland", _cyl_mesh(0.3, 0.16, 12), Vector3(0, MAST_LEN * 0.27, 0))

	var canopy := _node(mast, "Canopy", Vector3(0, MAST_LEN, 0),
			Vector3(MAST_RAKE * DEG, 0, 0))
	_mesh(canopy, "Hub", _cyl_mesh(0.26, 0.22, 12), Vector3.ZERO)
	_mesh(canopy, "Hoop", _torus_mesh(1.12, 1.32), Vector3.ZERO)

	# FOUR, NOT THREE. See the header: the planted state has to read from any
	# bearing, and four-fold symmetry gives the same silhouette in all four
	# quadrants where the concept's three does not.
	var stays := _node(canopy, "Stays", Vector3.ZERO)
	var emitters := _node(canopy, "Emitters", Vector3.ZERO)
	var lenses := _node(canopy, "Lenses", Vector3.ZERO)
	var lens_mat := _projector_material()
	var i := 0
	for a_deg in [45.0, 135.0, 225.0, 315.0]:
		var a: float = float(a_deg) * DEG
		var sa := sin(a)
		var ca := cos(a)
		# A strut from the hub out and UP to the hoop: 1.02 of run against 0.26
		# of rise, so -14.3 degrees about X after the yaw puts its outboard end
		# at the hoop rather than in the air under it. A POSITIVE angle here
		# would take the far end downward, which is the sign error three of
		# Picket's five first-round concepts had.
		_mesh(stays, "Stay%d" % i, _boxm(Vector3(0.09, 0.09, 1.08)),
				Vector3(sa * 0.71, -0.13, ca * 0.71),
				Vector3(-14.3 * DEG, a, 0))
		# THE EMITTER HEAD: post, collar, and a dish aimed at the GROUND, which
		# is where the field goes. Hung under the hoop on the hoop's own radius,
		# clear of the turret's 0.70 m sweep by 0.17 m on the two front bearings.
		var head := _node(emitters, "Emitter%d" % i,
				Vector3(sa * 1.22, 0.0, ca * 1.22))
		_mesh(head, "Post", _cyl_mesh(0.085, 0.26, 8), Vector3(0, -0.13, 0))
		_mesh(head, "Collar", _cyl_mesh(0.15, 0.06, 10), Vector3(0, -0.28, 0))
		# WIDE RADIUS AT THE BOTTOM. A cone's apex is its +Y, so built the other
		# way round this is a funnel pointed at the sky.
		_mesh(head, "Dish", _cone_mesh(0.1, 0.22, 0.18, 10), Vector3(0, -0.4, 0))
		# The lit face, in its own emissive material and NOT in the livery list.
		var lens := _mesh(lenses, "Lens%d" % i, _sphere_mesh(0.13),
				Vector3(sa * 1.22, -0.5, ca * 1.22))
		lens.material_override = lens_mat
		i += 1
	return mast


# ─────────────────────────────────────────────
# THE OUTRIGGERS — hammered down
# ─────────────────────────────────────────────
## FOUR LONG OUTRIGGERS AT THE CARDINALS, so they sit in the gaps between the
## legs rather than fouling them. With the locked legs these are the half of the
## silhouette that says PLANTED without needing the hoop at all, which is the
## second reason concept B won and the thing the doc is emphatic about: a frame
## whose most important state is invisible is a frame the player cannot play
## around.
##
## ALL FOUR LEAN OUTWARD ALONG THEIR OWN RADIUS. Yaw first, then lean, and the
## lean is applied INSIDE the yawed frame — which is what ConceptsC._spade's
## docstring says it is for and what the two side spades in bastion_b() do not
## do. See the header.
##
## Each one reads as DRIVEN rather than as a bar hanging down, from three pieces
## doing three jobs: a square beam off the deck, a polished jack visibly
## extended out of its gland at the end of it, and a chisel blade wider than the
## beam so the foot is a foot and not the end of a stick.
func _outriggers(rig: Node3D) -> void:
	var grp := _node(rig, "Outriggers", Vector3.ZERO)
	# yaw is the bearing the ram's own -Z runs out along: 0 is dead ahead, +90
	# puts it on -X. Root positions are measured so the blades land on the
	# concept's 3.44 x 4.21 footprint once they lean the right way.
	var specs := [
		["F", Vector3(0, GROUND + 1.78, -0.926), 0.0],
		["A", Vector3(0, GROUND + 1.78, 0.926), 180.0],
		["L", Vector3(-0.541, GROUND + 1.78, 0), 90.0],
		["R", Vector3(0.541, GROUND + 1.78, 0), -90.0],
	]
	for spec: Array in specs:
		var post := _node(grp, "Outrigger%s" % spec[0], spec[1],
				Vector3(0, float(spec[2]) * DEG, 0))
		# THE ONE NODE A STOW HAS TO MOVE. Everything below it is the deployed
		# assembly and nothing else is under it.
		var ram := _node(post, "Ram", Vector3.ZERO, Vector3(PLANT_LEAN * DEG, 0, 0))
		_mesh(ram, "Beam", _boxm(Vector3(0.4, 1.0, 0.36)), Vector3(0, -0.5, 0))
		_mesh(ram, "Gland", _cyl_mesh(0.24, 0.14, 10), Vector3(0, -1.0, 0))
		_mesh(ram, "Jack", _cyl_mesh(0.145, 0.86, 10), Vector3(0, -1.4, 0))
		# The blade: 0.68 across, which is measured and not chosen — at 0.80 its
		# outboard corner clipped the foot pad of the leg beside it by 4 cm.
		var blade_size := Vector3(0.68, 0.22, 0.62)
		var blade := _hull(ram, "Blade", blade_size, Vector3(0, -PLANT_REACH, 0))
		# Both long bottom edges chamfered, so it reads as a wedge driven into
		# soil rather than a pad set on top of it.
		_cut(blade, "EdgeF", Vector3(0.9, 0.17, 0.17), Vector3(0, -0.11, 0.31),
				Vector3(45.0 * DEG, 0, 0))
		_cut(blade, "EdgeA", Vector3(0.9, 0.17, 0.17), Vector3(0, -0.11, -0.31),
				Vector3(45.0 * DEG, 0, 0))
		_studs(ram, "Stud", 3, Vector3(0, -0.26, -0.19), Vector3(0, -0.24, 0),
				Vector3(PI * 0.5, 0, 0))


# ─────────────────────────────────────────────
# THE SKIRTS — hip aprons, dropped
# ─────────────────────────────────────────────
## See the header for why these are aprons rather than option A's full skirts:
## B's winning read is four locked columns, and a skirt that occludes the legs
## throws it away. These cover the hip joints and stop at y 0.92, which leaves
## the whole lower half of every leg, both knee collars and all four feet on
## screen underneath them.
##
## OUTBOARD OF THE THIGHS, ON A BRACKET. A thigh's outer face is at x 1.31 and
## the hull flank is at 1.25, so an apron hung flush against the hull would pass
## straight through the leg. Hinged at 1.44 instead, which puts it 0.10 clear of
## the leg and standing 0.19 off the hull — the first rule in mockup_parts.gd's
## header, which is that a fitting flush against the body disappears into the
## silhouette however big it is.
##
## The brackets are HULL and must not swing with the aprons, so they are on the
## container and not on the hinges.
func _skirts(rig: Node3D) -> void:
	var grp := _node(rig, "Skirts", Vector3.ZERO)
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		# One stout bracket per side, on the centreline where the frame has no
		# leg and the side outrigger has already dropped to y 0.26.
		_mesh(grp, "Bracket%s" % tag, _boxm(Vector3(0.24, 0.18, 0.44)),
				Vector3(s * 1.35, GROUND + 1.56, 0))
		# THE HINGE. A negative Z rotation on the port side takes the apron's
		# bottom edge outboard, the same sign ConceptKit.leg uses for splay and
		# the hull bevels use for their chamfers. Built the other way the aprons
		# tuck under the frame and read as a dropped belly.
		var hinge := _node(grp, "Skirt%s" % tag, Vector3(s * 1.44, GROUND + 1.62, 0),
				Vector3(0, 0, s * SKIRT_CANT * DEG))
		var panel_size := Vector3(0.16, 0.7, 1.96)
		var panel := _hull(hinge, "Panel", panel_size, Vector3(0, -0.35, 0))
		# The lower corners raked off both ends. A rectangle hanging off a hull
		# reads as a placeholder because it is one.
		_cut(panel, "EndF", Vector3(0.4, 0.44, 0.44), Vector3(0, -0.35, -0.98),
				Vector3(45.0 * DEG, 0, 0))
		_cut(panel, "EndA", Vector3(0.4, 0.44, 0.44), Vector3(0, -0.35, 0.98),
				Vector3(45.0 * DEG, 0, 0))
		_studs(hinge, "Stud%s" % tag, 4, Vector3(s * 0.09, -0.52, -0.7),
				Vector3(0, 0, 0.47), Vector3(0, 0, PI * 0.5), 0.032)


# ─────────────────────────────────────────────
# THE LEGS — locked straight
# ─────────────────────────────────────────────
## PILLAR LEGS, BARELY SPLAYED, THICK: columns rather than limbs, which is what
## a frame that has stopped moving stands on. Digitigrade legs would say "about
## to run", which is the whole difference between this and concept C.
##
## Proportions are ConceptKit.leg's non-digitigrade branch at thick 1.7, which is
## where the 3.44 m measured width comes from: a foot pad centre lands at x 1.278
## and the pad is 0.442 across the radius.
##
## THE SPLAY IS ON A CHILD NODE, NOT ON THE HIP. walker.gd's _pose_leg writes
## hip.rotation.x and hip.rotation.z absolutely every physics frame, including
## zeroes at a dead stop, so anything baked onto a hip is erased on the first
## tick. walker.tscn does the same thing — HipL is at identity and the 15-degree
## tilt is on the ThighL mesh.
##
## Returns the four hip nodes, which are what the livery paints through.
func _legs(rig: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	# sx: -1 port, +1 starboard. sz: -1 fore, +1 aft. The fore pair takes the
	# plain L/R tags because walker.gd's gait drives it.
	var specs := [
		["L", -1.0, -1.0], ["R", 1.0, -1.0],
		["LA", -1.0, 1.0], ["RA", 1.0, 1.0],
	]
	for spec: Array in specs:
		var tag: String = spec[0]
		var sx: float = spec[1]
		var sz: float = spec[2]
		var hip := _node(rig, "Hip%s" % tag,
				Vector3(sx * 0.95, GROUND + 1.72, sz * 0.8))
		_mesh(hip, "HipCap%s" % tag, _sphere_mesh(0.323), Vector3.ZERO)
		# Splay out sideways, and out fore-and-aft. The fore-aft sign is negated
		# against the concept's: there, `sz * 4.0` leans the aft legs TOWARD the
		# centre, which is the same inward-lean slip as the side spades. Four
		# degrees either way is 12 cm, but a frame braced for a siege splays.
		var splay := _node(hip, "Splay%s" % tag, Vector3.ZERO,
				Vector3(-sz * 4.0 * DEG, 0, sx * 11.0 * DEG))
		_mesh(splay, "Thigh%s" % tag, _boxm(Vector3(0.7225, 0.85, 0.85)),
				Vector3(0, -0.425, 0))
		var knee := _node(splay, "Knee%s" % tag, Vector3(0, -0.85, 0))
		_mesh(knee, "KneeCollar%s" % tag, _cyl_mesh(0.36, 0.12, 12), Vector3.ZERO)
		_mesh(knee, "Shin%s" % tag, _boxm(Vector3(0.5746, 0.8, 0.663)),
				Vector3(0, -0.4, 0))
		_mesh(knee, "Foot%s" % tag, _cyl_mesh(0.442, 0.14, 14), Vector3(0, -0.87, 0))
		out.append(hip)
	return out
