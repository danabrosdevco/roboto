extends Node3D

# ─────────────────────────────────────────────
# OPERATIONS TABLE — Home Command's tasking board, in the world.
#
# This is the layer that knows about the campaign. It reads the mission list,
# works out what each site is worth and who holds it, and hands plain data to
# HoloBoard, which draws it and knows nothing. See docs/briefs/OPERATIONS_TABLE.md.
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


func _on_interacted(_source) -> void:
	# The zoomed view is the next piece. Until it exists, pressing F refreshes
	# the projection rather than doing nothing silently.
	refresh()


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
@export var readout_lift: float = 0.105
## Label3D pixel size. 0.0032 was the first guess and the readout filled the
## screen; 0.00055 overcorrected into an unreadable smudge. 0.0013 is the
## size at which a six-line panel sits over one site without covering its
## neighbours.
## Sized so each of the five lines lands near fourteen pixels on screen from
## standing distance. Below about ten the outline closes the counters up and
## the whole block reads as a smudge — which it did, twice, at 0.0008 and at
## 0.0011. Width is not the constraint here: the strip sits in the board's
## empty near margin and has room.
@export var readout_size: float = 0.0022

var _readout: Label3D = null


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
	# And the site itself answers, which is the half of this the player
	# actually looks at.
	if board != null:
		board.set_site(id, _Pal.BRIGHT, 2.4)


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
	var lines: Array = [String(f["name"]).to_upper()]
	if f["locked"]:
		lines.append("LOCKED %s" % String(f["unmet"][0]).to_upper().left(10))
	elif f["cleared"]:
		lines.append("HELD x%d" % int(f["clears"]))
	else:
		lines.append("CONTESTED")
	lines.append("COMPUTE %4d/T" % _per_turn(int(f["compute"])))
	lines.append("RESRCE  %4d/T" % _per_turn(int(f["resources"])))
	var resist := "RESIST  %4d" % int(f["resistance"])
	if int(f["reserve"]) > 0:
		resist += "+%d" % int(f["reserve"])
	lines.append(resist)
	return "\n".join(lines)


## A site's standing yield, from what taking it pays once.
##
## A TENTH, FLOORED AT ONE. Entirely a placeholder, and deliberately a crude
## one: a site worth 2200 up front should not read as 2200 a turn, and the
## real number belongs to the territory layer that does not exist. Floored so
## that holding anything is always worth something.
func _per_turn(one_off: int) -> int:
	return maxi(1, int(round(float(one_off) * 0.1)))


# ─────────────────────────────────────────────
# READING THE CAMPAIGN
# ─────────────────────────────────────────────

## Rebuild the projection and the facts behind it.
func refresh() -> void:
	if Campaign == null or board == null:
		return
	facts.clear()
	var missions: Array = []
	for m in Campaign.missions:
		if m != null:
			missions.append(m)
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
			"icon": ICONS.get(m.id, _Icons.Kind.MARKER),
			"scale": _icon_scale(m.id)})
	board.build(nodes, _edges(missions))


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
	return {
		"id": m.id,
		"name": m.display_name,
		"clears": clears,
		"cleared": clears > 0,
		"locked": not unmet.is_empty(),
		"unmet": unmet,
		"deployable": Campaign.available_missions().has(m),
		"compute": m.compute_reward,
		"resources": m.reward_resources,
		"resistance": force["supply"],
		"bodies": force["on_map"],
		"reserve": force["reserve"],
	}


## What the garrison would cost at the player's own supply prices.
##
## body_count(), NEVER spec.count. A roster-form spec spawns one body per
## roster entry and ignores count — and every spec in the shipped missions is
## roster-form while still carrying a stale count of 3, so reading count
## directly is wrong on every single mission in the game.
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
## NOT FAC_HOME FOR "YOURS", despite that being Home Command's own colour.
## FAC_HOME is an institutional olive — it is the paint on their crates, and
## it is the right colour for a wall. As a marker on a dark board, additively
## blended and two centimetres across, it comes out gold and sits a few
## degrees of hue away from the Swarm's amber: photographed, a cleared site
## and a contested one were the same marker.
##
## So the board borrows the HUD's own vocabulary instead, which the player has
## already learnt everywhere else: BRIGHT green is yours and working, amber is
## the enemy's, GONE grey is a thing you cannot act on. Three colours nobody
## has to be taught, and no two of them adjacent.
func _tint_for(f: Dictionary) -> Color:
	if f["locked"]:
		return _Pal.GONE
	if f["cleared"]:
		return _Pal.BRIGHT
	return _Pal.FAC_SWARM


## The dotted routes: the authored borders, filtered to sites that are
## actually on this board.
##
## An edge naming a site the campaign does not have is dropped WITH A WARNING
## rather than quietly — a border to nowhere means ADJACENCY and the mission
## list have drifted apart, and that is worth hearing about the first time it
## happens rather than discovering as a gap in the map.
func _edges(missions: Array) -> Array:
	var known := {}
	for m in missions:
		known[m.id] = true
	var out: Array = []
	for pair in ADJACENCY:
		if known.has(pair[0]) and known.has(pair[1]):
			out.append([pair[0], pair[1]])
		else:
			var missing = pair[0] if not known.has(pair[0]) else pair[1]
			push_warning("OpsTable: ADJACENCY has a border to '%s', which is not in Campaign.missions. That route is not drawn." % String(missing))
	return out


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
const ICONS := {
	&"arena_1_contact":      _Icons.Kind.DERRICK,
	&"arena_3_firing_line":  _Icons.Kind.DERRICK,
	&"arena_5_proving":      _Icons.Kind.DERRICK,
	&"hillfort_1_relay":     _Icons.Kind.RELAY,
	&"basin_1_anchor":       _Icons.Kind.ANCHOR,
	&"coast_1_road":         _Icons.Kind.BRIDGE,
	&"pitt_1_rivers":        _Icons.Kind.FURNACE,
	&"mutaha_2_city":        _Icons.Kind.WHEEL,
	&"georgetown_1_ascent":  _Icons.Kind.STACK,
	&"polaris_1_siege":      _Icons.Kind.MALL,
	&"causeway_1_tower":     _Icons.Kind.TOWER,
	&"salient_1_overthetop": _Icons.Kind.CLOCKTOWER,
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
const HEIGHTS := {
	&"arena_1_contact": 16.0, &"arena_3_firing_line": 16.0,
	&"arena_5_proving": 16.0, &"hillfort_1_relay": 63.0,
	&"basin_1_anchor": 240.0, &"coast_1_road": 4.5,
	&"pitt_1_rivers": 44.0, &"mutaha_2_city": 48.0,
	&"georgetown_1_ascent": 44.0, &"polaris_1_siege": 15.0,
	&"causeway_1_tower": 408.0, &"salient_1_overthetop": 51.5,
}


## Log-scaled icon size, 0.62 for the shortest landmark up to 1.0 for the
## tallest. Unknown heights sit in the middle rather than at either end.
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
	&"hillfort_1_relay":     Vector2(0.0, 0.0),
	&"basin_1_anchor":       Vector2(175.0, -80.0),
	&"salient_1_overthetop": Vector2(175.0, 85.0),
	&"coast_1_road":         Vector2(340.0, -130.0),
	&"pitt_1_rivers":        Vector2(345.0, 25.0),
	&"mutaha_2_city":        Vector2(515.0, -90.0),
	&"georgetown_1_ascent":  Vector2(520.0, 70.0),
	&"polaris_1_siege":      Vector2(680.0, -15.0),
	&"causeway_1_tower":     Vector2(845.0, -15.0),
	# ── the rig, off the map ────────────────────
	&"arena_1_contact":      Vector2(0.0, 250.0),
	&"arena_3_firing_line":  Vector2(120.0, 250.0),
	&"arena_5_proving":      Vector2(240.0, 250.0),
}


## WHICH SITES BORDER WHICH — the geography, authored.
##
## NOT DERIVED FROM `requires`. That field is an unlock order: it says what
## you must have finished before an operation is offered, which is a property
## of the campaign's pacing and not of the ground. Drawing it as routes made
## the board claim that Qamareen borders Three Rivers because one follows the
## other in the mission list, which is not a statement anybody authored.
##
## Adjacency is the thing the later campaign actually needs: territory that
## pays per turn, an enemy that attacks what you hold, and a decision between
## defending a place and pushing on to the next one. All three of those are
## questions about what is NEXT TO what.
##
## Undirected — listed once, drawn once. A site with no entry simply has no
## borders, which is the right answer for the sim arenas.
const ADJACENCY := [
	[&"hillfort_1_relay", &"basin_1_anchor"],
	[&"hillfort_1_relay", &"salient_1_overthetop"],
	[&"basin_1_anchor", &"coast_1_road"],
	[&"basin_1_anchor", &"pitt_1_rivers"],
	[&"salient_1_overthetop", &"pitt_1_rivers"],
	[&"coast_1_road", &"mutaha_2_city"],
	[&"pitt_1_rivers", &"mutaha_2_city"],
	[&"pitt_1_rivers", &"georgetown_1_ascent"],
	[&"mutaha_2_city", &"polaris_1_siege"],
	[&"georgetown_1_ascent", &"polaris_1_siege"],
	[&"polaris_1_siege", &"causeway_1_tower"],
]


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
