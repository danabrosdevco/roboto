extends SceneTree

# ─────────────────────────────────────────────
# RENDER A CONCEPT SHEET FOR ONE FRAME.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_concepts.gd -- <out dir> [frame ...]
#   ... -- scratchpad/sheets lance kite
#   ... -- scratchpad/sheets                 # every frame that has builders
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
#
# One sheet per frame: the four options plus the WALKER for scale, drawn
# through the game's own icon studio so what you are judging is this project's
# line art and not a sketch in another style. Also prints each option's
# measured bounding box, because the studio fits every cell to its own box and
# therefore says NOTHING about size — a label claiming otherwise would be a
# lie, and was one in an earlier pass.
#
# The builders live in tools/concepts_*.gd, written per batch so three of them
# could be drafted in parallel without colliding. This file only knows their
# names.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")
const _CK := preload("res://tools/concept_kit.gd")
const _A := preload("res://tools/concepts_a.gd")
const _B := preload("res://tools/concepts_b.gd")
const _C := preload("res://tools/concepts_c.gd")

const SHOT := Vector2i(380, 380)
const CELL := Vector2i(400, 430)
const COLS := 2
const SHEET_BG := Color(0.043, 0.071, 0.063)

var _studio: Node


## frame id -> [[label, Callable], ...]. Add a batch here when it lands.
func _sets() -> Dictionary:
	return {
		"lance": [["A", _A.lance_a], ["B", _A.lance_b], ["C", _A.lance_c], ["D", _A.lance_d]],
		"sapper": [["A", _A.sapper_a], ["B", _A.sapper_b], ["C", _A.sapper_c], ["D", _A.sapper_d]],
		"kite": [["A", _A.kite_a], ["B", _A.kite_b], ["C", _A.kite_c], ["D", _A.kite_d]],
		"warden": [["A", _B.warden_a], ["B", _B.warden_b], ["C", _B.warden_c], ["D", _B.warden_d]],
		"drayman": [["A", _B.drayman_a], ["B", _B.drayman_b], ["C", _B.drayman_c], ["D", _B.drayman_d]],
		"vessel": [["A", _B.vessel_a], ["B", _B.vessel_b], ["C", _B.vessel_c], ["D", _B.vessel_d]],
		"brood": [["A", _C.brood_a], ["B", _C.brood_b], ["C", _C.brood_c], ["D", _C.brood_d]],
		"bastion": [["A", _C.bastion_a], ["B", _C.bastion_b], ["C", _C.bastion_c], ["D", _C.bastion_d]],
		"argus": [["A", _C.argus_a], ["B", _C.argus_b], ["C", _C.argus_c], ["D", _C.argus_d]],
	}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_concepts: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("shoot_concepts: <out dir> [frame ...]")
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

	for frame in wanted:
		if not sets.has(frame):
			printerr("  no builders for '%s'" % frame)
			continue
		var cells: Array = [["WALKER  for scale", await _render(_walker_reference)]]
		for opt in sets[frame]:
			cells.append([str(opt[0]), await _render(opt[1])])
		var path := "%s/%s_concepts.png" % [out_dir, frame]
		_save(await _sheet(cells), path)
		print("shoot_concepts: %s" % ProjectSettings.globalize_path(path))
		await _measure(frame, sets[frame])
	quit(0)


func _render(build: Callable) -> Image:
	var body := Node3D.new()
	build.call(body)
	return await _studio.render_body(body, SHOT, _Studio.Framing.THREE_QUARTER,
			false, false, 0.0)


## The Walker as it ships, so every sheet has a known quantity on it.
func _walker_reference(root_node: Node3D) -> void:
	_CK.hull(root_node, _CK.W_HULL, Vector3(0, 0.3, 0))
	_CK.head(root_node, Vector3(0, 0.76, 0), 1.0)
	for sx in [-1.0, 1.0]:
		_CK.leg(root_node, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)


## Measured sizes, because the sheet cannot show them.
##
## SUBTRACTION SHAPES DO NOT COUNT. They are deliberately oversized — a glacis
## cut is 1.4x the hull width so it slices cleanly through both flanks — and
## including them put the Walker at 3.3 m wide when its hull is 1.5.
func _measure(frame: String, opts: Array) -> void:
	print("  %-10s     W     H     L   (metres)" % frame.to_upper())
	for opt in opts:
		var body := Node3D.new()
		(opt[1] as Callable).call(body)
		root.add_child(body)
		await process_frame
		await process_frame
		var bb := _bounds(body, body)
		print("    %-6s %5.2f %5.2f %5.2f" % [str(opt[0]), bb.size.x, bb.size.y, bb.size.z])
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
	if n is VisualInstance3D:
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
	l.add_theme_font_size_override("font_size", 20)
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
		var label: Image = await _label_image(str(parts[i][0]))
		sheet.blend_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
				Vector2i(ox, oy + CELL.y - 36))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_concepts: could not write %s (%s)" % [path, error_string(err)])
