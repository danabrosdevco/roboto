extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/tick.tscn — the TICK.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_tick.gd
#
# RUN ONCE, THEN THE .tscn IS THE SOURCE OF TRUTH. This is not a build step.
# Re-running it over a scene somebody has touched in the editor throws that work
# away, which is how --force rebuilds have repeatedly cost this project its
# gameplay layers. If the geometry needs changing after today, change the scene.
# build_bulwark.gd and build_brood.gd say the same thing for the same reason.
#
# ─────────────────────────────────────────────
# WHAT THIS IS
#
# SWARM · AERIAL · the hack drone that is its own payload. Concept A, THE TICK,
# out of ConceptsHack.tick_flight() / tick_placed() in tools/concepts_hack.gd,
# which is the authority on the silhouette. It flies in carrying nothing because
# IT IS the payload: it settles on the cap of a compute core, four barbed legs
# clamp down the flanks, the rotor booms droop dead against the body, and the
# drone stops being a drone and becomes a permanent structure hacking the core.
#
# ONE MODEL, TWO STATES. That is the concept's whole argument and it is the
# reason this file writes one scene and not two. Everything that differs between
# flight and placed is a rotation or a slide on a NAMED node — see THE PLACEMENT
# below, which is the contract a future script codes against.
#
# ─────────────────────────────────────────────
# THE PLACEMENT — exactly what has to move, and by how much
#
# The scene ships in the FLIGHT pose. A placement script drives these and
# nothing else; no geometry is created, destroyed or reparented.
#
#   Rig/Legs/Leg{1,2,3,4}/Thigh        rotation.x   +46 deg  ->  -22 deg
#   Rig/Legs/Leg{1,2,3,4}/Thigh/Shin   rotation.x  -148 deg  ->  -62 deg
#       The folded Z breaks open into a splayed clamp. THIGH IS THE SPAN
#       CONTROL: it is the one hinge that answers the core size range, and at
#       -22 deg the barbs reach 1.81 m out from the axis and 1.88 m down.
#       F2 RAFT's cap is a CONSTANT 2.60 m across at every core size
#       (concepts_core2.gd's F_PAD := 1.3 half-width, "THE RULER"), so -22 is
#       correct on a 4.2 m core and a 12.4 m one alike: the barbs land 0.51 m
#       OUTSIDE the 1.30 m pad edge, i.e. down the flanks, which is what
#       gripping means. Nothing here has to be re-solved per core size. Tighter
#       (toward -5) walks the barbs inward if a narrower pad ever appears.
#
#   Rig/FanTower                       position.y   1.50     ->  0.76
#       The whole lift assembly — hub, struts, all three rotors — telescopes
#       0.74 m down onto the drum. The struts sink into the shell, which is the
#       point: a machine that has settled, not one with a mast still up.
#
#   Rig/FanTower/Rotor{1,2,3}/Boom     rotation.x     0 deg  ->  -48 deg
#       The droop. All three the same angle, which is deliberate — see THE
#       DROOPED ROTORS below.
#
#   And the body itself: this frame's ORIGIN IS THE DRUM CENTRE, so seating it
#   is one translation. ConceptsHack.tick_placed() builds with the barb tips at
#   y 0 and the drum centre 2.00 m above them, so
#       tick.global_position = <contact point on the cap> + Vector3(0, 2.00, 0)
#   lands the barbs on the pad. Nothing else needs solving.
#
#   Eight rotations, one slide, one translation. That is the whole state change.
#
# ─────────────────────────────────────────────
# THE DROOPED ROTORS ARE THE TELL AND THEY ARE ALSO THE RISK
#
# HACK_DRONE.md section 1 records the honest weakness in terms: "the drooped
# rotors read as a collapsed helicopter, which is WRECKAGE, and a wrecked-
# looking objective is a bad objective." Four things are done about it here, and
# they are the only places this build argues with the sheet:
#
#   1. THE DUCT IS PROMOTED TO THE BLADE TIP. In the concept, _fan() builds a
#      duct ring at 1.1x the fan radius and then calls K.rotor() with r * 2.0 —
#      and rotor() uses that value as the BLADE TIP RADIUS, so every blade
#      overhangs its own hoop by 0.9 r. Look at the "IN FLIGHT" cell of
#      hack_tick.png: the hoops are small and the blades are long whiskers
#      sticking out past them. That is the identical fault build_brood.gd
#      records ("three whiskers poking out past the hoop rather than as three
#      fans") and it is what makes the placed pose read as broken: once the
#      booms droop, the small hoops sink into the drum and ALL THAT IS LEFT
#      OUTSIDE THE BODY IS BARE SPOKES. So the ring here is moved out to enclose
#      the blades — DUCT_K below — and the placed frame grows three big intact
#      hoops arcing down around the drum instead of nine loose sticks. An
#      unbroken hoop is the single cheapest "this is a machine" in the game
#      (concepts_hack._fan's own docstring says so) and a wreck does not have
#      three of them, matched and circular.
#      THE OVERALL SPAN IS PRESERVED, not shrunk: DUCT_K is solved so the
#      measured in-flight box still lands on the concept's 4.08 x 4.17.
#
#   2. EVERY BOOM DROOPS TO THE SAME ANGLE. Uneven droop is what a crash looks
#      like. The booms are three different lengths at three bearings that are
#      not on a 90 — Swarm counts badly and that stays — but the ANGLE is one
#      number for all three, so the three hoops come to rest as a set.
#
#   3. THREE PARK CRADLES ON THE DRUM, at Rig/Cradles/Cradle{1,2,3}, each sized
#      and angled to the motor that lands on it. A limb resting in hardware made
#      to receive it is parked; a limb hanging is broken. They are placed at the
#      measured drooped boom-end positions, not eyeballed — see _cradles().
#      In flight they read as three unequal pads bolted to the dome, which is
#      the correct Swarm read anyway.
#
#   4. THE SENSOR IS LIT, IN BOTH STATES. Six unequal emissive ocelli on the
#      drum's forward flank. A powered sensor is the one thing a wreck never
#      has, and it costs six spheres. This is also the "not ours" read — see
#      NO EYE below.
#
# Nothing is bent, nothing is shed and nothing is detached anywhere in the
# placed pose: every hoop is circular, every blade straight and in its own
# plane, and every joint is a modelled gland that the boom rotates in.
#
# ─────────────────────────────────────────────
# NO EYE, AND NOTHING NAMED "Eye"
#
# The Walker's single offset optic in a chamfered head is Home Command's grammar
# and the player's own factory, and Swarm must not borrow it. The sensor is
# instead six unequal OCELLI scattered on the drum's forward flank, no two sizes
# alike and no two spacings alike — the Broodcarrier's answer, and for the same
# reason. They are the only pieces on the frame that keep their own material and
# are therefore the only pieces left off the livery list; they are built through
# _unpainted_mesh() so that "what is not painted" is one grep.
# check_frame.gd's EYE EXCLUDED assertion does not fire on this frame because
# there is nothing called Eye to exclude; the exclusion it protects is done here
# by hand.
#
# ─────────────────────────────────────────────
# TWO CONES FLIPPED, AND WHY
#
# The concept's drill snout and its four barbs are both CSGCylinder3D with
# `cone = true` and NO rotation, which in Godot tapers toward +Y — so both widen
# DOWNWARD and end in a flat disc. The snout is described as "a tapered bit...
# driven INTO the cabinet" and the barbs as claws that "bite", and a reverse
# taper cannot do either; in the "STRUCTURE PLACED, ALONE" cell they photograph
# as four little bells. Every other deliberately-downward cone in
# concepts_hack.gd carries an explicit Vector3(PI, 0, 0) (the Piton's nose, the
# Parasol's skirt) and these two do not, which is the signature of an oversight
# rather than a choice. Both are built apex-down here. The AABB of a cone is the
# same either way, so NO MEASUREMENT CHANGES — it is one line each to put back.
#
# ─────────────────────────────────────────────
# ORIGIN — THE DRUM CENTRE, WHICH IS NOT THE BROODCARRIER'S CHOICE
#
# A flyer's origin is free, and three things ride on it: the collision shape,
# spotter_drone.gd holding global_position.y at cruise_height above whatever its
# GroundRay finds, and that ray starting there. build_brood.gd puts the origin
# at the centre of its collision sphere for that reason.
#
# This frame puts it at THE DRUM CENTRE instead, because this frame has a second
# job the Broodcarrier does not: it has to be seated on a cap, and
# tick_placed() defines that seat as "the drum centre is 2.00 m above the barb
# tips". Origin at the drum centre makes placement one addition with no magic
# number buried in a script. The collision sphere is therefore offset upward
# rather than centred — the mass is the drum and the tower above it, not the
# legs — and that is the one place this frame departs from the Broodcarrier's
# convention.
#
# ─────────────────────────────────────────────
# NOT ONE CSG NODE, DELIBERATELY
#
# The concept is mockup_parts.gd, which is all CSG, because a concept sheet is
# one render. A shipped robot pays for CSG every frame: csg_bake.gd exists only
# because the CSG in the AI scenes cost 335 ms the first time a reserve wave
# ran. Nothing on this frame needs a boolean, so every visible piece is a plain
# MeshInstance3D with a material_override and there is nothing for csg_bake.gd
# to swap.
#
# ─────────────────────────────────────────────
# SCOPE: THE MODEL, AND NOTHING ELSE
#
# No ChassisDefinition, no catalogue entry, no weapon item, no tick.gd, no
# faction, no mission placement, no registry edited. The root script is the
# existing spotter_drone.gd — see BODY_SCRIPT. A registration block for a
# coordinator is in the agent's report, not in any shared file here.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/tick.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
## spotter_drone.gd, the existing flying script. It now declares
## _carries_a_weapon() -> false, which is exactly right for a frame that carries
## no weapon: handle_weapon_logic and roll_combat_action both no-op through it,
## and nothing has to fork the most-edited state machine in the project to say
## so. It also declares rotor_loop, which the script stops and restarts on park,
## crash, downed and revive — four paths — so a flyer without that node is
## silent through all four with nothing saying so.
const BODY_SCRIPT := "res://Character/characters/ai/spotter_drone.gd"
## Thin and dry rather than the Broodcarrier's deep pair: this is a small, busy
## thing. Voice is a game-feel call the human owns; changing it later is one
## line in the .tscn.
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__18.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__73.wav"
const ROTOR_LOOP := "res://sounds/sfx/quadcopter loop/freesound_community-mini-quadcopter-flying-loop-80330.mp3"

const DEG := PI / 180.0

# ── the two states, as numbers ───────────────
const FLIGHT_OUT := 46.0
const FLIGHT_KNEE := -148.0
const PLACED_OUT := -22.0
const PLACED_KNEE := -62.0
const FLIGHT_TOWER_Y := 1.50
const PLACED_TOWER_Y := 0.76
const FLIGHT_DROOP := 0.0
const PLACED_DROOP := -48.0

## DUCT OUTER RADIUS, AS A MULTIPLE OF THE CONCEPT'S FAN RADIUS.
##
## The concept's own span comes from blades reaching 2.0x the fan radius while
## the hoop sits at 1.1x — i.e. K would be 2.0 to put the hoop exactly where the
## concept's blade tips are, and the frame's maximum reach from the axis would
## be the sheet's own 2.66 m.
##
## IT IS 1.46 INSTEAD, AND THE REASON IS A MEASUREMENT ARTEFACT WORTH KNOWING.
## check_frame.gd measures by merging each piece's AABB after transform, so a
## flat disc on a yawed node is measured as the enclosing box of a ROTATED
## square: a hoop of radius R on a boom at bearing a measures
## R * (|cos a| + |sin a|) in BOTH axes, which is up to 1.41x its real radius.
## The concept dodges that only because three bare blades genuinely occupy three
## directions and nothing in between. So a hoop that reaches exactly as far as
## the concept's blades measures 4.49 x 4.98 against the sheet's 4.08 x 4.17 —
## a frame that is NOT bigger reading as 20 per cent bigger.
##
## SOLVED, NOT TUNED BY EYE. With the fan hubs at the concept's own three
## positions the measured width is 1.660 + 1.647 * DUCT_K; 1.46 puts it on
## 4.08, the sheet's figure to the centimetre. Length comes out 4.52 against
## 4.17 and cannot be fixed by the same number — the two want 1.46 and 1.26 —
## because the hoop occupies every bearing where the blades occupied three.
## Width is the one matched because it is the dimension the sheet's own cells
## are read across. The frame's true maximum reach from the axis is then 2.38 m
## against the concept's 2.66: this model is slightly TIGHTER than the sheet,
## not larger, whatever the length figure says.
const DUCT_K := 1.46
## Blade tip clearance inside the hoop, so a blade never crosses its own duct.
const BLADE_GAP := 0.14

## THE THREE LIFT FANS: bearing, boom reach, concept fan radius. Three lengths,
## three bearings, nothing on a 90 and nothing a pair. This is Swarm's whole
## grammar and it is lifted unchanged.
const FANS := [
	[18.0, 1.18, 0.74],
	[147.0, 0.98, 0.60],
	[265.0, 1.30, 0.66],
]

## THE FOUR LEGS: bearing, upper-segment length. The alternating 1.16 / 1.00 is
## the concept's — a matched set of four would be issued hardware.
const LEGS := [
	[34.0, 1.16],
	[128.0, 1.00],
	[212.0, 1.16],
	[303.0, 1.00],
]
const LEG_LOWER := 1.26

## The drum ellipsoid, held as constants because the ocelli are solved AGAINST
## it rather than eyeballed near it — see _ocelli().
const DRUM_R := 0.86
const DRUM_SQUASH := Vector3(1.0, 0.64, 1.06)

var _root: CharacterBody3D
var _metal: Material
## Every painted piece, collected as it is built. A piece is painted unless it
## went through _unpainted_mesh(), which is the one door out and exists only for
## the ocelli.
var _paint: Array[Node3D] = []
var _ocelli_count := 0


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_tick: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_tick: save failed (%s)" % error_string(err))
		quit(1)
		return
	print("build_tick: wrote %s" % OUT)
	print("build_tick: %d painted pieces, %d ocelli left off the livery"
			% [_paint.size(), _ocelli_count])
	_report_reach()
	quit(0)


## THE SPAN, PRINTED RATHER THAN ASSUMED. The whole concept rests on one hinge
## answering every core size, so the number that claim depends on gets printed
## by the thing that builds it rather than quoted from a doc.
func _report_reach() -> void:
	# The barb's own tip in the Shin frame: the cone's centre, plus half its
	# height along its own +Y, which Rx(72) sends to (0, -cos72, -sin72) — i.e.
	# down and outward, which is the end that bites.
	var tip_y := -0.12 - 0.21 * cos(72.0 * DEG)
	var tip_z := -LEG_LOWER - 0.04 - 0.21 * sin(72.0 * DEG)
	for state: Array in [["flight", FLIGHT_OUT, FLIGHT_KNEE], ["placed", PLACED_OUT, PLACED_KNEE]]:
		var out: float = float(state[1]) * DEG
		var knee: float = out + float(state[2]) * DEG
		# Walked down the chain exactly the way the nodes are nested: hub, then
		# Thigh's swing, then Shin's, then the barb inside Shin. Rx(a) sends
		# (0, y, z) to (0, y cos a - z sin a, y sin a + z cos a).
		var y := -0.14 + sin(out) * LEGS[0][1] + (tip_y * cos(knee) - tip_z * sin(knee))
		var rho := 0.62 + cos(out) * LEGS[0][1] - (tip_y * sin(knee) + tip_z * cos(knee))
		print("build_tick: legs %-6s  barb tip %.2f m out, %.2f m below the drum centre"
				% [state[0], rho, -y])


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A painted mesh piece. EVERYTHING VISIBLE goes through here except the ocelli,
## so nothing can be left without the shared faction metal — a single unpainted
## piece is invisible as a bug until someone renders the frame in a faction
## colour, and this frame has eighty of them.
func _mesh(parent: Node, nm: String, mesh: Mesh, at: Vector3,
		euler: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := _unpainted_mesh(parent, nm, mesh, at, euler, scl)
	m.material_override = _metal
	_paint.append(m)
	return m


## The one door out of the paint list, and the only thing that uses it is the
## sensor. A separate function rather than a flag so that "which pieces are not
## painted" is answerable by grepping for one name.
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


## Low segment counts throughout — this is a PSX-textured game and an
## eighty-piece frame is not the place to spend faces.
func _spherem(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


## `top` and `bottom` are given separately so a cone can be built APEX DOWN,
## which CSGCylinder3D's `cone` flag cannot do without an extra PI about X. See
## TWO CONES FLIPPED in the header.
func _cylm(top: float, bottom: float, h: float, sides: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	c.rings = 0
	return c


func _torusm(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	return t


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Tick"
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
	# A sphere, like both existing flyers and the Broodcarrier. OFFSET UPWARD
	# rather than centred on the origin: the origin is the drum centre (see the
	# header) and the mass a player shoots at is the drum plus the lift tower
	# standing on it, so r 1.00 at y +0.25 spans -0.75 .. +1.25 and contains the
	# whole drum, the snout collar and the lower half of the tower. Centred on
	# the origin it would instead contain a lot of empty air under the belly.
	# The legs and the drooped hoops are outside it in both states, which is the
	# same deal every limbed frame in the game takes.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	col.shape = sphere
	col.position = Vector3(0.0, 0.25, 0.0)
	root_body.add_child(col)
	col.owner = root_body

	# NO GroundRay NODE. spotter_drone.gd builds its own in _ready() —
	# target (0, -300, 0), mask 1, exclude_parent — specifically so that no
	# drone scene can ship without the ray it needs to hold an altitude.
	# Authoring one here would give the frame two.

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, or the assignment is silently dropped. bark_clips is
	# Array[AudioStream]; a plain Array fails with no error and the scene keeps
	# bark.tscn's three default clips instead. That line was untyped in
	# build_bulwark.gd and bulwark.tscn has shipped with the wrong voice ever
	# since — nobody noticed, because it still barks.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	bark.set("pitch_min", 0.92)
	bark.set("pitch_max", 1.08)
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
	dsphere.radius = 20.0
	dcol.shape = dsphere
	det.add_child(dcol)
	dcol.owner = root_body
	# NO SIGNALS CONNECTED, matching walker.tscn, enemy_watcher.tscn and the
	# other flyers. check_frame.gd reports this count rather than asserting it
	# because the shipped frames disagree with each other and which is right is
	# a gameplay question. Flagged in the report rather than decided here.

	# ── the rig ──
	var rig := _node(root_body, "Rig", Vector3.ZERO)
	_drum(rig)
	_legs(rig)
	_fan_tower(rig)
	_cradles(rig)
	_ocelli(rig)

	# A MOUNT WITH NOTHING ON IT, EVER. The Tick carries no weapon —
	# spotter_drone.gd's _carries_a_weapon() returns false and this frame
	# inherits that correctly — but enemy.gd declares weapon_mount as a typed
	# Node3D export and this pass does not edit enemy.gd. So the frame provides
	# one and leaves it empty, body-fixed on the snout collar where the only
	# thing this machine does to anything is done.
	#
	# +90 DEGREES, NOT -90. A weapon's muzzle runs down its own +X and the mount
	# has to turn that onto the body's -Z. Read off a matrix the yaw looks like
	# a quarter turn either way; it is not, and the Bulwark's first build had it
	# backwards — the gun fitted, elevated, tracked targets and fired directly
	# behind the frame. Kept correct even though nothing will ever hang on it,
	# because the next person to read this scene should not learn the wrong sign
	# from it.
	var wm := _node(rig, "WeaponMount", Vector3(0.05, -0.62, -0.04),
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
	# park, crash, downed and revive, and a flyer without it is silent through
	# all four with nothing saying so. Quieter and tighter than the
	# Broodcarrier's -5 dB / 18 m: three small ducted fans on a 1.8 m drum, and
	# the frame's whole threat is that it gets somewhere before you notice.
	#
	# IT IS ALSO THE PLACED STATE'S ONE AUDIO PROBLEM, and it is flagged rather
	# than solved: a parked Tick with its rotors dead should not still be making
	# a flying loop. Stopping it belongs to whatever script drives the
	# placement, next to the eight rotations, and this pass writes no script.
	var rotor_loop := AudioStreamPlayer3D.new()
	rotor_loop.name = "RotorLoop"
	rotor_loop.stream = load(ROTOR_LOOP)
	rotor_loop.volume_db = -9.0
	rotor_loop.unit_size = 12.0
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
	# EVERY PAINTED PIECE, IN A TYPED ARRAY, AND LEAVES ONLY.
	#
	# `pieces` is Array[Node3D]. An untyped array lands as [] and FactionLivery
	# falls back to walking its whole parent — which paints every mesh on the
	# frame. The same trap has a second door: FactionLivery._gather() RECURSES,
	# so listing `Rig` once instead of eighty leaves would paint the ocelli too
	# and lose the one thing marking this sensor as not the player's. So: leaves
	# only, collected by _mesh() as each one is built, and the ocelli are not in
	# it because they were built through _unpainted_mesh().
	livery.set("pieces", _paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed, so assigning a
	# NodePath silently does nothing and the frame comes out with a null
	# detection area and no rotor sound. Nothing errors. PackedScene.pack()
	# turns these references back into the node_paths=PackedStringArray(...)
	# form the editor writes, so the saved scene looks hand-authored either way.
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

	# JUST `Rig`. visible_pieces does two jobs in enemy.gd: hide_body() /
	# show_body() toggle `visible` on each entry, and the death collapse applies
	# an 84-degree pitch to each entry in the body's own space about the body
	# origin. Nothing on this frame stays behind, so one entry covering the whole
	# rig both hides completely and tips as a single mass. Listing Rig AND a
	# child of Rig would be the bug: the child would take the pitch twice.
	var vis: Array[Node3D] = []
	vis.append(rig)
	root_body.set("visible_pieces", vis)

	# ── stats ──
	#
	# PLACEHOLDERS, AND THE REAL ONES BELONG IN A ChassisDefinition THIS PASS
	# DOES NOT CREATE. 120 is between the Spotter's 80 and the bomber's 100 on
	# the way in, and low for a thing that becomes an objective — which is the
	# open question, because a Tick in flight and a Tick clamped on a core are
	# arguably not the same health pool. The human owns that.
	root_body.set("health", 120)
	root_body.set("max_health", 120)
	root_body.set("sensor_range", 45.0)
	# The Spotter's 250, for the reason recorded against the long ADVANCE
	# orders: always_active does not exempt a robot from the distance cull, and
	# a culled flyer stops holding its altitude.
	root_body.set("activation_distance", 250)
	root_body.set("soldier_name", "Tick")
	# A flyer has no collider to flatten; the Spotter sets this false for the
	# same reason — it crashes and lies there, it does not sink.
	root_body.set("flatten_collider_when_downed", false)

	# ── flight tuning: PLACEHOLDERS, FOR THE HUMAN ──
	#
	# Game feel, which cannot be judged from here. Set fast and low rather than
	# slow and high: this is a small thing whose whole job is to reach a core
	# before the squad reaches it, so the pressure is "shoot it NOW" rather than
	# "shoot it eventually". Lower than the Spotter's 22 m cruise because it has
	# to come down to a cap.
	root_body.set("move_speed", 11.0)
	root_body.set("cruise_speed", 11.0)
	root_body.set("cruise_height", 14.0)
	root_body.set("orbit_radius", 8.0)
	root_body.set("orbit_speed", 6.0)
	root_body.set("turn_speed", 2.6)
	root_body.set("bank_angle", 0.45)
	return root_body


# ─────────────────────────────────────────────
# THE DRUM — three overlapping lobes, a band, and the one machined part
# ─────────────────────────────────────────────
#
# Numbers straight out of ConceptsHack._tick_drum(). Nothing centred, nothing
# matched: the chamfered box, the turret ring and the whip antenna in
# concept_kit.gd are the PLAYER's language and are deliberately absent. The only
# square-shouldered thing on the frame is the bit that bites, which is the whole
# "hacking" read — something driven INTO the cabinet rather than parked on it.
func _drum(rig: Node3D) -> void:
	var drum := _node(rig, "Drum", Vector3.ZERO)
	_mesh(drum, "Shell", _spherem(DRUM_R), Vector3.ZERO, Vector3.ZERO, DRUM_SQUASH)
	_mesh(drum, "Band", _torusm(0.80, 0.99), Vector3(0.0, 0.07, 0.0))
	_mesh(drum, "LobeA", _spherem(0.48), Vector3(-0.44, 0.12, 0.32),
			Vector3.ZERO, Vector3(1.0, 0.82, 1.0))
	_mesh(drum, "LobeB", _spherem(0.34), Vector3(0.48, 0.04, -0.26))

	# THE SNOUT: a collar, a lock ring and a tapered bit. Offset from the axis
	# like everything else on this body.
	var snout := _node(drum, "Snout", Vector3(0.05, 0.0, -0.04))
	_mesh(snout, "Collar", _cylm(0.23, 0.23, 0.44, 8), Vector3(0.0, -0.5, 0.0))
	_mesh(snout, "LockRing", _torusm(0.23, 0.33), Vector3(0.0, -0.62, 0.0))
	# APEX DOWN — see TWO CONES FLIPPED in the header. Same AABB either way.
	_mesh(snout, "Bit", _cylm(0.14, 0.0, 0.78, 8), Vector3(0.0, -1.04, 0.0))


# ─────────────────────────────────────────────
# THE LEGS — four, and the one hinge that answers every core size
# ─────────────────────────────────────────────
#
# YAW FIRST, SWING INSIDE THAT FRAME. This is the discipline concepts_c._spade's
# docstring exists for and that build_bastion.gd had to repair on its outriggers:
# swing the limbs in the ROOT's frame instead and all four lean the same way, so
# two of them drive into the body rather than away from it. Every Leg<n> node
# carries only the bearing; every rotation that opens or closes the clamp is on
# Thigh and Shin, inside it.
func _legs(rig: Node3D) -> void:
	var legs := _node(rig, "Legs", Vector3.ZERO)
	for i in LEGS.size():
		var bearing: float = float(LEGS[i][0])
		var upper: float = float(LEGS[i][1])
		# The hub carries the bearing and NOTHING ELSE, so a placement script
		# never has to know which leg it is holding.
		var hub := _node(legs, "Leg%d" % (i + 1), Vector3(0.0, -0.14, 0.0),
				Vector3(0.0, bearing * DEG, 0.0))
		# The shoulder stands off the drum's rim rather than on the axis, so the
		# limbs start where a limb would and the four do not pile into the
		# middle of the body.
		var thigh := _node(hub, "Thigh", Vector3(0.0, 0.0, -0.62),
				Vector3(FLIGHT_OUT * DEG, 0.0, 0.0))
		_mesh(thigh, "Shoulder", _spherem(0.17), Vector3.ZERO)
		_mesh(thigh, "Upper", _boxm(Vector3(0.21, 0.21, upper)),
				Vector3(0.0, 0.0, -upper * 0.5))
		var shin := _node(thigh, "Shin", Vector3(0.0, 0.0, -upper),
				Vector3(FLIGHT_KNEE * DEG, 0.0, 0.0))
		_mesh(shin, "Knee", _spherem(0.14), Vector3.ZERO)
		_mesh(shin, "Lower", _boxm(Vector3(0.16, 0.16, LEG_LOWER)),
				Vector3(0.0, 0.0, -LEG_LOWER * 0.5))
		# THE BARB, ACROSS THE LIMB RATHER THAN ALONG IT. A claw drawn along the
		# limb reads as a longer limb; across it, it reads as a grip. Apex down
		# out of the ankle — see TWO CONES FLIPPED.
		_mesh(shin, "Barb", _cylm(0.12, 0.0, 0.42, 6),
				Vector3(0.0, -0.12, -LEG_LOWER - 0.04),
				Vector3(72.0 * DEG, 0.0, 0.0))


# ─────────────────────────────────────────────
# THE LIFT — one tower, three booms that agree about nothing except the droop
# ─────────────────────────────────────────────
#
# THE WHOLE ASSEMBLY IS ONE NODE so the placement is one slide. In the concept
# the flight and placed builders simply call _tick_fans() at two different
# heights; here that difference is FanTower.position.y and the geometry under it
# is identical in both states, which is the difference between a concept and a
# model.
func _fan_tower(rig: Node3D) -> void:
	var tower := _node(rig, "FanTower", Vector3(0.0, FLIGHT_TOWER_Y, 0.0))
	# The lump the fans hang off. The carrier is not a vehicle, it is more tick.
	_mesh(tower, "Hub", _spherem(0.46), Vector3(0.06, -0.04, -0.04),
			Vector3.ZERO, Vector3(1.15, 0.78, 1.1))
	# Three struts at bearings that match neither the fans nor the legs. On
	# placement they sink into the shell, which is what a telescoped mast does.
	for i in 3:
		var a: float = [52.0, 176.0, 291.0][i] * DEG
		_mesh(tower, "Strut%d" % (i + 1), _boxm(Vector3(0.11, 0.86, 0.11)),
				Vector3(sin(a) * 0.4, -0.48, cos(a) * 0.4),
				Vector3(0.0, -a, 10.0 * DEG))

	for i in FANS.size():
		var bearing: float = float(FANS[i][0])
		var reach: float = float(FANS[i][1])
		var fan_r: float = float(FANS[i][2])
		# Bearing on the Rotor node, droop on the Boom inside it. Same rule as
		# the legs: a placement script drives Boom and never touches Rotor.
		var rotor := _node(tower, "Rotor%d" % (i + 1), Vector3.ZERO,
				Vector3(0.0, bearing * DEG, 0.0))
		# THE GLAND. A hinge pin lying across the boom's own axis, which is the
		# cheapest possible "this joint is a joint". A drooped boom with a
		# modelled pivot at its root is articulated; one without is snapped off.
		_mesh(rotor, "Gland", _cylm(0.13, 0.13, 0.30, 8), Vector3.ZERO,
				Vector3(0.0, 0.0, PI * 0.5))
		var boom := _node(rotor, "Boom", Vector3.ZERO,
				Vector3(FLIGHT_DROOP * DEG, 0.0, 0.0))
		_mesh(boom, "Arm", _boxm(Vector3(0.12, 0.12, reach)),
				Vector3(0.0, 0.0, -reach * 0.5))
		_fan(boom, Vector3(0.0, 0.06, -reach), fan_r)


## ONE DUCTED FAN. Motor, three blades, a hoop that CONTAINS them, and three
## stator struts tying the hoop to the motor.
##
## The hoop is at DUCT_K * fan_r rather than the concept's 1.1 * fan_r — the
## reason is THE DROOPED ROTORS in the header and it is the one real argument
## this build has with the sheet. The blades keep the concept's three-fold count
## and reach to just inside the hoop.
func _fan(boom: Node3D, at: Vector3, fan_r: float) -> void:
	var fan := _node(boom, "Fan", at)
	var outer: float = fan_r * DUCT_K
	var tip: float = outer - BLADE_GAP
	_mesh(fan, "Motor", _cylm(0.16, 0.16, 0.20, 10), Vector3.ZERO)
	# A WIDER CHORD THAN THE CONCEPT'S 0.10. concept_kit.rotor()'s blade is a
	# sliver, which on a concept sheet is a line and on a real render is a
	# whisker. 0.19 is build_brood.gd's own correction and it is still a blade
	# and not a paddle.
	var blade := _boxm(Vector3(tip, 0.045, 0.19))
	for b in 3:
		var ba: float = TAU * float(b) / 3.0
		# Rotating about Y by -ba takes local +X to (cos ba, 0, sin ba), so the
		# blade's long axis and its offset from the motor point the same way and
		# the blade runs outward rather than across the hub.
		_mesh(fan, "Blade%d" % (b + 1), blade,
				Vector3(cos(ba) * tip * 0.5, 0.05, sin(ba) * tip * 0.5),
				Vector3(0.0, -ba, 0.0))
	_mesh(fan, "Duct", _torusm(outer - 0.10, outer), Vector3.ZERO)
	# THREE STATORS, offset 60 degrees from the blades so they never line up
	# with one. They are what stops the hoop reading as a halo floating around
	# the fan, and in the placed pose they are what says the hoop is still
	# attached to something.
	var span: float = outer - 0.21
	for s in 3:
		var sa: float = TAU * float(s) / 3.0 + PI / 3.0
		_mesh(fan, "Stator%d" % (s + 1), _boxm(Vector3(span, 0.05, 0.07)),
				Vector3(cos(sa) * (0.16 + span * 0.5), 0.0, sin(sa) * (0.16 + span * 0.5)),
				Vector3(0.0, -sa, 0.0))


# ─────────────────────────────────────────────
# THE PARK CRADLES — what makes a drooped rotor PARKED rather than BROKEN
# ─────────────────────────────────────────────
#
# Three saddles on the drum's shoulder, one per boom, each at the place that
# boom's motor actually comes to rest. MEASURED, NOT EYEBALLED: with the tower
# at PLACED_TOWER_Y and the boom at PLACED_DROOP, the motor ends at
#
#     y   = PLACED_TOWER_Y + sin(PLACED_DROOP) * reach
#     rho = cos(PLACED_DROOP) * reach
#
# and the saddle sits one motor-radius under that along the boom's own normal.
# The three come out at different radii and different heights because the booms
# are three different lengths, which is correct: a matched trio of cradles on an
# unmatched trio of booms would be the issued-hardware read this faction does
# not get.
#
# In flight they are three unequal pads bolted to the dome. That is the right
# Swarm read on its own, so nothing is paid for them in the flying state.
func _cradles(rig: Node3D) -> void:
	var cradles := _node(rig, "Cradles", Vector3.ZERO)
	var droop: float = PLACED_DROOP * DEG
	for i in FANS.size():
		var bearing: float = float(FANS[i][0])
		var reach: float = float(FANS[i][1])
		var y: float = PLACED_TOWER_Y + sin(droop) * reach
		var rho: float = cos(droop) * reach
		# The boom's own "down" is (0, -cos, +sin) once drooped; stepping along
		# it puts the saddle under the motor instead of inside it.
		var drop := 0.22
		var at := Vector3(0.0, y - drop * cos(droop), -(rho + drop * sin(droop)))
		var node := _node(cradles, "Cradle%d" % (i + 1), Vector3.ZERO,
				Vector3(0.0, bearing * DEG, 0.0))
		_mesh(node, "Saddle", _boxm(Vector3(0.34, 0.12, 0.30)), at,
				Vector3(droop, 0.0, 0.0))
		# Two lugs, because a pad is a pad and a pad with lugs is a fitting.
		for s in [-1.0, 1.0]:
			_mesh(node, "Lug%s" % ("L" if s < 0.0 else "R"),
					_boxm(Vector3(0.07, 0.20, 0.09)),
					at + Vector3(s * 0.17, 0.08 * cos(droop), -0.08 * sin(droop)),
					Vector3(droop, 0.0, 0.0))


# ─────────────────────────────────────────────
# THE SENSOR — six ocelli, and NOT AN EYE
# ─────────────────────────────────────────────
#
# PLACED ON THE ELLIPSOID, NOT NEAR IT. Each centre is the drum's actual surface
# point along a chosen direction — centre + dir * (DRUM_R * DRUM_SQUASH) — so
# every ocellus is exactly half-buried and therefore visibly proud of the skin.
# Nudged by eye against a squashed sphere they would have ended up floating off
# the flanks or sunk inside, which is the same mistake in two directions.
#
# THE ONLY PIECES ON THE FRAME THAT KEEP THEIR OWN MATERIAL. A sensor repainted
# in the faction colour on every faction is a sensor that identifies nothing.
#
# They are also the placed state's strongest claim to being alive: a wreck does
# not have six lit eyes on it. See THE DROOPED ROTORS in the header.
func _ocelli(rig: Node3D) -> void:
	var cluster := _node(rig, "SensorCluster", Vector3.ZERO)
	var mat := _ocellus_material()
	# direction, radius. No two sizes alike, no two spacings alike, and the
	# cluster is off-centre on the forward flank rather than set in a face.
	var eyes: Array = [
		[Vector3(0.14, 0.30, -0.94), 0.085],
		[Vector3(-0.29, 0.44, -0.85), 0.055],
		[Vector3(0.49, 0.21, -0.85), 0.047],
		[Vector3(-0.05, -0.18, -0.98), 0.068],
		[Vector3(-0.62, 0.12, -0.77), 0.036],
		[Vector3(0.33, 0.58, -0.75), 0.040],
	]
	var half := DRUM_R * DRUM_SQUASH
	for i in eyes.size():
		var d: Vector3 = (eyes[i][0] as Vector3).normalized()
		var on_skin := Vector3(d.x * half.x, d.y * half.y, d.z * half.z)
		var o := _unpainted_mesh(cluster, "Ocellus%d" % (i + 1),
				_spherem(float(eyes[i][1])), on_skin)
		o.material_override = mat
		_ocelli_count += 1


## Dark glass with a cold glow behind it. ONE MATERIAL FOR THE SIX, built fresh
## in this generator rather than loaded from a shared .tres: a material handed to
## two frames is one object, and this project has already paid for that once —
## see the duplicate() rule in CLAUDE.md.
##
## Green-white rather than the Broodcarrier's amber, because these two are the
## only Swarm frames in the game so far and giving them the same lit colour
## would be the first step toward a faction palette that nothing has decided.
## This is NOT a faction assignment: no faction is set on this frame and no enum
## is appended.
func _ocellus_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.09, 0.08)
	m.metallic = 0.5
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = Color(0.52, 0.95, 0.72)
	m.emission_energy_multiplier = 0.9
	return m
