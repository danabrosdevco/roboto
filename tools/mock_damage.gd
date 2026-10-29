extends SceneTree

# ─────────────────────────────────────────────
# MOCK DAMAGE — poses a frame into a damage state and photographs it.
#
#   godot --audio-driver Dummy --path . --script res://tools/mock_damage.gd -- <out dir> [what]
#
# `what` is `all` (the default), or one of `kinetic`, `ekill`, `eye`, `frames`.
#
# IT NEEDS A WINDOW. Run it WITHOUT --headless. Two reasons, and the second one
# is the one that bites: the grab is off the real viewport, AND the signal
# filter READS THE SCREEN. A headless run has no screen to read, so the filter
# contributes nothing, the shot comes back flat, and it looks like proof.
#
# ─────────────────────────────────────────────
# THIS IS A MOCK-UP GENERATOR. IT IS NOT A DAMAGE SYSTEM.
#
# Nothing here is wired into anything. It does not touch enemy.gd, it does not
# call die(), apply_damage() or _collapse_pieces(), and no frame scene is
# modified on disk. It instantiates a frame, shoves its nodes into a shape that
# LOOKS like a damage state, takes the photograph and frees it.
#
# The point of doing it this way is that the frames are already built out of
# separate named nodes, so every state below is a reparent, a rotation, or one
# material write. If the design is approved, the real work is deciding WHEN
# each of these happens — not building the geometry, which exists.
#
# What is faked, and must not be read as a design claim:
#   - detached parts are POSED on the deck, not dropped by a RigidBody3D. A
#     still photograph cannot tell the difference and a posed part lands in the
#     same place every run, which is what makes two shots comparable.
#   - the oil leak is a looping emitter built here, not the frame's own
#     OilSpray, which is a 0.6 s one-shot and is over before a shot settles.
#   - the e-kill "sequence" is four separate staged frames, not an animation.
#
# ─────────────────────────────────────────────
# THE FIVE THINGS THAT COST TIME WHEN THIS WAS WRITTEN
#
# 1. THE PARTS ARE MOSTLY MeshInstance3D, NOT CSG. Only the Hull, the turret
#    body and the bolt-on plates are CSGMesh3D roots; thighs, shins, feet,
#    lenses, dishes and studs are plain MeshInstance3D with primitive meshes.
#    That matters twice: a primitive mesh is CLOSED, so detaching a leg leaves
#    no open cut face at all (see _stump and the DISMEMBERMENT doc), and a
#    CSGBox3D sitting UNDER a CSGMesh3D is an operand of that root rather than
#    a piece of its own — detaching one changes the parent's shape instead of
#    taking a panel off. Anything that is to come off has to be a render root.
#
# 2. walker.gd's _pose_leg ASSIGNS hip/knee/foot rotations every physics frame.
#    A limb reparented to the world while still named by `hip_right` is driven
#    from a body it has left. _unwire() nulls the export before the reparent,
#    and SAYS which ones it cut. Physics is off in here, so this is belt and
#    braces for the mock-up and the actual fix for the real thing.
#
# 3. SUB-RESOURCE MATERIALS ARE SHARED BETWEEN INSTANCES of the same scene, and
#    FactionLivery's are shared between every robot of a faction on purpose.
#    So every write goes through _own(), which duplicates once and marks the
#    node. Without it, darkening one Bastion's plate darkened all five in the
#    row shot — which is how the first run of the progression came back with
#    the control scorched.
#
# 4. THE EYE IS NOT EMISSIVE. Every player-lineage frame has one offset Eye
#    whose material is deliberately off the FactionLivery list — that part is
#    true and it is the free win it is claimed to be. But the material is a
#    StandardMaterial3D carrying `albedo_texture` and NOTHING ELSE: no
#    emission_enabled, no emission, no energy. So "one emission_energy write"
#    does nothing on any frame in the game as it stands. _eye() turns emission
#    ON for the live state, which is the change the tell needs.
#
# 5. A BARE LEVEL HAS NO HUD AND THEREFORE NO FILTER. mockup_shots.gd's frame
#    pass loads the base level alone, which is right for its purpose and wrong
#    here. _install_filter() lifts the SignalFilter ColorRect out of
#    hud.tscn WITHOUT putting the HUD in the tree, so it arrives carrying the
#    scene's authored uniforms rather than the shader's declared defaults —
#    which is where three "the lighting is broken" investigations went.
# ─────────────────────────────────────────────

## For the reason bake_icons.gd records: pull the robot script in FIRST, or a
## chassis scene loading mid-load goes round in a circle and soldier.gd reports
## missing.
const _SOLDIER := preload("res://Character/characters/ai/soldier.gd")
const _SignalArc := preload("res://Character/weapon/appx/signal_arc.gd")

## THE LIVE BASE. This used to be depot_level, which was retired on 2026-10-24
## (vault Backlog H15) — the railhead is the base world.tscn actually loads.
## NOTHING ABOUT THE LIGHT CHANGED, which is worth knowing before anyone moves
## it again: both levels instance the same Env/world_environment.tscn, so the
## sun is the same sun on the same bearing at the same energy, and LIT below
## still points across it. What did change is the deck, 16.50 → 11.00 — and
## that is probed rather than typed, so it cost nothing.
const LEVEL := "res://maps/railhead_level.tscn"
const HUD := "res://Character/hud/hud.tscn"
const SPARK := "res://Character/components/spark_burst.tscn"

## Where the frames stand. The level's own deck height is PROBED, not assumed
## — see _ground(). This is only the x/z the stage sits at.
const STAGE := Vector3(0.0, 0.0, 0.0)

## THE PLAYER'S EYE. Every shot is taken from the height the game is seen from,
## because a damage state that reads from a 10 m crane shot and not from here
## is a damage state the player never sees.
const EYE := 1.50

const FRAMES := {
	"bastion": "res://Character/characters/ai/bastion.tscn",
	"see_engine": "res://Character/characters/ai/see_engine.tscn",
	"tick": "res://Character/characters/ai/tick.tscn",
	"brood": "res://Character/characters/ai/brood.tscn",
	"vessel": "res://Character/characters/ai/vessel.tscn",
}

## The three that belong to a hostile faction, photographed in the livery they
## will wear. mockup_shots.gd keeps the same list for the same reason.
const ENEMY_FRAMES := ["brood", "bastion", "see_engine", "tick"]

## Node paths on the Bastion, which carries states A and B. Named here rather
## than inline because every one of them is a claim about the scene that will
## go stale if the frame is rebuilt, and a missing one has to say so loudly
## rather than photograph an intact robot into a slot labelled "crippled".
## ALL THREE ON THE SAME FLANK, and the eye is on that flank too.
##
## The first pass struck the LEFT applique and took the RIGHT skirt and the
## RIGHT leg, which is a perfectly good spread of damage and photographs as
## nothing: no single camera position can see both sides of a 3.5 m hull, so
## "scuffed" and "breached" came out as two pictures of an undamaged robot from
## the blind side. The frame's one Eye sits at x −0.272 — the left — so the left
## is the side the camera has to be on, and everything that happens has to
## happen there.
##
## This is a mock-up convenience, not a design claim. In the real thing damage
## lands where the round lands.
const BAST := {
	"plate": "Rig/AppliqueL",                 # bolt-on applique: Plate + 4 studs
	"panel": "Rig/Skirts/SkirtL",             # the detachable sheet
	"limb": "Rig/HipL",                       # a whole leg subtree, 1 of 4
	"eye": "Rig/Turret/Eye",
	"lamps": [                                # top-down, the eye is NOT in here
		"Rig/Mast/Canopy/Lenses/Lens0",
		"Rig/Mast/Canopy/Lenses/Lens1",
		"Rig/Mast/Canopy/Lenses/Lens2",
		"Rig/Mast/Canopy/Lenses/Lens3",
	],
	"knees": [
		"Rig/HipL/SplayL/KneeL",
		"Rig/HipR/SplayR/KneeR",
		"Rig/HipLA/SplayLA/KneeLA",
		"Rig/HipRA/SplayRA/KneeRA",
	],
}

## Every node-path export on walker.gd / rover.gd / enemy.gd that NAMES a piece
## of the rig. A detached part has to come off all of them.
##
## `rig` is deliberately in the list and deliberately never matched in practice
## — nothing detaches the whole rig — but leaving it out would have made this
## table read as "the leg joints", which is the wrong mental model. It is "every
## export that points into the body".
const POSE_EXPORTS := ["rig", "turret", "gun_pivot", "hip_left", "hip_right",
		"knee_left", "knee_right", "foot_left", "foot_right",
		"wheels", "reverse_lamps", "visible_pieces"]

var _cam: Camera3D
var _level: Node
var _deck: float = 0.0
var _notes: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mock_damage: this photographs the game AND the signal filter reads the")
		printerr("            screen, so run it WITHOUT --headless or every shot is a lie.")
		quit(1)
		return
	# Nothing in here reads Settings, but every tool in this folder points it at
	# a probe path and the one that does not is the one that eventually writes.
	Settings.path = "user://settings_probe.json"

	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mock_damage"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var what: String = args[1].strip_edges().to_lower() if args.size() > 1 else "all"

	await _boot()
	print("mock_damage: frames are %dx%d, eye at %.2f m, deck probed at y=%.3f" % [
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
		EYE, _deck])

	if what == "all" or what == "kinetic":
		await _sheet_kinetic(out_dir)
	if what == "all" or what == "ekill":
		await _sheet_ekill(out_dir)
	if what == "all" or what == "eye":
		await _sheet_eye(out_dir)
	if what == "all" or what == "frames":
		await _sheet_frames(out_dir)

	print("")
	print("mock_damage: written to %s" % ProjectSettings.globalize_path(out_dir))
	if not _notes.is_empty():
		print("")
		print("WHAT THIS RUN COULD NOT DO — read this before trusting a shot:")
		for n in _notes:
			print("  * %s" % n)
	quit(0)


## Says it once, in the run summary as well as in place. A warning in a 400-line
## console log is a warning nobody reads.
func _note(text: String) -> void:
	push_warning("mock_damage: %s" % text)
	if not _notes.has(text):
		_notes.append(text)


# ─────────────────────────────────────────────
# THE RIG
# ─────────────────────────────────────────────
func _boot() -> void:
	# A REAL LEVEL FIRST, for its WorldEnvironment and its sun. The base has no
	# light of its own in its own file — it instances Env/world_environment.tscn
	# — which is why this loads the level rather than building a
	# DirectionalLight3D: a hand-built sun is a different sun from the game's and
	# the whole point is this frame's own light.
	_level = load(LEVEL).instantiate()
	root.add_child(_level)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	root.add_child(_cam)
	_cam.current = true
	_install_filter()
	# Terrain, CSG and the navmesh all settle a frame or two after entering the
	# tree. A grab before that photographs a level with holes in it.
	for _i in 60:
		await process_frame
	_deck = _ground(STAGE)


## The real post-process, with the real uniforms.
##
## hud.tscn is INSTANTIATED BUT NEVER ADDED TO THE TREE, so no _ready() on it
## runs — the HUD wants a Player, a campaign and a squad, none of which this rig
## has, and all this needs is one ColorRect. The ShaderMaterial comes with it,
## carrying the values hud.tscn authored (luma_levels 10, signal_height 360,
## palette_strength 0.6 and the rest) rather than the shader's own defaults,
## which are different numbers and a different-looking game.
func _install_filter() -> void:
	var ps := load(HUD) as PackedScene
	if ps == null:
		_note("hud.tscn would not load, so NO SIGNAL FILTER is on any shot in this run.")
		return
	var hud: Node = ps.instantiate()
	var rect := hud.get_node_or_null("SignalFilter") as Control
	if rect == null:
		_note("hud.tscn has no SignalFilter child any more, so NO FILTER is on these shots.")
		hud.free()
		return
	if rect.material == null:
		_note("hud.tscn's SignalFilter carries no material, so the shots are unfiltered.")
	# remove_child BEFORE anything else: queue_free is deferred and freeing the
	# HUD with the rect still under it would take the rect with it.
	hud.remove_child(rect)
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.free()
	print("mock_damage: signal filter installed from %s" % HUD)


## The deck under a point, measured. Everything in this file stands on what this
## returns, because a typed floor height drifts the first time TERRAIN rebuilds
## a map and then every frame in every shot floats or sinks by the same amount
## and it looks deliberate.
func _ground(at: Vector3) -> float:
	var space := root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0, 40, 0), at + Vector3(0, -40, 0))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_note("no deck under %s in %s, so frames are parked at y=0 and may float."
				% [str(at), LEVEL.get_file()])
		return 0.0
	return (hit["position"] as Vector3).y


# ─────────────────────────────────────────────
# SPAWNING AND PLACING
# ─────────────────────────────────────────────
func _spawn(id: String) -> Node3D:
	if not FRAMES.has(id):
		_note("no frame called '%s', so whatever it was going to show is missing." % id)
		return null
	var bot: Node3D = load(FRAMES[id]).instantiate()
	# BEFORE IT ENTERS THE TREE. FactionLivery reads `faction` off its parent in
	# _ready, so setting it afterwards leaves the robot in the wrong colours and
	# needs a second repaint to fix.
	bot.faction = Enums.Factions.ENEMY if id in ENEMY_FRAMES else Enums.Factions.PLAYER
	# The scene's own hat off: RankKit reads this in _ready and an empty one
	# means "chose none". A cosmetic is not what any of these shots is about.
	bot.set_meta("cosmetic_id", &"")
	root.add_child(bot)
	# A photograph, not a fight. A robot left thinking walks out of shot looking
	# for something to shoot, and _pose_leg would rewrite every joint this file
	# sets.
	bot.set_physics_process(false)
	bot.set_process(false)
	return bot


## Stand it on the deck, feet down, by MEASUREMENT. A frame's origin is not its
## feet and it is not the same distance off them on any two frames — the Tick's
## is inside the drum, the Vessel's is a metre up.
func _stand(bot: Node3D, at: Vector3) -> void:
	bot.global_position = Vector3(at.x, _deck, at.z)
	# CSG rebuilds the frame after it enters the tree; an AABB read before that
	# measures half-built armour.
	for _i in 12:
		await process_frame
	var bb := _aabb(bot, bot)
	if bb.size == Vector3.ZERO:
		_note("%s measured as nothing drawn, so it is standing on its origin." % bot.name)
		return
	bot.global_position.y = _deck - bb.position.y


## Subtraction shapes do not count: a glacis cut is deliberately oversized and
## counting it framed the Walker as twice its width. Lifted from
## mockup_shots.gd, which learned this the hard way.
func _aabb(n: Node, body: Node3D) -> AABB:
	if n is CSGShape3D and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
		return AABB()
	var out := AABB()
	var started := false
	for c in n.get_children():
		var sub := _aabb(c, body)
		if sub.size != Vector3.ZERO:
			out = sub if not started else out.merge(sub)
			started = true
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var local := body.global_transform.affine_inverse() * vi.global_transform
		var a := local * vi.get_aabb()
		out = a if not started else out.merge(a)
	return out


## Three-quarter on, by measurement. look_at to a camera ABOVE the subject
## pitches the subject forward to meet it and the photograph comes back of a
## robot falling over, so aim at the camera's GROUND position and let the yaw be
## the only thing that changes.
func _face(bot: Node3D, extra_yaw_deg: float = 34.0) -> void:
	var flat := Vector3(_cam.global_position.x, bot.global_position.y, _cam.global_position.z)
	if flat.is_equal_approx(bot.global_position):
		return
	bot.look_at(flat, Vector3.UP)
	bot.rotate_y(deg_to_rad(extra_yaw_deg))


## THE BEARING THE LIGHT IS ON. Every wide shot uses it unless there is a reason
## not to: the base's sun comes across the stage, and a camera on -Z alone
## photographs five backlit silhouettes that are all the same shape. This is the
## bearing the close eye shots came out lit on, measured off those.
const LIT := Vector3(-0.5, 0.0, -0.87)

## Screen-right for a camera on LIT, so a row laid along it reads left to right.
## forward x up, with the y dropped out.
const ACROSS := Vector3(-0.87, 0.0, 0.5)


## The camera, at the player's eye, pulled back far enough to hold `span` metres
## of subject ACROSS the frame AND `height` metres UP it.
##
## BOTH DIMENSIONS, and the second one was the bug. Fitting the width alone put
## a 4.5 m Bastion four metres from the lens with its head and its feet out of
## frame, and the close shots came back as photographs of a hull. A frame that
## stands taller than it is wide — which is most of them — is framed by its
## height, so the distance is whichever of the two is further and the aim sits
## at the middle of the subject rather than at a typed 1.6 m.
##
## THE AIM HEIGHT IS NOT THE STAGE'S y, EITHER. STAGE is an x/z mark with a zero
## in the middle of it and the base's deck is a long way off zero — 16.5 on the
## old depot, 11.0 on the railhead — so the first run aimed every wide shot
## sixteen metres into the ground and the progression sheet came back as a
## photograph of the floor with no robots in it. Everything vertical in this
## file goes through _deck, which is why the 2026-10-24 level swap did not
## repeat it.
func _frame_up(centre: Vector3, span: float, bearing: Vector3 = LIT,
		height: float = 2.2) -> void:
	var dir := Vector3(bearing.x, 0.0, bearing.z).normalized()
	var aspect := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)) \
			/ maxf(1.0, float(ProjectSettings.get_setting("display/window/size/viewport_height", 648)))
	var half_v := deg_to_rad(_cam.fov) * 0.5
	var half_h := atan(tan(half_v) * aspect)
	var mid: float = maxf(0.4, height * 0.5)
	var dist: float = (span * 0.58) / maxf(0.05, tan(half_h))
	# The vertical fit is NOT symmetric about the aim, because the camera is at
	# the player's eye and the aim is at the middle of a robot that may be three
	# times that high. Solved by walking the distance out until both the feet and
	# the crown fall inside the half-angle, which is shorter than the algebra and
	# does not get the sign wrong.
	for _i in 60:
		var a_aim := atan2(mid - EYE, dist)
		var a_top := atan2(height + 0.7 - EYE, dist)
		var a_bot := atan2(-EYE - 0.7, dist)
		if maxf(absf(a_top - a_aim), absf(a_bot - a_aim)) <= half_v:
			break
		dist += 0.35
	_cam.global_position = Vector3(centre.x, _deck + EYE, centre.z) + dir * dist
	_cam.look_at(Vector3(centre.x, _deck + mid, centre.z), Vector3.UP)


# ─────────────────────────────────────────────
# MATERIALS — every write goes through here
# ─────────────────────────────────────────────
## This node's OWN copy of its material.
##
## NOT OPTIONAL. FactionLivery hands the SAME ShaderMaterial to every robot of a
## faction in the whole level on purpose, and a .tscn's sub-resource materials
## are shared between instances of that scene. So one unguarded write scorches
## every frame in the shot. Duplicated once and marked, so repeated writes to
## the same node do not pile up copies.
const _OWNED := &"mock_damage_owned"


func _own(gi: GeometryInstance3D) -> Material:
	if gi == null:
		return null
	var mat := gi.material_override
	if mat == null and gi is CSGShape3D:
		mat = (gi as CSGShape3D).material
	if mat == null and gi is MeshInstance3D:
		var mesh := (gi as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			mat = mesh.surface_get_material(0)
	if mat == null:
		return null
	if gi.has_meta(_OWNED):
		return gi.material_override
	var mine := mat.duplicate()
	mine.resource_local_to_scene = true
	gi.material_override = mine
	gi.set_meta(_OWNED, true)
	return mine


## Every drawn thing at or under a node. A CSG shape's children are operands of
## it rather than renderers of their own, so the walk stops there.
func _drawn(node: Node, into: Array[GeometryInstance3D]) -> void:
	if node == null:
		return
	if node is CSGShape3D or node is MeshInstance3D:
		into.append(node as GeometryInstance3D)
		if node is CSGShape3D:
			return
	for c in node.get_children():
		_drawn(c, into)


## Scorch. `amount` 0 is untouched, 1 is burnt through.
##
## Two material families and they darken differently. FactionLivery's
## faction_metal.gdshader has `base_tint` and a `shutdown` that kills the accent
## markers, which is exactly what a struck plate should do — the paint goes and
## the markings go with it. A StandardMaterial3D (lenses, the eye) has neither,
## so its albedo is dimmed directly.
func _scorch(node: Node, amount: float) -> void:
	var pieces: Array[GeometryInstance3D] = []
	_drawn(node, pieces)
	if pieces.is_empty():
		_note("nothing drawn under %s, so the scorch has no surface to land on." % node.name)
		return
	var k := clampf(amount, 0.0, 1.0)
	for gi in pieces:
		var mat := _own(gi)
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			sm.set_shader_parameter("base_tint", Color(1, 1, 1).lerp(Color(0.10, 0.09, 0.08), k))
			sm.set_shader_parameter("roughness", lerpf(0.55, 0.95, k))
			sm.set_shader_parameter("shutdown", k)
		elif mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			bm.albedo_color = bm.albedo_color.lerp(Color(0.07, 0.06, 0.05), k)
			bm.emission_energy_multiplier *= (1.0 - k)


## A lamp on or off. StandardMaterial3D only — the canopy lenses and the pupil
## are the emissive things on these frames.
func _lamp(gi: GeometryInstance3D, on: bool, tint: Color = Color(0, 0, 0, 0)) -> void:
	if gi == null:
		return
	var mat := _own(gi)
	var bm := mat as BaseMaterial3D
	if bm == null:
		_note("%s is not on a StandardMaterial3D, so it cannot be lit or put out." % gi.name)
		return
	if on:
		bm.emission_enabled = true
		if tint.a > 0.0:
			bm.emission = tint
		bm.emission_energy_multiplier = maxf(bm.emission_energy_multiplier, 2.6)
	else:
		# OUT, not merely unlit. Killing the energy alone leaves a pale green
		# bead that still reads as a working light under the sun; the glass has
		# to go dark as well.
		bm.emission_energy_multiplier = 0.0
		bm.emission_enabled = false
		bm.albedo_color = Color(0.06, 0.07, 0.07)


## THE UNIVERSAL DEATH TELL, as far as it goes.
##
## Every player-lineage frame has exactly one offset `Eye`, and it is held off
## the FactionLivery piece list so a repaint cannot reach it. That much is true
## and it is the whole value of the idea: ONE node name, ONE write, every
## chassis.
##
## What is NOT true is that the write is `emission_energy`. The Eye's material
## is a StandardMaterial3D carrying `albedo_texture` and nothing else — no
## emission at all — on every frame checked. So a live eye is not currently
## glowing, and turning the energy down turns down nothing. Lighting it is a
## three-line change to the frame generators; this does it here so the two
## states can be photographed side by side and judged.
func _eye(bot: Node3D, lit: bool) -> Node3D:
	var eye := bot.get_node_or_null("Rig/Turret/Eye") as GeometryInstance3D
	if eye == null:
		for n in bot.find_children("Eye", "", true, false):
			if n is GeometryInstance3D:
				eye = n as GeometryInstance3D
				break
	if eye == null:
		# The See-Engine's is called Pupil, which is the point of looking twice:
		# a tell keyed on the literal name "Eye" misses it.
		for n in bot.find_children("Pupil", "", true, false):
			if n is GeometryInstance3D:
				eye = n as GeometryInstance3D
				_note("%s has no node called Eye — its lens is `Pupil`, so a tell keyed on the name misses it." % bot.name)
				break
	if eye == null:
		_note("%s has no Eye and no Pupil, so it has no eye tell at all." % bot.name)
		return null
	var mat := _own(eye)
	var bm := mat as BaseMaterial3D
	if bm == null:
		_note("%s's eye is not on a StandardMaterial3D, so the tell needs a different write." % bot.name)
		return eye
	if lit:
		bm.emission_enabled = true
		bm.emission = Color(1.0, 0.38, 0.18)
		# 1.5, NOT 3.2. The first pass used 3.2 and photographed a white disc
		# with an orange ring round it: the signal filter quantises luma to ten
		# levels, so anything over about 2 lands on the top step and the colour
		# — which is the entire tell — is gone. An emissive read through this
		# filter has to sit UNDER the clip, not over it.
		bm.emission_energy_multiplier = 1.5
		bm.albedo_color = Color(1, 0.55, 0.3)
	else:
		bm.emission_enabled = false
		bm.emission_energy_multiplier = 0.0
		# Dead glass, not dim glass. A dim eye under a bright sun is an eye.
		bm.albedo_color = Color(0.05, 0.05, 0.06)
	return eye


# ─────────────────────────────────────────────
# COMING APART
# ─────────────────────────────────────────────
## Take every export that NAMES this part off it, and say which.
##
## This is the bug class the project has hit before: walker.gd's `_pose_leg`
## ASSIGNS `hip.rotation.x`, `hip.rotation.z`, `knee.rotation.x` and both foot
## rotations every physics frame, including zeroes at a dead stop. A limb
## reparented to the world while `hip_right` still points at it is driven from a
## body it is no longer attached to — it will sit on the deck twitching in step
## with the walk cycle of the robot it fell off.
##
## Worth knowing for the real thing: on the Bastion only HipL and HipR are wired
## to the pose exports. HipLA and HipRA — the rear pair — are named by nothing,
## so they are never posed and detaching one needs no unwiring at all. The
## fragility is per leg, not per frame.
func _unwire(bot: Node, gone: Node) -> Array:
	var cut: Array = []
	for key in POSE_EXPORTS:
		if not (key in bot):
			continue
		var v = bot.get(key)
		if v is Array:
			var keep: Array[Node3D] = []
			var changed := false
			for n in v:
				if n is Node and (n == gone or (gone as Node).is_ancestor_of(n as Node)):
					changed = true
				elif n != null:
					keep.append(n as Node3D)
			if changed:
				bot.set(key, keep)
				cut.append(key)
		elif v is Node and (v == gone or (gone as Node).is_ancestor_of(v as Node)):
			bot.set(key, null)
			cut.append(key)
	return cut


## Off the body and onto the deck.
##
## The livery is told as well as the exports: `pieces` and `_meshes` hold LIVE
## NODE OBJECTS, and a repaint or a set_shutdown() that touches a freed one
## takes the game with it. remove_pieces() exists for exactly this.
func _detach(bot: Node3D, path: String) -> Node3D:
	var part := bot.get_node_or_null(path) as Node3D
	if part == null:
		_note("%s has no %s any more, so nothing came off and that state photographs INTACT."
				% [bot.name, path])
		return null
	var cut := _unwire(bot, part)
	if not cut.is_empty():
		print("    unwired %s from %s before detaching it" % [str(cut), path])
	var liv := bot.get_node_or_null("FactionLivery")
	if liv != null and liv.has_method("remove_pieces"):
		var gone: Array[Node3D] = [part]
		liv.call("remove_pieces", gone)
	var world := part.global_transform
	part.get_parent().remove_child(part)   # remove_child first; queue_free is deferred
	_level.add_child(part)
	part.global_transform = world
	return part


## Lay a detached part on the deck at an offset from where it came off.
##
## POSED, NOT SIMULATED. A RigidBody3D would be the real thing and would need a
## collision shape per part, a settling wait, and would land somewhere different
## every run — which makes two shots of "the same" state incomparable, and
## comparing shots is the entire job here.
func _lay(part: Node3D, slide: Vector3, tip_deg: float, yaw_deg: float) -> void:
	if part == null:
		return
	part.rotate_y(deg_to_rad(yaw_deg))
	part.global_rotate(Vector3.RIGHT, deg_to_rad(tip_deg))
	part.global_position += slide
	for _i in 4:
		await process_frame
	var bb := _aabb(part, part)
	if bb.size == Vector3.ZERO:
		return
	# Its lowest drawn point on the deck, not its origin on the deck. A shin
	# dropped by its origin goes half through the floor.
	part.global_position.y += _deck - (part.global_position.y + bb.position.y)


## Fill the socket a detached limb left.
##
## THE CLAIM BEING TESTED. "A detached CSG limb leaves a flat cut face" — so fill
## it with a dark emissive and it reads as torn open instead of mesh-deleted.
##
## On these frames it is not a cut face. The parts are primitive MeshInstance3Ds
## — closed cylinders and boxes — and the Hull is a closed CSG solid, so taking a
## leg off leaves two intact surfaces and a gap between them. There is nothing
## open to see. The fill therefore has nothing to cover and has to EARN its place
## as a piece of art instead: a torn socket, drawn, where the leg used to be.
## Both versions are photographed and the doc says which one works.
func _stump(bot: Node3D, at_global: Vector3, radius: float) -> Node3D:
	var torn := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.4
	mesh.radial_segments = 10
	mesh.rings = 5
	torn.mesh = mesh
	var mat := StandardMaterial3D.new()
	# DARK FIRST, EMISSIVE SECOND. A bright fill reads as a light fitting. This
	# is almost black with a dull ember in it, which is what the inside of
	# something looks like when it has just been opened.
	mat.albedo_color = Color(0.035, 0.03, 0.028)
	mat.emission_enabled = true
	mat.emission = Color(0.80, 0.26, 0.07)
	# 0.35, NOT 0.9. The first pass photographed as a flat red lozenge stuck on
	# the hip — a sticker, not a hole. The signal filter quantises luma to ten
	# steps, so a mid-bright saturated red lands on one flat step with no
	# gradient left in it. It has to sit low enough that the quantiser still
	# reads it as shadow with an ember IN the shadow.
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 1.0
	torn.material_override = mat
	bot.add_child(torn)
	torn.global_position = at_global

	# AND SOMETHING STICKING OUT OF IT. A smooth dark dome photographed as a
	# flat maroon ellipse painted on the hip — the signal filter flattens a
	# curved surface of one colour onto one luma step, so the shading that was
	# supposed to make it read as a cavity is quantised away and what is left is
	# a decal. Four bent rods — torn actuator shafts — put an outline and a
	# shadow back, and an outline is what the filter's edge pass can see.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	for i in 4:
		var rod := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.016
		cyl.bottom_radius = 0.022
		cyl.height = radius * (1.5 + rng.randf() * 1.1)
		cyl.radial_segments = 5
		rod.mesh = cyl
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.07, 0.065, 0.06)
		rmat.roughness = 0.9
		rod.material_override = rmat
		torn.add_child(rod)
		var a := TAU * (float(i) / 4.0) + rng.randf() * 0.5
		rod.position = Vector3(cos(a) * radius * 0.55, -radius * 0.2, sin(a) * radius * 0.55)
		rod.rotation = Vector3(deg_to_rad(62.0 + rng.randf() * 30.0), a, 0.0)
	return torn


# ─────────────────────────────────────────────
# EFFECTS
# ─────────────────────────────────────────────
## The frame's own SparkBurst, moved to the hit.
##
## A FRESH INSTANCE, not the one on the body. The scene's SparkBurst sits at the
## body origin and `particle_effects_hit` fires it there; a hit on a shoulder
## plate that sparks from between the robot's feet is not the state being drawn.
func _sparks(at_global: Vector3) -> Node:
	var ps := load(SPARK) as PackedScene
	if ps == null:
		_note("spark_burst.tscn would not load, so the scuffed state has no sparks in it.")
		return null
	var fx: Node3D = ps.instantiate()
	_level.add_child(fx)
	fx.global_position = at_global
	# Opened by _shoot three frames before the shutter, not here.
	_pending_add(fx)
	return fx


## A leak, not a spray.
##
## The frame's own OilSpray is a 0.6 s one-shot of six globules, which is right
## for an impact and over long before a shot settles. This is the same art — the
## oil globule mesh off that scene — on a looping emitter with the velocity
## taken out of it, so there is oil in the air AND oil on the deck at the moment
## of the grab.
func _leak(at_global: Vector3, run_for: float = 1.4) -> Node3D:
	var holder := Node3D.new()
	_level.add_child(holder)
	holder.global_position = at_global
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.025, 0.02)
	mat.roughness = 0.15
	mat.metallic = 0.4
	mesh.material = mat
	p.mesh = mesh
	p.amount = 26
	p.lifetime = run_for
	p.preprocess = run_for        # already running when the shot is taken
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.direction = Vector3(0, -1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	holder.add_child(p)
	# And the puddle it has been making. A leak with no pool under it reads as
	# a robot that has just started leaking, every time, which is a different
	# state.
	var pool := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.46
	disc.height = 0.012
	disc.radial_segments = 20
	pool.mesh = disc
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.025, 0.02, 0.018)
	pmat.roughness = 0.08
	pmat.metallic = 0.55
	pool.material_override = pmat
	_level.add_child(pool)
	pool.global_position = Vector3(at_global.x, _deck + 0.008, at_global.z)
	return holder


## The suppression arc the game already has, at full.
##
## SignalArc is what a robot losing its signal looks like in this game today —
## cold, blue-white, crackling, in the HUD's own SIGNAL colour. An e-kill
## mock-up that invented its own electrical effect would be proposing a second
## visual language for the same event.
func _arc(host: Node3D, height: float, radius: float, at_local: Vector3) -> Node:
	var arc = _SignalArc.new()
	arc.body_height = height
	arc.body_radius = radius
	host.add_child(arc)
	(arc as Node3D).position = at_local
	# Ticked rather than set: `tick` is what opens the emitter, and the crackle
	# gap is zero at 1.0 so it spits continuously, which is the e-kill look.
	for _i in 10:
		arc.tick(1.0 / 60.0, 1.0)
		await process_frame
	return arc


## Earth discharge — the frame dumping into the ground it is standing on.
##
## Deliberately NOT the same effect as the body arc. The arc is loss; this is
## the last of the charge going somewhere, so it is a column from the lowest
## part of the chassis to the deck plus a flash where it lands. One beat, and
## the only moment in the e-kill where anything leaves the silhouette.
func _earth(at_global: Vector3) -> Node3D:
	var holder := Node3D.new()
	_level.add_child(holder)
	var top := at_global
	var foot := Vector3(at_global.x, _deck, at_global.z)
	var span: float = maxf(0.08, top.y - foot.y)

	var bolt := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.035
	rod.bottom_radius = 0.012
	rod.height = span
	rod.radial_segments = 6
	bolt.mesh = rod
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = SignalArc.CORE_COLOUR
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bolt.material_override = bm
	holder.add_child(bolt)
	bolt.global_position = (top + foot) * 0.5

	# Where it lands. Sparks thrown OUT and low, so it reads as hitting the deck
	# rather than as a second arc off the hull.
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.35
	p.explosiveness = 0.9
	p.preprocess = 0.1
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3(0, 0.15, 0)
	p.spread = 180.0
	p.flatness = 0.85
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.damping_min = 12.0
	p.damping_max = 22.0
	p.gravity = Vector3(0, -3.0, 0)
	p.color = SignalArc.ARC_COLOUR
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = SignalArc.CORE_COLOUR
	qm.disable_receive_shadows = true
	q.material = qm
	p.mesh = q
	holder.add_child(p)
	(p as Node3D).global_position = foot
	return holder


## The livery's accent markers, arcing.
##
## faction_metal.gdshader already has `marker_energy` and `shutdown` as
## uniforms, which is the whole e-kill surface treatment for free: the markers
## flare, then go dark, and the paint under them never changes. Each piece is
## pushed to a DIFFERENT energy so the flicker reads as electrical rather than
## as the robot being lit from somewhere.
func _flicker(bot: Node3D, seed_value: int) -> void:
	var liv := bot.get_node_or_null("FactionLivery")
	if liv == null:
		_note("%s has no FactionLivery, so there are no accent markers to flicker." % bot.name)
		return
	var pieces: Array[GeometryInstance3D] = []
	_drawn(bot.get_node_or_null("Rig"), pieces)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value            # same flicker every run, so shots compare
	var touched := 0
	for gi in pieces:
		if not (gi.material_override is ShaderMaterial):
			continue
		var mat := _own(gi) as ShaderMaterial
		if mat == null:
			continue
		var roll := rng.randf()
		if roll < 0.45:
			mat.set_shader_parameter("marker_energy", 5.6)   # arcing
		elif roll < 0.7:
			mat.set_shader_parameter("marker_energy", 0.0)   # already gone
		touched += 1
	if touched == 0:
		_note("%s: no piece on a faction ShaderMaterial, so the arc flicker has nothing to flicker." % bot.name)


# ─────────────────────────────────────────────
# THE GRAB
# ─────────────────────────────────────────────
## One-shot effects are fired HERE, three frames before the grab.
##
## SparkBurst is `one_shot`, 14 particles, lifetime 0.1 s. Fired during staging
## it is over 1.9 seconds before the shutter — the first Vessel shot fired its
## hinge sparks at build time and photographed two dead specks of debris
## hanging in the sky with no robot damage visible at all. Anything that wants
## to be in the picture registers itself with _pending() and is opened from
## here instead.
var _pending: Array = []


func _pending_add(fx: Node) -> void:
	if fx != null:
		_pending.append(fx)


func _shoot(file: String) -> void:
	for _i in 24:
		await process_frame
	if not _pending.is_empty():
		for fx in _pending:
			if fx != null and is_instance_valid(fx) and fx.has_method("activate"):
				fx.call("activate")
		_pending.clear()
		for _i in 3:
			await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(file)
	if err != OK:
		printerr("mock_damage: could not write %s (%s)" % [file, error_string(err)])
	else:
		print("  %s" % file.get_file())


func _clear(made: Array) -> void:
	for n in made:
		if n != null and is_instance_valid(n):
			var p := (n as Node).get_parent()
			if p != null:
				p.remove_child(n)   # remove_child first: queue_free is deferred
			(n as Node).free()


# ─────────────────────────────────────────────
# A · KINETIC — five escalating states on one frame
# ─────────────────────────────────────────────
# ON THE BASTION, and that is a considered choice. The five states need a frame
# that has (a) a bolt-on plate that is its own render root, which the Applique
# and the Skirts are and a CSGBox3D cut into a hull is not; (b) a limb it can
# lose and still be standing, which four legs gives and two do not; and (c) one
# offset eye. Three of the ten frames fail one of those.
const STATES := ["intact", "scuffed", "breached", "crippled", "dead"]


func _sheet_kinetic(out_dir: String) -> void:
	print("")
	print("A · KINETIC — the five states, on the Bastion")

	# THE ROW FIRST, because the progression is the thing being judged and five
	# separate photographs are five photographs, not a progression. The close
	# shots under it are for reading detail that 230 px of frame cannot carry.
	await _kinetic_row(out_dir)
	for i in STATES.size():
		await _kinetic_one(out_dir, i)
	await _cut_face(out_dir)


## A row laid ACROSS the lit bearing, not along the world X.
##
## Two things went wrong with the obvious version and this fixes both. Laying
## the row along X and putting the camera on -Z backlit every frame, so the
## sheet came back as five identical black cut-outs — the one view in which a
## progression of surface damage is guaranteed not to read. And "left to right"
## in the world is right to left on screen from a camera on -Z, so the sheet
## ran dead → intact and had to be read backwards.
##
## ACROSS is screen-right for a camera on LIT, so index 0 is genuinely the
## leftmost thing in the photograph.
func _row_spot(i: int, n: int, gap: float) -> Vector3:
	return STAGE + ACROSS * (gap * float(i) - gap * float(n - 1) * 0.5)


func _kinetic_row(out_dir: String) -> void:
	var made: Array = []
	var gap := 5.4
	var span := gap * float(STATES.size() - 1)
	# CAMERA FIRST, because _face turns each frame to meet it and cannot do that
	# before it knows where it is.
	_frame_up(STAGE, span + 4.6, LIT, 3.9)
	for i in STATES.size():
		var bot := _spawn("bastion")
		if bot == null:
			return
		made.append(bot)
		await _stand(bot, _row_spot(i, STATES.size(), gap))
		# Three-quarter on and TOWARDS the camera: the eye, the struck plate and
		# the hip that loses its leg are all on the front half of this frame, and
		# a row of backs shows none of them.
		_face(bot, -22.0)
		var fx := await _apply(bot, i, false)
		for n in fx:
			made.append(n)
	await _shoot("%s/dam_kinetic_row.png" % out_dir)
	_clear(made)


func _kinetic_one(out_dir: String, i: int) -> void:
	var made: Array = []
	var bot := _spawn("bastion")
	if bot == null:
		return
	made.append(bot)
	await _stand(bot, STAGE)
	var bb := _aabb(bot, bot)
	var span: float = maxf(bb.size.x, bb.size.z) * 1.5
	_frame_up(STAGE, span, LIT, bb.size.y)
	_face(bot, -34.0)
	var fx := await _apply(bot, i, false)
	for n in fx:
		made.append(n)
	# Re-framed AFTER the state is built: a dead Bastion is a low wide thing and
	# the standing framing cuts it in half.
	await process_frame
	var after := _aabb(bot, bot)
	_frame_up(STAGE, maxf(span, maxf(after.size.x, after.size.z) * 1.6), LIT,
			maxf(1.2, after.size.y))
	await _shoot("%s/dam_a%d_%s.png" % [out_dir, i + 1, STATES[i]])
	_clear(made)


## One state, built on an already-standing frame. Returns anything it made that
## is not under the body, so the caller can free it.
func _apply(bot: Node3D, i: int, _close: bool) -> Array:
	var extra: Array = []
	var state: String = STATES[i]
	_eye(bot, state != "dead")

	if state == "intact":
		return extra

	# SCUFFED and up: the struck plate is darkened. The hit lands on the left
	# applique, which is the biggest addressable livery piece on the frame.
	var plate := bot.get_node_or_null(BAST["plate"]) as Node3D
	if plate == null:
		_note("Bastion has no %s, so the struck plate cannot be darkened." % BAST["plate"])
	else:
		_scorch(plate, 0.55 if state == "scuffed" else 0.8)
		var hit := _hit_point(plate)
		if state == "scuffed":
			var fx := _sparks(hit)
			if fx != null:
				extra.append(fx)
	if state == "scuffed":
		return extra

	# BREACHED: a sheet off, and oil out of where it was.
	var panel := _detach(bot, BAST["panel"])
	if panel != null:
		extra.append(panel)
		await _lay(panel, Vector3(-1.1, 0, 0.5), 74.0, 26.0)
		extra.append(_leak(_hit_point(bot.get_node_or_null("Rig/Skirts")) \
				if bot.get_node_or_null("Rig/Skirts") != null else bot.global_position))
	if state == "breached":
		return extra

	# CRIPPLED: a leg subtree gone, the frame on three and still fighting. The
	# gun stays level — "crippled" has to look different from "dying".
	var limb_at := Vector3.ZERO
	var limb := bot.get_node_or_null(BAST["limb"]) as Node3D
	if limb != null:
		limb_at = limb.global_position
	var off := _detach(bot, BAST["limb"])
	if off != null:
		extra.append(off)
		await _lay(off, Vector3(-1.9, 0, -0.9), 88.0, 54.0)
		# Dropped onto the hip it lost, so the hull sits down on that corner
		# rather than standing level on three legs like nothing happened.
		var rig := bot.get_node_or_null("Rig") as Node3D
		if rig != null:
			rig.rotate_z(deg_to_rad(7.0))
			rig.position.y -= 0.18
		extra.append(_stump(bot, limb_at, 0.21))
	if state == "crippled":
		return extra

	# DEAD: eye out, markers out, body over.
	#
	# TIP THE RIG, not the body. Rotating the CharacterBody3D takes the
	# collision capsule and the nav agent with it, which is what enemy.gd's
	# _collapse_pieces exists to avoid — and the same reason applies to a
	# photograph: a tipped capsule changes where the frame measures as standing
	# and _stand has already used that.
	var liv := bot.get_node_or_null("FactionLivery")
	if liv != null and liv.has_method("set_shutdown"):
		liv.call("set_shutdown", 1.0)
	for path in BAST["lamps"]:
		_lamp(bot.get_node_or_null(path) as GeometryInstance3D, false)
	var rig2 := bot.get_node_or_null("Rig") as Node3D
	if rig2 == null:
		_note("Bastion has no Rig, so the dead state cannot be tipped over.")
		return extra
	rig2.rotate_x(deg_to_rad(84.0))        # enemy.gd's own collapse_pitch_degrees
	for _i in 4:
		await process_frame
	var bb := _aabb(bot, bot)
	# Onto the deck. collapse_drop is 0.5 m on the 2 m frames and this is 4.5 m
	# of robot, so the drop is measured instead.
	rig2.position.y += _deck - (bot.global_position.y + bb.position.y)
	return extra


## A point on the surface of a piece, facing the camera, for an effect to sit
## at. Derived from the piece's own bounds — a typed offset is right for one
## frame and wrong for the next.
func _hit_point(piece: Node3D) -> Vector3:
	if piece == null:
		return STAGE
	var pieces: Array[GeometryInstance3D] = []
	_drawn(piece, pieces)
	if pieces.is_empty():
		return piece.global_position
	var box: AABB = (pieces[0] as VisualInstance3D).get_aabb()
	var centre: Vector3 = (pieces[0] as Node3D).global_transform * (box.position + box.size * 0.5)
	var toward := (_cam.global_position - centre)
	toward.y = 0.0
	if toward.length() < 0.01:
		return centre
	return centre + toward.normalized() * (maxf(box.size.x, box.size.z) * 0.35)


# ─────────────────────────────────────────────
# THE CUT FACE — the claim, and both answers
# ─────────────────────────────────────────────
func _cut_face(out_dir: String) -> void:
	print("  the cut face, both ways")
	for filled in [false, true]:
		var made: Array = []
		var bot := _spawn("bastion")
		if bot == null:
			return
		made.append(bot)
		await _stand(bot, STAGE)
		var limb := bot.get_node_or_null(BAST["limb"]) as Node3D
		var limb_at := limb.global_position if limb != null else bot.global_position
		var outward := limb_at - bot.global_position
		outward.y = 0.0
		outward = outward.normalized() if outward.length() > 0.05 else Vector3(-0.55, 0, -0.84).normalized()
		var off := _detach(bot, BAST["limb"])
		if off != null:
			made.append(off)
			# OUTWARD AND ASIDE. Outward alone put the leg on the line between
			# the camera and the socket, and it is a two-metre limb two metres
			# from the lens — it filled the right half of the picture and hid
			# the thing the picture is of.
			var aside := outward.cross(Vector3.UP).normalized()
			await _lay(off, outward * 1.0 + aside * 2.1, 88.0, 54.0)
		if filled:
			made.append(_stump(bot, limb_at, 0.21))
		# CLOSE, ON THE SOCKET, FROM OUTSIDE THE HULL.
		#
		# This is the one question in the set that a wide shot cannot answer, and
		# the first attempt answered it with a photograph of a wall: a fixed
		# bearing put the camera under the Bastion's hull overhang, which hangs
		# straight over its hips, so the socket was in shadow behind a metre of
		# glacis. The bearing is taken from the BODY CENTRE OUT THROUGH THE HIP
		# instead, which is the only line that clears the overhang — derived off
		# the frame, so it still works if the leg is moved.
		_cam.global_position = limb_at + outward * 3.4 + Vector3(0, 0.45, 0)
		_cam.look_at(limb_at, Vector3.UP)
		await _shoot("%s/dam_cut_%s.png" % [out_dir, "filled" if filled else "bare"])
		_clear(made)


# ─────────────────────────────────────────────
# B · THE E-KILL — nothing comes off
# ─────────────────────────────────────────────
# THE DESIGN RULE BEING DRAWN: kinetic SCATTERS, e-kill PRESERVES. So every
# beat below is forbidden from moving a part out of the silhouette, and the only
# thing that leaves the body at all is the earth discharge, once, at the end.
#
# Four beats, because "in sequence" is the whole idea and one still of a slumped
# robot cannot show a sequence:
#   b1  lit — the control, same as A's intact
#   b2  the canopy lenses out, top first, THE EYE STILL ON
#   b3  arc flicker across the livery markers, eye on, still standing
#   b4  joints limp in order, eye out, earth discharge — intact and down
const EKILL := ["lit", "lamps", "arc", "slumped"]


func _sheet_ekill(out_dir: String) -> void:
	print("")
	print("B · E-KILL — four beats, on the same frame as A")
	await _ekill_row(out_dir)
	for i in EKILL.size():
		await _ekill_one(out_dir, i)
	await _compare(out_dir)


func _ekill_row(out_dir: String) -> void:
	var made: Array = []
	var gap := 5.4
	var span := gap * float(EKILL.size() - 1)
	_frame_up(STAGE, span + 4.6, LIT, 3.9)
	for i in EKILL.size():
		var bot := _spawn("bastion")
		if bot == null:
			return
		made.append(bot)
		await _stand(bot, _row_spot(i, EKILL.size(), gap))
		_face(bot, -22.0)
		var fx := await _ekill_beat(bot, i)
		for n in fx:
			made.append(n)
	await _shoot("%s/dam_ekill_row.png" % out_dir)
	_clear(made)


func _ekill_one(out_dir: String, i: int) -> void:
	var made: Array = []
	var bot := _spawn("bastion")
	if bot == null:
		return
	made.append(bot)
	await _stand(bot, STAGE)
	var bb := _aabb(bot, bot)
	var span: float = maxf(bb.size.x, bb.size.z) * 1.5
	_frame_up(STAGE, span, LIT, bb.size.y)
	_face(bot, -34.0)
	var fx := await _ekill_beat(bot, i)
	for n in fx:
		made.append(n)
	# RE-FRAMED AFTER THE BEAT, the same as the kinetic close shots. The slump
	# takes three quarters of a metre out of the frame's height and widens its
	# stance, and the standing framing cut the legs — which is the one part of
	# the slump worth photographing — off the bottom of the picture.
	await process_frame
	var after := _aabb(bot, bot)
	_frame_up(STAGE, maxf(span, maxf(after.size.x, after.size.z) * 1.5), LIT,
			maxf(1.2, after.size.y))
	await _shoot("%s/dam_b%d_%s.png" % [out_dir, i + 1, EKILL[i]])
	_clear(made)


func _ekill_beat(bot: Node3D, i: int) -> Array:
	var extra: Array = []
	# THE EYE IS LAST. It stays lit through the lamps going out and through the
	# arc, and only goes with the slump — which is what makes the sequence read
	# as something shutting down in order rather than as a power cut.
	_eye(bot, i < 3)

	if i == 0:
		for path in BAST["lamps"]:
			_lamp(bot.get_node_or_null(path) as GeometryInstance3D, true)
		return extra

	# LAMPS: top-down. The canopy lenses are the highest lights on the frame and
	# they are already emissive in the scene — albedo (0.78,0.95,0.80), emission
	# (0.42,0.90,0.52) at 2.6. They are also off the livery piece list, like the
	# eye, so they are addressable without a repaint reaching them.
	var lamps: Array = BAST["lamps"]
	var out_count: int = lamps.size() if i >= 2 else int(ceil(lamps.size() * 0.5))
	for j in lamps.size():
		_lamp(bot.get_node_or_null(lamps[j]) as GeometryInstance3D, j >= out_count)
	if i == 1:
		return extra

	# ARC: the markers spitting, the body untouched. Height and radius measured
	# off the frame so the arcs come off the chassis and not out of the air
	# around a 2 m assumption.
	var bb := _aabb(bot, bot)
	_flicker(bot, 20261018)
	extra.append(await _arc(bot, bb.size.y * 0.8, maxf(bb.size.x, bb.size.z) * 0.26,
			Vector3(0, bb.position.y + bb.size.y * 0.5, 0)))
	if i == 2:
		return extra

	# SLUMPED: joints limp IN ORDER, not ragdolled as one.
	#
	# Four knees, each bent further than the last, and the splay rolled out so
	# the legs go wide instead of the hull going over. The rig sinks by what the
	# knees gave up. The silhouette stays a Bastion — that is the deliverable.
	var fold := [0.62, 0.48, 0.34, 0.20]
	var knees: Array = BAST["knees"]
	for j in knees.size():
		var knee := bot.get_node_or_null(knees[j]) as Node3D
		if knee == null:
			_note("Bastion has no %s, so that joint does not go limp." % knees[j])
			continue
		knee.rotate_x(deg_to_rad(-fold[j] * 95.0))
		var splay := knee.get_parent() as Node3D
		if splay != null and splay.name.begins_with("Splay"):
			splay.rotate_z(deg_to_rad((1.0 if j % 2 == 0 else -1.0) * fold[j] * 14.0))
	var rig := bot.get_node_or_null("Rig") as Node3D
	if rig != null:
		# A LEAN, NOT A FALL. Enough to read as dead weight on the legs; any
		# more and it is a kinetic death with the parts still on.
		rig.rotate_x(deg_to_rad(9.0))
		rig.rotate_z(deg_to_rad(4.0))
		rig.position.y -= 0.72
	var liv := bot.get_node_or_null("FactionLivery")
	if liv != null and liv.has_method("set_shutdown"):
		liv.call("set_shutdown", 1.0)
	_flicker(bot, 20261018)
	# The last of the charge going into the ground it is standing on.
	var low := _aabb(bot, bot)
	extra.append(_earth(bot.global_position + Vector3(0, low.position.y + 0.25, 0)))
	extra.append(await _arc(bot, low.size.y * 0.5, maxf(low.size.x, low.size.z) * 0.26,
			Vector3(0, low.position.y + low.size.y * 0.3, 0)))
	return extra


## THE ONE IMAGE THAT DECIDES THIS. Kinetic dead on the left, e-killed on the
## right, same frame, same light, same distance. If the two silhouettes do not
## separate here then the design rule is not doing its job and no amount of
## detail in the close shots rescues it.
func _compare(out_dir: String) -> void:
	print("  the silhouette test")
	var made: Array = []
	var gap := 7.0
	var a := _spawn("bastion")
	var b := _spawn("bastion")
	if a == null or b == null:
		return
	made.append(a)
	made.append(b)
	_frame_up(STAGE, gap + 7.5, LIT, 4.8)
	await _stand(a, _row_spot(0, 2, gap))
	await _stand(b, _row_spot(1, 2, gap))
	_face(a, -22.0)
	_face(b, -22.0)
	for n in await _apply(a, STATES.size() - 1, false):
		made.append(n)
	for n in await _ekill_beat(b, EKILL.size() - 1):
		made.append(n)
	# Re-framed low: one of the two is on the deck and the standing framing puts
	# it in the bottom eighth of the picture, which is not a comparison.
	_frame_up(STAGE, gap + 7.5, LIT, 3.4)
	await _shoot("%s/dam_compare_dead.png" % out_dir)
	_clear(made)


# ─────────────────────────────────────────────
# THE EYE, ON ITS OWN, ON THREE FRAMES
# ─────────────────────────────────────────────
# Tested FIRST and reported plainly, because it is the cheapest universal tell
# available and the whole case for it rests on one claim: one node name, one
# material, every chassis. Lit and out, close, on three different frames.
const EYE_FRAMES := ["bastion", "tick", "vessel"]


func _sheet_eye(out_dir: String) -> void:
	print("")
	print("THE EYE — lit and out, close, on three frames")
	for id in EYE_FRAMES:
		for lit in [true, false]:
			var made: Array = []
			var bot := _spawn(id)
			if bot == null:
				continue
			made.append(bot)
			await _stand(bot, STAGE)
			var eye := _eye(bot, lit)
			var at := eye.global_position if eye != null else bot.global_position
			# CLOSE ON THE HEAD. An eye is 13 cm of sphere on a 4.5 m robot: at
			# the catalogue framing it is three pixels and every answer about it
			# is a guess. 1.5 m was too close — it photographed the eye and no
			# robot, which answers "is it bright" and not "does it read as the
			# thing that died". 3.2 m puts the head and shoulders in.
			var dir := Vector3(-0.5, 0, -0.87).normalized()
			_cam.global_position = at + dir * 3.2 + Vector3(0, 0.25, 0)
			_cam.look_at(at, Vector3.UP)
			await _shoot("%s/dam_eye_%s_%s.png" % [out_dir, id, "lit" if lit else "out"])
			_clear(made)


# ─────────────────────────────────────────────
# C · PER-FRAME IDENTITY — four deaths only that frame can die
# ─────────────────────────────────────────────
# One image each, two-up: alive on the left, dead on the right, in one frame so
# the difference is the subject rather than something to remember between files.
func _sheet_frames(out_dir: String) -> void:
	print("")
	print("C · PER-FRAME IDENTITY — four frames, alive beside dead")
	for id in ["see_engine", "tick", "brood", "vessel"]:
		await _identity(out_dir, id)


## Per-frame framing, where the default is wrong.
##
## `yaw` is the extra swing after the frame has turned to meet the camera, and
## `lift` raises the camera above the player's eye.
##
## THE VESSEL IS THE REASON THIS EXISTS, and it is a finding rather than a
## framing preference. Its bay is a well in the ROOF of a 3.37 m vehicle, and
## VESSEL_PANELS.md says in as many words that the player "looks at [these]
## from above". From the eye the player actually has, at 1.50 m, you cannot see
## into it at all: the first pass photographed two Vessels that were identical,
## because everything that had happened to the second one had happened on a
## surface pointing at the sky. It is shot from 4.6 m here — the height of a
## loading gantry or the Kite's view, not the player's — and the doc says so.
const SHOT_FIX := {
	"vessel": {"yaw": 150.0, "lift": 3.1},
}


func _identity(out_dir: String, id: String) -> void:
	var made: Array = []
	var a := _spawn(id)
	var b := _spawn(id)
	if a == null or b == null:
		return
	made.append(a)
	made.append(b)
	await _stand(a, STAGE)
	var bb := _aabb(a, a)
	var fix: Dictionary = SHOT_FIX.get(id, {})
	var yaw: float = float(fix.get("yaw", 24.0))
	var lift: float = float(fix.get("lift", 0.0))
	var gap: float = maxf(3.2, maxf(bb.size.x, bb.size.z) * 1.4)
	var span: float = gap + maxf(bb.size.x, bb.size.z) + 1.6
	var height: float = maxf(1.4, bb.size.y * 1.25)
	_frame_up(STAGE, span, LIT, height)
	_cam.global_position.y += lift
	_cam.look_at(Vector3(STAGE.x, _deck + height * 0.4, STAGE.z), Vector3.UP)
	await _stand(a, _row_spot(0, 2, gap))
	await _stand(b, _row_spot(1, 2, gap))
	_face(a, yaw)
	_face(b, yaw)
	_eye(a, true)
	for n in await _kill(b, id):
		made.append(n)
	_frame_up(STAGE, span, LIT, height)
	_cam.global_position.y += lift
	_cam.look_at(Vector3(STAGE.x, _deck + height * 0.4, STAGE.z), Vector3.UP)
	await _shoot("%s/dam_c_%s.png" % [out_dir, id])
	_clear(made)


func _kill(bot: Node3D, id: String) -> Array:
	match id:
		"see_engine": return await _kill_see_engine(bot)
		"tick": return await _kill_tick(bot)
		"brood": return await _kill_brood(bot)
		"vessel": return await _kill_vessel(bot)
	return []


## SEE-ENGINE — the lens goes dark and the gimbal goes slack, so a 2.3 m eye
## hangs staring at the floor. Nothing detaches: this frame's whole character is
## that it is one enormous sensor, and breaking it into pieces would make it a
## generic walker with bits off.
##
## ITS LENS IS NOT CALLED `Eye`. The node is `Rig/GimbalYaw/LensPitch/Pupil`, and
## there is no Eye on this frame at all — so the universal tell is universal only
## if it keys on something other than the literal name.
func _kill_see_engine(bot: Node3D) -> Array:
	var extra: Array = []
	_eye(bot, false)                      # finds Pupil, and says so
	var pitch := bot.get_node_or_null("Rig/GimbalYaw/LensPitch") as Node3D
	var yaw := bot.get_node_or_null("Rig/GimbalYaw") as Node3D
	if pitch == null or yaw == null:
		_note("See-Engine has no GimbalYaw/LensPitch, so its death cannot be posed.")
		return extra
	# SLACK, BOTH HOOPS. Pitched over hard so the lens looks at its own feet, and
	# the yaw hoop let go a few degrees off true — a gimbal that has lost its
	# drives does not stop square.
	pitch.rotate_x(deg_to_rad(-72.0))
	yaw.rotate_y(deg_to_rad(17.0))
	# The legs give a little so the whole thing settles rather than standing to
	# attention with its head down.
	for path in ["Rig/LegFR/HipR", "Rig/LegFL/HipL", "Rig/LegRR/HipRR", "Rig/LegRL/HipRL"]:
		var hip := bot.get_node_or_null(path) as Node3D
		if hip != null:
			hip.rotate_x(deg_to_rad(11.0))
	var rig := bot.get_node_or_null("Rig") as Node3D
	if rig != null:
		rig.position.y -= 0.22
	_scorch(bot.get_node_or_null("Rig/GimbalYaw"), 0.35)
	var liv := bot.get_node_or_null("FactionLivery")
	if liv != null and liv.has_method("set_shutdown"):
		liv.call("set_shutdown", 1.0)
	return extra


## TICK — the rotors are separate and non-faction. Stop one, it yaws, then drops.
##
## Three rotors on three booms off a central FanTower, each its own subtree. This
## kills Rotor2: its blades stop while the other two are mid-blur, the frame
## cants over onto the dead corner, and it is already on its way down. The yaw is
## the tell — nothing else in the game rotates about its own axis while falling.
func _kill_tick(bot: Node3D) -> Array:
	var extra: Array = []
	_eye(bot, false)
	var tower := bot.get_node_or_null("Rig/FanTower") as Node3D
	if tower == null:
		_note("Tick has no Rig/FanTower, so the rotor death cannot be posed.")
		return extra
	var dead := tower.get_node_or_null("Rotor2/Boom/Fan") as Node3D
	if dead == null:
		_note("Tick has no Rotor2/Boom/Fan, so no rotor can be stopped.")
	else:
		# STOPPED, AND BENT. A stopped rotor that is otherwise perfect reads as a
		# rotor that was never turning. Its blades are splayed off true and the
		# duct scorched.
		for blade in ["Blade1", "Blade2", "Blade3"]:
			var b := dead.get_node_or_null(blade) as Node3D
			if b != null:
				b.rotate_z(deg_to_rad(23.0))
		_scorch(dead, 0.7)
		var boom := tower.get_node_or_null("Rotor2/Boom") as Node3D
		if boom != null:
			boom.rotate_z(deg_to_rad(-15.0))   # the boom droops on the dead side
		extra.append(_leak(dead.global_position, 0.9))
	# The yaw, and the cant onto the dead corner. Rig, not the body: the capsule
	# and the nav agent stay upright.
	var rig := bot.get_node_or_null("Rig") as Node3D
	if rig != null:
		rig.rotate_y(deg_to_rad(42.0))
		rig.global_rotate(Vector3.FORWARD, deg_to_rad(21.0))
		rig.global_rotate(Vector3.RIGHT, deg_to_rad(9.0))
		rig.position.y += 0.45             # caught on the way down, not landed
	var liv := bot.get_node_or_null("FactionLivery")
	if liv != null and liv.has_method("set_shutdown"):
		liv.call("set_shutdown", 1.0)
	return extra


## BROOD — it breaks and the swarm spills out.
##
## Six pods on stalks round the lift hoop, and Pod1 carries a modelled Hatchling
## inside it. The kill opens three pods, tips the carrier, and puts hatchlings on
## the deck — so what the player sees is not a wreck, it is a problem that has
## just got bigger.
##
## ONLY POD1 HAS A HATCHLING IN THE SCENE. The other five are Shell, Band and
## Stalk. The spilled ones here are DUPLICATES of Pod1's, which is honest for a
## mock-up and is a real content gap for the real thing: five of the six pods are
## empty boxes.
func _kill_brood(bot: Node3D) -> Array:
	var extra: Array = []
	_eye(bot, false)
	var bay := bot.get_node_or_null("Rig/BroodBay") as Node3D
	if bay == null:
		_note("Brood has no Rig/BroodBay, so the swarm cannot spill.")
		return extra
	var source := bay.get_node_or_null("Pod1/Hatchling") as Node3D
	if source == null:
		_note("Brood's Pod1 has no Hatchling, so the spill has nothing to spill.")
	# Three pods burst: flaps off true, shells scorched, stalks snapped.
	var burst := ["Pod1", "Pod2", "Pod4"]
	for i in burst.size():
		var pod := bay.get_node_or_null(burst[i]) as Node3D
		if pod == null:
			continue
		_scorch(pod, 0.6)
		for flap in ["Flap1", "Flap2"]:
			var f := pod.get_node_or_null(flap) as Node3D
			if f != null:
				f.rotate_x(deg_to_rad(96.0 + 14.0 * float(i)))
		var stalk := pod.get_node_or_null("Stalk") as Node3D
		if stalk != null:
			stalk.rotate_z(deg_to_rad(-34.0 - 11.0 * float(i)))
		pod.rotate_x(deg_to_rad(28.0 + 9.0 * float(i)))
	# And the swarm on the deck, out from under it.
	if source != null:
		var spread := [Vector3(-1.5, 0, -0.9), Vector3(0.4, 0, -1.7),
				Vector3(1.6, 0, -0.4), Vector3(-0.7, 0, 0.9), Vector3(1.0, 0, 1.3)]
		for i in spread.size():
			var h: Node3D = source.duplicate()
			_level.add_child(h)
			extra.append(h)
			h.global_position = bot.global_position + spread[i]
			h.rotation = Vector3(0, deg_to_rad(53.0 * float(i)), 0)
			# Two of the five on their backs, so it reads as a spill and not as
			# a formation that has just deployed.
			if i % 2 == 1:
				h.rotate_x(deg_to_rad(132.0))
			await _lay(h, Vector3.ZERO, 0.0, 0.0)
	# The carrier over, rotors stopped and splayed.
	for r in ["RotorA", "RotorB", "RotorC"]:
		var rot := bot.get_node_or_null("Rig/" + r) as Node3D
		if rot != null:
			rot.rotate_z(deg_to_rad(17.0))
	var rig := bot.get_node_or_null("Rig") as Node3D
	if rig != null:
		rig.global_rotate(Vector3.RIGHT, deg_to_rad(38.0))
		rig.global_rotate(Vector3.FORWARD, deg_to_rad(-14.0))
	var liv := bot.get_node_or_null("FactionLivery")
	if liv != null and liv.has_method("set_shutdown"):
		liv.call("set_shutdown", 1.0)
	# set_shutdown IS NOT A DEATH TELL ON ITS OWN, and this frame is where that
	# showed. The shader line is
	#     EMISSION = faction_color * marker_mask * marker_energy * (1 - shutdown)
	# so shutdown takes the GLOW off the accent markers and leaves the PAINT
	# under them exactly as it was. On a Broodcarrier the markers are six amber
	# beads on the pods and three on the cores, and with the glow off they are
	# still six amber beads — the first pass photographed a wrecked carrier that
	# was visibly still lit from twelve metres. The bay is darkened as well, so
	# the colour goes with the glow.
	_scorch(bay, 0.75)
	for _i in 4:
		await process_frame
	var bb := _aabb(bot, bot)
	if rig != null:
		rig.position.y += _deck - (bot.global_position.y + bb.position.y)
	return extra


## VESSEL — panels spall and the hoppers inside show BEFORE it dies.
##
## This is the one state in the set that is deliberately not a death. The two
## bay door leaves are the biggest flat surfaces on any robot in the game — 2.63
## square metres each, per VESSEL_PANELS.md — so losing them is a silhouette
## change the player can read across a street, and what it exposes is the cargo:
## two Hatchlings on their cradles in an open well. A Vessel with its back open
## is still driving, and now everyone can see what it is carrying.
func _kill_vessel(bot: Node3D) -> Array:
	var extra: Array = []
	_eye(bot, true)                 # STILL ALIVE. The eye is the thing that says so.
	var bay := bot.get_node_or_null("Rig/Bay") as Node3D
	if bay == null:
		_note("Vessel has no Rig/Bay, so no panels can spall.")
		return extra
	# ONE LEAF OFF, ONE HANGING. Both gone is a hole; one off and one on a
	# wrecked hinge is a machine that has been hit.
	var gone := _detach(bot, "Rig/Bay/DoorR")
	if gone != null:
		extra.append(gone)
		_scorch(gone, 0.45)
		await _lay(gone, Vector3(1.7, 0, 1.2), 82.0, 41.0)
	var hanging := bay.get_node_or_null("DoorL") as Node3D
	if hanging != null:
		hanging.rotate_z(deg_to_rad(-38.0))
		hanging.rotate_x(deg_to_rad(16.0))
		_scorch(hanging, 0.6)
	# The studs that held the gone leaf, bent where it tore off its hinge bar.
	var bar := bay.get_node_or_null("HingeBarR") as Node3D
	if bar != null:
		bar.rotate_x(deg_to_rad(23.0))
		_scorch(bar, 0.7)
	# And the hull around the opening, burnt. The point is that the eye goes to
	# the hole, so the hole has to be the darkest thing on the frame.
	_scorch(bay.get_node_or_null("Coaming"), 0.5)
	extra.append(_leak(bay.global_position + Vector3(0.9, -0.4, 0.6), 1.2))
	# Sparks from the torn hinge at the moment of the grab.
	var fx := _sparks(bar.global_position if bar != null else bay.global_position)
	if fx != null:
		extra.append(fx)
	return extra
