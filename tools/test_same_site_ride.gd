extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# NO JOURNEY TO A PLACE YOU ARE ALREADY AT.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_same_site_ride.gd
#
# Take a site, have the enemy raid it on the next turn, and the defence is
# fought on ground the train is already standing at. Playing the full ride for
# that is a lie the player can read: ten seconds of tunnel going past the
# windows and the doors open onto the same platform they shut on.
#
# So DepartureRide.begin() skips straight to the arrival when the destination
# matches Campaign.last_site. The arrival is NOT skipped — the doors open, the
# pad is armed and `arrived` fires exactly as they do after a real ride, because
# everything downstream of the train hangs off those three things.
#
# WHAT THIS GUARDS, and why each one is worth a check:
#
#   - last_site is set when a mission is extracted from, or the train never
#     knows where it is and always rides.
#   - an UNKNOWN position rides. That is the fresh-boot case and a ride is a
#     second of spectacle; refusing to ride on no information would open the
#     doors onto a platform the player never travelled to.
#   - a DIFFERENT site rides.
#   - the sim arena, which deliberately has no Location, rides.
#   - the skip still arms the pad. Forgetting that is a soft-lock: doors open,
#     nothing to walk into.
# ─────────────────────────────────────────────

const RIDE := preload("res://Env/world_objects/departure_ride.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cm = preload("res://Campaign/campaign.gd").new()
	cm.name = "Campaign"
	cm.add_to_group(&"campaign")
	root.add_child(cm)
	cm.reset_campaign()

	_check("Campaign carries a last_site", &"last_site" in cm)
	_check("a fresh campaign does not claim to be anywhere", cm.last_site == &"")

	# A real mission and the Location it resolves to, read off the catalogue
	# rather than invented — an id that does not exist would pass every check
	# here by resolving to null on both sides.
	var mission = _first_site_mission(cm)
	if mission == null:
		_check("found a mission with a Location to test against", false)
		_done()
		return
	var site = cm.state.locations.for_mission(mission.id)
	_check("found a mission with a Location to test against", true,
		"%s -> %s" % [mission.id, site.id])

	var ride = RIDE.new()
	root.add_child(ride)

	# ── UNKNOWN POSITION RIDES ────────────────
	cm.last_site = &""
	_check("an unknown position rides", not ride._already_there(mission))

	# ── A DIFFERENT SITE RIDES ────────────────
	cm.last_site = &"somewhere_else_entirely"
	_check("a different site rides", not ride._already_there(mission))

	# ── NO MISSION RIDES ──────────────────────
	_check("a departure with no mission rides", not ride._already_there(null))

	# ── THE SAME SITE DOES NOT ────────────────
	cm.last_site = site.id
	_check("the same site skips the ride", ride._already_there(mission))

	# ── AND THE SKIP STILL ARRIVES PROPERLY ───
	# A stub in place of the real LevelExit: begin() must still arm it, or the
	# doors open onto a pad that refuses to deploy.
	var pad := _Pad.new()
	ride.exit_to_arm = pad
	var seen := {}
	ride.arrived.connect(func(_m): seen["arrived"] = true)
	ride.begin(mission)
	_check("the skip arrives at once", ride.arrived_already and not ride.running)
	_check("the skip arms the departure pad", pad.armed)
	_check("the skip still emits arrived", seen.has("arrived"))

	# ── AND A REAL RIDE DOES NOT SHORT-CIRCUIT ─
	var ride2 = RIDE.new()
	root.add_child(ride2)
	var pad2 := _Pad.new()
	ride2.exit_to_arm = pad2
	cm.last_site = &"somewhere_else_entirely"
	ride2.begin(mission)
	_check("a real departure is still running after begin", ride2.running and not ride2.arrived_already)

	# BOTH STUBS FREED BY HAND. Neither is parented — a LevelExit normally is,
	# but `exit_to_arm` is only read, never walked — so nothing else will ever
	# free them, and both showed up as `Leaked instance: Node3D` under
	# --verbose. Measured 2026-10-26: a script-only orphan like this leaks the
	# ObjectDB instance and its inner-class GDScript, but drags no PATHED
	# resource and no RID to the sweep, so it is the mild end of the family in
	# Traps ("an orphaned node that keeps a Resource alive") — still the rule.
	pad.free()
	pad2.free()
	_done()


func _done() -> void:
	print("")
	print("PASS" if _fails == 0 else "FAIL  %d check(s) failed" % _fails)
	quit(0 if _fails == 0 else 1)


## The first mission the catalogue can resolve to a Location. Not hard-coded:
## mission ids move, and a test that pins one is a test that goes red for a
## rename rather than for a regression.
##
## READ OFF DISK, not off cm.missions — `missions` is an  filled in by
## world.tscn, so a bare Campaign.new() has an empty one and every lookup here
## would quietly resolve to null and pass.
func _first_site_mission(cm):
	if cm.state == null or cm.state.locations == null:
		return null
	var dir := DirAccess.open("res://Campaign/missions")
	if dir == null:
		return null
	var names := dir.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".tres"):
			continue
		var m = load("res://Campaign/missions/" + f)
		if m == null:
			continue
		if cm.state.locations.for_mission(m.id) != null:
			return m
	return null


## Stands in for the LevelExit the ride arms. Only `arm` is reached.
##
## Node3D, because `exit_to_arm` is typed Node3D and a plain Node is refused
## at assignment — which is the export doing its job.
class _Pad extends Node3D:
	var armed: bool = false

	func arm() -> void:
		armed = true
