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
	# An EMPTY folder argument is not "use the default": String("") joined with
	# "/items/x.png" is an absolute path, so it silently wrote fifteen icons to
	# the root of the drive. Treat it as unsaid.
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else _Icons.DIR
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
				# A WIDE SLOT GETS A WIDE DRAWING BOX. Handed a square view for
				# a 96x36 icon the SVG is stretched to nearly three times its
				# width, and every round thing on it comes out an ellipse.
				img = studio.render_svg(drawing, _Art.drawing_box(cls), size)
			if img == null:
				skipped.append("%s (%s)" % [item.id, size_name])
				continue
			var file := "%s/items/%s_%s.png" % [out_dir, item.id, size_name]
			if _save(img, file):
				made.append(file)
				if size_name == "l":
					sheet_parts.append([String(item.id), img])

	# Built-in tools, into the same folder as items: they land in the same slot
	# on the same rows, so they are the same kind of picture.
	for built_in_id in _Art.BUILT_INS:
		if not only.is_empty() and not only.has(built_in_id):
			continue
		var tool_model := load(_Art.BUILT_INS[built_in_id]) as PackedScene \
			if ResourceLoader.exists(_Art.BUILT_INS[built_in_id]) else null
		if tool_model == null:
			skipped.append("%s (no model at %s)" % [built_in_id, _Art.BUILT_INS[built_in_id]])
			continue
		for size_name in _Art.SIZES["wide"]:
			var size: Vector2i = _Art.SIZES["wide"][size_name]
			var img: Image = await studio.render_model(tool_model, size, _Studio.Framing.SIDE,
				false, false, 1.0 if size_name == "s" else 0.0)
			if img == null:
				skipped.append("%s (%s)" % [built_in_id, size_name])
				continue
			var file := "%s/items/%s_%s.png" % [out_dir, built_in_id, size_name]
			if _save(img, file):
				made.append(file)
				if size_name == "l":
					sheet_parts.append([String(built_in_id), img])

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
			# ARMED, IF ITS SCENE DOES NOT ALREADY CARRY A GUN. A Rover's turret
			# takes whatever is fitted and is empty in the scene, so the Rover
			# and the Lobber Rover — same hull, different issue — drew the same
			# picture. Only frames that come up empty are fitted here; anything
			# that models its own weapon (the marksman and its rifle) is left
			# exactly as it was.
			var img: Image = await studio.render_body(_armed_body(frame, catalogue), size,
				_Studio.Framing.THREE_QUARTER, false, false, 0.0)
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


# The frame's scene, with the weapon it is issued fitted to its mount — exactly
# as Enemy.equip_weapon_scene does it at runtime, which CLEARS the mount first.
#
# That clearing is the point. A Rover's mount carries a DisplayGun stand-in so
# the model is not empty in the editor, and the game throws it away the moment a
# real weapon is fitted. Treating that stand-in as "already armed" and leaving
# it alone is why the Rover and the Lobber Rover baked pixel-identical icons:
# both were drawn wearing the placeholder neither of them fights with.
func _armed_body(frame: ChassisDefinition, catalogue: ItemCatalogue) -> Node:
	var body := frame.scene.instantiate()
	if frame.starting_weapon_id == &"" or catalogue == null:
		return body
	var mount = body.get("weapon_mount")
	if mount == null or not (mount is Node3D):
		return body
	var item := catalogue.item(frame.starting_weapon_id)
	if item == null or item.ai_scene == null:
		return body
	for child in (mount as Node3D).get_children():
		(mount as Node3D).remove_child(child)
		child.queue_free()
	var gun := item.ai_scene.instantiate()
	(mount as Node3D).add_child(gun)
	if gun is Node3D:
		(gun as Node3D).transform = Transform3D.IDENTITY
	return body


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
