extends RefCounted

# ─────────────────────────────────────────────
# MINIMAP PAINTER — objective, extraction and insertion markers, drawn onto any
# CanvasItem over a baked MinimapData.
#
# Shared by the briefing screen and the map board beside the mission terminal,
# so the two cannot drift apart: a marker that means "leave" on one has to mean
# it on the other.
#
# `r` is the rectangle the map image occupies on the canvas. `s` scales every
# radius, stroke and font size: the briefing draws at 1.0, the board bigger,
# because it is read through the signal filter from across the room.
#
# No class_name on purpose. It is reached by preload, so an open editor that
# has not registered a new global class yet cannot null out whoever uses it.
# ─────────────────────────────────────────────

const COL_BRIGHT := HUDPalette.BRIGHT
const COL_DIM := HUDPalette.DIM
const COL_WARN := HUDPalette.WARN
const COL_CRIT := HUDPalette.CRIT

## Insertion points closer than this many pixels (times the scale) share one
## INSERTION label.
const INSERTION_ONE_SPOT := 40.0


static func to_px(r: Rect2, uv: Vector2) -> Vector2:
	return r.position + Vector2(uv.x * r.size.x, uv.y * r.size.y)


## One objective: red rings for a goal, amber rings and a cross for the
## extraction, grey with a tick once it is done.
static func draw_objective(ci: CanvasItem, font: Font, r: Rect2, data: MinimapData,
		i: int, text: String, done: bool = false, s: float = 1.0) -> void:
	var uv := data.to_uv(data.objective_positions[i])
	var p := to_px(r, uv)
	var extract: bool = data.objective_kinds[i] == &"extract"
	var col: Color = COL_WARN if extract else COL_CRIT
	var w := 2.0 * s
	# A finished objective goes grey and gets a tick. Leaving it red would make
	# the map say "go here" about somewhere you have already taken.
	if done:
		col = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.75)
		ci.draw_line(p + Vector2(-7, 0) * s, p + Vector2(-2, 6) * s, col, w)
		ci.draw_line(p + Vector2(-2, 6) * s, p + Vector2(8, -7) * s, col, w)

	ci.draw_arc(p, 16.0 * s, 0.0, TAU, 32, col, w)
	ci.draw_arc(p, 7.0 * s, 0.0, TAU, 20, col, w)
	if extract:
		# Extraction gets a cross as well as a ring: it is the one marker that
		# means "leave", and it must not read as another target.
		ci.draw_line(p + Vector2(-11, 0) * s, p + Vector2(11, 0) * s, col, w)
		ci.draw_line(p + Vector2(0, -11) * s, p + Vector2(0, 11) * s, col, w)

	draw_marker_label(ci, font, r, p, uv, text, col, s)


# Label below a marker in the top half, above one in the bottom half.
# Always-below put "WEST GARRISON" straight through the ring of the objective
# underneath it, and the valley's relays sit close together.
static func draw_marker_label(ci: CanvasItem, font: Font, r: Rect2, p: Vector2, uv: Vector2,
		text: String, col: Color, s: float = 1.0) -> void:
	if text == "":
		return
	draw_label(ci, font, marker_label_at(font, r, p, uv, text, s), text, col, s)


## Where draw_marker_label puts a label: the left end of its baseline.
static func marker_label_at(font: Font, r: Rect2, p: Vector2, uv: Vector2, text: String,
		s: float = 1.0) -> Vector2:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size(s)).x
	var below: bool = uv.y < 0.5
	var pos := p + Vector2(-w * 0.5, (36.0 if below else -24.0) * s)
	# Keep the name inside the map rather than letting it run off the edge.
	pos.x = clampf(pos.x, r.position.x + 4.0, maxf(r.position.x + 4.0, r.end.x - w - 4.0))
	pos.y = clampf(pos.y, r.position.y + 18.0 * s, r.end.y - 6.0)
	return pos


## A marker's label with its drop shadow, baseline starting at `pos`. For a
## caller that places labels itself, like the map board sorting out a crowd.
static func draw_label(ci: CanvasItem, font: Font, pos: Vector2, text: String, col: Color,
		s: float = 1.0) -> void:
	var size := label_size(s)
	ci.draw_string(font, pos + Vector2(1, 1) * s, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.9))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func label_size(s: float = 1.0) -> int:
	return int(round(16.0 * s))


# WHERE YOU COME IN. Green because it is ours — every objective is red or
# amber — and a solid diamond rather than a ring, so it can never read as one
# more thing to capture. Anything right of `sweep` (0-1 across the map) is not
# drawn yet, so the briefing's sweep reveals it with everything else.
static func draw_insertion(ci: CanvasItem, font: Font, r: Rect2, data: MinimapData,
		sweep: float = 1.0, s: float = 1.0) -> void:
	var col := Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.9)
	var labelled: Array[Vector2] = []
	for pos in data.insertion_positions:
		var uv := data.to_uv(pos)
		if uv.x > sweep:
			continue
		var p := to_px(r, uv)
		var d := 8.0 * s
		ci.draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), col)
		ci.draw_arc(p, 15.0 * s, 0.0, TAU, 28,
			Color(COL_BRIGHT.r, COL_BRIGHT.g, COL_BRIGHT.b, 0.5), 1.5 * s)
		# One word per landing zone. A squad pad a few metres off the spawn
		# printed INSERTION twice over itself, which reads as a smudge.
		if labelled.any(func(q: Vector2) -> bool: return q.distance_to(p) < INSERTION_ONE_SPOT * s):
			continue
		labelled.append(p)
		draw_marker_label(ci, font, r, p, uv, "INSERTION", col, s)
