extends SceneTree

# ─────────────────────────────────────────────
# RENDER THE HACK-DRONE CONCEPT SHEETS.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_hack.gd -- <out dir> [concept ...]
#   ... -- scratchpad/hack tick piton
#   ... -- scratchpad/hack                  # all five
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
#
# One sheet per concept, six cells: the Walker for scale, the thing in flight,
# the structure alone, and the structure seated on each of the three compute
# cores. The last three are the point of this pass — a structure that works on a
# 4.2 m core and is lost on a 12.4 m one has not answered the brief — and they
# are rendered rather than argued because the studio fits every cell to its own
# box and a claim about fit is only worth what the picture shows.
#
# WHY A SECOND RENDERER AND NOT shoot_concepts.gd. That file's `_sets` is keyed
# by frame and pairs one builder per cell; these concepts need a builder that
# takes a core size as well, and the sheet is 2 x 3 rather than 2 x 2. Rather
# than edit a file three other concept batches already depend on — in a shared
# checkout, mid-edit — this is its own entry point. It borrows the studio, the
# label plate and the measurer unchanged.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _CK := preload("res://tools/concept_kit.gd")
const _H := preload("res://tools/concepts_hack.gd")

const SHOT := Vector2i(380, 380)
const CELL := Vector2i(400, 430)
const COLS := 2
const SHEET_BG := Color(0.043, 0.071, 0.063)

var _studio: Node


## concept -> [label, flight, placed, seated]. `seated` takes (root, core key).
func _sets() -> Dictionary:
	return {
		"tick": ["A  TICK", _H.tick_flight, _H.tick_placed, _H.tick_seated],
		"piton": ["B  PITON", _H.piton_flight, _H.piton_placed, _H.piton_seated],
		"parasol": ["C  PARASOL", _H.parasol_flight, _H.parasol_placed, _H.parasol_seated],
		"yoke": ["D  YOKE", _H.yoke_flight, _H.yoke_placed, _H.yoke_seated],
		"chrysalis": ["E  CHRYSALIS", _H.chrysalis_flight, _H.chrysalis_placed,
				_H.chrysalis_seated],
	}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_hack: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("shoot_hack: <out dir> [concept ...]")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var sets := _sets()
	var wanted: Array = args.slice(1)
	if wanted.is_empty():
		wanted = sets.keys()

	_studio = _Studio.new()
	root.add_child(_studio)

	for name in wanted:
		if not sets.has(name):
			printerr("  no builders for '%s'" % name)
			continue
		var set: Array = sets[name]
		var seated: Callable = set[3]
		var cells: Array = [
			["WALKER  3.81 m, for scale", await _render(_walker_reference)],
			["IN FLIGHT  carrying", await _render(set[1])],
			["STRUCTURE  placed, alone", await _render(set[2])],
			["ON  compute_core_small  4.2 m", await _render(seated.bind("small"))],
			["ON  compute_core  7.0 m", await _render(seated.bind("medium"))],
			["ON  compute_core_large  12.4 m", await _render(seated.bind("large"))],
		]
		var path := "%s/%s_hack.png" % [out_dir, name]
		_save(await _sheet(cells), path)
		print("shoot_hack: %s" % ProjectSettings.globalize_path(path))
		await _measure(str(set[0]), [["in flight", set[1]], ["structure", set[2]]])
	quit(0)


func _render(build: Callable) -> Image:
	var body := Node3D.new()
	build.call(body)
	return await _studio.render_body(body, SHOT, _Studio.Framing.THREE_QUARTER,
			false, false, 0.0)


## The Walker as it ships, so every sheet has a known quantity on it. Lifted
## from shoot_concepts.gd unchanged, deliberately: two scale references that
## disagree would be worse than none.
func _walker_reference(root_node: Node3D) -> void:
	_CK.hull(root_node, _CK.W_HULL, Vector3(0, 0.3, 0))
	_CK.head(root_node, Vector3(0, 0.76, 0), 1.0)
	for sx in [-1.0, 1.0]:
		_CK.leg(root_node, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)


## Measured sizes, because the sheet cannot show them — the studio fits every
## cell to its own bounding box, so nothing about relative size survives the
## render. Subtraction shapes are skipped: they are deliberately oversized so a
## cut goes clean through, and counting them put the Walker at 3.3 m wide.
func _measure(label: String, opts: Array) -> void:
	print("  %-14s     W     H     L   (metres)" % label)
	for opt in opts:
		var body := Node3D.new()
		(opt[1] as Callable).call(body)
		root.add_child(body)
		await process_frame
		await process_frame
		var bb := _bounds(body, body)
		print("    %-10s %5.2f %5.2f %5.2f   (y %5.2f .. %5.2f)"
				% [str(opt[0]), bb.size.x, bb.size.y, bb.size.z,
				bb.position.y, bb.position.y + bb.size.y])
		body.queue_free()


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
	if n is VisualInstance3D and not (n is OccluderInstance3D):
		var local := body.global_transform.affine_inverse() * (n as VisualInstance3D).global_transform
		var a := local * (n as VisualInstance3D).get_aabb()
		out = a if not started else out.merge(a)
	return out


func _label_image(text: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, 30)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _Kit.FONT_BODY)
	l.add_theme_font_size_override("font_size", 18)
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


func _sheet(parts: Array) -> Image:
	var rows := int(ceil(parts.size() / float(COLS)))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in parts.size():
		var img: Image = parts[i][1]
		var col: int = i % COLS
		var row: int = i / COLS
		var ox := col * CELL.x
		var oy := row * CELL.y
		if img != null:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
					Vector2i(ox + (CELL.x - img.get_width()) / 2, oy + 12))
		else:
			push_warning("shoot_hack: cell '%s' rendered empty" % str(parts[i][0]))
		var label: Image = await _label_image(str(parts[i][0]))
		sheet.blend_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
				Vector2i(ox, oy + CELL.y - 36))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_hack: could not write %s (%s)" % [path, error_string(err)])
