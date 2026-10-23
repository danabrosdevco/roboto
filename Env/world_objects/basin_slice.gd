extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# VALLEY BASIN, AS A SITE.
#
# Everything that makes a map into a site — cores, the bunker, heat, the
# commander, the garrison, the win and the loss — lives in site_slice.gd. This
# is only the basin's ANSWERS to it, and it is deliberately the whole file:
# the measure of whether that generalisation worked is that a map costs thirty
# lines of data rather than four hundred of code.
#
# docs/briefs/archive/SITE_CONVERSION.md has the same table for the other eight,
# measured rather than guessed.
#
# WHY A SUBCLASS AND NOT EXPORTS IN THE SCENE. Both work, and the scene is
# arguably the righter Godot answer. This one touches no .tscn — the level
# gained four lines when the slice was added and has not been reopened since,
# and a hand-edited scene is the one change in this project that has gone
# wrong twice. A map whose values ARE authored in its scene will override
# these, because scene values beat script defaults.
# ─────────────────────────────────────────────


func _init() -> void:
	# BEFORE _ready, which is where site_slice reads all of this.
	#
	# THE AUTHORED CAPTURE POINTS, by node name and size. 0 small · 1 medium ·
	# 2 large. The anchor is the prize and is authored with a ten-second
	# channel, so it is the large one.
	cores_by_node = {
		"InteractObjective": 0,
		"InteractObjective2": 0,
		"InteractObjective3": 1,
		"AnchorObjective": 2,
	}

	# THE BUNKER — the way down, at the east pass.
	#
	# FOUND BY MARKER, NOT TYPED. Basin_ExitPass is an authored squad objective
	# point already sitting where the briefing says the operation ends, so the
	# bunker reads its position rather than carrying a copy. The first cut
	# hardcoded Vector3(356, -11.25, 140) — the same rule this project broke
	# three times on terrain before writing it down: a typed coordinate is
	# correct until somebody moves the thing it was copied from, and then it is
	# silently wrong. The fallback below is only used if the marker is gone,
	# and it says so when it uses it.
	bunker_marker = &"Basin_ExitPass"
	bunker_fallback = Vector3(356.0, -11.25, 140.0)
	bunker_tier = 1

	# Where heat-committed reinforcements walk on from: authored squad points
	# at the edges, so they arrive from depth rather than on top of the player.
	entry_markers_named = [&"Basin_ExitPass", &"Basin_North", &"Basin_South",
		&"Valley_Garrison5"] as Array[StringName]

	# Total enemy supply, MEASURED off the authored force rather than invented
	# — §2, resistance is supply and not squad count. basin_1_anchor's roster
	# sums to 82, and tools/measure_resistance.gd is where that came from. The
	# Location overrides this at runtime where a campaign is running; this is
	# the standalone-probe answer.
	resistance = 82
	defence_assault_seconds = 240.0
	stand_down_seconds = 45.0
