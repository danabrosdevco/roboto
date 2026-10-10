extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/drayman.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_drayman.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. Re-running it over a scene
# that has since been touched in the editor throws that work away, which is how
# --force rebuilds have repeatedly cost this project its gameplay layers. If the
# geometry needs changing after today, change the scene.
#
# It exists for the reason build_bulwark.gd records: a robot scene is thirty
# sub-resources with hand-numbered ids and an exact load_steps count, and
# writing that out by hand is transcription with nothing to learn from.
#
# ── WHAT THIS IS ─────────────────────────────
# DRAYMAN — supply 2, wheeled, logistics. The frame that answers an ammunition
# system that shipped with only half of itself: items carry an ammo_type,
# AIWeapon counts magazines down, and nothing in the game puts one back.
# docs/frames/DRAYMAN.md is the design doc; concept A, THE FLATBED, is the
# selected silhouette.
#
# THE WHOLE FRAME IS TWO FACTS IN ONE OUTLINE: it is carrying something, and it
# can hand it over. The strapped crate block does the first and the boom does
# the second, and if either stops reading at icon size the frame has lost the
# reason it beat three other options. Everything below serves those two.
#
# THE PROPORTIONS ARE NOT A NEW DESIGN. Sizes and positions are read off
# ConceptsB.drayman_a() in tools/concepts_b.gd, which is the approved silhouette
# built from the shared Walker vocabulary in tools/concept_kit.gd. Two
# systematic changes, both recorded in CONCEPT_Y and SINK below, plus three
# local corrections called out at their own call sites.
#
# Kit helpers are rebuilt rather than called, for the reason build_lance.gd
# gives: ConceptKit's shapes are raw CSG with no material and no scene
# ownership, which is right for a concept render and wrong for a shipping
# scene. Everything here goes through _mesh / _hull / _cut, which set the shared
# robot_metal material and the owner PackedScene.pack() needs. The concept's
# chamfered CSGPolygon3D plates are rebuilt as boxes — plain where the piece is
# small or hidden, CSGMesh3D with bevel cuts where it is on the outline — which
# is the idiom walker.tscn, vehicle_rover.tscn and bulwark.tscn already use.
#
# ── THE ONE DELIBERATE CHANGE FROM CONCEPT A ─
# THE BOOM TIP IS A FEED BELT, NOT A GRAB. drayman_a ends its boom in a generic
# grab block with a crate swinging under it, which says CARGO; drayman_b ends in
# a chute mouth paying out a run of linked rounds, which says AMMUNITION. The
# doc (sections 1 and 8) says to take B's tip and that it is not optional — it is
# the one part that separates resupply from generic cargo handling, and it is
# also the only cue in the whole concept kit that reads as ammunition without a
# weapon attached to it. So A's grab, its two wedge jaws and its hanging crate
# are gone and B's mouth and belt are here instead, with links added between the
# rounds: B's six rounds were modelled as a cascade spilling out of a hopper,
# and this frame is handing over a BELT, which has to look joined.
#
# ── HOW THE BOOM MAPS ONTO turret / gun_pivot ─
#
# THE DOC GIVES THIS FRAME turret = false, AND rover.gd DECLARES BOTH EXPORTS
# ANYWAY. The brief is explicit that the script is not to be edited, so the
# question is what those two exports may be allowed to point at.
#
# THE RECLAIMER IS THE LINEAGE BUT NOT THE PRECEDENT HERE. It does not run
# rover.gd at all: it has its own script, its own arm_base/shoulder/elbow/wrist
# chain, and no WeaponMount in its scene — equip_weapon_scene() builds one on
# the wrist at runtime, which is why enemy_force_spawner.gd deliberately does
# not guard on weapon_mount != null for it. THE LANCE IS THE PRECEDENT: the
# other turretless rover, and it answers the same question three files earlier.
#
# So, following the Lance: `Turret` and `GunPivot` are STUBS SATISFYING THE
# EXPORTS, NOT A TRAVERSE, and the boom is not wired to either of them.
#
#   1. NOTHING HANGS OFF EITHER STUB. Both sit on the hull centreline with zero
#      rotation and no children but each other. This is the part that matters,
#      because rover.gd's _update_facing is GUN-AIMING CODE: it yaws `turret`
#      toward weapon_target, pitches `gun_pivot` between gun_min/gun_max, and
#      _wreck slews the turret 50-125 degrees and slams the barrel to
#      wreck_barrel_degrees on death. Every one of those, applied to a cargo
#      boom, is a supply truck tracking you with its arm — which is the art
#      brief's single explicit prohibition, "the one thing it must not look like
#      is a gun truck".
#   2. turret_traverse_degrees = 0.0 and gun_elevation_degrees = 0.0, so both
#      rotate_toward calls are no-ops every frame rather than merely harmless.
#      wreck_barrel_degrees = 0.0 for the same reason: _wreck writes
#      gun_pivot.rotation.x directly, bypassing the rate.
#   3. On the centreline at zero rotation, _turret_forward() returns the HULL's
#      own bearing, which is what a frame that never fires should report to
#      _weapon_on_target and to the sight.
#
# It also buys what the Lance's header notes: hull_spoils_aim in enemy.gd is
# excused by a node property literally NAMED `turret` being non-null, not by
# ChassisDefinition.turret, and _update_facing only falls through to Soldier's
# body-turning version when turret == null. A stub keeps both of those on the
# rails without giving the frame a turret.
#
# WEAPON MOUNT: AUTHORED, NOT RUNTIME. The doc's section 5 asks for this to be
# decided before building because it changes a contract. Decided: AUTHORED. The
# boom is the selected concept — a Drayman without it is a flatbed truck and
# reads as scenery — so it is geometry in the scene, and a boom that exists in
# the scene has a tip in the scene to bolt a tool to. `WeaponMount` therefore
# hangs off BoomTip at yaw +PI/2 like every other frame's, and the Drayman does
# NOT inherit the Reclaimer's "mount appears only once a tool is equipped"
# contract: anything that guards on weapon_mount != null is correct for it.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/drayman.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
## rover.gd, unchanged. No new behaviour script in this pass — see the brief.
const BODY_SCRIPT := "res://Character/characters/ai/rover.gd"
## THE RECLAIMER'S OWN PAIR, 19 and 23, because the two support vehicles should
## sound like the same two machines — that is what "lineage" is worth on a
## soundtrack. Pitched just under it (0.68-0.76 against 0.70-0.78): same engine,
## more load.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__19.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__23.wav"

const DEG := PI / 180.0
## The eye keeps the Walker's own material — a plain StandardMaterial3D with
## this as albedo — and is deliberately absent from the livery list below.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

# ── WHERE THE GROUND IS, in body space ───────
#
# A CharacterBody3D sits where its collision shape's bottom does, so the body
# origin has to be CAPSULE_RADIUS above the ground. The Rover's side-laid
# capsule of radius 0.85 puts its own ground at y -0.85 and stands its wheel
# centres at -0.49 on a 0.36 tyre; this is the same arrangement with a bigger
# tyre.
const CAPSULE_RADIUS := 0.85
const GROUND := -CAPSULE_RADIUS

## AND THE CONCEPT SINKS ITS OWN TYRES. ConceptsB.drayman_a() puts the wheel
## centres at y 0.22 on a 0.42 radius, so its tyres pass 0.20 m THROUGH the
## ground line everything else on the sheet stands on. Lifting the whole frame
## by that amount is what stands them on it, and it changes no proportion
## anywhere: every y below is written `_y(<the concept's own y>)` so this file
## and ConceptsB.drayman_a() can be read side by side.
const SINK := 0.20

## Tyre and hub. One wheel size, because rover.gd has ONE wheel_radius for the
## whole frame and uses it for the spin rate and the suspension rays.
const WHEEL_R := 0.42
const WHEEL_W := 0.28
const HUB_R := 0.19

var _metal: Material
var _root: CharacterBody3D
## Built once each and shared across the pieces that use them, because they are
## read-only here — unlike the eye, which gets a fresh material per call for the
## reason CLAUDE.md gives about handing one resource to two instances.
var _rubber: StandardMaterial3D
var _hub_metal: StandardMaterial3D
## THE BELT IS BRASS AND THE HULL IS NOT. This is the only colour decision in
## the frame and it is load-bearing: a belt painted in the faction's own metal
## disappears into the boom it hangs off, and the belt is the part that says
## AMMUNITION rather than CARGO. Left off the livery list for the same reason
## the tyres are.
var _brass: StandardMaterial3D
var _lamp_lens: StandardMaterial3D


func _init() -> void:
	_metal = load(METAL)
	_rubber = _plain(Color(0.06, 0.06, 0.065), 0.0, 0.95)
	_hub_metal = _plain(Color(0.42, 0.43, 0.44), 0.55, 0.5)
	_brass = _plain(Color(0.72, 0.56, 0.24), 0.8, 0.35)
	_lamp_lens = _plain(Color(0.94, 0.90, 0.78), 0.0, 0.2)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_drayman: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_drayman: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_drayman: wrote %s" % OUT)
	quit(0)


## A concept y, in body space. See GROUND and SINK.
func _y(concept_y: float) -> float:
	return GROUND + SINK + concept_y


# ─────────────────────────────────────────────
# PIECES — the Bulwark's helpers, verbatim, for the reason its header gives:
# everything visible goes through one place that sets the shared material and
# the scene owner, so no piece can be left unpainted or unowned.
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


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


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
## reads as coming out of the same factory.
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


## A CSG hull: a box with cuts taken out of it. Baked ONCE AT BOOT by
## csg_bake.gd and shared between every instance, which is the only reason these
## may exist at all — see that file for the 335 ms spike that made baking
## compulsory. They are still not free at startup, so this frame spends them on
## the four pieces that are actually on the outline and uses plain boxes
## everywhere else.
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
## chosen by eye. Lifted off ConceptKit.hull, which lifted them off walker.tscn:
## a cut 70% of the width and 80% of the height, seated at 68% of the half-width
## and 66% of the half-height, turned 30 degrees.
func _bevel(hull: CSGMesh3D, size: Vector3, s: float, nm: String) -> void:
	_cut(hull, nm, Vector3(size.x * 0.7, size.y * 0.8, size.z * 1.4),
			Vector3(s * size.x * 0.68, size.y * 0.66, 0),
			Vector3(0, 0, s * 30.0 * DEG))


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Drayman"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's second
	# argument defaults to false, meaning "for this run only" — a frame built
	# without it packs with no groups line, and a robot outside "enemies" is
	# invisible to AIManager, to EMP and to every hostile sweep in the game while
	# still driving around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))
	# The Rover's floor handling, because this drives the same way it does.
	root_body.floor_constant_speed = true
	root_body.floor_max_angle = deg_to_rad(50.0)
	root_body.floor_snap_length = 0.4

	# ── collision and senses ──
	#
	# THE ROVER'S CAPSULE, UNCHANGED: radius 0.85, height 3.4, laid along Z. Not
	# copied for convenience — it is the honest shape of this frame. The hull is
	# 1.75 across against the Rover's 1.9 and 3.3 long against its 3.4, so the
	# same capsule covers the same body, and the two frames then bump, park and
	# fit through a doorway identically, which is what "same wheelbase, same
	# class" has to mean in practice.
	#
	# WHAT IT DOES NOT COVER, said out loud: the crate stack tops out 0.52 above
	# the capsule and the boom reaches 1.4 outside it, so a round fired at the
	# load or the arm passes through. The Rover's own turret and whip stand
	# outside its capsule in exactly the same way, and inventing a second
	# collider for the load is a gameplay decision, not a model one — flagged
	# rather than taken.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = 3.4
	col.shape = cap
	# Rotated onto Z: a capsule stands along its own Y, and this one lies down.
	col.rotation = Vector3(PI * 0.5, 0, 0)
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, OR THE ASSIGNMENT IS SILENTLY DROPPED. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three default clips instead. build_bulwark.gd had this line
	# untyped for the Bulwark's whole life and bulwark.tscn shipped with the
	# wrong voice, which nobody noticed because it still barks. build_lance.gd
	# still has it untyped — reported, not edited, because it is not my file.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	bark.set("pitch_min", 0.68)
	bark.set("pitch_max", 0.76)
	root_body.add_child(bark)
	bark.owner = root_body

	var nav := NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	# Sized to the art: 2.18 m across the tyres, 2.5 m to the top of the boom.
	# The bake is the only clearance the engine really enforces and radius and
	# climb quantise to cell units behind your back (see the family note in
	# CLAUDE.md), so these are honesty about the frame rather than a promise
	# about pathing. The Rover's desired distances, because it is the same
	# vehicle class arriving at the same kind of place.
	nav.radius = 1.1
	nav.height = 2.5
	nav.path_desired_distance = 3.0
	nav.target_desired_distance = 3.0
	root_body.add_child(nav)
	nav.owner = root_body

	var det := Area3D.new()
	det.name = "Detection"
	root_body.add_child(det)
	det.owner = root_body
	var dcol := CollisionShape3D.new()
	dcol.name = "CollisionShape3D"
	var dsphere := SphereShape3D.new()
	# The family's radius. This is the contact trigger, not the sensor: the
	# design doc's 40 m goes on `sensor_range` below.
	dsphere.radius = 25.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body

	# ── the rig ──
	#
	# AT IDENTITY ON THE BODY, and the wheels are its DIRECT children. Not a
	# style choice: rover.gd's suspension caches each wheel's local position and
	# then casts its ray from `global_transform * _wheel_rest[i]`, which is only
	# the right place if wheel-local, rig-local and body-local are the same
	# space. An offset rig or a nested wheel would put every suspension ray
	# somewhere the wheel is not.
	var rig := _node(root_body, "Rig", Vector3.ZERO)

	var hull := _bodywork(rig)
	var deck := _deck(rig)
	var load_block := _load(rig)
	var head_ring := _head_ring(rig)
	var head := _head(rig)
	var boom := _boom(rig)
	var wheel_nodes := _wheels(rig)
	_reverse_lamps(rig)

	# THE STUBS. See the header: body-fixed, on the centreline, nothing hanging
	# off either of them, and both rates zeroed below so rover.gd's gun-aiming
	# code cannot move a single visible piece. Parented GunPivot-under-Turret the
	# way vehicle_rover.tscn does, so the two scenes read the same.
	var turret := _node(rig, "Turret", Vector3(0, _y(1.14), 0))
	var gun_pivot := _node(turret, "GunPivot", Vector3.ZERO)

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
	# EVERY PAINTED PIECE, as Node OBJECTS in a TYPED array.
	#
	# `pieces` is Array[Node3D]; an untyped one lands as [] silently and
	# FactionLivery then falls back to walking its whole parent, which paints
	# every mesh on the frame — THE EYE INCLUDED. That is how the Bulwark's eye
	# ended up faction-coloured after being carefully left off a list that was
	# never there.
	#
	# GROUP NODES WHERE A WHOLE SUBTREE IS PAINTED, individual pieces where it is
	# not. FactionLivery._gather recurses, so listing `Load` paints all thirty of
	# its crates, lids and straps in one entry — but `Head` and `BoomSlew` are
	# NOT listed, because the eye hangs under the first and the brass belt under
	# the second, and recursion would take both.
	#
	# DELIBERATELY ABSENT: the EYE, because the one feature that identifies a
	# robot in this game must not change colour per faction; the TYRES and HUBS,
	# because rubber and bare steel are not livery and the Rover excludes its own
	# for the same reason; the BELT, because brass against painted steel is the
	# whole reason it reads as ammunition; and the LAMP LENSES.
	var paint: Array[Node3D] = []
	paint.append(hull)
	paint.append(deck)
	paint.append(rig.get_node("RailL"))
	paint.append(rig.get_node("RailR"))
	paint.append(rig.get_node("Studs"))
	paint.append(load_block)
	paint.append(head_ring)
	paint.append(head.get_node("HeadBody"))
	paint.append(head.get_node("SensorCowl"))
	paint.append(head.get_node("Antenna"))
	paint.append(rig.get_node("SlewRing"))
	paint.append(boom.get_node("BoomBase/BasePin"))
	paint.append(boom.get_node("BoomBase/BoomArm"))
	paint.append(boom.get_node("BoomBase/BoomElbow/ElbowPin"))
	paint.append(boom.get_node("BoomBase/BoomElbow/BoomStick"))
	paint.append(boom.get_node("BoomBase/BoomElbow/BoomTip/ChuteMouth"))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D or Array[Node3D] rather than NodePath, so assigning a NodePath to
	# one silently does nothing and the frame comes out with a null turret and
	# wheels the suspension cannot find. PackedScene.pack() turns the references
	# back into the node_paths=PackedStringArray(...) form the editor writes, so
	# the saved scene looks hand-authored either way.
	root_body.set("rig", rig)
	root_body.set("turret", turret)
	root_body.set("gun_pivot", gun_pivot)
	root_body.set("weapon_mount", boom.get_node("BoomBase/BoomElbow/BoomTip/WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED, OR THEY SAVE AS []. rover.gd declares `wheels` as Array[Node3D] and
	# `wheel_steer` as Array[float]; a plain Array assigned to either fails with
	# no error at all and the robot ships with no wheels to turn, no suspension,
	# and a _ready warning nobody reads.
	var wheels: Array[Node3D] = []
	for w in wheel_nodes:
		wheels.append(w)
	root_body.set("wheels", wheels)
	# IN THE SAME ORDER AS `wheels` — FL, FR, ML, MR, RL, RR — and these are the
	# Rover's own six values. The rear pair steers AGAINST the front, which is
	# what makes the middle axle the one that does not scrub and what sets the
	# turning circle rover.gd's `wheelbase` comment describes.
	var steer: Array[float] = [1.0, 1.0, 0.0, 0.0, -1.0, -1.0]
	root_body.set("wheel_steer", steer)
	root_body.set("wheel_radius", WHEEL_R)
	# MEASURED OFF THE ART, not inherited: front axle at z -1.2 to middle axle at
	# z 0 is 1.2 m, against the Rover's 1.1. rover.gd uses it for the bicycle
	# model and the turning circle, so leaving the Rover's value on a wider
	# wheelbase would have the hull swing along a radius it does not have.
	root_body.set("wheelbase", 1.2)
	var lamps: Array[Node3D] = []
	lamps.append(rig.get_node("ReverseLampL"))
	lamps.append(rig.get_node("ReverseLampR"))
	root_body.set("reverse_lamps", lamps)
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# The whole rig, as the Rover and the Lance do it: one entry that hides, tips
	# and drops the entire frame together. Enemy._collapse pitches each piece in
	# the BODY's space, so a single root is also the only way a vehicle goes over
	# as one object rather than coming apart into wheels, crates and a boom.
	var vis: Array[Node3D] = []
	vis.append(rig)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)

	# ── stats, from docs/frames/DRAYMAN.md section 3 and nowhere else ──
	#
	# base_health 170 — "slightly above the Reclaimer's 150, it is a truck".
	root_body.set("health", 170)
	root_body.set("max_health", 170)
	# base_sensor_range 40 — the Reclaimer's. "It is not a scout."
	root_body.set("sensor_range", 40.0)
	# THE ONE DERIVED NUMBER, derived rather than invented because the doc's
	# figure is in the wrong unit for this node. ChassisDefinition base_speed is
	# a MULTIPLIER (see ItemFacts.chassis_speed); a frame's real speed lives on
	# its scene as move_speed, and the Rover's is 7.0. The doc asks for 0.95 —
	# "loaded" — so: 6.65 m/s.
	root_body.set("move_speed", 6.65)
	root_body.set("soldier_name", "Drayman")
	# A vehicle does not lie down when it is knocked out; it settles on its
	# belly and goes over on one side, which rover.gd's _wreck already does.
	root_body.set("flatten_collider_when_downed", false)
	# The Rover's step figures, not Enemy's defaults. Nothing in the doc covers
	# them and they are not balance: a six-wheeled truck cannot lift a leg over a
	# kerb, and the default 0.45 / 0.35 are sized for something that can.
	root_body.set("step_height", 0.75)
	root_body.set("step_forward", 0.9)
	# ZEROED, AND THIS IS THE FRAME'S CHARACTER, NOT TUNING. See the header: with
	# both rates at zero rover.gd's turret yaw and gun pitch are no-ops every
	# frame, so the two stubs stay bolted to the hull. Raising either gives a
	# supply truck a tracking arm.
	root_body.set("turret_traverse_degrees", 0.0)
	root_body.set("gun_elevation_degrees", 0.0)
	# And _wreck writes gun_pivot.rotation.x DIRECTLY, bypassing the rate above,
	# so the droop angle has to be zeroed too or death would snap the stub.
	root_body.set("wreck_barrel_degrees", 0.0)
	# NOT SET, DELIBERATELY: max_steer_degrees, drive_accel, cornering_speed and
	# the rest of rover.gd's driving block keep their defaults. The doc gives no
	# mobility figures beyond the speed, and a loaded truck's steering lock is a
	# number for someone who can drive it.
	return root_body


## THE HULL AND ITS GLACIS, cut exactly as every other hull in this family is:
## sloped glacis, cut-back tail, bevels down both flanks. The concept's own
## 1.75 x 0.85 x 3.3 block — low and long, which is the half of the Reclaimer
## lineage that is not the arm.
func _bodywork(rig: Node3D) -> CSGMesh3D:
	var size := Vector3(1.75, 0.85, 3.3)
	var hull := _hull(rig, "Hull", size, Vector3(0, _y(0.68), 0))
	_cut(hull, "Glacis", Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.8),
			Vector3(0, -size.y * 0.72, -size.z * 0.62), Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.6),
			Vector3(0, -size.y * 0.68, size.z * 0.64), Vector3(20.0 * DEG, 0, 0))
	_bevel(hull, size, -1.0, "BevelL")
	_bevel(hull, size, 1.0, "BevelR")
	return hull


## THE DECK AND ITS RAILS. The rails stand proud of nothing in particular and
## that is the point: a flat bed with a kerb round it reads as a thing loads are
## PUT ON, where a smooth top reads as armour.
##
## LENGTHENED FROM THE CONCEPT'S 2.2 TO 2.3 AND MOVED BACK 0.08. The concept's
## crate block and its boom slew ring occupy the same volume — the ring is at
## (0.3, 1.2, 0.3) with a 0.3 radius and the stack covers x +/-0.59, z -0.33 to
## 1.33, so they intersect, which a concept render does not notice and a model
## cannot have. The load went aft and the ring went forward into the gap; the
## deck grew to stay under both. Nothing else moved.
func _deck(rig: Node3D) -> MeshInstance3D:
	var deck := _mesh(rig, "Deck", _boxm(Vector3(1.6, 0.12, 2.3)),
			Vector3(0, _y(1.14), 0.50))
	for s in [-1.0, 1.0]:
		_mesh(rig, "Rail%s" % ("L" if s < 0.0 else "R"),
				_boxm(Vector3(0.09, 0.34, 2.3)), Vector3(s * 0.8, _y(1.33), 0.50))
	# Bolt heads along the rails' outer faces, which is what makes the deck look
	# BOLTED TO a chassis rather than extruded out of it.
	#
	# AXIS ALONG X, NOT Z. mockup_parts.studs() lays every stud along Z, which on
	# a flank puts the head edge-on to the camera and shows nothing — the same
	# correction build_lance.gd made for its ammo rack. These face outboard,
	# where the three-quarter icon view looks.
	var studs := _node(rig, "Studs", Vector3.ZERO)
	for s in [-1.0, 1.0]:
		for i in 4:
			_mesh(studs, "Stud%s%d" % ["L" if s < 0.0 else "R", i],
					_cyl_mesh(0.032, 0.045, 6),
					Vector3(s * 0.87, _y(1.20), -0.40 + 0.60 * float(i)),
					Vector3(0, 0, PI * 0.5))
	return deck


## THE LOAD, AND IT IS HALF THE FRAME. Twelve crates in two columns, two courses
## and three ranks, over the middle and rear axles, strapped down.
##
## COUNTABLE, NOT A MASS. The concept's own note is the whole trick and it is
## kept: the 0.6 / 0.42 / 0.56 spacings against 0.54 / 0.38 / 0.50 crates leave a
## 6 cm gap on every seam, and one thin lid band per crate that overhangs the
## body by 2 cm. That is what separates a stack into things you can count at
## forty pixels instead of masonry.
##
## PLAIN BOXES, NO CSG. Thirty pieces here and every one of them would otherwise
## be a CSG root for csg_bake.gd to build at boot. The gaps and the lid bands
## carry the read; a chamfer on a crate 0.54 across does not survive the icon
## anyway.
##
## STRAPPED, which is the word the concept and the brief both use. Two runs over
## the top and four down the flanks, each 3.5 cm thick and seated 2 cm outside
## the stack so they cross it rather than sink into it, and the flank runs go
## below the crate bases into the deck so they read as tied DOWN.
func _load(rig: Node3D) -> Node3D:
	var block := _node(rig, "Load", Vector3.ZERO)
	var at := Vector3(0, 1.18, 0.82)
	for ix in 2:
		for iy in 2:
			for iz in 3:
				var p := at + Vector3(
						(float(ix) - 0.5) * 0.6,
						float(iy) * 0.42,
						(float(iz) - 1.0) * 0.56)
				var tag := "%d%d%d" % [ix, iy, iz]
				_mesh(block, "Crate%s" % tag, _boxm(Vector3(0.54, 0.38, 0.50)),
						Vector3(p.x, _y(p.y + 0.19), p.z))
				_mesh(block, "Lid%s" % tag, _boxm(Vector3(0.58, 0.05, 0.54)),
						Vector3(p.x, _y(p.y + 0.395), p.z))
	for i in 2:
		var z := 0.30 + 1.04 * float(i)
		_mesh(block, "StrapTop%d" % i, _boxm(Vector3(1.26, 0.035, 0.08)),
				Vector3(0, _y(2.055), z))
		for s in [-1.0, 1.0]:
			_mesh(block, "Strap%s%d" % ["L" if s < 0.0 else "R", i],
					_boxm(Vector3(0.035, 0.90, 0.08)),
					Vector3(s * 0.6125, _y(1.60), z))
	return block


## THE MOUNT RING UNDER THE CAB, AND IT IS MOVED.
##
## THE BRIEF'S KNOWN FAULT IN concept_kit.gd, present in ConceptsB._blind_head
## too: the ring is placed at `at` and the head body at at + 0.19 * scale with
## the body taller than the gap, so the ring is INSIDE the body at every scale
## and has never been visible on any concept sheet. Six wasted faces in a model.
##
## MOVED, NOT DROPPED. The ring is the family's single most reusable "a turret
## goes here" cue and this frame badly needs one, having no turret: it is the
## thing that says the cab is a head on a hull rather than a box glued to a
## bonnet. So it is seated ON the hull's top face (y 1.105) and the whole head
## above it lifted 0.094 to clear it. That lift changes no other dimension — the
## boom, not the cab, is the top of this frame's bounding box.
func _head_ring(rig: Node3D) -> MeshInstance3D:
	return _mesh(rig, "TurretRing", _cyl_mesh(0.3024, 0.0672),
			Vector3(0, _y(1.1386), -1.15))


## THE CAB — the Walker's head with the gun taken off it, which is exactly what
## ConceptsB._blind_head is for: a frame whose brief forbids reading as a gun
## truck may not carry the kit head's mantlet and 1.5 m barrel. Everything that
## makes the Walker's head recognisable is kept — ring, cheek and brow cuts, ONE
## eye offset LEFT, the whip — and a sensor cowl stands where the mantlet was.
##
## Scaled 0.56, the concept's own figure, and seated over the front axle.
func _head(rig: Node3D) -> Node3D:
	var sf := 0.56
	var head := _node(rig, "Head", Vector3(0, _y(1.3402), -1.15))
	var body_size := Vector3(1.18, 0.6, 1.3) * sf
	var body := _hull(head, "HeadBody", body_size, Vector3.ZERO)
	var cutter := Vector3(1.18 * 1.3, 0.7, 0.7) * sf
	_cut(body, "Cheek", cutter, Vector3(0, -0.44, -0.86) * sf, Vector3(-35.0 * DEG, 0, 0))
	_cut(body, "Brow", cutter, Vector3(0, 0.5, -0.78) * sf, Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, OFFSET LEFT, with the WALKER'S OWN material rather than the shared
	# faction metal — a StandardMaterial3D with the eye texture as albedo. It is
	# deliberately absent from the livery list, and so is `Head`, because
	# FactionLivery recurses into whatever it is handed.
	#
	# NOTHING CROSSES IT. The eye is at x -0.19 and the boom slews out to the
	# front RIGHT quarter; that is the concept's own rule — slewed over the nose
	# the arm and its load pass straight across the eye, which may never happen.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.17 * sf
	eye_mesh.height = 0.17 * sf * 2.0 * 0.82   # the family's squash
	eye_mesh.radial_segments = 14
	eye_mesh.rings = 7
	var eye := _mesh(head, "Eye", eye_mesh, Vector3(-0.34, 0.14, -0.66) * sf)
	eye.material_override = _eye_material()

	# The whip, off the port rear corner of the cab. CHECKED RATHER THAN
	# ASSUMED, which is the brief's warning about the Kite: the kit's antenna is
	# safe on a head standing on a hull and was inside the fuselage on a head
	# hung under one. This one rises from y 1.389 to 1.959 at z -0.88, forward of
	# the deck's front edge at -0.65 and clear of the hull top at 1.105.
	_mesh(head, "Antenna", _boxm(Vector3(0.03, 0.85, 0.03) * sf),
			Vector3(-0.5, 0.68, 0.48) * sf)

	# THE SENSOR COWL, ON THE RIGHT, because the eye is on the left and nothing
	# may cross an eye. Pushed forward of the concept's seat so it stands a full
	# 0.112 proud of the face instead of 0.027: the brow cut takes the upper
	# front away, and a cowl flush with what is left sinks into the cut and
	# shows nothing — the first rule in mockup_parts.gd's header.
	var cowl_size := Vector3(0.46, 0.3, 0.2) * sf
	var cowl := _hull(head, "SensorCowl", cowl_size, Vector3(0.2 * sf, 0, -0.42))
	_bevel(cowl, cowl_size, -1.0, "ChamferL")
	_bevel(cowl, cowl_size, 1.0, "ChamferR")
	return head


## THE REACH — the second of the frame's two facts, and the one the crates
## cannot carry.
##
##   SlewRing    on the deck, where the ring is visible as a ring
##   BoomSlew    yawed out to the front quarter. Fixed: see the header on why
##               nothing here is wired to rover.gd's aiming.
##   BoomBase    lifted 36 degrees, the concept's own
##   BoomElbow   bent -56, which folds the stick back DOWN
##   BoomTip     pitched +20, which is the SUM OF THE TWO ABOVE UNDONE, so the
##               feed head hangs level whatever the arm is posed to
##
## THE LEVELLING IS NOT OPTIONAL AND THE CONCEPT SAYS SO. The tip inherits lift
## plus bend, so anything parented straight to it comes out tilted by their sum —
## the same error that once had the Bulwark's tower shield lying flat like a
## dropped door. Undoing it at BoomTip keeps the mouth and the belt upright, and
## the two numbers have to be changed TOGETHER: 36 - 56 + 20 = 0.
##
## -56 AT THE ELBOW, NOT THE CONCEPT'S -70. At -70 the feed head hung level with
## the tops of the front tyres and tangled with them in the icon view, which puts
## the one part that says AMMUNITION in the busiest place on the frame. At -56 the
## mouth sits about 1.5 m off the ground — chest height on a Walker, which is also
## the right height to hand a belt to one — and the arm still reads as folded
## down rather than held out.
##
## -55 DEGREES OF SLEW, NOT THE CONCEPT'S -45. The slew ring had to move 0.63 m
## forward to get out of the crate block (see _deck), and at -45 from there the
## boom reached 0.35 m past the hull's own nose — a supply truck with its arm
## stuck out in front of it, longer than the doc's 3.35 and in the way of its own
## driving. Fifteen more degrees of slew spends that reach out to the FLANK
## instead, which is where the concept wanted it anyway: the fiction is handing a
## crate to a squad walking beside the vehicle.
func _boom(rig: Node3D) -> Node3D:
	_mesh(rig, "SlewRing", _cyl_mesh(0.28, 0.14), Vector3(0.30, _y(1.27), -0.33))
	var slew := _node(rig, "BoomSlew", Vector3(0.30, _y(1.34), -0.33),
			Vector3(0, -55.0 * DEG, 0))
	var base := _node(slew, "BoomBase", Vector3.ZERO, Vector3(36.0 * DEG, 0, 0))
	# A cylinder stands along its own Y; a quarter turn about X lays the axis
	# along Z, which is the pin the boom swings on.
	_mesh(base, "BasePin", _cyl_mesh(0.16, 0.22), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	_mesh(base, "BoomArm", _boxm(Vector3(0.22, 0.22, 1.4)), Vector3(0, 0, -0.7))
	var elbow := _node(base, "BoomElbow", Vector3(0, 0, -1.4), Vector3(-56.0 * DEG, 0, 0))
	_mesh(elbow, "ElbowPin", _sphere_mesh(0.14), Vector3.ZERO)
	_mesh(elbow, "BoomStick", _boxm(Vector3(0.18, 0.18, 1.1)), Vector3(0, 0, -0.55))
	var tip := _node(elbow, "BoomTip", Vector3(0, 0, -1.1), Vector3(20.0 * DEG, 0, 0))
	_feed_head(tip)
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the mount
	# has to turn that onto the parent's -Z. Read off a matrix the two look like
	# the same quarter turn; they are not, and the Bulwark's first build had it
	# backwards — the gun fitted, elevated, tracked and fired directly behind the
	# frame, with nothing complaining, because a mount pointing the wrong way is
	# a perfectly valid transform.
	#
	# UNDER THE LEVELLED TIP, so -Z here is the boom's own horizontal reach and a
	# fitted supply_boom hands its load outward past the feed head rather than
	# into the ground at the arm's droop angle.
	_node(tip, "WeaponMount", Vector3(0, -0.35, -0.30), Vector3(0, PI * 0.5, 0))
	return slew


## THE FEED HEAD — a chute mouth with a belt of linked rounds paying out of it.
##
## THIS IS THE PART THAT SAYS AMMUNITION. drayman_a ended its boom in a grab
## block holding a crate, which says cargo; this is drayman_b's tip, moved over
## on the doc's instruction (sections 1 and 8), and the design doc is explicit
## that it is not cosmetic — it is the one part that distinguishes resupply from
## generic cargo handling.
##
## LINKED, which is the doc's word and a change from B. B's six rounds are a
## CASCADE spilling out of a hopper and are modelled as six loose objects; a
## frame that hands a belt over has to look like the belt is JOINED, so there is
## a link plate between every pair. The 7-degrees-per-round splay is B's own and
## is what stops a straight run of boxes reading as a ladder.
##
## FIVE ROUNDS, SCALED UP FROM B's 0.07 TO 0.10. B's chute hangs off a 0.85 m
## boom on a hopper truck and its rounds are read at arm's length; this one hangs
## off a 2.5 m boom whose tip is the furthest point on the frame, and at that
## distance a 7 cm box is a hairline that disappears into the wheels behind it.
## One fewer, each bigger, is the same belt that still reads.
##
## BRASS, NOT LIVERY. See _brass: the belt is the only thing on the frame that is
## not painted steel, and that contrast is the whole reason it reads at distance.
func _feed_head(tip: Node3D) -> void:
	# B's chute mouth is a chamfered plate 0.5 x 0.44 extruded 0.3 downward;
	# rebuilt here as a box with its top corners taken off, because it is on the
	# outline and a square slab there reads as a placeholder.
	var mouth_size := Vector3(0.50, 0.30, 0.44)
	var mouth := _hull(tip, "ChuteMouth", mouth_size, Vector3(0, -0.35, 0))
	_bevel(mouth, mouth_size, -1.0, "ChamferL")
	_bevel(mouth, mouth_size, 1.0, "ChamferR")
	for i in 5:
		var at := Vector3(0.0, -0.50 - 0.18 * float(i), -0.05 - 0.06 * float(i))
		var round_mesh := _mesh(tip, "Round%d" % i, _boxm(Vector3(0.10, 0.16, 0.10)),
				at, Vector3(float(i) * 7.0 * DEG, 0, 0))
		round_mesh.material_override = _brass
		if i == 0:
			continue
		# The link between this round and the one above it: a flat plate across
		# the gap, which is what makes five rounds a BELT instead of five rounds.
		var prev := Vector3(0.0, -0.50 - 0.18 * float(i - 1), -0.05 - 0.06 * float(i - 1))
		var link := _mesh(tip, "Link%d" % i, _boxm(Vector3(0.13, 0.06, 0.05)),
				(at + prev) * 0.5, Vector3(float(i) * 7.0 * DEG, 0, 0))
		link.material_override = _brass


## SIX WHEELS, THREE AXLES, WHICH IS THE ROVER'S OWN ARRANGEMENT AND THE
## RECLAIMER'S WHEELBASE. Front and rear steer against each other; the middle
## axle is fixed, which is what stops a 3.3 m hull scrubbing round a corner.
##
## ORDER MATTERS AND IT IS FL, FR, ML, MR, RL, RR. rover.gd indexes `wheel_steer`
## against `wheels` by position, and its _terrain_fit reads each wheel's own
## local z and x to decide which axle and which side it is on — so the array is
## the suspension's only map of the frame.
##
## Each wheel is a PIVOT with a child named "Spin" under it, and the tyre inside
## that. Not decoration: rover.gd steers the pivot about Y and rolls `Spin` about
## X BY NAME — `w.get_node_or_null(^"Spin")` — so a tyre parented straight to the
## pivot would steer and never turn.
func _wheels(rig: Node3D) -> Array:
	var out: Array = []
	for sz in [-1.2, 0.0, 1.2]:
		for sx in [-1.0, 1.0]:
			var tag := "F" if sz < -0.5 else ("M" if sz < 0.5 else "R")
			tag += "L" if sx < 0.0 else "R"
			# THE CONCEPT'S OWN 0.22, NOT GROUND + WHEEL_R. Those are the same
			# number here and that is the whole definition of SINK — the lift is
			# exactly what stands a 0.42 tyre centred at 0.22 on the ground. The
			# first build wrote GROUND + WHEEL_R, which applies the lift TWICE
			# and left all six tyres floating 0.20 m in the air: nothing errored,
			# the frame measured 0.20 short, and rover.gd's suspension rays would
			# have cast from above the contact patch for the life of the chassis.
			out.append(_wheel(rig, "Wheel%s" % tag,
					Vector3(sx * 0.95, _y(0.22), sz)))
	return out


func _wheel(rig: Node3D, nm: String, at: Vector3) -> Node3D:
	var pivot := _node(rig, nm, at)
	var spin := _node(pivot, "Spin", Vector3.ZERO)
	# A cylinder stands along its own Y; a quarter turn about Z lays the axis
	# along X, which is the axle. Inside Spin, so rolling Spin about X turns it.
	var tyre := _mesh(spin, "Tyre", _cyl_mesh(WHEEL_R, WHEEL_W), Vector3.ZERO,
			Vector3(0, 0, PI * 0.5))
	tyre.material_override = _rubber
	# Five sides, so the hub reads as a wheel TURNING. A smooth disc at this size
	# animates as a disc that is not moving.
	var hub := _mesh(spin, "Hub", _cyl_mesh(HUB_R, WHEEL_W * 1.08, 5), Vector3.ZERO,
			Vector3(0, 0, PI * 0.5))
	hub.material_override = _hub_metal
	return pivot


## REVERSE LAMPS, which the Rover has and which a logistics vehicle has more
## business having than a gun truck does: half of what this frame does is back up
## to somebody. rover.gd shows them when the drive command goes below -0.3 m/s,
## so they ship OFF — `visible = false` — or they would glow until the first
## physics tick.
##
## On the hull's rear face above the tail cut. Their own lens material, left off
## the livery list: a faction-coloured lamp is not a lamp.
func _reverse_lamps(rig: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var lamp := _mesh(rig, "ReverseLamp%s" % ("L" if s < 0.0 else "R"),
				_boxm(Vector3(0.16, 0.12, 0.06)),
				Vector3(s * 0.55, _y(0.80), 1.62))
		lamp.material_override = _lamp_lens
		lamp.visible = false


func _cyl_mesh(r: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


func _sphere_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object — see the duplicate() rule in
## CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m


## Rubber, bare steel, brass and lamp glass, in the Rover's own idiom so the two
## frames' wheels are the same objects on screen.
func _plain(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m
