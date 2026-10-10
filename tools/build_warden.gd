extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/warden.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_warden.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. This is not a build step.
# Re-running it over an edited scene throws the edit away, which is how
# force-rebuilds have repeatedly cost this project its gameplay layers. If the
# geometry needs changing after today, change the scene.
#
# The silhouette is WARDEN concept A, "THE MAST", from
# tools/concepts_b.gd -> ConceptsB.warden_a(), rebuilt out of the Walker's own
# part vocabulary so this reads as issued rather than imported.
#
# ─────────────────────────────────────────────
# WHAT CHANGED FROM THE CONCEPT, AND WHY: THE HEIGHT.
#
# The rendered concept measures 1.97 W x 6.68 H x 2.24 L. The 6.68 must not
# survive — it is taller than anything in the game and would catch on every
# bridge deck and doorway. docs/frames/WARDEN.md section 1 settles it: the mast
# TELESCOPES, stowed ~2.6 m on the move and raised ~4.5 m while emitting.
#
# THIS FILE BUILDS THE RAISED STATE, at 4.48 m. Width and length are the
# concept's (the crown's radials set both, and they are untouched); only the
# column and the legs are shortened. The legs are the Walker's own leg scaled
# to 0.76, which also plants the frame lower — correct for something this
# top-heavy.
#
# HOW A FUTURE warden.gd STOWS IT. The mast is a CHAIN OF NAMED Node3Ds, each
# the child of the last, so sliding it is setting four y values and never
# rebuilding geometry:
#
#   Rig/MastBase                      fixed collar — the three coil torii and
#                                     the junction boss live here and NEVER move
#   Rig/MastBase/MastRaise            the handle. Stays at y 0 in both states;
#                                     it exists so a script has ONE node to
#                                     grab (and one place to take extra drop if
#                                     2.5 m still fouls something).
#     .../Stage1                      y 0.00  (raised)  ->  0.00  (stowed)
#       .../Stage2                    y 0.74            ->  0.00
#         .../Stage3                  y 0.64            ->  0.00
#           .../MastHead              y 0.58            ->  0.00
#
# Each tube is drawn in its own stage's local space with its base at the stage
# origin, so at y 0 a stage sits fully inside its parent's tube and the three
# diameters (0.165 / 0.125 / 0.092) nest without clipping. Zeroing all four
# puts the crown at y 1.18 and the frame at 2.53 m overall — the doc's stowed
# figure. The tube LENGTHS are deliberately longer than their stage offsets
# (0.92 vs 0.74, 0.80 vs 0.64, 0.66 vs 0.58) so the raised column has 0.18 m of
# overlap at each joint and does not read as three sticks balanced end to end.
#
# NOTHING HERE WRITES warden.gd. The nodes are present for it; the script is
# somebody else's pass.
#
# ─────────────────────────────────────────────
# THE TURRET QUESTION: Rig/Turret IS A STUB, AND THAT IS THE HONEST ANSWER.
#
# The Warden has no gun — docs/frames/WARDEN.md section 3 sets `turret = false`
# and section 6 has warden.gd no-op the whole weapon loop. walker.gd declares
# `turret` and `gun_pivot` regardless, and this is the Lance's situation
# exactly, so it gets the Lance's answer (see tools/build_lance.gd):
#
#   1. `Turret` is a BARE Node3D with NO GEOMETRY UNDER IT. The mast head is
#      NOT the turret. Wiring the head to `turret` would have walker.gd's
#      _update_facing slew the crown toward whatever the frame is looking at —
#      an emitter that AIMS, which is precisely the read that lost option B the
#      vote. The field is a radius; nothing on this frame may point.
#
#   2. turret_traverse_degrees = 0.0, so rotate_toward(turret.rotation.y, ...)
#      is a no-op every frame and the stub cannot drift even in isolation.
#
#   3. It is still WIRED, not null, and this is the part that matters. With
#      `turret == null` walker.gd falls through to super(), which turns the
#      WHOLE BODY to face the target — a gunless frame pivoting to line up a
#      shot it cannot take. enemy.gd's `hull_spoils_aim` (line 2894) also tests
#      the node named `turret` for null, not ChassisDefinition.turret. A stub
#      absorbs both for free.
#
# DO NOT EDIT walker.gd TO REMOVE THE EXPORT.
#
# gun_elevation_degrees is left at its default rather than zeroed: nothing is
# parented to GunPivot except WeaponMount, so a free pitch costs nothing, and
# if a conventional weapon is ever fitted here it should elevate.
#
# WeaponMount is at yaw +PI/2 on that stub, where section 5 of the doc says it
# must be "in case a conventional weapon is ever fitted". MastMount, under
# MastHead, is where the emitter scene would actually parent.
#
# ─────────────────────────────────────────────
# TWO FINDINGS ABOUT THE CONCEPT CODE, carried here rather than silently fixed
# upstream (shared file, other agents mid-edit — reported instead).
#
# 1. THE RADIALS IN warden_a() SWEEP UP, NOT DOWN. Its comment says "a +125
#    degree tilt about X takes the cylinder's +Y axis to (0, -0.57, -0.82):
#    down and outward together". It does not. Godot's basis for a rotation of
#    θ about X sends local +Y to (0, cos θ, sin θ), so +125 degrees gives
#    (0, -0.574, +0.819) — down and INBOARD, which draws a rod from below the
#    hub up and out to the rim. The sign is wrong; -125 degrees is what the
#    comment describes. This is the same family as the muzzle-sign warning in
#    docs/briefs/FRAME_MODELS.md section 5. BUILT AT -125 HERE, because the
#    doc, the brief and the concept's own comment all say down-swept.
#
# 2. THAT BUG IS ALSO WHY THE DOC SAYS "a loose ring of unattached nodes".
#    warden_a() puts each rib's bead at (0, -0.57, -1.0) while the mis-signed
#    rod ends at (0, 0, -1.0) — so on the sheet the beads hung 0.57 m clear of
#    the rods they belonged to, and were read as free-floating nodes. Fixing
#    the sign puts each bead back on its rod tip, so the floating ring is built
#    HERE AS ITS OWN FEATURE (Halo0..5): six small spheres at radius 0.62,
#    interleaved 30 degrees between the radials, at two alternating heights, no
#    connecting geometry. The doc's section 1 lists the radials and the node
#    ring as two separate things, and now they are.
#
# SIX RADIALS, NOT FOUR. The doc's prose says four; warden_a() builds six, and
# six is what was rendered and selected. The code is the authority on
# silhouette, so six.
#
# THE KNOWN concept_kit.head() FAULT IS MOOT HERE: that head is never used.
# This frame carries ConceptsB._blind_head — the Walker's head with the mantlet
# and barrel replaced by a sensor cowl — and its neck ring is placed BELOW the
# head body with the gap to clear it, not inside it.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/warden.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
const BODY_SCRIPT := "res://Character/characters/ai/walker.gd"
# LEGGED, so walker.gd. Section 5 of the doc left the choice to the concept and
# the concept has two digitigrade legs.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__63.wav"

const DEG := PI / 180.0
## The Walker's eye is a plain StandardMaterial3D with this as its albedo, not
## the shared faction metal. Carried over verbatim so every frame's eye is the
## same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

## Walker measurements, so the family does not drift. Read off walker.tscn.
const W_TURRET := Vector3(1.18, 0.6, 1.3)
const W_RING_R := 0.54
## The head is scaled DOWN so the mast, not the head, owns the top of the
## frame — the concept's whole staging.
const HEAD_S := 0.60
## Hull deck height: the top face of the hull, where the mast collar stands.
const DECK := 0.65

var _metal: Material
var _root: CharacterBody3D
## Collected by _mesh() and _hull() as they build, so the livery list cannot
## miss a piece by transcription. The eye is removed from it by name.
var _painted: Array[Node3D] = []


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_warden: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_warden: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_warden: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A mesh piece. Everything visible goes through here so nothing can be left
## without the shared metal material — a single unpainted piece is invisible as
## a bug until someone renders the frame in a faction colour.
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
	_painted.append(m)
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


func _sphere_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _cyl_mesh(r: float, h: float, sides: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


## A flat torus. The concept's coil and crown are CSGTorus3D with inner/outer
## radii; TorusMesh takes the same two numbers, so the proportions carry over
## unchanged. A torus is already flat about Y — rotating one "to lay it down"
## stands it into an arch, which is a mistake this project has made repeatedly.
func _torus_mesh(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	return t


## A CSG box used as a CUT. Subtractions are how the Walker gets its sloped
## glacis and chamfered shoulders, and reusing them is most of why this reads as
## the same factory. Cuts take no material: they are nested inside a CSG root,
## so faction_livery merges them into it.
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
## which is why these may exist at all — see that file for the 335 ms spike that
## made baking compulsory.
func _hull(parent: Node, nm: String, size: Vector3, at: Vector3) -> CSGMesh3D:
	var h := CSGMesh3D.new()
	h.name = nm
	h.mesh = _boxm(size)
	h.position = at
	h.material = _metal
	parent.add_child(h)
	h.owner = _root
	_painted.append(h)
	return h


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Warden"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, meaning "this run only" — a scene built
	# without it saves with no groups line, and a robot outside "enemies" is
	# invisible to AIManager, to EMP and to every hostile sweep in the game
	# while still walking around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision and senses ──
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	# SIZED TO THE STOWED SILHOUETTE, NOT THE RAISED ONE, and this is a
	# decision rather than an oversight. The mast telescopes precisely so the
	# frame does not foul level geometry; a capsule tall enough to contain the
	# raised crown would reinstate the problem the telescoping exists to solve,
	# and would be 2 m of empty air around a 0.09 m rod besides. 2.55 m is the
	# stowed envelope (foot bottom -1.335 to stowed crown 1.18).
	cap.radius = 0.88
	cap.height = 2.55
	col.shape = cap
	col.position = Vector3(0, -0.08, 0)
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, or the assignment is silently dropped. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three DEFAULT clips instead. That line was untyped for the
	# Bulwark's whole life and bulwark.tscn still ships the defaults, which
	# nobody noticed because it still barks.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# Higher and flatter than the Bulwark's 0.64-0.72 and lower than the Lance's
	# 1.04-1.16: a support frame that talks over its own carrier hum. A voice is
	# a game-feel call, so this is a first guess for the human to judge.
	bark.set("pitch_min", 0.92)
	bark.set("pitch_max", 1.00)
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
	# The family default. The doc's base_sensor_range of 55 is a
	# ChassisDefinition field and is out of scope for this pass.
	dsphere.radius = 25.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body

	# ── the rig ──
	var rig := _node(root_body, "Rig", Vector3.ZERO)

	# HULL. The Walker's own block, a shade longer and thinner, sat low: this is
	# a carrier deck for a mast, and the lower the deck the less top-heavy the
	# whole thing is for the same reach. Top face at DECK.
	var hull := _hull(rig, "Hull", Vector3(1.52, 0.86, 1.78), Vector3(0, 0.22, 0))
	_cut(hull, "Glacis", Vector3(2.13, 1.03, 1.42), Vector3(0, -0.62, -1.10),
			Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(2.13, 1.03, 1.07), Vector3(0, -0.58, 1.14),
			Vector3(20.0 * DEG, 0, 0))
	for s in [-1.0, 1.0]:
		_cut(hull, "Bevel%s" % ("L" if s < 0.0 else "R"),
				Vector3(1.06, 0.69, 2.49), Vector3(s * 1.03, 0.57, 0),
				Vector3(0, 0, s * 30.0 * DEG))

	_head(rig)
	_turret_stub(rig)
	_mast(rig)
	_legs(rig)

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
	# Node OBJECTS in a TYPED array. pieces is Array[Node3D]; an untyped one
	# lands as [] and FactionLivery then falls back to walking its whole parent,
	# which paints every mesh on the frame INCLUDING THE EYE. That is how the
	# Bulwark's eye ended up faction-coloured despite being left off a list that
	# was never there.
	#
	# THE EYE IS DELIBERATELY ABSENT. It keeps its own StandardMaterial3D
	# because the one feature that identifies a robot in this game must not
	# change colour per faction. _painted is built by _mesh()/_hull() as they
	# go and the eye is pulled out of it below, so a new piece cannot be
	# forgotten here by transcription.
	var paint: Array[Node3D] = []
	for p in _painted:
		paint.append(p)
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D or Array[Node3D] — not NodePath — so assigning a NodePath silently
	# does nothing and the frame comes out with a null turret and legs the gait
	# cannot find. Nothing errors. PackedScene.pack() turns these references
	# back into the node_paths=PackedStringArray(...) form the editor writes, so
	# the saved scene looks hand-authored either way.
	root_body.set("rig", rig)
	root_body.set("hip_left", rig.get_node("HipL"))
	root_body.set("knee_left", rig.get_node("HipL/KneeL"))
	root_body.set("hip_right", rig.get_node("HipR"))
	root_body.set("knee_right", rig.get_node("HipR/KneeR"))
	root_body.set("foot_left", rig.get_node("HipL/KneeL/FootL"))
	root_body.set("foot_right", rig.get_node("HipR/KneeR/FootR"))
	root_body.set("turret", rig.get_node("Turret"))
	root_body.set("gun_pivot", rig.get_node("Turret/GunPivot"))
	root_body.set("weapon_mount", rig.get_node("Turret/GunPivot/WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY. particle_effects_die is
	# Array[ParticleEffect] and visible_pieces is Array[Node3D]; a plain
	# untyped Array fails SILENTLY and the packed scene comes out with [].
	# The Bulwark shipped all three empty on its first build: no death effects,
	# no hit sparks, and a frame that painted its own eye.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# THREE PARENTS, NOT THIRTY MESHES. enemy.gd both hides these and tips them
	# individually when the frame collapses, so listing the Node3D that carries
	# an assembly takes the whole assembly with it — MastBase is the entire mast
	# in one entry, which is also what makes the death pose drop the crown
	# rather than leave it hanging in the air.
	var vis: Array[Node3D] = []
	vis.append(hull)
	vis.append(rig.get_node("Head"))
	vis.append(rig.get_node("MastBase"))
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	root_body.set("activation_distance", 200)
	# base_health 160, docs/frames/WARDEN.md section 3. It is the squad's
	# priority target and has to survive being one.
	root_body.set("health", 160)
	root_body.set("max_health", 160)
	root_body.set("soldier_name", "Warden")
	root_body.set("flatten_collider_when_downed", false)
	# ZERO, so the stub cannot traverse. See the turret note in the header.
	root_body.set("turret_traverse_degrees", 0.0)
	# Everything else — supply, cost, speed, sensor range, weapon slots,
	# built_in = "MAST" — is ChassisDefinition's and is deliberately NOT set
	# here. No catalogue entry in this pass.
	return root_body


# ─────────────────────────────────────────────
# HEAD — the Walker's, without the gun.
#
# ConceptsB._blind_head: the turret ring, the cheek and brow cuts, ONE eye
# offset LEFT and the whip antenna all carried over, with a sensor cowl where
# the Walker has a mantlet and a barrel. NOTHING ON THIS FRAME MAY RESEMBLE A
# BARREL — it is the only non-lethal frame in the game and the art brief in
# section 1 of the doc rules a gun shape out explicitly.
#
# SET LOW AND FORWARD, off the mast's axis, so the mast owns the top of the
# silhouette and the eye is never crossed by a rod.
# ─────────────────────────────────────────────
func _head(rig: Node3D) -> void:
	_mesh(rig, "NeckRing", _cyl_mesh(W_RING_R * HEAD_S, 0.12 * HEAD_S, 14),
			Vector3(0, DECK + 0.05, -0.22))
	var head := _node(rig, "Head", Vector3(0, DECK + 0.19, -0.22))
	var body := _hull(head, "HeadBody", W_TURRET * HEAD_S, Vector3.ZERO)
	# The cutters are 1.3x the block they slice: anything tighter leaves a
	# sliver of uncut face along the edge.
	_cut(body, "Cheek", Vector3(W_TURRET.x * 1.3, 0.7, 0.7) * HEAD_S,
			Vector3(0, -0.44, -0.86) * HEAD_S, Vector3(-35.0 * DEG, 0, 0))
	_cut(body, "Brow", Vector3(W_TURRET.x * 1.3, 0.7, 0.7) * HEAD_S,
			Vector3(0, 0.5, -0.78) * HEAD_S, Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, offset left, and the WALKER'S OWN material rather than the
	# shared metal. Painting it with faction livery like everything else would
	# make the one feature that identifies a robot in this game change colour
	# per faction, so it is pulled back out of _painted here.
	#
	# BIGGER THAN THE CONCEPT'S. A 0.60 head puts the kit's eye at 0.10 m,
	# against 0.17 on both the Walker and the Bulwark, and the eye is what
	# reads at forty pixels. 0.13 is a compromise: slightly large for this head,
	# still legible at distance, and it keeps the mast owning the top.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.13
	eye_mesh.height = 0.21
	eye_mesh.radial_segments = 16
	eye_mesh.rings = 8
	var eye := _mesh(head, "Eye", eye_mesh, Vector3(-0.20, 0.08, -0.40))
	eye.material_override = _eye_material()
	_painted.erase(eye)

	# The whip, off the back corner. Kept at the Walker's 0.03 section rather
	# than scaled to 0.018, which would be a hair.
	_mesh(head, "Antenna", _boxm(Vector3(0.03, 0.51, 0.03)), Vector3(-0.30, 0.41, 0.29))
	# The sensor cowl, standing proud of the face so it breaks the outline
	# rather than sinking into the brow cut, and on the RIGHT because the eye is
	# on the left and nothing may cross an eye.
	_mesh(head, "SensorCowl", _boxm(Vector3(0.26, 0.17, 0.12)), Vector3(0.13, 0.0, -0.44))


# ─────────────────────────────────────────────
# THE TURRET STUB. Geometry: none. See the header.
# ─────────────────────────────────────────────
func _turret_stub(rig: Node3D) -> void:
	# On the starboard shoulder bevel, clear of the head (x +-0.35) and clear of
	# the mast collar (z 0.30, outer radius 0.35), so a conventional weapon ever
	# fitted here would sit somewhere plausible instead of inside the mast.
	var turret := _node(rig, "Turret", Vector3(0.50, DECK + 0.05, -0.05))
	var pivot := _node(turret, "GunPivot", Vector3.ZERO)
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the
	# mount has to turn that onto the body's -Z. Read off the Walker's matrix
	# the yaw looks like a quarter turn either way; it is not, and the Bulwark's
	# first build had it backwards — the gun fitted, elevated, tracked targets
	# and fired directly behind the frame. Nothing warns, because a mount
	# pointing the wrong way is a perfectly valid transform.
	_node(pivot, "WeaponMount", Vector3(0, 0.0, -0.34), Vector3(0, PI * 0.5, 0))


# ─────────────────────────────────────────────
# THE MAST. The frame's entire proposition, and the thing that must read as
# RADIATING rather than AIMING.
#
# Stage offsets and tube lengths, and what a stow moves, are in the header.
# ─────────────────────────────────────────────
func _mast(rig: Node3D) -> void:
	# Standing on the deck, aft of centre, exactly where the concept puts it
	# (z +0.30) — forward of the mast is where the head goes.
	var base := _node(rig, "MastBase", Vector3(0, DECK, 0.30))

	# THE COIL. Three flat torii wrapping the base tube, and it is doing real
	# work: a comms mast has no coil and no ribbed crown, and those two features
	# are the whole reason this silhouette is an emitter and not a radio van.
	#
	# PACKED LOW AND TIGHT, tighter than the concept's 0.26 spacing. On a 3.3 m
	# column it did not matter where the coil sat; on this one every centimetre
	# the coil climbs is a centimetre of bare column lost, and the bare column
	# is the "single vertical stroke" the icon depends on.
	for i in 3:
		_mesh(base, "Coil%d" % i, _torus_mesh(0.19, 0.35),
				Vector3(0, 0.10 + float(i) * 0.18, 0))
	# The junction boss, off to one side, where the feed enters. Asymmetry on
	# the column is what stops it reading as a lamp post.
	_mesh(base, "Junction", _sphere_mesh(0.15), Vector3(0.28, 0.22, 0))

	# THE HANDLE. One node for a script to grab, and one place to take extra
	# drop. It does not move between the two authored states.
	var raise := _node(base, "MastRaise", Vector3.ZERO)

	# THREE STAGES, each a child of the last, each tube drawn with its base at
	# its own stage origin. Quoting a single 2 m cylinder would have been one
	# line and would have read as a flagpole — and could not telescope.
	var s1 := _node(raise, "Stage1", Vector3.ZERO)
	_mesh(s1, "Tube1", _cyl_mesh(0.165, 0.92), Vector3(0, 0.46, 0))
	var s2 := _node(s1, "Stage2", Vector3(0, 0.74, 0))
	_mesh(s2, "Tube2", _cyl_mesh(0.125, 0.80), Vector3(0, 0.40, 0))
	var s3 := _node(s2, "Stage3", Vector3(0, 0.64, 0))
	_mesh(s3, "Tube3", _cyl_mesh(0.092, 0.66), Vector3(0, 0.33, 0))

	var head := _node(s3, "MastHead", Vector3(0, 0.58, 0))
	# THE CROWN: two stepped rings and a terminal bulb. The wide ring is 1.1 m
	# across on a 0.09 m rod, which is what makes the top of this frame a BLOB
	# ON A STROKE at icon size — the one silhouette in the roster that reads
	# that way.
	#
	# THINNER IN SECTION THAN THE CONCEPT'S (tube 0.135 and 0.090 against 0.230
	# and 0.155), AND THIS WAS A RENDER, NOT A PREFERENCE. The concept's rings
	# are nearly solid discs, which on a 3.3 m column read as a small crown and
	# on this 2 m column stacked with the bulb into one lens — a flying saucer.
	# Opened out they read as two concentric HOOPS round a bulb, which is both
	# more energised and lets the column show through. Diameters are unchanged,
	# so the frame's measured width is not.
	_mesh(head, "CrownRingA", _torus_mesh(0.28, 0.55), Vector3.ZERO)
	_mesh(head, "CrownRingB", _torus_mesh(0.20, 0.38), Vector3(0, 0.19, 0))
	_mesh(head, "Bulb", _sphere_mesh(0.17), Vector3(0, 0.36, 0))

	# SIX RADIALS, DOWN AND OUT. Each lives in its own yawed node so only one
	# rotation is ever composed by hand — hanging a rod off a rotated parent's
	# local axis is the mistake this project makes most often. Inside the yawed
	# node local -Z is outward, and -125 degrees about X takes the cylinder's
	# +Y to (0, -0.574, -0.819): down and outward together. THE CONCEPT HAS
	# THIS SIGN POSITIVE and its rods sweep up instead; see the header.
	for i in 6:
		var a := TAU * float(i) / 6.0
		var rad := _node(head, "Radial%d" % i, Vector3.ZERO, Vector3(0, -a, 0))
		_mesh(rad, "Rib%d" % i, _cyl_mesh(0.05, 1.0, 8), Vector3(0, -0.29, -0.59),
				Vector3(-125.0 * DEG, 0, 0))
		_mesh(rad, "Tip%d" % i, _sphere_mesh(0.09), Vector3(0, -0.57, -1.0))

	# THE LOOSE RING OF UNATTACHED NODES, from section 1 of the doc. Six beads
	# at radius 0.62 — just outside the wide crown ring — interleaved 30 degrees
	# between the radials and at two alternating heights, with NO CONNECTING
	# GEOMETRY. Nothing else in the game has floating parts, and a halo that
	# obeys no structure is the clearest possible statement that the field goes
	# OUTWARD, ALL WAYS, rather than anywhere in particular.
	for i in 6:
		var a := TAU * float(i) / 6.0 + PI / 6.0
		var y := 0.30 if (i % 2) == 0 else 0.44
		_mesh(head, "Halo%d" % i, _sphere_mesh(0.065),
				Vector3(sin(a) * 0.62, y, -cos(a) * 0.62))

	# Where the emitter scene parents. NOT named WeaponMount and NOT wired to
	# the weapon_mount export: the mast is a mount class of its own
	# (built_in = "MAST", section 3 of the doc) and the conventional mount lives
	# on the turret stub.
	_node(head, "MastMount", Vector3.ZERO)


# ─────────────────────────────────────────────
# LEGS — the Walker's own leg at 0.76 scale.
#
# SHORTER THAN THE WALKER'S ON PURPOSE, and this is half of where the height
# came from. A squat stance under two metres of mast reads as planted and keeps
# the centre of mass where it can be defended; the concept's legs were actually
# LONGER than the Walker's, which on a top-heavy frame was the wrong way round.
# Digitigrade, which is what makes these read as the Walker's relatives.
# ─────────────────────────────────────────────
func _legs(rig: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		# Splayed OUTWARD, the Bulwark's way: s * angle, so the left leg at
		# -x leans further -x. Built with the sign flipped the frame stands
		# knock-kneed, which on something this top-heavy looks like it is
		# already falling.
		var hip := _node(rig, "Hip%s" % tag, Vector3(s * 0.66, -0.20, 0),
				Vector3(0, 0, s * 5.0 * DEG))
		_mesh(hip, "HipCap%s" % tag, _sphere_mesh(0.185), Vector3.ZERO)
		_mesh(hip, "Thigh%s" % tag, _boxm(Vector3(0.34, 0.56, 0.40)),
				Vector3(0, -0.24, 0.11), Vector3(15.0 * DEG, 0, 0))
		var knee := _node(hip, "Knee%s" % tag, Vector3(0, -0.47, 0.21))
		_mesh(knee, "KneeCap%s" % tag, _sphere_mesh(0.145), Vector3.ZERO)
		_mesh(knee, "Shin%s" % tag, _boxm(Vector3(0.26, 0.65, 0.30)),
				Vector3(0, -0.29, -0.12), Vector3(-15.0 * DEG, 0, 0))
		_mesh(knee, "Foot%s" % tag, _boxm(Vector3(0.42, 0.15, 0.80)),
				Vector3(0, -0.59, -0.35))


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object and this project has already
## paid for that once — see the duplicate() rule in CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m
