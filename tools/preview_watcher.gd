extends SceneTree

# ─────────────────────────────────────────────
# WATCHER OPTIONS — four designs for the enemy watch post, side by side.
#
# ONE CAMERA SIZE FOR ALL FOUR. A contact sheet that frames each model to fill
# its own cell is useless for a building: the whole question is how big the
# thing is on a ridge 200m away, and per-model framing hides exactly that. Every
# cell here is the same 10 metres tall, so the silhouettes are comparable.
#
# THE GREY POST IS 2m — a soldier's height. Read every design against it.
#
# Renders, so it needs a window. Throwaway.
#
#   godot --audio-driver Dummy --path . --script res://tools/preview_watcher.gd
# ─────────────────────────────────────────────

const DIR := "res://Character/characters/ai/watcher"
const OUT := "user://watcher_options"
const CELL := Vector2i(520, 760)
const FRAME_HEIGHT := 11.0
const BG := Color(0.07, 0.09, 0.09)

## [file, label] in the order they appear left to right.
const OPTIONS := [
	["res://Character/characters/ai/enemy_watcher.tscn", "THE WATCHER"],
]


var _show_hits := false


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	# "hits" draws each design's intended COLLISION box in translucent red.
	# The question "is it easily shot at" is about the hitbox, not the model, and
	# the two are authored separately — so the sheet has to show the hitbox.
	_show_hits = OS.get_cmdline_user_args().has("hits")
	await process_frame
	var shots: Array = []
	for opt in OPTIONS:
		var path: String = opt[0] if String(opt[0]).begins_with("res://") else "%s/%s.tscn" % [DIR, opt[0]]
		if not ResourceLoader.exists(path):
			printerr("preview_watcher: missing %s" % path)
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		var img: Image = await _shot(model, String(opt[1]))
		if img == null:
			continue
		shots.append(img)
		var one := "%s/%s.png" % [OUT, String(opt[0]).get_file().get_basename()]
		DirAccess.make_dir_recursive_absolute(OUT)
		img.save_png(ProjectSettings.globalize_path(one))
		print("OK    %-26s %s" % [opt[0], _extent(model)])

	if shots.is_empty():
		printerr("preview_watcher: nothing rendered")
		quit(1)
		return
	var sheet := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	DirAccess.make_dir_recursive_absolute(OUT)
	var sheet_path := ProjectSettings.globalize_path("%s/watcher_options%s.png" % [OUT, "_hitbox" if _show_hits else ""])
	sheet.save_png(sheet_path)
	print("")
	print("SHEET %s" % sheet_path)
	print("WATCHER PREVIEW DONE")
	quit(0)


## Height and footprint, so the console says what the picture cannot measure.
func _extent(model: Node3D) -> String:
	var box := _bounds(model)
	return "%.1fm tall, %.1f x %.1fm footprint" % [box.size.y, box.size.x, box.size.z]


func _shot(model: Node3D, label: String) -> Image:
	var vp := SubViewport.new()
	vp.size = CELL * 2
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.54)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-36, -48, 0)
	key.light_energy = 1.7
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14, 128, 0)
	fill.light_energy = 0.5
	vp.add_child(fill)

	var stage := Node3D.new()
	stage.add_child(model)
	stage.add_child(_ground())
	stage.add_child(_scale_post())
	stage.add_child(_caption(label))
	if _show_hits:
		for n in _all(model):
			if n.name == &"Hitbox" and n is GeometryInstance3D:
				(n as GeometryInstance3D).visible = true
	vp.add_child(stage)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# KEEP_HEIGHT and a fixed size: the point of the sheet is that the four are
	# drawn to one scale.
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = FRAME_HEIGHT
	# Aimed at the middle of the tallest design, not at the ground: the first
	# pass framed the floor and cut the top off both towers.
	cam.position = Vector3(13.0, 8.2, 17.0)
	vp.add_child(cam)
	root.add_child(vp)
	# AFTER it is in the tree: look_at works off global_transform, and a camera
	# that has not been parented yet has none to speak of.
	cam.look_at(Vector3(0, 4.4, 0), Vector3.UP)
	await process_frame
	await process_frame
	var tex := vp.get_texture()
	if tex == null:
		vp.queue_free()
		return null
	var img := tex.get_image()
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img


## A dark pad so the base of each design reads against something.
func _ground() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(11, 11)
	m.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.12, 0.11)
	mat.roughness = 0.95
	m.material_override = mat
	return m


## 2m, a soldier's height, stood 2.6m to one side.
func _scale_post() -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(3.0, 0.0, 1.6)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 2.0, 0.28)
	m.mesh = box
	m.position = Vector3(0, 1.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.45, 0.43)
	mat.roughness = 0.8
	m.material_override = mat
	n.add_child(m)
	var tag := Label3D.new()
	tag.text = "2m"
	tag.font_size = 96
	tag.pixel_size = 0.004
	tag.modulate = Color(0.62, 0.95, 0.66)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.4, 0)
	n.add_child(tag)
	return n


func _caption(text: String) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 128
	l.pixel_size = 0.006
	l.modulate = Color(0.86, 1.0, 0.88)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 8.6, 0)
	return l


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in _all(node):
		if child is VisualInstance3D:
			var vi := child as VisualInstance3D
			var local := vi.get_aabb()
			if local.size == Vector3.ZERO:
				continue
			var world := vi.global_transform * local
			if first:
				out = world
				first = false
			else:
				out = out.merge(world)
		elif child is CSGShape3D:
			var csg := child as CSGShape3D
			var local2 := csg.get_aabb()
			if local2.size == Vector3.ZERO:
				continue
			var world2 := csg.global_transform * local2
			if first:
				out = world2
				first = false
			else:
				out = out.merge(world2)
	return out


func _all(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out
