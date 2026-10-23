extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# HILLFORT, AS A SITE.
#
# The first real site, and the simplest: one core on the fort bench and one way
# up to it. site_slice.gd holds all the behaviour; this is only Hillfort's
# answers to it.
#
# IT GETS A DEFENCE LIKE EVERY OTHER SITE, decided 2026-10-14. The shape
# argument against it was real and is recorded here rather than deleted: its own
# briefing says "one way
# on" and the measurement agrees — a single entry at the trailhead, one core, no
# flanks and nothing to cover. Every site is defensible now, so the job here is
# to MAKE it defensible rather than to skip it: the defence leans on the three
# entry markers below arriving from different sides of the hill, because the
# trail alone would be a queue.
#
# It is still the right opening site, and its defence is the gentlest on the
# board. See docs/briefs/archive/ATTACK_AND_DEFEND.md.
# ─────────────────────────────────────────────


func _init() -> void:
	# BEFORE _ready, which is where site_slice reads all of this.
	#
	# ONE CORE. Named by NODE NAME, not by tag — site_slice._find() matches
	# node names, and every marker table in SITE_CONVERSION.md lists tags. That
	# mismatch would have silently resolved nothing on all eight maps.
	cores_by_node = {"RelayObjective": 1}

	# THE BUNKER — the hall roof, which is the exit pad to the metre.
	# Hillfort_Roof is an authored squad objective point already standing where
	# the operation ends, so the bunker reads its position rather than carrying
	# a copy of it.
	# THE POSTERN, OUTSIDE THE FORT. The way down is a back entrance in the
	# hillside, not a hatch on the hall roof — a station entrance belongs at the
	# foot of a wall you can drive to, and the roof pad was only ever where the
	# old extraction happened to be.
	bunker_marker = &"Hillfort_Postern"
	bunker_fallback = Vector3(54.0, 132.0, -325.0)
	bunker_tier = 1

	# Where heat-committed reinforcements walk on from. The trail is the only
	# genuine approach; the saddle and the shoulder at least arrive from a
	# different side of the hill than the player did.
	entry_markers_named = [&"Hillfort_Trailhead", &"Hillfort_Saddle",
		&"Hillfort_Shoulder"] as Array[StringName]

	# Off loc_hillfort, which measured it. The Location overrides this at
	# runtime; this is the standalone-probe answer.
	resistance = 79
	# A 430 m climb from the trailhead, so an assault takes longer to arrive
	# than the basin's 240 s allows for.
	defence_assault_seconds = 300.0
	stand_down_seconds = 45.0
	# The fort bench is at y 132 with open sky above it, so the default 34 m
	# column is fine here.
