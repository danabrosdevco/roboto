extends SceneTree

# ─────────────────────────────────────────────
# THE FIRST-PERSON VIEW, rendered from the player's own camera, in both poses.
#
# A viewmodel can only be judged from where the player sits. This builds the
# player, hangs a weapon off the camera the way the loadout does, poses it at
# base_position and then ads_position, and renders each — at the FOV the game
# actually uses for that pose, at the project's viewport aspect.
#
# A crosshair is drawn at dead centre, because "do the sights line up" means
# "do they sit on that cross".
#
#   godot --audio-driver Dummy --path . --script res://tools/preview_viewmodel.gd -- <outdir> <weapon.tscn> ...
# ─────────────────────────────────────────────

const SHOT := Vector2i(900, 506)   # the project's 16:9 viewport, halved
const BG := Color(0.09, 0.12, 0.13)
const INK := Color(0.55, 1.0, 0.6, 0.85)


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("preview_viewmodel: need an out dir and a weapon scene")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var shots: Array = []
	for path in args.slice(1):
		if not ResourceLoader.exists(path):
			printerr("preview_viewmodel: no such scene %s" % path)
			continue
		for pose in ["hip", "ads", "reload", "thrust"]:
			var img := await _shot(path, pose)
			if img != null:
				img.save_png("%s/%s_%s.png" % [
					out_dir, path.get_file().get_basename(), pose])
				shots.append(img)
				print("  %s %s" % [path.get_file(), pose])
	if shots.is_empty():
		quit(1)
		return
	var sheet := Image.create(SHOT.x, SHOT.y * shots.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for i in shots.size():
		sheet.blend_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i(0, SHOT.y * i))
	sheet.save_png("%s/_view.png" % out_dir)
	print("preview_viewmodel: %s/_view.png" % out_dir)
	quit(0)


func _shot(path: String, pose: String) -> Image:
	var vp := SubViewport.new()
	vp.size = SHOT * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# THE GAME'S OWN ENVIRONMENT, not an approximation of it.
	#
	# This used to build a flat BG_COLOR environment with ambient from a colour,
	# and that has no radiance map — so every metallic material rendered almost
	# black, because a metal's response is nearly all specular and there was
	# nothing to reflect. The Squad Automatic's front post simply vanished, and
	# it looked like a geometry fault. The Mark One survived only because its
	# materials never set `metallic` at all.
	#
	# world_environment.tres is BG_SKY with ambient_light_sky_contribution 0.75,
	# so metals behave here the way the player will actually see them.
	# duplicate() because resources are shared and this run poses it.
	var env: Environment = load("res://Env/world_environment.tres")
	if env == null:
		printerr("preview_viewmodel: no world_environment.tres — falling back to flat ambient, and METALS WILL READ TOO DARK.")
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = BG
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.66, 0.64)
		env.ambient_light_energy = 1.0
	elif pose == "hip":
		env = env.duplicate(true)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -38, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	root.add_child(vp)

	var player: Node3D = load("res://Character/characters/player/test_character.tscn").instantiate()
	vp.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await process_frame
	var cam: Camera3D = player.get_node_or_null("Camera3D")
	if cam == null:
		vp.queue_free()
		return null
	cam.current = true
	var gun: Node3D = (load(path) as PackedScene).instantiate()
	cam.add_child(gun)
	# THE ITEM MOVES THE GUN, NOT JUST THE SCENE.
	#
	# EquipmentLoadout overwrites the weapon node's transform from the catalogue
	# entry AFTER add_child — player_mount_offset / player_mount_rotation_degrees
	# — so a preview that only instantiates the scene renders a gun the game
	# never shows. The Mark One inherited the Ancient Rifle's mount when its
	# item was copied from it, and sat 19cm right and 21cm low in the hand while
	# every render here said the sights were dead on. Two passes of "fixed" ADS
	# went by before anyone thought to check the item rather than the model.
	var mount := _mount_for(path)
	gun.position = mount[0]
	gun.rotation_degrees = mount[1]
	await process_frame
	# NOT EVERY HELD ITEM IS A GUN. A melee weapon has no ADS_FOV or HIP_FOV at
	# all, so these are asked for rather than reached for; PlayerEquipment.ads_fov()
	# returns 0 for anything that cannot be aimed.
	var hip_fov = gun.get("HIP_FOV")
	var ads_fov = gun.get("ADS_FOV")
	var want: float = float(hip_fov) if hip_fov != null else 70.0
	if pose == "ads" and ads_fov != null:
		want = float(ads_fov)
	cam.fov = want
	var model := _viewmodel(gun)
	if model == null:
		printerr("preview_viewmodel: %s names no `viewmodel`, so there is no pose to render." % path.get_file())
		vp.queue_free()
		return null
	# THE AUTHORED REST POSE, COPIED IN FIRST, exactly as PlayerEquipment does
	# during init (player_equipment.gd:141). Without this base_position is still
	# the class default here, so anything that builds its pose ON TOP of it —
	# the lance's thrust — was drawn relative to a place the game never uses.
	if gun.get("use_default_position") == false:
		gun.base_position = model.position
		gun.base_rotation = model.rotation_degrees
	model.position = _pose_pos(gun, pose)
	# DEGREES, matching PlayerEquipment.update_view(), which writes
	# rotation_degrees. This said RADIANS before, on the grounds that the pose lerp
	# ran on viewmodel.rotation — which it did, and that was the bug: the lerp read
	# back 1/57.3 of what it had written and every pose settled at about 17% of the
	# angle it named. So this preview agreed with the lerp's intermediate value and
	# with nothing the player ever saw. Any sight solve taken from an older run of
	# this tool was measured against a picture the game does not draw.
	model.rotation_degrees = _pose_rot(gun, pose)
	for _i in 6:
		await process_frame
	if pose == "ads":
		_probe_sights(cam, model)
	elif pose == "hip":
		_probe_frame(cam, model)
	var img := vp.get_texture().get_image()
	img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_LANCZOS)
	_crosshair(img)
	vp.queue_free()
	return img


# ONLY WEAPONS THAT NAME THEIR VIEWMODEL. Without one there is nothing this
# can pose, and guessing at a node produced a render of the whole gun scene at
# the wrong scale that looked like a broken weapon rather than a skipped one.
func _viewmodel(gun: Node) -> Node3D:
	var vm = gun.get("viewmodel")
	if vm is Node3D:
		return vm
	# FALL BACK TO weapon_model, because that is what HUDWeapon._on_initialize()
	# does. Scenes only set `viewmodel` explicitly when it differs; the Ancient
	# Rifle does not set it at all, so this tool skipped the most-used weapon in
	# the game with an error — and it was skipped silently enough that it was
	# used as the comparison baseline for framing without anyone noticing it
	# had never rendered.
	var wm = gun.get("weapon_model")
	return wm if wm is Node3D else null


## WHERE THE SIGHTS ACTUALLY SIT, MEASURED IN THE EYE'S OWN AXES.
##
## The Mark One's ADS took three passes to land because "is the post on the
## cross" is a judgement call about a twenty-pixel silhouette, and twice the
## judgement was wrong. This is not a judgement call. With the sight line lying
## on the optical axis, the rear aperture centre and the front post tip both
## have a camera-local x and y of zero — the camera looks down its own -Z.
##
## So the numbers read directly as the fix:
##   * tilt is the sight line's angle to the view axis. Kill it with
##     ads_rotation before touching anything else; a tilted line cannot put
##     both sights on the cross at any height.
##   * once tilt is ~0, both y values are the same height h, and ads_position
##     wants -h. The gun node sits on the camera with a zero mount, so gun
##     space IS camera space and the correction needs no conversion.
func _probe_sights(cam: Camera3D, model: Node3D) -> void:
	if model.get_node_or_null("RearSight") == null:
		# Not every viewmodel has irons — a scoped or bare weapon is not a
		# failure, it just has nothing here to measure.
		return
	# THE MODEL DECLARES ITS OWN SIGHT LINE, with two empty markers. This used
	# to derive the aperture from "RearSight/EarL", which worked only as long
	# as every rear sight was built from the same two ears and a bridge. The
	# Squad Automatic's M249 peep has no ears, so the probe found nothing and
	# went SILENT — the one failure mode a measuring tool must not have.
	var rear = _marker(model, "Aperture")
	var front = _marker(model, "Tip")
	if rear == null or front == null:
		printerr("preview_viewmodel: %s has a RearSight but no '%s' marker, so its sight line cannot be measured. Add an empty Node3D at the aperture centre and at the front post tip." % [
			model.name, "Aperture" if rear == null else "Tip"])
		return
	var r: Vector3 = cam.to_local(model.to_global(rear))
	var f: Vector3 = cam.to_local(model.to_global(front))
	print("    rear  x%+.4f y%+.4f at %.3fm | front x%+.4f y%+.4f at %.3fm" % [
		r.x, r.y, -r.z, f.x, f.y, -f.z])
	print("    tilt %+.5f rad | ads_position wants (%+.4f, %+.4f)" % [
		atan2(f.y - r.y, r.z - f.z), -0.5 * (r.x + f.x), -0.5 * (r.y + f.y)])


## HOW MUCH GUN IS IN FRAME AT THE HIP, as a box in the eye's own axes.
##
## "Too much stock showing" is the commonest note on a viewmodel and the
## hardest to act on, because the pose is authored in the Holder's scaled,
## rotated space where no number resembles what you see. This prints the box
## the model actually occupies in metres from the eye: `back` is the nearest
## point to the camera — the butt — and that is the number that decides whether
## the gun looks shouldered or shoved in your face. Compare a new weapon
## against m4_hud_weapon.tscn, which is the one nobody complains about.
func _probe_frame(cam: Camera3D, model: Node3D) -> void:
	var meshes: Array = []
	_collect_meshes(model, meshes)
	if meshes.is_empty():
		printerr("preview_viewmodel: %s has no MeshInstance3D under it, so there is no hip framing to measure." % model.name)
		return
	var to_eye := cam.global_transform.affine_inverse()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for mi in meshes:
		var box: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = to_eye * (mi as Node3D).global_transform
		for i in 8:
			var p: Vector3 = xf * box.get_endpoint(i)
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	# -z is forward, so the LARGEST z is the closest thing to the eye.
	print("    hip  back %.3fm  muzzle %.3fm  x %+.3f..%+.3f  y %+.3f..%+.3f" % [
		-hi.z, -lo.z, lo.x, hi.x, lo.y, hi.y])


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


## A sight marker's position in MODEL space, found BY NAME ANYWHERE under the
## model rather than at a fixed path. The Cluster Launcher hangs its aperture
## off a pivoting leaf (RearSight/Leaf/Aperture) so a range setting can swing
## the whole sight; a hard-coded "RearSight/Aperture" missed it. Z is zeroed
## because the sight line runs down the middle of the gun whatever the marker
## was nudged to.
func _marker(model: Node3D, marker_name: String) -> Variant:
	var node := model.find_child(marker_name, true, false) as Node3D
	if node == null:
		return null
	var p := model.to_local(node.global_position)
	p.z = 0.0
	return p


## Dead centre, where the crosshair is. The sights have to sit on this.
func _crosshair(img: Image) -> void:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for d in range(-14, 15):
		if absi(d) > 3:
			img.set_pixel(cx + d, cy, INK)
			img.set_pixel(cx, cy + d, INK)


## The mount the catalogue puts this weapon on, as [position, rotation_degrees].
## Found by matching player_scene, because the preview is given a scene path and
## the offset lives on the ITEM. Zero when no entry claims it — a scene nobody
## sells is rendered exactly as authored.
func _mount_for(scene_path: String) -> Array:
	var catalogue: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	if catalogue == null:
		return [Vector3.ZERO, Vector3.ZERO]
	for item in catalogue.items:
		if item == null or item.player_scene == null:
			continue
		if item.player_scene.resource_path == scene_path:
			return [item.player_mount_offset, item.player_mount_rotation_degrees]
	printerr("preview_viewmodel: no catalogue item uses %s, so no mount offset is applied." % scene_path.get_file())
	return [Vector3.ZERO, Vector3.ZERO]


## THE THREE POSES THE PLAYER ACTUALLY SEES. Reload is in here because it was
## the one nobody looked at: PlayerWeapon.reload_position defaults to the same
## (0.31, -0.425, -0.015) that base_position used to, so every weapon that
## moved its hip pose left its reload pose behind at the old spot — the gun
## snapped across the screen the moment you pressed R.
func _pose_pos(gun: Node, pose: String) -> Vector3:
	if pose == "thrust":
		var th = _thrust_pose(gun)
		return th[0] if th != null else _rest_pos(gun)
	match pose:
		"ads":
			var a = gun.get("ads_position")
			return a if a is Vector3 else _rest_pos(gun)
		"reload":
			var r = gun.get("reload_position")
			return r if r is Vector3 else _rest_pos(gun)
		_: return _rest_pos(gun)


func _pose_rot(gun: Node, pose: String) -> Vector3:
	if pose == "thrust":
		var th = _thrust_pose(gun)
		return th[1] if th != null else _rest_rot(gun)
	match pose:
		"ads":
			var a = gun.get("ads_rotation")
			return a if a is Vector3 else _rest_rot(gun)
		"reload":
			var r = gun.get("reload_rotation")
			return r if r is Vector3 else _rest_rot(gun)
		_: return _rest_rot(gun)


## THE REST POSE IS NOT ALWAYS base_position. PlayerEquipment reads it off the
## viewmodel's AUTHORED transform when use_default_position is false — see the
## note at player_equipment.gd:141 — and the melee weapons all do that. Reading
## base_position for those showed a lance parked at the class default, nowhere
## near where the scene puts it.
func _rest_pos(gun: Node) -> Vector3:
	var vm := _viewmodel(gun)
	if vm != null and gun.get("use_default_position") == false:
		return vm.position
	return gun.base_position


func _rest_rot(gun: Node) -> Vector3:
	var vm := _viewmodel(gun)
	if vm != null and gun.get("use_default_position") == false:
		return vm.rotation_degrees
	return gun.base_rotation


## MELEE AT FULL EXTENSION. A thrust is a pose you never see standing still,
## and the lance's whole animation lives in _get_pose_target() rather than in a
## rotation, so posing it by hand is the only way to look at it. Returns null
## for anything that does not swing, and that frame is skipped.
func _thrust_pose(gun: Node) -> Variant:
	if gun.get("_swinging") == null or gun.get("swing_time") == null:
		return null
	gun.set("_swinging", true)
	gun.set("_swing_t", float(gun.get("impact_at")) * float(gun.get("swing_time")))
	var pose = gun._get_pose_target()
	gun.set("_swinging", false)
	gun.set("_swing_t", 0.0)
	return pose
