extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# LOCKSIDE, AS A SITE.
#
# Five cores on four benches, four ways in. The second-best defence shape after
# Three Rivers and the only one with real verticality in its PLAYABLE ground —
# its briefing's "four flat benches, not a slope" means a defender can hold a
# terrace rather than a line.
#
# THE SLICE NODE GOES IN maps/georgetown_level.tscn AT ROOT, not in the ops
# scene. site_slice._ready() searches downward from get_parent() only; inside
# georgetown_ops.tscn it would see the objectives and none of the level's own
# markers. And georgetown_level.tscn is rewritten by tools/build_georgetown.gd
# on --force-level, so the slice node needs a fourth insertion in
# tools/mission_ops.sh or it vanishes on the next rebuild with no error at all.
# ─────────────────────────────────────────────


func _init() -> void:
	cores_by_node = {"RelayPark": 0, "RelayStack": 1, "RelayLock": 1,
		"RelayStreet": 2, "RelayMill": 0}

	# THE BUNKER — the street exit at the top bench.
	bunker_marker = &"GT_StreetOut"
	bunker_fallback = Vector3(200.0, 4.0, -96.0)
	bunker_tier = 1

	# THE TOWN STOPS AT z = -140, quoted from the ops file's own header: the
	# navmesh's filter_baking_aabb starts there and nothing beyond it can be a
	# post, an objective or an entry. GT_BackLane at z -136 is deliberately the
	# last 4 m of walkable bench — do not push the north entry out any further.
	entry_markers_named = [&"GT_BackLane", &"GT_Mill", &"GT_StreetOut",
		&"GT_Pier"] as Array[StringName]

	resistance = 264
	defence_assault_seconds = 360.0
	stand_down_seconds = 45.0
	# FOUR BENCHES AT y -8, -4, 0 AND +4, under a town. A 34 m beacon from the
	# bottom bench stands through three of the others.
	beacon_height = 18.0
