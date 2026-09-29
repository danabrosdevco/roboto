extends SceneTree

# ─────────────────────────────────────────────
# KIT MOCK-UPS — what a soldier could LOOK like with things fitted.
#
# Throwaway visualiser, not game code. Builds the squad soldier with its Ancient
# Rifle, bolts a rough shape onto it for each piece of equipment and each hat,
# and renders the lot through the same icon studio the UI icons come from, so
# what you are looking at is this game's own line art rather than a sketch.
#
# Shapes are deliberately crude. The question these answer is "does this read at
# a glance, and does it read as THIS item rather than that one", which is a
# silhouette question. Whichever ones survive get modelled properly.
#
# WHICH SIDE THINGS GO ON. The three-quarter framing looks at the robot's FRONT
# RIGHT, so it sees +X and -Z. Anything hung on the back or the left is behind
# the body and may as well not be there — the first pass put the grenades, the
# canister and the nanite cell where none of them could be seen. A fitting also
# has to BREAK THE OUTLINE to register: flush against a capsule it disappears
# into the silhouette however big it is.
#
#   godot --audio-driver Dummy --path . --script res://tools/mockup_kit.gd -- <out dir>
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")
const SOLDIER := "res://Character/characters/ai/soldier_chassis.tscn"
const RIFLE := "res://Character/weapon/ai-wep_m4.tscn"
const CELL := Vector2i(300, 320)
const SHOT := Vector2i(256, 256)
const COLS := 4
const SHEET_BG := Color(0.043, 0.071, 0.063)
const SHEET_INK := Color(0.62, 0.95, 0.66)

var _studio: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mockup_kit: this renders, so it needs a window. Run it without --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mockups"
	_studio = _Studio.new()
	root.add_child(_studio)
	DirAccess.make_dir_recursive_absolute(out_dir)

	for pair in [["kit", _kit_list()], ["hats", _hat_list()]]:
		var cells: Array = []
		for entry in (pair[1] as Array):
			cells.append([entry[0], await _shot(entry[1])])
		_save(await _sheet(cells), "%s/%s.png" % [out_dir, pair[0]])
		print("mockup_kit: %s -> %s/%s.png" % [pair[0], out_dir, pair[0]])
	quit(0)


# One soldier, rifle fitted, with `build` called to bolt things on.
func _shot(build: Callable) -> Image:
	var body: Node = load(SOLDIER).instantiate()
	var mount = body.get("weapon_mount")
	if mount != null and mount is Node3D:
		(mount as Node3D).add_child(load(RIFLE).instantiate())
	build.call(body)
	return await _studio.render_body(body, SHOT, _Studio.Framing.THREE_QUARTER, false, false, 0.0)


# The shapes themselves live in mockup_parts.gd, so the line art on this sheet
# and the in-game screenshots (mockup_shots.gd) can never drift apart.
func _kit_list() -> Array:
	return _Parts.kit_list()


func _hat_list() -> Array:
	return _Parts.hat_list()



# ─────────────────────────────────────────────
# THE SHEET
# ─────────────────────────────────────────────
# Labelled, because a grid of twelve unlabelled capsules is not something two
# people can have a conversation about. Drawn in the HUD's own font through a
# viewport, for the same reason the robots are drawn through the icon studio.
func _label_image(text: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, 28)
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
	return img


func _sheet(parts: Array) -> Image:
	var rows := int(ceil(parts.size() / float(COLS)))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in parts.size():
		var img: Image = parts[i][1]
		if img == null:
			continue
		@warning_ignore("integer_division")
		var col := i % COLS
		@warning_ignore("integer_division")
		var row := i / COLS
		var ink := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		ink.fill(SHEET_INK)
		@warning_ignore("integer_division")
		var at := Vector2i(col * CELL.x + (CELL.x - img.get_width()) / 2, row * CELL.y + 4)
		sheet.blend_rect_mask(ink, img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		var text: Image = await _label_image(str(parts[i][0]))
		if text != null:
			var tink := Image.create(text.get_width(), text.get_height(), false, Image.FORMAT_RGBA8)
			tink.fill(SHEET_INK)
			sheet.blend_rect_mask(tink, text, Rect2i(Vector2i.ZERO, text.get_size()),
				Vector2i(col * CELL.x, row * CELL.y + SHOT.y + 8))
	return sheet


func _save(img: Image, file: String) -> void:
	var err := img.save_png(file)
	if err != OK:
		printerr("mockup_kit: could not write %s (%s)" % [file, error_string(err)])
