extends SceneTree

# ─────────────────────────────────────────────
# WHAT THE VIEWMODEL POSES ACTUALLY RESOLVE TO ON SCREEN.
#
# Every held item's pose is a Vector3 of EULER ANGLES IN DEGREES. Everything
# that authors one agrees: swing_rotation (-18, 6, 0), the default
# reload_rotation (0.2, 20.5, 58.0), obstructed_rotation (0.3, 90, 3), and the
# bob term, which is amount * 20.0. PlayerEquipment.update_view() ends by
# writing the result to viewmodel.rotation_DEGREES.
#
# This exists because the lerp in between ran on viewmodel.rotation, which is
# RADIANS. Reading back what the previous frame wrote divided the running pose
# by 57.3 every frame, so a pose settled at about 17% of the angle it named, and
# the repair lance — the one item that carries its orientation on the viewmodel
# node rather than on a Holder inside it — had its authored 107.9 degrees of yaw
# resolve to 0.4. It lay flat across the screen like a bar held sideways, which
# is the exact failure the lance scene's own comment says it was built to avoid.
#
# So: drive the real update_view() and assert that a pose ARRIVES at the angle
# it names. Nothing here mocks the lerp — that is the part that was wrong.
#
#   godot --headless --path . --script res://tools/test_viewmodel_poses.gd
# ─────────────────────────────────────────────

const SCENES := [
	"res://Character/weapon/m4_hud_weapon.tscn",
	"res://Character/weapon/bolt_hud_weapon.tscn",
	"res://Character/weapon/cluster_hud_weapon.tscn",
	"res://Character/weapon/squad_auto_hud_weapon.tscn",
	"res://Character/weapon/pistol_hud_weapon.tscn",
	"res://Character/weapon/shotgun_hud_weapon.tscn",
	"res://Character/weapon/knife_hud_weapon.tscn",
	"res://Character/weapon/repair_lance_hud_weapon.tscn",
	"res://Character/weapon/repair tool_hud_weapon.tscn",
	"res://Character/weapon/scanner_hud_weapon.tscn",
	"res://Character/weapon/grenade_hud_weapon.tscn",
	"res://Character/weapon/smoke_hud_weapon.tscn",
	"res://Character/weapon/rocket_hud_weapon.tscn",
]

# Settling tolerance, in degrees. The pose lerp is exponential and bob never
# fully stops, so this is "arrived", not "identical".
const TOL := 1.5
const SETTLE_FRAMES := 400

var _fails: int = 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"

	print("")
	print("══ VIEWMODEL POSES ═══════════════════════════════════════")
	print("   authored -> where it settles, both in DEGREES")
	for path in SCENES:
		_check(path)

	_check_lance_thrust()

	print("")
	if _fails == 0:
		print("PASS — every authored pose resolves to the angle it names")
	else:
		print("FAIL — %d pose(s) do not resolve to what they say" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("%s did not load" % path.get_file())
		return
	var item: Node3D = packed.instantiate()
	if not item.has_method("update_view"):
		_fail("%s is not a PlayerEquipment" % path.get_file())
		return
	# No tree and no player: update_view() touches the viewmodel child and the
	# item's own fields, nothing else. Keeping it out of the tree is what makes
	# this runnable headless at all.
	item.initialize(null, null, null)
	var vm: Node3D = item.get("viewmodel")
	if vm == null:
		print("  %-30s no viewmodel" % path.get_file())
		return

	# What the scene asked for, before anything has had a chance to overwrite it.
	var authored: Vector3 = item.base_rotation
	item.equip()
	var settled := _settle(item, false)

	print("")
	print("  %s" % path.get_file())
	print("     base        %-28s -> %s" % [_v(authored), _v(settled)])
	if not _near(authored, settled):
		_fail("%s: base_rotation says %s, settles at %s" % [
			path.get_file(), _v(authored), _v(settled)])

	# The holster pose, which is also where it goes when the muzzle is in a wall.
	var obstructed: Vector3 = item.obstructed_rotation
	if item.get("lowers_when_obstructed"):
		var got := _settle(item, true)
		print("     obstructed  %-28s -> %s" % [_v(obstructed), _v(got)])
		if not _near(obstructed, got):
			_fail("%s: obstructed_rotation says %s, settles at %s" % [
				path.get_file(), _v(obstructed), _v(got)])

	# And the pose equip() snaps to before the lerp starts. It has to BE the
	# holster pose, or the item swings up out of somewhere it never declared.
	item.unequip()
	item.equip()
	var snap := vm.rotation_degrees
	print("     equip snap  %-28s -> %s" % [_v(obstructed), _v(snap)])
	if not _near(obstructed, snap):
		_fail("%s: equip() snaps to %s, not the declared holster pose %s" % [
			path.get_file(), _v(snap), _v(obstructed)])
	# Freed explicitly: these were never in the tree, so nothing else will, and the
	# renderer's dummy backend aborts on teardown with live instances left over.
	item.free()


func _settle(item: Node3D, obstructed: bool) -> Vector3:
	var vm: Node3D = item.get("viewmodel")
	var d := 1.0 / 60.0
	for _f in SETTLE_FRAMES:
		item.update_view(d, 0.0, obstructed, false)
	return vm.rotation_degrees


# Angle comparison has to wrap: 359 degrees and -1 are the same pose, and the
# default holster yaw of 270 comes back as -90.
func _near(a: Vector3, b: Vector3) -> bool:
	for pair in [[a.x, b.x], [a.y, b.y], [a.z, b.z]]:
		var diff: float = fmod(absf(pair[0] - pair[1]), 360.0)
		if minf(diff, 360.0 - diff) > TOL:
			return false
	return true


func _v(v: Vector3) -> String:
	return "(%7.2f,%8.2f,%7.2f)" % [v.x, v.y, v.z]


func _fail(msg: String) -> void:
	_fails += 1
	print("     >> FAIL: %s" % msg)


# ─────────────────────────────────────────────
# THE LANCE THRUST LANDS ON TIME AND AT FULL REACH
# ─────────────────────────────────────────────
# The thrust is the one pose movement in the game with a DEADLINE: it has to be
# fully out at the moment _strike() fires, or the hit lands on a lance that is
# still halfway there.
#
# It used to be folded into _get_pose_target() and therefore lerped at
# pose_speed, which chases and never arrives — so it reached roughly four fifths
# of its extension by impact and peaked afterwards. It reads as a shove. It is
# applied through _extra_position() now, outside the lerp, so the numbers below
# are the numbers the player sees.
func _check_lance_thrust() -> void:
	var packed := load("res://Character/weapon/repair_lance_hud_weapon.tscn") as PackedScene
	var lance: Node3D = packed.instantiate()
	lance.initialize(null, null, null)
	var vm: Node3D = lance.get("viewmodel")
	lance.equip()
	var d := 1.0 / 60.0
	# Past the raise, or primary_pressed() refuses the swing.
	for _f in 200:
		lance.update_view(d, 0.0, false, false)
	var rest: Vector3 = vm.position

	lance.primary_pressed()
	var reach: float = float(lance.thrust_distance)
	var impact_at_s: float = float(lance.swing_time) * float(lance.impact_at)
	var peak: float = 0.0
	var t_full: float = -1.0
	var at_impact: float = -1.0
	var elapsed: float = 0.0
	for _f in 200:
		lance.tick(d)
		lance.update_view(d, 0.0, false, false)
		elapsed += d
		var out: float = rest.z - vm.position.z          # -Z is forward
		peak = maxf(peak, out)
		if t_full < 0.0 and out >= reach * 0.95:
			t_full = elapsed
		if at_impact < 0.0 and elapsed >= impact_at_s:
			at_impact = out

	print("")
	print("  repair lance thrust")
	print("     reach %.3f m, impact at %.3f s" % [reach, impact_at_s])
	print("     95%% out at %.3f s, %.0f%% extended when the hit lands, peak %.3f m" % [
		t_full, (at_impact / reach) * 100.0, peak])

	if not (t_full > 0.0 and t_full <= impact_at_s + 0.02):
		_fail("the lance is not out by the time it connects: 95%% at %.3fs vs impact at %.3fs" % [
			t_full, impact_at_s])
	# The whole complaint was that it felt slow. A sixth of a second reads as a jab.
	if t_full > 0.20:
		_fail("the out-stroke takes %.3fs, which is too slow to read as a thrust" % t_full)
	# And it has to actually ARRIVE, which the lerped version did not.
	if at_impact < reach * 0.95:
		_fail("only %.0f%% extended at impact — the thrust is being chased, not driven" % (
			(at_impact / reach) * 100.0))
	if peak > reach * 1.05:
		_fail("overshoots its reach: peak %.3f vs %.3f" % [peak, reach])

	# It must come home, or the lance creeps forward a little on every swing.
	for _f in 200:
		lance.tick(d)
		lance.update_view(d, 0.0, false, false)
	var settled: float = absf(rest.z - vm.position.z)
	if settled > 0.01:
		_fail("does not return to rest: %.3f m still extended after the swing" % settled)
	lance.free()
