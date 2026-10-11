extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPHS A SMOKE CANISTER THROUGH ITS WHOLE LIFE.
#
# tools/test_smoke.gd already proves the cloud does its job — it blocks the
# sight line, a round still goes through it, it only blocks where it actually is,
# it expires and sight comes back. Those are booleans. They say nothing about
# whether it LOOKS like smoke, which is the half a person has to judge.
#
# So: a camera, a target robot twenty metres away, and a canister between them.
# One frame per beat of the cloud's life, written to PNG.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_smoke.gd -- <out dir>
#
# MUST RUN HEADFUL — --headless has no renderer and would write black frames.
# Nothing is saved: the campaign is loaded with autosave off and nothing here
# touches a profile.
# ─────────────────────────────────────────────

const SMOKE := "res://Character/weapon/smoke_volume.tscn"
const TARGET := "res://Character/characters/ai/soldier_rifle.tscn"
const SHOT := Vector2i(1280, 720)
## Seconds after the burst to photograph. The cloud grows over 1.2 s, lives 14,
## then fades for 3 — so these are: just burst, grown, mid-life, starting to go,
## and gone.
const BEATS := [0.4, 1.6, 7.0, 14.5, 17.5]
## Where the camera stands and what it looks at, on the valley floor.
const EYE := Vector3(300.0, 1.7, 232.0)
const LOOK := Vector3(300.0, 1.2, 252.0)


func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://") + out)
	await process_frame

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	if player == null:
		printerr("shot_smoke: no Player, so there is no level to stand in.")
		quit(1)
		return
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/appendix/valley_level.tscn").instantiate())
	for _i in 30:
		await physics_frame

	# THE HUD COMES OFF. hud.tscn's root is a Control, not a CanvasLayer, so it
	# is found by name — a scan for CanvasLayer finds nothing and every frame
	# comes back with the squad readout over the thing being photographed.
	for n in root.find_children("HUD", "", true, false):
		if n is CanvasItem:
			(n as CanvasItem).visible = false

	# GROUND, FOUND RATHER THAN GUESSED. The first version typed coordinates in
	# and photographed the sky over a water plane with the robot hanging in it.
	# The valley floor is where a downward ray says it is.
	var space: PhysicsDirectSpaceState3D = (level as Node3D).get_world_3d().direct_space_state
	var ground: Callable = func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -300.0, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return (hit.position as Vector3).y if hit else 0.0
	var eye_y: float = ground.call(EYE.x, EYE.z)
	var look_y: float = ground.call(LOOK.x, LOOK.z)
	var eye := Vector3(EYE.x, eye_y + 1.7, EYE.z)
	var look := Vector3(LOOK.x, look_y + 1.0, LOOK.z)

	# The player is in shot otherwise, and this is about the cloud.
	player.global_position = eye + Vector3(0, -60, 0)

	# Something to be hidden BY the smoke. Without a subject in frame there is no
	# way to see what the cloud is doing — an empty field of grey proves nothing.
	var mark: Node3D = load(TARGET).instantiate()
	level.add_child(mark)
	mark.global_position = Vector3(LOOK.x, look_y + 0.2, LOOK.z)
	var mgr := _find(root, "AIManager")
	if mgr != null and mgr.has_method("register_enemy"):
		mgr.register_enemy(mark)

	var cam := Camera3D.new()
	level.add_child(cam)
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.current = true
	cam.fov = 70.0

	# Before: the target in the clear, so there is something to compare against.
	for _i in 20:
		await process_frame
	await _shoot("%s/smoke_0_before.png" % out, "before — target in the clear")

	# Midway between the camera and the target, which is where a thrown canister
	# would be screening from.
	var cloud: Node3D = load(SMOKE).instantiate()
	level.add_child(cloud)
	cloud.global_position = eye.lerp(look, 0.55) + Vector3(0, -1.0, 0)

	var elapsed := 0.0
	for i in BEATS.size():
		var want: float = BEATS[i]
		while elapsed < want:
			await process_frame
			elapsed += root.get_process_delta_time()
		await _shoot("%s/smoke_%d_t%.1fs.png" % [out, i + 1, elapsed],
			"t=%.1fs" % elapsed)

	# FROM INSIDE IT. A player who throws smoke at his own feet, or walks into
	# the screen he just made, is standing in this — and a sphere with default
	# culling is invisible from within, so this is worth looking at rather than
	# assuming.
	if is_instance_valid(cloud):
		cloud.queue_free()
	for _i in 10:
		await process_frame
	var inner: Node3D = load(SMOKE).instantiate()
	level.add_child(inner)
	inner.global_position = eye + (look - eye).normalized() * 1.2 - Vector3(0, 0.8, 0)
	var t2 := 0.0
	for beat in [0.6, 2.5, 8.0]:
		while t2 < float(beat):
			await process_frame
			t2 += root.get_process_delta_time()
		await _shoot("%s/smoke_inside_t%.1fs.png" % [out, t2], "INSIDE t=%.1fs" % t2)
	quit(0)


func _shoot(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("shot_smoke: could not write %s (%s)" % [path, error_string(err)])
	else:
		print("  %-34s %s" % [label, path.get_file()])
