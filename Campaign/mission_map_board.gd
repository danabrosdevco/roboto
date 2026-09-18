extends Node3D

# ─────────────────────────────────────────────
# MISSION MAP BOARD — the queued op's map, standing beside the terminal.
#
# The terminal screen says WHAT the op is; this shows WHERE. It reads the same
# baked MinimapData as the briefing, draws it into a SubViewport and hangs that
# in the room on a Sprite3D, so you can look the ground over before you commit
# instead of first seeing it on the deploy screen with the level already
# loading behind it.
#
# Map first, big type second. Everything in the world goes through the signal
# filter, which squeezes the picture down to 360 lines, so the text is sized to
# survive that from a couple of metres rather than to look tidy up close. The
# markers are numbered to match the list instead of carrying their full names,
# because a number survives the filter where "SOUTH GARRISON" at map-label size
# does not. The briefing prose stays on the deploy screen, which is unfiltered.
#
# Follows Campaign.mission_selected. On a CYCLING terminal it shows whatever is
# queued; on a PINNED one only its own mission, and only while that is queued.
# Nothing queued, nothing shown — it previews a choice, it is not decoration.
#
# Costs nothing per frame: the viewport renders once per selection change.
# ─────────────────────────────────────────────

const _Painter := preload("res://Character/hud/minimap_painter.gd")

const COL_BG := Color(0.02, 0.03, 0.04, 1.0)
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_DIM := HUDPalette.DIM
const COL_WARN := HUDPalette.WARN
const COL_CRIT := HUDPalette.CRIT

## Board width in metres. Height follows from `resolution`.
@export var width_m: float = 3.6
## Turn about Y to face whoever is looking, like a hologram, so it reads from
## anywhere in the room. Off, it faces this node's +Z like a panel on a wall.
@export var face_player: bool = true
## Canvas size. Only affects sharpness; it is rendered once per selection.
@export var resolution: Vector2i = Vector2i(1152, 576)
## Marker size relative to the briefing screen's.
@export var marker_scale: float = 2.0
## Above 1 pushes the board past the room's brightest surfaces, so it reads as
## a lit screen once the signal filter has flattened everything else.
@export var brightness: float = 1.35
## Seconds for the switch-on when a new op is queued.
@export var power_on_seconds: float = 0.18

var _viewport: SubViewport
var _canvas: Node2D
var _sprite: Sprite3D
var _campaign: Node = null
var _mission: MissionDefinition = null
var _data: MinimapData = null
var _shown: Array[int] = []
var _tween: Tween = null
var _font: FontVariation = null


func _ready() -> void:
	_build()
	# The terminal resolves the campaign in its own _ready, which runs after
	# this one, so wait a frame and borrow it rather than finding it twice.
	_hook_up.call_deferred()


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.size = resolution
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_canvas = Node2D.new()
	_canvas.draw.connect(_paint)
	_viewport.add_child(_canvas)

	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.pixel_size = width_m / float(maxi(resolution.x, 1))
	# Unshaded: it is a lit screen, and should read the same whatever the room
	# lighting is doing.
	_sprite.shaded = false
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if face_player else BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.modulate = Color(brightness, brightness, brightness, 1.0)
	_sprite.visible = false
	add_child(_sprite)


func _hook_up() -> void:
	var terminal := get_parent()
	if terminal != null:
		_campaign = terminal.get("Campaign")
	if _campaign == null:
		_campaign = get_tree().get_first_node_in_group("campaign")
	if _campaign == null:
		return
	_campaign.mission_selected.connect(_on_mission_selected)
	_campaign.returned_to_base.connect(_refresh)
	_campaign.state_loaded.connect(_refresh)
	_refresh()


func _on_mission_selected(_m: MissionDefinition) -> void:
	_refresh()


func _refresh() -> void:
	var queued: MissionDefinition = null
	if _campaign != null and _campaign.get("state") != null:
		queued = _campaign.selected_mission()
	# A pinned terminal's board speaks only for its own mission.
	var pinned = get_parent().get("mission") if get_parent() != null else null
	if pinned is MissionDefinition and queued != null and (pinned as MissionDefinition).id != queued.id:
		queued = null
	_show(queued)


func _show(m: MissionDefinition) -> void:
	var data: MinimapData = MinimapData.for_mission(m)
	if m == null or data == null:
		_mission = null
		_data = null
		_sprite.visible = false
		return
	var changed: bool = m != _mission
	_mission = m
	_data = data
	_shown = data.objective_order(m.active_objectives)
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sprite.visible = true
	if changed:
		_power_on()


# Opens from a line, like an old tube warming up, so a new selection is
# something you notice out of the corner of your eye.
func _power_on() -> void:
	if _tween != null:
		_tween.kill()
	_sprite.scale = Vector3(1.0, 0.03, 1.0)
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", Vector3.ONE, maxf(power_on_seconds, 0.01)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ─────────────────────────────────────────────
# DRAW — map square on the left, name and objectives down the right.
# ─────────────────────────────────────────────
func _paint() -> void:
	var size := Vector2(resolution)
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if _mission == null or _data == null:
		return
	var font := _board_font()
	var pad := 22.0

	var side := size.y - pad * 2.0
	var map_r := Rect2(Vector2(pad, pad), Vector2(side, side))
	var tex := _data.texture()
	if tex != null:
		_canvas.draw_texture_rect(tex, map_r, false)
	_canvas.draw_rect(map_r, Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.45), false, 3.0)

	var n := 0
	for i in _shown:
		var tag := "EXTRACT"
		if _data.objective_kinds[i] != &"extract":
			n += 1
			tag = str(n)
		_Painter.draw_objective(_canvas, font, map_r, _data, i, tag, false, marker_scale)
	_Painter.draw_insertion(_canvas, font, map_r, _data, 1.0, marker_scale)

	# ── the column ──
	var x := map_r.end.x + 30.0
	var w := size.x - x - pad
	var y := pad

	y = _line(font, "NEXT OPERATION", x, y, w, 34, COL_DIM) + 4.0
	y = _line(font, _mission.display_name.to_upper(), x, y, w, 56, COL_BRIGHT) + 26.0

	if not _shown.is_empty():
		y = _line(font, "OBJECTIVES", x, y, w, 36, COL_DIM) + 8.0
	n = 0
	for i in _shown:
		if _data.objective_kinds[i] == &"extract":
			y = _line(font, "THEN %s" % _data.display_name_of(i), x, y, w, 42, COL_WARN) + 8.0
		else:
			n += 1
			y = _line(font, "%d. %s" % [n, _data.display_name_of(i)], x, y, w, 42, COL_CRIT) + 8.0

	# Size along the bottom: "is this a two-minute op or a twenty-minute one"
	# is the other thing the map is for.
	var span := _data.world_span()
	var metres: int = int(round(maxf(absf(span.x), absf(span.y))))
	var foot := "%d M ACROSS" % metres
	var foot_size := 36
	var foot_y := map_r.end.y - font.get_descent(foot_size)
	_canvas.draw_string(font, Vector2(x, foot_y), foot, HORIZONTAL_ALIGNMENT_LEFT, w, foot_size, COL_DIM)


# Wrapped text with its top at `y`. Returns the y just under it.
func _line(font: Font, text: String, x: float, y: float, w: float, font_size: int, col: Color) -> float:
	var block := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, font_size)
	_canvas.draw_multiline_string(font, Vector2(x, y + font.get_ascent(font_size)), text,
		HORIZONTAL_ALIGNMENT_LEFT, w, font_size, -1, col)
	return y + block.y


# The HUD font, thickened. Its strokes are one pixel wide at the sizes that fit
# here, and the signal filter averages a one-pixel stroke into the background.
func _board_font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.9
	return _font
