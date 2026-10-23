extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE LAST EXERCISE TEACHES CAPTURING.
#
# The three arenas taught shooting and a squad in a fight; neither taught the
# verb the campaign is actually made of. A player reaching Hillfort having
# never worked a core meets it for the first time under fire.
#
# The Proving Ground is shared by ALL THREE arenas, so the gating matters as
# much as the core: MissionObjective._ready frees any objective the current
# operation did not ask for, and only arena_5 asks.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_training_core.gd
# ─────────────────────────────────────────────

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	# ── only the SECOND exercise asks for it ────
	# Three arenas became two: CONTACT is solo, eliminate and extract; FIRING
	# LINE is where the squad, the core and the bunker are taught. The Proving
	# Ground is shared by both, so the gating is the objective list and nothing
	# else — MissionObjective._ready frees what the operation did not ask for.
	var asks := {}
	for id in ["arena_1_contact", "arena_3_firing_line"]:
		var m = load("res://Campaign/missions/mission_%s.tres" % id)
		asks[id] = m.active_objectives.has(&"proving_capture")
	_check("THE SECOND exercise asks for the core", asks["arena_3_firing_line"])
	_check("...and the first does not — it is eliminate and extract",
		not asks["arena_1_contact"], str(asks))
	var a3 = load("res://Campaign/missions/mission_arena_3_firing_line.tres")
	_check("...and it asks for the bunker too", a3.active_objectives.has(&"proving_bunker"))

	# ── it builds a real core, not a teaching mock ──
	var lvl: Node = load("res://maps/proving_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 60:
		await physics_frame
	var tc = lvl.get_node_or_null(^"TrainingCore")
	_check("the arena carries a training core", tc != null)
	if tc == null:
		_done()
		return
	_check("...with the SAME HoldableCore the real sites use",
		tc.core != null and tc.core.has_method("start_held")
		and tc.core.has_method("_dock_y"))
	_check("...an interact volume on layer 3, where the player's ray can find it",
		tc.core.interactible != null and tc.core.interactible.collision_layer == 3,
		"layer %d" % (tc.core.interactible.collision_layer if tc.core.interactible else -1))
	# SOLID, NOT "has a node called CoreSolid".
	#
	# This checked for the placeholder's own box by name. The arena now raises
	# the REAL compute_core_point prefab (2026-10-16), which brings its own
	# StaticBody3D from maps/blocks/compute/compute_core.tscn — more solid than
	# the generated box, and under a different name.
	#
	# So it asks the question it actually cares about: is there anything the
	# player can walk into. That survives the next art change too, which the
	# node-name version did not.
	_check("...something solid to walk up to", _has_collider(tc),
		"no StaticBody3D or CollisionShape3D anywhere under it")
	_check("...and a beacon, so it can be found",
		tc.get_node_or_null(^"Signal") != null)

	# ── it ticks the objective it IS ────────────
	_check("it starts untaken", tc.progress()[0] == 0, str(tc.progress()))
	tc.core._set_holder(2)   # Holder.PLAYER
	await process_frame
	_check("HOLDING IT COMPLETES THE EXERCISE", tc.progress()[0] == 1 and tc.completed,
		"progress %s, completed %s" % [str(tc.progress()), str(tc.completed)])

	_done()


func _done() -> void:
	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## Anything the player can walk into, anywhere under this node. Deliberately
## not a name match: the placeholder builds "CoreSolid", the real prefab brings
## "entity_0_worldspawn", and a third one will be called something else again.
func _has_collider(n: Node) -> bool:
	if n is CollisionShape3D and (n as CollisionShape3D).shape != null:
		return true
	if n is StaticBody3D or n is CharacterBody3D:
		return true
	for c in n.get_children():
		if _has_collider(c):
			return true
	return false
