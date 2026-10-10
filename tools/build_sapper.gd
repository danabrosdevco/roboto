extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/sapper.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_sapper.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. This is not a build step:
# re-running it over a scene that has since been touched in the editor throws
# that work away, which is how --force rebuilds have repeatedly cost this
# project its gameplay layers. If the geometry needs changing after today,
# CHANGE THE SCENE. It exists only because a robot scene is forty-odd
# sub-resources with hand-numbered ids and an exact load_steps count that
# check.sh verifies, and writing that by hand is transcription with nothing to
# learn from.
#
# ─────────────────────────────────────────────
# WHAT THIS IS
#
# SAPPER — supply 1, INFANTRY, engineer. docs/frames/SAPPER.md is the design
# doc; concept B, the PLANTER, is the selected silhouette: both hands on a
# T-handled tool driven into the ground ahead of it, a bandolier of mine discs
# across the small of the back, hunched over the work. 1.04 W x 2.10 H x 1.44 L
# in the concept — the smallest thing in this batch of ten.
#
# ─────────────────────────────────────────────
# WHERE THE PROPORTIONS COME FROM
#
# ConceptsA.sapper_b() in tools/concepts_a.gd, which is the authority. Every
# position, length and thickness below is that function's own number, written
# in that function's own frame of reference so the two files can be read side
# by side. The kit calls are expanded rather than called because ConceptKit's
# shapes are raw CSG with no material and no scene ownership — fine for a
# concept render, wrong for a shipping scene — so everything here goes through
# _mesh / _hull / _cut, the same three helpers build_bulwark.gd uses, which set
# the shared robot_metal material and the owner PackedScene.pack() needs.
#
# THE CONCEPT'S GROUND IS y = 0 AND THIS FRAME'S ORIGIN IS NOT. enemy.gd says
# it outright at _feet_y(): "the origin is the middle of the capsule, so it is
# -1.0 on a 2m frame". Every chassis in the game honours that — the soldier's
# default capsule is r 0.5 h 2.0 centred on the origin, the walker's is
# r 0.85 h 3.0. So the whole frame hangs off a Rig node at y = GROUND and every
# number under it is the concept's own, unshifted. Nothing else in the scene
# sits in concept space: the collider, the detection sphere and the particles
# are all body-space, which is where they belong.
#
# ─────────────────────────────────────────────
# THIS IS THE ONLY INFANTRY FRAME IN THE BATCH, AND IT FOLLOWS THE SOLDIER
#
# docs/briefs/FRAME_MODELS.md's node contract was written from the Bulwark,
# which is a mech. Where a mech and the shipped infantry disagree, these follow
# soldier_chassis.tscn / soldier_rifle.tscn and the reason is written at each
# one:
#
#   COLLIDER    the soldier's own default capsule, r 0.5 h 2.0, not a capsule
#               sized to the art. See the note at the shape.
#   NO TURRET   soldier.gd declares none, and enemy.gd's hull_spoils_aim tests
#               `"turret" in self` — adding one would silently tell the aiming
#               code this frame traverses when it does not. The head is
#               body-fixed. (The Lance's stub-turret rule is a walker.gd rule.)
#   MOUNT SCALE WeaponMount is scaled 0.4, which is what both soldier scenes
#               and the Mechanic do: AI weapon scenes are authored at vehicle
#               scale and infantry shrink them at the mount. The Walker's mount
#               is scale 1.0; copying that would fit a carbine the size of the
#               robot.
#   DETECTION   body_entered / body_exited are CONNECTED. Every shipped soldier
#               scene connects them; none of bulwark/lance/picket/kite does.
#               See the note at the Area3D.
#
# Everything at the contract's edges is unchanged: persistent "enemies" group,
# typed arrays everywhere, a livery list with the eye left off it, mount yaw
# +PI/2, Rig/Hull naming, no RankKit (none of the four new frames has one).
#
# ─────────────────────────────────────────────
# WHERE THE MINES LIVE, AND WHY YOU CAN SEE THEM
#
# THE DOC SETTLES THIS and this build follows it. SAPPER.md section 1: "a
# bandolier of mine discs across the lower back", drawn as "flat discs with a
# ring, ~0.26 m — a shape new to the roster, which is what lets a bandolier of
# them read as ordnance rather than pouches". So: four discs on edge across the
# small of the back, 0.22 across the disc and 0.28 across its ring, on the
# TORSO so they ride the hunch, and ON EDGE rather than stacked flat so the
# disc shape survives in profile. A sapper whose charges you cannot see is a
# sapper that looks like a soldier, which is the one thing this frame must not
# be.
#
# EACH ONE IS ITS OWN NAMED NODE — Bandolier/Mine0 .. Mine3, each holding a
# Disc and a Ring — so a future script can hide them one at a time as they are
# planted without touching geometry. Nothing does that today; the nodes cost
# nothing and the alternative (four discs welded into one mesh) would have to
# be unpicked by hand the day something wants to.
#
# ─────────────────────────────────────────────
# FIVE THINGS MEASURED IN THE CONCEPT AND CORRECTED HERE
#
# All five are seating faults, not redesigns: the silhouette, the limb lengths,
# the shoulder positions, the tool and the bandolier are the concept's.
#
# 1. THE HANDS WERE 0.37 m FROM THE TOOL. The concept's whole argument is that
#    the verb IS the silhouette — "both hands on a T-handled tool". Measured,
#    they are not on it: the concept's arm angles (droop 44/20, out 6/-6, fore
#    26/40) put the right wrist at (0.35, 0.95, -0.37) and the left at
#    (-0.35, 0.94, -0.41), while the shaft at that height runs through
#    (0, ~0.95, -0.50). The two grip collars the concept adds "to bridge
#    whatever the arm angles leave over" are 0.35 away from the nearest hand
#    and bridge nothing.
#    The shaft itself is unreachable — 0.64 from the shoulder against a 0.52 m
#    arm — but THE T-HANDLE IS NOT: its ends at (+-0.17, 1.10, -0.47) are 0.473
#    from the shoulder, inside the reach with a bend to spare. So the arms are
#    re-posed onto the handle ends and nothing else about them changes. Solved,
#    not eyeballed: with equal 0.26 segments the elbow angle is fixed by
#    |delta| = 2L cos(droop/2), and the two shoulder angles fall out of
#    matching (u + v) to delta. ARM_* below are that solution and the wrist
#    lands on the handle end to the millimetre.
#    The collars are replaced by a fist at each wrist, which is what they were
#    standing in for.
#
# 2. THE SATCHEL FLOATED 0.14 m OFF THE HULL. mockup_parts.plate() extrudes
#    along its own -Z, not +Z — the comment in ConceptsA.sapper_a() has the
#    sign backwards. Proof is the measurement: with +Z the concept's B is
#    0.90 wide and with -Z it is 1.03, and shoot_concepts prints 1.04. So the
#    concept's single satchel, placed at x -0.40 and turned a quarter turn
#    about Y, runs OUTBOARD from -0.40 to -0.58 — and the hull's port face is
#    at -0.26, so it hangs in mid-air with a hand's width of daylight behind
#    it. It is seated against the flank here instead, 0.18 thick from -0.44 to
#    -0.26. THAT IS WHERE THE MISSING 0.14 OF WIDTH WENT; see the report.
#
# 3. THE MOUNT RING WAS INSIDE THE HEAD. The fault FRAME_MODELS.md names in
#    concept_kit.head(): the ring sits at `at` and the turret body at
#    `at + 0.19 * scale`, and the body is taller than that gap, so the ring has
#    never been visible on any sheet. MOVED, not dropped — lowered to y 0.3286
#    where it fills the 0.044 m gap between the hull's top and the head's
#    underside and reads as the neck collar the Bulwark calls NeckRing.
#
# 4. THE GUN PORT WAS INSIDE THE EYE. concept_kit.head() puts the mantlet at
#    x -0.2 * scale and the eye at x -0.34 * scale, and at this frame's 0.42
#    head scale the two intersect. (So do the Walker's, at scale 1.0 — this is
#    inherited, not introduced.) On a head 0.50 m across two overlapping lumps
#    read as one, so the mantlet is MIRRORED to starboard: eye to port, gun to
#    starboard, nothing touching.
#
# 5. THE CAST BARREL IS GONE. concept_kit.head() ends in a 1.5 * scale
#    cylinder, which here is a 0.63 m barrel out of the head of a 1.75 m
#    robot — and the doc's named risk for this concept is that it reads as
#    carrying a rifle. The WeaponMount goes where the barrel was instead, so
#    the catalogue's carbine occupies the space the concept drew a gun in.
#    (The Lance keeps its cast barrel because the gun IS the Lance; here it is
#    a frame that "can defend itself, badly".)
#
# AND THE MOUNT IS LEVELLED. The head rides a torso leaning 10 degrees forward,
# so a mount built straight into it hands every fitted weapon a 10-degree nose
# dive. GunCant undoes it: +10 about X, which is the sign that lifts a -Z
# muzzle (FRAME_MODELS.md's sixth trap). It is its own node rather than folded
# into the mount's euler because check_frame reads rotation.y off the mount and
# a composed pitch-and-yaw basis does not decompose to a clean +90.
#
# ─────────────────────────────────────────────
# WHAT THIS DELIBERATELY DOES NOT DO
#
# No ChassisDefinition, no catalogue entry, no items, no sapper.gd. The doc's
# section 3 stats that have a home on the SCENE are set (health 55, and
# move_speed 5.7 = the soldier scene's 6.0 times the doc's base_speed 0.95);
# the ones that only exist on ChassisDefinition — cost, supply, equipment_slots
# 3, module_slots, required_rank, starting_weapon_id — are not invented here.
# A frame whose model exists and whose stats do not is the deliberate
# half-finished state FRAME_MODELS.md describes.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/sapper.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
const BODY_SCRIPT := "res://Character/characters/ai/soldier.gd"
## The soldier's own first two voices. This frame is in the soldier's size
## class and the doc's argument is that it must read as the same army, so it is
## issued the same throat.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__19.wav"
## The Walker's eye is a plain StandardMaterial3D with this as its albedo, not
## the shared faction metal. Carried over verbatim so every eye in the game is
## the same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

const DEG := PI / 180.0

## Where the concept's ground plane (y = 0) sits in body space. Half the
## collision capsule's height, because enemy.gd._feet_y() measures the deck off
## the bottom of that capsule and a frame whose soles are anywhere else either
## floats or sinks when it collapses.
const GROUND := -1.0

## The concept's two thickness factors, kept as names because every limb
## dimension below is one of the kit's constants times one of these.
const LEG_T := 0.62
const ARM_T := 0.58
## The head's scale factor in concept_kit terms.
const HEAD_S := 0.42

## THE RE-POSED ARMS. See correction 1 in the header. Solved for a wrist on the
## T-handle's end at (+-0.17, 1.10, -0.47) from a shoulder at (+-0.30, 0.22,
## -0.04) with two 0.26 m segments; `out` is mirrored per side, the other two
## are not. The concept's own values were droop 44/20, out 6/-6, fore 26/40 —
## arms hanging beside the body, which is the pose this replaces.
const ARM_FORE := 44.02
const ARM_OUT := 17.59
const ARM_DROOP := 49.06

var _metal: Material
var _root: CharacterBody3D


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_sapper: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_sapper: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_sapper: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
#
# The same three helpers build_bulwark.gd uses. EVERYTHING VISIBLE GOES THROUGH
# ONE OF THEM, so nothing can be left without the shared metal — a single
# unpainted piece is invisible as a bug until someone renders the frame in a
# faction colour.
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


## A CSG box used as a CUT. Subtractions are how this family gets its sloped
## glacis and chamfered flanks, and reusing them is most of why a new frame
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
## which is the only reason these may exist at all — see that file for the
## 335 ms spike that made baking compulsory. Everything that needs no cut is a
## plain MeshInstance3D, which costs the bake nothing.
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


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere_mesh(r: float, squash: float = 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 * squash
	s.radial_segments = 12
	s.rings = 6
	return s


func _cyl_mesh(r: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	return c


## A real torus, not a thin cylinder standing in for one. The mine's ring is
## the whole reason a disc on this frame reads as ordnance and not as a pouch
## (SAPPER.md section 1), so it is the one place that earns the extra faces.
func _torus_mesh(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 12
	t.ring_segments = 6
	return t


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object — see the duplicate() rule in
## CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Sapper"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, which means "for this run only" — a
	# frame built without it packs with no groups line, and a robot outside
	# "enemies" is invisible to AIManager, to EMP and to every hostile sweep in
	# the game while still walking around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision ──
	#
	# THE SOLDIER'S OWN CAPSULE, not one sized to this art, and that is a
	# deliberate departure from FRAME_MODELS.md section 3. soldier_chassis.tscn
	# ships the default CapsuleShape3D — r 0.5, h 2.0, centred on the origin —
	# and so does every infantry scene behind it. Three reasons to match it
	# rather than fit 2.10:
	#   it is the gameplay volume. A supply-1 infantry frame that cannot follow
	#   a soldier through a gap a soldier fits is a bug nobody would diagnose
	#   as a collider.
	#   the art's extra 0.10 is the whip antenna. The head crowns at 1.72 and
	#   the shoulders at 1.33; a capsule drawn to the antenna tip would be a
	#   capsule drawn to a 12 mm wire. The Walker does the same in the other
	#   direction — its soles are at -1.675 under a capsule that stops at -1.5.
	#   it fixes GROUND. _feet_y() returns -1.0 and the soles are modelled at
	#   exactly -1.0, so a collapse needs no lift.
	# The planting tool reaches 0.97 forward of the origin, well outside the
	# capsule, ON PURPOSE: a tool stuck in the ground must not block a doorway.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 2.0
	col.shape = cap
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, OR THE ASSIGNMENT IS DISCARDED IN SILENCE. bark_clips is
	# Array[AudioStream]; handing it a plain Array fails with no error and the
	# instance keeps bark.tscn's three defaults. bulwark.tscn is the proof the
	# brief cites and it is still the one frame shipping WAV_RDV__2/5/98 while
	# its generator names 17/23 — left alone deliberately, because changing a
	# built robot's voice is a game-feel call for the human.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# A shade under the soldier's stock 0.96-1.06: the same voice class, which
	# is the doc's "same army" argument, carrying a load. Flagged in the report
	# as a game-feel number the human may want elsewhere.
	bark.set("pitch_min", 0.92)
	bark.set("pitch_max", 1.02)
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
	# WIRED UP, WHICH THE FOUR NEW FRAMES ARE NOT. enemy.gd does not connect
	# these anywhere — _on_detection_body_entered is reached from the engine
	# signal and from force_check_detection(), nothing else — so every shipped
	# soldier, shotgunner, marksman, chaser and watcher scene carries the two
	# connections in its .tscn, and NOT ONE of the generated frames does —
	# counted at the time of writing: bulwark, lance, picket, kite, bastion,
	# drayman, warden and vessel all have zero [connection] lines. Without them
	# the proximity path is dead and the frame sees only what its vision cone
	# finds. Following the soldier scenes here; the others are the
	# coordinator's, since it is one line in each generator.
	#
	# CONNECT_PERSIST, OR THE CONNECTION IS NOT SAVED. Same shape of trap as
	# add_to_group's second argument: PackedScene.pack() only writes out
	# connections carrying that flag, so a plain connect() here produces a
	# scene with no [connection] lines at all and a Detection area wired to
	# nothing — correct in the generator's own process, gone the moment it is
	# saved. Verified by reading them back out of the .tscn.
	det.body_entered.connect(Callable(root_body, "_on_detection_body_entered"),
			Object.CONNECT_PERSIST)
	det.body_exited.connect(Callable(root_body, "_on_detection_body_exited"),
			Object.CONNECT_PERSIST)

	# ── the rig ──
	#
	# AT GROUND, SO EVERY NUMBER BELOW IS THE CONCEPT'S OWN. ConceptsA draws
	# with the deck at y = 0 and a chassis scene puts its origin at the middle
	# of its collider, so the whole visual tree is dropped by one node's
	# position instead of GROUND + y being written forty times. tools/
	# concepts_a.gd:335 and this function can be diffed line against line.
	var rig := _node(root_body, "Rig", Vector3(0, GROUND, 0))

	_legs(rig)
	var torso := _torso(rig)
	_tool(rig)

	# ── effects ──
	var spark := (load(SPARK) as PackedScene).instantiate()
	spark.name = "SparkBurst"
	root_body.add_child(spark)
	spark.owner = root_body
	var oil := (load(OIL) as PackedScene).instantiate()
	oil.name = "OilSpray"
	root_body.add_child(oil)
	oil.owner = root_body

	# ── livery ──
	var livery := Node.new()
	livery.name = "FactionLivery"
	livery.set_script(load(LIVERY))
	root_body.add_child(livery)
	livery.owner = root_body
	livery.set("base_material", _metal)
	livery.set("paint_blend", 1.0)
	livery.set("marker_energy", 6.0)
	# NODE OBJECTS, IN A TYPED ARRAY. `pieces` is Array[Node3D]; an untyped one
	# lands as [] and FactionLivery then falls back to walking its whole
	# parent — which paints every mesh on the frame, THE EYE INCLUDED. That is
	# exactly how the Bulwark's eye ended up faction-coloured despite being
	# left off a list that was never there.
	#
	# THE EYE IS DELIBERATELY ABSENT and nothing here contains it. _gather()
	# RECURSES, so listing `Rig` or `Head` would drag the eye in through the
	# back door; the head's three painted pieces are therefore named one by one
	# while the legs, arms, bandolier and tool are listed at their group node,
	# which holds nothing but metal.
	var paint: Array[Node3D] = []
	paint.append(rig.get_node("HipL"))
	paint.append(rig.get_node("HipR"))
	paint.append(rig.get_node("Tool"))
	paint.append(torso.get_node("Hull"))
	paint.append(torso.get_node("NeckRing"))
	paint.append(torso.get_node("Head/HeadBody"))
	paint.append(torso.get_node("Head/Antenna"))
	paint.append(torso.get_node("Head/Mantlet"))
	paint.append(torso.get_node("ArmL"))
	paint.append(torso.get_node("ArmR"))
	paint.append(torso.get_node("Bandolier"))
	paint.append(torso.get_node("Satchel"))
	paint.append(torso.get_node("SatchelStudA"))
	paint.append(torso.get_node("SatchelStudB"))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D or an array of them — not NodePath — so assigning a NodePath does
	# nothing at all and the frame comes out with a null mount and no senses.
	# Nothing errors. PackedScene.pack() turns the references back into the
	# node_paths=PackedStringArray(...) form the editor writes, so the saved
	# scene looks hand-authored either way.
	#
	# soldier.gd declares NO node paths of its own (grep '^@export var' says
	# so: aggressive, formation_trail, the cover and suppression floats, and
	# nothing else). Everything below is inherited from enemy.gd. There is no
	# `rig` export on this script and none is set — that one belongs to
	# walker.gd and rover.gd.
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	root_body.set("weapon_mount", torso.get_node("Head/GunCant/WeaponMount"))
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY. particle_effects_die/_hit are
	# Array[ParticleEffect] and visible_pieces is Array[Node3D]; a plain
	# untyped Array assigned to any of them fails SILENTLY and the packed scene
	# comes out with []. The Bulwark shipped all three empty on its first
	# build: no death effects, no hit sparks, and a frame that painted its own
	# eye.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# ONE ENTRY, AND IT IS THE WHOLE RIG. enemy.gd._collapse_pieces tips each
	# listed piece about the BODY's origin, so a list of leaf meshes tips only
	# those leaves: the Bulwark lists its pelvis and torso box and leaves its
	# arms, shield and legs standing upright in the air around a fallen chest.
	# Rig is one Node3D above everything drawn, so the frame goes over in one
	# piece, hide_body() hides all of it, and _keep_pieces_above_deck measures
	# the soles — which are at exactly _feet_y(), so the lift is zero.
	var vis: Array[Node3D] = []
	vis.append(rig)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	# SAPPER.md section 3, and only the two stats that have a home on a scene.
	# base_health 55 — under the soldier's 60, as the doc asks.
	root_body.set("health", 55)
	root_body.set("max_health", 55)
	# base_speed 0.95 against the soldier scene's own move_speed of 6.0.
	# "carrying a load", per the doc.
	root_body.set("move_speed", 5.7)
	root_body.set("soldier_name", "Sapper")
	# base_sensor_range 45 is already enemy.gd's default for sensor_range, so
	# there is nothing to write; activation_distance is left at the default the
	# player-squad infantry frames use (soldier_chassis and mechanic_chassis
	# both leave it alone). Neither is invented here.
	#
	# AllowedMovementOptions / AllowedCombatOptions are left empty, as on all
	# four frames built before this one. Both are guarded by is_empty() in
	# enemy.gd so nothing breaks, and both are what produce the two expected
	# "Cannot assign contents of Array[Object] to Array[int]" errors on load —
	# one shared fix for the whole family, and not this frame's to make.
	return root_body


# ─────────────────────────────────────────────
# LEGS — pillars with round pads, ConceptsA.sapper_b() lines 338-339.
#
# NOT the kit's digitigrade leg. Its foot is 0.86 m long whatever `thick` says,
# which on a 1.75 m frame is a flipper — concepts_a.gd's own header says so and
# every Sapper concept stands on the pillar leg's pad instead.
#
# BRACED, NOT SYMMETRIC. Positive `reach` swings a limb forward, so the right
# leg is planted ahead (+12) and the left is back (-10): it is leaning into the
# tool. Named HipL/ThighL/KneeL/ShinL/FootL after the Walker's bones, so
# anything that goes looking for a leg by name on this family finds one.
# ─────────────────────────────────────────────
func _legs(rig: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		var reach := -10.0 if s < 0.0 else 12.0
		var hip := _node(rig, "Hip%s" % tag, Vector3(s * 0.20, 0.98, 0),
				Vector3(reach * DEG, 0, s * 3.0 * DEG))
		_mesh(hip, "HipCap%s" % tag, _sphere_mesh(0.19 * LEG_T), Vector3.ZERO)
		# W_THIGH (0.34, -, 0.4) widened 1.25x by the pillar branch, then
		# thinned by LEG_T. The thigh's own length is the concept's 0.44.
		_mesh(hip, "Thigh%s" % tag,
				_boxm(Vector3(0.34 * 1.25 * LEG_T, 0.44, 0.4 * 1.25 * LEG_T)),
				Vector3(0, -0.22, 0))
		var knee := _node(hip, "Knee%s" % tag, Vector3(0, -0.44, 0))
		# A collar at the joint. The kit draws a torus; a thin disc of the same
		# outer radius is the Bulwark's idiom for a ring and reads identically
		# at 0.12 across, for a fraction of the faces.
		_mesh(knee, "KneeRing%s" % tag, _cyl_mesh(0.2 * LEG_T, 0.05, 10), Vector3.ZERO)
		# W_SHIN (0.26, -, 0.3) widened 1.3x, thinned by LEG_T, length 0.42.
		_mesh(knee, "Shin%s" % tag,
				_boxm(Vector3(0.26 * 1.3 * LEG_T, 0.42, 0.3 * 1.3 * LEG_T)),
				Vector3(0, -0.21, 0))
		# The pad. Its underside is the sole: knee -0.44, pad centre -0.47,
		# half-height 0.07, so -0.98 in leg space against a hip at 0.98 — the
		# concept's ground, and therefore the collider's bottom.
		_mesh(knee, "Foot%s" % tag, _cyl_mesh(0.26 * LEG_T, 0.14, 12),
				Vector3(0, -0.47, 0))


# ─────────────────────────────────────────────
# THE TORSO, and everything that rides the hunch.
#
# Only a slight lean — the doc's words are "this one is driving something down,
# not carrying", against the Spool's 17 and the Mule's 26. A torso leaning
# FORWARD is a NEGATIVE angle about X, because a positive one takes +Y to +Z.
# ─────────────────────────────────────────────
func _torso(rig: Node3D) -> Node3D:
	var torso := _node(rig, "Torso", Vector3(0, 1.12, 0), Vector3(-10.0 * DEG, 0, 0))

	# The Walker's hull, scaled: a chamfered block with a sloped glacis, a
	# cut-back tail and a bevel down each flank. Every cut below is
	# concept_kit.hull()'s own expression evaluated at size (0.52, 0.62, 0.38).
	var hull := _hull(torso, "Hull", Vector3(0.52, 0.62, 0.38), Vector3.ZERO)
	_cut(hull, "Glacis", Vector3(0.728, 0.744, 0.304), Vector3(0, -0.4464, -0.2356),
			Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(0.728, 0.744, 0.228), Vector3(0, -0.4216, 0.2432),
			Vector3(20.0 * DEG, 0, 0))
	for s in [-1.0, 1.0]:
		_cut(hull, "Bevel%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.364, 0.496, 0.532), Vector3(s * 0.3536, 0.4092, 0),
				Vector3(0, 0, s * 30.0 * DEG))

	# THE NECK RING, MOVED OUT OF THE HEAD. See correction 3 in the header: the
	# kit puts this at y 0.40 with the head body spanning 0.3538 upward, so it
	# has been buried at every scale it has ever been drawn at. Dropped to
	# 0.3286 it fills the 0.044 gap between the hull's crown at 0.31 and the
	# head's underside at 0.3538 and finally reads as a neck. Radius is the
	# kit's own W_RING_R * HEAD_S, so it is narrower than the head it carries.
	_mesh(torso, "NeckRing", _cyl_mesh(0.54 * HEAD_S, 0.12 * HEAD_S, 14),
			Vector3(0, 0.3286, -0.05))

	_head(torso)
	_arms(torso)
	_bandolier(torso)
	_satchel(torso)
	return torso


# ─────────────────────────────────────────────
# THE HEAD — the Walker's turret silhouette at 0.42, BODY-FIXED.
#
# It does not traverse and nothing drives it. soldier.gd declares no `turret`
# and enemy.gd's hull_spoils_aim keys off whether the script has one, so this
# frame correctly pays the moving-accuracy penalty of something that aims with
# its whole body. The node is called Head for that reason — calling it Turret
# would read as a traverse to the next person who opens the scene.
#
# The profile — a box with the cheek sliced off below and the brow above, one
# eye offset left, a whip antenna off the back corner — is how a frame in this
# game is recognised at forty pixels, and it is the whole of what keeps a
# 1.75 m engineer looking issued by the same factory as a 3 m walker.
# ─────────────────────────────────────────────
func _head(torso: Node3D) -> void:
	var head := _node(torso, "Head", Vector3(0, 0.19 * HEAD_S + 0.40, -0.05))
	var body := _hull(head, "HeadBody",
			Vector3(1.18, 0.6, 1.3) * HEAD_S, Vector3.ZERO)
	_cut(body, "Cheek", Vector3(1.18 * 1.3, 0.7, 0.7) * HEAD_S,
			Vector3(0, -0.44, -0.86) * HEAD_S, Vector3(-35.0 * DEG, 0, 0))
	_cut(body, "Brow", Vector3(1.18 * 1.3, 0.7, 0.7) * HEAD_S,
			Vector3(0, 0.5, -0.78) * HEAD_S, Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, OFFSET LEFT, AND THE WALKER'S OWN MATERIAL. A StandardMaterial3D
	# with the white tile texture as albedo, not the shared metal: painting the
	# one feature that identifies a robot with the faction livery would make it
	# change colour per side, so it is deliberately left off the livery list.
	#
	# It is 0.071 across, which is small in absolute terms and exactly the
	# Walker's proportion — W_EYE_R is 14.4% of the turret's width on both
	# frames. Kept proportional rather than enlarged to "read", because the
	# thing that makes an eye read is being the only sphere on a box, not being
	# big. (The shipped soldier's eye is enormous relative to its body for the
	# opposite reason: it has no head to put one on.)
	var eye := _mesh(head, "Eye", _sphere_mesh(0.17 * HEAD_S, 0.82),
			Vector3(-0.34, 0.14, -0.66) * HEAD_S)
	eye.material_override = _eye_material()

	# The same whip the Walker and the Bulwark carry, off the back corner. On
	# the Kite, hanging this head UNDER a hull put the antenna inside the
	# fuselage; here the head stands on top of the torso, so the whip's base at
	# 0.587 in torso space is clear of the hull's 0.31 crown by a quarter metre
	# and nothing is inside anything.
	_mesh(head, "Antenna", _boxm(Vector3(0.03, 0.85, 0.03) * HEAD_S),
			Vector3(-0.5, 0.68, 0.48) * HEAD_S)

	# THE GUN PORT, MIRRORED TO STARBOARD. See correction 4: the kit draws this
	# at x -0.2 * scale and the eye at -0.34 * scale, and at 0.42 the two
	# intersect — as they also do on the Walker, which is where this geometry
	# comes from. Two overlapping lumps on a 0.50 m head read as one lump, so
	# the sign is flipped: eye to port, gun to starboard. Nothing else moves.
	var mantlet_at := Vector3(0.2, 0.02, -0.62) * HEAD_S
	_mesh(head, "Mantlet", _boxm(Vector3(0.5, 0.36, 0.26) * HEAD_S), mantlet_at)

	# THE MOUNT, LEVELLED, WHERE THE CAST BARREL WAS.
	#
	# GunCant exists only to undo the torso's 10-degree hunch. A rotation about
	# +X maps -Z to (0, sin, -cos), so a POSITIVE angle lifts the muzzle and a
	# negative one buries it in the floor — three of Picket's five first-round
	# concepts had this backwards. It is a separate node rather than part of
	# the mount's own euler because check_frame reads rotation.y straight off
	# the mount, and a basis carrying both a pitch and a yaw does not decompose
	# to a clean +90.
	var cant := _node(head, "GunCant", mantlet_at, Vector3(10.0 * DEG, 0, 0))
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the
	# mount has to turn that onto the body's -Z. Read off a matrix the yaw
	# looks like a quarter turn either way; it is not, and the Bulwark's first
	# build had it backwards — the gun fitted, elevated, tracked targets and
	# fired directly behind the frame, with nothing complaining, because a
	# mount pointing the wrong way is a perfectly valid transform.
	#
	# SCALE 0.4, WHICH IS THE INFANTRY NUMBER. soldier_chassis.tscn and
	# soldier_rifle.tscn both scale their mount 0.4 and the Mechanic 0.25; the
	# Walker's is 1.0. AI weapon scenes are authored at vehicle size, so an
	# unscaled mount on a 1.75 m frame fits a carbine as long as the robot.
	var wm := _node(cant, "WeaponMount", Vector3(0, 0, -0.075),
			Vector3(0, PI * 0.5, 0))
	wm.scale = Vector3(0.4, 0.4, 0.4)


# ─────────────────────────────────────────────
# THE ARMS — both hands on the T-handle. See correction 1 in the header for the
# measurement that forced the re-pose and the solve that produced ARM_*.
#
# Lengths, thickness and shoulder positions are the concept's untouched: a
# 0.26 upper arm and a 0.26 forearm off a shoulder at (+-0.30, 0.22, -0.04),
# thick 0.58. Only the three angles changed, and they changed so that the wrist
# lands on the handle's end instead of 0.37 m short of the shaft.
#
# `out` is the only one mirrored. On the right arm it is NEGATIVE, which brings
# the limb IN across the body — the opposite of the concept's +6, because the
# hands now meet near the centreline instead of hanging wide. The elbow ends up
# resting against the chest's front corner, which is where an elbow goes when
# something reaches forward with both arms, and is a solid union rather than a
# floating part.
#
# The kit's hand = "none" leaves a forearm ending in nothing. A fist closes it,
# and it is the piece the concept's two loose grip collars were standing in
# for: a sphere needs no orientation, so it cannot be mis-rolled around a bar
# whose axis arrives through three stacked rotations.
# ─────────────────────────────────────────────
func _arms(torso: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		var arm := _node(torso, "Arm%s" % tag, Vector3(s * 0.30, 0.22, -0.04),
				Vector3(ARM_FORE * DEG, 0, -s * ARM_OUT * DEG))
		_mesh(arm, "ShoulderCap%s" % tag, _sphere_mesh(0.26 * ARM_T), Vector3.ZERO)
		_mesh(arm, "UpperArm%s" % tag,
				_boxm(Vector3(0.36 * ARM_T, 0.26, 0.36 * ARM_T)), Vector3(0, -0.13, 0))
		var elbow := _node(arm, "Elbow%s" % tag, Vector3(0, -0.26, 0),
				Vector3(ARM_DROOP * DEG, 0, 0))
		_mesh(elbow, "ElbowCap%s" % tag, _sphere_mesh(0.19 * ARM_T), Vector3.ZERO)
		_mesh(elbow, "Forearm%s" % tag,
				_boxm(Vector3(0.3 * ARM_T, 0.26, 0.3 * ARM_T)), Vector3(0, -0.13, 0))
		var wrist := _node(elbow, "Wrist%s" % tag, Vector3(0, -0.26, 0))
		_mesh(wrist, "Hand%s" % tag, _sphere_mesh(0.075), Vector3(0, -0.02, 0))


# ─────────────────────────────────────────────
# THE BANDOLIER — four mines on edge across the small of the back.
#
# SAPPER.md section 1 settles both halves of this: where they live ("a
# bandolier of mine discs across the lower back") and what they look like
# ("flat discs with a ring, ~0.26 m — a shape new to the roster"). ON EDGE
# rather than stacked flat, which is the concept's own note, so the disc
# survives in profile where a stack would read as a cylinder.
#
# ON THE TORSO, so they ride the hunch — a load strapped to a leaning back
# leans with it, and the concept hangs them off the spine for the same reason.
# Seated into the hull: the hull's rear face is at z 0.19 and the discs run
# 0.12 to 0.40, so they are strapped on rather than hovering behind.
#
# EACH ONE IS ITS OWN NODE, named Mine0 through Mine3, with the disc and its
# ring inside. Nothing hides them today. The day something does — a frame that
# visibly spends its charges is the one piece of feedback this whole unit is
# missing — it should be a `get_node("Bandolier/Mine%d").visible = false` and
# not a modelling job.
# ─────────────────────────────────────────────
func _bandolier(torso: Node3D) -> void:
	var belt := _node(torso, "Bandolier", Vector3.ZERO)
	for i in 4:
		var mine := _node(belt, "Mine%d" % i,
				Vector3(-0.21 + float(i) * 0.14, -0.10, 0.26))
		# Laid on edge: a quarter turn about Z puts the disc's axis across the
		# frame, so the flat face shows from the side.
		_mesh(mine, "Disc", _cyl_mesh(0.11, 0.045, 14), Vector3.ZERO,
				Vector3(0, 0, PI * 0.5))
		_mesh(mine, "Ring", _torus_mesh(0.11, 0.14), Vector3.ZERO,
				Vector3(0, 0, PI * 0.5))


# ─────────────────────────────────────────────
# THE SATCHEL — one pouch, port hip, "to keep the back from being only mines".
#
# SEATED AGAINST THE FLANK, which the concept's is not. See correction 2: the
# concept's chamfered plate extrudes OUTBOARD from x -0.40 to -0.58 against a
# hull whose port face is at -0.26, so it floats with 0.14 m of daylight behind
# it — and that daylight is where 0.14 of the concept's quoted 1.04 m width
# comes from. Rebuilt as a 0.18-thick box from -0.44 to -0.26, which touches.
#
# Built in TORSO space rather than the concept's root space so it rides the
# hunch with the hull it is strapped to; the position is the concept's own
# (-0.40, 0.95, 0.14) brought through the lean and in to the flank.
#
# A chamfer off the top-front edge, because nothing in this kit is a plain box:
# a slab with square corners reads as a placeholder because it is one. Two
# studs on the outer face, which is what makes a pouch look bolted on rather
# than floating a centimetre off the hull. The studs hang off the TORSO and not
# off the satchel's CSG, so they stay their own meshes instead of becoming
# operands of a boolean that does not want them.
# ─────────────────────────────────────────────
func _satchel(torso: Node3D) -> void:
	var bag := _hull(torso, "Satchel", Vector3(0.18, 0.22, 0.26),
			Vector3(-0.35, -0.19, 0.11))
	_cut(bag, "Flap", Vector3(0.30, 0.08, 0.08), Vector3(0, 0.11, -0.13),
			Vector3(45.0 * DEG, 0, 0))
	for i in 2:
		_mesh(torso, "SatchelStud%s" % ("A" if i == 0 else "B"),
				_cyl_mesh(0.016, 0.022, 6),
				Vector3(-0.445, -0.14 - float(i) * 0.10, 0.11),
				Vector3(0, 0, PI * 0.5))


# ─────────────────────────────────────────────
# THE TOOL — the whole reason this frame is legible.
#
# "Both hands on a long T-handled tool driven into the ground in front of it...
# a two-handed pole angled into the deck is a pose nothing else in the roster
# holds." The stated risk is that at distance the shaft reads as a rifle or a
# spear, and the wide shoe and the cross handle are what stop that — both
# oversized for the job, deliberately.
#
# IN RIG SPACE, NOT ON A WRIST. It is planted in the ground: it must not
# inherit the torso's lean, and hanging a 1.12 m shaft off a joint that already
# carries three rotations is how this project has aimed things at the sky
# before. The arms are brought to it instead.
#
# Its own node so a future script can stow or swing it as one thing. The shaft
# runs from the shoe at (0, 0.02, -0.72) up and back to the handle at
# (0, 1.13, -0.46), which is the 13-degree cant the concept gives it.
# ─────────────────────────────────────────────
func _tool(rig: Node3D) -> void:
	var tool_node := _node(rig, "Tool", Vector3.ZERO)
	_mesh(tool_node, "Shaft", _cyl_mesh(0.035, 1.12, 10),
			Vector3(0, 0.575, -0.59), Vector3(13.0 * DEG, 0, 0))
	# The cross handle, across the frame. Its ends at +-0.17 are what the hands
	# are posed onto; see the note on _arms.
	_mesh(tool_node, "Handle", _cyl_mesh(0.028, 0.34, 8),
			Vector3(0, 1.10, -0.47), Vector3(0, 0, PI * 0.5))
	# THE SHOE, flat on the deck and wide enough to read as a thing for burying
	# something rather than as the end of a stick. The concept draws it as a
	# chamfered plate; rebuilt as a box with the chamfer cut off both long
	# edges, which is the idiom every shipped hull in this game uses and avoids
	# introducing the one CSG node type no robot scene has.
	var shoe := _hull(tool_node, "Shoe", Vector3(0.32, 0.06, 0.28),
			Vector3(0, 0.04, -0.72))
	for s in [-1.0, 1.0]:
		_cut(shoe, "Chamfer%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.08, 0.08, 0.40), Vector3(s * 0.16, 0.03, 0),
				Vector3(0, 0, 45.0 * DEG))
	# The spade edge ahead of it. Reaches z -0.97, which is the front of this
	# frame's bounding box and a quarter metre beyond its collider — a tool in
	# the ground is not allowed to be something squadmates path around.
	_mesh(tool_node, "SpadeEdge", _boxm(Vector3(0.32, 0.05, 0.18)),
			Vector3(0, 0.045, -0.88))
