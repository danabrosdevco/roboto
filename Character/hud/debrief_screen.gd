extends Control

# ─────────────────────────────────────────────
# DEBRIEF — the mission-complete screen, in the squad manager's style.
#
# Replaces the payout toast. Campaign.extract() hands over everything in its
# result: resources and compute before and after, what the operation unlocked,
# and one entry per robot that went (Campaign._debrief_squad) — what it killed,
# by kind, the XP it earned and whether it came home. This holds the result
# until the squad is back at base, then shows it, paused, until CONTINUE.
#
# Built in code and added to the HUD by the objective HUD, so no scene has to
# carry it.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
const KillKinds := preload("res://Campaign/kill_kinds.gd")
## Seconds the resources and compute take to count up.
const COUNT_SECONDS := 1.4

var _campaign: Node
var _pending: Dictionary = {}
var _mission: MissionDefinition
var _column: VBoxContainer
## Every number on the page that counts up, filled by _counter() as it builds
## them. A list rather than a field per counter: the two-field version silently
## dropped any counter nobody remembered to wire.
var _counters: Array[Label] = []
var _counting := 0.0
var _page: int = 0
var _result_now: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	_campaign = get_tree().get_first_node_in_group("campaign")
	if _campaign == null:
		push_warning("DebriefScreen: no campaign in the scene; there will be no debrief.")
		return
	_campaign.extracted.connect(_on_extracted)
	_campaign.returned_to_base.connect(_on_home)


func _on_extracted(mission: MissionDefinition, result: Dictionary) -> void:
	_mission = mission
	_pending = result
	_cover()


# ─────────────────────────────────────────────
# THE DEPOT FLASH.
#
# The debrief waits for returned_to_base, for a good reason: the level behind
# it should be home, with nothing left running in the one you just left. What
# it did NOT account for is the gap. World._change_level adds the base,
# places the player, and then awaits a process frame AND a physics frame
# before calling on_returned_to_base — both load-bearing, the physics one
# because the navigation server only commits its regions on a physics step
# and the enemy spawner queries it.
#
# So for at least two frames the depot is on screen, lit, with no debrief over
# it. You extract and you see home before you are told what happened.
#
# The awaits cannot go. So the screen is covered at EXTRACT instead, the
# moment the result exists, and stays covered across the swap until the real
# debrief is built on top of it. Nothing about the load sequence changes.
#
# NO PAUSE HOLD on the cover. show_result takes one; taking one here would
# pause the tree during the level load, which is exactly where that sequence
# is doing careful work with the navigation server.
var _blackout: ColorRect = null


func _cover() -> void:
	if _blackout != null and is_instance_valid(_blackout):
		return
	_blackout = ColorRect.new()
	# The debrief's own backdrop colour, so the cover and the screen that
	# replaces it are the same black and the handover is invisible.
	_blackout.color = Color(0.025, 0.04, 0.035, 1.0)
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	_blackout.process_mode = Node.PROCESS_MODE_ALWAYS
	_blackout.z_index = 109   # under the debrief itself, over everything else
	var host: Node = get_parent()
	if host == null:
		push_warning("DebriefScreen: no parent to hang the extraction cover on, so the depot will flash.")
		_blackout = null
		return
	host.add_child(_blackout)


func _uncover() -> void:
	if _blackout == null or not is_instance_valid(_blackout):
		return
	# remove_child first: queue_free is deferred, and a cover that lingers one
	# frame on top of the debrief is the same bug pointing the other way.
	_blackout.get_parent().remove_child(_blackout)
	_blackout.queue_free()
	_blackout = null


# Shown at base, not at the extraction point: the level behind it is home, and
# nothing is left running in the one you just left. The cover above holds the
# screen in the meantime.
func _on_home() -> void:
	if _pending.is_empty():
		_uncover()   # arrived home without a result to show: let the base through
		return
	show_result(_mission, _pending)
	_pending = {}


func is_open() -> bool:
	return visible


# ─────────────────────────────────────────────
# PAGES
# ─────────────────────────────────────────────
# The debrief is up to three screens, each closed with the same CONTINUE:
#
#   1. what the operation paid and what the squad did
#   2. anything it unlocked, if it unlocked something
#   3. the campaign being over, if it just ended
#
# They used to be one page, with the unlocks as a chip beside the payout and
# the win as a line of text above the squad. Both are the biggest thing that
# can happen on that screen and both read as footnotes — a new frame arriving
# is the reason you played the mission, and it was smaller than the XP.
#
# One screen and one pause hold throughout: this rebuilds itself rather than
# handing off to another node, so nothing else has to know the flow exists.
const PAGE_RESULTS := &"results"
const PAGE_UNLOCKS := &"unlocks"
const PAGE_WON := &"won"


func _pages() -> Array:
	var out: Array = [PAGE_RESULTS]
	var unlocked: Array = _result_now.get("unlocked", [])
	if not unlocked.is_empty() and _unlocks(unlocked) != null:
		out.append(PAGE_UNLOCKS)
	if bool(_result_now.get("won", false)):
		out.append(PAGE_WON)
	return out


## CONTINUE, and the keyboard. Moves to the next page, or leaves if that was
## the last one.
func advance() -> void:
	var pages := _pages()
	if _page + 1 < pages.size():
		_page += 1
		_build(_mission, _result_now)
		return
	close()


func show_result(mission: MissionDefinition, result: Dictionary) -> void:
	_page = 0
	_result_now = result
	_build(mission, result)
	visible = true
	# AFTER visible, never before: dropping the cover first would show one
	# frame of depot between the two, which is the bug this exists to stop.
	_uncover()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseHold.take(&"debrief")
	_counting = 0.0
	set_physics_process(true)


func close() -> void:
	_uncover()   # belt and braces: never leave the screen black
	if not visible:
		return
	visible = false
	set_physics_process(false)
	PauseHold.release(&"debrief")
	# The click on CONTINUE must not reach the gun as a held trigger.
	SquadManagerUI.release_pending = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		advance()


# Every counter on the page counts up to where the mission left it. Physics,
# not process (the project rule), and only while counting.
func _physics_process(delta: float) -> void:
	_counting += delta
	var t := clampf(_counting / COUNT_SECONDS, 0.0, 1.0)
	t = 1.0 - pow(1.0 - t, 3.0)
	for counter in _counters:
		if counter == null or not is_instance_valid(counter) or not counter.has_meta(&"from"):
			continue
		var now := int(round(lerpf(counter.get_meta(&"from"), counter.get_meta(&"to"), t)))
		if bool(counter.get_meta(&"clock", false)):
			counter.text = _clock(now)
			continue
		counter.text = str(counter.get_meta(&"prefix", "")) + str(now)
	if t >= 1.0:
		set_physics_process(false)


# ─────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────
func _build(mission: MissionDefinition, result: Dictionary) -> void:
	Kit.clear(self)
	# Kit.clear() has just freed the labels the last page registered, and page 2
	# builds its own. Cleared rather than filtered so the list cannot grow a
	# freed entry per page turn.
	_counters.clear()
	var backdrop := ColorRect.new()
	# Opaque: the HUD underneath (the wallet, the weapon bar) showed through.
	backdrop.color = Color(0.025, 0.04, 0.035, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	_column = Kit.vbox(12)
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column.offset_left = 26
	_column.offset_right = -26
	_column.offset_top = 18
	_column.offset_bottom = -22
	add_child(_column)

	var page: StringName = _pages()[mini(_page, _pages().size() - 1)]
	var success := bool(result.get("success", true))
	var head := Kit.hbox(14)
	var titles := Kit.vbox(0)
	var heading := "MISSION COMPLETE" if success else "MISSION FAILED"
	if page == PAGE_UNLOCKS:
		heading = "NEW HARDWARE"
	elif page == PAGE_WON:
		heading = "CAMPAIGN WON"
	titles.add_child(Kit.label(heading,
		Kit.BRIGHT if success or page != PAGE_RESULTS else Kit.PROBLEM, 32, true))
	if mission != null:
		var name_row := Kit.hbox(14)
		name_row.add_child(Kit.label(mission.display_name.to_upper(), Kit.DIM, Kit.HEADING))
		# The clock used to hang off the end of this row. It is a TIME counter
		# down in the stats now, where the other numbers are and where it gets
		# a label — see _rewards().
		titles.add_child(name_row)
	# A failed run is rolled back to the state it deployed in, so everything
	# below reads as a report rather than a bill: wrecks are shown because they
	# happened, and the payout is zero because none of it was kept. Say so, or
	# the zeros and the write-offs look like something broken.
	if bool(result.get("rewound", false)):
		titles.add_child(Kit.label("RUN VOIDED · THE SQUAD AND THE STORES ARE AS YOU LEFT BASE",
			Kit.BRIGHT, Kit.SMALL, true))
	head.add_child(titles)
	# THE BUTTON KEEPS ITS PLACE, THE TITLE GIVES WAY. A Label's minimum width
	# is the full width of its text, so a long mission name pushed CONTINUE off
	# the right-hand edge of the screen where it could not be clicked — and the
	# font this HUD draws in is wider than anything a headless check can
	# measure, so the overflow only ever showed up on the real thing. Letting
	# the titles clip means the row can always seat the button.
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in titles.get_children():
		if child is Label:
			(child as Label).clip_text = true
		elif child is HBoxContainer:
			for inner in child.get_children():
				if inner is Label:
					(inner as Label).clip_text = true
	var go := Kit.button("CONTINUE", Kit.BRIGHT, 20)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(advance)
	head.add_child(go)
	_column.add_child(head)
	var rule := ColorRect.new()
	rule.color = Kit.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	_column.add_child(rule)

	if page == PAGE_UNLOCKS:
		_build_unlocks(result)
		return
	if page == PAGE_WON:
		_build_won()
		return

	_column.add_child(_rewards(result))

	var squad: Array = result.get("squad", [])
	var lost := 0
	for entry in squad:
		if bool(entry.get("destroyed", false)):
			lost += 1
	var squad_head := Kit.hbox(10)
	squad_head.add_child(Kit.heading("SQUAD"))
	squad_head.add_child(Kit.label("%d CAME HOME%s" % [squad.size() - lost, " · %d LOST" % lost if lost > 0 else ""],
		Kit.PROBLEM if lost > 0 else Kit.DIM, Kit.SMALL))
	_column.add_child(squad_head)
	# BY TEAM, the way you sent them in: you first, then each team under its
	# own name with what it did. One grid per team — a single grid would line
	# the cards up across the headings.
	var grid := Kit.vbox(10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for group in _by_team(squad):
		var team_head := Kit.hbox(8)
		team_head.add_child(Kit.label(str(group["label"]), Kit.BRIGHT, Kit.BODY, true))
		# The team's own tally sits NEXT TO ITS NAME, not pushed out to the far
		# right of a very wide screen where it reads as belonging to nothing and
		# ran off the edge entirely. Bright, because it is the thing you came to
		# this screen to find out.
		team_head.add_child(Kit.label(_tally_text(int(group["kills"]), int(group["revives"])),
			Kit.BRIGHT, Kit.SMALL))
		team_head.add_child(Kit.fill())
		grid.add_child(team_head)
		var row := GridContainer.new()
		row.columns = 3
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for entry in group["entries"]:
			var card := _card(entry)
			if card == null:
				continue   # no record on it: _card has already said so
			row.add_child(card)
		grid.add_child(row)
	# Ten robots is four rows of cards, and the screen has room for three: the
	# last row ran off the bottom with no way to reach it. The cards scroll;
	# everything above them — the payout, the unlocks — stays put.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Clear of the scrollbar: the team headings carry a tally on the right, and
	# the bar sat over it.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 14)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(grid)
	scroll.add_child(pad)
	_column.add_child(scroll)


# RESOURCES and COMPUTE counting up, then anything the operation unlocked.
func _rewards(result: Dictionary) -> Control:
	var row := Kit.hbox(40)
	var before := int(result.get("resources_before", 0))
	var after := int(result.get("resources_after", before))
	var mission_pay := int(result.get("reward", 0))
	var bonus := int(result.get("objective_reward", 0))
	var salvage := int(result.get("salvage", 0))
	var parts := PackedStringArray()
	if mission_pay > 0:
		parts.append("%d MISSION" % mission_pay)
	if bonus > 0:
		parts.append("%d BONUS" % bonus)
	if salvage > 0:
		parts.append("%d SALVAGE" % salvage)
	# WHAT YOU EARNED IS THE HEADLINE, not what you happen to be holding.
	#
	# The big number used to be the balance, with the payout as a footnote
	# beside the breakdown — so the screen you get for finishing a mission led
	# with a number that barely moved. The take is the thing you did; the
	# balance is context for it, and goes underneath.
	var earned := after - before
	var money := _counter("EARNED", 0, earned, Kit.MONEY,
		" + ".join(parts) if earned > 0 else "NO PAYOUT", "+")
	money.add_child(Kit.label("%d IN THE BANK" % after, Kit.DIM, Kit.SMALL))
	row.add_child(money)
	var gained := int(result.get("compute", 0))
	if gained > 0:
		var c_before := int(result.get("compute_before", 0))
		var brain := _counter("COMPUTE", c_before, c_before + gained, Kit.COMPUTE, "+%d" % gained)
		row.add_child(brain)
	# WHAT THE SQUAD DID, AT THE SAME SIZE AS WHAT IT EARNED. These two used to
	# be one small right-aligned line up beside the roster heading, where the
	# longest run in the game ran off the edge of the screen and got clipped
	# mid-word. They are the other half of the result — a mission is a payout
	# AND a body count — so they are counted up here next to it instead.
	var tally_kills := 0
	var tally_lifts := 0
	for entry in result.get("squad", []):
		tally_kills += int(entry.get("kills", 0))
		tally_lifts += int(entry.get("revives", 0))
	row.add_child(_counter("KILLS", 0, tally_kills, Kit.BRIGHT, "BY THE WHOLE SQUAD"))
	# GREEN, not the compute blue. Blue is the colour of the compute currency
	# everywhere else on this screen and in the squad manager, so a blue REVIVES
	# read as a second resource you had earned rather than as something the
	# squad did. Revives belong with KILLS: both are what the squad did.
	if tally_lifts > 0:
		row.add_child(_counter("REVIVES", 0, tally_lifts, Kit.BRIGHT, "STOOD BACK UP"))
	# HOW LONG IT TOOK, counted up beside the rest. It used to be a bare "12:34"
	# tucked against the mission name at heading size, next to nothing else that
	# was a number — so the one figure on the page with no label was the one
	# nobody read. It is a stat, so it goes in the row of stats.
	var seconds := float(result.get("seconds", 0.0))
	if seconds > 0.0:
		row.add_child(_counter("TIME", 0, int(round(seconds)), Kit.DIM,
			"ON THE GROUND", "", true))
	# Unlocks are NOT here any more. They get the whole screen after this one —
	# a chip beside the payout was the smallest thing on the page and it was
	# the reason you ran the operation.
	return row


func _counter(title: String, from: int, to: int, color: Color, note: String, prefix: String = "",
		clock: bool = false) -> Control:
	var col := Kit.vbox(0)
	col.add_child(Kit.label(title, Kit.DIM, Kit.SMALL, true))
	var number := Kit.label(_clock(from) if clock else prefix + str(from), color, 34, true)
	number.set_meta(&"from", float(from))
	number.set_meta(&"to", float(to))
	# A counter that counts a GAIN reads as a gain: "+490", not "490".
	number.set_meta(&"prefix", prefix)
	# A clock counts in seconds and is WRITTEN as m:ss, so the run-up reads as
	# a clock running rather than as a four-figure number of seconds.
	number.set_meta(&"clock", clock)
	col.add_child(number)
	col.add_child(Kit.label(note, Kit.DIM, Kit.SMALL))
	col.set_meta(&"number", number)
	# REGISTERED HERE, not by the caller. The count-up used to run over two
	# named fields the builder had to remember to assign, so KILLS and REVIVES
	# were built, shown, and never counted — they sat on their `from` value and
	# reported 0 kills under a squad that had made 74. Every counter is made in
	# this function, so this is the one place registration cannot be forgotten.
	_counters.append(number)
	return col


# Gear and frames only — the next operation opening is the terminal's news.
# PAGE 2. What the operation opened up, big, on its own, with where to go and
# get it. The same tiles as the old chip, scaled up and centred.
func _build_unlocks(result: Dictionary) -> void:
	var ids: Array = result.get("unlocked", [])
	var body := Kit.vbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	var line := Kit.label("%s CLEARED. THE FOLLOWING IS NOW AVAILABLE TO YOU."
		% (_mission.display_name.to_upper() if _mission != null else "THE OPERATION"),
		Kit.DIM, Kit.HEADING)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(line)
	var tiles := _unlocks(ids, true)
	if tiles != null:
		tiles.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(tiles)
	var hint := Kit.label("FIT IT BEFORE YOU DEPLOY AGAIN", Kit.BRIGHT, Kit.SMALL, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)
	_column.add_child(body)


# PAGE 3. The end of the campaign, which was a line of text above the squad
# grid and is now the screen it deserves.
func _build_won() -> void:
	var body := Kit.vbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	for text in ["THE VALLEY IS YOURS.",
			"EVERY OPERATION IS NOW OPEN AT THE TERMINAL, IN ANY ORDER.",
			"TAKE THE SQUAD BACK OUT WHENEVER YOU LIKE."]:
		var bright: bool = text.begins_with("THE VALLEY")
		var line := Kit.label(text, Kit.BRIGHT if bright else Kit.DIM, 26 if bright else Kit.HEADING, bright)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(line)
	_column.add_child(body)


func _unlocks(ids: Array, large: bool = false) -> Control:
	var catalogue = _campaign.get("catalogue") if _campaign != null else null
	if catalogue == null or ids.is_empty():
		return null
	var col := Kit.vbox(4)
	if not large:
		col.add_child(Kit.label("UNLOCKED", Kit.DIM, Kit.SMALL, true))
	var row := Kit.hbox(34 if large else 14)
	for id in ids:
		var item: ItemDefinition = catalogue.item(id)
		var frame: ChassisDefinition = catalogue.chassis_def(id)
		var tile := Kit.vbox(6 if large else 2)
		# NOTHING THE ARMOURER WILL NOT SELL. Every tile here says "AT THE
		# ARMORER", so announcing something with in_shop off sends the player to
		# a shelf that does not stock it. The unlock still happens — it is only
		# the announcement that is withheld.
		if item != null and not item.in_shop:
			continue
		if item != null:
			var wide := item.kind == ItemDefinition.Kind.WEAPON
			var size := Vector2(232, 88) if wide else Vector2(88, 88)
			tile.add_child(Kit.icon(Icons.item(item, "l" if large else "m"), Kit.BRIGHT,
				size if large else (Vector2(96, 36) if wide else Vector2(36, 36))))
			tile.add_child(Kit.label(item.display_name.to_upper(), Kit.BRIGHT, Kit.HEADING if large else Kit.SMALL, true))
			tile.add_child(Kit.label("AT THE ARMORER", Kit.DIM, Kit.SMALL if large else 11))
		elif frame != null:
			tile.add_child(Kit.icon(Icons.chassis(frame, "l" if large else "m"), Kit.BRIGHT,
				Vector2(128, 128) if large else Vector2(64, 64)))
			tile.add_child(Kit.label(Kit.frame_word(frame), Kit.BRIGHT, Kit.HEADING if large else Kit.SMALL, true))
			tile.add_child(Kit.label("AT THE FACTORY", Kit.DIM, Kit.SMALL if large else 11))
		else:
			continue
		row.add_child(tile)
	if row.get_child_count() == 0:
		return null
	col.add_child(row)
	return col


# One robot: its frame, whether it came home, what it killed and its XP.
# The squad split the way it was sent in: one group per team in the squad
# page's order, then anything with no team (a save from before teams).
#
# You are counted in YOUR team, not in a group of your own. A bucket labelled
# YOU meant the team you fought with was always short its best gun in the
# tally, and read as though you had been somewhere else.
func _by_team(squad: Array) -> Array:
	var groups: Array = []
	var index := {}
	for entry in squad:
		var id := StringName(str(entry.get("team", "")))
		# Held in a local and stored once, rather than indexed back out of
		# `index` twice. The Dictionary is the same object either way, so the
		# grouping is unchanged — but nothing here does a `[]` lookup that can
		# throw on a results screen, which is the whole point.
		var group: Dictionary = index.get(id, {})
		if group.is_empty():
			group = {"label": _team_label(id), "id": id, "entries": [], "kills": 0, "revives": 0}
			index[id] = group
			groups.append(group)
		# Your card leads the team you are in, wherever you sit in the roster.
		if bool(entry.get("player", false)):
			(group["entries"] as Array).push_front(entry)
		else:
			(group["entries"] as Array).append(entry)
		group["kills"] = int(group["kills"]) + int(entry.get("kills", 0))
		group["revives"] = int(group["revives"]) + int(entry.get("revives", 0))
	var order: Array = _team_order()
	groups.sort_custom(func(a, b): return _rank_of(order, a["id"]) < _rank_of(order, b["id"]))
	return groups


func _team_order() -> Array:
	var state = _campaign.get("state") if _campaign != null else null
	var out: Array = []
	if state == null or not ("teams" in state):
		return out   # no campaign state to ask: first seen, first listed
	for team in state.teams:
		out.append(StringName(str(team.get("id", ""))))
	return out


func _rank_of(order: Array, id) -> int:
	var at := order.find(id)
	return at if at >= 0 else order.size()   # a team the page no longer lists goes last


func _team_label(id: StringName) -> String:
	var state = _campaign.get("state") if _campaign != null else null
	if state != null and id != &"" and state.has_method("team_name"):
		var name: String = state.team_name(id)
		if name != "":
			return name.to_upper()
	return "SQUAD"


# "12 KILLS", "12 KILLS : 3 REVIVES", "3 REVIVES" — and "0 KILLS" when there
# was neither, which is a result too.
func _tally_text(kills: int, revives: int) -> String:
	var parts: Array[String] = []
	if kills > 0 or revives == 0:
		parts.append("%d KILL%s" % [kills, "" if kills == 1 else "S"])
	if revives > 0:
		parts.append("%d REVIVE%s" % [revives, "" if revives == 1 else "S"])
	return " : ".join(parts)


func _card(entry: Dictionary) -> Control:
	# A CARD IS ABOUT A ROBOT, so an entry with no robot on it has no card —
	# and used to throw instead, taking the rest of the roster down with it and
	# then handing add_child() a null on the way out. Every entry the campaign
	# builds carries a record; one that does not came from somewhere else, and
	# the screen should say which rather than die.
	if not entry.has("record") or entry["record"] == null:
		push_warning("DebriefScreen: a squad entry has no record on it, so it gets no card. Keys: %s" % str(entry.keys()))
		return null
	var record: SoldierRecord = entry["record"]
	var catalogue = _campaign.get("catalogue") if _campaign != null else null
	var frame: ChassisDefinition = catalogue.chassis_def(record.chassis_id) if catalogue != null else null
	var destroyed := bool(entry.get("destroyed", false))
	var is_player := bool(entry.get("player", false))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Kit.PROBLEM if destroyed else Kit.LINE, Kit.PANEL, 1, 10.0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 104)
	var col := Kit.vbox(6)
	card.add_child(col)

	var top := Kit.hbox(10)
	top.add_child(Kit.icon(Icons.chassis(frame, "s"), Kit.PROBLEM if destroyed else Kit.BRIGHT, Vector2(40, 40)))
	var who := Kit.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(Kit.label(record.display_name.to_upper(), Kit.PROBLEM if destroyed else Kit.BRIGHT, 18, true))
	var status := "YOU" if is_player else ("DESTROYED" if destroyed else "CAME HOME")
	who.add_child(Kit.label(status, Kit.PROBLEM if destroyed else Kit.DIM, Kit.SMALL, destroyed))
	top.add_child(who)
	# THE COUNT, between who it was and what they got for it. The kinds below
	# say what they killed and the icons take a moment to read; this is the one
	# number you actually compare squadmates on, so it goes in the header.
	var tally := int(entry.get("kills", 0))
	var lifts := int(entry.get("revives", 0))
	var score := Kit.vbox(0)
	# What this one did. A Mechanic that killed nothing and stood four
	# squadmates back up read "0 KILLS", which said nothing about its mission:
	# with no kills, its revives take the number. Neither is still 0 KILLS.
	if tally > 0 or lifts == 0:
		score.add_child(Kit.label(str(tally), Kit.BRIGHT if tally > 0 else Kit.DIM, 26, true))
		score.add_child(Kit.label("KILLS" if tally != 1 else "KILL", Kit.DIM, Kit.SMALL))
		if lifts > 0:
			score.add_child(Kit.label("+%d REVIVED" % lifts, Kit.BRIGHT, Kit.SMALL))
	else:
		score.add_child(Kit.label(str(lifts), Kit.BRIGHT, 26, true))
		score.add_child(Kit.label("REVIVES" if lifts != 1 else "REVIVE", Kit.DIM, Kit.SMALL))
	for line in score.get_children():
		(line as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(score)
	if not is_player:
		var xp_col := Kit.vbox(0)
		var gained := int(entry.get("xp", 0))
		var xp_label := Kit.label("+%d XP" % gained if gained > 0 else "NO XP", Kit.BRIGHT if gained > 0 else Kit.DIM, Kit.HEADING, true)
		xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		xp_col.add_child(xp_label)
		var promoted := record.rank > int(entry.get("rank_before", record.rank))
		var rank_row := Kit.hbox(4)
		rank_row.alignment = BoxContainer.ALIGNMENT_END
		rank_row.add_child(Kit.label("PROMOTED · %s" % record.rank_title().to_upper() if promoted else record.rank_title().to_upper(),
			Kit.BRIGHT if promoted else Kit.DIM, Kit.SMALL, promoted))
		rank_row.add_child(Kit.chevrons(record.rank))
		xp_col.add_child(rank_row)
		top.add_child(xp_col)
	col.add_child(top)
	col.add_child(_kills(entry.get("kinds", {}), int(entry.get("kills", 0))))
	return card


# What it killed, by kind: the enemy's frame and a count. A kind with no icon
# yet still reads, by name.
#
# WRAPPED, NOT ONE LONG ROW. The cards sit in a three-column grid, and a grid
# sizes its columns to the widest card in them — so a player who came home with
# seven kinds on their tally stretched their card until the other two columns
# ran off the right of the screen. The cards only scroll DOWN, so what went off
# the side was gone rather than reachable. Four to a row caps how wide any card
# can ever ask to be; the card grows downwards instead, which the scroll covers.
const KILLS_PER_ROW := 4


func _kills(kinds: Dictionary, total: int) -> Control:
	var box := Kit.vbox(4)
	if kinds.is_empty():
		# The header carries the count now, so an empty tally says nothing
		# rather than saying "NO KILLS" directly under a "0 KILLS".
		if total > 0:
			box.add_child(Kit.label("%d KILLS" % total, Kit.DIM, Kit.SMALL))
		return box
	var ordered: Array = kinds.keys()
	ordered.sort_custom(func(a, b): return int(kinds[a]) > int(kinds[b]))
	var row: HBoxContainer = null
	for i in ordered.size():
		if i % KILLS_PER_ROW == 0:
			row = Kit.hbox(10)
			box.add_child(row)
		var kind = ordered[i]
		var pair := Kit.hbox(3)
		var frame := KillKinds.frame_of(kind)
		var tex := Icons.chassis(frame, "s") if frame != null else null
		if tex != null:
			pair.add_child(Kit.icon(tex, Kit.PROBLEM.lerp(Kit.DIM, 0.35), Vector2(40, 40)))
		else:
			pair.add_child(Kit.label(KillKinds.name_of(kind), Kit.DIM, Kit.SMALL))
		pair.add_child(Kit.label("X%d" % int(kinds[kind]), Kit.BRIGHT, Kit.BODY, true))
		pair.tooltip_text = KillKinds.name_of(kind)
		pair.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(pair)
	return box


# Mission length, ASCII only — the HUD font has no glyph outside it. Minutes
# and seconds up to an hour, then hours and minutes, because a mission that
# runs past the hour is an evening and the seconds stop mattering.
func _clock(seconds: float) -> String:
	var whole := int(round(maxf(seconds, 0.0)))
	if whole < 3600:
		return "%d:%02d" % [whole / 60, whole % 60]
	@warning_ignore("integer_division")
	return "%dh %02dm" % [whole / 3600, (whole % 3600) / 60]
