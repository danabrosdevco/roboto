extends SceneTree

# ─────────────────────────────────────────────
# RENDER THE COMPUTE CORE CONCEPT SHEET — ROUND TWO.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_cores2.gd -- <out dir>
#
# WHY THIS IS A COPY OF shoot_cores.gd AND NOT AN EDIT OF IT. Round one's
# renderer is right and nothing in it needed changing — but it hard-codes
# round one's builder file, it is another lane's committed work in a shared
# checkout, and re-pointing it would make round one's sheets unreproducible.
# So it is a SIBLING. Two things are added, both of them about the hack drone:
# a sixth row that seats TICK on the medium of every concept, and a per-row
# print of the cap heights so the seats can be checked against the geometry
# rather than against the drawing.
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
#
# WHY THIS IS NOT shoot_concepts.gd WITH MORE COLUMNS. That script renders one
# body per cell and the icon studio FITS EVERY BODY TO ITS OWN BOUNDS — a
# 0.4 m grenade and a 4 m Walker come out the same size on the page. For a
# frame sheet that is correct: you are judging shape, and shape is all the cell
# has to carry. Here the whole question is whether three sizes of the same
# object read as three sizes, and a renderer that normalises size cannot answer
# it. It would, in fact, answer "no" every time, by construction.
#
# So a ROW IS ONE PHOTOGRAPH. All three sizes of a concept are built into a
# single body, stood side by side on one ground plane, and shot with one
# camera. Within a row the proportions are true, and the 4.2 is small on the
# page because it is small.
#
# AND A WALKER STANDS IN FRONT OF EVERY ONE OF THEM. The Walker ships at
# 3.81 m; concept_kit's reference build is drawn at its own scale, so it is
# measured here and scaled to 3.81 before being placed. It is put at the
# APPROACH FACE, front and centre, which also makes the brief's disqualifying
# rule visible: if there is nowhere for that figure to stand and face, the
# concept is out.
#
# The sheet is written whole, and each row is also written on its own, because
# a 1600 x 3000 sheet is unreadable once anything downsamples it.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")
const _CK := preload("res://tools/concept_kit.gd")
const _Cores := preload("res://tools/concepts_core2.gd")

const SHOT_H := 620         ## every row is this tall; its width follows the row
const LABEL_H := 44
const SHEET_BG := Color(0.043, 0.071, 0.063)
const GAP := 5.0            ## metres of clear ground between sizes
const WALKER_H := 3.81      ## the Walker as it ships, and the only true ruler here

## The shipped cores, measured alongside so the concepts are compared with the
## thing they would replace and not with a memory of it.
const STOCK := [
	"res://maps/blocks/compute/compute_core_small.tscn",
	"res://maps/blocks/compute/compute_core.tscn",
	"res://maps/blocks/compute/compute_core_large.tscn",
]

var _studio: Node
var _walker_scale := 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_cores2: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("shoot_cores2: <out dir>")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	_studio = _Studio.new()
	root.add_child(_studio)

	await _calibrate_walker()
	await _measure_stock()

	var rows: Array = []
	for row in _Cores.sets():
		var label: String = row[0]
		var builders: Array = [row[1], row[2], row[3]]
		print("  %-44s     W     H     L   (metres)" % label)
		var boxes: Array = []
		for i in 3:
			var bb := await _bounds_of(builders[i])
			boxes.append(bb)
			print("    %-8s %28s %5.2f %5.2f %5.2f"
					% [["small", "medium", "large"][i], "", bb.size.x, bb.size.y, bb.size.z])
		var img := await _render_row(builders, boxes)
		rows.append([label, img])
		var one := "%s/core2_%s.png" % [out_dir, label.substr(0, 1).to_lower()]
		_save(await _with_label(img, label, img.get_width() if img != null else SHOT_H), one)
		print("shoot_cores2: %s" % ProjectSettings.globalize_path(one))

	# THE ROW THIS ROUND EXISTS FOR. The chosen hack drone, seated on the medium
	# of all five, in ONE photograph with ONE camera — so the five are at a true
	# common scale and the Tick is the same object five times. Claiming a fit in
	# prose is what round one could have done; this is the fit.
	var tick_label := "TICK SEATED ON EVERY MEDIUM  one camera, true common scale"
	var tick_builders: Array = []
	var tick_boxes: Array = []
	print("  %-44s     W     H     L   (metres)" % tick_label)
	for t in _Cores.tick_set():
		tick_builders.append(t[1])
		var bb := await _bounds_of(t[1] as Callable)
		tick_boxes.append(bb)
		print("    %-36s %5.2f %5.2f %5.2f" % [t[0], bb.size.x, bb.size.y, bb.size.z])
	var tick_img := await _render_row(tick_builders, tick_boxes)
	rows.append([tick_label, tick_img])
	var tpath := "%s/core2_tick.png" % out_dir
	_save(await _with_label(tick_img, tick_label,
			tick_img.get_width() if tick_img != null else SHOT_H), tpath)
	print("shoot_cores2: %s" % ProjectSettings.globalize_path(tpath))

	var sheet := await _sheet(rows)
	var path := "%s/compute_cores_2.png" % out_dir
	_save(sheet, path)
	print("shoot_cores2: %s" % ProjectSettings.globalize_path(path))
	quit(0)


# ─────────────────────────────────────────────
# MEASURING
# ─────────────────────────────────────────────

## The Walker reference is concept_kit geometry, which is drawn at the kit's
## own scale and NOT in metres. Measure it once and work out the factor that
## puts it at 3.81 m, or the ruler on this sheet is a lie — which is the exact
## failure shoot_concepts.gd's _measure comment was written about.
func _calibrate_walker() -> void:
	var w := Node3D.new()
	_build_walker(w)
	root.add_child(w)
	await process_frame
	await process_frame
	var bb := _bounds(w, w)
	_walker_scale = WALKER_H / maxf(bb.size.y, 0.001)
	print("shoot_cores2: walker reference %.2f m -> scaled x%.3f to %.2f m"
			% [bb.size.y, _walker_scale, WALKER_H])
	w.queue_free()


func _measure_stock() -> void:
	print("  SHIPPED CORES (what is there today)       W     H     L   (metres)")
	for p in STOCK:
		if not ResourceLoader.exists(p):
			printerr("    missing %s" % p)
			continue
		var inst := (load(p) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		await process_frame
		await process_frame
		var bb := _bounds(inst, inst)
		print("    %-36s %5.2f %5.2f %5.2f"
				% [p.get_file().get_basename(), bb.size.x, bb.size.y, bb.size.z])
		inst.queue_free()


func _bounds_of(build: Callable) -> AABB:
	var body := Node3D.new()
	build.call(body)
	root.add_child(body)
	await process_frame
	await process_frame
	var bb := _bounds(body, body)
	body.queue_free()
	return bb


## SUBTRACTION SHAPES DO NOT COUNT — they are deliberately oversized (a shear
## cut is 3x the body so it slices clean through), and counting them put an
## earlier sheet's Walker at 3.3 m wide when its hull is 1.5.
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

## Three sizes on one ground plane, left to right, each with a Walker standing
## at its approach face. Laid out from the MEASURED boxes, not from the numbers
## the builders were written to, so an overrun shows as a collision on the page
## instead of being quietly hidden.
func _render_row(builders: Array, boxes: Array) -> Image:
	var body := Node3D.new()
	var cursor := 0.0
	# LARGE FIRST, ALONG +X. The three-quarter camera sits 35 degrees round to
	# the model's right, which puts +X on the LEFT of the picture — built
	# small-first the row read large-to-small, backwards from every other size
	# chart anyone has seen.
	# Reversed, however many there are: the tick row has five cells, not three,
	# and a hard-coded [2, 1, 0] would have silently photographed the first
	# three of them and looked like a complete picture.
	for i in range(builders.size() - 1, -1, -1):
		var bb: AABB = boxes[i]
		var holder := Node3D.new()
		# Lay the measured box's edge on the cursor, and put the model's own
		# origin wherever that implies.
		holder.position = Vector3(cursor - bb.position.x, 0, 0)
		body.add_child(holder)
		(builders[i] as Callable).call(holder)
		var w := Node3D.new()
		w.scale = Vector3.ONE * _walker_scale
		# Squarely in front of the approach face. If it ends up standing in
		# something, the concept has no approachable face and the brief
		# disqualifies it — so this placement is a test, not just a ruler.
		# At the front corner, clear of the footprint. Dead in front it is
		# geometrically honest and photographs as a figure standing ON the
		# thing: the three-quarter view projects 2 m of ground to almost
		# nothing, and on concept B it put the Walker on the desk.
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
## by whichever of height and width is tighter, so a fixed 1600 x 560 frame on
## a row that is 19 m across and 17 m tall in view fits by HEIGHT and throws
## away two thirds of the page — which is what the first pass did.
##
## So project the row's eight corners onto the camera's own axes, using the
## same yaw and pitch icon_studio._aim uses, and ask for a frame of that shape.
func _shot_size(box: AABB) -> Vector2i:
	var yaw := deg_to_rad(35.0)
	var pitch := deg_to_rad(15.0)
	var toward := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3.UP.cross(toward).normalized()
	var up := toward.cross(right).normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.dot(right)), minf(lo.y, p.dot(up)))
		hi = Vector2(maxf(hi.x, p.dot(right)), maxf(hi.y, p.dot(up)))
	var span := hi - lo
	var aspect: float = clampf(span.x / maxf(span.y, 0.001), 0.8, 4.0)
	return Vector2i(int(round(SHOT_H * aspect)), SHOT_H)


## The Walker as it ships, out of concept_kit — the same reference every other
## concept sheet in this project uses. Its own scale is applied by the caller.
func _build_walker(to: Node3D) -> void:
	_CK.hull(to, _CK.W_HULL, Vector3(0, 0.3, 0))
	_CK.head(to, Vector3(0, 0.76, 0), 1.0)
	for sx: float in [-1.0, 1.0]:
		_CK.leg(to, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)
	# Dropped so the feet land on y = 0 rather than the hull's origin. The kit
	# builds a Walker about its waist; everything else on this sheet is built
	# off the ground, and a figure floating 1.8 m up would ruin the one thing
	# the figure is here for.
	to.position.y += 1.95


# ─────────────────────────────────────────────
# PAGE
# ─────────────────────────────────────────────

## Row plus its caption, on a page `page_w` wide. Rows have different widths
## because they have different shapes, so the narrow ones are CENTRED rather
## than stretched: stretching would be the one thing this sheet must not do.
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
		printerr("shoot_cores2: nothing to write to %s" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_cores2: could not write %s (%s)" % [path, error_string(err)])
