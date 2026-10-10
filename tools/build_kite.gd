extends SceneTree

# ─────────────────────────────────────────────
# ONE-SHOT GENERATOR for Character/characters/ai/kite.tscn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_kite.gd
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
# The silhouette is CONCEPT D, SKYHOOK, already built in code as
# ConceptsA.kite_d() (tools/concepts_a.gd) out of the shared vocabulary in
# tools/concept_kit.gd. That function is the authority on proportions and
# positions and nothing here redesigns it: every rig-level number below is the
# concept's own, written as the concept's coordinate and passed through _a()
# so the two files can be diffed line against line.
#
# What this adds is everything a concept sheet does not need: a collision
# sphere, a rig hierarchy with a traversing turret, the shared robot_metal
# material on every piece, a faction livery list with the eye left off it, a
# weapon mount, and the Spotter's rotor loop.
#
# ─────────────────────────────────────────────
# THE ORIGIN CONVENTION — read this before moving anything
#
# The concept draws the Kite AIRBORNE, body at y 2.12, because a flyer with no
# legs drawn at y 0 reads as wreckage. A scene cannot keep that: the root's
# origin is what spotter_drone.gd holds at `ground + cruise_height`, what the
# ground ray casts down from, and what the collision sphere is centred on, so
# an origin 2 m under the aircraft would put the collider in the dirt and the
# altitude solver two metres out.
#
# So the whole frame is translated down by DATUM, which is the MIDPOINT OF ITS
# OWN BOUNDING BOX. The origin therefore lands at the aircraft's centre, the
# 0.7 m sphere is concentric with the mass it stands for, and the frame hangs
# half above and half below y 0 — the same convention both existing flyers use
# (the Spotter's core sits at y 0.05, the bomber's GLB is centred).
#
# Altitude is the flight code's job, not the scene's. Rendered on a floor this
# model is half-buried; in the air it is level.
#
# ─────────────────────────────────────────────
# WHERE THE WEAPON GOES, AND WHY
#
# The Kite is the first friendly flyer that shoots and there is no aerial mount
# to copy — the Spotter has weapon_slots = 0 and its whole weapon loop stubbed.
# KITE.md §5 settles the chain (Turret -> GunPivot -> WeaponMount) and the
# concept settles the place: "the entire weapon in a pod slung on a thin pylon
# and canted 24 degrees down", and its own comment says everything in the pod
# inherits that cant — "the gun, its eye and its ring all look where it shoots".
#
# So THE POD IS THE TURRET. `Turret` carries the -24 degrees of X rotation and
# every pod part hangs under it, which means:
#
#   * a fitted weapon inherits the down-cant for free, and a 24 degree depression
#     is exactly what a frame orbiting at altitude over ground targets wants;
#   * Node3D euler order is YXZ, so a later `turret.rotation.y = yaw` yaws about
#     the WORLD vertical and then applies the fixed cant. Traverse and cant do
#     not fight;
#   * NEGATIVE X is down. Rotating about +X maps -Z to (0, sin, -cos), so a
#     negative angle aims the muzzle at the floor — which is what is wanted here
#     and the sign three of Picket's first-round concepts got wrong.
#
# WeaponMount itself carries yaw +PI/2 AND NOTHING ELSE. +90, not -90: a
# weapon's muzzle runs down its own +X and the mount has to turn that onto the
# body's -Z. Built the other way the gun fits, elevates, tracks and fires
# directly behind the frame, and nothing complains.
#
# ITS OFFSET IS THE WALKER'S, SCALED. Walker turret space puts the mantlet at
# (-0.2, 0.02, -0.6) and the mount at (-0.2, 0.02, -0.72) — 0.01 inside the
# mantlet's front face. The Kite's pod is the same head at scale 0.6, so those
# become (-0.12, 0.012, -0.36) and (-0.12, 0.012, -0.432). A fitted machine_gun
# is 0.56 of receiver centred on the mount and 1.4 m of jacket, fins and flash
# hider in front of it, so the receiver sits in the pod and the barrel comes out
# of the port.
#
# THE CONCEPT'S STUB BARREL AND MUZZLE BRAKE ARE DELIBERATELY ABSENT, and this
# is the one place the model departs from kite_d(). Concept sheets draw a barrel
# because nothing is fitted to them; shipping frames do not — the Walker has a
# Mantlet and a mount and no barrel at all, and the gun is the weapon scene.
# Kept, the pod would carry a 0.9 m modelled barrel with a brake halfway along
# a fitted 1.4 m one. It costs the measured box 0.3 m of height and 0.4 m of
# length against the design doc's figure, which is reported rather than hidden.
#
# The brake was there to stop the pod reading as the enemy bomber's ordnance, so
# that job moves to `GunPort`: a ring round the barrel line on the mantlet face,
# wide enough (inner radius 0.12 against the receiver's 0.113 half-diagonal) for
# a fitted weapon to pass through it without clipping. A pod with a ringed
# aperture, a mantlet, an eye and an ammo drum does not read as a bomb.
#
# ─────────────────────────────────────────────
# WHAT THIS PASS CANNOT WIRE
#
# `Turret` and `GunPivot` EXIST, are named and are positioned — but they are not
# wired, because the root script is spotter_drone.gd and neither Enemy nor
# Soldier declares those exports (only walker.gd and rover.gd do). KITE.md §6
# is explicit that the `turret` export is kite.gd's job, and §6.2 is why it
# matters: enemy.gd:2895 reads
#
#     var hull_spoils_aim := _is_moving() and not ("turret" in self and get("turret") != null)
#
# so a flyer cruising at 18 m/s with no `turret` PROPERTY never leaves
# WeaponState.AIM and never fires — silently. The nodes are here so that script,
# when it is written, has only to point at them. No script was edited to make
# this model work.
#
# `GroundRay` is likewise absent on purpose: spotter_drone.gd builds it in
# _ready() (target (0,-300,0), mask 1) precisely so no drone scene can ship
# without one. Authoring a second would be a duplicate.
# ─────────────────────────────────────────────

const OUT := "res://Character/characters/ai/kite.tscn"
const METAL := "res://Character/characters/ai/robot_metal.tres"
const BARK := "res://Character/components/bark.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"
const OIL := "res://Character/components/oil_spray.tscn"
const LIVERY := "res://faction_livery.gd"
const BODY_SCRIPT := "res://Character/characters/ai/spotter_drone.gd"
const V1 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__17.wav"
const V2 := "res://sounds/sfx/Robot Droid Voices/WAV_RDV__19.wav"
const ROTOR_SFX := "res://sounds/sfx/quadcopter loop/freesound_community-mini-quadcopter-flying-loop-80330.mp3"

const DEG := PI / 180.0
## The Walker's eye: a plain StandardMaterial3D with this as albedo, not the
## shared faction metal. Carried over verbatim so every eye in the game is the
## same object on screen.
const EYE_TEX := "res://textures/PSX_Textures/robot_eye_psx.png"

## See THE ORIGIN CONVENTION above. Concept y minus this is scene y.
const DATUM := 2.00
## The concept builds the gun pod from ConceptKit.head() at this scale, and the
## Walker's own mount offsets are scaled by it below.
const POD_SCALE := 0.60

var _metal: Material
var _root: CharacterBody3D


func _init() -> void:
	_metal = load(METAL)
	var body := _build()
	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		printerr("build_kite: pack failed (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("build_kite: save failed (%s)" % error_string(err))
		quit(1)
		return
	_strip_mistyped_enum_arrays()
	print("build_kite: wrote %s" % OUT)
	quit(0)


## TWO LINES THE .tscn WRITER GETS WRONG, DELETED.
##
## Enemy declares `AllowedMovementOptions: Array[MovementOptions]` and
## `AllowedCombatOptions: Array[CombatOptions]` — arrays of an ENUM, so
## Array[int]. Probed on the live instance they are exactly that
## (get_typed_builtin() == TYPE_INT). The scene writer nevertheless emits them
## as `Array[ExtResource("...ai_equipment_slot.gd")]([])`, borrowing the element
## script from `equipment_slots` above them, and every load of the scene then
## prints
##
##     ERROR: Cannot assign contents of "Array[Object]" to "Array[int]".
##
## twice. bulwark.tscn has the identical pair and has been printing them since
## it was generated, so this is the family's bug and not this frame's — but it is
## a NEW scene and it should not arrive with two errors in it.
##
## Both values are empty, and empty is the script's own default, so deleting the
## lines changes nothing except the noise. The ExtResource they named is still
## referenced by `equipment_slots`, so load_steps is untouched. A real fix is a
## change to the shared generator idiom (or to Godot), which is not this pass's
## to make — see the report.
func _strip_mistyped_enum_arrays() -> void:
	var f := FileAccess.open(OUT, FileAccess.READ)
	if f == null:
		printerr("build_kite: could not reopen %s to clean it" % OUT)
		return
	var text := f.get_as_text()
	f.close()
	var kept := PackedStringArray()
	var dropped := 0
	for line in text.split("\n"):
		if line.begins_with("AllowedMovementOptions = Array[ExtResource") \
				or line.begins_with("AllowedCombatOptions = Array[ExtResource"):
			dropped += 1
			continue
		kept.append(line)
	if dropped == 0:
		# Say why nothing happened rather than passing silently: either the
		# writer was fixed, or the property names moved and this needs updating.
		print("build_kite: no mistyped enum arrays found — writer behaviour changed?")
		return
	var w := FileAccess.open(OUT, FileAccess.WRITE)
	if w == null:
		printerr("build_kite: could not rewrite %s" % OUT)
		return
	w.store_string("\n".join(kept))
	w.close()
	print("build_kite: dropped %d mistyped enum-array line(s)" % dropped)


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────

## A concept-space position, in scene space. Every rig-level number in _build()
## goes through here, so the figures can be read straight off kite_d().
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


## A chamfered slab, extruded: mockup_parts.plate(), which is what the concept's
## tail fin is. There is no mesh primitive for it, so this is CSG — a root of
## its own, baked like the hulls and collected by the livery the same way.
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


func _torusm(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 5
	return t


## ConceptKit.rotor(): a hub and `blades` thin bars lying flat, each box offset
## half its own length along its bearing and turned onto it, so a blade runs
## from the hub out to exactly `r`. The reading of "this flies" in one shape, and
## the only piece of the frame that is 2.20 m across.
func _rotor(parent: Node, nm: String, at: Vector3, yaw: float, r: float,
		blades: int) -> Node3D:
	var disc := _node(parent, nm, at, Vector3(0, yaw, 0))
	_mesh(disc, "Hub", _cylm(0.13, 0.18), Vector3.ZERO)
	for i in blades:
		var a := TAU * float(i) / float(blades)
		_mesh(disc, "Blade%d" % i, _boxm(Vector3(r, 0.035, 0.1)),
				Vector3(cos(a) * r * 0.5, 0.05, sin(a) * r * 0.5),
				Vector3(0, -a, 0))
	return disc


# ─────────────────────────────────────────────
# THE FRAME
# ─────────────────────────────────────────────
func _build() -> CharacterBody3D:
	var root_body := CharacterBody3D.new()
	root_body.name = "Kite"
	_root = root_body
	# PERSISTENT, or it is not saved into the scene at all. add_to_group's second
	# argument defaults to false, which means "for this run only" — the Bulwark's
	# first build packed a frame with no groups line, and a robot outside
	# "enemies" is invisible to AIManager, to EMP and to every hostile sweep in
	# the game while still flying around looking correct.
	root_body.add_to_group("enemies", true)
	root_body.set_script(load(BODY_SCRIPT))

	# ── collision and senses ──
	#
	# A SPHERE, like both existing flyers, and BIGGER THAN BOTH on purpose:
	# KITE.md §5 asks for ~0.7 against the Spotter's 0.5 and the bomber's 0.6.
	# At 0.5 m the Spotter is hard to hit by accident, and a 90-hull frame that
	# is MEANT to be shot down should be hittable on purpose. Concentric with
	# the origin, which the datum above puts at the aircraft's own centre.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	col.shape = sphere
	root_body.add_child(col)
	col.owner = root_body

	var bark := (load(BARK) as PackedScene).instantiate()
	bark.name = "Bark"
	# TYPED, OR THE ASSIGNMENT IS DISCARDED. bark_clips is Array[AudioStream];
	# handing it a plain Array fails silently and the instance keeps bark.tscn's
	# three defaults. bulwark.tscn is the proof — its generator sets two clips and
	# the saved scene has three. Same trap as visible_pieces, different property.
	var clips: Array[AudioStream] = []
	clips.append(load(V1))
	clips.append(load(V2))
	bark.set("bark_clips", clips)
	# Pitched UP, where the Bulwark is pitched down. It is a 90-hull airframe
	# made of paper and it should not sound like the thing pushing a wall.
	bark.set("pitch_min", 1.02)
	bark.set("pitch_max", 1.14)
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

	# HULL. The Walker's chamfered block at 0.70 x 0.46 x 0.90 — small, because
	# the silhouette's argument is that the body exists to carry the gun pod
	# somewhere high rather than to be anything itself. `size` is the UNCUT
	# block; the four subtractions below take material off it.
	var hull := _hull(rig, "Hull", Vector3(0.70, 0.46, 0.90), _a(0, 2.12, 0))
	_cut(hull, "Glacis", Vector3(0.98, 0.552, 0.72), Vector3(0, -0.3312, -0.558),
			Vector3(-30.0 * DEG, 0, 0))
	_cut(hull, "Tail", Vector3(0.98, 0.552, 0.54), Vector3(0, -0.3128, 0.576),
			Vector3(20.0 * DEG, 0, 0))
	for s in [-1.0, 1.0]:
		_cut(hull, "Bevel%s" % ("L" if s < 0.0 else "R"),
				Vector3(0.49, 0.368, 1.26), Vector3(s * 0.476, 0.3036, 0),
				Vector3(0, 0, s * 30.0 * DEG))

	# MAST, and COAXIAL ROTORS — the whole reason this frame cannot be mistaken
	# for the Spotter or the enemy quadcopter. Two discs on one mast with the
	# lower turned 60 degrees so its blades sit between the upper's: from above
	# that is six blades on one hub, which no four-arm X can look like.
	_mesh(rig, "Mast", _cylm(0.10, 0.60), _a(0, 2.48, 0))
	var rotor_up := _rotor(rig, "RotorUpper", _a(0, 2.72, 0), 0.0, 1.10, 3)
	var rotor_lo := _rotor(rig, "RotorLower", _a(0, 2.46, 0), 60.0 * DEG, 1.10, 3)

	# Tail fin: a chamfered plate stood on edge behind the hull, 0.48 fore-and-aft
	# by 0.42 tall. It is what keeps the frame from reading as symmetrical from
	# above, which is the other half of not being a quadcopter.
	_plate(rig, "TailFin", 0.48, 0.42, 0.05, 0.08, _a(-0.025, 2.18, 0.64),
			Vector3(0, PI * 0.5, 0))

	# THE PYLON, thin and short, with daylight either side of it. The gap is the
	# silhouette break: a pod faired into the body would read as a fat fuselage
	# and the frame would stop being a diagram of its own job.
	_mesh(rig, "Pylon", _boxm(Vector3(0.12, 0.46, 0.14)), _a(0, 1.78, -0.04))

	var turret := _gun_pod(rig)

	# ── effects, livery ──
	var spark := (load(SPARK) as PackedScene).instantiate()
	spark.name = "SparkBurst"
	root_body.add_child(spark)
	spark.owner = root_body
	var oil := (load(OIL) as PackedScene).instantiate()
	oil.name = "OilSpray"
	root_body.add_child(oil)
	oil.owner = root_body

	# THE ROTOR LOOP. spotter_drone.gd declares `rotor_loop` and stops it when
	# the frame is parked at base, crashes or is downed, and plays it again on
	# revive — so a flyer without this node is silent through all four. Both
	# existing aerials carry the same stream at the same levels.
	var rotor_loop := AudioStreamPlayer3D.new()
	rotor_loop.name = "RotorLoop"
	rotor_loop.stream = load(ROTOR_SFX)
	rotor_loop.volume_db = -8.0
	rotor_loop.unit_size = 14.0
	rotor_loop.autoplay = true
	root_body.add_child(rotor_loop)
	rotor_loop.owner = root_body

	var livery := Node.new()
	livery.name = "FactionLivery"
	livery.set_script(load(LIVERY))
	root_body.add_child(livery)
	livery.owner = root_body
	livery.set("base_material", _metal)
	livery.set("paint_blend", 1.0)
	# EVERY PAINTED PIECE, NAMED ONE AT A TIME, in a TYPED array.
	#
	# `pieces` is Array[Node3D]; an untyped one lands as [] and FactionLivery
	# then falls back to walking its whole parent — which paints every mesh on
	# the frame, THE EYE INCLUDED. That is how the Bulwark's eye ended up
	# faction-coloured despite being carefully left off a list that was never
	# there.
	#
	# And named one at a time rather than by group because _gather() RECURSES:
	# listing `Turret` or `Head` would collect the eye through it and undo the
	# exclusion just as thoroughly.
	#
	# THE EYE IS DELIBERATELY ABSENT. It keeps its own StandardMaterial3D,
	# the Walker's, because the one feature that identifies a robot in this game
	# must not change colour per faction.
	var paint: Array[Node3D] = []
	paint.append(hull)
	paint.append(rig.get_node("Mast"))
	paint.append(rig.get_node("TailFin"))
	paint.append(rig.get_node("Pylon"))
	for disc in [rotor_up, rotor_lo]:
		paint.append(disc.get_node("Hub"))
		for i in 3:
			paint.append(disc.get_node("Blade%d" % i))
	paint.append(turret.get_node("MountRing"))
	paint.append(turret.get_node("AmmoDrum"))
	paint.append(turret.get_node("DrumBand"))
	paint.append(turret.get_node("Head/HeadBody"))
	paint.append(turret.get_node("GunPivot/Mantlet"))
	paint.append(turret.get_node("GunPivot/GunPort"))
	livery.set("pieces", paint)

	# ── the body's own exports ──
	#
	# NODE OBJECTS, NOT NODE PATHS. Every one of these is typed Node3D, Bark,
	# Area3D, AudioStreamPlayer3D or Array[Node3D] — not NodePath — so assigning
	# a NodePath silently does nothing and the frame comes out with a null mount
	# and no senses. Nothing errors. PackedScene.pack() turns these references
	# back into the node_paths=PackedStringArray(...) form the editor writes, so
	# the saved scene looks hand-authored either way.
	root_body.set("nav_agent", nav)
	root_body.set("bark", bark)
	root_body.set("detection", det)
	root_body.set("rotor_loop", rotor_loop)
	root_body.set("weapon_mount", turret.get_node("GunPivot/WeaponMount"))
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
	# EVERY TOP-LEVEL PIECE OF THE RIG, not a sample of it. hide_body() sets
	# `visible = false` on exactly this list, so anything missing from it stays
	# drawn on a hidden robot — the Spotter lists its core and arms and leaves
	# four rotors hanging in the air. Groups rather than meshes because a Node3D
	# hides its children with it, and Enemy's death collapse applies its pitch in
	# the BODY's space, so the whole frame tips about one point.
	var vis: Array[Node3D] = []
	vis.append(hull)
	vis.append(rig.get_node("Mast"))
	vis.append(rig.get_node("TailFin"))
	vis.append(rig.get_node("Pylon"))
	vis.append(rotor_up)
	vis.append(rotor_lo)
	vis.append(turret)
	root_body.set("particle_effects_die", dies)
	root_body.set("particle_effects_hit", hits)
	root_body.set("visible_pieces", vis)
	# The Spotter's 250, not the ground frames' 75-200: an aircraft at cruise is
	# visible from much further away than it can be walked to, and culling one at
	# 200 m makes it vanish in mid-air. See the ADVANCE-freeze note in CLAUDE.md
	# — always_active does not exempt a frame from culling.
	root_body.set("activation_distance", 250)
	# 90, from KITE.md §3: above the Spotter's 80, far under the Rover's 180.
	# It is made of paper and that is the point — a frame you commit and protect.
	root_body.set("health", 90)
	root_body.set("max_health", 90)
	# The Spotter's authored flight speed. The doc's base_speed of 1.2 is a
	# CHASSIS multiplier applied on top of this (see Campaign/item_facts.gd), and
	# that resource is out of scope for a model pass — setting 21.6 here would
	# double-count it.
	root_body.set("move_speed", 18.0)
	root_body.set("soldier_name", "Kite")
	# Both flyers set this false: there is no standing corpse to flatten, and a
	# crashed airframe keeps its shape.
	root_body.set("flatten_collider_when_downed", false)
	return root_body


## THE GUN POD — the turret, and the frame's whole proposition.
##
## One node at the pod's position carrying the 24 degree down-cant, with
## everything the concept hangs on the pod beneath it. See WHERE THE WEAPON GOES
## in the header for why the cant lives here, why it is negative, and why the
## concept's stub barrel is not rebuilt.
func _gun_pod(rig: Node3D) -> Node3D:
	var turret := _node(rig, "Turret", _a(0, 1.52, -0.08), Vector3(-24.0 * DEG, 0, 0))

	# THE COLLAR THE POD HANGS ON, and the one piece whose POSITION is not the
	# concept's — because the concept's is inside the pod.
	#
	# ConceptKit.head() puts its ring at `at` and the turret body at
	# `at + 0.19 * scale`, and the body is 0.6 * scale tall. At every scale that
	# leaves the ring INSIDE the body: measured on the built scene it came out at
	# y -0.754..-0.425 within a head body of -0.809..-0.162, and radius 0.324
	# inside a half-width of 0.354. Six faces of it, buried. It never rendered on
	# the concept sheet either; nobody could have seen it.
	#
	# So it is moved to the one place a mount ring means anything on a slung pod:
	# seated on the pod's top face at the point where the pylon enters it, which
	# measures turret-local (0, 0.174, 0.121). Radius 0.324 there would be a lid
	# covering a 0.708-wide pod, so it comes down to 0.20 and reads as a flange.
	# Solid, not a hole — the pylon runs into it the way a pylon runs into a
	# mounting plate.
	_mesh(turret, "MountRing", _cylm(0.20, 0.072), Vector3(0, 0.205, 0.121))

	# ── HEAD ──
	# The Walker's turret profile at 0.6: a box with the cheek sliced off below
	# and the brow sliced off above. That profile plus one offset eye is how a
	# frame in this game is recognised at forty pixels.
	var head := _node(turret, "Head", Vector3(0, -0.006, 0))
	var head_body := _hull(head, "HeadBody", Vector3(0.708, 0.36, 0.78), Vector3.ZERO)
	_cut(head_body, "Cheek", Vector3(0.9204, 0.42, 0.42), Vector3(0, -0.264, -0.516),
			Vector3(-35.0 * DEG, 0, 0))
	_cut(head_body, "Brow", Vector3(0.9204, 0.42, 0.42), Vector3(0, 0.30, -0.468),
			Vector3(25.0 * DEG, 0, 0))

	# ONE EYE, offset left, squashed, and carrying the WALKER'S OWN material
	# rather than the shared metal — a StandardMaterial3D with the eye texture as
	# albedo. Deliberately left out of the livery list above: painting it with the
	# faction colour like everything else would make the one feature that
	# identifies a robot change colour per side. KITE.md asks for exactly one.
	var eye := _mesh(head, "Eye", _spherem(0.102), Vector3(-0.204, 0.084, -0.396))
	eye.scale = Vector3(1.0, 0.82, 1.0)
	eye.material_override = _eye_material()

	# NO ANTENNA. ConceptKit.head() hangs the Walker's whip off the back corner,
	# which is right for a turret standing on top of a hull and wrong for a pod
	# hanging under one: built, it measured y -0.232..0.241 at x -0.30, z ~0.0 —
	# a 0.51 m rod whose upper 0.35 m runs straight up inside the fuselage, with
	# two millimetres of tip clearing the hull's port bevel. It is in the concept
	# too and photographs as a bar crossing the body.
	#
	# There is nowhere else on this frame for a whip: the hull's roof is the
	# rotor mast, and anything standing off it reaches into a 1.10 m disc. The
	# tail fin carries the aerial reading instead, which is what a blade antenna
	# is anyway.

	# ── GUN PIVOT ──
	# Exists, named and placed, and at ZERO rotation because that is where the
	# aiming code expects to find it — any rest pose here would be clamped
	# straight back to level the moment something pitched it. It is unwired: see
	# WHAT THIS PASS CANNOT WIRE in the header.
	var pivot := _node(turret, "GunPivot", Vector3(0, -0.024, -0.30))
	_mesh(pivot, "Mantlet", _boxm(Vector3(0.30, 0.216, 0.156)), Vector3(-0.12, 0.036, -0.072))
	# The aperture ring on the mantlet face — the concept's muzzle brake, moved
	# to where the barrel now begins instead of where a stand-in barrel used to
	# end. Inner radius 0.12 clears a fitted machine_gun's receiver, whose
	# half-diagonal is 0.113, so the weapon passes through rather than into it.
	_mesh(pivot, "GunPort", _torusm(0.12, 0.15), Vector3(-0.12, 0.036, -0.155),
			Vector3(PI * 0.5, 0, 0))
	# YAW +PI/2 AND NOTHING ELSE. The down-cant is the pod's, inherited; putting
	# any of it here would both double it and break the one assertion that
	# catches a backwards mount. See the header.
	_node(pivot, "WeaponMount", Vector3(-0.12, 0.036, -0.132), Vector3(0, PI * 0.5, 0))

	# AMMO DRUM on the pod's flank, laid across the airflow. With the port and
	# the mantlet it is what says "gun" on a frame carrying no barrel of its own,
	# and the concept's note for it is "so the pod has a mass to it".
	#
	# MOVED OUTBOARD, for that reason. The concept centres it at x 0.22 with a
	# length of 0.34 on a pod 0.708 wide, so it runs x 0.05..0.39 against a flank
	# at 0.354 — thirty-six millimetres of a 0.28 m drum outside the body and the
	# rest of it, and the whole band, inside. A mass that is inside the pod is
	# not a mass. Centred at 0.40 it beds 0.124 into the flank and stands 0.216
	# proud, which is a drum bolted on.
	_mesh(turret, "AmmoDrum", _cylm(0.14, 0.34, 10), Vector3(0.40, -0.02, 0.18),
			Vector3(0, 0, PI * 0.5))
	_mesh(turret, "DrumBand", _torusm(0.14, 0.19), Vector3(0.40, -0.02, 0.18),
			Vector3(0, 0, PI * 0.5))
	return turret


## The eye's own material. Built fresh rather than shared, because a material
## handed to two frames is one object — see the duplicate() rule in CLAUDE.md.
func _eye_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(EYE_TEX)
	return m
