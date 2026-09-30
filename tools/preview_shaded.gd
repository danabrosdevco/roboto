extends SceneTree

# ─────────────────────────────────────────────
# SHADED CONTACT SHEET — the gun pack as it actually looks, not as line art.
# The icon studio paints flat silhouettes, which is right for icons and useless
# for judging whether a stock reads as wood or as machined metal.
#
# Throwaway. Renders, so it needs a window.
#
#   godot --audio-driver Dummy --path . --script res://tools/preview_shaded.gd -- <outdir> <name> ...
# ─────────────────────────────────────────────

const PACK := "%s"
const CELL := Vector2i(760, 240)
const BG := Color(0.07, 0.09, 0.09)

## Set by a focus=x,y,width argument; INF means frame the whole model.
var _focus: Vector3 = Vector3.INF


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("preview_shaded: need an out dir and at least one model name")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shots: Array = []
	for n in args.slice(1):
		if n.begins_with("focus="):
			var f: PackedStringArray = n.substr(6).split(",")
			if f.size() == 3:
				_focus = Vector3(f[0].to_float(), f[1].to_float(), f[2].to_float())
			continue
		var path: String = PACK % n
		if not ResourceLoader.exists(path):
			printerr("preview_shaded: no such model %s" % path)
			continue
		var img: Image = await _shot((load(path) as PackedScene).instantiate())
		if img == null:
			continue
		img.save_png("%s/%s.png" % [out_dir, n.get_file().get_basename()])
		shots.append(img)
		print("  %s" % n)
	if shots.is_empty():
		quit(1)
		return
	var sheet := Image.create(CELL.x, CELL.y * shots.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for i in shots.size():
		sheet.blend_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(0, CELL.y * i))
	sheet.save_png("%s/_shaded.png" % out_dir)
	print("preview_shaded: %d -> %s/_shaded.png" % [shots.size(), out_dir])
	quit(0)


func _shot(body: Node3D) -> Image:
	var vp := SubViewport.new()
	vp.size = CELL * 2
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.58)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -52, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	vp.add_child(body)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	root.add_child(vp)
	await process_frame
	# Framed off the real bounds: pack models differ in scale by a lot.
	var box := _bounds(body)
	# KEEP_WIDTH, sized off the model's LENGTH. The default keeps height, so a
	# size taken from the long axis made the vertical extent 7 units for a gun
	# 1.5 units tall — the subject was a fifth of the frame and unjudgeable.
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = box.size.x * 1.08
	var c := box.position + box.size * 0.5
	# focus=x,y,width pins the camera on one part instead of the whole model, so
	# a join can be checked at the size it is actually judged at.
	if _focus != Vector3.INF:
		c = Vector3(_focus.x, _focus.y, 0.0)
		cam.size = _focus.z
	# Side on, from slightly above and in front, so the receiver reads.
	cam.global_position = c + Vector3(0.0, box.size.y * 0.35, maxf(box.size.x, box.size.z) * 2.0)
	cam.look_at(c)
	for _i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in _meshes(node):
		var world := m.global_transform * m.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box


func _meshes(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out
