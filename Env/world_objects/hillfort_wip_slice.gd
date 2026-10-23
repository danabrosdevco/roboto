extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# HILLFORT REDOUBT, AS A SITE.
#
# The alternative first mission. Same idea as Hillfort at a quarter of the
# size: TERRAIN measured the shipped one at 0.43 km² with two capture points —
# 217,440 m² per objective, 3.5x sparser than the next worst map in the project
# — and rebuilt it at 0.0983 km² with six. See
# docs/briefs/archive/HILLFORT_WIP_HANDOVER.md, which is the contract this file keeps.
#
# IT DOES NOT REPLACE loc_hillfort. Both are first sites and both gate off
# arena_3_firing_line, so the campaign offers a fork and the two can be played
# against each other. Deciding which one ships is a judgement about how it
# FEELS, and nobody here can make that call.
#
# SIX CORES, ALREADY AUTHORED. Unlike the other nine sites, the level instances
# real compute_core_point prefabs with their own ids, names and rewards — so
# this slice only has to seat a HoldableCore on each, which is what
# cores_by_node does. _build_core_body bails on a host that already has a Core,
# so nothing is doubled.
#
# THE COUNT PER LANE IS THE DESIGN, not an oversight: centre 1, west 2, east 2,
# and the relay in the fort. The short exposed lane pays for its speed in what
# it does not pick up, and an operation is won at the BUNKER rather than by
# clearing the board — which is why all six are `optional` in the level.
# ─────────────────────────────────────────────


func _init() -> void:
	# BEFORE _ready, which is where site_slice reads all of this.
	#
	# BY NODE NAME, not by tag — site_slice._find() matches node names, and the
	# handover's tag table lists tags. That mismatch silently resolved nothing
	# on all eight of the earlier conversions before it was caught.
	#
	# THE TIER IS THE PREFAB, and a mismatch is not cosmetic: _fit_reach sizes
	# the interact volume from it, and a tier too small puts the player INSIDE
	# the volume where the ray reports nothing to press. Five of these are
	# compute_core_point (tier 1); RelayCore is compute_core_point_large
	# (tier 2). Checked against the level file, not assumed.
	cores_by_node = {
		"CisternCore": 1, "ShoulderCore": 1, "PillarsCore": 1,
		"GatehouseCore": 1, "TerraceCore": 1,
		"RelayCore": 2,
	}

	# THE WAY DOWN — a tunnel mouth driven into the back of the north rampart.
	bunker_marker = &"HFW_Bunker"
	bunker_fallback = Vector3(6.0, 34.0, -99.0)
	bunker_tier = 1

	# CLIFF, WHICH IS A FIT AS WELL AS A JUDGEMENT. TERRAIN measured it: `open`
	# is 33.8 m deep with its sunken court and the yard between the dish's north
	# face and the curtain is 30.6, so it does not go in. `cliff` is 18.3 and
	# leaves 12 m spare, and its revetted headwall is what a tunnel mouth driven
	# into a rampart looks like. `wall` needs a ceiling and there is none.
	bunker_mount = &"cliff"
	bunker_offset = Vector3.ZERO

	# LEFT AS AUTHORED, which is TERRAIN's option 1 and NOT the option they
	# recommended. §4 of the handover asked GAMEPLAY to settle the bunker's
	# facing and preferred turning it 90°, on the grounds that the relay dish's
	# pedestal stands 17 m in front of the doors and fills the arrival frame.
	#
	# SO IT WAS PHOTOGRAPHED, at all four quarters, from the mouth at the real
	# 1.50 m eye with the doors driven open through the slice's own handler —
	# tools/shot_bunker_arrival.gd. The recommendation does not survive it:
	#
	#     0   dish pedestal to the RIGHT of frame, the yard opening out to the
	#         left, the curtain and the gate structures in view.   clear 60 m
	#    90   square into the Data Hall, which stands 14 m east. blocked 20.8 m
	#   180   into the rampart the tunnel is driven through.      blocked 12.0 m
	#   270   open, but a featureless apron facing away from the fort. clear 60 m
	#
	# The dish does not fill the frame from the doorway once the doors are
	# open; it stands beside it. §12.8 wants ground in front of the doors to
	# turn round and hold, and 0 is the only facing with both that AND the dish
	# in shot. Turning it would have bought a wall.
	#
	# The export it was measured with stays, because it is how the next one of
	# these gets settled by looking rather than by arguing.
	bunker_yaw = 0.0

	# Where heat-committed reinforcements walk on from. All three lanes, so
	# pressure does not arrive down the one the player happens to be in — the
	# whole point of a three-lane map is that the other two still exist.
	entry_markers_named = [&"HFW_SouthMeadow", &"HFW_WestFlank",
		&"HFW_EastFlank"] as Array[StringName]

	# MEASURED off mission_hfw_1_fort's roster with tools/measure_resistance.gd,
	# not typed: §2 is explicit that resistance is supply. 79 total, which is
	# hillfort_1_relay's number to the unit — deliberately, because two first
	# missions that cost different amounts cannot be compared.
	# The Location overrides this at runtime; this is the standalone answer.
	resistance = 45

	# A QUARTER OF THE GROUND, so an assault crosses it in less than half the
	# time. Hillfort's 300 s is paced against a 430 m climb; the longest leg
	# here is the 281 m west lane and the shortest is 108 m.
	defence_assault_seconds = 240.0
	stand_down_seconds = 45.0

	# The plateau is at y 34 with open sky above it, so the default beacon
	# column is fine here.
