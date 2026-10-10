extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/bulwark.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_bulwark.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. This exists because a robot
# scene is thirty sub-resources with hand-numbered ids and an exact load_steps
# count that check.sh verifies, and writing that by hand is a transcription
# exercise with nothing to learn from. It is NOT a build step: re-running it
# after the scene has been touched in the editor would throw that work away,
# the way --force rebuilds have repeatedly cost this project its gameplay
# layers. If the geometry needs changing after today, change the scene.
#
# The proportions come straight from the BULWARK concept in tools/mockup_mech.gd
# and the part vocabulary from the Walker, so the three stay in family.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/bulwark.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
const BODY_SCRIPT := "res://Character/characters/ai/bulwark.gd"
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__23.wav"

const DEG := PI / 180.0
## The Walker's eye is a plain StandardMaterial3D with this as its albedo —
## not the shared faction metal. Carried over verbatim so the two frames' eyes
## are the same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

var _metal: Material


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_bulwark: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_bulwark: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_bulwark: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A mesh piece. Everything visible on the frame goes through here so nothing
## can be left without the shared metal material — a single unpainted piece is
## the kind of thing that only shows up in a faction colour nobody tested.
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


## A CSG box used as a CUT. Subtractions are how the Walker gets its sloped
## glacis and chamfered shoulders, and reusing them is most of why this reads
## as the same factory.
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
func _hull(parent: Node, nm: String, size: Vector3, at: Vector3) -> CSGMesh3D:
	var h := CSGMesh3D.new()
	h.name = nm
	h.mesh = _boxm(size)
	h.position = at
	h.material = _metal
	parent.add_child(h)
	h.owner = _root
	return h


var _root: CharacterBody3D


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Bulwark"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's
	# second argument defaults to false, which means "for this run only" — the
	# first build packed a frame with no groups line, and a robot outside
	# "enemies" is invisible to AIManager, to EMP and to every hostile sweep in
	# the game while still walking around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision and senses ──
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	# Wider and shorter than the Walker's 0.85 x 3.0: this frame is broader
	# across the shoulders and stands lower.
	cap.radius = 0.95
	cap.height = 2.7
	col.shape = cap
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, or the assignment is silently dropped. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three default clips. This line was untyped for the Bulwark's
	# whole life and bulwark.tscn shipped with WAV_RDV__2/5/98 — the defaults —
	# instead of the 17/23 named above. Nobody noticed because it still barks.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	bark.set("pitch_min", 0.64)
	bark.set("pitch_max", 0.72)
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

	# PELVIS. Lower than the Walker's hull and wider, because the torso above
	# it carries the shield and the whole thing has to look like it would not
	# tip over.
	var pelvis := _hull(rig, "Hull", Vector3(1.85, 1.0, 1.5), Vector3(0, 0.1, 0))
	_cut(pelvis, "Glacis", Vector3(2.6, 1.2, 1.2), Vector3(0, -0.72, -0.9), Vector3(-30.0 * DEG, 0, 0))
	_cut(pelvis, "Tail", Vector3(2.6, 1.2, 0.9), Vector3(0, -0.68, 0.95), Vector3(20.0 * DEG, 0, 0))
	for s in [-1.0, 1.0]:
		_cut(pelvis, "Bevel%s" % ("L" if s < 0.0 else "R"),
				Vector3(1.3, 0.8, 2.1), Vector3(s * 1.26, 0.6, 0),
				Vector3(0, 0, s * 30.0 * DEG))

	_mesh(rig, "TurretRing", _ring_mesh(0.56, 0.12), Vector3(0, 0.62, 0))

	# ── TORSO: this is `turret`. See the note in bulwark.gd. ──
	# Plain shoulders and chest. The turret-SHAPED part is the head above it;
	# this is the box the arms hang off.
	var torso := _node(rig, "Torso", Vector3(0, 0.76, 0))
	var torso_body := _hull(torso, "TorsoBody", Vector3(1.66, 1.0, 1.25), Vector3.ZERO)
	for s in [-1.0, 1.0]:
		_cut(torso_body, "Shoulder%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.9, 0.7, 1.8), Vector3(s * 1.08, 0.62, 0),
				Vector3(0, 0, s * 32.0 * DEG))
	_cut(torso_body, "Chest", Vector3(1.9, 0.6, 0.6), Vector3(0, -0.54, -0.78),
			Vector3(-32.0 * DEG, 0, 0))

	# ── HEAD ──
	#
	# A TURRET-SHAPED HEAD, not a head turret. It does not rotate on its own —
	# the whole torso traverses and this rides it — but it carries the Walker's
	# turret silhouette exactly: a box with the cheek sliced off below and the
	# brow sliced off above, sat on a ring. That profile plus one offset eye is
	# how a frame in this game is recognised at forty pixels, and the first
	# build had neither because the eye was stuck straight onto the chest.
	_mesh(torso, "NeckRing", _ring_mesh(0.42, 0.1), Vector3(0, 0.52, -0.04))
	var head := _node(torso, "Head", Vector3(0, 0.84, -0.06))
	var head_body := _hull(head, "HeadBody", Vector3(1.0, 0.58, 0.92), Vector3.ZERO)
	_cut(head_body, "Cheek", Vector3(1.4, 0.5, 0.5), Vector3(0, -0.34, -0.6), Vector3(-35.0 * DEG, 0, 0))
	_cut(head_body, "Brow", Vector3(1.4, 0.5, 0.5), Vector3(0, 0.38, -0.54), Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, offset left, and the WALKER'S OWN material rather than the
	# shared metal — a StandardMaterial3D with the white tile texture as
	# albedo. Painting it with faction livery like everything else would make
	# the one feature that identifies a robot in this game change colour per
	# faction, so it is deliberately left out of the livery list below.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.17
	eye_mesh.height = 0.28
	eye_mesh.radial_segments = 16
	eye_mesh.rings = 8
	var eye := _mesh(head, "Eye", eye_mesh, Vector3(-0.26, 0.04, -0.44))
	eye.material_override = _eye_material()

	# Same whip as the Walker's, off the back corner of the head.
	_mesh(head, "Antenna", _boxm(Vector3(0.03, 0.85, 0.03)), Vector3(-0.36, 0.7, 0.3))

	_arm_shield(torso)
	_arm_gun(torso)
	_legs(rig)

	# ── effects, livery, rank ──
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
	# EVERY PAINTED PIECE, and the shield most of all: an unpainted tower
	# shield is the largest flat surface on the frame and would read as a
	# different faction's kit bolted on.
	# Node objects, in a TYPED array. pieces is Array[Node3D]; an untyped one
	# lands as [] and FactionLivery then falls back to walking its whole
	# parent — which paints every mesh on the frame, the EYE INCLUDED. That is
	# how the eye ended up faction-coloured despite being left off this list:
	# the list itself was never there.
	#
	# THE EYE IS DELIBERATELY ABSENT. It keeps its own StandardMaterial3D, the
	# Walker's, because the one feature that identifies a robot in this game
	# must not change colour per faction.
	var paint: Array[Node3D] = []
	paint.append(pelvis)
	paint.append(rig.get_node("TurretRing"))
	paint.append(torso_body)
	paint.append(head_body)
	paint.append(torso.get_node("NeckRing"))
	paint.append(head.get_node("Antenna"))
	paint.append(torso.get_node("ShoulderL/ShoulderCapL"))
	paint.append(torso.get_node("ShoulderL/UpperArmL"))
	paint.append(torso.get_node("ShoulderL/ElbowL/ElbowCapL"))
	paint.append(torso.get_node("ShoulderL/ElbowL/ForearmL"))
	paint.append(torso.get_node("ShoulderL/ElbowL/ShieldMount/Shield"))
	paint.append(torso.get_node("ShoulderL/ElbowL/ShieldMount/ShieldBossL"))
	paint.append(torso.get_node("ShoulderR/ArmYaw/ShoulderCapR"))
	paint.append(torso.get_node("ShoulderR/ArmYaw/UpperArmR"))
	paint.append(torso.get_node("ShoulderR/ArmYaw/GunPivot/ElbowCapR"))
	paint.append(torso.get_node("ShoulderR/ArmYaw/GunPivot/ForearmR"))
	paint.append(torso.get_node("ShoulderR/ArmYaw/GunPivot/MantletR"))
	paint.append(rig.get_node("HipL"))
	paint.append(rig.get_node("HipR"))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D or Array[Node3D] — not NodePath — so assigning a NodePath to them
	# silently does nothing and the frame comes out with a null turret, a null
	# shield and legs the gait cannot find. Nothing errors; the first build did
	# exactly that and only the test caught it. PackedScene.pack() turns these
	# references back into the `node_paths=PackedStringArray(...)` form the
	# editor writes, so the saved scene looks hand-authored either way.
	root_body.set("rig", rig)
	root_body.set("hip_left", rig.get_node("HipL"))
	root_body.set("knee_left", rig.get_node("HipL/KneeL"))
	root_body.set("hip_right", rig.get_node("HipR"))
	root_body.set("knee_right", rig.get_node("HipR/KneeR"))
	root_body.set("foot_left", rig.get_node("HipL/KneeL/FootL"))
	root_body.set("foot_right", rig.get_node("HipR/KneeR/FootR"))
	root_body.set("turret", torso)
	root_body.set("gun_pivot", torso.get_node("ShoulderR/ArmYaw/GunPivot"))
	root_body.set("weapon_mount", torso.get_node("ShoulderR/ArmYaw/GunPivot/WeaponMount"))
	root_body.set("arm_yaw", torso.get_node("ShoulderR/ArmYaw"))
	root_body.set("shoulder_shield", torso.get_node("ShoulderL"))
	root_body.set("shield", torso.get_node("ShoulderL/ElbowL/ShieldMount/Shield"))
	root_body.set("head", head)
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY.
	#
	# particle_effects_die is Array[ParticleEffect] and visible_pieces is
	# Array[Node3D]. Assigning a plain untyped Array to either one fails
	# SILENTLY — no error, no warning, and the packed scene comes out with
	# `visible_pieces = []`. The first build shipped all four of these empty:
	# no death effects, no hit sparks, and — because FactionLivery falls back
	# to walking its entire parent when `pieces` is empty — a frame that
	# painted every mesh on itself including the eye.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	var vis: Array[Node3D] = []
	vis.append(pelvis)
	vis.append(torso_body)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	root_body.set("activation_distance", 200)
	root_body.set("health", 400)
	root_body.set("max_health", 400)
	# Slower than the Walker's 4.16. It is pushing a wall.
	root_body.set("move_speed", 3.3)
	root_body.set("soldier_name", "Bulwark")
	root_body.set("flatten_collider_when_downed", false)
	# THE WHOLE POINT, and it lives here rather than on ChassisDefinition
	# because that resource has no signal field — see AI.signal_resistance.
	# Divides incoming suppression AND the length of an EMP lock.
	root_body.set("signal_resistance", 2.4)
	# A turret traverse slower than the Walker's 55: flanking a Bulwark is the
	# counter, and it should be a real one.
	root_body.set("turret_traverse_degrees", 42.0)
	return root_body


## The shield arm. Braced across the body, shield carried on the forearm.
func _arm_shield(torso: Node3D) -> void:
	# NO OUTWARD TILT ON THIS SHOULDER. A Z rotation here is inherited by
	# everything below it, including the shield, and 14 degrees of it left the
	# plate leaning like a dropped door. The arm reaches ACROSS instead, which
	# is what a tower shield is carried like anyway.
	# ARMS THE SIZE OF THE LEGS. The first build gave this frame limbs thinner
	# than its own thighs, which read as a heavy mech wearing somebody else's
	# arms. A thigh here is 0.42 x 0.70 x 0.48; an upper arm has no business
	# being smaller than that on a chassis whose job is carrying a wall.
	var sh := _node(torso, "ShoulderL", Vector3(-1.0, 0.22, -0.1), Vector3(-8.0 * DEG, 0, 0))
	_mesh(sh, "ShoulderCapL", _sphere_mesh(0.4), Vector3.ZERO)
	_mesh(sh, "UpperArmL", _boxm(Vector3(0.58, 0.82, 0.58)), Vector3(0, -0.41, 0))
	var el := _node(sh, "ElbowL", Vector3(0, -0.82, 0), Vector3(80.0 * DEG, 0, 0))
	_mesh(el, "ElbowCapL", _sphere_mesh(0.31), Vector3.ZERO)
	_mesh(el, "ForearmL", _boxm(Vector3(0.5, 0.8, 0.5)), Vector3(0, -0.4, 0))
	# THE SHIELD STANDS BACK UP. It hangs off a forearm that has already been
	# rotated 80 degrees by the elbow, so built straight in it would lie flat —
	# a paddle held out sideways rather than a wall held in front. This is the
	# same correction the concept pass needed, kept because the cause is the
	# same and so is the mistake waiting to be made again.
	# INBOARD, so the plate crosses the centreline. A shield that only covers
	# the arm carrying it is a vambrace. X is unchanged by the elbow's rotation
	# about X, so shifting +x here moves it toward the body in world space too.
	var mount := _node(el, "ShieldMount", Vector3(0.32, -0.72, 0), Vector3(-80.0 * DEG, 0, 0))
	var shield := _hull(mount, "Shield", Vector3(1.55, 2.2, 0.18), Vector3(0, -0.28, -0.46))
	# A vision slot, which is what makes it read as a shield rather than a door.
	_cut(shield, "Slot", Vector3(0.64, 0.13, 0.5), Vector3(-0.12, 0.66, 0.0))
	_mesh(mount, "ShieldBossL", _sphere_mesh(0.2), Vector3(0, -0.36, -0.56))
	_shield_blocker(mount)


## The weapon arm, built as a REAL ARM with two joints.
##
##   ShoulderR   position only — where the limb hangs off the torso
##   ArmYaw      swings the WHOLE limb left and right. This is the joint that
##               lets the gun track a target while the shield keeps facing
##               somewhere else, which is the frame's defining ability.
##   GunPivot    the elbow. Pitches the forearm and the gun.
##
## The upper arm is parented to ArmYaw and not to ShoulderR on purpose: a
## shoulder that yaws without taking the limb with it is a forearm swinging off
## a static stump, which is worse than no yaw at all.
func _arm_gun(torso: Node3D) -> void:
	var sh := _node(torso, "ShoulderR", Vector3(0.98, 0.24, 0.04))
	var yaw := _node(sh, "ArmYaw", Vector3.ZERO)
	_mesh(yaw, "ShoulderCapR", _sphere_mesh(0.38), Vector3.ZERO)
	_mesh(yaw, "UpperArmR", _boxm(Vector3(0.56, 0.84, 0.56)), Vector3(0, -0.42, 0))
	# The pivot sits AT the elbow and pitches: Walker clamps it between
	# gun_min_pitch_degrees and gun_max_pitch_degrees, so a rest pose of 74
	# degrees would be clamped straight back to level. The arm's forward break
	# is therefore built into the forearm's own offset instead, and the pivot
	# starts at zero where the aiming code expects it.
	var pivot := _node(yaw, "GunPivot", Vector3(0, -0.84, 0))
	_mesh(pivot, "ElbowCapR", _sphere_mesh(0.3), Vector3.ZERO)
	_mesh(pivot, "ForearmR", _boxm(Vector3(0.5, 0.52, 1.2)), Vector3(0, -0.06, -0.5))
	_mesh(pivot, "MantletR", _boxm(Vector3(0.62, 0.54, 0.34)), Vector3(0, -0.04, -1.08))
	# Muzzle forward along -Z, matching the Walker's WeaponMount basis so a
	# weapon scene fitted here points the same way it would on any other frame.
	#
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X, and the
	# mount has to turn that onto the body's -Z. Read off the Walker's matrix
	# the yaw looks like a quarter turn either way; it is not, and the first
	# build had it backwards — the gun fitted, elevated, tracked targets and
	# fired directly behind the frame. Nothing warns, because a mount pointing
	# the wrong way is a perfectly valid transform.
	var wm := _node(pivot, "WeaponMount", Vector3(0, -0.04, -1.26), Vector3(0, PI * 0.5, 0))
	wm.name = "WeaponMount"


func _legs(rig: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		var hip := _node(rig, "Hip%s" % tag, Vector3(s * 0.56, -0.26, 0), Vector3(0, 0, s * 6.0 * DEG))
		_mesh(hip, "HipCap%s" % tag, _boxm(Vector3(0.36, 0.36, 0.4)), Vector3.ZERO)
		_mesh(hip, "Thigh%s" % tag, _boxm(Vector3(0.42, 0.7, 0.48)),
				Vector3(0, -0.3, 0.13), Vector3(15.0 * DEG, 0, 0))
		var knee := _node(hip, "Knee%s" % tag, Vector3(0, -0.58, 0.26))
		_mesh(knee, "Shin%s" % tag, _boxm(Vector3(0.32, 0.78, 0.36)),
				Vector3(0, -0.35, -0.15), Vector3(-15.0 * DEG, 0, 0))
		_mesh(knee, "Foot%s" % tag, _boxm(Vector3(0.48, 0.17, 0.95)),
				Vector3(0, -0.72, -0.42))


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
	return c


## The eye's own material. Built fresh per call rather than shared, because a
## material handed to two frames is one object and this project has already
## paid for that once — see the duplicate() rule in CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m


## THE SHIELD HAS TO STOP ROUNDS, and on its own it stopped nothing.
##
## Measured before this existed: a shot at the shield's centre passed straight
## through the plate and hit the body capsule behind it, and a shot at the
## plate's outer half — which sticks out past the 0.95 m capsule — hit nothing
## at all and carried on into the distance. The wall was decoration.
##
## IT FOLLOWS BY PARENTING, NOT BY CODE. A CharacterBody3D only collects
## CollisionShape3D nodes that are its DIRECT children, so a shape on the body
## cannot ride a plate that hangs four levels down on a limb that yaws, pitches
## and swings with the gait. Repositioning one every physics frame was the
## obvious answer and it is strictly worse than hanging a body off the mount
## itself, which costs no per-frame work and cannot drift out of sync.
##
## AnimatableBody3D rather than StaticBody3D because that is precisely what it
## is for: a static body that something else moves.
##
## LAYER 10, WHICH NOTHING ELSE USES. This is what makes it block ROUNDS AND
## NOTHING ELSE, which is the whole requirement:
##
##   weapon raycasts    _one_round sets no collision_mask, so it tests every
##                      layer and therefore hits this        -> blocked
##   walking            robots move with mask 1               -> ignored, so
##                      the plate cannot shove a squadmate or jam a doorway
##   melee / near-miss  AIWeapon.character_mask is 1|2|4|8    -> ignored
##   navigation         navmesh, not physics                  -> unaffected
##
## It has no mask of its own: it is a thing to be hit, and it collides with
## nothing itself.
const SHIELD_LAYER := 1 << 9


func _shield_blocker(mount: Node3D) -> void:
	var body := AnimatableBody3D.new()
	body.name = "ShieldBlocker"
	body.sync_to_physics = false
	body.collision_layer = SHIELD_LAYER
	body.collision_mask = 0
	mount.add_child(body)
	body.owner = _root
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	# Matches the plate, a little thinner so the visible edge is the one that
	# stops things rather than a centimetre of air around it.
	box.size = Vector3(1.5, 2.15, 0.14)
	col.shape = box
	col.position = Vector3(0, -0.28, -0.46)
	body.add_child(col)
	col.owner = _root
