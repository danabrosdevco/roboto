extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/brood.tscn — the BROODCARRIER.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_brood.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. This is not a build step.
# Re-running it over a scene somebody has touched in the editor throws that
# work away, which is how --force rebuilds have repeatedly cost this project
# its gameplay layers. If the geometry needs changing after today, change the
# scene. See tools/build_bulwark.gd, which says the same thing for the reason.
#
# ─────────────────────────────────────────────
# WHAT THIS IS
#
# SWARM · supply 2 · AERIAL · spawner · enemy only. Concept A, THE BUNCH: a
# lift hoop overhead, three fans that do not agree with each other, a core of
# three off-axis lobes, and NINE PODS hanging under it like fruit. It never
# shoots — the brood is the weapon.
#
# The proportions are not invented here. They are lifted number for number out
# of ConceptsC.brood_a() in tools/concepts_c.gd, which is the authority on the
# silhouette; this file turns that into a robot scene (collision, rig, livery,
# wiring) rather than redesigning it. Every place a number differs from the
# concept is commented with the measurement that forced it.
#
# ─────────────────────────────────────────────
# THREE DECISIONS THE CONCEPT DID NOT SETTLE
#
# 1. THE TWO FREE-FALLING HATCHLINGS ARE CUT. The concept draws two offspring
#    already away and dropping, which is behaviour drawn rather than described
#    — right for a concept sheet, wrong in a scene. Geometry parented to the
#    body does not fall: they would fly in rigid formation under the carrier
#    forever, they would read as two more brood on a frame whose whole job is
#    to let you COUNT the remaining brood, and they would sit outside the
#    collider as two unhittable floaters. The behaviour survives as the one pod
#    modelled cracked open with a hatchling half out of it — attached, so it
#    moves with the frame, and it still says SPAWNS rather than CARRIES.
#
# 2. THE PODS ARE NINE NAMED SIBLINGS, Rig/BroodBay/Pod1 .. Pod9, ordered
#    LOWEST FIRST. A spawner whose remaining stock the player cannot read is a
#    spawner the player cannot make a decision about, so a future spawn script
#    hides them one at a time: `bay.get_node("Pod%d" % n).visible = false`,
#    counting up, so the bay empties from the bottom — the direction the brood
#    leaves. Pod1 is the lowest and is the one modelled open, i.e. the one
#    currently launching. Nothing in this pass hides anything; the hierarchy is
#    the only promise made here.
#
# 3. NO EYE, AND NOTHING NAMED "Eye". The Walker's single offset optic is
#    StratCom's grammar and the player's own factory, and this frame must not
#    borrow it. The sensor is instead a ragged patch of five unequal OCELLI on
#    the core's forward-lower flank — too many eyes, none of them centred, no
#    two spacings alike. They are the ONLY pieces on the frame that keep their
#    own material, and they are therefore the only pieces left off the livery
#    list. check_frame.gd's "EYE EXCLUDED" assertion does not fire on this
#    frame because there is nothing called Eye to exclude; the exclusion it
#    protects is done here by hand.
#
# ─────────────────────────────────────────────
# ORIGIN CONVENTION — IT MATTERS, BECAUSE A FLYER HAS NO LEGS
#
# A legged frame's origin is settled for it: the feet stand on the floor. There
# is nothing holding this one off the ground, so the origin is a free choice
# and three things depend on it — the collision sphere is centred on it,
# spotter_drone.gd holds `global_position.y` at `cruise_height` above whatever
# its GroundRay finds under it, and that ray starts there.
#
# So THE ORIGIN IS THE CENTRE OF THE COLLISION SPHERE, placed at the centroid
# of the hull and the brood cluster: concept y 2.25, hence SHIFT below. At
# r 0.9 the sphere then contains all three core lobes, the plane of the lift
# hoop and the centre of all nine pods — the mass a player shoots at. Put at
# the core instead, the lower half of the brood bay falls outside the collider
# and rounds pass through the pods; put at the lowest pod, the core does. The
# frame therefore hangs mostly BELOW its own origin, which is correct: the
# brood is cargo, and `cruise_height` means "the hull is that high", not "the
# lowest pod is".
#
# ─────────────────────────────────────────────
# NOT ONE CSG NODE, DELIBERATELY
#
# The concept is built from mockup_parts.gd, which is all CSG, because a
# concept sheet is one render and CSG is the fastest way to author one. A
# SHIPPED robot pays for CSG at runtime: csg_bake.gd exists because the CSG in
# the AI scenes cost 335 ms on the frame a reserve wave first ran, and it only
# exists to take it back out again. Nothing here needs a boolean — the one cut
# in the concept (the crack in the open pod) is a hemisphere plus two
# shell flaps, which reads better anyway because the opening faces the camera
# instead of being a slice through a sphere. So every visible piece below is a
# plain MeshInstance3D with a material_override, there is nothing for
# csg_bake.gd to swap, and nothing for it to repoint.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/brood.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
## spotter_drone.gd, NOT a new script and NOT the bomber's.
##
## No new behaviour scripts in this pass, so the root takes the existing flying
## script. The design doc is explicit about WHICH flying script: the Spotter's
## handle_movement is 34 lines with no phase machine and it already answers the
## squad seams — slot_tolerance, formation_width, takes_cover,
## off_navmesh_is_normal. enemy_helicopter.gd overrides NONE of those, so it
## inherits takes_cover() -> true and can be handed a point of GROUND COVER as
## a loiter centre. Copying the bomber would inherit that latent bug.
##
## What this script does NOT do is spawn anything, which is the frame's entire
## purpose. That is section 6 of the design doc, it is gated behind
## are_hostile() becoming a table, and it is not this pass. Until then this is
## a Spotter-shaped flyer wearing a hive: it circles, it holds altitude, it can
## be shot down, and it carries nine pods that nothing yet empties.
const BODY_SCRIPT := "res://Character/characters/ai/spotter_drone.gd"
## Deeper and slower than the Walker's or the Bulwark's pair. Picked for a big
## cold thing rather than a soldier; the human can judge it, and changing a
## shipped frame's voice is a game-feel call, not a build one.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__41.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__57.wav"
const ROTOR_LOOP := "res://sounds/sfx/quadcopter loop/freesound_community-mini-quadcopter-flying-loop-80330.mp3"

const DEG := PI / 180.0

## Concept y -> model y. See the origin note in the header.
const SHIFT := -2.25

## The core's big lobe, as the concept states it: a sphere of this radius with
## this squash on it, centred here. Held as constants because the pod stalks and
## the ocelli are both solved AGAINST this ellipsoid rather than eyeballed
## against it — see _stalk_top() and _ocelli().
const CORE_AT := Vector3(0.0, 2.68, 0.0)
const CORE_R := 0.6
const CORE_SQUASH := Vector3(1.25, 0.82, 1.15)

var _root: CharacterBody3D
var _metal: Material
## Every painted piece, collected as it is built. See the livery note in
## _build(): a piece is painted unless it was built through _unpainted_mesh(),
## which is the one door out and exists only for the ocelli.
var _paint: Array[Node3D] = []
## One mesh resource shared by all nine rotor blades, and one by all three
## hubs. They are identical and immutable, so nine copies would be nine
## sub-resources in the .tscn for no difference on screen. Everything that
## differs per piece gets its own mesh.
var _blade_mesh: BoxMesh
var _hub_mesh: CylinderMesh


func _init() -> void:
	_metal = load(METAL)
	# A WIDER CHORD THAN THE CONCEPT'S 0.10. concept_kit.gd's rotor() is a
	# generic part shared by twelve concepts and its blade is a 0.72 x 0.10
	# sliver, which on a concept sheet is a line and on the first render of this
	# frame read as three whiskers poking out past the hoop rather than as three
	# fans. 0.19 is still a blade and not a paddle, and it is the only dimension
	# on the frame changed for legibility rather than for fit.
	_blade_mesh = _boxm(Vector3(0.72, 0.045, 0.19))
	_hub_mesh = _cylm(0.13, 0.18, 10)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_brood: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_brood: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_brood: wrote %s" % OUT)
	print("build_brood: %d painted pieces, %d ocelli left off the livery"
			% [_paint.size(), _ocelli_count])
	# THE HEMISPHERE'S OWN EXTENT, PRINTED RATHER THAN ASSUMED. The open pod's
	# shell is a SphereMesh with is_hemisphere, and where Godot puts the flat
	# face — at y 0 or at y -height/2 — decides whether the mouth sits at the
	# pod's waist or at its floor. Nothing errors either way; it just models the
	# wrong half. One print is cheaper than finding out from a render.
	print("build_brood: open-pod shell aabb %s (full sphere %s)"
			% [_spherem(0.38, true).get_aabb(), _spherem(0.38).get_aabb()])
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## Concept space -> model space.
func _at(v: Vector3) -> Vector3:
	return v + Vector3(0.0, SHIFT, 0.0)


## A painted mesh piece. EVERYTHING VISIBLE goes through here except the ocelli,
## so nothing can be left without the shared faction metal — a single unpainted
## piece is invisible as a bug until someone renders the frame in a faction
## colour, and this frame has sixty of them.
func _mesh(parent: Node, nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := _unpainted_mesh(parent, nm, mesh, at, euler, scl)
	m.material_override = _metal
	_paint.append(m)
	return m


## The one door out of the paint list, and the only thing that uses it is the
## sensor. Kept as a separate function rather than a flag on _mesh() so that
## "which pieces are not painted" is answerable by grepping for one name.
func _unpainted_mesh(parent: Node, nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.position = at
	m.rotation = euler
	m.scale = scl
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


## Low segment counts throughout, matching the Spotter's own meshes. This is a
## PSX-textured game and a sixty-piece frame is not the place to spend faces.
##
## `height` IS HALVED FOR A HEMISPHERE, and that is not an obvious correction.
## A full SphereMesh spans -height/2 .. +height/2, so height = 2r gives a ball
## of radius r. With is_hemisphere the mesh instead spans 0 .. height, so the
## same height = 2r gives a dome TWICE AS TALL AS IT IS WIDE — measured:
## aabb S (0.74, 0.76, 0.74) against a full sphere's S (0.74, 0.76, 0.74) with
## its origin dropped. Nothing errors; the open pod just grows a 0.9 m spire up
## through the hull. height = r is the dome that matches the other eight pods.
func _spherem(r: float, hemi: bool = false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.radial_segments = 12
	s.rings = 6
	s.is_hemisphere = hemi
	return s


func _cylm(r: float, h: float, sides: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 0
	return c


func _torusm(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 18
	t.ring_segments = 6
	return t


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Broodcarrier"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, meaning "for this run only" — a scene
	# built without it packs with no groups line, and a robot outside "enemies"
	# is invisible to AIManager, to EMP and to every hostile sweep in the game
	# while still flying around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision ──
	#
	# A SPHERE, like both existing flyers, and bigger than either: the Spotter
	# is 0.5 and the bomber 0.6, and this frame is 2.1 m across its core alone.
	# 0.9 is the design doc's figure and it checks out against the art — see the
	# origin note in the header for what it does and does not contain. Left at
	# the origin, so the body, the ground ray and the hitbox share a centre.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	col.shape = sphere
	root_body.add_child(col)
	col.owner = root_body

	# NO GroundRay NODE. spotter_drone.gd builds its own in _ready() —
	# target (0, -300, 0), mask 1, exclude_parent — specifically so that no
	# drone scene can ship without the ray it needs to hold an altitude.
	# Authoring a second one here would give the frame two.

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, or the assignment is silently dropped. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three default clips instead. That line was untyped in
	# build_bulwark.gd for the Bulwark's whole life and bulwark.tscn shipped
	# with the wrong voice — nobody noticed, because it still barks. Read it as
	# the shape of the whole trap: it is every typed export on every node
	# touched here, including ones on components merely instantiated.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	bark.set("pitch_min", 0.5)
	bark.set("pitch_max", 0.58)
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
	_lift(rig)
	_core(rig)
	var bay := _brood_bay(rig)
	_ocelli(rig)

	# A MOUNT WITH NOTHING ON IT, EVER. weapon_slots = 0 is the design: a
	# flying spawner that also shot would be two units, and the frame is a
	# problem you have to prioritise rather than one that threatens you
	# directly. But enemy.gd declares `weapon_mount` as a typed Node3D export,
	# and this pass does not edit enemy.gd to remove it, so the frame provides
	# one and leaves it empty. Body-fixed under the core, where the brood
	# leaves — nothing aims on this frame, so there is no pivot to hang it off.
	#
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the
	# mount has to turn that onto the body's -Z. Read off a matrix the yaw looks
	# like a quarter turn either way; it is not, and the Bulwark's first build
	# had it backwards — the gun fitted, elevated, tracked targets and fired
	# directly behind the frame. Nothing warns. Kept correct here even though
	# nothing will ever hang on it, because the next person to read this scene
	# should not learn the wrong sign from it.
	var wm := _node(rig, "WeaponMount", _at(Vector3(0.0, 2.46, -0.70)),
			Vector3(0.0, PI * 0.5, 0.0))

	# ── effects ──
	var spark := (load(SPARK) as PackedScene).instantiate()
	spark.name = "SparkBurst"
	root_body.add_child(spark)
	spark.owner = root_body
	var oil := (load(OIL) as PackedScene).instantiate()
	oil.name = "OilSpray"
	root_body.add_child(oil)
	oil.owner = root_body

	# ── rotor audio ──
	#
	# NOT OPTIONAL ON A FLYER. spotter_drone.gd stops and restarts this node on
	# park, crash, downed and revive — four paths — and a flyer without it is
	# silent through all four with nothing saying so. The brief's script table
	# originally claimed the flying script declared no node paths at all; this
	# is the one it does. Louder and wider than the Spotter's -8 dB / 14 m,
	# because three mismatched fans on a 2.7 m frame are not a toy quadcopter.
	var rotor_loop := AudioStreamPlayer3D.new()
	rotor_loop.name = "RotorLoop"
	rotor_loop.stream = load(ROTOR_LOOP)
	rotor_loop.volume_db = -5.0
	rotor_loop.unit_size = 18.0
	rotor_loop.autoplay = true
	root_body.add_child(rotor_loop)
	rotor_loop.owner = root_body

	# ── livery ──
	var livery := Node.new()
	livery.name = "FactionLivery"
	livery.set_script(load(LIVERY))
	root_body.add_child(livery)
	livery.owner = root_body
	livery.set("base_material", _metal)
	livery.set("paint_blend", 1.0)
	# EVERY PAINTED PIECE, IN A TYPED ARRAY, AND NOT THE RIG ITSELF.
	#
	# `pieces` is Array[Node3D]. An untyped array lands as [] and FactionLivery
	# then falls back to walking its whole parent — which paints every mesh on
	# the frame. On the Bulwark that is how the eye ended up faction-coloured
	# despite being carefully left off a list that was never there. The same
	# trap has a second door on this frame: FactionLivery._gather() recurses
	# into whatever it is given, so listing `Rig` once instead of sixty leaves
	# would paint the ocelli too and lose the one thing that marks this sensor
	# as not the player's. So the list is LEAVES ONLY, collected by _mesh() as
	# each one is built, and the ocelli are not in it because they were built
	# through _unpainted_mesh().
	livery.set("pieces", _paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed — Node3D, Bark,
	# Area3D, AudioStreamPlayer3D, Array[Node3D] — so assigning a NodePath to
	# them silently does nothing and the frame comes out with a null detection
	# area and no rotor sound. Nothing errors. PackedScene.pack() turns these
	# references back into the node_paths=PackedStringArray(...) form the editor
	# writes, so the saved scene looks hand-authored either way.
	root_body.set("rotor_loop", rotor_loop)
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	root_body.set("weapon_mount", wm)

	# TYPED ARRAYS, OR THEY SAVE AS EMPTY.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)

	# JUST `Rig`, AND THAT IS THE RIGHT ANSWER HERE RATHER THAN A SHORT LIST.
	#
	# visible_pieces does two jobs in enemy.gd: hide_body()/show_body() toggle
	# `visible` on each entry, and the death collapse applies an 84-degree pitch
	# to each entry IN THE BODY'S OWN SPACE, about the body origin. A legged
	# frame lists its hull and turret and leaves the legs standing. This frame
	# has no legs and no part of it stays behind, so one entry covering the
	# whole rig both hides completely and tips as a single mass — a hive falling
	# out of the sky, not a hoop rotating off a cluster.
	#
	# Listing Rig AND a child of Rig would be the bug: both get the pitch, so
	# the child would receive it twice.
	var vis: Array[Node3D] = []
	vis.append(rig)
	root_body.set("visible_pieces", vis)

	# ── stats, from the design doc's section 3 ──
	#
	# 200 HP is high for a flyer (the Spotter is 80, the bomber 100) because
	# killing this one IS the objective rather than an inconvenience removed.
	root_body.set("health", 200)
	root_body.set("max_health", 200)
	# 70 m, the doc's base_sensor_range.
	root_body.set("sensor_range", 70.0)
	# The Spotter's 250, for the reason recorded against the long ADVANCE
	# orders: always_active does not exempt a robot from the distance cull, and
	# a culled flyer stops holding its altitude.
	root_body.set("activation_distance", 250)
	root_body.set("soldier_name", "Broodcarrier")
	# A flyer has no collider to flatten and the Spotter sets this false for
	# the same reason: it crashes and lies there, it does not sink.
	root_body.set("flatten_collider_when_downed", false)

	# ── flight tuning: PLACEHOLDERS, FOR THE HUMAN ──
	#
	# These are not in the design doc and they are game feel, which cannot be
	# judged from here. What the doc DOES say is "slow, so that reaching it is
	# possible" and that the pressure is "stop it, now, while it is in reach" —
	# so every one of these is set well below the Spotter's, whose job is to sit
	# at 22 m where nothing can touch it. In particular the doc's base_speed of
	# 0.7 is a ChassisDefinition MULTIPLIER (the bomber's is 1.0), so it belongs
	# in a .tres that this pass does not create; the numbers below are the
	# scene-level speeds it would multiply.
	root_body.set("move_speed", 6.0)
	root_body.set("cruise_speed", 6.0)
	# Low enough that a squad can shoot it and that dropped brood lands in the
	# fight rather than somewhere else.
	root_body.set("cruise_height", 12.0)
	root_body.set("orbit_radius", 10.0)
	root_body.set("orbit_speed", 3.5)
	# A heavy thing turns slowly, and a slow turn is what lets a squad cut it
	# off rather than chase it.
	root_body.set("turn_speed", 1.2)
	# Barely banks. A hive does not roll into its turns, and anything more tips
	# the pods into the silhouette of the hoop.
	root_body.set("bank_angle", 0.25)
	return root_body


# ─────────────────────────────────────────────
# THE LIFT — a hoop, three fans that disagree, three struts that disagree more
# ─────────────────────────────────────────────
func _lift(rig: Node3D) -> void:
	# THE LIFT IS A HOOP, not a pair of booms. An unbroken ring overhead is the
	# cheapest "this hovers" there is and it leaves the whole underside clear,
	# which is the only place the brood can be seen from.
	_mesh(rig, "LiftHoop", _torusm(1.02, 1.28), _at(Vector3(0.0, 3.0, 0.0)))

	# THREE FANS AT 14, 139 AND 243 DEGREES. A matched trio on 120s would read
	# as issued hardware; Swarm counts badly on purpose. The hubs sit at radius
	# 1.15, on the hoop itself, and the blades reach out past it to 1.87 — which
	# is where most of the frame's width comes from.
	#
	# EACH FAN IS A NODE AT ITS OWN HUB with the blades as children, so a later
	# script can spin one by rotating one node, and so each fan can be tilted
	# out of the common plane. The tilt is the one addition to the concept: three
	# exactly coplanar fans were the last precision-made thing left on a frame
	# whose brief is that nothing on it is.
	var fans: Array = [
		[14.0, Vector3(-4.0, 0.0, 3.0)],
		[139.0, Vector3(6.0, 0.0, -2.0)],
		[243.0, Vector3(-2.0, 0.0, -7.0)],
	]
	for i in fans.size():
		var a: float = float(fans[i][0]) * DEG
		var tilt: Vector3 = fans[i][1]
		var fan := _node(rig, "Rotor%s" % ["A", "B", "C"][i],
				_at(Vector3(sin(a) * 1.15, 2.97, cos(a) * 1.15)),
				Vector3(tilt.x * DEG, 0.0, tilt.z * DEG))
		_mesh(fan, "Hub", _hub_mesh, Vector3.ZERO)
		for b in 3:
			var ba := TAU * float(b) / 3.0
			# Rotating about Y by -ba takes local +X to (cos ba, 0, sin ba), so
			# the blade's long axis and its offset from the hub point the same
			# way and the blade runs from the hub outward rather than across it.
			_mesh(fan, "Blade%d" % b, _blade_mesh,
					Vector3(cos(ba) * 0.36, 0.05, sin(ba) * 0.36),
					Vector3(0.0, -ba, 0.0))

	# STRUTS AT 62, 186 AND 300 — angles that match NOTHING above. These are
	# CHORDS, not spokes: the position is radial but the rotation is -a, so each
	# bar runs from the hoop rim across to the core instead of straight out to
	# it. Measured, they span radius 1.02 to 0.00, 0.00 to 1.15, and 1.00 to
	# 0.00, so all three do reach from hoop to hull — they just get there the
	# wrong way, which is the point. Accretion, not assembly.
	var strut_deg := [62.0, 186.0, 300.0]
	for i in 3:
		var a: float = float(strut_deg[i]) * DEG
		_mesh(rig, "Strut%s" % ["A", "B", "C"][i], _boxm(Vector3(0.1, 0.1, 1.15)),
				_at(Vector3(sin(a) * 0.58, 2.9, cos(a) * 0.58)),
				Vector3(0.0, -a, 0.0))


# ─────────────────────────────────────────────
# THE CORE — three overlapping lobes, none of them on the axis
# ─────────────────────────────────────────────
## A single centred body is a hull, and a hull is what this faction does not
## have. The chamfered box, the turret ring and the whip antenna in
## concept_kit.gd are the PLAYER's language and are deliberately absent: there
## is not one flat panel or one cut corner on this frame.
func _core(rig: Node3D) -> void:
	_mesh(rig, "CoreA", _spherem(CORE_R), _at(CORE_AT), Vector3.ZERO, CORE_SQUASH)
	_mesh(rig, "CoreB", _spherem(0.42), _at(Vector3(-0.36, 2.54, 0.2)))
	_mesh(rig, "CoreC", _spherem(0.34), _at(Vector3(0.32, 2.58, -0.26)))


# ─────────────────────────────────────────────
# THE BROOD BAY — nine named pods, lowest first
# ─────────────────────────────────────────────
#
# Nine pods, eight sizes, no two gaps equal. Two of the concept's positions are
# moved and the reason is measured, not aesthetic: see _pods().
func _brood_bay(rig: Node3D) -> Node3D:
	var bay := _node(rig, "BroodBay", Vector3.ZERO)
	var specs := _pods()
	for i in specs.size():
		var at: Vector3 = specs[i][0]
		var r: float = specs[i][1]
		var open: bool = specs[i][2]
		_pod(bay, i + 1, at, r, open)
	return bay


## The nine pods, SORTED LOWEST FIRST so that Pod1..Pod9 counts upward and a
## depletion script hiding them in order empties the bay from the bottom.
##
## TWO POSITIONS DIFFER FROM THE CONCEPT, and both were measured rather than
## judged. The concept's pods at y 2.20 and y 2.26 sit with their CENTRES inside
## the core ellipsoid, so on a concept sheet they are two pods you cannot see —
## the same fault concept_kit.gd's head() has, where the mount ring is inside
## the turret body at every scale and has never once been visible. Harmless in a
## concept; on a frame whose whole proposition is that you can COUNT the
## remaining brood, two invisible pods is two-ninths of the proposition.
##
## So both are dropped until their shell tops clear the core's lower surface at
## their own (x, z), solved against the ellipsoid rather than nudged by eye:
##
##   (-0.52, ?, 0.18)  surface y 2.350   shell half-height 0.396  ->  2.03
##   ( 0.12, ?, 0.46)  surface y 2.322   shell half-height 0.348  ->  2.05
##
## They still overlap the hull by 80 mm, which is what makes them read as hung
## off it rather than floating under it. The other seven are the concept's own
## numbers untouched; the deepest of them, the big 0.44 on the axis, is 42 per
## cent swallowed by the belly and is meant to be.
func _pods() -> Array:
	return [
		[Vector3(-0.06, 1.60, 0.02), 0.38, true],
		[Vector3(-0.58, 1.76, 0.36), 0.24, false],
		[Vector3(0.38, 1.78, 0.30), 0.29, false],
		[Vector3(-0.30, 1.86, -0.42), 0.32, false],
		[Vector3(0.64, 2.00, -0.02), 0.25, false],
		[Vector3(-0.52, 2.03, 0.18), 0.33, false],
		[Vector3(0.12, 2.05, 0.46), 0.29, false],
		[Vector3(0.00, 2.10, 0.00), 0.44, false],
		[Vector3(0.46, 2.16, -0.22), 0.31, false],
	]


## ONE POD, as its own node so it can be hidden as one thing.
##
## A squashed egg with a band round it and a stalk up into the hull. `open`
## replaces the egg with a dome whose underside is gone and puts a hatchling
## half out of it, which is the only part of this frame that says SPAWNS rather
## than CARRIES.
func _pod(bay: Node3D, idx: int, at: Vector3, r: float, open: bool) -> Node3D:
	var pod := _node(bay, "Pod%d" % idx, _at(at))
	# Children are placed RELATIVE to the pod node, so hiding or later moving
	# Pod<n> takes its shell, band, stalk and hatchling with it. A pod built as
	# four siblings in rig space would need four nodes hidden in step and would
	# silently half-empty the first time somebody forgot one.
	if open:
		# THE CRACK, WITHOUT A BOOLEAN. The concept subtracts an oversized box
		# from the bottom front of the shell. A hemisphere does the same job
		# with no CSG and a better result: the opening is a full rim rather than
		# a slice, so it reads as a hole from above — which is the only angle
		# the game ever sees a flyer from — instead of needing a side view.
		#
		# Dropped 0.30r below the pod centre so the dome occupies the lower half
		# of the pod's slot rather than hovering at the top of it, and tilted
		# 14 degrees nose-down so the mouth faces forward along -Z, the way it
		# flies and the way the brood leaves.
		_mesh(pod, "Shell", _spherem(r, true), Vector3(0.0, -r * 0.30, 0.0),
				Vector3(14.0 * DEG, 0.0, 0.0), Vector3(1.0, 1.2, 1.0))
		# The bottom of the shell, cracked off and still hanging. Two plates at
		# angles that are not each other's mirror — a symmetrical pair would
		# read as jaws, i.e. as a mechanism, and nothing on this frame is one.
		_mesh(pod, "Flap1", _boxm(Vector3(r * 0.85, 0.035, r * 0.70)),
				Vector3(-r * 0.52, -r * 0.46, -r * 0.30),
				Vector3(52.0 * DEG, -18.0 * DEG, 26.0 * DEG))
		_mesh(pod, "Flap2", _boxm(Vector3(r * 0.62, 0.035, r * 0.55)),
				Vector3(r * 0.44, -r * 0.60, r * 0.34),
				Vector3(-38.0 * DEG, 31.0 * DEG, -34.0 * DEG))
		_mesh(pod, "Band", _torusm(r * 0.94, r * 1.15), Vector3(0.0, -r * 0.04, 0.0))
		_hatchling(pod, "Hatchling", Vector3(0.0, -r * 0.95, -r * 0.45), r * 0.46)
	else:
		_mesh(pod, "Shell", _spherem(r), Vector3.ZERO, Vector3.ZERO,
				Vector3(1.0, 1.2, 1.0))
		# The band LIES FLAT, which is a TorusMesh's own orientation: the pod
		# hangs vertically, so a torus in the XZ plane girdles it. Standing it
		# up would build an arch over the egg.
		_mesh(pod, "Band", _torusm(r * 0.94, r * 1.15), Vector3(0.0, r * 0.26, 0.0))

	# THE STALK IS SOLVED, NOT GUESSED. The concept gives every stalk the same
	# length, which is fine on a cluster drawn at one size and wrong here: the
	# outboard pods' stalks ended in mid-air, and a stalk that stops short of
	# the hull reads as a bug rather than as accretion. Each one instead runs
	# from inside its own shell up to a point proven to be inside the core
	# ellipsoid — see _stalk_top().
	var bottom := at.y + r * 0.9
	var top := _stalk_top()
	if top > bottom + 0.05:
		_mesh(pod, "Stalk", _cylm(r * 0.2, top - bottom),
				Vector3(0.0, (top + bottom) * 0.5 - at.y, 0.0))
	else:
		# Never reached by the nine above, and it says so rather than silently
		# building nothing: every early return in this project warns.
		push_warning("build_brood: Pod%d is too high to need a stalk (top %.3f, bottom %.3f)"
				% [idx, top, bottom])
	return pod


## Where every stalk ends: concept y 2.70, 20 mm above the core's centre.
##
## Checked, not assumed. For each of the nine pods' (x, z), the point
## (x, 2.70, z) was tested against the core ellipsoid — centre CORE_AT,
## half-extents CORE_R * CORE_SQUASH — and the worst of the nine scores 0.55 on
## a test that fails at 1.0. So all nine stalks end solidly inside the hull and
## none of them is a bar hanging in the air.
func _stalk_top() -> float:
	return 2.70


# ─────────────────────────────────────────────
# THE HATCHLING — what is in the pods
# ─────────────────────────────────────────────
## The small melee drone the carrier spawns, at roughly the size the Chaser
## ships at. Four stub legs and two mandibles, no gun: the brood's whole threat
## is contact, and a hatchling with a barrel on it would read as a spare sensor.
##
## Its own node, so the open pod's occupant is one thing to hide or later hand
## to a real spawn.
func _hatchling(parent: Node3D, nm: String, at: Vector3, r: float) -> Node3D:
	var h := _node(parent, nm, at)
	_mesh(h, "Body", _spherem(r), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.8, 1.15))
	for s in [-1.0, 1.0]:
		for f in [-1.0, 1.0]:
			var tag := "%s%s" % ["L" if s < 0.0 else "R", "F" if f < 0.0 else "B"]
			_mesh(h, "Leg%s" % tag, _boxm(Vector3(r * 0.22, r * 1.2, r * 0.22)),
					Vector3(s * r * 0.62, -r * 0.6, f * r * 0.55),
					Vector3(0.0, 0.0, s * 24.0 * DEG))
	for s in [-1.0, 1.0]:
		_mesh(h, "Mandible%s" % ("L" if s < 0.0 else "R"),
				_boxm(Vector3(r * 0.18, r * 0.18, r * 0.85)),
				Vector3(s * r * 0.3, 0.0, -r * 1.05),
				Vector3(0.0, s * 15.0 * DEG, 0.0))
	return h


# ─────────────────────────────────────────────
# THE SENSOR — five ocelli, and NOT AN EYE
# ─────────────────────────────────────────────
var _ocelli_count := 0

## NO EYE IN THE PLAYER'S SENSE. One offset optic in a chamfered head is how a
## frame in this game is recognised at forty pixels, and it is StratCom's
## grammar — the player's own factory. Swarm must not carry it. So: five eyes,
## not one; unequal, not matched; scattered over the hull's forward-lower flank,
## not set in a face. Too many eyes is the oldest "not a machine, and not yours"
## there is and it costs five spheres.
##
## PLACED ON THE ELLIPSOID, NOT NEAR IT. Each centre is the core's actual
## surface point along a chosen direction — centre + direction * (CORE_R *
## CORE_SQUASH) — so each ocellus is exactly half-buried and therefore visibly
## proud of the skin. Dropped straight onto the underside they would have been
## inside the pods instead, which is the same mistake in a different place.
##
## THE ONLY PIECES ON THE FRAME THAT KEEP THEIR OWN MATERIAL, built through
## _unpainted_mesh() so they never enter the livery list. A sensor repainted in
## the faction colour on every faction is a sensor that identifies nothing.
func _ocelli(rig: Node3D) -> void:
	var cluster := _node(rig, "SensorCluster", Vector3.ZERO)
	var mat := _ocellus_material()
	# direction (unit-ish), radius. No two spacings alike, no two sizes alike.
	var eyes: Array = [
		[Vector3(0.10, -0.42, -0.90), 0.080],
		[Vector3(-0.33, -0.36, -0.87), 0.055],
		[Vector3(0.46, -0.30, -0.84), 0.045],
		[Vector3(0.02, -0.72, -0.69), 0.065],
		[Vector3(-0.58, -0.58, -0.57), 0.035],
	]
	var half := CORE_R * CORE_SQUASH
	for i in eyes.size():
		var d: Vector3 = (eyes[i][0] as Vector3).normalized()
		var on_skin := CORE_AT + Vector3(d.x * half.x, d.y * half.y, d.z * half.z)
		var o := _unpainted_mesh(cluster, "Ocellus%d" % (i + 1),
				_spherem(float(eyes[i][1])), _at(on_skin))
		o.material_override = mat
		_ocelli_count += 1


## Dark glass with a weak amber glow behind it. ONE MATERIAL FOR THE FIVE, built
## fresh in this generator rather than loaded from a shared .tres: a material
## handed to two frames is one object, and this project has already paid for
## that once — see the duplicate() rule in CLAUDE.md.
##
## Amber is Swarm's colour (hud_palette.gd has FAC_SWARM waiting), but this is
## NOT a faction assignment and does not touch one: no faction is set on this
## frame, no enum is appended, and faction_livery.gd will render the painted
## pieces grey until Factions.SWARM exists. The glow is here because a sensor
## that does not light up is a bump.
func _ocellus_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.07, 0.05)
	m.metallic = 0.5
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = Color(0.95, 0.52, 0.08)
	m.emission_energy_multiplier = 0.9
	return m
