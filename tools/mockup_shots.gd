extends SceneTree

# ─────────────────────────────────────────────
# THE CAMERA RIG. Photographs the game, in the game, headful.
#
# TWO SHOT LISTS, ONE RIG. It started as kit mock-ups only — the same fittings
# as mockup_kit.gd, but photographed IN THE GAME rather than drawn as line art.
# Why both of those exist: the icon sheet answers "does this read as a
# silhouette at 40 pixels", which is a UI question. This answers "does it look
# like part of the machine when it is lit, painted in faction blue and standing
# in a level", which is the question you actually care about. A shape can pass
# one and fail the other — a flat slab reads fine in outline and looks like
# cardboard the moment a light hits it.
#
# docs/marketing/SHOT_BRIEF.md then wanted store stills out of the same rig, and
# asked for it generalised rather than copied, because a copy drifts. So the
# level, the camera, the resolution, the HUD and the cast are parameters now,
# and the kit list is just the first caller. Everything either list needs goes
# through _stage() and _shoot().
#
#   godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir> [what]
#
# `what` is `kit` (the default, unchanged), `marketing` for all five store
# shots, or one shot id — `01_coast_squad`, `03_basin_mechanic`, and so on.
#
# ON RESOLUTION. The frame is whatever the window is, because the window is the
# viewport this grabs. It is NOT resized here: this machine runs borderless
# fullscreen, so native is both the largest and the only size that looks right,
# and SHOT_BRIEF accepts 1920x1080. Pass `--size 2560x1440` if you want the
# brief's first choice and can spare the window.
#
# ON THE HUD. Both passes come off ONE staging — stage, grab, hide the HUD
# layer, grab again. The brief is explicit that re-staging to get the second
# pass is what makes capture expensive, so it is deliberately not possible to
# get the two out of step here.
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")
const SOLDIER := "res://Character/characters/ai/soldier_chassis.tscn"
const RIFLE := "res://Character/weapon/ai-wep_m4.tscn"
const LEVEL := "res://maps/depot_level.tscn"
## Where the soldiers stand, in a level the camera can see all of.
const STAGE := Vector3(0.0, 1.2, 0.0)
const SPACING := 2.0

## The cast, by the name SHOT_BRIEF uses for each frame.
const FRAMES := {
	"soldier": "res://Character/characters/ai/soldier_rifle.tscn",
	"rover": "res://Character/characters/ai/vehicle_rover.tscn",
	"spotter": "res://Character/characters/ai/spotter_drone.tscn",
	"mechanic": "res://Character/characters/ai/mechanic_chassis.tscn",
	"walker": "res://Character/characters/ai/walker.tscn",
}

# ─────────────────────────────────────────────
# THE FIVE STORE SHOTS, as data. docs/marketing/SHOT_BRIEF.md is the brief; this
# is that brief in the form the rig takes.
#
# `anchor` and `toward` are REAL NODE NAMES in the level, looked up at capture
# time rather than written out as coordinates. The brief gives landmarks for
# exactly this reason: TERRAIN owns these maps and moves things in them, and a
# hard-coded camera position silently photographs the wrong hillside the first
# time a level is rebuilt. A missing landmark says so and skips the shot.
#
# `cam` and `aim` are offsets in metres from those landmarks. `cast` is placed
# relative to the anchor, each entry [frame, offset, facing-degrees].
# ─────────────────────────────────────────────
const SHOTS := [
	{
		"id": "01_coast_squad",
		"level": "res://maps/coastal-road_level.tscn",
		# Four frames, separated, with the road running away from camera and
		# the bridge in the far third. This is the cover image: its whole job
		# is "these are capsules, and there are four of them".
		"anchor": "Coast_Hill", "toward": "Coast_Bridge",
		"cam": Vector3(0, 1.7, 10.0), "aim": Vector3(0, 1.0, 0),
		"cast": [
			["soldier", Vector3(-3.2, 0, -1.0), 0.0],
			["soldier", Vector3(2.9, 0, -2.4), 0.0],
			["rover", Vector3(-0.4, 0, -6.2), 0.0],
			["spotter", Vector3(4.4, 5.5, -8.0), 0.0],
		],
	},
	{
		"id": "02_mutaha_order",
		# THE LIVE LEVEL, NOT THE WIP. The brief asks which Mutaha and says to
		# shoot whichever is current; mutaha_level is the one the campaign
		# plays. Its two named crossings (Mutaha_CrossWest, Mutaha_CorePlaza)
		# exist only in the WIP, so this anchors on Mutaha_Compute, which is in
		# both — and which the brief wanted in frame anyway.
		"level": "res://maps/mutaha_level.tscn",
		"anchor": "Mutaha_Compute", "toward": "Mutaha_Compute",
		"cam": Vector3(7.0, 1.7, 13.0), "aim": Vector3(0, 2.0, 0),
		"cast": [
			["soldier", Vector3(2.0, 0, 3.0), 200.0],
			["soldier", Vector3(-1.4, 0, 1.6), 200.0],
			["rover", Vector3(4.6, 0, 5.0), 200.0],
		],
	},
	{
		"id": "03_basin_mechanic",
		"level": "res://maps/valley_basin_level.tscn",
		# Side-on, both robots in frame, close enough to read the welder. The
		# two figures ARE the composition, so nothing else is staged.
		"anchor": "Basin_Anchor", "toward": "Basin_Anchor",
		"cam": Vector3(6.5, 1.5, 0.0), "aim": Vector3(0, 0.8, 0),
		"cast": [
			["mechanic", Vector3(0, 0, -0.9), 180.0],
			["soldier", Vector3(0, 0, 0.9), 0.0],
		],
	},
	{
		"id": "04_pitt_walker",
		"level": "res://maps/pittsburgh_level.tscn",
		# Wide enough that the Walker's turret facing and the flanking frame
		# are both visible at once — the whole point is that its guns are
		# pointing the wrong way, which is a composition problem, not a pose.
		"anchor": "Pitt_Bridgehead", "toward": "Pitt_Point",
		"cam": Vector3(9.0, 4.0, 11.0), "aim": Vector3(0, 1.2, 0),
		"cast": [
			["walker", Vector3(-2.0, 0, -4.0), 250.0],
			["soldier", Vector3(5.0, 0, 1.5), 300.0],
			["soldier", Vector3(6.4, 0, 3.2), 300.0],
		],
	},
	{
		"id": "05_depot_manager",
		"level": "res://maps/depot_level.tscn",
		# FULL-SCREEN UI, NO WORLD. The one shot the rig cannot finish on its
		# own: it wants the squad manager open on a roster with ranks on it,
		# and ranks come from a played campaign. Staged and framed here; see
		# the note this prints when it runs.
		"anchor": "ChassisBays", "toward": "ChassisBays",
		"cam": Vector3(0, 2.0, 7.0), "aim": Vector3(0, 1.2, 0),
		"cast": [],
		"ui_only": true,
	},
]

var _cam: Camera3D
var _hud: CanvasItem = null
var _host: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mockup_shots: this photographs the game, so it needs a window.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mockups"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var what: String = args[1].strip_edges().to_lower() if args.size() > 1 else "kit"
	_apply_size(args)

	if what == "kit":
		await _kit_shots(out_dir)
	else:
		await _store_shots(out_dir, what)
	print("mockup_shots: written to %s" % ProjectSettings.globalize_path(out_dir))
	quit(0)


## `--size 2560x1440`, and ONLY if asked for. This machine runs borderless
## fullscreen and a resized window lands small in the bottom-left corner, so the
## default is to photograph whatever the window already is.
##
## THE WINDOW IS NOT THE FRAME, THOUGH. project.godot sets
## display/window/stretch/mode="viewport", which is what gives the game its
## look: it renders at a fixed internal resolution and upscales to the window.
## So every grab off this rig comes out at that internal size — measured 1152x648
## — no matter how big the window is, and SHOT_BRIEF wants 2560x1440 or 1920x1080.
## Raising it means raising window/size/viewport_width and _height in
## project.godot, which is a shared file and changes how the game looks for
## everyone, so it is not something this tool does on its own.
func _apply_size(args: Array) -> void:
	var asked := ""
	for i in args.size():
		var s := str(args[i])
		if not s.begins_with("--size"):
			continue
		# Both spellings: --size=1920x1080, and --size 1920x1080 as two args,
		# which is how anyone actually types it.
		var val := s.replace("--size", "").replace("=", "").strip_edges()
		if val == "" and i + 1 < args.size():
			val = str(args[i + 1]).strip_edges()
		var wh := val.split("x")
		if wh.size() == 2 and wh[0].is_valid_int() and wh[1].is_valid_int():
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
			asked = val
		else:
			push_warning("mockup_shots: could not read '%s'; wanted --size 2560x1440." % s)
	var frame := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)))
	if asked != "" and str(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "viewport":
		push_warning(("mockup_shots: window set to %s, but stretch/mode is \"viewport\" so the "
			+ "frame is still the internal %dx%d. Raise display/window/size/viewport_width "
			+ "and _height in project.godot to change it — that is a shared setting.") % [
			asked, frame.x, frame.y])
	print("mockup_shots: frames will be %dx%d" % [frame.x, frame.y])

# ─────────────────────────────────────────────
# THE KIT LIST — the original caller, unchanged.
# ─────────────────────────────────────────────
func _kit_shots(out_dir: String) -> void:
	# A real level, for its WorldEnvironment and its sun. Without one the robots
	# are lit by nothing and every screenshot is a black rectangle.
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	root.add_child(_cam)
	_cam.current = true
	for _i in 30:
		await process_frame

	# One wide line-up of every fitting, then a portrait of each.
	var kit: Array = _Parts.capsule_kit_list()
	await _group(kit, out_dir + "/ingame_kit_lineup.png")
	for entry in kit:
		await _portrait(entry[1], "%s/ingame_%s.png" % [out_dir, _slug(entry[0])])
	# The promotion, on its own: a blue soldier with an Ancient Rifle and a cap.
	for entry in _Parts.hat_list():
		if str(entry[0]) == "PEAKED CAP":
			await _portrait(entry[1], out_dir + "/ingame_nco_peaked_cap.png")


# ─────────────────────────────────────────────
# THE STORE SHOTS
# ─────────────────────────────────────────────
func _store_shots(out_dir: String, which: String) -> void:
	var todo: Array = []
	for s in SHOTS:
		if which == "marketing" or which == str(s["id"]):
			todo.append(s)
	if todo.is_empty():
		var ids: Array = []
		for s in SHOTS:
			ids.append(str(s["id"]))
		printerr("mockup_shots: no shot called '%s'. Have: marketing, %s" % [
			which, ", ".join(ids)])
		return

	# THE WORLD, FOR THE HUD. The kit shots load a bare level because they only
	# need its lighting; the brief wants every store shot in two passes, HUD on
	# and HUD off, and the HUD is not in a level — it is in world.tscn, with the
	# player and the campaign. So the world comes up once and the five levels
	# are added into it in turn.
	#
	# AUTOSAVE OFF BEFORE IT CAN TICK. A campaign that boots with autosave on
	# writes the player's real campaign.json, and photographing the game is not
	# a reason to touch a save. This has gone wrong once already.
	var world: Node = load("res://Env/world.tscn").instantiate()
	var cm := world.get_node_or_null("CampaignManager")
	if cm != null:
		cm.autosave = false
	root.add_child(world)
	for _i in 120:
		await process_frame

	# AND TAKE THE DEPOT BACK DOWN — BUT KEEP ITS SUN. world.tscn ships with
	# Homebase already in it, because that is where the game starts, so adding
	# a shot level beside it puts two levels at the same origin: the first pass
	# came back as a photograph of the inside of a depot wall.
	#
	# NONE OF THE FIVE SHOT LEVELS HAS A LIGHT IN IT. Checked: coastal-road,
	# mutaha, valley_basin, pittsburgh and depot all carry zero
	# WorldEnvironment and zero DirectionalLight3D — homebase_level is the only
	# map in the repo that does, and it lights the whole world from there. So
	# deleting Homebase outright turned every store shot into a dark rectangle.
	# Its WorldEnvironment is lifted out first and kept for the rest of the run,
	# which is also what gives SHOT_BRIEF the one time of day held across all
	# five: there is only one sun, and every level is photographed under it.
	var homebase := world.get_node_or_null("Homebase")
	if homebase != null:
		var sun := homebase.get_node_or_null("WorldEnvironment")
		if sun != null:
			homebase.remove_child(sun)
			world.add_child(sun)
		else:
			push_warning("mockup_shots: no WorldEnvironment under Homebase, so the shots will be unlit.")
		world.remove_child(homebase)   # remove_child first: queue_free is deferred
		homebase.queue_free()
	await process_frame
	_host = _find_player_parent()
	if _host == null:
		push_warning("mockup_shots: no Player in world.tscn, so levels go under the root and there will be no HUD.")
		_host = root

	for s in todo:
		await _store_shot(out_dir, s)


func _store_shot(out_dir: String, spec: Dictionary) -> void:
	var id := str(spec["id"])
	# ONE LEVEL PER PROCESS WOULD BE CLEANER, but five processes is five of
	# everything; the level is torn down and the next one built in its place.
	var level: Node = load(str(spec["level"])).instantiate()
	_host.add_child(level)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55.0        # wider than the kit portraits: these are places
		root.add_child(_cam)
	_cam.current = true
	# Terrain and CSG both build on entering the tree, and the navmesh behind
	# them settles a frame or two later. A grab before that photographs a level
	# with holes in it.
	for _i in 90:
		await process_frame

	var anchor := _landmark(level, str(spec["anchor"]))
	var toward := _landmark(level, str(spec["toward"]))
	if anchor == Vector3.INF or toward == Vector3.INF:
		# SAYS WHY, AND KEEPS GOING. The landmarks are node names in a level
		# another lane owns; one of them being renamed should cost this shot,
		# not the other four.
		push_warning("%s: landmark '%s' or '%s' is not in %s any more, so it was skipped." % [
			id, spec["anchor"], spec["toward"], str(spec["level"]).get_file()])
		level.queue_free()
		await process_frame
		return

	var cast_made: Array[Node3D] = []
	for entry in spec.get("cast", []):
		var made := _frame(str(entry[0]), anchor + (entry[1] as Vector3), float(entry[2]), level)
		if made != null:
			cast_made.append(made)

	_cam.global_position = anchor + (spec["cam"] as Vector3)
	_cam.look_at(toward + (spec["aim"] as Vector3), Vector3.UP)

	if bool(spec.get("ui_only", false)):
		print("")
		print("  %s NEEDS A HUMAN. The brief wants the squad manager open on a" % id)
		print("  roster with ranks on it, and ranks come from a campaign that has")
		print("  been played. This rig will not open a profile to get them: writing")
		print("  to campaign.json is how a real save got overwritten once already.")
		print("  Open the depot on your own campaign, press the manager key, and")
		print("  grab it. The frame below is the backdrop, for reference.")

	await _pass(out_dir, id)
	for n in cast_made:
		n.free()
	level.queue_free()
	await process_frame


## Both passes off one staging, which is the whole point of doing it here.
func _pass(out_dir: String, id: String) -> void:
	_find_hud()
	if _hud != null:
		_hud.visible = true
		await _shoot("%s/%s_hud.png" % [out_dir, id])
		_hud.visible = false
		await _shoot("%s/%s_nohud.png" % [out_dir, id])
		_hud.visible = true
	else:
		# NOT SILENT. A bare level has no HUD in it — the HUD lives in
		# world.tscn — so a run that forgot world comes back with half the set
		# and no explanation unless this says so.
		push_warning("%s: no HUD layer in the tree, so only the clean pass was taken." % id)
		await _shoot("%s/%s_nohud.png" % [out_dir, id])


func _find_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		return
	_hud = null
	# BY NAME, AND IT IS A Control. The first version scanned for a CanvasLayer
	# because that is what a HUD usually is; hud.tscn's root is a Control, so
	# the scan found nothing and every store shot came back clean-pass only.
	for n in root.find_children("HUD", "", true, false):
		if n is CanvasItem:
			_hud = n as CanvasItem
			return


## Where a level has to go to be lit and seen by the HUD: the node the player
## lives under, which is what Campaign.on_level_loaded parents levels to.
##
## BY SCRIPT CLASS, NOT BY NODE NAME. The player node in world.tscn is called
## `test_character`, so looking for one called "Player" found nothing and the
## levels went under the root instead.
func _find_player_parent() -> Node:
	for n in root.find_children("*", "CharacterBody3D", true, false):
		var s: Script = n.get_script() as Script
		if s != null and s.get_global_name() == &"Player":
			return n.get_parent()
	return null


func _landmark(level: Node, wanted: String) -> Vector3:
	var hits := level.find_children(wanted, "", true, false)
	if hits.is_empty() or not (hits[0] is Node3D):
		return Vector3.INF
	return (hits[0] as Node3D).global_position


## One member of the cast, parked and switched off. Same reasoning as _soldier:
## a robot left thinking walks out of shot looking for something to shoot.
func _frame(kind: String, at: Vector3, facing_deg: float, level: Node) -> Node3D:
	if not FRAMES.has(kind):
		push_warning("mockup_shots: no frame called '%s'." % kind)
		return null
	var bot: Node3D = load(FRAMES[kind]).instantiate()
	# Blue. FactionLivery reads this off its parent in _ready, so it has to be
	# set BEFORE the node enters the tree or the robot comes out enemy amber.
	bot.faction = Enums.Factions.ALLIED
	level.add_child(bot)
	bot.global_position = at
	bot.rotation.y = deg_to_rad(facing_deg)
	bot.set_physics_process(false)
	bot.set_process(false)
	return bot


func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "_")


# A row of soldiers, one per fitting, seen together so they can be compared.
func _group(entries: Array, file: String) -> void:
	var made: Array[Node3D] = []
	var span := float(entries.size() - 1) * SPACING
	for i in entries.size():
		var at := STAGE + Vector3(-span * 0.5 + float(i) * SPACING, 0, 0)
		made.append(_soldier((entries[i] as Array)[1], at))
	_cam.global_position = STAGE + Vector3(0, 1.4, -span * 0.62 - 6.0)
	_cam.look_at(STAGE + Vector3(0, 0.1, 0), Vector3.UP)
	await _shoot(file)
	for n in made:
		n.free()


# One soldier, close, turned three-quarter on so the fitted side is toward the
# camera — the same angle the icons use, for the same reason.
func _portrait(build: Callable, file: String) -> void:
	var bot := _soldier(build, STAGE)
	_cam.global_position = STAGE + Vector3(-2.30, 1.05, -3.80)
	_cam.look_at(STAGE + Vector3(0, 0.05, 0), Vector3.UP)
	# TURNED BY MEASUREMENT, NOT BY GUESSWORK — but on the FLAT only. look_at to
	# a camera that is above the robot pitches the robot forward to meet it, and
	# the photograph comes back of a soldier falling over. Aim at the camera's
	# ground position and the yaw is all that changes.
	var flat := Vector3(_cam.global_position.x, bot.global_position.y, _cam.global_position.z)
	bot.look_at(flat, Vector3.UP)
	# The extra yaw swings its right side into view, which is the side
	# everything is fitted to.
	bot.rotate_y(deg_to_rad(42.0))
	await _shoot(file)
	bot.free()


func _soldier(build: Callable, at: Vector3) -> Node3D:
	var bot: Node3D = load(SOLDIER).instantiate()
	# Blue. FactionLivery reads this off its parent in _ready, so it has to be
	# set BEFORE the node enters the tree or the robot comes out enemy amber.
	bot.faction = Enums.Factions.PLAYER
	var mount = bot.get("weapon_mount")
	if mount != null and mount is Node3D:
		(mount as Node3D).add_child(load(RIFLE).instantiate())
	# IN THE TREE FIRST, THEN BOLT THINGS ON, THEN PAINT. The livery runs in
	# _ready and only ever walks the pieces the scene lists, so anything added
	# afterwards keeps Godot's default white — the first pass came back with
	# lavender shoulder plates on a blue robot.
	root.add_child(bot)
	# ONLY WHAT WE ADDED gets repainted: the robot's own hull and its eye are
	# already its children, and painting those rust turned its one facial
	# feature into a scab.
	var before := bot.get_child_count()
	build.call(bot)
	_paint(bot, before)
	# Standing still and not thinking: this is a photograph, not a fight, and a
	# soldier left to its own devices walks out of shot looking for a target.
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.global_position = at
	bot.rotation.y = deg_to_rad(200.0)
	return bot



# Hand every bolted-on piece its OWN material. Kit is bought hardware, not part
# of the hull, and painting it faction blue is what made the armour vanish into
# the body. It is also RUSTED rather than flat matte: the hull it bolts to is
# a rusted texture was tried and read as varnished wood at this scale, and as
# tweed once the noise was fine enough not to.
func _paint(bot: Node3D, from: int) -> void:
	var armor := _Parts.armor_material()
	for i in range(from, bot.get_child_count()):
		var child := bot.get_child(i)
		if child is CSGCombiner3D:
			(child as CSGCombiner3D).material_override = armor
		elif child is CSGShape3D:
			(child as CSGShape3D).material = armor


func _shoot(file: String) -> void:
	# CSG rebuilds its mesh the frame after it enters the tree, so an immediate
	# grab catches half-built armour.
	for _i in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(file)
	if err != OK:
		printerr("mockup_shots: could not write %s (%s)" % [file, error_string(err)])
