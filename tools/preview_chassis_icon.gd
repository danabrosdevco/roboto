extends SceneTree

# ─────────────────────────────────────────────
# A CHASSIS ICON, ARMED, IN EVERY FRAMING — so the one that reads best can be
# picked by eye instead of inherited. Chassis icons are hardcoded to
# THREE_QUARTER in bake_icons.gd, which was chosen when a soldier was a bare
# capsule; a rifle across the body is a different composition problem.
#
#   godot --audio-driver Dummy --path . --script res://tools/preview_chassis_icon.gd -- <outdir> <chassis id>
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _SOLDIER := preload("res://Character/characters/ai/soldier.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const CELL := Vector2i(260, 260)
const BG := Color(0.043, 0.071, 0.063)


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var want := StringName(args[1]) if args.size() > 1 else &"soldier"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cat: ItemCatalogue = load(CATALOGUE)
	var frame: ChassisDefinition = cat.chassis_def(want)
	if frame == null:
		printerr("no such chassis: %s" % want)
		quit(1)
		return

	var studio := _Studio.new()
	root.add_child(studio)
	var shots: Array = []
	# armed / bare × each framing, so the gun's contribution is visible.
	for armed in [true, false]:
		for framing in [_Studio.Framing.THREE_QUARTER, _Studio.Framing.SIDE]:
			for flip in [false, true]:
				var img: Image = await studio.render_body(
					_body(frame, cat, armed), CELL, framing, flip, false, 0.0)
				if img == null:
					continue
				shots.append({"img": img, "label": "%s %s%s" % [
					"armed" if armed else "bare",
					"3/4" if framing == _Studio.Framing.THREE_QUARTER else "side",
					" flipped" if flip else ""]})
				print("  %s" % shots.back()["label"])

	var cols := 4
	var rows := int(ceil(float(shots.size()) / float(cols)))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for i in shots.size():
		sheet.blend_rect(shots[i]["img"], Rect2i(Vector2i.ZERO, CELL),
			Vector2i(CELL.x * (i % cols), CELL.y * (i / cols)))
	sheet.save_png("%s/_icons.png" % out_dir)
	print("preview_chassis_icon: %s/_icons.png  (row order: %s)" % [
		out_dir, ", ".join(shots.map(func(s): return s["label"]))])
	quit(0)


# The frame's scene with its issued weapon fitted, the same way bake_icons does
# it — the mount is cleared first so a scene that ships with a gun does not end
# up holding two.
func _body(frame: ChassisDefinition, cat: ItemCatalogue, armed: bool) -> Node:
	var body := frame.scene.instantiate()
	if not armed or frame.starting_weapon_id == &"":
		return body
	var mount = body.get("weapon_mount")
	if mount == null or not (mount is Node3D):
		return body
	for child in (mount as Node3D).get_children():
		(mount as Node3D).remove_child(child)
		child.queue_free()
	var item: ItemDefinition = cat.item(frame.starting_weapon_id)
	if item != null and item.ai_scene != null:
		(mount as Node3D).add_child(item.ai_scene.instantiate())
	return body
