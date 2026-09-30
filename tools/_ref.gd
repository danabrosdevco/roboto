extends SceneTree
const CELL := Vector2i(520, 460)
const BG := Color(0.07, 0.09, 0.09)
func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "w"
	var list: Array = []
	if which == "w":
		list = [["res://Character/weapon/models/machine_gun_model.tscn", "MACHINE GUN", 3.0],
			["res://Character/weapon/models/grenade_launcher_model.tscn", "GRENADE LAUNCHER", 2.2],
			["res://Character/weapon/models/recoilless_model.tscn", "RECOILLESS", 3.0],
			["res://Character/weapon/models/pump_shotgun_model.tscn", "PUMP SHOTGUN", 2.4]]
	else:
		list = [["res://Character/characters/ai/spotter_drone.tscn", "SPOTTER DRONE", 3.0],
			["res://Character/characters/ai/enemy_helicopter.tscn", "QUADCOPTER", 5.0]]
	await process_frame
	var shots: Array = []
	for o in list:
		if not ResourceLoader.exists(String(o[0])):
			printerr("missing %s" % o[0]); continue
		var m: Node3D = (load(String(o[0])) as PackedScene).instantiate()
		var img := await _shot(m, String(o[1]), float(o[2]))
		if img != null: shots.append(img); print("OK  %s" % o[1])
	if shots.is_empty(): quit(1); return
	var sh := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in shots.size(): sh.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	DirAccess.make_dir_recursive_absolute("user://ref")
	var p := ProjectSettings.globalize_path("user://ref/%s.png" % which)
	sh.save_png(p); print("SHEET %s" % p); quit(0)

func _shot(model: Node3D, label: String, frame: float) -> Image:
	var vp := SubViewport.new(); vp.size = CELL * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR
	env.background_color = BG; env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.56); env.ambient_light_energy = 0.95
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var k := DirectionalLight3D.new(); k.rotation_degrees = Vector3(-34, -46, 0)
	k.light_energy = 1.8; vp.add_child(k)
	var f := DirectionalLight3D.new(); f.rotation_degrees = Vector3(-10, 130, 0)
	f.light_energy = 0.55; vp.add_child(f)
	var st := Node3D.new(); st.add_child(model)
	var l := Label3D.new(); l.text = label; l.font_size = 96; l.pixel_size = frame * 0.0008
	l.modulate = Color(0.86, 1, 0.88); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, frame * 0.38, 0); st.add_child(l)
	vp.add_child(st)
	var c := Camera3D.new(); c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.keep_aspect = Camera3D.KEEP_HEIGHT; c.size = frame
	c.position = Vector3(frame * 0.4, frame * 0.42, frame * 0.9)
	vp.add_child(c); root.add_child(vp)
	c.look_at(Vector3.ZERO, Vector3.UP)
	await process_frame
	await process_frame
	var t := vp.get_texture()
	if t == null: vp.queue_free(); return null
	var img := t.get_image(); img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free(); return img
