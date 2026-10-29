extends Node3D

# ─────────────────────────────────────────────
# OPERATIONS TABLE — Home Command's tasking board, in the world.
#
# This is the layer that knows about the campaign. It reads the mission list,
# works out what each site is worth and who holds it, and hands plain data to
# HoloBoard, which draws it and knows nothing. See docs/briefs/archive/OPERATIONS_TABLE.md.
#
# IT DRAWS EVERY MISSION, NOT THE AVAILABLE ONES. Campaign.available_missions()
# retires a cleared non-repeatable op entirely — eleven of the twelve shipped
# missions vanish from it the moment you finish them — so a board built on it
# would erase your own campaign behind you as you played. The node list comes
# from Campaign.missions; available_missions() is asked only the narrower
# question of whether a site can be queued right now.
#
# THE SELECTION GOES THROUGH select_mission(), never through
# state.selected_mission_id. That call also pushes the destination into the
# departure exits and emits mission_selected; setting the field by hand looks
# like it works and leaves the pad pointing at the last place you went.
# ─────────────────────────────────────────────

const _Board := preload("res://Env/world_objects/holo_board.gd")
const _Pal := preload("res://Character/hud/hud_palette.gd")
const _Icons := preload("res://Env/world_objects/site_icons.gd")
const _ZoomView := preload("res://Character/hud/ops_table_ui.gd")

## The Area3D you press F on. Found among the children if left unset.
@export var interactible: Interactible
## Where the projection hangs. Built as a child if left unset.
@export var board: Node3D
## Sites per row before the board wraps. See _layout.
@export var columns: int = 4
## Board-space units between sites.
@export var spacing: Vector2 = Vector2(100.0, 70.0)

var Campaign: Node = null
## id -> facts, rebuilt on every refresh. The zoomed view reads this rather
## than recomputing, so the table and the screen cannot disagree.
var facts: Dictionary = {}
## Hovered and queued, for the projection's own highlighting.
var _hovered = null
## The zoomed view, built on first use. See _zoom_view.
var _zoom = null


func _ready() -> void:
	add_to_group(&"ops_tables")
	Campaign = _find_campaign()
	if Campaign == null:
		push_warning("OpsTable '%s': no CampaignManager in the scene, so there is nothing to task. The table will stand there dark." % name)
	if board == null:
		board = _Board.new()
		add_child(board)
	_wire_interactible()
	if Campaign != null:
		# Everything that can change what a site is or whether it can be taken.
		Campaign.mission_selected.connect(func(_m): refresh())
		Campaign.returned_to_base.connect(refresh)
		Campaign.state_loaded.connect(refresh)
		Campaign.extracted.connect(func(_m, _r): refresh())
	refresh.call_deferred()


func _wire_interactible() -> void:
	if interactible == null:
		interactible = _find_interactible(self)
	if interactible == null:
		push_warning("OpsTable '%s' has no Interactible child, so it cannot be used. Add an instance of template_interactible.tscn under it." % name)
		return
	# ─────────────────────────────────────────────
	# THE TEMPLATE'S DEFAULTS ARE ALL WRONG FOR A TABLE, and the third one is
	# invisible until you stand in front of it in a real game.
	#
	# template_interactible.tscn sets NO collision_layer, so it is Godot's
	# default 1. The player's InteractRaycast is mask 2. Layer 1 and mask 2
	# never meet: the ray goes straight through the table and no prompt ever
	# appears. The mission terminal works because its scene writes
	# collision_layer = 3 — bits 1 AND 2 — and nothing says so anywhere.
	#
	# This was missed by a probe that called _on_interacted() directly: that
	# proves the handler works, which was never the thing in doubt. The
	# raycast is the thing in doubt, and only standing at the table tests it.
	# ─────────────────────────────────────────────
	interactible.collision_layer = 3
	# A table you can only use once is not a table — the same reason the
	# mission terminal clears these two.
	interactible.destroy_on_use = false
	interactible.disable_on_use = false
	# MISSION, so the HUD asks THIS node (the Interactible's parent) for the
	# prompt. See Hud.activate_interactible.
	interactible.type = Enums.InteractTypes.MISSION
	interactible.interacted.connect(_on_interacted)


## What the F prompt says. The HUD prefixes "F | ".
func get_prompt() -> String:
	if Campaign == null:
		return "Operations Table"
	var m = Campaign.selected_mission()
	if m == null:
		return "Operations Table"
	return "Operations Table — %s queued" % m.display_name


## F at the table takes you into the zoomed view.
##
## THE VIEW IS BUILT ON FIRST USE, not at _ready, and hung off the HUD rather
## than off this node. It has to be a sibling of the other HUD controls for
## two reasons: it hides them while it is open and puts them back after, and
## a Control parented to a Node3D in the level is not on the HUD's canvas at
## all. The debrief screen is created the same way, for the same reason.
func _on_interacted(_source) -> void:
	refresh()
	var ui = _zoom_view()
	if ui == null:
		push_warning("OpsTable: no HUD to open the zoomed view in, so F does nothing but refresh the projection.")
		return
	ui.open(self)


func _zoom_view():
	if _zoom != null and is_instance_valid(_zoom):
		return _zoom
	var hud := _find_hud()
	if hud == null:
		return null
	_zoom = _ZoomView.new()
	_zoom.name = "OpsTableUI"
	hud.add_child(_zoom)
	return _zoom


## The HUD is whatever node owns the rest of the screen furniture. Found the
## same way the contact marks find it — by the methods it has rather than by
## a path, because this node is instanced into a level and has no route to it.
func _find_hud() -> Node:
	for n in get_tree().get_nodes_in_group(&"hud"):
		return n
	var root := get_tree().get_root()
	return _hud_under(root)


func _hud_under(n: Node) -> Node:
	if n.has_method("set_signal") and n.has_method("register_hit"):
		return n
	for c in n.get_children():
		var f := _hud_under(c)
		if f != null:
			return f
	return null


# ─────────────────────────────────────────────
# THE READOUT
#
# What a site is worth, floating over the site. In the world rather than on
# the HUD, because the projection is supposed to answer you — a table that
# only reacts on a separate screen is a table with a monitor next to it.
#
# WHAT IT SAYS IS WHAT HOME COMMAND BELIEVES. The resistance figure is a sync
# that never happened; the per-turn yields are what the site paid when
# somebody last counted. None of it is hedged on screen, because the
# institution is not hedging. See the brief.
# ─────────────────────────────────────────────

## Height above a site's icon that the readout floats.
@export var readout_lift: float = 0.22
## Label3D pixel size. 0.0032 was the first guess and the readout filled the
## screen; 0.00055 overcorrected into an unreadable smudge. 0.0013 is the
## size at which a six-line panel sits over one site without covering its
## neighbours.
## Sized so each of the five lines lands near fourteen pixels on screen from
## standing distance. Below about ten the outline closes the counters up and
## the whole block reads as a smudge — which it did, twice, at 0.0008 and at
## 0.0011. Width is not the constraint here: the strip sits in the board's
## empty near margin and has room.
@export var readout_size: float = 0.0032

var _readout: Label3D = null
## One per gauge channel. See _show_figures.
var _figures: Array = []
## Matched to the readout strip. Smaller than this and the outline closes
## the counters — the third time that has bitten on this board, so: a figure
## on a dark ground wants about fourteen screen pixels and an outline of two.
@export var figure_size: float = 0.0030

## Compute, resources, resistance — the three bars, in the colours the HUD
## already uses for those currencies everywhere else.
const GAUGE_TINTS := [_Pal.SIGNAL, _Pal.WARN, _Pal.CRIT]


## Light one site on the projection WITHOUT the world-space strip.
##
## What the zoomed view wants: in there the panel is ordinary screen-space
## UI with room to breathe, so the strip and the little coloured figures are
## the same facts said twice, in the harder-to-read place.
func highlight(id) -> void:
	if _hovered != null and _hovered != id and facts.has(_hovered) and board != null:
		board.set_site(_hovered, _tint_for(facts[_hovered]), 1.0)
	_hovered = id
	if board == null:
		return
	if id == null or not facts.has(id):
		board.light_gauges(null, [], GAUGE_TINTS)
		return
	var f: Dictionary = facts[id]
	board.set_site(id, _Pal.HELD if f["cleared"] else _Pal.BRIGHT, 2.4)
	board.light_gauges(id, f.get("gauges", []), GAUGE_TINTS)


## Hide the world-space strip and its figures. Called when the zoomed view
## takes over the job of saying what a site is worth.
func hide_strip() -> void:
	if _readout != null:
		_readout.visible = false
	_hide_figures()


## Show the detail for one site, or clear it with null.
##
## ─────────────────────────────────────────────
## THE DETAIL DOES NOT GO OVER THE BOARD.
##
## It did, floating above the hovered site, and it could not be made to work
## at any size. The sites are about ten centimetres apart on a metre of
## board; text large enough to read standing at the table is wider than that
## gap, so a panel over one site always covers its neighbours. Tuning the
## font just picks which failure you get — too big and it swallows the map,
## too small and it is an unreadable smudge. Both were tried.
##
## So it moved to the TABLE'S NEAR EDGE and became a strip: one fixed place,
## in front of the board rather than on it, angled up at whoever is standing
## there. Three things fall out of that for free. It can be physically larger
## because it is no longer competing with the spacing of the sites. It is
## nearer the camera than the board is, so it reads bigger still for the same
## world size. And it never moves, so the eye learns one place to look
## instead of hunting for a panel that follows the cursor.
##
## The board's own response to hovering is the SITE LIGHTING UP, which is
## what the projection responding to you should look like anyway — the strip
## is the instrument, the board is the map.
## ─────────────────────────────────────────────
func show_readout(id) -> void:
	# Put the previously hovered site back to its own colour.
	if _hovered != null and _hovered != id and facts.has(_hovered) and board != null:
		board.set_site(_hovered, _tint_for(facts[_hovered]), 1.0)
	if id == null or not facts.has(id):
		if _readout != null:
			_readout.visible = false
		_hide_figures()
		if board != null:
			board.light_gauges(null, [], GAUGE_TINTS)
		_hovered = null
		return
	_hovered = id
	var f: Dictionary = facts[id]
	if _readout == null:
		_readout = Label3D.new()
		_readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Unshaded and drawn over the projection: a readout the hologram can
		# occlude is a readout you have to walk around the table to read.
		_readout.shaded = false
		_readout.no_depth_test = true
		_readout.pixel_size = readout_size
		_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_readout.modulate = _Pal.SIGNAL
		_readout.outline_modulate = Color(0.0, 0.05, 0.04, 0.85)
		# SMALL OUTLINE. At this pixel size a heavy one closes up the counters
		# and the panel reads as a dark block — the same trap the contact
		# marks' age tag fell into.
		_readout.outline_size = 3
		add_child(_readout)
	_readout.text = _readout_text(f)
	_readout.visible = true
	_readout.position = _strip_anchor()
	# The site answers, and so do its three bars: they are always on the
	# board at rest, and hovering lights them and puts figures beside them.
	if board != null:
		board.set_site(id, _tint_for(f), 2.4)
		board.light_gauges(id, f.get("gauges", []), GAUGE_TINTS)
	_show_figures(id, f)


## The three figures, in the strip, each in its channel's colour.
##
## NOT ONE PER BAR, which is what the mockup drew and what the geometry
## refuses. The bars are 22 mm apart on the board; a figure legible from
## standing height is about 77 mm tall. Three of them stacked at that spacing
## sit on top of each other — measured, not guessed. Putting a readable
## number against each bar would mean spreading the bars four times further
## apart, and the gauge block would then be taller than the landmark it
## belongs to.
##
## So the bars stay tight at the site, where their job is the at-a-glance
## SHAPE, and the figures go in the strip where there is room to space them.
## Colour is what ties the two together: the cyan number is the cyan bar.
##
## Three separate Label3Ds rather than one block, because one Label3D takes
## one modulate and the whole point is that each line is its own colour.
## Made once and moved — a hover is a mouse-over, and this would otherwise
## allocate three nodes on every frame the cursor crosses a site.
func _show_figures(_id, f: Dictionary) -> void:
	# NOTHING TO GAUGE. The arena has no yield, no compute and no garrison, so
	# three empty bars under it say only that somebody forgot to hide them.
	if bool(f.get("sim_site", false)):
		_hide_figures()
		return
	var rows := [
		# Compute is a flat figure, not a yield per turn — see the note in
		# ops_table_ui._refresh_panel. Resources still are per turn.
		["CPU ", int(f["compute"])],
		["RES ", int(f.get("per_resources", 0))],
		["RSST", int(f["resistance"])],
	]
	var anchor := _strip_anchor()
	for ch in 3:
		if _figures.size() <= ch:
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.shaded = false
			l.no_depth_test = true
			l.pixel_size = figure_size
			l.outline_size = 2
			l.outline_modulate = Color(0.0, 0.05, 0.04, 0.85)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.modulate = GAUGE_TINTS[ch]
			add_child(l)
			_figures.append(l)
		var lab: Label3D = _figures[ch]
		lab.text = "%s %d" % [rows[ch][0], rows[ch][1]]
		lab.visible = true
		# Below the name and state, one line each, spaced by the label's own
		# height rather than by the bars'.
		# BESIDE THE STRIP, not under it. Under it overlapped the third line,
		# and pushed far enough down to clear that, the figures ran off the
		# near edge of the board altogether. The margin has depth for one
		# block of text and width for two, so the figures take the width.
		lab.position = anchor + Vector3(0.90, 0.0, float(ch) * 0.105)


func _hide_figures() -> void:
	for l in _figures:
		if is_instance_valid(l):
			l.visible = false


## Where the strip sits: ON the plate, in its near margin.
##
## Not off the front edge, which was the first attempt and put it directly
## under the player every time — at a table you are standing AT, anything
## past the near edge is below the bottom of the screen.
##
## There is room for it because the sites do not use the depth. The campaign
## runs left to right, so the authored layout spans about eleven times as far
## in X as in Z: normalised to the plate, every site sits within a tenth of a
## metre of the centre line and the whole near half of the board is empty.
## The strip lives in that.
func _strip_anchor() -> Vector3:
	var half: float = 0.62 * (board.board_size if board != null and "board_size" in board else 1.1)
	return Vector3(-half * 0.34, 0.05, half * 0.46)


## RES/TURN AND COMPUTE/TURN, not the one-off reward.
##
## reward_resources and compute_reward are what clearing an op pays once. The
## brief's later campaign has sites YIELDING per turn, and the board is meant
## to be shaped for that now rather than rebuilt for it later — so the figures
## are labelled as the per-turn yields they are about to become, and derived
## from the one-off until the territory layer exists to supply the real thing.
## WHAT IS LEFT AFTER THE GAUGES TOOK THE NUMBERS.
##
## Compute, resources and resistance are bars at the site now, so the strip
## carries only what a bar cannot say: which site, whose it is, and the name
## of the prerequisite you are missing. Three short lines.
##
## THE NAME STAYS ON THE STRIP rather than under the icon as the mockup drew
## it. A name is the one long string in this readout, and a long string at a
## site covers its neighbours — the problem the strip exists to solve. The
## numbers were the part that genuinely wanted to be at the site, and those
## are the bars.
##
## NARROW BEATS SHORT. The first version was written as a table — label,
## spaces, value, unit, parenthetical — and the longest line was "RESERVE
## 30 MORE ON CALL" at twenty-four characters. On a board, WIDTH is the
## expensive dimension: a wide panel reaches across sites, a tall one only
## reaches down into empty air in front of the table.
##
## So it is five short lines, nothing over fourteen characters, and the prose
## is gone. "/T" rather than "per turn"; "+30" rather than "30 more on call";
## the unmet prerequisite named and nothing else. This is a machine telling
## another machine, which is also what it is.
func _readout_text(f: Dictionary) -> String:
	# THE ARENA IS NOT A SIDE'S GROUND. Without this it fell through to the
	# else below and read "ADVERSARY HELD" — the training facility, held by
	# the enemy. See the same fix on the zoomed card in ops_table_ui.
	if bool(f.get("sim_site", false)):
		return "%s\n%s" % [String(f["name"]).to_upper(),
			"START HERE" if bool(f.get("training_next", false)) else "TRAINING"]
	var lines: Array = [String(f["name"]).to_upper()]
	# THE MOST URGENT TRUE THING, in that order. A site waiting on an answer is
	# the only line here with a clock on it.
	if f.get("under_attack", false):
		lines.append("UNDER ATTACK")
		lines.append("DEFEND IT")
	elif f.get("held", false):
		lines.append("HELD x%d" % int(f["clears"]))
	elif f["locked"]:
		lines.append("LOCKED %s" % String(f["unmet"][0]).to_upper().left(10) if not f["unmet"].is_empty() else "LOCKED")
	else:
		lines.append("ADVERSARY HELD")
	if int(f["reserve"]) > 0:
		lines.append("+%d RESERVE" % int(f["reserve"]))
	return "\n".join(lines)



# ─────────────────────────────────────────────
# READING THE CAMPAIGN
# ─────────────────────────────────────────────

## Rebuild the projection and the facts behind it.
func refresh() -> void:
	if Campaign == null or board == null:
		return
	facts.clear()
	# The board draws SITES, not free actions — see _board_missions.
	var missions: Array = _board_missions()
	if missions.is_empty():
		push_warning("OpsTable: CampaignManager has no missions, so the board has no sites.")
		board.build([], [])
		return

	var place := _layout(missions)
	var nodes: Array = []
	for m in missions:
		var f := _facts_for(m)
		facts[m.id] = f
		nodes.append({"id": m.id, "at": place[m.id], "tint": _tint_for(f),
			"icon": ICONS.get(_site_key(m), _Icons.Kind.MARKER),
			"scale": _icon_scale(_site_key(m)) * (1.3 if _takeable(f) else 1.0)})


	# ── THE SIM ARENA, AS ONE ENTRY ─────────────────────────────────────
	#
	# The two exercises live INSIDE the arena, not beside the war as two more
	# sites. A free action must not look like a costly one, and "SIM ARENA" is
	# a place you go rather than an operation you pick — selecting it opens the
	# arena screen instead of queueing a destination.
	#
	# Synthetic: there is no Location and no mission behind this pin, which is
	# why it carries its own minimal facts rather than going through
	# _facts_for. Everything downstream reads facts by id and does not care.
	if _has_training():
		var waiting: bool = not _training_done()
		facts[SIM_SITE] = {
			"id": SIM_SITE, "name": "SIM ARENA", "clears": 0, "cleared": false,
			"locked": false, "unmet": [], "deployable": false, "sim_site": true,
			"compute": 0, "resources": 0, "resistance": 0, "held": false,
			"under_attack": false, "per_resources": 0, "per_compute": 0,
			"bodies": 0, "reserve": 0, "defend_id": &"", "needs_training": false,
			# THE ONLY THING YOU CAN DO YET, and the board should say so without
			# a word. _takeable already draws somewhere-you-could-go larger; a
			# fresh campaign has nowhere else, so while the exercises are
			# unfinished this is the one enlarged pin on the table.
			"training_next": waiting,
		}
		nodes.append({"id": SIM_SITE, "at": SIM_PLACE, "tint": _Pal.SIGNAL,
			"icon": _Icons.Kind.MARKER, "scale": 1.6 if waiting else 1.0})

	# WORKED OUT FROM THE BOARD, not hard-coded. A fixed ceiling per channel
	# is a number that goes stale the first time somebody adds a mission, and
	# silently: every bar just gets shorter and nobody notices the scale is
	# wrong. Taking the largest site on the board as full means the longest
	# bar is always the biggest thing there, which is the only claim these
	# bars actually make.
	var top := {"compute": 1, "resources": 1, "resistance": 1}
	for id in facts:
		for k in top:
			top[k] = maxi(int(top[k]), int(facts[id][k]))
	for n in nodes:
		var f: Dictionary = facts[n["id"]]
		n["gauges"] = [
			float(f["compute"]) / float(top["compute"]),
			float(f["resources"]) / float(top["resources"]),
			float(f["resistance"]) / float(top["resistance"]),
		]
		facts[n["id"]]["gauges"] = n["gauges"]
		# per_resources and per_compute now come straight off the Location in
		# _facts_for, so there is nothing to cache here any more.


	board.gauge_tints = GAUGE_TINTS
	board.build(nodes, _edges(missions))
	# AFTER build, not before. build() clears the board, which takes the ring
	# with it — and at that point the site positions it rings do not exist
	# yet either, so it silently drew nothing twice over. refresh() runs on
	# mission_selected, so this is also what puts the ring up the moment you
	# queue something.
	var queued = Campaign.selected_mission()
	board.set_queued(_pin_for(queued.id) if queued != null else null)


## Everything the board and the readout need to know about one site.
func _facts_for(m) -> Dictionary:
	var state = Campaign.state
	var clears: int = state.clears_of(m.id) if state != null else 0
	var unmet: Array = []
	for req in m.requires:
		if state != null and not state.completed_missions.has(req):
			var r = Campaign.get_mission(req)
			unmet.append(r.display_name if r != null else String(req))
	var force := _force(m)
	# THE REAL PER-TURN FIGURE, off the Location (§2).
	#
	# This used to be _per_turn(one_off) — literally `reward_resources × 0.1`,
	# a placeholder standing in for a territory layer that did not exist. The
	# board has been printing "RES n /turn" for income the game never paid.
	# Now the location says what it pays, and if there is no location the
	# answer is 0 rather than a flattering invention.
	var site = state.locations.for_mission(m.id) if state != null and state.locations != null else null
	var per_res: int = int(site.resources_per_turn) if site != null else 0
	var site_cpu: int = int(site.compute) if site != null else 0
	# RESISTANCE OFF THE LOCATION WHERE THERE IS ONE. The measured figure
	# includes the RESERVE, which _force() leaves out on purpose — but reserve
	# is exactly what SiteHeat spends, so the total is the honest number for
	# "how hard is this place". Falls back to the on-map supply.
	var resist: int = int(site.resistance) if site != null else int(force["supply"])
	return {
		"id": m.id,
		"name": m.display_name,
		"clears": clears,
		"cleared": clears > 0,
		# LOCKED MEANS "YOU CANNOT GO THERE", not "its prerequisite is unrun".
		#
		# Those came apart the moment the DEBUG switch existed: UNLOCK ALL
		# MISSIONS makes a mission deployable, but this used to read `requires`
		# directly and never asked the switch — so the board drew a site grey
		# and locked while cheerfully letting you deploy to it. `unmet` below
		# still carries WHICH operation is missing, for the readout that
		# explains it; this is only about whether the route is shut.
		"locked": not Campaign.available_missions().has(m),
		"deployable": Campaign.available_missions().has(m) and _training_done(),
		"compute": m.compute_reward,
		"resources": m.reward_resources,
		"resistance": resist,
		# DO YOU HOLD IT RIGHT NOW. Not "did you ever clear it" — see _tint_for.
		# Falls back to `cleared` for an operation with no Location, which is the
		# three Sim Arenas: they are a practice track and not on the board (§15).
		"held": state.holds(site.id) if (state != null and site != null) else (clears > 0),
		# UNDER ATTACK AND WAITING ON AN ANSWER (Phase 6.2). A raid too close to
		# call does not take the site — it offers you the fight, and this is what
		# marks it on the board until you answer or walk away.
		"under_attack": state != null and site != null and state.under_attack == site.id,
		# What HOLDING it pays, and the compute it carries — both the location's,
		# both 0 for an operation that is not a place (the Sim Arenas).
		"per_resources": per_res,
		"per_compute": site_cpu,
		# THE DEFENCE OF THIS PLACE, if one is waiting. The board draws one pin
		# per site now, so the defence has no pin of its own and is offered
		# from this one — see _board_missions and ONE_PIN_PER_SITE.md. Empty
		# unless a raid is actually in doubt here, because a defence that could
		# be picked at will would make losing ground impossible (§6.2).
		"defend_id": _defence_waiting(site),
		# THE WAR IS SHUT UNTIL THE TRAINING IS DONE. Not a route problem, so
		# it does not set `locked` and does not change the colour of anything:
		# it means "not yet", and the panel says so in those words.
		"needs_training": not _training_done(),
		"bodies": force["on_map"],
		"reserve": force["reserve"],
	}


## What the garrison would cost at the player's own supply prices.
##
## body_count(), never roster.size() inline. One body per roster entry, asked
## in one place. The field it used to warn about — a legacy `count` that every
## shipped spec carried as a stale 3 while its roster said otherwise — was
## removed by H9 on 2026-10-24; the habit of asking body_count() is what kept
## this figure right while both forms existed, so keep asking it.
##
## RESERVE IS COUNTED SEPARATELY. The spawner holds those back and only builds
## them when something calls them in, so folding them into the headline figure
## would overstate what the player actually walks into.
func _force(m) -> Dictionary:
	var on_map := 0
	var reserve := 0
	var supply := 0
	for spec in m.enemy_force:
		if spec == null:
			continue
		var bodies: int = spec.body_count()
		if spec.posture == EnemySquadSpec.Posture.RESERVE:
			reserve += bodies
		else:
			on_map += bodies
			for c in spec.roster:
				if c != null:
					supply += c.supply
	return {"on_map": on_map, "reserve": reserve, "supply": supply}


## Who holds it, in colour.
##
## OWNERSHIP FIRST, AND THAT ORDER IS THE FIX. This used to test `locked`
## before anything else and return grey — so a site you had TAKEN still drew as
## unreachable whenever its prerequisite operation had not been run. After a
## save wipe that is every site you jump straight to: beat Valley Basin as many
## times as you like and the marker stays grey, because Hillfort is what
## unlocks it and Hillfort was never played. Reported from a playtest.
##
## AND IT TINTS FROM OWNERSHIP, NOT FROM "EVER CLEARED". Clearing is a thing
## you did once; holding is a thing that is true now, and §2 is the whole
## argument for why those are different. A site you took in Act 1 and lost in
## Act 2 should go back to their amber, and `cleared` can never say that.
##
## NOT FAC_HOME FOR "YOURS", despite that being Home Command's own colour.
## FAC_HOME is an institutional olive — right for paint on a crate, wrong as a
## marker: additively blended and two centimetres across it comes out gold, a
## few degrees of hue from the Swarm's amber. Photographed, a cleared site and
## a contested one were the same marker. So the board borrows the HUD's own
## vocabulary, which the player has already learnt everywhere else.
func _tint_for(f: Dictionary) -> Color:
	# UNDER ATTACK OUTRANKS EVERYTHING, including held. A site waiting on an
	# answer is the only thing on the board with a clock on it, and a player
	# who misses it loses ground — so it must not read as "yours, fine".
	if f.get("under_attack", false):
		return _Pal.CRIT
	if f.get("held", false):
		return _Pal.HELD
	if f["locked"]:
		return _Pal.GONE
	return _Pal.FAC_ADVERSARY

## THE ROUTES, OFF THE LOCATIONS — the same graph the game plays against.
##
## This used to draw a hand-authored ADJACENCY table keyed by mission id. That
## table was right to exist when there was nothing else, and its own comment is
## right that `requires` is an unlock order rather than geography — but a
## measured `Location.connects_to` now exists, reciprocal and asserted by a
## suite, and EnemyTurn.frontier() decides what can be attacked from IT.
##
## Two graphs, and they disagreed. ADJACENCY bordered Coast Road with Qamareen;
## connects_to borders Qamareen with Valley Basin and Three Rivers and not with
## Coast Road at all. So the board drew the player one map and the frontier rule
## played another — the dotted line you were reading was not the line the enemy
## was moving along.
##
## Keyed to the MISSION ids the markers use, because a pin is still drawn per
## operation; the lookup goes through the catalogue so neither end has to know
## the other's naming.
func _edges(missions: Array) -> Array:
	var state = Campaign.state if Campaign != null else null
	var cat = state.locations if state != null else null
	if cat == null:
		push_warning("OpsTable: no location catalogue, so no routes can be drawn between sites.")
		return []
	# Location id -> the mission id drawn for it.
	var pin := {}
	for m in missions:
		var l = cat.for_mission(m.id)
		if l != null and not pin.has(l.id):
			pin[l.id] = m.id
	var out: Array = []
	var seen := {}
	for lid in pin:
		var l = cat.of(lid)
		if l == null or not ("connects_to" in l):
			continue
		for other in l.connects_to:
			if not pin.has(other):
				# A border to somewhere with no marker on this board. Not an
				# error — the later acts add sites — but silence here would hide
				# a typo in a location's connects_to forever.
				print("[OpsTable] '%s' borders '%s', which has no marker on this board." % [
					String(lid), String(other)])
				continue
			# UNDIRECTED: listed on both sides, drawn once.
			var key: String = "%s|%s" % [String(mini_id(lid, other)), String(maxi_id(lid, other))]
			if seen.has(key):
				continue
			seen[key] = true
			out.append([pin[lid], pin[other]])
	return out


## The two ends of a border in a fixed order, so an undirected pair has one key.
static func mini_id(a: StringName, b: StringName) -> StringName:
	return a if String(a) <= String(b) else b


static func maxi_id(a: StringName, b: StringName) -> StringName:
	return b if String(a) <= String(b) else a


# ─────────────────────────────────────────────
# LAYOUT
#
# NOT FROM map_position, which cannot be used as authored: the four late-game
# missions are all at (0,0) and one is in normalised 0-1 space while the rest
# are in hundreds. Four sites stacked on the origin is not a board.
#
# So the board is laid out from the requires DAG instead, which IS good data —
# a real chain runs arena -> hillfort -> basin -> coast -> pitt -> mutaha ->
# georgetown -> polaris -> causeway. Depth gives the order; the order is then
# wrapped into rows so eleven sites read as a theatre rather than as a queue.
#
# This is explicitly a v1. When the layout pass happens and map_position means
# something, this function is the only thing that has to change.
# ─────────────────────────────────────────────
## WHICH LANDMARK STANDS FOR EACH SITE.
##
## The board's whole claim is that you recognise a place by its silhouette
## rather than by reading a name off it, so these are the thing a player would
## point at: the relay on the hill, the anchor in the basin, the wheel over
## Qamareen, the lock at Lockside. A site with no entry falls back to a plain
## diamond, which is honest — it says "a place" and claims nothing about it.
##
## See Env/world_objects/site_icons.gd for the drawings.
## KEYED BY LOCATION ID, because that is what _site_key() hands the lookup.
##
## IT WAS KEYED BY MISSION ID AND EVERY SITE MISSED. _site_key resolves a
## mission to its Location and returns the LOCATION's id — so
## `ICONS.get(_site_key(m))` was asking a mission-keyed table for
## "valley_basin" and getting nothing, every time, for every site that had a
## Location. The default is MARKER, a plain diamond, so the board drew ten
## identical diamonds at one size and looked merely plain rather than broken.
## Reported from play as "all the icons are wrong".
##
## The same miss hit HEIGHTS through _icon_scale, which is why they were all
## the same size as well: an unknown height falls back to 40 m.
##
## docs/briefs/archive/ONE_PIN_PER_SITE.md called this re-key out as outstanding and it
## is the thing it was waiting for. A site has one icon; what you DO there does
## not change what the place looks like, so the attack and the defence of one
## site share a row rather than needing two.
##
## THE SIM ARENAS STAY MISSION-KEYED. They deliberately have no Location (§15 —
## a practice track, off the adjacency graph), so _site_key falls back to the
## mission id for them and finds these.
const ICONS := {
	&"arena_3_firing_line": _Icons.Kind.DERRICK,
	&"arena_5_proving":     _Icons.Kind.DERRICK,
	&"hillfort_wip":        _Icons.Kind.RELAY,
	&"valley_basin":        _Icons.Kind.ANCHOR,
	&"coast_road":          _Icons.Kind.BRIDGE,
	&"three_rivers":        _Icons.Kind.FURNACE,
	&"qamareen":            _Icons.Kind.WHEEL,
	&"lockside":            _Icons.Kind.STACK,
	&"polaris":             _Icons.Kind.MALL,
	&"causeway":            _Icons.Kind.TOWER,
	&"over_the_top":        _Icons.Kind.CLOCKTOWER,
	# The retired original, kept so that un-retiring it needs no edit here.
	&"hillfort":            _Icons.Kind.RELAY,
}


## HOW TALL EACH LANDMARK REALLY IS, in metres, measured off its own .map.
##
## The spread is enormous — the Coast Road bridge deck is 4 m and the
## Causeway tower is 408 — and neither obvious answer works. Draw them all
## the same size and the board lies about the places; draw them to true
## scale and the bridge is a hundredth of the tower and invisible.
##
## So the board scales them LOGARITHMICALLY, which keeps the order honest
## (the tower is plainly the biggest thing on the table, the bridge plainly
## the smallest) while keeping the smallest one legible. See _icon_scale.
## KEYED BY LOCATION ID, for the same reason as ICONS above — _icon_scale is
## called with _site_key(), so a mission-keyed table missed on every site and
## every landmark fell back to 40 m. That is why they were all one size.
const HEIGHTS := {
	&"arena_3_firing_line": 16.0,
	&"arena_5_proving": 16.0,
	&"hillfort_wip": 62.0, &"hillfort": 63.0,
	&"valley_basin": 240.0, &"coast_road": 4.5,
	&"three_rivers": 44.0, &"qamareen": 48.0,
	&"lockside": 44.0, &"polaris": 15.0,
	&"causeway": 408.0, &"over_the_top": 51.5,
}


## Log-scaled icon size, 0.62 for the shortest landmark up to 1.0 for the
## tallest. Unknown heights sit in the middle rather than at either end.


## THE SITE A MISSION IS FOUGHT OVER, as an id — the key the board's three
## authored tables use.
##
## LAYOUT, ICONS and HEIGHTS are facts about a PLACE: where it sits on the
## board, what landmark stands for it, how tall that landmark is. They were
## keyed by mission id, which meant the defence of Valley Basin needed its own
## entry in all three saying the same thing as the attack's — and got the
## attack's coordinates copied in as a stopgap, which is how two pins came to be
## drawn on one spot.
##
## Falls back to the mission id so the sim arenas, which have no Location by
## design, still find their own entries.
func _site_key(m) -> StringName:
	var state = Campaign.state if Campaign != null else null
	var cat = state.locations if state != null else null
	if cat == null:
		return m.id
	var l = cat.for_mission(m.id)
	return l.id if l != null else m.id
static func _icon_scale(id) -> float:
	var h: float = float(HEIGHTS.get(id, 40.0))
	return 0.62 + 0.38 * clampf(log(maxf(h, 2.0)) / log(408.0), 0.0, 1.0)


## WHERE EACH SITE SITS, authored by hand, left to right along the campaign.
##
## NOT IN THE .tres FILES, and that is a deliberate and temporary choice. The
## right home for these is MissionDefinition.map_position — that is what the
## field is for — but git shows another lane mid-edit across Campaign/missions,
## and twelve resource files is a bad place to collide. tools/set_map_positions.gd
## pushes this table into them in one pass when the lanes are quiet.
##
## The shape: three sim arenas stepping down on the far left, because they are
## a training rig and not ground anybody holds; then the real theatre running
## east with the line rising and falling so it reads as places rather than as
## a progress bar. Over The Top sits off on its own at the bottom — it is
## repeatable and needs nothing, so it is a standing job rather than a step.
## HILLFORT IS THE WEST END and the map opens out from it: two routes east,
## reconverging on the river, a choice of approach through the middle, and
## one way into the Causeway at the far end.
##
## THE SIM ARENAS ARE NOT ON THE MAP. They sit in their own row underneath
## it, detached, because they are not ground — they are a training rig, and a
## territory board that lets you "hold" a simulator is lying about what the
## campaign is. They are still sites you can select; they are just not places
## anyone borders.
const LAYOUT := {
	# ── the theatre ─────────────────────────────
	# THE OPENING SITE. This is Hillfort — the rebuilt one, a quarter of the
	# ground with six capture points instead of two. hillfort_1_relay was
	# swapped out for it on 2026-10-15 and its board rows went with it; the
	# old mission and level are still on disk, just not in the campaign.
	&"hfw_1_fort":           Vector2(0.0, 0.0),
	&"basin_1_anchor":       Vector2(175.0, -80.0),
	# THE DEFENCE OF THE SAME GROUND sits where the attack does, because it IS
	# the same place. Two pins on one spot is not right either — the board
	# should draw one marker per SITE with its available operations on it, and
	# that belongs with the Phase 6 board work rather than here.
	&"basin_2_defend":       Vector2(175.0, -80.0),
	&"salient_1_overthetop": Vector2(175.0, 85.0),
	&"coast_1_road":         Vector2(340.0, -130.0),
	&"pitt_1_rivers":        Vector2(345.0, 25.0),
	&"mutaha_2_city":        Vector2(515.0, -90.0),
	&"georgetown_1_ascent":  Vector2(520.0, 70.0),
	&"polaris_1_siege":      Vector2(680.0, -15.0),
	&"causeway_1_tower":     Vector2(845.0, -15.0),
	# ── the rig, off the map ────────────────────
	&"arena_3_firing_line":  Vector2(0.0, 250.0),
	&"arena_5_proving":      Vector2(120.0, 250.0),
}




## Authored positions where we have them, DAG serpentine where we do not.
##
## The fallback is not dead code: a mission added tomorrow has no entry here
## and must still land somewhere sensible rather than on the origin with
## everything else that was never placed.
func _layout(missions: Array) -> Dictionary:
	var placed := {}
	var unplaced: Array = []
	for m in missions:
		if LAYOUT.has(m.id):
			placed[m.id] = LAYOUT[m.id]
		else:
			unplaced.append(m)
	if unplaced.is_empty():
		return placed
	push_warning("OpsTable: %d mission(s) have no authored board position and were laid out from the requires chain instead: %s"
		% [unplaced.size(), str(unplaced.map(func(m): return String(m.id)))])
	var fallback := _serpentine(unplaced)
	# Below the authored rows, so a stray site is visibly not part of the line.
	for id in fallback:
		placed[id] = fallback[id] + Vector2(0.0, 280.0)
	return placed


func _serpentine(missions: Array) -> Dictionary:
	var depth := _depths(missions)
	var order: Array = missions.duplicate()
	order.sort_custom(func(a, b):
		var da: int = depth.get(a.id, 0)
		var db: int = depth.get(b.id, 0)
		if da != db:
			return da < db
		return String(a.id) < String(b.id))

	var out := {}
	var cols: int = maxi(columns, 1)
	for i in order.size():
		var row: int = i / cols
		var col: int = i % cols
		# Serpentine: odd rows run back the other way, so the chain stays
		# continuous instead of jumping the full width at every wrap.
		if row % 2 == 1:
			col = cols - 1 - col
		out[order[i].id] = Vector2(float(col) * spacing.x, float(row) * spacing.y)
	return out


## Longest path to each mission through `requires`. Depth 0 is a site you can
## start at. Memoised, and cycle-safe: a mission that (wrongly) requires
## itself through a loop resolves to its first-seen depth rather than hanging.
func _depths(missions: Array) -> Dictionary:
	var by_id := {}
	for m in missions:
		by_id[m.id] = m
	var depth := {}
	var walking := {}
	for m in missions:
		_depth_of(m.id, by_id, depth, walking)
	return depth


func _depth_of(id, by_id: Dictionary, depth: Dictionary, walking: Dictionary) -> int:
	if depth.has(id):
		return depth[id]
	if walking.has(id):
		push_warning("OpsTable: mission '%s' is in a requires loop. Treating it as a starting site." % String(id))
		return 0
	var m = by_id.get(id)
	if m == null:
		return 0
	walking[id] = true
	var d := 0
	for req in m.requires:
		if by_id.has(req):
			d = maxi(d, _depth_of(req, by_id, depth, walking) + 1)
	walking.erase(id)
	depth[id] = d
	return d


# ─────────────────────────────────────────────
# LOOKUPS
# ─────────────────────────────────────────────

## Same ladder the mission terminal walks: group, then autoload, then up the
## parents. A table nested one level deeper than expected should still find it.
func _find_campaign() -> Node:
	var c := get_tree().get_first_node_in_group(&"campaign")
	if c != null:
		return c
	c = get_node_or_null(^"/root/Campaign")
	if c != null:
		return c
	var n: Node = get_parent()
	while n != null:
		if n.get("Campaign") != null:
			return n.get("Campaign")
		n = n.get_parent()
	return null


func _find_interactible(node: Node):
	for child in node.get_children():
		if child is Interactible:
			return child
		var found = _find_interactible(child)
		if found != null:
			return found
	return null
## EVERY MISSION THE OPERATIONS TABLE SHOULD DRAW.
##
## THE EXERCISES ARE NOT ON IT. They live INSIDE the sim arena, which is one
## entry on this board rather than two more sites. A free action must not look
## like a costly one, and "SIM ARENA" is a place you go rather than a war you
## pick. The two exercises are listed when you get there — see SimArenaUI.

##
## The thing that is not on the board is the LAB: free-play matchups, which are
## a mode rather than a destination. See SimArenaUI.
## THE SITES, ONE ENTRY EACH — not one per operation.
##
## A site is a PLACE with two operations on it: take it, or hold it. LAYOUT is
## keyed by mission id and `basin_2_defend` was given the attack's coordinates,
## so the board drew two pins in exactly the same spot and the top one hid the
## bottom one. Reported from a screenshot as "valley basin has a duplicate
## location on top of it", which is what it looked like.
##
## The defence is not dropped — it is FOLDED ONTO the attack's pin, as
## `defend_id` in _facts_for, and offered there when the site is under attack.
## See docs/briefs/archive/ONE_PIN_PER_SITE.md: what you can do somewhere is a property
## of the place, not a reason to draw a second place.
##
## The sim arena is left out here too (`m.sim`) and added back by refresh() as
## one synthetic pin, for the same reason: two exercises, one door.
func _board_missions() -> Array:
	var out: Array = []
	for m in Campaign.missions:
		if m == null or m.sim or m.defence:
			continue
		out.append(m)
	return out


## THE SIM ARENA'S PIN. Not a mission id — there is no mission behind it.
const SIM_SITE := &"sim_arena"
## Off to one side of the war, because it is not part of it.
const SIM_PLACE := Vector2(-40.0, 150.0)


## Is there anything to train on? If both exercises are cleared the arena is
## still there — free play lives in it — so this asks whether it EXISTS, not
## whether it is unfinished.
func _has_training() -> bool:
	for m in Campaign.missions:
		if m != null and m.sim:
			return true
	return false


## SOMEWHERE YOU COULD GO RIGHT NOW — a site you do not hold, that is not
## already answering a raid, and that the ladder and the frontier both allow.
##
## Drawn slightly larger rather than in a colour of its own. The board already
## spends every colour it has: amber is theirs, blue is yours, grey is out of
## reach, red is under attack. A fifth tint would be a fifth thing to learn,
## and the question this answers — "where can I actually go" — is better asked
## by size, which reads before you have read anything.
func _takeable(f: Dictionary) -> bool:
	return bool(f.get("deployable", false)) \
		and not bool(f.get("held", false)) \
		and not bool(f.get("under_attack", false))


## The defence waiting on this site, or nothing. Asked of available_missions()
## rather than read off the Location, so the one rule about when a defence
## exists lives in one place: it is offered only while that raid is in doubt.
func _defence_waiting(site) -> StringName:
	if site == null or Campaign == null:
		return &""
	var want: StringName = site.defend_mission_id if "defend_mission_id" in site else &""
	if want == &"":
		return &""
	for m in Campaign.available_missions():
		if m != null and m.id == want:
			return want
	return &""


## HAS THE PLAYER FINISHED THE TWO EXERCISES? Until they have, the war is not
## offered at all and the arena is the only pin you can act on.
##
## The ladder already gates the first site behind the arenas through `requires`,
## but that is invisible until you point at something and read why it is shut,
## and the DEBUG switch opens it. This is the explicit version: it reads the
## clears, so it is the same answer however the mission list is arranged.
##
## ASKED OF THE SIM MISSIONS THEMSELVES, not a count. "The two exercises" is a
## fact about which missions are flagged `sim`, and a third would otherwise
## have to be remembered here as well as added.
func _training_done() -> bool:
	var state = Campaign.state if Campaign != null else null
	if state == null:
		# No state means no clears to read, and shutting the whole board on a
		# missing state would make the game unplayable rather than fail loudly.
		push_warning("OpsTable: no campaign state, so whether training is finished cannot be read. Treating it as finished.")
		return true
	for m in Campaign.missions:
		if m != null and m.sim and state.clears_of(m.id) <= 0:
			return false
	return true


## WHICH PIN STANDS FOR THIS OPERATION. Itself, for everything with a marker —
## but a defence has no marker of its own any more (see _board_missions), and
## HoloBoard.set_queued silently draws nothing for an id it has no point for.
## So queueing a defence put the ring nowhere and the player got no confirmation
## of what they had just chosen.
##
## THROUGH THE LOCATION, which is the whole reason the defence is reachable
## from the attack's card in the first place: both operations resolve to one
## place, and the place is what is drawn.
func _pin_for(id: StringName) -> StringName:
	if id == &"" or facts.has(id):
		return id
	var state = Campaign.state if Campaign != null else null
	if state == null or state.locations == null:
		push_warning("OpsTable: no location catalogue, so '%s' cannot be matched to a marker and the queued ring will not be drawn." % String(id))
		return id
	var site = state.locations.for_mission(id)
	if site == null:
		push_warning("OpsTable: '%s' belongs to no location, so there is no marker to put the queued ring on." % String(id))
		return id
	var owner: StringName = site.mission_id if "mission_id" in site else &""
	if owner == &"" or not facts.has(owner):
		push_warning("OpsTable: '%s' resolves to location '%s', which has no marker on this board." % [String(id), String(site.id)])
		return id
	return owner
