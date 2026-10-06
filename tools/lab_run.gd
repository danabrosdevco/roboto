extends SceneTree

# ─────────────────────────────────────────────
# RUN A LABORATORY PLAN AND PRINT ITS RESULTS.
#
# tools/test_lab.gd proves the Laboratory WORKS, on a two-robot plan. This runs
# a REAL plan off disk and reports what it found, which is what you need when
# the question is "did that AI change alter how fights go" rather than "does the
# lab still function".
#
#   godot --audio-driver Dummy --path . --script res://tools/lab_run.gd -- <plan> [speed] [repeats]
#   ... -- engagement_range 8 2
#
# `plan` is a file in Campaign/lab/plans, with or without .tres.
# `speed` overrides the plan's time scale; higher finishes sooner and is the
# first thing to lower if results look unstable.
# `repeats` overrides every matchup's repeat count.
#
# RUN IT ON A QUIET MACHINE. The fights are simulated in game time, so anything
# else competing for the CPU does not merely slow the run down — it can wedge it
# (a previous attempt managed three seconds of CPU in twenty-one minutes against
# another process spawning Godot in a loop). If it has not finished in the time
# you expect, that is why.
#
# HEADLESS. Nothing is drawn and nothing is written to a campaign: lab mode runs
# with autosave off, and SaveSlots points itself at a sandbox under --script.
# ─────────────────────────────────────────────

const PLAN_DIR := "res://Campaign/lab/plans"
## Wall-clock ceiling. A plan that has not finished by now is wedged, not slow,
## and saying so beats hanging until somebody notices.
const PATIENCE := 2400.0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: lab_run.gd -- <plan name> [speed] [repeats]")
		var dir := DirAccess.open(PLAN_DIR)
		if dir != null:
			printerr("plans: %s" % ", ".join(dir.get_files()))
		quit(2)
		return
	var name: String = str(args[0]).trim_suffix(".tres")
	var path := "%s/%s.tres" % [PLAN_DIR, name]
	if not ResourceLoader.exists(path):
		printerr("lab_run: no plan at %s" % path)
		quit(1)
		return
	await process_frame

	var plan = load(path)
	if args.size() > 1:
		plan.speed = float(args[1])
	if args.size() > 2:
		for m in plan.matchups:
			m.repeats = int(args[2])

	var fights := 0
	for m in plan.matchups:
		fights += int(m.repeats) * (2 if m.swap_sides else 1)
	print("PLAN  %s — %d matchup(s), %d fight(s), speed %.1f" % [
		plan.title if "title" in plan else name, plan.matchups.size(), fights, plan.speed])

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.lab_mode = true
	master.lab_plan = plan
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	# NEVER a real campaign. Lab mode does not award anything, but autosave off
	# is the belt to that braces.
	cm.autosave = false
	root.add_child(master)

	var waited := 0.0
	var spoke := 0.0
	while master._menu != "lab" and waited < PATIENCE:
		await process_frame
		waited += root.get_process_delta_time()
		# A long plan with no output looks identical to a wedged one. Say
		# something every half minute so the difference is visible.
		if waited - spoke > 30.0:
			spoke = waited
			print("  ... %.0f s" % waited)
	if master._menu != "lab":
		printerr("lab_run: no results after %.0f s — wedged, not slow. Check nothing else is using the CPU." % waited)
		quit(1)
		return

	print("")
	print("RESULTS after %.0f s" % waited)
	var results = master.lab_results if "lab_results" in master else null
	if results == null:
		# EVERY EMPTY RESULT SAYS WHY. The run finished; if the figures are not
		# where this expects them, that is a different problem to a failed run.
		printerr("lab_run: the plan finished but Master exposes no lab_results to print.")
		quit(1)
		return
	print(JSON.stringify(results, "\t"))
	quit(0)
