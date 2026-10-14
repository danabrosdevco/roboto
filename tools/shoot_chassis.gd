extends SceneTree

# ─────────────────────────────────────────────
# RENDER BUILT CHASSIS SCENES, by path.
#
#   godot --audio-driver Dummy --path . --script res://tools/shoot_chassis.gd -- <out dir> <scene.tscn> [...]
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
#
# bake_icons.gd already draws every frame in the game, but it reads the
# CATALOGUE, so it can only see a frame that has a ChassisDefinition. A model
# built before its .tres exists is invisible to it. This takes scene paths
# instead, which is the whole difference.
#
# Labels are the scene's filename, because at this stage the file IS the name.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
# Loaded before anything instantiates a chassis, for the reason bake_icons.gd
# records: if the first thing to pull in the robot script is a chassis scene
# mid-load, the load goes round in a circle and soldier.gd reports missing.
const _SOLDIER := preload("res://Character/characters/ai/soldier.gd")

const SHOT := Vector2i(380, 380)
const CELL := Vector2i(400, 440)
const COLS := 2
const SHEET_BG := Color(0.043, 0.071, 0.063)

var _studio: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shoot_chassis: this renders, so run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("shoot_chassis: <out dir> <scene.tscn> [...]")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	_studio = _Studio.new()
	root.add_child(_studio)

	var cells: Array = []
	for path in args.slice(1):
		if not ResourceLoader.exists(path):
			printerr("  missing %s" % path)
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			printerr("  not a scene %s" % path)
			continue
		var img: Image = await _studio.render_model(ps, SHOT,
				_Studio.Framing.THREE_QUARTER, false, false, 0.0)
		cells.append([path.get_file().get_basename().to_upper(), img])
	if cells.is_empty():
		printerr("shoot_chassis: nothing rendered")
		quit(1)
		return
	var out := "%s/chassis.png" % out_dir
	_save(await _sheet(cells), out)
	print("shoot_chassis: %s" % ProjectSettings.globalize_path(out))
	quit(0)


func _label_image(text: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, 32)
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


func _sheet(parts: Array) -> Image:
	var rows := int(ceil(parts.size() / float(COLS)))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in parts.size():
		var img: Image = parts[i][1]
		var ox := (i % COLS) * CELL.x
		var oy := (i / COLS) * CELL.y
		if img != null:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
					Vector2i(ox + (CELL.x - img.get_width()) / 2, oy + 10))
		var label: Image = await _label_image(str(parts[i][0]))
		sheet.blend_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
				Vector2i(ox, oy + CELL.y - 40))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("shoot_chassis: could not write %s (%s)" % [path, error_string(err)])
