extends SceneTree

# ─────────────────────────────────────────────
# THE TEN WINNERS, ON ONE SHEET.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_winners.gd -- <out dir>
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
#
# shoot_concepts.gd draws the four OPTIONS for one frame and labels them A-D,
# because at selection time the letter is the only thing that matters. This
# draws the one SELECTED option for every frame and labels it with the frame's
# name and what it is for, because after selection the letter is meaningless
# and the name is the only thing that matters.
#
# The Walker is on it too, first, for the same reason it is on every option
# sheet: the studio fits each cell to its own bounding box, so nothing here
# says anything about size unless a known quantity is standing next to it.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _CK := preload("res://tools/concept_kit.gd")
const _A := preload("res://tools/concepts_a.gd")
const _B := preload("res://tools/concepts_b.gd")
const _C := preload("res://tools/concepts_c.gd")
const _P := preload("res://tools/concepts_p.gd")

const SHOT := Vector2i(380, 380)
const CELL := Vector2i(400, 486)
const COLS := 2
const SHEET_BG := Color(0.043, 0.071, 0.063)

var _studio: Node


## [name, subtitle, builder]. Supply order, player's seven then the enemy
## three — the same order as docs/frames/README.md, so the sheet and the index
## can be read side by side.
func _winners() -> Array:
	return [
		["WALKER", "SUPPLY 3 - SHIPPING TODAY, FOR SCALE", _walker_reference],
		["LANCE", "SUPPLY 1 - CHEAP WHEELS, NO TURRET", _A.lance_a],
		["SAPPER", "SUPPLY 1 - MINES THE GROUND FIRST", _A.sapper_b],
		["PICKET", "SUPPLY 2 - ANTI-AIR, TUBES CANTED UP", _P.picket_c2],
		["WARDEN", "SUPPLY 2 - A JAMMING FIELD, NO GUN", _B.warden_a],
		["DRAYMAN", "SUPPLY 2 - REFILLS MAGAZINES", _B.drayman_a],
		["KITE", "SUPPLY 2 - FIRST ARMED FLYER YOU OWN", _A.kite_d],
		["VESSEL", "SUPPLY 3 - DROPS TWO HATCHLINGS", _B.vessel_a],
		["BROODCARRIER", "SWARM - A NEST THAT KEEPS MOVING", _C.brood_a],
		["BASTION", "STRATCOM - PLANTS, HARDENS ITS SQUAD", _C.bastion_b],
		["SEE-ENGINE", "ARGUS - SEES ALL, SHOOTS NOTHING", _C.argus_a],
	]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_winners: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("shoot_winners: <out dir>")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	_studio = _Studio.new()
	root.add_child(_studio)

	var cells: Array = []
	for w in _winners():
		cells.append([w[0], w[1], await _render(w[2])])
	var path := "%s/winners.png" % out_dir
	_save(await _sheet(cells), path)
	print("shoot_winners: %s" % ProjectSettings.globalize_path(path))
	quit(0)


func _render(build: Callable) -> Image:
	var body := Node3D.new()
	build.call(body)
	return await _studio.render_body(body, SHOT, _Studio.Framing.THREE_QUARTER,
			false, false, 0.0)


func _walker_reference(root_node: Node3D) -> void:
	_CK.hull(root_node, _CK.W_HULL, Vector3(0, 0.3, 0))
	_CK.head(root_node, Vector3(0, 0.76, 0), 1.0)
	for sx in [-1.0, 1.0]:
		_CK.leg(root_node, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)


func _label_image(text: String, size_px: int, col: Color) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, size_px + 12)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _Kit.FONT_BODY)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
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
		var img: Image = parts[i][2]
		var ox := (i % COLS) * CELL.x
		var oy := (i / COLS) * CELL.y
		if img != null:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
					Vector2i(ox + (CELL.x - img.get_width()) / 2, oy + 8))
		var name_img: Image = await _label_image(str(parts[i][0]), 24, Color.WHITE)
		sheet.blend_rect(name_img, Rect2i(Vector2i.ZERO, name_img.get_size()),
				Vector2i(ox, oy + CELL.y - 76))
		var sub: Image = await _label_image(str(parts[i][1]), 14,
				Color(0.62, 0.74, 0.68))
		sheet.blend_rect(sub, Rect2i(Vector2i.ZERO, sub.get_size()),
				Vector2i(ox, oy + CELL.y - 40))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_winners: could not write %s (%s)" % [path, error_string(err)])
