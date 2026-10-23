extends Control
class_name SquadManagerUI

## Prices come from one table now — see Campaign/pricing.gd. Preloaded rather
## than named, because a new `class_name` is not visible until the editor
## rescans and this project cannot run --import.
const _Pricing := preload("res://Campaign/pricing.gd")

# ─────────────────────────────────────────────
# SQUAD MANAGER — three pages behind one key, each with one job:
#
#   SQUAD     who goes, in which team, what they carry  squad/squad_page.gd
#   FACTORY   production lines, marks, modules, seats   squad/factory_page.gd
#   MEMORY    your own weapons, equipment, upgrades     squad/memory_page.gd
#
# One screen used to do all of it at once — roster, loadouts, a shop, the
# stockpile, recruiting, supply — and playtesters could not find how to buy a
# rifle. It went to five pages, and then back to three as the shops went.
#
# THERE IS NO SHOP ANY MORE (2026-10-22, MARK_SYSTEM_SPEC.md step 7b). Tooling
# sold the right to open a line; the Armorer sold copies of gear. The Mark
# system made a robot's loadout a property of its production LINE, so there
# are no copies to buy, and the Factory card charges for the line it is
# already showing you. The player's own gun was the Armorer's last real
# customer, and MEMORY took that — see docs/briefs/archive/MEMORY_SCREEN_SPEC.md.
#
# CampaignState.buy_item()/sell_item() SURVIVE and are still tested. Nothing
# in the UI calls them now; they are the armoury's transaction shape, and
# recover_kit and the seed still move stock through it.
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
const _FactoryPage := preload("res://Character/hud/squad/factory_page.gd")
const _MemoryPage := preload("res://Character/hud/squad/memory_page.gd")
# TOOLING IS GONE (2026-10-22). Its whole job was opening a line, which now
# happens on the Factory card for the line it opens — a page whose only reason
# to exist was charging for the thing you were already looking at.
#
# SOFTWARE IS NOW MEMORY (2026-10-22), and holds the player's own weapons and
# equipment beside the branches — see docs/briefs/archive/MEMORY_SCREEN_SPEC.md §2.1.
# The KEY changed with the title, so a save or a context that still says
# "software" lands on SQUAD rather than on a tab that no longer exists.
const TABS := [&"squad", &"factory", &"memory"]
const TAB_TITLES := {&"squad": "SQUAD", &"factory": "FACTORY", &"memory": "MEMORY"}

var campaign: Node
var state: CampaignState
var catalogue: ItemCatalogue

var _hidden: Array[Control] = []
var _tab: StringName = &"squad"
var _tab_buttons := {}
var _pages := {}
# ── MOTION (see the MOTION block in ui_kit.gd) ──
## The two halves of the screen, kept so opening can bring them in.
var _backdrop: ColorRect
var _column: VBoxContainer
## True for the one rebuild that is an ARRIVAL — the screen opening, or a tab
## you just pressed. False for the dozens that are a REFRESH: every purchase
## rebuilds the whole page, and replaying the entrance on each of them would
## make buying four things in a row look like the screen was struggling.
var _entering: bool = false
## What the purse said last, so a change can be counted rather than snapped.
## -1 means "nothing to count from yet", which is the state on open.
var _shown_resources: int = -1
var _shown_compute: int = -1
var _res_roll: Tween
var _compute_roll: Tween
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
	# NOTHING TO COUNT FROM. The purse rolls when a number changes while you
	# are looking at it; on the way in it is simply what it is.
	_shown_resources = -1
	_shown_compute = -1
	for page in _pages.values():
		page.on_open()
	_entering = true
	_rebuild()
	_play_arrival()


## THE SCREEN ARRIVES; IT DOES NOT SLIDE OR WIPE. The ground comes up first
## and the contents a beat behind it, which reads as a panel being brought up
## rather than as going somewhere else — this is a screen you open over the
## world with TAB, not a destination.
##
## 0.19 s ALL IN, and that ceiling is the whole design. You open this
## constantly; anything you can notice waiting for is worse than no animation
## at all. The cards' own stagger (Kit.stagger) runs underneath it and is
## capped at 0.30 s.
func _play_arrival() -> void:
	if _backdrop == null or _column == null:
		return
	if not Kit.motion:
		_backdrop.modulate.a = 1.0
		_column.modulate.a = 1.0
		return
	_backdrop.modulate.a = 0.0
	_column.modulate.a = 0.0
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_backdrop, "modulate:a", 1.0, 0.09).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_column, "modulate:a", 1.0, 0.19).set_ease(Tween.EASE_OUT).set_delay(0.04)


# CLOSING IS INSTANT, ON PURPOSE. Everything else here releases on the same
# frame — the pause hold, the cursor, the mouse mode, `release_pending` so the
# click that dismissed the menu is not inherited by the gun. Fading out while
# all of that has already happened shows you a ghost menu over a running game
# for the length of the fade.
func close() -> void:
	visible = false
	release_pending = true
	PauseHold.release(&"squad_manager")
	_hide_other_hud(false)
	_clear_cursors()
	_play(sfx_close)
	_restore_mouse()


## GIVE THE MOUSE BACK TO WHOEVER STILL WANTS IT.
##
## This used to capture unconditionally, which is right when the squad
## manager is the only screen open and wrong the moment it is not. Open the
## ops table, press TAB, close the squad manager again: you are still
## standing at the table looking at the board, and the cursor you need to
## use it has just been taken away with no way to get it back short of
## closing and reopening.
##
## Any other screen holding the pause is a screen that wants a cursor, so
## the capture only happens when this was the last one up.
static func _restore_mouse() -> void:
	for who in PauseHold.holders():
		if who != &"squad_manager":
			return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Switches page. `context` can steer the page it lands on: {"kind": n} opens
## the Armorer on that kind of gear, or the Squad page on a slot of that kind.
func show_tab(tab: StringName, context: Dictionary = {}) -> void:
	if not _pages.has(tab):
		return
	var moved: bool = tab != _tab
	_tab = tab
	if context.has("kind") and _pages[tab].has_method("focus_kind"):
		_pages[tab].focus_kind(int(context["kind"]))
	_play(sfx_select)
	# A TAB YOU ACTUALLY MOVED TO is an arrival. Pressing the tab you are
	# already on is not, or the page would flash every time a page sent you
	# back to itself.
	_entering = _entering or moved
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
	_backdrop = backdrop

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = panel_margin
	column.offset_right = -panel_margin
	column.offset_top = panel_margin * 0.6
	column.offset_bottom = -panel_margin
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_column = column

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
			&"factory":
				page = _FactoryPage.new()
			&"memory":
				page = _MemoryPage.new()
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = false
		column.add_child(page)
		page.setup(self)
		_pages[tab] = page


## The two numbers in the header, counted rather than snapped.
##
## WHAT YOU SPENT IS THE ONLY THING ON THIS SCREEN THAT MOVES BY ITSELF. A
## price changing from 4140 to 3890 between two frames is information you have
## to go and check; the same change counted down over a third of a second is
## the screen telling you it took the money.
##
## THE OLD TWEEN IS KILLED FIRST. Buy two things quickly and two rolls would
## otherwise write `text` on the same frame, and the number flickers between
## the two of them.
func _roll_purse() -> void:
	var res: int = state.available()
	var comp: int = state.compute_free()
	if _res_roll != null and _res_roll.is_valid():
		_res_roll.kill()
	if _compute_roll != null and _compute_roll.is_valid():
		_compute_roll.kill()
	_res_roll = Kit.roll(_resources, _shown_resources if _shown_resources >= 0 else res,
		res, "RESOURCES %d")
	_compute_roll = Kit.roll(_compute, _shown_compute if _shown_compute >= 0 else comp,
		comp, "COMPUTE %d")
	_shown_resources = res
	_shown_compute = comp


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
	_roll_purse()
	_refresh_tabs()
	for tab in _pages:
		_pages[tab].visible = tab == _tab
	_pages[_tab].rebuild()
	# ONLY ON AN ARRIVAL, and the flag is cleared here rather than by whoever
	# set it so that every path out of this function leaves it false. A
	# purchase rebuilds this page too, and it must not replay the entrance.
	if _entering:
		Kit.stagger(_pages[_tab])
	_entering = false
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
			# A REFUSAL USED TO BE SILENCE. There are 23 play(&"denied")
			# calls across the three pages and `sfx_denied` was assigned in
			# no scene in the project, so every one of them was mute — and
			# because an unaffordable button is DISABLED, most refusals never
			# reached even this. "No" was communicated by the screen being
			# inert. The shake is here because it still works with the sound
			# slot empty.
			_play(sfx_denied)
			Kit.nudge(_column)


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


## Is this line still shut? (Campaign.is_locked), falling back to the ledger
## when there is no campaign manager to ask.
##
## Replaces locked_by(), which named the OPERATION that would unlock a thing.
## Operations no longer grant kit — you open a line in the fabrication car —
## so there is no mission to name.
func is_locked(id: StringName) -> bool:
	if campaign != null and campaign.has_method("is_locked"):
		return campaign.is_locked(id)
	# NO CAMPAIGN MANAGER, BUT THE STATE STILL KNOWS.
	#
	# This used to return false outright, on the reasoning that a stand-in
	# campaign locks nothing. That made every page list EVERYTHING the moment
	# the manager was absent — the exact failure the gate exists to prevent,
	# and silent, because a shop showing too much looks like a shop. The ledger
	# is the authority; only the DEBUG switch lives on the manager.
	if state != null:
		return not state.is_unlocked(id)
	return false


## EVERY PRODUCTION LINE, open or not — open ones first, each half cheapest
## first.
##
## buildable_frames() below hides a shut line, which was right while the
## Tooling fabricator was the place you opened one. With that page gone the
## Factory is the only place a line exists at all, and a line you cannot see
## is a line you will never open. Shut ones are drawn dimmed with their price.
func production_lines() -> Array:
	var open_lines: Array = []
	var shut: Array = []
	if catalogue == null:
		return open_lines
	for frame in catalogue.chassis:
		if frame == null or not frame.purchasable:
			continue
		if is_locked(frame.id):
			shut.append(frame)
		else:
			open_lines.append(frame)
	var by_price := func(a: ChassisDefinition, b: ChassisDefinition) -> bool:
		return _Pricing.chassis_buy(a) < _Pricing.chassis_buy(b)
	open_lines.sort_custom(by_price)
	shut.sort_custom(by_price)
	return open_lines + shut


func buildable_frames() -> Array:
	var out: Array = []
	if catalogue == null:
		return out
	for frame in catalogue.chassis:
		if frame != null and frame.purchasable and not is_locked(frame.id):
			out.append(frame)
	# CHEAPEST FIRST, left to right. The row is a ladder and "what can I afford
	# next" runs in one direction; read the other way the Walker led and the
	# Soldier — the thing you actually buy early — was first off the end when
	# the row overflowed its scroller.
	out.sort_custom(func(a: ChassisDefinition, b: ChassisDefinition) -> bool:
		return _Pricing.chassis_buy(a) < _Pricing.chassis_buy(b))
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
