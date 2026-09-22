extends Control
class_name SquadManagerUI

# ─────────────────────────────────────────────
# SQUAD MANAGER — three pages behind one key, each with one job:
#
#   SQUAD     who goes, in which team, what they carry  squad/squad_page.gd
#   ARMORER   buying and selling gear                 squad/armorer_page.gd
#   FACTORY   building robots, adding seats           squad/factory_page.gd
#
# One screen used to do all of it at once — roster, loadouts, a shop, the
# stockpile, recruiting, supply — and playtesters could not find how to buy a
# rifle. Now prices appear only at the Armorer, compute only at the Factory,
# and the Squad page answers "is everyone ready?" before anything else.
#
# This file is the frame round the pages: opening and closing, the tabs, the
# resources, sounds, and the few lookups every page needs. The pages build
# themselves from CampaignState, and every change goes through CampaignState,
# which announces it; this rebuilds the page on the announcement.
#
# Built in code for the same reason the HUDs are: it self-wires, so there's no
# inspector slot to leave blank. Toggle with the `squad_manager` action.
# ─────────────────────────────────────────────

@export var open_action: StringName = &"squad_manager"
@export var panel_margin: float = 26.0

# ── AUDIO ─────────────────────────────────────
# Assign AudioStreamPlayers in the inspector; every one is optional and the UI
# is silent rather than broken if you leave them blank.
@export var sfx_hover: AudioStreamPlayer
## Taking something off (back to stores), and selling.
@export var sfx_pick_up: AudioStreamPlayer
## Fitting something, rebuilding, building a robot.
@export var sfx_drop: AudioStreamPlayer
@export var sfx_denied: AudioStreamPlayer
@export var sfx_select: AudioStreamPlayer
@export var sfx_open: AudioStreamPlayer
@export var sfx_close: AudioStreamPlayer

# ── CURSORS ───────────────────────────────────
# hotspot is the pixel in the texture that counts as the point.
@export var cursor_arrow: Texture2D
@export var cursor_drag: Texture2D
@export var cursor_forbidden: Texture2D
@export var cursor_hotspot: Vector2 = Vector2.ZERO

# ── WHAT TO HIDE WHILE OPEN ───────────────────
# Leave empty and every sibling Control under the HUD is hidden, which is
# usually what you want. Name specific nodes to keep something visible.
@export var hide_while_open: Array[Control] = []

# Set on close, consumed by the player on its next physics frame, so the click
# that dismissed the menu is not inherited by the gun as a held trigger. It has
# to be a flag rather than an edge check on "is the menu open", because
# _physics_process does not run at all while the tree is paused.
static var release_pending: bool = false

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _SquadPage := preload("res://Character/hud/squad/squad_page.gd")
const _ArmorerPage := preload("res://Character/hud/squad/armorer_page.gd")
const _FactoryPage := preload("res://Character/hud/squad/factory_page.gd")
const _SoftwarePage := preload("res://Character/hud/squad/software_page.gd")
const TABS := [&"squad", &"armorer", &"factory", &"software"]
const TAB_TITLES := {&"squad": "SQUAD", &"armorer": "ARMORER", &"factory": "FACTORY", &"software": "SOFTWARE"}

var campaign: Node
var state: CampaignState
var catalogue: ItemCatalogue

var _hidden: Array[Control] = []
var _tab: StringName = &"squad"
var _tab_buttons := {}
var _pages := {}
var _resources: Label
var _compute: Label
var _rebuilding: bool = false

# Rebuilding Controls underneath a stationary mouse can emit mouse_entered on
# the replacement Controls. Suppress hover SFX until the player actually moves
# the mouse again so a click only produces its confirm/select sound.
var _suppress_hover_until_mouse_moves: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The INTERFACE slider in the options, not EFFECTS.
	for p in [sfx_hover, sfx_pick_up, sfx_drop, sfx_denied, sfx_select, sfx_open, sfx_close]:
		if p != null:
			p.bus = AudioBuses.INTERFACE

	# Build FIRST, unconditionally: in world.tscn the HUD is declared above
	# CampaignManager, so the campaign does not exist yet when this readies.
	_build_ui()
	_resolve_campaign()

	if not InputMap.has_action(open_action):
		push_warning("SquadManagerUI: no input action '%s'. Add it in Project Settings > Input Map." % open_action)
	else:
		print("[SquadManager] ready, bound to '%s'" % open_action)


# Deferred and retried, because the campaign node readies after this one.
func _resolve_campaign() -> bool:
	if state != null:
		return true
	campaign = get_tree().get_first_node_in_group("campaign")
	if campaign == null:
		return false
	state = campaign.state
	catalogue = campaign.get("catalogue")
	if state != null:
		if not state.roster_changed.is_connected(_rebuild):
			state.roster_changed.connect(_rebuild)
			state.ledger_changed.connect(_rebuild)
	return state != null


# _input, not _unhandled_input. Tab is bound to ui_focus_next by default and the
# UI layer eats it before unhandled input ever runs.
func _input(event: InputEvent) -> void:
	# A real mouse movement re-arms hover audio after a rebuild.
	if event is InputEventMouseMotion:
		_suppress_hover_until_mouse_moves = false

	# ESC closes. Master's own ESC handler bails out whenever the tree is
	# already paused — which this screen does on open.
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return

	if not InputMap.has_action(open_action):
		return
	if event.is_action_pressed(open_action):
		# Not behind another screen: TAB would open this UNDER the pause menu or
		# the options, invisible there and holding its own pause.
		if not visible and (PauseHold.is_held(&"master") or PauseHold.is_held(&"briefing")
				or PauseHold.is_held(&"debrief")):
			return
		get_viewport().set_input_as_handled()
		toggle()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if not _resolve_campaign():
		push_warning("SquadManagerUI: no CampaignManager yet — cannot open.")
		return
	visible = true
	# A management screen with the mouse captured is unusable.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseHold.take(&"squad_manager")
	_apply_cursors()
	_hide_other_hud(true)
	_play(sfx_open)
	# Always onto the squad: "is everyone ready?" is what you open it to see.
	_tab = &"squad"
	for page in _pages.values():
		page.on_open()
	_rebuild()


func close() -> void:
	visible = false
	release_pending = true
	PauseHold.release(&"squad_manager")
	_hide_other_hud(false)
	_clear_cursors()
	_play(sfx_close)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Switches page. `context` can steer the page it lands on: {"kind": n} opens
## the Armorer on that kind of gear, or the Squad page on a slot of that kind.
func show_tab(tab: StringName, context: Dictionary = {}) -> void:
	if not _pages.has(tab):
		return
	_tab = tab
	if context.has("kind") and _pages[tab].has_method("focus_kind"):
		_pages[tab].focus_kind(int(context["kind"]))
	_play(sfx_select)
	_rebuild()


# The crosshair, ammo readout, squad roster and objective list are all noise
# behind a management screen — and the squad HUD keeps drawing world markers
# over the top of it, which looks like a bug.
func _hide_other_hud(hiding: bool) -> void:
	if hiding:
		_hidden.clear()
		var targets: Array[Control] = hide_while_open
		if targets.is_empty():
			for sibling in get_parent().get_children():
				if sibling is Control and sibling != self:
					targets.append(sibling)
		for c in targets:
			if c != null and is_instance_valid(c) and c.visible:
				c.visible = false
				_hidden.append(c)
		return
	for c in _hidden:
		if c != null and is_instance_valid(c):
			c.visible = true
	_hidden.clear()


func _apply_cursors() -> void:
	if cursor_arrow != null:
		Input.set_custom_mouse_cursor(cursor_arrow, Input.CURSOR_ARROW, cursor_hotspot)
	if cursor_drag != null:
		Input.set_custom_mouse_cursor(cursor_drag, Input.CURSOR_DRAG, cursor_hotspot)
		Input.set_custom_mouse_cursor(cursor_drag, Input.CURSOR_CAN_DROP, cursor_hotspot)
	if cursor_forbidden != null:
		Input.set_custom_mouse_cursor(cursor_forbidden, Input.CURSOR_FORBIDDEN, cursor_hotspot)


func _clear_cursors() -> void:
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_FORBIDDEN]:
		Input.set_custom_mouse_cursor(null, shape)


func _play(player: AudioStreamPlayer) -> void:
	if player != null:
		player.play()


# ─────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────
func _build_ui() -> void:
	# Near-opaque: the base behind used to show through and fight the text.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.04, 0.035, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = panel_margin
	column.offset_right = -panel_margin
	column.offset_top = panel_margin * 0.6
	column.offset_bottom = -panel_margin
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var header := Kit.hbox(6)
	column.add_child(header)
	for tab in TABS:
		var b := Button.new()
		b.text = TAB_TITLES[tab]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Kit.FONT_BOLD)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_hover_color", Kit.BRIGHT)
		b.add_theme_color_override("font_pressed_color", Kit.BRIGHT)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.mouse_entered.connect(hover)
		b.pressed.connect(func():
			if _tab != tab:
				show_tab(tab))
		header.add_child(b)
		_tab_buttons[tab] = b
	header.add_child(Kit.fill())
	# Compute beside the resources, on every page: the two things you have.
	_compute = Kit.label("", Kit.COMPUTE, 22, true)
	header.add_child(_compute)
	header.add_child(Kit.spacer(18, 0))
	_resources = Kit.label("", Kit.MONEY, 22, true)
	header.add_child(_resources)
	header.add_child(Kit.spacer(16, 0))
	var close_btn := Kit.button("CLOSE", Kit.DIM, Kit.SMALL)
	close_btn.tooltip_text = "Close (TAB or ESC)"
	close_btn.mouse_entered.connect(hover)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var rule := ColorRect.new()
	rule.color = Kit.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	for tab in TABS:
		var page: Control
		match tab:
			&"squad":
				page = _SquadPage.new()
			&"armorer":
				page = _ArmorerPage.new()
			&"factory":
				page = _FactoryPage.new()
			&"software":
				page = _SoftwarePage.new()
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = false
		column.add_child(page)
		page.setup(self)
		_pages[tab] = page


func _refresh_tabs() -> void:
	for tab in _tab_buttons:
		var b: Button = _tab_buttons[tab]
		var on: bool = tab == _tab
		b.add_theme_color_override("font_color", Kit.BRIGHT if on else Kit.DIM)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Kit.BRIGHT
		style.border_width_bottom = 2 if on else 0
		style.set_content_margin_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, style)


func _rebuild() -> void:
	if state == null or _pages.is_empty() or not visible:
		return
	# Renames emit roster_changed, which is wired straight back here.
	if _rebuilding:
		return
	_rebuilding = true
	# Anything rebuilt under a still mouse fires mouse_entered: keep it quiet.
	_suppress_hover_until_mouse_moves = true
	_resources.text = "RESOURCES %d" % state.available()
	_compute.text = "COMPUTE %d" % state.compute_free()
	_refresh_tabs()
	for tab in _pages:
		_pages[tab].visible = tab == _tab
	_pages[_tab].rebuild()
	_rebuilding = false


# ─────────────────────────────────────────────
# FOR THE PAGES
# ─────────────────────────────────────────────
## "select", "fit", "remove" or "denied".
func play(what: StringName) -> void:
	match what:
		&"select":
			_play(sfx_select)
		&"fit":
			_play(sfx_drop)
		&"remove":
			_play(sfx_pick_up)
		&"denied":
			_play(sfx_denied)


func hover() -> void:
	if not _suppress_hover_until_mouse_moves:
		_play(sfx_hover)


func is_rebuilding() -> bool:
	return _rebuilding


func in_field() -> bool:
	return campaign != null and bool(campaign.get("in_mission"))


## The operation picked at the terminal, if we are at base and one is.
func next_op() -> MissionDefinition:
	if campaign == null or in_field() or not campaign.has_method("selected_mission"):
		return null
	return campaign.selected_mission()


func item(id: StringName) -> ItemDefinition:
	if catalogue == null or id == &"":
		return null
	return catalogue.item(id)


func frame_of(record: SoldierRecord) -> ChassisDefinition:
	if catalogue == null or record == null:
		return null
	return catalogue.chassis_def(record.chassis_id)


## Everything the Armorer lists: all that is for sale, plus anything retired
## from sale that you still have a spare of, so it can be fitted or sold.
## Weapons, then gear, then modules; cheapest first; name breaks ties so the
## order never reshuffles.
func shop_items() -> Array:
	var out: Array = []
	if catalogue == null:
		return out
	for entry in catalogue.items:
		if entry != null and (entry.in_shop or state.armoury.spare(entry.id) > 0):
			out.append(entry)
	out.sort_custom(func(a, b):
		if a.kind != b.kind:
			return a.kind < b.kind
		if a.cost != b.cost:
			return a.cost < b.cost
		return a.display_name < b.display_name)
	return out


## The operation that unlocks `id` while it is still locked, else null
## (Campaign.locked_by). A stand-in campaign with no unlocks locks nothing.
func locked_by(id: StringName) -> MissionDefinition:
	if campaign == null or not campaign.has_method("locked_by"):
		return null
	return campaign.locked_by(id)


func buildable_frames() -> Array:
	var out: Array = []
	if catalogue == null:
		return out
	for frame in catalogue.chassis:
		if frame != null and frame.purchasable:
			out.append(frame)
	return out


## Who has this item fitted, by name: where your copies are.
func carriers_of(item_id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var everyone: Array = [state.player_record]
	everyone.append_array(state.roster)
	for r in everyone:
		if r != null and r.all_fitted_ids().has(item_id):
			out.append(r.display_name.to_upper())
	return out
