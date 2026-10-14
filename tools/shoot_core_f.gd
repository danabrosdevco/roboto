extends SceneTree

# ─────────────────────────────────────────────
# RENDER THE COMPUTE CORE SHEET — F REFINED.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_core_f.gd -- <out dir>
#
# WHY THIS IS A COPY OF shoot_cores2.gd AND NOT AN EDIT OF IT. Same reason
# shoot_cores2 is a copy of shoot_cores: round two's renderer is right, it
# hard-codes round two's builder file, it is committed work in a shared
# checkout, and re-pointing it would make round two's sheets unreproducible. So
# it is a SIBLING. Its contract is carried over unchanged and it IS the point:
#
#   A ROW IS ONE PHOTOGRAPH WITH ONE CAMERA. All three sizes of a variant are
#   built into a single body, stood side by side on one ground plane, and shot
#   once — so within a row the three sizes are at TRUE COMMON SCALE and the
#   4.2 m core is small on the page because it is small. A renderer that fits
#   each cell to its own bounds would answer "no, the sizes do not read" by
#   construction, which is the fault shoot_concepts.gd's comment is about.
#
#   AND A WALKER STANDS AT EVERY APPROACH FACE. 3.81 m as it ships, measured
#   and scaled rather than assumed. It is a test and not just a ruler: if the
#   figure ends up standing in something, that variant has no approachable face.
#
# ONE THING IS NEW, and it is the thing this round was convened about.
# _paint_share() measures how much of each variant is FACTION-PAINTED. The
# builders tag every painted part `Paint_<tag>` (ConceptsCoreF._paint), and this
# walks for that prefix, projects each painted part's box onto the camera's own
# axes, and prints the total against the whole body's projected box.
#
# WHAT THAT NUMBER IS AND IS NOT. It is a PROJECTED-BOX SHARE, not a silhouette
# area: each painted part contributes its own projected bounding rectangle, and
# those are summed. The painted zones in these five variants are spatially
# disjoint by construction — a lip, a collar and two pilasters never overlap —
# so the sum is close to the union, but a part seen end-on still contributes
# its full box and perspective can overlap two of them. Treat it as a
# comparable figure between variants, which is what it is for, and not as a
# pixel count. It is still a measurement and not an estimate, which is the
# standard this project holds concept numbers to.
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _CK := preload("res://tools/concept_kit.gd")
const _Cores := preload("res://tools/concepts_core_f.gd")

const SHOT_H := 620         ## every row is this tall; its width follows the row
const LABEL_H := 44
const SHEET_BG := Color(0.043, 0.071, 0.063)
const GAP := 5.0            ## metres of clear ground between sizes
const WALKER_H := 3.81      ## the Walker as it ships, and the only true ruler here
const PAINT_PREFIX := "Paint"

## The camera the icon studio aims with. Duplicated here because the paint
## share and the frame shape both have to be computed in the camera's own
## axes, and guessing them would make both numbers fiction.
const CAM_YAW := 35.0
const CAM_PITCH := 15.0

var _studio: Node
var _walker_scale := 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_core_f: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("shoot_core_f: <out dir>")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	_studio = _Studio.new()
	root.add_child(_studio)

	await _calibrate_walker()

	var rows: Array = []
	for row in _Cores.sets():
		var label: String = row[0]
		var builders: Array = [row[1], row[2], row[3]]
		print("  %-50s    W     H     L    PAINT  ZONES" % label)
		var boxes: Array = []
		for i in 3:
			var m := await _measure(builders[i])
			boxes.append(m["box"])
			var bb: AABB = m["box"]
			print("    %-34s %5.2f %5.2f %5.2f   %4.1f%%  %s"
					% [["small", "medium", "large"][i], bb.size.x, bb.size.y, bb.size.z,
							float(m["share"]) * 100.0, str(m["zones"])])
		var img := await _render_row(builders, boxes)
		rows.append([label, img])
		var one := "%s/core_f_%s.png" % [out_dir, label.substr(0, 2).to_lower()]
		_save(await _with_label(img, label, img.get_width() if img != null else SHOT_H), one)
		print("shoot_core_f: %s" % ProjectSettings.globalize_path(one))

	# THE OCCLUSION ROW. The cap is identical in all five, so this is not asking
	# whether the drone fits — round two settled that. It asks what colour is
	# LEFT once a 3.23 m drone is clamped over the top of the core, which is the
	# question "lots of places to have faction colour" actually raises.
	var tick_label := "TICK SEATED ON EVERY MEDIUM  what colour survives the hack"
	var tick_builders: Array = []
	var tick_boxes: Array = []
	print("  %-50s    W     H     L    PAINT  ZONES" % tick_label)
	for t in _Cores.tick_set():
		tick_builders.append(t[1])
		var m := await _measure(t[1] as Callable)
		tick_boxes.append(m["box"])
		var bb: AABB = m["box"]
		print("    %-34s %5.2f %5.2f %5.2f   %4.1f%%  %s"
				% [t[0], bb.size.x, bb.size.y, bb.size.z,
						float(m["share"]) * 100.0, str(m["zones"])])
	var tick_img := await _render_row(tick_builders, tick_boxes)
	rows.append([tick_label, tick_img])
	var tpath := "%s/core_f_tick.png" % out_dir
	_save(await _with_label(tick_img, tick_label,
			tick_img.get_width() if tick_img != null else SHOT_H), tpath)
	print("shoot_core_f: %s" % ProjectSettings.globalize_path(tpath))

	var sheet := await _sheet(rows)
	var path := "%s/core_f_variants.png" % out_dir
	_save(sheet, path)
	print("shoot_core_f: %s" % ProjectSettings.globalize_path(path))
	quit(0)


# ─────────────────────────────────────────────
# MEASURING
# ─────────────────────────────────────────────

## The Walker reference is concept_kit geometry, drawn at the kit's own scale
## and NOT in metres. Measure it once and work out the factor that puts it at
## 3.81, or the ruler on this sheet is a lie.
func _calibrate_walker() -> void:
	var w := Node3D.new()
	_build_walker(w)
	root.add_child(w)
	await process_frame
	await process_frame
	var bb := _bounds(w, w)
	_walker_scale = WALKER_H / maxf(bb.size.y, 0.001)
	print("shoot_core_f: walker reference %.2f m -> scaled x%.3f to %.2f m"
			% [bb.size.y, _walker_scale, WALKER_H])
	w.queue_free()


## Build once, and take BOTH numbers off the same body: its measured box and
## its painted share. Building it twice would be two bodies and two chances for
## them to disagree.
func _measure(build: Callable) -> Dictionary:
	var body := Node3D.new()
	build.call(body)
	root.add_child(body)
	await process_frame
	await process_frame
	var bb := _bounds(body, body)
	var painted: Array = []
	_collect_paint(body, body, painted)
	var zones := {}
	var paint_area := 0.0
	for e: Array in painted:
		paint_area += _projected_area(e[1] as AABB)
		var tag: String = String(e[0])
		zones[tag] = int(zones.get(tag, 0)) + 1
	var whole: float = _projected_area(bb)
	body.queue_free()
	if painted.is_empty():
		push_warning("_measure: nothing named '%s*' in this body, so it has no faction colour at all" % PAINT_PREFIX)
	return {
		"box": bb,
		"share": paint_area / maxf(whole, 0.0001),
		"zones": zones,
	}


## Every painted part, as [tag, AABB in the body's frame]. The tag is the part
## name with the prefix and Godot's uniquifying suffix taken off, so four fins
## count as four parts of one zone rather than as four zones.
func _collect_paint(n: Node, body: Node3D, out: Array) -> void:
	if n is CSGShape3D and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
		return
	if n is VisualInstance3D and String(n.name).begins_with(PAINT_PREFIX):
		var local := body.global_transform.affine_inverse() * (n as VisualInstance3D).global_transform
		var tag: String = String(n.name).substr(PAINT_PREFIX.length() + 1).rstrip("0123456789")
		out.append([tag, local * (n as VisualInstance3D).get_aabb()])
	for c in n.get_children():
		_collect_paint(c, body, out)


## A box's area as the camera sees it. Projected onto the camera's own right
## and up axes, which is the only projection that corresponds to the picture —
## a box's X times Y is the elevation, and nothing on this sheet is shot in
## elevation.
func _projected_area(box: AABB) -> float:
	if box.size == Vector3.ZERO:
		return 0.0
	var span := _projected_span(box)
	return span.x * span.y


func _projected_span(box: AABB) -> Vector2:
	var yaw := deg_to_rad(CAM_YAW)
	var pitch := deg_to_rad(CAM_PITCH)
	var toward := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3.UP.cross(toward).normalized()
	var up := toward.cross(right).normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.dot(right)), minf(lo.y, p.dot(up)))
		hi = Vector2(maxf(hi.x, p.dot(right)), maxf(hi.y, p.dot(up)))
	return hi - lo


## SUBTRACTION SHAPES DO NOT COUNT — they are deliberately oversized, and
## counting them put an earlier sheet's Walker at 3.3 m wide when its hull is
## 1.5.
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
# BUILDING THE ROW
# ─────────────────────────────────────────────

func _render_row(builders: Array, boxes: Array) -> Image:
	var body := Node3D.new()
	var cursor := 0.0
	# LARGE FIRST, ALONG +X. The three-quarter camera sits 35 degrees round to
	# the model's right, which puts +X on the LEFT of the picture — built
	# small-first the row reads large-to-small, backwards from every size chart
	# anyone has seen. Reversed by count, not by a hard-coded [2, 1, 0]: the
	# tick row has five cells.
	for i in range(builders.size() - 1, -1, -1):
		var bb: AABB = boxes[i]
		var holder := Node3D.new()
		holder.position = Vector3(cursor - bb.position.x, 0, 0)
		body.add_child(holder)
		(builders[i] as Callable).call(holder)
		var w := Node3D.new()
		w.scale = Vector3.ONE * _walker_scale
		# At the front corner, clear of the footprint. Dead in front it is
		# geometrically honest and photographs as a figure standing ON the
		# thing: the three-quarter view projects 2 m of ground to almost
		# nothing.
		w.position = Vector3(cursor + bb.size.x + 1.7, 0, bb.position.z - 0.6)
		body.add_child(w)
		_build_walker(w)
		cursor += bb.size.x + GAP
	root.add_child(body)
	await process_frame
	await process_frame
	var shot := _shot_size(_bounds(body, body))
	root.remove_child(body)
	return await _studio.render_body(body, shot, _Studio.Framing.THREE_QUARTER,
			false, false, 0.0)


## THE SHOT HAS TO FIT THE ROW, not the other way round. The studio fits a body
## by whichever of height and width is tighter, so a fixed frame on a row that
## is 19 m across and 17 m tall in view fits by HEIGHT and throws away two
## thirds of the page.
func _shot_size(box: AABB) -> Vector2i:
	var span := _projected_span(box)
	var aspect: float = clampf(span.x / maxf(span.y, 0.001), 0.8, 4.0)
	return Vector2i(int(round(SHOT_H * aspect)), SHOT_H)


## The Walker as it ships, out of concept_kit — the same reference every other
## concept sheet in this project uses.
func _build_walker(to: Node3D) -> void:
	_CK.hull(to, _CK.W_HULL, Vector3(0, 0.3, 0))
	_CK.head(to, Vector3(0, 0.76, 0), 1.0)
	for sx: float in [-1.0, 1.0]:
		_CK.leg(to, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)
	# Dropped so the feet land on y = 0 rather than the hull's origin. The kit
	# builds a Walker about its waist; everything else here is built off the
	# ground, and a figure floating 1.8 m up would ruin the one thing the figure
	# is here for.
	to.position.y += 1.95


# ─────────────────────────────────────────────
# PAGE
# ─────────────────────────────────────────────

## Row plus its caption, on a page `page_w` wide. Rows have different widths
## because they have different shapes, so the narrow ones are CENTRED rather
## than stretched.
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
		printerr("shoot_core_f: nothing to write to %s" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_core_f: could not write %s (%s)" % [path, error_string(err)])
