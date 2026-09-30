extends Control
class_name MissionBriefing

# ─────────────────────────────────────────────
# MISSION BRIEFING — the map you read before you deploy.
#
# Answers the three questions a first-time player could not answer at all:
# where am I going, how many of them are there, and how big is this place.
# That last one is why the scale bar is not decoration — "is this a two minute
# mission or a twenty minute one" was a real source of confusion.
#
# Reads a MinimapData baked by tools/minimap.sh: a top-down render of the
# level's own geometry plus every objective's id, name and world position. All
# this screen does is draw that image and put markers on it, so it works for
# any level that has been baked and shows a text-only briefing for any that
# has not.
#
# PROCESS_MODE_ALWAYS. The tree is paused while the level streams in, which is
# precisely the window this is meant to fill — without it the sweep would sit
# frozen on the first frame.
# ─────────────────────────────────────────────

signal finished

# BRIEFING is the pre-deploy read; MAP is the same screen opened mid-mission.
# One class rather than two because everything that matters — the baked image,
# the world-to-pixel mapping, the markers, the layout — is identical. The only
# differences are that the map has no sweep to run, knows which objectives are
# already done, and draws where you and your squad currently are.
enum Mode { BRIEFING, MAP }

## Wait for the player instead of timing out. On by default: this screen is the
## only chance to read the map, and a briefing that dismisses itself while you
## are still looking at it is worse than no briefing.
@export var require_keypress: bool = true
## Only used when require_keypress is off — seconds to hold after the sweep.
@export var hold_seconds: float = 2.6
## How long the radar sweep takes to cross the map.
@export var sweep_seconds: float = 1.9
## Ignore input for this long so the keypress that opened the mission cannot
## also dismiss the briefing in the same breath.
@export var input_grace: float = 0.45
## Seconds between the map finishing and PRESS ANY KEY TO DEPLOY appearing. No
## key deploys until it is up. The first press finishes the sweep, and without
## this beat a quick second press — or a double-click — landed in the same
## instant the prompt did and skipped the finished map entirely.
@export var prompt_delay: float = 0.3

@export var map_fraction: float = 0.8
@export var blip_sound: AudioStreamPlayer = null

const COL_BRIGHT := HUDPalette.BRIGHT
const COL_DIM := HUDPalette.DIM
const COL_WARN := HUDPalette.WARN
const COL_CRIT := HUDPalette.CRIT
const _Painter := preload("res://Character/hud/minimap_painter.gd")

var _data: MinimapData = null
# Indices of the objectives THIS mission uses, goals then extraction. The bake
# holds every objective the level has; most ops switch on only some of them.
var _shown: Array[int] = []
var _mission_name: String = ""
var _squad_label: String = ""
var _elapsed: float = 0.0
var _sweep: float = 0.0
var _done: bool = false
var _revealed: Dictionary = {}
var _mode: Mode = Mode.BRIEFING
# _elapsed at the moment the sweep finished, however it finished. -1 until then.
var _swept_at: float = -1.0

var _title: Label
var _footer: Label
var _map: TextureRect
var _overlay: Control
var _list: VBoxContainer
var _list_rows: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_title = _label(46, COL_BRIGHT)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 46
	_title.offset_bottom = 110
	add_child(_title)

	# The map sits in the middle and the markers are drawn by _overlay ON TOP of
	# it, rather than as child controls — a marker is a circle, a tick and a
	# label that all have to line up exactly, and _draw is far less fiddly than
	# positioning three nodes per objective.
	_map = TextureRect.new()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	# THE LIST, in the dead space left of the map. The screen is 16:9 and the
	# map is square, so those margins were empty — and marker labels alone are
	# not enough: they overlap when objectives sit close together, and they
	# give no sense of how many there are in total.
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)

	_footer = _label(20, COL_DIM)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_top = -92
	_footer.offset_bottom = -34
	add_child(_footer)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ─────────────────────────────────────────────
# SHOW
# ─────────────────────────────────────────────
func brief(mission: MissionDefinition) -> void:
	_mission_name = mission.display_name if mission != null else "OPERATION"
	_squad_label = mission.squad_label() if mission != null else ""
	_data = MinimapData.for_mission(mission)
	_shown.clear()
	if _data != null:
		_shown = _data.objective_order(mission.active_objectives)
	_elapsed = 0.0
	_sweep = 0.0
	_swept_at = -1.0
	_done = false
	_revealed.clear()
	_mode = Mode.BRIEFING

	_title.text = _mission_name.to_upper()

	var tex: Texture2D = _data.texture() if _data != null else null
	_map.texture = tex
	_map.visible = tex != null

	_footer.text = _footer_text()
	_build_list()
	visible = true
	set_process(true)
	queue_redraw()
	_overlay.queue_redraw()


## The same screen, opened mid-mission. No sweep — you already know where the
## objectives are, and making you watch a reveal animation every time you check
## the map would be an obstacle rather than atmosphere.
func open_map(mission: MissionDefinition) -> void:
	brief(mission)
	_mode = Mode.MAP
	_sweep = 1.0
	for i in _shown:
		_revealed[i] = true
	for entry in _list_rows:
		(entry["row"] as Label).modulate.a = 1.0
	_footer.text = _footer_text()
	_overlay.queue_redraw()


func is_open() -> bool:
	return visible and not _done


# Which objectives are already done, by id.
#
# Read off the objective NODES rather than through ObjectiveTracker, which
# exposes only all_required_complete(). The nodes carry both `id` and
# `completed` already, and this way the map cannot disagree with the world.
func _completed_ids() -> Dictionary:
	var out: Dictionary = {}
	_scan_completed(get_tree().root, out)
	return out


func _scan_completed(node: Node, out: Dictionary) -> void:
	if "id" in node and "completed" in node:
		if bool(node.get("completed")):
			out[StringName(str(node.get("id")))] = true
	for c in node.get_children():
		_scan_completed(c, out)


# One row per objective, in the order the mission lists them, with extraction
# always last because it is the thing you do after the others.
#
# remove_child before queue_free: queue_free is deferred, so clearing and
# refilling in the same frame would otherwise leave the previous mission's
# objectives stacked under the new ones.
func _build_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list_rows.clear()
	if _data == null:
		return

	# Only if there is something to head. A lone "OBJECTIVES" over empty space
	# reads as a list that failed to load rather than a level with none.
	if not _shown.is_empty():
		var head := _label(19, COL_BRIGHT)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.text = "OBJECTIVES"
		_list.add_child(head)

	var n := 0
	for i in _shown:
		var extract: bool = _data.objective_kinds[i] == &"extract"
		var name := _data.display_name_of(i)
		var row := _label(17, COL_WARN if extract else COL_CRIT)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if extract:
			row.text = "  ↳  THEN %s" % name
		else:
			n += 1
			row.text = "  %d.  %s" % [n, name]
		# Revealed in step with the blips, so the list fills as the sweep runs
		# rather than giving the answer away before the map has drawn it.
		row.modulate.a = 0.0
		_list.add_child(row)
		_list_rows.append({"row": row, "index": i})


func _footer_text() -> String:
	if _data == null:
		return "NO MAP DATA — run tools/minimap.sh"
	var span := _data.world_span()
	var metres: int = int(round(maxf(absf(span.x), absf(span.y))))
	var head := "%d OBJECTIVE%s     %d M ACROSS" % [
		_goal_count(), "" if _goal_count() == 1 else "S", metres]
	# Solo / N allies, when the op limits the squad — said here as well as on
	# the terminal, because this is the screen they are reading as they go in.
	if _squad_label != "":
		head += "     %s" % _squad_label
	# The prompt only appears once there is nothing left to watch. Offering
	# "press any key" over a map still drawing itself invites the player to
	# skip the thing they opened the screen to see.
	if _mode == Mode.MAP:
		return "%s     ▸ ANY KEY TO CLOSE" % head
	if _prompt_ready():
		return "%s     ▸ PRESS ANY KEY TO DEPLOY" % head
	return head


func _goal_count() -> int:
	if _data == null:
		return 0
	var n := 0
	for i in _shown:
		if _data.objective_kinds[i] != &"extract":
			n += 1
	return n


# ─────────────────────────────────────────────
# TICK
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	_elapsed += delta
	_layout_map()
	# Rows fade up as their blip lights, so the list and the map tell the same
	# story at the same moment.
	for entry in _list_rows:
		var row: Label = entry["row"]
		var target: float = 1.0 if _revealed.has(entry["index"]) else 0.0
		row.modulate.a = lerpf(row.modulate.a, target, clampf(delta * 9.0, 0.0, 1.0))
	if _sweep < 1.0:
		_sweep = minf(1.0, _sweep + delta / maxf(sweep_seconds, 0.01))
		_check_reveals()
		_overlay.queue_redraw()
		if _sweep >= 1.0:
			_swept_at = _elapsed
	elif not _done and not require_keypress and _elapsed >= sweep_seconds + hold_seconds:
		_finish()
	_footer.text = _footer_text()


# Whether a key now deploys. The footer shows the prompt on exactly the same
# condition, so it is on screen if and only if pressing will do something.
func _prompt_ready() -> bool:
	return _sweep >= 1.0 and _swept_at >= 0.0 and _elapsed >= input_grace \
		and _elapsed - _swept_at >= prompt_delay


func _layout_map() -> void:
	# Fitted into the BAND between the title and the footer. The briefing
	# paragraph that used to sit under the title is gone — the terminal and the
	# map board carry the facts now — and the map takes its space.
	var top: float = 118.0
	var bottom: float = size.y - 104.0
	var side: float = minf(minf(size.x, size.y) * map_fraction, maxf(bottom - top, 80.0))
	var r := Rect2(
		Vector2((size.x - side) * 0.5, top + (bottom - top - side) * 0.5),
		Vector2(side, side))
	_map.position = r.position
	_map.size = r.size
	_overlay.position = r.position
	_overlay.size = r.size

	# The list fills the left margin, top-aligned with the map so the two read
	# as one panel rather than two things that happen to be on screen.
	_list.position = Vector2(56.0, r.position.y + 8.0)
	_list.size = Vector2(maxf(r.position.x - 80.0, 140.0), r.size.y)


# A blip lights when the sweep line crosses it, which is the whole reason the
# sweep exists — it paces the reveal so the eye lands on one objective at a
# time instead of taking in five at once.
func _check_reveals() -> void:
	if _data == null:
		return
	for i in _shown:
		if _revealed.has(i):
			continue
		var uv := _data.to_uv(_data.objective_positions[i])
		if uv.x <= _sweep:
			_revealed[i] = true
			if blip_sound != null:
				blip_sound.play()


func _draw_overlay() -> void:
	var r := Rect2(Vector2.ZERO, _overlay.size)
	# Frame, so the map reads as a display rather than a photograph.
	_overlay.draw_rect(r, Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.35), false, 2.0)

	if _data == null:
		return

	# The sweep line itself, and a dim veil over everything it has not reached.
	var x: float = r.size.x * _sweep
	if _sweep < 1.0:
		_overlay.draw_rect(Rect2(Vector2(x, 0), Vector2(r.size.x - x, r.size.y)),
			Color(0.02, 0.03, 0.04, 0.82), true)
		_overlay.draw_line(Vector2(x, 0), Vector2(x, r.size.y),
			Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.9), 2.0)

	var font := ThemeDB.fallback_font
	var done: Dictionary = _completed_ids() if _mode == Mode.MAP else {}

	for i in _shown:
		if not _revealed.has(i):
			continue
		_Painter.draw_objective(_overlay, font, r, _data, i, _data.display_name_of(i),
			done.has(_data.objective_ids[i]))

	# On the live map the insertion sits under your arrow, which is how you see
	# how far you've come.
	_Painter.draw_insertion(_overlay, font, r, _data, _sweep)

	if _mode == Mode.MAP:
		_draw_live(r)


# YOU, and your squad. The whole difference between a briefing and a map: a
# picture of the objectives tells you where to go, and this tells you where you
# are relative to them, which is the question you actually open a map to ask.
func _draw_live(r: Rect2) -> void:
	for s in get_tree().get_nodes_in_group("squads"):
		var squad := s as Squad
		if squad == null or not squad.player_commandable:
			continue
		for m in squad.get_living_members():
			if not (m is Node3D):
				continue
			var q := _data.to_uv((m as Node3D).global_position)
			_overlay.draw_circle(Vector2(q.x * r.size.x, q.y * r.size.y), 3.5,
				Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.75))

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		player = _find_player(get_tree().root)
	if player == null:
		return
	var uv := _data.to_uv(player.global_position)
	var p := Vector2(uv.x * r.size.x, uv.y * r.size.y)
	# An arrow, not a dot: which way you are FACING is half of orienting
	# yourself on a map, and a dot cannot say it.
	var yaw: float = -player.global_transform.basis.z.signed_angle_to(Vector3.FORWARD, Vector3.UP)
	var fwd := Vector2(sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var pts := PackedVector2Array([
		p + fwd * 11.0, p - fwd * 6.0 + side * 7.0, p - fwd * 6.0 - side * 7.0])
	_overlay.draw_colored_polygon(pts, COL_BRIGHT)
	_overlay.draw_arc(p, 14.0, 0.0, TAU, 24,
		Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.5), 1.5)


func _find_player(node: Node) -> Node3D:
	if node is Player:
		return node as Node3D
	for c in node.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null


# ─────────────────────────────────────────────
# DISMISS
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not visible or _done:
		return
	if _elapsed < input_grace:
		return
	var pressed: bool = false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	# First press completes the sweep, second dismisses. Skipping straight out
	# would hide the thing the player just asked to see.
	if _sweep < 1.0:
		_sweep = 1.0
		_check_reveals()
		_elapsed = sweep_seconds
		_swept_at = _elapsed
		_overlay.queue_redraw()
		return
	# The map is done but the prompt is not up yet (prompt_delay): this press
	# is the tail of the one that finished the sweep, not a decision to deploy.
	if _mode == Mode.BRIEFING and not _prompt_ready():
		return
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	visible = false
	finished.emit()
