extends Node3D

# ─────────────────────────────────────────────
# THE VERTICAL SLICE, ASSEMBLED AT RUNTIME ON VALLEY BASIN.
#
# Stage 1 of docs/briefs/CAMPAIGN_REWORK.md: the whole in-mission loop on one
# map with everything campaign-side faked, so the question the entire plan is
# downstream of — IS THIS FUN — can be answered before another line of the
# campaign layer is written.
#
# WHY A RUNTIME NODE AND NOT A FIT SCRIPT. The first attempt wrote the nodes
# into maps/valley_basin_level.tscn the way tools/fit_ops_table.gd writes into
# the ops car. That works there because the car is GENERATED and flat — one
# FuncGodotMap and nothing else. Valley Basin is hand-authored and made of
# instanced prefabs, and `PackedScene.pack()` on an instantiated copy BAKES
# THOSE INSTANCES IN: the scene went 8,199 lines to 9,692, every `uid` was
# dropped, and the links to spawn_point.tscn, level_exit.tscn and the rest were
# replaced by copies of their contents. Reverted from a backup; do not do it
# again on an authored scene.
#
# So nothing is written to disk. This node is dropped in the level once, and
# everything else it needs it builds when the map loads.
#
# WHAT IT DOES NOT TOUCH. The four authored capture points keep their meshes,
# their motes and their ids. A HoldableCore is parented to each and takes the
# terminal over at runtime (see holdable_core.gd) — so removing the slice is
# removing this one node, and nothing authored was altered to try it.
#
# SCAFFOLDING, NOT THE SYSTEM. The layout below is hardcoded for one map on
# purpose. When Phase 5b lands properly, maps carry their own cores and the
# campaign supplies the resistance; this exists to answer one question first.
# ─────────────────────────────────────────────

const _Core := preload("res://Env/world_objects/holdable_core.gd")
const _Op := preload("res://Env/world_objects/site_operation.gd")
const _Heat := preload("res://Env/world_objects/site_heat.gd")
const _Commander := preload("res://Env/world_objects/enemy_commander.gd")
const _BunkerObj := preload("res://Env/world_objects/bunker_objective.gd")
const _Signal := preload("res://Env/world_objects/core_signal.gd")

## The two door leaves, and the way out past them. Held so the stand-down can
## drive the doors and the win can open the exit.
var _leaf_left: Node3D = null
var _leaf_right: Node3D = null
var _exit_volume: Node3D = null

## HOW TALL THE BEACON STANDS, per map.
##
## CoreSignal exports BEACON_HEIGHT at 34 m and _dress never set it, so every
## site got 34 whatever its geometry — and a subclass had no way to change it.
## That is fine in an open bowl and wrong indoors: the Causeway's cores sit at
## y 72 and y 138 in halls with 5.25 m of clearance, where a 34 m column spears
## six floors. 0 keeps CoreSignal's own default.
@export var beacon_height: float = 0.0
const INTERACTIBLE := preload("res://Env/world_objects/components/template_interactible.tscn")

## The authored capture points, and the size each should be.
## 0 small · 1 medium · 2 large. The anchor is the prize and is already
## authored with a ten-second channel, so it is the large one.
## THE AUTHORED CAPTURE POINTS, by node name, and the size each should be.
## 0 small · 1 medium · 2 large.
##
## BY NODE NAME because that is what a level actually offers: these are nodes
## the map author placed, and a slice is the thing that turns them into cores.
@export var cores_by_node: Dictionary = {
}

## THE BUNKER — the way down, at the east pass. Not one of the cores it counts:
## it is a place, and taking it starts the stand-down (§12.7).
##
## FOUND BY MARKER, NOT TYPED. Basin_ExitPass is an authored squad objective
## point and it is already where the briefing says the operation ends, so the
## bunker reads its position rather than carrying a copy of it. The first cut
## hardcoded Vector3(356, -11.25, 140), which is the same rule this project
## broke three times on terrain before writing it down: a typed coordinate is
## correct until somebody moves the thing it was copied from, and then it is
## silently wrong. Measured where it lands — on collision, 0.42 m off the
## navmesh, 34 m past the old exit — but measured is not the same as derived.
@export var bunker_marker: StringName = &""
## Only if the marker is gone, and it says so when it uses this.
@export var bunker_fallback: Vector3 = Vector3.ZERO
@export var bunker_tier: int = 1

## WHICH WAY THE DOORS FACE, in degrees about Y.
##
## The entrance kit is authored facing +Z and nine sites were fine with that,
## so this defaults to 0 and changes nothing anywhere it is not set.
##
## HILLFORT REDOUBT NEEDED IT. Its bunker sits 17 m behind the relay dish's
## pedestal, so a squad surfacing there got the back of a 62 m dish filling the
## frame and no sightline at all to the gate the doors are meant to hold —
## §12.8 is "you come up out of the ground and turn round to hold the ground in
## front of them", and there was no ground in front of them to hold. TERRAIN
## measured the clearance at that exact spot and asked for the call; turning
## the doors keeps the measurement and buys 50 m of open yard, where moving the
## entrance would have thrown the clearance away.
##
## It rotates the HOST, so the kit, its handles and both leaves travel with it
## and nothing downstream has to know.
@export var bunker_yaw: float = 0.0


## Total enemy supply for the site. Measured off the authored force rather than
## invented — §2, resistance is supply, not squad count. basin_1_anchor's
## roster sums to 82.
@export var resistance: int = 82

## How long the attacker's pool takes to spend on a DEFENCE. The defence ends
## when it is spent and the field is clear, so this is how long holding takes.
@export var defence_assault_seconds: float = 240.0
@export var stand_down_seconds: float = 45.0
## Which act this site is fought in. Faked at 1 for the slice; the campaign
## supplies it for real later.
@export var act: int = 1

## Where heat-committed reinforcements walk on from. Authored squad points at
## the edges of the map, so they arrive from depth.
@export var entry_markers_named: Array[StringName] = []

var operation: Node3D = null
var heat: Node3D = null
var cores: Array = []
var commander: Node3D = null
var _label: Label = null


func _ready() -> void:
	var level := get_parent()
	if level == null:
		push_warning("SiteSlice: no parent to search, so nothing is fitted and the map plays as it always did.")
		return

	for named in cores_by_node:
		var host := _find(level, named) as Node3D
		if host == null:
			push_warning("SiteSlice: no '%s' in the level, so that core is not holdable. Has the map been re-authored?" % named)
			continue
		var c := _seat_core(host, int(cores_by_node[named]))
		if c != null:
			cores.append(c)

	var bunker := _build_bunker(level)

	# WHICH KIND OF OPERATION THIS IS, asked once and used by both halves.
	var cm_op = get_tree().get_first_node_in_group("campaign")
	var op_def = cm_op.current_mission if cm_op != null and "current_mission" in cm_op else null
	var is_defence: bool = op_def != null and "defence" in op_def and op_def.defence

	# SOMEBODY COMES BACK FOR WHAT YOU TAKE. HoldableCore lets hostiles retake
	# a core by standing in its circle; this is the thing that sends them.
	# Added here rather than into every level, for the same reason the cores
	# are: the behaviour belongs to a SITE, and a level should not carry nodes
	# that belong to a system.
	var retakers := Node.new()
	retakers.name = "CoreRetakers"
	retakers.set_script(preload("res://Env/world_objects/core_retakers.gd"))
	# BEFORE add_child, like SiteOperation below: CoreRetakers scans for cores
	# in _ready, which fires the moment it is parented. Handing it the level
	# rather than letting it find its own way is what stops it depending on
	# get_tree().current_scene, which is null in every headless harness.
	retakers.search_root = level
	add_child(retakers)

	operation = Node3D.new()
	operation.set_script(_Op)
	operation.name = "SiteOperation"
	operation.bunker = bunker
	operation.stand_down_seconds = stand_down_seconds
	operation.defence = is_defence
	# BEFORE add_child: SiteOperation walks for cores in _ready, which fires the
	# moment it is parented.
	operation.search_root = level

	# HEAT IS BUILT BEFORE THE OPERATION IS PARENTED, because on a defence the
	# operation connects to its pool_spent in _ready — and _ready fires the
	# instant it is added. The two reference each other, so both nodes are made
	# first and only then put in the tree.
	heat = Node3D.new()
	heat.set_script(_Heat)
	heat.name = "SiteHeat"
	heat.operation = operation
	operation.heat = heat

	# AND IT HAS TO ACTUALLY END THE OPERATION.
	#
	# SiteOperation decides the win; nothing used to act on it. operation_complete
	# ticked BunkerObjective's line and that was all — the player stood in a
	# finished mission with no extraction objective pointing anywhere, because
	# §12.7 replaced the extraction with the bunker and the going-home half was
	# never wired. Campaign.open_way_out() is the real sequence; see the note there
	# for why it moves the player rather than calling extract().
	operation.operation_complete.connect(_on_operation_won)
	# THE DOORS ARE THE PROGRESS BAR. §12.7 is "the time it takes to open the
	# way down", and the player spends it standing next to this being shot at —
	# so the leaves have to say how far through it is with no HUD element. One
	# float drives both, and because it is a position rather than an animation,
	# a stand-down that stalls when the bunker is lost simply stops moving and
	# resumes where it left off.
	operation.stand_down_progress.connect(_on_doors)
	add_child(operation)

	# The bunker as a HUD line, so the stand-down is read where every other
	# objective is read rather than in a corner label of its own.
	var bobj := Node3D.new()
	bobj.set_script(_BunkerObj)
	bobj.name = "BunkerObjective"
	bobj.display_name = "HOLD THE BUNKER"
	bobj.operation = operation
	bobj.starts_active = true
	add_child(bobj)
	# The tracker built its list before any of this existed.
	var camp := get_tree().get_first_node_in_group(&"campaign")
	if camp != null and camp.get("objectives") != null:
		camp.objectives.refresh.call_deferred()

	# RESISTANCE FROM THE LOCATION, where a campaign is running.
	#
	# The export below is the Stage 1 fallback and was measured by hand; the
	# board now carries the same number, derived by tools/measure_resistance.gd
	# from the same authored force. Reading it here means the slice and the
	# operations table cannot disagree about how hard this place is, and the
	# hardcoded 82 stops being a second source of truth.
	#
	# Falls back silently when there is no campaign: probes and shot scripts
	# load this level on its own, and that is not an error.
	# THE LOCATION FOR THE OPERATION BEING PLAYED, not a hardcoded id.
	#
	# This used to ask for `basin_1_anchor` by name, which happened to work on
	# the defence only because both operations resolve to the same Location.
	# On any other map, and on any site whose two operations are not a pair,
	# it would have read the wrong site's resistance.
	var cm = get_tree().get_first_node_in_group("campaign")
	var st = cm.state if cm != null and "state" in cm else null
	var op_now = cm.current_mission if cm != null and "current_mission" in cm else null
	var site = st.locations.for_mission(op_now.id) if st != null and st.locations != null and op_now != null else null
	if site != null:
		if int(site.resistance) != resistance:
			print("[SiteSlice] resistance from the Location: %d (export said %d)" % [
				int(site.resistance), resistance])
		resistance = int(site.resistance)
	heat.resistance = resistance
	# A DEFENCE IS A TIMED ASSAULT, not a slow build — see SiteHeat.assault_seconds.
	# Four minutes of attacker supply: long enough to be a fight, short enough
	# that holding is a thing that visibly ENDS.
	if is_defence:
		heat.assault_seconds = defence_assault_seconds
	add_child(heat)

	# The thing that turns committed supply into bodies. Without it heat drains
	# its reserve and nothing arrives, which is how the first playtest ran.
	commander = Node3D.new()
	commander.set_script(_Commander)
	commander.name = "EnemyCommander"
	commander.heat = heat
	commander.act = act
	# Reinforcements come on from the authored squad points, furthest from the
	# target first, so they arrive from depth rather than on top of the player.
	var entries: Array[Node3D] = []
	for named in entry_markers_named:
		var m := _find(level, named) as Node3D
		if m != null:
			entries.append(m)
	commander.entry_markers = entries
	add_child(commander)

	# ── A DEFENCE STARTS WITH THE GROUND ALREADY YOURS (Phase 5) ────────
	#
	# The cores are what a defence is fought over, so on one they begin
	# PLAYER-held with their anchors standing and the attackers take them by
	# shooting those off. On an attack they begin hostile, as they always have.
	#
	# The first cut of the defence left them hostile — orange, untakeable,
	# nothing to lose — so the map had no win or lose condition. Reported from
	# the first watch of it.
	if is_defence:
		for c in cores:
			if c != null and c.has_method("start_held"):
				c.start_held()
		if operation != null and operation.bunker != null \
				and operation.bunker.has_method("start_held"):
			operation.bunker.start_held()
		print("[SiteSlice] DEFENCE: %d cores start held, anchors standing" % cores.size())


	print("[SiteSlice] %d cores + bunker, %d supply of resistance, %.0fs stand-down" % [
		cores.size(), resistance, stand_down_seconds])


## A HoldableCore parented to an authored capture point, handed that point's own
## terminal. Handed rather than hunted: the Interactible is a child of the
## authored node, which makes it the core's SIBLING, and a core only searches
## its own children.
func _seat_core(host: Node3D, tier: int) -> Node3D:
	# THE TERMINAL IS FOUND BEFORE THE CORE IS BUILT. The core used to be
	# stood up first, and the bail below then dropped the only reference to
	# it — the H10 defect class, since the orphan keeps the holdable_core.gd
	# GDScript alive into ObjectDB's exit sweep. Measured on this exact path
	# (K24, 2026-10-26): a leaked Node3D "Hold" and
	# `Resource still in use: holdable_core.gd (GDScript)`, which is the tell
	# in the log. A node that is never created cannot leak.
	var inter = _interactible_under(host)
	if inter == null:
		push_warning("SiteSlice: '%s' has no Interactible, so it cannot be captured." % host.name)
		return null
	var core := Node3D.new()
	core.set_script(_Core)
	core.name = "Hold"
	core.size_tier = tier
	core.interactible = inter
	host.add_child(core)
	_dress(host, core)
	_build_core_body(host, tier)
	_fit_reach(inter, tier)
	return core


## A CORE YOU CAN SEE AND WALK UP TO.
##
## Valley Basin uses capture_point.tscn, which is a dummy terminal and a drift
## of motes — NOT compute_core_point.tscn, the 4-to-12 metre structure. So
## there was literally no core on the map to interact with, which is what the
## first playtest reported. This stands one up.
##
## Placeholder, sized off the real prefabs so the scale is right when TERRAIN
## replaces it: footprints 1.88 / 3.38 / 5.19, heights 4.19 / 6.97 / 12.38.
func _build_core_body(host: Node3D, tier: int) -> void:
	if host.get_node_or_null(^"CoreBody") != null:
		return   # already standing; a level can be re-entered
	# AND NOT ON A HOST THAT ALREADY HAS A REAL CORE.
	#
	# This builds a placeholder column for a host that is only a terminal. Every
	# capture point on the eight maps still to convert is a
	# compute_core_point*.tscn, which ships an actual `Core` mesh — so this
	# would stand a grey box inside it and add a second collider around it.
	# _hide_authored_console() hides the Terminal's parts and has never touched
	# `Core`, so nothing downstream caught it.
	#
	# The docstring above used to say Valley Basin was exempt because it uses
	# capture_point.tscn. It does not: valley_basin_level.tscn instances
	# compute_core_point_small.tscn, same as the rest. Found by a recon pass
	# over the maps rather than by anything going wrong, because a box inside a
	# core looks like a core.
	if host.get_node_or_null(^"Core") != null:
		return
	_hide_authored_console(host)
	var foot: float = [1.88, 3.38, 5.19][clampi(tier, 0, 2)]
	var tall: float = [4.19, 6.97, 12.38][clampi(tier, 0, 2)]

	var body := MeshInstance3D.new()
	body.name = "CoreBody"
	var bm := BoxMesh.new()
	bm.size = Vector3(foot * 0.55, tall, foot * 0.55)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.19, 0.20)
	mat.emission_enabled = true
	# Amber while theirs, from the palette. The pillar is the biggest thing on
	# the objective and should read its state before the label does — once FX
	# land this is what the light climbing the shaft tints (§13.2).
	mat.emission = HUDPalette.FAC_ADVERSARY
	mat.emission_energy_multiplier = 0.55
	body.material_override = mat
	body.position = Vector3(0.0, tall * 0.5, 0.0)
	host.add_child(body)

	# COLLISION, so it is a pillar rather than a hologram you walk through. On a
	# StaticBody3D of its own: the interact volume is an Area3D on layer 3 and
	# must stay separate, or the ray would stop on the body before reaching it.
	var solid := StaticBody3D.new()
	solid.name = "CoreSolid"
	var scs := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = bm.size
	scs.shape = sbox
	solid.add_child(scs)
	solid.position = Vector3(0.0, tall * 0.5, 0.0)
	host.add_child(solid)

	# A plinth, so it reads as installed rather than dropped.
	var base := MeshInstance3D.new()
	base.name = "CoreBase"
	var pm := BoxMesh.new()
	pm.size = Vector3(foot, 0.5, foot)
	base.mesh = pm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.14, 0.15, 0.14)
	base.material_override = bmat
	base.position = Vector3(0.0, 0.25, 0.0)
	host.add_child(base)


## The bunker has no authored furniture, so it brings its own terminal.
## WHICH MOUNTING THE BUNKER USES, per map.
##
## TERRAIN's kit ships the entrance as one module plus three surrounds, because
## nine maps that look nothing alike cannot share one monument: "open" is a
## sunken court for open ground, "cliff" a revetted headwall for a slope, and
## "wall" a flush interior surround for somewhere with a ceiling. See
## docs/briefs/BUNKER_ENTRANCE_MODEL.md.
@export var bunker_mount: StringName = &"open"

## NUDGE OFF THE MARKER, in the level's own axes.
##
## A marker is a POSITION and nothing about it promises 9 m of clear ground in
## front of a 9 m door. Two of the nine landed in something: the Causeway's
## CW_Bunker is a post INSIDE an authored sandbag redoubt, so the entrance came
## up buried 3.3 m with its doorway packed, and Polaris had a wall 2 m off the
## opening. Both were found by tools/probe_bunker_clear.gd, which is the thing
## to re-run after moving one of these.
##
## Measured, never guessed — the rule this project has broken on terrain three
## times. Zero on a map whose marker already stands in the open.
@export var bunker_offset: Vector3 = Vector3.ZERO

const BUNKER_MOUNTS := {
	&"open": preload("res://maps/blocks/bunker/bunker_entrance_open.tscn"),
	&"cliff": preload("res://maps/blocks/bunker/bunker_entrance_cliff.tscn"),
	&"wall": preload("res://maps/blocks/bunker/bunker_entrance_wall.tscn"),
}


## THE WAY DOWN — a real entrance now, not the placeholder post.
##
## It used to build a 1.2 m glowing box on a 6 m slab, which is the wrong order
## of magnitude for a thing a train runs under and read as a bollard. The kit
## replaces it wholesale: a mouth, two leaves that slide, a signal strip, and
## the named handles this function hangs gameplay off —
##
##   TerminalFace   where you press F
##   DockPad        where the tap drone lands
##   ExitVolume     the point past which the squad has left
##   LeafLeft/Right the stand-down, as geometry
##
## NOTHING IS MEASURED OFF THE MESH. Every one of those is a node TERRAIN
## placed from its own constants, so this reads positions rather than guessing
## them — the rule this project has broken on terrain three times.
func _build_bunker(level: Node) -> Node3D:
	var host := Node3D.new()
	host.name = "SiteBunker"
	add_child(host)
	var mark := _find(level, bunker_marker) as Node3D
	if mark != null:
		host.global_position = mark.global_position + bunker_offset
	else:
		push_warning("SiteSlice: no '%s' marker in the level, so the bunker falls back to a typed position that may no longer be on the ground." % bunker_marker)
		host.global_position = bunker_fallback + bunker_offset
	host.rotation.y = deg_to_rad(bunker_yaw)

	var mount: PackedScene = BUNKER_MOUNTS.get(bunker_mount, null)
	if mount == null:
		push_warning("SiteSlice: '%s' is not a bunker mounting; using the open court. Pick one of %s." % [
			String(bunker_mount), str(BUNKER_MOUNTS.keys())])
		mount = BUNKER_MOUNTS[&"open"]
	var kit := mount.instantiate()
	kit.name = "Entrance"
	host.add_child(kit)

	# THE HANDLES. A missing one is not survivable silently — the whole point of
	# the kit is that gameplay attaches to names rather than to coordinates, so
	# a rename upstream has to be loud.
	var face := _find(kit, "TerminalFace") as Node3D
	var dock := _find(kit, "DockPad") as Node3D
	var way_out := _find(kit, "ExitVolume") as Node3D
	_leaf_left = _find(kit, "LeafLeft") as Node3D
	_leaf_right = _find(kit, "LeafRight") as Node3D
	for pair in [["TerminalFace", face], ["DockPad", dock], ["ExitVolume", way_out],
			["LeafLeft", _leaf_left], ["LeafRight", _leaf_right]]:
		if pair[1] == null:
			push_warning("SiteSlice: the bunker kit has no '%s'. It has been renamed or the module is stale, and the bunker will not work properly without it." % pair[0])

	# F GOES ON THE TERMINAL FACE, not in the middle of the doorway.
	var inter = INTERACTIBLE.instantiate()
	host.add_child(inter)
	if face != null:
		inter.global_position = face.global_position
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Sized to a thing you walk up to and no bigger. An oversized volume is one
	# the player ends up standing INSIDE, where the interact ray reports
	# nothing at all — the same trap the compute cores already document.
	box.size = Vector3(2.4, 1.8, 2.4)
	cs.shape = box
	cs.position = Vector3(0.0, 0.9, 0.0)
	inter.add_child(cs)

	var core := Node3D.new()
	core.set_script(_Core)
	core.name = "Hold"
	core.size_tier = bunker_tier
	core.mark_noun = "BUNKER"
	# OFF THE PAD TERRAIN PLACED, not from the tier table and not from the
	# geometry. The drone is 3.4 m across and has to land ON the model.
	core.dock_height = (dock.global_position.y - host.global_position.y) if dock != null else 4.9
	core.interactible = inter
	host.add_child(core)
	_exit_volume = way_out
	_dress(host, core, _find(kit, "BeaconMount") as Node3D)
	return core


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _find(c, named)
		if f != null:
			return f
	return null


func _interactible_under(n: Node):
	for c in n.get_children():
		if c is Interactible:
			return c
		var f = _interactible_under(c)
		if f != null:
			return f
	return null


## AN ON-SCREEN READOUT, because a slice you cannot read is a slice you cannot
## judge. Everything below is scaffolding for Stage 1 only — the real versions
## are a core state you read off the core itself (§12.3) and a coarse pressure
## band on the HUD (§12.4). This is here so the first question can be answered
## at all: is any of it happening.
func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SliceReadout"
	layer.layer = 3
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 120.0)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.62, 0.90, 0.72))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	# A slow tick rather than per-frame: this is four numbers and nobody is
	# reading them sixty times a second.
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(_refresh_readout)
	add_child(t)
	_refresh_readout()


func _refresh_readout() -> void:
	if _label == null or operation == null or not is_instance_valid(operation):
		return   # torn down with the level
	var held: int = operation.held_cores()
	var total: int = operation.cores.size()
	# The objective HUD and the minimap now carry core state — the cores drive
	# the authored objectives both ways (holdable_core.gd). What is left here is
	# the two things no existing HUD has a concept of.
	var lines: Array = []
	if operation.bunker != null and is_instance_valid(operation.bunker):
		var b: String = "HELD" if operation.bunker.is_held_by_player() else "ADVERSARY"
		lines.append("BUNKER  %s      cores %d / %d" % [b, held, total])
	if operation.is_standing_down():
		lines.append("STAND-DOWN  %d%%" % int(round(operation.stand_down_fraction() * 100.0)))
	elif operation.stand_down_fraction() > 0.0:
		lines.append("STAND-DOWN  %d%%  (stalled)" % int(round(operation.stand_down_fraction() * 100.0)))
	if heat != null and is_instance_valid(heat):
		lines.append("PRESSURE  %s   reserve %d / %d" % [
			["QUIET", "BUILDING", "COMMITTED", "SPENT"][clampi(heat.pressure(), 0, 3)],
			heat.remaining(), heat.resistance])
	_label.text = "\n".join(lines)


## MAKE THE WHOLE CORE REACHABLE.
##
## Measured: every authored capture point ships a 1.88 x 3 x 1.88 interact
## volume, whatever size the core is. The anchor is 12.4 m tall and 2.85 m
## wide, so standing at its base and looking up the shaft sends the player's
## 2 m ray straight over a box that stops 3 m off the ground. You could see the
## core, you could not use it.
##
## So the volume becomes the core's own footprint, full height. That is the one
## shape that cannot go wrong here, because _build_core_body gives the pillar
## COLLISION — the player can never be inside the footprint, which is the
## condition an interact volume needs (a ray that starts inside one reports
## nothing).
##
## SET `reach_size`, DO NOT TOUCH THE SHAPE.
##
## DummyTerminal already owns this: it has a `reach_size` export and sizes its
## own CollisionShape3D in _ready, duplicating the shared shape first for
## exactly the reason you would. Writing the shape directly loses a race —
## SiteSlice sits near the top of the scene so its _ready runs first, the
## terminal readies afterwards and puts the console-sized default straight
## back. Measured: set to 6.39 x 12.38, read back as 1.88 x 3.
##
## That is the SECOND time this slice has lost the same race (see
## holdable_core._take_terminal). The lesson both times is the same — when an
## authored node already exposes a knob, set the knob.
## THE REACH VOLUME — but only where the prefab did not author one.
##
## THIS USED TO OVERWRITE, ALWAYS, from a table of its own:
##     foot = [1.88, 3.38, 5.19][tier]
##     tall = [4.19, 6.97, 12.38][tier]
## Those numbers were measured off the OLD core art. TERRAIN rebuilt the three
## core prefabs on 2026-10-14 and they are a different size and no longer
## square in plan — small is 3.56 x 4.50 x 5.56, medium 4.81 x 7.31 x 6.31,
## large 6.56 x 12.72 x 8.25 — and the new prefabs carry their OWN reach, inset
## about 0.7 m inside the core, which is the clearance this is supposed to
## produce. Overwriting that with the stale table put a 3.08 m volume around a
## 3.56 x 5.56 m core: smaller than the thing it belongs to, so the terminal
## can only be reached from inside the core.
##
## Scene values beat script defaults — the project's own rule. A prefab that
## says what its reach is, wins. This now fills in only for a host that never
## said, which is what the fallback was for in the first place.
func _fit_reach(inter: Node, tier: int) -> void:
	var term := inter.get_parent()
	if term == null or not ("reach_size" in term):
		push_warning("SiteSlice: a terminal has no reach_size, so its core keeps the console-sized reach and a tall one cannot be used.")
		return
	if term.reach_size != Vector3.ZERO:
		return   # the prefab authored it; see above
	var foot: float = [3.56, 4.81, 6.56][clampi(tier, 0, 2)]
	var tall: float = [4.50, 7.31, 12.72][clampi(tier, 0, 2)]
	# The core footprint plus a margin, and its FULL height — a volume that
	# stops 3 m up on a 12.7 m core is one you can see and cannot use.
	term.reach_size = Vector3(foot + 1.2, tall, foot + 1.2)


## TAKE THE OLD CONSOLE OUT OF THE PICTURE.
##
## The authored capture point is a DummyTerminal — Body, Screen, Indicator,
## Label3D — and the new core pillar stands in the same spot, so you get both:
## a console buried inside a pillar. The console is the thing that goes.
##
## Hidden, not freed, and only its VISUALS. The Interactible is a child of that
## same terminal and is what the whole capture runs through; freeing the parent
## would take the terminal with it. Its UseSound stays too. Hiding a Node3D
## does not affect Area3D monitoring or the player's interact ray, both of
## which are physics.
func _hide_authored_console(host: Node3D) -> void:
	var term := host.get_node_or_null(^"Terminal")
	if term == null:
		return   # the bunker builds its own and has no authored console
	for part in ["Body", "Screen", "Indicator", "Label3D"]:
		var n := term.get_node_or_null(NodePath(part))
		if n != null and n is Node3D:
			(n as Node3D).visible = false


## LIGHT AND SOUND FOR A CORE, as a sibling node.
##
## Separate from the core so the presentation can be replaced wholesale when
## the real art exists, and so deleting it proves the state machine does not
## depend on it. core_signal.gd has the long version.
##
## `core` IS SET BEFORE add_child, not after. CoreSignal._ready reads it to
## find the shaft height, and add_child runs _ready synchronously — a node
## handed its subject afterwards has already decided it has none. The same
## mistake cost this slice two bugs; see §12 and holdable_core._on_tap_docked.
## Light and sound for a core.
##
## `mount` is where the beacon STANDS, when that is not the thing itself. A
## surface core is its own beacon base and passes nothing. The bunker is not:
## its origin is the middle of the doorway, so a column raised there goes up
## through the opening and out of the roof — which is exactly what the first
## screenshots of all nine maps showed. TERRAIN put a BeaconMount node off to
## one side of the mouth for this, and using it is the whole fix.
func _dress(host: Node3D, core: Node3D, mount: Node3D = null) -> void:
	if core == null or not is_instance_valid(core):
		push_warning("SiteSlice: asked to dress nothing, so a core will capture in silence.")
		return
	var fx := Node3D.new()
	fx.set_script(_Signal)
	fx.name = "Signal"
	fx.core = core
	# BEFORE add_child: CoreSignal reads its height in _ready, which fires the
	# instant it is parented.
	if beacon_height > 0.0:
		fx.BEACON_HEIGHT = beacon_height
	host.add_child(fx)
	if mount != null and is_instance_valid(mount):
		# AFTER add_child, because a global position means nothing until the
		# node is in the tree.
		fx.global_position = mount.global_position


## The operation is won. Take the squad home.
##
## DEFERRED, because operation_complete can fire from inside a physics step —
## the stand-down ticks in _physics_process — and the campaign touches the
## objective list and the exit, neither of which should change mid-step.
func _on_operation_won() -> void:
	_open_way_out.call_deferred()


func _open_way_out() -> void:
	var cm = get_tree().get_first_node_in_group("campaign")
	if cm == null or not cm.has_method("open_way_out"):
		push_warning("SiteSlice '%s': the operation was won but there is no campaign to extract through, so the mission cannot end." % name)
		return
	print("[SiteSlice] operation won: %s" % cm.open_way_out())


## HOW FAR EACH LEAF RUNS. Must match block_bunker.gd's TRAVEL — the leaves
## overlap their jambs by 0.3 m when shut, so a shorter throw leaves the way
## down visibly blocked and a longer one drives them into the surround.
const LEAF_TRAVEL := 4.3


## Open the doors to match the stand-down.
##
## POSITION, NOT AN ANIMATION. TERRAIN built LeafLeft and LeafRight as separate
## nodes precisely so one float could drive them: see the note at the top of
## tools/build_bunker.gd. It also means there is no animation state to get out
## of sync with the operation when a stand-down is interrupted and resumed.
func _on_doors(fraction: float) -> void:
	var f: float = clampf(fraction, 0.0, 1.0)
	if _leaf_left != null and is_instance_valid(_leaf_left):
		_leaf_left.position.x = -LEAF_TRAVEL * f
	if _leaf_right != null and is_instance_valid(_leaf_right):
		_leaf_right.position.x = LEAF_TRAVEL * f
