extends SceneTree

# ─────────────────────────────────────────────
# WHAT FIRING A WEAPON DOES TO THE CAMERA, IN DEGREES.
#
# Recoil is the one system in this project you cannot judge from a render and
# cannot judge from reading the numbers, because the number in the scene is not
# the number you feel: the kick is ADDED every frame while a lerp drags the
# camera back, so the offset you actually see is roughly the per-frame add
# divided by (delta * look_interp_speed). A `recoil_per_shot` of 6.5 means
# nothing until you run it.
#
# So this runs it. It replays hud_weapon_template.gd's exact arithmetic at
# 60fps for a burst, and prints the peak pitch and yaw the player would see.
#
# TWO THINGS IT GUARDS, both of which shipped broken:
#
#  1. YAW MUST COME BACK. cam.rotation.y had no line pulling it toward a rest
#     value — the player BODY carries yaw, so nothing ever wrote it — and the
#     `+=` accumulated for as long as the trigger was held. The Ancient Rifle
#     walked the camera 160 degrees off to the left. A bound on peak yaw is the
#     only test that would have caught it, because every static value involved
#     looked reasonable.
#
#  2. EVERY PLAYER WEAPON NEEDS A CURVE. `recoil_curve.sample()` is guarded by
#     a null check that used to fall back to 0.0, so a weapon without a curve
#     had no camera recoil whatever its other numbers said. Only the Ancient
#     Rifle had one. Three weapons shipped feeling inert and it read as a
#     tuning problem rather than a missing resource.
#
# The peaks are PRINTED, not asserted tightly — the right feel is the human's
# call and these are dials. The bounds are only there to catch a kick that has
# stopped being a kick and become a bug.
# ─────────────────────────────────────────────

const FPS := 60.0
const BURST := 2.0          # seconds of held trigger
const SETTLE := 1.0         # seconds after the last shot, to prove it returns

# Every weapon the player can hold. A weapon missing from here is not tested,
# so it is a list rather than a scan of the folder on purpose: an AI-only
# weapon has no camera to kick.
const WEAPONS := [
	"res://Character/weapon/m4_hud_weapon.tscn",
	"res://Character/weapon/bolt_hud_weapon.tscn",
	"res://Character/weapon/squad_auto_hud_weapon.tscn",
	"res://Character/weapon/cluster_hud_weapon.tscn",
]

## Past this and it is not recoil any more. The bug that prompted this test
## reached 160 degrees; a hard-kicking rifle is nowhere near 30.
const YAW_LIMIT := 30.0
const PITCH_LIMIT := 45.0
## And it has to come back down once you stop firing.
const REST_LIMIT := 1.0

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	for path in WEAPONS:
		if not ResourceLoader.exists(path):
			_check("%s exists" % path.get_file(), false, "no such scene")
			continue
		var gun: Node = (load(path) as PackedScene).instantiate()
		_run(gun, path.get_file())
		gun.free()
		print("")

	print("RECOIL FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL RECOIL CHECKS PASS")
	quit(1 if _fails > 0 else 0)


func _run(gun: Node, label: String) -> void:
	var curve: Curve = gun.get("recoil_curve")
	_check("%s has a recoil_curve" % label, curve != null,
		"without one the camera does not move at all, whatever its other numbers say")
	if curve == null:
		return

	var duration: float = float(gun.get("recoil_duration"))
	var per_shot: float = float(gun.get("recoil_per_shot"))
	var pitch_scale: float = float(gun.get("camera_recoil_scale"))
	var yaw_scale: float = float(gun.get("camera_recoil_yaw_scale"))
	var interp: float = float(gun.get("look_interp_speed"))
	var rate: float = maxf(float(gun.get("FIRE_RATE")), 1.0 / FPS)
	var settle_shots: int = int(gun.get("settle_shots"))
	var settle_to: float = float(gun.get("settle_to"))
	# MANUAL and SEMI cannot be held down: the cycle gate and the trigger both
	# stop them, so simulating automatic fire from them would report a climb no
	# player can produce. Enums.FireModes: 0 SEMI, 1 FULL, 2 MANUAL.
	var automatic: bool = int(gun.get("firemode")) == 1
	var shot_gap: float = rate if automatic else maxf(rate, duration * 1.6)

	# WORST CASE, NOT AVERAGE. recoil_yaw_kick rolls randf_range(0.55, 1.0) per
	# burst; the bound has to hold on the roll that kicks hardest.
	var yaw_kick: float = 1.0 * per_shot * yaw_scale

	var dt := 1.0 / FPS
	var timer := 0.0
	var burst_shots := 0
	var cam_pitch := 0.0
	var cam_yaw := 0.0
	var peak_pitch := 0.0
	var peak_yaw := 0.0
	var first_kick := 0.0
	var last_kick := 0.0
	var next_shot := 0.0
	var t_now := 0.0
	var shots := 0

	while t_now < BURST + SETTLE:
		if t_now < BURST and t_now >= next_shot:
			if timer <= 0.0:
				burst_shots = 0
			else:
				burst_shots += 1
			timer = duration
			next_shot += shot_gap
			shots += 1

		var cur_pitch := 0.0
		var cur_yaw := 0.0
		if timer > 0.0:
			timer -= dt
			var t: float = clampf(1.0 - (timer / duration), 0.0, 1.0)
			var scale := 1.0
			if settle_shots > 0:
				scale = lerpf(1.0, settle_to, clampf(float(burst_shots) / float(settle_shots), 0.0, 1.0))
			var kick: float = curve.sample(t) * scale
			cur_pitch = kick * per_shot * pitch_scale
			cur_yaw = kick * yaw_kick
			if shots == 1:
				first_kick = maxf(first_kick, absf(cur_pitch))
			last_kick = absf(cur_pitch)

		# The template's own two lines, in the same order.
		cam_pitch = lerp_angle(cam_pitch, 0.0, dt * interp) + deg_to_rad(cur_pitch)
		cam_yaw = lerp_angle(cam_yaw, 0.0, dt * interp) + deg_to_rad(cur_yaw)
		peak_pitch = maxf(peak_pitch, absf(rad_to_deg(cam_pitch)))
		peak_yaw = maxf(peak_yaw, absf(rad_to_deg(cam_yaw)))
		t_now += dt

	var rest_pitch := absf(rad_to_deg(cam_pitch))
	var rest_yaw := absf(rad_to_deg(cam_yaw))
	print("  %-26s %d shots | peak pitch %6.2f deg | peak yaw %6.2f deg | settles to %.2f / %.2f" % [
		label, shots, peak_pitch, peak_yaw, rest_pitch, rest_yaw])
	if settle_shots > 0:
		print("      first shot kicks %.2f deg/frame, last kicks %.2f — settle_shots %d to %.2f" % [
			first_kick, last_kick, settle_shots, settle_to])

	_check("%s yaw stays a kick, not a spin" % label, peak_yaw < YAW_LIMIT,
		"peaked at %.1f deg, limit %.1f — this is the unbounded-yaw bug" % [peak_yaw, YAW_LIMIT])
	_check("%s pitch stays on the screen" % label, peak_pitch < PITCH_LIMIT,
		"peaked at %.1f deg, limit %.1f" % [peak_pitch, PITCH_LIMIT])
	_check("%s camera returns to rest after firing" % label,
		rest_pitch < REST_LIMIT and rest_yaw < REST_LIMIT,
		"left at pitch %.2f yaw %.2f after %.1fs of nothing" % [rest_pitch, rest_yaw, SETTLE])
