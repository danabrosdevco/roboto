extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/lance.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_lance.gd
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
# LANCE — supply 1, wheeled, scout and harasser. The cheapest vehicle in the
# game, and the frame that makes supply 1 a real choice rather than "infantry or
# nothing". docs/frames/LANCE.md is the design doc; concept A, the TRIKE, is the
# selected silhouette.
#
# THE PROPORTIONS ARE NOT A NEW DESIGN. Every position and size below is read
# straight off ConceptsA.lance_a() in tools/concepts_a.gd, which is the approved
# silhouette built from the shared Walker vocabulary in tools/concept_kit.gd.
# The only systematic change is the VERTICAL ORIGIN: the concept builders put
# ground at y = 0, and a robot scene has to put the body origin where the
# collision capsule's bottom touches the ground. GROUND below is that offset and
# every y is written as GROUND + <the concept's own y>, so the two files can be
# read side by side.
#
# Two kit helpers had to be rebuilt rather than called. ConceptKit's shapes are
# raw CSG with no material and no scene ownership, which is fine for a concept
# render and wrong for a shipping scene — so everything here goes through _mesh
# / _hull / _cut, the same helpers build_bulwark.gd uses, which set the shared
# robot_metal material and the owner that PackedScene.pack() needs. The
# concept's chamfered CSGPolygon3D "plates" (the gun cradle and the ammo rack)
# are rebuilt as CSGMesh3D boxes with bevel cuts taken off them, which is the
# idiom the Walker, the Rover and the Bulwark already use and avoids
# introducing the one CSG node type no shipped robot scene has.
#
# ── THE LANCE HAS NO TURRET, AND Turret IS STILL WIRED ──
#
# The frame's defining trait is that it aims by pointing its whole body: the
# Rover's counter — flank it faster than its turret can traverse — turned into a
# chassis. rover.gd declares `turret` and `gun_pivot` as exports regardless, and
# the brief is explicit that the script is NOT to be edited to remove them.
#
# So `Turret` here is A STUB SATISFYING THE EXPORT, NOT A TRAVERSE. Three things
# make that true rather than merely intended:
#
#   1. turret_traverse_degrees = 0.0. rover.gd's _update_facing calls
#      rotate_toward(turret.rotation.y, want, deg_to_rad(traverse) * delta);
#      with traverse zero that call returns the angle it was given, so the node
#      never moves. Leaving the Rover's 95 would have given the Lance a working
#      turret, which is the one thing this frame must not have.
#   2. NOTHING HANGS OFF IT. The gun is parented to GunMount in the nose, not to
#      Turret, so even rover.gd's death flourish (_wreck slews turret.rotation.y
#      by 50-125 degrees) cannot move a single visible piece. A stub with the
#      barrel underneath would have spun the Lance's bolted-on nose gun off to
#      one side the moment it died.
#   3. It sits on the spine centreline with zero rotation, so _turret_forward()
#      — which rover.gd uses for _weapon_on_target and for the sight — returns
#      the HULL's forward. That is exactly the behaviour LANCE.md section 6
#      wanted from a turretless frame, and it falls out of Rover for free.
#
# It also buys the thing LANCE.md section 5 trap 5 is about: `hull_spoils_aim`
# in enemy.gd is excused by a node property literally named `turret` being
# non-null, not by ChassisDefinition.turret, so a Lance with a null turret would
# never settle its aim and never leave WeaponState.AIM while moving.
#
# ONE CONSEQUENCE IS LEFT FOR THE BEHAVIOUR PASS, deliberately, because fixing
# it would mean editing rover.gd: _update_facing only falls through to Soldier's
# body-turning version when `turret == null`. With a stub wired and zero
# traverse, a stationary Lance will not rotate to face a target at all — it
# aims only by driving. That is a decision for whoever writes lance.gd and the
# chassis .tres, and it is recorded here so it is not discovered as a bug.
#
# ── THE GUN IS GEOMETRY, NOT KIT ─────────────
# The barrel and muzzle brake are built into the rig under GunPivot rather than
# left to a fitted weapon scene, because "the gun is the nose" IS the selected
# concept — a Lance without them is an empty frame on three wheels and reads as
# scenery. WeaponMount therefore sits at the cradle's front face, where the
# Rover puts its own mount: at the breech, 0.12 m ahead of its GunPivot.
# A fitted weapon will overlay the cast barrel until the light_cannon pass
# decides which of the two owns it; that is noted in the report, not papered
# over here.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/lance.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
## rover.gd, unchanged. No new behaviour script in this pass — see the brief.
const BODY_SCRIPT := "res://Character/characters/ai/rover.gd"
## The small, quick pair, and the pitch range to match: this is the lightest
## frame on the roster and the Rover's 0.80-0.88 is already the voice of
## something three times its mass.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__19.wav"

const DEG := PI / 180.0
## The eye keeps the Walker's own material — a plain StandardMaterial3D with
## this as albedo — and is deliberately absent from the livery list below.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

## WHERE THE GROUND IS, in body space.
##
## The concept builders put ground at y = 0 and stand the wheels on it. A
## CharacterBody3D sits where its collision shape's bottom does, so the body
## origin has to be CAPSULE_RADIUS above the ground — the same arrangement the
## Rover has, whose side-laid capsule of radius 0.85 puts its own ground at
## y -0.85. Every y below reads `GROUND + <the concept's y>` so build_lance.gd
## and ConceptsA.lance_a() can be diffed by eye.
const CAPSULE_RADIUS := 0.52
const GROUND := -CAPSULE_RADIUS

## The driven wheels. rover.gd has ONE wheel_radius for the whole frame and uses
## it for the spin rate and for the suspension rays, so a trike with two sizes
## has to pick one: the big driven pair, because the castor behind only drags.
const DRIVE_WHEEL_R := 0.44
const DRIVE_WHEEL_W := 0.26
const CASTOR_R := 0.26
const CASTOR_W := 0.20

var _metal: Material
var _root: CharacterBody3D
## Built once each and shared across the pieces that use them, because they are
## read-only here — unlike the eye, which gets a fresh material per call for the
## reason CLAUDE.md gives about handing one resource to two instances.
var _rubber: StandardMaterial3D
var _hub_metal: StandardMaterial3D


func _init() -> void:
	_metal = load(METAL)
	_rubber = _plain(Color(0.06, 0.06, 0.065), 0.0, 0.95)
	_hub_metal = _plain(Color(0.42, 0.43, 0.44), 0.55, 0.5)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_lance: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_lance: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_lance: wrote %s" % OUT)
	quit(0)


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


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Lance"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, meaning "for this run only" — a frame
	# built without it packs with no groups line, and a robot outside "enemies"
	# is invisible to AIManager, to EMP and to every hostile sweep in the game
	# while still driving around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))
	# The Rover's floor handling, because this drives the same way it does.
	root_body.floor_constant_speed = true
	root_body.floor_max_angle = deg_to_rad(50.0)
	root_body.floor_snap_length = 0.4

	# ── collision and senses ──
	#
	# LOW AND SHORT, as the design doc asks. Laid along Z like the Rover's, so
	# the capsule is the vehicle's length and its radius is the half-width that
	# sets how it bumps and how far off a wall it parks. 0.52 covers the spine
	# and both driven wheels vertically and leaves the tyres standing 0.27
	# proud of it either side — the same proportion the Rover has, whose wheels
	# stand 0.20 outside its own capsule. A collider out to the full 1.58 m
	# track would make the cheapest, nimblest frame in the game the widest
	# thing in a doorway.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	# Nose of the cradle to the back of the castor's tyre; the barrel ahead of
	# that is deliberately NOT a collider, the way the Rover's is not either.
	cap.height = 2.3
	col.shape = cap
	# Rotated onto Z: a capsule stands along its own Y, and this one lies down.
	col.rotation = Vector3(PI * 0.5, 0, 0)
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, or the assignment is silently dropped and the scene keeps
	# bark.tscn's three defaults. This frame shipped with them: the trap was
	# still live in build_bulwark.gd when this generator was copied from it.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# HIGHER THAN ANYTHING ELSE ON THE ROSTER. The Bulwark is 0.64-0.72 and the
	# Rover 0.80-0.88; this is the smallest frame in the game and it should
	# sound like it.
	bark.set("pitch_min", 1.04)
	bark.set("pitch_max", 1.16)
	root_body.add_child(bark)
	bark.owner = root_body

	var nav := NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	# Sized to the art: 1.58 m across the tyres, 1.75 m to the top of the whip.
	# The bake is the only clearance the engine really enforces (see the note in
	# CLAUDE.md's family), so these are honesty about the frame rather than a
	# promise about pathing.
	nav.radius = 0.8
	nav.height = 1.8
	# Tighter than the Rover's 3.0: a third of its mass on a shorter wheelbase
	# can be asked to arrive somewhere more exactly.
	nav.path_desired_distance = 2.0
	nav.target_desired_distance = 2.0
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
	# design doc's 60 m goes on `sensor_range` below.
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

	var spine := _spine(rig)
	_front_axle(rig)
	_tail(rig)

	# THE STUB. See the header: body-fixed, nothing parented to it, and
	# turret_traverse_degrees is zero so rover.gd cannot move it. It sits on the
	# spine centreline at the height a turret ring would be, which is what makes
	# _turret_forward() read the hull's own bearing.
	var turret := _node(rig, "Turret", Vector3(0, GROUND + 0.74, 0))

	var gun_pivot := _gun(rig)
	_ammo_rack(rig)
	var head := _head(rig)
	# The whip, off the starboard quarter. With no turret ring, the eye and the
	# aerial are the whole family resemblance — see the note at the top of
	# concepts_a.gd.
	_mesh(rig, "Antenna", _boxm(Vector3(0.03, 0.90, 0.03)),
			Vector3(0.26, GROUND + 1.30, 0.56))

	var wheel_nodes := _wheels(rig)

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
	# THE EYE IS DELIBERATELY ABSENT, and so are the tyres and hubs: rubber and
	# bare steel are not livery, and the Rover paints only its hull, turret and
	# fenders for the same reason.
	var paint: Array[Node3D] = []
	paint.append(spine)
	paint.append(rig.get_node("Axle"))
	paint.append(rig.get_node("DropLinkL"))
	paint.append(rig.get_node("DropLinkR"))
	paint.append(rig.get_node("SwingArm"))
	paint.append(rig.get_node("GunMount/Cradle"))
	paint.append(gun_pivot.get_node("Barrel"))
	paint.append(gun_pivot.get_node("MuzzleBrake"))
	paint.append(rig.get_node("AmmoRack"))
	paint.append(rig.get_node("Antenna"))
	paint.append(head.get_node("Stalk"))
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
	root_body.set("weapon_mount", gun_pivot.get_node("WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED, OR IT SAVES AS []. rover.gd declares `wheels` as Array[Node3D] and
	# `wheel_steer` as Array[float]; a plain Array assigned to either fails with
	# no error at all and the robot ships with no wheels to turn, no suspension
	# and a _ready warning nobody reads.
	var wheels: Array[Node3D] = []
	for w in wheel_nodes:
		wheels.append(w)
	root_body.set("wheels", wheels)
	# IN THE SAME ORDER AS `wheels`: 1 steers with the front, -1 against it,
	# 0 fixed. The two driven wheels are the steering axle. The castor behind
	# gets 0.4 rather than 0 or -1 because a DRAGGED wheel aligns with its own
	# path, not with the steering input and not against it — it follows the
	# turn, by less than the wheels making it.
	var steer: Array[float] = [1.0, 1.0, 0.4]
	root_body.set("wheel_steer", steer)
	root_body.set("wheel_radius", DRIVE_WHEEL_R)
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# The whole rig, as the Rover does it: one entry that hides, tips and drops
	# the entire frame together. Enemy._collapse pitches each piece in the
	# BODY's space, so a single root is also the only way a vehicle tips over
	# as one object rather than coming apart into wheels and a spine.
	var vis: Array[Node3D] = []
	vis.append(rig)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)

	# ── stats, from docs/frames/LANCE.md section 3 and nowhere else ──
	#
	# base_health 110 — "survives a burst, not an engagement".
	root_body.set("health", 110)
	root_body.set("max_health", 110)
	# base_sensor_range 60 — "better eyes than infantry, worse than a Spotter".
	root_body.set("sensor_range", 60.0)
	# THE ONE DERIVED NUMBER, and it is derived rather than invented because the
	# doc's figure is in the wrong unit for this node. ChassisDefinition
	# base_speed is a MULTIPLIER (1.00 on every buildable frame, see
	# ItemFacts.chassis_speed); a frame's real speed lives on its scene as
	# move_speed, and the Rover's is 7.0. The doc asks for 1.35, so: 9.45 m/s,
	# which is what "the fastest thing the player owns" means in metres.
	root_body.set("move_speed", 9.45)
	root_body.set("soldier_name", "Lance")
	# A vehicle does not lie down when it is knocked out; it settles on its
	# belly, which rover.gd's _wreck already does.
	root_body.set("flatten_collider_when_downed", false)
	# ZERO, AND THIS IS THE DEFINING TRAIT, NOT A TUNING VALUE. rover.gd turns
	# the turret with rotate_toward(..., deg_to_rad(turret_traverse_degrees) *
	# delta); at zero the call is a no-op every frame, so `Turret` stays bolted
	# to the hull and the frame can only aim by pointing itself. Raising this
	# gives the Lance a working turret and deletes the reason it exists.
	root_body.set("turret_traverse_degrees", 0.0)
	# NOT SET, DELIBERATELY: wheelbase, max_steer_degrees, drive_accel and the
	# rest of rover.gd's driving block keep their defaults. The design doc gives
	# no mobility figures beyond the speed, and guessing a turning circle for
	# the frame whose whole identity is agility is exactly the kind of number
	# that should be set by someone who can drive it.
	return root_body


## THE SPINE, AND IT IS NOT A HULL. 0.62 across, so the chamfered box reads as a
## beam with equipment hung off it rather than as an armoured body — which is
## the single thing keeping this frame from being read as a small Rover. Cut
## exactly as every other hull in the family is: sloped glacis, cut-back tail,
## bevels down both flanks.
func _spine(rig: Node3D) -> CSGMesh3D:
	var size := Vector3(0.62, 0.44, 1.40)
	var spine := _hull(rig, "Hull", size, Vector3(0, GROUND + 0.74, 0))
	_cut(spine, "Glacis", Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.8),
			Vector3(0, -size.y * 0.72, -size.z * 0.62), Vector3(-30.0 * DEG, 0, 0))
	_cut(spine, "Tail", Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.6),
			Vector3(0, -size.y * 0.68, size.z * 0.64), Vector3(20.0 * DEG, 0, 0))
	_bevel(spine, size, -1.0, "BevelL")
	_bevel(spine, size, 1.0, "BevelR")
	return spine


## ONE TOP-FLANK CHAMFER, in the family's own proportions rather than in
## numbers chosen by eye. Lifted off ConceptKit.hull, which lifted them off
## walker.tscn: a cut 70% of the width and 80% of the height, seated at 68% of
## the half-width and 66% of the half-height, turned 30 degrees. Used on the
## spine, the gun cradle and the ammo rack so all three chamfer the same way —
## a bevel sized by hand per piece is how a frame stops looking issued.
func _bevel(hull: CSGMesh3D, size: Vector3, s: float, nm: String) -> void:
	_cut(hull, nm, Vector3(size.x * 0.7, size.y * 0.8, size.z * 1.4),
			Vector3(s * size.x * 0.68, size.y * 0.66, 0),
			Vector3(0, 0, s * 30.0 * DEG))


## THE EXPOSED CROSS AXLE. The single clearest "no armour here" signal available
## and the thing that breaks the outline at the front — a bare beam straight
## across the nose with the drop links canted off it. Hide this behind a fender
## and the frame is a Rover again.
func _front_axle(rig: Node3D) -> void:
	_mesh(rig, "Axle", _cyl_mesh(0.055, 1.30),
			Vector3(0, GROUND + 0.44, -0.55), Vector3(0, 0, PI * 0.5))
	for s in [-1.0, 1.0]:
		# Canted, so it reads as suspension rather than as a post.
		_mesh(rig, "DropLink%s" % ("L" if s < 0.0 else "R"),
				_boxm(Vector3(0.09, 0.42, 0.12)),
				Vector3(s * 0.40, GROUND + 0.58, -0.55),
				Vector3(0, 0, s * 26.0 * DEG))


## THE SWING ARM. A positive X angle drops the +Z end, which is what puts the
## castor on the ground behind rather than in the air — the sign the concept
## file warns about twice.
func _tail(rig: Node3D) -> void:
	_mesh(rig, "SwingArm", _boxm(Vector3(0.14, 0.14, 0.80)),
			Vector3(0, GROUND + 0.50, 0.58), Vector3(14.0 * DEG, 0, 0))


## THE GUN IS THE NOSE, which is the turretless constraint made visible: bolted
## into a cradle on the spine's front face, on the centreline, where every other
## frame in the game has a ring.
##
##   GunMount   fixed. Where the gun is bolted. Never moves.
##   GunPivot   elevates, and nothing else. rover.gd pitches this between
##              gun_min_pitch_degrees and gun_max_pitch_degrees, so it starts at
##              zero where the aiming code expects to find it.
##
## Returns GunPivot, which is what rover.gd's export wants.
func _gun(rig: Node3D) -> Node3D:
	# The concept's cradle is a chamfered plate 0.34 x 0.30 x 0.42 whose FRONT
	# FACE is at z -0.68 (CSGPolygon3D extrudes along its own +Z), so the block
	# is centred at z -0.47. Rebuilt here as a box with its top corners taken
	# off, because a slab with square corners reads as a placeholder.
	var mount := _node(rig, "GunMount", Vector3(0, GROUND + 0.80, -0.47))
	var cradle_size := Vector3(0.34, 0.30, 0.42)
	var cradle := _hull(mount, "Cradle", cradle_size, Vector3.ZERO)
	_bevel(cradle, cradle_size, -1.0, "ChamferL")
	_bevel(cradle, cradle_size, 1.0, "ChamferR")
	var pivot := _node(mount, "GunPivot", Vector3.ZERO)
	# A cylinder stands along its own Y; +90 degrees about X lays it along Z, so
	# the barrel runs forward down -Z like every other muzzle in the game.
	_mesh(pivot, "Barrel", _cyl_mesh(0.085, 1.00), Vector3(0, 0, -0.58),
			Vector3(PI * 0.5, 0, 0))
	# THE MUZZLE BRAKE IS A CONE AND ITS APEX IS ITS +Y, so -90 degrees about X
	# is what puts the point FORWARD instead of back at the frame. The concept
	# file flags this one explicitly and it is worth repeating: built the other
	# way it is a funnel.
	var brake := _cyl_mesh(0.12, 0.20, 10)
	brake.top_radius = 0.0
	_mesh(pivot, "MuzzleBrake", brake, Vector3(0, 0, -1.09),
			Vector3(-PI * 0.5, 0, 0))
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the mount
	# has to turn that onto the body's -Z. Read off a matrix the two look like
	# the same quarter turn; they are not, and the Bulwark's first build had it
	# backwards — the gun fitted, elevated, tracked and fired directly behind
	# the frame, with nothing complaining, because a mount pointing the wrong
	# way is a perfectly valid transform.
	#
	# AT THE BREECH, 0.22 ahead of the pivot, which is where the Rover puts its
	# own (0.12 ahead of its GunPivot, at the mantlet): the frame provides the
	# mounting, the fitted weapon provides what sticks out of it.
	_node(pivot, "WeaponMount", Vector3(0, 0, -0.22), Vector3(0, PI * 0.5, 0))
	return pivot


## READY ROUNDS IN AN OPEN RACK on the starboard flank, standing OFF the spine
## so they are in the outline. Flush against it they would be invisible however
## big they were — the first rule in mockup_parts.gd's header, and the reason
## this frame has anything to look at besides wheels.
##
## The concept seats it at x 0.26 and lets the plate's extrusion carry it
## outboard to 0.44; a box has to be placed at the middle of that, so 0.35.
func _ammo_rack(rig: Node3D) -> void:
	var size := Vector3(0.18, 0.26, 0.46)
	var rack := _hull(rig, "AmmoRack", size, Vector3(0.35, GROUND + 0.80, 0.18))
	# The OUTBOARD top corner only, so it reads as a pressed bin rather than a
	# crate taped to the side. One side, not two: the inboard face is against
	# the spine and nothing can see it.
	_bevel(rack, size, 1.0, "Chamfer")
	# Bolt heads along the rack's outer face, which is what makes it look BOLTED
	# ON rather than floating a centimetre off the frame. Axis along X so the
	# heads face outboard, where the three-quarter view sees them, and at the
	# rack's mid-height where that face is still flat — the chamfer has taken
	# the top of it away.
	for i in 3:
		_mesh(rig, "RackStud%d" % i, _cyl_mesh(0.03, 0.042, 6),
				Vector3(0.44, GROUND + 0.80, -0.02 + 0.20 * float(i)),
				Vector3(0, 0, PI * 0.5))


## THE EYE, ON A STALK. With no turret ring the eye and the whip carry the whole
## family resemblance on their own, so the eye is lifted clear of both the gun
## and the ammo rack where nothing can cross it — the sixth rule in
## mockup_parts.gd, learned on the hats.
##
## Offset to PORT, because one eye off the centreline is this factory's single
## most recognisable feature and the cheapest thing to carry over.
func _head(rig: Node3D) -> Node3D:
	var head := _node(rig, "Head", Vector3(-0.26, GROUND + 0.92, -0.26))
	_mesh(head, "Stalk", _cyl_mesh(0.045, 0.28), Vector3(0, 0.14, 0))
	# ConceptKit.W_EYE_R scaled to 0.78, the concept's own figure: this frame's
	# eye is smaller than the Walker's because everything about it is.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.1326
	eye_mesh.height = 0.2175   # 0.82 of a sphere: the family's squash
	eye_mesh.radial_segments = 14
	eye_mesh.rings = 7
	# ITS OWN MATERIAL, not the shared metal, and left off the livery list: the
	# one feature that identifies a robot in this game must not change colour
	# per faction.
	var eye := _mesh(head, "Eye", eye_mesh, Vector3(0, 0.34, -0.04))
	eye.material_override = _eye_material()
	return head


## THREE CONTACT POINTS, WHICH NOTHING ELSE IN THE ROSTER HAS. Two big driven
## wheels on the exposed axle and one small one dragging behind.
##
## THE CASTOR IS SMALLER, NOT FURTHER AWAY. A trike with three equal wheels
## reads as a tricycle toy; the size difference is what makes it read as a
## driven pair and a trailer.
##
## Each wheel is a PIVOT with a child named "Spin" under it, and the tyre inside
## that. Not decoration: rover.gd steers the pivot about Y and rolls `Spin`
## about X by name — `w.get_node_or_null(^"Spin")` — so a tyre parented straight
## to the pivot would steer and never turn.
func _wheels(rig: Node3D) -> Array:
	var out: Array = []
	for s in [-1.0, 1.0]:
		out.append(_wheel(rig, "Wheel%s" % ("L" if s < 0.0 else "R"),
				Vector3(s * 0.66, GROUND + DRIVE_WHEEL_R, -0.55),
				DRIVE_WHEEL_R, DRIVE_WHEEL_W, 0.18))
	out.append(_wheel(rig, "WheelT", Vector3(0, GROUND + CASTOR_R, 0.88),
			CASTOR_R, CASTOR_W, 0.11))
	return out


func _wheel(rig: Node3D, nm: String, at: Vector3, r: float, w: float,
		hub_r: float) -> Node3D:
	var pivot := _node(rig, nm, at)
	var spin := _node(pivot, "Spin", Vector3.ZERO)
	# A cylinder stands along its own Y; a quarter turn about Z lays the axis
	# along X, which is the axle. Inside Spin, so rolling Spin about X turns it.
	var tyre := _mesh(spin, "Tyre", _cyl_mesh(r, w), Vector3.ZERO,
			Vector3(0, 0, PI * 0.5))
	tyre.material_override = _rubber
	# Five sides, so the hub reads as a wheel TURNING. A smooth disc at this
	# size animates as a disc that is not moving.
	var hub := _mesh(spin, "Hub", _cyl_mesh(hub_r, w * 1.08, 5), Vector3.ZERO,
			Vector3(0, 0, PI * 0.5))
	hub.material_override = _hub_metal
	return pivot


func _cyl_mesh(r: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object — see the duplicate() rule in
## CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m


## Rubber and bare steel, lifted off the Rover so the two frames' wheels are the
## same objects on screen.
func _plain(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m
