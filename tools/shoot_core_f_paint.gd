extends SceneTree

# ─────────────────────────────────────────────
# WHERE THE FACTION COLOUR IS — the F variants, whole against paint-only.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_core_f_paint.gd -- <out dir>
#
# WHY THIS SHEET EXISTS, and it is a fault in the last one. core_f_variants.png
# shows five bases and they read — but A PAINTED FIN AND AN UNPAINTED ONE DRAW
# IDENTICALLY IN THIS LINE ART. The numbers said F2 was 86.8% painted and F4
# 39.7%; the picture said nothing at all, which is useless for judging the one
# note this round was convened about ("lots of places to have faction colour").
#
# So each row here is THE SAME BUILD TWICE: the whole variant, and then only
# the parts named `Paint_*`. Stripped of the grey structure the painted set
# becomes a floating constellation, and that is what shows at a glance whether
# the colour is a thin ring round the foot or a set of fins running the full
# height — the difference CORE_F_VARIANTS.md §6 identified and could not show.
#
# A FILTER OVER THE SAME BUILD, NOT A SECOND SET OF GEOMETRY. The paint-only
# cell calls the same builder and then deletes every VisualInstance3D whose
# name does not begin with `Paint`. The two cells cannot drift, because there
# is only one description of the variant.
#
# THE TWO CELLS ARE ONE PHOTOGRAPH, which is the whole point of the comparison:
# they stand on one ground plane, are shot with one camera, and are therefore
# at true common scale. A height in the right-hand cell is the same height in
# the left-hand one.
#
# THE FILL, and this is the one trick in the file. IconStudio.render_body's
# last argument fills the outline solid. Outlines are right for the structure
# cell — you have to see what is painted ON — and solid is right for the paint
# cell, because a colour zone is an AREA and a hollow outline of one reads as a
# wire frame of nothing. They are different values of one per-render argument,
# so the row is RENDERED TWICE, identically, and composited: the structure cell
# comes out of the fill-0 pass and the paint cell out of the fill-1 pass.
#
# The two passes register pixel for pixel because the bodies are built from the
# same deterministic builders and are therefore the same bounds and the same
# camera. The seam is computed, not eyeballed: _split_px replicates
# IconStudio._aim — same yaw, pitch, distance, PAD and orthographic fit — and
# projects the world x halfway down the gap between the cells. If that number
# is ever wrong the symptom is obvious and local, which is why it is worth
# computing rather than guessing.
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _CK := preload("res://tools/concept_kit.gd")
const _Cores := preload("res://tools/concepts_core_f.gd")

const SHOT_H := 620
const LABEL_H := 44
const SHEET_BG := Color(0.043, 0.071, 0.063)
const GAP := 6.0            ## metres of clear ground between cells
const WALKER_H := 3.81
const PAINT_PREFIX := "Paint"

## IconStudio's own numbers, needed to reproduce its framing for the seam.
const CAM_YAW := 35.0
const CAM_PITCH := 15.0
const STUDIO_PAD := 0.06

var _studio: Node
var _walker_scale := 1.0

## Pass `outline` as a second argument to draw the paint cells in outline too,
## and write the sheet with an `_outline` suffix. That is the comparison the
## fill decision was made on rather than guessed at: run it both ways, look at
## both, keep the one that reads. The answer was solid, and CORE_F_VARIANTS.md
## §0 says why, but the losing sheet should be reproducible or the claim is
## just an assertion.
var _paint_fill := 1.0
var _suffix := ""


func _initialize() -> void:
	_run.call_deferred()


## Rows, as [label, cells]. A cell is [builder, paint_only, walker].
##
## THE FIRST FIVE ARE THE DELIVERABLE: every variant's MEDIUM, whole against
## paint-only.
##
## THE LAST TWO ARE THERE FOR A REASON AND NOT FOR COMPLETENESS. §6 of
## CORE_F_VARIANTS.md found that colour share falls with size in all five, and
## that the two which fall least are the two whose zones run VERTICALLY rather
## than ringing the foot. F2 and F3 are those two, and that claim is about how
## the colour SCALES — which a single medium cannot show and three paint-only
## cells can. The other three have no scale story: their zones are the same
## ring on a taller tower.
func _rows() -> Array:
	return [
		["F1 APRON   whole / paint only   lip, collar, pilasters",
			[[_Cores.f1_medium, false, true], [_Cores.f1_medium, true, false]]],
		["F2 RAFT   whole / paint only   four full-height fins",
			[[_Cores.f2_medium, false, true], [_Cores.f2_medium, true, false]]],
		["F3 DAIS   whole / paint only   riser bands, bays, lintel",
			[[_Cores.f3_medium, false, true], [_Cores.f3_medium, true, false]]],
		["F4 WELL   whole / paint only   kerb cap, runs, lamp",
			[[_Cores.f4_medium, false, true], [_Cores.f4_medium, true, false]]],
		["F5 BUTTRESS   whole / paint only   shoulders, caps, banner",
			[[_Cores.f5_medium, false, true], [_Cores.f5_medium, true, false]]],
		["F2 PAINT ONLY at all three sizes   does the colour climb with the core",
			[[_Cores.f2_small, true, false], [_Cores.f2_medium, true, false],
				[_Cores.f2_large, true, false]]],
		["F3 PAINT ONLY at all three sizes   the bay count is itself a size cue",
			[[_Cores.f3_small, true, false], [_Cores.f3_medium, true, false],
				[_Cores.f3_large, true, false]]],
	]


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_core_f_paint: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("shoot_core_f_paint: <out dir>")
		quit(1)
		return
	var out_dir: String = args[0]
	if args.size() > 1 and String(args[1]) == "outline":
		_paint_fill = 0.0
		_suffix = "_outline"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	_studio = _Studio.new()
	root.add_child(_studio)
	await _calibrate_walker()

	var sheet_rows: Array = []
	for row in _rows():
		var label: String = row[0]
		var cells: Array = row[1]
		var boxes: Array = []
		print("  %-62s     W     H     L" % label)
		for c: Array in cells:
			var bb := await _cell_bounds(c)
			boxes.append(bb)
			print("    %-22s %5.2f %5.2f %5.2f"
					% ["paint only" if bool(c[1]) else "whole",
							bb.size.x, bb.size.y, bb.size.z])
		var img := await _render_pair(cells, boxes)
		sheet_rows.append([label, img])
		var one := "%s/core_f_paint_%s%s.png" % [out_dir, label.substr(0, 2).to_lower(), _suffix]
		if label.begins_with("F2 PAINT"):
			one = "%s/core_f_paint_f2_sizes%s.png" % [out_dir, _suffix]
		elif label.begins_with("F3 PAINT"):
			one = "%s/core_f_paint_f3_sizes%s.png" % [out_dir, _suffix]
		_save(await _with_label(img, label, img.get_width() if img != null else SHOT_H), one)
		print("shoot_core_f_paint: %s" % ProjectSettings.globalize_path(one))

	var sheet := await _sheet(sheet_rows)
	var path := "%s/core_f_paint%s.png" % [out_dir, _suffix]
	_save(sheet, path)
	print("shoot_core_f_paint: %s" % ProjectSettings.globalize_path(path))
	quit(0)


# ─────────────────────────────────────────────
# THE FILTER
# ─────────────────────────────────────────────

## Delete everything that is not faction-painted.
##
## It does not descend into a kept node: a painted part's own children belong
## to it. And it REMOVES BEFORE IT FREES, because queue_free is deferred — a
## node freed but still parented is still in the tree for the frame the bounds
## are measured on, which would quietly put the grey structure back into a
## paint-only cell's box.
func _paint_filter(root_node: Node) -> void:
	var doomed: Array = []
	_find_doomed(root_node, doomed)
	if doomed.is_empty():
		push_warning("_paint_filter: nothing to strip, so this cell is not a paint-only cell")
	for n: Node in doomed:
		var p := n.get_parent()
		if p != null:
			p.remove_child(n)
		n.queue_free()


func _find_doomed(n: Node, out: Array) -> void:
	if n is VisualInstance3D:
		if String(n.name).begins_with(PAINT_PREFIX):
			return
		out.append(n)
		return
	for c in n.get_children():
		_find_doomed(c, out)


# ─────────────────────────────────────────────
# MEASURING
# ─────────────────────────────────────────────

func _calibrate_walker() -> void:
	var w := Node3D.new()
	_build_walker(w)
	root.add_child(w)
	await process_frame
	await process_frame
	var bb := _bounds(w, w)
	_walker_scale = WALKER_H / maxf(bb.size.y, 0.001)
	print("shoot_core_f_paint: walker reference %.2f m -> scaled x%.3f to %.2f m"
			% [bb.size.y, _walker_scale, WALKER_H])
	w.queue_free()


func _build_cell(cell: Array, into: Node3D) -> void:
	(cell[0] as Callable).call(into)
	if bool(cell[1]):
		_paint_filter(into)


func _cell_bounds(cell: Array) -> AABB:
	var body := Node3D.new()
	_build_cell(cell, body)
	root.add_child(body)
	await process_frame
	await process_frame
	var bb := _bounds(body, body)
	root.remove_child(body)
	body.queue_free()
	return bb


## SUBTRACTION SHAPES DO NOT COUNT — they are deliberately oversized.
func _bounds(n: Node, body: Node3D) -> AABB:
	if n is CSGShape3D and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
		return AABB()
	var out := AABB()
	var started := false
	for c in n.get_children():
		var sub := _bounds(c, body)
		if sub.size != Vector3.ZERO:
			out = sub if not started else out.merge(sub)
			started = true
	if n is VisualInstance3D:
		var local := body.global_transform.affine_inverse() * (n as VisualInstance3D).global_transform
		var a := local * (n as VisualInstance3D).get_aabb()
		out = a if not started else out.merge(a)
	return out


# ─────────────────────────────────────────────
# THE ROW
# ─────────────────────────────────────────────

## One row body. Returns the body and the world x of each gap between cells, so
## the compositor knows where the structure cell stops and the paint cell
## starts without measuring the picture.
func _row_body(cells: Array, boxes: Array) -> Array:
	var body := Node3D.new()
	var cursor := 0.0
	var gaps: Array = []
	# LARGE FIRST, ALONG +X — the three-quarter camera sits 35 degrees round to
	# the model's right, which puts +X on the LEFT of the picture, so the list's
	# first entry has to be built LAST to end up leftmost.
	for i in range(cells.size() - 1, -1, -1):
		var bb: AABB = boxes[i]
		var holder := Node3D.new()
		holder.position = Vector3(cursor - bb.position.x, 0, 0)
		body.add_child(holder)
		_build_cell(cells[i], holder)
		if bool(cells[i][2]):
			var w := Node3D.new()
			w.scale = Vector3.ONE * _walker_scale
			w.position = Vector3(cursor + bb.size.x + 1.7, 0, bb.position.z - 0.6)
			body.add_child(w)
			_build_walker(w)
		cursor += bb.size.x
		if i > 0:
			gaps.push_front(cursor + GAP * 0.5)
		cursor += GAP
	return [body, gaps]


## Two passes, one seam. See the header: the structure cell wants outlines and
## the paint cell wants solid, and fill is a per-render argument, so the row is
## drawn twice from two identical builds and cut.
func _render_pair(cells: Array, boxes: Array) -> Image:
	var made := _row_body(cells, boxes)
	var body: Node3D = made[0]
	var gaps: Array = made[1]
	root.add_child(body)
	await process_frame
	await process_frame
	var bounds := _bounds(body, body)
	var shot := _shot_size(bounds)
	root.remove_child(body)
	var outline: Image = await _studio.render_body(body, shot,
			_Studio.Framing.THREE_QUARTER, false, false, 0.0)

	# Any cell that is paint-only wants the filled pass. If there is nothing to
	# fill — a row of all-structure cells — one pass is the answer and a second
	# render would be a minute of nothing.
	var wants_fill := false
	for c: Array in cells:
		if bool(c[1]):
			wants_fill = true
	if not wants_fill or outline == null:
		return outline

	var again := _row_body(cells, boxes)
	var body2: Node3D = again[0]
	root.add_child(body2)
	await process_frame
	await process_frame
	root.remove_child(body2)
	var filled: Image = await _studio.render_body(body2, shot,
			_Studio.Framing.THREE_QUARTER, false, false, _paint_fill)
	if filled == null:
		push_warning("_render_pair: the filled pass drew nothing, so this row is outlines throughout")
		return outline
	return _composite(outline, filled, cells, gaps, bounds, shot)


## Cut the two passes together. Walking the cells left to right, each one takes
## its pixels from whichever pass suits it, and the boundaries are the PROJECTED
## gaps — computed from the camera, not found by looking at the image.
func _composite(outline: Image, filled: Image, cells: Array, gaps: Array,
		bounds: AABB, shot: Vector2i) -> Image:
	if outline.get_format() != Image.FORMAT_RGBA8:
		outline.convert(Image.FORMAT_RGBA8)
	if filled.get_format() != Image.FORMAT_RGBA8:
		filled.convert(Image.FORMAT_RGBA8)
	var out := Image.create(shot.x, shot.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	# Cell i's pixel band, in list order (left to right on the page).
	var edges: Array = [0]
	for g in gaps:
		edges.append(_split_px(bounds, shot, float(g)))
	edges.append(shot.x)
	for i in cells.size():
		var x0: int = clampi(int(edges[i]), 0, shot.x)
		var x1: int = clampi(int(edges[i + 1]), 0, shot.x)
		if x1 <= x0:
			push_warning("_composite: cell %d got no pixels, so the seam is in the wrong place" % i)
			continue
		var src: Image = filled if bool(cells[i][1]) else outline
		var band := Rect2i(x0, 0, x1 - x0, shot.y)
		out.blit_rect(src, band, Vector2i(x0, 0))
	return out


## The image column a world x falls in, reproducing IconStudio._aim exactly:
## same yaw and pitch, the same distance of radius * 3 + 1, the same
## orthographic fit of max(span.y, span.x / aspect) / (1 - 2 * PAD), and the
## camera centred on the bounds. Guessing this put the seam through the model
## in the first pass; it is twenty lines and it is right.
##
## z MATTERS AND y DOES NOT. The camera's right axis is UP x toward, which has
## no Y component, so a point's image column depends only on its world x and z.
## The gap is taken at the bounds' own centre z, which is why the cells need
## real clear ground between them rather than a token metre.
func _split_px(bounds: AABB, shot: Vector2i, world_x: float) -> int:
	var to_view := _view_of(bounds).affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = to_view * bounds.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	var aspect: float = float(shot.x) / float(shot.y)
	var cam_size: float = maxf(span.y, span.x / aspect) / (1.0 - STUDIO_PAD * 2.0)
	var c := bounds.get_center()
	var v: Vector3 = to_view * Vector3(world_x, c.y, c.z)
	return int(round(float(shot.x) * 0.5 + v.x * float(shot.x) / (cam_size * aspect)))


func _view_of(bounds: AABB) -> Transform3D:
	var yaw := deg_to_rad(CAM_YAW)
	var pitch := deg_to_rad(CAM_PITCH)
	var toward := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var c := bounds.get_center()
	var dist: float = maxf(bounds.size.length() * 0.5, 0.001) * 3.0 + 1.0
	return Transform3D(Basis.IDENTITY, c + toward * dist).looking_at(c, Vector3.UP)


func _shot_size(box: AABB) -> Vector2i:
	var to_view := _view_of(box).affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = to_view * box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	var aspect: float = clampf(span.x / maxf(span.y, 0.001), 0.8, 4.0)
	return Vector2i(int(round(SHOT_H * aspect)), SHOT_H)


func _build_walker(to: Node3D) -> void:
	_CK.hull(to, _CK.W_HULL, Vector3(0, 0.3, 0))
	_CK.head(to, Vector3(0, 0.76, 0), 1.0)
	for sx: float in [-1.0, 1.0]:
		_CK.leg(to, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)
	to.position.y += 1.95


# ─────────────────────────────────────────────
# PAGE
# ─────────────────────────────────────────────

func _with_label(img: Image, text: String, page_w: int) -> Image:
	var out := Image.create(page_w, SHOT_H + LABEL_H, false, Image.FORMAT_RGBA8)
	out.fill(SHEET_BG)
	if img != null:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i((page_w - img.get_width()) / 2, 0))
	var label: Image = await _label_image(text, page_w)
	out.blend_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
			Vector2i(0, SHOT_H + 4))
	return out


func _sheet(rows: Array) -> Image:
	var page_w := 0
	for r in rows:
		if r[1] != null:
			page_w = maxi(page_w, (r[1] as Image).get_width())
	var cell := SHOT_H + LABEL_H
	var sheet := Image.create(page_w, cell * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in rows.size():
		var one: Image = await _with_label(rows[i][1], str(rows[i][0]), page_w)
		sheet.blend_rect(one, Rect2i(Vector2i.ZERO, one.get_size()), Vector2i(0, i * cell))
	return sheet


func _label_image(text: String, page_w: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(page_w, 34)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _Kit.FONT_BODY)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(l)
	root.add_child(vp)
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, path: String) -> void:
	if img == null:
		printerr("shoot_core_f_paint: nothing to write to %s" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_core_f_paint: could not write %s (%s)" % [path, error_string(err)])
