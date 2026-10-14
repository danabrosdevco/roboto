extends SceneTree

# ─────────────────────────────────────────────
# WATCH A LABORATORY PLAN. Same fights as tools/lab_run.gd, on screen.
#
#   godot --audio-driver Dummy --path . --script res://tools/lab_watch.gd -- bulwark_screen
#   ... -- bulwark_screen 0.5          # half speed, to actually see the arm move
#
# NO --headless. That is the whole point: lab_run prints a table, this one
# shows you the fight.
#
# WHY A SCRIPT AND NOT THE TICKBOX. `lab_mode` is an @export on master.tscn, so
# the documented way in is to tick it in the editor — but master.tscn is shared
# with two other lanes and a scene saved with lab_mode on would send everybody
# into the arena instead of the game. This sets the same two fields on an
# INSTANCE, exactly as tools/lab_run.gd already does, and touches nothing on
# disk.
#
# SPEED IS THE FIRST THING TO TURN. The plan ships at 1.0 and a rifle fight at
# 45 m is over in eight seconds. Pass 0.5 and watch the arm track; pass 2.0 if
# you only want to see who wins.
#
# IT CLOSES ITSELF when the plan is done, and prints the same summary lab_run
# does. Close the window early if you have seen enough — nothing is saved
# either way, lab mode runs with autosave off.
# ─────────────────────────────────────────────

const PLAN_DIR := "res://Campaign/lab/plans"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("lab_watch: this is the one you WATCH. Drop --headless, or use tools/lab_run.gd.")
		quit(1)
		return

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("lab_watch: name a plan. Available:")
		var dir := DirAccess.open(PLAN_DIR)
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".tres"):
					printerr("  %s" % f.get_basename())
		quit(1)
		return

	var name: String = args[0]
	if not name.ends_with(".tres"):
		name += ".tres"
	var path := "%s/%s" % [PLAN_DIR, name]
	if not ResourceLoader.exists(path):
		printerr("lab_watch: no plan at %s" % path)
		quit(1)
		return
	var plan: Resource = load(path)

	var master: Node = load("res://Managers/master.tscn").instantiate()
	master.lab_mode = true
	master.lab_plan = plan
	# SPEED IS THE PLAN'S, unless overridden here. Set on the plan object we
	# just loaded rather than on the file — this is a view, not an edit.
	if args.size() > 1:
		plan.speed = maxf(float(args[1]), 0.1)

	# NO AUTOSAVE, the same guard lab_run relies on. Lab mode already runs with
	# saving off, but this boots the real Master and the cost of being wrong is
	# the player's campaign, so it is stated here too rather than assumed.
	var cm: Node = master.find_child("CampaignManager", true, false)
	if cm != null and "autosave" in cm:
		cm.autosave = false

	root.add_child(master)
	print("lab_watch: %s  (speed %.2f)" % [plan.title, float(plan.speed)])
	print("           close the window when you have seen enough.")

	# Wait for it to finish, then print what lab_run would have.
	var waited := 0.0
	while waited < 1800.0:
		await process_frame
		# SceneTree has no delta of its own; this is only a runaway timeout.
		waited += 1.0 / 60.0
		if not is_instance_valid(master):
			break
		var done = master.get("lab_results") if "lab_results" in master else null
		# _menu == "lab" IS the results screen, set once the plan is done.
		if done != null and not (done as Array).is_empty() and master._menu == "lab":
			break
	if is_instance_valid(master):
		var res = master.get("lab_results") if "lab_results" in master else null
		if res != null:
			print("")
			for row in res:
				print("  %s" % str(row))
	quit(0)
