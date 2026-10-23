extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# TRENCHLINE, AS A SITE.
#
# The best-shaped map of the eight and the hardest ground on the board — 365 of
# resistance against Valley Basin's 82. A literal depth ladder: front line,
# support, gun park, village, west to east.
#
# ITS FOUR CORES WERE BUILT FOR THIS. salient_ops.tscn had ZERO capture points
# until 2026-10-14 — all four of its "cores" were eliminate objectives, which
# have no Interactible and so cannot be captured. The RelayFrontLine /
# RelaySupport / RelayGuns / RelayBack instances were added alongside them and
# sit off the trench lines rather than on them, because a core standing on a
# parapet has one corner in the revetment.
#
# THE SLICE NODE GOES IN maps/salient_level.tscn AT ROOT — it cannot go in the
# ops scene. site_slice._ready() searches downward from get_parent(), and every
# entry and garrison marker this needs is a sibling of the ops node rather than
# a descendant of it. build_salient.gd leaves the level alone unless
# --force-level, which is survivable, but mission_ops.sh does not re-insert it.
# ─────────────────────────────────────────────


func _init() -> void:
	# THE DEPTH LADDER, west to east. The gun park is open ground, so it takes
	# the large core; the trench lines are tight and take smalls.
	cores_by_node = {"RelayFrontLine": 0, "RelaySupport": 1,
		"RelayGuns": 2, "RelayBack": 0}

	# THE BUNKER — the east exit, past the village.
	bunker_marker = &"LevelExitOps"
	bunker_fallback = Vector3(455.0, 1.0, 165.0)
	bunker_tier = 1

	entry_markers_named = [&"Salient_Jumpoff", &"Salient_Railhead",
		&"Salient_Village", &"Salient_Church"] as Array[StringName]

	resistance = 365
	# THE HARDEST SITE ON THE BOARD, and a 940 m map. Last to get a defence for
	# balance reasons — see docs/briefs/archive/ATTACK_AND_DEFEND.md's build order.
	defence_assault_seconds = 480.0
	stand_down_seconds = 45.0
