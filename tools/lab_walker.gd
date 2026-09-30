extends SceneTree
# Launches the Laboratory on the Walker duel plan, windowed, for watching.
# Nothing is saved: lab mode never touches the campaign, and autosave is off.
#
#   godot --audio-driver Dummy --path . --script res://tools/lab_walker.gd -- --no-save

# The lab scores its fights off analytics events, and analytics switches itself
# OFF under a --script harness (analytics.gd:_should_record) so test suites do
# not write into the playtest folder. This launcher IS a --script harness, so
# without force_enable every damage, shot and kill column comes back zero while
# the fight itself plays out normally. Master points the folder at user://lab.
const _Analytics := preload("res://Managers/analytics.gd")


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	_Analytics.force_enable = true
	root.size = Vector2i(1500, 860)
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	master.lab_mode = true
	master.lab_plan = load("res://Campaign/lab/plans/walker_duel.tres")
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	if cm != null:
		cm.autosave = false
	root.add_child(master)
	print("[LabWalker] running '%s' at %.1fx — close the window when you are done." % [
		master.lab_plan.title, float(master.lab_plan.speed)])
