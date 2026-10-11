extends PlayerEquipment
class_name PlayerWeapon

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

# ─────────────────────────────────────────────
# PLAYER WEAPON — the gun half of the split.
#
# Magazines, reserve ammunition, reloading, firemode and ADS live here.
# Everything above this (bob, pose, equip lifecycle, the HUD readout contract)
# is PlayerEquipment and is shared with the grenade, scanner and repair tool.
#
# TWO THINGS THIS FIXES OUTRIGHT
#
# 1. Ammunition is finite. The old start_reload() did
#        magazine_capacity = magazine_size
#    unconditionally. Reloading now transfers rounds out of the shared AmmoPool
#    and fails when the pool is empty.
#
# 2. The reload is cancellable. The old one was
#        await get_tree().create_timer(reload_time).timeout
#    which cannot be aborted — switch weapons or die mid-reload and the
#    coroutine still fired and still refilled the magazine. Harmless while ammo
#    was free; with a reserve it's a duplication bug. It's now a delta-driven
#    timer that _on_unequip() cancels.
#
# NAMING — the old script had magazine_size as the maximum and
# magazine_capacity as the current count, which reads backwards. The maximum
# keeps the name magazine_size (the weapon scenes store it, renaming it would
# silently drop the stored values) and the current count is now `loaded`.
# ─────────────────────────────────────────────

# ── AMMUNITION ────────────────────────────────
# Keyed by TYPE, so two weapons on the same feed share a reserve. Must match an
# AmmoStock in the loadout's starting_ammo.
@export var ammo_type: StringName = &"5.56"
@export var magazine_size: int = 30
@export var reload_time: float = 2.15
# TRUE  — a partial magazine is thrown away when you reload. Every reload is a
#         decision and panic-reloading after each contact costs you. The HUD
#         then counts MAGAZINES, because magazines are what you are spending.
# FALSE — leftover rounds go back into the pool, so a reload never costs you
#         anything, and the HUD counts ROUNDS, because rounds are what you
#         are spending.
# This is the single most felt consequence of finite ammo. It's per-weapon so
# a particular gun can still be run the other way; the shotgun already is.
@export var discrete_magazines: bool = false
# Fire the first shot straight out of a reload without a cooldown gap.
@export var chamber_round: bool = true

# ── FIRING ────────────────────────────────────
@export var firemode: Enums.FireModes

# ── MANUAL ACTION (pump / bolt) ───────────────
# FireModes.MANUAL existed in the enum but nothing implemented it — a weapon set
# to MANUAL simply never fired, because primary_pressed only answered SEMI and
# FULL. A manual gun fires one round per trigger pull and then has to cycle
# before the next, which is what makes a pump feel like a pump rather than a
# slow semi-auto.
@export var pump_time: float = 0.55
@export var pump_sound: AudioStreamPlayer3D

@export var damage: int = 10
@export var FIRE_RATE: float = 0.100

# ── ADS ───────────────────────────────────────
@export var ADS_FOV: float = 45.0
@export var HIP_FOV: float = 70.0
@export var ADS_SPEED: float = 10.0
@export var ads_bob_scale: float = 0.05
@export var ads_position: Vector3 = Vector3(0.0, 0.0, -1.077)
@export var ads_rotation: Vector3 = Vector3(0.0, 0.0, 3.0)

# ── RELOAD PRESENTATION ───────────────────────
@export var reload_position: Vector3 = Vector3(0.31, -0.425, -0.015)
@export var reload_rotation: Vector3 = Vector3(0.2, 20.5, 58.0)
@export var reload_sounds: Array[AudioStreamPlayer3D]
@export var reload_delays: Array[float]
@export var click_stream_player: AudioStreamPlayer3D

signal fired
signal reload_started
signal reload_finished
signal reload_cancelled

# ── RUNTIME ───────────────────────────────────
var loaded: int = 0
var is_reloading: bool = false
var fire_cooldown: float = 0.0

var _reload_t: float = 0.0
## HOW LONG THIS PARTICULAR RELOAD WAS GOING TO TAKE.
##
## Normally reload_time, but a weapon that loads round by round shortens it for
## a top-up — and progress has to be measured against what this reload actually
## started with, or a two-round fill on the Cluster Launcher begins at 60% done
## and the animation skips its own first half.
var _reload_span: float = 0.0
var _sound_index: int = 0
var _sound_t: float = 0.0
var _fire_held: bool = false

# MANUAL action only: true while the gun is being cycled and cannot fire.
var needs_pump: bool = false
var _pump_remaining: float = 0.0


func _on_initialize() -> void:
	loaded = magazine_size
	# Spawning with a full magazine shouldn't also cost you a magazine from the
	# reserve — the starting AmmoStock is what you carry ON TOP of what's loaded.


# ─────────────────────────────────────────────
# AMMUNITION
# ─────────────────────────────────────────────
func reserve() -> int:
	if ammo == null:
		return 0
	return ammo.get_count(ammo_type)


# A gun is "charged" if it can shoot OR could be reloaded. An empty magazine
# with rounds in the bag is still a usable weapon, so it stays selectable.
func has_charge() -> bool:
	return loaded > 0 or reserve() > 0


func charges_remaining() -> int:
	return loaded + reserve()


func consume_charge() -> void:
	loaded = maxi(0, loaded - 1)
	charges_changed.emit()


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.MAGAZINE)
	r.primary = loaded
	r.secondary = reserve()
	r.label = display_name
	# Discrete magazines means the player is choosing between MAGAZINES, so show
	# them magazines — a raw round count doesn't support the decision.
	if discrete_magazines and magazine_size > 0:
		r.secondary = int(floor(float(reserve()) / float(magazine_size)))
	@warning_ignore("integer_division")
	r.warn = loaded == 0 or (loaded <= magazine_size / 4 and reserve() == 0)
	return r


# ─────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────
# Mid-reload counts as busy. The loadout decides whether that blocks a switch or
# just cancels — see EquipmentLoadout.cancel_busy_on_switch.
func is_busy() -> bool:
	return is_reloading


func _on_unequip() -> void:
	# THE important line. Without it a reload that started before the switch
	# completes in the background and credits a magazine you didn't pay for.
	cancel_reload()
	_fire_held = false


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	_fire_held = true
	if firemode == Enums.FireModes.SEMI:
		try_fire()
	elif firemode == Enums.FireModes.FULL:
		try_fire()
	elif firemode == Enums.FireModes.MANUAL:
		# One round per pull, same as SEMI. The difference is the cycle gate in
		# can_fire(), not the trigger.
		try_fire()


func primary_held(_delta: float) -> void:
	if firemode == Enums.FireModes.FULL:
		try_fire()


func primary_released() -> void:
	_fire_held = false


func reload_pressed() -> void:
	start_reload()


func tick(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	_tick_pump(delta)
	_tick_reload(delta)


# The cycle. Ends by telling the HUD, because "ready to fire again" is part of
# the readout even though the round count has not moved.
func _tick_pump(delta: float) -> void:
	if not needs_pump:
		return
	_pump_remaining -= delta
	if _pump_remaining <= 0.0:
		_pump_remaining = 0.0
		needs_pump = false
		# The bolt goes home even if the cycle was cut short by a weapon switch.
		rest_parts()
		charges_changed.emit()


func _start_pump() -> void:
	needs_pump = true
	_pump_remaining = pump_time
	if pump_sound != null:
		pump_sound.play()
	charges_changed.emit()


# ─────────────────────────────────────────────
# FIRING
# ─────────────────────────────────────────────
func can_fire() -> bool:
	return not is_reloading and fire_cooldown <= 0.0 and not is_raising() \
		and not needs_pump


func try_fire() -> void:
	if not can_fire():
		return
	if loaded <= 0:
		_dry_fire()
		return
	fire_cooldown = FIRE_RATE
	# Counted before the shot resolves: a hit lands inside _fire_shot, and
	# the log pairs it with the shot fired in the same physics frame.
	_Analytics.shot(player, display_name)
	_fire_shot()
	loaded = maxi(0, loaded - 1)
	# Cycle even on the last round: you rack the empty gun, and the reload picks
	# up from there. Skipping the pump when empty would let a reload-cancel fire
	# instantly off a gun that was never cycled.
	if firemode == Enums.FireModes.MANUAL:
		_start_pump()
	charges_changed.emit()
	fired.emit()
	used.emit()
	# A gun with an empty magazine and an empty bag is spent. reverts_when_empty
	# is off for guns by default — you want to keep holding it and hear the
	# click, not get silently switched — but the signal is there if you want it.
	if not has_charge():
		_notify_spent()


func _dry_fire() -> void:
	_Analytics.ammo("dry_fire", ammo_type, display_name)
	fire_cooldown = FIRE_RATE
	if click_stream_player != null:
		click_stream_player.play()
	denied.emit("EMPTY")


# Subclasses do the actual shot — raycast, tracer, muzzle flash, recoil.
func _fire_shot() -> void:
	pass


# ─────────────────────────────────────────────
# RELOAD — delta driven, cancellable, paid for
# ─────────────────────────────────────────────
func start_reload() -> void:
	if not is_equipped or is_reloading:
		return
	if loaded >= magazine_size:
		return
	if reserve() <= 0:
		_Analytics.ammo("no_reserve", ammo_type, display_name)
		if click_stream_player != null:
			click_stream_player.play()
		denied.emit("NO AMMO")
		return
	is_reloading = true
	_reload_t = reload_time
	_reload_span = reload_time
	_sound_index = 0
	_sound_t = 0.0
	reload_started.emit()


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_t = 0.0
	_stop_reload_sounds()
	# A CANCELLED RELOAD IS THE ONE THAT STRANDS A PART. Sprinting out of a
	# magazine change at 0.4 leaves the magazine hanging in the air under a gun
	# that has gone back to level.
	_reload_rest()
	reload_cancelled.emit()


func _tick_reload(delta: float) -> void:
	if not is_reloading:
		return

	# Reload sounds, previously a chain of awaits that couldn't be stopped.
	if _sound_index < reload_sounds.size() and _sound_index < reload_delays.size():
		_sound_t += delta
		if _sound_t >= reload_delays[_sound_index]:
			_sound_t = 0.0
			var s: AudioStreamPlayer3D = reload_sounds[_sound_index]
			if s != null:
				s.play()
			_sound_index += 1

	_reload_t -= delta
	if _reload_t > 0.0:
		return
	_finish_reload()


# The reserve is debited HERE, at completion, not at the start. A cancelled
# reload therefore costs nothing and needs no refund path — which is the one
# place an ammo system usually leaks.
func _finish_reload() -> void:
	is_reloading = false
	_reload_rest()
	# Reloading chambers a round, so a manual action comes out of it ready. Left
	# set, the gun would demand a pump it had already been given.
	needs_pump = false
	_pump_remaining = 0.0
	if ammo == null:
		loaded = magazine_size
		charges_changed.emit()
		reload_finished.emit()
		return

	var wanted: int = magazine_size
	if not discrete_magazines:
		wanted = magazine_size - loaded

	var granted: int = ammo.take(ammo_type, wanted)

	if discrete_magazines:
		# Whatever was still in the magazine goes on the floor with it.
		loaded = granted
	else:
		loaded = mini(magazine_size, loaded + granted)

	charges_changed.emit()
	reload_finished.emit()
	if chamber_round:
		fire_cooldown = 0.0


func _stop_reload_sounds() -> void:
	for s in reload_sounds:
		if s != null and s.playing:
			s.stop()


# ─────────────────────────────────────────────
# VIEWMODEL
# ─────────────────────────────────────────────
func _get_pose_target() -> Array:
	# Reset here because this runs once a frame and _pose_is_exact is asked right
	# after it, which is the only reason that flag can be a cached answer rather
	# than a second call into the weapon.
	_pose_exact_now = false
	if needs_pump and not is_reloading:
		var cycling: Array = _pump_frame(pump_progress())
		if cycling.size() == 2:
			_pose_exact_now = true
			return cycling
	if is_reloading:
		# ASKED EVERY FRAME, and it is also where a weapon moves its own parts.
		# An empty answer means the weapon has nothing scripted and wants the one
		# static pose, which is what this did for everything before.
		var scripted: Array = _reload_frame(reload_progress())
		if scripted.size() == 2:
			_pose_exact_now = true
			return scripted
		return [reload_position, reload_rotation]
	if is_obstructed:
		return [obstructed_position, obstructed_rotation]
	if is_ads:
		return [ads_position, ads_rotation]
	return [base_position, base_rotation]


func _bob_amount_now() -> float:
	return bob_amount * ads_bob_scale if is_ads else bob_amount


func _apply_bob() -> bool:
	return not is_reloading


# A gun aims to its own ADS_FOV. See PlayerEquipment.ads_fov.
func ads_fov() -> float:
	return ADS_FOV


# ─────────────────────────────────────────────
# RELOAD MOTION
#
# WHAT A RELOAD USED TO BE: one pose. The viewmodel was handed
# reload_position/reload_rotation the moment the reload started and chased it at
# pose_speed until the reload ended, then chased its way back. Nothing moved on
# the gun itself, nothing happened at any particular moment, and every weapon in
# the game did the same thing at a different angle.
#
# So the pose becomes a FUNCTION OF TIME. `_reload_frame(t)` is asked where the
# weapon sits when the reload is `t` through, 0 to 1, every frame — and because
# it is called every frame it is also where a weapon moves its own parts: the
# Mark One's magazine, the launcher's drum, the squad automatic's feed cover.
# One hook, because they have to agree. A magazine that drops while the gun is
# still level looks like a bug, and the only way to keep them together is to
# solve them from the same t.
#
# THE CHASE LERP IS TURNED OFF while this runs (see _pose_is_exact and
# PlayerEquipment.update_view). pose_speed is an exponential chase: it never
# quite arrives, and it rounds off exactly the beats this exists to create — a
# magazine leaving at 0.3 and seating at 0.75 becomes one slow wallow. A
# scripted reload owns the pose outright and does its own easing, so the beats
# land when they say they do.
# ─────────────────────────────────────────────

## How far through the reload, 0 on the first frame and 1 on the last. Safe to
## call when not reloading; it answers 0.
func reload_progress() -> float:
	if not is_reloading or _reload_span <= 0.0:
		return 0.0
	return clampf(1.0 - (_reload_t / _reload_span), 0.0, 1.0)


## Smoothstep between two poses. The easing every weapon's reload is built from,
## here rather than in each of them so they share one feel.
static func ease_pose(from: Array, to: Array, k: float) -> Array:
	var e: float = smoothstep(0.0, 1.0, clampf(k, 0.0, 1.0))
	return [(from[0] as Vector3).lerp(to[0] as Vector3, e),
		(from[1] as Vector3).lerp(to[1] as Vector3, e)]


## Where the weapon sits `t` through its reload, as [position, rotation], or an
## empty array for "nothing scripted, hold the single reload pose".
##
## Override to animate. It runs every frame of the reload, so a weapon that has
## moving parts poses them here too — see PlayerBoltRifle for the shape.
##
## The default is a generic four-beat magazine change, built out of whatever
## reload_position/reload_rotation the weapon already carries, so every gun in
## the game gets timing without being authored one by one: bring it in, drop the
## magazine, seat the new one, bring it back up. A weapon with nothing to say
## about its own reload still reads as doing something at a particular moment.
func _reload_frame(t: float) -> Array:
	var up := [base_position, base_rotation]
	var down := [reload_position, reload_rotation]
	# The jolt: a few millimetres and a couple of degrees, down when the old
	# magazine leaves and up when the new one is struck home. Small on purpose —
	# this is felt at the edge of vision, and anything bigger reads as the gun
	# being dropped.
	var drop := [(down[0] as Vector3) + Vector3(0.0, -0.035, 0.0),
		(down[1] as Vector3) + Vector3(-6.0, 0.0, 0.0)]
	var seat := [(down[0] as Vector3) + Vector3(0.0, 0.022, 0.0),
		(down[1] as Vector3) + Vector3(5.0, 0.0, 0.0)]
	if t < 0.18:
		return ease_pose(up, down, t / 0.18)
	if t < 0.34:
		return ease_pose(down, drop, (t - 0.18) / 0.16)
	if t < 0.62:
		return ease_pose(drop, down, (t - 0.34) / 0.28)
	if t < 0.76:
		return ease_pose(down, seat, (t - 0.62) / 0.14)
	if t < 0.86:
		return ease_pose(seat, down, (t - 0.76) / 0.10)
	# BACK UP BEFORE THE RELOAD ENDS, not after. The pose is exact while this
	# runs and chased once it stops, so a frame that finished anywhere but the
	# base pose would hand the lerp a step to smooth out — which is the pop this
	# whole system exists to remove.
	return ease_pose(down, up, (t - 0.86) / 0.14)


## Put any moving parts back where the scene left them. Called whenever a reload
## stops, finished or cancelled, because a cancelled reload is the one that
## leaves a magazine hanging in the air half out of the gun.
func _reload_rest() -> void:
	rest_parts()


func _pose_is_exact() -> bool:
	return _pose_exact_now


# ─────────────────────────────────────────────
# MOVING PARTS
#
# A reload that only swings the whole gun about is a camera move, not a reload.
# What makes it read is the magazine actually leaving the magazine well — so
# weapons pose the nodes inside their own model, and these are the three things
# all of them need to do it.
#
# EVERYTHING IS AN OFFSET FROM REST, never an absolute transform. Rest is
# whatever the model scene put there, remembered the first time a part is asked
# for and restored by _reload_rest(). Writing absolute transforms would move the
# authored position into this script, where nobody editing the model would think
# to look, and the project's rule is the other way round: scene values beat
# script defaults.
# ─────────────────────────────────────────────

## Where each posed part sits when nothing is happening to it, by node path.
var _part_rest: Dictionary = {}
## Whether this frame's pose is being driven exactly rather than chased. Set by
## _get_pose_target, read by _pose_is_exact immediately afterwards.
var _pose_exact_now: bool = false


## A named node inside this weapon's model, with its rest transform recorded the
## first time it is asked for. Null, with a warning, if the model has no such
## part — a renamed node would otherwise silently animate nothing at all.
func part(path: String) -> Node3D:
	# viewmodel, not weapon_model: they are the same node in every weapon scene,
	# and this one is declared on PlayerEquipment where this can see it.
	if viewmodel == null:
		return null
	var node := viewmodel.get_node_or_null(NodePath(path)) as Node3D
	if node == null:
		push_warning("%s: no part '%s' in its model, so that piece of the reload does nothing." % [display_name, path])
		return null
	if not _part_rest.has(path):
		_part_rest[path] = node.transform
	return node


## Put a part at its rest transform with `move` applied around it, in model
## space. Pass Transform3D.IDENTITY to pin it at rest for this frame.
func pose_part(path: String, move: Transform3D) -> void:
	var node := part(path)
	if node == null:
		return
	node.transform = move * (_part_rest[path] as Transform3D)


## Every part this weapon has moved, back where the model scene put it.
func rest_parts() -> void:
	if viewmodel == null:
		return
	for path in _part_rest:
		var node := viewmodel.get_node_or_null(NodePath(path)) as Node3D
		if node != null:
			node.transform = _part_rest[path]


## Where a part sits at rest, for spinning it about its own middle rather than
## about the model origin half a gun away.
func rest_origin(path: String) -> Vector3:
	var node := part(path)
	return (_part_rest[path] as Transform3D).origin if node != null else Vector3.ZERO


## A rotation of `degrees` about `axis`, around a `pivot` that is not the model
## origin — a cover on its hinge, a drum on its spindle.
static func swing(axis: Vector3, degrees: float, pivot: Vector3) -> Transform3D:
	var basis := Basis(axis.normalized(), deg_to_rad(degrees))
	return Transform3D(basis, pivot - basis * pivot)


## A straight translation, for the things that just come out and go back in.
static func shift(by: Vector3) -> Transform3D:
	return Transform3D(Basis(), by)


## How far through the cycle, 0 on the first frame and 1 on the last. A MANUAL
## action rifle spends pump_time working its bolt after every shot, and until now
## nothing moved during it — the gun simply refused to fire for 0.7 seconds.
func pump_progress() -> float:
	if not needs_pump or pump_time <= 0.0:
		return 0.0
	return clampf(1.0 - (_pump_remaining / pump_time), 0.0, 1.0)


## Where the weapon sits `t` through its cycle, as [position, rotation], or an
## empty array for "nothing scripted". The twin of _reload_frame, and it poses
## the model's own parts for the same reason: see PlayerBoltRifle.
func _pump_frame(_t: float) -> Array:
	return []


# ─────────────────────────────────────────────
# CUTTING A PART OUT OF ONE MESH.
#
# Hand-built models name their parts as nodes and every one can be posed. An
# imported .blend usually does not: it arrives as a single MeshInstance3D whose
# surfaces split by MATERIAL, each spanning the whole weapon, so there is nothing
# to animate even though the part is plainly there in the geometry. The Ancient
# Rifle's magazine and the Mark One's bolt handle are both like this.
#
# So the part is separated AT LOAD, from the geometry, by taking the triangles
# whose CENTROID falls inside a measured region and building two meshes out of
# one. Centroid rather than vertex, so a triangle is never half in each and no
# hole opens along the cut.
#
# NOTHING IS EDITED TO DO THIS. The source asset is untouched, the imported mesh
# is only ever READ — resources are shared in this project and writing to one
# would corrupt every other copy of that weapon — and the two meshes built here
# are new ArrayMeshes belonging to this instance alone. Both keep the whole
# original vertex array and differ only in their index list, which costs a little
# memory and keeps every normal and UV exactly as the artist left them.
#
# THE REGIONS ARE MEASURED, NEVER GUESSED, and they are right only for the model
# as it imports today. Reimport at a different scale or origin and a box lands
# somewhere else on the weapon in silence. Two things make that survivable: this
# warns when a region catches nothing, and PART_TINT=<name> on
# tools/preview_viewmodel.gd paints whatever came away bright pink. The pink is
# not optional diagnostics — a cut that took the trigger guard instead of the
# magazine looked like nothing at all until it was tinted.
# ─────────────────────────────────────────────

## Cut `regions` out of the weapon model's mesh into a new child node called
## `part_name`, which can then be posed like any other part. True if it worked.
## `only_materials` restricts the cut to surfaces with those material names. A box
## alone cannot always separate a part from what it is bolted to — the Mark One's
## bolt shares its space with a wooden receiver panel, and the two are only told
## apart by what they are made of. Empty means take whatever falls in the box.
func split_part(part_name: String, regions: Array[AABB], from: String = "", only_materials: Array[String] = []) -> bool:
	if viewmodel == null:
		# EVERY EARLY RETURN WARNS. A silent one here looks exactly like a region
		# that caught nothing, and the two want completely different fixes.
		push_warning("%s: asked to cut '%s' out before it has a model, so nothing was separated." % [display_name, part_name])
		return false
	# WHICH MESH TO CUT. An imported weapon is usually one MeshInstance3D and the
	# model IS it; a hand-built one is a Node3D of many, and then the caller has to
	# say which child carries the geometry — the Mark One's body is its "Rifle"
	# child, with the sights and magazine as siblings.
	var src_node: Node = viewmodel if from == "" else viewmodel.get_node_or_null(NodePath(from))
	if src_node == null or not (src_node is MeshInstance3D):
		push_warning("%s: '%s' is not a MeshInstance3D, so '%s' cannot be cut out of it." % [display_name, from if from != "" else "the model", part_name])
		return false
	var mi := src_node as MeshInstance3D
	if mi.mesh == null:
		push_warning("%s: no mesh to cut '%s' out of." % [display_name, part_name])
		return false
	if mi.get_node_or_null(NodePath(part_name)) != null:
		return true   # already done

	var src: Mesh = mi.mesh
	var body := ArrayMesh.new()
	var cut := ArrayMesh.new()
	var taken := 0
	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# READ UNTYPED FIRST. An unindexed surface gives NULL here, not an empty
		# array, and assigning that straight into a typed PackedInt32Array throws
		# before any emptiness check can run — which is exactly how the Mark One's
		# body silently refused to be cut while the Ancient Rifle's, which is
		# indexed, worked first time.
		var raw = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw if raw != null else PackedInt32Array()
		if idx.is_empty():
			# Unindexed: the vertices are already listed in triangle order.
			for i in verts.size():
				idx.append(i)
		var mat: Material = src.surface_get_material(s)
		# A SURFACE THE CALLER DID NOT ASK FOR IS KEPT WHOLE. Nothing on it can be
		# part of the thing being cut out, whatever the box says.
		var wanted: bool = only_materials.is_empty() or (mat != null and only_materials.has(str(mat.resource_name)))
		var keep := PackedInt32Array()
		var drop := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			if not wanted:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
				continue
			var mid: Vector3 = (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			var inside := false
			for box in regions:
				if box.has_point(mid):
					inside = true
					break
			if inside:
				drop.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		taken += drop.size() / 3
		if not keep.is_empty():
			_surface(body, arrays, keep, mat)
		if not drop.is_empty():
			_surface(cut, arrays, drop, mat)

	if taken == 0:
		# EVERY SKIP SAYS WHY. A region that catches nothing leaves the weapon
		# looking exactly as it did, which is indistinguishable from the feature
		# being switched off.
		push_warning("%s: the regions for '%s' caught no triangles, so nothing was separated. The model has probably been reimported and moved — remeasure them." % [display_name, part_name])
		return false

	mi.mesh = body
	# Surface overrides were indexed against the OLD surface list and are wrong
	# for the new one, so they go. The materials travel on the surfaces instead.
	for s in mi.get_surface_override_material_count():
		mi.set_surface_override_material(s, null)
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = cut
	node.cast_shadow = mi.cast_shadow
	node.layers = mi.layers
	# The cut vertices are already in the model's space, so it sits at the origin
	# and is posed from there.
	mi.add_child(node)
	return true


func _surface(into: ArrayMesh, arrays: Array, indices: PackedInt32Array, mat: Material) -> void:
	var out: Array = arrays.duplicate()
	out[Mesh.ARRAY_INDEX] = indices
	into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	if mat != null:
		into.surface_set_material(into.get_surface_count() - 1, mat)
