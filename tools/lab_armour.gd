extends SceneTree

# ─────────────────────────────────────────────
# ARMOUR BASELINE — runs Campaign/lab/plans/armour_baseline.tres headless and
# prints the two numbers the armour multipliers will move: damage a rifle puts
# into a hull, and how long the fight takes.
#
# Headless and on the clock, because this is a measurement rather than something
# to watch. Analytics switches itself off under a --script harness, so it is
# forced on here — without that every damage column comes back zero while the
# fights play out normally, which has caught this project once already.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/lab_armour.gd -- --no-save
#
# Run it again after the armour helper is in and compare. Keep the output.
# ─────────────────────────────────────────────

const _Analytics := preload("res://Managers/analytics.gd")
const PLAN := "res://Campaign/lab/plans/armour_baseline.tres"

## Override on the command line: -- --no-save --plan=res://.../other.tres


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	_Analytics.force_enable = true
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	master.lab_mode = true
	var which := PLAN
	var watch := false
	var speed := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--plan="):
			which = a.substr(7)
		elif a == "--watch":
			watch = true
		elif a.begins_with("--speed="):
			speed = a.substr(8).to_float()
	# DUPLICATED BEFORE TOUCHING IT. Resources are shared in this project, so
	# overriding the speed on the loaded plan would change it for anything else
	# holding the same one.
	var the_plan: Resource = load(which)
	if speed > 0.0:
		the_plan = the_plan.duplicate()
		the_plan.speed = speed
	master.lab_plan = the_plan
	print("lab_armour: running %s%s" % [which, "  (watching at %.1fx)" % speed if speed > 0.0 else ""])
	# NO WINDOW OVERRIDE. Setting root.size here fought the project's own display
	# mode and left the game maximised into the bottom-left corner looking broken.
	# Watch mode only means "do not quit when the results come up".
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	if cm != null:
		cm.autosave = false
	root.add_child(master)

	var waited := 0.0
	while master._menu != "lab" and waited < 600.0:
		await create_timer(0.5).timeout
		waited += 0.5
	var lab = master._lab
	if lab == null or master._menu != "lab":
		printerr("lab_armour: the plan did not reach the results screen (waited %.0fs)" % waited)
		quit(1)
		return

	print("")
	print("ARMOUR BASELINE — no armour rule in the build")
	print("%-34s %5s %6s %8s %8s %7s" % ["matchup", "runs", "ally%", "dmg A", "dmg H", "time"])
	for row in lab.summary():
		var runs := int(row["runs"])
		print("%-34s %5d %5d%% %8d %8d %6.1fs" % [
			str(row["label"]), runs,
			int(round(float(row["ally_wins"]) / maxf(1.0, float(runs)) * 100.0)),
			int(row["a_dmg"]), int(row["h_dmg"]), float(row["time"]) / maxf(1.0, float(runs))])
	print("")
	print("dmg A = damage the four troopers put into the vehicle, summed over all runs.")
	print("dmg H = damage the vehicle put into them. Report at %s" % lab.report_path)
	if watch:
		print("lab_armour: results are up — close the window when you are done.")
		return
	quit(0)
