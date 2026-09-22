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
# Wide rather than tall, so a long op fits by going to two columns at the same
# type size instead of shrinking the type: Coast Road's eight rows ran the one
# column off the bottom of the old board.
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

## Type sizes the objective list may use, largest first. It only steps down
## when two columns at the larger size would still run into the footer.
const LIST_SIZES: Array[int] = [42, 36, 30, 26]
const ROW_GAP := 8.0
const COLUMN_GAP := 40.0

## Board width in metres. Height follows from `resolution`.
@export var width_m: float = 5.4
## Turn about Y to face whoever is looking, like a hologram, so it reads from
## anywhere in the room. Off, it faces this node's +Z like a panel on a wall.
@export var face_player: bool = true
## Canvas size. Only affects sharpness; it is rendered once per selection.
@export var resolution: Vector2i = Vector2i(1728, 576)
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
# DRAW — map square on the left; the op's name across the rest, and under it
# the objectives, in one column or two.
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

	# Rings first and labels after, so no ring is ever drawn over a number.
	for i in _shown:
		_Painter.draw_objective(_canvas, font, map_r, _data, i, "", false, marker_scale)
	_Painter.draw_insertion(_canvas, font, map_r, _data, 1.0, marker_scale)
	_draw_marker_labels(font, map_r)

	# ── the text ──
	var x := map_r.end.x + 30.0
	var w := size.x - x - pad
	var y := pad

	y = _line(font, "NEXT OPERATION", x, y, w, 34, COL_DIM) + 4.0
	y = _line(font, _mission.display_name.to_upper(), x, y, w, 56, COL_BRIGHT) + 26.0

	# Size along the bottom: "is this a two-minute op or a twenty-minute one"
	# is the other thing the map is for.
	var span := _data.world_span()
	var metres: int = int(round(maxf(absf(span.x), absf(span.y))))
	var foot := "%d M ACROSS" % metres
	var foot_size := 36
	var foot_y := map_r.end.y - font.get_descent(foot_size)
	_canvas.draw_string(font, Vector2(x, foot_y), foot, HORIZONTAL_ALIGNMENT_LEFT, w, foot_size, COL_DIM)

	if not _shown.is_empty():
		y = _line(font, "OBJECTIVES", x, y, w, 36, COL_DIM) + 8.0
		_list(font, x, y, w, foot_y - font.get_ascent(foot_size) - 16.0)


# Each marker's number, or EXTRACT. Objectives a few metres apart land on the
# same spot at board scale — each of Coast Road's relays stands beside a hive —
# and two numbers printed over each other read as one wrong one. So markers on
# one spot share one label, "1,2", and each label goes on whichever side of its
# spot is clearest of the other rings and labels, rather than always below:
# Foundry's 1 landed in the rings beside it and could not be seen at all.
func _draw_marker_labels(font: Font, map_r: Rect2) -> void:
	var s := marker_scale
	# The outer ring's radius and a little of its stroke.
	var ring := 17.0 * s
	var spots: Array[Dictionary] = []
	var n := 0
	for i in _shown:
		var p := _Painter.to_px(map_r, _data.to_uv(_data.objective_positions[i]))
		var rings := Rect2(p - Vector2.ONE * ring, Vector2.ONE * ring * 2.0)
		if _data.objective_kinds[i] == &"extract":
			spots.append({"at": p, "box": rings, "text": "EXTRACT", "col": COL_WARN, "goal": false})
			continue
		n += 1
		var shared := false
		for spot in spots:
			if spot["goal"] and (spot["at"] as Vector2).distance_to(p) < ring * 0.75:
				spot["text"] += ",%d" % n
				spot["box"] = (spot["box"] as Rect2).merge(rings)
				shared = true
				break
		if not shared:
			spots.append({"at": p, "box": rings, "text": str(n), "col": COL_CRIT, "goal": true})

	# What a label must keep off: every marker's rings, the insertion's word,
	# and each label already placed.
	var taken: Array[Rect2] = []
	for spot in spots:
		taken.append(spot["box"])
	var size := _Painter.label_size(s)
	var ascent := font.get_ascent(size)
	var h := font.get_height(size)
	for pos in _data.insertion_positions:
		var uv := _data.to_uv(pos)
		var p := _Painter.to_px(map_r, uv)
		taken.append(Rect2(p - Vector2.ONE * ring, Vector2.ONE * ring * 2.0))
		var at := _Painter.marker_label_at(font, map_r, p, uv, "INSERTION", s)
		var w := font.get_string_size("INSERTION", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		taken.append(Rect2(at.x, at.y - ascent, w, h))

	var gap := 3.0 * s
	for spot in spots:
		var b: Rect2 = spot["box"]
		var mid := b.get_center()
		var w := font.get_string_size(spot["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var below := Rect2(mid.x - w * 0.5, b.end.y + gap, w, h)
		var above := Rect2(mid.x - w * 0.5, b.position.y - gap - h, w, h)
		var right := Rect2(b.end.x + gap, mid.y - h * 0.5, w, h)
		var left := Rect2(b.position.x - gap - w, mid.y - h * 0.5, w, h)
		# Toward the middle of the map first, the same as the briefing's rule.
		var tries: Array[Rect2] = [below, above, right, left]
		if mid.y >= map_r.get_center().y:
			tries = [above, below, right, left]
		var best := tries[0]
		var least := INF
		for box in tries:
			var cost := _clutter(box, taken, map_r)
			if cost < least - 0.5:
				least = cost
				best = box
		taken.append(best)
		_Painter.draw_label(_canvas, font, best.position + Vector2(0, ascent), spot["text"], spot["col"], s)


# How much of a label's box would land on something already drawn, or off the
# map. Zero means clear.
func _clutter(box: Rect2, taken: Array[Rect2], map_r: Rect2) -> float:
	var cost := box.get_area() - box.intersection(map_r).get_area()
	for t in taken:
		cost += box.intersection(t).get_area()
	return cost


# The objectives, numbered as the markers are, extraction last. One column while
# that fits above the footer, otherwise two: read down the first and then the
# second, split where the two come out most even. The type only comes down a
# size when two columns will not fit either.
func _list(font: Font, x: float, top: float, w: float, bottom: float) -> void:
	var rows: Array[String] = []
	var cols: Array[Color] = []
	var n := 0
	for i in _shown:
		if _data.objective_kinds[i] == &"extract":
			rows.append("THEN %s" % _data.display_name_of(i))
			cols.append(COL_WARN)
		else:
			n += 1
			rows.append("%d. %s" % [n, _data.display_name_of(i)])
			cols.append(COL_CRIT)
	var room := bottom - top
	var half := (w - COLUMN_GAP) * 0.5
	for font_size in LIST_SIZES:
		# The gap under the last row may hang past the bottom: it is empty.
		var one := _heights(font, rows, w, font_size)
		if _sum(one, 0, rows.size()) - ROW_GAP <= room:
			_column(font, rows, cols, 0, rows.size(), x, top, w, font_size)
			return
		var two := _heights(font, rows, half, font_size)
		var k := _split(two)
		var tall := maxf(_sum(two, 0, k), _sum(two, k, rows.size())) - ROW_GAP
		if tall <= room or font_size == LIST_SIZES[-1]:
			_column(font, rows, cols, 0, k, x, top, half, font_size)
			_column(font, rows, cols, k, rows.size(), x + half + COLUMN_GAP, top, half, font_size)
			return


func _column(font: Font, rows: Array[String], cols: Array[Color], from: int, to: int,
		x: float, y: float, w: float, font_size: int) -> void:
	for r in range(from, to):
		y = _line(font, rows[r], x, y, w, font_size, cols[r]) + ROW_GAP


# Each row's height at a width and size, the gap under it included. A long name
# wraps, so rows are measured rather than counted.
func _heights(font: Font, rows: Array[String], w: float, font_size: int) -> Array[float]:
	var out: Array[float] = []
	for text in rows:
		out.append(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, font_size).y + ROW_GAP)
	return out


func _sum(h: Array[float], from: int, to: int) -> float:
	var total := 0.0
	for r in range(from, to):
		total += h[r]
	return total


# How many rows the first column takes: the split that leaves the taller column
# shortest, and on a tie the one that gives the first column the extra row, the
# way a printed list runs.
func _split(h: Array[float]) -> int:
	var total := _sum(h, 0, h.size())
	var best := h.size()
	var best_tall := INF
	var run := 0.0
	for k in range(1, h.size() + 1):
		run += h[k - 1]
		var tall := maxf(run, total - run)
		if tall <= best_tall + 0.5:
			best_tall = minf(tall, best_tall)
			best = k
	return best


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
