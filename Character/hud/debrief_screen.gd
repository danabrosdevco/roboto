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
var _resources: Label
var _compute: Label
var _counting := 0.0


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


# Shown at base, not at the extraction point: the level behind it is home, and
# nothing is left running in the one you just left.
func _on_home() -> void:
	if _pending.is_empty():
		return
	show_result(_mission, _pending)
	_pending = {}


func is_open() -> bool:
	return visible


func show_result(mission: MissionDefinition, result: Dictionary) -> void:
	_build(mission, result)
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseHold.take(&"debrief")
	_counting = 0.0
	set_physics_process(true)


func close() -> void:
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
		close()


# The two numbers count up to where the mission left them. Physics, not
# process (the project rule), and only while counting.
func _physics_process(delta: float) -> void:
	_counting += delta
	var t := clampf(_counting / COUNT_SECONDS, 0.0, 1.0)
	t = 1.0 - pow(1.0 - t, 3.0)
	if _resources != null and _resources.has_meta(&"from"):
		_resources.text = str(int(round(lerpf(_resources.get_meta(&"from"), _resources.get_meta(&"to"), t))))
	if _compute != null and _compute.has_meta(&"from"):
		_compute.text = str(int(round(lerpf(_compute.get_meta(&"from"), _compute.get_meta(&"to"), t))))
	if t >= 1.0:
		set_physics_process(false)


# ─────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────
func _build(mission: MissionDefinition, result: Dictionary) -> void:
	Kit.clear(self)
	_resources = null
	_compute = null
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

	var success := bool(result.get("success", true))
	var head := Kit.hbox(14)
	var titles := Kit.vbox(0)
	titles.add_child(Kit.label("MISSION COMPLETE" if success else "MISSION FAILED",
		Kit.BRIGHT if success else Kit.PROBLEM, 32, true))
	if mission != null:
		titles.add_child(Kit.label(mission.display_name.to_upper(), Kit.DIM, Kit.HEADING))
	head.add_child(titles)
	head.add_child(Kit.fill())
	var go := Kit.button("CONTINUE", Kit.BRIGHT, 20)
	go.pressed.connect(close)
	head.add_child(go)
	_column.add_child(head)
	var rule := ColorRect.new()
	rule.color = Kit.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	_column.add_child(rule)

	_column.add_child(_rewards(result))
	if bool(result.get("won", false)):
		_column.add_child(Kit.label("CAMPAIGN WON · EVERY OPERATION IS NOW OPEN AT THE TERMINAL", Kit.BRIGHT, 18, true))

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
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in squad:
		grid.add_child(_card(entry))
	_column.add_child(grid)


# RESOURCES and COMPUTE counting up, then anything the operation unlocked.
func _rewards(result: Dictionary) -> Control:
	var row := Kit.hbox(40)
	var before := int(result.get("resources_before", 0))
	var after := int(result.get("resources_after", before))
	var mission_pay := int(result.get("reward", 0))
	var bonus := int(result.get("objective_reward", 0))
	var parts := PackedStringArray()
	if mission_pay > 0:
		parts.append("%d MISSION" % mission_pay)
	if bonus > 0:
		parts.append("%d BONUS" % bonus)
	var money := _counter("RESOURCES", before, after, Kit.MONEY,
		("+%d · %s" % [after - before, " + ".join(parts)]) if after > before else "NO PAYOUT")
	_resources = money.get_meta(&"number")
	row.add_child(money)
	var gained := int(result.get("compute", 0))
	if gained > 0:
		var c_before := int(result.get("compute_before", 0))
		var brain := _counter("COMPUTE", c_before, c_before + gained, Kit.COMPUTE, "+%d" % gained)
		_compute = brain.get_meta(&"number")
		row.add_child(brain)
	var unlocked: Array = result.get("unlocked", [])
	var shown := _unlocks(unlocked)
	if shown != null:
		row.add_child(shown)
	return row


func _counter(title: String, from: int, to: int, color: Color, note: String) -> Control:
	var col := Kit.vbox(0)
	col.add_child(Kit.label(title, Kit.DIM, Kit.SMALL, true))
	var number := Kit.label(str(from), color, 34, true)
	number.set_meta(&"from", float(from))
	number.set_meta(&"to", float(to))
	col.add_child(number)
	col.add_child(Kit.label(note, Kit.DIM, Kit.SMALL))
	col.set_meta(&"number", number)
	return col


# Gear and frames only — the next operation opening is the terminal's news.
func _unlocks(ids: Array) -> Control:
	var catalogue = _campaign.get("catalogue") if _campaign != null else null
	if catalogue == null or ids.is_empty():
		return null
	var col := Kit.vbox(4)
	col.add_child(Kit.label("UNLOCKED", Kit.DIM, Kit.SMALL, true))
	var row := Kit.hbox(14)
	for id in ids:
		var item: ItemDefinition = catalogue.item(id)
		var frame: ChassisDefinition = catalogue.chassis_def(id)
		var tile := Kit.vbox(2)
		if item != null:
			var wide := item.kind == ItemDefinition.Kind.WEAPON
			tile.add_child(Kit.icon(Icons.item(item, "m"), Kit.BRIGHT, Vector2(96, 36) if wide else Vector2(36, 36)))
			tile.add_child(Kit.label(item.display_name.to_upper(), Kit.BRIGHT, Kit.SMALL, true))
			tile.add_child(Kit.label("AT THE ARMORER", Kit.DIM, 11))
		elif frame != null:
			tile.add_child(Kit.icon(Icons.chassis(frame, "m"), Kit.BRIGHT, Vector2(64, 64)))
			tile.add_child(Kit.label(Kit.frame_word(frame), Kit.BRIGHT, Kit.SMALL, true))
			tile.add_child(Kit.label("AT THE FACTORY", Kit.DIM, 11))
		else:
			continue
		row.add_child(tile)
	if row.get_child_count() == 0:
		return null
	col.add_child(row)
	return col


# One robot: its frame, whether it came home, what it killed and its XP.
func _card(entry: Dictionary) -> Control:
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
func _kills(kinds: Dictionary, total: int) -> Control:
	var row := Kit.hbox(10)
	if kinds.is_empty():
		row.add_child(Kit.label("NO KILLS" if total == 0 else "%d KILLS" % total, Kit.DIM, Kit.SMALL))
		return row
	var ordered: Array = kinds.keys()
	ordered.sort_custom(func(a, b): return int(kinds[a]) > int(kinds[b]))
	for kind in ordered:
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
	return row
