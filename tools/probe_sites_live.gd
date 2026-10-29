extends SceneTree

# ─────────────────────────────────────────────
# IS EVERY SITE ACTUALLY A SITE NOW — loading the level ALONE?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_sites_live.gd
#
# probe_bunker_sites.gd stood each slice up by hand to test the kit. This one
# does not: it loads the nine levels exactly as the game does and asks whether
# the slice node authored INTO them built a site. If a .tscn edit is wrong, or
# a level is regenerated from a template and loses its slice, this is what says
# so — and that is the failure mode the recon warned about for Georgetown,
# Polaris and Trenchline, where a --force-level rebuild drops the node with no
# error at all.
#
# "the nine levels exactly as the game does" USED TO BE A TYPED TABLE HERE, and
# it was wrong about the first row (backlog H14): it named the RETIRED
# maps/hillfort_level.tscn, while the campaign has deployed
# maps/hillfort_wip_level.tscn since the Hillfort was rebuilt. So the probe that
# exists to catch a level losing its slice was reporting `ok` on a level the
# game does not load, and never looked at the one it does. The levels now come
# from tools/_live_sites.gd, which reads Env/world.tscn's `missions` array —
# same principle as the suite runner reading `# BUCKET:` off each file instead
# of carrying its own list. A hand-kept list in a tool IS the defect.
#
# THE SLICE IS DERIVED TOO, as the node whose script extends site_slice.gd, so a
# renamed slice node no longer reads as a missing slice. A level with NO slice
# still fails — that is the whole point of the probe and `_live_sites` hands the
# row over empty rather than dropping it.
# ─────────────────────────────────────────────

const Sites := preload("res://tools/_live_sites.gd")

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var skipped := Sites.sim_levels()
	if not skipped.is_empty():
		# Named rather than dropped: a sim arena is the practice track (§15),
		# it is not territory and it carries no slice on purpose.
		print("sim arenas, not sites, skipped: %s" % ", ".join(skipped))
	print("site         slice  cores  bunker  operation  verdict")
	for s in Sites.sites():
		await _one(s.label, s.level, s.node)
	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, level_path: String, node_name: String) -> void:
	var level = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 60:
		await physics_frame

	# An empty name is _live_sites saying it found no slice script in this level
	# at all — kept as a row and failed below, never dropped.
	var slice = level.get_node_or_null(NodePath(node_name)) if node_name != "" else null
	var cores := 0
	var has_bunker := false
	var has_op := false
	if slice != null:
		has_op = slice.operation != null and is_instance_valid(slice.operation)
		if has_op:
			cores = slice.operation.cores.size()
			has_bunker = slice.operation.bunker != null
	var bad: Array = []
	if slice == null:
		bad.append("NO SLICE NODE IN THE LEVEL")
	else:
		if not has_op:
			bad.append("no operation")
		if cores < 1:
			bad.append("no cores")
		if not has_bunker:
			bad.append("no bunker")

	print("%-12s %-6s %5d  %-6s  %-9s  %s" % [
		label, "yes" if slice != null else "NO", cores,
		"yes" if has_bunker else "NO", "yes" if has_op else "NO",
		"ok" if bad.is_empty() else "FAIL: " + str(bad)])
	if not bad.is_empty():
		_fails += 1
	level.queue_free()
	await process_frame
