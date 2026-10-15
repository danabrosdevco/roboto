extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPHING THE COMPUTE CORE SKELETON — lit, in a level, three bearings.
#
#   godot --audio-driver Dummy --path . \
#       --script res://tools/shoot_core_skeleton.gd -- <out dir>
#
# NO --headless: this photographs the game, so it needs a window. The grabs
# come out at the project's internal viewport size whatever the window is,
# because project.godot sets stretch mode "viewport".
#
# IT WRITES core_relay_*.png NOW, AND THAT IS THE SECOND ROUND. The human saw
# round one's interlaced skeleton lit and rejected the band language outright;
# tools/build_core_relay.gd replaced the geometry and this rig photographs
# whatever compute_core{_small,,_large}.tscn currently is. ROUND ONE'S SHOTS
# ARE KEPT, as docs/concepts/core_skel_*.png, because docs/concepts/
# CORE_SKELETON.md is written about them and a rejected round is evidence. The
# file name is the only thing that moved; the staging, the bearings and the
# distances are the same rig, which is what makes the two sets comparable.
#
# ─────────────────────────────────────────────
# WHY A SECOND SHOOTER AND NOT JUST mockup_shots.gd
#
# mockup_shots.gd -- <dir> props takes ONE portrait per prop, framed to fit the
# whole object. That is the right shot for a catalogue and the wrong one for
# the question this round has to answer, which is:
#
#   DO 17 SLOTS ON THE 12.4 m CORE READ AS A MACHINE OR AS A LADDER?
#
# Band density is a function of VIEWING DISTANCE, and a frame-to-fit portrait
# normalises exactly the variable in question — the 4.2 m core and the 12.4 m
# core come back the same size on the page, which is the one framing that
# cannot answer it. So each core is shot three ways:
#
#   eye    from a standing player's eye at 1.5 m, about two core-heights out,
#          looking slightly up. The bands are read texel by texel here and the
#          console is in frame, because this is the distance a capture happens
#          at.
#   far    the same bearing from 40 m at eye height. The silhouette question:
#          at this range the bands are either a scale cue or a stripe.
#   pulse  CORE_PHASE frozen mid-travel, mid distance. core_pulse.gd's
#          diagnostic hatch, so a still can prove a moving thing: the bands
#          are at different energies in one frame rather than all at rest.
#
# The core's approach face is -Z and it does not turn to meet the camera the
# way a robot does, so the camera goes round to the face: a core shot from the
# back is a box.
#
# The three PROPS entries in mockup_shots.gd are kept as well, so the cores sit
# beside the fifteen study renders in the catalogue framing.
# ─────────────────────────────────────────────

## A REAL LEVEL FIRST, for its WorldEnvironment and its sun. Without one every
## shot is a black rectangle, which is how the first pass of every shooter in
## this project has failed.
##
## proving_level AND NOT depot_level, which is what mockup_shots.gd stages
## props in. depot_level is a shed: measured, the only ground in it is one
## 16.5 m floor at the origin under a roof, so the 12.4 m core came back with
## its cap through the ceiling and the 40 m shot had a structural pillar across
## it. A core is an outdoor objective and the silhouette question cannot be
## asked indoors. proving_level has flat open ground at y = -1.5 from
## x = -40..40 over z = -80..120. This spot was picked by casting a 16-ray
## fan at eye height from every 20 m node on that ground and taking the one
## with the longest clearance: 49 m, with the proving ground's own structures
## on the horizon for scale. Assuming an empty patch put the first attempt
## behind a pillar.
const LEVEL := "res://maps/proving_level.tscn"
const STAGE := Vector3(-40.0, -1.5, -80.0)

const CORES := {
	"relay_small": "res://maps/blocks/compute/compute_core_small.tscn",
	"relay_med": "res://maps/blocks/compute/compute_core.tscn",
	"relay_large": "res://maps/blocks/compute/compute_core_large.tscn",
}

## Eye height of a standing player: a 1.7 m capsule with the camera 0.65 above
## its middle. Every "eye" and "far" shot is taken from exactly this, because
## the whole point is that it is the player's own elevation and not a
## three-quarter view from above that flatters a tower.
const EYE := 1.5
const FAR := 40.0
## Frozen 35% through the cycle: far enough in that the lowest bands have
## fallen back to rest and the band in travel is partway up.
const PHASE := "0.35"

const TICK := "res://Character/characters/ai/tick.tscn"
const TickPlaced := preload("res://tools/tick_placed.gd")

var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_core_skeleton: this photographs the game, so it needs a window — drop --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://core_skeleton"
	DirAccess.make_dir_recursive_absolute(out)
	# CORE_PHASE is read by core_pulse.gd in _ready, so it has to be set before
	# the core is instanced and cleared before the ones that should animate.
	OS.set_environment("CORE_PHASE", "")

	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	root.add_child(_cam)
	_cam.current = true
	for _i in 30:
		await process_frame

	for id: String in CORES:
		await _shots(out, id)
	await _row(out)
	print("shoot_core_skeleton: written to %s" % ProjectSettings.globalize_path(out))


## ALL THREE SIZES, ONE GROUND PLANE, ONE CAMERA, ONE FRAME — so within this
## picture the sizes are at TRUE COMMON SCALE and the 4.2 m core is small
## because it is small.
##
## It is the only shot that can answer the second half of the band-density
## question. Band COUNT is the size cue the whole look rests on: 2 / 4 / 8
## painted rings is supposed to say "bigger machine" without a second cue. A
## renderer that frames each core to its own bounds answers that question yes
## by construction, which is the fault shoot_core_f.gd's own header is about,
## so this one does not.
func _row(out: String) -> void:
	var made: Array = []
	var x: float = -7.0
	var tallest := 0.0
	for id: String in CORES:
		var core: Node3D = (load(CORES[id]) as PackedScene).instantiate()
		root.add_child(core)
		core.global_position = STAGE + Vector3(x, 0, 0)
		made.append(core)
		await process_frame
		var bb := _aabb(core, core)
		tallest = maxf(tallest, bb.size.y)
		# Spaced off the piece that was just placed rather than on a fixed
		# pitch: the decks are 3.25 / 4.44 / 6.31 m square and a constant step
		# either overlaps the large one or strands the small one.
		x += bb.size.x * 0.5 + 4.0
	await process_frame
	var centre := STAGE + Vector3(-1.0, tallest * 0.45, 0)
	_cam.global_position = STAGE + Vector3(-1.0, EYE + tallest * 0.25, -30.0)
	_cam.look_at(centre, Vector3.UP)
	await _shoot("%s/core_relay_row.png" % out)
	for c: Node3D in made:
		root.remove_child(c)
		c.free()
	quit(0)


func _shots(out: String, id: String) -> void:
	var packed := load(CORES[id]) as PackedScene
	if packed == null:
		push_warning("shoot_core_skeleton: no scene for '%s'" % id)
		return
	for view: String in ["eye", "far", "pulse", "flank", "tick", "tickclose"]:
		# The flank is frozen too, and so are the docked shots: the lit staircase
		# between the fins is the one place the travel is visible as a STAIRCASE
		# rather than as a line, and at rest every panel is at the same energy
		# and proves nothing. CAPTURE IS A PULSING CORE WITH A DRONE ON IT, so a
		# still of it has to show both at once or it is a still of neither.
		OS.set_environment("CORE_PHASE", PHASE if view != "eye" and view != "far" else "")
		var core: Node3D = packed.instantiate()
		root.add_child(core)
		core.global_position = STAGE
		await process_frame
		await process_frame
		# THE DRONE DOCKED, which is what a captured core looks like and what
		# the human asked to see. The pose is tools/tick_placed.gd — which is
		# build_tick.gd's own documented state change and nothing invented — and
		# the seat is the core's Dock marker plus that file's LIFT.
		#
		# NOTE WHAT THIS IS NOT. Nothing in the game does this: holdable_core.gd
		# spawns capture_tap.gd's procedural placeholder pod at
		# Vector3(0, _dock_y(), 0), which on this core is a point in mid-air
		# beside the crown. The marker exists so that can be fixed; until it is,
		# these two shots are a rig staging a drone, not a screenshot of capture.
		var tick: Node3D = null
		if view.begins_with("tick"):
			tick = _dock_tick(core)
			await process_frame
		var bb := _aabb(core, core)
		var h: float = bb.size.y
		var centre := STAGE + bb.position + bb.size * 0.5
		# A BEARING OFF THE CONSOLE FACE, not square on to it: square on, the
		# mast is one flat elevation and the interlacing has no edge to turn.
		# 28 degrees off -Z is enough to see two faces of every band.
		var bearing := Vector3(-0.47, 0.0, -0.88).normalized()
		# THE FLANK SHOT, ADDED IN ROUND TWO, and it is not a flourish: the
		# relay carries its fin bank, its lit staircase and its painted collar
		# on the map -Y elevation (Godot -X), which the approach bearing above
		# sees at a glancing 28 degrees — five of the large core's thirteen lit
		# pieces are behind a fin from there. A machine with a front and a back
		# needs a photograph of each or half of it is never judged.
		if view == "flank":
			bearing = Vector3(-0.90, 0.0, -0.44).normalized()
		# FRAMED OFF THE BIGGER OF HEIGHT AND WIDTH, which round one did not have
		# to do: its cores were 3.2 to 6.3 m square and always taller than they
		# were wide, so height alone framed them. The relay is WIDER THAN IT IS
		# TALL at the small size — 4.5 m across a 4.19 m object — and a distance
		# set from height alone cropped the bund off both sides of the close shot.
		var wide: float = maxf(bb.size.x, bb.size.z)
		var dist: float = FAR if view == "far" else maxf(5.0, maxf(h, wide) * (1.7 if view == "eye" else 2.4))
		var at := STAGE + bearing * dist + Vector3(0, EYE, 0)
		_cam.global_position = at
		# AIMED AT THE MIDDLE OF THE MAST RATHER THAN AT THE BOUNDING CENTRE on
		# the close shot: a camera at 1.5 m looking at the centre of a 12.4 m
		# box pitches so far up that the deck and the console leave the frame,
		# and the console is half of what the close shot is for.
		var look: Vector3 = centre
		if view != "far":
			look = Vector3(STAGE.x, STAGE.y + h * 0.42, STAGE.z)
		# THE CLOSE DOCK SHOT IS THE ONLY ONE NOT TAKEN FROM A PLAYER'S EYE, and
		# it is a diagnostic rather than a picture of the game: the clamp is at
		# 2.9 to 7.8 m and from the ground the shelf's own underside hides every
		# leg. Camera 1.6 m above the pad, 7 m out, aimed at the dock point.
		if view == "tickclose" and tick != null:
			_cam.global_position = tick.global_position + bearing * 7.0 + Vector3(0, -0.4, 0)
			look = tick.global_position
		_cam.look_at(look, Vector3.UP)
		await _shoot("%s/core_%s_%s.png" % [out, id, view])
		if tick != null:
			root.remove_child(tick)
			tick.free()
		root.remove_child(core)
		core.free()
	OS.set_environment("CORE_PHASE", "")


func _shoot(file: String) -> void:
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(file)
	if err != OK:
		printerr("shoot_core_skeleton: could not write %s (%s)" % [file, error_string(err)])


func _aabb(n: Node, body: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.get_children():
		var sub := _aabb(c, body)
		if sub.size != Vector3.ZERO:
			box = sub if first else box.merge(sub)
			first = false
	var vi := n as VisualInstance3D
	if vi != null:
		var local := vi.get_aabb()
		var xf := body.global_transform.affine_inverse() * vi.global_transform
		var own := AABB(xf * local.position, Vector3.ZERO)
		for i in 8:
			own = own.expand(xf * (local.position + local.size * Vector3(
					float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))))
		box = own if first else box.merge(own)
	return box


## A tick.tscn seated on `core`'s Dock marker, or null with a warning.
##
## It is parented to the ROOT and not to the core, so the core's own _aabb()
## framing is unchanged between the docked and undocked views and the two can
## be compared.
func _dock_tick(core: Node3D) -> Node3D:
	var packed := load(TICK) as PackedScene
	if packed == null:
		push_warning("shoot_core_skeleton: tick.tscn would not load, so the docked shots are of a bare core")
		return null
	var dock := core.get_node_or_null(^"Dock") as Node3D
	if dock == null:
		# Every early return warns. A core built before the dress pass learned
		# to write the marker would otherwise be photographed bare and read as
		# "the drone does not fit", which is a different finding entirely.
		push_warning("shoot_core_skeleton: %s has no Dock marker — run tools/core_skeleton_dress.gd" % core.name)
		return null
	var tick: Node3D = packed.instantiate()
	root.add_child(tick)
	TickPlaced.seat(tick)
	tick.global_position = dock.global_position + TickPlaced.LIFT
	return tick
