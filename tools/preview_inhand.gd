extends SceneTree

# Throwaway: a soldier holding a named weapon, shaded, so scale and mount
# placement can be judged before anyone launches the game.

const _SOLDIER := preload("res://Character/characters/ai/soldier.gd")
const CELL := Vector2i(560, 560)
const BG := Color(0.07, 0.09, 0.09)


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var shots: Array = []
	for id in args.slice(1):
		var body: Node = load("res://Character/characters/ai/soldier_chassis.tscn").instantiate()
		var item: ItemDefinition = cat.item(StringName(id))
		if item != null and item.ai_scene != null:
			body.equip_weapon_scene(item.ai_scene)
		var img := await _shot(body)
		if img != null:
			img.save_png("%s/hand_%s.png" % [out_dir, id])
			shots.append(img)
			print("  %s" % id)
	if shots.is_empty():
		quit(1); return
	var sheet := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for i in shots.size():
		sheet.blend_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	sheet.save_png("%s/_hands.png" % out_dir)
	print("preview_inhand: %s/_hands.png" % out_dir)
	quit(0)


func _shot(body: Node3D) -> Image:
	var vp := SubViewport.new()
	vp.size = CELL * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.62)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -48, 0); key.light_energy = 1.4
	vp.add_child(key)
	vp.add_child(body)
	body.set_physics_process(false)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	root.add_child(vp)
	for _i in 4:
		await process_frame
	var box := _bounds(body)
	cam.size = 4.6  # FIXED, so two weapons render at the same scale and can be compared
	var c: Vector3 = body.global_position + Vector3(0.35, 0.9, 0.0)
	cam.global_position = c + Vector3(2.6, 0.7, 3.0).normalized() * 12.0
	cam.look_at(c)
	for _i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img


func _bounds(node: Node) -> AABB:
	var box := AABB(); var first := true
	for m in _meshes(node):
		var w: AABB = m.global_transform * m.get_aabb()
		box = w if first else box.merge(w); first = false
	return box


func _meshes(node: Node, out: Array[VisualInstance3D] = []) -> Array[VisualInstance3D]:
	if node is VisualInstance3D and not (node is GPUParticles3D):
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out
