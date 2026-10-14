extends SceneTree

# ─────────────────────────────────────────────
# THE ANCIENT RIFLE'S MAGAZINE CUT, SEEN SIDE ON.
#
#   godot --audio-driver Dummy --path . \
#       --script res://tools/probe_m4_split_shot.gd -- <out dir>
#
# IT NEEDS A WINDOW. It is a camera; run it WITHOUT --headless.
#
# preview_viewmodel renders from the player's eye, which is the right place to
# judge how a reload FEELS and the wrong place to judge what a cut TOOK: the
# magwell faces away and the receiver hides it. This looks straight at the side
# of the weapon with the magazine tinted and dropped clear, so "what came away"
# and "what stayed behind" are both in frame at once.
#
# Pink is the part that leaves. Anything grey hanging below the receiver after
# the magazine has gone is the fault being chased.
# ─────────────────────────────────────────────

const SCENE := "res://Character/weapon/m4_hud_weapon.tscn"
## How far down the magazine is pushed for the "gone" shots, in model units.
const DROPS := [0.0, 1.0]


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("probe_m4_split_shot: this is a camera. Run it without --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	var weapon: Node3D = load(SCENE).instantiate()
	root.add_child(weapon)
	for _i in 4:
		await process_frame

	# The split happens in _ready; the node it makes is a child of the mesh.
	var mag := _find(weapon, "Magazine")
	print("magazine node: %s" % ("<missing — the cut took nothing>" if mag == null else mag.get_path()))
	if mag != null:
		_tint(mag, Color(1.0, 0.15, 0.6))

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	root.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)

	# Frame the weapon from its own bounding box, so this keeps working if the
	# model is replaced.
	var aabb := _bounds(weapon)
	var centre := aabb.get_center()
	var span: float = maxf(aabb.size.length(), 1.0)

	for drop in DROPS:
		if mag != null:
			mag.position = Vector3(-0.12, -2.6, 0.0) * drop
		await process_frame
		# Side on, and then from below-front, because a thin slice left behind
		# reads as nothing at all from exactly side on.
		# FRAMED OFF THE BOUNDING BOX'S OWN AXES. The barrel is whichever axis
		# is longest and the side is whichever is shortest; hardcoding Z put the
		# camera straight down the muzzle and showed a circle.
		var long_axis := _axis(aabb.size, true)
		var side_axis := _axis(aabb.size, false)
		var up_axis := Vector3(1, 1, 1) - long_axis - side_axis
		await _shoot(centre + side_axis * span * 0.75, centre, out,
				"m4_side_drop%d" % int(drop * 10))
		await _shoot(centre + side_axis * span * 0.5 - up_axis * span * 0.45
				+ long_axis * span * 0.15, centre, out,
				"m4_under_drop%d" % int(drop * 10))
	print("done")
	quit(0)


func _find(n: Node, want: String) -> Node3D:
	if n.name == want and n is Node3D:
		return n
	for c in n.get_children():
		var r := _find(c, want)
		if r != null:
			return r
	return null


func _tint(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_tint(c, col)


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _shoot(eye: Vector3, look: Vector3, out: String, name_text: String) -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.current = true
	cam.near = 0.01
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name_text])
	print("  %s.png" % name_text)
	cam.queue_free()


## The unit axis of `v`'s largest (or smallest) component.
func _axis(v: Vector3, largest: bool) -> Vector3:
	var a := absf(v.x)
	var b := absf(v.y)
	var c := absf(v.z)
	if largest:
		if a >= b and a >= c: return Vector3(1, 0, 0)
		return Vector3(0, 1, 0) if b >= c else Vector3(0, 0, 1)
	if a <= b and a <= c: return Vector3(1, 0, 0)
	return Vector3(0, 1, 0) if b <= c else Vector3(0, 0, 1)
