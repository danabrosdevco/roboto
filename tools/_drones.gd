extends SceneTree
const CELL := Vector2i(520, 460)
func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var list := [
		["res://3d_assets/chatgptg/flying quadcopter drones/drone_variant_01_scout/drone_variant_01_scout.glb", "01 SCOUT"],
		["res://3d_assets/chatgptg/drone_variant_02_interceptor.glb", "02 INTERCEPTOR"],
		["res://3d_assets/chatgptg/flying quadcopter drones/drone_variant_03_jammer/drone_variant_03_jammer.glb", "03 JAMMER"]]
	var shots: Array = []
	for o in list:
		if not ResourceLoader.exists(String(o[0])):
			printerr("missing %s" % o[0]); continue
		var m: Node3D = (load(String(o[0])) as PackedScene).instantiate()
		var img := await _shot(m, String(o[1]))
		if img != null: shots.append(img); print("OK  %s" % o[1])
	if shots.is_empty(): quit(1); return
	var sh := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in shots.size(): sh.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	DirAccess.make_dir_recursive_absolute("user://ref")
	var p := ProjectSettings.globalize_path("user://ref/drones.png")
	sh.save_png(p); print("SHEET %s" % p); quit(0)

func _shot(model: Node3D, label: String) -> Image:
	var vp := SubViewport.new(); vp.size = CELL * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.58); env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var k := DirectionalLight3D.new(); k.rotation_degrees = Vector3(-34, -46, 0)
	k.light_energy = 1.8; vp.add_child(k)
	var st := Node3D.new(); st.add_child(model); vp.add_child(st)
	var c := Camera3D.new(); c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(c); root.add_child(vp)
	await process_frame
	var box := AABB(); var first := true
	for n in _all(model):
		if n is VisualInstance3D:
			var a: AABB = (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
			if a.size == Vector3.ZERO: continue
			box = a if first else box.merge(a); first = false
	var sz: float = maxf(maxf(box.size.x, box.size.y), box.size.z) * 1.5
	if sz <= 0.001: sz = 2.0
	c.size = sz
	var mid := box.position + box.size * 0.5
	c.position = mid + Vector3(sz * 0.4, sz * 0.4, sz * 0.9)
	c.look_at(mid, Vector3.UP)
	var l := Label3D.new(); l.text = label; l.font_size = 96
	l.pixel_size = sz * 0.0016; l.modulate = Color(0.86, 1, 0.88)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = mid + Vector3(0, sz * 0.4, 0); st.add_child(l)
	await process_frame
	await process_frame
	var t := vp.get_texture()
	if t == null: vp.queue_free(); return null
	var img := t.get_image(); img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free(); return img

func _all(n: Node) -> Array:
	var o: Array = [n]
	for c in n.get_children(): o.append_array(_all(c))
	return o
