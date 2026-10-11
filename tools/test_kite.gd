extends SceneTree

# ─────────────────────────────────────────────
# THE KITE — the first aerial in the game that shoots.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_kite.gd
#
# WHAT IS WORTH GUARDING HERE is not the model and not the flight. It is the
# three things that would leave a frame that looks finished, deploys, flies,
# costs 240 compute and puts no rounds anywhere — none of which raise:
#
#   * THE WEAPON LOOP IS SWITCHED BACK ON. `SpotterDrone.handle_weapon_logic`
#     and `roll_combat_action` are stubbed behind `_carries_a_weapon()`, which
#     is `false` for the unarmed scout. A Kite that inherits the `false` has no
#     weapon state machine at all and never fires a shot.
#
#   * THE POD IS THE TURRET. `enemy.gd:2895` escapes `hull_spoils_aim` only via
#     a property literally called `turret` being non-null. This frame cruises
#     at 18 m/s against a 0.6 m/s `_is_moving()` threshold, so it is NEVER
#     stationary: without that property `_aim_tracking` is decayed every frame,
#     the gun never leaves WeaponState.AIM, and nothing warns.
#
#   * base_accuracy IS NOT 0.0. It is a MULTIPLIER on a player frame
#     (squad_spawner.gd:348), and the obvious template for the chassis file —
#     chassis_spotter.tres:19 — sets it to 0.0. At 0.0 the spread is
#     `ai_spread_mrad / 0.01` = 1200 mrad, about 69 degrees, and the frame fires
#     happily and hits nothing.
#
# The geometry is deliberately NOT asserted. Shapes are judged by looking at
# them, and build_kite.gd owns them.
# ─────────────────────────────────────────────

const KITE := "res://Character/characters/ai/kite.tscn"
const SPOTTER := "res://Character/characters/ai/spotter_drone.tscn"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_kite.tres"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const MG := "res://Character/weapon/ai-wep_machine_gun.tscn"

var _fails: int = 0


func _init() -> void:
	await _test_the_chassis_is_registered()
	await _test_the_gun_is_legal_on_it()
	await _test_the_pod_is_the_turret()
	await _test_the_weapon_loop_is_not_stubbed()
	await _test_it_fires_while_moving()
	await _test_the_pod_aims_where_the_gun_points()
	await _test_it_flies()
	await _test_it_can_be_shot_down()
	await _test_emp_drops_it()
	await _test_the_groups_and_the_typed_arrays()

	print("")
	if _fails == 0:
		print("ALL KITE CHECKS PASS")
	else:
		print("KITE FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _spawn(path: String, at: Vector3 = Vector3.ZERO) -> Node:
	var body: Node = load(path).instantiate()
	root.add_child(body)
	(body as Node3D).global_position = at
	body.set_physics_process(false)
	body.set_process(false)
	return body


# ─────────────────────────────────────────────
func _test_the_chassis_is_registered() -> void:
	var def = load(CHASSIS)
	_ok("the chassis definition loads", def != null)
	if def == null:
		return
	_ok("...and names itself kite", def.id == &"kite", str(def.id))
	_ok("...and carries a scene", def.scene != null)
	_ok("...one weapon slot, because one mount exists", int(def.weapon_slots) == 1,
			"%d" % int(def.weapon_slots))
	# There is no coax_mount node on this frame. equip_coax_scene warns once per
	# body per mission if anything tries (enemy.gd:77-81).
	_ok("...and no coax, because there is no second mount",
			String(def.coax_weapon_id) == "", str(def.coax_weapon_id))
	_ok("...and it is a turret frame", bool(def.turret))
	_ok("...and costs two supply", int(def.supply) == 2, "%d" % int(def.supply))
	_ok("...and it is purchasable", bool(def.purchasable))
	# THE SILENT KILLER. See the header.
	_ok("...and base_accuracy is not the Spotter's 0.0",
			float(def.base_accuracy) > 0.0,
			"%.2f — a 0.0 multiplier makes the spread 1200 mrad" % float(def.base_accuracy))
	# `built_in` DISPLAYS IN PLACE OF A WEAPON SLOT (factory_page.gd:258-259),
	# so the Spotter's "OPTICS" on an armed frame hides the gun on the card.
	_ok("...and it declares no built_in, which would hide the gun slot",
			String(def.built_in) == "", str(def.built_in))

	var cat = load(CATALOGUE)
	var ids: Array = []
	for c in cat.chassis:
		if c != null:
			ids.append(String(c.id))
	# NOT YET AN ERROR IF ABSENT: the catalogue is a shared registry and the
	# coordinator appends to it in one pass. Reported either way so the gap is
	# visible rather than assumed.
	_ok("...and the catalogue carries it", ids.has("kite"),
			"REGISTRATION PENDING — append to test_item_catalogue.tres")
	# Loaded by path: kill_kinds.gd is a plain RefCounted with static methods,
	# not a global class or an autoload, so the identifier does not exist in a
	# headless parse. test_ledger.gd:651 does the same.
	var kinds = load("res://Campaign/kill_kinds.gd")
	_ok("...and KillKinds knows the frame", kinds.frame_of(&"kite") != null,
			"REGISTRATION PENDING — add &\"kite\" to kill_kinds.gd FRAMES")


func _test_the_gun_is_legal_on_it() -> void:
	# THE BULWARK'S LIVE DEFECT, AS AN ASSERTION. `recruit()` writes
	# starting_weapon_id straight into weapon_ids[0] without consulting takes()
	# (campaign_state.gd:750-751), so a turret frame missing from its own gun's
	# chassis_whitelist deploys armed, can never be refitted, and taking the gun
	# off is irreversible. Nothing warns. A frame with that hole passes every
	# other check in this file.
	var def = load(CHASSIS)
	var cat = load(CATALOGUE)
	if def == null or cat == null:
		_ok("the chassis and catalogue load", false)
		return
	var item = cat.item(def.starting_weapon_id)
	_ok("the starting weapon resolves in the catalogue", item != null,
			str(def.starting_weapon_id))
	if item == null:
		return
	_ok("...and the frame is allowed to be fitted with it", def.takes(item),
			"chassis_definition.gd:91 — is &\"kite\" in its chassis_whitelist?")
	_ok("...and a robot can carry it", item.fits_ai())


func _test_the_pod_is_the_turret() -> void:
	var k := _spawn(KITE)
	await process_frame
	var turret = k.get("turret")
	var pivot = k.get("gun_pivot")
	var mount = k.get("weapon_mount")
	_ok("the frame has a turret node", turret != null,
			"the export is typed Node3D — a NodePath that is not in the root's node_paths resolves to null")
	_ok("...and a gun pivot", pivot != null)
	if turret == null or pivot == null or mount == null:
		k.free()
		await process_frame
		return
	_ok("...and the pivot hangs off the turret, so traversing carries the gun",
			turret.is_ancestor_of(pivot))
	_ok("...and the mount rides the pivot, so elevating carries the gun",
			pivot.is_ancestor_of(mount))
	# enemy.gd:2895 verbatim. Asked of the object the same way the engine asks.
	_ok("...and enemy.gd's hull_spoils_aim escape is satisfied",
			"turret" in k and k.get("turret") != null)
	k.free()
	await process_frame


func _test_the_weapon_loop_is_not_stubbed() -> void:
	# GUARDS AGAINST A FUTURE EDIT RE-STUBBING THE KITE. The two functions live
	# on spotter_drone.gd behind a virtual predicate; this frame's whole claim
	# to being armed is that it answers that predicate differently from the
	# scout it inherits from.
	var k := _spawn(KITE)
	var s := _spawn(SPOTTER, Vector3(200, 0, 0))
	await process_frame
	_ok("the Kite says it carries a weapon", bool(k._carries_a_weapon()))
	_ok("...and the Spotter still says it does not, so nothing changed for it",
			not bool(s._carries_a_weapon()))
	# enemy.gd:3053-3054 returns on an empty combat array, which is the quiet
	# version of "the frame never chooses to shoot".
	var combat: Array = k.AllowedCombatOptions
	var movement: Array = k.AllowedMovementOptions
	_ok("the combat options are not empty", combat.size() > 0,
			"an empty array means roll_combat_action returns immediately")
	_ok("...and FIRE is among them, which is the only path to _commit_burst",
			combat.has(k.CombatOptions.FIRE), str(combat))
	_ok("...and AIM, so the spread gets a chance to settle",
			combat.has(k.CombatOptions.AIM), str(combat))
	# MOVE IS DELIBERATELY ABSENT. perform_action turns MOVE into
	# move_to(find_reposition_target()), and move_to on a flyer means "this is
	# now my orbit centre" — so a MOVE roll would hand a 14 m orbit at 18 m/s a
	# station chosen as a 2 m lateral step for a robot on foot. The squad leash
	# would overwrite it within 1.6 s anyway.
	_ok("...and MOVE is NOT, because move_to on a flyer sets its orbit centre",
			not combat.has(k.CombatOptions.MOVE), str(combat))
	# FALLBACK's only live reader for this frame is _on_reload_started
	# (enemy.gd:3039-3042): it breaks station on a 5 s reload and comes back.
	_ok("the movement options carry FALLBACK, so a reload breaks station",
			movement.has(k.MovementOptions.FALLBACK), str(movement))
	_ok("...and nothing that needs the navmesh or gravity",
			not movement.has(k.MovementOptions.LEAP)
			and not movement.has(k.MovementOptions.CHASE), str(movement))
	# THE TYPED-ARRAY FAMILY BUG. The scene writer emits these as
	# Array[ExtResource(...)] on every generated frame in this batch, which
	# saves as an empty array in silence.
	_ok("the combat array really is Array[int] on disk",
			combat.get_typed_builtin() == TYPE_INT, "%d" % combat.get_typed_builtin())
	_ok("...and so is the movement array",
			movement.get_typed_builtin() == TYPE_INT, "%d" % movement.get_typed_builtin())
	k.free()
	s.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_it_fires_while_moving() -> void:
	# THE ASSERTION THE WHOLE FRAME TURNS ON. Everything else in this file is
	# plumbing around it.
	#
	# Well clear of the origin, because this one resolves damage rays through
	# the world and a body leaked by an earlier test would be what they hit.
	var k := _spawn(KITE, Vector3(600, 22, 600))
	var target := _spawn(RIFLE, Vector3(600, 0, 560))
	await process_frame
	target.faction = Enums.Factions.PLAYER
	k.faction = Enums.Factions.ENEMY

	k.equip_weapon_scene(load(MG))
	await process_frame
	_ok("a machine gun fits the pod", k.weapon != null,
			"equip_weapon_scene casts to AIWeapon and warns if it cannot")
	if k.weapon == null:
		k.free()
		target.free()
		await process_frame
		return
	var loaded: int = int(k.weapon.magazine_current)
	_ok("...and comes loaded", loaded > 0, "%d rounds" % loaded)

	k.ai_state = k.AIState.COMBAT
	k.combat_target = target
	k.weapon_target = (target as Node3D).global_position
	k._has_los = true
	# ABOVE THE _is_moving() THRESHOLD, which is the whole point: this frame is
	# never under it, and a frame whose hull spoils its aim never fires.
	k.velocity = Vector3(18, 0, 0)
	_ok("the frame counts as moving, as it always will", k._is_moving(),
			"threshold is 0.6 m/s (enemy.gd:2837)")

	# Point the pod at the target first, or the frame is legitimately still
	# slewing and holding fire — which is _weapon_on_target doing its job.
	for i in 120:
		k._update_facing(1.0 / 60.0)
	_ok("...and the pod traverses onto the target", k._weapon_on_target(),
			"cone is %.0f deg" % float(k.fire_cone_degrees))

	var reached_fire: bool = false
	var peak_tracking: float = 0.0
	for i in 240:
		k._update_facing(1.0 / 60.0)
		k.handle_weapon_logic(1.0 / 60.0)
		peak_tracking = maxf(peak_tracking, float(k._aim_tracking))
		if k.weapon_state == k.WeaponState.FIRE:
			reached_fire = true

	# THE ONE THAT CATCHES THE SILENT FAILURE. enemy.gd:2895 decays
	# _aim_tracking every frame unless a non-null `turret` property exists, and
	# this frame is permanently moving.
	_ok("the sight picture builds despite the frame moving", peak_tracking > 0.0,
			"peak _aim_tracking %.3f — zero means the turret property is missing"
			% peak_tracking)
	_ok("...and the weapon state machine reaches FIRE", reached_fire,
			"stuck in %s" % str(k.weapon_state))
	# THE PROOF THAT ROUNDS ACTUALLY LEFT, not merely that a state was entered.
	var spent: int = loaded - int(k.weapon.magazine_current)
	_ok("...and rounds actually left the gun", int(k.weapon.magazine_current) < loaded,
			"%d of %d rounds spent" % [spent, loaded])
	k.free()
	target.free()
	await process_frame


func _test_the_pod_aims_where_the_gun_points() -> void:
	# THE CANT. Rig/Turret carries a fixed -24 degrees of down-cant, and
	# want_pitch is computed from WORLD geometry but assigned to a rotation that
	# is LOCAL to that cant. Uncompensated the gun sits 24 degrees under its
	# target — which fires and hits, because the cone flattens y and
	# check_damage is position-to-position, and looks like a bug on screen.
	var k := _spawn(KITE, Vector3(0, 22, 0))
	await process_frame
	var pivot = k.get("gun_pivot")
	var turret = k.get("turret")
	if pivot == null or turret == null:
		_ok("the pod resolved", false)
		k.free()
		await process_frame
		return
	_ok("the pod really is canted, so the compensation is not dead code",
			absf(float(turret.rotation.x)) > deg_to_rad(5.0),
			"%.1f deg" % rad_to_deg(float(turret.rotation.x)))

	# Something on the ground 25 m away horizontally, from 22 m up: about 41
	# degrees of depression.
	k.ai_state = k.AIState.COMBAT
	k.weapon_target = Vector3(0, 0, -25)
	for i in 240:
		k._update_facing(1.0 / 60.0)
	var world_pitch: float = asin(clampf(
			-(pivot as Node3D).global_transform.basis.z.normalized().y, -1.0, 1.0))
	var want: float = atan2(-22.0, 25.0)
	_ok("...and the gun ends up pointing at the target in WORLD space",
			absf(world_pitch - want) < deg_to_rad(4.0),
			"gun at %.1f deg, target bears %.1f deg"
			% [rad_to_deg(world_pitch), rad_to_deg(want)])
	k.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_it_flies() -> void:
	# Given a station, it holds roughly cruise_height above the ground under it
	# rather than sitting on the ground or climbing away. Driven the way
	# tools/test_air_clearance.gd drives the Spotter.
	var k := _spawn(KITE, Vector3(900, 1, 900))
	await process_frame
	await physics_frame
	k.move_to(Vector3(900, 0, 900))
	var height := float(k.cruise_height)
	for i in 600:
		k.handle_movement(1.0 / 60.0)
		(k as Node3D).global_position += k.velocity * (1.0 / 60.0)
	var y: float = (k as Node3D).global_position.y
	_ok("it climbs to its cruise height and stays there",
			absf(y - height) < height * 0.35, "at %.1f m, cruise is %.1f m" % [y, height])
	_ok("...and it is not on the navmesh, which is the point of the chassis",
			k.off_navmesh_is_normal())
	_ok("...and it never takes cover, because a cover point is on the ground",
			not k.takes_cover())
	# A flyer that does not widen its slot tolerance is re-ordered every frame,
	# because it is permanently orbit_radius from where it was told to stand.
	_ok("...and its slot is as wide as its orbit",
			k.slot_tolerance(1.6) >= float(k.orbit_radius),
			"%.1f vs orbit %.1f" % [k.slot_tolerance(1.6), float(k.orbit_radius)])
	k.free()
	await process_frame


func _test_it_can_be_shot_down() -> void:
	var k := _spawn(KITE, Vector3(1200, 22, 1200))
	await process_frame
	await physics_frame
	await physics_frame
	var ss := (k as Node3D).get_world_3d().direct_space_state
	var from: Vector3 = (k as Node3D).global_position + Vector3(0, -30, 0)
	var to: Vector3 = (k as Node3D).global_position + Vector3(0, 4, 0)
	var hit = ss.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	_ok("a round from the ground hits it", not hit.is_empty() and hit.collider == k,
			"hit %s" % ("nothing" if hit.is_empty() else str(hit.collider.name)))
	# It goes DOWN rather than being destroyed, so a Mechanic can stand it back
	# up — and it must NOT flatten its collider, or the wreck is a pancake in
	# the air rather than a crash.
	_ok("...and it is downable rather than simply destroyed", bool(k.can_be_downed))
	_ok("...and it does not flatten its collider, so the crash reads as a crash",
			not bool(k.flatten_collider_when_downed))
	k.free()
	await process_frame


func _test_emp_drops_it() -> void:
	# ASSERTED DELIBERATELY. SpotterDrone._enter_ekill calls die() — losing the
	# link at altitude means losing lift, which is what makes EMP anti-air.
	# Whether a 240-compute frame should be one-shot by an EMP is an open
	# question; this assertion is what makes changing the answer a visible
	# decision rather than a regression.
	var k := _spawn(KITE, Vector3(1500, 22, 1500))
	await process_frame
	k._enter_ekill()
	await process_frame
	_ok("an EMP takes the rotors, not just the orders",
			not bool(k.alive) or bool(k.downed),
			"alive=%s downed=%s" % [str(k.alive), str(k.downed)])
	k.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_groups_and_the_typed_arrays() -> void:
	var k := _spawn(KITE)
	await process_frame
	_ok("it is in the \"enemies\" group, which every hostile sweep uses",
			k.is_in_group("enemies"))
	_ok("...and in the signal group, so EMP can find it",
			k.is_in_group(AI.SIGNAL_GROUP))
	# PROVES _ready CALLED super(). The "air" group is joined in
	# spotter_drone.gd:108, and it is what _separation walks — without it two
	# Kites fly through each other and through the Spotter.
	_ok("...and in the \"air\" group, so its _ready called super()",
			k.is_in_group("air"))

	var liv = k.get_node_or_null("FactionLivery")
	var eye = k.find_child("Eye", true, false)
	_ok("the frame has an eye", eye != null)
	_ok("...and a livery", liv != null)
	if eye == null or liv == null:
		k.free()
		await process_frame
		return
	# An untyped array assigned to a typed export saves as [] in silence, and an
	# empty FactionLivery.pieces falls back to painting the WHOLE frame — eye
	# included, which is the one feature every robot in the game is identified
	# by.
	_ok("the livery names its pieces explicitly", liv.pieces.size() > 0,
			"%d — empty means it walks the whole frame instead" % liv.pieces.size())
	_ok("...and the eye is not one of them", not liv.pieces.has(eye))
	liv.apply(Enums.Factions.ENEMY)
	await process_frame
	var m = eye.material_override
	_ok("...so a repaint leaves the eye alone",
			m != null and m is StandardMaterial3D,
			"eye wears %s" % ("null" if m == null else m.get_class()))
	var hull = k.find_child("Hull", true, false)
	_ok("...while the hull did take the faction coat",
			hull != null and hull.material_override is ShaderMaterial)

	_ok("death effects are wired", (k.get("particle_effects_die") as Array).size() > 0)
	_ok("hit effects are wired", (k.get("particle_effects_hit") as Array).size() > 0)
	_ok("visible_pieces is wired", (k.get("visible_pieces") as Array).size() > 0)
	k.free()
	await process_frame
