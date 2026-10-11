extends SceneTree

# ─────────────────────────────────────────────
# RELOADS ARE CONTINUOUS, AND THEY PUT THE GUN BACK.
#
# A scripted reload is a hand-written piecewise function: six or seven segments,
# each easing between two poses, with the end of one meant to be the start of the
# next. That is exactly the shape of thing that develops a step at a boundary —
# and a step is invisible in the source and very visible in the hand, because the
# viewmodel no longer lerps during a reload and so takes the jump whole.
#
# So this walks each weapon's reload frame by frame and asserts three things that
# no screenshot can check: no jump between adjacent frames, the gun is back at its
# base pose by the end, and every part the reload moved is back where the model
# scene put it.
# ─────────────────────────────────────────────

## Biggest step allowed between two adjacent frames at 60fps, in metres and in
## degrees. Generous — a snap is allowed to be fast, it is not allowed to teleport.
const MAX_STEP_M := 0.045
const MAX_STEP_DEG := 6.0
## How many samples across the reload. Finer than a real frame at the longest
## reload in the game, so a boundary cannot hide between samples.
const SAMPLES := 600

var _fails := 0


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-54s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-54s got %s, wanted %s" % [label, str(got), str(want)])


func _init() -> void:
	await process_frame
	for path in [
		"res://Character/weapon/bolt_hud_weapon.tscn",
		"res://Character/weapon/cluster_hud_weapon.tscn",
		"res://Character/weapon/squad_auto_hud_weapon.tscn",
		"res://Character/weapon/m4_hud_weapon.tscn",
		"res://Character/weapon/shotgun_hud_weapon.tscn",
		"res://Character/weapon/pistol_hud_weapon.tscn",
		"res://Character/weapon/rocket_hud_weapon.tscn",
	]:
		await _walk(path)
	await _ancient_rifle_split()
	await _cluster_tops_up()
	await _cluster_spends_rounds()
	await _cycling_keeps_the_sights()
	if _fails == 0:
		print("ALL RELOAD MOTION CHECKS PASS")
	else:
		print("RELOAD MOTION FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _walk(path: String) -> void:
	var gun = load(path).instantiate()
	root.add_child(gun)
	for _i in 4:
		await process_frame
	print("%s" % str(gun.display_name if "display_name" in gun else path.get_file()))

	var worst_m := 0.0
	var worst_d := 0.0
	var at_m := 0.0
	var prev: Array = []
	for i in range(SAMPLES + 1):
		var t: float = float(i) / float(SAMPLES)
		var frame: Array = gun._reload_frame(t)
		if frame.size() != 2:
			print("  --   no scripted motion; holds the single reload pose")
			gun.queue_free()
			await process_frame
			return
		if not prev.is_empty():
			var dm: float = (frame[0] as Vector3).distance_to(prev[0] as Vector3)
			var dd: float = (frame[1] as Vector3).distance_to(prev[1] as Vector3)
			if dm > worst_m:
				worst_m = dm
				at_m = t
			worst_d = maxf(worst_d, dd)
		prev = frame
	_check("...no jump in position (worst at t=%.2f)" % at_m, worst_m <= MAX_STEP_M, true)
	_check("...no jump in rotation", worst_d <= MAX_STEP_DEG, true)

	# AND IT ENDS WHERE IT STARTED. The pose is exact while a reload runs and
	# chased once it stops, so a reload finishing anywhere but the base pose hands
	# the lerp a step to smooth out — the pop this system exists to remove.
	var ended: Array = gun._reload_frame(1.0)
	_check("...ends at the base position",
		(ended[0] as Vector3).distance_to(gun.base_position) < 0.002, true)
	_check("...ends at the base rotation",
		(ended[1] as Vector3).distance_to(gun.base_rotation) < 0.5, true)

	# AND THE PARTS GO HOME. _reload_rest() is what a cancelled reload relies on;
	# without it a magazine stays hanging in the air under a level gun.
	var moved: Array = []
	if "_part_rest" in gun:
		for p in gun._part_rest:
			moved.append(str(p))
	if not moved.is_empty():
		gun._reload_frame(0.4)   # mid-sequence, parts well away from rest
		var away := 0
		for p in moved:
			var node := gun.viewmodel.get_node_or_null(NodePath(p)) as Node3D
			if node != null and node.transform != gun._part_rest[p]:
				away += 1
		_check("...%d part(s) actually move" % moved.size(), away > 0, true)
		gun._reload_rest()
		var home := true
		for p in moved:
			var node := gun.viewmodel.get_node_or_null(NodePath(p)) as Node3D
			if node != null and node.transform != gun._part_rest[p]:
				home = false
		_check("...and all of them go back on a cancelled reload", home, true)
	# AND THE SAME FOR THE CYCLE. A MANUAL action weapon works its bolt after every
	# shot, which is far more often than it reloads — a step there is seen a
	# hundred times a mission.
	var cyc: Array = gun._pump_frame(0.5) if gun.has_method("_pump_frame") else []
	if cyc.size() == 2:
		var cworst := 0.0
		var cprev: Array = []
		for i in range(SAMPLES + 1):
			var frame: Array = gun._pump_frame(float(i) / float(SAMPLES))
			if not cprev.is_empty():
				cworst = maxf(cworst, (frame[0] as Vector3).distance_to(cprev[0] as Vector3))
			cprev = frame
		_check("...the bolt cycle has no jump either", cworst <= MAX_STEP_M, true)
		var cend: Array = gun._pump_frame(1.0)
		_check("...and the cycle ends at the base pose",
			(cend[0] as Vector3).distance_to(gun.base_position) < 0.002, true)
		# The bolt must be CLOSED when the cycle ends, or the rifle fires the next
		# shot with its handle standing up.
		# ASK THE WEAPON WHICH PARTS IT MOVED rather than naming one. The Mark One's
		# bolt was BoltKnob and is now Rifle/BoltHandle — a test that hardcodes the
		# node goes green on a weapon that has stopped animating anything.
		gun._pump_frame(0.5)
		var shifted := 0
		var home := 0
		var mid: Dictionary = {}
		for p in gun._part_rest:
			var node := gun.viewmodel.get_node_or_null(NodePath(p)) as Node3D
			if node != null:
				mid[p] = node.transform
				if node.transform != gun._part_rest[p]:
					shifted += 1
		gun._pump_frame(1.0)
		for p in mid:
			var node := gun.viewmodel.get_node_or_null(NodePath(p)) as Node3D
			if node != null and node.transform == gun._part_rest[p]:
				home += 1
		_check("...the bolt actually moves mid-cycle", shifted > 0, true)
		# It must be CLOSED by the end, or the rifle fires its next shot with the
		# handle standing up.
		_check("...and every part is back home by the end", home, mid.size())
	gun.queue_free()
	await process_frame


# ─────────────────────────────────────────────
# THE ANCIENT RIFLE'S MAGAZINE IS CUT OUT OF THE MESH, and that cut is the one
# thing here that is not code.
#
# It is a box in the model's own coordinates, and it is right only for the model
# as it is imported today: reimport the .blend with a different scale or origin
# and the box lands somewhere else on the gun, silently. The first cut was off by
# one lump and took the TRIGGER GUARD — which looked like nothing at all until it
# was tinted. So this asserts the shape of what came away rather than trusting
# the numbers, and asserts that turning the feature off gives the rifle back
# exactly as the artist shipped it.
# ─────────────────────────────────────────────
func _ancient_rifle_split() -> void:
	print("THE ANCIENT RIFLE'S MAGAZINE COMES OUT OF ONE MESH")
	var whole = load("res://Character/weapon/m4_hud_weapon.tscn").instantiate()
	whole.split_magazine = false
	root.add_child(whole)
	await process_frame
	var before: int = _tris(whole.weapon_model.mesh)
	_check("switched off, nothing is separated",
		whole.weapon_model.get_node_or_null("Magazine") == null, true)

	var cut = load("res://Character/weapon/m4_hud_weapon.tscn").instantiate()
	root.add_child(cut)
	await process_frame
	var mag := cut.weapon_model.get_node_or_null("Magazine") as MeshInstance3D
	_check("switched on, a magazine is", mag != null, true)
	if mag == null:
		whole.queue_free()
		cut.queue_free()
		return
	var after: int = _tris(cut.weapon_model.mesh)
	var took: int = _tris(mag.mesh)
	# NOTHING IS LOST OR DUPLICATED. A triangle is sorted by its centroid into one
	# mesh or the other, never both and never neither.
	_check("...and every triangle went to exactly one of them", after + took, before)

	# IDENTIFIED BY SHAPE. A magazine is thin across the weapon and deep down it;
	# the trigger guard this first caught by mistake is neither.
	var box := _used_bounds(mag.mesh)
	_check("...it is magazine-shaped, not a trigger guard",
		box.size.z < 0.2 and box.size.y > 0.5 and box.size.x < 0.7, true)
	_check("...and it is the piece under the receiver, not the grip",
		box.position.y < -0.5, true)
	whole.queue_free()
	cut.queue_free()
	await process_frame


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


## Bounds of the triangles a mesh actually USES. Both meshes keep the whole
## vertex array and differ only in their index list, so mesh.get_aabb() reports
## the entire rifle for both and says nothing about where the cut fell.
func _used_bounds(m: Mesh) -> AABB:
	var box := AABB()
	var first := true
	for s in m.get_surface_count():
		var arrays: Array = m.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
			if first:
				box = AABB(verts[i], Vector3.ZERO)
				first = false
			else:
				box = box.expand(verts[i])
	return box


# ─────────────────────────────────────────────
# THE CLUSTER LAUNCHER LOADS WHAT IT IS MISSING, NOT SIX EVERY TIME.
#
# Topping up is the whole reason a revolver reload is interesting, and it is also
# the part that silently reverts: every other weapon in the game throws its
# magazine away and takes a whole new one, so "reload means fill it" is the
# assumption everything else here is built on.
#
# Three things have to hold together or it reads as a bug rather than a feature:
# the count, the time it takes, and the rounds left in the chambers that were
# already loaded.
# ─────────────────────────────────────────────
func _cluster_spends_rounds() -> void:
	print("FIRING THE CLUSTER LAUNCHER EMPTIES A CHAMBER AND TURNS THE DRUM")
	var gun = load("res://Character/weapon/cluster_hud_weapon.tscn").instantiate()
	root.add_child(gun)
	await process_frame
	# THE WAY THE GAME DOES IT. _ready builds the cylinder while `loaded` is still
	# 0, and only _on_initialize fills the magazine — a launcher that syncs before
	# that is carried into the mission showing six empty holes, and an empty drum
	# turned by one sixth looks exactly like one that never moved, so the rotation
	# disappears with the rounds.
	gun._on_initialize()
	_check("initialised, it is carrying six rounds", _rounds_shown(gun), 6)
	var pool := AmmoPool.new()
	root.add_child(pool)
	pool.add(gun.ammo_type, 60)
	gun.ammo = pool
	gun.is_equipped = true
	_check("a full cylinder shows six rounds", _rounds_shown(gun), 6)
	var turned_before: int = gun._turned
	var barrel: int = gun._chamber_at_barrel()
	gun._spend_chamber()
	_check("...firing empties the chamber that was under the barrel",
		gun._full[barrel], false)
	_check("...and that round is no longer on the drum", _rounds_shown(gun), 5)
	_check("...and the cylinder has turned one detent", gun._turned, turned_before + 1)
	_check("...so a different chamber is under the barrel now",
		gun._chamber_at_barrel() != barrel, true)
	# THREE MORE, and the drum keeps its position between shots rather than
	# snapping back — which is the thing a count alone cannot represent.
	for _i in 3:
		gun._spend_chamber()
	_check("...four shots leave two rounds", _rounds_shown(gun), 2)
	_check("...and the drum is four detents round", gun._turned, turned_before + 4)
	# AND THE RELOAD FILLS THE ONES THAT ARE ACTUALLY EMPTY, which after firing are
	# not the first four chambers.
	gun.loaded = 2
	gun.start_reload()
	_check("...the top-up loads the four that are empty", gun._to_load, 4)
	var fills_empty := true
	for i in gun._fill_order:
		if gun._full[i]:
			fills_empty = false
	_check("...and every chamber it fills was empty", fills_empty, true)
	gun._reload_frame(0.99)
	gun._finish_reload()
	_check("...ending with a full cylinder again", _rounds_shown(gun), 6)
	pool.queue_free()
	gun.queue_free()
	await process_frame


func _cluster_tops_up() -> void:
	print("THE CLUSTER LAUNCHER ONLY LOADS WHAT IS MISSING")
	for had in [0, 3, 5]:
		var gun = load("res://Character/weapon/cluster_hud_weapon.tscn").instantiate()
		root.add_child(gun)
		await process_frame
		var pool := AmmoPool.new()
		root.add_child(pool)
		pool.add(gun.ammo_type, 60)
		gun.ammo = pool
		gun.is_equipped = true
		gun.loaded = had
		gun._show_loaded()
		_check("holding %d of 6, %d round(s) are in the chambers" % [had, had],
			_rounds_shown(gun), had)
		gun.start_reload()
		_check("...and the reload puts in the %d that are missing" % (6 - had),
			gun._to_load, 6 - had)
		# A one-round top-up must not hang the cylinder open for the full five
		# and a half seconds.
		_check("...in less time than a full six", gun._reload_span < gun.reload_time or had == 0, true)
		# Mid-feed, the rounds that were ALREADY in it are still there.
		gun._reload_frame(0.5)
		_check("...without the ones already loaded vanishing",
			_rounds_shown(gun) >= had, true)
		gun._reload_frame(0.99)
		_check("...and it ends full", _rounds_shown(gun), 6)
		pool.queue_free()
		gun.queue_free()
		await process_frame


func _rounds_shown(gun) -> int:
	var n := 0
	for r in gun._rounds:
		if is_instance_valid(r) and r.visible:
			n += 1
	return n


# ─────────────────────────────────────────────
# WORKING THE BOLT MUST NOT TAKE YOU OUT OF THE SIGHTS.
#
# PlayerWeapon._get_pose_target asks for the cycle BEFORE it asks about ADS, so a
# cycle written against base_position quietly overrides aiming: the rifle drops
# to the hip for two thirds of a second after every shot and shoves itself back
# up again. On a weapon whose whole job is deliberate aimed fire that is the
# worst place in the game to throw the sight picture away, and it is invisible
# unless you test it down the sights specifically.
# ─────────────────────────────────────────────
func _cycling_keeps_the_sights() -> void:
	print("CYCLING THE MARK ONE KEEPS THE SIGHT PICTURE")
	var gun = load("res://Character/weapon/bolt_hud_weapon.tscn").instantiate()
	root.add_child(gun)
	await process_frame
	if not gun.has_method("_pump_frame"):
		_check("the Mark One has a cycle at all", false, true)
		gun.queue_free()
		return

	# Hip: the cycle happens around the hip pose.
	gun.is_ads = false
	var hip_worst := 0.0
	for i in 40:
		var f: Array = gun._pump_frame(float(i) / 39.0)
		hip_worst = maxf(hip_worst, (f[0] as Vector3).distance_to(gun.base_position))
	_check("from the hip it stays around the hip pose", hip_worst < 0.2, true)

	# AIMING: the same cycle must happen around the ADS pose instead. These two
	# poses are nearly a metre apart, so a regression here is not subtle.
	gun.is_ads = true
	var ads_worst := 0.0
	for i in 40:
		var f: Array = gun._pump_frame(float(i) / 39.0)
		ads_worst = maxf(ads_worst, (f[0] as Vector3).distance_to(gun.ads_position))
	_check("...and down the sights it stays in the sights", ads_worst < 0.2, true)
	_check("...rather than dropping to the hip",
		gun.ads_position.distance_to(gun.base_position) > 0.5, true)

	# AND IT BARELY TURNS. A rifle that swings off target every shot is unusable.
	var turned := 0.0
	for i in 40:
		var f: Array = gun._pump_frame(float(i) / 39.0)
		turned = maxf(turned, (f[1] as Vector3).distance_to(gun.ads_rotation))
	_check("...and turns only a few degrees doing it", turned < 8.0, true)
	gun.queue_free()
	await process_frame
