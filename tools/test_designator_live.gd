extends SceneTree

# ─────────────────────────────────────────────
# THE DESIGNATOR, IN THE PLAYER'S HANDS.
#
# tools/test_designator.gd pins the ORDER — who answers, where it lands, what
# the refusals say — by building squads directly. None of that proves the tool
# exists. This boots the real world and checks the half that is wiring, which is
# the half that fails silently:
#
#   * IT IS ON A KEY. The first attempt gave it equipment_order -1, which put it
#     on key 4 and pushed a Utility Harness's third throwable off the end of the
#     row where nothing could select it. It now reserves key 7 instead, and
#     "reserved" is only true if item_for_slot(6) returns it.
#
#   * THE SCREEN IS LIVE. The readout is a SubViewport drawn onto the slab's
#     material, and the material is a shared sub-resource — so it is duplicated
#     before the texture goes on. If that wiring breaks, the tool still works
#     perfectly and the player holds a blank slab, which gets reported as "the
#     designator does nothing".
#
#   * IT COMES UP WITH NOTHING FITTED. A designator that refuses to draw while
#     the squad carries no kit hides the one screen that tells the player the
#     shop sells smoke.
#
# Boots world.tscn with autosave OFF: this reads the save on this machine and
# must never write it.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-58s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-58s got %s, wanted %s" % [label, str(got), str(want)])


func _find(node: Node, named: String) -> Node:
	if node.name == named:
		return node
	for kid in node.get_children():
		var hit := _find(kid, named)
		if hit != null:
			return hit
	return null


func _init() -> void:
	await process_frame
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame

	# BY GROUP, not by name. The player node is called `test_character` in
	# world.tscn — looking for "Player" finds nothing and every check below then
	# fails for the wrong reason.
	var player: Node3D = get_first_node_in_group("player") as Node3D
	if player == null:
		player = _find(root, "test_character") as Node3D
	_check("there is a player", player != null, true)
	if player == null:
		print("FAIL — nothing else can be checked")
		quit(1)
		return

	var loadout = player.get("loadout")
	_check("the player has a loadout", loadout != null, true)

	print("IT IS ON A KEY, AND NOT ONE A GRENADE WANTED")
	var tool_node = _find(player, "Designator")
	_check("the designator is in the player's hands", tool_node != null, true)
	if tool_node == null:
		print("FAIL — nothing else can be checked")
		quit(1)
		return
	_check("it reserves an action rather than a row position",
		str(tool_node.fixed_slot_action), "2")
	_check("...which the loadout lists", loadout.slot_actions.has(&"2"), true)
	_check("key 2 draws it", loadout.item_for_slot(1) == tool_node, true)
	# THE REGRESSION THAT CAUGHT THE FIRST ATTEMPT: keys 4-6 still belong to
	# whatever the player bought, and the built-in is not standing in one.
	for i in [0, 3, 4, 5]:
		_check("key %d is still the player's own" % (i + 1),
			loadout.item_for_slot(i) != tool_node, true)
	_check("the loadout can find its slot back again",
		loadout._slot_index_for_item(tool_node), 1)

	print("IT COMES UP EVEN WITH NOTHING TO DESIGNATE")
	_check("it can be equipped regardless", tool_node.can_equip(), true)
	loadout.equip_slot(1)
	for _i in 10:
		await physics_frame
	_check("...and pressing 2 actually draws it", loadout.current == tool_node, true)
	# Whatever the squad happens to carry on this save, the readout must be
	# words rather than an empty string — an empty label is a blank screen.
	_check("the screen has something to say", tool_node.mode_label() != "", true)
	print("      it reads: %s / %d can answer / %d mode(s)" % [
		tool_node.mode_label(), tool_node.mode_holders(), tool_node.mode_count()])

	print("THE SCREEN IS LIVE")
	var screen = tool_node.screen
	_check("the slab has a screen mesh", screen != null, true)
	var readout = tool_node.get_node_or_null("DesignatorModel/Readout")
	_check("...with a readout viewport behind it", readout != null, true)
	_check("...which knows which tool it is drawing",
		readout != null and readout.tool_node == tool_node, true)
	if screen != null:
		var mat = screen.material_override
		_check("the screen material carries the viewport's texture",
			mat != null and mat.albedo_texture != null, true)
		# Emissive too, or a flat green glow sits over the top of the text.
		_check("...on the emission map as well",
			mat != null and mat.emission_texture != null, true)

	print("THE HUD AGREES WITH THE TOOL")
	var r = tool_node.get_readout()
	_check("the readout names the same mode", r.label, tool_node.mode_label())
	_check("...and counts the same holders", r.primary, tool_node.mode_holders())

	if _fails == 0:
		print("ALL LIVE DESIGNATOR CHECKS PASS")
	else:
		print("LIVE DESIGNATOR FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
