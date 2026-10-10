extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/picket.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_picket.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. A robot scene is forty-odd
# sub-resources with hand-numbered ids and an exact load_steps count that
# check.sh verifies, and writing that by hand is a transcription exercise with
# nothing to learn from. It is NOT a build step: re-running it after the scene
# has been touched in the editor throws that work away, the way --force
# rebuilds have repeatedly cost this project its gameplay layers. If the
# geometry needs changing after today, CHANGE THE SCENE.
#
# ─────────────────────────────────────────────
# WHERE THE PROPORTIONS COME FROM
#
# ConceptsP.picket_c2() in tools/concepts_p.gd, which is the selected
# silhouette and the authority on every position below. Hull 1.55 x 0.9 x 1.5
# at y 0.45; the launcher block's origin at (0, 1.22, 0) canted 54 degrees; the
# dish head at (-0.86, 1.22, 0.42) canted -52; legs at x +-0.62, y -0.12, thigh
# 0.66, shin 0.76, splay 6 degrees. Those numbers are reproduced here EXACTLY
# and in the same frame of reference — the concept's y = 0 is already this
# family's body origin, because its legs put the sole at y -1.675, which is
# where walker.tscn's sole is to the millimetre.
#
# What the concept does NOT have, and this does, is everything a concept does
# not need: collision, the rig hierarchy the gait drives, a head with an eye,
# the mounts, the livery list, and the material on every piece.
#
# ─────────────────────────────────────────────
# THE TURRET QUESTION: WHAT YAWS AND WHAT PITCHES
#
# walker.gd wants two nodes (walker.gd:200-227): `turret`, whose rotation.y it
# drives toward the target bearing, and `gun_pivot`, whose rotation.x it drives
# toward the target elevation. The Picket's whole premise is a launcher block
# that points up, so the mapping has to be decided rather than assumed.
#
#   Turret    the whole upper assembly — the yoke, the head and eye, the
#             antenna, the sensor dish and the launcher. One bearing for the
#             frame, so the dish looks where the tubes look. (PICKET.md section
#             8 leaves a dish that traverses on its own as an open question;
#             this is the "not modelled now" answer.)
#   GunPivot  the trunnion at the top of the yoke, at the launcher block's own
#             origin (0, 1.22, 0). It carries the launcher and nothing else.
#
# GunPivot's OWN ROTATION IS ZERO, and the 54-degree cant lives on a child,
# `PodCant`. This is not tidiness. walker.gd:224 ASSIGNS rotation.x every
# frame, clamped between gun_min_pitch_degrees and gun_max_pitch_degrees
# (-12 .. +35 by default) — so a rest pose of 54 degrees built into the pivot
# would be clamped flat on the first frame of combat and the launcher would
# flop level. The same trap cost the Bulwark its forward-broken arm, which is
# why its forearm offset is baked into the forearm. Here the cant is structure
# below the hinge, and the hinge starts where the aiming code expects it: at
# zero, adding elevation on top of a launcher that already points up.
#
# THE CANT IS POSITIVE ABOUT +X. A rotation about +X maps -Z to
# (0, sin, -cos), so a NEGATIVE angle aims the muzzle at the FLOOR — on the one
# frame in the roster whose entire reason to exist is shooting upward. Three of
# Picket's five first-round concepts had this sign wrong and that is most of
# why they "looked like guns". The dish is the opposite case and is correctly
# negative: a cone's axis is +Y, and +X by a negative angle tilts +Y up and
# forward. See the long note in tools/concepts_p.gd.
#
# THE WEAPON MOUNT RIDES THE CANT. It hangs under PodCant at the muzzle plane,
# so a fitted weapon's barrel lies along the tubes instead of pointing level
# out of the middle of a launcher. Its own yaw is +PI/2 — not -PI/2 — which is
# what turns a weapon's +X muzzle onto the assembly's -Z; read off the Walker's
# matrix it looks like a quarter turn either way, it is not, and the Bulwark
# fired backwards for it.
#
# ─────────────────────────────────────────────
# TWO THINGS THAT DISAGREE WITH docs/frames/PICKET.md, ON PURPOSE
#
# 1. THE SIZE IN SECTION 1 IS WRONG. The doc says C2 is 2.24 W x 3.27 H x
#    1.76 L. Width and length are exact; the HEIGHT IS NOT. Rendering the
#    refine sheet (tools/mockup_frames.gd) measures the selected concept at
#    2.24 x 4.15 x 1.76 — so C2 is TALLER than the 4.07 m original whose height
#    was one of the three faults C2 was drawn to fix. 3.27 appears nowhere in
#    the code. Nothing here is scaled to chase it: the brief says the concept
#    is the authority on proportions and that a disagreement gets reported, not
#    papered over. Bringing it down is a proportions decision (shorter tubes, a
#    shallower cant) and belongs to whoever owns the concept.
#
# 2. THE CAPSULE IS SIZED TO THE ART, not to the doc's r 0.8 / h 2.4. Radius
#    0.8 is right — the hull is 1.55 across and the feet reach x 0.975. Height
#    2.4 is not: a capsule centred on the origin would then stop at y 1.2,
#    which is BELOW the entire launcher, so rounds aimed at the one part of
#    this frame anybody will aim at would pass through it, and the sole would
#    float 0.475 m under the floor. Height 3.0 puts the bottom at -1.5, exactly
#    0.175 above the sole — the Walker's own relationship — and the top just
#    over the yoke, exactly where the Walker's capsule stops below its barrel
#    and antenna.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/picket.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
# AN EXISTING SCRIPT. The model pass adds no behaviour: this frame is a legged
# turret, which is Walker, and Walker already owns the gait, the traverse, the
# facing split and the fire cone. PICKET.md section 5 names a picket.gd that
# would extend it to change NUMBERS; that is a stats pass and is deliberately
# not here.
const BODY_SCRIPT := "res://Character/characters/ai/walker.gd"
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__23.wav"

const DEG := PI / 180.0
## The Walker's eye is a plain StandardMaterial3D with this as its albedo —
## not the shared faction metal. Carried over verbatim so all three frames'
## eyes are the same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

# ── the concept's numbers, named ──
const HULL := Vector3(1.55, 0.9, 1.5)
const HULL_Y := 0.45
## Launcher block origin, in body space. The trunnion goes here.
const PODS_AT := Vector3(0.0, 1.22, 0.0)
const PODS_CANT := 54.0
const TUBE_R := 0.14
const TUBE_LEN_F := 1.25
const TUBE_LEN := 1.1 * TUBE_LEN_F
## Dish head, in body space.
const DISH_AT := Vector3(-0.86, 1.22, 0.42)
const DISH_R := 0.4
const DISH_CANT := -52.0
## Where the yawing assembly is seated. The hull's cut top is at y 0.9.
const TURRET_Y := 1.0
const RING_Y := 0.93

var _metal: Material
var _root: CharacterBody3D


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_picket: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_picket: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_picket: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A mesh piece. Everything visible on the frame goes through here or through
## _hull/_tube so nothing can be left without the shared metal — a single
## unpainted piece is the kind of thing that only shows up in a faction colour
## nobody tested.
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


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## NOTHING REFERENCED MAY HANG OFF A CSG SHAPE. csg_bake.gd replaces every CSG
## root with a baked MeshInstance3D at boot and frees the original — children
## of it that are not subtraction operands go with it. So pivots, mounts and
## the eye are parented to plain Node3D nodes, never to a hull.
func _node(parent: Node, nm: String, at: Vector3, euler: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = at
	n.rotation = euler
	parent.add_child(n)
	n.owner = _root
	return n


## A CSG box used as a CUT. Subtractions are how this family gets its sloped
## glacis and chamfered shoulders, and reusing them is most of why a new frame
## reads as the same factory.
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
## which is why these may exist at all — see that file for the 335 ms spike
## that made baking compulsory.
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


## ONE LAUNCHER TUBE, BORED OUT.
##
## A solid cylinder reads as a rod, and six rods read as a gun — the exact
## failure that killed three of the five first-round concepts. A visible bore
## is what makes the frame say "launcher" at forty pixels, and it costs one
## subtraction per tube: cheaper than the muzzle rings and separate backplate
## the alternative needed, and baked once at boot either way.
##
## The mesh's axis is +Y and the node is turned +90 about X, which puts the
## bore along the assembly's Z. Local -Y is therefore the MUZZLE, so the cut is
## offset that way and stops short of the far end, leaving a closed breech.
func _tube(parent: Node, nm: String, r: float, length: float, at: Vector3) -> CSGMesh3D:
	var c := CSGMesh3D.new()
	c.name = nm
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 12
	cm.rings = 0
	c.mesh = cm
	c.position = at
	c.rotation = Vector3(PI * 0.5, 0, 0)
	c.material = _metal
	parent.add_child(c)
	c.owner = _root
	var bore := CSGCylinder3D.new()
	bore.name = "%sBore" % nm
	bore.radius = r - 0.045
	bore.height = length
	# Same facet count as the outer wall, or the bore reads as a different part
	# of the machine from the tube it is inside.
	bore.sides = 12
	bore.position = Vector3(0, -0.1 * length, 0)
	bore.operation = CSGShape3D.OPERATION_SUBTRACTION
	c.add_child(bore)
	bore.owner = _root
	return c


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Picket"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, which means "for this run only" — the
	# Bulwark's first build packed a frame with no groups line, and a robot
	# outside "enemies" is invisible to AIManager, to EMP and to every hostile
	# sweep in the game while still walking around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision and senses ──
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	# SIZED TO THE ART — see the header. 0.8 across because the hull is 1.55
	# and the feet reach 0.975; 3.0 tall because the bottom then sits 0.175
	# above the sole, which is walker.tscn's own relationship, and the top
	# clears the yoke the launcher is bolted to.
	cap.radius = 0.8
	cap.height = 3.0
	col.shape = cap
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# Higher than the Walker's 0.72-0.80 and well clear of the Bulwark's
	# 0.64-0.72: this is the lightest frame in the family that still has legs,
	# and the three have to be tellable apart with the screen turned off.
	# TYPED, or the assignment is silently dropped and the scene keeps
	# bark.tscn's three defaults. This frame shipped with them: the trap was
	# still live in build_bulwark.gd when this generator was copied from it.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	bark.set("pitch_min", 0.82)
	bark.set("pitch_max", 0.92)
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
	# The family's 25, unchanged. PICKET.md's sensor range of 75 is a
	# ChassisDefinition field and belongs to the stats pass, not to this area.
	dsphere.radius = 25.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body

	# ── the rig ──
	var rig := _node(root_body, "Rig", Vector3.ZERO)

	# HULL. The concept's, to the centimetre, with the family's cuts: a sloped
	# glacis, a cut-back tail and a chamfer down each flank.
	var hull := _hull(rig, "Hull", HULL, Vector3(0, HULL_Y, 0))
	_cut(hull, "Glacis", Vector3(HULL.x * 1.4, HULL.y * 1.2, HULL.z * 0.8),
			Vector3(0, -HULL.y * 0.72, -HULL.z * 0.62), Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(HULL.x * 1.4, HULL.y * 1.2, HULL.z * 0.6),
			Vector3(0, -HULL.y * 0.68, HULL.z * 0.64), Vector3(20.0 * DEG, 0, 0))
	for s in [-1.0, 1.0]:
		_cut(hull, "Bevel%s" % ("L" if s < 0.0 else "R"),
				Vector3(HULL.x * 0.7, HULL.y * 0.8, HULL.z * 1.4),
				Vector3(s * HULL.x * 0.68, HULL.y * 0.66, 0),
				Vector3(0, 0, s * 30.0 * DEG))

	_mesh(rig, "TurretRing", _ring_mesh(0.52, 0.12), Vector3(0, RING_Y, 0))

	var turret := _node(rig, "Turret", Vector3(0, TURRET_Y, 0))
	# THE YOKE, not a turret house. The launcher is the unit; this is only the
	# low box that carries the trunnion, the head and the dish outrigger, and
	# it is kept shallow on purpose — C2's whole brief was that the tubes lead
	# and nothing competes with them.
	var yoke := _hull(turret, "TurretBody", Vector3(1.1, 0.34, 0.92), Vector3(0, 0.03, 0.03))
	for s in [-1.0, 1.0]:
		_cut(yoke, "Shoulder%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.5, 0.3, 1.3), Vector3(s * 0.66, 0.22, 0),
				Vector3(0, 0, s * 34.0 * DEG))

	_head(turret)
	# The Walker's whip — but off the RIGHT rear, not the left.
	#
	# The Walker wears it on the left because nothing else is there. Here the
	# left shoulder is the dish's, and a whip put beside it at x -0.4 sat
	# directly behind the launcher from every angle the game ever draws a robot
	# from: rendered, it was simply absent. One fitting per shoulder, and both
	# of them visible.
	_mesh(turret, "Antenna", _boxm(Vector3(0.03, 0.85, 0.03)), Vector3(0.42, 0.56, 0.44))
	_dish(turret)
	_launcher(turret)
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
	# EVERY PAINTED PIECE, as Node OBJECTS in a TYPED array. `pieces` is
	# Array[Node3D]; an untyped one lands as [] and FactionLivery then falls
	# back to walking its whole parent — which paints every mesh on the frame,
	# THE EYE INCLUDED. That is how the Bulwark's eye ended up faction-coloured
	# despite being left off this list: the list itself was never there.
	#
	# THE EYE IS DELIBERATELY ABSENT, and so is `Head`, which would reach it by
	# recursion (FactionLivery._gather walks children). The pieces named here
	# that ARE containers — Dish, HipL, HipR — hold nothing but metal.
	var paint: Array[Node3D] = []
	paint.append(hull)
	paint.append(rig.get_node("TurretRing"))
	paint.append(yoke)
	paint.append(turret.get_node("Head/HeadBody"))
	paint.append(turret.get_node("Antenna"))
	paint.append(turret.get_node("DishBracket"))
	paint.append(turret.get_node("DishMast"))
	paint.append(turret.get_node("Dish"))
	paint.append(turret.get_node("GunPivot/PodCant/PodPlate"))
	for i in 6:
		paint.append(turret.get_node("GunPivot/PodCant/Tube%d" % i))
	paint.append(rig.get_node("HipL"))
	paint.append(rig.get_node("HipR"))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D or Array[Node3D] — not NodePath — so assigning a NodePath to them
	# silently does nothing and the frame comes out with a null turret and legs
	# the gait cannot find. Nothing errors. PackedScene.pack() turns these
	# references back into the node_paths=PackedStringArray(...) form the editor
	# writes, so the saved scene looks hand-authored either way.
	root_body.set("rig", rig)
	root_body.set("hip_left", rig.get_node("HipL"))
	root_body.set("knee_left", rig.get_node("HipL/KneeL"))
	root_body.set("hip_right", rig.get_node("HipR"))
	root_body.set("knee_right", rig.get_node("HipR/KneeR"))
	root_body.set("foot_left", rig.get_node("HipL/KneeL/FootL"))
	root_body.set("foot_right", rig.get_node("HipR/KneeR/FootR"))
	root_body.set("turret", turret)
	root_body.set("gun_pivot", turret.get_node("GunPivot"))
	root_body.set("weapon_mount", turret.get_node("GunPivot/PodCant/WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY.
	#
	# particle_effects_die/_hit are Array[ParticleEffect] and visible_pieces is
	# Array[Node3D]. Assigning a plain untyped Array to one fails SILENTLY — no
	# error, no warning, and the packed scene comes out with []. The Bulwark
	# shipped all four empty: no death effects, no hit sparks, and a frame that
	# painted every mesh on itself.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# The three structural masses, which is what Enemy tips on death and hides
	# when the body is pooled. The launcher is in the list because on this frame
	# it is most of the machine — a Picket that hid only its hull would still be
	# a launcher standing in the field.
	var vis: Array[Node3D] = []
	vis.append(hull)
	vis.append(yoke)
	vis.append(turret.get_node("GunPivot/PodCant/PodPlate"))
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	# PICKET.md section 3 gives the hull. Everything else it lists —
	# supply, cost, speed, sensor range, slots — is ChassisDefinition's and is
	# not set here.
	root_body.set("health", 170)
	root_body.set("max_health", 170)
	root_body.set("soldier_name", "Picket")
	# THE TWO VALUES BOTH SHIPPING VEHICLE FRAMES SET, and both are scene
	# wiring rather than balance. enemy.gd defaults activation_distance to 75,
	# which is the known frozen-at-distance failure (see the ADVANCE sweep: a
	# spec beyond the activation radius never walks); the Walker and the Bulwark
	# both carry 200. And a legged gun platform does not flatten its collider
	# when it goes down, for the same reason they do not.
	root_body.set("activation_distance", 200)
	root_body.set("flatten_collider_when_downed", false)
	return root_body


## THE HEAD. Small, forward, and on the shoulder the dish is not on.
##
## C2 has no head at all — it is a silhouette study — but PICKET.md section 5
## calls for one and a frame in this game without the box-with-a-sliced-cheek
## profile and one offset eye is not recognisable as one of ours at forty
## pixels. It is built at exactly 0.6 of the Bulwark's head so the cheek and
## brow cuts land in the same places relative to it.
##
## IT OVERHANGS THE NOSE. Sat flush on the yoke it was a bump between two
## larger masses and disappeared into them in the render — the same thing
## mockup_parts.gd learned about every fitting it draws: a shape inside the
## outline is not in the picture. Pushed forward it breaks the hull's front
## edge and reads as a head, while its back end still overlaps the yoke so it
## is attached to something. It does not lengthen the frame: the tubes already
## reach further forward than it does.
func _head(turret: Node3D) -> void:
	var f := 0.6
	var head := _node(turret, "Head", Vector3(0.34, 0.07, -0.6))
	var body := _hull(head, "HeadBody", Vector3(1.0, 0.58, 0.92) * f, Vector3.ZERO)
	_cut(body, "Cheek", Vector3(1.4, 0.5, 0.5) * f, Vector3(0, -0.34, -0.6) * f,
			Vector3(-35.0 * DEG, 0, 0))
	_cut(body, "Brow", Vector3(1.4, 0.5, 0.5) * f, Vector3(0, 0.38, -0.54) * f,
			Vector3(25.0 * DEG, 0, 0))
	# ONE EYE, offset left, and the WALKER'S OWN material rather than the
	# shared metal. Painting it with faction livery like everything else would
	# make the one feature that identifies a robot in this game change colour
	# per faction, so it is deliberately left out of the livery list.
	#
	# NOT SCALED WITH THE HEAD. 0.6 of the Walker's 0.17 is a tenth of a metre,
	# which is gone by the time anything is far enough away to need identifying.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.14
	eye_mesh.height = 0.24
	eye_mesh.radial_segments = 16
	eye_mesh.rings = 8
	var eye := _mesh(head, "Eye", eye_mesh, Vector3(-0.16, 0.02, -0.26))
	eye.material_override = _eye_material()


## THE SENSOR DISH, demoted to a shoulder fitting — which is the entire
## difference between C2 and the round-one winner it replaced, where the dish
## read as the whole unit.
##
## The dish head keeps the concept's world position exactly. Its MOUNTING does
## not: the concept drops a post from the dish down into the hull, because a
## concept has no yawing assembly to hang it off. Here it rides the Turret with
## everything else, so the post stands on the yoke and a bracket reaches out to
## it. Same shape from the front; it now traverses with the launcher instead of
## sweeping through the hull.
func _dish(turret: Node3D) -> void:
	var local := DISH_AT - Vector3(0, TURRET_Y, 0)
	_mesh(turret, "DishBracket", _boxm(Vector3(0.36, 0.2, 0.3)),
			Vector3(-0.7, -0.02, local.z))
	_mesh(turret, "DishMast", _ring_mesh(0.1, 0.34), Vector3(local.x, 0.05, local.z))
	# NEGATIVE about +X, and correctly so: a cone's axis is +Y, so -X tilts the
	# face up and forward. The launcher two lines below is the opposite case.
	var d := _node(turret, "Dish", local, Vector3(DISH_CANT * DEG, 0, 0))
	_mesh(d, "DishFace", _cone_mesh(DISH_R, 0.14), Vector3.ZERO)
	_mesh(d, "DishNeck", _ring_mesh(0.055, DISH_R * 0.75), Vector3(0, DISH_R * 0.45, 0))
	_mesh(d, "DishFeed", _sphere_mesh(0.1), Vector3(0, DISH_R * 0.82, 0))


## THE LAUNCHER. Six tubes, three across and two high, canted up hard.
##
## GunPivot sits at the block's origin and DOES NOT ROTATE — see the header for
## why a cant built into it would be clamped flat by walker.gd:224 on the first
## frame of combat. PodCant below it holds the 54 degrees.
func _launcher(turret: Node3D) -> void:
	var pivot := _node(turret, "GunPivot", PODS_AT - Vector3(0, TURRET_Y, 0))
	# POSITIVE X. A rotation about +X maps -Z to (0, sin, -cos), so a NEGATIVE
	# angle sends the muzzles DOWN and forward. Three of five first-round
	# concepts had this sign wrong on the one frame whose premise is shooting
	# up; it is the single easiest thing to get backwards here.
	var cant := _node(pivot, "PodCant", Vector3.ZERO, Vector3(PODS_CANT * DEG, 0, 0))

	var cols := 3
	var rows := 2
	var step := TUBE_R * 2.3
	# The backplate the tubes are seated in, immediately behind their breeches.
	var plate := _hull(cant, "PodPlate",
			Vector3(float(cols) * TUBE_R * 2.4, float(rows) * TUBE_R * 2.4, 0.16),
			Vector3(0, 0, 0.145))
	for s in [-1.0, 1.0]:
		_cut(plate, "PlateCorner%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.22, 0.22, 0.4), Vector3(s * 0.5, 0.336, 0),
				Vector3(0, 0, 45.0 * DEG))

	for c in cols:
		for w in rows:
			var x := (float(c) - float(cols - 1) * 0.5) * step
			var y := (float(w) - float(rows - 1) * 0.5) * step
			_tube(cant, "Tube%d" % (c * rows + w), TUBE_R, TUBE_LEN,
					Vector3(x, y, -0.5 * TUBE_LEN_F))

	# AT THE MUZZLE PLANE AND ON THE CANT, so a fitted weapon lies along the
	# tubes rather than poking level out of the middle of the block.
	#
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the
	# mount has to turn that onto the assembly's -Z. Read off the Walker's
	# matrix the yaw looks like a quarter turn either way; it is not, and the
	# Bulwark's first build fitted, elevated, tracked targets and fired directly
	# behind itself. Nothing warns: a mount pointing the wrong way is a
	# perfectly valid transform.
	_node(cant, "WeaponMount", Vector3(0, 0, -0.5 * TUBE_LEN_F - TUBE_LEN * 0.5),
			Vector3(0, PI * 0.5, 0))


## THE LEGS, straight out of the concept: hip ball, thigh broken forward, shin
## broken back, long flat foot. Digitigrade, which is what makes this read as
## the Walker's relative rather than a pillar-legged dray.
##
## FootL/FootR ARE THE MESHES, not nodes above them — walker.gd counters the
## hip and knee on the foot's own rotation to keep the sole flat, exactly as
## walker.tscn does it.
func _legs(rig: Node3D) -> void:
	var thigh_len := 0.66
	var shin_len := 0.76
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		var hip := _node(rig, "Hip%s" % tag, Vector3(s * 0.62, -0.12, 0),
				Vector3(0, 0, s * 6.0 * DEG))
		_mesh(hip, "HipCap%s" % tag, _sphere_mesh(0.19), Vector3.ZERO)
		_mesh(hip, "Thigh%s" % tag, _boxm(Vector3(0.34, thigh_len, 0.4)),
				Vector3(0, -thigh_len * 0.5, thigh_len * 0.18), Vector3(15.0 * DEG, 0, 0))
		var knee := _node(hip, "Knee%s" % tag, Vector3(0, -thigh_len, thigh_len * 0.38))
		_mesh(knee, "KneeCap%s" % tag, _sphere_mesh(0.15), Vector3.ZERO)
		_mesh(knee, "Shin%s" % tag, _boxm(Vector3(0.26, shin_len, 0.3)),
				Vector3(0, -shin_len * 0.5, -shin_len * 0.2), Vector3(-15.0 * DEG, 0, 0))
		_mesh(knee, "Foot%s" % tag, _boxm(Vector3(0.4, 0.15, 0.86)),
				Vector3(0, -shin_len - 0.06, -shin_len * 0.42 - 0.18))


func _sphere_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _ring_mesh(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 0
	return c


## A shallow cone, which is a CylinderMesh with nothing at the top. The concept
## draws the dish face with CSGCylinder3D's `cone` flag; this is the same shape
## as a primitive mesh, so it needs no boolean and no bake.
func _cone_mesh(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 0
	return c


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object and this project has already
## paid for that once — see the duplicate() rule in CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m
