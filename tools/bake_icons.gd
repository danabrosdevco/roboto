extends SceneTree

# ─────────────────────────────────────────────
# BAKE ICONS — writes the line-art icons in res://icons/ from the game's own
# models (Character/hud/icons/icon_studio.gd): every item and every frame in the
# catalogue, once per size in icon_art.gd.
#
# It renders, so it needs a window; a small one opens for a few seconds.
#   double-click tools\bake_icons.bat
#   or: godot --path . --script res://tools/bake_icons.gd
# Re-run it whenever a model changes. The editor imports the new files the
# next time it has focus.
#
# For a look without touching res://icons, name a folder, and optionally only
# some ids; a folder also gets _sheet.png, every large icon on one page:
#   ... --script res://tools/bake_icons.gd -- C:/somewhere m4 shotgun soldier
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Art := preload("res://Character/hud/icons/icon_art.gd")
const _Icons := preload("res://Character/hud/icons/icons.gd")
const _KillKinds := preload("res://Campaign/kill_kinds.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
# Loaded before the catalogue. Otherwise the first thing to load the robot
# script is a chassis scene half-way through loading the catalogue, the load
# goes round in a circle, and Godot reports soldier.gd as missing.
const _SOLDIER := preload("res://Character/characters/ai/soldier.gd")
const SHEET_BG := Color(0.043, 0.071, 0.063)
const SHEET_INK := Color(0.62, 0.95, 0.66)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("bake_icons: this renders, so it needs a window. Run it without --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else _Icons.DIR
	var only: Array[StringName] = []
	for i in range(1, args.size()):
		only.append(StringName(args[i]))
	var catalogue: ItemCatalogue = load(CATALOGUE)
	var studio: Node = _Studio.new()
	root.add_child(studio)

	var made: Array[String] = []
	var skipped: PackedStringArray = []
	var sheet_parts: Array = []

	for item: ItemDefinition in catalogue.items:
		if item == null or (not only.is_empty() and not only.has(item.id)):
			continue
		var cls := _Art.size_class(item)
		var model := _Art.model_for(item)
		var drawing: String = _Art.DRAWINGS.get(item.id, _Art.FALLBACK_DRAWING)
		var flips: Array = _Art.FLIPS.get(item.id, [false, false])
		var framing: int = _Studio.Framing.SIDE if item.kind == ItemDefinition.Kind.WEAPON else _Studio.Framing.UPRIGHT
		match str(_Art.FRAMINGS.get(item.id, "")):
			"side": framing = _Studio.Framing.SIDE
			"upright": framing = _Studio.Framing.UPRIGHT
			"three_quarter": framing = _Studio.Framing.THREE_QUARTER
		for size_name in _Art.SIZES[cls]:
			var size: Vector2i = _Art.SIZES[cls][size_name]
			var img: Image = null
			if model != null:
				img = await studio.render_model(model, size, framing, flips[0], flips[1],
					1.0 if size_name == "s" else 0.0)
			else:
				img = studio.render_svg(drawing, Vector2(32, 32), size)
			if img == null:
				skipped.append("%s (%s)" % [item.id, size_name])
				continue
			var file := "%s/items/%s_%s.png" % [out_dir, item.id, size_name]
			if _save(img, file):
				made.append(file)
				if size_name == "l":
					sheet_parts.append([String(item.id), img])

	# The frames you can build, and the ones enemies are built from — the
	# debrief draws what each robot killed.
	var frames: Array[ChassisDefinition] = []
	for frame in catalogue.chassis:
		if frame != null:
			frames.append(frame)
	for path in _KillKinds.FRAMES.values():
		var enemy_frame := load(path) as ChassisDefinition if ResourceLoader.exists(path) else null
		if enemy_frame != null and not frames.any(func(f): return f.id == enemy_frame.id):
			frames.append(enemy_frame)
	for frame: ChassisDefinition in frames:
		if frame == null or frame.scene == null or (not only.is_empty() and not only.has(frame.id)):
			continue
		for size_name in _Art.SIZES["frame"]:
			var size: Vector2i = _Art.SIZES["frame"][size_name]
			# Frames are drawn as outlines at every size, small ones included.
			# Filled, the 40px cut is a green blob — a row of them on the squad
			# cards and the debrief says nothing about what each robot IS, and
			# a rover and a soldier read as the same smudge. Items keep the
			# fill: at 16px their lines really do run together.
			var img: Image = await studio.render_model(frame.scene, size, _Studio.Framing.THREE_QUARTER,
				false, false, 0.0)
			if img == null:
				skipped.append("%s (%s)" % [frame.id, size_name])
				continue
			var file := "%s/chassis/%s_%s.png" % [out_dir, frame.id, size_name]
			if _save(img, file):
				made.append(file)
				if size_name == "l":
					sheet_parts.append([String(frame.id), img])

	print("bake_icons: %d icons written to %s" % [made.size(), out_dir])
	if not skipped.is_empty():
		print("bake_icons: nothing visible to draw for: %s" % ", ".join(skipped))
	if out_dir != _Icons.DIR and not sheet_parts.is_empty():
		_save(_sheet(sheet_parts), out_dir + "/_sheet.png")
		print("bake_icons: contact sheet at %s/_sheet.png" % out_dir)
	quit()


func _save(img: Image, file: String) -> bool:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var err := img.save_png(file)
	if err != OK:
		printerr("bake_icons: could not write %s (%s)" % [file, error_string(err)])
	return err == OK


# Every large icon, in the HUD's green on its dark panel, for looking at.
func _sheet(parts: Array) -> Image:
	var cell := Vector2i(280, 150)
	var cols := 4
	var rows := int(ceil(parts.size() / float(cols)))
	var sheet := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in parts.size():
		var img: Image = parts[i][1]
		var ink := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		ink.fill(SHEET_INK)
		var at := Vector2i((i % cols) * cell.x + (cell.x - img.get_width()) / 2,
			(i / cols) * cell.y + (cell.y - img.get_height()) / 2)
		sheet.blend_rect_mask(ink, img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	return sheet
