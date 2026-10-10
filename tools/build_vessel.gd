extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/vessel.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_vessel.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. This is not a build step:
# re-running it over a scene that has been touched in the editor throws that
# work away, which is how force-rebuilds have repeatedly cost this project its
# gameplay layers. If the geometry needs changing after today, change the scene.
# It exists only because a robot scene is thirty sub-resources with hand-
# numbered ids and an exact load_steps count, and writing that by hand is
# transcription with nothing to learn from.
#
# ─────────────────────────────────────────────
# WHERE THE SHAPE COMES FROM
#
# CONCEPT A, BAY DOORS, already built in code as ConceptsB.vessel_a()
# (tools/concepts_b.gd) out of the shared vocabulary in tools/concept_kit.gd.
# That function is the authority on proportions and positions. Every rig-level
# number below is written as the CONCEPT'S OWN coordinate and passed through
# _a(), so the two files can be read line against line.
#
# What this adds is everything a concept sheet does not need: a collision
# capsule, a rig whose wheels rover.gd can drive, a traversing turret, the
# shared robot_metal material on every piece, a livery list with the eye left
# off it, a weapon mount, and a bay whose doors and cargo are separately named
# so a behaviour script can move and hide them.
#
# ─────────────────────────────────────────────
# WHAT CHANGED FROM THE CONCEPT, AND WHY — all five measured, not guessed
#
# The concept was instantiated and every child's world AABB printed before a
# line of this was written. Five things came back wrong, and four of them are
# the same root cause:
#
# **CSGPolygon3D EXTRUDES ALONG ITS OWN −Z, NOT +Z.** Measured: a unit polygon
# with depth 2.0 at the origin occupies z −2.0..0.0. Two comments in this repo
# say +Z — tools/build_lance.gd:521 and the _hatchling() note in
# tools/concepts_b.gd — and both are wrong. Every `plate()` and `wedge()` in the
# Vessel concept therefore extrudes the opposite way from what its author
# intended, which produced:
#
#   1. CRADLES FLOATING, AND THE DRONES BELOW THEM. The cradle plate was placed
#      at concept y 1.90 with depth 0.12 meaning to fill 1.78..1.90 under a
#      drone whose skids end at 1.84. It actually filled 1.90..2.02 — above the
#      skids entirely, so the drone hung THROUGH its own cradle and the cradle
#      floated 0.25 m over the bay floor. Rebuilt as a deck: bottom on the bay
#      floor at 1.65, depth 0.19, top at 1.84 where the skids now rest.
#
#   2. THE DRONE BODY ABOVE ITS OWN ROTORS. Same cause. concepts_b's comment
#      says the body is "placed at the top of its own thickness so it hangs
#      under the rotors"; measured it sat at y 2.18..2.38 with the rotor hubs at
#      2.15..2.33, so the rotors were buried in the body and the body floated
#      0.20 m above the skids. Fixed by rotating the body plate −90 about X
#      instead of +90, which sends the extrusion down and lands it exactly where
#      the comment says it should be: 1.98..2.18, bottom on the skid tops.
#
#   3. ONE STOWAGE CHOCK THROUGH THE DRONE. Both chocks extruded toward −X, so
#      the port one ran outboard correctly (x −0.80..−0.30) and the starboard
#      one ran INBOARD across the drone's centreline (x −0.20..0.30). The
#      mirroring is now in the yaw — euler.y = −s * PI/2 — so each extrudes away
#      from the bay centre and neither crosses its cargo.
#
#   4. THE TWO DOOR LEAVES WERE DIFFERENT SHAPES. Both carried euler
#      (0, PI/2, 0), so the 0.1 m of thickness went outboard on one leaf and
#      inboard on the other: port reached x 1.774 and y 2.908, starboard only
#      1.743 and 2.813. The doors are rebuilt from scratch (see below) and are
#      now mirror images.
#
# **AND THE TURRET RING WAS INSIDE THE TURRET.** The fault the brief warns
# about, confirmed on this frame: ConceptKit.head() puts the ring at `at` and
# the turret body at `at + 0.19 * scale`, and at scale 0.58 the ring measured
# y 1.665..1.735 inside a body of 1.636..1.984. Six buried faces. MOVED, not
# dropped, to where vehicle_rover.tscn puts its own: seated on the hull's top
# face (1.650..1.720) with the turret body resting ON it, which raises the
# turret 0.084 m above the concept's figure. That is the only part of the
# silhouette this changes and it is the arrangement both shipping vehicles use.
#
# ─────────────────────────────────────────────
# THE DOORS — REBUILT, BECAUSE THE CONCEPT'S CANNOT CLOSE
#
# The doors are this frame's whole proposition: VESSEL.md §1 picked A over three
# other options because "doors open is a universally legible statement about
# what a vehicle is for", and because open and closed are two silhouettes, so
# the state the player cares about is the state they can see.
#
# The concept's leaves are centred ON their hinge axis and offset 0.55 m out
# along it, so rotating the hinge back to zero does not close them — it swings
# each leaf down into a vertical wall standing outboard of the hull at x 1.6.
# There is no angle at which that rig is a roof. A future vessel.gd animating
# `rotation.z` would therefore have had nothing to animate toward.
#
# So the hinge moves to the OUTER EDGE, which is what a bay door is hinged on:
#
#   DoorL / DoorR   Node3D on the coaming's outer top rail, rotation.z only.
#   +- Leaf         2.45 long, 1.075 across, 0.1 thick, extending INBOARD so
#                   that at rotation.z = 0 the two leaves lie flat across the
#                   coaming and MEET ON THE CENTRELINE. That is the closed roof.
#
# TO CLOSE, ROTATE EACH DOOR'S LOCAL Z TO ZERO: DoorL from +130 degrees and
# DoorR from −130 degrees, 130 degrees of travel each. Nothing else moves. The
# leaves are built AT 130 degrees — open — because the brief asks for open and
# because a carrier only ever closes for a reason.
#
# WHY 130 AND NOT 72. The concept's 72 degrees is measured on a hinge in a
# different place, so the number does not transfer; what transfers is the
# ENVELOPE, because that envelope is the box quoted in VESSEL.md §1. With the
# leaf on its outer edge, half-width = 1.075 * (1 + sin b) and the top =
# 1.43 + 1.075 * cos b + 0.1 * sin b, for b degrees past vertical. b = 40
# (rotation.z = 130) puts the frame at 3.53 m wide against the doc's 3.52 — and
# width is the measurement that decides whether this thing fits through a gate,
# which §1 already flagged as the cost that sank concept C. Height comes out
# 0.13 m over the doc's figure and is reported rather than tuned, because no
# single angle hits both.
#
# ─────────────────────────────────────────────
# THE BAY SHIPS LOADED
#
# VESSEL.md §5 is explicit that the carried drones' presence has to be legible
# and §1 that it has to read FROM ABOVE, because the player commands from a
# height. Both carried Hatchlings are therefore BUILT, as `Bay/CargoA` and
# `Bay/CargoB` — two Node3Ds, each with its own geometry under it, so a future
# vessel.gd hides one node per release and the cradle under it stays. A bay that
# looks identical loaded and spent is a bay whose state cannot be read, and §5
# calls two hideable meshes "the cheap version and enough".
#
# They sit low enough to be inside the coaming and high enough that the rotor
# blades clear its rim by 0.12 m, which is what makes the cargo visible in a
# three-quarter view from above rather than only from the side.
#
# THE CARGO IS GEOMETRY, NOT A DRONE. It is not an instance of diver.tscn: that
# would put a second CharacterBody3D in the "enemies" group inside this one, and
# release is behaviour, which this pass does not write.
#
# ─────────────────────────────────────────────
# WHEELED, AND WHAT rover.gd ACTUALLY WANTS
#
# VESSEL.md §1 overrides §3's table: `drives` is true and the selected hull is a
# six-wheeler. Root script is therefore rover.gd, and its contract was read off
# the script rather than off the brief's table:
#
#   * `wheels` is Array[Node3D] and EACH ENTRY NEEDS A CHILD NAMED "Spin".
#     rover.gd:191 caches `w.get_node_or_null(^"Spin")` and rolls that; the
#     wheel node itself takes the STEER angle as `rotation.y`, absolutely, so it
#     must be authored at zero rotation and the 90 degrees that lays a cylinder
#     on its side lives on the tyre mesh instead.
#   * `wheel_steer` is Array[float] in the SAME ORDER, and rover.gd:195 warns
#     if the two sizes differ. Order is FL, FR, ML, MR, RL, RR with
#     [1, 1, 0, 0, −1, −1] — front steers, middle fixed, rear counter-steers,
#     which is what makes `wheelbase` mean "front axle to middle axle".
#   * THE WHEELS MUST BE DIRECT CHILDREN OF Rig, AND Rig MUST BE AT IDENTITY.
#     rover.gd caches each wheel's `position` and then raycasts from
#     `global_transform * _wheel_rest[i]` — the BODY's transform, not the rig's.
#     A rig with an offset, or wheels nested one level deeper, puts every
#     suspension ray in the wrong place and nothing says so.
#   * `wheel_radius` IS SET, to 0.58. It is the divisor for wheel spin and the
#     length of the suspension ray, and it defaults to 0.36.
#     vehicle_rover.tscn never overrides it although it draws a 0.54 tyre, so
#     the Rover's wheels have always spun 1.5x too fast; that scene is not this
#     pass's to change and is reported instead.
#   * `reverse_lamps` is Array[Node3D] and rover.gd shows them below −0.3 m/s,
#     so they are authored hidden.
#   * `turret` is REAL here. VESSEL.md §3 has turret = true and the concept has
#     a turret, so unlike the Lance this is a genuine traverse and not a stub.
#     enemy.gd also reads the PROPERTY to decide `hull_spoils_aim`, so a null
#     one would leave the frame unable to fire while it drives.
#
# Turret, GunPivot and WeaponMount are arranged as vehicle_rover.tscn arranges
# them — ring on the hull, body on the ring, pivot inside the body's front face,
# mantlet straddling it, mount just inside the mantlet's front face — with the
# offsets taken from the Walker's own turret space scaled by the concept's 0.58.
#
# WeaponMount carries yaw +PI/2 AND NOTHING ELSE. +90, not −90: a weapon's
# muzzle runs down its own +X and the mount has to turn that onto the body's
# −Z. Built the other way the gun fits, elevates, tracks and fires directly
# behind the frame, and nothing complains.
#
# NO MODELLED BARREL. The concept draws one because nothing is fitted to a
# concept; shipping frames do not — the Walker, the Bulwark and the Rover all
# carry a Mantlet, a mount and no barrel, and the gun is the weapon scene. The
# concept's 0.87 m stub is the single reason its measured length is 4.72 m, so
# dropping it takes the box to 4.00 and that is reported, not hidden.
#
# ─────────────────────────────────────────────
# THE ORIGIN CONVENTION — read this before moving anything
#
# The concept draws the frame with its ground at y 0, but its wheel centres at
# y 0.30 under a 0.58 m radius, so the tyres hang 0.28 m BELOW that plane. A
# scene cannot keep that: a CharacterBody3D floats with its collider's lowest
# point on the floor, so the art has to be placed against the collider.
#
# So DATUM = 0.72: scene y = concept y − 0.72. That puts the origin 1.00 m above
# the tyre contact patch, which is exactly the radius of the collision capsule,
# so the capsule's bottom and the bottoms of all six tyres are the same plane
# and the frame sits on its wheels. Both shipping ground frames get this wrong
# by 0.18–0.30 m in the other direction (the Rover's tyres and the Bulwark's
# feet both end up under its collider); this one is measured.
#
# ─────────────────────────────────────────────
# WHAT THIS PASS DOES NOT DO
#
# No chassis .tres, no catalogue entry, no vessel.gd, no edits to rover.gd or
# enemy.gd. The model exists and the stats do not, which is the deliberate
# half-finished state FRAME_MODELS.md §1 describes. Nothing was registered.
#
# The two `Cannot assign contents of "Array[Object]" to "Array[int]"` errors
# this scene prints on load are the family's known .tscn-writer bug on
# Enemy.AllowedMovementOptions / AllowedCombatOptions. FRAME_MODELS.md §5 says
# to leave them alone, so they are left alone — see the report.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/vessel.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
const BODY_SCRIPT := "res://Character/characters/ai/rover.gd"
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__24.wav"

const DEG := PI / 180.0
## The Walker's eye: a plain StandardMaterial3D with this as albedo, not the
## shared faction metal. Carried over verbatim so every eye in the game is the
## same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

## See THE ORIGIN CONVENTION above. Concept y minus this is scene y.
const DATUM := 0.72
## ConceptKit.head() is drawn at this scale on this frame, and the Walker's own
## turret offsets are scaled by it below.
const HEAD_SCALE := 0.58
## Tyre radius and width, straight off K.wheel() in the concept.
const TYRE_R := 0.58
const TYRE_W := 0.34
## Half-width of the coaming, which is both the hinge line and the length of a
## door leaf — closed, the two leaves meet on the centreline.
const LEAF := 1.075
## How far past vertical each leaf leans when open. See THE DOORS above for why
## this number and not the concept's 72.
const DOOR_OPEN := 130.0

var _metal: Material
var _root: CharacterBody3D


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_vessel: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_vessel: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_vessel: wrote %s" % OUT)
	quit(0)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A concept-space position, in scene space. Every rig-level number in _build()
## goes through here, so the figures can be read straight off vessel_a().
func _a(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y - DATUM, z)


## A mesh piece. Everything visible goes through here so nothing can be left
## without the shared metal material — a single unpainted piece is the kind of
## bug that only shows up once someone renders the frame in a faction colour.
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


## A CSG box used as a CUT. Subtractions are how the hull gets its sloped glacis
## and chamfered flanks, and reusing them is most of why this reads as the same
## factory as the Walker.
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


## A chamfered slab: mockup_parts.plate(). There is no mesh primitive for it, so
## this is CSG — a root of its own, baked like the hulls.
##
## IT EXTRUDES ALONG ITS OWN −Z, measured, not assumed. Every offset below that
## depends on the thickness depends on this; see WHAT CHANGED FROM THE CONCEPT.
func _plate(parent: Node, nm: String, w: float, h: float, depth: float,
		bevel: float, at: Vector3, euler: Vector3 = Vector3.ZERO) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	p.name = nm
	var x := w * 0.5
	var y := h * 0.5
	var b: float = minf(bevel, minf(x, y) * 0.9)
	p.polygon = PackedVector2Array([
		Vector2(-x + b, -y), Vector2(x - b, -y), Vector2(x, -y + b), Vector2(x, y - b),
		Vector2(x - b, y), Vector2(-x + b, y), Vector2(-x, y - b), Vector2(-x, -y + b)])
	p.depth = depth
	p.position = at
	p.rotation = euler
	p.material = _metal
	parent.add_child(p)
	p.owner = _root
	return p


## A slab that tapers: mockup_parts.wedge(). Used for the stowage chocks, where
## the taper is what makes a block read as SHAPED to hold something.
func _wedge(parent: Node, nm: String, w: float, h: float, depth: float,
		taper: float, at: Vector3, euler: Vector3 = Vector3.ZERO) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	p.name = nm
	var x := w * 0.5
	var y := h * 0.5
	p.polygon = PackedVector2Array([
		Vector2(-x, -y), Vector2(x, -y + taper), Vector2(x, y - taper), Vector2(-x, y)])
	p.depth = depth
	p.position = at
	p.rotation = euler
	p.material = _metal
	parent.add_child(p)
	p.owner = _root
	return p


## Bolt heads in a row — what makes a panel look BOLTED ON rather than floating.
##
## mockup_parts.studs() hardcodes euler (PI/2, 0, 0), which points the heads
## along Z. That is right for a plate lying in XY and wrong for a door leaf
## whose face normal is its own Y, so the axis is a parameter here. The concept's
## own four studs measured out at y 2.343..2.428 against a leaf starting at
## 2.473 — a row of bolts hanging in the air under the door — because the same
## assumption was never checked.
func _studs(parent: Node, count: int, from: Vector3, step: Vector3,
		radius: float, euler: Vector3 = Vector3.ZERO) -> void:
	for i in count:
		_mesh(parent, "Stud%d" % i, _cylm(radius, radius * 1.4, 6),
				from + step * float(i), euler)


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cylm(r: float, h: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 0
	return c


func _spherem(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Vessel"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's second
	# argument defaults to false, which means "for this run only" — the Bulwark's
	# first build packed a frame with no groups line, and a robot outside
	# "enemies" is invisible to AIManager, to EMP and to every hostile sweep in
	# the game while still driving around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))
	# The Rover's own floor settings. A vehicle on a kinematic body needs the
	# constant speed and the snap or it skates off crests.
	root_body.floor_constant_speed = true
	root_body.floor_max_angle = 0.872665
	root_body.floor_snap_length = 0.4

	# ── collision and senses ──
	#
	# A CAPSULE LAID ALONG Z, which is how vehicle_rover.tscn does it, and sized
	# to the ART rather than guessed: radius 1.00 is the distance from the origin
	# to the tyre contact patch under the datum above, so the collider's bottom
	# and the wheels' bottoms are one plane. Height 4.00 is the hull's own
	# length, so the collider ends where the bodywork does instead of 0.2 m past
	# it the way the Rover's does.
	#
	# VESSEL.md §5 asks for "larger than the Walker's r 0.85 h 3.0" and this is
	# the biggest collider on any frame in the game.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 1.0
	cap.height = 4.0
	col.shape = cap
	col.rotation = Vector3(PI * 0.5, 0, 0)
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, OR THE ASSIGNMENT IS DISCARDED. bark_clips is Array[AudioStream];
	# handing it a plain Array fails silently and the instance keeps bark.tscn's
	# three defaults. bulwark.tscn is the proof — its generator names two clips
	# and the saved scene carries three. Same trap as visible_pieces, different
	# property, different node.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# Between the Bulwark's 0.64 and the Rover's 0.80: the biggest hull in the
	# game, but a carrier rather than the thing pushing a wall.
	bark.set("pitch_min", 0.70)
	bark.set("pitch_max", 0.78)
	root_body.add_child(bark)
	bark.owner = root_body

	var nav := NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	# The Rover's path tolerances, with the radius and height taken from this
	# frame's real size. Both are avoidance figures only — the BAKE is the only
	# clearance the navmesh enforces — so they cost nothing and lying about them
	# would only make this thing shoulder its way through a squad.
	nav.path_desired_distance = 3.0
	nav.target_desired_distance = 3.0
	nav.radius = 1.4
	nav.height = 3.2
	root_body.add_child(nav)
	nav.owner = root_body

	var det := Area3D.new()
	det.name = "Detection"
	root_body.add_child(det)
	det.owner = root_body
	var dcol := CollisionShape3D.new()
	dcol.name = "CollisionShape3D"
	var dsphere := SphereShape3D.new()
	# 25, the same as every other frame's. VESSEL.md's base_sensor_range of 50
	# is a CHASSIS field and this trigger volume is not it.
	dsphere.radius = 25.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body

	# ── the rig ──
	#
	# AT IDENTITY, AND IT MUST STAY THERE. rover.gd raycasts the suspension from
	# the BODY's transform times each wheel's rig-local position, so any offset
	# here silently moves every ray.
	var rig := _node(root_body, "Rig", Vector3.ZERO)

	# HULL. The concept's uncut block: 2.7 wide, 1.3 tall, 4.0 long — the biggest
	# in the game, which VESSEL.md §5 asks for outright. `size` is the block
	# BEFORE the four subtractions, so the finished hull is shorter at both ends.
	var hull := _hull(rig, "Hull", Vector3(2.7, 1.3, 4.0), _a(0, 1.0, 0))
	_cut(hull, "Glacis", Vector3(3.78, 1.56, 3.2), Vector3(0, -0.936, -2.48),
			Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(3.78, 1.56, 2.4), Vector3(0, -0.884, 2.56),
			Vector3(20.0 * DEG, 0, 0))
	for s in [-1.0, 1.0]:
		_cut(hull, "Bevel%s" % ("L" if s < 0.0 else "R"),
				Vector3(1.89, 1.04, 5.6), Vector3(s * 1.836, 0.858, 0),
				Vector3(0, 0, s * 30.0 * DEG))

	_lamps(rig)
	var turret := _turret(rig)
	var bay := _bay(rig)
	var wheels := _wheels(rig)

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
	# EVERY PAINTED PIECE, in a TYPED array.
	#
	# `pieces` is Array[Node3D]; an untyped one lands as [] and FactionLivery
	# then falls back to walking its whole parent — which paints every mesh on
	# the frame, THE EYE INCLUDED. That is how the Bulwark's eye ended up
	# faction-coloured despite being carefully left off a list that was never
	# there.
	#
	# THE EYE IS DELIBERATELY ABSENT, and so is everything named one at a time
	# around it: _gather() RECURSES, so listing `Turret` would collect the eye
	# through it and undo the exclusion just as thoroughly.
	#
	# CargoA and CargoB ARE listed whole, deliberately — recursion is what is
	# wanted there. They are our drones and they should wear our colour, and
	# neither contains an eye: the nose blob is a sensor in painted metal, not
	# the one feature that identifies a robot.
	#
	# THE WHEELS ARE ABSENT. Tyres carry their own rubber and the hubs their own
	# bare metal, exactly as the Rover's do; a faction-coloured tyre is a
	# faction-coloured tyre.
	var paint: Array[Node3D] = []
	paint.append(hull)
	paint.append(rig.get_node("TurretRing"))
	paint.append(turret.get_node("TurretBody"))
	paint.append(turret.get_node("Antenna"))
	paint.append(turret.get_node("GunPivot/Mantlet"))
	paint.append(bay.get_node("Coaming"))
	for tag in ["L", "R"]:
		paint.append(bay.get_node("HingeBar%s" % tag))
		var door: Node3D = bay.get_node("Door%s" % tag)
		paint.append(door.get_node("Leaf"))
		for i in 4:
			paint.append(door.get_node("Stud%d" % i))
	for tag in ["A", "B"]:
		paint.append(bay.get_node("Cradle%s" % tag))
		paint.append(bay.get_node("Chock%sL" % tag))
		paint.append(bay.get_node("Chock%sR" % tag))
		paint.append(bay.get_node("Cargo%s" % tag))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D, NavigationAgent3D or Array[Node3D] — not NodePath — so assigning a
	# NodePath silently does nothing and the frame comes out with a null turret
	# and wheels the drive cannot find. Nothing errors. PackedScene.pack() turns
	# these references back into the node_paths=PackedStringArray(...) form the
	# editor writes, so the saved scene looks hand-authored either way.
	root_body.set("rig", rig)
	root_body.set("turret", turret)
	root_body.set("gun_pivot", turret.get_node("GunPivot"))
	root_body.set("weapon_mount", turret.get_node("GunPivot/WeaponMount"))
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	# TYPED, IN ORDER, AND THE SAME LENGTH. rover.gd indexes wheel_steer by the
	# wheels array and warns if the counts differ; an untyped Array[float] would
	# save as [] and every wheel would be fixed with no error anywhere.
	root_body.set("wheels", wheels)
	var steers: Array[float] = [1.0, 1.0, 0.0, 0.0, -1.0, -1.0]
	root_body.set("wheel_steer", steers)
	var lamps: Array[Node3D] = []
	lamps.append(rig.get_node("ReverseLampL"))
	lamps.append(rig.get_node("ReverseLampR"))
	root_body.set("reverse_lamps", lamps)
	# THE TYRE'S REAL RADIUS. Divides the wheel spin and sets the length of the
	# suspension ray; the default is 0.36.
	root_body.set("wheel_radius", TYRE_R)
	# Front axle to middle axle, measured: the concept's axles are at z −1.4, 0
	# and +1.4. rover.gd turns this into the turning circle, so a stale 1.1 would
	# have this thing cornering like the Rover.
	root_body.set("wheelbase", 1.4)
	# TYPED ARRAYS, OR THEY SAVE AS EMPTY. particle_effects_* are
	# Array[ParticleEffect] and visible_pieces is Array[Node3D]; a plain untyped
	# Array fails SILENTLY and the packed scene comes out with `= []`. The
	# Bulwark shipped all three empty on its first build: no death effects, no
	# hit sparks, and a frame that painted its own eye.
	var dies: Array[ParticleEffect] = []
	dies.append(spark)
	dies.append(oil)
	var hits: Array[ParticleEffect] = []
	hits.append(spark)
	# THE WHOLE RIG, one entry, which is what vehicle_rover.tscn lists. hide_body
	# only sets `visible`, and a Node3D takes its children with it — and because
	# it is the parent that is hidden, a Cargo node a release has already hidden
	# stays hidden when the body is shown again. rover.gd overrides
	# _collapse_pieces, so this list is not also the death pose.
	var vis: Array[Node3D] = []
	vis.append(rig)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	# 200, the Bulwark's, not the 75 default. A supply-3 frame sent across a
	# level on one ADVANCE order has to still be awake when it gets there —
	# always_active does not exempt a frame from culling, which is what froze ten
	# squads across five missions.
	root_body.set("activation_distance", 200)
	# 260, from VESSEL.md §3: under the Walker's 320 and well under the
	# Bulwark's 400. It is not a firepower platform and should not survive like
	# one.
	root_body.set("health", 260)
	root_body.set("max_health", 260)
	# The Rover's own authored speed, unchanged. VESSEL.md's base_speed of 0.85
	# is a CHASSIS MULTIPLIER, not a speed — see ItemFacts.chassis_speed — so the
	# 0.85 belongs on a .tres this pass does not write, and it will land this
	# frame at 5.95 against the Rover's 7.0 without anything here pretending to
	# know the answer. A game-feel call for the human either way.
	root_body.set("move_speed", 7.0)
	root_body.set("soldier_name", "Vessel")
	# A vehicle does not fall over, and there is no standing corpse to flatten.
	# Both existing vehicles set this false.
	root_body.set("flatten_collider_when_downed", false)
	return root_body


## THE TURRET — small, and set well forward of the bay.
##
## Arranged as vehicle_rover.tscn arranges its own, which is the one thing the
## brief asks for by name: ring on the hull's top face, body sitting ON the ring,
## GunPivot just inside the body's front face, mantlet straddling it, mount just
## inside the mantlet's. The head itself is ConceptKit.head() at 0.58 — the
## Walker's turret profile with the cheek sliced off below and the brow above,
## one eye offset left, and the whip antenna off the back corner. That profile
## plus the offset eye is how a frame in this game is recognised at forty pixels.
func _turret(rig: Node3D) -> Node3D:
	var ring_h := 0.12 * HEAD_SCALE
	# THE RING, MOVED. ConceptKit.head() puts it at `at` with the body at
	# `at + 0.19 * scale`, which buries it: measured y 1.665..1.735 inside a body
	# of 1.636..1.984. Here it is seated on the hull's top face at 1.65, which
	# costs the turret 0.084 m of lift and is the only departure from the
	# concept's own positions on this assembly.
	_mesh(rig, "TurretRing", _cylm(0.54 * HEAD_SCALE, ring_h),
			_a(0, 1.65 + ring_h * 0.5, -1.5))

	# Body bottom ON the ring's top. 1.65 + 0.0696 + half of 0.6 * 0.58.
	var turret := _node(rig, "Turret", _a(0, 1.65 + ring_h + 0.3 * HEAD_SCALE, -1.5))
	var body_size := Vector3(1.18, 0.6, 1.3) * HEAD_SCALE
	var body := _hull(turret, "TurretBody", body_size, Vector3.ZERO)
	# Cheek and brow, cut exactly as the Walker's are. The cutters are 1.3x the
	# block they slice because anything tighter leaves a sliver of uncut face.
	_cut(body, "Cheek", Vector3(1.18 * 1.3, 0.7, 0.7) * HEAD_SCALE,
			Vector3(0, -0.44, -0.86) * HEAD_SCALE, Vector3(-35.0 * DEG, 0, 0))
	_cut(body, "Brow", Vector3(1.18 * 1.3, 0.7, 0.7) * HEAD_SCALE,
			Vector3(0, 0.5, -0.78) * HEAD_SCALE, Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, offset left, squashed, and carrying the WALKER'S OWN material
	# rather than the shared metal. Deliberately left out of the livery list:
	# painting it with the faction colour like everything else would make the one
	# feature that identifies a robot change colour per side.
	var eye := _mesh(turret, "Eye", _spherem(0.17 * HEAD_SCALE),
			Vector3(-0.34, 0.14, -0.66) * HEAD_SCALE)
	eye.scale = Vector3(1.0, 0.82, 1.0)
	eye.material_override = _eye_material()

	# The Walker's whip, off the turret's rear corner. Checked rather than
	# assumed, because the same antenna ended up inside the fuselage on the Kite:
	# here it stands at z −1.22, which is 0.32 m clear of the bay coaming's front
	# wall and well forward of the open door leaves.
	_mesh(turret, "Antenna", _boxm(Vector3(0.03, 0.85, 0.03) * HEAD_SCALE),
			Vector3(-0.5, 0.68, 0.48) * HEAD_SCALE)

	# ── GUN PIVOT ──
	# Inside the body's front face by 0.047, where vehicle_rover.tscn puts its
	# own, and at ZERO rotation because that is where the aiming code expects to
	# find it — any rest pose here is clamped straight back to level by
	# gun_min_pitch_degrees the moment something pitches it.
	var pivot := _node(turret, "GunPivot", Vector3(0, 0.02 * HEAD_SCALE, -0.33))
	# The Walker's mantlet and mount offsets, scaled by 0.58: the mantlet centred
	# at turret-local z −0.36 so it straddles the face, and the mount at −0.418,
	# which is 0.01 inside the mantlet's front face.
	_mesh(pivot, "Mantlet", _boxm(Vector3(0.5, 0.36, 0.26) * HEAD_SCALE),
			Vector3(-0.2 * HEAD_SCALE, 0, -0.62 * HEAD_SCALE + 0.33))
	# YAW +PI/2 AND NOTHING ELSE. See the header.
	_node(pivot, "WeaponMount",
			Vector3(-0.2 * HEAD_SCALE, 0, -0.72 * HEAD_SCALE + 0.33),
			Vector3(0, PI * 0.5, 0))
	return turret


## THE BAY — the coaming, the two hinged leaves, and what is in it.
##
## The coaming is a block standing proud of the deck with a cutter taller than
## its own walls taken out of it; a cutter the same height leaves a skin across
## the top, which is the concept's own note and is correct. The FLOOR of the well
## is the hull's top face at concept 1.65, not the coaming's underside — the
## coaming is a separate CSG root, so the hull's material is still there.
## Finished, the bay is 1.78 wide by 2.15 long by 0.50 deep.
func _bay(rig: Node3D) -> Node3D:
	var bay := _node(rig, "Bay", Vector3.ZERO)
	var coaming := _hull(bay, "Coaming", Vector3(2.15, 0.6, 2.5), _a(0, 1.85, 0.35))
	_cut(coaming, "Well", Vector3(1.78, 0.8, 2.15), Vector3(0, 0.12, 0))

	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		# THE HINGE LINE, on the coaming's outer top rail. A visible barrel
		# there is what sells "hinged" on a static render, and it is parented to
		# the Bay rather than the door because a hinge pin does not swing.
		_mesh(bay, "HingeBar%s" % tag, _cylm(0.05, 2.45, 8),
				_a(s * LEAF, 2.15, 0.35), Vector3(PI * 0.5, 0, 0))

		# THE DOOR. Rotation.z is the ONLY thing a close has to touch: this node
		# is on the hinge axis and the leaf hangs inboard of it, so rotation.z
		# going to 0 lays the leaf flat across the coaming with its neighbour.
		# See THE DOORS in the header for the sign and the 130 degrees.
		var door := _node(bay, "Door%s" % tag, _a(s * LEAF, 2.15, 0.35),
				Vector3(0, 0, -s * DOOR_OPEN * DEG))
		# euler (−PI/2, 0, −PI/2) maps the plate's own axes onto the hinge's:
		# its width (2.45, full length of the bay) onto Z, its height (1.075,
		# the inboard reach) onto X, and its extrusion onto −Y, so closed the
		# 0.1 m of thickness hangs INTO the bay and the top face is flush with
		# the rim. Derived from the YXZ euler composition, not guessed.
		_plate(door, "Leaf", 2.45, LEAF, 0.1, 0.12,
				Vector3(-s * LEAF * 0.5, 0, 0), Vector3(-PI * 0.5, 0, -PI * 0.5))
		# Bolts down the leaf's face, standing 0.045 proud of it. ZERO rotation:
		# a cylinder already stands along Y, which is this leaf's normal — it is
		# mockup_parts.studs()'s hardcoded PI/2 that would lay them flat.
		_studs(door, 4, Vector3(-s * 0.3, -0.12, -0.9), Vector3(0, 0, 0.6), 0.035)

	# ── WHAT IS IN IT ──
	# Two cradles at the concept's own z, each with a drone on it and a chock
	# either side. See THE BAY SHIPS LOADED in the header for why they are built
	# at all, and WHAT CHANGED for why the cradle is a deck rather than a slab
	# floating 0.25 m over the floor.
	var tags := ["A", "B"]
	for i in 2:
		var tag: String = tags[i]
		var az := -0.42 + float(i) * 1.5
		# A DECK, bottom on the bay floor at 1.65 and top at 1.84 where the
		# skids land.
		#
		# 1.7 WIDE, NOT THE CONCEPT'S 0.7. Measured on the first build, the two
		# chocks either side of each drone reach out to x 0.80 and their
		# undersides stopped 0.21 m above the bay floor — two wedges floating in
		# a hole, which is the one thing a bay must not contain. Widening the
		# cradle to span the chocks' footprint lands them on it and turns the
		# pair into one stowage position: a deck, a drone, and a chock either
		# side of it. The alternative was a taller chock on a pedestal, which is
		# three numbers tuned by eye instead of one measured.
		_plate(bay, "Cradle%s" % tag, 1.7, 0.6, 0.19, 0.07, _a(0, 1.65, az),
				Vector3(PI * 0.5, 0, 0))
		for s in [-1.0, 1.0]:
			# euler.y = −s * PI/2 so each chock extrudes AWAY from the
			# centreline. With the concept's fixed +PI/2 both went to −X and the
			# starboard one ran through the drone it was meant to hold.
			#
			# 2.00 rather than the concept's 2.02, which is the 0.018 that sets
			# each chock's heel on the cradle deck instead of just over it. It
			# still reaches the drone's body sides, which is what a chock is for.
			_wedge(bay, "Chock%s%s" % [tag, "L" if s < 0.0 else "R"],
					0.3, 0.26, 0.5, 0.1, _a(s * 0.3, 2.0, az),
					Vector3(0, -s * PI * 0.5, s * 14.0 * DEG))
		_cargo(bay, "Cargo%s" % tag, _a(0, 2.08, az))
	return bay


## A CARRIED HATCHLING, as cargo and nothing else.
##
## concepts_b._hatchling(): small on purpose — 0.86 m across rotors against a
## 2.7 m hull — because the whole proposition is that the Vessel adds BODIES,
## and a drone drawn big enough to be comfortable reads as a second vehicle
## bolted on rather than as a thing that came out of the bay. Two rotors rather
## than four, because at this size four discs overlap into one blob.
##
## ONE NODE PER DRONE, NAMED. A release hides this and the cradle under it stays,
## which is the "visibly empty after launch" VESSEL.md §5 asks for.
func _cargo(bay: Node3D, nm: String, at: Vector3) -> Node3D:
	var d := _node(bay, nm, at)
	# The body, extruded DOWNWARD. −PI/2 about X, not +PI/2: the concept's own
	# comment says this hangs under the rotors and with +PI/2 it measured
	# 0.20 m above its own skids with the rotors buried inside it. This lands it
	# at −0.1..+0.1 of the drone's origin, bottom flush on the skid tops.
	_plate(d, "Body", 0.42, 0.5, 0.2, 0.08, Vector3(0, 0.1, 0),
			Vector3(-PI * 0.5, 0, 0))
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		_mesh(d, "Arm%s" % tag, _boxm(Vector3(0.2, 0.07, 0.07)),
				Vector3(s * 0.14, 0.14, 0))
		# ConceptKit.rotor(): a hub and two thin bars lying flat. "This flies"
		# in one shape, which is the only thing the cargo has to say.
		var hub_at := Vector3(s * 0.24, 0.16, 0)
		_mesh(d, "Hub%s" % tag, _cylm(0.13, 0.18, 8), hub_at)
		for b in 2:
			var ang := PI * float(b)
			_mesh(d, "Blade%s%d" % [tag, b], _boxm(Vector3(0.19, 0.035, 0.1)),
					hub_at + Vector3(cos(ang) * 0.095, 0.05, sin(ang) * 0.095),
					Vector3(0, -ang, 0))
		# Skids, which are what makes it read as a thing that LANDS — and what
		# the cradle under it now actually touches.
		_mesh(d, "Skid%s" % tag, _boxm(Vector3(0.05, 0.14, 0.42)),
				Vector3(s * 0.15, -0.17, 0))
	# A nose sensor in painted metal, NOT an eye. One eye per frame, and this
	# frame's is on the turret.
	_mesh(d, "Nose", _spherem(0.07), Vector3(0, 0, -0.26))
	return d


## SIX WHEELS, in rover.gd's order: FL, FR, ML, MR, RL, RR.
##
## Each is a bare Node3D at the axle — the steer angle is written straight onto
## its `rotation.y`, so it has to be authored square — with a child named "Spin"
## that the drive rolls about X, and the quarter turn that lays a cylinder on its
## side carried by the tyre mesh below that.
##
## Tyres and hubs keep their own materials, the Rover's: a faction-coloured tyre
## is a faction-coloured tyre. They are therefore absent from the livery list.
func _wheels(rig: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var rubber := _rubber_material()
	var steel := _hub_material()
	for row in [["F", -1.4], ["M", 0.0], ["R", 1.4]]:
		for s in [-1.0, 1.0]:
			var nm := "Wheel%s%s" % [row[0], "L" if s < 0.0 else "R"]
			var w := _node(rig, nm, _a(s * 1.42, 0.3, float(row[1])))
			var spin := _node(w, "Spin", Vector3.ZERO)
			var tyre := _mesh(spin, "Tyre", _cylm(TYRE_R, TYRE_W, 12),
					Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			tyre.material_override = rubber
			# Standing a little proud of the tyre, so there is a hub to see.
			var hub := _mesh(spin, "Hub", _cylm(0.183, TYRE_W + 0.04, 5),
					Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			hub.material_override = steel
			out.append(w)
	# Rover order, not build order: front pair, middle pair, rear pair, left
	# before right — which is what wheel_steer is written against.
	return out


## Tail lamps and reverse lamps, on the one band of rear face the tail chamfer
## leaves standing: the cut takes everything below concept y 1.15 at z 2.0, so
## these sit at 1.35 in the middle of what is left.
##
## rover.gd shows the reverse pair below −0.3 m/s, so they are authored HIDDEN
## and they are what `reverse_lamps` points at.
func _lamps(rig: Node3D) -> void:
	var dark := _lamp_dark_material()
	var bright := _lamp_lit_material()
	for s in [-1.0, 1.0]:
		var tag := "L" if s < 0.0 else "R"
		var tail := _mesh(rig, "TailLamp%s" % tag,
				_boxm(Vector3(0.2, 0.09, 0.05)), _a(s * 0.85, 1.35, 2.0))
		tail.material_override = dark
		var rev := _mesh(rig, "ReverseLamp%s" % tag,
				_boxm(Vector3(0.21, 0.1, 0.055)), _a(s * 0.85, 1.35, 2.005))
		rev.material_override = bright
		rev.visible = false


## The eye's own material. Built fresh rather than shared, because a material
## handed to two frames is one object — see the duplicate() rule in CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m


func _rubber_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.06, 0.065, 1.0)
	m.roughness = 0.95
	return m


func _hub_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.43, 0.44, 1.0)
	m.metallic = 0.55
	m.roughness = 0.5
	return m


func _lamp_dark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.115, 0.12, 1.0)
	m.metallic = 0.45
	m.roughness = 0.6
	return m


func _lamp_lit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.96, 0.88, 1.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.94, 0.8, 1.0)
	m.emission_energy_multiplier = 3.0
	return m
