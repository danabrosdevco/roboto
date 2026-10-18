extends Control

# ─────────────────────────────────────────────
# THE OPERATIONS TABLE, ZOOMED.
#
# Press F at the table and you come in close: the same board, filling the
# screen, with a mouse.
#
# IT IS THE SAME BOARD, NOT A DRAWING OF ONE. A SubViewport sharing the
# level's World3D, with its own camera over the table. Nothing is duplicated
# — the sites, the routes, the landmark icons and the gauges are the ones
# standing on the table, seen from a better seat. Redrawing the graph in 2D
# would have meant a second copy of every landmark that could drift from the
# first, and the player would eventually catch the two disagreeing.
#
# IT ALSO SOLVES THE TEXT. Everything legible about this board has been a
# fight with world-space labels: text sized in metres on a table whose sites
# are ten centimetres apart covers its neighbours at any size that can be
# read. In here the chrome is ordinary screen-space UI, sized in pixels,
# against the edge of the screen rather than the middle of the map.
#
# HOUSE PATTERN, borrowed wholesale from SquadManagerUI: full rect,
# PROCESS_MODE_ALWAYS because opening pauses the tree, PauseHold under its
# own name, ESC in _input rather than _unhandled_input, and release_pending
# on the way out so the click that closed it is not inherited by the gun.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _Pal := preload("res://Character/hud/hud_palette.gd")
## The sim arena, which this board offers as one entry rather than two sites.
const _SimArena := preload("res://Character/hud/sim_arena_ui.gd")
const _Wipe := preload("res://Character/hud/cyberspace_wipe.gd")
const _Lab := preload("res://Managers/lab.gd")
const _Plan := preload("res://Campaign/lab/lab_plan.gd")

## Its own hold. Sharing one with the squad manager would mean closing either
## released both — a mistake already documented in master.gd.
const HOLD := &"ops_table"

## The one HUD widget that stays up. You are deciding what to spend, so the
## purse has to be on screen; everything else is battlefield furniture and is
## noise in here.
const KEEP_VISIBLE := &"WalletHUD"

## How far above the board the camera sits, and how far back, as multiples of
## the board's width. Angled rather than straight down: the landmarks STAND
## UP, and from directly overhead a relay dish and a chimney are both a dot.
const CAM_UP := 0.62
const CAM_BACK := 0.74

var table: Node3D = null
var _sub: SubViewport = null
var _cam: Camera3D = null
var _screen: TextureRect = null
var _panel: VBoxContainer = null
var _hovered = null
var _hidden: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Between the squad manager (100) and the debrief (110): the debrief must
	# still land on top of this if a mission ends with the table open.
	z_index = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_physics_process(false)


# ─────────────────────────────────────────────
# OPEN / CLOSE
# ─────────────────────────────────────────────
func open(from_table: Node3D) -> void:
	if from_table == null or not is_instance_valid(from_table):
		push_warning("OpsTableUI: asked to open with no table, so there is nothing to show.")
		return
	table = from_table
	_build()
	visible = true
	set_physics_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseHold.take(HOLD)
	_hide_player(true)
	_hide_other_hud(true)
	_aim_camera()
	if table.has_method("hide_strip"):
		table.hide_strip()
	_select_hover(null)


func close() -> void:
	if not visible:
		return
	visible = false
	set_physics_process(false)
	_hide_player(false)
	PauseHold.release(HOLD)
	_hide_other_hud(false)
	# AND DO NOT HAND BACK A STALE INTERACT PROMPT.
	#
	# _hide_other_hud restores everything it hid, which is right for the purse
	# and the squad list. It is wrong for the interact prompt: that was on
	# screen because the player was looking at this table in order to press F
	# on it, so restoring it puts the prompt back with the table's own words.
	# If a level load follows — which it does on every deploy — the table is
	# freed and nothing ever takes the prompt down again. Reported twice from
	# the sim arena as "still have the problem with select mission".
	var body := _player()
	if body != null and body.has_method("forget_interactible"):
		body.forget_interactible()
	# The click on CLOSE must not reach the gun as a held trigger. The same
	# static flag the debrief screen reuses rather than inventing its own.
	SquadManagerUI.release_pending = true
	# Same guard as the squad manager: only take the cursor back if no other
	# screen is still up wanting it.
	var others := false
	for who in PauseHold.holders():
		if who != HOLD:
			others = true
	if not others:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if table != null and table.has_method("highlight"):
		table.highlight(null)


func is_open() -> bool:
	return visible


## Take the player out of the picture.
##
## The SubViewport shares the level's World3D, so it renders everything the
## world holds — including the player, who is standing AT the table with a
## cluster launcher held out in front of their camera. From overhead that is
## a gun lying across the middle of the campaign.
##
## The whole body, not just the weapon: the loadout swaps viewmodels and
## hiding whichever one happened to be out would miss the next one. This is
## a first-person game, so nothing is lost by hiding the player — and
## visibility does not touch physics, so they stay standing where they were.
func _hide_player(hide_them: bool) -> void:
	var p := _player()
	if p == null:
		return
	p.visible = not hide_them


func _player() -> Node3D:
	if table == null:
		return null
	var n: Node = table
	while n != null:
		var w = n.get("player")
		if w != null and w is Node3D:
			return w
		n = n.get_parent()
	return null


## Hide every sibling HUD control except the purse, and put back exactly
## those we hid. Recorded rather than toggled wholesale: something already
## hidden for its own reasons must stay hidden on the way out.
func _hide_other_hud(hide_them: bool) -> void:
	var host := get_parent()
	if host == null:
		return
	if not hide_them:
		for c in _hidden:
			if is_instance_valid(c):
				c.visible = true
		_hidden.clear()
		return
	_hidden.clear()
	for c in host.get_children():
		if c == self or not (c is CanvasItem):
			continue
		if c.name == KEEP_VISIBLE:
			continue
		if (c as CanvasItem).visible:
			_hidden.append(c)
			(c as CanvasItem).visible = false


# ─────────────────────────────────────────────
# THE VIEW
# ─────────────────────────────────────────────
## A flat grade over the whole zoomed composite, board included. OFF — see the
## long note in _build where it is applied. An alpha above 0 dims the
## projection as much as the room, so raise it only for a base whose interior
## is genuinely too bright to read a hologram against.
@export var room_wash: Color = Color(0.025, 0.04, 0.035, 0.0)


func _build() -> void:
	if _sub != null:
		_refresh_panel()
		return
	# The squad manager's own backdrop colour, so the two screens read as
	# the same machine rather than two programs that happen to be adjacent.
	var back := ColorRect.new()
	back.color = Color(0.025, 0.04, 0.035, 0.97)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_sub = SubViewport.new()
	# THE SAME WORLD. Without this the SubViewport makes its own empty one
	# and the screen is black — the board is in the level, not in here.
	_sub.world_3d = table.get_world_3d()
	_sub.own_world_3d = false
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.size = Vector2i(1280, 720)
	add_child(_sub)

	_cam = Camera3D.new()
	_sub.add_child(_cam)
	_cam.current = true

	_screen = TextureRect.new()
	_screen.texture = _sub.get_texture()
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)

	# ─────────────────────────────────────────────
	# THE WASH IS OFF, AND THIS IS WHY IT EXISTED.
	#
	# The SubViewport renders the world raw: it does not go through the signal
	# filter the rest of the game is seen through. At the DEPOT that mattered —
	# a bright, ungraded floor with the projection sitting on top of it looked
	# like two different games — so a 55% near-black wash pushed the room back
	# down.
	#
	# It cannot do that any more. The wash covers the WHOLE composite, board
	# included, because the room and the projection arrive as one texture from
	# the SubViewport and there is no way to dim one without the other. So it
	# was taking 55% off the brightness of the only thing you open this screen
	# to look at — and the board is additive, so that loss is straight off the
	# top with nothing to recover it.
	#
	# And the premise is gone with the depot. The base is the train, and the
	# ops car is built dark on purpose — "low, dark, and empty. The brightest
	# thing is the projection" — so the room already sits where the wash was
	# dragging it. Keeping both grades the room twice.
	#
	# Left here, off, rather than deleted: if a future base is a bright room
	# the problem comes straight back, and the fix is a number, not a rewrite.
	if room_wash.a > 0.0:
		var wash := ColorRect.new()
		wash.color = room_wash
		wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(wash)

	_build_chrome()


## BROADSIDE, NOT END-ON.
##
## The first version offset the camera along world +Z, which on this train is
## straight down the car — and since the board was turned to lie along the
## car, that looked at a 6.6 m map end-on, foreshortened into a receding
## line. You cannot read a wide map from its narrow end.
##
## The offset now comes off the BOARD'S OWN basis, so the camera sits square
## to its long axis however the table is turned: ninety degrees round from
## where you were standing, with the campaign running left to right.
func _aim_camera() -> void:
	if _cam == null or table == null:
		return
	var board = table.get("board")
	if board == null:
		return
	_pivot = board.global_position
	_span = float(board.board_size) if "board_size" in board else 1.1
	# The board's local Z is across its short axis — the side you read it from.
	_side = board.global_transform.basis.z.normalized()
	if _side.length() < 0.01:
		_side = Vector3.BACK
	# 0.72, not 1.0: at the full standoff a 6.6 m board sat in the middle
	# third of the screen with the car around it. You come here to read the
	# map, so the map opens filling the frame and the wheel pulls back.
	_dist = 0.72
	_cam.fov = 58.0
	_apply_camera()


func _apply_camera() -> void:
	if _cam == null:
		return
	var back: float = _span * CAM_BACK * _dist
	var up: float = _span * CAM_UP * _dist
	_cam.global_position = _pivot + _side * back + Vector3.UP * up
	_cam.look_at(_pivot, Vector3.UP)


# ─────────────────────────────────────────────
# MOVING AROUND IT
#
# WASD walks the view over the board and the wheel comes in and out. In
# _physics_process rather than _process because the tree is PAUSED while this
# is open — PROCESS_MODE_ALWAYS keeps the callback running either way, and
# the project's rule is that new per-frame work goes in the physics tick and
# is switched off when idle, which closing does.
#
# The pan is in the BOARD'S plane, not the camera's: dragging a map should
# move the map, and a pan that drifts in world axes feels like the table is
# sliding rather than the view.
# ─────────────────────────────────────────────
@export var pan_speed: float = 1.4
@export var zoom_step: float = 0.12
@export var zoom_near: float = 0.35
@export var zoom_far: float = 2.2

var _pivot: Vector3 = Vector3.ZERO
var _side: Vector3 = Vector3.BACK
var _span: float = 1.1
var _dist: float = 1.0


func _physics_process(delta: float) -> void:
	if not visible:
		return
	if _cam == null:
		return   # no camera yet; the view has not been built
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move.y += 1.0
	if Input.is_key_pressed(KEY_S): move.y -= 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move == Vector2.ZERO:
		return
	move = move.normalized() * pan_speed * _span * _dist * delta
	# ─────────────────────────────────────────────
	# THE PAN AXES COME OFF THE CAMERA, NOT THE BOARD, and that is the fix for
	# a bug that has now been "fixed" twice.
	#
	# They used to be derived from `_side`, which is `board.basis.z`. NOTHING
	# CONSTRAINS THE SIGN OF THAT. A board turned +90 and a board turned -90
	# give opposite local Z, so pan axes built from it flip as a pair — which
	# is exactly why negating both axes made the controls correct for one
	# table rotation and reversed them again for another. The first report was
	# "WASD reversed" and the negation below was the wrong cure; the second
	# was "W and D are reversed", both axes again, which is the same bug
	# wearing the other sign.
	#
	# The camera's own basis cannot be wrong about which way is up the screen,
	# because it IS the screen. Flattened so panning never lifts off the
	# table. W pans up the map, D pans right, the way every map does it.
	# ─────────────────────────────────────────────
	var fwd: Vector3 = -_cam.global_transform.basis.z
	fwd.y = 0.0
	var right: Vector3 = _cam.global_transform.basis.x
	right.y = 0.0
	if fwd.length() < 0.01 or right.length() < 0.01:
		push_warning("OpsTableUI: the camera is looking straight down, so there is no flat direction to pan along and WASD does nothing this frame.")
		return
	_pivot += right.normalized() * move.x + fwd.normalized() * move.y
	_apply_camera()


func _build_chrome() -> void:
	var head := HBoxContainer.new()
	# The header gets its own band for the same reason.
	var strip := ColorRect.new()
	strip.color = Color(0.025, 0.04, 0.035, 0.97)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 54
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 26
	head.offset_right = -26
	head.offset_top = 18
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	head.add_child(Kit.label("OPERATIONS TABLE", Kit.DIM, Kit.HEADING, true))
	head.add_child(Kit.label("HOME COMMAND · TASKING", Kit.LINE, Kit.SMALL))
	head.add_child(Kit.fill())
	var shut := Kit.button("CLOSE", Kit.DIM, Kit.SMALL)
	# F cannot reach the player while the tree is paused, so there has to be
	# something on screen to press as well as ESC.
	shut.pressed.connect(close)
	head.add_child(shut)

	# A BACKED PANEL, not loose text. The view behind it is the real room —
	# a lit depot floor — and Kit.DIM on that is invisible. Everything the
	# chrome says sits on its own dark ground.
	var box := PanelContainer.new()
	# Kit.box with the kit's own PANEL fill and LINE border — the same
	# stylebox every card in the squad manager wears.
	box.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, 14.0))
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 26
	box.offset_top = -196
	box.offset_bottom = -26
	box.custom_minimum_size = Vector2(330, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_panel = Kit.vbox(6)
	box.add_child(_panel)


# ─────────────────────────────────────────────
# HOVER AND SELECT
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP \
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var d: float = -zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else zoom_step
		_dist = clampf(_dist + d, zoom_near, zoom_far)
		_apply_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_select_hover(_site_under(event.position))
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var hit = _site_under(event.position)
		if hit != null:
			get_viewport().set_input_as_handled()
			_queue(hit)


## Which site the cursor is over, by projecting each one into the view.
##
## Projected rather than raycast: the icons are line art a few millimetres
## thick with no colliders, and giving every one an Area3D so a mouse could
## find it would be a collision shape per landmark for something a dot
## product already answers.
func _site_under(at: Vector2):
	if _cam == null or table == null or _screen == null:
		return null
	var board = table.get("board")
	if board == null or not board.has_method("site_world_position"):
		return null
	# The SubViewport is letterboxed into the screen rect, so a mouse
	# position has to come back through that fit before it means anything.
	var view := Vector2(_sub.size)
	var box := _screen.get_rect()
	var scale: float = minf(box.size.x / view.x, box.size.y / view.y)
	var shown := view * scale
	var local := (at - box.position - (box.size - shown) * 0.5) / scale
	if local.x < 0.0 or local.y < 0.0 or local.x > view.x or local.y > view.y:
		return null

	var best = null
	var best_d: float = 46.0        # pixels, in the SubViewport's own space
	for id in table.facts:
		var world: Vector3 = board.site_world_position(id)
		if _cam.is_position_behind(world):
			continue
		var d: float = _cam.unproject_position(world).distance_to(local)
		if d < best_d:
			best_d = d
			best = id
	return best


func _select_hover(id) -> void:
	if id == _hovered:
		return
	_hovered = id
	# highlight, not show_readout: the board answers, the strip stays down.
	if table.has_method("highlight"):
		table.highlight(id)
	_refresh_panel()


## Act on the site that was clicked.
##
## Through the campaign's own call, never by writing selected_mission_id —
## select_mission also pushes the destination into the departure pad and
## announces it.
func _queue(id) -> void:
	var f: Dictionary = table.facts.get(id, {})

	# CLICKING THE ARENA OPENS THE ARENA. It is not deployable — it is a door,
	# not an operation — so this used to fall straight through the guard below
	# and do nothing at all, while swallowing the click on the way. The only
	# way in was to hover it and find the button on the card, which is why it
	# was reported as "you can't click back to the sim arena".
	if bool(f.get("sim_site", false)):
		_open_arena()
		return

	if f.is_empty():
		push_warning("OpsTableUI: clicked '%s', which the board has no facts for, so there is nothing to queue." % str(id))
		return
	if not bool(f.get("deployable", false)):
		# NOT SILENT. A site you cannot go to yet is the normal case and the
		# card already says why — but a site that should be deployable and is
		# not is invisible otherwise, and this is where that shows up.
		print("[OpsTable] '%s' is not deployable: %s" % [str(id),
			"training unfinished" if bool(f.get("needs_training", false))
			else ("no route" if bool(f.get("locked", false)) else "already held or answering a raid")])
		return
	var campaign = table.get("Campaign")
	if campaign != null and campaign.has_method("select_mission"):
		campaign.select_mission(id)
	_refresh_panel()


func _refresh_panel() -> void:
	if _panel == null:
		return
	Kit.clear(_panel)
	if _hovered == null or not table.facts.has(_hovered):
		_panel.add_child(Kit.label("POINT AT A SITE", Kit.LINE, Kit.SMALL))
		return
	var f: Dictionary = table.facts[_hovered]

	# ── THE SIM ARENA IS A PLACE YOU GO, NOT AN OPERATION YOU QUEUE ─────
	#
	# FIRST, so none of the war furniture below is built for it. It has no
	# Location, no yield and no garrison, so COMPUTE, RESOURCE and RESISTANCE
	# were three rows of zero — and "ADVERSARY HELD" under the name, because
	# the default state line assumes anything you do not hold is theirs. A
	# training facility is not held by the adversary, the zeroes said nothing,
	# and together they made the card twice as tall as it had any reason to be.
	if bool(f.get("sim_site", false)):
		var head: Color = _Pal.SIGNAL
		_panel.add_child(Kit.label(String(f["name"]).to_upper(), head, Kit.HEADING, true))
		_panel.add_child(Kit.label(
			"START HERE" if bool(f.get("training_next", false)) else "OPEN",
			head, Kit.SMALL))
		_panel.add_child(Kit.spacer(0, 8))
		var enter := Kit.button("ENTER THE ARENA", Kit.BRIGHT, Kit.BODY)
		enter.pressed.connect(_open_arena)
		_panel.add_child(enter)
		return

	# WHOSE IT IS, IN THE NAME. Worked out before the name is written so the
	# two lines share one colour: the heading tells you who holds the place
	# at the same instant it tells you which place it is, and it matches the
	# colour of the marker you are pointing at on the board.
	var state := "ADVERSARY HELD"
	var state_col: Color = _Pal.FAC_ADVERSARY
	if bool(f.get("under_attack", false)):
		state = "UNDER ATTACK"
		state_col = _Pal.CRIT
	elif f["locked"]:
		state = "NO ROUTE — NEEDS %s" % String(f["unmet"][0]).to_upper()
		state_col = _Pal.GONE
	elif f["cleared"]:
		state = "HELD · CLEARED x%d" % int(f["clears"])
		state_col = _Pal.HELD

	_panel.add_child(Kit.label(String(f["name"]).to_upper(), state_col, Kit.HEADING, true))
	_panel.add_child(Kit.label(state, state_col, Kit.SMALL))

	_panel.add_child(Kit.spacer(0, 6))
	# COMPUTE IS NOT PER TURN. Resources are a standing yield from ground you
	# hold; compute is not metered that way, so it is just a number.
	_panel.add_child(_figure("COMPUTE", "%d" % int(f.get("compute", 0)), Kit.COMPUTE))
	_panel.add_child(_figure("RESOURCE", "%d /turn" % int(f.get("per_resources", 0)), Kit.MONEY))
	var resist := "%d" % int(f["resistance"])
	if int(f["reserve"]) > 0:
		resist += "   +%d in reserve" % int(f["reserve"])
	_panel.add_child(_figure("RESISTANCE", resist, _Pal.CRIT))

	# ── WHAT YOU CAN DO HERE ────────────────────────────────────────────
	#
	# ANSWERING A RAID COMES FIRST. The defence has no pin of its own — the
	# board draws one per place — so this is the only way to reach it, and it
	# is the thing that is about to cost you the site if you walk away.
	var defend: StringName = f.get("defend_id", &"")
	if defend != &"":
		_panel.add_child(Kit.spacer(0, 8))
		var d := Kit.button("DEFEND IT", _Pal.CRIT, Kit.BODY)
		d.pressed.connect(func(): _queue(defend))
		_panel.add_child(d)

	# NOT YET, AND IT SAYS WHY. Until the two exercises are done the war is not
	# offered at all; without this line the button is simply absent and the
	# board looks broken rather than sequenced.
	if bool(f.get("needs_training", false)):
		_panel.add_child(Kit.spacer(0, 8))
		_panel.add_child(Kit.label("FINISH TRAINING FIRST", _Pal.DIM, Kit.SMALL, true))
		return

	if bool(f.get("deployable", false)):
		_panel.add_child(Kit.spacer(0, 8))
		var queued = table.Campaign.selected_mission() if table.Campaign != null else null
		var is_queued: bool = queued != null and queued.id == _hovered
		var b := Kit.button("QUEUED" if is_queued else "QUEUE THIS OPERATION",
			Kit.DIM if is_queued else Kit.BRIGHT, Kit.BODY)
		b.disabled = is_queued
		b.pressed.connect(func(): _queue(_hovered))
		_panel.add_child(b)


func _figure(name_text: String, value: String, col: Color) -> Control:
	var row := Kit.hbox(10)
	var l := Kit.label(name_text, Kit.DIM, Kit.SMALL)
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	row.add_child(Kit.label(value, col, Kit.BODY, true))
	return row


## Open the sim arena over the board. The two exercises live in here, and so
## does free play once they are done — see SimArenaUI.
##
## NO TRANSITION HERE. This is a menu opening over the board: you are still at
## the table, still choosing. The wipe belongs on the step AFTER this one — the
## moment you commit to an exercise or a fight and actually go in. Putting it on
## the menu made choosing feel like arriving somewhere, and then arriving
## somewhere had no transition left to spend.
func _open_arena() -> void:
	var cm = table.Campaign if table != null else null
	if cm == null:
		push_warning("OpsTableUI: no campaign, so the sim arena has nothing to list.")
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_build_arena(layer, cm)


## GOING INTO THE SIMULATION, which is the one thing in here that gets the wipe.
##
## `at_cover` runs at the midpoint, under full cover, so the load starts while
## nothing can be seen and the wipe clears onto whatever it produced. One helper
## for both doors — an exercise and a lab fight — so they cannot drift apart.
##
## ON THE SCENE ROOT, not on this control. The board closes and the level is
## torn down and rebuilt inside `at_cover`; a wipe parented to the board would
## be freed halfway through its own animation, which is exactly the moment it
## exists to cover.
func _wipe(caption: String, at_cover: Callable) -> void:
	var wipe = _Wipe.new()
	wipe.caption = caption
	var wipe_layer := CanvasLayer.new()
	# UNDER THE LOADING SCREEN, which Master builds at 128. The wipe is what
	# you cross to get there; once the load puts its own overlay up, that is
	# the thing to look at and the wipe belongs behind it. Sharing 128 made
	# the order depend on which was added last, and the grid ran over the
	# loading screen.
	wipe_layer.layer = 100
	# AND IT RUNS WHILE THE TREE IS PAUSED, which it always is here: the
	# operations board takes a PauseHold the moment it opens, and a Tween on a
	# pausable node simply does not advance. The wipe sat frozen at nothing and
	# ENTER appeared to do nothing until you escaped the menu and released the
	# hold. The board sets the same mode on itself, for the same reason.
	wipe_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(wipe_layer)
	wipe_layer.add_child(wipe)
	wipe.midpoint.connect(at_cover)
	wipe.finished.connect(func():
		if is_instance_valid(wipe_layer):
			wipe_layer.queue_free())
	wipe.play()


## The arena screen itself.
func _build_arena(layer: CanvasLayer, cm) -> void:
	if not is_instance_valid(layer) or cm == null:
		push_warning("OpsTableUI: no layer or no campaign, so the arena was not built.")
		return
	var ui = _SimArena.new()
	ui.campaign = cm
	ui.catalogue = cm.catalogue
	layer.add_child(ui)

	# Closing the menu is not going anywhere, so it gets no transition either.
	ui.closed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())

	# ENTER ON AN EXERCISE: wipe, then the mission loads under it.
	ui.training_chosen.connect(func(id: StringName):
		_wipe("ENTERING SIM ARENA", func():
			if is_instance_valid(layer):
				layer.queue_free()
			_deploy_sim(cm, id)))

	# WATCH / LEAD: same door. This was never connected on this path at all —
	# the arena emitted the signal and nothing listened, so both buttons built a
	# matchup and dropped it.
	ui.fight_requested.connect(func(matchup: Resource, lead: bool):
		_wipe("LEAD" if lead else "SPECTATE", func():
			if is_instance_valid(layer):
				layer.queue_free()
			_run_fight(matchup, lead)))


## Deploy straight into an exercise.
##
## NOT select_mission ALONE, which only queues a destination into the departure
## pad and leaves you standing at the table waiting to pull a lever. A sim run
## is not a journey — there is no train to catch, because the arena runs on your
## own hardware. World.load_next_level does the whole lifecycle: begin_deploy,
## tear down the depot, build the level, put the squad in it.
func _deploy_sim(cm, id: StringName) -> void:
	var m = cm.get_mission(id) if cm.has_method("get_mission") else null
	if m == null or m.level_scene == null:
		push_warning("OpsTableUI: '%s' has no level to load, so the exercise cannot start." % String(id))
		return
	if cm.has_method("select_mission"):
		cm.select_mission(id)
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = _find_world(get_tree().root)
	if world == null:
		push_warning("OpsTableUI: no World, so '%s' has nowhere to load." % String(id))
		return
	close()
	world.load_next_level(m.level_scene)


## Hand a matchup the player built to the Laboratory, which already knows how to
## seat two sides facing each other on the proving ground.
func _run_fight(matchup: Resource, lead: bool) -> void:
	if matchup == null:
		push_warning("OpsTableUI: no matchup, so there is no fight to run.")
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = _find_world(get_tree().root)
	if world == null:
		push_warning("OpsTableUI: no World, so the Laboratory has nowhere to put the fight.")
		return
	# The board goes away with it: you are in the arena now, not at the table.
	close()
	var plan = _Plan.new()
	plan.title = "Sim Arena"
	plan.matchups = [matchup] as Array[Resource]
	var lab = _Lab.new()
	lab.name = "SimFight"
	lab.plan = plan
	lab.world = world
	# SPECTATE OR LEAD. A measurement run is always watched so the player cannot
	# affect the numbers; this is not a measurement.
	lab.spectate = not lead
	get_tree().root.add_child(lab)
	lab.run()


func _find_world(n: Node) -> Node:
	if n is World:
		return n
	for c in n.get_children():
		var f := _find_world(c)
		if f != null:
			return f
	return null
