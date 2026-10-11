extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/see_engine.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_see_engine.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. A robot scene is thirty
# sub-resources with hand-numbered ids and an exact load_steps count, which is
# why this exists at all; it is NOT a build step. Re-running it over a scene
# that has been touched in the editor throws that work away, which is how
# force-rebuilds have repeatedly cost this project its gameplay layers. If the
# geometry needs changing after today, CHANGE THE SCENE.
#
# ─────────────────────────────────────────────
# WHAT THIS IS
#
# SEE-ENGINE — Argus, supply 3, ground, command node, enemy only. The only
# frame in the game that IS Argus rather than merely belonging to it: the
# highest sensor range in the roster and ZERO weapon slots. It sees everything
# and shoots nothing, and everything near it shoots better for that reason.
#
# Concept A, THE OCULUS, from tools/concepts_c.gd -> ConceptsC.argus_a(). That
# function is the authority on silhouette and position; every number below is
# transcribed from it, not re-invented. One 2.3 m lens in a two-hoop gimbal on
# a too-slender column, four thin overlong legs, and the pupil off-centre and
# low.
#
# NO SINGLE OFFSET EYE AND NO FACE. The Walker's one offset eye plus chamfered
# turret is Home Command's grammar and the player's own factory; Argus has to be
# recognisable at icon size as not from the same production line. So
# concept_kit.gd's head() is deliberately NOT used — nor is its equivalent
# rebuilt here — and NOTHING ON THIS FRAME IS NAMED "Eye". The one enormous
# lens is the sensor; the off-centre low pupil is the detail that makes it
# uncomfortable to look at, and it stays off-centre.
#
# ─────────────────────────────────────────────
# THE FOUR-LEG / TWO-LEG DECISION — READ THIS BEFORE EDITING THE LEGS
#
# walker.gd drives exactly two legs: hip_left/knee_left/foot_left and
# hip_right/knee_right/foot_right. The Oculus has FOUR, and the four thin
# overlong legs are a large part of why this concept won, so all four are here.
#
#   WIRED (animated):  LegFR, bearing 130 deg -> HipR/KneeR/FootR
#                      LegFL, bearing 220 deg -> HipL/KneeL/FootL
#   STATIC (never move): LegRR, bearing  40 deg
#                        LegRL, bearing 310 deg
#
# The front pair is wired because it is the pair facing an approaching player,
# and because 130/220 is the closest thing to a mirrored pair the concept's
# bearings offer (a true mirror of 130 would be 230; it is 10 degrees out).
# THE REAR TWO DO NOT MOVE AT ALL. walker.gd was not edited to add legs and
# must not be — see docs/briefs/FRAME_MODELS.md section 1.
#
# HIPS AND KNEES REST AT ZERO ROTATION, WHICH IS WHY THE LEG IS BUILT THE WAY
# IT IS. _pose_leg() ASSIGNS hip.rotation.x, hip.rotation.z and knee.rotation.x
# outright rather than adding to them, so any outward kick baked into a hip's
# own rotation is erased on the first physics frame — and only on the two wired
# legs, which would leave this frame standing with two legs splayed and two
# plumb. The concept's 30 degrees of outward reach therefore lives in the
# THIGH AND SHIN MESH transforms and in the child node POSITIONS, which nothing
# animates. All four legs are built identically by _leg() for that reason.
#
# ─────────────────────────────────────────────
# THE TURRET DECISION
#
# weapon_slots = 0 and turret = false on the chassis: it genuinely never fires.
# walker.gd declares `turret` and `gun_pivot` regardless. Rather than a dead
# stub, THE GIMBAL IS THE TURRET, because a gimbal is precisely a thing that
# looks around and this frame's whole character is looking:
#
#   GimbalYaw  = turret      traverses the lens in yaw, at 24 deg/s
#   LensPitch  = gun_pivot   the pitch axis between the two trunnions
#
# That is a real traverse, not a stub satisfying an export, and it costs
# nothing: walker.gd yaws `turret` toward whatever the body wants to face, so a
# See-Engine visibly turns its eye onto what it has noticed. gun_pivot only
# pitches in COMBAT with a weapon_target, which a frame with no weapon will
# rarely have — harmless either way.
#
# WeaponMount IS a stub, and is documented as one: there are no weapon slots,
# so nothing will ever be fitted. It exists because enemy.gd declares
# `weapon_mount` and a null one is a silent null. It is at yaw +PI/2, NOT
# -PI/2 — a weapon's muzzle runs down its own +X and the mount has to turn that
# onto the body's -Z. Built the other way a gun points backwards and nothing
# complains. It sits on the pupil's bearing, so if a later pass ever does mount
# something it points where the eye is looking.
#
# ─────────────────────────────────────────────
# WHAT THIS DELIBERATELY DOES NOT DO
#
# NO FACTION IS SET. `faction` is left at Enums.Factions.ENEMY. ARGUS does not
# exist in Managers/enums.gd and must not be added here: are_hostile() has no
# default arm, so a robot carrying an unknown faction value is simultaneously
# invisible and near-invulnerable across thirty-five call sites, not one of
# which errors. See docs/frames/ENEMY_FACTIONS.md — that work is task zero and
# belongs to the coordinator.
#
# No chassis .tres, no catalogue entry, no enum change, no edit to walker.gd or
# enemy.gd. A frame whose model exists and whose stats do not is a known,
# deliberate, half-finished state.
#
# TWO LOAD ERRORS ARE EXPECTED from the scene this writes:
#   ERROR: Cannot assign contents of "Array[Object]" to "Array[int]".
# printed twice. Enemy declares AllowedMovementOptions/AllowedCombatOptions as
# Array[int] and the .tscn writer types them against the element script of the
# equipment_slots array above them. Both are empty defaults, nothing is lost,
# and bulwark.tscn has the identical pair. Do not chase it and do not work
# around it.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/see_engine.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
const BODY_SCRIPT := "res://Character/characters/ai/walker.gd"
## NOT the 17/19/23 set every Home Command frame in the game shares. Argus is a
## different production line and should not answer in the same voice.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__61.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__74.wav"

const DEG := PI / 180.0
## The optic texture — the same object on screen as every other lens in the
## game, on its own StandardMaterial3D rather than the shared faction metal.
## This frame has no node named "Eye": the big lens's PUPIL and the two small
## column pods carry it instead, and all three are kept off the livery list for
## the same reason the Walker's eye is — the feature that says "sensor" must
## not change colour per faction.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

# ── THE RIG SITS BELOW THE BODY ORIGIN ──
#
# Every position below is in CONCEPT SPACE, exactly as ConceptsC.argus_a()
# writes it: foot pads at y ~0, column 0.05..2.05, lens centre at y 3.0. That
# is deliberate — it makes this file diffable against the concept function,
# which is the authority.
#
# A CharacterBody3D's collision capsule is centred on the body origin, so the
# origin rides at capsule-half-height above the floor and the ART has to be
# built around it, not around the ground. Both shipping frames do this: the
# Walker's capsule is 3.0 tall centred at zero, with its feet at -1.675 — a
# touch below the capsule's own bottom, so the soles are very slightly
# embedded rather than hovering.
#
# So the whole rig is dropped by this much instead, and `Rig.position.y` is
# where walker.gd reads `_rig_rest_y` from for the gait bob, so a non-zero
# value here is expected and supported.
#
#   capsule   r 0.95, h 4.40, centred -> spans y -2.20 .. +2.20
#   rig drop  2.26  -> foot pads at -2.305 (0.105 below the capsule bottom)
#                   -> top of the yoke at +2.20, level with the capsule top
const RIG_DROP := 2.26

# ── THE CAPSULE IS BULWARK-WIDE ON PURPOSE ──
#
# 0.95 is the widest collider on any legged frame in the game, so a See-Engine
# gets through everything a Bulwark gets through. The lens is 1.15 in radius
# and therefore OVERHANGS the capsule by 0.20 m on each side: a round grazing
# the extreme edge of the lens passes through it. Widening the capsule to the
# lens instead would put a 2.3 m collider on a navmesh baked for smaller
# agents, and Godot enforces no per-agent path clearance — the bake is the only
# clearance there is. A hard navigation failure is worse than a 20 cm ghost
# edge, so the capsule stays narrow. If the lens must be hittable to its rim,
# that wants an AnimatableBody3D on the gimbal the way the Bulwark's shield has
# one, and it is a gameplay call rather than a modelling one.
const CAP_RADIUS := 0.95
const CAP_HEIGHT := 4.40

var _metal: Material
var _root: CharacterBody3D


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_see_engine: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_see_engine: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_see_engine: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A mesh piece. EVERYTHING VISIBLE GOES THROUGH HERE so nothing can be left
## without the shared metal material — a single unpainted piece is invisible as
## a bug until someone renders the frame in a faction colour. The two optics
## override the material afterwards, and only those two.
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


## A sphere at the concept's own tessellation — 14 x 7, which is what
## mockup_parts.sphere() builds, so the lens reads at the same faceting the
## concept sheet was judged at.
func _spherem(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


## A hoop. mockup_parts.ring() takes inner/outer radii and builds a CSGTorus3D
## at 16 sides and 6 ring sides; this is the MeshInstance3D equivalent at the
## same counts, because a standalone CSG primitive per hoop would be six
## boolean builds this frame does not need — see csg_bake.gd for the 335 ms
## that made that lesson compulsory.
func _torusm(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	return t


func _cylm(r: float, h: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	return c


## A CSG box used as a CUT.
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


## The one CSG hull on the frame, baked at boot by csg_bake.gd. NOTHING BUT
## CUTS MAY BE PARENTED TO IT: csg_bake swaps the node out for a plain
## MeshInstance3D holding its baked mesh, and anything hanging off it goes with
## it. Every other part of this frame is a child of Rig for that reason.
func _hull(parent: Node, nm: String, mesh: Mesh, at: Vector3) -> CSGMesh3D:
	var h := CSGMesh3D.new()
	h.name = nm
	h.mesh = mesh
	h.position = at
	h.material = _metal
	parent.add_child(h)
	h.owner = _root
	return h


## The optic's own material. Built fresh per call rather than shared, because a
## material handed to two instances is one object — see the duplicate() rule in
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
	root_body.name = "SeeEngine"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, which means "for this run only" — a
	# frame built without it packs with no groups line, and a robot outside
	# "enemies" is invisible to AIManager, to EMP and to every hostile sweep in
	# the game while still walking around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision and senses ──
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_RADIUS
	cap.height = CAP_HEIGHT
	col.shape = cap
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, OR THE ASSIGNMENT IS SILENTLY DROPPED. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three default clips. That line was untyped in
	# build_bulwark.gd for the Bulwark's whole life and bulwark.tscn shipped
	# with the defaults instead of the two clips its generator names. Nobody
	# noticed, because it still barks. Read it as the shape of the whole trap:
	# it is about every typed export on every node you touch, including ones on
	# components you merely instantiate.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# Lower and slower than anything else in the roster. The Bulwark is
	# 0.64-0.72, the Walker 0.72-0.80.
	bark.set("pitch_min", 0.46)
	bark.set("pitch_max", 0.54)
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
	# 25, the same as the Walker and the Bulwark. This area is the "notice
	# company" trigger, not the sensor: the 110 m sensor_range below is what
	# carries the design, and a 110 m Area3D on a command node would wake every
	# hostile on the map and take the distance cull with it.
	dsphere.radius = 25.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body

	# ── the rig ──
	# Concept space from here down. See RIG_DROP.
	var rig := _node(root_body, "Rig", Vector3(0, -RIG_DROP, 0))

	# ── THE COLUMN — this frame's Hull ──
	#
	# A plain unchamfered cylinder, 0.6 m across carrying a 2.3 m lens. TOO
	# SLENDER FOR THE MASS ON TOP OF IT, which is the point: it should not look
	# like it carries its own weight, and it is explicitly not the player's
	# chamfered box-and-bevel vocabulary. Three flutes cut down it so it reads
	# as machined rather than as a dowel; that is the only geometry on this
	# frame that is not transcribed from the concept.
	var column := _hull(rig, "Hull", _cylm(0.3, 2.0, 10), Vector3(0, 1.05, 0))
	for i in 3:
		var a: float = (50.0 + 120.0 * float(i)) * DEG
		_cut(column, "Flute%d" % i, Vector3(0.1, 1.5, 0.1),
				Vector3(sin(a) * 0.3, 0.0, cos(a) * 0.3), Vector3(0, a, 0))
	_mesh(rig, "Collar", _torusm(0.3, 0.46), Vector3(0, 1.9, 0))

	# ── TWO SMALL PODS ON THE COLUMN, LOOKING BACKWARD AND DOWN ──
	#
	# From the concept, at its own units. One enormous eye is the proposal;
	# these are what say what the eye is FOR. They are low, behind, and aimed
	# at the ground its own units are standing on — nowhere near each other and
	# nowhere near symmetric, so they cannot resolve into a pair of eyes and
	# therefore cannot read as a face.
	#
	# THE ONLY POSITIONS ON THIS FRAME THAT ARE NOT THE CONCEPT'S, AND WHY.
	# argus_a() mounts these at (-0.42, 1.5, 0.3) and (0.38, 1.16, 0.34) —
	# bearings 305.5 and 48.2 degrees, which are 4.5 and 8.2 degrees off the
	# legs at 310 and 40. Measured against the built leg: pod A's 0.20 m lens
	# centre lands 0.08 m from the rear-left thigh's axis, inside a limb whose
	# cross-section is 0.234 x 0.275, so more than half the lens is swallowed.
	# Pod B is the same against the rear-right thigh. On a concept sheet that
	# is a smudge; on a model it is six wasted faces and a sensor you cannot
	# see, and a detail that vanishes into a limb is the exact failure the
	# brief warns about.
	#
	# So the two mounts are ROTATED ABOUT THE COLUMN into the gaps between the
	# legs — 355 and 85 degrees, the mid-points of the two rear quadrants —
	# and their yaws are re-aimed so each still looks outward, BACKWARD and
	# DOWN as the concept has them. Height, radius, pitch, size and the fact
	# that no two of them match are all unchanged, and the nearest limb is now
	# 0.39 m away against a 0.29 m combined half-width. They are also pulled in
	# to a 0.44/0.42 mounting radius so the barrel BITES the 0.30 column
	# instead of floating 6 cm off it.
	#
	#   A  bearing 355, mount r 0.44, looks to bearing 350, pitch -24, r 0.20
	#   B  bearing  85, mount r 0.42, looks to bearing  80, pitch -38, r 0.17
	var pod_a := _sensor_pod(rig, "A", Vector3(-0.038, 1.5, 0.438), 0.2, 160.0, -24.0)
	var pod_b := _sensor_pod(rig, "B", Vector3(0.418, 1.16, 0.037), 0.17, 245.0, -38.0)

	# ── FOUR LEGS ──
	var leg_fr := _leg(rig, "FR", "R", 130.0)
	var leg_fl := _leg(rig, "FL", "L", 220.0)
	_leg(rig, "RR", "RR", 40.0)
	_leg(rig, "RL", "RL", 310.0)

	# ── THE GIMBAL ──
	var gimbal := _gimbal(rig)
	var pitch := gimbal.get_node("LensPitch") as Node3D

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
	# EVERY PAINTED PIECE, LISTED, IN A TYPED ARRAY. `pieces` is Array[Node3D];
	# an untyped one lands as [] and FactionLivery then falls back to walking
	# its whole parent — which paints every mesh on the frame, THE OPTICS
	# INCLUDED. That is exactly how the Bulwark's eye ended up
	# faction-coloured despite being left off a list that was never there.
	#
	# THE THREE OPTICS ARE DELIBERATELY ABSENT: Pupil, PodLensA, PodLensB.
	# They keep their own StandardMaterial3D, because the feature that reads as
	# "this is a sensor" must not change colour per faction. Their BEZELS are
	# painted, which is what makes the lens itself pop out of the hull.
	var paint: Array[Node3D] = []
	paint.append(column)
	paint.append(rig.get_node("Collar"))
	for p in [pod_a, pod_b]:
		paint.append(p.get_node("Barrel"))
		paint.append(p.get_node("Bezel"))
	for tag in ["FR", "FL", "RR", "RL"]:
		var hub := rig.get_node("Leg%s" % tag) as Node3D
		for path in ["HipCap", "Thigh", "Knee/KneeRing", "Knee/Shin", "Knee/Foot/Pad"]:
			paint.append(hub.get_child(0).get_node(path))
	paint.append(gimbal.get_node("Yoke"))
	paint.append(gimbal.get_node("TrunnionL"))
	paint.append(gimbal.get_node("TrunnionR"))
	paint.append(pitch.get_node("Lens"))
	paint.append(pitch.get_node("Equator"))
	paint.append(pitch.get_node("PupilBezel"))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D or Array[Node3D] — not NodePath — so assigning a NodePath to them
	# silently does nothing and the frame comes out with a null turret and legs
	# the gait cannot find. PackedScene.pack() turns these references back into
	# the node_paths=PackedStringArray(...) form the editor writes, so the
	# saved scene looks hand-authored either way.
	root_body.set("rig", rig)
	# THE WIRED PAIR IS THE FRONT PAIR. The rear two are not referenced here by
	# anything and therefore never move. See the header.
	root_body.set("hip_left", leg_fl.get_node("HipL"))
	root_body.set("knee_left", leg_fl.get_node("HipL/Knee"))
	root_body.set("foot_left", leg_fl.get_node("HipL/Knee/Foot"))
	root_body.set("hip_right", leg_fr.get_node("HipR"))
	root_body.set("knee_right", leg_fr.get_node("HipR/Knee"))
	root_body.set("foot_right", leg_fr.get_node("HipR/Knee/Foot"))
	# The gimbal IS the turret, and the lens cradle IS the gun pivot. Neither
	# is a stub. See the header.
	root_body.set("turret", gimbal)
	root_body.set("gun_pivot", pitch)
	root_body.set("weapon_mount", pitch.get_node("WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY. particle_effects_die is
	# Array[ParticleEffect] and visible_pieces is Array[Node3D]; assigning a
	# plain untyped Array to either fails SILENTLY and the packed scene comes
	# out with `visible_pieces = []`. The Bulwark's first build shipped all
	# four empty: no death effects, no hit sparks, and a frame that painted
	# every mesh on itself.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# The two pieces that ARE the silhouette: the column and the lens.
	var vis: Array[Node3D] = []
	vis.append(column)
	vis.append(pitch.get_node("Lens"))
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)

	# ── stats that live on the scene ──
	#
	# The rest of section 3 of docs/frames/SEE_ENGINE.md is ChassisDefinition
	# and is out of scope for this pass: supply, cost, purchasable,
	# weapon_slots = 0, turret = false, vehicle, the slot counts. No chassis
	# .tres is written here.
	root_body.set("activation_distance", 200)
	root_body.set("health", 240)
	root_body.set("max_health", 240)
	# Ponderous. The Walker is 4.16 and the Bulwark 3.3; this barely fights and
	# should look like it is being escorted rather than leading.
	root_body.set("move_speed", 2.2)
	root_body.set("soldier_name", "See-Engine")
	# A 4.5 m frame does not fold flat.
	root_body.set("flatten_collider_when_downed", false)
	# THE HIGHEST SENSOR IN THE GAME — the Spotter is 90. This is a plain
	# export on Enemy, so the scene is correct on its own; once a chassis
	# exists, enemy_force_spawner.gd:531 overwrites it from base_sensor_range
	# with the same 110.
	root_body.set("sensor_range", 110.0)
	# Hardened, not immune. Lives on the scene rather than on
	# ChassisDefinition because that resource has no signal field — see
	# AI.signal_resistance. Divides incoming suppression AND the length of an
	# EMP lock.
	root_body.set("signal_resistance", 1.4)
	# A sweep, not a snap. Slower than the Walker's 55 and the Bulwark's 42:
	# the eye should look like it is deciding to look at you.
	root_body.set("turret_traverse_degrees", 24.0)
	root_body.set("gun_elevation_degrees", 18.0)
	# Wider than the default -12/35 in the downward direction, because a
	# command node watching infantry is usually looking DOWN. A rotation about
	# +X maps -Z to (0, sin, -cos), so the NEGATIVE limit is the one that aims
	# at the floor.
	root_body.set("gun_min_pitch_degrees", -30.0)
	root_body.set("gun_max_pitch_degrees", 22.0)
	# ── gait, tuned down because only two of the four legs move ──
	# Short, shallow and slow. A full 26-degree stride with two legs rigid
	# would advertise the mismatch; at this amplitude the frame reads as
	# picking its way forward. This is the number to reach for first if the
	# four-on-two gait looks wrong in motion.
	root_body.set("stride_length", 1.8)
	root_body.set("hip_swing_degrees", 13.0)
	root_body.set("knee_bend_degrees", 12.0)
	root_body.set("side_swing_degrees", 7.0)
	root_body.set("body_bob", 0.04)
	return root_body


# ─────────────────────────────────────────────
# PARTS
# ─────────────────────────────────────────────

## One small sensor pod: a stub barrel, a lens and a bezel, aimed by the pod
## node's own yaw and pitch. The proportions are concepts_c.gd's _eye_pod() at
## the same multiples of `r`, so the two column pods are the same object the
## concept sheet was judged on.
##
## Rotation is (pitch, yaw, 0) and Node3D's default order is YXZ, so the yaw
## applies first and the pitch is then about the already-yawed X axis. That is
## what makes the pod point along a bearing and then tip down it, rather than
## tipping in the rig's frame and swinging the tip sideways.
func _sensor_pod(rig: Node3D, tag: String, at: Vector3, r: float,
		yaw_deg: float, pitch_deg: float) -> Node3D:
	var pod := _node(rig, "SensorPod%s" % tag, at,
			Vector3(pitch_deg * DEG, yaw_deg * DEG, 0))
	_mesh(pod, "Barrel", _cylm(r * 0.8, r * 1.2, 10), Vector3(0, 0, -r * 0.45),
			Vector3(PI * 0.5, 0, 0))
	var lens := _mesh(pod, "Lens", _spherem(r), Vector3(0, 0, -r * 1.05))
	lens.material_override = _eye_material()
	_mesh(pod, "Bezel", _torusm(r * 0.98, r * 1.28), Vector3(0, 0, -r * 0.95),
			Vector3(PI * 0.5, 0, 0))
	return pod


## ONE LEG, ON A BEARING.
##
## The hub is a yaw-only node at the rig's origin and the hip hangs inside it,
## so "outward" is the hub's own +Z and the leg's kick stays in its own radial
## plane. Splaying a leg in the ROOT's frame instead kicks legs spaced round a
## circle tangentially rather than outward, which is the note
## concepts_c.gd:_radial_leg() carries and the reason it exists.
##
## The concept builds this as a single node rotated -30 degrees about X with a
## plumb thigh and shin inside it. THAT CANNOT BE DONE HERE: walker.gd assigns
## hip.rotation.x / .z and knee.rotation.x outright, so a hip holding the kick
## in its own rotation loses it on the first physics frame — and only on the
## two legs that are wired, leaving a frame with two legs splayed and two
## plumb. So the kick is pre-applied: the child node POSITIONS are the rotated
## ones and the thigh and shin MESHES carry the -30 degrees themselves. The
## geometry is identical, hips and knees rest at zero, and all four legs are
## built the same way whether they are animated or not.
##
## Pillar legs, no knee break: thin, overlong and load-bearing-looking rather
## than quick, which is what makes this frame read as assembled for seeing.
func _leg(rig: Node3D, hub_tag: String, tag: String, yaw_deg: float) -> Node3D:
	const REACH := -30.0 * DEG
	const HIP_Y := 1.8
	const HIP_R := 0.4
	const THIGH := 1.0
	const SHIN := 1.0
	# thick 0.55, from the concept. Every cross-section below is that times
	# concept_kit's Walker-derived limb sizes, so these legs are a little over
	# half the thickness of the Walker's own.
	const THICK := 0.55
	var dy := cos(REACH)
	var dz := -sin(REACH)   # REACH is negative, so this is +0.5: outward

	var hub := _node(rig, "Leg%s" % hub_tag, Vector3.ZERO, Vector3(0, yaw_deg * DEG, 0))
	var hip := _node(hub, "Hip%s" % tag, Vector3(0, HIP_Y, HIP_R))
	_mesh(hip, "HipCap", _spherem(0.19 * THICK), Vector3.ZERO)
	_mesh(hip, "Thigh", _boxm(Vector3(0.34 * 1.25 * THICK, THIGH, 0.4 * 1.25 * THICK)),
			Vector3(0, -THIGH * 0.5 * dy, THIGH * 0.5 * dz), Vector3(REACH, 0, 0))
	var knee := _node(hip, "Knee", Vector3(0, -THIGH * dy, THIGH * dz))
	_mesh(knee, "KneeRing", _torusm(0.05 * THICK, 0.2 * THICK), Vector3.ZERO)
	_mesh(knee, "Shin", _boxm(Vector3(0.26 * 1.3 * THICK, SHIN, 0.3 * 1.3 * THICK)),
			Vector3(0, -SHIN * 0.5 * dy, SHIN * 0.5 * dz), Vector3(REACH, 0, 0))
	# The pad is under a Foot NODE rather than being the foot itself, because
	# walker.gd counter-rotates `foot` to keep the sole flat through the
	# stride. A disc, not a plate: four of these and the stance is a tripod
	# that cannot decide.
	var foot := _node(knee, "Foot", Vector3(0, -(SHIN + 0.05) * dy, (SHIN + 0.05) * dz))
	_mesh(foot, "Pad", _cylm(0.26 * THICK, 0.14, 12), Vector3.ZERO)
	return hub


## THE GIMBAL — one 2.3 m lens in two hoops, and the whole reason this concept
## won. It reads as a single watching intelligence because it is ONE SHAPE: a
## sphere with two rings round it, which survives being drawn at forty pixels
## in a way that a chandelier of small eyes does not.
##
## The two hoops are in perpendicular planes, which is what a gimbal is:
##
##   Yoke      stood upright in the XY plane, carrying the trunnions at its
##             left and right extremes. It yaws with GimbalYaw.
##   Equator   a great circle round the lens, CANTED 30 degrees about the
##             trunnion axis so it clears the pupil (see below — it used to cut
##             straight through it). It PITCHES with the lens, which is what
##             sells the trunnions as a real axis — a hoop that stayed level
##             while the lens tipped inside it would read as a hula hoop.
##
## THE TRUNNIONS BELONG TO THE YAW NODE, NOT THE PITCH NODE. They are the pins
## the lens turns on; bolted to the lens they would swing with it and the
## bearing would have nothing to bear against.
func _gimbal(rig: Node3D) -> Node3D:
	var gimbal := _node(rig, "GimbalYaw", Vector3(0, 3.0, 0))
	_mesh(gimbal, "Yoke", _torusm(1.22, 1.46), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	for s in [-1.0, 1.0]:
		_mesh(gimbal, "Trunnion%s" % ("L" if s < 0.0 else "R"), _cylm(0.16, 0.5, 8),
				Vector3(s * 1.3, 0, 0), Vector3(0, 0, PI * 0.5))

	var pitch := _node(gimbal, "LensPitch", Vector3.ZERO)
	_mesh(pitch, "Lens", _spherem(1.15), Vector3.ZERO)
	# ── THE EQUATOR IS CANTED, AND THE CANT IS THE PUPIL'S ──
	#
	# The hoop below the comment said the hoops "pass well outboard" of the
	# pupil. THEY DID NOT. Measured on the built scene, the Equator's centreline
	# circle (radius 1.30, tube radius 0.12) ran 0.224 m THROUGH the pupil
	# sphere and 0.142 m through its bezel: the pupil is 0.44 in radius and
	# stands 0.307 m proud of a 1.15 lens, so at y 0 it is squarely in the
	# hoop's band. The human's note was "the ring can't cut into the eye
	# itself". Only the Equator was at fault — the Yoke clears the pupil by
	# 0.890 m and is untouched.
	#
	# THE FIX IS THE HOOP'S PLANE, WHICH IS THE ONLY FREE ONE. The hoop is
	# concentric with the lens, so ANY plane through the lens centre keeps every
	# point of it at the same 1.30 from the centre and therefore hugging the
	# lens exactly as closely as before — it costs nothing and the measured box
	# does not move. The alternatives all do cost: lifting the hoop to y 0.363
	# clears the pupil but leaves it floating 0.09 m off a surface it is
	# supposed to be strapped to, and widening its inner radius to 1.443 both
	# detaches it and grows the frame by a quarter of a metre a side.
	#
	# 30 DEGREES, ABOUT X, POSITIVE. Positive X raises the FRONT of the hoop
	# (y = -z tan t, and the pupil is at -Z), so the belt arcs up and over the
	# pupil instead of across it. About X specifically because the X axis lies
	# IN the hoop's plane at any tilt, so the hoop still passes through
	# (±1.30, 0, 0) — exactly where the trunnions are — and the pins still have
	# a ring to bear against. 25 degrees is the minimum that clears the bezel
	# (by 0.003 m); 30 leaves 0.243 m on the pupil and 0.069 m on the bezel.
	#
	# THE PUPIL DID NOT MOVE AND MUST NOT. Off-centre and low is the detail the
	# concept was chosen for; centring it would "fix" this by throwing the frame
	# away.
	_mesh(pitch, "Equator", _torusm(1.18, 1.42), Vector3.ZERO,
			Vector3(30.0 * DEG, 0, 0))

	# ── THE PUPIL, OFF-CENTRE AND LOW ──
	#
	# A CENTRED PUPIL IS A FACE. This one is looking somewhere you are not,
	# which is the whole character of the faction and the detail that makes the
	# frame uncomfortable to look at. KEEP IT OFF-CENTRE. Nothing is allowed to
	# cross it, and MEASURE THAT RATHER THAN ASSERTING IT — the line that used
	# to stand here said the hoops passed well outboard, and the Equator was in
	# fact 0.224 m inside this sphere. It is canted now; the Yoke clears by
	# 0.890 m; the column stops a metre below.
	#
	# NOTE THE NAME. There is no node called "Eye" anywhere on this frame, on
	# purpose — the Walker's single offset eye is Home Command's grammar and the
	# player's own factory, and Argus must read at icon size as not from the
	# same production line. check_frame.gd's eye-exclusion assertion therefore
	# has nothing to find here; the exclusion is still enforced by this piece
	# being absent from the livery list.
	#
	# Concept y 2.84 against a lens centre of 3.0, so -0.16 in this frame.
	var pupil := _mesh(pitch, "Pupil", _spherem(0.44), Vector3(0.22, -0.16, -0.98))
	pupil.material_override = _eye_material()
	_mesh(pitch, "PupilBezel", _torusm(0.46, 0.62), Vector3(0.22, -0.16, -1.0),
			Vector3(PI * 0.5, 0, 0))

	# A STUB MOUNT. weapon_slots = 0 and nothing will ever be fitted; this
	# exists because enemy.gd declares `weapon_mount` and the brief's rule is a
	# stub that is wired and documented rather than a null nobody notices.
	# +PI/2, not -PI/2 — a muzzle runs down its own +X and the mount turns that
	# onto the body's -Z. On the pupil's bearing, just clear of the lens, so if
	# this frame is ever given a gun it points where the eye is looking.
	var wm := _node(pitch, "WeaponMount", Vector3(0.22, -0.16, -1.52),
			Vector3(0, PI * 0.5, 0))
	wm.name = "WeaponMount"
	return gimbal
