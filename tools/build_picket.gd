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
# THE TUBES ARE A WEAPON, NOT A CHASSIS (revision, 2026-10-10)
#
# The six canted launcher tubes used to be geometry in this rig. They are gone.
# The human's ruling, said of the Lance's cast cannon and then of this frame:
# "likewise the tubes should be a weapon not part of the chassis." Every other
# gun-carrying frame in the family already obeys it — walker.tscn, bulwark.tscn
# and vehicle_rover.tscn each carry a mantlet, a WeaponMount and NO BARREL,
# because the gun is the fitted weapon scene. A chassis that ships with its
# armament welded on cannot be refitted, cannot be shown empty in the armoury,
# and double-draws the moment a weapon IS fitted to it.
#
# WHAT THAT COSTS HERE, AND WHAT IS LEFT BEHIND. More than on any other frame:
# the selected concept is literally called "launcher-led" and PICKET.md section
# 1 says the tubes are what makes this read as an answer to being BOMBED rather
# than as a gun that happens to elevate. Deleted naively, the Picket is an
# anonymous legged box with a dish on it.
#
# So the launcher is removed and its MOUNTING IS NOT. What stays is everything
# that is chassis in the first place — the hardware a launch vehicle keeps when
# its pack is lifted off:
#
#   TrunnionL/R   bearing bosses on the yoke flanks, on the elevation axis
#   TrunnionPin   the axis itself, through them
#   Mantlet       the canted breech plate the pack bolted to, still 1.0 x 0.67
#                 — six tubes wide and two high, so the hole states its size
#   RailL/R       the cradle's side rails, open-topped and EMPTY. This is the
#                 piece doing the work: two long plates with a gap between them
#                 is a frame missing its load, where a bare plate is just a box.
#   CradleYoke    the cross brace closing the rails at the muzzle end
#   RamBodyL/R    the elevation actuators, on the yoke
#   RamRodL/R     their rods, on the cradle — see the telescope note below
#
# The sensor dish was a shoulder fitting demoted out of the way of the tubes.
# With the tubes gone it is the loudest thing on the frame, and it is now doing
# most of the identifying: a dish says AIRCRAFT before anything else has parsed.
#
# IF YOU ARE THE ONE BUILDING THE WEAPON: the tubes were CSGMesh3D cylinders,
# axis +Y, turned +90 about X so the bore lay along Z, each with a
# CSGCylinder3D subtraction offset toward local -Y (the muzzle) and stopping
# short of the far end so the breech stayed closed. A solid cylinder reads as a
# rod and six rods read as a gun — the visible bore is what makes the frame say
# "launcher" at forty pixels, and it cost one subtraction per tube. Six tubes,
# three across and two high, radius 0.14, length 1.375, spaced 0.322.
#
# ─────────────────────────────────────────────
# THE TURRET QUESTION: WHAT YAWS AND WHAT PITCHES
#
# walker.gd wants two nodes (walker.gd:200-227): `turret`, whose rotation.y it
# drives toward the target bearing, and `gun_pivot`, whose rotation.x it drives
# toward the target elevation. The Picket's whole premise is a launcher that
# points up, so the mapping has to be decided rather than assumed.
#
#   Turret    the whole upper assembly — the yoke, the head and eye, the
#             antenna, the sensor dish and the cradle. One bearing for the
#             frame, so the dish looks where the launcher looks. (PICKET.md
#             section 8 leaves a dish that traverses on its own as an open
#             question; this is the "not modelled now" answer.)
#   GunPivot  the trunnion at the top of the yoke, at the launcher's own origin
#             (0, 1.22, 0). It carries the cradle and nothing else.
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
# THE WEAPON MOUNT RIDES THE CANT, and it has MOVED TO THE BREECH PLANE.
# It used to hang at the muzzle end, which was right while the tubes were
# chassis: a fitted weapon then started where they stopped. Now the tubes ARE
# the fitted weapon, so the mount goes where their breeches were — cant-local
# z +0.0625, the face of the mantlet — and a fitted launcher grows forward out
# of the cradle and fills it, instead of hanging 1.4 m off the nose.
#
# Its own yaw is +PI/2 — not -PI/2 — which is what turns a weapon's +X muzzle
# onto the assembly's -Z; read off the Walker's matrix it looks like a quarter
# turn either way, it is not, and the Bulwark fired backwards for it.
#
# THE ELEVATION RAMS TELESCOPE, DELIBERATELY. A strut between a static node and
# one walker.gd re-aims every frame cannot be rigid: the body is on the yoke and
# the rod is on the cradle, so elevation slides one along the other. They are
# built with ~0.1 m of overlap at rest so the pair reads as one actuator
# through the whole of gun_min/max_pitch_degrees instead of pulling apart. A
# single rigid strut on either node would visibly detach from the other.
#
# ─────────────────────────────────────────────
# TWO THINGS THAT DISAGREE WITH docs/frames/PICKET.md, ON PURPOSE
#
# 1. THE HEIGHT. PICKET.md section 1 records 4.15 m measured off the built
#    frame, taller than the Walker's 3.81 and taller than the 4.07 the chosen
#    concept was drawn specifically to cut down — an open decision, and not
#    this generator's to make.
#
#    REMOVING THE TUBES CHANGED IT, because the tubes were the tallest thing on
#    the frame: canted 54 degrees and 1.375 long, their muzzles alone reached
#    y 2.46. With the cradle in their place the frame measures 3.74 m, and the
#    tallest piece is now the antenna. NOTHING HERE WAS SCALED TO HIT THAT
#    NUMBER — it is what the concept's own proportions come to once the pack is
#    a weapon, and the cradle's length is set by the trunnion frame a 1.375 m
#    pack would need (0.78, a little over half), not by a height target. Note
#    that a fitted launcher puts the silhouette back near 4.15 in the field;
#    what has changed is what the CHASSIS measures.
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
#
#    KEPT AT 3.0 THROUGH THE TUBE REMOVAL. It is deliberately a hull capsule,
#    not a silhouette capsule: the Walker's stops below its gun too, and a
#    fitted launcher puts volume straight back where the tubes were. Shrinking
#    it to the bare chassis would make the frame harder to hit once it is armed
#    than it was while it was unarmed.
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
## THE PACK THAT IS NO LONGER HERE. These are kept because the cradle is sized
## by them and by nothing else: the mantlet is as wide as three tubes and as
## tall as two, the breech plane is where their rear faces were, and the rail
## length is a fraction of their length. A cradle measured in its own round
## numbers would stop fitting the weapon the moment either moved.
const TUBE_R := 0.14
const TUBE_LEN_F := 1.25
const TUBE_LEN := 1.1 * TUBE_LEN_F
const TUBE_COLS := 3
const TUBE_ROWS := 2
## Cant-local z of the pack's breech faces. The WeaponMount goes here.
const BREECH_Z := -0.5 * TUBE_LEN_F + TUBE_LEN * 0.5
## The cradle's side rails, a little over half the pack's length — a trunnion
## frame carries the load at its root, it does not sleeve the whole of it.
const RAIL_LEN := 0.78
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


## A CYLINDER LAID BETWEEN TWO POINTS in the parent's own space — the trunnion
## pin, the bosses and the elevation ram.
##
## The rotation is COMPUTED, not hand-written, and that is the point of having
## this at all: the ram's two halves live on nodes 54 degrees apart, and the
## Euler angles for "the same strut, expressed on the cant" are precisely the
## kind of sign error the cant note in the header is about. Give it two points
## and let it do the trigonometry.
##
## A CylinderMesh's axis is +Y, so the piece takes the shortest arc from +Y onto
## the strut direction.
func _strut(parent: Node, nm: String, from: Vector3, to: Vector3, r: float,
		facets: int = 10) -> MeshInstance3D:
	var axis := to - from
	var length := axis.length()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = facets
	cm.rings = 0
	var m := _mesh(parent, nm, cm, (from + to) * 0.5)
	var dir := axis / length
	var dot := dir.dot(Vector3.UP)
	if dot < 0.99999:
		# Antiparallel has no unique arc and cross() degenerates to zero, which
		# would normalize() to (0,0,0) and silently leave the piece upright.
		# Nothing here is antiparallel today; a half-turn is the right answer if
		# something ever is.
		var ax := Vector3.UP.cross(dir)
		ax = Vector3.FORWARD if ax.length() < 0.0001 else ax.normalized()
		m.transform.basis = Basis(ax, Vector3.UP.angle_to(dir))
	return m


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
	_cradle(turret)
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
	# THE CRADLE, NOT THE LAUNCHER. These replaced PodPlate and Tube0..5 when
	# the tubes became a fitted weapon, and the list was NOT updated with them:
	# get_node returned null for every old path, the seven new pieces joined no
	# list, and the first render came back with a bare metal cradle bolted to a
	# faction-blue frame. Nothing errored that check_frame.gd could see.
	paint.append(turret.get_node("TrunnionL"))
	paint.append(turret.get_node("TrunnionR"))
	paint.append(turret.get_node("RamBody"))
	paint.append(turret.get_node("GunPivot/TrunnionPin"))
	paint.append(turret.get_node("GunPivot/PodCant/Mantlet"))
	paint.append(turret.get_node("GunPivot/PodCant/RailL"))
	paint.append(turret.get_node("GunPivot/PodCant/RailR"))
	paint.append(turret.get_node("GunPivot/PodCant/CradleYoke"))
	paint.append(turret.get_node("GunPivot/PodCant/RamRod"))
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
	# The mantlet, not the launcher plate it replaced — visible_pieces drives
	# hide_body and the death collapse, and a stale path put a null in a typed
	# array here too.
	vis.append(turret.get_node("GunPivot/PodCant/Mantlet"))
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


## THE CRADLE — the launcher's mounting, with the launcher gone. See the header:
## the six tubes are a fitted weapon now, and what a launch vehicle keeps when
## its pack is lifted off is the trunnion, the rails it sat in, the breech
## mantlet and the elevation hardware. All of that is here and nothing else is.
##
## The piece carrying the read is RailL/RailR: two long plates with an OPEN,
## EMPTY trough between them. A bare mantlet is a box on a yoke; a visibly
## empty cradle is a machine with its load missing, which is the difference
## between "frame awaiting a launcher" and "frame that never had one".
##
## GunPivot sits at the pack's origin and DOES NOT ROTATE — see the header for
## why a cant built into it would be clamped flat by walker.gd:224 on the first
## frame of combat. PodCant below it holds the 54 degrees, and the name is kept
## because it is what the saved scene's node paths already say.
func _cradle(turret: Node3D) -> void:
	var pivot_at := PODS_AT - Vector3(0, TURRET_Y, 0)
	var pivot := _node(turret, "GunPivot", pivot_at)
	# POSITIVE X. A rotation about +X maps -Z to (0, sin, -cos), so a NEGATIVE
	# angle sends the cradle's mouth DOWN and forward. Three of five first-round
	# concepts had this sign wrong on the one frame whose premise is shooting
	# up; it is the single easiest thing to get backwards here.
	var cant := _node(pivot, "PodCant", Vector3.ZERO, Vector3(PODS_CANT * DEG, 0, 0))

	# THE TRUNNION. Bearing bosses on the yoke flanks — which do NOT elevate, so
	# they hang off the Turret — and the pin between them, which does, so it
	# hangs off the pivot. A cylinder turning about its own axis shows nothing,
	# which is the only reason the pin can be on the moving half at all.
	for s: float in [-1.0, 1.0]:
		var bx := s * 0.56
		_strut(turret, "Trunnion%s" % ("L" if s < 0.0 else "R"),
				Vector3(bx - s * 0.06, pivot_at.y, 0.0),
				Vector3(bx + s * 0.06, pivot_at.y, 0.0), 0.15, 12)
	_strut(pivot, "TrunnionPin", Vector3(-0.59, 0, 0), Vector3(0.59, 0, 0), 0.055, 10)

	# THE MANTLET — the canted plate the pack bolts to, kept at the pack's own
	# footprint: three tubes across, two high. That is deliberate. The hole in
	# the middle of this frame has to state the size of what belongs in it, and
	# a plate trimmed to look tidy would understate it.
	var mantlet := _hull(cant, "Mantlet",
			Vector3(float(TUBE_COLS) * TUBE_R * 2.4, float(TUBE_ROWS) * TUBE_R * 2.4, 0.16),
			Vector3(0, 0, 0.145))
	for s in [-1.0, 1.0]:
		_cut(mantlet, "PlateCorner%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.22, 0.22, 0.4), Vector3(s * 0.5, 0.336, 0),
				Vector3(0, 0, 45.0 * DEG))

	# THE RAILS. Flush with the mantlet's flanks, running forward to just over
	# half the pack's length, open at the top and at the muzzle end.
	for s in [-1.0, 1.0]:
		_mesh(cant, "Rail%s" % ("L" if s < 0.0 else "R"),
				_boxm(Vector3(0.07, 0.42, RAIL_LEN)),
				Vector3(s * 0.5, -0.13, -RAIL_LEN * 0.5))
	# The cross brace closing the rails, kept LOW so the trough still reads as
	# open from in front. Across the bottom it is a cradle; across the top it
	# would be a box with a slot in it.
	_mesh(cant, "CradleYoke", _boxm(Vector3(1.07, 0.1, 0.13)),
			Vector3(0, -0.29, -RAIL_LEN + 0.065))

	# THE ELEVATION RAM. One, not two, and offset LEFT of centre: the head sits
	# on the right shoulder at x 0.04..0.64 and a symmetric pair put the
	# starboard ram straight through it. Asymmetry is already this frame's
	# language — dish left, antenna and head right, eye offset.
	#
	# TELESCOPING ON PURPOSE. The body is on the yoke and the rod is on the
	# cradle, so elevation slides one along the other; they overlap ~0.1 m at
	# rest so the pair still reads as one actuator across the whole travel. A
	# rigid strut on either node would visibly tear away from the other, which
	# is the shape of the rest-pose trap one level down: anything that spans a
	# joint walker.gd writes every frame cannot be one piece.
	var foot := Vector3(-0.10, 0.17, -0.42)
	var head_end := cant.transform * Vector3(-0.10, -0.37, -0.62)
	var reach := head_end - foot
	_strut(turret, "RamBody", foot, foot + reach * 0.80, 0.075, 10)
	var to_cant := cant.transform.affine_inverse()
	_strut(cant, "RamRod", to_cant * (foot + reach * 0.34), to_cant * head_end, 0.04, 8)

	# AT THE BREECH PLANE AND ON THE CANT, so a fitted launcher grows forward
	# out of the cradle and fills it. It used to sit at the muzzle plane, which
	# was correct while the tubes were chassis and is 1.4 m too far forward now
	# that they are the weapon.
	#
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the
	# mount has to turn that onto the assembly's -Z. Read off the Walker's
	# matrix the yaw looks like a quarter turn either way; it is not, and the
	# Bulwark's first build fitted, elevated, tracked targets and fired directly
	# behind itself. Nothing warns: a mount pointing the wrong way is a
	# perfectly valid transform.
	_node(cant, "WeaponMount", Vector3(0, 0, BREECH_Z), Vector3(0, PI * 0.5, 0))


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
